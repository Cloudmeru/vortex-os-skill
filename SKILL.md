---
name: VORTEX-OS
display_name: VORTEX-OS - Multi-Agent Orchestration Engine
version: 0.1.12
description: |
  VORTEX-OS is a self-bootstrapping PowerShell skill that drives the
  [Cloudmeru/vortex-os-dotnet](https://github.com/Cloudmeru/vortex-os-dotnet)
  .NET 10 C++/CLI engine to orchestrate multi-agent work pipelines with
  strict continuity enforcement, self-healing prompts, and explicit
  Human-in-the-Loop approval. The engine decomposes a master objective
  into a 4-tier chain of command (planner → supervisor → shift →
  specialized workers), runs the workers in parallel across distinct
  domains (writing, audio, code, video, image, data, etc.), auto-
  rewrites any prompt that violates a continuity rule, gates high-
  stakes actions behind explicit human approval, and writes a fully-
  attributed audit log (every action tied to a named agent, a
  timestamp, and a status).

  Trigger this skill when the user's request exhibits one or more of:
    - multi-domain work (3+ distinct deliverable types in one pipeline)
    - continuity / consistency requirements (character, era, lore,
      brand, style, or any rules that must survive across iterations)
    - explicit Human-in-the-Loop approval on high-stakes actions
      (publishing, packaging, writing to a protected directory, etc.)
    - a per-agent audit trail (every decision attributable to a named
      worker, with timestamp and outcome)
    - long-running / episodic / series scope (Golden Path templates
      that replay across episodes, chapters, releases, etc.)
    - in-house / offline execution (no external API dependencies
      for the orchestration layer)

  Do NOT trigger this skill for:
    - simple one-line code questions
    - pure chat / Q&A tasks
    - single-file edits with no cross-domain coordination
    - read-only research or web search
    - tasks with no clear objective (ask the user for clarification first)
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
self-healing prompts, and Human-in-the-Loop approval gates.

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
```

After the first install, the engine is available directly as a
PowerShell module from any session:

```powershell
Import-Module Vortex
Get-VortexAgent
Get-VortexHitlPending
Approve-VortexHitl -TaskId package_websim
Test-VortexPackage
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
  (e.g. writing + audio + code + image; or research + analysis +
  visualization + report; or schema + migration + tests + docs)
- **Hierarchical task decomposition** — the user wants a complex
  objective broken into a 4-tier chain of command (planner →
  supervisor → shift → workers) rather than a single LLM call
- **Continuity / consistency requirements** — the user names rules
  that must survive across iterations (character, era, lore, brand,
  style, terminology, schema, API contract, code style, etc.) and
  wants the engine to detect and auto-rewrite violations
- **Self-healing prompts** — the user wants the system to recover
  from LLM drift without manual intervention
- **Auditable LLM pipelines** — every decision must be attributable
  to a named agent, with timestamp and outcome (writes to
  `memory\audit.jsonl` by default)
- **Human-in-the-Loop approval on high-stakes actions** — the user
  explicitly wants to gate finalization (publishing, packaging,
  writing to a protected directory, deploying, etc.) behind human
  confirmation
- **Long-running / episodic / series scope** — the user has a
  multi-episode / multi-chapter / multi-release project and wants
  Golden Path templates that replay the same workflow for each unit
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
| `CHANGELOG.md` | Per-version changes | When the user asks "what changed in v0.1.2?" |
| `_meta.json` | **Platform metadata** (skill_id, version, capabilities, install flow) | When the platform introspects the skill for registration / discovery |
| `walkthrough/` | **Visual HTML walkthrough** — 11 slides, auto-advancing viewer, MP4 recording recipe (PowerShell + Edge + ffmpeg). Open `walkthrough/index.html` in a browser | When you want a 5-minute visual tour of the skill before reading |
| `idea-future-recommendations.md` | 18 prioritized next-version items + 12 known gaps + 5 open questions | When planning v0.1.7+ roadmap |
| `idea-architecture-decisions.md` | 15 Architecture Decision Records (engine choice, two-root storage, user-scope install, self-bootstrapping, etc.) | When you need to know *why* a design decision was made |
| `idea-faq-and-pitfalls.md` | 30+ Q&As across 10 categories (install, storage, HITL, self-heal, manifest, audio, etc.) | When something is broken and you need a fast answer |
| `skill.ps1` | **The one-shot CLI entry point.** Self-bootstrapping: auto-installs the engine on first run. This is the primary command for any code agent | Always invoke this to dispatch a command |
| `install.ps1` | **The engine installer** (downloads from the GitHub release). Run `skill.ps1 -Install` or this directly | When the user wants to pin a specific engine version or pre-stage the install |
| `install-deps.ps1` | **System-dependency installer** (uses `winget` to install `sqlite3` and optionally `ffmpeg`). Reads the dep list from `_meta.json.winget_install_ids` | Run on a fresh machine before the first dispatch, if `verify.ps1` reports missing tools |
| `auto-update.ps1` | **Engine self-updater**. Queries GitHub for the latest `vortex-os-dotnet` release (rate-limited to once per 6 h per `VORTEX_HOME`) and calls `install.ps1` if a newer version is available. Opt out with `$env:VORTEX_NO_AUTO_UPDATE=1`. Called automatically by `skill.ps1` on every invocation | First run per day, or after a long pause |
| `migrate-state.ps1` | **One-time migration** of legacy state (deliverables, audit log, swarms, state) from the skill folder to `$env:VORTEX_HOME` (default `%APPDATA%\Vortex-OS`). Idempotent, dry-run with `-WhatIf`, has `-AdoptFlat` switch to file legacy flat deliverables into `deliverables/_unfiled/` after upgrading to v0.1.5+ | Run ONCE after upgrading to skill v0.1.4+ to move existing data to the durable location; re-run with `-AdoptFlat` once after upgrading to v0.1.5+ to organize the new per-project layout |
| `uninstall.ps1` | **Clean removal**. Dry-run by default; flags `-Engine` (remove engine + module), `-State` (remove `%APPDATA%\Vortex-OS`), `-All` (both). The skill folder itself is never auto-deleted | When uninstalling or resetting the environment |
| `verify.ps1` | **Post-upload verification** (8 checks: file presence, JSON validity, branding, agent discovery, agent lint, help banner, engine installation). Self-bootstrapping | Run before publishing; CI gate |
| `build.ps1` | **Source-build helper** for forkers (downloads + compiles the .NET engine from `vortex-os-dotnet`) | Only if you've cloned this skill to fork the engine |
| `agents/` | **3 supervisor/inspector manifest files** (the engine's input) | When writing custom agent manifests |
| `templates/` | Golden Path episode template (engine reads it when `--dispatch-template` is passed) | When designing a multi-episode / series workflow |

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
└── deliverables/
    ├── trial_of_echoes/                 # project 1 (auto-derived)
    │   ├── .manifest.json               # self-describing project metadata
    │   ├── scene1.md
    │   ├── scene2.md
    │   ├── scene3.md
    │   ├── mira_portrait.png
    │   └── trial_of_echoes.html
    ├── cartographer_daughter/          # project 2
    │   ├── .manifest.json
    │   ├── episode1_script.md
    │   └── beatriz_portrait.png
    └── _unfiled/                        # legacy files (post-migration)
```

The project name is auto-derived (in priority order):
1. `$env:VORTEX_PROJECT`
2. The `-Project <name>` flag on `skill.ps1`
3. The parent dir of the `--dispatch-master` arg (e.g. `projects/trial_of_echoes/objective.md` → `trial_of_echoes`)
4. The filename of the objective without extension (e.g. `cartographer_ep1.md` → `cartographer_ep1`)
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
| Check HITL queue | `pwsh -NoProfile -File .\skill.ps1 --hitl-status` |
| Approve / deny a HITL halt | `pwsh -NoProfile -File .\skill.ps1 --hitl-approve <task_id>` / `--hitl-deny <task_id>` |
| View audit log | `pwsh -NoProfile -File .\skill.ps1 --audit-trail` |
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
