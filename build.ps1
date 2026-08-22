# =============================================================================
# build.ps1 — VORTEX-OS skill helper: rebuild the engine from source
# =============================================================================
# This is the SOURCE-BUILD helper for people who have cloned this skill to
# FORK or PATCH the upstream .NET 10 C++/CLI engine. It is NOT the routine
# install path. For routine use, just run `skill.ps1` — it self-bootstraps by
# downloading the latest prebuilt engine from the public GitHub release of
# Cloudmeru/vortex-os-dotnet. See `install.ps1` for the download flow, and
# `references/INSTRUCTIONS.md` §12 for details.
#
# When do you need this?
#   * You cloned this skill to fork the engine and need to test a patch.
#   * You need a runtime older than .NET 10.
#   * You are packaging a custom internal build of the engine.
#
# Prerequisites:
#   * Visual Studio 2022 17.10+ BuildTools (or full VS) with the C++/CLI
#     workload installed
#   * .NET 10 SDK on PATH  (ref + host packs under
#     %ProgramFiles%\dotnet\packs\)
#   * PowerShell 7+
#
# Usage:
#   pwsh -NoProfile -File build.ps1            # download + build the .NET repo
#   pwsh -NoProfile -File build.ps1 -DotnetSrc 'C:\path\to\vortex-os-dotnet'
#   pwsh -NoProfile -File build.ps1 -Install   # build then install.ps1 over it
# =============================================================================
[CmdletBinding()]
param(
    # Optional: path to a local checkout of the vortex-os-dotnet source repo.
    # If omitted, the script downloads main.zip from GitHub.
    [string] $DotnetSrc = $env:VORTEX_DOTNET_SRC,

    # After a successful source build, run install.ps1 to register the freshly
    # built Vortex.psd1/.dll in user-scope. Useful for "I patched the engine,
    # now I want to use my patched build" — but you also need to copy your
    # build output into the user-scope module folder manually, since this
    # script writes to the local skill dir, not to $HOME\Documents\PowerShell\Modules.
    [switch] $Install
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
if (-not $here) { $here = (Get-Location).Path }

function Build-Engine {
    if ($DotnetSrc) {
        $srcRoot = (Resolve-Path $DotnetSrc).Path
        Write-Host "Using local source at $srcRoot" -ForegroundColor Cyan
    } else {
        $srcUrl  = 'https://github.com/Cloudmeru/vortex-os-dotnet/archive/refs/heads/main.zip'
        $zipPath = Join-Path $env:TEMP 'vortex-os-dotnet.zip'
        $extractDir = Join-Path $env:TEMP 'vortex-os-dotnet-extract'

        Write-Host "Downloading VORTEX-OS .NET engine source from $srcUrl ..." -ForegroundColor Cyan
        if (Test-Path $extractDir) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($extractDir, 'OnlyErrorDialogs', 'RecycleBin')
        }
        if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $srcUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

        $srcRoot = (Get-ChildItem -Path $extractDir -Directory | Select-Object -First 1).FullName
        Write-Host "Extracted to $srcRoot" -ForegroundColor Cyan
    }

    Write-Host "Building..." -ForegroundColor Cyan
    & pwsh -NoProfile -File (Join-Path $srcRoot 'src\build.ps1')
    if ($LASTEXITCODE -ne 0) { throw "Engine build failed (exit $LASTEXITCODE)" }

    # Copy artifacts next to the skill's entry points. These are gitignored
    # and only used as a scratch buffer for the source-build path.
    foreach ($name in 'Vortex.dll', 'Vortex.psm1', 'Vortex.psd1', 'ijwhost.dll') {
        $src = Join-Path $srcRoot $name
        if (Test-Path $src) {
            Copy-Item -Path $src -Destination (Join-Path $here $name) -Force
        }
    }
    Write-Host "Engine built and copied to the skill root." -ForegroundColor Green
    Write-Host "Note: the skill's skill.ps1 / verify.ps1 always Import-Module Vortex from user-scope." -ForegroundColor Yellow
    Write-Host "      To use this fresh build, copy these 4 files into `$HOME\Documents\PowerShell\Modules\Vortex\<version>\ manually." -ForegroundColor Yellow
}

Build-Engine

if ($Install) {
    Write-Host "Running installer (install.ps1) ..." -ForegroundColor Cyan
    & pwsh -NoProfile -File (Join-Path $here 'install.ps1')
    if ($LASTEXITCODE -ne 0) { throw "Installer failed with exit $LASTEXITCODE" }
}
