# image-portrait plugin -- character portrait generation
# v0.3.5: defaults to mcode-tools generate_image, falls back to a
# labeled placeholder PNG.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force

$inputs = Get-VortexPluginInput
$prompt = $inputs.prompt
$style  = if ($inputs.PSObject.Properties.Name -contains 'style') { $inputs.style } else { 'realistic' }
$aspect = if ($inputs.PSObject.Properties.Name -contains 'aspect') { $inputs.aspect } else { '1:1' }
$seed   = if ($inputs.PSObject.Properties.Name -contains 'seed') { [int]$inputs.seed } else { 0 }
Write-VortexPluginLog "image-portrait invoked: prompt_len=$($prompt.Length) style=$style aspect=$aspect seed=$seed"

# Build output path
$vortexHome = $env:VORTEX_HOME
if (-not $vortexHome) { $vortexHome = Join-Path $env:APPDATA 'Vortex-OS' }
$project = if ($env:VORTEX_PROJECT) { $env:VORTEX_PROJECT } else { 'default' }
$outDir = Join-Path $vortexHome 'deliverables' $project
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$ts = Get-Date -Format 'yyyyMMddHHmmss'
$outFile = Join-Path $outDir "portrait_${ts}.png"

$size = switch ($aspect) {
    '1:1'  { @{ w = 1024; h = 1024 } }
    '3:4'  { @{ w = 1024; h = 1365 } }
    '4:3'  { @{ w = 1365; h = 1024 } }
    '16:9' { @{ w = 1920; h = 1080 } }
    '9:16' { @{ w = 1080; h = 1920 } }
    default { @{ w = 1024; h = 1024 } }
}

$args = @{
    requests = @(@{
        prompt      = $prompt
        aspect_ratio = $aspect
        style       = $style
        output_file = "portrait_${ts}.png"
    })
}
if ($seed -gt 0) { $args.requests[0].seed = $seed }

$result = Invoke-VortexWithFallback `
    -ToolName 'connector__matrix__generate_image' `
    -Args $args `
    -DownloadTo $outFile `
    -Fallback {
        param($a, $out)
        $label = if ($a.requests[0].PSObject.Properties.Name -contains 'prompt') { $a.requests[0].prompt } else { '' }
        New-VortexPlaceholderPng -OutFile $out -Width $size.w -Height $size.h -Label $label
    }

Write-VortexPluginLog "image-portrait: produced via $($result.Provider)"
Write-VortexPluginOutput @{ file = $result.File; width = $size.w; height = $size.h; style = $style; provider = $result.Provider }
