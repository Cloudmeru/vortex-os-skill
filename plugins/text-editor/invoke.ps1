# text-editor plugin — polish / rephrase / summarize
# v0.2.0 reference plugin
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force

$inputs = Get-VortexPluginInput
$action = $inputs.action
$targetHint = if ($inputs.PSObject.Properties.Name -contains 'target' -and $inputs.target) { "Target register: $($inputs.target)." } else { '' }

$prompts = @{
    'polish'       = "Polish the following prose for clarity, flow, and rhythm. Preserve the voice. $targetHint"
    'rephrase'     = "Rephrase the following text with fresh wording. Preserve the meaning. $targetHint"
    'shorten'      = "Shorten the following text by ~50% while preserving the key points. $targetHint"
    'expand'       = "Expand the following text with more detail, examples, and texture. $targetHint"
    'summarize'    = "Summarize the following text in 2-3 sentences, capturing the essence. $targetHint"
    'fix-grammar'  = "Fix any grammar, spelling, and punctuation errors in the following text. Preserve the voice. $targetHint"
}
$sys = $prompts[$action]
if (-not $sys) { throw "Unknown action: $action. Must be one of: $($prompts.Keys -join ', ')" }

Write-VortexPluginLog "text-editor invoked: action=$action input_len=$($inputs.text.Length)"

try {
    $text = Invoke-MiniMaxLLM -Prompt $inputs.text -SystemPrompt $sys -Model 'MiniMax-Text-01' -MaxTokens 2048
    $wc = ($text -split '\s+').Count
    Write-VortexPluginOutput @{
        text       = $text
        action     = $action
        word_count = $wc
    }
} catch {
    Write-VortexPluginLog "ERROR: $($_.Exception.Message)"
    throw
}
