# 01. 배포와 연결 확인

시나리오를 실행하기 전에 **에이전트가 조사에 쓸 재료가 모두 연결되어 있는지** 확인합니다.
여기서 빠진 것이 있으면 이후 채점이 에이전트의 능력이 아니라 환경 문제를 측정하게 됩니다.

---

## 1. 배포

```bash
az login
azd auth login
az provider register -n Microsoft.App --wait

azd env new sre-lab --location eastus2 --subscription <subscription-id>
azd env set GITHUB_USER <your-github-username>   # 아래 경고 참고
azd up
bash scripts/post-provision.sh
```

> ⚠️ **`GITHUB_USER` 는 반드시 설정하세요.**
> 설정하지 않으면 에이전트가 **업스트림 저장소(`dm-chelupati/grubify`)를 대상으로 삼아**
> 남의 저장소에 이슈를 만듭니다. 이 Lab 에서 실제로 발생했습니다 →
> [05-results.md — 발견한 문제](05-results.md#에이전트가-업스트림-저장소에-이슈를-만든-건)
>
> 이슈를 앱 저장소가 아닌 **별도 저장소**에 모으려면 `GITHUB_ISSUE_REPO` 를 함께 지정하세요.
> 지정하지 않으면 `GITHUB_REPO` 와 같은 저장소를 사용합니다.
>
> ```bash
> azd env set GITHUB_ISSUE_REPO <owner>/<repo>
> ```

`azd up` 은 **인프라만** 만듭니다. 컨테이너 이미지 빌드와 에이전트 구성(지식 베이스 업로드,
Custom Agent · Response Plan 생성)은 `post-provision.sh` 가 담당합니다. **둘 다 실행해야 합니다.**

---

## 2. 배포 확인

```bash
bash scripts/post-provision.sh --status
```

아래가 모두 ✅ 여야 합니다.

```text
  📚 Knowledge Base:  런북·아키텍처·리포트 템플릿·환경 정보
  🤖 Subagents:       incident-handler
  🚨 Response Plans:  grubify-http-errors → incident-handler
  📡 Incident Platform: Azure Monitor
```

---

## 3. 경고 규칙 3종

시나리오마다 **별도의 경고 규칙**을 씁니다. 재조사 쿨다운이 **규칙 단위**라,
규칙 하나로 여러 시나리오를 돌리면 두 번째부터는 새 조사가 생기지 않고 기존 스레드에 병합됩니다.

| 규칙 | 신호 | Sev | 쓰는 시나리오 |
|---|---|:--:|---|
| `alert-http-5xx-*` | Container Apps `Requests` 5xx > 5 / 5분 | 3 | [S1](02-scenario-s1.md) |
| `alert-revision-unhealthy-*` | `ContainerAppSystemLogs_CL` 의 PortMismatch · ReplicaUnhealthy | 2 | [S2](03-scenario-s2.md) |
| `alert-latency-*` | `ResponseTime` 평균 > 200ms / 5분 | 2 | [S3](04-scenario-s3.md) |

```bash
az monitor metrics alert list -g rg-sre-lab -o table
az monitor scheduled-query list -g rg-sre-lab -o table
```

---

## 4. 기준선 확인

장애를 넣기 전 **정상 값**을 기록해 둡니다. 이 값이 있어야 "얼마나 나빠졌는지" 를 말할 수 있습니다.

```bash
APP_URL=$(azd env get-value CONTAINER_APP_URL)

curl -s -o /dev/null -w "fooditems  HTTP %{http_code} %{time_total}s\n" "$APP_URL/api/fooditems"
curl -s -o /dev/null -w "orders     HTTP %{http_code} %{time_total}s\n" "$APP_URL/api/orders/user/demo-user"
```

이 Lab 에서 측정한 정상 값입니다.

| 항목 | 값 |
|---|---|
| `GET /api/fooditems` | HTTP 200 |
| 서버 응답 시간 (`ResponseTime` 평균) | **1~4 ms** |
| 활성 리비전 | 1개, Healthy, 레플리카 1 |
| 컨테이너 사양 | CPU 1.0 / 메모리 2Gi |

> `ResponseTime` 은 **서버 측** 시간입니다. `curl` 의 `time_total` 은 네트워크·TLS 왕복이 포함되어
> 0.6~0.8초로 나오는 것이 정상입니다. 두 값을 섞어 비교하지 마세요.

---

## 5. 알아둘 제약

| 제약 | 영향 |
|---|---|
| **재조사 쿨다운 3시간** | 같은 규칙 재발화는 새 조사를 만들지 않음 → 시나리오별 규칙 분리 |
| `AppRequests` 테이블 없음 | 이 앱은 App Insights 요청 계측이 없어 KQL 기반 요청 분석 불가 → Container Apps 진단 도구로 우회 |
| Autonomous 모드 | 에이전트가 **스스로 되돌릴 수 있습니다.** 복구가 이미 되어 있어도 놀라지 마세요 |

---

## 다음 단계

[02. S1 — 메모리 누수 장애](02-scenario-s1.md)
