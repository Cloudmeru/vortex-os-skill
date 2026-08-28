---
name: VORTEX-OS
display_name: VORTEX-OS - Multi-Agent Orchestration Engine
version: 0.3.4
description: |
  VORTEX-OS is a self-bootstrapping PowerShell skill that drives the
  [Cloudmeru/vortex-os-dotnet](https://github.com/Cloudmeru/vortex-os-dotnet)
  .NET 10 C++/CLI engine to orchestrate multi-agent work pipelines. The
  engine decomposes a master objective into a 4-tier chain of command
  (planner -> supervisor -> shift -> specialized workers), runs workers
  in parallel across distinct domains, enforces continuity + contract
  rules, gates high-stakes actions behind Human-in-the-Loop approval, and
  writes a per-agent audit log. Engine v0.3.0+ adds a cross-project
  memory layer so subsequent dispatches inherit context. Trigger
  conditions are in the "Trigger Conditions" section below.
author: MiniMax Agent
license: MIT
category: automation
subcategory: multi-agent-orchestration
entry_point: skill.ps1
---

# VORTEX-OS — Multi-Agent Orchestration Engine

> **Stop managing tasks. Start commanding a native digital workforce.**

VORTEX-OS is a **self-bootstrapping PowerShell skill** that drives the
[Cloudmeru/vortex-os-dotnet](https://github.com/Cloudmeru/vortex-os-dotnet)
.NET 10 C++/CLI engine to orchestrate **multi-agent, multi-domain
work pipelines** end-to-end with strict continuity enforcement,
self-healing prompts, and Human-in-the-Loop approval gates. It is
domain-agnostic: the same engine drives a research report, a software
release, a data audit, a design system, a video campaign, or a
narrative series — only the master objective and the plugin roster
change.

The first time the skill runs, it auto-installs the engine (downloads 4
files from the public `vortex-os-dotnet` release, places them in a
user-scope PowerShell module folder, no admin needed). Subsequent runs
are instant. The install is **idempotent**.

---

## Quick Start

```powershell
# 1. Clone the skill (any code agent, any Windows host with PowerShell 7+)
#    OR just point at the existing clone:
cd path\to\vortex-os-skill

# 2. Verify the package is ready (downloads the engine on first run)
pwsh -NoProfile -File .\verify.ps1

# 3. Discover agents + dispatch your first master objective
pwsh -NoProfile -File .\skill.ps1 --agents-discover
# Write your objective to a file, then:
pwsh -NoProfile -File .\skill.ps1 --dispatch-master my_project\objective.md

# 4. When the engine pages you for HITL approval:
pwsh -NoProfile -File .\skill.ps1 --hitl-approve <task_id>

# 5. (Optional, v0.3.0+) Inspect the cross-project memory the engine
#    left behind from this dispatch:
pwsh -NoProfile -File .\skill.ps1 --memory-show my_project
Get-VortexMemory -Project my_project
```

After the first install, the engine is available directly as a
PowerShell module from any session:

```powershell
Import-Module Vortex
Get-VortexAgent
Get-VortexHitlPending
Approve-VortexHitl -TaskId package_websim
Test-VortexPackage

# Cross-project memory (v0.3.0+)
Get-VortexMemory -Project my_project
Get-VortexMemory -Series q1_release
Get-VortexMemory -Operator
```

For the **complete operator walkthrough** (HITL protocol, Continuity
Engine handling, error codes, the 4-tier mental model, the 8 contract
invariants, end-to-end example), read
[`references/INSTRUCTIONS.md`](./references/INSTRUCTIONS.md).

For the **user-facing overview** (install flow, command reference,
4-tier diagram, license), read [`README.md`](./README.md).

For **multi-code-agent support** (minimax code, hermes, aider,
continue.dev, cline, Claude Code, GitHub Copilot Coding Agent) and
the 4-line install contract, read [`COMPATIBILITY.md`](./COMPATIBILITY.md).

---

## Trigger Conditions

**Use this skill when the user's prompt exhibits one or more of:**

- **Multi-domain work** — 3+ distinct deliverable types in one pipeline
  (e.g. research + analysis + visualization + report; or writing +
  audio + code + image; or schema + migration + tests + docs; or
  storyboard + voiceover + music + cut)
- **Multi-step media production** — one source markdown / script
  becoming a finished media deliverable (tutorial video, ad cut,
  narrated slide deck, social clip): N slides + voiceover per slide
  + BGM + final MP4. Use the `media-stack` agent + the
  `media-tutorial-video` recipe in `templates/`.
- **Hierarchical task decomposition** — the user wants a complex
  objective broken into a 4-tier chain of command (planner →
  supervisor → shift → workers) rather than a single LLM call
- **Continuity / consistency requirements** — the user names rules
  that must survive across iterations (entities, brand, style,
  terminology, schema, API contract, code style, regulatory
  constraints, design system, data model, etc.) and wants the engine
  to detect and auto-rewrite violations
- **Self-healing prompts** — the user wants the system to recover
  from LLM drift without manual intervention
- **Auditable LLM pipelines** — every decision must be attributable
  to a named agent, with timestamp and outcome (writes to
  `memory\audit.jsonl` by default)
- **Human-in-the-Loop approval on high-stakes actions** — the user
  explicitly wants to gate finalization (publishing, packaging,
  writing to a protected directory, deploying, etc.) behind human
  confirmation
- **Long-running / multi-iteration / series scope** — the user has a
  multi-iteration / multi-release / multi-chapter project and wants
  Golden Path templates that replay the same workflow for each unit
- **Cross-project context reuse** — the user has run similar projects
  before and wants the new dispatch to inherit the prior operator
  (plugin) profile, deliverable-type histogram, and known gotchas
  instead of starting cold (engine v0.3.0+)
- **In-house / offline execution** — the orchestration layer must
  not depend on external APIs; everything runs locally on the host
- **Cross-domain coordination** — the project touches multiple
  domains (writing + code, or data + viz, or audio + video, etc.)
  and you don't want to hand-coordinate 4 separate tools

**Do NOT use this skill for:**

- Simple one-line code questions → just answer
- Pure chat / Q&A → just chat
- Single-file edits with no cross-domain coordination → use a single tool
- Read-only research or web search → use a search tool
- Tasks with no clear objective → ask the user for clarification first

**Respect explicit invocation.** When the user explicitly invokes the
skill (e.g. `/VORTEX-OS`, "use vortex-os", "via the skill", "with
VORTEX-OS"), you MUST dispatch through the engine
(`--dispatch-master` or `--dispatch-template`) — not bypass to
direct tool calls. The only acceptable bypass is an explicit
"skip the orchestration layer" or "do it directly" phrase from the
user. Hand-rolled direct tool calls are a violation of the skill
contract when the user has asked for the skill.

---

## Skill Anatomy

This skill folder is laid out as follows. Read only what you need.

| File / Folder | Purpose | When to read |
|---|---|---|
| `SKILL.md` (this file) | Lean entry point: **what + when + how to invoke** | Always, on every trigger (~5 KB) |
| `references/INSTRUCTIONS.md` | **Operator playbook** — full walkthrough, HITL protocol, Continuity Engine handling, error codes, 4-tier mental model, the 8 contract invariants, end-to-end example | When you need the details (~20 KB, loaded on demand) |
| `references/architecture.md` | **Mermaid architecture diagrams** — 7 diagrams (big picture, 4-tier chain, storage split, install flow, dispatch+HITL flow, auto-update, data lifecycle) + component reference | When you need the visual mental model (~16 KB, loaded on demand) |
| `README.md` | **User-facing landing page** — install flow, full command reference, 4-tier diagram, license | When the user is new to VORTEX-OS or asks for the public overview |
| `COMPATIBILITY.md` | **Multi-code-agent support** matrix + the 4-line install contract | When a code agent (minimax code, hermes, etc.) needs to know how to drive the skill |
| `CHANGELOG.md` | Per-version changes | When the user asks "what changed in v0.3.0?" |
| `_meta.json` | **Platform metadata** (skill_id, version, capabilities, install flow) | When the platform introspects the skill for registration / discovery |
| `walkthrough/` | **Visual HTML walkthrough** — 11 slides, auto-advancing viewer, MP4 recording recipe (PowerShell + Edge + ffmpeg). Open `walkthrough/index.html` in a browser | When you want a 5-minute visual tour of the skill before reading |
| `CHANGELOG.md` (this file) | **Per-version changes** — what was added, what was reworded, what was removed | When you ask "what changed in v0.3.0?" or "what's the engine version for this skill release?" |
| `skill.ps1` | **The one-shot CLI entry point.** Self-bootstrapping: auto-installs the engine on first run. This is the primary command for any code agent | Always invoke this to dispatch a command |
| `install.ps1` | **The engine installer** (downloads from the GitHub release). Run `skill.ps1 -Install` or this directly | When the user wants to pin a specific engine version or pre-stage the install |
| `install-deps.ps1` | **System-dependency installer** (uses `winget` to install `sqlite3` and optionally `ffmpeg`). Reads the dep list from `_meta.json.winget_install_ids` | Run on a fresh machine before the first dispatch, if `verify.ps1` reports missing tools |
| `auto-update.ps1` | **Engine self-updater**. Queries GitHub for the latest `vortex-os-dotnet` release (rate-limited to once per 6 h per `VORTEX_HOME`) and calls `install.ps1` if a newer version is available. Opt out with `$env:VORTEX_NO_AUTO_UPDATE=1`. Called automatically by `skill.ps1` on every invocation | First run per day, or after a long pause |
| `migrate-state.ps1` | **One-time migration** of legacy state (deliverables, audit log, swarms, state) from the skill folder to `$env:VORTEX_HOME` (default `%APPDATA%\Vortex-OS`). Idempotent, dry-run with `-WhatIf`, has `-AdoptFlat` switch to file legacy flat deliverables into `deliverables/_unfiled/` after upgrading to v0.1.5+ | Run ONCE after upgrading to skill v0.1.4+ to move existing data to the durable location; re-run with `-AdoptFlat` once after upgrading to v0.1.5+ to organize the new per-project layout |
| `uninstall.ps1` | **Clean removal**. Dry-run by default; flags `-Engine` (remove engine + module), `-State` (remove `%APPDATA%\Vortex-OS`), `-All` (both). The skill folder itself is never auto-deleted | When uninstalling or resetting the environment |
| `verify.ps1` | **Post-upload verification** (8 checks: file presence, JSON validity, branding, agent discovery, agent lint, help banner, engine installation). Self-bootstrapping | Run before publishing; CI gate |
| `build.ps1` | **Source-build helper** for forkers (downloads + compiles the .NET engine from `vortex-os-dotnet`) | Only if you've cloned this skill to fork the engine |
| `agents/` | **3 supervisor/inspector manifest files** (the engine's input) | When writing custom agent manifests |
| `templates/` | Golden Path iteration template (engine reads it when `--dispatch-template` is passed) | When designing a multi-iteration / multi-release workflow |

---

## How the install works (one-time, on first run)

`skill.ps1` is self-bootstrapping. The first invocation:

1. Searches `$env:VORTEX_MODULE_PATH`, `$env:PSModulePath`, and the
   canonical `$HOME\Documents\PowerShell\Modules` for an installed
   `Vortex\<version>\Vortex.psd1`.
2. If not found, runs `install.ps1`, which:
   - Calls `GET https://api.github.com/repos/Cloudmeru/vortex-os-dotnet/releases/latest`
     (unauthenticated; 60 req/hr per IP, fine for one install).
   - Downloads `Vortex.dll`, `Vortex.psm1`, `Vortex.psd1`,
     `ijwhost.dll` from the release's `assets[].browser_download_url`.
   - Places them in the first writable user-scope module folder
     (canonical: `$HOME\Documents\PowerShell\Modules\Vortex\<version>\`).
     Handles OneDrive-redirected `Documents` folders gracefully by
     probing each PSModulePath entry with a sentinel subdir.
3. Sets `$env:VORTEX_SKILL_ROOT` to the skill folder so the engine
   finds the skill's `agents/` (and `templates/`, if any).
4. Imports the module and dispatches the command.

The install is **idempotent** — re-running when the same engine version
is already present is a no-op. To upgrade, just re-run `skill.ps1` (or
`install.ps1` directly). To pin a version: `-Version v0.1.7` or set
`$env:VORTEX_VERSION` before invoking.

---

## Where is my data stored?

Starting with **skill v0.1.4 + engine v0.1.7**, the engine splits
storage into two locations:

| Path | What's there | Replaced on skill update? | Shared across skill instances? |
|---|---|---|---|
| **Skill folder** (where you cloned the skill) | `agents/`, `templates/`, scripts, docs, `_meta.json` | **Yes** — that's the whole point | No |
| **`$env:VORTEX_HOME`** (default: `%APPDATA%\Vortex-OS\`) | `state/`, `memory/`, `swarms/`, `deliverables/`, `tasks/` | **No** — durable, user-scope | **Yes** — multiple code agents on the same machine share the same data |

This means:

- **Upgrading the skill never wipes your work.** Re-cloning the
  skill (or pulling a new version) only replaces the scripts, the
  agent manifests, and the docs. Your `deliverables/`, audit log,
  swarms, HITL state, and memory all live in `%APPDATA%\Vortex-OS\`
  and survive.
- **Two code agents on the same machine share state.** If you have
  the VORTEX-OS skill deployed to both `minimax code` and `hermes`,
  they both read and write the same `%APPDATA%\Vortex-OS\` folder
  (unless you override `VORTEX_HOME`). A dispatch from one agent
  shows up in the audit log the other agent reads.
- **Override the location** by setting `$env:VORTEX_HOME` to any
  directory you own. Useful for shared dev environments, sandboxed
  CI runners, or putting data on a non-system drive.

**Starting with skill v0.1.5 + engine v0.1.8**, the engine
**groups deliverables by project** so outputs from multiple
sessions and conversations don't clobber each other:

```
$VORTEX_HOME/
├── memory/
│   ├── audit.jsonl                              # append-only event log
│   └── derived/                                 # v0.3.0+ cross-project memory
│       ├── project/<slug>.json                  # per-project fingerprint
│       ├── series/<series>.json                 # per-series iteration template
│       └── operator.json                        # per-plugin operator profile
└── deliverables/
    ├── client_onboarding_q1/                    # project 1 (auto-derived)
    │   ├── .manifest.json                       # self-describing project metadata
    │   ├── research_notes.md
    │   ├── data_pipeline.py
    │   ├── summary_report.pdf
    │   └── rollout.html
    ├── release_v2/                              # project 2
    │   ├── .manifest.json
    │   ├── changelog.md
    │   ├── migration.sql
    │   └── regression_tests.ps1
    └── _unfiled/                                # legacy files (post-migration)
```

The project name is auto-derived (in priority order):

1. `$env:VORTEX_PROJECT`
2. The `-Project <name>` flag on `skill.ps1`
3. The parent dir of the `--dispatch-master` arg (e.g. `projects/client_onboarding_q1/objective.md` → `client_onboarding_q1`)
4. The filename of the objective without extension (e.g. `release_v2.md` → `release_v2`)
5. If none of the above apply, deliverables land at the flat `deliverables\` root

To re-dispatch the same project with new instructions, the engine
**refuses to overwrite** and asks you to pick a new project name
(or use `-Project <name>_v2`). To force overwrites, manually
clear the project's `deliverables\<project>\` folder first.

**Migrating from an older skill version (v0.1.3 and below):**
the engine v0.1.7+ does **NOT** auto-migrate. Run the skill's
`migrate-state.ps1` once to copy the old `deliverables/`, `memory/`,
`swarms/`, `state/`, `tasks/` from the skill folder to
`%APPDATA%\Vortex-OS\`. The script is idempotent and supports
`-WhatIf` (dry-run) and `-DeleteSource` (remove the originals
after verifying the copy).

```powershell
# 1. Dry-run to see what would move
pwsh -NoProfile -File .\migrate-state.ps1 -WhatIf

# 2. Actually move (leaves the source in place; you can delete it later)
pwsh -NoProfile -File .\migrate-state.ps1

# 3. After verifying the target, remove the originals
pwsh -NoProfile -File .\migrate-state.ps1 -DeleteSource

# 4. (only after upgrading to v0.1.5+) File legacy flat deliverables
#    into deliverables\_unfiled\ so the new per-project layout can take over
pwsh -NoProfile -File .\migrate-state.ps1 -AdoptFlat
```

---

## Cross-project memory (engine v0.3.0+)

Starting with engine v0.3.0, every dispatch leaves behind a small
JSON fingerprint in `$VORTEX_HOME/memory/derived/`. Three layers:

| Layer | File | What it captures |
|---|---|---|
| **Per-project** | `memory/derived/project/<slug>.json` | The project's `project_type_hint`, deliverable-type histogram, the plugin roster used, the last 10 audit events, the manifest of the last successful dispatch |
| **Per-series** | `memory/derived/series/<series>.json` | Auto-detected when project names share a prefix (e.g. `release_q1`, `release_q2` → series `release`). Carries the iteration template, the cross-iteration deltas, the operator (plugin) profile |
| **Per-operator (plugin)** | `memory/derived/operator.json` | Each plugin's `cost_band`, `failure_rate`, `latency_p50/p95`, and last-seen-at — so the dispatcher can rank candidates for the next dispatch |

**Series detection** is purely lexical: a trailing `_<digits>` or
`_<letter><digits>` suffix on the project name is treated as the
iteration index. Works with `client_acme_q1/q2`, `release_v1/v2`,
`audit_iter1/iter2`, `episode_ep1/ep2`, etc. The series name is the
prefix.

To (re)compile the memory store from the on-disk deliverables +
audit log + agent manifests:

```powershell
# One-shot — compile everything (default; idempotent, no-op if up to date)
pwsh -NoProfile -File .\skill.ps1 --compile-memory

# Just one project
pwsh -NoProfile -File .\skill.ps1 --compile-memory --project client_onboarding_q1

# Just the series the project belongs to
pwsh -NoProfile -File .\skill.ps1 --compile-memory --series release

# Just the operator profile (plugin cost + failure stats)
pwsh -NoProfile -File .\skill.ps1 --compile-memory --operator

# Dry-run + force
pwsh -NoProfile -File .\skill.ps1 --compile-memory --dry-run
pwsh -NoProfile -File .\skill.ps1 --compile-memory --all --force
```

To inspect the store from PowerShell (after `Import-Module Vortex`):

```powershell
Get-VortexMemory -Project client_onboarding_q1
Get-VortexMemory -Series release
Get-VortexMemory -Operator
Get-VortexMemory -As detail   # full JSON for one project
Get-VortexMemory -As json     # raw string for ConvertFrom-Json
```

Or via the engine CLI:

```powershell
pwsh -NoProfile -File .\skill.ps1 --memory-show
pwsh -NoProfile -File .\skill.ps1 --memory-show client_onboarding_q1
```

**Future integration:** the `--with-memory` dispatch flag is
reserved for engine v0.3.1 — when set, the dispatcher will read the
relevant slice of `derived/` and inject it into the worker prompt
as a "context this dispatch inherits" block.

## Auto-update of the .NET engine

Starting with **skill v0.1.5**, `skill.ps1` automatically checks
for a newer `vortex-os-dotnet` release on GitHub on every
invocation and installs it if a newer version is available. The
check is rate-limited to once per 6 hours per `VORTEX_HOME` (so
the GitHub API is hit at most ~4 times per day) and is opt-out
via `$env:VORTEX_NO_AUTO_UPDATE=1`.

When an update is found, the new engine is downloaded to a new
`Vortex\<version>\` folder (e.g. `Vortex\0.1.9\`), the old
version is left in place for rollback, and the message
`"Engine updated to v0.1.9. Restart skill.ps1 to use the new
version."` is printed. The next `skill.ps1` invocation picks up
the new version automatically (PowerShell's module loader uses
the highest version by default).

To force a check right now (bypassing the 6h rate limit):

```powershell
pwsh -NoProfile -File .\auto-update.ps1 -Force
```

To install a specific version manually (bypasses auto-update):

```powershell
pwsh -NoProfile -File .\install.ps1 -Version v0.1.7
```

---

## System dependencies (one-time, per machine)

The engine is **pure .NET 10 / C++/CLI**. It does **NOT** need Python,
jq, or any scripting runtime. The only required external tool is
`sqlite3` (used by the engine's VectorHydrate step for memory
persistence). `ffmpeg` is optional — only the engine's *generated
audio deliverables* use it.

Install via `winget` (Windows Package Manager) — never pip / brew / apt:

```powershell
# Dry-run: see what would be installed
pwsh -NoProfile -File .\install-deps.ps1

# Install the required dep(s)
pwsh -NoProfile -File .\install-deps.ps1 -Install

# Also install ffmpeg (for audio deliverables)
pwsh -NoProfile -File .\install-deps.ps1 -Install -IncludeOptional
```

The dep list is the single source of truth at
`_meta.json.winget_install_ids`. The current deps:

| Tool | winget ID | Required? | Used by |
|---|---|---|---|
| `sqlite3` | `SQLite.SQLite` | yes | Engine: `VectorHydrate` for memory persistence |
| `ffmpeg` | `Gyan.FFmpeg` | no | Generated audio deliverables (Foley, DSP, sample chopping) |

> **A code agent reading this skill MUST install these via `winget
> install --id <winget_id>`, NOT via pip, brew, apt, or choco.**
> Running `pip install` for these will fail and waste time. The
> `_meta.json.winget_install_ids` field is the authoritative source.

---

## Command reference (one-liner)

For the full table with 20+ subcommands, see [`README.md`](./README.md).
The most common invocations:

| Goal | Command |
|---|---|
| List available agents | `pwsh -NoProfile -File .\skill.ps1 --agents-discover` |
| Lint all agents | `pwsh -NoProfile -File .\skill.ps1 --agents-lint --all` |
| Run a project | `pwsh -NoProfile -File .\skill.ps1 --dispatch-master my_project\objective.md` |
| Run a media-tutorial-video recipe (one source -> finished video) | `pwsh -NoProfile -File .\skill.ps1 --dispatch-template templates\media-tutorial-video.json --project intro_tutorial` |
| Check HITL queue | `pwsh -NoProfile -File .\skill.ps1 --hitl-status` |
| Approve / deny a HITL halt | `pwsh -NoProfile -File .\skill.ps1 --hitl-approve <task_id>` / `--hitl-deny <task_id>` |
| View audit log | `pwsh -NoProfile -File .\skill.ps1 --audit-trail` |
| Compile the cross-project memory store | `pwsh -NoProfile -File .\skill.ps1 --compile-memory` |
| Show one project's memory fingerprint | `pwsh -NoProfile -File .\skill.ps1 --memory-show my_project` |
| Force engine reinstall | `pwsh -NoProfile -File .\skill.ps1 -Install` |
| Engine version | `pwsh -NoProfile -File .\skill.ps1 --version` |

---

## Engine source

The C++/CLI engine that powers this skill lives in a separate repo:
**[Cloudmeru/vortex-os-dotnet](https://github.com/Cloudmeru/vortex-os-dotnet)**.
Public releases there are what `install.ps1` downloads. If you need to
patch / fork the engine, see `references/INSTRUCTIONS.md` §13 (build
from source) and the `[Cloudmeru/vortex-os-dotnet README](https://github.com/Cloudmeru/vortex-os-dotnet)` itself.

---

## License

MIT

## Author

MiniMax Agent
