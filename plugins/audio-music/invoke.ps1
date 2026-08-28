# audio-music plugin -- background music loops
# v0.3.5: defaults to mcode-tools batch_text_to_music, falls back to
# ffmpeg-generated tone, then to silent WAV.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force

$inputs = Get-VortexPluginInput
$prompt = $inputs.prompt
$duration = if ($inputs.PSObject.Properties.Name -contains 'duration_s') { [int]$inputs.duration_s } else { 30 }
$format = if ($inputs.PSObject.Properties.Name -contains 'format') { $inputs.format } else { 'wav' }
$bpm = if ($inputs.PSObject.Properties.Name -contains 'bpm') { [int]$inputs.bpm } else { 0 }
Write-VortexPluginLog "audio-music invoked: prompt='$prompt' duration=${duration}s bpm=$bpm format=$format"

# Build output path
$vortexHome = $env:VORTEX_HOME
if (-not $vortexHome) { $vortexHome = Join-Path $env:APPDATA 'Vortex-OS' }
$project = if ($env:VORTEX_PROJECT) { $env:VORTEX_PROJECT } else { 'default' }
$outDir = Join-Path $vortexHome 'deliverables' $project
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$ts = Get-Date -Format 'yyyyMMddHHmmss'
$outFile = Join-Path $outDir "music_${ts}.${format}"

# Try mcode-tools first; fall back to ffmpeg tone (frequency from bpm if set),
# then to silent WAV
$result = Invoke-VortexWithFallback `
    -ToolName 'connector__matrix__batch_text_to_music' `
    -Args @{
        requests = @(@{
            prompt      = $prompt
            duration_s  = $duration
            output_file = "music_${ts}.${format}"
        })
    } `
    -DownloadTo $outFile `
    -Fallback {
        param($a, $out)
        $req = $a.requests[0]
        $dur = if ($req.PSObject.Properties.Name -contains 'duration_s') { [int]$req.duration_s } else { 30 }
        $hz  = 440
        if ($a.PSObject.Properties.Name -contains 'bpm' -and $a.bpm) { $hz = [int]$a.bpm }
        New-VortexFfmpegToneWav -OutFile $out -DurationSec $dur -FrequencyHz $hz
    }

Write-VortexPluginLog "audio-music: produced via $($result.Provider)"
Write-VortexPluginOutput @{ file = $result.File; duration_s = $duration; format = $format; provider = $result.Provider }
