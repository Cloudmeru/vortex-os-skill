# =============================================================================
# verify.ps1 — VORTEX-OS post-upload verification (PowerShell 7+)
# =============================================================================
# Self-bootstraps the engine (downloads from the public GitHub release of
# Cloudmeru/vortex-os-dotnet on first run), then invokes the C++/CLI verify
# engine against the package root.
#
# Returns exit code 0 on full success, 1 on any failure.
#
# Usage:
#   pwsh -NoProfile -File .\verify.ps1
#   pwsh -NoProfile -File .\verify.ps1 -Install    # force engine reinstall
# =============================================================================
[CmdletBinding()]
param(
    [switch] $Install
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- 0. Tell the engine where the skill folder is ---------------------------
# The Vortex verifier resolves its "package root" (where agents/, _meta.json,
# etc. live) from $env:VORTEX_SKILL_ROOT. We set it here so the in-process
# engine call finds the skill's agents/ rather than the user-scope module
# folder.
$env:VORTEX_SKILL_ROOT = $here

# --- 1. PS7+ guard -----------------------------------------------------------
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    throw "VORTEX-OS requires PowerShell 7+ (Core). Detected: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)). Install from https://aka.ms/powershell"
}

# --- 2. Locate the installed Vortex module manifest ------------------------
# Scan every plausible user-scope module base (PSModulePath + canonical
# fallback) so we work on machines with OneDrive-redirected Documents too.
function Find-VortexManifest {
    $candidates = @()
    if ($env:VORTEX_MODULE_PATH) { $candidates += $env:VORTEX_MODULE_PATH }
    if ($env:PSModulePath) {
        foreach ($entry in ($env:PSModulePath -split [IO.Path]::PathSeparator)) {
            $e = $entry.Trim()
            if (-not $e) { continue }
            if ($e -like '*WindowsPowerShell*') { continue }
            if ($e -like '*Program Files*') { continue }
            if ($candidates -notcontains $e) { $candidates += $e }
        }
    }
    $canonical = Join-Path $HOME 'Documents\PowerShell\Modules'
    if ($candidates -notcontains $canonical) { $candidates += $canonical }

    foreach ($cand in $candidates) {
        $vortexDir = Join-Path $cand 'Vortex'
        if (-not [IO.Directory]::Exists($vortexDir)) { continue }
        $versions = Get-ChildItem -LiteralPath $vortexDir -Directory -ErrorAction SilentlyContinue |
            Sort-Object { [version]($_.Name.TrimStart('v')) } -Descending
        foreach ($v in $versions) {
            $psd1 = Join-Path $v.FullName 'Vortex.psd1'
            if ([IO.File]::Exists($psd1)) { return $psd1 }
        }
    }
    return $null
}

$manifest = Find-VortexManifest

# --- 3. Auto-install if missing ---------------------------------------------
if ($Install -or -not $manifest) {
    $installer = Join-Path $here 'install.ps1'
    if (-not (Test-Path $installer)) {
        throw "Engine module 'Vortex' is not installed and the installer ($installer) is missing."
    }
    Write-Host "[vortex-os] Engine not found locally -- running installer (one-time, downloads from GitHub release) ..." -ForegroundColor Cyan
    & pwsh -NoProfile -File $installer
    if ($LASTEXITCODE -ne 0) { throw "Engine installer failed with exit $LASTEXITCODE" }
    $manifest = Find-VortexManifest
    if (-not $manifest) {
        throw "Engine installer ran but no Vortex.psd1 was found in any user-scope module folder."
    }
}

# --- 4. Tier-2 / file-I/O checks (run BEFORE the engine verify) ------------
# These checks don't require the engine to be loadable. They validate the
# skill's static structure. If they fail, the engine verify is skipped (no
# point running the engine if the skill is broken).
$v010_pass = $true
Write-Host ""
Write-Host "v0.1.10 file-I/O checks"
Write-Host "----------------------"

# Check 1: LLM-FALLBACK.md exists (Tier-2 recipe, required by the 2-tier design)
$llmFallback = Join-Path $here 'references\LLM-FALLBACK.md'
if (Test-Path $llmFallback) {
    $lineCount = (Get-Content $llmFallback).Count
    if ($lineCount -ge 50) {
        Write-Host "  ✓ LLM-FALLBACK.md present ($lineCount lines)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ LLM-FALLBACK.md too short ($lineCount lines, expected >= 50)" -ForegroundColor Red
        $v010_pass = $false
    }
} else {
    Write-Host "  ✗ LLM-FALLBACK.md MISSING (Tier 2 recipe required for engine-unavailable recovery)" -ForegroundColor Red
    $v010_pass = $false
}

# Check 2: skill.ps1 declares the 2-tier maintenance flags
$skillPs1 = Join-Path $here 'skill.ps1'
$skillContent = Get-Content $skillPs1 -Raw
$requiredFlags = @('\$Health', '\$RecoverEngine', '\$NoEngine')
foreach ($flag in $requiredFlags) {
    if ($skillContent -match $flag) {
        Write-Host "  ✓ skill.ps1 declares $flag" -ForegroundColor Green
    } else {
        Write-Host "  ✗ skill.ps1 missing $flag" -ForegroundColor Red
        $v010_pass = $false
    }
}

# Check 3: --health works (engine loadable)
if ($manifest) {
    try {
        $healthOut = & pwsh -NoProfile -File $skillPs1 --health 2>&1 | Out-String
        if ($healthOut -match 'AVAILABLE') {
            Write-Host "  ✓ --health reports engine AVAILABLE" -ForegroundColor Green
        } else {
            Write-Host "  ✗ --health did not report AVAILABLE" -ForegroundColor Red
            $v010_pass = $false
        }
    } catch {
        Write-Host "  ✗ --health failed: $($_.Exception.Message)" -ForegroundColor Red
        $v010_pass = $false
    }
}

# Check 4: --no-engine shows the Tier 2 banner
try {
    $noEngineOut = & pwsh -NoProfile -File $skillPs1 --no-engine --dispatch-master 'test.md' 2>&1 | Out-String
    if ($noEngineOut -match 'NOT AVAILABLE' -and $noEngineOut -match 'LLM-FALLBACK') {
        Write-Host "  ✓ --no-engine shows Tier 2 banner with LLM-FALLBACK pointer" -ForegroundColor Green
    } else {
        Write-Host "  ✗ --no-engine did not show the expected Tier 2 banner" -ForegroundColor Red
        $v010_pass = $false
    }
} catch {
    Write-Host "  ✗ --no-engine check failed: $($_.Exception.Message)" -ForegroundColor Red
    $v010_pass = $false
}

if (-not $v010_pass) {
    Write-Host ""
    Write-Host "v0.1.10 file-I/O checks FAILED. Skipping engine verify." -ForegroundColor Red
    exit 1
}

# --- 5. Import + verify ------------------------------------------------------
try {
    Import-Module $manifest -Force -ErrorAction Stop
    Write-Host "  ✓ engine module loaded: $manifest" -ForegroundColor Green
} catch {
    throw "VORTEX-OS engine is installed on disk at $manifest but PowerShell can't load it: $($_.Exception.Message)"
}

# Vortex.Verify::Run returns 0 on success, 1 on failure. The C++/CLI side also
# writes a human-readable summary (✓ / ✗) to stdout. The skill folder is the
# "package root" the verifier inspects (it contains _meta.json, agents/, etc.).
$rc = [Vortex.Verify]::Run($here)
exit $rc
