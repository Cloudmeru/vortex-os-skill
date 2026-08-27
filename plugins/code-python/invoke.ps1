# code-python plugin — Python code generation
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force
$inputs = Get-VortexPluginInput
$style = if ($inputs.PSObject.Properties.Name -contains 'style') { $inputs.style } else { 'script' }
$filename = if ($inputs.PSObject.Properties.Name -contains 'filename' -and $inputs.filename) { $inputs.filename } else { 'output.py' }
Write-VortexPluginLog "code-python invoked: style=$style filename=$filename"

$system = @"
You are a senior Python engineer. Generate clean, idiomatic, well-typed Python code for the following specification.
- Match the $style style conventions
- Include all necessary imports
- Use type hints on public functions
- Add minimal docstrings on public functions
- Output ONLY the raw code; no markdown fencing, no commentary.
"@
try {
    $code = Invoke-MiniMaxLLM -Prompt $inputs.spec -SystemPrompt $system -Model 'MiniMax-Text-01' -MaxTokens 3000
    $code = $code -replace '^```(?:python|py)?\s*\n', '' -replace '\n```\s*$', ''
    $vortexHome = $env:VORTEX_HOME
    if (-not $vortexHome) { $vortexHome = Join-Path $env:APPDATA 'Vortex-OS' }
    $project = if ($env:VORTEX_PROJECT) { $env:VORTEX_PROJECT } else { 'default' }
    $outDir = Join-Path $vortexHome 'deliverables' $project 'code'
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $outFile = Join-Path $outDir $filename
    Set-Content -LiteralPath $outFile -Value $code -Encoding UTF8
    $lineCount = ($code -split "`n").Count
    Write-VortexPluginLog "wrote $lineCount lines to $outFile"
    Write-VortexPluginOutput @{ file = $outFile; filename = $filename; line_count = $lineCount }
} catch {
    Write-VortexPluginLog "ERROR: $($_.Exception.Message)"
    throw
}
