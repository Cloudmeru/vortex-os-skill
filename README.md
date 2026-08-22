# VORTEX-OS

> **The Native Autonomous Studio Command Center**
> *Stop managing tasks. Start commanding a native digital workforce.*

The VORTEX-OS skill for the MiniMax ecosystem. The underlying .NET 10
C++/CLI engine lives in **[Cloudmeru/vortex-os-dotnet](https://github.com/Cloudmeru/vortex-os-dotnet)**
and is **downloaded from its public GitHub releases at install time** —
the skill itself ships zero engine binaries, so the version stays in
lockstep with the latest release.

---

## Quick Start

> **Self-bootstrapping install.** The first time you run `skill.ps1`
> or `verify.ps1`, the skill downloads the 4 engine files
> (`Vortex.dll` + `Vortex.psm1` + `Vortex.psd1` + `ijwhost.dll`) from
> the public release of `Cloudmeru/vortex-os-dotnet` and installs them
> to `$HOME\Documents\PowerShell\Modules\Vortex\<version>\`. No admin,
> no system changes, no authentication. Subsequent runs are instant.

```powershell
# Verify the package is ready (downloads the engine on first run, then checks)
pwsh -NoProfile -File .\verify.ps1

# Discover agents + lint them
pwsh -NoProfile -File .\skill.ps1 --agents-discover
pwsh -NoProfile -File .\skill.ps1 --agents-lint --all

# Submit your first master objective
New-Item -ItemType Directory -Force -Path my_project
# ... write my_project\objective.md ...
pwsh -NoProfile -File .\skill.ps1 --dispatch-master my_project\objective.md

# When HITL fires:
pwsh -NoProfile -File .\skill.ps1 --hitl-status
pwsh -NoProfile -File .\skill.ps1 --hitl-approve package_websim

# Inspect results:
Get-ChildItem deliverables\
pwsh -NoProfile -File .\skill.ps1 --audit-trail

# In any persistent PowerShell 7+ session after install:
Import-Module Vortex
Get-VortexAgent
Get-VortexHitlPending
Approve-VortexHitl -TaskId package_websim
```

---

## File Structure

```
vortex-os-skill/
├── SKILL.md                              ← ★ LLM instruction brain (lean, always-on)
├── README.md                              ← (this file)
├── COMPATIBILITY.md                       ← Supported code agents + install patterns
├── _meta.json                             ← Platform metadata
├── CHANGELOG.md                           ← Per-version changes
├── LICENSE                                ← MIT
│
├── references/
│   └── INSTRUCTIONS.md                    ← ★ LLM operator knowledge base (deep dive, on-demand)
│
├── skill.ps1                              ← ★ One-shot CLI entry point (self-bootstrapping)
├── verify.ps1                             ← ★ Post-upload verification entry point
├── install.ps1                            ← Engine installer (downloads from GitHub release)
├── install-deps.ps1                       ← System-dep installer (uses winget; reads _meta.json)
├── migrate-state.ps1                      ← One-time state migration (skill folder → $env:VORTEX_HOME)
├── build.ps1                              ← Helper: source-build the engine (for forkers)
│
├── agents/                                ← 3 supervisor/inspector manifests
│   ├── supervisor.store.json
│   ├── supervisor.shift.json
│   └── inspector.governance.json
│
└── state/  swarms/  tasks/  memory/  deliverables/   ← Runtime (created on first run)
```

The skill follows the Mavis/Claude 3-level loading convention:
- `SKILL.md` (this file) is **lean** (~10 KB) so the agent can detect +
  decide to trigger on it without bloating its context.
- `references/INSTRUCTIONS.md` (~20 KB) is the **operator playbook** —
  loaded on demand when the agent needs the full walkthrough, the
  HITL protocol, the error code table, the 4-tier mental model, etc.
- `README.md` is the **user-facing overview** (install flow, command
  reference, license).

---

## Engine installation

The C++/CLI engine (`Vortex.dll` + `Vortex.psm1` + `Vortex.psd1` +
`ijwhost.dll`) is the upstream component. The skill does **not** bundle
it — it downloads the latest release from
[Cloudmeru/vortex-os-dotnet/releases](https://github.com/Cloudmeru/vortex-os-dotnet/releases)
at install time and places the files in a user-scope PowerShell module
folder. This keeps the skill package small and the engine version in
lockstep with upstream.

### Default (self-bootstrapping)

```powershell
pwsh -NoProfile -File .\skill.ps1 --version
```

The first invocation downloads + installs the engine. Re-runs are
free. The install is **idempotent**: re-running when the same engine
version is already present is a no-op.

### Manual install

```powershell
pwsh -NoProfile -File .\install.ps1                          # latest
pwsh -NoProfile -File .\install.ps1 -Version v0.1.4          # pin a version
pwsh -NoProfile -File .\install.ps1 -ModulePath 'D:\psmodules'  # custom path
$env:VORTEX_VERSION = 'v0.1.4'; pwsh -NoProfile -File .\install.ps1
```

The install scans `$env:PSModulePath` and the canonical
`$HOME\Documents\PowerShell\Modules` for a writable user-scope module
base, and handles OneDrive-redirected `Documents` folders
gracefully (falls back to the first non-OneDrive entry).

### PowerShell Gallery (future)

When the `Vortex` module ships to PSGallery, you can install it
directly:

```powershell
Install-Module -Name Vortex -Scope CurrentUser -Force
```

The skill's `skill.ps1` / `verify.ps1` will pick up the PSGallery
version from the user-scope module folder.

### Build from source (for forkers only)

```powershell
pwsh -NoProfile -File .\build.ps1                  # download main.zip + build
pwsh -NoProfile -File .\build.ps1 -DotnetSrc 'C:\path\to\vortex-os-dotnet'
pwsh -NoProfile -File .\build.ps1 -Install         # build + install to user-scope
```

This compiles the C++/CLI engine with MSVC v143
(`cl /clr:netcore /std:c++20`) and copies the artifacts. Only useful
if you've cloned this skill to patch the engine.

### System dependencies (one-time, per machine)

The engine is pure .NET 10 / C++/CLI. It does **not** need Python, jq,
or any scripting runtime. The only required external tool is
`sqlite3` (for memory persistence); `ffmpeg` is optional (for
generated audio deliverables). Install via `winget`:

```powershell
pwsh -NoProfile -File .\install-deps.ps1                 # dry-run
pwsh -NoProfile -File .\install-deps.ps1 -Install        # install required
pwsh -NoProfile -File .\install-deps.ps1 -Install -IncludeOptional   # + ffmpeg
```

The dep list lives in [`_meta.json.winget_install_ids`](./_meta.json)
and is the single source of truth. Current deps:

| Tool | winget ID | Required? | Used by |
|---|---|---|---|
| `sqlite3` | `SQLite.SQLite` | yes | Engine: VectorHydrate for memory persistence |
| `ffmpeg` | `Gyan.FFmpeg` | no | Generated audio deliverables |

> **A code agent reading this MUST install these via `winget install
> --id <winget_id>`, NOT via pip / brew / apt / choco.** The
> `install-deps.ps1` script is the canonical wrapper.

### Where is my data stored?

Starting with **skill v0.1.4 + engine v0.1.7**, the engine splits
storage into two locations:

| Location | Holds | Replaced on skill update? | Shared across instances? |
|---|---|---|---|
| **Skill folder** (where you cloned) | `agents/`, `templates/`, scripts, docs | **Yes** | No |
| **`$env:VORTEX_HOME`** (default `%APPDATA%\Vortex-OS\`) | `state/`, `memory/`, `swarms/`, `deliverables/`, `tasks/` | **No** | **Yes** |

This means upgrading the skill **never wipes your work**, and
multiple code agents on the same machine (e.g. minimax code +
hermes) share the same audit log + deliverables. Override the
location with `$env:VORTEX_HOME = 'D:\my-data'`.

After upgrading from skill v0.1.3 or earlier, run the bundled
migration once to move your existing data:

```powershell
pwsh -NoProfile -File .\migrate-state.ps1 -WhatIf       # dry-run
pwsh -NoProfile -File .\migrate-state.ps1              # move
pwsh -NoProfile -File .\migrate-state.ps1 -DeleteSource # remove originals
```

---

## The Complete Command Reference

> All commands below invoke **`skill.ps1`** (the master entry point),
> which locates the Vortex module (downloading + installing it on
> first run), imports it, and forwards every argument to the C++/CLI
> dispatcher. From a persistent PowerShell 7+ session, you can also
> call the cmdlets directly after `Import-Module Vortex`.

### Discovery & Inspection
| Command | Cmdlet | Purpose |
|---|---|---|
| `skill.ps1 --agents-discover` | `Get-VortexAgent` | List all available agents |
| `skill.ps1 --agents-inspect <name>` | `Invoke-Vortex --agents-inspect <name>` | Dump a single agent's manifest |
| `skill.ps1 --agents-validate <file.json>` | `Invoke-Vortex --agents-validate <file.json>` | Validate a custom agent manifest |
| `skill.ps1 --agents-lint [--all\|<name>]` | `Invoke-Vortex --agents-lint` | Lint agents against the 8 invariants |
| `skill.ps1 --agents-graph` | `Invoke-Vortex --agents-graph` | Print the agent graph |

### Dispatch
| Command | Cmdlet | Purpose |
|---|---|---|
| `skill.ps1 --dispatch-master <objective.md>` | `Invoke-Vortex --dispatch-master` | Submit to T0 General Manager |
| `skill.ps1 --dispatch-template <template.json>` | `Invoke-Vortex --dispatch-template` | Replay a Golden Path |
| `skill.ps1 --dispatch-v4 <task_id> <agent>` | `Invoke-Vortex --dispatch-v4` | Direct V4 dispatch |

### HITL
| Command | Cmdlet | Purpose |
|---|---|---|
| `skill.ps1 --hitl-status` | `Get-VortexHitlPending` | List pending requests |
| `skill.ps1 --hitl-approve <task_id>` | `Approve-VortexHitl -TaskId …` | Approve |
| `skill.ps1 --hitl-deny <task_id>` | `Deny-VortexHitl -TaskId …` | Deny |

### Inspection
| Command | Cmdlet | Purpose |
|---|---|---|
| `skill.ps1 --inspector-check <task_id>` | `Invoke-Vortex --inspector-check` | Run Continuity Engine check |
| `skill.ps1 --audit-trail` | `Get-VortexAuditTrail` | Print the audit log |

---

## How HITL Works

When a high-stakes action is reached, VORTEX-OS **suspends its state to disk** and pages you:

```powershell
pwsh -NoProfile -File .\skill.ps1 --hitl-status
# → package_websim is PENDING_HUMAN

pwsh -NoProfile -File .\skill.ps1 --hitl-approve package_websim   # greenlight
# or
pwsh -NoProfile -File .\skill.ps1 --hitl-deny package_websim     # block
```

**Never auto-approve. Always surface the halt to the user.**

---

## The 4-Tier Chain of Command

```
T0 — GENERAL MANAGER (The Apex)
       │  • Receives your master objective
       │  • Performs deep decomposition
       ▼
T1 — STORE SUPERVISOR (Domain Strategy)
       │  • Maintains the "Golden Path" project files
       │  • Routes to the right specialist swarm
       ▼
T2 — SHIFT SUPERVISOR (Tactical QA)
       │  • Enforces the Continuity Engine (universe canon)
       │  • Runs sandbox verification on generated code
       │  • Holds the HITL checkpoint for high-stakes actions
       ▼
T3 — THE CREW (Specialized Workers)
       ├─── writer.docs          (prose, dialogue, narrative)
       ├─── media.native         (minimax-music audio, Hailuo video)
       ├─── coder.typescript     (HTML/CSS/JS, WebSim UIs, VibeOS)
       ├─── coder.python         (ffmpeg scripts, data pipelines, DSP)
       ├─── researcher.web       (web research, citations)
       ├─── analyst.strategic    (strategy, planning, risk)
       └─── designer.brand       (visual identity, continuity)
```

---

## License

[MIT](./LICENSE)

## See also

- **[Cloudmeru/vortex-os-dotnet](https://github.com/Cloudmeru/vortex-os-dotnet)** —
  the upstream .NET 10 C++/CLI engine that this skill wraps.
- **[Cloudmeru/vortex-os-dotnet/releases](https://github.com/Cloudmeru/vortex-os-dotnet/releases)** —
  engine releases + CI build artifacts (downloaded by `install.ps1`).
- **[COMPATIBILITY.md](./COMPATIBILITY.md)** — list of supported code
  agents and the install pattern for each.
