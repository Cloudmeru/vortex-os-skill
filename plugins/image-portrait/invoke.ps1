# image-portrait plugin — character portrait generation
# v0.2.0 reference plugin. Wraps MiniMax-Image (stub: writes a tiny
# 1x1 PNG so the contract is satisfied without hitting the network).
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force

$inputs = Get-VortexPluginInput
$style = if ($inputs.PSObject.Properties.Name -contains 'style') { $inputs.style } else { 'realistic' }
$aspect = if ($inputs.PSObject.Properties.Name -contains 'aspect') { $inputs.aspect } else { '1:1' }

Write-VortexPluginLog "image-portrait invoked: style=$style aspect=$aspect"

$vortexHome = $env:VORTEX_HOME
if (-not $vortexHome) { $vortexHome = Join-Path $env:APPDATA 'Vortex-OS' }
$project = if ($env:VORTEX_PROJECT) { $env:VORTEX_PROJECT } else { 'default' }
$outDir = Join-Path $vortexHome 'deliverables' $project
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$ts = Get-Date -Format 'yyyyMMddHHmmss'
$outFile = Join-Path $outDir "portrait_${ts}.png"

# 1x1 transparent PNG (valid PNG; 67 bytes). Real impl calls MiniMax-Image.
$png = [byte[]](
    0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,
    0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
    0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
    0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
    0x89,0x00,0x00,0x00,0x0D,0x49,0x44,0x41,
    0x54,0x78,0x9C,0x63,0x00,0x01,0x00,0x00,
    0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,
    0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
    0x42,0x60,0x82
)
[System.IO.File]::WriteAllBytes($outFile, $png)

Write-VortexPluginLog "wrote stub portrait: $outFile"
Write-VortexPluginOutput @{
    file   = $outFile
    width  = 1
    height = 1
    style  = $style
}
