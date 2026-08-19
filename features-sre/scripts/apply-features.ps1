<#
.SYNOPSIS
  Populates the Azure SRE Agent portal with the feature set defined in features-sre/.

.DESCRIPTION
  Applies knowledge sources, skills, hooks, subagents, scheduled tasks and response plans
  to a running SRE Agent through its data-plane API, so that the portal sections
  (Knowledge Sources, Skill Builder, Hooks, Agent Canvas, Automation, Incidents) are populated
  instead of empty.

  Safe to re-run: every resource is created with PUT (idempotent) or replaced by name.

.PARAMETER Endpoint
  SRE Agent data-plane endpoint. Defaults to the value stored in the azd environment.

.EXAMPLE
  pwsh -File features-sre/scripts/apply-features.ps1

.EXAMPLE
  pwsh -File features-sre/scripts/apply-features.ps1 -Endpoint https://my-agent--x.y.eastus2.azuresre.ai
#>
[CmdletBinding()]
param(
  [string] $Endpoint,
  [switch] $SkipKnowledge,
  [switch] $EnableGitHubConnector
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

function Write-Step($msg) { Write-Host "`n$msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "   OK   $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "   WARN $msg" -ForegroundColor Yellow }

# ── Resolve endpoint ─────────────────────────────────────────────────────────
if (-not $Endpoint) {
  $Endpoint = (azd env get-value SRE_AGENT_ENDPOINT 2>$null)
  if ($LASTEXITCODE -ne 0 -or -not $Endpoint -or $Endpoint -match 'ERROR|not found') {
    throw "Could not resolve the agent endpoint. Pass it explicitly: -Endpoint https://<agent>--<id>.<region>.azuresre.ai"
  }
}
$Endpoint = $Endpoint.Trim().TrimEnd('/')

function Get-Token {
  $t = az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv 2>$null
  if (-not $t) { throw "Could not acquire a token for https://azuresre.dev. Run 'az login' first." }
  return $t.Trim()
}

function Invoke-Agent($Method, $Path, $Body) {
  $h = @{ Authorization = "Bearer $(Get-Token)"; 'Content-Type' = 'application/json' }
  return Invoke-WebRequest -Uri "$Endpoint$Path" -Headers $h -Method $Method -Body $Body -SkipHttpErrorCheck
}

function Test-Ok($resp) { return @(200, 201, 202, 204) -contains [int]$resp.StatusCode }

function Show-Failure($resp) {
  $c = ($resp.Content -replace '\s+', ' ')
  if ($c.Length -gt 300) { $c = $c.Substring(0, 300) + '...' }
  return "HTTP $([int]$resp.StatusCode) $c"
}

Write-Host "`n=============================================" -ForegroundColor White
Write-Host "  SRE Agent — features-sre" -ForegroundColor White
Write-Host "=============================================" -ForegroundColor White
Write-Host "  Endpoint: $Endpoint"

# ── 1. Knowledge Sources ─────────────────────────────────────────────────────
if (-not $SkipKnowledge) {
  Write-Step "1/7  Knowledge Sources  ->  Builder / Knowledge Sources"
  $kb = Get-ChildItem "$root\knowledge\*.md" -ErrorAction SilentlyContinue
  if ($kb) {
    $form = @{ triggerIndexing = 'true'; files = @($kb) }
    $h = @{ Authorization = "Bearer $(Get-Token)" }
    $r = Invoke-WebRequest -Uri "$Endpoint/api/v1/AgentMemory/upload" -Headers $h -Method POST -Form $form -SkipHttpErrorCheck
    if (Test-Ok $r) { Write-Ok "uploaded: $((($kb).Name) -join ', ')" }
    else { Write-Warn2 "upload failed — $(Show-Failure $r)" }
  } else { Write-Warn2 "no files in features-sre/knowledge" }
} else {
  Write-Step "1/7  Knowledge Sources  ->  skipped"
}

# ── 2. Skills ────────────────────────────────────────────────────────────────
Write-Step "2/7  Skills  ->  Builder / Skill Builder"
foreach ($f in Get-ChildItem "$root\skills\*.json") {
  $spec = Get-Content $f.FullName -Raw | ConvertFrom-Json
  $contentFile = $spec.properties.skillContentFile
  if ($contentFile) {
    $md = Join-Path $f.DirectoryName $contentFile
    if (-not (Test-Path $md)) { Write-Warn2 "$($spec.name): missing $contentFile"; continue }
    $spec.properties | Add-Member -NotePropertyName skillContent -NotePropertyValue (Get-Content $md -Raw) -Force
    $spec.properties.PSObject.Properties.Remove('skillContentFile')
  }
  $r = Invoke-Agent PUT "/api/v2/extendedAgent/skills/$($spec.name)" ($spec | ConvertTo-Json -Depth 10)
  if (Test-Ok $r) { Write-Ok "skill: $($spec.name)" } else { Write-Warn2 "skill $($spec.name) — $(Show-Failure $r)" }
}

# ── 3. Hooks ─────────────────────────────────────────────────────────────────
Write-Step "3/7  Hooks  ->  Builder / Hooks"
foreach ($f in Get-ChildItem "$root\hooks\*.json") {
  $spec = Get-Content $f.FullName -Raw | ConvertFrom-Json
  $r = Invoke-Agent PUT "/api/v2/extendedAgent/hooks/$($spec.name)" ($spec | ConvertTo-Json -Depth 10)
  if (Test-Ok $r) { Write-Ok "hook: $($spec.name)  [$($spec.properties.eventType)]" }
  else { Write-Warn2 "hook $($spec.name) — $(Show-Failure $r)" }
}

# ── 4. Subagents ─────────────────────────────────────────────────────────────
Write-Step "4/7  Subagents  ->  Builder / Agent Canvas"
foreach ($f in Get-ChildItem "$root\agents\*.json") {
  $spec = Get-Content $f.FullName -Raw | ConvertFrom-Json
  $r = Invoke-Agent PUT "/api/v2/extendedAgent/agents/$($spec.name)" ($spec | ConvertTo-Json -Depth 10)
  if (Test-Ok $r) { Write-Ok "agent: $($spec.name)" } else { Write-Warn2 "agent $($spec.name) — $(Show-Failure $r)" }
}

# Subagent PUT is asynchronous; give it a moment before scheduled tasks reference them.
Start-Sleep -Seconds 10

# ── 5. Scheduled tasks ───────────────────────────────────────────────────────
Write-Step "5/7  Scheduled tasks  ->  Automation"
$existing = (Invoke-Agent GET '/api/v1/scheduledtasks' $null).Content | ConvertFrom-Json
foreach ($f in Get-ChildItem "$root\automation\*.json") {
  $spec = Get-Content $f.FullName -Raw | ConvertFrom-Json
  foreach ($t in @($existing | Where-Object { $_.name -eq $spec.name })) {
    Invoke-Agent DELETE "/api/v1/scheduledtasks/$($t.id)" $null | Out-Null
  }
  $r = Invoke-Agent POST '/api/v1/scheduledtasks' ($spec | ConvertTo-Json -Depth 10)
  if (Test-Ok $r) { Write-Ok "task: $($spec.name)  [$($spec.cronExpression)] -> $($spec.agent)" }
  else { Write-Warn2 "task $($spec.name) — $(Show-Failure $r)" }
}

# ── 6. Response plans ────────────────────────────────────────────────────────
Write-Step "6/7  Response plans  ->  Incidents / Response plans"
foreach ($f in Get-ChildItem "$root\response-plans\*.json") {
  $spec = Get-Content $f.FullName -Raw | ConvertFrom-Json
  $json = $spec | ConvertTo-Json -Depth 10
  $r = Invoke-Agent PUT "/api/v1/incidentPlayground/filters/$($spec.id)" $json
  # The API rejects PUT on an existing filter and asks for POST instead.
  if ([int]$r.StatusCode -eq 409) { $r = Invoke-Agent POST "/api/v1/incidentPlayground/filters/$($spec.id)" $json }
  if (Test-Ok $r) { Write-Ok "plan: $($spec.id)  [$($spec.agentMode)] -> $($spec.handlingAgent)" }
  else { Write-Warn2 "plan $($spec.id) — $(Show-Failure $r)" }
}

# ── 7. Connectors (opt-in: needs an interactive OAuth authorisation afterwards) ─
if ($EnableGitHubConnector) {
  Write-Step "7/7  Connectors  ->  Builder / Connectors"
  foreach ($f in Get-ChildItem "$root\connectors\*.json") {
    $spec = Get-Content $f.FullName -Raw | ConvertFrom-Json
    $r = Invoke-Agent PUT "/api/v2/extendedAgent/connectors/$($spec.name)" ($spec | ConvertTo-Json -Depth 10)
    if (Test-Ok $r) { Write-Ok "connector: $($spec.name) — authorise it in the portal to finish" }
    else { Write-Warn2 "connector $($spec.name) — $(Show-Failure $r)" }
  }
} else {
  Write-Step "7/7  Connectors  ->  skipped (pass -EnableGitHubConnector to create)"
}

# ── Verification ─────────────────────────────────────────────────────────────
Write-Step "Verification — what the portal will now show"
$checks = [ordered]@{
  'Knowledge Sources' = '/api/v1/AgentMemory/files'
  'Skill Builder'     = '/api/v2/extendedAgent/skills'
  'Hooks'             = '/api/v2/extendedAgent/hooks'
  'Agent Canvas'      = '/api/v2/extendedAgent/agents'
  'Automation'        = '/api/v1/scheduledtasks'
  'Response plans'    = '/api/v1/incidentPlayground/filters'
  'Connectors'        = '/api/v2/extendedAgent/connectors'
  'Code Access'       = '/api/v2/repos'
}
foreach ($k in $checks.Keys) {
  $body = (Invoke-Agent GET $checks[$k] $null).Content | ConvertFrom-Json
  $items = if ($body -is [array]) { $body }
           elseif ($null -ne $body.value) { $body.value }
           elseif ($null -ne $body.files) { $body.files }
           else { @($body) }
  $n = @($items).Count
  $names = (@($items) | ForEach-Object {
      if ($_.name) { $_.name } elseif ($_.taskName) { $_.taskName } elseif ($_.id) { $_.id }
    } | Where-Object { $_ }) -join ', '
  $color = if ($n -gt 0) { 'Green' } else { 'Yellow' }
  Write-Host ("   {0,-18} {1,2} item(s)  {2}" -f $k, $n, $names) -ForegroundColor $color
}

Write-Host "`n  Portal: https://sre.azure.com" -ForegroundColor White
Write-Host "  Sections showing 0 items need a manual step — see features-sre/README.md`n" -ForegroundColor DarkGray
