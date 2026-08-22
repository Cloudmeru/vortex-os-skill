---
name: VORTEX-OS
display_name: VORTEX-OS — Native Autonomous Studio Command Center
version: 0.1.0
description: |
  VORTEX-OS is a Hierarchical Autonomous Orchestration Engine designed to treat
  AI agency as a high-stakes, closed-loop corporate operation. Built exclusively
  to maximize the native capabilities of the MiniMax ecosystem, VORTEX-OS
  decouples strategic planning from operational labor. It enables you to ship
  complex, multi-modal projects — such as internal web apps, interactive
  sandboxed code, foley sound design, and procedural video — without ever
  relying on fragile external websites.

  TRIGGER when: building VibeOS modules, WebSims, interactive apps, narrative
  series, native Hailuo video pipelines, local ffmpeg audio processing, lore
  universe management (When Ocean Meets Sky, Book of the Fading Age), complex
  internal app scaffolding, procedural media generation entirely in-house with
  no external API keys.

  DO NOT TRIGGER when: simple one-line code requests, pure chat / Q&A tasks,
  single-file edits with no cross-domain coordination, read-only research
  questions.
author: MiniMax Agent
license: MIT
category: automation
subcategory: multi-agent-orchestration
entry_point: skill.ps1
---

# VORTEX-OS: The Autonomous Operating System for Creative Production

**VORTEX-OS** is a **Hierarchical Autonomous Orchestration Engine** designed to treat AI agency as a high-stakes, closed-loop corporate operation. Built exclusively to maximize the native capabilities of the MiniMax ecosystem, VORTEX-OS decouples strategic planning from operational labor.

**VORTEX-OS turns your chat interface into a factory. You define the mission; the swarm handles the rest.**

---

## THE ARCHITECTURE OF A DIGITAL WORKFORCE

VORTEX-OS utilizes a rigid, 4-tier chain of command to eliminate the "Context Rot" and "Infinite Loop" failures common in standard agentic systems:

* **General Manager (The Apex)** — Receives your master objective and performs a deep decomposition, creating a master plan that ensures your vision is respected throughout the entire lifecycle.
* **Store Supervisors (Domain Strategy)** — Strategic domain managers that maintain your "Golden Path" project files. They know exactly which specialized swarm is required for your request and manage the resource allocation.
* **Shift Supervisors (Tactical QA)** — The heartbeat of the system. These agents act as a brick wall between your vision and "The Crew." They enforce your universe's physical laws (The Continuity Engine), perform automated code-sandbox testing, and reject any generation that fails to meet your high-fidelity standards.
* **The Crew (Specialized Workers)** — Tiered, specialized agents — from `coder.typescript` to `media.native` — that execute the granular labor directly utilizing MiniMax's native APIs.

---

## UNMATCHED GOVERNANCE & SAFETY

* **The Governance Inspector** — An always-on auditing tier that monitors token velocity. If a swarm hits a recursive loop or a cost-spike, the Inspector pulls the emergency brake instantly, protecting your compute budget.
* **Deep-Sleep HITL (Human-In-The-Loop)** — When a task reaches a "High-Stakes" threshold (like compiling a complex UI package), the system automatically suspends its state to disk, performs a "Deep Sleep," and pages you for explicit approval before proceeding.
* **Self-Healing Prompt Optimizer** — If an agent hallucinates or violates a constraint, VORTEX-OS rewrites its own core instructions to ensure the failure mode is permanently eliminated.

---

## 100% IN-HOUSE, NATIVE EXECUTION

VORTEX-OS is designed for absolute internal autonomy:

* **Native MiniMax Media** — Triggers internal image generation, Hailuo video generation, and speech/foley generation natively. No external API keys required.
* **Local Audio Processing** — Delegates complex sound manipulation, sample chopping, and DSP effects to local ffmpeg and Python audio scripts within the sandbox. No external music sites.
* **Internal App Scaffolding** — Brainstorms, architects, and writes the code for complex digital environments (like VibeOS modules) meant to run entirely within the MiniMax ecosystem environment.

---

## USAGE

The skill ships a one-shot CLI (`skill.ps1`) that talks to the bundled
`Vortex.dll` engine. The engine is a **.NET 10 C++/CLI class library**
loaded by PowerShell 7+ via `Add-Type`. See `INSTRUCTIONS.md` for the
LLM-facing walkthrough.

> **Engine sources:** The C++/CLI source lives in the companion repo
> [Cloudmeru/vortex-os-dotnet](https://github.com/Cloudmeru/vortex-os-dotnet).
> A prebuilt `Vortex.dll` is bundled in this skill so the one-shot CLI
> works out of the box.

### One-shot CLI

```powershell
# Run a command
pwsh -NoProfile -File skill.ps1 --agents-discover
pwsh -NoProfile -File skill.ps1 --dispatch-master my_project\objective.md
pwsh -NoProfile -File skill.ps1 --hitl-approve package_websim

# Or dot-source the entry point in a persistent PS7+ session
. .\skill.ps1                       # not needed; just import the module:
Import-Module .\Vortex.psd1
Get-VortexAgent
Get-VortexHitlPending
Approve-VortexHitl -TaskId package_websim
Test-VortexPackage
```

### Install the engine from PowerShell Gallery (future, when published)

Once the VORTEX-OS .NET engine ships to PSGallery (target: a future
v0.2.x release), the skill can use the gallery module instead of the
bundled `Vortex.dll`. To switch:

```powershell
pwsh -NoProfile -File build.ps1 psgallery     # installs Vortex from PSGallery
Remove-Item .\Vortex.dll, .\Vortex.psm1, .\Vortex.psd1, .\ijwhost.dll
Import-Module Vortex                          # gallery module is picked up
```

### Build the engine from source

If you cloned this skill to patch the engine, rebuild `Vortex.dll` from
the upstream source:

```powershell
pwsh -NoProfile -File build.ps1
```

This downloads the C++/CLI source from `vortex-os-dotnet`, compiles it
with `cl /clr:netcore`, and copies the artifacts back next to the
skill's `skill.ps1`.

---

## TRIGGER CONDITIONS

**Use this skill when the user requests:**
- Building VibeOS modules, WebSims, interactive apps, narrative series
- Managing multi-stage workflows across writing, audio, code, and video domains using native MiniMax engines
- Automating multi-agent orchestration with universe-constrained creativity
- Native Hailuo video generation and MiniMax image generation pipelines
- Local ffmpeg audio processing, sample manipulation, and Foley synthesis
- Internal app scaffolding for the MiniMax ecosystem
- Long-running creative projects requiring continuity enforcement (lore universes, visual novels, games)
- Tasks requiring auditable decision-making with full audit trails
- High-stakes deployments that need Human-in-the-Loop approval
- Self-healing pipelines that recover from LLM drift
- Procedural media generation at factory scale, entirely in-house

**Do NOT use this skill for:**
- Simple one-line code questions
- Pure chat / Q&A tasks
- Single-file edits with no cross-domain coordination
- Read-only research questions

---

## THE 8 CONTRACT INVARIANTS

Every agent must satisfy:

- **I1 — Idempotence:** Re-running with identical input produces byte-identical output.
- **I2 — Resource Honesty:** Declared resources match actual consumption (±20%).
- **I3 — Write Containment:** Never writes outside its declared `writes[]`.
- **I4 — Read Containment:** Never reads outside its declared `reads[]`.
- **I5 — Sealed Envelope:** Output strictly conforms to the standard JSON schema.
- **I6 — Retry Honesty:** Never loops internally — orchestrator drives retries.
- **I7 — Secret Hygiene:** No secrets in logs; all secrets declared.
- **I8 — Metric Truthfulness:** Cost/token metrics are actual, not estimated.

---

## LICENSE

MIT

## AUTHOR

MiniMax Agent
