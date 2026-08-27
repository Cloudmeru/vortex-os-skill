# code-typescript plugin — TypeScript code generation
# v0.2.0 reference plugin. Wraps MiniMax-Text-01 with a code-specialist
# system prompt; writes the output as a .ts file under the project's
# deliverables dir.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force

$inputs = Get-VortexPluginInput
$framework = if ($inputs.PSObject.Properties.Name -contains 'framework') { $inputs.framework } else { 'vanilla' }
$filename = if ($inputs.PSObject.Properties.Name -contains 'filename' -and $inputs.filename) { $inputs.filename } else { 'output.ts' }

Write-VortexPluginLog "code-typescript invoked: framework=$framework filename=$filename"

$system = @"
You are a senior TypeScript engineer. Generate clean, idiomatic, well-typed TypeScript code for the following specification.
- Use the $framework framework conventions where applicable
- Include all necessary imports
- Use strict types (no `any`)
- Add minimal JSDoc on public functions
- Output ONLY the raw code; no markdown fencing, no commentary.
"@

try {
    $code = Invoke-MiniMaxLLM -Prompt $inputs.spec -SystemPrompt $system -Model 'MiniMax-Text-01' -MaxTokens 3000

    # Strip any ```typescript ... ``` fences the LLM may have added
    $code = $code -replace '^```(?:typescript|ts)?\s*\n', '' -replace '\n```\s*$', ''

    $vortexHome = $env:VORTEX_HOME
    if (-not $vortexHome) { $vortexHome = Join-Path $env:APPDATA 'Vortex-OS' }
    $project = if ($env:VORTEX_PROJECT) { $env:VORTEX_PROJECT } else { 'default' }
    $outDir = Join-Path $vortexHome 'deliverables' $project 'code'
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $outFile = Join-Path $outDir $filename
    Set-Content -LiteralPath $outFile -Value $code -Encoding UTF8

    $lineCount = ($code -split "`n").Count
    Write-VortexPluginLog "wrote $lineCount lines to $outFile"
    Write-VortexPluginOutput @{
        file       = $outFile
        filename   = $filename
        line_count = $lineCount
    }
} catch {
    Write-VortexPluginLog "ERROR: $($_.Exception.Message)"
    throw
}
