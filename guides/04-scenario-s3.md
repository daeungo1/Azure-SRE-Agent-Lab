# 04. S3 — 주문 API 응답 지연

주문 API 가 **오류 없이 느려지기만** 하는 장애입니다.
5xx 가 하나도 없기 때문에 [S1](02-scenario-s1.md) · [S2](03-scenario-s2.md) 보다 근거를 고르기 어렵습니다.
"에러 없으니 이상 없음" 으로 넘어가지 않는지가 이 시나리오의 핵심입니다.

- 실행일: **2026-08-20** · 리전 `eastus2` · 모드 **Autonomous**

---

## 시작 조건

- [S2](03-scenario-s2.md) 가 복구되어 있을 것
- `alert-latency-*` 규칙이 활성일 것
- 앱 이미지에 **`ORDER_DELAY_MS` 미들웨어가 포함**되어 있을 것 (아래 참고)

### 앱에 지연 주입 지점 만들기

기본 Grubify 이미지에는 지연을 넣을 방법이 없습니다.
그래서 fork 한 저장소에 미들웨어를 넣습니다.

```csharp
// GrubifyApi/Program.cs — app.UseForwardedHeaders() 다음
app.Use(async (context, next) =>
{
    if (int.TryParse(Environment.GetEnvironmentVariable("ORDER_DELAY_MS"), out var delayMs)
        && delayMs > 0
        && context.Request.Path.StartsWithSegments("/api/orders"))
    {
        await Task.Delay(delayMs);
    }

    await next();
});
```

이미지를 다시 빌드하고 배포합니다.

```bash
az acr build --registry <ACR> --image grubify-api:latency-lab \
  --file Dockerfile "https://github.com/<your-account>/grubify.git#main:GrubifyApi"

az containerapp update -g rg-sre-lab -n <APP> \
  --image <ACR>.azurecr.io/grubify-api:latency-lab
```

---

## Ground truth

`ORDER_DELAY_MS=4000` 을 설정하면 `/api/orders` 경로가 **4초 지연 후 200** 을 반환합니다.
오류율은 변하지 않고 **지연만** 올라갑니다.

---

## 실행

```bash
# 1) 주입 — 새 리비전이 Healthy 가 될 때까지 기다린다
bash scripts/break-app-latency.sh break

# 2) 부하 — 모두 200 이지만 4초씩 걸린다
CONCURRENCY=10 ROUNDS=20 bash scripts/break-app-latency.sh load

# 3) 복구
bash scripts/break-app-latency.sh restore
```

---

## Azure 에서 일어나는 일

| 순서 | 변화 |
|:--:|---|
| 1 | `ORDER_DELAY_MS=4000` 이 설정되어 새 리비전 생성 |
| 2 | `/api/orders/user/...` 요청이 **200 인 채로** 4초 걸림 |
| 3 | Container Apps `ResponseTime` 평균이 **4ms → 4000ms** 로 상승 |
| 4 | 5분 창 평균이 200ms 를 넘어 `alert-latency-*`(Sev2) 발화 |
| 5 | 느린 응답 때문에 요청이 쌓여 **HTTP 스케일러가 레플리카를 늘림** |

---

## SRE Agent 에서 확인할 항목

- 5xx 가 없는 상황에서 **지연 자체를 근거로 삼는지**
- 정상 구간과의 차이를 **수치로** 제시하는지
- 원인을 최근 설정 변경으로 좁히는지, "리소스 부족" 으로 뭉개지 않는지
- 완화가 되돌릴 수 있는 최소 변경인지

---

## 실측 결과

### 타임라인

| 시각(UTC) | 이벤트 | Δ |
|---|---|--:|
| 06:32:37 | `ORDER_DELAY_MS=4000` **주입** | — |
| 06:33:25 | 부하 시작 (10 동시 × 20회, 전부 200) | +48초 |
| 06:34 | `ResponseTime` **4034 ms** 기록 (정상 4 ms) | |
| 06:36:21 | 경고 `alert-latency-sre-lab`(Sev2) **발화** | +3분 44초 |
| 06:37:30 | 에이전트 **인수** | +69초 |
| 06:42:19 | **근본 원인 확정** — `ORDER_DELAY_MS=4000` | **+4분 49초** |
| 06:42:56 | 정상 이미지(`latest`)와 문제 이미지(`latency-lab`) 판별 | |
| 06:43:08 | 롤백 준비 — 이미지 복구 + 환경 변수 제거 | |
| 06:43:30 | `pre-write-evidence-gate` 훅 통과 — **이후 쓰기 미완료** | |
| 06:46:03 | 사람이 수동 복구 (`ORDER_DELAY_MS=0`) | |

### 응답 시간 변화

| 구간 | `ResponseTime` 평균 |
|---|--:|
| 정상 | **4 ms** |
| `ORDER_DELAY_MS=4000` 적용 후 | **4034 ms** · **4002 ms** |

단일 요청 실측: `0.72초 → 4.72초`.

### 에이전트 분석

| 항목 | 결과 |
|---|---|
| **직접 원인** | *"Root cause identified: `ORDER_DELAY_MS=4000` environment variable is injecting 4 seconds of artificial delay per request"* — **정확** |
| **조사 경로** | 리비전 이력 → 시작 프로브 이력 → 이미지 태그(`latency-lab`) 의심 → **환경 변수 확인** 순으로 좁힘 |
| **부수 관찰** | 1시간 내 리비전 7개 배포(churn), HTTP 스케일러가 레플리카 4개로 확장한 사실을 지연과 연결 |
| **막힌 지점** | ACR 접근 거부 — 관리 ID 에 레지스트리 권한이 없어 이미지 내용은 확인 불가. **막힌 사실을 그대로 보고** |
| **코드 확인 실패** | 소스에서 `ORDER_DELAY_MS` 를 찾지 못함 (0 matches) — Code Access 의 저장소 복제본이 **미들웨어 커밋 이전 시점**이었기 때문 |

### 이 시나리오가 드러낸 것

**1) 오류 없는 장애를 장애로 인식합니다.**
5xx 가 하나도 없는 상황에서 "이상 없음" 으로 끝내지 않고 **설정값 하나까지** 좁혔습니다.

**2) 조치는 완료되지 않았습니다.**
에이전트는 롤백 명령을 구성하고 `pre-write-evidence-gate` 훅까지 통과했지만,
**실제 쓰기가 뒤따르지 않은 채 조사가 멈췄습니다.** 앱은 4초 지연이 남아 사람이 복구했습니다.
S1·S2 에서는 같은 권한으로 자율 조치가 **성공했으므로 권한 문제는 아닙니다.**

**3) 소스 동기화 시점이 조사 품질을 좌우합니다.**
에이전트는 소스에서 `ORDER_DELAY_MS` 를 찾지 못하자 *"코드에 없고 이미지에만 있다"* 고 **단정**했습니다.
실제로는 커밋되어 있었고, Code Access 복제본이 **커밋 이전 시점**이었을 뿐입니다.

> **교훈** — 소스 연결은 "연결됨" 만으로 부족하고 **동기화 시점**이 중요합니다.
> 배포한 코드와 에이전트가 읽는 코드가 다르면, 원인을 찾아도 근거를 채우지 못합니다.

### 점수

| 영향 | 원인 | 증거 | 완화 | 불확실성 | 합계 | 판정 |
|--:|--:|--:|--:|--:|--:|---|
| 2 | 3 | 2 | **1** | **0** | **8/10** | ✅ Pass |

- 완화 **-1** — 계획은 정확했으나 **실행이 완료되지 않음**
- 불확실성 **-1** — 확인하지 못한 것(소스 내용)을 단정

---

## 복구 확인

```bash
bash scripts/break-app-latency.sh restore   # ORDER_DELAY_MS=0
```

`/api/orders/user/demo-user` 가 다시 1초 미만으로 응답하고 `alert-latency-*` 가 `Resolved` 여야 합니다.

---

## 다음 단계

[05. 채점 종합](05-results.md)
