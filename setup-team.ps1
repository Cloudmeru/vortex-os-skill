# =============================================================================
# setup-team.ps1 - VORTEX-OS team-mode setup wizard (PRD-10, v0.2.2)
# =============================================================================
# One-time setup that writes .vortex/config.json and creates the per-user
# subdirs. Idempotent: re-running with the same answers is a no-op.
#
# Usage:
#   pwsh -NoProfile -File .\setup-team.ps1
#   pwsh -NoProfile -File .\setup-team.ps1 -Yes    # accept all defaults
#   pwsh -NoProfile -File .\setup-team.ps1 -Verify # check the existing config
#
# The wizard asks 3 questions:
#   1. Team mode? (yes/no)
#   2. Per-user audit log? (yes/no, default yes if team mode)
#   3. Per-user state? (yes/no, default yes if team mode)
# Writes .vortex/config.json and creates the per-user subdirs.
# =============================================================================
[CmdletBinding()]
param(
    [switch] $Yes,     # accept all defaults without prompting
    [switch] $Verify   # print the active config and exit
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($here -match 'plugins\\') { throw "setup-team.ps1 must be run from the skill root, not from a plugin folder" }

$vortexHome = $env:VORTEX_HOME
if (-not $vortexHome) { $vortexHome = Join-Path $env:APPDATA 'Vortex-OS' }
$vortexDir = Join-Path $vortexHome '.vortex'
$cfgPath = Join-Path $vortexDir 'config.json'

if ($Verify) {
    if (-not (Test-Path $cfgPath)) {
        Write-Host "  (no .vortex/config.json; team mode is off -- default single-user mode)"
        exit 0
    }
    Get-Content $cfgPath -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 5
    exit 0
}

# Read the current config (if any) for defaults.
$current = $null
if (Test-Path $cfgPath) {
    try { $current = Get-Content $cfgPath -Raw | ConvertFrom-Json } catch { $current = $null }
}

# Helper: ask a yes/no question, with a default.
function Ask-YN {
    param([string]$Prompt, [bool]$Default)
    if ($Yes) { return $Default }
    $yn = if ($Default) { 'Y/n' } else { 'y/N' }
    $reply = (Read-Host "$Prompt [$yn]").Trim()
    if (-not $reply) { return $Default }
    return ($reply -match '^(y|yes)$')
}

$teamMode     = if ($current) { [bool]$current.team_mode } else { $false }
$userAudit    = if ($current) { [bool]$current.user_audit_log } else { $true }
$userState    = if ($current) { [bool]$current.user_state } else { $true }
$userTasks    = if ($current) { [bool]$current.user_tasks } else { $true }
$sharedDelivs = if ($current) { [bool]$current.shared_deliverables } else { $true }

Write-Host ""
Write-Host "VORTEX-OS team-mode setup (PRD-10)" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  VORTEX_HOME: $vortexHome"
Write-Host ""
Write-Host "  Team mode shards the audit log + state + tasks per-user so two"
Write-Host "  operators (or two coding agents) can run dispatches in parallel"
Write-Host "  against a shared VORTEX_HOME without trampling each other."
Write-Host ""

$teamMode     = Ask-YN "Enable team mode?" $teamMode
$userAudit    = Ask-YN "Per-user audit log?  (audit-<user>.jsonl)" $userAudit
$userState    = Ask-YN "Per-user state?       (state/<user>/pending_approvals/)" $userState
$userTasks    = Ask-YN "Per-user tasks?       (tasks/<user>/)" $userTasks
$sharedDelivs = Ask-YN "Shared deliverables?  (deliverables/ is one shared dir)" $sharedDelivs

$config = [ordered]@{
    team_mode             = $teamMode
    user_audit_log        = $userAudit
    user_state            = $userState
    user_tasks            = $userTasks
    shared_deliverables   = $sharedDelivs
    file_locking          = 'advisory'
    lock_retry_ms         = 100
    lock_max_attempts     = 50
}

New-Item -ItemType Directory -Path $vortexDir -Force | Out-Null
$config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding UTF8

Write-Host ""
Write-Host "Wrote $cfgPath" -ForegroundColor Green
Write-Host ""
$config | ConvertTo-Json -Depth 5 | Write-Host

# When team mode is on, ensure the per-user subdirs exist.
if ($teamMode) {
    $user = if ($env:USERNAME) { $env:USERNAME } else { 'anonymous' }
    Write-Host ""
    Write-Host "Creating per-user subdirs for $user ..."
    if ($userAudit) {
        New-Item -ItemType Directory -Path (Join-Path $vortexHome 'memory') -Force | Out-Null
    }
    if ($userState) {
        $userStateDir = Join-Path $vortexHome 'state' $user
        New-Item -ItemType Directory -Path $userStateDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $userStateDir 'pending_approvals') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $userStateDir 'in_progress') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $userStateDir 'tmp') -Force | Out-Null
    }
    if ($userTasks) {
        New-Item -ItemType Directory -Path (Join-Path $vortexHome 'tasks' $user) -Force | Out-Null
    }
    if ($sharedDelivs) {
        New-Item -ItemType Directory -Path (Join-Path $vortexHome 'deliverables') -Force | Out-Null
    }
    Write-Host "  Done. Your audit log is at: $(Join-Path $vortexHome 'memory' "audit-$user.jsonl")"
}

Write-Host ""
Write-Host "Team setup complete. Run skill.ps1 --team-config to verify." -ForegroundColor Green
