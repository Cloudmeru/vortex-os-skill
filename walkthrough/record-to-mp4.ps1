#Requires -Version 7.0
<#
.SYNOPSIS
    Record the VORTEX-OS walkthrough HTML slides into an MP4 file.

.DESCRIPTION
    Uses headless Microsoft Edge to screenshot each slide at 960x540,
    then stitches the frames into an MP4 with ffmpeg.

    Optional flags:
      -DryRun          Show the commands but don't run them
      -SlideDuration   Seconds per slide in the output (default 6)
      -Output          Path to the output MP4 (default vortex-os-walkthrough.mp4 in the script folder)

.REQUIRES
    - Microsoft Edge (any recent version on Windows 10/11)
    - ffmpeg on PATH (winget install Gyan.FFmpeg)
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [int]$SlideDuration = 6,
    [string]$Output
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$slidesDir = Join-Path $scriptRoot 'slides'
$framesDir = Join-Path $env:TEMP "vortex-walkthrough-frames"

if (-not (Test-Path $slidesDir)) {
    throw "Slides directory not found: $slidesDir"
}

# Find Edge
$edge = @(
    'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    'C:\Program Files\Microsoft\Edge\Application\msedge.exe'
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw "Microsoft Edge not found. Install it from https://aka.ms/edge." }

# Find ffmpeg
$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue)?.Source
if (-not $ffmpeg) { throw "ffmpeg not on PATH. Install with: winget install Gyan.FFmpeg" }

# Default output
if (-not $Output) {
    $Output = Join-Path $scriptRoot 'vortex-os-walkthrough.mp4'
}

# Collect slides
$slides = Get-ChildItem -Path $slidesDir -Filter 'slide-*.html' | Sort-Object Name
if ($slides.Count -eq 0) { throw "No slide-*.html files in $slidesDir" }

Write-Host "Recording $($slides.Count) slides at ${SlideDuration}s each." -ForegroundColor Cyan
Write-Host "Frames dir: $framesDir"
Write-Host "Output:     $Output"

if ($DryRun) {
    Write-Host "`n--- DRY RUN: no changes will be made ---" -ForegroundColor Yellow
}

if (-not $DryRun) {
    if (Test-Path $framesDir) { Remove-Item -Recurse -Force $framesDir }
    New-Item -ItemType Directory -Path $framesDir -Force | Out-Null
}

# Capture each slide
for ($i = 0; $i -lt $slides.Count; $i++) {
    $slide = $slides[$i]
    $framePath = Join-Path $framesDir ("frame-{0:D4}.png" -f $i)
    $url = "file:///" + ($slide.FullName -replace '\\','/')
    Write-Host ("[{0:D2}/{1:D2}] {2}" -f ($i+1), $slides.Count, $slide.Name)
    if (-not $DryRun) {
        & $edge --headless=new --disable-gpu --window-size=960,540 `
            --screenshot=$framePath --hide-scrollbars $url
        Start-Sleep -Milliseconds 500
    }
}

# Stitch (each frame held for SlideDuration seconds, output 30 fps)
$holdFilter = "tpad=stop_duration=$($SlideDuration-1):stop_mode=add:color=black,fps=30"
$ffmpegArgs = @(
    '-y', '-framerate', '1',
    '-i', (Join-Path $framesDir 'frame-%04d.png'),
    '-vf', $holdFilter,
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
    $Output
)

Write-Host "`nffmpeg $ffmpegArgs"
if (-not $DryRun) {
    & $ffmpeg @ffmpegArgs
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed with exit code $LASTEXITCODE" }
}

if (-not $DryRun -and (Test-Path $framesDir)) {
    Remove-Item -Recurse -Force $framesDir
}

Write-Host "`nDone. Wrote $Output" -ForegroundColor Green
