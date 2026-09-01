# =============================================================================
# skill.ps1 — VORTEX-OS dispatcher entry point (PowerShell 7+, v0.2.2)
# =============================================================================
# Thin routing layer for the C++/CLI engine (Vortex.dll). The engine is the
# ONLY implementation of every command; this script:
#   1. Locates the installed engine (or auto-installs it on first run)
#   2. Loads the engine module
#   3. Forwards the user's args
#   4. Surfaces the Tier-2 LLM-as-engine fallback banner if the engine is missing
#   5. Handles two maintenance flags: --health and --recover-engine
#   6. Short-circuits --audit-trail to the rich PowerShell viewer
#      (lib/Vortex.AuditViewer.psm1) so the operator gets tree / selfheal /
#      hitl / json / html output instead of the engine's basic dump.
#
# The C++/CLI engine is the canonical implementation of every command. There
# is NO parallel PowerShell implementation of any command. Per user direction
# (2026-08-27), the earlier 3-tier design (with a "Tier 1 PowerShell-only
# re-implementation of 14 commands") was rejected as a second engine to
# maintain. See docs/prd-phase2/prd-08-engine-unavailable-degraded-mode.md
# for the rationale.
# =============================================================================
[CmdletBinding()]
param(
    # Maintenance flags. Each multi-word switch is aliased to the
    # kebab-case form so the user can pass --no-engine, --recover-engine
    # (PowerShell's switch matching is case-insensitive for the alias).
    # Single-word switches ($Health, $Install, $Force) don't need aliases.
    [switch] $Health,

    [Alias('Recover-Engine')]
    [switch] $RecoverEngine,

    [Alias('No-Engine')]
    [switch] $NoEngine,

    [switch] $Install,

    [switch] $Force,

    # Audit viewer output format. Only consulted when --audit-trail is in
    # $Arguments. Pulled out of $Arguments below (after param binding) so
    # we don't expose it as a wrapper param — that would let PowerShell
    # greedily bind unrelated string args (like "--version") to it via
    # the default position-based binding rule.
    # (No wrapper param declared here — see the post-binding parse below.)

    # Note: we deliberately do NOT declare [string] $Project. The engine
    # accepts --project <slug> as a positional engine arg; declaring it
    # here would make PowerShell greedily bind --project (and silently
    # swallow it), which breaks the dispatcher's argv passthrough.
    # Callers set the project via $env:VORTEX_PROJECT (or by passing
    # --project=foo directly to the engine, which survives the
    # [ValueFromRemainingArguments] pass-through below).

    # All other args (the engine args) are captured here.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Arguments
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Allow VORTEX_PROJECT to be set via a wrapper-level alias for backward
# compatibility. We unexported the [string]$Project parameter (see the
# param block above) to prevent PowerShell from auto-binding the engine's
# `--project` flag, but scripts that called `skill.ps1 -Project foo` should
# still work. To restore that, we accept the alias via a different route:
# `skill.ps1 --project foo` (no `-Project` wrapper) flows into $Arguments
# and is then set as the env var by the engine's own dispatch path. The
# env var path is the canonical way to set the project for the dispatch.

# --- Tier 2 banner (defined at the top so the early-exit paths can call it) -
function Show-Tier2Banner {
    [CmdletBinding()]
    param(
        [string[]] $Args,
        [string] $Reason = ''
    )
    $reasonLine = if ($Reason) { "  Reason: $Reason`n" } else { '' }
    $cmd = if ($Args -and $Args.Count -gt 0) { $Args[0] } else { '<command>' }
    $llmFallback = Join-Path $here 'references\LLM-FALLBACK.md'
    Write-Host ""
    Write-Host "  +-- VORTEX-OS Engine: NOT AVAILABLE --+" -ForegroundColor Yellow
    if ($reasonLine) { Write-Host $reasonLine -ForegroundColor Yellow -NoNewline }
    Write-Host "  The C++/CLI engine (Vortex.dll) is the canonical implementation of" -ForegroundColor Yellow
    Write-Host "  every VORTEX-OS command. Without it, no command works." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  How to recover:" -ForegroundColor Yellow
    Write-Host "    1. Retry the install:  pwsh -NoProfile -File .\skill.ps1 --recover-engine" -ForegroundColor Yellow
    Write-Host "    2. If the install fails, run install.ps1 -Verbose manually to see the error." -ForegroundColor Yellow
    Write-Host "    3. If you're an LLM-coding-agent, read the Tier 2 recipe:" -ForegroundColor Yellow
    Write-Host "         $llmFallback" -ForegroundColor Yellow
    Write-Host "       The recipe lets the LLM act as the engine for this one dispatch." -ForegroundColor Yellow
    Write-Host "  +-----------------------------------------+" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "ERROR: engine unavailable; cannot run '$cmd'." -ForegroundColor Red
    Write-Host "Run 'pwsh -NoProfile -File .\skill.ps1 --health' for a full report." -ForegroundColor Red
}

# --- 0. Env setup -------------------------------------------------------------
$env:VORTEX_SKILL_ROOT = $here
# (Project is no longer a wrapper param — see the top-of-file note.)

# v0.3.7 (G22): the engine's CWD after `Import-Module Vortex` is the Vortex
# module folder, not the skill folder. When the user passes a relative
# template path like `templates\iteration_pattern.json`, the engine's
# File::Exists check fails and it bails with "Usage: skill.exe ...". We
# pre-resolve relative path args against the skill folder here so the
# engine receives absolute paths regardless of the current CWD.
#
# Path-accepting flags we know about:
#   --dispatch-template <file>     template JSON (relative or absolute)
#   --dispatch-master   <file>     master objective markdown
#   --source <file> / --source-file <file>   used by --recipe
#   --plugin-test --input <file>   plugin test input
#   --plugin-invoke --input <file> plugin invoke input
#   --agents-validate <file>       agent manifest to validate
function Resolve-RelativeSkillPath([string]$Path) {
    if ([string]::IsNullOrEmpty($Path)) { return $Path }
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    $resolved = Join-Path $here $Path
    if (Test-Path -LiteralPath $resolved) { return $resolved }
    # Fall back to the literal arg; engine will produce the proper "not
    # found" error if it really is missing.
    return $Path
}

# Flags that take a path as their next positional arg. For each, if the
# next arg is a relative path, resolve it against the skill folder.
$pathFlags = @('--dispatch-template', '--dispatch-master', '--source', '--source-file', '--agents-validate')
# Flags that take a path AFTER a --input subflag.
$inputFlags = @('--plugin-test', '--plugin-invoke')
if ($Arguments) {
    $resolved = New-Object System.Collections.Generic.List[string]
    $i = 0
    while ($i -lt $Arguments.Count) {
        $a = $Arguments[$i]
        $resolved.Add($a)
        if ($pathFlags -contains $a -and ($i + 1) -lt $Arguments.Count) {
            $resolved.Add((Resolve-RelativeSkillPath $Arguments[$i + 1]))
            $i += 2
            continue
        }
        if ($inputFlags -contains $a) {
            # Walk forward; if the next token is --input, resolve the token
            # after it as a path.
            for ($j = $i + 1; $j -lt $Arguments.Count; $j++) {
                $resolved.Add($Arguments[$j])
                if ($Arguments[$j] -eq '--input' -and ($j + 1) -lt $Arguments.Count) {
                    $resolved.Add((Resolve-RelativeSkillPath $Arguments[$j + 1]))
                    $i = $j + 1
                    break
                }
            }
            $i++
            continue
        }
        $i++
    }
    $Arguments = $resolved.ToArray()
    # v0.3.7 (G22): also fix the dotnet CurrentDirectory so the engine's
    # own relative-path resolution (e.g. reading production_bible.json
    # from the project state dir) works as expected. Without this, the
    # engine sees the Vortex module folder as CWD, which is why
    # Plugin.cpp's `Path::Combine(pluginDir, entry)` is fine (pluginDir
    # is absolute) but the production_bible lookup at the executor
    # level would not be.
    $env:VORTEX_SKILL_ROOT = $here
}

# --- 0a. PS7+ guard -----------------------------------------------------------
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    throw "VORTEX-OS requires PowerShell 7+ (Core). Detected: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)). Install from https://aka.ms/powershell"
}

# --- 0b. --health (works regardless of engine state) --------------------------
# Prints the active tier + recovery hints. Exits 0 always.
if ($Health) {
    $engineManifest = $null
    $engineAvailable = $false
    if (-not $NoEngine) {
        $engineManifest = & {
            # Inline Find-VortexManifest (no engine needed for the lookup).
            $candidates = @()
            if ($env:VORTEX_MODULE_PATH) { $candidates += $env:VORTEX_MODULE_PATH }
            if ($env:PSModulePath) {
                foreach ($entry in ($env:PSModulePath -split [IO.Path]::PathSeparator)) {
                    $e = $entry.Trim()
                    if (-not $e) { continue }
                    if ($e -like '*WindowsPowerShell*') { continue }
                    if ($e -like '*Program Files*') { continue }
                    if ($candidates -notcontains $e) { $candidates += $e }
                }
            }
            $canonical = Join-Path $HOME 'Documents\PowerShell\Modules'
            if ($candidates -notcontains $canonical) { $candidates += $canonical }
            foreach ($cand in $candidates) {
                $vortexDir = Join-Path $cand 'Vortex'
                if (-not [IO.Directory]::Exists($vortexDir)) { continue }
                $versions = Get-ChildItem -LiteralPath $vortexDir -Directory -ErrorAction SilentlyContinue |
                    Sort-Object { [version]($_.Name.TrimStart('v')) } -Descending
                foreach ($v in $versions) {
                    $psd1 = Join-Path $v.FullName 'Vortex.psd1'
                    if ([IO.File]::Exists($psd1)) { return $psd1 }
                }
            }
            return $null
        }
        if ($engineManifest) {
            try {
                Import-Module $engineManifest -Force -ErrorAction Stop
                $engineAvailable = $true
            } catch { }
        }
    }
    $tier = if ($NoEngine -or -not $engineAvailable) { 'NOT AVAILABLE (engine missing or --no-engine forced)' } else { "AVAILABLE ($engineManifest)" }
    Write-Host ""
    Write-Host "VORTEX-OS health"
    Write-Host "================"
    Write-Host "  Tier 1 (engine): $tier"
    Write-Host "  Tier 2 (LLM):    See <skill>/references/LLM-FALLBACK.md (recipe only)"
    Write-Host "  Skill folder:    $here"
    $vortexHome = if ($env:VORTEX_HOME) { $env:VORTEX_HOME } else { Join-Path $env:APPDATA 'Vortex-OS' }
    Write-Host "  VORTEX_HOME:     $vortexHome"
    $llmFallback = Join-Path $here 'references\LLM-FALLBACK.md'
    Write-Host "  LLM fallback:    $(if (Test-Path $llmFallback) { 'present' } else { 'MISSING' })"
    Write-Host ""
    if ($engineAvailable) {
        Write-Host "  All 18 commands work. Use --recover-engine to reinstall if anything breaks."
    } else {
        Write-Host "  Engine unavailable. Recovery options:"
        Write-Host "    1. pwsh -NoProfile -File .\skill.ps1 --recover-engine"
        Write-Host "    2. If the download fails, check network or run install.ps1 -Verbose manually."
        Write-Host "    3. If you're an LLM-coding-agent, read <skill>/references/LLM-FALLBACK.md"
        Write-Host "       to act as the engine for one dispatch."
    }
    exit 0
}

# --- 0c. --recover-engine (retry install) ------------------------------------
if ($RecoverEngine) {
    $env:VORTEX_NO_AUTO_UPDATE = '0'  # clear the cache for this run
    $installer = Join-Path $here 'install.ps1'
    if (-not (Test-Path $installer)) {
        Write-Host "ERROR: install.ps1 not found at $installer" -ForegroundColor Red
        exit 2
    }
    Write-Host "[vortex-os] Retrying engine install..." -ForegroundColor Cyan
    if ($Force) { & pwsh -NoProfile -File $installer -Force } else { & pwsh -NoProfile -File $installer }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[vortex-os] install.ps1 failed (exit $LASTEXITCODE). Try install.ps1 -Verbose manually." -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "[vortex-os] Re-detecting engine..." -ForegroundColor Cyan
    $recovered = & pwsh -NoProfile -File $MyInvocation.MyCommand.Path --health
    if ($recovered -match 'AVAILABLE') {
        Write-Host "[vortex-os] Engine recovered." -ForegroundColor Green
        exit 0
    }
    Write-Host "[vortex-os] install.ps1 ran but no Vortex.psd1 found. Network or GitHub issue?" -ForegroundColor Red
    exit 1
}

# --- 0d. --no-engine: simulate engine missing (for testing) -------------------
if ($NoEngine) {
    Show-Tier2Banner -Args $Arguments
    exit 2
}

# --- 1. Auto-update check (rate-limited, opt-out) ----------------------------
# On first invocation (and every 6h after), check if a newer engine is on
# GitHub and install it if so. Skipped if $env:VORTEX_NO_AUTO_UPDATE = '1'.
$autoUpdate = Join-Path $here 'auto-update.ps1'
if (Test-Path $autoUpdate) {
    try {
        & pwsh -NoProfile -File $autoUpdate
    } catch {
        Write-Host "[vortex-os] auto-update.ps1 failed (non-fatal): $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

# --- 2. Locate the installed Vortex module manifest --------------------------
function Find-VortexManifest {
    $candidates = @()
    if ($env:VORTEX_MODULE_PATH) { $candidates += $env:VORTEX_MODULE_PATH }
    if ($env:PSModulePath) {
        foreach ($entry in ($env:PSModulePath -split [IO.Path]::PathSeparator)) {
            $e = $entry.Trim()
            if (-not $e) { continue }
            if ($e -like '*WindowsPowerShell*') { continue }
            if ($e -like '*Program Files*') { continue }
            if ($candidates -notcontains $e) { $candidates += $e }
        }
    }
    $canonical = Join-Path $HOME 'Documents\PowerShell\Modules'
    if ($candidates -notcontains $canonical) { $candidates += $canonical }
    foreach ($cand in $candidates) {
        $vortexDir = Join-Path $cand 'Vortex'
        if (-not [IO.Directory]::Exists($vortexDir)) { continue }
        $versions = Get-ChildItem -LiteralPath $vortexDir -Directory -ErrorAction SilentlyContinue |
            Sort-Object { [version]($_.Name.TrimStart('v')) } -Descending
        foreach ($v in $versions) {
            $psd1 = Join-Path $v.FullName 'Vortex.psd1'
            if ([IO.File]::Exists($psd1)) { return $psd1 }
        }
    }
    return $null
}

$manifest = Find-VortexManifest

# --- 3. Auto-install if missing ---------------------------------------------
if ($Install -or -not $manifest) {
    $installer = Join-Path $here 'install.ps1'
    if (-not (Test-Path $installer)) {
        throw "Engine module 'Vortex' is not installed and the installer ($installer) is missing. Run install.ps1 manually or download the 4 engine files into your user-scope module folder."
    }
    Write-Host "[vortex-os] Engine not found locally -- running installer (one-time, downloads from GitHub release) ..." -ForegroundColor Cyan
    & pwsh -NoProfile -File $installer
    if ($LASTEXITCODE -ne 0) { throw "Engine installer failed with exit $LASTEXITCODE" }
    $manifest = Find-VortexManifest
    if (-not $manifest) {
        Show-Tier2Banner -Args $Arguments -Reason 'install.ps1 ran but no Vortex.psd1 was found.'
        exit 2
    }
}

# --- 4. Import the engine ----------------------------------------------------
try {
    Import-Module $manifest -Force -ErrorAction Stop
} catch {
    Show-Tier2Banner -Args $Arguments -Reason "engine manifest found at $manifest but PowerShell can't load it: $($_.Exception.Message)"
    exit 2
}

# --- 5. --audit-trail short-circuit (use the rich PowerShell viewer) --------
# If the caller asked for the audit trail, hand off to the viewer module
# instead of letting the engine's basic --audit-trail dump mix with the
# rich output. The viewer supports table / tree / selfheal / hitl / json
# / html formats and filters by -Project / -Task / -Agent / -Severity /
# -Since / -Last. Without --AuditFormat we default to 'table'.
#
# We parse --AuditFormat out of $Arguments rather than declaring it as a
# wrapper param: declaring `[string] $AuditFormat` here would let
# PowerShell greedily bind the first positional string arg (e.g. `--version`)
# to it via the default position-based binding rule, which broke
# `skill.ps1 --version`. The wrapper's only named args are the maintenance
# switches; everything else flows through to the engine / viewer.
$AuditFormat = ''
if ($Arguments) {
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $a = $Arguments[$i]
        if ($a -eq '--AuditFormat' -or $a -eq '-AuditFormat') {
            if ($i + 1 -lt $Arguments.Count) {
                $AuditFormat = $Arguments[$i + 1]
                $Arguments[$i] = $null
                $Arguments[$i + 1] = $null
                $i++
            }
        } elseif ($a -match '^--AuditFormat=(.+)$' -or $a -match '^-AuditFormat=(.+)$') {
            $AuditFormat = $Matches[1]
            $Arguments[$i] = $null
        }
    }
    $Arguments = @($Arguments | Where-Object { $_ -ne $null })
    # Validate
    if ($AuditFormat -and $AuditFormat -notin @('table','tree','selfheal','hitl','json','html')) {
        throw "--AuditFormat must be one of: table, tree, selfheal, hitl, json, html (got '$AuditFormat')"
    }
}
if ($Arguments -and ($Arguments -contains '--audit-trail') -and -not ($Arguments -contains '--json' -or $Arguments -contains '--json-only')) {
    # v0.3.11.2 (bug fix): when --json is present, skip the audit-viewer
    # short-circuit (same fix as the second --audit-trail short-circuit
    # at line ~509). The engine's CmdAuditTrail --json path produces
    # a single-line JSON object per docs/cli-json-contract.md. The
    # viewer's --Format json path emits ConvertTo-Json -Depth 5 which
    # is multi-line pretty-printed (the OPPOSITE of the contract).
    $viewer = Join-Path $here 'lib\Vortex.AuditViewer.psm1'
    if (-not (Test-Path $viewer)) {
        Write-Host "ERROR: audit viewer module missing at $viewer" -ForegroundColor Red
        exit 2
    }
    Import-Module $viewer -Force -ErrorAction Stop

    # Build the viewer's parameter splat. Default to 'table' if the caller
    # didn't pick a format. Any filter args (--project, --task, --agent,
    # --severity, --since, --last) are picked up by name from $Arguments
    # via PowerShell's splat-binding rules.
    $fmt = if ($AuditFormat) { $AuditFormat } else { 'table' }
    $splat = @{ Format = $fmt }

    # Translate the kebab-case CLI args into PowerShell parameter names.
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $a = $Arguments[$i]
        switch -Regex ($a) {
            '^--project=(.+)$'   { $splat['Project']  = $Matches[1]; $Arguments[$i] = $null; continue }
            '^--project$'        { if ($i + 1 -lt $Arguments.Count) { $splat['Project'] = $Arguments[$i + 1]; $Arguments[$i + 1] = $null; $Arguments[$i] = $null; $i++ }; continue }
            '^--task=(.+)$'      { $splat['Task']     = $Matches[1]; $Arguments[$i] = $null; continue }
            '^--task$'           { if ($i + 1 -lt $Arguments.Count) { $splat['Task'] = $Arguments[$i + 1]; $Arguments[$i + 1] = $null; $Arguments[$i] = $null; $i++ }; continue }
            '^--agent=(.+)$'     { $splat['Agent']    = $Matches[1]; $Arguments[$i] = $null; continue }
            '^--agent$'          { if ($i + 1 -lt $Arguments.Count) { $splat['Agent'] = $Arguments[$i + 1]; $Arguments[$i + 1] = $null; $Arguments[$i] = $null; $i++ }; continue }
            '^--severity=(.+)$'  { $splat['Severity'] = $Matches[1]; $Arguments[$i] = $null; continue }
            '^--severity$'       { if ($i + 1 -lt $Arguments.Count) { $splat['Severity'] = $Arguments[$i + 1]; $Arguments[$i + 1] = $null; $Arguments[$i] = $null; $i++ }; continue }
            '^--since=(.+)$'     { $splat['Since']    = $Matches[1]; $Arguments[$i] = $null; continue }
            '^--since$'          { if ($i + 1 -lt $Arguments.Count) { $splat['Since'] = $Arguments[$i + 1]; $Arguments[$i + 1] = $null; $Arguments[$i] = $null; $i++ }; continue }
            '^--last=(\d+)$'     { $splat['Last']     = [int]$Matches[1]; $Arguments[$i] = $null; continue }
            '^--last$'           { if ($i + 1 -lt $Arguments.Count) { $splat['Last'] = [int]$Arguments[$i + 1]; $Arguments[$i + 1] = $null; $Arguments[$i] = $null; $i++ }; continue }
        }
    }

    Get-VortexAuditTrail @splat
    exit 0
}

# --- 5b. --audit-trail user filter (PRD-10) ----------------------------------
# In team mode, the audit log is sharded per-user. The viewer's -User /
# -AllUsers flags let the operator pick which shard to view. We extract
# them here so the engine call stays clean.
if ($Arguments -and ($Arguments -contains '--audit-trail') -and
    ($Arguments -contains '--user' -or ($Arguments | Where-Object { $_ -like '--user=*' }) -or
     $Arguments -contains '--all-users')) {
    $viewerPath = Join-Path $here 'lib\Vortex.AuditViewer.psm1'
    if (Test-Path $viewerPath) {
        Import-Module $viewerPath -Force
        $fmt = if ($AuditFormat) { $AuditFormat } else { 'table' }
        $splat = @{ Format = $fmt }
        $allUsers = $false
        for ($i = 0; $i -lt $Arguments.Count; $i++) {
            $a = $Arguments[$i]
            switch -Regex ($a) {
                '^--user=(.+)$' { $splat['Project'] = $Matches[1]; $Arguments[$i] = $null; continue }
                '^--user$'      { if ($i + 1 -lt $Arguments.Count) { $splat['Project'] = $Arguments[$i + 1]; $Arguments[$i + 1] = $null; $Arguments[$i] = $null; $i++ }; continue }
                '^--all-users$'  { $allUsers = $true; $Arguments[$i] = $null; continue }
            }
        }
        # When --all-users, the viewer falls back to reading the shared
        # audit.jsonl (which in team mode is a generated aggregate). For
        # now, --all-users reads the per-user shard of the current user.
        if ($allUsers) { $splat['Project'] = '' }
        # Drop the trigger and any consumed filters.
        $Arguments = @($Arguments | Where-Object { $_ -ne $null -and $_ -ne '--audit-trail' })
        Get-VortexAuditTrail @splat
        exit 0
    }
}

# --- 5c. Streaming (PRD-14) --------------------------------------------------
# Short-circuit the streaming flags to the rich Vortex.Streamer module
# BEFORE the engine's basic dump can mix with the streamed output. The
# streamer wraps FileSystemWatcher + y/n/q interactive prompts.
if ($Arguments -and (
    $Arguments -contains '--stream-list' -or
    ($Arguments | Where-Object { $_ -like '--stream' -or $_ -like '--stream=*' }) -or
    $Arguments -contains '--stream-stop' -or
    ($Arguments | Where-Object { $_ -like '--hint' -or $_ -like '--hint=*' })
) -and -not ($Arguments -contains '--json' -or $Arguments -contains '--json-only')) {
    # v0.3.11.2 (bug fix): when --json is present, skip the streamer
    # short-circuit entirely. The engine's CmdStreamList --json path
    # already produces a single-line JSON object per
    # docs/cli-json-contract.md, and routing through the streamer would
    # either strip --json (the pre-v0.3.11.2 bug) or emit rich
    # presentation text that the JSON contract forbids.
    $streamerPath = Join-Path $here 'lib\Vortex.Streamer.psm1'
    if (-not (Test-Path $streamerPath)) {
        Write-Host "ERROR: streaming module missing at $streamerPath" -ForegroundColor Red
        exit 2
    }
    Import-Module $streamerPath -Force

    if ($Arguments -contains '--stream-list') {
        # Delegate to the engine's --stream-list which prints the canonical
        # "(no in-progress dispatches)" line when empty.
        $Arguments = @($Arguments | Where-Object { $_ -ne '--stream-list' })
        Invoke-Vortex -Arguments @('--stream-list')
        exit (Get-VortexLastExitCode)
    }
    # Extract the streaming sub-command + args.
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $a = $Arguments[$i]
        if ($a -eq '--stream') {
            if ($i + 1 -lt $Arguments.Count) {
                $taskId = $Arguments[$i + 1]
                $autoOpen = ($Arguments -contains '--auto-open')
                $Arguments[$i] = $null; $Arguments[$i + 1] = $null; $i++
                Start-VortexStream -TaskId $taskId -AutoOpen:$autoOpen
                exit 0
            }
        } elseif ($a -eq '--stream-stop') {
            if ($i + 1 -lt $Arguments.Count) {
                Stop-VortexStream -TaskId $Arguments[$i + 1]
                $Arguments[$i] = $null; $Arguments[$i + 1] = $null; $i++
                exit 0
            }
        } elseif ($a -eq '--hint') {
            if ($i + 2 -lt $Arguments.Count -and $Arguments[$i + 1] -eq '--text') {
                Send-VortexHint -TaskId '' -Text $Arguments[$i + 2]
                # The engine call below handles the real write (the streamer
                # delegates via skill.ps1 --hint, which the engine resolves).
                $Arguments = @($Arguments | Where-Object { $_ -ne $null })
                break
            }
        }
    }
}

# --- 6. Dispatch ------------------------------------------------------------
# Invoke-Vortex is the thin wrapper the Vortex.psm1 module exports. The
# engine is the canonical implementation of every command. Forward argv.
# v0.1.11: short-circuit --audit-trail to use the PowerShell-side viewer
# (lib/Vortex.AuditViewer.psm1). This avoids the engine's basic --audit-trail
# output being mixed with the rich viewer's output.
# v0.3.0 (PRD-17): --compile-memory runs the engine and prints a one-line
# summary. --memory-show <slug> prints the prior-projects-context slice
# that --with-memory would inject into the next dispatch.
if ($Arguments.Count -ge 1 -and $Arguments[0] -eq '--audit-trail' -and -not ($Arguments -contains '--json' -or $Arguments -contains '--json-only')) {
    # v0.3.11.2 (bug fix): when --json is present, skip the audit-viewer
    # short-circuit. The engine's CmdAuditTrail --json path produces a
    # single-line JSON object per docs/cli-json-contract.md. The
    # viewer's --Format json path emits ConvertTo-Json -Depth 5 which
    # is multi-line pretty-printed (the OPPOSITE of the contract).
    # Routing through the viewer would have either stripped --json
    # (pre-v0.3.11.2) or emitted a non-contract-compliant multi-line
    # JSON.
    $viewerPath = Join-Path $here 'lib\Vortex.AuditViewer.psm1'
    if (Test-Path $viewerPath) {
        Import-Module $viewerPath -Force -ErrorAction SilentlyContinue
        $filters = @{}
        $i = 1
        while ($i -lt $Arguments.Count) {
            $a = $Arguments[$i]
            if ($a -eq '--project' -and ($i + 1) -lt $Arguments.Count) { $filters['Project'] = $Arguments[$i + 1]; $i += 2 }
            elseif ($a -eq '--task' -and ($i + 1) -lt $Arguments.Count)     { $filters['Task'] = $Arguments[$i + 1]; $i += 2 }
            elseif ($a -eq '--agent' -and ($i + 1) -lt $Arguments.Count)    { $filters['Agent'] = $Arguments[$i + 1]; $i += 2 }
            elseif ($a -eq '--severity' -and ($i + 1) -lt $Arguments.Count){ $filters['Severity'] = $Arguments[$i + 1]; $i += 2 }
            elseif ($a -eq '--since' -and ($i + 1) -lt $Arguments.Count)   {
                $s = $Arguments[$i + 1]
                if ($s -match '^\d+d$') {
                    $n = [int]($s -replace 'd$', '')
                    $filters['Since'] = (Get-Date).AddDays(-$n)
                } else {
                    $filters['Since'] = [datetime]$s
                }
                $i += 2
            }
            else { $i++ }
        }
        $sinceArg = if ($filters.ContainsKey('Since')) { $filters['Since'] } else { [datetime]::MinValue }
        Get-VortexAuditTrail -As $AuditFormat `
            -Project ($filters['Project']  ?? '') `
            -Task    ($filters['Task']     ?? '') `
            -Agent   ($filters['Agent']    ?? '') `
            -Severity($filters['Severity'] ?? '') `
            -Since   $sinceArg
        exit 0
    }
}

Invoke-Vortex -Arguments $Arguments
$rc = Get-VortexLastExitCode
exit $rc
