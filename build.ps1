# =============================================================================
# VORTEX-OS skill — build script
# =============================================================================
# Re-builds the bundled Vortex.dll from source if you want a self-contained
# skill package without depending on the prebuilt binaries.
#
# Most users will NOT need this. The skill ships with a prebuilt Vortex.dll
# that matches the current skill version. You only need to rebuild if:
#   * you cloned this skill repo to fork it / patch the engine
#   * you need to run the skill on an older .NET runtime than 10
#   * you're packaging the skill for a custom deployment
#
# For routine use, prefer the one-shot CLI (skill.ps1 / verify.ps1) — no
# build step needed.
#
# Prerequisites:
#   * Visual Studio 2022 17.10+ BuildTools (or full VS) with the C++/CLI
#     workload installed
#   * .NET 10 SDK on PATH  (ref + host packs under
#     %ProgramFiles%\dotnet\packs\)
#   * PowerShell 7+
#
# Usage:
#   pwsh -NoProfile -File build.ps1
#   pwsh -NoProfile -File build.ps1 download-engine  (replace the bundled
#                                                       Vortex.dll with one
#                                                       installed from
#                                                       PSGallery)
# =============================================================================
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
if (-not $here) { $here = (Get-Location).Path }

function Build-Engine {
    # The skill repo only ships the bundled binary. The C++/CLI source
    # lives in the .NET source repo (https://github.com/Cloudmeru/vortex-os-dotnet).
    # Use that repo's src/build.ps1 and copy the artifacts back.
    $srcUrl = 'https://github.com/Cloudmeru/vortex-os-dotnet/archive/refs/heads/main.zip'
    $zipPath = Join-Path $env:TEMP 'vortex-os-dotnet.zip'
    $extractDir = Join-Path $env:TEMP 'vortex-os-dotnet-extract'

    Write-Host "Downloading VORTEX-OS .NET engine source..."
    if (Test-Path $extractDir) { Remove-Item -Recurse -Force $extractDir }
    if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $srcUrl -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    $srcRoot = Get-ChildItem -Path $extractDir -Directory | Select-Object -First 1
    Write-Host "Extracted to $($srcRoot.FullName)"
    Write-Host "Building..."
    & pwsh -NoProfile -File (Join-Path $srcRoot.FullName 'src/build.ps1')
    if ($LASTEXITCODE -ne 0) { throw "Engine build failed (exit $LASTEXITCODE)" }

    # Copy artifacts back to the skill root
    Copy-Item -Path (Join-Path $srcRoot.FullName 'Vortex.dll') -Destination (Join-Path $here 'Vortex.dll') -Force
    Copy-Item -Path (Join-Path $srcRoot.FullName 'ijwhost.dll') -Destination (Join-Path $here 'ijwhost.dll') -Force
    Write-Host "Engine rebuilt and copied to the skill root."
}

function Install-FromPSGallery {
    # Replace the bundled Vortex.dll with the one installed from PSGallery.
    # Run this once, then delete the bundled Vortex.dll/ijwhost.dll so the
    # skill picks up the gallery-installed module.
    Write-Host "Installing Vortex from PowerShell Gallery..."
    if ($PSVersionTable.PSEdition -ne 'Core') {
        throw "This requires PowerShell 7+ (Core). Detected: $($PSVersionTable.PSEdition)."
    }
    Install-Module -Name Vortex -Scope CurrentUser -Force -AllowClobber
    Write-Host "Installed. Module is now in $env:USERPROFILE\Documents\PowerShell\Modules\Vortex\"
    Write-Host "To use it, delete the bundled Vortex.dll/ijwhost.dll from this skill folder."
}

switch ($args[0]) {
    'download-engine' { Build-Engine }
    'psgallery'       { Install-FromPSGallery }
    default           { Build-Engine }
}
