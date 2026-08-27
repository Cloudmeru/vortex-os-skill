# =============================================================================
# skill.ps1 — VORTEX-OS dispatcher entry point (PowerShell 7+, v0.1.10)
# =============================================================================
# Thin routing layer for the C++/CLI engine (Vortex.dll). The engine is the
# ONLY implementation of every command; this script:
#   1. Locates the installed engine (or auto-installs it on first run)
#   2. Loads the engine module
#   3. Forwards the user's args
#   4. Surfaces the Tier-2 LLM-as-engine fallback banner if the engine is missing
#   5. Handles two maintenance flags: --health and --recover-engine
#
# The C++/CLI engine is the canonical implementation of every command. There
# is NO parallel PowerShell implementation of any command. Per user direction
# (2026-08-27), the earlier 3-tier design (with a "Tier 1 PowerShell-only
# re-implementation of 14 commands") was rejected as a second engine to
# maintain. See docs/prd-phase2/prd-08-engine-unavailable-degraded-mode.md
# for the rationale.
# =============================================================================
[CmdletBinding()]
param(
    # Maintenance flags. Each multi-word switch is aliased to the
    # kebab-case form so the user can pass --no-engine, --recover-engine
    # (PowerShell's switch matching is case-insensitive for the alias).
    # Single-word switches ($Health, $Install, $Force) don't need aliases.
    [switch] $Health,

    [Alias('Recover-Engine')]
    [switch] $RecoverEngine,

    [Alias('No-Engine')]
    [switch] $NoEngine,

    [switch] $Install,

    [switch] $Force,

    # Override the project name (defaults to auto-deriving from the
    # objective file path or $env:VORTEX_PROJECT). The deliverables
    # for this dispatch will land at
    #   $env:VORTEX_HOME\deliverables\<Project>\
    [string] $Project,

    # All other args (the engine args) are captured here.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Arguments
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Tier 2 banner (defined at the top so the early-exit paths can call it) -
function Show-Tier2Banner {
    [CmdletBinding()]
    param(
        [string[]] $Args,
        [string] $Reason = ''
    )
    $reasonLine = if ($Reason) { "  Reason: $Reason`n" } else { '' }
    $cmd = if ($Args -and $Args.Count -gt 0) { $Args[0] } else { '<command>' }
    $llmFallback = Join-Path $here 'references\LLM-FALLBACK.md'
    Write-Host ""
    Write-Host "  +-- VORTEX-OS Engine: NOT AVAILABLE --+" -ForegroundColor Yellow
    if ($reasonLine) { Write-Host $reasonLine -ForegroundColor Yellow -NoNewline }
    Write-Host "  The C++/CLI engine (Vortex.dll) is the canonical implementation of" -ForegroundColor Yellow
    Write-Host "  every VORTEX-OS command. Without it, no command works." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  How to recover:" -ForegroundColor Yellow
    Write-Host "    1. Retry the install:  pwsh -NoProfile -File .\skill.ps1 --recover-engine" -ForegroundColor Yellow
    Write-Host "    2. If the install fails, run install.ps1 -Verbose manually to see the error." -ForegroundColor Yellow
    Write-Host "    3. If you're an LLM-coding-agent, read the Tier 2 recipe:" -ForegroundColor Yellow
    Write-Host "         $llmFallback" -ForegroundColor Yellow
    Write-Host "       The recipe lets the LLM act as the engine for this one dispatch." -ForegroundColor Yellow
    Write-Host "  +-----------------------------------------+" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "ERROR: engine unavailable; cannot run '$cmd'." -ForegroundColor Red
    Write-Host "Run 'pwsh -NoProfile -File .\skill.ps1 --health' for a full report." -ForegroundColor Red
}

# --- 0. Env setup -------------------------------------------------------------
$env:VORTEX_SKILL_ROOT = $here
if ($Project) { $env:VORTEX_PROJECT = $Project }

# --- 0a. PS7+ guard -----------------------------------------------------------
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    throw "VORTEX-OS requires PowerShell 7+ (Core). Detected: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)). Install from https://aka.ms/powershell"
}

# --- 0b. --health (works regardless of engine state) --------------------------
# Prints the active tier + recovery hints. Exits 0 always.
if ($Health) {
    $engineManifest = $null
    $engineAvailable = $false
    if (-not $NoEngine) {
        $engineManifest = & {
            # Inline Find-VortexManifest (no engine needed for the lookup).
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
        if ($engineManifest) {
            try {
                Import-Module $engineManifest -Force -ErrorAction Stop
                $engineAvailable = $true
            } catch { }
        }
    }
    $tier = if ($NoEngine -or -not $engineAvailable) { 'NOT AVAILABLE (engine missing or --no-engine forced)' } else { "AVAILABLE ($engineManifest)" }
    Write-Host ""
    Write-Host "VORTEX-OS health"
    Write-Host "================"
    Write-Host "  Tier 1 (engine): $tier"
    Write-Host "  Tier 2 (LLM):    See <skill>/references/LLM-FALLBACK.md (recipe only)"
    Write-Host "  Skill folder:    $here"
    $vortexHome = if ($env:VORTEX_HOME) { $env:VORTEX_HOME } else { Join-Path $env:APPDATA 'Vortex-OS' }
    Write-Host "  VORTEX_HOME:     $vortexHome"
    $llmFallback = Join-Path $here 'references\LLM-FALLBACK.md'
    Write-Host "  LLM fallback:    $(if (Test-Path $llmFallback) { 'present' } else { 'MISSING' })"
    Write-Host ""
    if ($engineAvailable) {
        Write-Host "  All 18 commands work. Use --recover-engine to reinstall if anything breaks."
    } else {
        Write-Host "  Engine unavailable. Recovery options:"
        Write-Host "    1. pwsh -NoProfile -File .\skill.ps1 --recover-engine"
        Write-Host "    2. If the download fails, check network or run install.ps1 -Verbose manually."
        Write-Host "    3. If you're an LLM-coding-agent, read <skill>/references/LLM-FALLBACK.md"
        Write-Host "       to act as the engine for one dispatch."
    }
    exit 0
}

# --- 0c. --recover-engine (retry install) ------------------------------------
if ($RecoverEngine) {
    $env:VORTEX_NO_AUTO_UPDATE = '0'  # clear the cache for this run
    $installer = Join-Path $here 'install.ps1'
    if (-not (Test-Path $installer)) {
        Write-Host "ERROR: install.ps1 not found at $installer" -ForegroundColor Red
        exit 2
    }
    Write-Host "[vortex-os] Retrying engine install..." -ForegroundColor Cyan
    if ($Force) { & pwsh -NoProfile -File $installer -Force } else { & pwsh -NoProfile -File $installer }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[vortex-os] install.ps1 failed (exit $LASTEXITCODE). Try install.ps1 -Verbose manually." -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "[vortex-os] Re-detecting engine..." -ForegroundColor Cyan
    $recovered = & pwsh -NoProfile -File $MyInvocation.MyCommand.Path --health
    if ($recovered -match 'AVAILABLE') {
        Write-Host "[vortex-os] Engine recovered." -ForegroundColor Green
        exit 0
    }
    Write-Host "[vortex-os] install.ps1 ran but no Vortex.psd1 found. Network or GitHub issue?" -ForegroundColor Red
    exit 1
}

# --- 0d. --no-engine: simulate engine missing (for testing) -------------------
if ($NoEngine) {
    Show-Tier2Banner -Args $Arguments
    exit 2
}

# --- 1. Auto-update check (rate-limited, opt-out) ----------------------------
# On first invocation (and every 6h after), check if a newer engine is on
# GitHub and install it if so. Skipped if $env:VORTEX_NO_AUTO_UPDATE = '1'.
$autoUpdate = Join-Path $here 'auto-update.ps1'
if (Test-Path $autoUpdate) {
    try {
        & pwsh -NoProfile -File $autoUpdate
    } catch {
        Write-Host "[vortex-os] auto-update.ps1 failed (non-fatal): $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

# --- 2. Locate the installed Vortex module manifest --------------------------
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
        throw "Engine module 'Vortex' is not installed and the installer ($installer) is missing. Run install.ps1 manually or download the 4 engine files into your user-scope module folder."
    }
    Write-Host "[vortex-os] Engine not found locally -- running installer (one-time, downloads from GitHub release) ..." -ForegroundColor Cyan
    & pwsh -NoProfile -File $installer
    if ($LASTEXITCODE -ne 0) { throw "Engine installer failed with exit $LASTEXITCODE" }
    $manifest = Find-VortexManifest
    if (-not $manifest) {
        Show-Tier2Banner -Args $Arguments -Reason 'install.ps1 ran but no Vortex.psd1 was found.'
        exit 2
    }
}

# --- 4. Import the engine ----------------------------------------------------
try {
    Import-Module $manifest -Force -ErrorAction Stop
} catch {
    Show-Tier2Banner -Args $Arguments -Reason "engine manifest found at $manifest but PowerShell can't load it: $($_.Exception.Message)"
    exit 2
}

# --- 5. Dispatch ------------------------------------------------------------
# Invoke-Vortex is the thin wrapper the Vortex.psm1 module exports. The
# engine is the canonical implementation of every command. Forward argv.
Invoke-Vortex -Arguments $Arguments
$rc = Get-VortexLastExitCode
exit $rc
