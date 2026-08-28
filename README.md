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
├── auto-update.ps1                        ← Engine self-updater (checks GitHub, rate-limited 6h, opt-out)
├── migrate-state.ps1                      ← One-time state migration (skill folder → $env:VORTEX_HOME; -AdoptFlat for v0.1.4 legacy data)
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

Starting with **skill v0.1.5 + engine v0.1.8**, deliverables
are **grouped by project** so multiple sessions of the same
project (or multiple projects) live side by side without
clobbering each other:

```
%APPDATA%\Vortex-OS\
├── memory\
│   ├── audit.jsonl
│   └── derived\                         # v0.3.0+ cross-project memory
│       ├── project\client_onboarding_q1.json
│       ├── series\release.json
│       └── operator.json
└── deliverables\
    ├── client_onboarding_q1\             # project 1 (slug from the objective file)
    │   ├── .manifest.json
    │   ├── research_notes.md
    │   ├── data_pipeline.py
    │   └── rollout.html
    ├── release_v2\                       # project 2
    │   ├── .manifest.json
    │   ├── changelog.md
    │   └── migration.sql
    └── _unfiled\                         # legacy files (post-migration)
```

The project name is auto-derived from the objective file path
(`projects/client_onboarding_q1/objective.md` → `client_onboarding_q1`),
or override with `-Project <name>` / `$env:VORTEX_PROJECT`.
A v0.3.0+ project with a `_q1` / `_v1` / `_iter1` suffix
auto-joins a series of the same prefix; the engine keeps a
fingerprint per project + per series + per operator in
`memory\derived\` so subsequent dispatches inherit context.

After upgrading from skill v0.1.3 or earlier, run the bundled
migration once to move your existing data:

```powershell
pwsh -NoProfile -File .\migrate-state.ps1 -WhatIf       # dry-run
pwsh -NoProfile -File .\migrate-state.ps1              # move
pwsh -NoProfile -File .\migrate-state.ps1 -DeleteSource # remove originals

# (only after upgrading to v0.1.5+) file legacy flat deliverables
# into deliverables\_unfiled\ so the per-project layout can take over
pwsh -NoProfile -File .\migrate-state.ps1 -AdoptFlat
```

### Cross-project memory (engine v0.3.0+)

The engine writes a small JSON fingerprint to
`$VORTEX_HOME\memory\derived\` after every dispatch. Three layers:

```
%APPDATA%\Vortex-OS\memory\derived\
├── project\client_onboarding_q1.json   # per-project fingerprint
├── series\release.json                 # auto-detected series template
└── operator.json                       # per-plugin cost + failure profile
```

Use it to:

- **Skip cold starts.** A fresh dispatch on `release_v3` inherits the
  plugin roster, the deliverable-type histogram, and the last-10 audit
  events from the `release` series instead of starting from scratch.
- **Rank plugins by cost + failure rate.** The operator profile ranks
  plugins by `cost_band` × `failure_rate` × `latency_p95`, so the
  supervisor picks the right tool without operator prompting.
- **Audit cross-project decisions.** Every dispatch writes a
  per-project manifest; the index in `index.json` answers "where did I
  last see this pattern?" in O(1).

Inspect / compile it from PowerShell:

```powershell
Import-Module Vortex
Get-VortexMemory -Project client_onboarding_q1
Get-VortexMemory -Series release
Get-VortexMemory -Operator

# Or from the engine CLI:
pwsh -NoProfile -File .\skill.ps1 --memory-show
pwsh -NoProfile -File .\skill.ps1 --memory-show client_onboarding_q1
pwsh -NoProfile -File .\skill.ps1 --compile-memory
pwsh -NoProfile -File .\skill.ps1 --compile-memory --project client_onboarding_q1 --force
```

The `--with-memory` dispatch flag (engine v0.3.1) will wire the
fingerprint slice into the worker prompt automatically.

### Auto-update of the .NET engine

`skill.ps1` automatically checks for a newer `vortex-os-dotnet`
release on every invocation and installs it if available. The
check is rate-limited to once per 6 hours per `VORTEX_HOME`,
opt-out via `$env:VORTEX_NO_AUTO_UPDATE=1`.

```powershell
# Force a check right now (bypass the 6h cache)
pwsh -NoProfile -File .\auto-update.ps1 -Force

# Dry-run: print what would happen, don't actually install
pwsh -NoProfile -File .\auto-update.ps1 -DryRun

# Pin a specific engine version (bypass auto-update)
pwsh -NoProfile -File .\install.ps1 -Version v0.1.7
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
T3 — THE CREW (Specialized Workers — pluggable per project)
       ├─── writer.docs          (prose, dialogue, documentation, scripts)
       ├─── media.native         (minimax-music audio, Hailuo video, MiniMax image)
       ├─── coder.typescript     (HTML/CSS/JS, interactive UIs, browser apps)
       ├─── coder.python         (data pipelines, DSP, ffmpeg scripts, tooling)
       ├─── researcher.web       (web research, citations, fact-check)
       ├─── analyst.strategic    (strategy, planning, risk, forecasting)
       ├─── designer.brand       (visual identity, design system, brand)
       ├─── data.sqlite          (SQLite queries, vector hydrate, migrations)
       └─── data.researcher      (literature review, dataset cards, comparisons)
```

The roster is **pluggable**: the supervisor dispatches to whichever
T3 plugins the master objective and the agent manifests name. A
research report uses `researcher.web` + `analyst.strategic` + `writer.docs`;
a video campaign uses `media.native` + `designer.brand` + `writer.docs`;
a data audit uses `data.sqlite` + `data.researcher` + `analyst.strategic`.
Same 4-tier chain, different crew.

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
