# 03. S2 — 인그레스 포트 불일치

인그레스를 **앱이 듣지 않는 포트**로 돌려 모든 요청을 실패시킵니다.
증상은 [S1](02-scenario-s1.md) 과 같은 HTTP 5xx 이지만, 원인은 **배포 설정 오류**입니다.
컨테이너 자체는 멀쩡하므로 에이전트가 "앱이 죽었다"고 오판하지 않는지까지 봅니다.

- 실행일: **2026-08-20** · 리전 `eastus2` · 모드 **Autonomous**
- 결과: ✅ **Pass 8/10**

---

## 시작 조건

- [S1](02-scenario-s1.md) 이 복구되어 있을 것 (경고 `Resolved`, 앱 200)
- `alert-revision-unhealthy-*` 규칙이 활성일 것

---

## Ground truth

인그레스 `targetPort` 를 **8080 → 9090** 으로 변경합니다.
앱은 그대로 8080 에서 듣고 있으므로 **엣지에서 전 요청이 실패**합니다.

> 처음에는 `ASPNETCORE_URLS=http://+:9090` 으로 시도했지만 **동작하지 않았습니다.**
> 이 이미지는 환경 변수와 무관하게 8080 을 바인딩합니다. 인그레스를 옮겨야 실제 장애가 납니다.
> 이 실패가 남긴 리비전 이력이 뒤에서 에이전트의 오판을 유발했습니다 — [아래](#잘못된-주장-감점-사유) 참고.

---

## 실행

```bash
# 1) 주입
bash scripts/break-app-config.sh break

# 2) 경고 임계값을 넘기도록 트래픽을 준다
for i in $(seq 1 90); do curl -s -o /dev/null "$APP_URL/api/fooditems"; sleep 0.7; done

# 3) 상태 확인 (에이전트가 이미 고쳤을 수 있습니다)
bash scripts/break-app-config.sh status

# 4) 필요하면 복구
bash scripts/break-app-config.sh restore
```

---

## Azure 에서 일어나는 일

| 순서 | 변화 |
|:--:|---|
| 1 | `targetPort` 가 9090 으로 바뀌고 인그레스가 죽은 포트로 전달 |
| 2 | 시작 프로브가 `connection refused` 로 실패 → `ReplicaUnhealthy` |
| 3 | `ContainerAppSystemLogs_CL` 에 `Pending:PortMismatch` 기록 |
| 4 | 모든 요청 **503** → `alert-revision-unhealthy-*`(Sev2) 와 `alert-http-5xx-*`(Sev3) 가 **각각** 발화 |
| 5 | 규칙이 다르므로 **조사 스레드도 2개** 생성 |

---

## SRE Agent 에서 확인할 항목

- 같은 5xx 증상에서 **S1 의 OOM 결론을 재사용하지 않는지**
- 시스템 로그의 `PortMismatch` 를 근거로 제시하는지
- 컨테이너는 정상인데 엣지에서 실패한다는 **구조를 구분**하는지
- 완화가 최소 변경인지 (재배포가 아니라 포트 정렬)

---

## 실측 결과

### 타임라인

| 시각(UTC) | 이벤트 | Δ |
|---|---|--:|
| 05:48:57 | `targetPort` 8080 → 9090 **주입** | — |
| 05:49:39 | 첫 503 (부하 90건 **전부** 503) | +42초 |
| 05:51:49 | 경고 `alert-revision-unhealthy-sre-lab`(Sev2) **발화** | +2분 52초 |
| 05:52:38 | 에이전트 **인수** | +49초 |
| 05:53:27 | 팀 메모리 검색 — 과거 OOM 인시던트 6건 회수 | +49초 |
| 05:54:08 | **근본 원인 확정** | **+80초** |
| 05:54:53 | **자율 조치** — `targetPort` 9090 → 8080 | +45초 |
| 05:55:22 | 복구 검증 시작 | |
| 05:53:32 | *(별도 규칙)* 5xx 경고 발화 → 두 번째 조사 스레드 | |

### 에이전트 분석

| 항목 | 결과 |
|---|---|
| **영향 범위** | `ca-grubify-huvqg3bjooyw6`, 리비전 `--0000005`, 요청 67건 5xx — 정확 |
| **직접 원인** | *"The TargetPort 9090 does not match the listening port 8080"* — **정확** |
| **증거** | `Pending:PortMismatch`, `ReplicaUnhealthy`(startup probe: connection refused), 컨테이너 바인딩 로그, 메모리·CPU 정상(1~2%) |
| **완화책** | `targetPort` 정렬 — 최소 범위, 되돌리기 가능 |
| **변별력** | *"No OOM this time — different root cause than previous incidents"* |

이 문장이 **이 Lab 의 핵심**입니다. 같은 증상에서 과거 결론에 끌려가지 않았습니다.

### 잘못된 주장 (감점 사유)

에이전트는 원인을 **"새 리비전이 앱의 리슨 포트를 바꿨는데 인그레스를 안 맞췄다"** 로 서술했습니다.
실제로는 반대입니다 — **앱은 계속 8080 이었고 바뀐 것은 인그레스**입니다. 인과를 뒤집었습니다.

원인은 위에서 언급한 **첫 주입 실패가 남긴 리비전 이력**이었습니다.
`ASPNETCORE_URLS=9090` 리비전이 남아 있어 "앱이 9090 을 듣다가 8080 으로 바뀌었다"고 추론할 근거가 됐습니다.

> **조치는 정확했지만 서사는 틀렸습니다.** 장애 주입 Lab 에서 *증거 위생* 이 중요하다는 실제 사례입니다.

### 점수

| 영향 | 원인 | 증거 | 완화 | 불확실성 | 합계 | 판정 |
|--:|--:|--:|--:|--:|--:|---|
| 2 | 3 | **1** | 2 | **0** | **8/10** | ✅ Pass |

증거에서 감점 — 남아 있던 리비전 이력을 오독해 인과를 반대로 서술했습니다.
불확실성에서 감점 — 그 서술을 **단정**했고, 리비전 이력과 인그레스 변경 중
무엇이 원인인지 확인하지 못했다는 표시를 하지 않았습니다.

### 조치 주체 검증

```text
05:49:02Z  containerApps/write  admin@MngEnvMCAP359144.onmicrosoft.com   ← 사람(주입)
05:54:53Z  containerApps/write  25b6a2dc-...(id-sre-huvqg3bjooyw6)      ← 에이전트(자율 복구)
```

---

## 복구 확인

`targetPort` **8080**, 리비전 `--0000005` **Healthy**, `GET /api/fooditems` **HTTP 200**.

---

## 다음 단계

[04. S3 — 주문 API 응답 지연](04-scenario-s3.md)
