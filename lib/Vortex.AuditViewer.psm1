# =============================================================================
# Vortex.AuditViewer — PowerShell viewer for the VORTEX-OS audit log
# =============================================================================
# Sits in the skill's lib/ folder so it can be dot-sourced from skill.ps1 and
# exposed as a public cmdlet. The engine writes a JSONL file to
#   $env:VORTEX_HOME\memory\audit.jsonl
# and this module turns that file into rich, filterable output.
#
# Output formats:
#   table  - default, one line per event with the most-useful fields
#   tree   - groups events by tier (T0..T4) for at-a-glance sweeps
#   selfheal- highlights violation -> fix pairs from the Self-Healing Optimizer
#   hitl   - the gate-by-gate HITL trail (every PENDING_HUMAN + every gate_id)
#   json   - machine-readable array (for piping to jq / ConvertFrom-Json)
#   html   - standalone HTML report (single file, no external assets)
#
# Filters:
#   -Project  <slug>     - exact match on the project field
#   -Task     <id>       - exact match on the task_id field
#   -Agent    <name>     - exact match on the agent field
#   -Severity <lvl>      - LOW / MEDIUM / HIGH / CRITICAL
#   -Since    <iso>      - only events after this ISO-8601 timestamp
#   -Last     <n>        - only the last N events (after filters)
#   -Path     <file>     - override the audit.jsonl location (testing)
#
# Backward compatibility:
#   * Missing fields are returned as empty strings / empty arrays
#   * v0.1.10 logs (5 legacy fields) work — the new fields are simply empty
#   * Lines that fail to parse are returned as PSCustomObject with
#     `_raw` set to the line text and all known fields empty
# =============================================================================
$ErrorActionPreference = 'Stop'

function Get-VortexAuditTrail {
<#
.SYNOPSIS
    Print a filtered, formatted view of the VORTEX-OS audit log.
.PARAMETER Format
    One of: table, tree, selfheal, hitl, json, html. Default: table.
.PARAMETER Project
    Filter: exact match on the project field.
.PARAMETER Task
    Filter: exact match on the task_id field.
.PARAMETER Agent
    Filter: exact match on the agent field.
.PARAMETER Severity
    Filter: LOW / MEDIUM / HIGH / CRITICAL.
.PARAMETER Since
    Filter: only events after this ISO-8601 timestamp (e.g. '2026-08-22' or
    '2026-08-22T10:00:00').
.PARAMETER Last
    Filter: only the last N events after all other filters.
.PARAMETER Path
    Override the audit.jsonl location (default: $env:VORTEX_HOME\memory\audit.jsonl).
#>
    [CmdletBinding()]
    param(
        [ValidateSet('table','tree','selfheal','hitl','json','html')]
        [string] $Format = 'table',

        [string] $Project,
        [string] $Task,
        [string] $Agent,
        [ValidateSet('','LOW','MEDIUM','HIGH','CRITICAL')]
        [string] $Severity = '',
        [string] $Since = '',
        [int]    $Last = 0,
        [string] $Path = ''
    )

    # --- 1. Resolve the audit log path --------------------------------------
    if (-not $Path) {
        $home = if ($env:VORTEX_HOME) { $env:VORTEX_HOME } else { (Join-Path $env:APPDATA 'Vortex-OS') }
        $Path = Join-Path $home 'memory\audit.jsonl'
    }

    # --- 2. Load events -----------------------------------------------------
    $events = @()
    if (Test-Path -LiteralPath $Path) {
        Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue | ForEach-Object {
            $line = $_
            if ([string]::IsNullOrWhiteSpace($line)) { return }
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop
            } catch {
                $obj = [PSCustomObject]@{ _raw = $line }
            }
            # Normalize missing fields so the renderer never trips.
            foreach ($f in 'ts','tier','agent','action','status','project','task_id','severity','rule_violated','rule_fixed','gate_id') {
                if (-not ($obj.PSObject.Properties.Name -contains $f)) {
                    Add-Member -InputObject $obj -NotePropertyName $f -NotePropertyValue '' -Force
                }
            }
            if (-not ($obj.PSObject.Properties.Name -contains 'tags')) {
                Add-Member -InputObject $obj -NotePropertyName 'tags' -NotePropertyValue @() -Force
            }
            $events += $obj
        }
    }

    # --- 3. Apply filters ---------------------------------------------------
    $filtered = $events
    if ($Project)   { $filtered = @($filtered | Where-Object { $_.project -eq $Project }) }
    if ($Task)      { $filtered = @($filtered | Where-Object { $_.task_id -eq $Task }) }
    if ($Agent)     { $filtered = @($filtered | Where-Object { $_.agent   -eq $Agent }) }
    if ($Severity)  { $filtered = @($filtered | Where-Object { $_.severity -eq $Severity }) }
    if ($Since) {
        $sinceDate = $null
        try { $sinceDate = [datetime]::Parse($Since) } catch { throw "Bad -Since value '$Since'. Use ISO-8601 like '2026-08-22' or '2026-08-22T10:00:00'." }
        $filtered = @($filtered | Where-Object {
            if (-not $_.ts) { return $false }
            try { [datetime]::Parse($_.ts) -ge $sinceDate } catch { return $false }
        })
    }
    if ($Last -gt 0 -and $filtered.Count -gt $Last) {
        $filtered = @($filtered | Select-Object -Last $Last)
    }

    # --- 4. Render ----------------------------------------------------------
    # All formatters ALSO emit the events to the pipeline so callers can
    # pipe the raw objects to Where-Object / ConvertFrom-Json etc. The
    # formatted text is written via Write-Host which doesn't pollute the
    # pipeline.
    switch ($Format) {
        'json'   { Format-AuditJson   $filtered;  $filtered }
        'tree'   { Format-AuditTree   $filtered;  $filtered }
        'selfheal'{ Format-AuditSelfHeal $filtered; $filtered }
        'hitl'   { Format-AuditHitl   $filtered;  $filtered }
        'html'   { Format-AuditHtml   $filtered;  $filtered }
        default  { Format-AuditTable  $filtered;  $filtered }
    }
}

# -----------------------------------------------------------------------------
# Renderers
# -----------------------------------------------------------------------------

function Format-AuditTable {
    param([array] $Events)
    if ($Events.Count -eq 0) {
        Write-Host "  (no audit events match the current filters)"
        return
    }
    Write-Host ("  {0,-23}  {1,-4}  {2,-26}  {3,-22}  {4,-14}  {5,-10}  {6}" -f 'ts','tier','agent','action','status','severity','task_id')
    $sep = '  ' + ('-' * 23) + '  ' + ('-' * 4) + '  ' + ('-' * 26) + '  ' + ('-' * 22) + '  ' + ('-' * 14) + '  ' + ('-' * 10) + '  ' + ('-' * 8)
    Write-Host $sep
    foreach ($e in $Events) {
        $sev = if ($e.severity) { $e.severity } else { '-' }
        $tid = if ($e.task_id)  { $e.task_id }  else { '-' }
        Write-Host ("  {0,-23}  {1,-4}  {2,-26}  {3,-22}  {4,-14}  {5,-10}  {6}" -f $e.ts, $e.tier, $e.agent, $e.action, $e.status, $sev, $tid)
        # Show rule violation/fix as a sub-line so the simple table still
        # surfaces the most important self-heal context without needing
        # the operator to switch to --format selfheal.
        if ($e.rule_violated) { Write-Host ("     ↳ VIOLATED: {0}" -f $e.rule_violated) -ForegroundColor Red }
        if ($e.rule_fixed)    { Write-Host ("     ↳ FIXED:    {0}" -f $e.rule_fixed)    -ForegroundColor Green }
        if ($e.gate_id)       { Write-Host ("     ↳ GATE:     {0}" -f $e.gate_id)       -ForegroundColor Magenta }
    }
    Write-Host ""
    Write-Host ("  Total: {0} event(s)" -f $Events.Count)
}

function Format-AuditTree {
    param([array] $Events)
    if ($Events.Count -eq 0) {
        Write-Host "  (no audit events match the current filters)"
        return
    }
    # Group by tier, preserve first-seen order.
    $tiers = @{}
    foreach ($e in $Events) {
        $t = if ($e.tier) { $e.tier } else { '?' }
        if (-not $tiers.ContainsKey($t)) { $tiers[$t] = @() }
        $tiers[$t] += $e
    }
    foreach ($tier in @('T0','T1','T2','T3','T4')) {
        if (-not $tiers.ContainsKey($tier)) { continue }
        Write-Host ""
        Write-Host "Tier $tier  ($($tiers[$tier].Count) event(s))" -ForegroundColor Cyan
        foreach ($e in $tiers[$tier]) {
            $marker = ''
            $color  = 'White'
            if ($e.action -eq 'self_heal' -and $e.status -eq 'ok')   { $marker = ' [HEALED]';     $color = 'Green' }
            if ($e.action -eq 'self_heal' -and $e.status -eq 'fail') { $marker = ' [HEAL-FAIL]';  $color = 'Yellow' }
            if ($e.action -eq 'token_audit'-and $e.status -eq 'warn') { $marker = ' [VIOLATED]';   $color = 'Red' }
            if ($e.action -eq 'hitl_request')                         { $marker = ' [HITL GATE]';  $color = 'Magenta' }
            if ($e.action -eq 'dispatch_start')                      { $marker = ' [DISPATCH]';   $color = 'DarkCyan' }
            if ($e.action -eq 'dispatch_end')                        { $marker = ' [END]';        $color = 'DarkCyan' }
            $line = "  ├─ {0,-23}  {1,-22}  {2,-12}  {3}{4}" -f $e.ts, $e.action, $e.status, $e.agent, $marker
            Write-Host $line -ForegroundColor $color
            if ($e.rule_violated) { Write-Host ("  │   violated: {0}" -f $e.rule_violated) -ForegroundColor DarkYellow }
            if ($e.rule_fixed)    { Write-Host ("  │   fixed:    {0}" -f $e.rule_fixed)    -ForegroundColor DarkGreen }
            if ($e.gate_id)       { Write-Host ("  │   gate:     {0}" -f $e.gate_id)       -ForegroundColor DarkMagenta }
            if ($e.task_id)       { Write-Host ("  │   task:     {0}" -f $e.task_id) }
        }
    }
    Write-Host ""
    Write-Host ("  Total: {0} event(s) across {1} tier(s)" -f $Events.Count, $tiers.Count)
}

function Format-AuditSelfHeal {
    param([array] $Events)
    $heals = @($Events | Where-Object { $_.action -eq 'self_heal' -or $_.action -eq 'token_audit' -or $_.rule_violated -or $_.rule_fixed })
    if ($heals.Count -eq 0) {
        Write-Host "  (no self-heal events match the current filters)"
        return
    }
    Write-Host ""
    Write-Host "Self-Healing Optimizer audit" -ForegroundColor Yellow
    Write-Host "============================" -ForegroundColor Yellow
    # A "violation" is the observation that triggered the heal (e.g. a
    # token_audit warn with rule_violated set). The self_heal "ok" event
    # itself is the fix, not a separate violation — it carries the same
    # rule_violated + rule_fixed pair. Filtering out ok-status self_heal
    # events keeps the violation count semantically correct.
    $violations = @($heals | Where-Object { $_.rule_violated -and -not ($_.action -eq 'self_heal' -and $_.status -eq 'ok') })
    $fixes      = @($heals | Where-Object { $_.rule_fixed -and $_.action -eq 'self_heal' -and $_.status -eq 'ok' })
    Write-Host ""
    Write-Host ("  Violations: {0}" -f $violations.Count)
    foreach ($e in $violations) {
        Write-Host ("    - {0,-30}  {1,-23}  status={2}" -f $e.rule_violated, $e.ts, $e.status) -ForegroundColor Red
    }
    Write-Host ""
    Write-Host ("  Fixes applied: {0}" -f $fixes.Count)
    foreach ($e in $fixes) {
        Write-Host ("    - {0,-30}  {1,-23}  matches '{2}'" -f $e.rule_fixed, $e.ts, $e.rule_violated) -ForegroundColor Green
    }
    Write-Host ""
    Write-Host ("  Total self-heal events: {0}" -f $heals.Count)
}

function Format-AuditHitl {
    param([array] $Events)
    $hitl = @($Events | Where-Object { $_.action -eq 'hitl_request' -or $_.gate_id -or $_.status -eq 'PENDING_HUMAN' })
    if ($hitl.Count -eq 0) {
        Write-Host "  (no HITL events match the current filters)"
        return
    }
    Write-Host ""
    Write-Host "HITL (Human-in-the-Loop) audit" -ForegroundColor Magenta
    Write-Host "==============================" -ForegroundColor Magenta
    Write-Host ("  {0,-23}  {1,-22}  {2,-10}  {3,-12}  {4}" -f 'ts','action','severity','status','task_id')
    foreach ($e in $hitl) {
        Write-Host ("  {0,-23}  {1,-22}  {2,-10}  {3,-12}  {4}" -f $e.ts, $e.action, $e.severity, $e.status, $e.task_id)
        if ($e.gate_id) { Write-Host ("    gate_id: {0}" -f $e.gate_id) -ForegroundColor DarkMagenta }
    }
    Write-Host ""
    Write-Host ("  Total HITL events: {0}" -f $hitl.Count)
}

function Format-AuditJson {
    param([array] $Events)
    # Convert to a plain array of hashtables so ConvertTo-Json -Depth N works.
    $out = @()
    foreach ($e in $Events) {
        $h = [ordered]@{}
        foreach ($k in 'ts','tier','agent','action','status','project','task_id','severity','rule_violated','rule_fixed','gate_id') {
            $h[$k] = if ($e.PSObject.Properties.Name -contains $k) { $e.$k } else { '' }
        }
        # tags may be either an array (from JSONL) or a single string
        # (in case ConvertFrom-Json saw a single-element list). Force
        # an array so jq / downstream consumers always see a list.
        $h['tags'] = if ($e.PSObject.Properties.Name -contains 'tags') {
            $t = $e.tags
            if ($null -eq $t) { @() }
            elseif ($t -is [array]) { @($t) }
            elseif ($t -is [string]) {
                if ([string]::IsNullOrEmpty($t)) { @() } else { ,@($t) }
            }
            else { @($t) }
        } else { @() }
        $out += [PSCustomObject]$h
    }
    # Force array context: a single-element collection otherwise serializes
    # as a bare object, which makes the output unfriendly for jq / CI.
    # The comma operator wraps in an extra array, then ConvertTo-Json
    # sees a 1-element collection which still serializes as a bare object
    # — so we have to use @($out) which is a guaranteed array.
    ,@($out) | ConvertTo-Json -Depth 5
}

function Format-AuditHtml {
    param([array] $Events)
    $rows = foreach ($e in $Events) {
        $sev = if ($e.severity) { $e.severity } else { '-' }
        $tid = if ($e.task_id)  { $e.task_id }  else { '-' }
        "<tr><td>$([WebUtility]::HtmlEncode([string]$e.ts))</td><td>$([WebUtility]::HtmlEncode([string]$e.tier))</td><td>$([WebUtility]::HtmlEncode([string]$e.agent))</td><td>$([WebUtility]::HtmlEncode([string]$e.action))</td><td>$([WebUtility]::HtmlEncode([string]$e.status))</td><td>$sev</td><td>$tid</td></tr>"
    } -join "`n"
    @"
<!doctype html>
<html><head><meta charset="utf-8"><title>VORTEX-OS Audit Trail</title>
<style>
body { font-family: 'Segoe UI', sans-serif; background:#0d1117; color:#c9d1d9; padding:24px; }
h1 { color:#58a6ff; font-size:18pt; }
table { border-collapse:collapse; width:100%; }
th, td { border:1px solid #30363d; padding:6px 10px; text-align:left; font-size:10pt; }
th { background:#161b22; color:#8b949e; }
tr:nth-child(even) td { background:#0d1117; }
tr:nth-child(odd)  td { background:#161b22; }
</style></head><body>
<h1>VORTEX-OS Audit Trail ($($Events.Count) events)</h1>
<table><thead><tr><th>ts</th><th>tier</th><th>agent</th><th>action</th><th>status</th><th>severity</th><th>task_id</th></tr></thead>
<tbody>
$rows
</tbody></table>
</body></html>
"@
}

# -----------------------------------------------------------------------------
# Public surface
# -----------------------------------------------------------------------------
Export-ModuleMember -Function 'Get-VortexAuditTrail'
