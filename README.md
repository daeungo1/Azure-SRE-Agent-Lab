# Azure SRE Agent — 기능 소개 & 실습 Lab (한국어)

> Azure SRE Agent 를 배포하고, 샘플 앱을 의도적으로 망가뜨린 뒤,
> 에이전트가 **스스로 진단하고 완화**하는 과정을 확인하는 실습 저장소입니다.
>
> - 기능 설명: **[SRE_Agent.md](SRE_Agent.md)**
> - 원본 Lab: [microsoft/sre-agent — labs/starter-lab](https://github.com/microsoft/sre-agent/tree/main/labs/starter-lab) ([영문 README](docs/README.en.md))
> - **이 저장소의 모든 절차는 실제 Azure 구독에서 E2E 검증을 마쳤습니다.** → [6. E2E 실행 결과](#6-e2e-실행-결과)

<p align="center">
  <img src="docs/architecture-ko.svg" alt="Lab 아키텍처" width="960"/>
</p>

---

## 목차

1. [무엇을 배포하나요](#1-무엇을-배포하나요)
2. [사전 요구사항](#2-사전-요구사항)
3. [빠른 시작](#3-빠른-시작)
4. [배포 확인](#4-배포-확인)
5. [실습 시나리오](#5-실습-시나리오)
6. [E2E 실행 결과](#6-e2e-실행-결과)
7. [정리 (Cleanup)](#7-정리-cleanup)
8. [트러블슈팅](#8-트러블슈팅)
9. [저장소 구조](#9-저장소-구조)

---

## 1. 무엇을 배포하나요

| 리소스 | 용도 |
|---|---|
| **SRE Agent** | Managed Identity · Knowledge Base · Custom Agent 를 갖춘 AI 에이전트 |
| **Grubify 앱** | 샘플 음식 주문 앱 (API + Frontend, Azure Container Apps) |
| **Log Analytics + App Insights** | 로그 저장 및 모니터링 |
| **Azure Monitor 경고** | HTTP 5xx 경고 → 에이전트 조사 자동 트리거 |
| **Container Registry (ACR)** | Grubify 컨테이너 이미지 빌드/저장 |
| **Managed Identity** | Reader + Monitoring Reader + Log Analytics Reader RBAC |

### SRE Agent 구성 요소

| 구성 요소 | 내용 |
|---|---|
| **Knowledge Base** | HTTP 오류 런북, 앱 아키텍처 문서, 인시던트 리포트 템플릿, 이슈 분류 기준 |
| **incident-handler** | 로그 · KQL · 런북 기반 조사 (도구 19종) |
| **code-analyzer** | 위 기능 + 소스 코드 검색, GitHub 이슈 생성 *(GitHub 연동 시)* |
| **issue-triager** | 고객 이슈 분류 · 라벨 · 코멘트 *(GitHub 연동 시)* |
| **Response Plan** | `grubify-http-errors` — Sev0~Sev4 경고를 `incident-handler` 로 Autonomous 라우팅 |
| **Scheduled Task** | 12시간마다 이슈 트리아지 *(GitHub 연동 시)* |
| **Global Tools** | DevOps + Python plotting 활성화 |

---

## 2. 사전 요구사항

| 도구 | Windows 설치 | macOS 설치 |
|---|---|---|
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) 2.60+ | `winget install Microsoft.AzureCLI` | `brew install azure-cli` |
| [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) 1.9+ | `winget install Microsoft.Azd` | `brew install azd` |
| [Git](https://git-scm.com/) 2.x | `winget install Git.Git` | `brew install git` |
| [Python](https://python.org) 3.10+ | `winget install Python.Python.3.12` | `brew install python3` |

> **Windows 주의 (중요):** Python 설치 후 **설정 → 앱 → 앱 실행 별칭**에서 `python.exe`, `python3.exe` 를 **끄세요.**
> 켜져 있으면 `python3` 가 Microsoft Store 스텁으로 잡혀 구성 스크립트가 조용히 실패합니다.
> (이 저장소의 스크립트는 스텁을 자동 감지해 우회하도록 수정했습니다 — [6.4 발견·수정한 이슈](#64-실습-중-발견하고-수정한-이슈) 참고)
>
> Bash 스크립트는 **Git Bash** 로 실행합니다: `& "C:\Program Files\Git\bin\bash.exe" scripts/...`

### Azure 요구사항

- 구독에 **Owner** 권한 (구독 범위 RBAC 역할 할당 필요)
- 리소스 공급자 등록: `az provider register -n Microsoft.App --wait`
- 허용 리전: `eastus2`, `swedencentral`, `australiaeast`

### 선택 사항

- GitHub 계정 — 시나리오 2·3 을 위해 [dm-chelupati/grubify](https://github.com/dm-chelupati/grubify/fork) 를 fork

---

## 3. 빠른 시작

### 방법 A — 원커맨드 스크립트

```bash
git clone https://github.com/daeungo1/Azure-SRE-Agent-Lab.git
cd Azure-SRE-Agent-Lab
bash scripts/setup.sh
```

Windows(PowerShell):

```powershell
git clone https://github.com/daeungo1/Azure-SRE-Agent-Lab.git
cd Azure-SRE-Agent-Lab
& "C:\Program Files\Git\bin\bash.exe" scripts/setup.sh
```

### 방법 B — 단계별 수동 실행 (E2E 검증에 사용한 절차)

```bash
az login
azd auth login
az provider register -n Microsoft.App --wait

azd env new sre-lab --location eastus2 --subscription <subscription-id>
# 선택: azd env set GITHUB_USER <your-username>

azd up
bash scripts/post-provision.sh
```

> `azd up` 은 **인프라만** 만듭니다. 컨테이너 이미지 빌드(ACR Task)와
> SRE Agent 구성(Knowledge Base 업로드, Custom Agent · Response Plan 생성)은
> `scripts/post-provision.sh` 가 담당합니다. **두 단계 모두 실행해야 합니다.**

---

## 4. 배포 확인

```bash
bash scripts/post-provision.sh --status
```

`post-provision.sh` 마지막에 출력되는 검증 섹션이 아래처럼 모두 ✅ 여야 합니다.

```text
  📚 Knowledge Base:
     ✅ github-issue-triage.md
     ✅ grubify-architecture.md
     ✅ http-500-errors.md
     ✅ incident-report-template.md

  🤖 Subagents:
     ✅ incident-handler (19 tools)

  🚨 Response Plans:
     ✅ grubify-http-errors → subagent: incident-handler

  📡 Incident Platform:
     ✅ Azure Monitor
```

[sre.azure.com](https://sre.azure.com) 에서도 동일하게 확인할 수 있습니다.

| 확인 위치 | 기대 결과 |
|---|---|
| Settings → Knowledge Base → Files | 런북 파일이 색인(Indexed)됨 |
| Builder → Agent Canvas | `incident-handler` Custom Agent 존재 |
| Builder → Incident response plans | `grubify-http-errors` 플랜이 On |
| Settings → Incident platform | Azure Monitor 연결됨 |

---

## 5. 실습 시나리오

| # | 시나리오 | 대상 | GitHub 필요 |
|:--:|---|---|:--:|
| 1 | 앱 장애 발생 → 에이전트가 로그 기반 조사·완화 | IT 운영 | ❌ |
| 2 | 동일 장애 → 소스 코드에서 근본 원인 발견 + GitHub 이슈 생성 | 개발자 + IT | ✅ |
| 3 | 고객 이슈 트리아지 → 분류·라벨·코멘트 자동화 | 워크플로 자동화 | ✅ |

### 시나리오 1 — IT 운영 (GitHub 불필요)

```bash
bash scripts/break-app.sh <API_URL> 200 0.5
```

`/api/cart/demo-user/items` 로 200회 POST 를 보내 **메모리 누수**를 유발합니다.
(in-memory 장바구니에 eviction 로직이 없음)

1. Grubify Frontend 를 열고 장바구니 담기 시도 → 실패 확인
2. [sre.azure.com](https://sre.azure.com) 에서 **새 채팅** → `/` 입력 → Custom Agent 선택
3. 다음 프롬프트 전송 (채팅은 영어만 지원):

   ```text
   The Grubify API is not responding — specifically the "Add to Cart" is failing.
   Can you investigate and find the root cause?
   ```

4. 완화 요청: `Can you mitigate this issue?`

> **자동 조사(권장):** 프롬프트를 보내지 않아도 됩니다.
> Azure Monitor 경고가 발화하면 Response Plan 이 `incident-handler` 를 **자율 모드로 자동 실행**합니다.
> **Activities → Incidents** 에서 진행 상황을 볼 수 있습니다. (실제 소요: 경고 발화 후 약 14분에 완료)

### 시나리오 2 — 개발자 (GitHub 필요)

동일한 장애이지만, 에이전트가 추가로:

- Grubify 소스 코드에서 근본 원인 검색 → 정확한 `파일:라인` 식별
- 코드 참조와 수정 제안이 포함된 GitHub 이슈 생성 (경우에 따라 수정 PR)

> 이슈 생성이 실패하면 이렇게 유도하세요:
> `Use the GitHub API to create the issue if the direct tool isn't working`

### 시나리오 3 — 워크플로 자동화 (GitHub 필요)

```bash
bash scripts/create-sample-issues.sh <your-user>/grubify
```

**Builder → Scheduled tasks → triage-grubify-issues → Run task now** 실행 후
각 `[Customer Issue]` 에 분류·라벨(`bug`, `api-bug`, `severity-high` 등)·트리아지 코멘트가 달립니다.

### 보너스 프롬프트

```text
What is the public endpoint URL for the Grubify frontend container app?
```

```text
Show me the CPU and memory usage trends for the Grubify container app over the last hour
```

```text
Using the http-500-errors runbook, walk me through all the diagnostic KQL queries
and show me the results for the Grubify app
```

---

## 6. E2E 실행 결과

> **실행일:** 2026-08-19 · **리전:** `eastus2` · **시나리오:** 1 (IT 운영, GitHub 미연동)
> 모든 타임스탬프는 **UTC** 기준입니다.

### 6.1 배포 결과

`azd up` 으로 생성된 리소스 (리소스 그룹 `rg-sre-lab`):

| 리소스 | 이름 | 소요 |
|---|---|---|
| Resource Group | `rg-sre-lab` | 6s |
| Application Insights | `appi-huvqg3bjooyw6` | 25s |
| Log Analytics workspace | `law-huvqg3bjooyw6` | 22s |
| Container Registry | `acrcagrubifyhuvqg3bjooyw6` | 10s |
| Container Apps Environment | `cae-huvqg3bjooyw6` | 58s |
| Container App (API) | `ca-grubify-huvqg3bjooyw6` | 17s |
| Container App (Frontend) | `ca-grubify-fe-huvqg3bjooyw6` | — |
| **SRE Agent** | `sre-agent-huvqg3bjooyw6` | — |
| Metric Alert | `alert-http-5xx-sre-lab` (Sev3, 5xx > 5 / 5분, 평가 1분) | — |

`scripts/post-provision.sh` 결과: ACR 이미지 2종 빌드·배포, CORS 구성,
Knowledge Base 4개 파일 색인, `incident-handler`(19 tools), Response Plan, Azure Monitor 연결 — **전부 성공**.

### 6.2 장애 주입 결과

```text
Target:   https://ca-grubify-huvqg3bjooyw6...azurecontainerapps.io
Requests: 200 (interval 0.5s)

00:11 UTC  시작 — App is healthy (HTTP 200)
00:14 UTC  25/200 → 오류 0건
00:16 UTC  75/200 → 오류 2건   ← 최초 5xx 발생
00:17 UTC  100/200 → 오류 26건
00:19 UTC  200/200 → 오류 126건

Results: 74 successes, 126 errors out of 200 requests
```

### 6.3 에이전트 자동 조사 타임라인

Azure Monitor 경고 → Response Plan → `incident-handler`(Autonomous) 로
**사람 개입 없이** 진행된 실제 기록입니다.

| 시각(UTC) | 이벤트 |
|---|---|
| 00:17:47 | 경고 `alert-http-5xx-sre-lab` (Sev3) **발화** |
| 00:18:41 | 에이전트가 경고 **수신·확인(Acknowledged)** 후 조사 시작 |
| 00:19:15 | **Knowledge Base 검색** — 유사 인시던트 3건 / 런북 4건 조회 |
| 00:19:30 | Grubify 아키텍처 문서 · 인시던트 템플릿 · HTTP 500 런북 로드 |
| 00:19:38 | Container Apps 진단 스킬 로드, 앱 정보·메트릭·로그·리비전 **병렬 수집** |
| 00:20:57 | 분석: CPU 최대 1% (원인 아님), 메모리 3%→5%, 트래픽 32 req/min |
| 00:22:06 | **근본 원인 확정** — `System.OutOfMemoryException` |
| 00:22:20 | **완화 1** — 리비전 재시작 + 요청/메모리 상관 차트 생성 |
| 00:22:50 | **완화 2** — 메모리 1Gi → 2Gi 확장, 새 리비전 `--0000003` 생성 |
| 00:24:11 | **Azure Monitor 경고 종료(Close)** |
| 00:29:58 | 경고 상태 `Resolved` 로 전환 확인 |
| 00:30:05 | 인시던트 리포트 파일 생성 (`incident-report-2026-08-19-oom-cart-api.md`, 113줄) |
| 00:31:37 | **Team Memory 저장** — `debugging.md`, `overview.md`, `grubify-oom-cart-api-incident.md` |
| 00:32:11 | 최종 요약 보고 완료 |

**측정 지표**

| 항목 | 값 |
|---|---|
| 감지(MTTD) — 최초 5xx → 경고 발화 | 약 3분 |
| 완화(MTTR) — 경고 발화 → 메모리 확장 적용 | **약 5분** |
| 전체 조사 완료 — 경고 발화 → 최종 보고 | **약 14분** |
| 사람 개입 | **0회** |

### 6.4 에이전트가 도출한 근본 원인

에이전트 최종 보고 원문(요약):

> **Root Cause**
> `System.OutOfMemoryException` in `CartController.AddItemToCart` at `/app/Controllers/CartController.cs:line 30`.
> The in-memory cart store uses an unbounded dictionary with no eviction — under ~32 req/min,
> it exhausted the container's 1Gi memory limit, causing 25+ HTTP 500 failures across 8 Kestrel
> connections in a 40-second window.

즉, **파일명과 라인 번호 수준까지** 원인을 특정했습니다.
근거로 Log Analytics 로그, 요청/메모리 상관 차트, 리비전 이력을 함께 제시했습니다.

### 6.5 완화 결과 검증

에이전트 조치 후 실제 상태:

```text
Name                               Active  Replicas  Health   Memory  Cpu
ca-grubify-huvqg3bjooyw6--0000003  True    1         Healthy  2Gi     1.0
```

```text
POST /api/cart/demo-user/items   → HTTP 200 (463ms)
GET  frontend /                  → HTTP 200 (700ms)
```

메모리 `1Gi → 2Gi`, CPU `0.5 → 1.0` 으로 확장된 새 리비전이 정상 동작하며, 서비스가 복구되었습니다.

### 6.6 GitHub 미연동 시의 제약 (재현됨)

`GITHUB_USER` 를 설정하지 않고 실행했기 때문에, 에이전트는 GitHub 이슈 생성 단계에서
`GitHub authorization failed. User must be logged in.` 로 실패했습니다.
에이전트는 이를 **스스로 인지하고** 대체 경로(gh CLI → curl → 커넥터 설정 확인)를 시도한 뒤,
최종적으로 인시던트 리포트를 **파일로 저장**하고 사용자에게 GitHub 계정 연결을 요청했습니다.

> 시나리오 2·3 을 실행하려면 `azd env set GITHUB_USER <username>` 후
> `bash scripts/post-provision.sh --retry` 를 실행하고, 출력되는 **OAuth URL 에서 브라우저 승인**이 필요합니다.
> (이 단계는 대화형이라 자동화되지 않습니다.)

### 6.7 실습 중 발견하고 수정한 이슈

원본 starter-lab 을 실제로 돌리면서 발견한 문제 3건을 이 저장소에서 수정했습니다.

| # | 증상 | 근본 원인 | 수정 |
|---|---|---|---|
| 1 | `incident-handler returned HTTP 400` — subagent 생성 실패 | Windows 에서 `command -v python3` 가 **Microsoft Store 별칭 스텁**을 찾음. 스텁은 출력이 없고 stderr 안내문만 내보내는데, 스크립트가 `2>&1` 로 캡처해 그 텍스트를 JSON 대신 요청 본문으로 전송 | [scripts/post-provision.sh](scripts/post-provision.sh), [scripts/setup.sh](scripts/setup.sh) — 후보 인터프리터를 **실제 실행해보고** 검증하도록 변경 |
| 2 | `Response plan failed after 5 attempts (HTTP 400)` | 데이터플레인 API 가 `maxAttempts` 속성을 거부 (`Unknown incident filter properties: maxAttempts`). 서버가 `maxAutomatedInvestigationAttempts` 를 자동 설정 | [scripts/post-provision.sh](scripts/post-provision.sh) — 페이로드에서 `maxAttempts` 제거 |
| 3 | 검증 섹션이 공백으로 출력 / 헬스체크가 항상 404 | (a) 한국어 등 비 UTF-8 Windows 로캘에서 이모지 출력 실패 (b) 배포된 API 에 `/health`·`/api/menu` 라우트가 없음 (실제: `/api/fooditems`, `/api/restaurants`, `/api/cart/{user}`) | `PYTHONIOENCODING=utf-8` 설정 + [scripts/break-app.sh](scripts/break-app.sh) 헬스체크 경로 교정 |

추가로 subagent 생성 PUT 이 **비동기(202)** 라 연속 호출 시 일시적으로 400 이 나는 현상이 있어,
`post-provision.sh` 의 subagent 생성에 **재시도 로직**을 넣었습니다.

---

## 7. 정리 (Cleanup)

```bash
azd down --purge
```

> ⚠️ **SRE Agent 는 사용량 기반 과금 리소스입니다.** 실습이 끝나면 반드시 삭제하세요.
> `--purge` 를 붙여야 Log Analytics / Application Insights 가 soft-delete 상태로 남지 않습니다.

---

## 8. 트러블슈팅

| 증상 | 해결 |
|---|---|
| Windows 에서 스크립트가 조용히 실패 / `python3` 못 찾음 | 앱 실행 별칭(Store alias) 끄고 터미널 재시작 |
| Response Plan 생성 시 HTTP 400/405 | 30초 대기 후 `bash scripts/post-provision.sh --retry` |
| subagent 생성 HTTP 400 | 직전 PUT 이 비동기 처리 중일 수 있음. 15초 후 재시도 (스크립트에 내장) |
| GitHub 이슈 생성 실패 | `azd env set GITHUB_USER <username>` → `--retry` → **브라우저에서 OAuth 승인** |
| `az login` 이 잘못된 계정 사용 | `az logout` 후 `az login --use-device-code` |
| `azd up` 리전 오류 | `azd env set AZURE_LOCATION eastus2` 후 재실행 |
| Container App 이 `Waiting` 상태 | ACR 이미지 빌드 대기 — `post-provision.sh` 를 먼저 실행했는지 확인 |
| 경고가 발화하지 않음 | 5xx 가 5분 창에서 5건을 넘어야 함. `break-app.sh` 요청 수를 늘리세요 |

---

## 9. 저장소 구조

```text
.
├── README.md                 # 이 문서 (실습 가이드 + E2E 결과)
├── SRE_Agent.md              # Azure SRE Agent 기능 소개
├── azure.yaml                # azd 템플릿 정의
├── docs/
│   ├── architecture-ko.svg   # 한국어 아키텍처 다이어그램
│   ├── architecture.svg      # 원본 아키텍처 다이어그램
│   └── README.en.md          # 원본(영문) starter-lab README
├── infra/                    # Bicep IaC (subscription scope)
│   ├── main.bicep
│   ├── resources.bicep
│   └── modules/              # monitoring · identity · container-app · sre-agent · alert-rules · rbac
├── knowledge-base/           # SRE Agent 에 업로드되는 런북 · 문서
├── lab/                      # Skillable 랩 진행용 지침
├── scripts/                  # setup · post-provision · break-app · 샘플 이슈 생성
└── sre-config/               # Custom Agent(YAML) · 커넥터 정의
```

---

## 참고

| 항목 | 링크 |
|---|---|
| SRE Agent 포털 | [sre.azure.com](https://sre.azure.com) |
| 공식 문서 | [learn.microsoft.com/azure/sre-agent](https://learn.microsoft.com/azure/sre-agent/overview) |
| 블로그 | [aka.ms/sreagent/blog](https://aka.ms/sreagent/blog) |
| 가격 | [aka.ms/sreagent/pricing](https://aka.ms/sreagent/pricing) |
| 원본 Lab | [microsoft/sre-agent](https://github.com/microsoft/sre-agent) |
