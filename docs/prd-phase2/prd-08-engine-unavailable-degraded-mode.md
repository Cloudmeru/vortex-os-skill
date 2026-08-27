# PRD-08 — Engine Unavailable: 2-Tier Fallback (Engine + LLM)

**Status:** Draft · Phase 2 (revised 2026-08-27 after user input)
**Owner:** VORTEX-OS maintainers
**Source:** `idea-future-recommendations.md` item 8 + user direction
**Scope:** **Windows only.** Linux/macOS support is explicitly out of scope for phase 2.

> **Revised architecture (2026-08-27, second user direction):** The earlier 3-tier design (PowerShell shell + C++ engine + LLM fallback) had a Tier 1 "PowerShell-only re-implementation of 14 commands" idea. The user has rejected that approach: a separate PowerShell implementation would be a parallel engine to maintain, with no shared code, no shared tests, and a long-term divergence risk. **The C++/CLI engine is the only engine. The PowerShell shell is just routing. Period.**
>
> The revised 2-tier design:
> - **Tier 1: C++/CLI engine (Vortex.dll).** Always present in production. The canonical implementation of every command.
> - **Tier 2: LLM-as-engine fallback.** When the engine is unavailable AND the dispatcher is an LLM-coding-agent (Mavis, Codex, Copilot), the LLM reads SKILL.md + agent manifests + templates and acts as the engine for that one dispatch. Documented as a recipe, not a re-implementation.
>
> The PowerShell `skill.ps1` is now strictly a thin routing layer: parse args, load the engine, forward. No parallel implementations of any command.

---

## 1. Problem

The skill is **self-bootstrapping**: the first `skill.ps1` invocation downloads `Vortex.dll` from the public `vortex-os-dotnet` GitHub release. If that download fails, every command fails with the same error.

**Phase-2 scope:** Windows only. The cross-platform options (A: self-contained .NET host, B: Mono, C: two engines) are deferred. This PRD now addresses **only the Windows engine-unavailable failure modes**:

1. Network down at install time
2. GitHub rate-limit hit (60/hr unauthenticated)
3. GitHub outage
4. PSModulePath is broken (OneDrive Files-On-Demand ghost, no writable module path)
5. `install.ps1` itself has a bug
6. The user has an unusual Windows config (corporate proxy, custom install location)

## 2. The 2-tier architecture

```
┌─────────────────────────────────────────────────────────┐
│ PowerShell shell (skill.ps1)                            │
│ THIN ROUTING ONLY. ~50 LoC.                              │
│  - parse args                                           │
│  - find / install / load the engine                     │
│  - forward argv to engine                               │
│  - show health banner if engine missing                 │
│  - show Tier 2 recipe pointer if dispatch is attempted  │
└─────────────────────────────────────────────────────────┘
            │
            │ if Vortex.dll is present (the ONLY engine)
            ▼
┌─────────────────────────────────────────────────────────┐
│ Tier 1: C++/CLI engine (Vortex.dll, 84 KB, v0.1.9+)     │
│ Canonical implementation of every command.              │
│ - 4-tier dispatch, Continuity Engine, self-heal          │
│ - File I/O (audit trail, HITL, decisions, package)      │
│ - Discovery, lint, validate, graph                      │
│ - The only engine. No parallel implementations.         │
│ WINDOWS ONLY.                                           │
└─────────────────────────────────────────────────────────┘
            │
            │ if engine is unavailable AND we're in an
            │ LLM-coding-agent context (Mavis, Codex, etc.):
            ▼
┌─────────────────────────────────────────────────────────┐
│ Tier 2: LLM-as-engine fallback                          │
│ DOCUMENTED RECIPE ONLY. No code.                         │
│ The LLM reads SKILL.md + agent manifests + templates     │
│ + decision history, and acts as the engine for that      │
│ one dispatch. Writes the deliverables, audit log,        │
│ manifest, and decisions itself.                         │
│ Slow (seconds per deliverable) but RESILIENT.           │
└─────────────────────────────────────────────────────────┘
```

**What the PowerShell shell is NOT:** it is not a parallel engine. It does not re-implement any command. If the C++ engine is missing, the PowerShell shell does nothing useful (except show a banner and the Tier 2 recipe).

**Why this design (rejected the earlier 3-tier):**
- A separate PowerShell implementation of the 14 file-I/O commands would be a parallel engine to maintain. No shared code, no shared tests, long-term divergence risk.
- The user wants ONE engine (the C++ one) and ONE source of truth (the engine source repo). Not two implementations that drift.
- For the few cases where the engine is genuinely unavailable, the LLM-as-engine fallback is enough. It's a one-shot recipe, not a parallel implementation.
- The PowerShell shell stays minimal (~50 LoC of routing). Every behavior is in the engine.

## 3. Goals

1. **The C++ engine is the only engine.** No parallel PowerShell implementations of any command.
2. **When the engine is missing, the user always knows how to recover.** A clear banner + `--recover-engine` + Tier 2 recipe pointer.
3. **Tier 2 (LLM fallback) is documented.** When a coding agent (Mavis/Codex) hits Tier 1 missing, there's a recipe in `references/LLM-FALLBACK.md` that tells the LLM what to do.
4. **Recovery is one command.** `--recover-engine` retries the install.
5. **No cross-platform code in v1.x.** All paths assume Windows. Linux/mac is a v2.x conversation.

## 4. Non-goals

- **Linux/macOS support.** Explicitly deferred per user direction.
- **A self-contained .NET engine (option A).** Deferred.
- **Mono runtime (option B).** Deferred.
- **Two-engine strategy (option C).** Deferred.
- **Re-implementing any engine command in PowerShell.** Rejected per user direction. The PowerShell shell is routing only.
- **A pure-PowerShell degraded mode.** Rejected per user direction. If the engine is missing, the user gets a clear error + the LLM fallback recipe.

## 5. Design

### 5.1 The PowerShell shell (skill.ps1) is thin

The shell's responsibilities are limited to:

1. Find the engine manifest (`Find-VortexManifest`).
2. If missing, try to install it (`install.ps1`).
3. If still missing, show the Tier 2 banner and exit cleanly.
4. If present, `Import-Module` and `Invoke-Vortex -Arguments $args`.
5. Two new flags: `--health` (print tier status) and `--recover-engine` (retry install).

**No parallel implementations.** No `lib/PS-Only/*.ps1`. No re-implementing `--agents-discover` in PowerShell. The PowerShell shell is **routing only**.

The shell shrinks to ~50 LoC. The previous version was ~155 LoC because it had the engine detection + install + dispatch; most of that stays, but no PS-Only code is added.

### 5.2 Tier 1 — the engine (today's v0.1.9, unchanged)

The C++/CLI engine stays exactly as it is. **No engine changes for PRD-08.**

The engine continues to handle **every command**:
- 4 engine-only commands (`--dispatch-master/template/v4`, `--inspector-check`)
- 14 file-I/O commands (audit trail, HITL, decisions, package, agent discovery, etc.)
- The Continuity Engine rule evaluation
- The SHA-1 checksum

### 5.3 Tier 2 — LLM-as-engine fallback

When Tier 1 is unavailable AND the dispatcher is an LLM-coding-agent, the LLM becomes the engine. This is documented in `<skill>/references/LLM-FALLBACK.md` (a new file). The recipe:

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
- Do NOT try to re-implement engine commands in PowerShell. The user explicitly rejected that approach. You are the fallback engine for this ONE dispatch, not a permanent parallel implementation.

## When to give up

- If the LLM doesn't have enough context (e.g. the manifest schema is unclear), tell the user "engine unavailable, here's a manual recipe: <link to SKILL.md>".
- If the deliverable requires a tool the LLM doesn't have (e.g. ffmpeg for audio chopping), tell the user "this deliverable needs ffmpeg; install it via `winget install Gyan.FFmpeg` and re-run".
```

The recipe is ~100 lines of Markdown. The LLM reads it, follows the steps, produces the deliverables. No code changes to the skill.

**Effort: ~100 LoC of Markdown documentation. Zero code.**

### 5.4 Detection in `skill.ps1`

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
    Write-Host "  | Tier 1 (C++/CLI engine): 18 commands unavailable." -ForegroundColor Yellow
    Write-Host "  | Tier 2 (LLM fallback):   if you're an LLM coding agent, see" -ForegroundColor Yellow
    Write-Host "  |   <skill>/references/LLM-FALLBACK.md" -ForegroundColor Yellow
    Write-Host "  | Run:  pwsh -NoProfile -File .\skill.ps1 --recover-engine" -ForegroundColor Yellow
    Write-Host "  +-----------------------------------------+" -ForegroundColor Yellow
    # Per-command error handling below; the engine is the dispatcher.
}
```

### 5.5 New commands (PowerShell shell only, no parallel engine implementation)

```powershell
# Print which tier is active + recovery hints
pwsh -NoProfile -File .\skill.ps1 --health

# Retry engine install
pwsh -NoProfile -File .\skill.ps1 --recover-engine

# Force a re-check of the engine (skip 6h cache)
pwsh -NoProfile -File .\skill.ps1 --recover-engine -Force
```

### 5.6 New env var

```powershell
$env:VORTEX_NO_ENGINE = '1'   # simulate missing engine (for testing the Tier 2 path)
$env:VORTEX_NO_ENGINE = '0'   # require engine (throw if missing)
# unset: best-effort (use Tier 1 if available, show Tier 2 banner if not)
```

## 6. API surface

### New files (skill-side)

```
<skill>/
  references/
    LLM-FALLBACK.md        # the Tier 2 recipe (~100 LoC of Markdown)
```

### Updated files

```
<skill>/
  skill.ps1                # ~50 LoC, thin routing
                           # adds: --health, --recover-engine
                           # adds: tier banner when engine is missing
                           # removes: any parallel PS-Only implementations
  verify.ps1               # adds a check that the engine is loadable
                           # adds a check that LLM-FALLBACK.md exists
```

### Behavior changes

| Command | Engine present | Engine absent |
|---|---|---|
| `--version`, `--help` | engine | **Tier 2 banner + error** |
| `--agents-*` | engine | **Tier 2 banner + error** |
| `--audit-trail` | engine | **Tier 2 banner + error** |
| `--hitl-*` | engine | **Tier 2 banner + error** |
| `--decision-*` | engine | **Tier 2 banner + error** |
| `--package` | engine | **Tier 2 banner + error** |
| `--dispatch-master/template/v4` | engine | **Tier 2 banner + error** |
| `--inspector-check` | engine | **Tier 2 banner + error** |
| `--health` | PS (always) | **PS** (always works, shows tier) |
| `--recover-engine` | PS (always) | **PS** (always works, retries install) |

**Every command except `--health` and `--recover-engine` requires the engine.** This is intentional: the user explicitly rejected a parallel PowerShell implementation.

## 7. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| The user has no LLM-coding-agent and the engine is missing — they're stuck | Medium | High | The `--health` and `--recover-engine` commands give clear next steps. The install script retries on transient network errors. The error message includes a link to the manual install recipe in SKILL.md. |
| The LLM-as-engine fallback misinterprets the Tier 2 recipe and does the wrong thing | Medium | Medium | The recipe is explicit about what to do AND what not to do. Tests in `verify.ps1` assert the recipe file exists and contains the key steps. |
| The LLM regenerates the engine from scratch (against directive) | Low | High | The recipe explicitly says "Do NOT try to compile a new C++ engine." Plus: on Windows, the engine either works or it doesn't. There's no in-session way to compile. |
| The C++ engine binary is corrupted on disk | Low | High | Reinstall via `--recover-engine` (re-downloads from GitHub). The auto-update check on every `skill.ps1` invocation catches most corruption cases. |

## 8. Acceptance criteria

1. `pwsh -NoProfile -File .\skill.ps1 --health` works without any engine installed and shows the tier + recovery hints.
2. `pwsh -NoProfile -File .\skill.ps1 --recover-engine` either succeeds (engine installed) or prints a clear network/GitHub error.
3. With the engine missing, every other command prints the Tier 2 banner and exits non-zero.
4. `references/LLM-FALLBACK.md` exists, is ~100 LoC, and contains the recipe (verified by a test in `verify.ps1`).
5. With the engine installed, every command behaves exactly as it does today (no behavior change for the happy path).
6. `verify.ps1` adds a check that the engine is loadable (current behavior).
7. `verify.ps1` adds a check that `references/LLM-FALLBACK.md` exists.
8. The PowerShell shell (`skill.ps1`) has shrunk from ~155 LoC to ~50 LoC of routing. No `lib/PS-Only/*.ps1` files exist.
9. The CHANGELOG documents the 2-tier model + the explicit rejection of the parallel PowerShell implementation.

## 9. Effort

- `references/LLM-FALLBACK.md`: ~100 LoC of Markdown
- `skill.ps1` refactor: ~150 LoC removed (the install + auto-update + dispatch logic stays, but the PS-Only implementations are removed) + ~30 LoC added (`--health`, `--recover-engine`, tier banner)
- `verify.ps1` integration: ~50 LoC
- Engine changes: **0 LoC**

**Net change: skill.ps1 shrinks by ~120 LoC. Total added: ~180 LoC. 1 PR. ~3 days for a single engineer.**

## 10. Open questions

- **Q1.** Should Tier 2 (LLM fallback) be auto-detected (via env vars like `MAVIS_SESSION_ID` or `CODEX_HOME`) or always advertised? — *Recommend: always advertised. The Tier 2 banner always shows the recipe pointer; the LLM decides whether to follow it.*
- **Q2.** Should `--health` be JSON-able for CI consumption? — *Recommend: yes, add `--health --json`.*
- **Q3.** When the engine recovers, should the next dispatch auto-use Tier 1? — *Recommend: yes, no special action needed. The detection is per-invocation.*
- **Q4.** Should the LLM-fallback write a special `state/last_tier2_dispatch.json` so a human operator can see when the LLM took over? — *Recommend: yes, useful for audit. The file lists the task_id, the start/end timestamps, the deliverables produced, and the agent(s) used.*

## 11. What was rejected (and why)

The earlier 3-tier design (PowerShell shell + C++ engine + LLM fallback) had a "Tier 1 PowerShell-only" idea where 14 of 18 commands were re-implemented in PowerShell so they'd work even if the engine was missing. **The user rejected this on 2026-08-27** because:

1. A parallel PowerShell implementation of the same commands would be a second engine to maintain.
2. No shared code with the C++ engine → long-term divergence risk.
3. The C++ engine is the only canonical implementation. The PowerShell shell is routing only.
4. For the rare case of engine-unavailable, the LLM fallback is sufficient.

**This is a 2-tier design going forward.** The PowerShell shell is minimal. The C++ engine is the source of truth. The LLM is the resilience layer.

## 12. Future work (deferred to v2.x)

- **Linux/macOS support** — option A (self-contained .NET host), B (Mono), or C (two engines). The user has explicitly deferred this.
- **Native CLI for Mac/Linux** — `vortex` binary (not `skill.ps1`) for users who don't have PowerShell. Deferred.
- **Tier 2 verification** — a test that runs `pwsh -NoProfile -File .\skill.ps1 --dispatch-master ...` with the engine absent and the dispatcher set to a mock LLM, then asserts the deliverables are correct. Hard to do in CI; maybe a manual smoke test.
