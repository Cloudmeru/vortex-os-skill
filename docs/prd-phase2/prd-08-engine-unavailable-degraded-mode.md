# PRD-08 — Engine Unavailable: Degraded Mode

**Status:** Draft · Phase 2
**Owner:** VORTEX-OS maintainers
**Source:** `idea-future-recommendations.md` item 8, plus the user's request:
> "if the engine is unavailable due to failed download, can it still run and survive with all the process? think about this approach, output as prd"

**Related:** directly enables PRD-11 (item 8 option C — two engines) and is the foundation for cross-platform support in v1.0+.

---

## 1. Problem

The skill is **self-bootstrapping**: the first `skill.ps1` invocation downloads `Vortex.dll` from the public `vortex-os-dotnet` GitHub release and installs it into `~\Documents\PowerShell\Modules\Vortex\<version>\`. If that download fails, **every command fails** with the same error:

```
[vortex-os] Engine not found locally -- running installer (one-time, downloads from GitHub release) ...
[vortex-os] v0.1.9 already installed at C:\Users\...\Vortex\0.1.9 -- nothing to do.
...or:
ERROR: None of the PSModulePath entries are writable for the current user.
```

The user can't even read the help, lint a custom agent, list pending HITL gates, or replay a saved decision. The skill is **all-or-nothing** today.

This bites in three scenarios:

1. **One-time install with a flaky network** — GitHub rate-limits unauthenticated requests to 60/hour. A user hitting the limit at install time can't recover without manual work.
2. **GitHub outage / region block** — the engine source is a single point of failure.
3. **Cross-platform option C** (item 8) — even if we ship a Linux/macOS C# engine, there will be a window where neither engine is built. The skill shell must survive that window.

## 2. Can the engine be unavailable and the skill still work?

**Yes — partially.** Most of the engine's surface is file I/O that PowerShell can re-implement in ~100 lines:

| Command | Engine today? | Can PS do it alone? | Notes |
|---|---|---|---|
| `--version` | yes | ✅ trivial | Just print `$skillFolder\CHANGELOG.md` head line |
| `--help` | yes | ✅ trivial | Static text in skill.ps1 |
| `--agents-discover` | yes | ✅ trivial | `Get-ChildItem agents\*.json` + parse |
| `--agents-inspect <name>` | yes | ✅ trivial | `Get-Content agents\<name>.json` |
| `--agents-validate <file>` | yes | ✅ trivial | `Test-Json` + schema check |
| `--agents-lint [--all]` | yes | ✅ trivial | Walk agents/, run validate on each |
| `--agents-graph` | yes | ✅ medium | Parse `triggers[]` / `escalates_to[]` + ASCII tree |
| `--agents-trace <run_id>` | yes | ✅ trivial | Read `swarms\active_<id>\memory\*.json` |
| `--audit-trail` | yes | ✅ trivial | Read last 50 lines of `memory\audit.jsonl` |
| `--hitl-status` | yes | ✅ trivial | `Get-ChildItem state\pending_approvals\*.json` |
| `--hitl-approve <task_id>` | yes | ✅ trivial | Write approved JSON to checkpoint file |
| `--hitl-deny <task_id>` | yes | ✅ trivial | Write denied JSON to checkpoint file |
| `--decision-list` | yes | ✅ trivial | Read `state\decision_history.json` |
| `--decision-record` | yes | ✅ trivial | Append to `state\decision_history.json` |
| `--package <id> [--dry-run]` | yes | ✅ medium | Copy + write manifest. SHA-1 in PowerShell: `[System.Security.Cryptography.SHA1]::Create().ComputeHash(...)` |
| `--dispatch-master` | yes | ❌ | LLM call + 4-tier chain. Requires engine. |
| `--dispatch-template` | yes | ❌ | Renders template + dispatches. Requires engine. |
| `--dispatch-v4` | yes | ❌ | Runs the master pipeline. Requires engine. |
| `--inspector-check` | yes | ❌ | Continuity Engine rule checks. Requires engine. |

**Conclusion: 14 of 18 commands can be re-implemented in pure PowerShell with no engine. The 4 that need the engine are the ones that actually do work (LLM calls + rule evaluation).**

The skill becomes a **layered system**:

```
┌─────────────────────────────────────────────┐
│ PowerShell shell (skill.ps1 + helpers)      │  ← ALWAYS present
│  - routing                                  │
│  - file I/O commands (14 of 18)             │
│  - degraded-mode banner + recovery hints    │
└─────────────────────────────────────────────┘
            │
            │ loads if present
            ▼
┌─────────────────────────────────────────────┐
│ C++/CLI engine (Vortex.dll)                 │  ← Windows primary
│  - 4-tier dispatch chain                    │
│  - LLM coordination                         │
│  - Continuity Engine (rule eval)            │
│  - Self-heal optimizer                      │
└─────────────────────────────────────────────┘
            │
            │ or, alternative engine (option C, item 8)
            ▼
┌─────────────────────────────────────────────┐
│ C# engine (Vortex.dll, .NET 10 only)        │  ← Linux/macOS
│  - same surface, slower (no IJW)            │
└─────────────────────────────────────────────┘
```

The PowerShell layer doesn't care which engine is loaded — it just calls `Invoke-Vortex` and checks `$LASTEXITCODE`. If no engine is present, the PowerShell commands still work; the engine-only commands print a clear "engine unavailable, here is how to recover" message.

## 3. Goals

1. **The skill shell survives a failed engine install.** All non-engine commands work end-to-end after a network failure.
2. **The skill shell is cross-platform-ready.** The PowerShell layer never assumes Vortex.dll; the same code works on Windows / Linux / macOS.
3. **The user always knows which commands are unavailable and why.** A single `--health` command reports the engine state, VORTEX_HOME, and a list of degraded-mode-capable commands.
4. **Recovery is one command.** `--recover-engine` retries the install (with `--force` to bypass any 6h auto-update rate limit) and re-detects.
5. **No new auto-update rate-limit surprise.** The 6h cache is per-`VORTEX_HOME`, not per-machine, so a fresh VORTEX_HOME gets a fresh check.

## 4. Non-goals

- **Re-implementing the 4-tier dispatch chain in PowerShell.** That's a rewrite of the engine, not a degraded mode. The 4 engine-only commands stay engine-only.
- **A pure-PowerShell Continuity Engine.** Continuity Engine has 8+ rules with non-trivial content analysis (anachronism detection, character-consistency checks). PowerShell could do crude regex versions, but the false-positive rate would be unacceptable. Keep the rule eval in the engine.
- **Replacing `install.ps1`.** Degraded mode is the fallback when install fails, not an alternative install path.
- **Self-update of the PowerShell layer.** The PowerShell layer is the skill folder, which already auto-syncs when the user updates the skill from the source repo. No new mechanism needed.

## 5. Design

### 5.1 Detection

In `skill.ps1`, replace the current "engine not found → throw" path with:

```powershell
# Find the engine manifest (returns $null if missing)
$manifest = Find-VortexManifest

$engineAvailable = $false
if ($manifest) {
    try {
        Import-Module $manifest -Force -ErrorAction Stop
        $engineAvailable = $true
    } catch {
        Write-Host "[vortex-os] Engine found at $manifest but failed to load: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

if (-not $engineAvailable) {
    Write-Host ""
    Write-Host "  +-- VORTEX-OS Engine: NOT AVAILABLE --+" -ForegroundColor Yellow
    Write-Host "  | 14 of 18 commands work in PS-only mode." -ForegroundColor Yellow
    Write-Host "  | Engine-only commands (--dispatch-*, --inspector-check) will fail with a clear message." -ForegroundColor Yellow
    Write-Host "  | Run:  pwsh -NoProfile -File .\skill.ps1 --recover-engine" -ForegroundColor Yellow
    Write-Host "  +-----------------------------------------+" -ForegroundColor Yellow
    Write-Host ""
    $script:EngineAvailable = $false
    $script:EngineManifest = $null
} else {
    $script:EngineAvailable = $true
    $script:EngineManifest = $manifest
}
```

### 5.2 New commands (all PowerShell-only)

Add to `skill.ps1` as native functions (no engine needed):

```powershell
# Print one line per command: status (OK/DEGRADED) + description
function Invoke-Health {
    $rows = @(
        @{ cmd = '--version';             status = 'OK';       note = 'reads SKILL.md' }
        @{ cmd = '--help';                status = 'OK';       note = 'static text' }
        @{ cmd = '--agents-discover';     status = 'OK';       note = 'reads agents/*.json' }
        @{ cmd = '--agents-inspect';      status = 'OK';       note = 'reads agents/<name>.json' }
        @{ cmd = '--agents-validate';     status = 'OK';       note = 'Test-Json + schema' }
        @{ cmd = '--agents-lint';         status = 'OK';       note = 'walks agents/, runs validate' }
        @{ cmd = '--agents-graph';        status = 'OK';       note = 'ASCII tree from triggers[]' }
        @{ cmd = '--audit-trail';         status = 'OK';       note = 'reads memory/audit.jsonl' }
        @{ cmd = '--hitl-status';         status = 'OK';       note = 'reads state/pending_approvals/' }
        @{ cmd = '--hitl-approve';        status = 'OK';       note = 'writes checkpoint JSON' }
        @{ cmd = '--hitl-deny';           status = 'OK';       note = 'writes checkpoint JSON' }
        @{ cmd = '--decision-list';       status = 'OK';       note = 'reads decision_history.json' }
        @{ cmd = '--decision-record';     status = 'OK';       note = 'appends to decision_history.json' }
        @{ cmd = '--package';             status = 'OK';       note = 'file copy + manifest + SHA-1 in PS' }
        @{ cmd = '--dispatch-master';     status = 'ENGINE';   note = 'requires Vortex.dll' }
        @{ cmd = '--dispatch-template';   status = 'ENGINE';   note = 'requires Vortex.dll' }
        @{ cmd = '--dispatch-v4';         status = 'ENGINE';   note = 'requires Vortex.dll' }
        @{ cmd = '--inspector-check';     status = 'ENGINE';   note = 'requires Vortex.dll' }
    )
    Write-Host "VORTEX-OS health report"
    Write-Host "======================="
    Write-Host ("  Engine:        {0}" -f ($(if ($script:EngineAvailable) { "loaded ($script:EngineManifest)" } else { "NOT AVAILABLE" })))
    Write-Host ("  VORTEX_HOME:   $env:VORTEX_HOME")
    Write-Host ("  Skill folder:  $env:VORTEX_SKILL_ROOT")
    Write-Host ""
    Write-Host "  Status  Command"
    Write-Host "  ------  -------"
    foreach ($r in $rows) {
        $tag = if ($r.status -eq 'OK') { '[OK]    ' } else { '[ENGINE]' }
        Write-Host ("  {0}  {1,-22}  {2}" -f $tag, $r.cmd, $r.note)
    }
}

# Retry the engine install (calls install.ps1, optionally with -Force on the auto-update)
function Invoke-RecoverEngine {
    $env:VORTEX_NO_AUTO_UPDATE = '0'
    $installer = Join-Path $env:VORTEX_SKILL_ROOT 'install.ps1'
    if (-not (Test-Path $installer)) { throw "install.ps1 not found at $installer" }
    Write-Host "[vortex-os] Retrying engine install..." -ForegroundColor Cyan
    & pwsh -NoProfile -File $installer
    if ($LASTEXITCODE -ne 0) { throw "install.ps1 failed: $LASTEXITCODE" }
    Write-Host "[vortex-os] Re-detecting engine..." -ForegroundColor Cyan
    $newManifest = Find-VortexManifest
    if ($newManifest) {
        Write-Host "[vortex-os] Engine recovered at $newManifest" -ForegroundColor Green
    } else {
        Write-Host "[vortex-os] install.ps1 ran but no Vortex.psd1 found. Check network / GitHub status." -ForegroundColor Red
        exit 1
    }
}
```

### 5.3 Engine-only command behavior

When the user runs an engine-only command in degraded mode, print a clear error:

```powershell
function Invoke-DispatchMaster {
    if (-not $script:EngineAvailable) {
        Write-Host ""
        Write-Host "ERROR: --dispatch-master requires the VORTEX-OS engine (Vortex.dll)." -ForegroundColor Red
        Write-Host ""
        Write-Host "  Why: The 4-tier dispatch chain runs LLM calls and the Continuity Engine."
        Write-Host "       PowerShell alone cannot do this."
        Write-Host ""
        Write-Host "  How to recover:"
        Write-Host "    1. Run:  pwsh -NoProfile -File .\skill.ps1 --recover-engine"
        Write-Host "    2. If that fails, run install.ps1 -Verbose to see the network error."
        Write-Host "    3. If GitHub is unreachable, try a different network or pin a version:"
        Write-Host "         \$env:VORTEX_VERSION = 'v0.1.9'"
        Write-Host "         pwsh -NoProfile -File .\install.ps1"
        Write-Host ""
        exit 2
    }
    Invoke-Vortex -Arguments @('--dispatch-master', $MasterPath)
}
```

The same pattern wraps `--dispatch-template`, `--dispatch-v4`, and `--inspector-check`.

### 5.4 What changes in the engine

**Nothing.** The engine stays exactly as it is. The PowerShell layer just learns to cope with it being absent.

This is a **skill-only change**. Estimated effort: ~300 lines added to `skill.ps1`, ~100 lines of test coverage in `verify.ps1` + a new test script.

## 6. API surface

### New commands (skill-side)

```powershell
# 1. Print health report
pwsh -NoProfile -File .\skill.ps1 --health

# 2. Retry engine install
pwsh -NoProfile -File .\skill.ps1 --recover-engine

# 3. Force a re-check of the engine (skip the 6h cache)
pwsh -NoProfile -File .\skill.ps1 --recover-engine -Force
```

### Existing commands — behavior changes

| Command | Engine present | Engine absent |
|---|---|---|
| `--version`, `--help` | same | same |
| `--agents-discover` | engine | **PS (new)** — reads agents/ directly |
| `--agents-inspect`, `--agents-validate`, `--agents-lint` | engine | **PS (new)** — file I/O + `Test-Json` |
| `--agents-graph` | engine | **PS (new)** — ASCII tree |
| `--agents-trace` | engine | **PS (new)** — reads swarms/ |
| `--audit-trail` | engine | **PS (new)** — last 50 lines of audit.jsonl |
| `--hitl-status` | engine | **PS (new)** — pending_approvals/ |
| `--hitl-approve`, `--hitl-deny` | engine | **PS (new)** — write checkpoint |
| `--decision-list`, `--decision-record` | engine | **PS (new)** — decision_history.json |
| `--package` | engine | **PS (new)** — copy + manifest + SHA-1 in PS |
| `--dispatch-master`, `--dispatch-template`, `--dispatch-v4`, `--inspector-check` | engine | **clear error + recovery instructions** |

### New env var

```powershell
$env:VORTEX_NO_ENGINE = '1'  # force degraded mode (skip engine import even if installed)
$env:VORTEX_NO_ENGINE = '0'  # require engine (throw if missing)
# unset: best-effort — use engine if available, fall back to PS otherwise
```

## 7. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| PS implementations of the engine commands diverge from the C++ versions (different output, different edge cases) | High | Medium | Phase 1: PS impl writes the same JSON shapes. Phase 2: a `tests/test_engine.ps1` regression check that runs the same command via both paths (when engine is loaded) and diffs the output. |
| SHA-1 in PowerShell is slow for large files | Low | Low | `System.Security.Cryptography.SHA1` is the same .NET API the C++ engine uses; perf should be identical. |
| Users in degraded mode get the wrong idea ("oh, the engine is gone, the skill is broken") | Medium | Low | The health banner + every engine-only error explains the situation. The 14 working commands make it clear the skill is functional, just limited. |
| Two impls of the same command means twice the bug surface | Medium | Medium | PS impl is the "dumb" file-I/O version; engine impl is the "smart" compute version. The PS impl is the fallback, so a regression only affects degraded mode. |
| An engine-only command sneaks in without degraded-mode handling | Low | High | A test in `verify.ps1` that runs every engine-only command in `$env:VORTEX_NO_ENGINE = 1` mode and asserts the error message is "engine unavailable". |

## 8. Acceptance criteria

1. `pwsh -NoProfile -File .\skill.ps1 --health` works without any engine installed and shows the 14 OK + 4 ENGINE rows.
2. `pwsh -NoProfile -File .\skill.ps1 --agents-discover` works in degraded mode and returns the same agent list as the engine version.
3. `pwsh -NoProfile -File .\skill.ps1 --package <id>` works in degraded mode and produces a `.manifest.json` with valid 16-hex SHA-1 checksums.
4. `pwsh -NoProfile -File .\skill.ps1 --decision-list` / `--decision-record` work in degraded mode and the file format matches what the engine writes.
5. `pwsh -NoProfile -File .\skill.ps1 --dispatch-master <md>` in degraded mode prints a clear "engine unavailable, run --recover-engine" error and exits 2.
6. `pwsh -NoProfile -File .\skill.ps1 --recover-engine` either succeeds (engine installed) or prints a clear network/GitHub error.
7. With the engine installed, every command behaves exactly as it does today (no behavior change for the happy path).
8. `verify.ps1` adds a new check `tests/test_degraded_mode.ps1` that sets `VORTEX_NO_ENGINE=1` and exercises every degraded-mode command.

## 9. Open questions

- **Q1.** Should the PS implementation of `--package` skip the SHA-1 checksum (it's optional per ADR-015) when the engine is absent, or always compute it? — *Recommend: always compute (same .NET SHA-1, identical perf).*
- **Q2.** Should the PS layer cache the engine's output for `--agents-lint` so a fresh install can replay the cache while the engine is being downloaded? — *Recommend: no, the lint is fast and stale cache hides real bugs.*
- **Q3.** When the engine recovers, should we re-run the previous failed dispatch automatically, or require the user to re-invoke? — *Recommend: require re-invoke. The dispatch is heavy and the operator may have moved on.*
- **Q4.** Should `--health` be JSON-able for CI consumption? — *Recommend: yes, add `--health --json`.*

## 10. Effort

- `skill.ps1` changes: ~300 lines
- New tests: ~200 lines (`tests/test_degraded_mode.ps1`)
- `verify.ps1` integration: ~50 lines
- Documentation: `idea-future-recommendations.md` item 8 → ✅ status, `references/INSTRUCTIONS.md` updated
- Engine changes: **0 lines**

**Total: ~550 lines of skill-side code. 1 PR. ~2-3 days for a single engineer.**
