# Azure SRE Agent 기능 소개

> Azure SRE Agent 는 운영 업무(toil)를 자동화하는 Azure 관리형 AI 에이전트입니다.
> 관측(Observability) 도구 · 인시던트 플랫폼 · 소스 코드 저장소를 하나의 자동화된 워크플로로 연결합니다.
>
> 포털 [sre.azure.com](https://sre.azure.com) · 공식 문서 [learn.microsoft.com/azure/sre-agent](https://learn.microsoft.com/azure/sre-agent/overview)
> 실제 검증 결과는 **[README — E2E 실행 결과](README.md#6-e2e-실행-결과)** 참고

---

## 목차

1. [한 줄 요약](#1-한-줄-요약)
2. [동작 흐름](#2-동작-흐름)
3. [포털 한눈에 보기](#3-포털-한눈에-보기)
4. [초기 설정 — 데이터 소스 6종](#4-초기-설정--데이터-소스-6종)
5. [핵심 기능](#5-핵심-기능)
6. [권한 모델 (Permission Model)](#6-권한-모델-permission-model)
7. [관리 대상 Azure 서비스 & 통합](#7-관리-대상-azure-서비스--통합)
8. [함께 생성되는 리소스](#8-함께-생성되는-리소스)
9. [고려사항](#9-고려사항)
10. [참고 링크 & 데모 영상](#10-참고-링크--데모-영상)

---

## 1. 한 줄 요약

**새벽 2시 47분, 당직 폰이 울립니다. "결제 API 5xx 급증."**

- **원인 파악에만 1시간.** 관제 통보 → 담당자 호출 → VPN 접속 → 시스템별 로그인.
  조사를 시작하기도 전에 한 시간이 지나갑니다.
- **아는 사람이 없으면 원점.** 지난 분기 같은 장애의 원인과 조치는 개인 메모에만 남아 있습니다.
- **복구가 끝나도 반나절.** 타임라인 재구성, 장애 보고서, 재발 방지 대책, 경영층 보고.

<p align="center">
  <img src="docs/sre-agent-hook-timeline-ko.svg" alt="같은 장애에 대한 사람 대응과 Azure SRE Agent 자율 대응 타임라인 비교" width="100%">
</p>

> **Azure SRE Agent 는 이 세 구간을 대신합니다.**
> 당직자가 접속을 마쳤을 때, **원인 · 영향 범위 · 다음 조치가 채워진 조사 결과(Investigation)** 가 이미 기다립니다.
> 조사 내용은 팀 메모리에 남아 다음 장애 때 재사용됩니다.

| 구분 | 사람이 하던 방식 | SRE Agent 도입 후 |
|---|---|---|
| 알림 확인 | 사람이 깰 때까지 대기 | 즉시 Acknowledge |
| 도구 전환 | 탭 5개 이상 | 0개 (에이전트가 처리) |
| 조사 | 도구별 수동 상관분석 | 모든 소스 자동 질의 |
| 지식 축적 | 담당자 머릿속 | Memory 에 영구 저장 |
| 사후 보고 | 타임라인 수기 재구성 | 인시던트 리포트 자동 생성 |
| 공유 | 화면 캡처 · 경로 설명 | 스레드 링크 복사 → Teams/Slack |

> 에이전트는 **변경을 제안(propose)** 하고 팀이 **승인(approve)** 하는 것이 기본입니다.
> 다만 **권한 수준과 실행 모드 조합**에 따라 직접 조치도 가능합니다 → [6. 권한 모델](#6-권한-모델-permission-model)

---

## 2. 동작 흐름

<p align="center">
  <img src="docs/sre-agent-flow-ko.svg" alt="SRE Agent 동작 흐름" width="1020"/>
</p>

| 단계 | 무슨 일이 일어나나 |
|---|---|
| ① 신호 수신 | Azure Monitor · PagerDuty · ServiceNow 에서 알림을 받습니다 |
| ② Response Plan | 심각도·서비스·키워드 필터로 **담당 Custom Agent 와 자율성 수준**을 결정합니다 |
| ③ 조사 | 관측 데이터 · Knowledge Base · 코드/배포 이력을 **병렬로** 조회하며 증거를 모읍니다 |
| ④ RCA | 근본 원인 가설을 세우고 완화 방안을 제시합니다 |
| ⑤ 조치 & 기록 | 완화 실행(또는 승인 요청) · 경고 종료 · 리포트/이슈 생성 · Memory 저장 |

---

## 3. 포털 한눈에 보기

<p align="center">
  <img src="docs/sre-agent-portal-map-ko.svg" alt="SRE Agent 포털 기능 지도" width="1020"/>
</p>

### 좌측 메뉴 — 운영 (무슨 일이 일어나고 있나)

| 메뉴 | 용도 | 실습에서 볼 것 |
|---|---|---|
| **Operations Hub** | 에이전트 운영 현황 통합 대시보드 (Overview / Incident Analytics / Automation) | 조사 후 절감 시간·해결률 확인 |
| **Incidents** | 진행 중인 인시던트 그리드. 각 행 → 조사 스레드로 연결 | 자동 조사 스레드 열람 |
| **Live Reports** | 자동 생성 일일 리포트 (보안 취약점 · 인시던트 · 리소스 헬스 · 권장 조치) | "밤새 무슨 일이?" 를 대체 |
| **Automation** | 예약 작업 · HTTP 트리거 실행 현황 | 이슈 트리아지 작업 실행 |
| **Monitor** | 에이전트 메트릭 · 인시던트 지표 | — |

### 좌측 메뉴 — 구성 (내 환경에 맞추기)

| 메뉴 | 하위 항목 |
|---|---|
| **Builder** | Agent Canvas · Custom agents · Knowledge base · Incident response plans · Connectors · Custom tools |
| **Capabilities** | Built-in / MCP / 코드 실행 / 지식 / 알림 도구, Skills, Agent hooks |
| **Settings** | Managed resources(범위) · 권한 수준 · Incident platform · Knowledge Base · 사용량(AAU) |

### 좌측 메뉴 — 대화

| 항목 | 설명 |
|---|---|
| **New Chat Thread** | 자연어로 질문·조사 요청 (채팅은 **영어만 지원**) |
| **Search Threads** | 과거 조사 스레드 검색 |
| `/agent` | 특정 Custom Agent 를 직접 호출 |
| `/learn` | 팀 온보딩 인터뷰 재시작 |
| **Copy link to thread** | 스레드 딥링크 복사 → Teams/Slack 공유 |
| **Favorites ▸ Team onboarding** | 최초 온보딩 대화가 고정됨 |

---

## 4. 초기 설정 — 데이터 소스 6종

에이전트를 만들면 **"더 많은 컨텍스트. 더 나은 조사."** 설정 페이지가 열립니다.
**연결한 소스가 많을수록 조사 품질이 올라갑니다.** (진행률 바로 미연결 항목 확인)

[![설정 페이지](https://learn.microsoft.com/azure/sre-agent/media/complete-setup/complete-setup-page.png)](https://learn.microsoft.com/azure/sre-agent/complete-setup)
<sup>출처: Microsoft Learn — [Complete setup for Azure SRE Agent](https://learn.microsoft.com/azure/sre-agent/complete-setup)</sup>

| 탭 | 소스 | 연결하면 가능해지는 것 |
|---|---|---|
| 빠른 시작 | **코드** *(권장)* | GitHub · Azure DevOps. 소스 읽기, **파일:라인 단위** 원인 특정, 최근 변경 식별 |
| 빠른 시작 | **로그** *(권장)* | Kusto · Datadog · Splunk · Elasticsearch · Dynatrace · New Relic 질의 |
| 빠른 시작 | **배포** | 인시던트와 최근 배포/롤아웃 상관분석 |
| 빠른 시작 | **인시던트** | Azure Monitor · PagerDuty · ServiceNow 알림 자동 수신 |
| 전체 설정 | **Azure 리소스** | 구독/리소스 그룹 지정 → 메트릭·헬스 조회, Azure CLI 실행 |
| 전체 설정 | **기술 자료 파일** | 런북·아키텍처 문서 (`.md`/`.txt`, 파일당 50MB, 인스턴스당 1,000개) |

> 💡 **"에이전트가 내 앱을 전혀 모른다"** 는 메시지가 보이면 **코드부터 연결**하세요. 조사 품질에 가장 큰 영향을 줍니다.
> 설정을 건너뛰었다면 상태 바의 **Complete setup** 으로 언제든 돌아올 수 있습니다.

### 팀 온보딩 (Team onboarding)

설정 후 **Done and go to agent** 를 누르면 에이전트가 연결된 리소스를 먼저 탐색한 뒤,
온콜 로테이션 · 담당 서비스 · 에스컬레이션 절차를 **인터뷰 형식으로** 물어보고 Memory 에 저장합니다.
언제든 `/learn` 으로 다시 시작할 수 있습니다.

---

## 5. 핵심 기능

### 5.1 인시던트 자동화 & Response Plan

인시던트를 **어떤 Custom Agent 가, 어떤 자율성 수준으로** 처리할지 규칙으로 정의합니다.

| 필터 조건 | 예시 |
|---|---|
| Severity / Priority (복수 선택) | Sev0~Sev4, P1+P2 |
| Impacted service | `api-gateway` |
| Incident type | Default, Major, Security |
| Title contains | `"Out of memory"` |

| 자율성 수준 | 동작 |
|---|---|
| **Review** | 조치를 제안하고 **승인 대기** (신규 플랜 권장) |
| **Autonomous** | 승인 없이 직접 조사·완화 (기본값, 별도 동의 대화상자 확인) |

**라우팅 예시**

| 트리거 | 필터 | Custom Agent | 모드 |
|---|---|---|---|
| `api-high-sev` | P1+P2 on `api-gateway` | `DeploymentAnalyzer` | Review |
| `db-critical` | P1 on `postgres-primary` | `DatabaseExpert` | Autonomous |

> ⚠️ 인시던트 플랫폼을 처음 연결하면 기본 `quickstart` 플랜이 자동 생성됩니다.
> 직접 만든 플랜과 **중복 라우팅**이 발생하므로 **Builder ▸ Incident response plans ▸ Table view** 에서 삭제하세요.
> (이 Lab 의 `scripts/post-provision.sh` 는 자동으로 처리합니다.)
>
> **재조사 쿨다운(Reinvestigation cooldown)** — Azure Monitor 연동 시 기본 3시간. 같은 경고 규칙의 재발화는
> 새 조사를 만들지 않고 기존 스레드에 병합됩니다. 반복 시연 시 이 값을 줄이세요.

### 5.2 Custom Agent & Agent Canvas

특정 운영 도메인에 특화된 에이전트를 **시각적 캔버스**에서 정의하고, 트리거·도구와 연결합니다.

[![Agent Canvas](https://learn.microsoft.com/azure/sre-agent/media/sub-agents/portal-sub-agent-canvas-full.png)](https://learn.microsoft.com/azure/sre-agent/sub-agents)
<sup>출처: Microsoft Learn — [Custom agents in Azure SRE Agent](https://learn.microsoft.com/azure/sre-agent/sub-agents)</sup>

| 뷰 | 용도 |
|---|---|
| **Canvas view** | 에이전트 · 도구 · 트리거 연결을 시각적으로 표현 |
| **Table view** | 전체 목록 + Response Plan / 예약 작업 통합 그리드 |
| **Test playground** | 왼쪽에서 지침 편집, 오른쪽에서 실시간 채팅 테스트 (AI 평가 점수 제공) |

[![Test playground](https://learn.microsoft.com/azure/sre-agent/media/common/playground-agent-selected.png)](https://learn.microsoft.com/azure/sre-agent/agent-playground)
<sup>출처: Microsoft Learn — [Agent playground](https://learn.microsoft.com/azure/sre-agent/agent-playground)</sup>

- 기본 제공 subagent 6종: `Explore`, `Plan`, `CodeReview`, `Bash`, `Verification`, `GeneralPurpose`
- 조사·계획·리뷰·셸·검증 작업을 **병렬 분산** 실행
- **핸드오프 체인** 지원 — 트리아지 → 도메인 전문가 → 알림 라우터 (대화 컨텍스트 공유)

이 Lab 이 만드는 Custom Agent:

| 이름 | 역할 | 정의 |
|---|---|---|
| `incident-handler` | 로그 · KQL · 런북 기반 조사 (도구 19종) | [incident-handler-full.yaml](sre-config/agents/incident-handler-full.yaml) |
| `code-analyzer` | 위 기능 + 소스 코드 검색, GitHub 이슈 생성 | [code-analyzer.yaml](sre-config/agents/code-analyzer.yaml) |
| `issue-triager` | 고객 이슈 분류 · 라벨링 · 코멘트 | [issue-triager.yaml](sre-config/agents/issue-triager.yaml) |

### 5.3 Knowledge Base

런북 · 아키텍처 문서 · 포스트모템을 업로드하면 자동 색인되어 조사 중 검색됩니다.

| 권장 콘텐츠 | 예 |
|---|---|
| 아키텍처 / 시스템 설계 | 컴포넌트·데이터 흐름 문서 |
| 트러블슈팅 가이드 | 반복 이슈 진단 절차 |
| 런북 / SOP | 정기 운영·인시던트 대응 워크플로 |
| 인시던트 리포트 · 포스트모템 | 과거 장애 원인·교훈 |
| 릴리스 노트 · 변경 이력 | 신규 기능·버그 수정 요약 |

이 Lab 에 포함된 지식 파일:

| 파일 | 내용 |
|---|---|
| [http-500-errors.md](knowledge-base/http-500-errors.md) | HTTP 500 진단 런북 (KQL 쿼리 포함) |
| [grubify-architecture.md](knowledge-base/grubify-architecture.md) | 샘플 앱 아키텍처 + 알려진 장애 모드 |
| [incident-report-template.md](knowledge-base/incident-report-template.md) | 인시던트 리포트 템플릿 |
| [github-issue-triage.md](knowledge-base/github-issue-triage.md) | 이슈 분류 기준 |

> 웹 페이지(내부 위키·상태 페이지) URL 도 지식 소스로 추가할 수 있습니다.

### 5.4 도구(Tools) & 확장 프리미티브

**도구 카테고리** — 에이전트가 실제로 "할 수 있는 일"의 최소 단위입니다.

| 카테고리 | 포함 | 설정 |
|---|---|---|
| **Built-in** | Azure CLI, App Insights/Log Analytics 질의, 메트릭 분석, AKS `kubectl`, Container Apps·Functions·App Service 진단, 차트 생성 | 불필요 (관리 ID) |
| **MCP** | Datadog · New Relic · Splunk · Elasticsearch · Dynatrace 등 40+ 커넥터, 또는 자체 MCP 서버 | MCP 커넥터 추가 |
| **코드 실행** | 샌드박스 Python · 셸 | 내장 |
| **지식** | 문서 검색, 에이전트 메모리, 애플리케이션 토폴로지 | 내장 |
| **알림** | Outlook · Teams | 커넥터 추가 |
| **인시던트/DevOps** | 인시던트 플랫폼, 소스 저장소 | 커넥터 추가 |
| **Custom tools** | 직접 만든 Kusto · Python · Link · HTTP 도구 | Builder UI |

**확장 프리미티브 5종**

| 프리미티브 | 언제 쓰나 |
|---|---|
| **Skills** | 마켓플레이스 런북 · Azure CLI 스크립트 등 팀 공용 절차 (자동 사용) |
| **Subagents / Custom agents** | 특정 도메인 전문가 (`/agent` 로 명시적 호출) |
| **Python tools** | 설정으로 표현 불가한 로직 · 데이터 변환 · API 연동 |
| **MCP servers** | 외부 데이터 소스·플랫폼 연결 |
| **Agent hooks** | 조사 전 / 해결 후 시점 이벤트 자동화 (정책 강제, 텔레메트리) |

> Skills · Custom agents · Knowledge files 비교
>
> | 구분 | Skills | Custom agents | Knowledge files |
> |---|---|---|---|
> | 호출 | 자동 | `/agent` | 검색 도구 경유 |
> | 도구 | 붙일 수 있음 | 보유 | 없음 |
> | 적합 대상 | 절차 | 도메인 전문가 | 런북·문서 |

### 5.5 Automation — 예약 작업 & 트리거

헬스 체크, 정리 작업, 컴플라이언스 스윕 등 반복 업무를 IaC 없이 일정 기반으로 실행합니다.
구성은 **커넥터 → Custom Agent → 예약 작업** 3단 조립입니다.

| 구성 요소 | 역할 | 예 |
|---|---|---|
| **Connector** | 외부 서비스 접근 | Teams, Outlook, Jira, Grafana |
| **Custom agent** | 특정 도구를 가진 작업자 | `health-check-reporter` |
| **Scheduled task** | 주기적 실행 트리거 | "매일 08:00 리소스 헬스 요약 발송" |

[![Operations Hub — Automation 탭](https://learn.microsoft.com/azure/sre-agent/media/operations-hub/operations-hub-automation-tab.png)](https://learn.microsoft.com/azure/sre-agent/operations-hub)
<sup>출처: Microsoft Learn — [Operations Hub](https://learn.microsoft.com/azure/sre-agent/operations-hub)</sup>

이 Lab 은 12시간마다 GitHub 이슈를 분류하는 `triage-grubify-issues` 작업을 생성합니다.

### 5.6 Operations Hub & Live Reports — 가치 측정

에이전트가 **실제로 도움이 되고 있는지**를 숫자로 봅니다.

[![Operations Hub — Overview](https://learn.microsoft.com/azure/sre-agent/media/operations-hub/operations-hub-overview-tab.png)](https://learn.microsoft.com/azure/sre-agent/operations-hub)
<sup>출처: Microsoft Learn — [Operations Hub](https://learn.microsoft.com/azure/sre-agent/operations-hub)</sup>

| 탭 | 답하는 질문 | 주요 카드 |
|---|---|---|
| **Overview** | 지금 내 확인이 필요한 것은? | 데이터 소스 연결 상태 · 일일 볼륨/AAU 사용량 · **Pending Actions** · System Health |
| **Incident Analytics** | 에이전트가 정말 도움이 되나? | 절감된 엔지니어링 시간 · 해결률 · 완화 중앙값(P50) · **IntentMet 점수(1~5)** |
| **Automation** | 반복 워크플로가 건강한가? | 자동화 수 · 실행 수 · 성공률 · 평균 실행 시간(P50/P95) |

[![Incident Analytics](https://learn.microsoft.com/azure/sre-agent/media/operations-hub/operations-hub-incident-analytics.png)](https://learn.microsoft.com/azure/sre-agent/operations-hub)
<sup>출처: Microsoft Learn — [Operations Hub](https://learn.microsoft.com/azure/sre-agent/operations-hub)</sup>

**Live Reports (일일 리포트)** — 매일 자동 생성되며 다음을 포함합니다.

1. 보안 findings (연결된 저장소의 CVE, 심각도별)
2. 인시던트 (활성/완화/해결 + 조사 상세)
3. 리소스별 헬스·가용성·CPU·메모리
4. 코드 최적화 권장
5. 우선순위가 매겨진 권장 조치 (예상 공수 포함)

[![Live Reports](https://learn.microsoft.com/azure/sre-agent/media/track-incident-value/daily-reports.png)](https://learn.microsoft.com/azure/sre-agent/track-incident-value)
<sup>출처: Microsoft Learn — [Track incident value](https://learn.microsoft.com/azure/sre-agent/track-incident-value)</sup>

> 기본 조회 범위는 최근 30일이며, Overview 기본 기간은 최근 7일입니다.

### 5.7 Team Memory — 사라지지 않는 지식

모든 조사가 학습됩니다. 근본 원인 · 해결 절차 · 팀 선호 · 운영 패턴이 축적되어 세션을 넘어 유지됩니다.

| 시점 | 기대 효과 |
|---|---|
| Day 1 | 도구 연결, 첫 트리아지, 내장 Azure 지식으로 즉시 진단 |
| Week 1 | 환경 토폴로지 · 장애 패턴 · 에스컬레이션 선호 학습 → 조사 속도·정확도 향상 |
| Month 1 | 조직 지식 축적, 장애 패턴 사전 포착, 신규 팀원이 첫 온콜부터 기여 |

> 이 Lab 의 E2E 에서도 에이전트가 조사 종료 시 `debugging.md`, `overview.md`,
> `grubify-oom-cart-api-incident.md` 3개 메모리 파일을 **스스로 생성**했습니다.

---

## 6. 권한 모델 (Permission Model)

<p align="center">
  <img src="docs/sre-agent-permissions-ko.svg" alt="SRE Agent 권한 모델" width="1020"/>
</p>

에이전트가 무엇을 할 수 있는지는 **세 개의 독립적인 계층**이 함께 결정합니다.

| 계층 | 무엇을 통제하나 | 설정 위치 |
|---|---|---|
| ① **관리 ID(UAMI) 의 Azure RBAC** | 에이전트가 Azure 리소스에 **할 수 있는 일** | Settings ▸ Managed resources ▸ 권한 수준 |
| ② **실행 모드 (Run mode)** | 조치 전 **승인이 필요한지** | Response Plan / 예약 작업별 |
| ③ **사용자 역할 (SRE Agent RBAC)** | 사람이 포털에서 **할 수 있는 일** | 에이전트 리소스 IAM |

### 6.1 권한 수준 — Reader vs Privileged

에이전트 생성 시 선택하며, 선택한 리소스 그룹에 대해 UAMI 에 부여되는 RBAC 역할이 달라집니다.

| 수준 | 부여되는 것 | 적합한 경우 |
|---|---|---|
| **Reader** *(기본값)* | 기본 모니터링 역할 + 리소스 종류별 **Reader** | 읽기 전용 진단. 조치가 필요하면 OBO 로 임시 승격 요청 |
| **Privileged** | 기본 모니터링 역할 + 리소스 종류별 **Contributor** | 완전한 운영 권한. 승인된 조치를 직접 실행 |

**권한 수준과 무관하게 항상 부여되는 역할**

| 역할 | 범위 | 허용 작업 |
|---|---|---|
| `Reader` | 리소스 그룹 | 리소스·속성 조회 |
| `Log Analytics Reader` | 리소스 그룹 | 로그·워크스페이스 질의 |
| `Monitoring Reader` | 리소스 그룹 | 메트릭·모니터링 데이터 |
| `Monitoring Contributor` | **구독** | Azure Monitor 경고 **확인(Acknowledge)·종료(Close)** |

> Privileged 를 선택하면 관리 리소스 그룹에서 **탐지된 리소스 종류에 맞는 Contributor 역할**이 추가됩니다.
> (예: 리소스 그룹에 Container Apps 가 있으면 Container Apps Contributor)
>
> 리소스 그룹을 지정하지 않으면 관리 ID 는 **아무 권한도 없습니다.**

**Reader 만 선택해도 그대로 동작하는 것 — 조사는 전부 됩니다**

| 작업 | Reader | 비고 |
|---|:--:|---|
| 경고 수신 · Acknowledge | ✅ | |
| Knowledge Base 검색 (런북·아키텍처·과거 인시던트) | ✅ | |
| 메트릭 · KQL 로그 질의 | ✅ | |
| 리비전 · 배포 이력 · 리소스 구성 조회 | ✅ | |
| 근본 원인 분석 · `파일:라인` 특정 | ✅ | 코드 연결 시 |
| 차트 생성 · 인시던트 리포트 작성 | ✅ | |
| Team Memory 저장 | ✅ | |
| GitHub 이슈/PR 생성 | ✅ | GitHub 커넥터 연결 시 |
| Azure Monitor 경고 **종료(Close)** | ✅ | `Monitoring Contributor` 가 항상 부여되기 때문 |
| 리소스 **재시작 · 스케일 · 설정 변경** | ⛔ | → **OBO 승인 요청** 후 사람이 승인해야 실행 |

즉 **Reader = "진단은 완전 자동, 실행은 사람이 버튼 한 번"**,
**Privileged = "진단부터 완화까지 무인"** 모델입니다.

### 6.2 이 Lab 이 사용하는 권한 — **Privileged (의도적 선택)**

기본값은 Reader 이지만, **에이전트가 조치까지 수행하는 장면을 재현**하기 위해
이 Lab 은 Privileged 상당으로 구성했습니다.
[infra/modules/subscription-rbac.bicep](infra/modules/subscription-rbac.bicep) 에서 **구독 범위**로 5개 역할을 할당합니다.

| 역할 | 종류 | 부여 기준 | 이 Lab 에서 실제로 쓰인 곳 |
|---|:--:|---|---|
| `Reader` | 읽기 | 항상 | Container App 구성·리비전 조회 |
| `Monitoring Reader` | 읽기 | 항상 | 요청/CPU/메모리 메트릭 조회 |
| `Log Analytics Reader` | 읽기 | 항상 | `ContainerAppConsoleLogs_CL` KQL 질의 |
| `Monitoring Contributor` | **쓰기** | 항상 | 경고 `alert-http-5xx-sre-lab` **종료** |
| `Container Apps Contributor` | **쓰기** | **Privileged 선택 시** | 리비전 **재시작**, 메모리 **1Gi→2Gi 확장** |

> 마지막 한 줄이 이 Lab 을 Privileged 로 만듭니다. 이것만 제거하면 Reader 상당으로 돌아가며,
> 에이전트는 조사를 마친 뒤 완화 단계에서 OBO 승인을 요청하며 대기합니다.
> (전환 방법은 [README — 권한 수준 선택](README.md#권한-수준-선택--reader기본값-vs-privileged) 참고)

> 🔐 운영 환경에서는 **구독 범위 Contributor 부여를 피하고**, 대상 리소스 그룹 범위로만 최소 권한을 부여하세요.
> 이 Lab 은 실습 편의를 위해 구독 범위를 사용합니다.

### 6.3 쓰기 작업 시 실제 동작 — 권한 × 실행 모드

| 권한 보유 | 실행 모드 | 에이전트 동작 |
|:--:|---|---|
| ✅ | Review | 조치 전 **동의(Consent) 요청** → 승인 후 자체 권한으로 실행 |
| ✅ | Autonomous | **승인 없이 즉시 실행** ← 이 Lab 의 E2E 경로 |
| ❌ | Review | **OBO 승인 요청** (관리자 자격 증명 필요) |
| ❌ | Autonomous | 자율 모드여도 **OBO 승인 요청** |

읽기 작업은 권한이 있으면 두 모드 모두 즉시 수행하고, 권한이 없으면 읽기라도 OBO 승인이 필요합니다.

### 6.4 OBO (On-Behalf-Of) — 권한이 없을 때의 우회 경로

[![OBO 승인 프롬프트](https://learn.microsoft.com/azure/sre-agent/media/permissions/portal-on-behalf-of-authorization.png)](https://learn.microsoft.com/azure/sre-agent/permissions)
<sup>출처: Microsoft Learn — [Agent permissions](https://learn.microsoft.com/azure/sre-agent/permissions)</sup>

1. 에이전트가 관리 ID 로 작업을 시도합니다.
2. 권한이 부족하면 **Approve action** 프롬프트가 뜹니다.
3. 승인하면 **사용자 자격 증명으로** 실행됩니다.
4. 자격 증명은 **보관되지 않고**, 작업 후 다시 관리 ID 로 돌아갑니다.

> ⚠️ **SRE Agent Administrator 역할**을 가진 사용자만 OBO 를 승인할 수 있습니다.
> Standard User 는 불가하며, 개인 Microsoft 계정도 불가합니다(직장/학교 계정만 지원).

<p align="center">
  <img src="https://learn.microsoft.com/azure/sre-agent/media/permissions/permission-flow.svg" alt="Permission flow" width="720"/>
</p>
<sup>출처: Microsoft Learn — [Agent permissions](https://learn.microsoft.com/azure/sre-agent/permissions)</sup>

### 6.5 사용자 역할 (사람에게 부여)

| 영역 | Reader | Standard User | Administrator |
|---|---|---|---|
| Chat | 스레드 조회만 | 메시지 전송·스레드 시작 | + **조치 승인**, 스레드 삭제 |
| Agent Canvas | 조회 | 조회 | 생성·편집·삭제 |
| Knowledge base | 조회 | 업로드 | 업로드 + 삭제 |
| Response plans | 조회 | 조회 | 생성·편집·삭제 |
| Managed resources / Settings | 조회 | 조회 | 변경, 에이전트 중지/삭제 |

```bash
az role assignment create \
  --assignee user@company.com \
  --role "SRE Agent Administrator" \
  --scope <agent-resource-id>
```

> **Permission Gate** — 위 계층과 별개로, 5가지 확장 프리미티브의 모든 도구 호출은 실행 전
> 사전 평가 계층을 통과합니다. 사람 승인 요구 · 정책 강제 · 차단이 가능하며,
> 감사 로그는 자체 Application Insights 로 전송됩니다.

---

## 7. 관리 대상 Azure 서비스 & 통합

| 범주 | 서비스 |
|---|---|
| Compute | Virtual Machines, App Service, Container Apps, AKS, Functions |
| Storage | Blob, File Share, Managed Disk, Storage Account |
| Networking | VNet, Load Balancer, Application Gateway, NSG |
| Database | Azure SQL, Cosmos DB, PostgreSQL, MySQL, Redis |
| Monitoring | Azure Monitor, Log Analytics, Application Insights, ARM |

| 통합 범주 | 지원 대상 |
|---|---|
| 모니터링/관측 | Azure Monitor, Application Insights, Log Analytics, Grafana |
| 인시던트 관리 | Azure Monitor Alerts, PagerDuty, ServiceNow |
| 소스 관리 / CI-CD | GitHub(리포·이슈·PR), Azure DevOps(리포·작업 항목) |
| 데이터 소스 | Azure Data Explorer(Kusto), MCP 서버 |
| 알림 | Slack, Microsoft Teams, Outlook |

> 커넥터 없이도 관리 ID + RBAC 만으로 App Insights · Log Analytics · Azure Monitor 메트릭 ·
> Resource Graph · Azure CLI · AKS 진단이 **즉시 동작**합니다. 커넥터는 **Azure 외부** 시스템 연결에 필요합니다.

---

## 8. 함께 생성되는 리소스

SRE Agent 리소스를 만들면 다음이 자동 생성됩니다.

- Azure Application Insights
- Log Analytics workspace
- User-assigned Managed Identity (UAMI)

에이전트의 관측성과 ID 관리를 담당하며, 구독 내에서 직접 확인·관리할 수 있습니다.

---

## 9. 고려사항

- 채팅 인터페이스는 **영어만 지원**합니다. (런북·문서는 한국어로 작성해도 색인되지만, 프롬프트는 영어 권장)
- 리전 및 테넌트 구성에 따라 **가용성이 다릅니다.** 이 Lab 은 `eastus2`, `swedencentral`, `australiaeast` 만 허용합니다.
- 브라우저에서 `*.azuresre.ai` 도메인 접근이 필요합니다. (일부 프록시/Zscaler 가 차단)
- **사용량 기반 과금(AAU)** 입니다. 사용량은 Operations Hub ▸ Overview 또는 Settings 에서 확인하세요.
- 모든 AI 시스템과 마찬가지로 **잘못된 결론이나 부적절한 완화 방안을 제안할 수 있습니다.** 승인 전 검토하세요.
- Operations Hub 는 기본 최근 30일 데이터를 표시하며, 그 이전은 아카이브 질의가 필요합니다.

---

## 10. 참고 링크 & 데모 영상

### 문서

| 항목 | 링크 |
|---|---|
| 포털 | [sre.azure.com](https://sre.azure.com) |
| 개요 | [Overview of Azure SRE Agent](https://learn.microsoft.com/azure/sre-agent/overview) |
| 생성 및 설정 | [Create and set up](https://learn.microsoft.com/azure/sre-agent/create-and-set-up) · [Complete setup](https://learn.microsoft.com/azure/sre-agent/complete-setup) |
| 팀 온보딩 | [Team onboarding](https://learn.microsoft.com/azure/sre-agent/team-onboard) |
| Custom agents | [Custom agents](https://learn.microsoft.com/azure/sre-agent/sub-agents) · [Agent playground](https://learn.microsoft.com/azure/sre-agent/agent-playground) |
| Response plans | [Incident response plans](https://learn.microsoft.com/azure/sre-agent/incident-response-plans) · [Create a response plan](https://learn.microsoft.com/azure/sre-agent/response-plan) |
| 인시던트 플랫폼 | [Incident platforms](https://learn.microsoft.com/azure/sre-agent/incident-platforms) |
| 도구 · 커넥터 | [Tools](https://learn.microsoft.com/azure/sre-agent/tools) · [Connectors](https://learn.microsoft.com/azure/sre-agent/connectors) · [MCP connectors](https://learn.microsoft.com/azure/sre-agent/mcp-connectors) |
| 자동화 | [Automate workflows](https://learn.microsoft.com/azure/sre-agent/automate-workflows) · [Scheduled tasks](https://learn.microsoft.com/azure/sre-agent/scheduled-tasks) |
| 가치 측정 | [Operations Hub](https://learn.microsoft.com/azure/sre-agent/operations-hub) · [Track incident value](https://learn.microsoft.com/azure/sre-agent/track-incident-value) |
| 권한 | [Agent permissions](https://learn.microsoft.com/azure/sre-agent/permissions) · [Manage permissions](https://learn.microsoft.com/azure/sre-agent/manage-permissions) · [User roles](https://learn.microsoft.com/azure/sre-agent/user-roles) · [Run modes](https://learn.microsoft.com/azure/sre-agent/run-modes) |
| 보안 · 네트워크 | [Security overview](https://learn.microsoft.com/azure/sre-agent/security-overview) · [Network integration](https://learn.microsoft.com/azure/sre-agent/network-integration) |
| 확장 | [Agent hooks](https://learn.microsoft.com/azure/sre-agent/agent-hooks) · [Skills](https://learn.microsoft.com/azure/sre-agent/skills) · [Python code execution](https://learn.microsoft.com/azure/sre-agent/python-code-execution) · [MCP server](https://learn.microsoft.com/azure/sre-agent/mcp-server) |
| 가격 | [Pricing and billing](https://learn.microsoft.com/azure/sre-agent/pricing-billing) |
| 문제 해결 | [Troubleshooting FAQ](https://learn.microsoft.com/azure/sre-agent/faq-troubleshooting) |

### 데모 영상 (공식)

| 영상 | 링크 |
|---|---|
| SRE Agent Overview | [youtube.com/watch?v=DRWppVNOTqQ](https://www.youtube.com/watch?v=DRWppVNOTqQ) |
| Less Toil, More Uptime, Maximum Innovation | [youtube.com/watch?v=5c9pl8_DI3w](https://www.youtube.com/watch?v=5c9pl8_DI3w) |
| Incident Management with ServiceNow | [youtube.com/watch?v=HFobZURqSzk](https://www.youtube.com/watch?v=HFobZURqSzk) |
| 전체 재생목록 | [aka.ms/sreagent/videos](https://go.microsoft.com/fwlink/?linkid=2353300) |

> 위 화면 이미지는 모두 Microsoft Learn 공식 문서에서 참조한 것으로, 원본 문서 링크로 연결됩니다.
> 제품 UI 는 지속적으로 업데이트되므로 최신 화면은 [sre.azure.com](https://sre.azure.com) 에서 확인하세요.
