# video-hailuo plugin — cinematic video clips (stub: 1-second mp4)
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force
$inputs = Get-VortexPluginInput
$duration = if ($inputs.PSObject.Properties.Name -contains 'duration_s') { [int]$inputs.duration_s } else { 6 }
Write-VortexPluginLog "video-hailuo invoked: duration=${duration}s"

$vortexHome = $env:VORTEX_HOME
if (-not $vortexHome) { $vortexHome = Join-Path $env:APPDATA 'Vortex-OS' }
$project = if ($env:VORTEX_PROJECT) { $env:VORTEX_PROJECT } else { 'default' }
$outDir = Join-Path $vortexHome 'deliverables' $project
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$ts = Get-Date -Format 'yyyyMMddHHmmss'
$outFile = Join-Path $outDir "hailuo_${ts}.mp4"
# Stub: just a placeholder file (real impl calls MiniMax-Hailuo API).
'VORTEX-OS video stub: replace with real MiniMax-Hailuo call' | Set-Content -LiteralPath $outFile -Encoding UTF8
Write-VortexPluginOutput @{ file = $outFile; duration_s = $duration; format = 'mp4' }
