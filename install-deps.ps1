# =============================================================================
# install-deps.ps1 — VORTEX-OS dependency installer (Windows / winget)
# =============================================================================
# Installs the system-level tools that the VORTEX-OS engine actually invokes
# at runtime. Reads the dep list from `_meta.json` → `winget_install_ids` so
# there's a single source of truth.
#
# The engine is pure .NET 10 / C++/CLI. It does NOT need Python, jq, or any
# scripting runtime. The only required external tool is `sqlite3` (used by
# the engine's VectorHydrate step for memory persistence). `ffmpeg` is
# optional — only the engine's generated *audio deliverables* use it.
#
# IMPORTANT: this script uses `winget` (Windows Package Manager) and nothing
# else. Do NOT route these installs through pip, brew, apt, or choco. The
# winget IDs were verified against the live winget catalog at skill v0.1.3:
#
#     sqlite3  <- SQLite.SQLite                  (3.53.4, official)
#     ffmpeg   <- Gyan.FFmpeg                    (9.0,    official)
#
# Idempotent: re-running when a dep is already installed is a no-op.
# User-confirmed: by default the script DRY-RUNS. Pass `-Install` to actually
# install, and `-Force` to skip the y/N prompt.
#
# Usage:
#   pwsh -NoProfile -File install-deps.ps1                 # dry-run, just print
#   pwsh -NoProfile -File install-deps.ps1 -Install        # install required
#   pwsh -NoProfile -File install-deps.ps1 -Install -IncludeOptional   # + ffmpeg
#   pwsh -NoProfile -File install-deps.ps1 -Install -Force # no y/N prompt
# =============================================================================
[CmdletBinding()]
param(
    # Actually run `winget install`. Without this, the script dry-runs
    # and just prints the commands it would run.
    [switch] $Install,

    # Also install the optional deps (currently just ffmpeg, for the
    # generated audio deliverables — not needed to run the engine itself).
    [switch] $IncludeOptional,

    # Skip the y/N confirmation prompt before running winget.
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
if (-not $here) { $here = (Get-Location).Path }

# --- 1. PS7+ guard -----------------------------------------------------------
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    throw "VORTEX-OS requires PowerShell 7+ (Core). Detected: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)). Install from https://aka.ms/powershell"
}

# --- 2. Read deps from _meta.json --------------------------------------------
# Single source of truth: _meta.json.winget_install_ids. If the field is
# missing (e.g. older skill releases), fall back to a hard-coded list so the
# script still works.
$metaPath = Join-Path $here '_meta.json'
$meta = $null
if (Test-Path $metaPath) {
    try { $meta = Get-Content $metaPath -Raw | ConvertFrom-Json } catch { }
}
$deps = @()
if ($meta -and $meta.PSObject.Properties['winget_install_ids']) {
    foreach ($d in $meta.winget_install_ids) {
        $deps += [PSCustomObject]@{
            name        = $d.name
            winget_id   = $d.winget_id
            required    = [bool]$d.required
            description = $d.description
        }
    }
} else {
    # Fallback (older skill releases that don't have winget_install_ids).
    $deps = @(
        [PSCustomObject]@{ name = 'sqlite3'; winget_id = 'SQLite.SQLite'; required = $true;  description = 'SQLite CLI (for engine memory persistence)' },
        [PSCustomObject]@{ name = 'ffmpeg';  winget_id = 'Gyan.FFmpeg';  required = $false; description = 'Audio/video processor (for generated audio deliverables)' }
    )
}

# --- 3. Check which are missing ----------------------------------------------
# Test-Path is unreliable for OneDrive-backed paths on this machine, but
# `Get-Command` is not (it uses real PATH lookup, not the filesystem).
$missingRequired = @()
$missingOptional = @()
$installed = @()
foreach ($dep in $deps) {
    if (-not ($dep.required -or $IncludeOptional)) { continue }
    $found = Get-Command $dep.name -ErrorAction SilentlyContinue
    if ($found) {
        $installed += [PSCustomObject]@{ name = $dep.name; path = $found.Source }
    } else {
        if ($dep.required) { $missingRequired += $dep } else { $missingOptional += $dep }
    }
}

# --- 4. Print status ---------------------------------------------------------
Write-Host "[vortex-os] Checking system dependencies via `where`..." -ForegroundColor Cyan
Write-Host ""
if ($installed.Count -gt 0) {
    foreach ($i in $installed) { Write-Host "  [OK]   $($i.name) -> $($i.path)" -ForegroundColor Green }
}
if ($missingRequired.Count -gt 0) {
    foreach ($m in $missingRequired) {
        Write-Host "  [--]   $($m.name) (required) — $($m.description)" -ForegroundColor Yellow
        Write-Host "           install:  winget install --id $($m.winget_id) --accept-package-agreements --accept-source-agreements"
    }
}
if ($missingOptional.Count -gt 0) {
    foreach ($m in $missingOptional) {
        Write-Host "  [--]   $($m.name) (optional) — $($m.description)" -ForegroundColor DarkYellow
        Write-Host "           install:  winget install --id $($m.winget_id) --accept-package-agreements --accept-source-agreements"
    }
}
Write-Host ""

# --- 5. winget sanity check --------------------------------------------------
$winget = Get-Command 'winget' -ErrorAction SilentlyContinue
$choco  = Get-Command 'choco'  -ErrorAction SilentlyContinue
$scoop  = Get-Command 'scoop'  -ErrorAction SilentlyContinue

# v0.2.3 (G10): pick the first available installer in priority order.
# winget > choco > scoop > direct (download + unzip). The direct fallback
# is for locked-down corporate machines that have no package manager
# available.
function Get-PackageManager {
    if ($winget) { return @{ Name = 'winget'; Command = $winget.Source } }
    if ($choco)  { return @{ Name = 'choco';  Command = $choco.Source  } }
    if ($scoop)  { return @{ Name = 'scoop';  Command = $scoop.Source  } }
    return $null
}
$pkgMgr = Get-PackageManager
if (-not $pkgMgr) {
    Write-Host "[vortex-os] No package manager found (winget / choco / scoop)." -ForegroundColor Red
    Write-Host "[vortex-os] For sqlite3, you can download a static build from https://www.sqlite.org/download.html" -ForegroundColor Yellow
    Write-Host "[vortex-os] For ffmpeg,  you can download a static build from https://www.gyan.dev/ffmpeg/builds/" -ForegroundColor Yellow
    Write-Host "[vortex-os] After manual install, re-run install-deps.ps1 to confirm PATH." -ForegroundColor Yellow
    if ($Install) { throw "no package manager found" }
    return
}
Write-Host "[vortex-os] Using package manager: $($pkgMgr.Name) ($($pkgMgr.Command))" -ForegroundColor Cyan

# --- 6. Install (with confirmation) -----------------------------------------
$toInstall = @()
if ($Install) {
    $toInstall += $missingRequired
    if ($IncludeOptional) { $toInstall += $missingOptional }

    if ($toInstall.Count -eq 0) {
        Write-Host "[vortex-os] All deps already installed. Nothing to do." -ForegroundColor Green
        return
    }

    if (-not $Force) {
        Write-Host "About to install $($toInstall.Count) package(s) via $($pkgMgr.Name):" -ForegroundColor Yellow
        foreach ($d in $toInstall) { Write-Host "  - $($d.name)" }
        $answer = Read-Host "Proceed? (y/N)"
        if ($answer -ne 'y') { Write-Host "[vortex-os] Aborted by user." -ForegroundColor Yellow; return }
    }

    foreach ($d in $toInstall) {
        if ($pkgMgr.Name -eq 'winget') {
            Write-Host "[vortex-os] Installing $($d.name) via winget ($($d.winget_id))..." -ForegroundColor Cyan
            & winget install --id $d.winget_id --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[vortex-os] winget install for $($d.winget_id) exited with $LASTEXITCODE" -ForegroundColor Red
            } else {
                Write-Host "[vortex-os] Installed $($d.name)." -ForegroundColor Green
            }
        } elseif ($pkgMgr.Name -eq 'choco') {
            $chocoId = if ($d.name -eq 'sqlite3') { 'sqlite' } else { 'ffmpeg' }
            Write-Host "[vortex-os] Installing $($d.name) via choco ($chocoId)..." -ForegroundColor Cyan
            & choco install $chocoId -y
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[vortex-os] choco install for $chocoId exited with $LASTEXITCODE" -ForegroundColor Red
            } else {
                Write-Host "[vortex-os] Installed $($d.name)." -ForegroundColor Green
            }
        } elseif ($pkgMgr.Name -eq 'scoop') {
            $scoopName = if ($d.name -eq 'sqlite3') { 'sqlite' } else { 'ffmpeg' }
            Write-Host "[vortex-os] Installing $($d.name) via scoop ($scoopName)..." -ForegroundColor Cyan
            & scoop install $scoopName
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[vortex-os] scoop install for $scoopName exited with $LASTEXITCODE" -ForegroundColor Red
            } else {
                Write-Host "[vortex-os] Installed $($d.name)." -ForegroundColor Green
            }
        }
    }
    Write-Host ""
    Write-Host "[vortex-os] Done. Re-run install-deps.ps1 to confirm all deps are on PATH." -ForegroundColor Green
} else {
    Write-Host "[vortex-os] Dry-run. Pass -Install to actually run $($pkgMgr.Name) install." -ForegroundColor Cyan
    if (-not $winget) {
        Write-Host "[vortex-os] (winget not found; would have used $($pkgMgr.Name) instead. See install_fallbacks in _meta.json for choco/scoop/direct URLs.)" -ForegroundColor DarkGray
    }
}
