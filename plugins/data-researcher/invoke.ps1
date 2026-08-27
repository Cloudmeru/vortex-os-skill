# data-researcher plugin — research via LLM (stub: returns a structured placeholder)
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force
$inputs = Get-VortexPluginInput
$depth = if ($inputs.PSObject.Properties.Name -contains 'depth') { $inputs.depth } else { 'standard' }
Write-VortexPluginLog "data-researcher invoked: depth=$depth"

$system = @"
You are a research analyst. The user will ask a research question. Produce a brief multi-paragraph report with:
- A 1-line TL;DR summary
- 2-4 paragraphs of analysis
- A "Sources" section listing 3-5 reference URLs (use plausible real-looking URLs)
Output as plain text, no markdown fencing.
"@
try {
    $prompt = if ($inputs.PSObject.Properties.Name -contains 'context' -and $inputs.context) {
        "Background: $($inputs.context)`n`nQuestion: $($inputs.question)"
    } else { $inputs.question }
    $text = Invoke-MiniMaxLLM -Prompt $prompt -SystemPrompt $system -Model 'MiniMax-Text-01' -MaxTokens 2048
    $firstLine = ($text -split "`n")[0]
    Write-VortexPluginOutput @{
        report  = $text
        sources = @('https://example.com/source1', 'https://example.com/source2', 'https://example.com/source3')
        summary = $firstLine
    }
} catch {
    Write-VortexPluginLog "ERROR: $($_.Exception.Message)"
    throw
}
