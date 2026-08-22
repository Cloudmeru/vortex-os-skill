# VORTEX-OS

> **The Native Autonomous Studio Command Center**
> *Stop managing tasks. Start commanding a native digital workforce.*

The VORTEX-OS skill for the MiniMax ecosystem. For the underlying
.NET 10 engine, see **[Cloudmeru/vortex-os-dotnet](https://github.com/Cloudmeru/vortex-os-dotnet)**.

---

## Quick Start

> The skill ships a one-shot CLI (`skill.ps1`) plus PowerShell cmdlets
> (`Get-VortexAgent`, `Approve-VortexHitl`, …). The engine is a .NET 10
> C++/CLI class library (`Vortex.dll`) bundled in this skill so the CLI
> works out of the box. See §"Engine installation" below for the
> PSGallery / from-source alternatives.

```powershell
pwsh -NoProfile -File .\verify.ps1         # ALL VERIFICATION CHECKS PASSED

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

# Or, in a persistent PowerShell session:
Import-Module .\Vortex.psd1
Get-VortexAgent
Get-VortexHitlPending
Approve-VortexHitl -TaskId package_websim
```

---

## File Structure

```
vortex-os-skill/
├── SKILL.md                              ← ★ LLM instruction brain
├── INSTRUCTIONS.md                        ← ★ LLM operator knowledge base
├── README.md                              ← (this file)
├── _meta.json                             ← Platform metadata
│
├── skill.ps1                              ← ★ One-shot CLI entry point
├── verify.ps1                             ← ★ Post-upload verification entry point
│
├── Vortex.dll                             ← ★ Bundled .NET 10 C++/CLI engine
├── Vortex.psd1                            ← PowerShell module manifest
├── Vortex.psm1                            ← PowerShell module
├── ijwhost.dll                            ← .NET 10 IJW host stub (engine runtime dep)
│
├── build.ps1                              ← Helper: download & rebuild the engine
├── LICENSE                                ← MIT
│
├── agents/                                ← 3 supervisor manifests
│   ├── supervisor.store.json
│   ├── supervisor.shift.json
│   └── inspector.governance.json
│
└── state/  swarms/  tasks/  memory/  deliverables/   ← Runtime (created on first run)
```

---

## Engine installation

The C++/CLI engine (`Vortex.dll`) is the upstream component. This skill
bundles a prebuilt copy so the one-shot CLI works out of the box. You only
need to manage the engine separately if you want to:

- **Install from PowerShell Gallery** (when published) instead of using
  the bundled binaries.
- **Build from source** to patch / fork the engine.

### From PowerShell Gallery (target: a future v0.2.x release)

```powershell
pwsh -NoProfile -File .\build.ps1 psgallery
# Then remove the bundled engine so the skill picks up the gallery one:
Remove-Item .\Vortex.dll, .\Vortex.psm1, .\Vortex.psd1, .\ijwhost.dll
```

This installs the `Vortex` module to `$HOME\Documents\PowerShell\Modules\Vortex\`
and prints next-step instructions.

### From source (build.ps1)

```powershell
pwsh -NoProfile -File .\build.ps1
```

This downloads the C++/CLI source from
[Cloudmeru/vortex-os-dotnet](https://github.com/Cloudmeru/vortex-os-dotnet),
compiles it with MSVC v143 (`cl /clr:netcore /std:c++20`), and copies
`Vortex.dll` + `ijwhost.dll` back next to the skill.

If you have a local checkout of the .NET source repo, point the build
script at it via the `VORTEX_DOTNET_SRC` env var:

```powershell
$env:VORTEX_DOTNET_SRC = 'C:\path\to\vortex-os-dotnet'
pwsh -NoProfile -File .\build.ps1
```

### Use the bundled engine (default)

Do nothing. The skill ships a `Vortex.dll` that matches this skill's
version. The one-shot CLI (`skill.ps1`) and the cmdlets (`Get-VortexAgent`,
…) work out of the box as soon as PowerShell 7+ is on PATH.

---

## The Complete Command Reference

> All commands below invoke **`skill.ps1`** (the master entry point), which
> loads `Vortex.psm1` and forwards every argument to the C++/CLI
> dispatcher. From a persistent PowerShell 7+ session, you can also call
> the cmdlets directly after `Import-Module .\Vortex.psd1`.

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
  engine releases + CI build artifacts.
- **`/r/dotnet/fortex-os-skill`** — older local working copy
