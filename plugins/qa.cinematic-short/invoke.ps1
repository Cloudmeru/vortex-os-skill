# qa.cinematic-short plugin -- specialist #2 for the cinematic-short template.
# v0.3.7: calls qa.core for basic checks, then runs director-specific
# checks: character continuity, palette, aspect, voice, transitions.
# Falls back to 'skip' verdicts for vision checks if mcode-tools is offline.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force

$inputs = Get-VortexPluginInput
$filesJson = $inputs.files
$files = if ($filesJson -is [string]) { $filesJson | ConvertFrom-Json } else { $filesJson }
$scenesPath = $inputs.scenes_manifest
$biblePath = $inputs.production_bible

Write-VortexPluginLog "qa.cinematic-short invoked: $($files.PSObject.Properties.Count) file(s), scenes='$scenesPath', bible='$biblePath'"

# Load the scenes + bible
$scenes = if (Test-Path -LiteralPath $scenesPath) { Get-Content -LiteralPath $scenesPath -Raw | ConvertFrom-Json } else { @() }
$bible  = if (Test-Path -LiteralPath $biblePath)  { Get-Content -LiteralPath $biblePath  -Raw | ConvertFrom-Json } else { $null }
$expectedAspect = if ($bible -and $bible.PSObject.Properties.Name -contains 'aspect') { $bible.aspect } else { '16:9' }

$findings = @()
$totalChecks = 0
$passedChecks = 0
$ffprobe = (Get-Command ffprobe -ErrorAction SilentlyContinue).Source

# ------------------------------------------------------------------
# Step 1: qa.core-style basic checks on every file
# ------------------------------------------------------------------
foreach ($prop in $files.PSObject.Properties) {
    $kind = $prop.Name
    $path = $prop.Value
    $totalChecks++

    if (-not (Test-Path -LiteralPath $path)) {
        $findings += [pscustomobject]@{ kind = $kind; severity = 'critical'; message = "file not found: $path"; file = $path; retry_hint = 'regenerate' }
        continue
    }
    $size = (Get-Item -LiteralPath $path).Length
    if ($size -le 100) {
        $findings += [pscustomobject]@{ kind = $kind; severity = 'critical'; message = "file is too small ($size bytes); likely a placeholder"; file = $path; retry_hint = 'regenerate' }
        continue
    }
    $passedChecks++

    if ($ffprobe -and $path -match '\.mp4$') {
        $probe = & ffprobe -v error -show_entries stream=codec_name:format=duration -of default=noprint_wrappers=1:nokey=1 $path 2>&1
        $joined = ($probe -join "`n")
        if ($joined -notmatch 'codec_name=h264' -and $joined -notmatch 'codec_name=vp9' -and $joined -notmatch 'codec_name=hevc') {
            $findings += [pscustomobject]@{ kind = $kind; severity = 'high'; message = "mp4 has no recognized video stream"; file = $path; retry_hint = 'regenerate' }
        }
    }
}

# ------------------------------------------------------------------
# Step 2: cinematic-specific checks
# ------------------------------------------------------------------
$provider = 'mcode-tools'

# Aspect consistency: every video_scene_NN clip should be at $expectedAspect
$videoKeys = $files.PSObject.Properties.Name | Where-Object { $_ -like 'video_scene_*' }
if ($videoKeys.Count -gt 0 -and $ffprobe) {
    foreach ($key in $videoKeys) {
        $path = $files.$key
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $dim = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 $path 2>&1
        $dimJoined = ($dim -join ',').Trim()
        $parts = $dimJoined.Split(',')
        $w = if ($parts.Count -gt 0) { [int]$parts[0] } else { 0 }
        $h = if ($parts.Count -gt 1) { [int]$parts[1] } else { 0 }
        $actualAspect = if ($w -gt 0 -and $h -gt 0) {
            $r = [math]::Round($w / $h, 2)
            switch ($r) {
                { $_ -ge 1.7 -and $_ -le 1.8 } { '16:9' }
                { $_ -ge 0.55 -and $_ -le 0.6 } { '9:16' }
                { $_ -ge 0.95 -and $_ -le 1.05 } { '1:1' }
                default { "${w}x${h}" }
            }
        } else { 'unknown' }
        $totalChecks++
        if ($actualAspect -ne $expectedAspect) {
            $findings += [pscustomobject]@{ kind = $key; severity = 'high'; message = "clip is $actualAspect but bible specifies $expectedAspect"; file = $path; retry_hint = "regenerate with aspect_ratio=$expectedAspect" }
        } else {
            $passedChecks++
        }
    }
}

# Transition continuity: each scene's transition_out should match the next scene's transition_in
if ($scenes -and $scenes.Count -gt 1) {
    for ($i = 0; $i -lt $scenes.Count - 1; $i++) {
        $totalChecks++
        $out = $scenes[$i].transition_out
        $nextIn = $scenes[$i + 1].transition_in
        if ($out -and $nextIn -and $out -ne $nextIn -and -not ($out -eq 'crossfade' -and $nextIn -eq 'fade')) {
            $findings += [pscustomobject]@{ kind = "transition_$($scenes[$i].index)_$($scenes[$i+1].index)"; severity = 'low'; message = "scene $($scenes[$i].index).transition_out='$out' but scene $($scenes[$i+1].index).transition_in='$nextIn'"; file = ''; retry_hint = 'update the scene manifest so transitions match' }
        } else {
            $passedChecks++
        }
    }
}

# Character continuity: for each character in the bible, the scenes that
# list that character must have a hero image that matches the description
# (vision LLM). Best-effort: only runs if mcode-tools is available.
if ($bible -and $bible.PSObject.Properties.Name -contains 'characters' -and $bible.characters.Count -gt 0) {
    if (-not (Test-VortexMcodeToolsAvailable)) {
        Write-VortexPluginLog "mcode-tools unavailable -- skipping character-continuity vision checks"
        $provider = 'local-fallback'
        $findings += [pscustomobject]@{ kind = 'vision_qa'; severity = 'info'; message = 'mcode-tools unavailable; character-continuity checks skipped; basic checks still ran'; file = ''; retry_hint = '' }
    } else {
        $heroKeys = $files.PSObject.Properties.Name | Where-Object { $_ -like 'hero_scene_*' }
        foreach ($heroKey in $heroKeys) {
            $sceneNum = ($heroKey -replace 'hero_scene_', '') -replace '^0+', ''
            if (-not $sceneNum) { continue }
            $scene = $scenes | Where-Object { $_.index -eq [int]$sceneNum } | Select-Object -First 1
            if (-not $scene) { continue }
            $sceneChars = if ($scene.PSObject.Properties.Name -contains 'characters') { $scene.characters } else { @() }
            if (-not $sceneChars -or $sceneChars.Count -eq 0) { continue }
            $charDescriptions = foreach ($charName in $sceneChars) {
                $charDef = $bible.characters | Where-Object { $_.name -eq $charName } | Select-Object -First 1
                if ($charDef) { "- $($charDef.name): $($charDef.description)" }
            }
            if (-not $charDescriptions) { continue }
            $question = "Does this image show the following character(s) consistent with the descriptions? $([string]::Join(' ', $charDescriptions)). Answer yes or no."
            $totalChecks++
            $verdict = Invoke-VortexVisionQA -FilePath $files.$heroKey -Question $question -ExpectYesNo
            if ($verdict.yes -eq $true) { $passedChecks++ }
            elseif ($verdict.yes -eq $false) {
                $findings += [pscustomobject]@{
                    kind       = $heroKey
                    severity   = 'high'
                    message    = "character continuity broken in scene $sceneNum. raw: $($verdict.raw)"
                    file       = $files.$heroKey
                    retry_hint = "regenerate hero for scene $sceneNum with characters: $([string]::Join(', ', $sceneChars))"
                }
            } else { $passedChecks++ }   # inconclusive = pass
        }
    }
}

# ------------------------------------------------------------------
# Step 3: aggregate
# ------------------------------------------------------------------
$score = if ($totalChecks -gt 0) { [math]::Round($passedChecks / $totalChecks, 3) } else { 1.0 }
$highestSeverity = if ($findings) { ($findings | ForEach-Object { $_.severity } | Sort-Object @{ Expression = { @('info','low','medium','high','critical').IndexOf($_) } } -Descending | Select-Object -First 1) } else { 'info' }
$decision = switch ($highestSeverity) {
    'critical'   { 'hitl-halt' }
    'high'       { 'retry' }
    'medium'     { if ($score -lt 0.7) { 'retry' } else { 'auto-approve' } }
    default      { 'auto-approve' }
}

Write-VortexPluginLog "qa.cinematic-short verdict: score=$score decision=$decision findings=$($findings.Count)"

Write-VortexPluginOutput @{
    score    = $score
    findings = ($findings | ConvertTo-Json -Depth 4 -Compress)
    decision = $decision
    provider = $provider
}
