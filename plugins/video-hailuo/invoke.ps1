# video-hailuo plugin -- cinematic video clips
# v0.3.5: defaults to mcode-tools submit_video_generation (async submit
# + poll for completion), falls back to a 1-second ffmpeg color frame.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force

$inputs = Get-VortexPluginInput
$prompt = $inputs.prompt
$duration = if ($inputs.PSObject.Properties.Name -contains 'duration_s') { [int]$inputs.duration_s } else { 6 }
$aspect = if ($inputs.PSObject.Properties.Name -contains 'aspect') { $inputs.aspect } else { '16:9' }
$fps = if ($inputs.PSObject.Properties.Name -contains 'fps') { [int]$inputs.fps } else { 24 }
Write-VortexPluginLog "video-hailuo invoked: prompt='$prompt' duration=${duration}s aspect=$aspect fps=$fps"

# Build output path
$vortexHome = $env:VORTEX_HOME
if (-not $vortexHome) { $vortexHome = Join-Path $env:APPDATA 'Vortex-OS' }
$project = if ($env:VORTEX_PROJECT) { $env:VORTEX_PROJECT } else { 'default' }
$outDir = Join-Path $vortexHome 'deliverables' $project
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$ts = Get-Date -Format 'yyyyMMddHHmmss'
$outFile = Join-Path $outDir "hailuo_${ts}.mp4"

# mcode-tools: submit_video_generation is async; query_video_generation polls.
# We use -Async with custom SubmitArgs + QueryAfter (the response on success
# has video_url directly, so we download that).
$submitArgs = @{
    prompt    = $prompt
    model     = 'MiniMax-Hailuo-2.3'
    duration  = $duration
    aspect_ratio = $aspect
}

$result = Invoke-VortexWithFallback `
    -Async `
    -SubmitTool 'connector__matrix__submit_video_generation' `
    -QueryTool 'connector__matrix__query_video_generation' `
    -SubmitArgs $submitArgs `
    -QueryArgs @{ model = 'MiniMax-Hailuo-2.3' } `
    -DownloadTo $outFile `
    -QueryAfter {
        param($resp, $out)
        # The query response on success has video_url directly (not a success_items array)
        $url = $resp.video_url
        if (-not $url) { throw "query_video_generation succeeded but no video_url: $($resp | ConvertTo-Json -Compress)" }
        return Save-VortexAssetFromUrl -Url $url -OutFile $out
    } `
    -Fallback {
        param($a, $out)
        $dur = if ($a.PSObject.Properties.Name -contains 'duration') { [int]$a.duration } else { 1 }
        $asp = if ($a.PSObject.Properties.Name -contains 'aspect_ratio') { $a.aspect_ratio } else { '16:9' }
        New-VortexFfmpegColorFrameMp4 -OutFile $out -DurationSec $dur -Aspect $asp -Color 'black'
    }

Write-VortexPluginLog "video-hailuo: produced via $($result.Provider)"
Write-VortexPluginOutput @{ file = $result.File; duration_s = $duration; format = 'mp4'; provider = $result.Provider }
