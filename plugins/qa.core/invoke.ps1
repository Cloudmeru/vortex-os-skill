# qa.core plugin -- shared basic QA checks.
# v0.3.7: called by every qa.* specialist (never directly by reviewer.quality).
# Returns a verdict with score 0-1 + finding list + decision.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force

$inputs = Get-VortexPluginInput
$filesJson = $inputs.files
$expectedJson = if ($inputs.PSObject.Properties.Name -contains 'expected_dimensions') { $inputs.expected_dimensions } else { $null }
if ($expectedJson -is [string]) { $expectedJson = $expectedJson | ConvertFrom-Json }
$files = if ($filesJson -is [string]) { $filesJson | ConvertFrom-Json } else { $filesJson }

Write-VortexPluginLog "qa.core invoked: $($files.PSObject.Properties.Count) file(s) to check"

$findings = @()
$totalChecks = 0
$passedChecks = 0

# ffprobe for media metadata
$ffprobe = (Get-Command ffprobe -ErrorAction SilentlyContinue).Source
$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source

foreach ($prop in $files.PSObject.Properties) {
    $kind = $prop.Name
    $path = $prop.Value
    $totalChecks++

    # 1. File exists
    if (-not (Test-Path -LiteralPath $path)) {
        $findings += [pscustomobject]@{ kind = $kind; severity = 'critical'; message = "file not found: $path"; file = $path; retry_hint = 'regenerate' }
        continue
    }
    # 2. Nonzero size
    $size = (Get-Item -LiteralPath $path).Length
    if ($size -le 100) {
        $findings += [pscustomobject]@{ kind = $kind; severity = 'critical'; message = "file is too small ($size bytes); likely a placeholder"; file = $path; retry_hint = 'regenerate (the worker probably hit a fallback that wrote an empty/placeholder file)' }
        continue
    }
    $passedChecks++

    # 3. Placeholder-text detection -- a plain text file written as an mp4 fallback
    # is detectable because ffmpeg can probe it and see duration=0 / invalid stream
    if ($ffprobe -and $path -match '\.(mp4|wav|png|jpg)$') {
        $probe = & ffprobe -v error -show_entries stream=codec_name:format=duration -of default=noprint_wrappers=1:nokey=1 $path 2>&1
        $joined = ($probe -join "`n")
        if ($path -match '\.mp4$') {
            if ($joined -notmatch 'codec_name=h264' -and $joined -notmatch 'codec_name=vp9' -and $joined -notmatch 'codec_name=hevc') {
                $findings += [pscustomobject]@{ kind = $kind; severity = 'high'; message = "mp4 has no recognized video stream (codec=$($joined.Trim()))"; file = $path; retry_hint = 'regenerate (the worker probably hit a local-placeholder-text fallback)' }
                continue
            }
        }
        if ($path -match '\.wav$') {
            if ($joined -notmatch 'codec_name=pcm') {
                $findings += [pscustomobject]@{ kind = $kind; severity = 'high'; message = "wav has no recognized audio stream (codec=$($joined.Trim()))"; file = $path; retry_hint = 'regenerate' }
                continue
            }
        }
    }

    # 4. Dimension / duration check (if expected)
    if ($expectedJson -and $expectedJson.PSObject.Properties.Name -contains $kind) {
        $exp = $expectedJson.$kind
        if ($ffprobe) {
            $dimOut = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height,duration -of csv=p=0 $path 2>&1
            $dimJoined = ($dimOut -join ',')
            if ($path -match '\.(png|jpg)$' -and $exp.PSObject.Properties.Name -contains 'min_width') {
                $parts = $dimJoined.Split(',')
                $w = if ($parts.Count -gt 0) { [int]$parts[0] } else { 0 }
                $h = if ($parts.Count -gt 1) { [int]$parts[1] } else { 0 }
                if ($w -lt [int]$exp.min_width -or $h -lt [int]$exp.min_height) {
                    $findings += [pscustomobject]@{ kind = $kind; severity = 'high'; message = "image is ${w}x${h}, expected at least $($exp.min_width)x$($exp.min_height)"; file = $path; retry_hint = 'regenerate with a larger size' }
                    continue
                }
            }
            if (($path -match '\.(wav|mp4)$') -and $exp.PSObject.Properties.Name -contains 'min_duration_s') {
                $parts = $dimJoined.Split(',')
                $dur = if ($parts.Count -gt 2) { [double]$parts[2] } else { 0 }
                $minD = [double]$exp.min_duration_s
                $maxD = if ($exp.PSObject.Properties.Name -contains 'max_duration_s') { [double]$exp.max_duration_s } else { 9999 }
                if ($dur -lt ($minD * 0.9) -or $dur -gt ($maxD * 1.1)) {
                    $findings += [pscustomobject]@{ kind = $kind; severity = 'medium'; message = "duration ${dur}s outside expected range [$minD, $maxD]s"; file = $path; retry_hint = 'regenerate with the right duration' }
                    continue
                }
            }
        }
    }
    # 5. No finding -> this check passed
    # (passedChecks was already incremented above)
}

# Aggregate decision
$score = if ($totalChecks -gt 0) { [math]::Round($passedChecks / $totalChecks, 3) } else { 1.0 }
$highestSeverity = if ($findings) { ($findings | ForEach-Object { $_.severity } | Sort-Object @{ Expression = { @('info','low','medium','high','critical').IndexOf($_) } } -Descending | Select-Object -First 1) } else { 'info' }
$decision = switch ($highestSeverity) {
    'critical'   { 'hitl-halt' }
    'high'       { 'retry' }
    'medium'     { if ($score -lt 0.7) { 'retry' } else { 'auto-approve' } }
    default      { 'auto-approve' }
}

Write-VortexPluginLog "qa.core verdict: score=$score decision=$decision findings=$($findings.Count)"

Write-VortexPluginOutput @{
    score    = $score
    findings = ($findings | ConvertTo-Json -Depth 4 -Compress)
    decision = $decision
    provider = 'local'
}
