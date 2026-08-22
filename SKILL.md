---
name: VORTEX-OS
display_name: VORTEX-OS — Native Autonomous Studio Command Center
version: 0.1.2
description: |
  VORTEX-OS is a self-bootstrapping PowerShell skill that drives the
  [Cloudmeru/vortex-os-dotnet](https://github.com/Cloudmeru/vortex-os-dotnet)
  .NET 10 C++/CLI engine to orchestrate multi-agent creative production
  pipelines (writing + audio + code + video + image) on the MiniMax
  ecosystem. Use it for VibeOS modules, WebSims, narrative universes
  (When Ocean Meets Sky, Book of the Fading Age), Hailuo video
  pipelines, ffmpeg audio, and any cross-domain project that needs
  continuity enforcement + audit trails + Human-in-the-Loop approval.

  TRIGGER when: multi-agent orchestration, hierarchical task
  decomposition (T0→T3), MiniMax native media generation,
  continuity-enforced creative work, auditable LLM pipelines,
  HITL-gated high-stakes actions, narrative-series / lore-universe
  management, procedural media generation at factory scale, internal
  MiniMax app scaffolding.

  DO NOT TRIGGER when: simple one-line code questions, pure chat /
  Q&A, single-file edits with no cross-domain coordination, read-only
  research, or tasks with no clear objective.
author: MiniMax Agent
license: MIT
category: automation
subcategory: multi-agent-orchestration
entry_point: skill.ps1
---

# VORTEX-OS — Native Autonomous Studio Command Center

> **Stop managing tasks. Start commanding a native digital workforce.**

VORTEX-OS is a **self-bootstrapping PowerShell skill** that drives the
[Cloudmeru/vortex-os-dotnet](https://github.com/Cloudmeru/vortex-os-dotnet)
.NET 10 C++/CLI engine to orchestrate **multi-agent, multi-domain
creative production pipelines** end-to-end on the MiniMax ecosystem —
writing, audio, code, video, and image, all in-house, with full audit
trails and Human-in-the-Loop approval gates.

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

**Use this skill when the user requests:**

- **Multi-disciplinary projects** that span writing + audio + code +
  video + image in one pipeline
- **Hierarchical task decomposition** — T0 General Manager → T1 Store
  Supervisor → T2 Shift Supervisor → T3 specialized workers
- **Universe-constrained creative work** — continuity enforcement for
  lore, character consistency, era rules, physics rules
- **Native MiniMax media generation** — Hailuo video, minimax-music
  audio, minimax-image — without external API keys
- **Auditable LLM pipelines** where every decision must be traceable
  in `memory\audit.jsonl`
- **High-stakes deployments** that require Human-in-the-Loop approval
  before finalization (e.g. packaging a WebSim, publishing a
  deliverable, writing to `deliverables\`)
- **Self-healing prompts** that recover from LLM drift via the
  Self-Healing Prompt Optimizer
- **VibeOS modules, WebSims, narrative series, internal app
  scaffolding** for the MiniMax ecosystem
- **Local ffmpeg audio** — Foley, sample chopping, DSP — inside a
  sandbox
- **Code generation** (TypeScript, Python) inside the engine's sandbox
- **Procedural media generation** at factory scale, entirely in-house
- **Long-running creative projects** that need persistence + replay
  (Golden Path templates)

**Do NOT use this skill for:**

- Simple one-line code questions → just answer
- Pure chat / Q&A → just chat
- Single-file edits with no cross-domain coordination → use a single tool
- Read-only research → use a web search
- Tasks with no clear objective → ask the user for clarification first

---

## Skill Anatomy

This skill folder is laid out as follows. Read only what you need.

| File / Folder | Purpose | When to read |
|---|---|---|
| `SKILL.md` (this file) | Lean entry point: **what + when + how to invoke** | Always, on every trigger (~5 KB) |
| `references/INSTRUCTIONS.md` | **Operator playbook** — full walkthrough, HITL protocol, Continuity Engine handling, error codes, 4-tier mental model, the 8 contract invariants, end-to-end example | When you need the details (~20 KB, loaded on demand) |
| `README.md` | **User-facing landing page** — install flow, full command reference, 4-tier diagram, license | When the user is new to VORTEX-OS or asks for the public overview |
| `COMPATIBILITY.md` | **Multi-code-agent support** matrix + the 4-line install contract | When a code agent (minimax code, hermes, etc.) needs to know how to drive the skill |
| `CHANGELOG.md` | Per-version changes | When the user asks "what changed in v0.1.2?" |
| `_meta.json` | **Platform metadata** (skill_id, version, capabilities, install flow) | When the platform introspects the skill for registration / discovery |
| `skill.ps1` | **The one-shot CLI entry point.** Self-bootstrapping: auto-installs the engine on first run. This is the primary command for any code agent | Always invoke this to dispatch a command |
| `install.ps1` | **The engine installer** (downloads from the GitHub release). Run `skill.ps1 -Install` or this directly | When the user wants to pin a specific engine version or pre-stage the install |
| `verify.ps1` | **Post-upload verification** (8 checks: file presence, JSON validity, branding, agent discovery, agent lint, help banner, engine installation). Self-bootstrapping | Run before publishing; CI gate |
| `build.ps1` | **Source-build helper** for forkers (downloads + compiles the .NET engine from `vortex-os-dotnet`) | Only if you've cloned this skill to fork the engine |
| `agents/` | **3 supervisor/inspector manifest files** (the engine's input) | When writing custom agent manifests |

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
   finds the skill's `agents/`, `state/`, `memory/`, `deliverables/`.
4. Imports the module and dispatches the command.

The install is **idempotent** — re-running when the same engine version
is already present is a no-op. To upgrade, just re-run `skill.ps1` (or
`install.ps1` directly). To pin a version: `-Version v0.1.4` or set
`$env:VORTEX_VERSION` before invoking.

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
