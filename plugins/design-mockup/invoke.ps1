# design-mockup plugin — UI mockup generation (stub: 1x1 PNG + design notes)
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force
$inputs = Get-VortexPluginInput
$style = if ($inputs.PSObject.Properties.Name -contains 'style') { $inputs.style } else { 'modern-minimal' }
$platform = if ($inputs.PSObject.Properties.Name -contains 'platform') { $inputs.platform } else { 'web' }
Write-VortexPluginLog "design-mockup invoked: style=$style platform=$platform"

$system = @"
You are a senior product designer. Given the design spec, write 3-4 sentences
of design notes covering typography, color palette, layout decisions, and
key component choices. Be specific to the $style style and $platform platform.
"@
try {
    $notes = Invoke-MiniMaxLLM -Prompt $inputs.spec -SystemPrompt $system -Model 'MiniMax-Text-01' -MaxTokens 800
    $vortexHome = $env:VORTEX_HOME
    if (-not $vortexHome) { $vortexHome = Join-Path $env:APPDATA 'Vortex-OS' }
    $project = if ($env:VORTEX_PROJECT) { $env:VORTEX_PROJECT } else { 'default' }
    $outDir = Join-Path $vortexHome 'deliverables' $project
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $ts = Get-Date -Format 'yyyyMMddHHmmss'
    $outFile = Join-Path $outDir "mockup_${ts}.png"
    $png = [byte[]](
        0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,
        0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
        0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
        0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
        0x89,0x00,0x00,0x00,0x0D,0x49,0x44,0x41,
        0x54,0x78,0x9C,0x63,0x00,0x01,0x00,0x00,
        0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,
        0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
        0x42,0x60,0x82
    )
    [System.IO.File]::WriteAllBytes($outFile, $png)
    Write-VortexPluginOutput @{ file = $outFile; notes = $notes }
} catch {
    Write-VortexPluginLog "ERROR: $($_.Exception.Message)"
    throw
}
