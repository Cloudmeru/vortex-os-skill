# =============================================================================
# Vortex.Plugin — Plugin author SDK (v0.2.0+)
# =============================================================================
# Helpers for plugin authors so they don't need to know the engine's
# file-based I/O protocol. A typical plugin:
#
#   Import-Module "$PSScriptRoot/../plugin-sdk/Vortex.Plugin.psm1"
#   $inputs = Get-VortexPluginInput
#   Test-VortexPluginInput -Schema $manifest.inputs
#   $result = Invoke-MiniMaxLLM -Prompt $inputs.prompt -Model 'MiniMax-Text-01'
#   Write-VortexPluginOutput -File $result.file -DurationS $result.duration_s
#
# Environment variables the engine sets (consumed by this SDK):
#   VORTEX_PLUGIN_NAME     - the plugin's name
#   VORTEX_PLUGIN_VERSION  - the plugin's version
#   VORTEX_PLUGIN_INPUTS   - path to the inputs JSON file
#   VORTEX_PLUGIN_OUTPUTS  - path where the plugin must write its output
#   VORTEX_PLUGIN_LOG      - path where stdout/stderr are captured
#   VORTEX_PLUGIN_DIR      - path to the plugin folder
# =============================================================================
$ErrorActionPreference = 'Stop'

function Get-VortexPluginInput {
<#
.SYNOPSIS
    Read the engine-supplied input JSON for this plugin invocation.
.EXAMPLE
    $inputs = Get-VortexPluginInput
    $prompt = $inputs.prompt
#>
    [CmdletBinding()]
    param()
    $path = $env:VORTEX_PLUGIN_INPUTS
    if (-not $path) { throw "VORTEX_PLUGIN_INPUTS is not set; not running inside the engine" }
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Plugin input file not found: $path"
    }
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Test-VortexPluginInput {
<#
.SYNOPSIS
    Validate the loaded input against the plugin's input schema.
.PARAMETER Schema
    The `inputs` object from plugin.json (each key has type / required / default / enum).
.EXAMPLE
    $inputs = Get-VortexPluginInput
    Test-VortexPluginInput -Schema $manifest.inputs
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Schema,
        [Parameter(Mandatory)]
        [object] $Inputs
    )
    $errors = @()
    foreach ($key in $Schema.PSObject.Properties.Name) {
        $def = $Schema.$key
        $has = $Inputs.PSObject.Properties.Name -contains $key
        $required = $def.required -eq $true
        if ($required -and -not $has) {
            $errors += "  - missing required input: '$key'"
            continue
        }
        if (-not $has) { continue }
        $val = $Inputs.$key
        # Type check (lightweight)
        $type = $def.type
        if ($type -eq 'string'  -and $val -isnot [string])  { $errors += "  - '$key' must be a string" }
        if ($type -eq 'integer' -and $val -isnot [int] -and $val -isnot [long]) { $errors += "  - '$key' must be an integer" }
        if ($type -eq 'number'  -and $val -isnot [int] -and $val -isnot [long] -and $val -isnot [double]) { $errors += "  - '$key' must be a number" }
        if ($type -eq 'boolean' -and $val -isnot [bool]) { $errors += "  - '$key' must be a boolean" }
        # Enum check
        if ($def.enum -and ($def.enum -notcontains $val)) {
            $errors += "  - '$key' must be one of: $($def.enum -join ', ')"
        }
    }
    if ($errors.Count -gt 0) {
        throw "Plugin input validation failed:`n$($errors -join "`n")"
    }
}

function Write-VortexPluginOutput {
<#
.SYNOPSIS
    Write the plugin's output JSON to the engine-expected path.
.PARAMETER Output
    A hashtable / PSCustomObject to serialize as JSON.
.EXAMPLE
    Write-VortexPluginOutput -Output @{ file = $outputPath; duration_s = 12.3 }
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Output
    )
    $path = $env:VORTEX_PLUGIN_OUTPUTS
    if (-not $path) { throw "VORTEX_PLUGIN_OUTPUTS is not set; not running inside the engine" }
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Output | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Invoke-MiniMaxLLM {
<#
.SYNOPSIS
    Call MiniMax's OpenAI-compatible chat completion API.
.PARAMETER Prompt
    The user message to send to the model.
.PARAMETER SystemPrompt
    Optional system message.
.PARAMETER Model
    Model name (default: MiniMax-Text-01).
.PARAMETER MaxTokens
    Token budget (default: 1024).
.PARAMETER ApiKey
    Override the API key. Defaults to $env:MINIMAX_API_KEY or
    $env:VORTEX_MINIMAX_API_KEY.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Prompt,
        [string] $SystemPrompt = '',
        [string] $Model = 'MiniMax-Text-01',
        [int]    $MaxTokens = 1024,
        [string] $ApiKey = ''
    )
    if (-not $ApiKey) {
        $ApiKey = if ($env:MINIMAX_API_KEY) { $env:MINIMAX_API_KEY }
                  elseif ($env:VORTEX_MINIMAX_API_KEY) { $env:VORTEX_MINIMAX_API_KEY }
                  else { throw "No MiniMax API key. Set $env:MINIMAX_API_KEY or pass -ApiKey." }
    }
    $endpoint = 'https://api.minimax.io/v1/chat/completions'
    $body = @{
        model       = $Model
        max_tokens  = $MaxTokens
        messages    = @(
            if ($SystemPrompt) { @{ role = 'system'; content = $SystemPrompt } }
            @{ role = 'user'; content = $Prompt }
        )
    }
    $json = $body | ConvertTo-Json -Depth 10
    try {
        $response = Invoke-RestMethod -Uri $endpoint -Method Post `
            -Headers @{ 'Authorization' = "Bearer $ApiKey"; 'Content-Type' = 'application/json' } `
            -Body $json -TimeoutSec 60
    } catch {
        throw "MiniMax API call failed: $($_.Exception.Message)"
    }
    if (-not $response.choices -or $response.choices.Count -eq 0) {
        throw "MiniMax returned no choices. Raw: $($response | ConvertTo-Json -Depth 3)"
    }
    return $response.choices[0].message.content
}

function Write-VortexPluginLog {
<#
.SYNOPSIS
    Append a line to the plugin's captured log (visible to the operator via
    state/plugin_logs/<name>_<ts>.log).
.EXAMPLE
    Write-VortexPluginLog "starting render of $prompt"
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $Message
    )
    process {
        $path = $env:VORTEX_PLUGIN_LOG
        if (-not $path) { return }
        $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $Message
        Add-Content -LiteralPath $path -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function @(
    'Get-VortexPluginInput'
    'Test-VortexPluginInput'
    'Write-VortexPluginOutput'
    'Invoke-MiniMaxLLM'
    'Write-VortexPluginLog'
)
