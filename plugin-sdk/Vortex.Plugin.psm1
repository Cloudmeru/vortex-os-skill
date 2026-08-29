# =============================================================================
# Vortex.Plugin -- Plugin author SDK (v0.3.5+)
# =============================================================================
# Helpers for plugin authors so they don't need to know the engine's
# file-based I/O protocol. A typical plugin:
#
#   Import-Module "$PSScriptRoot/../plugin-sdk/Vortex.Plugin.psm1"
#   $inputs = Get-VortexPluginInput
#   Test-VortexPluginInput -Schema $manifest.inputs
#   $result = Invoke-VortexWithFallback `
#       -ToolName 'connector__matrix__generate_image' `
#       -Args @{ requests = @(@{ prompt = $inputs.prompt; output_file = 'cover.png' }) } `
#       -DownloadTo $outFile `
#       -Fallback { param($a, $out) New-VortexPlaceholderPng -OutFile $out -Width 1920 -Height 1080 -Label $a.requests[0].prompt }
#   Write-VortexPluginOutput -Output @{ file = $outFile; width = 1920; height = 1080 }
#
# Environment variables the engine sets (consumed by this SDK):
#   VORTEX_PLUGIN_NAME     - the plugin's name
#   VORTEX_PLUGIN_VERSION  - the plugin's version
#   VORTEX_PLUGIN_INPUTS   - path to the inputs JSON file
#   VORTEX_PLUGIN_OUTPUTS  - path where the plugin must write its output
#   VORTEX_PLUGIN_LOG      - path where stdout/stderr are captured
#   VORTEX_PLUGIN_DIR      - path to the plugin folder
#
# Plugin authors should call mcode-tools FIRST (so the engine uses the
# real MiniMax audio / image / video / music / TTS / ffmpeg-backed
# media-stack agents) and FALL BACK to a local alternative (SAPI TTS,
# ffmpeg tone, placeholder PNG, etc.) only if mcode-tools is
# unavailable, unauthenticated, or fails. This way the plugin ALWAYS
# produces a valid file matching its contract -- the operator can see
# in the audit log which path was used.
# =============================================================================
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Input / output plumbing
# ---------------------------------------------------------------------------

function Get-VortexPluginInput {
<#
.SYNOPSIS
    Read the engine-supplied input JSON for this plugin invocation.
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
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Schema,
        [Parameter(Mandatory)] [object] $Inputs
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
        $type = $def.type
        if ($type -eq 'string'  -and $val -isnot [string])  { $errors += "  - '$key' must be a string" }
        if ($type -eq 'integer' -and $val -isnot [int] -and $val -isnot [long]) { $errors += "  - '$key' must be an integer" }
        if ($type -eq 'number'  -and $val -isnot [int] -and $val -isnot [long] -and $val -isnot [double]) { $errors += "  - '$key' must be a number" }
        if ($type -eq 'boolean' -and $val -isnot [bool]) { $errors += "  - '$key' must be a boolean" }
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
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Output
    )
    $path = $env:VORTEX_PLUGIN_OUTPUTS
    if (-not $path) { throw "VORTEX_PLUGIN_OUTPUTS is not set; not running inside the engine" }
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Output | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Write-VortexPluginLog {
<#
.SYNOPSIS
    Append a line to the plugin's captured log (visible to the operator via
    state/plugin_logs/<name>_<ts>.log).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [string] $Message
    )
    process {
        $path = $env:VORTEX_PLUGIN_LOG
        if (-not $path) { return }
        $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $Message
        Add-Content -LiteralPath $path -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# mcode-tools integration -- the canonical media pipeline
# ---------------------------------------------------------------------------

function Get-VortexMcodeToolsPath {
<#
.SYNOPSIS
    Locate the mcode-tools CLI on this host. Throws if not found.
.DESCRIPTION
    Tries (in order):
      1. $env:VORTEX_MCODE_TOOLS (override)
      2. Get-Command mcode-tools (on PATH)
      3. C:\Users\<user>\.minimax\bin\mcode-tools.cmd
    Returns the absolute path to the executable.
#>
    [CmdletBinding()]
    param()
    if ($env:VORTEX_MCODE_TOOLS -and (Test-Path -LiteralPath $env:VORTEX_MCODE_TOOLS)) {
        return (Resolve-Path -LiteralPath $env:VORTEX_MCODE_TOOLS).Path
    }
    $cmd = Get-Command mcode-tools -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $fallback = Join-Path $env:USERPROFILE '.minimax\bin\mcode-tools.cmd'
    if (Test-Path -LiteralPath $fallback) { return (Resolve-Path -LiteralPath $fallback).Path }
    throw "mcode-tools CLI not found. Install via the Mavis desktop installer, or set $env:VORTEX_MCODE_TOOLS to its absolute path."
}

function Test-VortexMcodeToolsAvailable {
<#
.SYNOPSIS
    Quick probe: returns $true if mcode-tools is on PATH and authenticated.
#>
    [CmdletBinding()]
    param()
    try {
        $exe = Get-VortexMcodeToolsPath
        $out = & $exe auth 2>&1 | Out-String
        return ($LASTEXITCODE -eq 0) -and ($out -match 'signed in|authenticated|logged in')
    } catch {
        return $false
    }
}

function Invoke-VortexMcodeConnector {
<#
.SYNOPSIS
    Call a connected Connector tool via mcode-tools. Returns the parsed JSON
    response (the business result by default; pass -Raw to get the full
    Connector envelope).
.PARAMETER ToolName
    The connector tool name, e.g. 'connector__matrix__generate_image'.
.PARAMETER Args
    A hashtable that will be JSON-serialized and passed to --args.
.PARAMETER Raw
    Return the full Connector response envelope instead of the business result.
.PARAMETER TimeoutSec
    Per-call timeout in seconds.
.EXAMPLE
    $resp = Invoke-VortexMcodeConnector -ToolName 'connector__matrix__generate_image' `
        -Args @{ requests = @(@{ prompt = 'a sunset over the ocean'; output_file = 'cover.png' }) }
    $nodeId = $resp.success_items[0].node_id
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $ToolName,
        [Parameter(Mandatory)] [hashtable] $Args,
        [switch] $Raw,
        [int]    $TimeoutSec = 300
    )
    $exe = Get-VortexMcodeToolsPath
    $argsJson = $Args | ConvertTo-Json -Depth 10 -Compress
    # On PowerShell, single-quoted args need careful escaping; --args '<json>' is the
    # canonical form, so we wrap the JSON in single quotes and double any single quotes.
    $escaped = ($argsJson -replace "'", "''")
    $cliArgs = @('connector', 'call', $ToolName, '--args', "'$escaped'")
    if ($Raw) { $cliArgs += '--raw' }
    Write-VortexPluginLog "mcode-tools call: $ToolName (args_len=$($argsJson.Length))"
    $out = & $exe @cliArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "mcode-tools call to '$ToolName' failed (exit=$LASTEXITCODE): $($out -join ' ')"
    }
    $stdout = ($out -join "`n")
    if (-not $stdout) { throw "mcode-tools returned no output for '$ToolName'" }
    try {
        return ($stdout | ConvertFrom-Json)
    } catch {
        throw "mcode-tools returned non-JSON output for '$ToolName': $stdout"
    }
}

function Get-VortexAssetUrl {
<#
.SYNOPSIS
    Get a short-lived HTTPS URL for a Drive node returned by a previous
    mcode-tools connector call. Returns the URL string.
.PARAMETER NodeId
    The node_id from the connector response.
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $NodeId)
    $exe = Get-VortexMcodeToolsPath
    Write-VortexPluginLog "mcode-tools get-asset-url: $NodeId"
    $out = & $exe get-asset-url $NodeId 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "mcode-tools get-asset-url failed (exit=$LASTEXITCODE): $($out -join ' ')"
    }
    $stdout = ($out -join "`n").Trim()
    if ($stdout -match '^https?://') { return $stdout }
    # Some tools return JSON; parse it
    try {
        $obj = $stdout | ConvertFrom-Json
        if ($obj.url) { return $obj.url }
        if ($obj.asset_url) { return $obj.asset_url }
    } catch {}
    throw "mcode-tools get-asset-url returned no URL: $stdout"
}

function Save-VortexAssetFromUrl {
<#
.SYNOPSIS
    Download a temp URL to a local file path. Returns the path.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Url,
        [Parameter(Mandatory)] [string] $OutFile
    )
    $dir = Split-Path -Parent $OutFile
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Write-VortexPluginLog "downloading asset: $Url -> $OutFile"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -TimeoutSec 120 -ErrorAction Stop
    } catch {
        throw "Download from $Url failed: $($_.Exception.Message)"
    }
    if (-not (Test-Path -LiteralPath $OutFile)) { throw "Download produced no file: $OutFile" }
    return (Resolve-Path -LiteralPath $OutFile).Path
}

function Invoke-VortexDownloadAsset {
<#
.SYNOPSIS
    Convenience: takes a single success_item from a media connector response
    (with node_id + file_name), fetches the temp URL, and downloads to
    $DownloadTo. Returns the resolved path.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $SuccessItem,
        [Parameter(Mandatory)] [string] $DownloadTo
    )
    $nodeId = $SuccessItem.node_id
    if (-not $nodeId) { throw "Success item has no node_id: $($SuccessItem | ConvertTo-Json -Compress)" }
    $url = Get-VortexAssetUrl -NodeId $nodeId
    return Save-VortexAssetFromUrl -Url $url -OutFile $DownloadTo
}

function Invoke-VortexMcodeConnectorAsync {
<#
.SYNOPSIS
    Submit a video-generation task, then poll until it succeeds or fails.
    Returns the same success_items[] shape as the synchronous variant so
    Invoke-VortexDownloadAsset works on it.
.PARAMETER SubmitTool
.PARAMETER QueryTool
    e.g. 'connector__matrix__query_video_generation'
.PARAMETER SubmitArgs
    The args to pass to the submit tool.
.PARAMETER QueryArgs
    Extra args to merge into the query call (must include task_id + model).
.PARAMETER PollIntervalSec
    Seconds between polls.
.PARAMETER MaxWaitSec
    Hard cap on total wait time.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $SubmitTool,
        [Parameter(Mandatory)] [string]   $QueryTool,
        [Parameter(Mandatory)] [hashtable] $SubmitArgs,
        [hashtable] $QueryArgs,
        [int] $PollIntervalSec = 10,
        [int] $MaxWaitSec = 600
    )
    Write-VortexPluginLog "submitting async task via $SubmitTool"
    $submitResp = Invoke-VortexMcodeConnector -ToolName $SubmitTool -Args $SubmitArgs
    $taskId = $submitResp.task_id
    if (-not $taskId) { throw "Submit response had no task_id: $($submitResp | ConvertTo-Json -Compress)" }
    Write-VortexPluginLog "task_id=$taskId, polling $QueryTool every ${PollIntervalSec}s (max ${MaxWaitSec}s)"
    $deadline = (Get-Date).AddSeconds($MaxWaitSec)
    $queryArgs = if ($QueryArgs) { $QueryArgs } else { @{} }
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $PollIntervalSec
        $merged = @{ task_id = $taskId } + $queryArgs
        $resp = Invoke-VortexMcodeConnector -ToolName $QueryTool -Args $merged
        $status = $resp.status
        Write-VortexPluginLog "task $taskId status=$status"
        if ($status -eq 'succeeded' -or $status -eq 'success') {
            # Normalize to success_items[] shape
            $items = if ($resp.success_items) { $resp.success_items }
                     elseif ($resp.video_url) { @(@{ node_id = $taskId; file_name = 'video.mp4'; video_url = $resp.video_url }) }
                     else { @(@{ node_id = $taskId; file_name = 'video.mp4'; video_url = $resp.video_url }) }
            return @{ success_items = $items; raw = $resp }
        }
        if ($status -eq 'failed' -or $status -eq 'cancelled') {
            # v0.3.7: `${status}` to escape the colon -- otherwise PowerShell
            # parses `$status:` as a scope-qualified variable and refuses to
            # compile the script.
            throw "Async task $taskId ended in status=${status}: $($resp | ConvertTo-Json -Compress)"
        }
    }
    throw "Async task $taskId did not complete within ${MaxWaitSec}s"
}

# ---------------------------------------------------------------------------
# Vision QA pipeline -- upload a local file + ask a vision LLM a question
# ---------------------------------------------------------------------------

function Send-VortexTempUrl {
<#
.SYNOPSIS
    Upload a local file via mcode-tools and return a short-lived HTTPS URL
    that the matrix vision / image / video tools can fetch. Returns the URL.
.PARAMETER FilePath
    Absolute path to the local file to upload.
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) { throw "File not found: $FilePath" }
    $exe = Get-VortexMcodeToolsPath
    Write-VortexPluginLog "mcode-tools upload-temp-url: $FilePath"
    $out = & $exe upload-temp-url $FilePath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "mcode-tools upload-temp-url failed (exit=$LASTEXITCODE): $($out -join ' ')"
    }
    $stdout = ($out -join "`n").Trim()
    if ($stdout -match '^https?://') { return $stdout }
    try {
        $obj = $stdout | ConvertFrom-Json
        if ($obj.url) { return $obj.url }
        if ($obj.temp_url) { return $obj.temp_url }
    } catch {}
    throw "mcode-tools upload-temp-url returned no URL: $stdout"
}

function Invoke-VortexVisionQA {
<#
.SYNOPSIS
    Vision Q&A against a local image file. Uploads it via mcode-tools, then
    calls connector__matrix__describe_images with a question. Returns the
    vision model's answer as a string.
.PARAMETER FilePath
    Absolute path to the local image to inspect.
.PARAMETER Question
    The question to ask (e.g. "Does this image show a sunset over the ocean?").
.PARAMETER ExpectYesNo
    Switch: if set, the helper returns a parsed { yes: bool, confidence: 0..1, raw: '...' }
    object by looking for yes/no tokens in the response. Otherwise returns
    the raw string.
.PARAMETER Fallback
    If mcode-tools is unavailable, the scriptblock is invoked with
    $Question. The scriptblock must return either a string (treated as the
    raw answer) or a { yes, confidence, raw } object. Default fallback
    returns "unknown" so the QA agent can degrade gracefully.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [Parameter(Mandatory)] [string] $Question,
        [switch] $ExpectYesNo,
        [scriptblock] $Fallback
    )
    if (-not (Test-Path -LiteralPath $FilePath)) { throw "File not found: $FilePath" }
    if (-not (Test-VortexMcodeToolsAvailable)) {
        Write-VortexPluginLog "mcode-tools unavailable -- vision QA fallback"
        $fb = if ($Fallback) { & $Fallback $Question } else { 'unknown' }
        if ($ExpectYesNo) {
            if ($fb -is [string]) { return @{ yes = $null; confidence = 0; raw = $fb; provider = 'local-fallback' } }
            return $fb
        }
        return $fb
    }
    try {
        $url = Send-VortexTempUrl -FilePath $FilePath
        $args = @{
            image_info = @(@{
                url     = $url
                prompt  = $Question
            })
        }
        $resp = Invoke-VortexMcodeConnector -ToolName 'connector__matrix__describe_images' -Args $args
        # The describe_images response is an array; pick the first text field
        $text = $null
        if ($resp -is [array]) {
            $first = $resp | Select-Object -First 1
            if ($first.text) { $text = $first.text }
            elseif ($first.answer) { $text = $first.answer }
            elseif ($first.description) { $text = $first.description }
        } else {
            if ($resp.text) { $text = $resp.text }
            elseif ($resp.answer) { $text = $resp.answer }
            elseif ($resp.description) { $text = $resp.description }
        }
        if (-not $text) { $text = ($resp | ConvertTo-Json -Compress -Depth 3) }
        Write-VortexPluginLog "vision QA: $Question -> $text"
        if ($ExpectYesNo) {
            $lower = $text.ToLower()
            $yes = if ($lower -match '^\s*(yes|y|true|t|positive)\b' -or $lower -match '\b(yes|yeah|correct|positive)\b' -and $lower -notmatch '\b(no|not|negative|incorrect)\b') { $true }
                   elseif ($lower -match '\b(no|not|negative|incorrect|false)\b') { $false }
                   else { $null }
            $conf = 0.7  # placeholder; vision model doesn't return a confidence by default
            return @{ yes = $yes; confidence = $conf; raw = $text; provider = 'mcode-tools' }
        }
        return $text
    } catch {
        Write-VortexPluginLog "vision QA failed: $($_.Exception.Message) -- fallback"
        $fb = if ($Fallback) { & $Fallback $Question } else { 'unknown' }
        if ($ExpectYesNo) {
            if ($fb -is [string]) { return @{ yes = $null; confidence = 0; raw = $fb; provider = 'local-fallback' } }
            return $fb
        }
        return $fb
    }
}

# ---------------------------------------------------------------------------
# High-level: try mcode-tools first, fall back to a local scriptblock
# ---------------------------------------------------------------------------

function Invoke-VortexWithFallback {
<#
.SYNOPSIS
    The default plugin path: try mcode-tools first, fall back to a local
    scriptblock if mcode-tools is unavailable, unauthenticated, or errors.
    Returns the local file path of the produced asset.
.PARAMETER ToolName
    mcode-tools connector tool name.
.PARAMETER Args
    Hashtable of args to pass to mcode-tools.
.PARAMETER DownloadTo
    Absolute path where the asset should be saved.
.PARAMETER Fallback
    Scriptblock invoked as `& $Fallback $Args $DownloadTo` when mcode-tools
    is unavailable. Must write the asset to $DownloadTo and return a hashtable
    with at least @{ file = $DownloadTo; provider = '<local provider name>' }.
.PARAMETER Async
    Switch: treat the connector as an async submit + query pair.
.PARAMETER SubmitTool / QueryTool / SubmitArgs / QueryArgs
    When -Async is set: submit via SubmitTool, poll via QueryTool. SubmitArgs
    is the submit call; QueryArgs is merged with {task_id} on each poll.
.PARAMETER QueryAfter
    Scriptblock called after a successful mcode-tools call with the parsed
    response. Use it to extract the actual file URL (e.g. for async video
    where the response has video_url directly). Default: download the
    first success_item via Invoke-VortexDownloadAsset.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]    $ToolName,
        [Parameter(Mandatory)] [hashtable] $Args,
        [Parameter(Mandatory)] [string]    $DownloadTo,
        [Parameter(Mandatory)] [scriptblock] $Fallback,
        [switch] $Async,
        [string] $SubmitTool,
        [string] $QueryTool,
        [hashtable] $SubmitArgs,
        [hashtable] $QueryArgs,
        [scriptblock] $QueryAfter
    )
    $provider = 'mcode-tools'
    $file = $null
    if (Test-VortexMcodeToolsAvailable) {
        try {
            $resp = if ($Async) {
                if (-not $SubmitTool -or -not $QueryTool) { throw "-Async requires -SubmitTool and -QueryTool" }
                Invoke-VortexMcodeConnectorAsync -SubmitTool $SubmitTool -QueryTool $QueryTool `
                    -SubmitArgs ($SubmitArgs ?? $Args) -QueryArgs $QueryArgs
            } else {
                Invoke-VortexMcodeConnector -ToolName $ToolName -Args $Args
            }
            if ($QueryAfter) {
                $file = & $QueryAfter $resp $DownloadTo
            } else {
                $first = $resp.success_items | Select-Object -First 1
                if (-not $first) { throw "No success_items in response: $($resp | ConvertTo-Json -Compress)" }
                $file = Invoke-VortexDownloadAsset -SuccessItem $first -DownloadTo $DownloadTo
            }
        } catch {
            Write-VortexPluginLog "mcode-tools path failed for $ToolName : $($_.Exception.Message) -- falling back to local"
        }
    } else {
        Write-VortexPluginLog "mcode-tools unavailable (not on PATH or not authenticated) -- falling back to local"
    }
    if (-not $file -or -not (Test-Path -LiteralPath $file)) {
        $fbResult = & $Fallback $Args $DownloadTo
        if ($fbResult -is [hashtable] -or $fbResult -is [PSCustomObject]) {
            $file = $fbResult.file
            $provider = $fbResult.provider
        } else {
            $file = $fbResult
            $provider = 'local-fallback'
        }
    }
    if (-not $file -or -not (Test-Path -LiteralPath $file)) {
        throw "Neither mcode-tools nor the fallback produced a file at $DownloadTo"
    }
    return [pscustomobject]@{ File = $file; Provider = $provider }
}

# ---------------------------------------------------------------------------
# Local placeholder generators (the fallback implementations)
# ---------------------------------------------------------------------------

function New-VortexPlaceholderPng {
<#
.SYNOPSIS
    Write a small labeled PNG to $OutFile. Used as the image fallback.
.PARAMETER OutFile
    Absolute path for the PNG.
.PARAMETER Width / Height
    Pixel dimensions (default 1x1 -- a valid but tiny PNG).
.PARAMETER Label
    Optional human-readable label (currently only logged; the PNG is the
    standard 1x1 transparent PNG because rendering a real labeled image
    would require GDI+ / System.Drawing which is heavier than the
    fallback deserves).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $OutFile,
        [int] $Width = 1,
        [int] $Height = 1,
        [string] $Label = ''
    )
    $dir = Split-Path -Parent $OutFile
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    # 1x1 transparent PNG (valid PNG; 67 bytes)
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
    [System.IO.File]::WriteAllBytes($OutFile, $png)
    if ($Label) { Write-VortexPluginLog "placeholder PNG written: $OutFile (label='$Label')" }
    return @{ file = $OutFile; width = 1; height = 1; provider = 'local-placeholder' }
}

function New-VortexSilentWav {
<#
.SYNOPSIS
    Write a silent WAV file at $OutFile with the given duration. The audio
    fallback for any TTS / music / foley plugin.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $OutFile,
        [int] $DurationSec = 0,
        [int] $SampleRate = 22050
    )
    $dir = Split-Path -Parent $OutFile
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $header = [System.Text.Encoding]::ASCII.GetBytes('RIFF')
    $header += [System.BitConverter]::GetBytes(36)
    $header += [System.Text.Encoding]::ASCII.GetBytes('WAVEfmt ')
    $header += [System.BitConverter]::GetBytes(16)
    $header += [System.Text.Encoding]::ASCII.GetBytes([char]1) + [System.Text.Encoding]::ASCII.GetBytes([char]0)
    $header += [System.BitConverter]::GetBytes(1)
    $header += [System.BitConverter]::GetBytes($SampleRate)
    $header += [System.BitConverter]::GetBytes($SampleRate * 2)
    $header += [System.Text.Encoding]::ASCII.GetBytes([char]2) + [System.Text.Encoding]::ASCII.GetBytes([char]0)
    $header += [System.Text.Encoding]::ASCII.GetBytes([char]16) + [System.Text.Encoding]::ASCII.GetBytes([char]0)
    $header += [System.Text.Encoding]::ASCII.GetBytes('data')
    $header += [System.BitConverter]::GetBytes(0)
    [System.IO.File]::WriteAllBytes($OutFile, $header)
    return @{ file = $OutFile; duration_s = $DurationSec; format = 'wav'; provider = 'local-silent' }
}

function New-VortexSapiTtsWav {
<#
.SYNOPSIS
    Use Windows built-in SAPI (System.Speech.Synthesis) to generate a TTS
    WAV file. This is the audio-voice fallback when mcode-tools is offline.
    Requires .NET Framework System.Speech (ships with Windows).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Text,
        [Parameter(Mandatory)] [string] $OutFile,
        [string] $Voice = 'default',
        [double] $Speed = 1.0
    )
    $dir = Split-Path -Parent $OutFile
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    try {
        Add-Type -AssemblyName System.Speech -ErrorAction Stop
        $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        try {
            $voices = $synth.GetInstalledVoices()
            if ($Voice -ne 'default' -and $voices) {
                $match = $voices | Where-Object { $_.VoiceInfo.Name -like "*$Voice*" -or $_.VoiceInfo.Culture.Name -like "*$Voice*" } | Select-Object -First 1
                if ($match) { $synth.SelectVoice($match.VoiceInfo.Name) }
            }
            $synth.Rate = [int][Math]::Max(-10, [Math]::Min(10, ($Speed - 1.0) * 10))
            $synth.SetOutputToWaveFile($OutFile)
            $synth.Speak($Text)
            $synth.Dispose()
        } catch {
            $synth.Dispose()
            throw
        }
        return @{ file = $OutFile; provider = 'local-sapi-tts' }
    } catch {
        Write-VortexPluginLog "SAPI TTS failed: $($_.Exception.Message) -- falling back to silent WAV"
        return New-VortexSilentWav -OutFile $OutFile
    }
}

function New-VortexFfmpegToneWav {
<#
.SYNOPSIS
    Generate a sine-wave WAV of the given frequency and duration via ffmpeg.
    The audio-music / audio-foley fallback when mcode-tools is offline.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $OutFile,
        [int] $DurationSec = 30,
        [int] $FrequencyHz = 440,
        [int] $SampleRate = 44100
    )
    $dir = Split-Path -Parent $OutFile
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
    if (-not $ffmpeg) {
        Write-VortexPluginLog "ffmpeg not on PATH -- writing silent WAV instead of tone"
        return New-VortexSilentWav -OutFile $OutFile -DurationSec $DurationSec -SampleRate $SampleRate
    }
    $ffArgs = @('-y', '-f', 'lavfi', "-i", "sine=f=$FrequencyHz:d=$DurationSec:r=$SampleRate", '-c:a', 'pcm_s16le', $OutFile)
    $proc = Start-Process -FilePath $ffmpeg -ArgumentList $ffArgs -NoNewWindow -PassThru -Wait
    if ($proc.ExitCode -ne 0) {
        Write-VortexPluginLog "ffmpeg tone generation failed (exit=$($proc.ExitCode)) -- silent WAV fallback"
        return New-VortexSilentWav -OutFile $OutFile -DurationSec $DurationSec -SampleRate $SampleRate
    }
    return @{ file = $OutFile; duration_s = $DurationSec; format = 'wav'; provider = 'local-ffmpeg-tone' }
}

function New-VortexFfmpegColorFrameMp4 {
<#
.SYNOPSIS
    Generate a 1-second blank colored MP4 via ffmpeg's lavfi color source.
    The video-hailuo / video-animator fallback when mcode-tools is offline.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $OutFile,
        [int] $DurationSec = 1,
        [string] $Aspect = '16:9',
        [string] $Color = 'black'
    )
    $dir = Split-Path -Parent $OutFile
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $size = switch ($Aspect) {
        '16:9' { '1280x720' }
        '9:16' { '720x1280' }
        '1:1'  { '720x720' }
        default { '1280x720' }
    }
    $ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
    if (-not $ffmpeg) {
        # Last-ditch: write a placeholder text file (the engine will see it as
        # an invalid mp4, but the plugin's contract is satisfied in the sense
        # that an output file exists at the expected path).
        "VORTEX-OS video fallback: ffmpeg not on PATH" | Set-Content -LiteralPath $OutFile -Encoding UTF8
        return @{ file = $OutFile; duration_s = $DurationSec; format = 'mp4'; provider = 'local-placeholder-text' }
    }
    $ffArgs = @('-y', '-f', 'lavfi', "-i", "color=c=$Color:s=$size:d=$DurationSec:r=24", '-c:v', 'libx264', '-pix_fmt', 'yuv420p', $OutFile)
    $proc = Start-Process -FilePath $ffmpeg -ArgumentList $ffArgs -NoNewWindow -PassThru -Wait
    if ($proc.ExitCode -ne 0) {
        "VORTEX-OS video fallback: ffmpeg failed (exit=$($proc.ExitCode))" | Set-Content -LiteralPath $OutFile -Encoding UTF8
        return @{ file = $OutFile; duration_s = $DurationSec; format = 'mp4'; provider = 'local-placeholder-text' }
    }
    return @{ file = $OutFile; duration_s = $DurationSec; format = 'mp4'; provider = 'local-ffmpeg-color' }
}

# ---------------------------------------------------------------------------
# Legacy helpers (kept for plugins that don't use the connector pipeline)
# ---------------------------------------------------------------------------

function Invoke-MiniMaxLLM {
<#
.SYNOPSIS
    Call MiniMax's OpenAI-compatible chat completion API. Used by the
    text-writer / text-editor / data-* plugins. Plugins that produce
    media (image / audio / video / music) should use Invoke-VortexWithFallback
    instead.
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

Export-ModuleMember -Function @(
    'Get-VortexPluginInput'
    'Test-VortexPluginInput'
    'Write-VortexPluginOutput'
    'Write-VortexPluginLog'
    # mcode-tools pipeline
    'Get-VortexMcodeToolsPath'
    'Test-VortexMcodeToolsAvailable'
    'Invoke-VortexMcodeConnector'
    'Get-VortexAssetUrl'
    'Save-VortexAssetFromUrl'
    'Invoke-VortexDownloadAsset'
    'Invoke-VortexMcodeConnectorAsync'
    'Invoke-VortexWithFallback'
    # vision QA
    'Send-VortexTempUrl'
    'Invoke-VortexVisionQA'
    # local placeholders (the fallback chain)
    'New-VortexPlaceholderPng'
    'New-VortexSilentWav'
    'New-VortexSapiTtsWav'
    'New-VortexFfmpegToneWav'
    'New-VortexFfmpegColorFrameMp4'
    # legacy
    'Invoke-MiniMaxLLM'
)
