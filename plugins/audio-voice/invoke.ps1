# audio-voice plugin — TTS narration
# v0.2.1 reference plugin. Stub: silent WAV; real impl wraps MiniMax-TTS.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force
$inputs = Get-VortexPluginInput
$format = if ($inputs.PSObject.Properties.Name -contains 'format') { $inputs.format } else { 'wav' }
Write-VortexPluginLog "audio-voice invoked: text_len=$($inputs.text.Length) format=$format"

$vortexHome = $env:VORTEX_HOME
if (-not $vortexHome) { $vortexHome = Join-Path $env:APPDATA 'Vortex-OS' }
$project = if ($env:VORTEX_PROJECT) { $env:VORTEX_PROJECT } else { 'default' }
$outDir = Join-Path $vortexHome 'deliverables' $project
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$ts = Get-Date -Format 'yyyyMMddHHmmss'
$outFile = Join-Path $outDir "voice_${ts}.${format}"
$header = [System.Text.Encoding]::ASCII.GetBytes('RIFF')
$header += [System.BitConverter]::GetBytes(36)
$header += [System.Text.Encoding]::ASCII.GetBytes('WAVEfmt ')
$header += [System.BitConverter]::GetBytes(16)
$header += [System.Text.Encoding]::ASCII.GetBytes([char]1) + [System.Text.Encoding]::ASCII.GetBytes([char]0)
$header += [System.BitConverter]::GetBytes(1)
$header += [System.BitConverter]::GetBytes(22050)
$header += [System.BitConverter]::GetBytes(44100)
$header += [System.Text.Encoding]::ASCII.GetBytes([char]2) + [System.Text.Encoding]::ASCII.GetBytes([char]0)
$header += [System.Text.Encoding]::ASCII.GetBytes([char]16) + [System.Text.Encoding]::ASCII.GetBytes([char]0)
$header += [System.Text.Encoding]::ASCII.GetBytes('data')
$header += [System.BitConverter]::GetBytes(0)
[System.IO.File]::WriteAllBytes($outFile, $header)
Write-VortexPluginOutput @{ file = $outFile; format = $format }
