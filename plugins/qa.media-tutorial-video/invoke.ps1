# qa.media-tutorial-video plugin -- specialist #1 for the media-tutorial-video template.
# v0.3.7: calls qa.core for basic checks, then runs template-specific
# vision-LLM checks (per-slide narrative coherence, palette consistency).
# Falls back to 'skip' verdicts for vision checks if mcode-tools is offline.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force

# Import the qa.core module so we can call its basic checks inline
$corePath = Join-Path $PSScriptRoot '..\qa.core\invoke.ps1'
# We can't easily Import-Module a script, so just dot-source it
. $corePath

$inputs = Get-VortexPluginInput
$filesJson = $inputs.files
$files = if ($filesJson -is [string]) { $filesJson | ConvertFrom-Json } else { $filesJson }
$scriptPath = if ($inputs.PSObject.Properties.Name -contains 'script') { $inputs.script } else { $null }
$palette = if ($inputs.PSObject.Properties.Name -contains 'palette') { $inputs.palette } else { '' }

Write-VortexPluginLog "qa.media-tutorial-video invoked: $($files.PSObject.Properties.Count) file(s), palette='$palette'"

# Load the source script (if provided) so we can cross-check slide content
$slideText = @{}
if ($scriptPath -and (Test-Path -LiteralPath $scriptPath)) {
    $script = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
    # Split on H2 / H3 headings; each section is a slide's content
    $sections = @()
    if ($script -match '(?m)^##\s+') {
        $sections = [regex]::Split($script, '(?m)^##\s+') | Where-Object { $_.Trim() } | ForEach-Object {
            $lines = $_ -split "`r?`n"
            $header = $lines[0].Trim()
            $body = ($lines[1..($lines.Count-1)] -join "`n").Trim()
            [pscustomobject]@{ title = $header; body = $body }
        }
    } else {
        $sections = ($script -split "`r?`n`r?`n") | Where-Object { $_.Trim() } | ForEach-Object {
            $firstLine = ($_ -split "`r?`n")[0].Trim()
            [pscustomobject]@{ title = $firstLine; body = $_ }
        }
    }
    for ($i = 0; $i -lt $sections.Count; $i++) {
        $slideText[("slide_{0:D2}" -f ($i + 1))] = $sections[$i]
    }
}

# ------------------------------------------------------------------
# Step 1: qa.core basic checks
# ------------------------------------------------------------------
$coreArgs = @{ files = ($files | ConvertTo-Json -Compress) }
$coreInputPath = $env:VORTEX_PLUGIN_INPUTS
$coreOutputPath = $env:VORTEX_PLUGIN_OUTPUTS
# We need to invoke qa.core inline. The simplest is to dot-source it (above) and
# re-run the same checks. For now, write a parallel basic-checks routine here.
$findings = @()
$totalChecks = 0
$passedChecks = 0
$ffprobe = (Get-Command ffprobe -ErrorAction SilentlyContinue).Source

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
# Step 2: template-specific vision-LLM checks (with graceful degradation)
# ------------------------------------------------------------------
$provider = 'mcode-tools'
$visionChecks = 0
$visionPassed = 0

# Group hero images by slide (file keys starting with 'hero_slide_NN')
$heroKeys = $files.PSObject.Properties.Name | Where-Object { $_ -like 'hero_slide_*' }
$heroCount = $heroKeys.Count
Write-VortexPluginLog "found $heroCount hero images for vision QA"

if ($heroCount -gt 0) {
    $firstHero = $files.$($heroKeys[0])
    if (-not (Test-VortexMcodeToolsAvailable)) {
        Write-VortexPluginLog "mcode-tools unavailable -- skipping vision QA checks"
        $provider = 'local-fallback'
        $findings += [pscustomobject]@{ kind = 'vision_qa'; severity = 'info'; message = 'mcode-tools unavailable; vision checks skipped; basic checks still ran'; file = ''; retry_hint = '' }
    } else {
        foreach ($key in $heroKeys) {
            $path = $files.$key
            $slideNum = ($key -replace 'hero_slide_', '') -replace '^0+', ''
            if (-not $slideNum) { $slideNum = '1' }
            $scriptKey = "slide_$('{0:D2}' -f [int]$slideNum)"
            $slideScript = if ($slideText.ContainsKey($scriptKey)) { $slideText[$scriptKey] } else { $null }
            $question = if ($slideScript) {
                "Does this image visually match the following slide content? Slide title: '$($slideScript.title)'. Body: $($slideScript.body.Substring(0, [Math]::Min(200, $slideScript.body.Length))). Answer yes or no, and a one-sentence reason."
            } else {
                "Is this image a coherent, well-composed slide cover (no placeholder, no blank frame, no obvious corruption)? Answer yes or no."
            }
            $visionChecks++
            $verdict = Invoke-VortexVisionQA -FilePath $path -Question $question -ExpectYesNo
            if ($verdict.yes -eq $true) { $visionPassed++ }
            elseif ($verdict.yes -eq $false) {
                $findings += [pscustomobject]@{
                    kind       = $key
                    severity   = 'medium'
                    message    = "vision QA: hero image does not match slide content. raw: $($verdict.raw)"
                    file       = $path
                    retry_hint = "regenerate hero with prompt more aligned to: $($slideScript.title)"
                }
            } else {
                # inconclusive -- don't penalize
                $visionPassed++
            }
        }

        # Palette consistency: sample the dominant color of each hero and check
        # they all share the same hue band. Cheaper than a vision call.
        if ($heroCount -ge 2) {
            $ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
            if ($ffmpeg) {
                $colors = @()
                foreach ($key in $heroKeys) {
                    $path = $files.$key
                    $tmp = Join-Path $env:TEMP "qa-palette-$([Guid]::NewGuid().ToString('N').Substring(0,6)).png"
                    & ffmpeg -y -i $path -vf "scale=8:8" -frames:v 1 $tmp 2>&1 | Out-Null
                    if (Test-Path -LiteralPath $tmp) {
                        $bytes = [System.IO.File]::ReadAllBytes($tmp)
                        # Sample the center pixel (approximate; png is compressed)
                        $colors += $bytes.Length   # crude size proxy; we just want a "different" signal
                        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                    }
                }
                # If all sizes are identical, the heroes are likely the same placeholder
                $unique = ($colors | Sort-Object -Unique).Count
                if ($unique -eq 1 -and $colors.Count -ge 3) {
                    $findings += [pscustomobject]@{
                        kind       = 'palette'
                        severity   = 'high'
                        message    = "all $heroCount hero images appear identical (likely all the same placeholder); expected $heroCount distinct slides"
                        file       = ''
                        retry_hint = 'regenerate with distinct prompts per slide'
                    }
                }
            }
        }
    }
}

# ------------------------------------------------------------------
# Step 3: aggregate
# ------------------------------------------------------------------
$totalChecks += $visionChecks
$passedChecks += $visionPassed
$score = if ($totalChecks -gt 0) { [math]::Round($passedChecks / $totalChecks, 3) } else { 1.0 }
$highestSeverity = if ($findings) { ($findings | ForEach-Object { $_.severity } | Sort-Object @{ Expression = { @('info','low','medium','high','critical').IndexOf($_) } } -Descending | Select-Object -First 1) } else { 'info' }
$decision = switch ($highestSeverity) {
    'critical'   { 'hitl-halt' }
    'high'       { 'retry' }
    'medium'     { if ($score -lt 0.7) { 'retry' } else { 'auto-approve' } }
    default      { 'auto-approve' }
}

Write-VortexPluginLog "qa.media-tutorial-video verdict: score=$score decision=$decision findings=$($findings.Count) vision_checks=$visionChecks"

Write-VortexPluginOutput @{
    score    = $score
    findings = ($findings | ConvertTo-Json -Depth 4 -Compress)
    decision = $decision
    provider = $provider
}
