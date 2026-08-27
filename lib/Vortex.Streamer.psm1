# =============================================================================
# Vortex.Streamer - PowerShell streamer for VORTEX-OS (PRD-14, v0.2.2)
# =============================================================================
# Subscribes to the engine's in_progress/<task_id>/ directory via
# FileSystemWatcher. Each new .partial file is surfaced to the operator
# with a y/n/q prompt:
#   y = open the file in the OS default handler
#   n = skip
#   q = stop watching (the dispatch continues in the background)
#
# Also exposes Send-VortexHint to append operator notes to .hints.jsonl
# so the next dispatch in the chain sees them.
# =============================================================================
$ErrorActionPreference = 'Stop'

function Get-VortexStream {
<#
.SYNOPSIS
    List the in-progress dispatches the engine is currently tracking.
.DESCRIPTION
    Reads <VORTEX_HOME>/state/in_progress/ and returns one record per
    task that has a .started file. No FileSystemWatcher -- just a
    snapshot of the current state.
.EXAMPLE
    PS> Get-VortexStream
#>
    [CmdletBinding()]
    param()
    $vortexHome = if ($env:VORTEX_HOME) { $env:VORTEX_HOME } else { (Join-Path $env:APPDATA 'Vortex-OS') }
    $inProgress = Join-Path $vortexHome 'state' 'in_progress'
    if (-not (Test-Path $inProgress)) { return @() }
    $results = @()
    Get-ChildItem -LiteralPath $inProgress -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $taskId = $_.Name
        $startedFile = Join-Path $_.FullName '.started'
        $startedAt = $null
        if (Test-Path $startedFile) {
            try {
                $started = Get-Content -LiteralPath $startedFile -Raw | ConvertFrom-Json
                $startedAt = [datetime]'1970-01-01 00:00:00Z'
                $startedAt = $startedAt.AddSeconds([int]$started.started_at).ToLocalTime()
            } catch {}
        }
        $partials = @(Get-ChildItem -LiteralPath $_.FullName -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '*.partial*' })
        $results += [PSCustomObject]@{
            TaskId     = $taskId
            StartedAt  = $startedAt
            Path       = $_.FullName
            PartialCount = $partials.Count
        }
    }
    return $results
}

function Start-VortexStream {
<#
.SYNOPSIS
    Attach to an in-progress dispatch and print each new .partial file
    as it appears. Prompts y/n/q per file.
.PARAMETER TaskId
    The dispatch to watch.
.PARAMETER AutoOpen
    If set, auto-open each .partial file (no prompt).
.PARAMETER PollSeconds
    Fallback polling interval if FileSystemWatcher fails (default 2s).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TaskId,
        [switch] $AutoOpen,
        [int] $PollSeconds = 2
    )
    $vortexHome = if ($env:VORTEX_HOME) { $env:VORTEX_HOME } else { (Join-Path $env:APPDATA 'Vortex-OS') }
    $taskDir = Join-Path $vortexHome 'state' 'in_progress' $TaskId
    if (-not (Test-Path $taskDir)) {
        throw "In-progress dir not found: $taskDir -- is the dispatch running?"
    }

    Write-Host "  [stream] attached to $TaskId" -ForegroundColor Cyan
    Write-Host "  [stream] in-progress: $taskDir"
    if ($AutoOpen) { Write-Host "  [stream] --auto-open enabled (no y/n/q prompt)" }
    Write-Host ""

    # Track which files we've already surfaced to avoid re-prompting.
    $seen = @{}
    foreach ($f in (Get-ChildItem -LiteralPath $taskDir -File -ErrorAction SilentlyContinue)) {
        $seen[$f.Name] = $true
    }

    # Try FileSystemWatcher first.
    $watcher = $null
    try {
        $watcher = New-Object System.IO.FileSystemWatcher -Property @{
            Path = $taskDir
            Filter = '*'
            IncludeSubdirectories = $false
            EnableRaisingEvents = $true
            NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::Size
        }
        $onChange = {
            param($s, $e)
            $name = Split-Path -Leaf $e.FullPath
            if ($script:seen[$name]) { return }
            $script:seen[$name] = $true
            $size = (Get-Item -LiteralPath $e.FullPath -ErrorAction SilentlyContinue).Length
            if ($name -like '.*' -or $name -like '.hints*' -or $name -like '*.json' -and $name -notlike '*.partial*') {
                # Skip dotfiles and pure manifests.
                if ($name -notlike '*.partial*') { return }
            }
            Write-Host "  [stream] ready: $name ($size bytes)" -ForegroundColor Green
            $reply = 'n'
            if ($script:AutoOpen) { $reply = 'y' }
            else {
                $key = Read-Host "  open? (y/n/q)"
                $reply = $key.Trim().ToLower()
                if ($reply -eq 'q') {
                    Write-Host "  [stream] stopped watching (dispatch continues in background)" -ForegroundColor Yellow
                    $script:StopStream = $true
                }
            }
            if ($reply -eq 'y') {
                try { Start-Process -FilePath $e.FullPath -ErrorAction SilentlyContinue }
                catch { Write-Host "  [stream] open failed: $($_.Exception.Message)" -ForegroundColor Red }
            }
        }
        Register-ObjectEvent -InputObject $watcher -EventName Created -Action $onChange | Out-Null
        Register-ObjectEvent -InputObject $watcher -EventName Changed -Action $onChange | Out-Null
    } catch {
        Write-Host "  [stream] FileSystemWatcher unavailable: $($_.Exception.Message); falling back to polling" -ForegroundColor Yellow
        $watcher = $null
    }

    # Print the initial snapshot.
    foreach ($f in (Get-ChildItem -LiteralPath $taskDir -File -ErrorAction SilentlyContinue)) {
        if ($f.Name -like '*.partial*') {
            Write-Host "  [stream] ready: $($f.Name) ($($f.Length) bytes)" -ForegroundColor DarkGreen
        }
    }

    # Poll loop (also serves as fallback when FileSystemWatcher is unavailable).
    $script:StopStream = $false
    try {
        while (-not $script:StopStream) {
            Start-Sleep -Seconds $PollSeconds
            foreach ($f in (Get-ChildItem -LiteralPath $taskDir -File -ErrorAction SilentlyContinue)) {
                $name = $f.Name
                if ($script:seen[$name]) { continue }
                $script:seen[$name] = $true
                if ($name -notlike '*.partial*') { continue }
                Write-Host "  [stream] ready: $name ($($f.Length) bytes)" -ForegroundColor Green
                $reply = 'n'
                if ($script:AutoOpen) { $reply = 'y' }
                else {
                    $key = Read-Host "  open? (y/n/q)"
                    $reply = $key.Trim().ToLower()
                    if ($reply -eq 'q') { $script:StopStream = $true; break }
                }
                if ($reply -eq 'y') {
                    try { Start-Process -FilePath $f.FullName -ErrorAction SilentlyContinue }
                    catch { Write-Host "  [stream] open failed: $($_.Exception.Message)" -ForegroundColor Red }
                }
            }
            if ($script:StopStream) { break }
            # Check if .completed exists -> dispatch done.
            if (Test-Path -LiteralPath (Join-Path $taskDir '.completed')) {
                Write-Host "  [stream] dispatch complete" -ForegroundColor Green
                break
            }
        }
    } finally {
        if ($watcher) {
            $watcher.EnableRaisingEvents = $false
            $watcher.Dispose()
        }
        Get-EventSubscriber | Where-Object { $_.SourceObject -eq $watcher } | Unregister-Event
    }
}

function Stop-VortexStream {
<#
.SYNOPSIS
    Stop watching a dispatch (or all dispatches if -TaskId is omitted).
#>
    [CmdletBinding()]
    param(
        [string] $TaskId
    )
    $script:StopStream = $true
    Write-Host "  [stream] stop signal sent" -ForegroundColor Yellow
}

function Send-VortexHint {
<#
.SYNOPSIS
    Append an operator hint to a running dispatch's .hints.jsonl so the
    next dispatch in the chain picks it up.
.PARAMETER TaskId
    The dispatch to annotate.
.PARAMETER Text
    The hint text.
.EXAMPLE
    PS> Send-VortexHint -TaskId ep2_writer -Text "Tone is too dark; lighten by 20%"
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TaskId,
        [Parameter(Mandatory)] [string] $Text
    )
    # We delegate to the engine's --hint command (which knows the path
    # to the right .vortex/config.json-aware in_progress dir).
    $skill = Join-Path $PSScriptRoot '..\skill.ps1'
    if (-not (Test-Path $skill)) { throw "skill.ps1 not found at $skill" }
    & pwsh -NoProfile -File $skill --hint $TaskId --text $Text
    if ($LASTEXITCODE -ne 0) {
        throw "Engine rejected the hint (exit $LASTEXITCODE)"
    }
}

Export-ModuleMember -Function @(
    'Get-VortexStream'
    'Start-VortexStream'
    'Stop-VortexStream'
    'Send-VortexHint'
)
