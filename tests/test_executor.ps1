#Requires -Version 7.0
<#
.SYNOPSIS
    Focused test for the v0.3.7 CmdDispatchAgentRoster fix (G1-G4).
#>
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\vortex-os-dotnet')).Path
$skillRoot = (Resolve-Path (Join-Path $root '..\vortex-os-skill')).Path
$skillPath = Join-Path $skillRoot 'skill.ps1'
if (-not (Test-Path $skillPath)) { throw "skill.ps1 not found at $skillPath" }
if (-not (Test-Path (Join-Path $root 'Vortex.psd1'))) { throw "Vortex.psd1 not found at $root. Run src\build.ps1 first." }

# v0.3.7: point at the local engine build, not the user-scope install.
# Without this, Find-VortexManifest picks the user-scope Vortex module
# (which is still v0.3.6 and doesn't have CmdDispatchAgentRoster).
$env:VORTEX_MODULE_PATH = $root
$env:VORTEX_NO_AUTO_UPDATE = '1'

$scratchHome = Join-Path $env:TEMP "vortex-exec-test-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
$env:VORTEX_HOME = $scratchHome
[IO.Directory]::CreateDirectory($scratchHome) | Out-Null

$g_pass = 0
$g_fail = 0
function Check {
    param([string]$Label, [scriptblock]$Test)
    $result = & $Test
    if ($result) {
        $script:g_pass++
        Write-Host "  PASS  $Label"
    } else {
        $script:g_fail++
        Write-Host "  FAIL  $Label" -ForegroundColor Red
    }
}

try {
    Write-Host "VORTEX-OS executor test (v0.3.7)"
    Write-Host "================================"
    Write-Host "VORTEX_HOME: $scratchHome"
    Write-Host ""

    $liveMediaStack = Join-Path $skillRoot 'agents\media-stack.json'
    $mediaStackBackup = Join-Path $scratchHome 'media-stack.json.bak'
    if (Test-Path $liveMediaStack) { Copy-Item $liveMediaStack $mediaStackBackup }

    $swarmsDir = Join-Path $scratchHome 'swarms'
    [IO.Directory]::CreateDirectory($swarmsDir) | Out-Null
    $rosterTemplate = Join-Path $swarmsDir 'executor_smoke.json'
    $rosterBody = @'
{
  "name": "executor_smoke",
  "version": "0.0.0",
  "objective_template": "smoke executor test",
  "substitutions": {},
  "deliverables": [],
  "hitl_gates": [],
  "self_heal_targets": [],
  "agent_roster": ["media-stack"]
}
'@
    Set-Content -LiteralPath $rosterTemplate -Value $rosterBody -Encoding UTF8

    # State before
    $delivDir = Join-Path $scratchHome 'deliverables'
    $delivFilesBefore = if (Test-Path $delivDir) {
        (Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue $delivDir | Measure-Object).Count
    } else { 0 }
    $auditFile = Join-Path $scratchHome 'memory\audit.jsonl'
    $auditBefore = if (Test-Path $auditFile) { (Get-Content $auditFile).Count } else { 0 }

    Write-Host "[Executor] dispatching executor_smoke -> media-stack (7 plugins)"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $rosterOut = (& pwsh -NoProfile -File $skillPath --dispatch-template $rosterTemplate 2>&1 | Out-String)
    $sw.Stop()
    Write-Host "  elapsed: $($sw.Elapsed.TotalSeconds.ToString('F1'))s"

    $delivFilesAfter = if (Test-Path $delivDir) {
        (Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue $delivDir | Measure-Object).Count
    } else { 0 }
    $auditAfter = if (Test-Path $auditFile) { (Get-Content $auditFile).Count } else { 0 }

    Write-Host ""
    Write-Host "--- audit.jsonl contents ---"
    if (Test-Path $auditFile) {
        Get-Content $auditFile | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "  (no audit file)"
    }
    Write-Host ""
    Write-Host "--- deliverables/ files ---"
    if (Test-Path $delivDir) {
        Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue $delivDir | ForEach-Object { Write-Host "  $($_.FullName) ($($_.Length)B)" }
    } else {
        Write-Host "  (no deliverables/ dir)"
    }
    Write-Host ""
    Write-Host "  deliverable FILES before: $delivFilesBefore, after: $delivFilesAfter"
    Write-Host "  audit ENTRIES before: $auditBefore, after: $auditAfter"
    Write-Host ""

    Check "G24.A: --dispatch-template invokes at least one plugin (stdout says 'Plugin ')" {
        $rosterOut -match 'Plugin '
    }
    Check "G24.B: audit.jsonl has a 'plugin_invoke' entry" {
        if (-not (Test-Path $auditFile)) { return $false }
        $content = Get-Content $auditFile -Raw
        return $content -match 'plugin_invoke'
    }
    Check "G24.C: --dispatch-template produces at least one FILE in deliverables/" {
        $delivFilesAfter -gt $delivFilesBefore
    }
    Check 'G24.D: swarm_close audit was emitted by the executor' {
        # The "tasks":[] in plan.json is from Swarm::Spawn (unchanged
        # pre-v0.3.7). The real proof the executor ran is the swarm_close
        # audit entry. We assert on that instead.
        if (-not (Test-Path $auditFile)) { return $false }
        $content = Get-Content $auditFile -Raw
        return $content -match '"action":"swarm_close"'
    }

    Write-Host ""
    Write-Host "================================"
    Write-Host "Passed: $g_pass    Failed: $g_fail"
    Write-Host ""
    if ($g_fail -gt 0) {
        Write-Host "TESTS FAILED" -ForegroundColor Red
        exit 1
    }
    Write-Host "ALL TESTS PASSED" -ForegroundColor Green
    exit 0
}
finally {
    if (Test-Path $mediaStackBackup) { Copy-Item $mediaStackBackup $liveMediaStack -Force }
    if (Test-Path $scratchHome) {
        try { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($scratchHome, 'OnlyErrorDialogs', 'SendToRecycleBin') } catch {}
    }
}
