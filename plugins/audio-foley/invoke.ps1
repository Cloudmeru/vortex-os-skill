# audio-foley plugin — foley sound effects from natural-language prompts
# v0.2.0 reference plugin. NOTE: the actual MiniMax-Music API call is left as
# a documented stub (mms_search_artist) so the plugin can be tested without
# hitting the network; replace the body of `Invoke-FoleyApi` with the real
# call when a MiniMax-Music API key is available.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force

$inputs = Get-VortexPluginInput
$duration = if ($inputs.PSObject.Properties.Name -contains 'duration_s') { [int]$inputs.duration_s } else { 5 }
$format = if ($inputs.PSObject.Properties.Name -contains 'format') { $inputs.format } else { 'wav' }

Write-VortexPluginLog "audio-foley invoked: prompt='$($inputs.prompt)' duration=${duration}s format=$format"

# Output path: <VORTEX_HOME>/deliverables/<project>/foley_<ts>.<format>
$vortexHome = $env:VORTEX_HOME
if (-not $vortexHome) { $vortexHome = Join-Path $env:APPDATA 'Vortex-OS' }
$project = if ($env:VORTEX_PROJECT) { $env:VORTEX_PROJECT } else { 'default' }
$outDir = Join-Path $vortexHome 'deliverables' $project
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$ts = Get-Date -Format 'yyyyMMddHHmmss'
$outFile = Join-Path $outDir "foley_${ts}.${format}"

# Stub: write a silent placeholder WAV so the contract is satisfied.
# Replace with a real MiniMax-Music call when an API key is available.
$sampleRate = 44100
$samples = New-Object 'short[]' ($sampleRate * $duration)
# Minimal valid WAV header + silence
$header = [System.Text.Encoding]::ASCII.GetBytes('RIFF')
$header += [System.BitConverter]::GetBytes(36 + $samples.Length * 2)
$header += [System.Text.Encoding]::ASCII.GetBytes('WAVEfmt ')
$header += [System.BitConverter]::GetBytes(16)
$header += [System.Text.Encoding]::ASCII.GetBytes([char]1)  # PCM
$header += [System.Text.Encoding]::ASCII.GetBytes([char]0)
$header += [System.BitConverter]::GetBytes(1)                # mono
$header += [System.BitConverter]::GetBytes($sampleRate)
$header += [System.BitConverter]::GetBytes($sampleRate * 2)  # byte rate
$header += [System.Text.Encoding]::ASCII.GetBytes([char]2) + [System.Text.Encoding]::ASCII.GetBytes([char]0)
$header += [System.Text.Encoding]::ASCII.GetBytes([char]16) + [System.Text.Encoding]::ASCII.GetBytes([char]0)
$header += [System.Text.Encoding]::ASCII.GetBytes('data')
$header += [System.BitConverter]::GetBytes($samples.Length * 2)
[System.IO.File]::WriteAllBytes($outFile, $header)
[System.IO.File]::WriteAllBytes($outFile, $header + [System.Text.Encoding]::ASCII.GetBytes([byte[]](0..($samples.Length * 2 - 1) | ForEach-Object { 0 })))

Write-VortexPluginLog "wrote stub foley: $outFile"
Write-VortexPluginOutput @{
    file       = $outFile
    duration_s = $duration
    format     = $format
}
