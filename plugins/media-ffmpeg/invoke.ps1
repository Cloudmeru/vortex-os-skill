# media-ffmpeg plugin — local ffmpeg wrapper (no LLM)
# v0.2.0 reference plugin. Demonstrates the "shim" pattern: a plugin that
# wraps a non-PowerShell, non-LLM tool (just calls ffmpeg on the host).
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force

$inputs = Get-VortexPluginInput
if (-not (Test-Path -LiteralPath $inputs.input)) { throw "Input file not found: $($inputs.input)" }

# Locate ffmpeg on PATH
$ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
Write-VortexPluginLog "ffmpeg binary: $ffmpeg"

# Build the output path if not supplied
$output = $inputs.output
if (-not $output) {
    $vortexHome = $env:VORTEX_HOME
    if (-not $vortexHome) { $vortexHome = Join-Path $env:APPDATA 'Vortex-OS' }
    $project = if ($env:VORTEX_PROJECT) { $env:VORTEX_PROJECT } else { 'default' }
    $outDir = Join-Path $vortexHome 'deliverables' $project
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $ts = Get-Date -Format 'yyyyMMddHHmmss'
    $ext = [System.IO.Path]::GetExtension($inputs.input)
    if (-not $ext) { $ext = '.mp4' }
    $output = Join-Path $outDir "ffmpeg_${ts}${ext}"
}

# Build the ffmpeg argument list
$ffArgs = @('-y', '-i', $inputs.input)
if ($inputs.PSObject.Properties.Name -contains 'start_s' -and $inputs.start_s) {
    $ffArgs += @('-ss', "$($inputs.start_s)")
}
if ($inputs.PSObject.Properties.Name -contains 'duration_s' -and $inputs.duration_s) {
    $ffArgs += @('-t', "$($inputs.duration_s)")
}
if ($inputs.PSObject.Properties.Name -contains 'sample_rate' -and $inputs.sample_rate) {
    $ffArgs += @('-ar', "$($inputs.sample_rate)")
}
if ($inputs.PSObject.Properties.Name -contains 'bitrate' -and $inputs.bitrate) {
    $ffArgs += @('-b:a', $inputs.bitrate)
}
$ffArgs += $output

Write-VortexPluginLog "running: ffmpeg $($ffArgs -join ' ')"

# Run ffmpeg
$proc = Start-Process -FilePath $ffmpeg -ArgumentList $ffArgs -NoNewWindow -PassThru -Wait
if ($proc.ExitCode -ne 0) {
    throw "ffmpeg exited with code $($proc.ExitCode)"
}

# Probe the output duration via ffprobe (best-effort)
$duration = 0
try {
    $probe = (Get-Command ffprobe -ErrorAction SilentlyContinue)
    if ($probe) {
        $probeOut = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $output
        $duration = [double]$probeOut
    }
} catch { $duration = 0 }

Write-VortexPluginLog "wrote: $output duration=${duration}s"
Write-VortexPluginOutput @{
    file       = $output
    duration_s = $duration
    command    = "ffmpeg $($ffArgs -join ' ')"
}
