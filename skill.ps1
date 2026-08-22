# =============================================================================
# skill.ps1 — VORTEX-OS dispatcher entry point (PowerShell 7+)
# =============================================================================
# Drop-in wrapper for the C++/CLI engine. Auto-installs the engine from the
# public GitHub release of Cloudmeru/vortex-os-dotnet on first run, then
# forwards every argument to the dispatcher.
#
# Usage:
#   pwsh -NoProfile -File .\skill.ps1 --agents-discover
#   pwsh -NoProfile -File .\skill.ps1 --dispatch-master my_project\objective.md
#   pwsh -NoProfile -File .\skill.ps1 --hitl-approve package_websim
#
# After the first run, the Vortex module is installed in user-scope. From any
# PowerShell 7+ session:
#
#   PS> Import-Module Vortex
#   PS> Get-VortexAgent
#   PS> Get-VortexHitlPending
#   PS> Approve-VortexHitl -TaskId package_websim
#   PS> Test-VortexPackage
#
# Notes:
#   * Self-bootstrapping: downloads + installs the engine into a user-scope
#     module folder the first time it runs. No admin / system changes.
#     Re-runs are free.
#   * Works on machines with OneDrive-redirected Documents: we scan
#     `$env:PSModulePath` + `$HOME\Documents\PowerShell\Modules` + the
#     `$env:VORTEX_MODULE_PATH` override to find the installed manifest,
#     so we don't depend on a particular PSModulePath layout.
#   * Force reinstall: pass `-Install` to run install.ps1 unconditionally,
#     or set `$env:VORTEX_VERSION = 'v0.1.1'` before calling.
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Arguments,

    # Re-run the engine installer before dispatching.
    [switch] $Install,

    # Override the project name (defaults to auto-deriving from the
    # objective file path or $env:VORTEX_PROJECT). The deliverables
    # for this dispatch will land at
    #   $env:VORTEX_HOME\deliverables\<Project>\
    # e.g. `--Project trial_of_echoes` puts outputs in
    #   %APPDATA%\Vortex-OS\deliverables\trial_of_echoes\
    [string] $Project
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- 0. Tell the engine where the skill folder is ---------------------------
# The engine resolves its "package root" (where agents/, state/, memory/,
# deliverables/ live) from the first argument of Vortex.Skill::Run. We set
# the env var so the Vortex module picks up the skill folder on every call,
# not just the ones coming from this script. Set it BEFORE Import-Module
# so the module's psm1 sees the right value at load time.
$env:VORTEX_SKILL_ROOT = $here

# Also set VORTEX_PROJECT if the user passed -Project. This is read by the
# engine in Skill::Run to compute p->ProjectName and p->ProjectDeliverablesDir.
if ($Project) { $env:VORTEX_PROJECT = $Project }

# --- 0b. Auto-update check (rate-limited, opt-out) ---------------------------
# On first invocation (and every 6h after), check if a newer engine is on
# GitHub and install it if so. Skipped if $env:VORTEX_NO_AUTO_UPDATE = '1'.
# The check is non-blocking on the dispatch: install.ps1 writes to a new
# versioned folder, the current run keeps using the engine that's already
# loaded into the PowerShell session.
$autoUpdate = Join-Path $here 'auto-update.ps1'
if (Test-Path $autoUpdate) {
    try {
        & pwsh -NoProfile -File $autoUpdate
    } catch {
        Write-Host "[vortex-os] auto-update.ps1 failed (non-fatal): $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

# --- 1. PS7+ guard -----------------------------------------------------------
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    throw "VORTEX-OS requires PowerShell 7+ (Core). Detected: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)). Install from https://aka.ms/powershell"
}

# --- 2. Locate the installed Vortex module manifest ------------------------
# We deliberately do NOT use `Get-Module Vortex -ListAvailable` alone
# because that depends on $env:PSModulePath being correct, and on machines
# with OneDrive-redirected Documents the default PSModulePath points to
# a broken OneDrive path. Instead, we scan every plausible user-scope
# module base (in priority order) and pick the highest-version Vortex
# manifest we find.
function Find-VortexManifest {
    $candidates = @()
    if ($env:VORTEX_MODULE_PATH) { $candidates += $env:VORTEX_MODULE_PATH }
    if ($env:PSModulePath) {
        foreach ($entry in ($env:PSModulePath -split [IO.Path]::PathSeparator)) {
            $e = $entry.Trim()
            if (-not $e) { continue }
            # Only per-user scopes. Skip system-wide paths so we never
            # accidentally require elevation.
            if ($e -like '*WindowsPowerShell*') { continue }
            if ($e -like '*Program Files*') { continue }
            if ($candidates -notcontains $e) { $candidates += $e }
        }
    }
    # Always also try the canonical non-OneDrive user-scope path as a
    # last-resort fallback.
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
        throw "Engine installer ran but no Vortex.psd1 was found in any user-scope module folder. Try running install.ps1 manually with -Verbose to see where the files were placed."
    }
}

# --- 4. Import + dispatch ----------------------------------------------------
try {
    Import-Module $manifest -Force -ErrorAction Stop
} catch {
    throw "VORTEX-OS engine is installed on disk at $manifest but PowerShell can't load it: $($_.Exception.Message)"
}

# `Invoke-Vortex` is the thin wrapper the Vortex.psm1 module exports. With no
# args it prints the help banner and returns 0. We let its pipeline output
# flow to the host (so the user sees the agent list / dispatch progress /
# audit trail in their terminal) and then grab the exit code from the
# companion Get-VortexLastExitCode cmdlet.
Invoke-Vortex -Arguments $Arguments
$rc = Get-VortexLastExitCode
exit $rc
