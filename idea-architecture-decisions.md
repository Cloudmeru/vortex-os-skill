# VORTEX-OS — Architecture Decision Records (ADRs)

> **Status:** Living document. Append a new ADR for every meaningful decision. Do not rewrite old ADRs — supersede them.
> **Audience:** Future maintainers asking "why did they do it this way?"
> **Scope:** Both [`vortex-os-dotnet`](https://github.com/Cloudmeru/vortex-os-dotnet) and [`vortex-os-skill`](https://github.com/Cloudmeru/vortex-os-skill).

This document captures the **why** behind the major design choices in VORTEX-OS. Each ADR is a short, focused record of one decision. They're written in the past tense as if the decision has already been made, because the goal is to document choices that were *already* taken — not to propose new ones (those go in `idea-future-recommendations.md`).

If you're about to make a change that contradicts an ADR, **either**:
1. Update the ADR to "superseded by ADR-NNN" and add a new ADR explaining the new decision
2. Or open a discussion first — the original reasoning might still apply

---

## ADR format

Each ADR has:

- **Number** — sequential, never reused
- **Title** — one-line summary
- **Status** — `Accepted` / `Superseded by ADR-NNN` / `Deprecated`
- **Date** — when the decision was made (release version)
- **Context** — the problem that was being solved
- **Decision** — what we chose
- **Consequences** — what became easier, what became harder
- **Alternatives considered** — what we rejected, and why

---

## ADR-001 — Engine is .NET 10 C++/CLI, not pure C# or pure PowerShell

**Status:** Accepted
**Date:** v0.1.0

**Context:** We needed a runtime for the orchestration engine. The options were:
- Pure C# (managed .NET 10) — easy, modern, cross-platform
- Pure PowerShell scripts — no compile step, but PS5 / PS7 string interop is awkward
- C++/CLI (mixed managed + native) — fastest path to "talk to PowerShell, talk to native APIs, talk to SQLite, talk to LLM providers" without choosing one paradigm

**Decision:** C++/CLI, compiled to a class library DLL (`Vortex.dll`).

**Consequences:**
- (+) One assembly, multiple languages: native Win32 for SQLite, .NET 10 for `System.Text.Json`, and PowerShell for the LLM provider interface
- (+) PowerShell 7+ `Add-Type`s the DLL into its existing CLR — no separate apphost.exe or `runtimeconfig.json` to ship
- (+) The `Vortex.dll` is loaded into the PS7+ process, so cmdlet calls are in-process (no `Process.Start` round-trip)
- (−) Requires .NET 10 ref + host packs on the build machine
- (−) C++/CLI is Windows-only (the `ijwhost.dll` IJW host doesn't exist on Linux)
- (−) Compiles slowly; a full rebuild takes ~30 seconds

**Alternatives considered:**
- **Pure C#:** rejected because we'd lose the "drop into native code for the perf-critical bits" option, and we'd be locked into one ecosystem.
- **Pure PowerShell:** rejected because PS5 / PS7 isn't a great host for a long-running service (startup time, no real threads, no easy way to share state with native libraries).
- **C# with P/Invoke to a native helper:** rejected because the IJW model is simpler than marshaling strings back and forth across the managed/native boundary.

---

## ADR-002 — Two-root storage: skill folder (mutable) + VORTEX_HOME (durable)

**Status:** Accepted
**Date:** v0.1.7

**Context:** Originally, all runtime state (audit logs, deliverables, swarms, HITL state) lived in the skill folder itself. This meant:
- Updating the skill (`git pull`, fresh deploy) wiped the user's work
- Multiple code agents on the same machine couldn't share state
- The skill folder became a weird mix of "scripts you can replace" and "data you can't"

**Decision:** Split the storage into two roots:
- `SkillDir` (mutable) — the skill folder; holds `agents/`, `templates/`, scripts, docs
- `HomeDir` (durable) — `$VORTEX_HOME` (default `%APPDATA%\Vortex-OS`); holds `state/`, `memory/`, `swarms/`, `deliverables/`, `tasks/`

The PowerShell wrapper passes `SkillDir` as the first arg to `Vortex.Skill::Run()`. The engine reads `HomeDir` from `$env:VORTEX_HOME` (with the default above).

**Consequences:**
- (+) Updating the skill never wipes user work — the user's deliverables, audit log, swarms, HITL state all live outside the skill folder
- (+) Multiple code agents on the same machine share data via the default `VORTEX_HOME` path
- (+) `migrate-state.ps1` provides a clean one-time migration story
- (−) The user has to know about `VORTEX_HOME` to find their data
- (−) OneDrive Files-On-Demand can make the default path broken (worked around with a sentinel-subdir probe in `install.ps1`)

**Alternatives considered:**
- **All in skill folder:** rejected because the "update wipes your work" problem is unacceptable for a tool meant for long-running projects.
- **All in VORTEX_HOME (no skill folder in path resolution):** rejected because the skill folder is the natural place to look for `agents/` and `templates/`. The split mirrors how most tools work (e.g. git keeps `.git/` separate from the working tree).
- **Per-engine-version state (e.g. `Vortex\0.1.7\` for state):** rejected because the engine changes too often for that to be useful, and users want their data to survive engine upgrades.

---

## ADR-003 — User-scope install, not system-wide

**Status:** Accepted
**Date:** v0.1.0

**Context:** The engine installs to `$HOME\Documents\PowerShell\Modules\Vortex\<version>\` (or the first writable per-user `PSModulePath` entry). The alternative was to install to `$env:ProgramFiles\PowerShell\Modules\` (system-wide).

**Decision:** User-scope. The skill uses `winget` for system-level dependencies (sqlite3, ffmpeg) but installs the engine itself to user-scope.

**Consequences:**
- (+) No admin / elevation needed
- (+) Each user on a shared machine can have their own engine version
- (+) `Remove-Item -Recurse -Force $HOME\Documents\PowerShell\Modules\Vortex` is a clean uninstall
- (−) Multiple users on the same machine each download their own copy (waste of disk)
- (−) The user-scope `PSModulePath` can be broken by OneDrive-redirected `Documents` folders (worked around with the sentinel-subdir probe)

**Alternatives considered:**
- **System-wide install:** rejected because it requires admin and creates "I can't uninstall it" support tickets.
- **Portable install (single-folder, add to PATH):** rejected because PowerShell modules have a standard install layout; fighting the convention creates confusion.

---

## ADR-004 — Self-bootstrapping from GitHub releases, not bundled

**Status:** Accepted
**Date:** v0.1.1

**Context:** Originally, the skill bundled the engine binaries (`Vortex.dll`, `Vortex.psm1`, `Vortex.psd1`, `ijwhost.dll`) in the skill folder. This meant:
- The skill package was 200+ KB
- A bug in the engine required a new skill release to ship the fix
- The engine version was locked to the skill release

**Decision:** The skill downloads the engine from `Cloudmeru/vortex-os-dotnet/releases` on first run. The skill folder contains only the install scripts (`install.ps1`, `install-deps.ps1`, `auto-update.ps1`).

**Consequences:**
- (+) Skill package is ~50 KB instead of ~250 KB
- (+) Engine bugs ship as engine releases — independent of the skill
- (+) The engine can auto-update (`auto-update.ps1` polls GitHub every 6h)
- (+) Multiple skill instances on the same machine share the engine install
- (−) Requires network access on first run (one HTTP call to `api.github.com`)
- (−) GitHub API rate limit (60 req/hr unauthenticated) means a busy CI could hit it

**Alternatives considered:**
- **Bundled engine:** rejected because of the size + update coupling.
- **PSGallery publish for the engine:** considered for v0.1.x but deferred (it's in the roadmap as item #9).

---

## ADR-005 — Per-project deliverables subfolder, not flat

**Status:** Accepted
**Date:** v0.1.8

**Context:** Originally, all deliverables from all dispatches went to a flat `deliverables/` folder in `VORTEX_HOME`. With multiple sessions and multiple projects, this collided: Trial of Echoes' `scene1.md` clobbered Cartographer's `scene1.md`.

**Decision:** Deliverables are grouped by project: `$VORTEX_HOME/deliverables/<project>/<file>`. The project name is auto-derived (in priority order):
1. `$env:VORTEX_PROJECT`
2. The `-Project` flag on `skill.ps1`
3. The parent dir of the `--dispatch-master` arg
4. The filename of the objective without extension

The engine refuses to overwrite an existing project's deliverables; the user must pick a new project name (e.g. `-Project trial_of_echoes_v2`) or manually clear the folder first.

**Consequences:**
- (+) Multiple projects can coexist without collision
- (+) Self-healing prompts, diegetic clocks, character state are scoped per project
- (+) Each project folder is a self-describing unit (with `.manifest.json` written by the future packager worker)
- (−) Project name must be re-typed or auto-derived correctly (the slugify handles 95% of cases)
- (−) The "refuse to overwrite" behavior can be surprising for users who re-dispatch a project

**Alternatives considered:**
- **Flat with prefix in filename:** rejected because every consumer (the user, the agent, the file explorer) has to parse filenames to group by project.
- **Auto-versioning (v2, v3 subfolders):** rejected because it can mask "I just re-ran the wrong project" mistakes.

---

## ADR-006 — Per-version engine install (allows rollback)

**Status:** Accepted
**Date:** v0.1.1

**Context:** The engine installs to `$HOME\Documents\PowerShell\Modules\Vortex\<version>\` (e.g. `Vortex\0.1.7\`, `Vortex\0.1.8\`). The alternative was a single-folder install with a version-suffixed binary (e.g. `Vortex-0.1.7.dll`).

**Decision:** Per-version folder. PowerShell's module loader uses the highest version by default. Old versions are kept in place until manually removed.

**Consequences:**
- (+) Multiple engine versions can coexist; the newest one is loaded by default
- (+) Rollback is `Remove-Item $HOME\Documents\PowerShell\Modules\Vortex\0.1.8` + restart
- (+) `auto-update.ps1` installs the new version in a new folder, doesn't touch the old one
- (−) Disk usage grows over time (user must manually clean up old versions)
- (−) If the user has v0.1.7 and v0.1.8 installed, v0.1.7 still loads (because PowerShell's default module loader picks the highest version — but custom PSModulePath order could break this)

**Alternatives considered:**
- **Single-folder install with `Vortex-<version>.dll`:** rejected because PowerShell's module loader is folder-based; custom filename doesn't work.
- **Side-by-side with symlinks:** rejected because Windows symlinks require admin or developer mode.

---

## ADR-007 — Capability-driven SKILL.md description, not product-bound

**Status:** Accepted
**Date:** v0.1.6

**Context:** The original SKILL.md description mentioned specific products (VibeOS, WebSims, Hailuo, MiniMax, named universes like "When Ocean Meets Sky"). This meant the Mavis/Claude trigger detector only fired for prompts mentioning those products. A user asking for a "multi-agent pipeline with continuity + HITL" wouldn't trigger the skill.

**Decision:** The description now describes the skill's capabilities and the observable prompt characteristics that should trigger it. No product names.

**Consequences:**
- (+) The skill fires on any prompt that exhibits the right shape (multi-domain, continuity, HITL, audit, episodic, in-house)
- (+) The description is durable across product evolution
- (+) Triggers correctly for cross-domain work (research + analysis + viz + report) the original wording missed
- (−) Slightly more abstract — a brand-new agent might be unsure if the skill is "for me"

**Alternatives considered:**
- **Keep product names:** rejected because the goal is universal skill detection.
- **List trigger conditions in priority order:** rejected because the description is read by an LLM as prose; a bulleted list of capabilities is more parseable than a ranked list.

---

## ADR-008 — Manual migration via `migrate-state.ps1`, not auto

**Status:** Accepted
**Date:** v0.1.4

**Context:** The user reported that the engine's runtime data should live in `VORTEX_HOME` (so it survives skill updates). We had to choose:
- Auto-migrate on first run (engine reads from the old location, writes to the new)
- Manual migration via a separate `migrate-state.ps1` script

**Decision:** Manual. `migrate-state.ps1` copies old data from the skill folder to `$VORTEX_HOME`. Idempotent. Supports `-WhatIf` and `-DeleteSource`.

**Consequences:**
- (+) The engine doesn't have to know about the legacy file layout forever
- (+) The user has explicit control over when to migrate (e.g. after they've verified the new version)
- (+) `-WhatIf` lets the user preview the migration before committing
- (−) Manual step that the user has to remember
- (−) If the user doesn't run the script, old data is orphaned in the skill folder

**Alternatives considered:**
- **Auto on first run:** the user explicitly chose manual ("Add explicit migrate-state.ps1 (manual)") because auto-migration can be surprising and the user wants explicit control.

---

## ADR-009 — `Vortex.psd1` + `Vortex.psm1` module structure, not just a `.dll`

**Status:** Accepted
**Date:** v0.1.0

**Context:** The engine is a C++/CLI class library. PowerShell can load it two ways:
- `Add-Type -Path Vortex.dll` — adds the types to the session but doesn't create a module
- `Import-Module Vortex.psd1` — creates a proper module with cmdlets, functions, manifests, and metadata

**Decision:** Ship a full module: `Vortex.psd1` (manifest) + `Vortex.psm1` (module script that loads the DLL via `Add-Type` and exposes the cmdlets).

**Consequences:**
- (+) Standard PowerShell module: discoverable, versionable, installable
- (+) The `.psd1` declares `CompatiblePSEditions = @('Core')` so PS5 fails fast with a clear error
- (+) PSGallery publish is a one-liner (`Publish-Module`)
- (+) Users can `Import-Module Vortex` from any session after install
- (−) Two more files to ship and maintain (`Vortex.psd1`, `Vortex.psm1`)

**Alternatives considered:**
- **Just the .dll:** rejected because the user wouldn't get a proper module with metadata.
- **A single `.ps1` that loads the .dll:** rejected because the manifest (`psd1`) is needed for proper PowerShell module semantics.

---

## ADR-010 — Aggressive `Slugify` for any user-provided identifier

**Status:** Accepted
**Date:** v0.1.8

**Context:** The project name (auto-derived from the objective file path) is used to build the deliverables subfolder path. If the project name contains spaces, slashes, or non-ASCII characters, the path could fail on Windows (which has a restricted character set) or contain shell metacharacters.

**Decision:** Every user-provided identifier is passed through `PathResolver::Slugify`, which:
- Lowercases
- Keeps only `[a-z0-9._-]`
- Collapses runs of `-` to one
- Trims leading/trailing `-`

**Consequences:**
- (+) Project names like "Trial of Echoes" → `trial_of_echoes` automatically
- (+) The deliverables path is always safe (`$VORTEX_HOME/deliverables/trial_of_echoes/`)
- (+) No shell injection risk in the path
- (−) Two projects that slugify to the same name (e.g. "Foo!" and "Foo?") collide — but this is a feature, not a bug (they ARE the same project)

**Alternatives considered:**
- **Hash-based slugs (e.g. `project_<hash>`):** rejected because humans can't read or remember them.
- **Refuse non-ASCII characters:** rejected because some users want Chinese / Japanese / etc. project names.

---

## ADR-011 — `winget` for system deps, not `pip` / `brew` / `apt`

**Status:** Accepted
**Date:** v0.1.3

**Context:** The skill needs `sqlite3` (required, for the engine's memory persistence) and `ffmpeg` (optional, for generated audio deliverables). The original `_meta.json.system_tools` listed `python3`, `jq`, `sqlite3`, `ffmpeg` as generic tool names. A code agent reading that list tried to `pip install python3` — wrong on Windows, wrong for a .NET-only project.

**Decision:** System deps are installed via `winget` (Windows Package Manager) only. The skill exposes `_meta.json.winget_install_ids` with the exact package IDs:
- `SQLite.SQLite` (required, for VectorHydrate)
- `Gyan.FFmpeg` (optional, for audio deliverables)

`install-deps.ps1` is the canonical wrapper.

**Consequences:**
- (+) No `pip` / `brew` / `apt` confusion — the agent reads `_meta.json` and uses `winget install --id <winget_id>`
- (+) `_meta.json.winget_install_note` explicitly tells agents to use winget, not pip
- (+) `winget` is the Windows-native package manager (no admin, no PATH issues)
- (−) Older Windows (pre-1809) doesn't have `winget` — but Windows 10 1809+ and all Windows 11 do

**Alternatives considered:**
- **choco or scoop:** rejected because `winget` is the Windows-native option and ships with Windows itself.
- **Direct download of binaries:** rejected because `winget` handles uninstall + PATH + signature verification.

---

## ADR-012 — PowerShell 7+ Core only, not PS5

**Status:** Accepted
**Date:** v0.1.0

**Context:** The engine is .NET 10, which PowerShell 5.1 (Windows PowerShell) cannot load. PS7+ (PowerShell Core) ships with .NET 9+ and can load the engine.

**Decision:** PS7+ Core only. The skill's `Vortex.psd1` declares `CompatiblePSEditions = @('Core')` and the engine's `Run` throws a clear error if invoked under PS5.

**Consequences:**
- (+) Uses the modern .NET runtime
- (+) Cross-platform-ready (PS7 runs on Linux, macOS — though the engine itself is still Windows-only)
- (+) Standard `pwsh` is the canonical command; users don't have to remember `powershell` vs `pwsh`
- (−) Users with only PS5 installed (older Windows defaults) have to install PS7 first

**Alternatives considered:**
- **Build a .NET Framework 4.x version of the engine for PS5:** rejected because .NET Framework is end-of-life and .NET 10 features are too valuable.
- **Build a separate "legacy" entry point:** rejected because it doubles the maintenance burden for a tiny user base.

---

## ADR-013 — 3-level docs convention (SKILL.md / references/ / agents/)

**Status:** Accepted
**Date:** v0.1.2

**Context:** The skill needs a SKILL.md (loaded by agents on every trigger) plus deeper operator docs. The original INSTRUCTIONS.md was 16+ KB — too big to load every time.

**Decision:** 3-level loading:
1. `SKILL.md` — lean entry point (~10 KB), always loaded
2. `references/INSTRUCTIONS.md` — operator playbook (~20 KB), loaded on demand
3. `agents/`, `templates/`, scripts — the actual artifacts

**Consequences:**
- (+) Agents see only the lean SKILL.md on every trigger (~10 KB) — fast trigger detection
- (+) Operator gets the full playbook on demand (~20 KB)
- (+) Standard Mavis/Claude pattern — other skills in the ecosystem use the same shape
- (−) Operators have to know to look in `references/` for the deep dive
- (−) The convention requires discipline (don't put deep material in SKILL.md; don't put quick reference in `references/`)

**Alternatives considered:**
- **Single big SKILL.md:** rejected because the agent would load 16+ KB on every trigger, which is wasteful and slows detection.
- **Multiple small docs at the root:** rejected because the convention is less clear; the 3-level pattern signals "this is what to load first, this is what to load on demand."

---

## ADR-014 — Auto-update with 6h rate limit, not aggressive / not disabled

**Status:** Accepted
**Date:** v0.1.5

**Context:** The user asked the skill to "auto-update when triggered first time, by checking the latest dotnet module version." We had to choose:
- Check on every invocation (no caching) — hits GitHub API constantly
- Check on first invocation per machine, then never again (no updates after the first)
- Cache the last check time, re-check every 6h

**Decision:** Cache the last check time at `$VORTEX_HOME/state/auto-update-check.json`. Re-check every 6h. The check is silent unless an update is found.

**Consequences:**
- (+) The skill is always up-to-date (at most 6h behind the latest release)
- (+) GitHub API is hit at most ~4 times per day per VORTEX_HOME (60 req/hr limit = 1440/day, well under)
- (+) Opt-out with `$env:VORTEX_NO_AUTO_UPDATE=1` for CI runners
- (+) Bypass with `-Force` for "check right now"
- (−) The user might be surprised by a version bump mid-session (mitigated by the install going to a new folder, doesn't affect the current run)

**Alternatives considered:**
- **No auto-update:** rejected because the user explicitly asked for it.
- **Always check on every invocation:** rejected because it wastes the GitHub API budget.

---

## ADR-015 — Slugify, not block on collision (refuse to overwrite, force user to pick new name)

**Status:** Accepted (refines ADR-005)
**Date:** v0.1.8

**Context:** When a user re-dispatches a project, what should the engine do?
- Auto-version (v2, v3 subfolders)
- Overwrite (replace the previous deliverables)
- Refuse to overwrite (force the user to pick a new name)

**Decision:** Refuse to overwrite. The user must pick a new name (e.g. `-Project trial_of_echoes_v2`) or manually clear the project's deliverables folder first.

**Consequences:**
- (+) No accidental data loss from "I just re-ran the wrong project"
- (+) The previous deliverables stay accessible for review / reference
- (+) Clear semantics: re-dispatching requires an explicit decision
- (−) Slightly more friction for the common "I want to redo this project" case
- (−) The error message ("project already exists") needs to be clear about how to proceed

**Alternatives considered:**
- **Auto-versioning:** rejected because it can mask mistakes (the user might not realize they're working on v3 instead of v1).
- **Overwrite with a backup:** rejected because backups pile up and confuse the user.

---

## How to add a new ADR

When making a meaningful design decision, add an ADR. The format is:

1. Copy the "ADR-XXX" template at the bottom of this file
2. Increment the number
3. Fill in Context, Decision, Consequences, Alternatives
4. Date it with the release version
5. Status: `Accepted`

If the new decision supersedes an older one, update the old ADR's status to `Superseded by ADR-NNN` (don't rewrite it). Add a sentence to the Consequences of the new ADR pointing back.

---

*Last updated: 2026-08-27. Current versions: `vortex-os-skill` v0.1.6, `vortex-os-dotnet` v0.1.8.*
