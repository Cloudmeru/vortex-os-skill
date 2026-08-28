# =============================================================================
# install-powershell7.ps1 — Bootstrap PowerShell 7+ from Windows PowerShell 5.1
# =============================================================================
# VORTEX-OS requires PowerShell 7+ (Core) because Vortex.dll targets .NET 10,
# which the built-in Windows PowerShell 5.1 cannot load. This script lets a
# fresh Windows install (which ships with only PS 5.1) bootstrap itself
# without the operator having to know about winget / msi / pwsh first.
#
# Usage from a PowerShell 5.1 prompt (cmd or Start menu "Windows PowerShell"):
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\install-powershell7.ps1
#
# What it does:
#   1. Detects the latest stable PowerShell 7 release from GitHub.
#   2. Downloads the win-x64 MSI to a temp folder.
#   3. Runs it with /quiet /norestart (no admin needed for per-user install).
#   4. Verifies `pwsh` is on PATH afterwards.
#
# After this script finishes, use `pwsh` (not `powershell`) for everything else.
# On Windows 10 1809+ and Server 2019+, MSI is delivered as a per-user install
# to %LOCALAPPDATA%\Microsoft\PowerShell\7 — no UAC prompt, no reboot.
#
# Network:    HTTPS to api.github.com + github.com (unauthenticated, 60 req/hr).
# Elevation:  NOT required (MSI is per-user when run as the current user).
# Idempotent: re-running detects an existing pwsh 7 install and exits.
# =============================================================================
[CmdletBinding()]
param(
    # Pin a specific PS7 version (default: latest stable). Examples:
    #   -Version 7.4.6
    #   -Version latest
    [string] $Version = 'latest',

    # Architecture: amd64 (default), arm64
    [ValidateSet('amd64', 'arm64', 'x86')]
    [string] $Arch = 'amd64'
)

$ErrorActionPreference = 'Stop'

# ---- 1. Already installed? --------------------------------------------------
$existing = Get-Command pwsh -ErrorAction SilentlyContinue
if ($existing) {
    $pwshVer = & pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>&1 | Select-Object -Last 1
    Write-Host "[vortex-os] PowerShell 7 already installed: pwsh -> $($existing.Source) (v$pwshVer)" -ForegroundColor Green
    Write-Host "[vortex-os] Nothing to do. Use 'pwsh' instead of 'powershell' for VORTEX-OS." -ForegroundColor Green
    return
}

# ---- 2. Architecture detection ---------------------------------------------
if ($Arch -eq 'amd64' -and [Environment]::Is64BitOperatingSystem -eq $false) {
    $Arch = 'x86'
}
Write-Host "[vortex-os] Detected OS arch: $([Environment]::OSVersion.Platform) ($Arch)" -ForegroundColor Cyan

# ---- 3. Resolve the release tag --------------------------------------------
$apiBase = 'https://api.github.com/repos/PowerShell/PowerShell/releases'
if ($Version -ieq 'latest' -or -not $Version) {
    Write-Host "[vortex-os] Resolving latest stable PowerShell 7 release ..." -ForegroundColor Cyan
    $release = Invoke-RestMethod -Uri "$apiBase/latest" -Headers @{ 'Accept' = 'application/vnd.github+json' }
    # The "latest" endpoint returns the highest release INCLUDING pre-releases.
    # Filter to stable only (no "-preview", "-rc", "-alpha" in tag_name).
    $stable = $release | Where-Object { $_.tag_name -notmatch '-(preview|rc|alpha|beta)\d*$' } | Select-Object -First 1
    if ($stable) { $release = $stable }
    $tag = $release.tag_name
} else {
    if ($Version -notlike 'v*') { $Version = "v$Version" }
    Write-Host "[vortex-os] Resolving PowerShell 7 release $Version ..." -ForegroundColor Cyan
    $release = Invoke-RestMethod -Uri "$apiBase/tags/$Version" -Headers @{ 'Accept' = 'application/vnd.github+json' }
    $tag = $release.tag_name
}
Write-Host "[vortex-os] Target release: $tag" -ForegroundColor Cyan

# ---- 4. Find the win-<arch> MSI asset --------------------------------------
$msiAsset = $release.assets | Where-Object {
    $_.name -like "PowerShell-*-win-$Arch.msi"
} | Select-Object -First 1
if (-not $msiAsset) {
    throw "No win-$Arch MSI found in PowerShell $tag release. Available: $($release.assets.name -join ', ')"
}
$msiUrl = $msiAsset.browser_download_url
Write-Host "[vortex-os] MSI: $($msiAsset.name)" -ForegroundColor DarkGray

# ---- 5. Download to a temp folder ------------------------------------------
$tmp = Join-Path $env:TEMP "vortex-os-ps7-install"
if (-not (Test-Path $tmp)) { New-Item -ItemType Directory -Path $tmp -Force | Out-Null }
$msiPath = Join-Path $tmp $msiAsset.name
Write-Host "[vortex-os] Downloading to $msiPath ..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing -ErrorAction Stop
} catch {
    throw "Failed to download $msiUrl : $($_.Exception.Message)"
}
if (-not (Test-Path $msiPath)) {
    throw "Download did not produce a file at $msiPath"
}
$size = (Get-Item $msiPath).Length
Write-Host "[vortex-os] Downloaded $size bytes" -ForegroundColor Green

# ---- 6. Run the MSI silently ------------------------------------------------
# Per-user install (no admin needed) when running as the current user.
# MSI flags:
#   /quiet       -- no UI
#   /norestart   -- don't reboot (operator can choose when)
#   ADD_EXPLORER_CONTEXT_MENUOPENPOWERSHELL=1  -- right-click "Open PowerShell 7 here"
#   ENABLE_PSREMOTING=0  -- opt-in only, not on by default
Write-Host "[vortex-os] Installing PowerShell 7 (per-user, silent) ..." -ForegroundColor Cyan
$msiArgs = @(
    '/i', "`"$msiPath`""
    '/quiet'
    '/norestart'
    'ADD_EXPLORER_CONTEXT_MENUOPENPOWERSHELL=1'
    'ENABLE_PSREMOTING=0'
)
$proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    throw "msiexec exited with code $($proc.ExitCode). See Windows Event Log for details."
}

# ---- 7. Verify install -----------------------------------------------------
$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $pwsh) {
    # On Windows 10 1809+, per-user install lands at
    # %LOCALAPPDATA%\Microsoft\PowerShell\7\pwsh.exe which is added to
    # the user's PATH for NEW sessions. The current PS5 session won't
    # see it until it's restarted.
    Write-Host ""
    Write-Host "[vortex-os] PowerShell 7 installed but `pwsh` is not on PATH in this session." -ForegroundColor Yellow
    Write-Host "[vortex-os] Open a NEW PowerShell window (or run: `$env:PATH += `";$env:LOCALAPPDATA\Microsoft\PowerShell\7`") and try again." -ForegroundColor Yellow
    Write-Host "[vortex-os] Then verify: pwsh -NoProfile -Command '$PSVersionTable.PSVersion'" -ForegroundColor Yellow
    return
}

$ver = & pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>&1 | Select-Object -Last 1
Write-Host ""
Write-Host "[vortex-os] PowerShell $ver installed at: $($pwsh.Source)" -ForegroundColor Green
Write-Host ""
Write-Host "Test it:" -ForegroundColor Cyan
Write-Host "  pwsh -NoProfile -Command 'Import-Module Vortex; Get-VortexVersion'"
Write-Host "  pwsh -NoProfile -File .\skill.ps1 --version"
