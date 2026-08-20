# Azure SRE Agent — 기능 소개 & 실습 Lab (한국어)

> Azure SRE Agent 를 배포하고, 샘플 앱을 의도적으로 망가뜨린 뒤,
> 에이전트가 **스스로 진단하고 완화**하는 과정을 확인하는 실습 저장소입니다.
>
> - 📖 **문서 사이트: [daeungo1.github.io/Azure-SRE-Agent-Lab](https://daeungo1.github.io/Azure-SRE-Agent-Lab/)** — 탭·목차·검색이 있는 읽기 편한 버전
> - 기능 설명: **[SRE_Agent.md](SRE_Agent.md)**
> - 원본 Lab: [microsoft/sre-agent — labs/starter-lab](https://github.com/microsoft/sre-agent/tree/main/labs/starter-lab) ([영문 README](docs/README.en.md))
> - **이 저장소의 모든 절차는 실제 Azure 구독에서 E2E 검증을 마쳤습니다.** → [6. 실제로 되나요](#6-실제로-되나요--e2e-실행-결과)

## 장애 시나리오 — 한눈에 보기

정답(Ground truth)을 먼저 적어 두고 장애를 주입한 뒤, 에이전트의 결론을 **10점 루브릭으로 채점**했습니다.
시나리오별 절차와 실측 기록은 [guides/](guides/README.md) 에 하나씩 정리되어 있습니다.

| # | 시나리오 | 근본 원인의 종류 | 장애 신호 | 원인 도달 | 점수 |
|---|---|---|---|--:|--:|
| [S1](guides/02-scenario-s1.md) | 메모리 누수 → OOM | 코드 · 리소스 한계 | HTTP 5xx 급증 | 4분 25초 | ✅ **10/10** |
| [S2](guides/03-scenario-s2.md) | 인그레스 포트 불일치 | 배포 설정 오류 | 전 요청 503 | **80초** | ✅ **8/10** |
| [S3](guides/04-scenario-s3.md) | 주문 API 응답 지연 | 애플리케이션 설정 | 오류 없이 4초 지연 | 4분 49초 | ✅ **8/10** |

**S1 과 S2 는 증상이 같고(5xx) 원인이 다릅니다. S3 는 아예 오류가 나지 않습니다.**
채점 종합과 에이전트가 틀린 부분은 [guides/05-results.md](guides/05-results.md) 에 있습니다.

<p align="center">
  <img src="docs/architecture-ko.svg" alt="Lab 아키텍처" width="960"/>
</p>

---

## 목차

1. [무엇을 배포하나요](#1-무엇을-배포하나요)
2. [무엇을 준비해야 하나요](#2-무엇을-준비해야-하나요)
3. [어떻게 배포하나요](#3-어떻게-배포하나요)
4. [제대로 배포됐는지 어떻게 확인하나요](#4-제대로-배포됐는지-어떻게-확인하나요)
5. [무엇을 실습하나요](#5-무엇을-실습하나요)
6. [실제로 되나요 — E2E 실행 결과](#6-실제로-되나요--e2e-실행-결과)
7. [다시 시연하려면 무엇을 되돌려야 하나요](#7-다시-시연하려면-무엇을-되돌려야-하나요)
8. [다 쓰고 나면 어떻게 정리하나요](#8-다-쓰고-나면-어떻게-정리하나요)
9. [잘 안 될 때는 어떻게 하나요](#9-잘-안-될-때는-어떻게-하나요)
10. [저장소는 어떻게 구성돼 있나요](#10-저장소는-어떻게-구성돼-있나요)

---

## 1. 무엇을 배포하나요

| 리소스 | 용도 |
|---|---|
| **SRE Agent** | Managed Identity · Knowledge Base · Custom Agent 를 갖춘 AI 에이전트 |
| **Grubify 앱** | 샘플 음식 주문 앱 (API + Frontend, Azure Container Apps) |
| **Log Analytics + App Insights** | 로그 저장 및 모니터링 |
| **Azure Monitor 경고** | HTTP 5xx 경고 → 에이전트 조사 자동 트리거 |
| **Container Registry (ACR)** | Grubify 컨테이너 이미지 빌드/저장 |
| **Managed Identity** | 에이전트가 Azure 를 조작할 때 쓰는 ID (권한은 아래 표 참고) |

### 권한 구조 — 조사와 조치의 경계

에이전트가 무엇을 할 수 있는지는 **서로 다른 두 가지**가 결정합니다. 이 둘을 하나로 보면 오해가 생깁니다.

| | 어디서 보나 | 무엇을 뜻하나 |
|---|---|---|
| ① **Agent permissions level** | 포털 **Settings ▸ Basics** | 에이전트를 만들 때 고르는 **권한 프로필** — Reader(기본값) / Privileged |
| ② **관리 ID 의 Azure RBAC** | 관리 ID 의 **역할 할당** | **Azure 가 실제로 허용·거부하는 경계.** ARM 은 이것만 보고 판정합니다 |

포털에서 에이전트를 만들면 ①을 고르는 순간 ②가 그에 맞게 채워지므로 보통 둘이 일치합니다.
**이 Lab 은 일치하지 않습니다 — 의도적으로 그렇게 구성했습니다.**

#### 이 Lab 의 실제 구성

| 항목 | 값 |
|---|---|
| Agent permissions level | **Reader** — 기본값 그대로 (`actionConfiguration.accessLevel: Low`) |
| Agent mode | **Autonomous** |
| 관리 ID 의 역할 | Reader · Monitoring Reader · Log Analytics Reader · Monitoring Contributor · **Container Apps Contributor** |

[infra/modules/subscription-rbac.bicep](infra/modules/subscription-rbac.bicep) 이 위 5개 역할을
**구독 범위로, 권한 수준과 무관하게 항상** 부여합니다. 마지막 `Container Apps Contributor` 가 쓰기 역할입니다.

#### 제품 기본값과 이 Lab 의 차이

무인 완화가 가능했던 것은 **제품이 원래 그렇게 동작해서가 아니라, 이 Lab 이 기본값 두 개를 바꿨기 때문입니다.**

| 항목 | 제품 기본값 | 이 Lab | 무엇이 달라지나 |
|---|---|---|---|
| Agent mode | **Review** — 조치 전 사람 승인 | **Autonomous** | 승인 대기 없이 실행 |
| 관리 ID 의 쓰기 역할 | 없음 *(Reader 선택 시)* | `Container Apps Contributor` | ARM 쓰기 요청이 통과 |

> **둘 중 하나만 빠져도 무인 완화는 일어나지 않습니다.** 기본 상태의 SRE Agent 는
> 조사를 마친 뒤 **사람의 승인을 기다립니다.**

> **그래서 포털에 `Reader` 로 표시되어도 에이전트는 컨테이너를 재시작하고 메모리를 확장할 수 있습니다.**
> ARM 은 권한 수준 표시가 아니라 **요청 주체가 그 작업에 대한 역할을 갖고 있는지**만 판정하기 때문입니다.
> 실제로 그렇게 동작한 기록은 [6.3 — 조치를 실행한 주체](#63-에이전트-자동-조사-타임라인)에서 활동 로그로 확인할 수 있습니다.

**이 Lab 에서 가장 중요한 보안 관점의 교훈이 여기 있습니다** —
포털의 권한 수준 표시만 보고 "이 에이전트는 읽기 전용이겠거니" 판단하면 안 되고,
**관리 ID 에 실제로 붙어 있는 역할 할당을 함께 확인해야 합니다.**

#### 단계별로 — 무엇이 권한을 필요로 하나

| 인시던트 처리 단계 | 필요한 역할 | 이 Lab |
|---|---|:--:|
| 경고 수신 · Acknowledge | `Monitoring Contributor` | ✅ |
| Knowledge Base(런북·아키텍처) 검색 | 없음 | ✅ |
| 메트릭 · KQL 로그 질의 | `Monitoring Reader` · `Log Analytics Reader` | ✅ |
| 리비전 · 배포 이력 · 리소스 구성 조회 | `Reader` | ✅ |
| 소스 코드에서 `파일:라인` 근본 원인 특정 | 없음 *(GitHub 연동 필요)* | 연동 시 |
| 차트 생성 · 인시던트 리포트 작성 · Team Memory 저장 | 없음 | ✅ |
| Azure Monitor 경고 **종료(Close)** | `Monitoring Contributor` | ✅ |
| 컨테이너 **재시작 · 스케일 · 설정 변경** | **`Container Apps Contributor`** | ✅ |

**조사에 해당하는 항목에는 쓰기 역할이 하나도 필요하지 않습니다.**
쓰기 역할이 없으면 마지막 줄만 막히고, 그때 에이전트는 조사를 끝낸 뒤
**`Approve action`(OBO) 승인 요청**을 띄우고 대기합니다.
승인하면 **승인한 사람의 자격 증명으로** 실행되며, 자격 증명은 저장되지 않고 작업 후 다시 관리 ID 로 돌아갑니다.
승인은 **SRE Agent Administrator** 역할을 가진 직장/학교 계정만 가능합니다.

즉 쓰기 역할 없이 운영하면 **"진단은 완전 자동, 실행은 사람이 버튼 한 번"** 모델이 되고,
쓰기 역할을 부여하면 이 Lab 처럼 **"진단부터 완화까지 무인"** 모델이 됩니다.

#### 쓰기 권한 없이 운영하려면 (선택)

OBO 승인 흐름을 확인하고 싶거나 쓰기 권한을 부여할 수 없는 환경이라면
`Container Apps Contributor` 만 제거하면 됩니다.

```bash
# 배포 후 해당 역할만 회수 → Reader 상당으로 전환
PRINCIPAL_ID=$(az identity show -g rg-sre-lab \
  --name "$(az identity list -g rg-sre-lab --query '[0].name' -o tsv)" \
  --query principalId -o tsv)

az role assignment delete --assignee "$PRINCIPAL_ID" \
  --role "Container Apps Contributor" \
  --scope "/subscriptions/$(az account show --query id -o tsv)"
```

이 상태로 `break-app.sh` 를 실행하면 에이전트가 조사를 마친 뒤
**완화 단계에서 승인 프롬프트를 띄우고 대기**합니다.

> 🔐 **운영 환경 권장:** 구독 범위 부여를 피하고 **대상 리소스 그룹 범위**로만
> 필요한 역할을 주세요. 또한 신규 Response Plan 은 **Review 모드로 시작**해 동작을 검증한 뒤
> Autonomous 로 전환하는 것이 안전합니다.
> 전체 권한 모델(계층 · 실행 모드 매트릭스 · OBO)은
> **[SRE_Agent.md — 권한 모델](SRE_Agent.md#5-권한과-승인은-어떻게-통제하나요)** 참고.

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

## 2. 무엇을 준비해야 하나요

| 도구 | Windows 설치 | macOS 설치 |
|---|---|---|
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) 2.60+ | `winget install Microsoft.AzureCLI` | `brew install azure-cli` |
| [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) 1.9+ | `winget install Microsoft.Azd` | `brew install azd` |
| [Git](https://git-scm.com/) 2.x | `winget install Git.Git` | `brew install git` |
| [Python](https://python.org) 3.10+ | `winget install Python.Python.3.12` | `brew install python3` |

> **Windows 주의 (중요):** Python 설치 후 **설정 → 앱 → 앱 실행 별칭**에서 `python.exe`, `python3.exe` 를 **끄세요.**
> 켜져 있으면 `python3` 가 Microsoft Store 스텁으로 잡혀 구성 스크립트가 조용히 실패합니다.
> (이 저장소의 스크립트는 스텕을 자동 감지해 우회하도록 수정했습니다 — [6.7 발견·수정한 이슈](#67-실습-중-발견하고-수정한-이슈) 참고)
>
> Bash 스크립트는 **Git Bash** 로 실행합니다: `& "C:\Program Files\Git\bin\bash.exe" scripts/...`

### Azure 요구사항

- 구독에 **Owner** 권한 (구독 범위 RBAC 역할 할당 필요)
- 리소스 공급자 등록: `az provider register -n Microsoft.App --wait`
- 리전 — SRE Agent 는 **Korea Central 을 포함해 19개 리전**을 지원합니다
  ([지원 리전](https://learn.microsoft.com/azure/sre-agent/supported-regions)).
  이 Lab 은 기본값으로 `eastus2` 를 쓰며, `azd env set AZURE_LOCATION <region>` 으로 바꿀 수 있습니다.
  구독이 SRE Agent 사용 대상으로 등록되지 않았다면 포털의 리전 목록이 비어 있습니다.

### 선택 사항

- GitHub 계정 — 시나리오 2·3 을 위해 [dm-chelupati/grubify](https://github.com/dm-chelupati/grubify/fork) 를 fork

> ⚠️ **fork 했다면 `GITHUB_USER` 를 반드시 설정하세요.**
> 설정하지 않으면 에이전트가 업스트림 저장소를 대상으로 삼아 **남의 저장소에 이슈를 만들 수 있습니다.**
> 실제로 이 Lab 에서 발생했고, 재발 방지 조치를 넣었습니다 → [6.11](#611-에이전트가-업스트림-저장소에-이슈를-만든-건)
>
> ```bash
> azd env set GITHUB_USER <your-github-username>
> ```
>
> 이슈를 앱 저장소가 아닌 **별도 저장소**에 모으고 싶다면 `GITHUB_ISSUE_REPO` 를 함께 지정하세요.
> 지정하지 않으면 `GITHUB_REPO` 와 같은 저장소를 사용합니다.
>
> ```bash
> azd env set GITHUB_ISSUE_REPO <owner>/<repo>
> ```

---

## 3. 어떻게 배포하나요

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

### 3단계 (선택) — 포털 기능 전체 채우기

기본 Lab 은 인시던트 자동 대응 하나만 구성합니다. SRE Agent 를 **제품 전체**로
보여주려면 [features-sre](features-sre) 를 적용해 포털의 빈 섹션을 채우세요.

```powershell
pwsh -File features-sre/scripts/apply-features.ps1
```

Skill Builder · Hooks · Agent Canvas · Automation · Knowledge Sources · Response Plans 가
실제 내용으로 채워집니다. 자세한 내용은 **[features-sre/README.md](features-sre/README.md)** 참고.

---

## 4. 제대로 배포됐는지 어떻게 확인하나요

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

## 5. 무엇을 실습하나요

| # | 시나리오 | 대상 | 소요 | GitHub 필요 |
|:--:|---|---|:--:|:--:|
| 0 | **포털 투어** — 설정·Builder·Capabilities 둘러보기 | 전체 | 10분 | ❌ |
| 1 | 앱 장애(메모리 누수) → 에이전트가 로그 기반 조사·완화 | IT 운영 | 20분 | ❌ |
| 1-B | **배포 설정 오류**(포트 불일치) → 리비전 기동 실패 조사 | IT 운영 · DevOps | 20분 | ❌ |
| 1-C | **용량 부족 지연**(CPU 삭감) → 오류 없는 느림 ⚠️ 재현 안 됨 | IT 운영 | 15분 | ❌ |
| 2 | 동일 장애 → 소스 코드에서 근본 원인 발견 + GitHub 이슈 생성 | 개발자 + IT | 20분 | ✅ |
| 3 | 고객 이슈 트리아지 → 분류·라벨·코멘트 자동화 | 워크플로 자동화 | 10분 | ✅ |
| 4 | **가치 측정** — Operations Hub · Live Reports 로 효과 확인 | 의사결정자 | 10분 | ❌ |

> 시간이 부족하면 **0 → 1 → 4** 순서만으로도 완결된 스토리가 됩니다 (GitHub 불필요, 약 40분).
> 시나리오 1 과 1-B 는 **근본 원인의 종류가 다릅니다** — 앞은 코드·용량 문제, 뒤는 배포 설정 오류입니다.
> 둘을 이어서 보여주면 "에이전트가 증상이 아니라 **원인을** 본다"는 점이 분명해집니다.

### 시나리오 0 — 포털 투어 (GitHub 불필요)

장애를 일으키기 전에 **에이전트가 어떤 재료로 일하는지**를 먼저 보여주세요.
[sre.azure.com](https://sre.azure.com) → 해당 에이전트 선택 후 순서대로 확인합니다.

| 순서 | 위치 | 볼 것 | 설명 포인트 |
|:--:|---|---|---|
| 1 | 상단 **Complete setup** (전체 설정) | 코드·로그·배포·인시던트·Azure 리소스·기술 자료 파일 | 연결한 소스가 많을수록 조사 품질이 올라간다 |
| 2 | **Settings ▸ Knowledge Base** | 업로드된 런북 4개가 색인(Indexed) 상태 | 에이전트가 *우리 팀 절차*를 따른다 |
| 3 | **Builder ▸ Agent Canvas** | `incident-handler` 와 연결된 도구 19종 | 도메인별 전문 에이전트를 직접 만든다 |
| 4 | **Builder ▸ Incident response plans** | `grubify-http-errors` → Autonomous | 사람 개입 없이 라우팅된다 |
| 5 | **Capabilities** | Built-in / 코드 실행 / 지식 / MCP 도구 목록 | 커넥터 없이도 Azure 진단은 바로 된다 |
| 6 | **Settings ▸ Basics / Managed resources** | 대상 리소스 그룹과 **권한 수준 · Agent mode** | 표시는 Reader 지만 관리 ID 에 쓰기 역할을 준 상태 — 그래서 완화까지 한다 |
| 7 | **Favorites ▸ Team onboarding** | 최초 온보딩 대화 | `/learn` 으로 재시작 가능 |

그런 다음 **새 채팅**에서 가볍게 질문해 보세요 (채팅은 영어만 지원):

```text
What Azure resources are you managing right now? Give me a one-line summary of each.
```

```text
What do you already know about the Grubify application? Cite your knowledge sources.
```

### 시나리오 1 — IT 운영 (GitHub 불필요)

```bash
bash scripts/break-app.sh <API_URL> 200 0.5
```

`/api/cart/demo-user/items` 로 200회 POST 를 보내 **메모리 누수**를 유발합니다.
(in-memory 장바구니에 eviction 로직이 없음)

1. Grubify Frontend 를 열고 장바구니 담기 시도 → 실패 확인
2. **기다리기** — 경고 발화 → Response Plan 이 `incident-handler` 를 **자율 모드로 자동 실행**합니다
3. **Incidents** 메뉴에서 새 인시던트 행 → 조사 스레드 진입
4. 스레드에서 순서대로 보여주기:
   - `Reasoning` 블록 — 에이전트가 세운 **조사 계획(To-Do Plan)**
   - `Memory Search` — 런북·아키텍처 문서를 참조하는 장면
   - 메트릭/로그 병렬 수집 → **근본 원인 확정**
   - 완화 조치 실행 → 경고 종료 → 메모리 저장
5. 복구 확인: Grubify Frontend 에서 다시 장바구니 담기

> **수동 조사도 가능:** 자동 경고를 기다리지 않고 바로 보여주려면
> 새 채팅 → `/` 입력 → `incident-handler` 선택 후 아래 프롬프트를 보내세요.
>
> ```text
> The Grubify API is failing on "Add to Cart". Investigate and find the root cause,
> then propose a mitigation.
> ```
>
> 실제 소요 시간: 경고 발화 → 완화 약 5분, 최종 보고까지 약 14분 → [6. E2E 결과](#6-실제로-되나요--e2e-실행-결과)

### 시나리오 2 — 개발자 (GitHub 필요)

동일한 장애이지만, 코드 소스를 연결하면 에이전트가 추가로:

- Grubify 소스 코드에서 근본 원인 검색 → 정확한 `파일:라인` 식별
- 직전 배포와의 상관분석 ("이번 배포가 원인인가?")
- 코드 참조와 수정 제안이 포함된 GitHub 이슈 생성 (경우에 따라 수정 PR)

> 설정 방법: **Complete setup ▸ 코드** 카드에서 GitHub 연결 (OAuth 또는 PAT)
> 또는 `azd env set GITHUB_USER <username>` 후 `bash scripts/post-provision.sh --retry`
>
> 이슈 생성이 실패하면: `Use the GitHub API to create the issue if the direct tool isn't working`

### 시나리오 3 — 워크플로 자동화 (GitHub 필요)

```bash
bash scripts/create-sample-issues.sh <your-user>/grubify
```

**Builder ▸ Scheduled tasks ▸ triage-grubify-issues ▸ Run task now** 실행 후
각 `[Customer Issue]` 에 분류·라벨(`bug`, `api-bug`, `severity-high` 등)·트리아지 코멘트가 달립니다.

이어서 **Operations Hub ▸ Automation** 탭에서 방금 실행한 작업의
실행 횟수 · 성공률 · 평균 소요시간을 확인하면 자동화 운영 관점까지 연결됩니다.

> 직접 만들어보기(심화): **Connector → Custom Agent → Scheduled task** 3단 조립으로
> "매일 08:00 리소스 헬스 요약을 Teams 로 발송" 같은 작업을 만들 수 있습니다.

### 시나리오 4 — 가치 측정 (GitHub 불필요)

조사가 끝난 뒤, **이 에이전트가 정말 도움이 되었는가**를 숫자로 보여줍니다.

| 순서 | 위치 | 볼 것 |
|:--:|---|---|
| 1 | **Operations Hub ▸ Overview** | 데이터 소스 연결 상태 · Pending Actions · System Health · AAU 사용량 |
| 2 | **Operations Hub ▸ Incident Analytics** | 절감된 엔지니어링 시간 · 해결률 · 완화 중앙값(P50) · **IntentMet 점수** |
| 3 | **Operations Hub ▸ Automation** | 예약 작업·트리거 성공률과 실행 시간 |
| 4 | **Live Reports** | 보안 findings · 인시던트 요약 · 리소스 헬스 · 권장 조치 |
| 5 | 조사 스레드 ▸ **⋯ ▸ Copy link to thread** | Teams/Slack 공유용 딥링크 |

> 지표는 조사가 누적되면서 의미를 갖습니다. 첫 시연 직후에는 표본이 적을 수 있으므로,
> **"이런 것을 측정할 수 있다"** 는 관점으로 소개하는 것을 권장합니다.

### 보너스 프롬프트

**환경 파악**

```text
What is the public endpoint URL for the Grubify frontend container app?
```

```text
What recent changes were made to resources in my resource group? Check the Activity Log.
```

**진단 · 시각화** (Python 차트 도구 사용을 유도)

```text
Show me the CPU and memory usage trends for the Grubify container app over the last hour,
and plot requests vs memory on the same chart.
```

```text
Using the http-500-errors runbook, walk me through all the diagnostic KQL queries
and show me the results for the Grubify app.
```

**운영 점검**

```text
Check if there are any Azure Advisor recommendations for my resource group.
```

```text
Are there any reliability risks in this resource group? Single points of failure,
missing health probes, or undersized containers?
```

**팀 메모리** (저장 → 회상 데모)

```text
Remember that our on-call rotation is: Monday-Wednesday is Team Alpha,
Thursday-Sunday is Team Beta. Escalation path: on-call → team lead → VP Engineering.
```

```text
Who is on call today, and what should they check first if the cart API fails again?
```

### 시나리오 1-B — 배포 설정 오류 (GitHub 불필요)

시나리오 1 과 **같은 증상(HTTP 5xx), 다른 원인**입니다.
"에이전트가 증상이 아니라 원인을 보는가" 를 확인하는 시나리오입니다.

```bash
# 1) 인그레스를 앱이 듣지 않는 포트로 돌린다 → 전 요청 503
bash scripts/break-app-config.sh break

# 2) 경고 임계값을 넘도록 트래픽을 준다 (약 90건)
for i in $(seq 1 90); do curl -s -o /dev/null "$APP_URL/api/fooditems"; sleep 0.7; done

# 3) 포털에서 조사 스레드를 연다 → 끝나면 상태 확인
bash scripts/break-app-config.sh status
```

| 볼 것 | 기대 |
|---|---|
| 경고 | `alert-revision-unhealthy-sre-lab` (Sev2) 발화 |
| 조사 | 시스템 로그의 `Pending:PortMismatch` 를 근거로 제시 |
| 변별 | **"NOT OOM this time"** — 과거 메모리 누수 인시던트와 구분 |
| 조치 | `targetPort` 를 8080 으로 정렬 (Autonomous) |

> 에이전트가 스스로 복구하지 않았다면 `bash scripts/break-app-config.sh restore` 로 되돌립니다.
> 실측 결과는 [6.8](#68-시나리오-1-b--인그레스-포트-불일치-2026-08-20) 에 있습니다.

### 시나리오 1-C — 용량 부족 지연 (선택 · ⚠️ 미검증)

오류 없이 **느려지기만 하는** 장애를 만들어 에이전트가 용량 문제로 판정하는지 보려는 시나리오입니다.

```bash
bash scripts/break-app-latency.sh break     # CPU 1.0 -> 0.25, 스케일아웃 차단
CONCURRENCY=40 ROUNDS=20 bash scripts/break-app-latency.sh load
bash scripts/break-app-latency.sh restore
```

> **이 저장소의 Grubify 에서는 동작하지 않습니다.** 엔드포인트가 너무 가벼워 CPU 를 1/4 로 줄여도
> 응답 시간이 1~3ms 그대로입니다. 실측 데이터와 필요 조건은 [6.10](#610-시나리오-1-c--용량-부족-지연--재현되지-않음) 참고.

---

## 6. 실제로 되나요 — E2E 실행 결과

> 이 저장소의 결과는 **주장이 아니라 채점 결과**입니다.
> 장애를 주입하기 전에 정답(Ground truth)을 적어 두고, 에이전트의 결론을 아래 기준으로 채점했습니다.
> **에이전트가 틀린 부분도 그대로 기록합니다.**

### 6.0 평가 방법

**시간 지표**

| 지표 | 계산 |
|---|---|
| 탐지 지연 | 경고 발화 − 장애 주입 |
| 인수 지연 | 조사 스레드 생성 − 경고 발화 |
| 근본 원인 도달 | 원인 확정 − 스레드 생성 |

**RCA 점수 (10점)**

| 항목 | 배점 | 기준 |
|---|:--:|---|
| 영향 범위 | 2 | 리소스·엔드포인트·리비전을 정확히 특정 |
| 직접 원인 | 3 | Ground truth 와 일치 |
| 증거 | 2 | 로그·설정·메트릭 근거 제시 |
| 완화책 | 2 | 최소 범위이고 되돌릴 수 있음 |
| 불확실성 | 1 | 확인 못 한 부분을 구분해 표시 |

판정: ✅ Pass(8~10) · ⚠️ Partial(5~7) · ❌ Fail(0~4)

### 6.1 한눈에 보기

| 시나리오 | 장애 신호 | 탐지 | 인수 | 원인 도달 | 조치 | 점수 | 판정 |
|---|---|--:|--:|--:|---|--:|---|
| **1 — 메모리 누수 → OOM** | HTTP 5xx 급증 | 3분 | 54초 | 4분 25초 | 재시작 + 1Gi→2Gi | **10/10** | ✅ Pass |
| **1-B — 인그레스 포트 불일치** | 전 요청 503 | 2분 52초 | 49초 | **80초** | targetPort 9090→8080 | **8/10** | ✅ Pass |
| **1-C — 용량 부족 지연** | — | — | — | — | — | — | ⚠️ 재현 안 됨 |

시나리오 1 과 1-B 는 **증상이 같고(5xx) 원인이 다릅니다.** 1-B 조사에서 에이전트가 남긴 문장이 이 Lab 의 핵심입니다.

> *"Root cause identified: Port mismatch, **NOT OOM this time**. … different root cause than previous incidents."*

1-C 는 **장애가 만들어지지 않아** 점수를 매기지 못했습니다. 그 과정과 이유를 [6.10](#610-시나리오-1-c--용량-부족-지연--재현되지-않음) 에 그대로 남겼습니다.

아래는 각 시나리오의 원본 기록입니다.

> **실행일:** 2026-08-19 · **리전:** `eastus2` · **시나리오:** 1 (IT 운영, GitHub 미연동)
> 모든 타임스탬프는 **UTC** 기준입니다.

### 시나리오 1 — 무엇이 배포됐나요

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

### 시나리오 1 — 장애를 어떻게 주입했나요

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

**조치를 실행한 주체 — 활동 로그 검증**

"사람 개입 0회" 는 에이전트의 자기 보고가 아니라 **Azure 활동 로그**로 확인한 사실입니다.

| 시각(UTC) | ARM 작업 | 호출자 | 결과 |
|---|---|---|---|
| 00:22:20 | `containerApps/revisions/restart/action` | `id-sre-huvqg3bjooyw6` | Succeeded |
| 00:22:43 | `containerApps/listSecrets/action` | `id-sre-huvqg3bjooyw6` | Succeeded |
| 00:22:43 → 00:22:59 | `containerApps/write` | `id-sre-huvqg3bjooyw6` | Succeeded |

호출자는 사용자 계정(UPN)이 아니라 **에이전트의 관리 ID (`ManagedIdentity`)** 입니다.
즉 OBO 승인 경로가 아니었고, 사람이 버튼을 누른 것도 아닙니다 —
[권한 구조](#권한-구조--조사와-조치의-경계)에서 설명한대로 **관리 ID 에 부여된 `Container Apps Contributor`** 로 통과했습니다.

```bash
# 직접 확인하는 명령
az monitor activity-log list -g rg-sre-lab \
  --start-time 2026-08-19T00:00:00Z --end-time 2026-08-19T01:00:00Z \
  --query "[?contains(operationName.value,'Microsoft.App')].{time:eventTimestamp, op:operationName.value, caller:caller}" -o table
```

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

### 6.8 시나리오 1-B — 인그레스 포트 불일치 (2026-08-20)

> **실행일:** 2026-08-20 · **리전:** `eastus2` · **모드:** Autonomous
> 시나리오 1 과 **증상은 같지만(HTTP 5xx) 원인이 다른** 장애입니다.

#### Ground truth

인그레스의 `targetPort` 를 `8080` → `9090` 으로 바꿉니다.
앱은 그대로 8080 에서 듣고 있으므로 **모든 요청이 엣지에서 실패**합니다.
컨테이너 자체는 정상이라, 에이전트가 "앱이 죽었다"고 오판하지 않는지까지 확인합니다.

```bash
bash scripts/break-app-config.sh break     # 주입
bash scripts/break-app-config.sh restore   # 복구
```

#### 타임라인

| 시각(UTC) | 이벤트 | Δ |
|---|---|--:|
| 05:48:57 | `targetPort` 8080 → 9090 **주입** | — |
| 05:49:39 | 첫 503 확인 (부하 90건 전부 503) | +42초 |
| 05:51:49 | 경고 `alert-revision-unhealthy-sre-lab` (Sev2) **발화** | +2분 52초 |
| 05:52:38 | 에이전트 **인수** — 조사 스레드 생성 | +49초 |
| 05:53:27 | 팀 메모리 검색 — 과거 OOM 인시던트 6건 회수 | +49초 |
| 05:54:08 | **근본 원인 확정** | +80초 |
| 05:54:53 | **자율 조치** — `targetPort` 9090 → 8080 | +45초 |
| 05:55:22 | 복구 검증 시작 | |
| 05:53:32 | *(별도)* 5xx 메트릭 경고 발화 → 두 번째 조사 스레드 | |

#### 에이전트 분석

| 항목 | 결과 |
|---|---|
| **영향 범위** | `ca-grubify-huvqg3bjooyw6`, 리비전 `--0000005`, 요청 67건 5xx — 정확 |
| **직접 원인** | *"The TargetPort 9090 does not match the listening port 8080"* — **정확** |
| **증거** | `Pending:PortMismatch` 시스템 로그, `ReplicaUnhealthy`(startup probe: connection refused), 컨테이너 콘솔의 바인딩 로그, 메모리·CPU 정상(1~2%) |
| **완화책** | `targetPort` 를 8080 으로 정렬 — 최소 범위이고 되돌릴 수 있음 |
| **오판 구분** | *"No OOM this time — different root cause than previous incidents"* — 과거 인시던트에 끌려가지 않음 |

**잘못된 주장 (감점 사유)**

에이전트는 원인을 **"새 리비전이 앱의 리슨 포트를 바꿨는데 인그레스를 안 맞췄다"** 로 서술했습니다.
실제로는 반대입니다 — **앱은 계속 8080 이었고, 바뀐 것은 인그레스 설정**입니다. 인과의 방향을 뒤집었습니다.

원인은 **이 Lab 이 남긴 흔적**이었습니다. 첫 주입 시도에서 `ASPNETCORE_URLS=http://+:9090` 을 설정했다가
효과가 없어 되돌렸는데(6.9 참고), 그 리비전 이력이 남아 에이전트가 "앱이 9090 을 듣다가 8080 으로 바뀌었다"고
추론할 근거를 만들었습니다. **조치는 정확했지만 서사는 틀렸습니다.**

#### 점수

| 영향 | 원인 | 증거 | 완화 | 불확실성 | 합계 | 판정 |
|--:|--:|--:|--:|--:|--:|---|
| 2 | 3 | 2 | 2 | **-1** | **8/10** | ✅ Pass |

> 불확실성 항목에서 감점했습니다. 인과 방향을 **단정**했고, 리비전 이력과 인그레스 변경 중
> 무엇이 원인인지 확인하지 못했다는 표시를 하지 않았습니다.

#### 조치 주체 검증

```text
2026-08-20T05:49:02Z  containerApps/write  admin@MngEnvMCAP359144.onmicrosoft.com   ← 사람(장애 주입)
2026-08-20T05:54:53Z  containerApps/write  25b6a2dc-...(id-sre-huvqg3bjooyw6)       ← 에이전트(자율 복구)
```

복구 결과: `targetPort` 8080, 리비전 `--0000005` **Healthy**, `GET /api/fooditems` **HTTP 200**.

### 6.9 시나리오를 만들며 실패한 것

참고용으로 남깁니다. **처음 설계한 주입 방법은 동작하지 않았습니다.**

| 시도 | 결과 |
|---|---|
| `ASPNETCORE_URLS=http://+:9090` 으로 변경 | ❌ 앱이 그대로 8080 을 바인딩 — 레플리카 정상, HTTP 200 |
| 인그레스 `targetPort` 를 9090 으로 변경 | ✅ 전 요청 503 |

이 이미지는 환경 변수와 무관하게 8080 에 바인딩합니다.
그리고 **실패한 시도가 남긴 리비전 이력이 위 6.8 의 오판을 유발했습니다** —
장애 주입 Lab 에서 *증거 위생(evidence hygiene)* 이 중요하다는 실제 사례입니다.

또 하나: 이 앱은 **Application Insights 요청 계측이 없어** `AppRequests` 테이블이 비어 있습니다.
두 번째 조사에서 에이전트가 이를 스스로 발견하고
*"App Insights and Log Analytics returned zero rows — need to sanity-check the data sources"* 라고 말한 뒤
Container Apps 진단 도구로 경로를 바꿔 조사를 완료했습니다. 데이터 소스가 비어도 **멈추지 않고 우회**합니다.

### 6.10 시나리오 1-C — 용량 부족 지연 ⚠️ 재현되지 않음

**의도한 Ground truth:** CPU 를 `1.0 → 0.25` 로 줄이고 스케일아웃을 막아(`maxReplicas 1`)
**오류 없이 느려지는** 상태를 만든다. 에이전트가 OOM·설정 오류가 아닌 **용량 문제**로 판정하는지 확인.

**결과: 지연이 발생하지 않아 경고가 발화하지 않았습니다.**

| 구간 | 요청량(분당) | 서버 응답시간(평균) |
|---|--:|--:|
| 정상 (cpu 1.0) | 120 | **1~3 ms** |
| CPU 1/4 + 스케일아웃 차단 | **518 ~ 633** | **0 ~ 0.5 ms** |

트래픽은 분명히 도달했지만(분당 600건 이상) 서버 응답 시간은 그대로였습니다.
`GET /api/fooditems` 가 **메모리에서 정적 목록을 반환하는 수준**이라 CPU 를 1/4 로 줄여도 병목이 생기지 않습니다.
중간에 관측된 72ms 는 리비전 교체 직후의 **콜드 스타트**였지 부하로 인한 지연이 아니었습니다.

**그래서 무엇이 필요한가**

| 필요한 것 | 이유 |
|---|---|
| 실제 작업을 하는 엔드포인트 | 외부 호출·DB 질의·직렬화 등 CPU/IO 를 쓰는 경로가 있어야 굶겼을 때 느려집니다 |
| 또는 앱의 App Insights 계측 | `AppRequests` 의 `DurationMs` 로 p95 를 재야 정확한 지연 판정이 가능합니다 |

**남겨둔 것** — [scripts/break-app-latency.sh](scripts/break-app-latency.sh) 와 `alert-latency-sre-lab`
(평균 `ResponseTime` > 200ms) 경고 규칙은 그대로 두었습니다.
계측된 앱이나 무거운 엔드포인트가 있는 환경이라면 **그대로 재사용**할 수 있습니다.
이 저장소에서는 **"검증되지 않은 시나리오"** 로 표시합니다.

### 6.11 에이전트가 업스트림 저장소에 이슈를 만든 건

**증상** — 에이전트가 조사 결과를 원본 저장소 `dm-chelupati/grubify` 에 이슈로 등록했습니다.
사용자의 fork 가 아니라 **남의 저장소**입니다.

**원인 두 가지**

| # | 원인 | 확인 방법 |
|:--:|---|---|
| 1 | `knowledge-base/grubify-architecture.md` 가 저장소를 `dm-chelupati/grubify` 로 **하드코딩** | Knowledge Base 에 색인된 문서라 에이전트가 이를 정답으로 신뢰 |
| 2 | `GITHUB_USER` 미설정 → `post-provision.sh` 의 예약 작업이 **업스트림을 기본값**으로 사용 | `azd env get-value GITHUB_USER` → key not found |

Code Access 에는 fork(`daeungo1/grubify`)가 정상 연결되어 있었습니다.
**코드를 읽는 대상과 이슈를 쓰는 대상이 서로 달랐던 것**이 핵심입니다.

**조치 — 읽는 저장소와 쓰는 저장소를 분리**

`GITHUB_ISSUE_REPO` 를 새로 도입해, 이슈를 쓸 저장소를 코드를 읽을 저장소와 **따로** 지정합니다.

```bash
azd env set GITHUB_ISSUE_REPO daeungo1/Azure-SRE-Agent-Lab   # 이슈가 쌓일 곳
azd env set GITHUB_REPO       daeungo1/grubify               # 코드를 읽을 곳
```

- 지식 베이스에서 저장소 하드코딩을 제거하고, 실행 환경 값은 `knowledge-base/lab-environment.md` 에 **배포 시점에 렌더링**해 색인
- 서브에이전트 지시문에 *"오직 `GITHUB_ISSUE_REPO` 에만 쓸 것. 다른 저장소에는 이슈·코멘트·PR 금지. 코드 읽기는 허용"* 을 명시
- `post-provision.sh` 가 `GITHUB_REPO` 없이 예약 작업을 만들지 않도록 변경 (업스트림 기본값 제거)
- `yaml-to-api-json.py` 가 빈 값이나 업스트림 저장소를 받으면 **오류로 중단**

**재검증 (2026-08-20 07:21~07:34 UTC)** — 같은 포트 불일치 장애를 다시 주입해 확인했습니다.

| 항목 | 결과 |
|---|---|
| 조사 스레드 | `58eb42e8` 신규 생성 (07:28:24) |
| 근본 원인 | targetPort 9090 ↔ 앱 8080 불일치로 시작 프로브 크래시 루프 |
| 조치 | `UpdateTargetPort` → 8080, 07:31 복구 (1/1 replica) |
| 이슈 등록 위치 | **`daeungo1/Azure-SRE-Agent-Lab#1`** ✅ |
| 업스트림 신규 이슈 | 없음 ✅ |

> **교훈** — 에이전트에 쓰기 권한이 있는 외부 시스템에서는 **대상 범위를 지식·설정 양쪽에서 고정**해야 합니다.
> 권한을 좁히는 것만으로는 부족하고, 에이전트가 참조하는 문서가 잘못된 대상을 가리키면 그대로 따라갑니다.

---

## 7. 다시 시연하려면 무엇을 되돌려야 하나요

환경을 삭제하지 않고 **여러 번 시연**할 때만 필요한 내용입니다.

### 7.1 데모 재현을 위한 필수 리셋

에이전트가 장애를 완화하면서 **컨테너 리소스를 확장**합니다.
따라서 시연 직후의 상태 그대로는 **동일한 OOM 장애가 재현되지 않습니다.**

| 구분 | 배포 직후 (장애 재현 ⭕) | 에이전트 완화 후 (장애 재현 ❌) |
|---|---|---|
| CPU | `0.5` | `1.0` |
| Memory | `1Gi` | `2Gi` |

**다음 시연 전에 반드시 원래 사양으로 되돌리세요.**

```powershell
# PowerShell — 앱 이름을 azd 환경에서 자동으로 가져옵니다
$app = azd env get-value CONTAINER_APP_NAME
$rg  = azd env get-value AZURE_RESOURCE_GROUP
az containerapp update --name $app --resource-group $rg --cpu 0.5 --memory 1Gi
az containerapp show   --name $app --resource-group $rg `
  --query "properties.template.containers[0].resources" -o json
```

```bash
# bash
az containerapp update --name "$(azd env get-value CONTAINER_APP_NAME)" \
  --resource-group "$(azd env get-value AZURE_RESOURCE_GROUP)" \
  --cpu 0.5 --memory 1Gi
```

### 7.2 시연 전 체크리스트

| # | 항목 | 확인 방법 |
|:--:|---|---|
| 1 | 컨테너 사양이 `0.5 CPU / 1Gi` 로 리셋됨 | [7.1](#71-데모-재현을-위한-필수-리셋) |
| 2 | 앱이 정상 응답 | `POST /api/cart/demo-user/items` → 200 |
| 3 | Response Plan 이 On 상태 | `bash scripts/post-provision.sh --status` 또는 Builder ▸ Incident response plans |
| 4 | 직전 경고가 `Resolved` 상태 | Azure Portal ▸ Monitor ▸ Alerts |
| 5 | 이전 조사 스레드 정리(선택) | sre.azure.com ▸ Search Threads |

> **재조사 쿼다운(Reinvestigation cooldown):** Azure Monitor 연동 시 기본 3시간 동안
> 동일 경고 규칙의 재발화는 **새 조사를 시작하지 않고 기존 스레드에 병합**됩니다.
> 같은 날 여러 번 시연하려면 **Builder ▸ Incident response plans** 에서
> 해당 플랜의 **Reinvestigation cooldown 을 1시간으로 줄이거나 비활성화**하세요.

### 7.3 장애 주입 강도 조절

경고 조건은 **5분 창에서 5xx 가 5건 초과** 입니다.

```bash
bash scripts/break-app.sh <API_URL> 200 0.5   # 검증된 기본값: 약 2분, 5xx 약 126건
bash scripts/break-app.sh <API_URL> 150 0.3   # 더 빠른 시연이 필요할 때
```

최초 5xx 발생까지 약 3분, 경고 발화까지 약 3분, 에이전트 완화까지 경고 발화 후 약 5분.
**세션 시간을 최소 20분 확보**하세요.

### 7.4 시연 사이 비용 절감

```bash
az containerapp update --name <APP> --resource-group rg-sre-lab --min-replicas 0  # 대기
az containerapp update --name <APP> --resource-group rg-sre-lab --min-replicas 1  # 시연 전 복구
```

> **SRE Agent 자체는 사용량 기반(AAU) 과금**이므로 조사를 실행하지 않으면 큰 비용이 발생하지 않지만,
> Log Analytics · Container Apps · ACR 은 상시 과금됩니다.
> 사용량은 **Operations Hub ▸ Overview** 또는 Settings 에서 확인하세요.

### 7.5 시연 동선 제안 (50분)

| 순서 | 내용 | 자료 | 소요 |
|:--:|---|---|---|
| 1 | SRE Agent 란 무엇인가 — 한 줄 요약과 동작 흐름 | [SRE_Agent.md §1~2](SRE_Agent.md) | 5분 |
| 2 | 포털 투어 (설정 · Builder · Capabilities · 권한) | [시나리오 0](#시나리오-0--포털-투어-github-불필요) | 10분 |
| 3 | 정상 동작 시연 후 `break-app.sh` 실행 | [시나리오 1](#시나리오-1--it-운영-github-불필요) | 3분 |
| 4 | 대기 중 — 아키텍처·런북·권한 모델 설명 | [architecture-ko.svg](docs/architecture-ko.svg) · [SRE_Agent.md §5](SRE_Agent.md#5-권한과-승인은-어떻게-통제하나요) | 10분 |
| 5 | Incidents ▸ 조사 스레드 실시간 시청 | 포털 | 10분 |
| 6 | 근본 원인·완화 결과 리뷰, E2E 기록과 비교 | [6. E2E 결과](#6-실제로-되나요--e2e-실행-결과) | 5분 |
| 7 | Operations Hub · Live Reports 로 가치 측정 | [시나리오 4](#시나리오-4--가치-측정-github-불필요) | 7분 |

---

## 8. 다 쓰고 나면 어떻게 정리하나요

```bash
azd down --purge
```

> ⚠️ **SRE Agent 는 사용량 기반 과금 리소스입니다.** 환경을 더 이상 쓰지 않으면 삭제하세요.
> `--purge` 를 붙여야 Log Analytics / Application Insights 가 soft-delete 상태로 남지 않습니다.
> 반복 시연을 위해 **환경을 유지**한다면 [7. 다시 시연하려면](#7-다시-시연하려면-무엇을-되돌려야-하나요)을 따르세요.

---

## 9. 잘 안 될 때는 어떻게 하나요

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
| 두 번째 시연에서 장애가 재현되지 않음 | 에이전트가 메모리를 확장해 둔 상태 — [7.1 데모 리셋](#71-데모-재현을-위한-필수-리셋) 수행 |
| 경고는 떴는데 새 조사가 안 생김 | 재조사 쿼다운(기본 3시간)으로 기존 스레드에 병합됨 — [7.2](#72-시연-전-체크리스트) 참고 |
| 포털이 응답 없음 / 채팅 불가 | 방화벽·프록시가 `*.azuresre.ai` 를 차단했는지 확인 (허용 목록 추가) |
| 에이전트가 조치를 못하고 승인만 요청 | 권한 수준이 Reader 일 수 있음 — [SRE_Agent.md §5](SRE_Agent.md#5-권한과-승인은-어떻게-통제하나요) 참고 |

---

## 10. 저장소는 어떻게 구성돼 있나요

```text
.
├── OVERVIEW.md                      # SRE Agent 개요 (5분 브리핑용)
├── README.md                        # 이 문서 (실습 가이드 + E2E 결과 + Lab 마무리)
├── SRE_Agent.md                     # Azure SRE Agent 기능 설명 (포털·기능·권한 전반)
├── azure.yaml                       # azd 템플릿 정의
├── mkdocs.base.yml                  # 문서 사이트 테마·확장 설정 (nav 는 빌드 시 생성)
├── .github/workflows/pages.yml      # 문서 사이트 자동 배포 (GitHub Pages)
├── docs/
│   ├── architecture-ko.svg          # Lab 아키텍처 (한국어)
│   ├── architecture.svg             # Lab 아키텍처 (원본)
│   ├── sre-agent-hook-timeline-ko.svg # 사람 대응 vs 에이전트 대응 타임라인
│   ├── sre-agent-flow-ko.svg        # 에이전트 동작 흐름
│   ├── sre-agent-portal-map-ko.svg  # 포털 기능 지도
│   ├── sre-agent-permissions-ko.svg # 권한 모델
│   └── README.en.md                 # 원본(영문) starter-lab README
├── features-sre/                    # 포털 기능 채우기 — Skill · Hook · Agent · Automation
│   ├── README.md                    # 포털 섹션 ↔ 파일 매핑 · 적용 방법
│   ├── skills/ hooks/ agents/       # Skill Builder · Hooks · Agent Canvas
│   ├── automation/ response-plans/  # 스케줄 작업 · 응답 계획
│   ├── knowledge/ connectors/       # 지식 문서 · 커넥터
│   └── scripts/apply-features.ps1   # 일괄 적용 (재실행 안전)
├── infra/                           # Bicep IaC (subscription scope)
│   ├── main.bicep
│   ├── resources.bicep
│   └── modules/                     # monitoring · identity · container-app · sre-agent · alert-rules · rbac
├── knowledge-base/                  # SRE Agent 에 업로드되는 런북 · 문서
├── lab/                             # Skillable 랩 진행용 지침
├── scripts/                         # setup · post-provision · break-app · build-site
└── sre-config/                      # Custom Agent(YAML) · 커넥터 정의
```

---

## 참고

| 항목 | 링크 |
|---|---|
| **이 저장소의 문서 사이트** | [daeungo1.github.io/Azure-SRE-Agent-Lab](https://daeungo1.github.io/Azure-SRE-Agent-Lab/) |
| SRE Agent 포털 | [sre.azure.com](https://sre.azure.com) |
| 공식 문서 | [learn.microsoft.com/azure/sre-agent](https://learn.microsoft.com/azure/sre-agent/overview) |
| 블로그 | [aka.ms/sreagent/blog](https://aka.ms/sreagent/blog) |
| 가격 | [aka.ms/sreagent/pricing](https://aka.ms/sreagent/pricing) |
| 원본 Lab | [microsoft/sre-agent](https://github.com/microsoft/sre-agent) |

### 문서 사이트

`README.md` · `SRE_Agent.md` · `features-sre/README.md` **원본은 그대로 두고**,
[scripts/build-site.py](scripts/build-site.py) 가 빌드 시점에만 장 단위로 분할합니다.
분할본은 커밋되지 않으므로 **문서는 한 벌만 관리**하면 됩니다.

```bash
# 로컬 미리보기
pip install "mkdocs-material>=9.5,<10"
python scripts/build-site.py && mkdocs serve -f .site/mkdocs.yml
```

**알려진 제약**

- **한국어 검색은 어절 단위** — lunr 에 한국어 형태소 분석기가 없어 `권한` 으로 `권한을` 은 찾지 못합니다.
  띄어쓰기 기준의 온전한 단어로 검색하거나 브라우저 `Ctrl+F` 를 함께 쓰세요.
- **코드 링크는 GitHub 로 이동** — 사이트는 문서만 배포합니다.
- **문서 변경만 자동 배포** — 그 외 변경 후 갱신하려면 Actions 에서 **Run workflow** 를 실행하세요.
