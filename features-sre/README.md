# features-sre — SRE Agent 포털 기능 채우기

이 폴더는 **Azure SRE Agent 포털의 각 섹션이 비어 있지 않도록** 하는 선언적 설정 모음입니다.

기본 Lab([README](../README.md))은 인시던트 자동 대응 하나만 시연합니다.
이 폴더를 적용하면 **Skill Builder · Hooks · Agent Canvas · Automation · Knowledge Sources ·
Response Plans** 가 실제 내용으로 채워져, 워크숍에서 SRE Agent 를 **제품 전체**로 소개할 수 있습니다.

---

## 목차

1. [적용 방법](#1-적용-방법)
2. [포털 섹션 ↔ 파일 매핑](#2-포털-섹션--파일-매핑)
3. [무엇이 만들어지나](#3-무엇이-만들어지나)
4. [수동 연결이 필요한 섹션](#4-수동-연결이-필요한-섹션)
5. [Lab 시나리오와의 연계](#5-lab-시나리오와의-연계)
6. [항목 추가·수정하기](#6-항목추가수정하기)
7. [정리](#7-정리)

---

## 1. 적용 방법

Lab 이 이미 배포되어 있어야 합니다 ([README — 3. 빠른 시작](../README.md#3-빠른-시작)).

```powershell
# 저장소 루트에서
pwsh -File features-sre/scripts/apply-features.ps1
```

엔드포인트는 azd 환경(`SRE_AGENT_ENDPOINT`)에서 자동으로 읽습니다. 직접 지정하려면:

```powershell
pwsh -File features-sre/scripts/apply-features.ps1 `
  -Endpoint https://<agent>--<id>.<region>.azuresre.ai
```

| 옵션 | 용도 |
|---|---|
| `-SkipKnowledge` | 지식 문서 업로드 건너뛰기 (재실행 시 인덱싱 시간 절약) |
| `-EnableGitHubConnector` | GitHub 커넥터 생성 — 이후 포털에서 **인증(Authorize)** 필요 |

**재실행 안전합니다.** 모든 리소스는 이름 기준으로 생성·교체되며, 스케줄 작업은 동일 이름을
삭제 후 재생성합니다. 스크립트 마지막에 각 섹션의 항목 수를 출력합니다.

```
Verification — what the portal will now show
   Knowledge Sources   6 item(s)  escalation-policy.md, grubify-slo.md, ...
   Skill Builder       4 item(s)  containerapp-safe-scaling, cost-guardrail-review, ...
   Hooks               4 item(s)  post-write-verification, pre-write-evidence-gate, ...
   Agent Canvas        3 item(s)  incident-handler, cost-analyzer, reliability-reviewer
   Automation          3 item(s)  daily-grubify-health, nightly-reliability-scan, ...
   Response plans      2 item(s)  Grubify HTTP Errors, Grubify Latency Degradation (Review mode)
```

적용 후 [sre.azure.com](https://sre.azure.com) 을 **새로고침**하세요.

---

## 2. 포털 섹션 ↔ 파일 매핑

| 포털 위치 | 이 폴더 | 사용하는 데이터플레인 API |
|---|---|---|
| Builder ▸ **Knowledge Sources** | [knowledge/](knowledge) | `POST /api/v1/AgentMemory/upload` |
| Builder ▸ **Skill Builder** | [skills/](skills) | `PUT /api/v2/extendedAgent/skills/{name}` |
| Builder ▸ **Hooks** | [hooks/](hooks) | `PUT /api/v2/extendedAgent/hooks/{name}` |
| Builder ▸ **Agent Canvas** | [agents/](agents) | `PUT /api/v2/extendedAgent/agents/{name}` |
| **Automation** | [automation/](automation) | `POST /api/v1/scheduledtasks` |
| **Incidents** ▸ Response plans | [response-plans/](response-plans) | `PUT · POST /api/v1/incidentPlayground/filters/{id}` |
| Builder ▸ **Connectors** | [connectors/](connectors) | `PUT /api/v2/extendedAgent/connectors/{name}` |

> API 경로는 이 저장소의 [scripts/post-provision.sh](../scripts/post-provision.sh) 가 사용하는 것과 동일한
> 데이터플레인 API 이며, 실제 응답으로 스키마를 확인해 작성했습니다. 문서화된 공개 API 가 아니므로
> preview 기간 중 변경될 수 있습니다.

---

## 3. 무엇이 만들어지나

### Skills — Builder ▸ Skill Builder (4개)

에이전트가 필요할 때 꺼내 쓰는 **절차서**입니다. 각 스킬은 메타데이터 `.json` + 본문 `.md` 한 쌍입니다.

| 스킬 | 하는 일 |
|---|---|
| `grubify-oom-triage` | OOM 진단 — 5xx 와 메모리 압박 상관 분석, 실패 컨트롤러 특정, 근거 기반 사이징 제안 |
| `containerapp-safe-scaling` | 안전한 스케일 변경 — CPU:메모리 허용 조합 검증, 적용, 리비전 확인, 롤백 절차 |
| `cost-guardrail-review` | 읽기 전용 비용 점검 — 과대 사이징, 유휴 리비전, Log Analytics 수집량 |
| `incident-report-writer` | 인시던트 리포트 작성 규칙 — UTC 타임라인, 재현 가능한 근거, 필수 섹션 |

### Hooks — Builder ▸ Hooks (4개, 이벤트 타입 전체 커버)

에이전트 실행 흐름의 특정 시점에 **자동으로 주입되는 지시**입니다.

| 훅 | eventType | 하는 일 |
|---|---|---|
| `session-context-loader` | `Start` | 조사 시작 전 과거 인시던트 검색 + 현재 baseline 확인 강제 |
| `pre-write-evidence-gate` | `PreToolUse` | **쓰기 직전** 근거·사이징·영향범위·롤백 4가지 확인 요구 |
| `post-write-verification` | `PostToolUse` | 쓰기 직후 실제 검증 전까지 "완화됨" 표현 금지 |
| `session-wrapup-memory` | `Stop` | 종료 시 재사용 가능한 교훈을 팀 메모리에 저장 |

> `pre-write-evidence-gate` 는 **Privileged 권한 데모와 짝**입니다. 에이전트가 쓰기 권한을 가지고 있어도
> 무근거 조치를 하지 않는다는 것을 보여줍니다 →
> [README — 권한 수준 선택](../README.md#권한-수준-선택--reader기본값-vs-privileged)

### Subagents — Builder ▸ Agent Canvas (2개 추가)

기본 `incident-handler` 외에, **GitHub 연동 없이도 동작하는** Azure 전용 에이전트입니다.

| 에이전트 | 역할 | 권한 |
|---|---|---|
| `cost-analyzer` | FinOps 분석 — 우선순위가 매겨진 절감안 제시 | 읽기 전용 |
| `reliability-reviewer` | 사전 안정성 점검 — 다음 장애의 선행 지표 탐지, RAG 상태 산출 | 읽기 전용 |

### Automation — 스케줄 작업 (3개)

| 작업 | 주기 (cron, UTC) | 담당 |
|---|---|---|
| `daily-grubify-health` | `0 0 * * *` — 매일 09:00 KST | `reliability-reviewer` |
| `nightly-reliability-scan` | `0 18 * * *` — 매일 03:00 KST | `reliability-reviewer` |
| `weekly-cost-review` | `0 1 * * 1` — 매주 월 10:00 KST | `cost-analyzer` |

> cron 은 **UTC** 기준입니다. KST 는 UTC+9 이므로 원하는 한국 시각에서 9시간을 뺀 값을 쓰세요.

### Response Plans — Incidents (1개 추가)

| 계획 | 필터 | 담당 | 모드 |
|---|---|---|---|
| `grubify-http-errors` *(기본 Lab)* | Sev0~Sev4 전체 | `incident-handler` | **Autonomous** |
| `grubify-latency-review` *(추가)* | 제목에 `latency` 포함, Sev2~Sev4 | `reliability-reviewer` | **Review** |

> 두 계획이 나란히 보이므로 **Autonomous vs Review 모드 차이**를 화면에서 바로 비교할 수 있습니다.
> 추가 계획은 제목 필터가 `latency` 라서 Lab 의 5xx 경고(`alert-http-5xx-sre-lab`)를 가로채지 않습니다.

### Knowledge Sources (2개 추가)

| 문서 | 내용 |
|---|---|
| `grubify-slo.md` | SLO·에러 예산·RAG 판정 규칙 — 스케줄 작업이 "정상"을 판단하는 기준 |
| `escalation-policy.md` | 자율 허용 범위, 사람 승인 필수 항목, 에스컬레이션 트리거 |

> 이 두 문서가 없으면 스케줄 작업이 "에러율 2%" 같은 **판단 불가능한 숫자**만 보고합니다.

---

## 4. 수동 연결이 필요한 섹션

아래 세 섹션은 외부 인증·외부 저장소가 필요해 스크립트만으로 채울 수 없습니다.

### Connectors (GitHub)

```powershell
pwsh -File features-sre/scripts/apply-features.ps1 -EnableGitHubConnector
```

생성 후 포털 **Builder ▸ Connectors** 에서 **Authorize** 를 눌러 GitHub OAuth 를 완료해야
연결됨 상태가 됩니다. 인증 전에는 목록에는 보이되 미인증 상태로 표시됩니다.

### Code Access

GitHub 커넥터 인증이 **먼저** 완료되어야 합니다. 그 다음 저장소를 연결하면
에이전트가 `파일:라인` 수준으로 근본 원인을 지목할 수 있습니다.

```bash
azd env set GITHUB_USER <your-github-username>
bash scripts/post-provision.sh --retry
```

### Plugins

플러그인은 **marketplace(플러그인 저장소)** 를 먼저 등록해야 목록이 채워집니다.
포털 **Builder ▸ Plugins ▸ Add marketplace** 에서 등록하거나 `Install from URL` 을 사용하세요.
등록된 marketplace 가 없으면 `No plugins available` 이 정상 상태입니다.

---

## 5. Lab 시나리오와의 연계

| Lab 단계 | 연계되는 이 폴더의 구성 |
|---|---|
| 장애 주입 (`break-app.sh`) | `grubify-oom-triage` 스킬이 진단 절차를 제공 |
| 에이전트 조사 | `session-context-loader` 훅이 과거 인시던트를 먼저 검색 |
| 자동 완화 | `pre-write-evidence-gate` → `containerapp-safe-scaling` → `post-write-verification` |
| 리포트 작성 | `incident-report-writer` 스킬 + `grubify-slo.md` 기준 |
| 사후 학습 | `session-wrapup-memory` 훅이 교훈을 팀 메모리에 저장 |
| 평시 운영 | `daily-grubify-health` · `nightly-reliability-scan` 이 장애 없이도 화면을 채움 |

### 워크숍 데모 동선 (추천)

1. **Operations Hub** — 지난 인시던트와 지표를 먼저 보여줌 (E2E 실행 이력이 있어야 채워짐)
2. **Agent Canvas** — 에이전트 3종과 각자의 도구 구성
3. **Skill Builder** — `grubify-oom-triage` 를 열어 "에이전트가 읽는 런북"을 보여줌
4. **Hooks** — `pre-write-evidence-gate` 로 가드레일 설명
5. **Automation** — 장애가 없을 때도 도는 3개 작업
6. **Incidents ▸ Response plans** — Autonomous vs Review 비교
7. **장애 주입** → 실시간으로 1~6이 어떻게 맞물리는지 시연

---

## 6. 항목 추가·수정하기

파일을 추가하고 스크립트를 다시 실행하면 됩니다. 스크립트는 각 폴더를 훑습니다.

### 스킬 추가

`skills/my-skill.json` + `skills/my-skill.md` 두 개를 만듭니다.

```json
{
  "name": "my-skill",
  "type": "Skill",
  "properties": {
    "description": "한 줄 설명 — 에이전트가 이 스킬을 언제 쓸지 판단하는 근거",
    "skillContentFile": "my-skill.md",
    "tools": ["RunAzCliReadCommands", "QueryLogAnalyticsByWorkspaceId"]
  }
}
```

### 훅 추가

```json
{
  "name": "my-hook",
  "type": "GlobalHook",
  "properties": {
    "eventType": "PreToolUse",
    "activationMode": "always",
    "description": "설명",
    "hook": { "type": "prompt", "matcher": "RunAzCliWriteCommands", "prompt": "...", "timeout": 60 }
  }
}
```

유효값 — `eventType`: `Start` · `Stop` · `PreToolUse` · `PostToolUse` /
`activationMode`: `always` · `onDemand` / `hook.type`: `prompt` · `command`

### 스케줄 작업 추가

`name` · `description` · `cronExpression` · `agentPrompt` · `agent` 가 모두 필수입니다.
`agent` 는 Agent Canvas 에 **실제 존재하는** 서브에이전트 이름이어야 합니다.

---

## 7. 정리

Lab 리소스는 그대로 두고 이 폴더가 만든 항목만 제거하려면:

```powershell
$ep  = azd env get-value SRE_AGENT_ENDPOINT
$h   = @{ Authorization = "Bearer $(az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv)" }

'containerapp-safe-scaling','cost-guardrail-review','grubify-oom-triage','incident-report-writer' |
  ForEach-Object { Invoke-WebRequest "$ep/api/v2/extendedAgent/skills/$_" -Headers $h -Method DELETE -SkipHttpErrorCheck }

'session-context-loader','pre-write-evidence-gate','post-write-verification','session-wrapup-memory' |
  ForEach-Object { Invoke-WebRequest "$ep/api/v2/extendedAgent/hooks/$_" -Headers $h -Method DELETE -SkipHttpErrorCheck }

'cost-analyzer','reliability-reviewer' |
  ForEach-Object { Invoke-WebRequest "$ep/api/v2/extendedAgent/agents/$_" -Headers $h -Method DELETE -SkipHttpErrorCheck }

Invoke-WebRequest "$ep/api/v1/incidentPlayground/filters/grubify-latency-review" -Headers $h -Method DELETE -SkipHttpErrorCheck
```

스케줄 작업은 ID 로 삭제합니다 — `GET /api/v1/scheduledtasks` 로 ID 를 확인한 뒤
`DELETE /api/v1/scheduledtasks/{id}`.

환경 전체를 삭제하려면 [README — 8. 정리](../README.md#8-정리-cleanup) 를 따르세요.
