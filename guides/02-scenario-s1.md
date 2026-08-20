# 02. S1 — 메모리 누수 장애

장바구니 API 를 반복 호출해 **메모리를 고갈시키고 OOM** 을 유발합니다.
증상은 HTTP 5xx 이고, 원인은 **코드가 메모리를 놓아주지 않는 것**입니다.

- 실행일: **2026-08-19** · 리전 `eastus2` · 모드 **Autonomous**
- 결과: ✅ **Pass 10/10**

---

## 시작 조건

- [01-setup.md](01-setup.md) 확인이 끝났을 것
- Grubify 가 정상 응답할 것
- 컨테이너 메모리가 **1Gi** 일 것 — 이전 실행에서 에이전트가 2Gi 로 올렸다면 되돌려야 재현됩니다

```bash
az containerapp update -g rg-sre-lab -n <APP> --cpu 0.5 --memory 1Gi
```

---

## Ground truth

`POST /api/cart/{userId}/items` 는 장바구니를 **메모리 딕셔너리에 쌓고 비우지 않습니다**
(`Controllers/CartController.cs`). 요청이 쌓이면 컨테이너의 1Gi 한도에 도달해
`System.OutOfMemoryException` 이 발생하고 컨테이너가 재시작되며 5xx 를 반환합니다.

---

## 실행

```bash
# 1) 장바구니 API 를 반복 호출해 메모리를 밀어 올린다
bash scripts/break-app.sh "$APP_URL" 200 0.5
```

`break-app.sh` 는 먼저 헬스를 확인하고, `POST /api/cart/demo-user/items` 를 200회 보냅니다.

---

## Azure 에서 일어나는 일

| 순서 | 변화 |
|:--:|---|
| 1 | 메모리 사용량이 계속 증가 |
| 2 | 1Gi 한도 도달 → **OOM kill** → 컨테이너 재시작 |
| 3 | 재시작 구간의 요청이 HTTP 500/503 반환 |
| 4 | `Requests` 메트릭의 5xx 가 5건/5분을 넘어 `alert-http-5xx-*`(Sev3) 발화 |
| 5 | Response Plan 이 `incident-handler` 로 **Autonomous** 라우팅 |

---

## SRE Agent 에서 확인할 항목

- 5xx 라는 증상에서 멈추지 않고 **메모리 추이와 상관 지어** 원인을 좁히는지
- 재시작이 원인인지 결과인지 구분하는지
- 완화책이 **되돌릴 수 있는 최소 변경**인지 (전면 재배포가 아니라 리소스 조정)
- 코드 위치까지 짚는지

---

## 실측 결과

### 타임라인

| 시각(UTC) | 이벤트 | Δ |
|---|---|--:|
| 00:16 | 최초 5xx 발생 | — |
| 00:17:47 | 경고 `alert-http-5xx-sre-lab` **발화** | +3분 |
| 00:18:41 | 에이전트 **인수**, 조사 시작 | +54초 |
| 00:19:15 | Knowledge Base 검색 — 유사 인시던트 3건 / 런북 4건 | +34초 |
| 00:22:06 | **근본 원인 확정** | +4분 25초 |
| 00:22:20 | **완화 1** — 리비전 재시작 | +14초 |
| 00:22:50 | **완화 2** — 메모리 1Gi → 2Gi | +30초 |
| 00:24:11 | Azure Monitor 경고 **종료** | |
| 00:30:05 | 인시던트 리포트 파일 생성 (113줄) | |
| 00:31:37 | Team Memory 저장 (파일 3개) | |

### 에이전트가 도출한 근본 원인

> **Root Cause**
> `System.OutOfMemoryException` in `CartController.AddItemToCart` at `/app/Controllers/CartController.cs:line 30`.
> The in-memory cart store uses an unbounded dictionary with no eviction — under ~32 req/min,
> it exhausted the container's 1Gi memory limit, causing 25+ HTTP 500 failures across 8 Kestrel
> connections in a 40-second window.

**파일명과 라인 번호까지** 특정했습니다. 근거로 Log Analytics 로그, 요청/메모리 상관 차트, 리비전 이력을 제시했습니다.

### 조치 주체 검증

"사람 개입 0회" 는 에이전트의 자기 보고가 아니라 **활동 로그**로 확인한 사실입니다.

| 시각(UTC) | ARM 작업 | 호출자 |
|---|---|---|
| 00:22:20 | `containerApps/revisions/restart/action` | `id-sre-huvqg3bjooyw6` |
| 00:22:43 → 00:22:59 | `containerApps/write` | `id-sre-huvqg3bjooyw6` |

호출자는 사용자 계정(UPN)이 아니라 **에이전트의 관리 ID** 입니다.

```bash
az monitor activity-log list -g rg-sre-lab \
  --start-time 2026-08-19T00:00:00Z --end-time 2026-08-19T01:00:00Z \
  --query "[?contains(operationName.value,'Microsoft.App')].{time:eventTimestamp, op:operationName.value, caller:caller}" -o table
```

### 점수

| 영향 | 원인 | 증거 | 완화 | 불확실성 | 합계 | 판정 |
|--:|--:|--:|--:|--:|--:|---|
| 2 | 3 | 2 | 2 | 1 | **10/10** | ✅ Pass |

---

## 복구 확인

```text
Name                               Active  Replicas  Health   Memory  Cpu
ca-grubify-huvqg3bjooyw6--0000003  True    1         Healthy  2Gi     1.0
```

`POST /api/cart/demo-user/items` → 200, 프론트엔드 → 200.

> **다음 시나리오 전에 메모리를 1Gi 로 되돌리지 않으면 S1 은 재현되지 않습니다.**
> 에이전트가 이미 2Gi 로 올려놓았기 때문입니다.

---

## 다음 단계

[03. S2 — 인그레스 포트 불일치](03-scenario-s2.md)
