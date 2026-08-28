# =============================================================================
# auto-update.ps1 — VORTEX-OS engine self-updater
# =============================================================================
# Checks if a newer .NET engine is available on
# `Cloudmeru/vortex-os-dotnet/releases/latest` and installs it if so.
# Idempotent and rate-limited (defaults to once per 6 hours per VORTEX_HOME).
#
# Usage:
#   pwsh -NoProfile -File auto-update.ps1                # check + install if newer
#   pwsh -NoProfile -File auto-update.ps1 -Force        # ignore rate limit
#   pwsh -NoProfile -File auto-update.ps1 -DryRun       # print, don't download
#   pwsh -NoProfile -File auto-update.ps1 -IntervalHours 12
#
# Opt-out:
#   $env:VORTEX_NO_AUTO_UPDATE = '1'   # never auto-update (still check, print only)
#
# How it works:
#   1. Read $VORTEX_HOME\state\auto-update-check.json (or $env:APPDATA\Vortex-OS\...).
#   2. If last_check was within IntervalHours, skip the GitHub call.
#   3. Otherwise, GET https://api.github.com/repos/Cloudmeru/vortex-os-dotnet/releases/latest
#      (1 call, 60 req/hr unauthenticated, fine for one check per IntervalHours).
#   4. If the tag is newer than the installed engine version, call install.ps1
#      to download + install it (install.ps1 is idempotent and always pulls latest).
#   5. Write back the new last_check timestamp + the seen version.
# =============================================================================
[CmdletBinding()]
param(
    # Bypass the rate-limit cache and always re-check.
    [switch] $Force,

    # Don't actually install; just print what would happen.
    [switch] $DryRun,

    # How many hours between checks (default 6). The check still
    # happens on every call; we just skip the GitHub call if the
    # last check was within this window.
    [int] $IntervalHours = 6
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
if (-not $here) { $here = (Get-Location).Path }

# --- 1. PS7+ guard -----------------------------------------------------------
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    throw "VORTEX-OS requires PowerShell 7+ (Core). Detected: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))."
}

# --- 2. Resolve VORTEX_HOME + check opt-out ---------------------------------
if ($env:VORTEX_NO_AUTO_UPDATE -eq '1') {
    Write-Host "[vortex-os] VORTEX_NO_AUTO_UPDATE=1 -> auto-update disabled." -ForegroundColor DarkGray
    return
}

$vortexHome = $env:VORTEX_HOME
if (-not $vortexHome) {
    $appData = [Environment]::GetFolderPath('ApplicationData')
    $vortexHome = Join-Path $appData 'Vortex-OS'
}
if (-not (Test-Path $vortexHome)) {
    New-Item -ItemType Directory -Path $vortexHome -Force | Out-Null
}

$stateDir = Join-Path $vortexHome 'state'
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
$cacheFile = Join-Path $stateDir 'auto-update-check.json'

# --- 3. Find currently installed engine version -----------------------------
# The engine is at $HOME\Documents\PowerShell\Modules\Vortex\<ver>\Vortex.psd1
# (or wherever VORTEX_MODULE_PATH / first PSModulePath entry points).
function Find-InstalledEngineVersion {
    $candidates = @()
    if ($env:VORTEX_MODULE_PATH) { $candidates += $env:VORTEX_MODULE_PATH }
    if ($env:PSModulePath) {
        foreach ($entry in ($env:PSModulePath -split [IO.Path]::PathSeparator)) {
            $e = $entry.Trim()
            if (-not $e) { continue }
            if ($e -like '*WindowsPowerShell*' -or $e -like '*Program Files*') { continue }
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
            if ([IO.File]::Exists($psd1)) { return $v.Name }
        }
    }
    return $null
}

$installedVer = Find-InstalledEngineVersion
Write-Host "[vortex-os] Installed engine: $(if ($installedVer) { $installedVer } else { '(none)' })" -ForegroundColor Gray

# --- 4. Rate-limit: skip the GitHub call if we checked recently --------------
$cache = $null
if (Test-Path $cacheFile) {
    try { $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json } catch { }
}

if (-not $Force -and $cache -and $cache.last_check) {
    $lastCheck = [datetime]::Parse($cache.last_check, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    $age = (Get-Date) - $lastCheck
    if ($age.TotalHours -lt $IntervalHours) {
        $mins = [int]$age.TotalMinutes
        Write-Host "[vortex-os] Last check was $mins min ago (< $IntervalHours h). Skipping GitHub call." -ForegroundColor DarkGray
        Write-Host "[vortex-os] Pass -Force to re-check, or set IntervalHours=0 to always check." -ForegroundColor DarkGray
        return
    }
}

# --- 5. Query GitHub for the latest release ----------------------------------
Write-Host "[vortex-os] Checking GitHub for the latest release..." -ForegroundColor Cyan
try {
    $apiUrl = 'https://api.github.com/repos/Cloudmeru/vortex-os-dotnet/releases/latest'
    $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ 'Accept' = 'application/vnd.github+json' }
} catch {
    Write-Host "[vortex-os] GitHub check failed: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "[vortex-os] Will retry on next skill invocation. (Network blip is non-fatal.)" -ForegroundColor Yellow
    return
}

$remoteTag = $release.tag_name   # e.g., "v0.1.8"
$remoteVer = $remoteTag.TrimStart('v')
Write-Host "[vortex-os] Latest on GitHub:  $remoteTag" -ForegroundColor Cyan

# --- 6. Compare versions -----------------------------------------------------
$needsUpdate = $false
if (-not $installedVer) {
    Write-Host "[vortex-os] No engine installed yet; install.ps1 will handle that on first skill run." -ForegroundColor Yellow
    $needsUpdate = $false
} else {
    $installedNorm = $installedVer.TrimStart('v')
    try {
        $installedV = [version]$installedNorm
        $remoteV    = [version]$remoteVer
        if ($remoteV -gt $installedV) {
            $needsUpdate = $true
            Write-Host "[vortex-os] Newer version available: $remoteTag (installed $installedVer)" -ForegroundColor Green
        } else {
            Write-Host "[vortex-os] Up to date ($installedVer >= $remoteTag)." -ForegroundColor Green
        }
    } catch {
        # Unparseable version string -- fall back to string compare
        if ($remoteVer -ne $installedNorm) {
            $needsUpdate = $true
            Write-Host "[vortex-os] Version compare unclear; treating as needing update." -ForegroundColor Yellow
        }
    }
}

# --- 7. Install if needed ----------------------------------------------------
if ($needsUpdate -and -not $DryRun) {
    $installer = Join-Path $here 'install.ps1'
    if (Test-Path $installer) {
        Write-Host "[vortex-os] Running install.ps1 to pull $remoteTag..." -ForegroundColor Cyan
        & pwsh -NoProfile -File $installer
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[vortex-os] install.ps1 exited with $LASTEXITCODE; skipping update." -ForegroundColor Red
        } else {
            Write-Host "[vortex-os] Engine updated to $remoteTag. Restart skill.ps1 to use the new version." -ForegroundColor Green
        }
    } else {
        Write-Host "[vortex-os] install.ps1 not found in skill folder; please run it manually." -ForegroundColor Yellow
    }
} elseif ($needsUpdate -and $DryRun) {
    Write-Host "[vortex-os] (dry-run) would call install.ps1 to install $remoteTag" -ForegroundColor Cyan
}

# --- 8. Write back the cache -------------------------------------------------
# v0.2.3 (G8): also persist the asset URLs so install.ps1 can short-circuit
# even the asset lookup (not just the version check) within the rate-limit
# window. The full asset list is small (~4 entries) and stable per release.
$cacheAssets = @()
if ($release -and $release.assets) {
    foreach ($a in $release.assets) {
        $cacheAssets += [PSCustomObject]@{
            name = $a.name
            browser_download_url = $a.browser_download_url
        }
    }
}
$cacheObj = @{
    last_check    = (Get-Date).ToString('o')
    remote_tag    = $remoteTag
    installed_ver = $installedVer
    updated       = ($needsUpdate -and -not $DryRun)
    assets        = $cacheAssets
}
$cacheObj | ConvertTo-Json | Set-Content -Path $cacheFile -Encoding UTF8
