# VORTEX-OS — Future Recommendations

> **Status:** Living document. Reviewed on every minor release.
> **Audience:** Project maintainers, contributors, and anyone evaluating VORTEX-OS.
> **Scope:** Both [`vortex-os-dotnet`](https://github.com/Cloudmeru/vortex-os-dotnet) (the .NET 10 C++/CLI engine) and [`vortex-os-skill`](https://github.com/Cloudmeru/vortex-os-skill) (the PowerShell skill package).

This document captures ideas, gaps, and improvements that emerged from building VORTEX-OS through v0.1.x. It's organized by horizon (near / mid / long term) and tagged with **impact** and **effort** so we can prioritize.

**Status legend:** 🟢 shipped (already done) · 🟡 in progress (partial) · ⚪ future (not started) · 🔴 known gap (not yet prioritized)

---

## TL;DR — top 5 things to do next

1. **🔴 Implement the actual packager / Golden Path replay** — the engine's audit log and the sample prompts reference `worker.packager` and `--dispatch-template`, but the C++ code doesn't implement either. The dispatcher is a stub. This is the single biggest "demo vs production" gap.
2. **🔴 Web UI for HITL gates** — currently gates are surfaced as text in the host terminal. For non-trivial dispatches, an operator needs a structured form (with the script preview, the choices, the moral-hinge explanation) that doesn't get lost in scrollback.
3. **⚪ Cross-platform engine** — engine is Windows-only because of the .NET 10 + C++/CLI + `ijwhost.dll` IJW host stack. Linux + macOS support would require a different hosting model (likely a self-contained .NET host with the engine as a regular managed assembly, not C++/CLI).
4. **⚪ Operator-driven branching** — the Episode 3 sample prompt asks the engine to pick an ending based on prior approvals (`state\decision_history.json`). This is a real capability gap, not just a sample-prompt aspiration.
5. **🟡 Test coverage** — the engine has zero unit tests. The CI smoke test (`Get-VortexAgent` ≥ 3 rows) catches gross regressions but not edge cases. The skill has no tests at all.

---

## What's working well (don't break these)

Before listing what to add, let me note what's already solid in the v0.1.x line — these are the things a v1.0 should preserve:

- **Self-bootstrapping install.** A code agent (or human) runs `pwsh -File skill.ps1 --agents-discover` and the engine just shows up. No admin, no apt, no pre-installed PowerShell modules. The auto-update on first run is invisible.
- **The 3-level loading convention** in `SKILL.md` / `references/INSTRUCTIONS.md` / agents. SKILL.md stays under 10 KB, so it loads fast on every trigger.
- **Two-root data split** (skill folder vs. `VORTEX_HOME`). User deliverables survive skill updates, and the skill folder is safe to `git pull`. This was the right architectural call.
- **Per-project deliverables subfolder** + auto-derivation from the objective file path. Multi-episode series work in a single `deliverables/cartographer_daughter/` folder.
- **Capability-driven SKILL.md description** (v0.1.6). The frontmatter trigger description fires on observable prompt characteristics, not product names, so the skill matches prompts across domains.
- **winget-only deps + `install-deps.ps1`**. The agent that reads SKILL.md knows to use `winget install SQLite.SQLite`, not `pip install python3`.
- **`auto-update.ps1` rate-limited to 6 h.** Quiet, predictable, opt-out. Exactly the right behavior for "always up to date, never surprising."

---

## Near-term (next 1–2 releases, the polish phase)

These are the things that should land before v1.0. They close demo-vs-production gaps, add quality, and make the project credible for a wider audience.

### 1. Implement the actual packager worker (engine) 🟢 ↗ 🔴

**Status:** The engine's audit log records a `worker.packager promote_to_deliverables` step, but the C++ code in `lib/Swarm.cpp` and `lib/DispatchV4.cpp` doesn't have the promotion logic. The skill's `install.ps1` and `verify.ps1` don't do it either.

**What to build:** a T3 worker in the C++ engine that, after HITL approval, copies intermediate deliverables from `swarms/active_<id>/deliverables/` to the durable `$VORTEX_HOME/deliverables/<project>/` location, then writes the `.manifest.json`.

**Impact:** High. Without this, the user has to do the promotion manually after every dispatch.

**Effort:** ~1 day. Pure file-copy + manifest-write. The PathResolver fields (`ProjectName`, `ProjectDeliverablesDir`) are already there from v0.1.8.

---

### 2. Implement Golden Path template replay (engine) 🟢 ↗ 🔴

**Status:** `--dispatch-template` is a recognized CLI flag in `skill.cpp`, but the engine doesn't actually load or replay a template. The Episode 3 sample prompt references the template being "locked" — currently the file is never even created.

**What to build:** a `lib/GoldenPath.cpp` that:
1. Reads `templates/episode_pattern_vN.json` from `$VORTEX_HOME/`
2. Substitutes episode-specific fields (episode number, deliverable roles, audio signatures)
3. Reconstructs a synthetic objective file from the template
4. Calls the same `Dispatch` pipeline as `--dispatch-master`

**Impact:** High. Multi-episode series (the Episode 1-2-3 arc) become a one-liner: `skill.ps1 -Project foo --dispatch-template templates/episode_pattern_v3.json`.

**Effort:** ~2 days. JSON parsing (the engine already has `JsonX::ReadFile`).

---

### 3. Web UI for HITL gates (engine + skill) 🔴

**Status:** Gates are surfaced as text in the host terminal. For long-running dispatches with script previews, image previews, and "choose an ending" decisions, the terminal scrollback is the wrong place.

**What to build:** a small local web server (could be Kestrel-hosted from the .NET engine) that:
1. Listens on `http://localhost:<random-port>` during a gate
2. Renders the gate payload as HTML (with markdown rendering for the script, image previews for the map, radio buttons for the choice gates)
3. Blocks the engine until the operator clicks Approve / Deny / pick-a-choice
4. Falls back to text-only if no browser is available (e.g. CI runners)

**Impact:** High. This is the single biggest UX upgrade for human operators.

**Effort:** ~1 week. A small ASP.NET Core Razor Pages app embedded in the engine. The agent would just open the URL printed by the gate (no port-forwarding needed because it's localhost).

**Alternative if v1.0 is too soon:** a terminal UI using `Spectre.Console` or a simple text menu. Cheaper, but worse UX.

---

### 4. Unit + integration test coverage (engine) 🟡 ↗ 🔴

**Status:** Zero unit tests. CI smoke test is one shell command that asserts `Get-VortexAgent` returns ≥ 3 rows. Catches gross regressions only.

**What to build:** a `tests/` directory with:
- `tests/PathResolver_Tests.cpp` — slugify, two-vs-three-arg resolve, project-name derivation from objective path
- `tests/JsonX_Tests.cpp` — round-trip, edge cases (empty, malformed, UTF-8 BOM)
- `tests/Slugify_Tests.cpp` — property-based: any input produces a string that matches `[a-z0-9._-]+` and is idempotent
- `tests/Commands_Agents_Tests.cpp` — discover, lint with the 3 fixture agents
- An `Invoke-EngineTests.ps1` that builds the engine, runs the tests, asserts `ALL PASSED`

**Impact:** Medium-high. The engine is currently a "hope it compiles + hope the smoke test passes" project. Tests let us refactor with confidence.

**Effort:** ~3 days. Most test cases are straightforward.

---

### 5. Operator-driven branching (engine) 🔴

**Status:** The Episode 3 sample prompt asks the engine to pick an ending based on prior HITL approvals. The `state/decision_history.json` file doesn't exist yet, and the engine has no logic to read it.

**What to build:** 
- `state/decision_history.json` written at every gate (task_id, severity, decision, timestamp, prior_decision_count)
- A `lib/Branching.cpp` that reads this file at the start of a dispatch and computes a "decision score"
- The dispatch then selects deliverable variants based on the score (e.g. score < 0 → ending A, score > 0 → ending C, score = 0 → ending B)

**Impact:** High. This is what makes the operator's earlier choices matter. Without it, the sample prompts that promise "operator-driven branching" are aspirational only.

**Effort:** ~2 days.

---

### 6. Documentation: architecture diagram + video walkthrough (skill) ⚪

**Status:** `SKILL.md` and `references/INSTRUCTIONS.md` are text-only. New users (or new LLM-driven code agents) would benefit from a visual.

**What to build:** 
- A single ASCII / Mermaid architecture diagram in `references/architecture.md` showing the 4-tier chain + the data flow
- A 5-minute screen-capture video walkthrough: install the skill, run `verify.ps1`, dispatch a sample objective, observe the audit log. Hosted on the README or as a `docs/walkthrough.mp4` in the repo

**Impact:** Medium. Helps adoption. Not a v1.0 blocker.

**Effort:** ~1 day for the diagram, ~1 day for the video.

---

### 7. Documented install + uninstall (skill) 🟡 ↗

**Status:** Install is well documented (`install.ps1`, `install-deps.ps1`, `auto-update.ps1`). **Uninstall is not** — the user has to manually delete `%APPDATA%\Vortex-OS\Vortex\0.1.8\` AND `%APPDATA%\Vortex-OS\` AND reset their `winget` deps if they want a full clean.

**What to build:** a `uninstall.ps1` with flags:
- `-EngineOnly` — delete `Vortex\<version>\` (keeps state, audit log, deliverables)
- `-All` — also delete `$VORTEX_HOME\` (destroys user data, requires confirmation)
- A `--dry-run` flag for safety

**Impact:** Medium. Makes the skill feel more polished.

**Effort:** ~half a day.

---

## Mid-term (next 3–6 months, the capability phase)

These add real capability beyond "this works on my machine." They're not v1.0-blockers, but they unlock the project's potential.

### 8. Cross-platform engine (engine) ⚪

**Status:** Windows-only because of the .NET 10 + C++/CLI + `ijwhost.dll` IJW host stack. PowerShell 7+ runs on Linux and macOS, but `ijwhost.dll` doesn't.

**Options:**
- **A. Self-contained .NET host:** rewrite the engine in C# (or compile the C++/CLI to plain C++ with a C ABI, then P/Invoke). Drops IJW. Larger rewrite.
- **B. Mono runtime on Linux/macOS:** continues to use C++/CLI via the Mono C++ compiler. Less tested; uncertain future.
- **C. Two engines:** keep the Windows C++/CLI for performance, ship a Linux/macOS equivalent in pure C# (slower but correct).

**Recommendation:** C. Ship a pure-C# rewrite of the engine for Linux/macOS, keep the C++/CLI engine on Windows. They share the same `Vortex.psm1` PowerShell wrapper so the skill is portable.

**Impact:** Massive. Unlocks the entire non-Windows world.

**Effort:** ~2 months for a focused engineer.

---

### 9. PSGallery publish (skill) ⚪

**Status:** The release workflow (`.github/workflows/release.yml`) has a `Publish to PowerShell Gallery` step that runs on tag. But the actual publish hasn't been verified end-to-end (no `PSGALLERY_API_KEY` has been set, the package metadata might not be perfect).

**What to do:**
- Verify the package manifest is PSGallery-compatible (already is, but worth double-checking)
- Set `PSGALLERY_API_KEY` in the repo secrets
- Verify the publish step actually runs and the package appears at https://www.powershellgallery.com/packages/Vortex
- Update `install-deps.ps1` / `install.ps1` to prefer PSGallery over GitHub release when available

**Impact:** Medium. Makes install even simpler (`Install-Module Vortex` is shorter than the GitHub-release dance).

**Effort:** ~half a day.

---

### 10. Multi-user / shared VORTEX_HOME (skill + engine) ⚪

**Status:** Single-user per machine (uses `%APPDATA%`). For team use, this is a limitation.

**What to build:** 
- Document the "team use" pattern: set `VORTEX_HOME` to a network drive or a shared server
- Add file-locking around `memory/audit.jsonl` writes (currently a race condition if two agents run simultaneously on a shared VORTEX_HOME)
- Add a "team" config layer: per-user audit log + shared deliverables pool

**Impact:** Medium. Unlocks team / studio use cases.

**Effort:** ~1 week. The file-locking alone is a day; the rest is config + docs.

---

### 11. Engine plugins / extension API (engine) ⚪

**Status:** The engine's "worker" types are hard-coded (writer, audio, image, code, packager). To add a new worker type, you have to modify the C++ source and rebuild.

**What to build:** a plugin contract:
- Workers are PowerShell scripts in `<Vortex>\<version>\Workers\<name>.ps1`
- The engine dispatches to them via `& pwsh -File <worker>.ps1 <args>`
- Each worker outputs a JSON result the engine parses

**Impact:** High. Opens the engine to third-party workers without a rebuild.

**Effort:** ~2 weeks. PowerShell-as-worker-language is much more accessible than C++.

---

### 12. Cost / token budgeting (engine) ⚪

**Status:** The audit log records `duration_ms` but not token spend. There's no per-project budget. The inspector.governance agent is meant to do "token velocity" but the implementation is a stub.

**What to build:** 
- `lib/CostTracker.cpp` that records token counts per dispatch
- Per-project budget in `_meta.json` (e.g. `"budgets": {"max_tokens_per_dispatch": 50000}`)
- Alert (PENDING_HUMAN) when a dispatch exceeds 80% of budget

**Impact:** Medium. Important for production use where cost matters.

**Effort:** ~1 week.

---

### 13. Audit log viewer (skill) ⚪

**Status:** `memory/audit.jsonl` is a JSONL file. Reading it directly is fine for a single dispatch, but multi-dispatch analysis is painful.

**What to build:** a PowerShell cmdlet (e.g. `Get-VortexAuditTrail -Project cartographer_daughter -Last 24h -AsTree`) that:
- Filters by project, time, agent, severity
- Renders the T0→T1→T2→T3 chain as a tree
- Highlights self-heal cycles (rules violated → rules fixed) and HITL gates

**Impact:** Medium. Quality-of-life upgrade.

**Effort:** ~1 day.

---

### 14. Streaming / partial results (engine) ⚪

**Status:** The engine buffers all deliverables until the end, then surfaces them. For long-running dispatches (e.g. a 6-episode series), the operator has no visibility until everything is done.

**What to build:** 
- `--stream` flag on `skill.ps1` that subscribes to a named pipe or HTTP endpoint
- The engine writes partial deliverables as they're generated (with `state\in_progress\` flag)
- The operator can preview the in-progress deliverable, give early feedback, or let it run

**Impact:** Medium. Better UX for long dispatches.

**Effort:** ~2 weeks.

---

## Long-term (1+ years, the ecosystem phase)

Strategic bets. These define the project's long-term direction.

### 15. VS Code / Copilot extension ⚪

A thin VS Code extension that:
- Surfaces the SKILL.md in the agent's context when triggered
- Shows HITL gates as native VS Code notifications (with the script preview in a webview)
- Lets the operator approve / deny from the editor
- Bundles the VORTEX-OS install into the extension (so a single `Extensions: Install VORTEX-OS` works)

**Impact:** Massive. Becomes the IDE-native experience.

**Effort:** ~1 month.

---

### 16. Standalone `vortex` CLI ⚪

A single executable that bundles install + verify + skill.ps1 + auto-update into one tool. `vortex run --dispatch-master obj.md` instead of `pwsh -File skill.ps1 --dispatch-master obj.md`.

**Impact:** Medium. Makes the skill feel more like a first-class tool.

**Effort:** ~1 week. Mostly a wrapper script.

---

### 17. Cross-project "memory" / "lore" (engine + skill) ⚪

Currently, each project lives in its own `deliverables/<project>/` subfolder and has no awareness of other projects. A cross-project memory would let the engine:
- "I worked on `<previous_project>` last week, here's what I learned about this character archetype"
- "Across all your projects, you tend to write 18% over the requested word count; here's a calibration"
- "Across the 3-episode Cartographer arc, the water-damage clock advanced 10% / 20% / 30% — here's a similar diegetic-clock template for your new project"

**Impact:** High for power users. The "I learn from my work" angle is the killer feature for a creative-production tool.

**Effort:** ~1 quarter. Genuinely hard problem.

---

### 18. Web-based audit-trail browser ⚪

A small static site (hosted on GitHub Pages from the audit.jsonl) that visualizes a dispatch as an interactive graph. Click on a T2 supervisor → see which T3 workers it dispatched → click on a T3 → see the audit trail.

**Impact:** Medium. Helps with debugging, demos, and trust.

**Effort:** ~1 week.

---

## Specific gaps I noticed during v0.1.x (not yet prioritized)

These are smaller things that came up in this session. Worth a backlog entry.

| # | Gap | Where | Effort |
|---|---|---|---|
| G1 | `worker.packager` doesn't actually exist in the C++ code, but the audit log shows it as a worker | engine | small (in scope of #1) |
| G2 | `state\active_budgets.json` is referenced but never written | engine | small (in scope of #12) |
| G3 | `lib/vector_schema.sql` is referenced but never shipped in the skill | engine + skill | small |
| G4 | `lib/Commands.cpp` VectorHydrate falls back to a stub DB when sqlite3 is missing — this is fine, but the fallback should be documented in `_meta.json` | engine + docs | tiny |
| G5 | No `Get-VortexVersion` cmdlet — the user has to know to run `skill.ps1 --version` | engine psm1 | small |
| G6 | `state\tmp\` is in `VORTEX_HOME` but `obj/`, `bin/` from the source build are also gitignored — if a user accidentally builds in the skill folder, the build artifacts are mixed with runtime state | skill .gitignore | tiny |
| G7 | The engine's `RunChecks` function in `verify.cpp` is 130+ lines and does file-presence + tool-check + JSON-validation + branding-check + lint + dispatch in one giant function. Refactor into smaller pieces for readability. | engine | medium |
| G8 | `auto-update.ps1` cache file `state/auto-update-check.json` is written but never read at the start of the install flow — a fresh install + run + wait 1 hour + run would re-hit GitHub on the second run. Cache should be read first. | skill | tiny |
| G9 | The `Vortex.psd1` `CompatiblePSEditions = @('Core')` means it won't load in Windows PowerShell 5.1. That's correct (the engine is .NET 10), but the error message when someone tries to load it in PS5 is "could not load type" rather than "this needs PowerShell 7+". | engine psm1 | tiny |
| G10 | The `winget install_ids` field in `_meta.json` doesn't include a `winget` install fallback. If a user doesn't have `winget` (older Windows), the installer just prints "install with: winget install X" without a fallback path (choco, scoop, direct download). | skill | small |
| G11 | `--agents-discover`, `--agents-lint`, `--audit-trail`, etc. all have a "skill.ps1" wrapper. They're not exposed as standalone cmdlets in the user's PSModulePath. | engine psm1 | small |
| G12 | The skill's `migrate-state.ps1 -AdoptFlat` moves legacy flat deliverables into `deliverables/_unfiled/`. There's no "review and file each into a project" UX — the user has to do it by hand. | skill | medium |

---

## Open questions / decisions needed

These are choices the maintainers should make explicitly, not just by default. Worth a design discussion in an issue.

### Q1. Single engine, multiple engines, or no engine?

Should the engine be:
- **A single binary** that the skill downloads once (current model)
- **Multiple versions side-by-side** so an old project keeps using v0.1.8 while a new project uses v0.2.0
- **No engine at all** — pure PowerShell (the engine code in C++/CLI is a perf choice; for a power user, pure PowerShell is fine)

The current model is "single engine, the latest." This is simple but inflexible. The "multiple engines" model is more correct but requires the skill to track which project uses which engine version.

### Q2. What's the v1.0 success criterion?

Is v1.0 "the engine has all the sample-prompt features implemented"? Or "one team has used it in production for 6 months"? Or "all the test coverage targets are met"?

I'd argue for the first: a v1.0 should implement the features the sample prompts already promise (packager, Golden Path replay, operator-driven branching). Without those, the sample prompts are aspirational.

### Q3. PSGallery first, GitHub first, or both?

The skill's install flow uses the GitHub release. If we publish to PSGallery, which becomes the canonical install path?

Recommendation: keep GitHub as the canonical (faster releases, no review), but also publish to PSGallery for discoverability.

### Q4. How prescriptive is the engine about LLM providers?

Currently, the engine is LLM-agnostic — it just calls PowerShell scripts. The skill (in the sample prompts) assumes specific LLM APIs. If we want to support multiple LLM providers (Anthropic, OpenAI, local Ollama), we need a provider abstraction.

Recommendation: defer this. The current "bring your own LLM" model is fine for v1.0.

### Q5. Single-tenant or multi-tenant `VORTEX_HOME`?

Currently `VORTEX_HOME` is per-user (under `%APPDATA%`). For team / studio use, should it be per-user-per-machine, per-team-shared, or both?

Recommendation: keep per-user for v1.0. Multi-team is a v2+ problem.

---

## How to use this document

1. **When planning the next release:** scan the "Near-term" section. Pick the items that are now-blockers, ship them.
2. **When triaging issues:** the "Specific gaps" table is a starter backlog. Add to it as you find more.
3. **When reviewing architectural choices:** the "Open questions" section is the design-decision queue. Resolve one before you start a major feature.
4. **When looking for a contributor project:** the "Mid-term" and "Long-term" sections are project-sized, well-scoped ideas. A new contributor can pick one up.

This document should be reviewed and updated on every minor release (v0.x.0). The TL;DR section is the priority list; everything else is context.

---

*Last updated: 2026-08-27. Current versions: `vortex-os-skill` v0.1.6, `vortex-os-dotnet` v0.1.8.*
