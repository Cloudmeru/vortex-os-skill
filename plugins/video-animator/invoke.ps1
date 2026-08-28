# video-animator plugin -- animation / motion graphics
# v0.3.5: defaults to mcode-tools submit_video_generation with model
# MiniMax-H3 (the recommended model for animation), async + poll, falls
# back to a 1-second ffmpeg color frame.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force

$inputs = Get-VortexPluginInput
$prompt = $inputs.prompt
$duration = if ($inputs.PSObject.Properties.Name -contains 'duration_s') { [int]$inputs.duration_s } else { 4 }
$style = if ($inputs.PSObject.Properties.Name -contains 'style') { $inputs.style } else { 'motion-graphics' }
Write-VortexPluginLog "video-animator invoked: prompt='$prompt' duration=${duration}s style=$style"

# Build output path
$vortexHome = $env:VORTEX_HOME
if (-not $vortexHome) { $vortexHome = Join-Path $env:APPDATA 'Vortex-OS' }
$project = if ($env:VORTEX_PROJECT) { $env:VORTEX_PROJECT } else { 'default' }
$outDir = Join-Path $vortexHome 'deliverables' $project
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$ts = Get-Date -Format 'yyyyMMddHHmmss'
$outFile = Join-Path $outDir "animator_${ts}.mp4"

$submitArgs = @{
    prompt    = "$prompt -- animation style: $style"
    model     = 'MiniMax-H3'
    duration  = $duration
}

$result = Invoke-VortexWithFallback `
    -Async `
    -SubmitTool 'connector__matrix__submit_video_generation' `
    -QueryTool 'connector__matrix__query_video_generation' `
    -SubmitArgs $submitArgs `
    -QueryArgs @{ model = 'MiniMax-H3' } `
    -DownloadTo $outFile `
    -QueryAfter {
        param($resp, $out)
        $url = $resp.video_url
        if (-not $url) { throw "query_video_generation succeeded but no video_url: $($resp | ConvertTo-Json -Compress)" }
        return Save-VortexAssetFromUrl -Url $url -OutFile $out
    } `
    -Fallback {
        param($a, $out)
        $dur = if ($a.PSObject.Properties.Name -contains 'duration') { [int]$a.duration } else { 1 }
        # Pick a color based on the style so different styles produce different
        # fallback frames (helps the operator spot which path was used)
        $color = switch ($a.PSObject.Properties.Name -contains 'style' ? $a.prompt : '') {
            { $_ -like '*logo*' }    { 'navy' }
            { $_ -like '*infographic*' } { 'teal' }
            { $_ -like '*kinetic*' } { 'crimson' }
            default                  { 'steelblue' }
        }
        New-VortexFfmpegColorFrameMp4 -OutFile $out -DurationSec $dur -Aspect '16:9' -Color $color
    }

Write-VortexPluginLog "video-animator: produced via $($result.Provider)"
Write-VortexPluginOutput @{ file = $result.File; duration_s = $duration; format = 'mp4'; provider = $result.Provider }
