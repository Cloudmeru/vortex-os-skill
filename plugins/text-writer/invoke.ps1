# text-writer plugin — long-form prose generation
# v0.2.0 reference plugin
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force

$inputs = Get-VortexPluginInput
$style = if ($inputs.PSObject.Properties.Name -contains 'style') { $inputs.style } else { 'literary' }
$words = if ($inputs.PSObject.Properties.Name -contains 'word_target') { $inputs.word_target } else { 800 }
$system = if ($inputs.PSObject.Properties.Name -contains 'system' -and $inputs.system) {
    $inputs.system
} else {
    "You are a skilled prose writer. Match the requested style: $style. Target approximately $words words."
}

Write-VortexPluginLog "text-writer invoked: style=$style words=$words"

try {
    $text = Invoke-MiniMaxLLM -Prompt $inputs.prompt -SystemPrompt $system -Model 'MiniMax-Text-01' -MaxTokens ([int]($words * 1.5))
    $wc = ($text -split '\s+').Count
    Write-VortexPluginOutput @{
        text       = $text
        word_count = $wc
        model      = 'MiniMax-Text-01'
    }
} catch {
    Write-VortexPluginLog "ERROR: $($_.Exception.Message)"
    throw
}
