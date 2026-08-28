# qa.iteration-pattern plugin -- generic specialist for the universal template.
# v0.3.7: qa.core basic checks + template-specific checks (every slot filled,
# every min_bytes met, every extension matches). No vision calls.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force

$inputs = Get-VortexPluginInput
$filesJson = $inputs.files
$files = if ($filesJson -is [string]) { $filesJson | ConvertFrom-Json } else { $filesJson }
$templatePath = if ($inputs.PSObject.Properties.Name -contains 'template_path') { $inputs.template_path } else { $null }

Write-VortexPluginLog "qa.iteration-pattern invoked: $($files.PSObject.Properties.Count) file(s), template='$templatePath'"

# Load the template (if provided) so we can verify min_bytes per slot
$template = $null
if ($templatePath -and (Test-Path -LiteralPath $templatePath)) {
    try { $template = Get-Content -LiteralPath $templatePath -Raw | ConvertFrom-Json } catch { $template = $null }
}
$slotSpecs = if ($template -and $template.PSObject.Properties.Name -contains 'deliverables') { $template.deliverables } else { @() }

$findings = @()
$totalChecks = 0
$passedChecks = 0
$ffprobe = (Get-Command ffprobe -ErrorAction SilentlyContinue).Source

# ------------------------------------------------------------------
# Step 1: qa.core-style basic checks
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
# Step 2: template-specific checks
# ------------------------------------------------------------------
if ($slotSpecs -and $slotSpecs.Count -gt 0) {
    # Every slot in the template should have a file in the files map.
    # We match by the deliverable's 'name' field.
    foreach ($slot in $slotSpecs) {
        $totalChecks++
        $slotName = $slot.name
        $minBytes = if ($slot.PSObject.Properties.Name -contains 'min_bytes') { [int]$slot.min_bytes } else { 0 }
        $ext = if ($slot.PSObject.Properties.Name -contains 'extension') { $slot.extension } else { '' }
        # Find a file with a key matching the slot name (loose match)
        $matched = $files.PSObject.Properties.Name | Where-Object { $_ -like "*$slotName*" -or $_ -eq $slotName -or $_ -eq ("slot_$slotName") } | Select-Object -First 1
        if (-not $matched) {
            $findings += [pscustomobject]@{
                kind       = $slotName
                severity   = 'high'
                message    = "template slot '$slotName' has no file in the QA map"
                file       = ''
                retry_hint = "ensure the dispatch produced the '$slotName' deliverable"
            }
            continue
        }
        $path = $files.$matched
        if (-not (Test-Path -LiteralPath $path)) {
            $findings += [pscustomobject]@{ kind = $slotName; severity = 'critical'; message = "slot '$slotName' file missing: $path"; file = $path; retry_hint = 'regenerate' }
            continue
        }
        $size = (Get-Item -LiteralPath $path).Length
        if ($minBytes -gt 0 -and $size -lt $minBytes) {
            $findings += [pscustomobject]@{
                kind       = $slotName
                severity   = 'medium'
                message    = "slot '$slotName' is $size bytes; template requires at least $minBytes"
                file       = $path
                retry_hint = 'regenerate with more content'
            }
            continue
        }
        if ($ext -and -not $path.EndsWith($ext)) {
            $findings += [pscustomobject]@{
                kind       = $slotName
                severity   = 'low'
                message    = "slot '$slotName' has extension $([System.IO.Path]::GetExtension($path)) but template requires $ext"
                file       = $path
                retry_hint = 'convert to the right extension'
            }
            continue
        }
        $passedChecks++
    }
}

$score = if ($totalChecks -gt 0) { [math]::Round($passedChecks / $totalChecks, 3) } else { 1.0 }
$highestSeverity = if ($findings) { ($findings | ForEach-Object { $_.severity } | Sort-Object @{ Expression = { @('info','low','medium','high','critical').IndexOf($_) } } -Descending | Select-Object -First 1) } else { 'info' }
$decision = switch ($highestSeverity) {
    'critical'   { 'hitl-halt' }
    'high'       { 'retry' }
    'medium'     { if ($score -lt 0.7) { 'retry' } else { 'auto-approve' } }
    default      { 'auto-approve' }
}

Write-VortexPluginLog "qa.iteration-pattern verdict: score=$score decision=$decision findings=$($findings.Count)"

Write-VortexPluginOutput @{
    score    = $score
    findings = ($findings | ConvertTo-Json -Depth 4 -Compress)
    decision = $decision
    provider = 'local'
}
