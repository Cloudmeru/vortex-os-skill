# PRD-08 — Engine Unavailable: 3-Tier Fallback

**Status:** Draft · Phase 2 (revised 2026-08-27 after user input)
**Owner:** VORTEX-OS maintainers
**Source:** `idea-future-recommendations.md` item 8 + user direction
**Scope:** **Windows only.** Linux/macOS support is explicitly out of scope for phase 2.

---

## 1. Problem

The skill is **self-bootstrapping**: the first `skill.ps1` invocation downloads `Vortex.dll` from the public `vortex-os-dotnet` GitHub release. If that download fails, every command fails with the same error.

**Phase-2 scope (revised):** Windows only. The cross-platform options (A: self-contained .NET host, B: Mono, C: two engines) are deferred. PRD-08 now addresses **only the Windows engine-unavailable failure modes**:

1. Network down at install time
2. GitHub rate-limit hit (60/hr unauthenticated)
3. GitHub outage
4. PSModulePath is broken (OneDrive Files-On-Demand ghost, no writable module path)
5. `install.ps1` itself has a bug
6. The user has an unusual Windows config (corporate proxy, custom install location)

## 2. The 3-tier architecture

```
┌─────────────────────────────────────────────────────────┐
│ Tier 1: PowerShell shell (always present, ~600 LoC)     │
│   14 commands work standalone.                           │
│   Always works, even if engine + LLM are both gone.     │
└─────────────────────────────────────────────────────────┘
            │
            │ if Vortex.dll is present
            ▼
┌─────────────────────────────────────────────────────────┐
│ Tier 2: C++/CLI engine (Vortex.dll, 84 KB)              │
│ Fast, deterministic, reproducible, versioned.           │
│ WINDOWS ONLY.                                           │
└─────────────────────────────────────────────────────────┘
            │
            │ if engine is unavailable AND we're in an
            │ LLM-coding-agent context (Mavis, Codex, etc.):
            ▼
┌─────────────────────────────────────────────────────────┐
│ Tier 3: LLM-as-engine fallback                          │
│ The coding agent's LLM reads SKILL.md, agent manifests, │
│ templates, and acts as the engine for that dispatch.    │
│ Slow (seconds per deliverable) but RESILIENT.           │
└─────────────────────────────────────────────────────────┘
```

**Tier 1 (PowerShell-only):** 14 of 18 commands work end-to-end. Pure file I/O + JSON. Re-implemented in `<skill>/lib/PS-Only/*.ps1`.

**Tier 2 (C++/CLI engine, today's v0.1.9):** The fast path. 4 of 18 commands (the LLM-dispatch ones) plus the engine provides the canonical implementation of the file-I/O commands for the happy path. Already shipped.

**Tier 3 (LLM-as-engine fallback, NEW):** When Tier 2 is unavailable AND the dispatcher is an LLM-coding-agent (Mavis, Codex, Copilot, etc.), the coding agent's own LLM acts as the engine. It reads the agent manifests, runs the LLM chain, writes the deliverables, updates the audit log. Slow but resilient. **No new code to ship** — the LLM is already there.

## 3. Can the LLM "produce its own engine"?

This was the user's question. The honest answer:

**Yes, but as Tier 3, not as a replacement for Tier 2.**

Three reasons to KEEP Tier 2:
1. **Burden analysis.** Asking the LLM to *be* the engine means it has to know the full agent schema, the 8 Continuity Engine rules, the 3-gate HITL pattern, the `.manifest.json` contract, all file paths, all error codes, all C++/CLI build pitfalls. That's ~5K tokens of context and a non-trivial "be a clean engineer" task. The LLM can do it, but the iteration loop is slow.
2. **Reproducibility.** A committed, versioned engine (`vortex-os-dotnet` releases `v0.1.9`) is the same on every machine. An LLM-regenerates-engine model means N machines have N subtly different engines. Bug fixes can't be one-line PRs.
3. **Speed.** Engine runs in microseconds. LLM runs in seconds-to-minutes per dispatch step. 7-deliverable episode: 30s vs 30min.

**Tier 3 is the right place for LLM-as-engine:**
- Slow path, opt-in (only when Tier 2 fails)
- No code generation — the LLM just *runs the workflow* with its own reasoning
- Output is the same deliverables, same manifest, same audit log
- Documented recipe: "if you got here, the LLM is the engine for this one dispatch"

The user's insight that "the LLM can produce its own solution" is exactly right — but the solution isn't "compile a new C++ engine"; it's "be the engine for this one dispatch."

## 4. Goals

1. **The skill shell never blocks on a missing engine.** Every command returns either a result or a clear "next step" message.
2. **Tier 1 is robust.** The 14 file-I/O commands are re-implemented in PowerShell and tested independently of the engine.
3. **Tier 3 is documented.** When a coding agent (Mavis/Codex) hits Tier 2 missing, there's a recipe in `SKILL.md` (or `references/LLM-FALLBACK.md`) that tells the LLM what to do.
4. **Recovery is one command.** `--recover-engine` retries the install.
5. **No cross-platform code in v1.x.** All paths assume Windows. Linux/mac is a v2.x conversation.

## 5. Non-goals

- **Linux/macOS support.** Explicitly deferred per user direction.
- **A self-contained .NET engine (option A).** Deferred.
- **Mono runtime (option B).** Deferred.
- **Two-engine strategy (option C).** Deferred.
- **Re-implementing the 4-tier dispatch chain in PowerShell.** That's a rewrite, not a degraded mode.
- **A pure-PowerShell Continuity Engine.** The 8+ rules are non-trivial; PowerShell could do crude regex but false positives are unacceptable.

## 6. Design

### 6.1 Tier 1 — PowerShell-only commands (14 of 18)

Move the engine-side implementations of these commands to `<skill>/lib/PS-Only/*.ps1`:

| Command | Current engine impl | PowerShell impl |
|---|---|---|
| `--version` | reads banner | reads `CHANGELOG.md` head line |
| `--help` | static text in `skill.cpp` | static text in `<skill>/lib/PS-Only/Help.ps1` |
| `--agents-discover` | reads `agents/*.json` | `Get-ChildItem agents/*.json \| ConvertFrom-Json` |
| `--agents-inspect <name>` | reads + pretty-prints | `Get-Content agents/<name>.json \| ConvertFrom-Json` |
| `--agents-validate <file>` | `Test-Json` + 8-invariant lint | same, moved to PowerShell |
| `--agents-lint [--all\|<name>]` | walks all agents, lints each | same, moved to PowerShell |
| `--agents-graph` | ASCII tree from `triggers[]` | same, moved to PowerShell |
| `--agents-trace <run_id>` | reads `swarms/active_<id>/*` | same, moved to PowerShell |
| `--audit-trail` | last 50 lines of `memory/audit.jsonl` | same, moved to PowerShell |
| `--hitl-status` | `Get-ChildItem state/pending_approvals/*.json` | same, moved to PowerShell |
| `--hitl-approve <task_id>` | writes approved JSON | same, moved to PowerShell |
| `--hitl-deny <task_id>` | writes denied JSON | same, moved to PowerShell |
| `--decision-list` | reads `state/decision_history.json` | same, moved to PowerShell |
| `--decision-record` | appends to `state/decision_history.json` | same, moved to PowerShell |
| `--package <id> [--dry-run]` | copy + manifest + SHA-1 (C++) | same, SHA-1 in `[System.Security.Cryptography.SHA1]::Create()` |

All 14 share the same file paths. The engine and PowerShell both read/write the same JSON shapes.

**Effort: ~600 LoC of PowerShell, ~150 LoC of tests.**

### 6.2 Tier 2 — the engine (today's v0.1.9, unchanged)

The C++/CLI engine stays exactly as it is. **No engine changes for PRD-08.**

The engine continues to handle:
- The 4 engine-only commands (`--dispatch-master/template/v4`, `--inspector-check`)
- The Continuity Engine rule evaluation
- The SHA-1 checksum (slightly faster than the PowerShell version, but identical output)

### 6.3 Tier 3 — LLM-as-engine fallback

When Tier 2 is unavailable AND the dispatcher is an LLM-coding-agent, the LLM becomes the engine. This is documented in `<skill>/references/LLM-FALLBACK.md` (a new file). The recipe:

```markdown
# LLM-as-Engine Fallback

If `skill.ps1 --dispatch-master <objective.md>` returns
"engine unavailable", and you (the LLM reading this) are
a coding agent (Mavis, Codex, Copilot, etc.), you can
act as the engine for this dispatch.

## What to do

1. Read the objective file: `<objective.md>`
2. Read the agent manifests: `<skill>/agents/*.json`
3. Read the templates: `<skill>/templates/*.json`
4. Read the decisions: `$VORTEX_HOME/state/decision_history.json`
5. For each deliverable in the objective's `deliverables[]`:
   a. Pick the matching agent (from the manifest's `capability`)
   b. Construct the prompt (objective + agent instructions + prior decisions)
   c. Call the LLM (yourself)
   d. Apply the 8 Continuity Engine rules (read SKILL.md section "Continuity Engine")
   e. If a rule fails: re-prompt with a hardened version (read the existing
      `state/prompt_optimizations/<agent>_<ts>.json` files for examples)
   f. Write the deliverable to `$VORTEX_HOME/deliverables/<project>/<file>`
   g. Append to `memory/audit.jsonl` (use the schema in the audit viewer PRD)
6. After all deliverables: write the `.manifest.json` and yield for the
   Gate 3 (final pack) approval.

## What NOT to do

- Do NOT try to compile a new C++ engine. The user's directive is "skip Linux/mac, focus on Windows." On Windows, the engine either works or it doesn't; you can't rebuild it from inside a PowerShell session.
- Do NOT regenerate the entire skill folder. The skill is the user's source of truth.
- Do NOT touch the user's `VORTEX_HOME` state files outside of the standard deliverables + audit + decision paths.

## When to give up

- If the LLM doesn't have enough context (e.g. the manifest schema is unclear), tell the user "engine unavailable, here's a manual recipe: <link to SKILL.md>".
- If the deliverable requires a tool the LLM doesn't have (e.g. ffmpeg for audio chopping), tell the user "this deliverable needs ffmpeg; install it via `winget install Gyan.FFmpeg` and re-run".
```

The recipe is ~100 lines of Markdown. The LLM reads it, follows the steps, produces the deliverables. No code changes to the skill.

**Effort: ~100 LoC of Markdown documentation. Zero code.**

### 6.4 Detection in `skill.ps1`

```powershell
# Find the engine manifest
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
    Write-Host "  | Tier 1 (PowerShell): 14 commands work." -ForegroundColor Yellow
    Write-Host "  | Tier 2 (C++/CLI):     4 commands unavailable." -ForegroundColor Yellow
    Write-Host "  | Tier 3 (LLM fallback): if you're an LLM coding agent, see" -ForegroundColor Yellow
    Write-Host "  |   <skill>/references/LLM-FALLBACK.md" -ForegroundColor Yellow
    Write-Host "  | Run:  pwsh -NoProfile -File .\skill.ps1 --recover-engine" -ForegroundColor Yellow
    Write-Host "  +-----------------------------------------+" -ForegroundColor Yellow
}
```

### 6.5 New commands

```powershell
# Print which tier is active + which commands work in each tier
pwsh -NoProfile -File .\skill.ps1 --health

# Retry engine install
pwsh -NoProfile -File .\skill.ps1 --recover-engine

# Force a re-check of the engine (skip 6h cache)
pwsh -NoProfile -File .\skill.ps1 --recover-engine -Force
```

### 6.6 New env vars

```powershell
$env:VORTEX_NO_ENGINE = '1'   # force Tier 1 (skip engine even if installed)
$env:VORTEX_NO_ENGINE = '0'   # require engine (throw if missing)
# unset: best-effort (use Tier 2 if available, fall back to Tier 1)
```

## 7. API surface

### New files (skill-side)

```
<skill>/
  lib/
    PS-Only/
      Help.ps1
      Version.ps1
      Agents.ps1           # discover, inspect, validate, lint, graph, trace
      AuditTrail.ps1
      Hitl.ps1             # status, approve, deny
      Decisions.ps1        # list, record
      Package.ps1          # + SHA-1 in PowerShell
  references/
    LLM-FALLBACK.md        # the Tier 3 recipe
```

### New commands

```
--health                  # print tier + command matrix
--recover-engine          # retry install.ps1
--recover-engine -Force   # skip 6h auto-update cache
```

### Behavior changes

| Command | Engine present | Engine absent |
|---|---|---|
| 14 file-I/O commands | engine | **PS (Tier 1)** |
| `--dispatch-master/template/v4` | engine | **Tier 3 recipe** (clear hint to read `LLM-FALLBACK.md` if in LLM context) |
| `--inspector-check` | engine | **Tier 3 recipe** |

## 8. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| PS implementations of the 14 commands diverge from the C++ versions | High | Medium | `tests/test_engine.ps1` runs each command in both Tier 1 and Tier 2 mode and diffs the output. |
| Tier 3 (LLM fallback) is slow | High | Low | Tier 3 is opt-in (only when Tier 2 fails). Users on a working Tier 2 never touch it. |
| A coding agent LLM misinterprets the Tier 3 recipe and does the wrong thing | Medium | Medium | The recipe is explicit about what to do AND what not to do. Tests in `verify.ps1` assert the recipe file exists and contains the key steps. |
| The LLM regenerates the engine from scratch (against directive) | Low | High | The recipe explicitly says "Do NOT try to compile a new C++ engine." Plus: on Windows, the engine either works or it doesn't. There's no in-session way to compile. |
| Tier 1 (PowerShell) is slower than Tier 2 for the same command | Low | Low | SHA-1 in PowerShell uses the same .NET API. Other commands are pure file I/O. Negligible difference. |
| Cross-platform users (someone on Linux/macOS) hit the Tier 1 banner | Low | Low | The banner says "Windows only." A Linux user gets the same Tier 1 behavior (14 commands work) and the Tier 2 / Tier 3 hints are advisory. |

## 9. Acceptance criteria

1. `pwsh -NoProfile -File .\skill.ps1 --health` works without any engine installed and shows the tier + command matrix.
2. `pwsh -NoProfile -File .\skill.ps1 --agents-discover` works in Tier 1 mode and returns the same agent list as Tier 2.
3. `pwsh -NoProfile -File .\skill.ps1 --package <id>` works in Tier 1 mode and produces a `.manifest.json` with valid 16-hex SHA-1 checksums (identical to Tier 2's).
4. `pwsh -NoProfile -File .\skill.ps1 --decision-list` / `--decision-record` work in Tier 1 mode and the file format matches what Tier 2 writes.
5. `pwsh -NoProfile -File .\skill.ps1 --dispatch-master <md>` in Tier 1 mode prints a clear message pointing to `references/LLM-FALLBACK.md`.
6. The `references/LLM-FALLBACK.md` file exists and contains the recipe (verified by a test in `verify.ps1`).
7. `pwsh -NoProfile -File .\skill.ps1 --recover-engine` either succeeds (engine installed) or prints a clear network/GitHub error.
8. With the engine installed, every command behaves exactly as it does today (no behavior change for the happy path).
9. `verify.ps1` adds `tests/test_tier1.ps1` that runs every Tier 1 command in `$env:VORTEX_NO_ENGINE = 1` mode and asserts the output.
10. `verify.ps1` adds `tests/test_tier2_compat.ps1` that runs the same commands in Tier 2 mode and diffs the output against Tier 1.

## 10. Effort

- `lib/PS-Only/*.ps1` (14 commands): ~600 LoC
- `lib/Vortex.Streamer.psm1` (the engine detection + dispatch): ~150 LoC
- `references/LLM-FALLBACK.md`: ~100 LoC of Markdown
- New tests: ~300 LoC (`tests/test_tier1.ps1` + `tests/test_tier2_compat.ps1`)
- `verify.ps1` integration: ~50 LoC
- Engine changes: **0 LoC**

**Total: ~1200 LoC of skill-side code + ~100 LoC of docs. 1 PR. ~1 week for a single engineer.**

## 11. Open questions

- **Q1.** Should Tier 3 (LLM fallback) be opt-in via a flag, or automatic when the dispatcher is an LLM-coding-agent? — *Recommend: automatic, gated by detection. The skill shell detects `Mavis/Codex/Copilot` env vars and shows the Tier 3 hint. For non-LLM dispatchers, just shows the Tier 2 error.*
- **Q2.** Should the Tier 1 PS implementations cache their results so a Tier 2 (re-)install doesn't re-run everything? — *Recommend: no, file I/O is fast and stale cache hides real bugs.*
- **Q3.** When the engine recovers, should the next dispatch auto-use Tier 2? — *Recommend: yes, no special action needed. The detection is per-invocation.*
- **Q4.** Should the Tier 3 recipe be in `SKILL.md` (visible to the trigger-detection LLM) or in a separate file? — *Recommend: separate file `references/LLM-FALLBACK.md`. SKILL.md stays lean.*
- **Q5.** Should the LLM fallback write a special `state/last_tier3_dispatch.json` so a human operator can see when the LLM took over? — *Recommend: yes, useful for audit. The file lists the task_id, the start/end timestamps, the deliverables produced, and the agent(s) used.*

## 12. Future work (deferred to v2.x)

- **Linux/macOS support** — option A (self-contained .NET host), B (Mono), or C (two engines). The user has explicitly deferred this.
- **Native CLI for Mac/Linux** — `vortex` binary (not `skill.ps1`) for users who don't have PowerShell. Deferred.
- **Tier 3 verification** — a test that runs `pwsh -NoProfile -File .\skill.ps1 --dispatch-master ...` with the engine absent and the dispatcher set to a mock LLM, then asserts the deliverables are correct. Hard to do in CI; maybe a manual smoke test.
