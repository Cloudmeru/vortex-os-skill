# audio-foley plugin -- sound effects / foley generation
# v0.3.5: defaults to mcode-tools synthesize_sound_effect (if exposed) or
# falls through to a ffmpeg-generated tone based on the prompt hash, then
# to silent WAV. The mcode-tools call will fail silently if no such
# connector is registered; the fallback path always produces a file.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force

$inputs = Get-VortexPluginInput
$prompt = $inputs.prompt
$duration = if ($inputs.PSObject.Properties.Name -contains 'duration_s') { [int]$inputs.duration_s } else { 2 }
$format = if ($inputs.PSObject.Properties.Name -contains 'format') { $inputs.format } else { 'wav' }
Write-VortexPluginLog "audio-foley invoked: prompt='$prompt' duration=${duration}s format=$format"

# Build output path
$vortexHome = $env:VORTEX_HOME
if (-not $vortexHome) { $vortexHome = Join-Path $env:APPDATA 'Vortex-OS' }
$project = if ($env:VORTEX_PROJECT) { $env:VORTEX_PROJECT } else { 'default' }
$outDir = Join-Path $vortexHome 'deliverables' $project
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$ts = Get-Date -Format 'yyyyMMddHHmmss'
$outFile = Join-Path $outDir "foley_${ts}.${format}"

# Map prompt -> deterministic frequency so the same prompt always produces
# the same tone (useful for cross-take consistency)
$bytes = [System.Text.Encoding]::UTF8.GetBytes($prompt)
$hash = 0
foreach ($b in $bytes) { $hash = ($hash * 31 + $b) -band 0xFFFF }
$baseHz = 200 + ($hash % 800)   # 200-1000 Hz range

# Try mcode-tools first; fall back to ffmpeg tone (frequency from prompt hash),
# then to silent WAV
$result = Invoke-VortexWithFallback `
    -ToolName 'connector__matrix__synthesize_sound_effect' `
    -Args @{
        prompt      = $prompt
        duration_s  = $duration
        output_file = "foley_${ts}.${format}"
    } `
    -DownloadTo $outFile `
    -Fallback {
        param($a, $out)
        $dur = if ($a.PSObject.Properties.Name -contains 'duration_s') { [int]$a.duration_s } else { 2 }
        # Derive the same hash-based frequency so the fallback is deterministic
        $bytes2 = [System.Text.Encoding]::UTF8.GetBytes($a.prompt)
        $h = 0
        foreach ($b in $bytes2) { $h = ($h * 31 + $b) -band 0xFFFF }
        $hz = 200 + ($h % 800)
        New-VortexFfmpegToneWav -OutFile $out -DurationSec $dur -FrequencyHz $hz
    }

Write-VortexPluginLog "audio-foley: produced via $($result.Provider)"
Write-VortexPluginOutput @{ file = $result.File; duration_s = $duration; format = $format; provider = $result.Provider }
