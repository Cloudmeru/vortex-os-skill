# =============================================================================
# uninstall.ps1 — VORTEX-OS engine + skill uninstaller
# =============================================================================
# Removes the VORTEX-OS engine and (optionally) the user's runtime state.
# Idempotent. Dry-run by default.
#
# Scopes:
#   -Engine        delete $HOME\Documents\PowerShell\Modules\Vortex\  (the engine)
#                   KEEPS $env:VORTEX_HOME (deliverables, audit log, swarms survive)
#   -State         delete $env:VORTEX_HOME\  (deliverables, audit log, etc.)
#                   USE WITH CAUTION — this destroys all user data
#   -All           = -Engine -State (full clean uninstall)
#   (default)      = dry-run; prints what would happen, doesn't delete
#
# System deps (sqlite3, ffmpeg) installed via `winget` are NOT touched.
# Use `winget uninstall SQLite.SQLite` etc. manually if you want them gone too.
#
# Usage:
#   pwsh -NoProfile -File uninstall.ps1                      # dry-run (default)
#   pwsh -NoProfile -File uninstall.ps1 -Engine              # remove engine, keep state
#   pwsh -NoProfile -File uninstall.ps1 -State -Confirm      # remove state (with -Confirm)
#   pwsh -NoProfile -File uninstall.ps1 -All -Confirm       # remove everything
#   pwsh -NoProfile -File uninstall.ps1 -VortexHome 'D:\data'  # custom state path
# =============================================================================
[CmdletBinding()]
param(
    # Remove the engine (the Vortex\<version>\ folder under
    # $HOME\Documents\PowerShell\Modules\).
    [switch] $Engine,

    # Remove the user's runtime state (deliverables, audit log, swarms,
    # HITL pending). DESTROYS ALL USER DATA. Requires -Confirm.
    [switch] $State,

    # Convenience: both -Engine and -State.
    [switch] $All,

    # Override $env:VORTEX_HOME. Default: $env:VORTEX_HOME if set,
    # otherwise $env:APPDATA\Vortex-OS.
    [string] $VortexHome = $env:VORTEX_HOME,

    # Suppress the y/N confirmation prompt. Use with caution.
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
if (-not $here) { $here = (Get-Location).Path }

# --- 1. PS7+ guard -----------------------------------------------------------
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    throw "VORTEX-OS requires PowerShell 7+ (Core). Detected: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))."
}

# --- 2. Resolve paths --------------------------------------------------------
$engineBase = Join-Path $HOME 'Documents\PowerShell\Modules\Vortex'
if (-not $VortexHome) {
    $appData = [Environment]::GetFolderPath('ApplicationData')
    if ($appData) { $VortexHome = Join-Path $appData 'Vortex-OS' }
}

# -All is a convenience flag
if ($All) { $Engine = $true; $State = $true }

# Dry-run if no action flag was passed
$isDryRun = -not ($Engine -or $State)
if ($isDryRun) {
    Write-Host "[vortex-os] DRY RUN — no files will be removed. Pass -Engine, -State, or -All to actually delete." -ForegroundColor Cyan
}

# --- 3. Discover what would be removed ---------------------------------------
Write-Host ""
Write-Host "[vortex-os] Summary of what would be removed:" -ForegroundColor Cyan
Write-Host ""

$engineVersions = @()
if (Test-Path $engineBase) {
    $engineVersions = Get-ChildItem -LiteralPath $engineBase -Directory -ErrorAction SilentlyContinue
    if ($engineVersions.Count -gt 0) {
        Write-Host "  Engine ($($engineVersions.Count) version$(if ($engineVersions.Count -eq 1) {''} else {'s'})):" -ForegroundColor Yellow
        foreach ($v in $engineVersions) {
            $size = (Get-ChildItem -LiteralPath $v.FullName -Recurse -File -ErrorAction SilentlyContinue |
                      Measure-Object -Property Length -Sum).Sum
            $sizeMB = [math]::Round($size / 1MB, 2)
            Write-Host "    $($v.Name) ($sizeMB MB)  --  $($v.FullName)"
        }
    } else {
        Write-Host "  Engine: none installed at $engineBase" -ForegroundColor Gray
    }
} else {
    Write-Host "  Engine: not installed at $engineBase" -ForegroundColor Gray
}

Write-Host ""
if ($VortexHome -and (Test-Path $VortexHome)) {
    $stateFiles = Get-ChildItem -LiteralPath $VortexHome -Recurse -File -ErrorAction SilentlyContinue
    $stateSize = ($stateFiles | Measure-Object -Property Length -Sum).Sum
    $stateSizeMB = [math]::Round($stateSize / 1MB, 2)
    $projectCount = (Get-ChildItem -LiteralPath (Join-Path $VortexHome 'deliverables') -Directory -ErrorAction SilentlyContinue).Count
    Write-Host "  State (in $VortexHome):" -ForegroundColor Yellow
    Write-Host "    $stateSizeMB MB across $($stateFiles.Count) files"
    Write-Host "    $projectCount project$(if ($projectCount -eq 1) {''} else {'s'}) in deliverables/"
} else {
    Write-Host "  State: not present at $VortexHome" -ForegroundColor Gray
}

# --- 4. Confirmation ---------------------------------------------------------
if ($isDryRun) {
    Write-Host ""
    Write-Host "[vortex-os] To actually remove:" -ForegroundColor Cyan
    if ($Engine) { Write-Host "  pwsh -NoProfile -File uninstall.ps1 -Engine -Force" }
    if ($State)  { Write-Host "  pwsh -NoProfile -File uninstall.ps1 -State -Force" }
    if ($All)    { Write-Host "  pwsh -NoProfile -File uninstall.ps1 -All -Force" }
    return
}

# Real deletion path
if (-not ($Engine -or $State)) {
    Write-Host "[vortex-os] No action flag passed. Use -Engine, -State, or -All." -ForegroundColor Yellow
    return
}

# -State destroys user data — always confirm unless -Force
if ($State -and -not $Force) {
    Write-Host ""
    Write-Host "[vortex-os] WARNING: -State will permanently delete all deliverables, audit logs, and HITL state." -ForegroundColor Red
    Write-Host "  Target: $VortexHome" -ForegroundColor Red
    $answer = Read-Host "Type 'delete my data' to confirm"
    if ($answer -ne 'delete my data') {
        Write-Host "[vortex-os] Aborted." -ForegroundColor Yellow
        return
    }
}

# -Engine is generally safe (no user data) but confirm anyway unless -Force
if ($Engine -and -not $Force) {
    Write-Host ""
    Write-Host "[vortex-os] -Engine will remove $($engineVersions.Count) version$(if ($engineVersions.Count -eq 1) {''} else {'s'}) of the engine." -ForegroundColor Yellow
    $answer = Read-Host "Continue? (y/N)"
    if ($answer -ne 'y') {
        Write-Host "[vortex-os] Aborted." -ForegroundColor Yellow
        return
    }
}

# --- 5. Delete ----------------------------------------------------------------
$removed = 0
$errors = 0

if ($Engine -and $engineVersions.Count -gt 0) {
    foreach ($v in $engineVersions) {
        try {
            # Use [IO.Directory]::Delete (handles long paths, doesn't require
            # ReadOnly attribute clearing). Force=false to fail safely.
            [IO.Directory]::Delete($v.FullName, $true)
            Write-Host "[vortex-os]   removed engine $($v.Name)" -ForegroundColor Green
            $removed++
        } catch {
            Write-Host "[vortex-os]   failed to remove engine $($v.Name): $($_.Exception.Message)" -ForegroundColor Red
            $errors++
        }
    }
    # Try to remove the empty parent too (it might have a leftover Vortex\
    # folder with no versions). Only if it ends up empty.
    if (Test-Path $engineBase) {
        $remaining = @(Get-ChildItem -LiteralPath $engineBase -Force -ErrorAction SilentlyContinue)
        if ($remaining.Count -eq 0) {
            try {
                [IO.Directory]::Delete($engineBase, $false)
                Write-Host "[vortex-os]   removed empty parent $engineBase" -ForegroundColor Green
            } catch {
                # Non-fatal: another tool may have raced us. Just leave it.
            }
        }
    }
}

if ($State -and $VortexHome -and (Test-Path $VortexHome)) {
    try {
        [IO.Directory]::Delete($VortexHome, $true)
        Write-Host "[vortex-os]   removed state at $VortexHome" -ForegroundColor Green
        $removed++
    } catch {
        Write-Host "[vortex-os]   failed to remove state: $($_.Exception.Message)" -ForegroundColor Red
        $errors++
    }
}

Write-Host ""
Write-Host "[vortex-os] Done. Removed $removed item$(if ($removed -eq 1) {''} else {'s'})." -ForegroundColor Cyan
if ($errors -gt 0) { Write-Host "[vortex-os]   $errors error$(if ($errors -eq 1) {''} else {'s'}) — see above." -ForegroundColor Red }

if ($State) {
    Write-Host ""
    Write-Host "[vortex-os] Reminder: if you also want to remove the system deps (sqlite3, ffmpeg), run:" -ForegroundColor Yellow
    Write-Host "  winget uninstall SQLite.SQLite" -ForegroundColor Yellow
    Write-Host "  winget uninstall Gyan.FFmpeg" -ForegroundColor Yellow
}
