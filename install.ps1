# =============================================================================
# install.ps1 — VORTEX-OS engine installer
# =============================================================================
# Downloads the latest VORTEX-OS engine (Vortex.dll + Vortex.psm1 + Vortex.psd1
# + ijwhost.dll) from the public GitHub release of Cloudmeru/vortex-os-dotnet
# and installs it to a PowerShell 7+ *user-scope* module folder:
#
#     $HOME\Documents\PowerShell\Modules\Vortex\<version>\
#
# Then any of these Just Work:
#
#     pwsh -NoProfile -File .\skill.ps1   --agents-discover
#     pwsh -NoProfile -File .\verify.ps1
#     Import-Module Vortex; Get-VortexAgent
#
# Idempotent: re-running when the same version is already installed is a no-op.
# Network:    uses only the unauthenticated GitHub REST API (60 req/hr/IP,
#             fine for one install per machine).
# Elevation:  NO admin / sudo / system-scope changes. The user-scope module
#             folder is owned by the current user.
# Re-pin:     set $env:VORTEX_VERSION = 'v0.1.0' (or 'latest') before running.
# Custom dir: set $env:VORTEX_MODULE_PATH = 'D:\tools\PowerShell\Modules' to
#             install somewhere other than $HOME\Documents\PowerShell\Modules.
#
# Usage:
#   pwsh -NoProfile -File install.ps1
#   pwsh -NoProfile -File install.ps1 -Version v0.1.0
#   pwsh -NoProfile -File install.ps1 -ModulePath 'D:\psmodules'
# =============================================================================
[CmdletBinding()]
param(
    [string] $Version = $env:VORTEX_VERSION,
    [string] $ModulePath = $env:VORTEX_MODULE_PATH
)

$ErrorActionPreference = 'Stop'

# ---- 1. PS7+ guard ----------------------------------------------------------
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    throw "VORTEX-OS requires PowerShell 7+ (Core). Detected: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)). Install from https://aka.ms/powershell"
}

# ---- 2. Config --------------------------------------------------------------
$RepoOwner = 'Cloudmeru'
$RepoName  = 'vortex-os-dotnet'
$Engine    = 'Vortex'        # PowerShell module name (matches Vortex.psd1)
$AssetNames = @('Vortex.dll', 'Vortex.psm1', 'Vortex.psd1', 'ijwhost.dll')

if (-not $ModulePath) {
    # Pick the first PSModulePath directory we can actually write to. We
    # probe by creating a sentinel sub-folder; if the path is a OneDrive
    # Files-On-Demand "ghost" (the folder shows in PSModulePath but
    # Test-Path / New-Item fail), we fall back to the next entry, and
    # finally to the canonical non-OneDrive user-scope path.
    $candidates = @()
    $psModuleEntries = $env:PSModulePath -split [IO.Path]::PathSeparator | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    foreach ($entry in $psModuleEntries) {
        # Only consider per-user scopes; skip system-wide paths to avoid
        # accidentally requiring elevation later.
        if ($entry -like '*WindowsPowerShell*' -or $entry -like '*Program Files*' -or $entry -like '*Program Files (x86)*') { continue }
        $candidates += $entry
    }
    # Always also offer the canonical non-OneDrive user-scope path as a
    # last-resort fallback (handles machines where PSModulePath only lists
    # the OneDrive redirect and that redirect is broken).
    $canonical = Join-Path $HOME 'Documents\PowerShell\Modules'
    if ($candidates -notcontains $canonical) { $candidates += $canonical }

    $ModulePath = $null
    foreach ($cand in $candidates) {
        $sentinel = Join-Path $cand '_vortex_probe'
        try {
            if (-not [IO.Directory]::Exists($cand)) { [IO.Directory]::CreateDirectory($cand) | Out-Null }
            if (-not [IO.Directory]::Exists($sentinel)) { [IO.Directory]::CreateDirectory($sentinel) | Out-Null }
            [IO.Directory]::Delete($sentinel)
            $ModulePath = $cand
            break
        } catch {
            Write-Verbose "PSModulePath entry '$cand' is not writable: $($_.Exception.Message)"
        }
    }
    if (-not $ModulePath) {
        throw "None of the PSModulePath entries are writable for the current user. Set `$env:VORTEX_MODULE_PATH to a path you own, then re-run."
    }
}

# ---- 3. Pick the release ----------------------------------------------------
$apiBase = "https://api.github.com/repos/$RepoOwner/$RepoName/releases"
if (-not $Version -or $Version -ieq 'latest') {
    Write-Host "[vortex-os] Resolving latest release of $RepoOwner/$RepoName ..." -ForegroundColor Cyan
    $release = Invoke-RestMethod -Uri "$apiBase/latest" -Headers @{ 'Accept' = 'application/vnd.github+json' }
    $Version = $release.tag_name
} else {
    # Strip a leading 'v' so the user can pass either '0.1.0' or 'v0.1.0'
    if ($Version -like 'v*') { $Version = $Version.Substring(1) }
    Write-Host "[vortex-os] Resolving release tag v$Version of $RepoOwner/$RepoName ..." -ForegroundColor Cyan
    $release = Invoke-RestMethod -Uri "$apiBase/tags/v$Version" -Headers @{ 'Accept' = 'application/vnd.github+json' }
}

$versionDir = $Version.TrimStart('v')
$destDir = Join-Path $ModulePath "$Engine\$versionDir"
$destDirAlt = Join-Path $ModulePath "$Engine\$Version"  # tolerate 'v0.1.0' too
Write-Host "[vortex-os] Target: $destDir"

# ---- 4. Idempotency check ---------------------------------------------------
# Use [IO.File]::Exists so OneDrive Files-On-Demand paths are reported
# correctly. A standard Test-Path returns False for files that ARE on disk
# but not yet synced into the local OneDrive cache.
$needsInstall = $true
if ([IO.Directory]::Exists($destDir)) {
    $allPresent = $true
    foreach ($name in $AssetNames) {
        if (-not [IO.File]::Exists((Join-Path $destDir $name))) { $allPresent = $false; break }
    }
    if ($allPresent) {
        Write-Host "[vortex-os] v$Version already installed at $destDir -- nothing to do." -ForegroundColor Green
        Write-Host "[vortex-os] Reinstall:  delete the folder and re-run install.ps1"
        return
    }
}

if (Test-Path $destDirAlt) {
    $destDir = $destDirAlt
}

# ---- 5. Download ------------------------------------------------------------
# Use [IO.Directory] rather than Test-Path/New-Item because OneDrive
# Files-On-Demand paths report as "not found" via Test-Path even when they
# exist locally. [IO.Directory]::Exists + CreateDirectory is idempotent
# and works correctly under both standard and OneDrive-backed profiles.
function Ensure-Dir([string] $Path) {
    if (-not [IO.Directory]::Exists($Path)) {
        [IO.Directory]::CreateDirectory($Path) | Out-Null
    }
}
Ensure-Dir $ModulePath
Ensure-Dir (Split-Path $destDir -Parent)
Ensure-Dir $destDir

# Map asset name -> download URL
$assetMap = @{}
foreach ($a in $release.assets) { $assetMap[$a.name] = $a.browser_download_url }

foreach ($name in $AssetNames) {
    $url = $assetMap[$name]
    if (-not $url) {
        throw "Release v$Version of $RepoOwner/$RepoName is missing the '$name' asset. Available: $($assetMap.Keys -join ', ')"
    }
    $out = Join-Path $destDir $name
    Write-Host "[vortex-os]   $name <- $url" -ForegroundColor DarkGray
    try {
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -ErrorAction Stop
    } catch {
        throw "Failed to download $name from $url : $($_.Exception.Message)"
    }
    if (-not (Test-Path $out)) {
        throw "Download of $name did not produce a file at $out"
    }
}

Write-Host "[vortex-os] Installed $Version to $destDir" -ForegroundColor Green
Write-Host ""
Write-Host "Test it:" -ForegroundColor Cyan
Write-Host "  Import-Module $Engine; Get-VortexAgent"
Write-Host "  pwsh -NoProfile -File .\verify.ps1"
Write-Host "  pwsh -NoProfile -File .\skill.ps1 --agents-discover"
