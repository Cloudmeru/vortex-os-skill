# INSTRUCTIONS — VORTEX-OS Operator's Knowledge Base

> **For LLMs and operators using VORTEX-OS**
> This is the complete operational contract: when to invoke it, how to invoke it, how to handle every event, how to recover from every error, and what the boundaries are.
>
> **Where this lives:** This file was moved from `INSTRUCTIONS.md` to `references/INSTRUCTIONS.md` in v0.1.2 to follow the Mavis/Claude skill convention: keep `SKILL.md` lean (always loaded on trigger) and move the deep operator playbook to `references/` (loaded on demand). The original 14-section structure is preserved; only the path changed. The skill's `_meta.json` `llm_instructions` field was updated to match.

---

## 0. TL;DR

```powershell
cd $env:USERPROFILE\.minimax\skills\VORTEX-OS
pwsh -NoProfile -File .\verify.ps1                   # confirm the package is ready
pwsh -NoProfile -File .\skill.ps1 --agents-discover  # what agents exist?
pwsh -NoProfile -File .\skill.ps1 --agents-lint --all # are they all healthy?
pwsh -NoProfile -File .\skill.ps1 --dispatch-master my_project\objective.md  # run a project
pwsh -NoProfile -File .\skill.ps1 --hitl-status      # what's waiting on me?
pwsh -NoProfile -File .\skill.ps1 --hitl-approve <task_id>  # greenlight it
pwsh -NoProfile -File .\skill.ps1 --audit-trail      # what just happened?

# Or, in a persistent PS7+ session (loads once, sticks around):
Import-Module Vortex
Get-VortexAgent
Get-VortexHitlPending
Approve-VortexHitl -TaskId package_websim
```

> **Engine acquisition:** The C++/CLI engine that powers these cmdlets
> lives in [Cloudmeru/vortex-os-dotnet](https://github.com/Cloudmeru/vortex-os-dotnet).
> The skill does **not** bundle the engine. The first time `skill.ps1`
> or `verify.ps1` runs, it downloads the 4 engine files
> (`Vortex.dll` + `Vortex.psm1` + `Vortex.psd1` + `ijwhost.dll`) from
> the public GitHub release of that repo and installs them to
> `$HOME\Documents\PowerShell\Modules\Vortex\<version>\` (user-scope,
> no admin needed). Re-runs are free. See §12 for full install details
> and §13 for building from source.
>
> **System dependencies:** The engine is pure .NET 10 / C++/CLI. It
> does **not** need Python, jq, or any scripting runtime. The only
> required system tool is `sqlite3` (used by `VectorHydrate` for memory
> persistence). `ffmpeg` is optional (used by *generated audio
> deliverables*, not the engine). Install via **`winget`** (Windows
> Package Manager) — never pip / brew / apt. Run
> `pwsh -NoProfile -File install-deps.ps1` (dry-run by default) or
> `install-deps.ps1 -Install` to actually install. See §12.5.

---

## 1. When To Invoke VORTEX-OS

### Invoke VORTEX-OS when the user requests:
- **A multi-disciplinary project** (writing + audio + code + research, all in one)
- **A long-running creative project** with universe canon (visual novel, game, series, worldbuilding)
- **An auditable autonomous pipeline** where every decision must be traceable
- **A high-stakes deployment** that requires human approval before finalization
- **A reproducible workflow** (they want to run the same kind of project again)
- **A procedurally-generated deliverable** (audio loop, dialogue, HTML page, Python script)

### Do NOT invoke VORTEX-OS when:
- The user asks a **simple one-line question**
- The user wants a **single-file edit** with no cross-domain coordination
- The user wants **read-only research** (use a web search instead)
- The user wants **pure chat / Q&A** (just answer directly)

---

## 2. The Invocation Pattern

The skill exposes `skill.ps1` as the primary entry point. Under the hood
it locates the Vortex PowerShell module (downloading + installing it on
first run) and `Add-Type`s the C++/CLI class library `Vortex.dll` into
PowerShell 7+'s existing .NET 10 CLR.

### Step 1 — Write the master objective to a file
```powershell
New-Item -ItemType Directory -Force -Path "$env:TEMP\vortex" | Out-Null
Set-Content -Path "$env:TEMP\vortex\objective.md" -Value @"
<the user's natural-language objective here>
"@
```

### Step 2 — Dispatch to VORTEX-OS
```powershell
pwsh -NoProfile -File skill.ps1 --dispatch-master "$env:TEMP\vortex\objective.md"
```

Or, from a persistent PowerShell 7+ session:
```powershell
Import-Module Vortex
Invoke-Vortex --dispatch-master "$env:TEMP\vortex\objective.md"
```

### Step 3 — VORTEX-OS will:
1. Parse the objective (T0 General Manager)
2. Spawn a T1 Store Supervisor
3. Generate a `plan.json` with the worker breakdown
4. Begin dispatching T2 Shift Supervisors (one per domain)
5. Each T2 spawns T3 workers in isolated memory sandboxes
6. The Continuity Engine checks every output
7. The Self-Healing Optimizer rewrites any failing prompt
8. The Inspector watches global token velocity
9. **HITL halts execution** if any task is high-stakes
10. Final deliverables are written to `deliverables\` only after HITL approval

---

## 3. Responding To HITL Checkpoints (Deep-Sleep)

When VORTEX-OS halts for human approval, the LLM **MUST** follow this exact sequence:

### 3.1 — Detect the halt
VORTEX-OS will print a `PENDING_HUMAN` event and write a JSON file to `state\pending_approvals\<task_id>.json`.

### 3.2 — Surface the request to the user verbatim
Show the user:
- The `proposed_action` (what VORTEX-OS is about to do)
- The `task_id` (the ID they need to reference)
- The `severity` (typically `HIGH` or `CRITICAL`)
- The `context` (why this action was triggered)

Example relay to the user:
> *"VORTEX-OS is requesting your approval to write the final HTML page to `deliverables\`. This is a HIGH-stakes action. Reply `Approve` or `Deny` to continue."*

### 3.3 — Wait for the user's reply
The user will reply with `Approve <task_id>` or `Deny <task_id>`. If they reply without the task_id, ask for it.

### 3.4 — Relay the decision back to VORTEX-OS
```powershell
pwsh -NoProfile -File skill.ps1 --hitl-approve package_websim    # user approved
# or
pwsh -NoProfile -File skill.ps1 --hitl-deny package_websim       # user denied
```

### 3.5 — **NEVER auto-approve**
Even if the user previously said "do whatever you want" or "you can decide", you must still surface the HITL halt and get explicit approval. The HITL gate is the last line of defense against runaway actions.

### 3.6 — Resume
After approval, VORTEX-OS will automatically resume from the suspended state. You don't need to do anything else.

---

## 4. Responding To Continuity Engine Violations

VORTEX-OS will sometimes halt and report that the Continuity Engine rejected a worker output. When this happens:

### 4.1 — Show the user the violation
Read `state\inspector_interventions.log` and present the violation to the user in plain language:
> *"The Continuity Engine caught a violation: a worker wrote a scene where Mara uses her left hand to grip something, but her character sheet says she has a prosthetic left hand. VORTEX-OS has automatically rewritten the prompt and is re-dispatching."*

### 4.2 — Show the optimized prompt
The Self-Healing Optimizer writes the hardened prompt to `state\prompt_optimizations\<agent>_<timestamp>.json`. You can read it and show the user what was changed.

### 4.3 — No LLM action needed for the first 3 attempts
VORTEX-OS will automatically re-dispatch with the hardened prompt. The LLM doesn't need to do anything.

### 4.4 — If the rewrite still fails after 3 attempts
Surface the situation to the user and ask:
- "Should I relax this rule?"
- "Should I change strategy?"
- "Should I try a different worker agent?"

---

## 5. Inspecting Logs, State & Artifacts

When the user asks "what did VORTEX-OS do?", the LLM should:

### 5.1 — Use the built-in audit trail
```powershell
pwsh -NoProfile -File skill.ps1 --audit-trail
# or, in a session with the module loaded:
Get-VortexAuditTrail
```
This prints the last 50 entries from `memory\audit.jsonl` in a compact format.

### 5.2 — Read the full audit JSONL
```powershell
Get-Content memory\audit.jsonl | ForEach-Object { $_ | ConvertFrom-Json | Select-Object ts,tier,agent,action,status,duration_ms | ConvertTo-Json -Compress }
```

### 5.3 — Read the Continuity Engine interventions
```powershell
Get-Content state\inspector_interventions.log
```

### 5.4 — Read the Self-Healing Optimizer rewrites
```powershell
Get-ChildItem state\prompt_optimizations\
Get-Content state\prompt_optimizations\writer.docs_*.json
```

### 5.5 — Read the native engine transcripts
```powershell
Get-Content state\minimax_music.log       # audio generation log
```

### 5.6 — List the generated deliverables
```powershell
Get-ChildItem deliverables\
```

### 5.7 — Per-swarm plan and outputs
```powershell
Get-ChildItem swarms\active_*\
Get-Content swarms\active_*\plan.json | ConvertFrom-Json
```

---

## 6. Saving & Reusing Workflows (Golden Path)

To re-run a previously successful workflow without burning planning tokens:

```powershell
# 1. Find a successful swarm
Get-ChildItem swarms\

# 2. Copy its plan.json as a template
Copy-Item swarms\active_<id>\plan.json templates\my_workflow.json

# 3. Replay it later (bypasses T0/T1 decomposition)
pwsh -NoProfile -File skill.ps1 --dispatch-template templates\my_workflow.json
```

---

## 7. Error Handling — Complete Reference

If VORTEX-OS returns a non-zero exit code, use this table to diagnose:

| Exit Code | Meaning | LLM Action |
|---|---|---|
| `0` | Success | Read the deliverables in `deliverables\`. Report results to the user. |
| `2` | Bad input / missing file | Ask the user for the missing file or correct the path. |
| `42` | Continuity violation unresolved after 3 rewrites | Show the violation log, ask the user to relax or revise the rules. |
| `100` | Invariant lint failure | Run `skill.ps1 --agents-lint --all` to see which agent failed which invariant. Show the user, suggest a fix. |
| `203` | HITL pending | Surface the request to the user (see Section 3). |
| `127` | Command not found | A system dependency is missing (typically `jq`, `sqlite3`, or `python3`). Tell the user to install it. |

---

## 8. Important Boundaries (Never Cross These)

The LLM operating VORTEX-OS **must never**:

1. **Never write to `deliverables\` directly** — only the HITL-approved packaging step may write there. The LLM's job is to invoke, not to package.
2. **Never modify `lib\` modules at runtime** — they are the immutable contract. If a worker needs a different prompt, use the Self-Healing Optimizer, not a hand edit.
3. **Never bypass the Continuity Engine** — even if the user asks for a "creative twist" that violates canon, surface the conflict first. The user can relax the rule, but you cannot silently bypass it.
4. **Never auto-approve HITL** — even if the user said "do whatever you want" earlier, you must still surface each individual halt.
5. **Never delete `memory/audit.jsonl`** — it is the system's black-box flight recorder. Append-only forever.
6. **Never run `--dispatch-master` and `--hitl-approve` in the same turn** — the HITL halt must be visible to the user, period.
7. **Never trust worker output without checking the audit log** — if a worker claims success, verify it via `memory/audit.jsonl` before reporting to the user.

---

## 9. The 4-Tier Mental Model (Always Remember)

When operating VORTEX-OS, keep this mental model in your head at all times:

| Tier | Role | What It Sees | What It Decides |
|---|---|---|---|
| **T0** | General Manager (Apex) | The user's master objective | Strategic decomposition, which domains to engage |
| **T1** | Store Supervisor | The master plan, the Golden Path | Which specialist swarm per domain, resource allocation |
| **T2** | Shift Supervisor | The per-domain task list | Worker assignment, Continuity Engine enforcement, HITL checkpoint |
| **T3** | The Crew | Their individual task | Generate the deliverable; never see anything outside their scope |

**The LLM is the Tier 0 General Manager / Human Liaison.** Your job is to:
1. Receive the user's master objective
2. Hand it to VORTEX-OS via `--dispatch-master`
3. Watch the audit log via `--audit-trail`
4. Relay HITL decisions between the user and VORTEX-OS
5. Explain the results to the user in natural language

The LLM should **not** re-implement any of VORTEX-OS's logic. It is the human-facing liaison.

---

## 10. Concrete Example Walkthrough

Here's a complete end-to-end example of how an LLM should drive VORTEX-OS for a real request.

### User says:
> *"Build a WebSim slice-of-life visual novel module for When Ocean Meets Sky — Mara is on her porch watching the tide come in. Make it feel like 1994."*

### LLM action:
1. **Write the master objective:**
   ```powershell
   New-Item -ItemType Directory -Force -Path "$env:TEMP\vortex\woms" | Out-Null
   @"
   # Project: When Ocean Meets Sky — Porch Scene

   Build a single WebSim scene: Mara on her porch, 1994, watching the tide.

   ## Required deliverables
   - 1 ambient audio loop (≈70 BPM, ocean + wind + distant gull)
   - 1 prose scene (250 words, present tense, 1st person)
   - 1 interactive HTML page with 2 choice buttons ("Stay" / "Go inside")

   ## Continuity rules
   - Mara is 19, has a prosthetic left hand
   - The porch is wood, faces west, salt-weathered
   - The radio inside plays only one station: a continuous weather report
   - Tone: quiet, melancholic, intimate
   - Era: 1994 (no smartphones, no internet references)

   ## High-stakes
   - package_websim: requires operator approval before writing the final HTML
   "@ | Set-Content -Path "$env:TEMP\vortex\woms\objective.md" -Encoding UTF8
   ```

2. **Dispatch:**
   ```powershell
   pwsh -NoProfile -File skill.ps1 --dispatch-master "$env:TEMP\vortex\woms\objective.md"
   ```

3. **VORTEX-OS runs autonomously for several minutes:**
   - T0 decomposes → 3 tasks (audio, prose, code)
   - T1 assigns specialist swarms
   - T2 dispatches workers
   - T3 generates; one violation triggers the Self-Healing Optimizer
   - HITL halts on `package_websim`

4. **VORTEX-OS prints:**
   ```
   >> PENDING_HUMAN: task_id=package_websim
   >> Proposed action: write deliverables/scene.html
   >> Severity: HIGH
   >> Context: final packaging step
   ```

5. **LLM surfaces to user:**
   > *"VORTEX-OS has finished generating the audio, prose, and code. It's now asking for your approval to write the final HTML page. The audio is at `deliverables\bedroom_loop_70bpm.wav`, the prose at `deliverables\scene.md`, and the code is ready. Shall I approve the final packaging?"*

6. **User says:** "Approve."

7. **LLM relays:**
   ```powershell
   pwsh -NoProfile -File skill.ps1 --hitl-approve package_websim
   ```

8. **VORTEX-OS finishes:**
   ```
   ✓ Approved: package_websim
   ✓ Wrote: deliverables/scene.html (3.2 KB)
   ```

9. **LLM reports to user:**
   > *"Done! Your WebSim scene is ready in `deliverables\`:
   > - `bedroom_loop_70bpm.wav` (705 KB ambient loop)
   > - `scene.md` (256 words of prose)
   > - `scene.html` (interactive page with Stay / Go inside buttons)
   >
   > Open `deliverables\scene.html` in a browser to play it."*

---

## 11. When To NOT Use VORTEX-OS (Boundaries)

The LLM should **decline** to invoke VORTEX-OS when:

- The user's request is a simple question (just answer)
- The user wants a one-line code change (use the regular code-edit tools)
- The user wants a quick chat (just chat)
- The request is read-only research (use web search)
- The request has no cross-domain coordination (use a single tool)
- The user's request is unclear or too vague (ask clarifying questions first)

When declining, explain to the user that VORTEX-OS is built for multi-disciplinary projects and that their request is better served by a simpler tool.

---

## 12. Engine Installation (download from GitHub release, user-scope)

The C++/CLI engine that powers VORTEX-OS is built and published at
[Cloudmeru/vortex-os-dotnet](https://github.com/Cloudmeru/vortex-os-dotnet).
The skill does **not** bundle the engine — it downloads the 4 engine
files (`Vortex.dll`, `Vortex.psm1`, `Vortex.psd1`, `ijwhost.dll`) from
the public release of that repo and installs them to a PowerShell
**user-scope** module folder. **No admin / system changes are required.**

### Default install flow (self-bootstrapping, zero config)

```powershell
cd path\to\vortex-os-skill
pwsh -NoProfile -File skill.ps1 --agents-discover
```

The first invocation:
1. Looks for a `Vortex\<version>\Vortex.psd1` in `$env:PSModulePath`,
   `$env:VORTEX_MODULE_PATH`, and the canonical
   `$HOME\Documents\PowerShell\Modules\Vortex`.
2. If none is found, runs `install.ps1` which:
   * Calls `GET https://api.github.com/repos/Cloudmeru/vortex-os-dotnet/releases/latest`
     (unauthenticated; GitHub allows 60 req/hr per IP).
   * Downloads `Vortex.dll`, `Vortex.psm1`, `Vortex.psd1`, `ijwhost.dll`
     from the release's `assets[].browser_download_url`.
   * Places them in the first writable user-scope module folder
     (canonical: `$HOME\Documents\PowerShell\Modules\Vortex\<version>\`).
3. Sets `$env:VORTEX_SKILL_ROOT` to the skill folder so the engine
   knows where `agents/`, `state/`, `memory/`, `deliverables/` live.
4. Imports the module and dispatches the command.

### Manual install / pin a specific engine version

```powershell
pwsh -NoProfile -File install.ps1                      # latest from GitHub
pwsh -NoProfile -File install.ps1 -Version v0.1.4      # pin a version
pwsh -NoProfile -File install.ps1 -ModulePath 'D:\psmodules'  # custom path
$env:VORTEX_VERSION = 'v0.1.4'; pwsh -NoProfile -File install.ps1
```

The install is **idempotent** — re-running it when the same engine
version is already present is a no-op. To upgrade, just re-run
`install.ps1`. To force a reinstall of the same version, delete the
folder first:

```powershell
Remove-Item -Recurse -Force "$HOME\Documents\PowerShell\Modules\Vortex\<version>"
pwsh -NoProfile -File install.ps1
```

### PowerShell Gallery (future)

When the `Vortex` module is published to PSGallery, you can use the
gallery version instead:

```powershell
Install-Module -Name Vortex -Scope CurrentUser -Force
```

The skill's `skill.ps1` / `verify.ps1` will prefer the user-scope
module (which PSGallery uses) over its own bundled engine. If the
user-scope module isn't found, it falls back to the GitHub-release
install.

### Override the install location

Set `$env:VORTEX_MODULE_PATH` to any directory you own. The skill
will look there first, then in `$env:PSModulePath`, then in the
canonical `$HOME\Documents\PowerShell\Modules`. This is useful for
shared dev environments or sandboxed CI runners.

### 12.6. Where is my data stored? (VORTEX_HOME)

Starting with **engine v0.1.7 + skill v0.1.4**, the engine splits
its storage into two roots. The skill folder is the "installer +
manifest" (gets replaced on update); `$env:VORTEX_HOME` is the
"user's work" (durable, user-scope, shared across skill instances).

| Location | Holds | Replaced on skill update? | Shared across instances? |
|---|---|---|---|
| **Skill folder** (where you cloned the skill) | `agents/`, `templates/`, scripts, docs, `_meta.json` | **Yes** | No |
| **`$env:VORTEX_HOME`** (default: `%APPDATA%\Vortex-OS\`) | `state/`, `memory/`, `swarms/`, `deliverables/`, `tasks/` | **No** | **Yes** |

**Why this matters for the LLM operating VORTEX-OS:**
- Your deliverables (the user's work) **never get wiped** when the
  skill is updated. A new skill release only replaces the
  scripts, the agent manifests, and the docs.
- Multiple code agents on the same machine (e.g. minimax code
  + hermes) share the same data because `$env:APPDATA%\Vortex-OS`
  is the same path for any process run by the same user.
- The audit log (`memory\audit.jsonl`) accumulates across skill
  updates AND across code agents — you get a single
  canonical history of all dispatches.

**Override the location** by setting `$env:VORTEX_HOME` to any
directory you own. The engine reads this env var on every call;
if unset, it defaults to `%APPDATA%\Vortex-OS`. Useful for
shared dev environments, sandboxed CI runners, or putting data
on a non-system drive.

**Concurrency note:** if you run VORTEX-OS from two code agents
simultaneously, both will write to the same `audit.jsonl` and
state files. Lines can interleave. If you need strict
single-writer semantics, set different `$env:VORTEX_HOME` for
each instance.

### 12.7. Migrating from an older skill version (v0.1.3 and below)

The engine v0.1.7 does **NOT** auto-migrate existing data from
the skill folder to `$env:VORTEX_HOME`. You run the skill's
`migrate-state.ps1` once to move the old data over. The script
is idempotent (skips subdirs that already exist at the target)
and supports `-WhatIf` for a dry-run.

```powershell
# 1. Dry-run: see what would be moved
pwsh -NoProfile -File .\migrate-state.ps1 -WhatIf

# 2. Actually move (leaves the source in place; you can delete it later)
pwsh -NoProfile -File .\migrate-state.ps1

# 3. After verifying the target, remove the originals from the skill folder
pwsh -NoProfile -File .\migrate-state.ps1 -DeleteSource
```

What gets moved (source: skill folder → target: `$env:VORTEX_HOME`):

| Source (skill folder) | Target (`$env:VORTEX_HOME`) |
|---|---|
| `<skill>/deliverables/` | `$env:VORTEX_HOME/deliverables/` |
| `<skill>/memory/` | `$env:VORTEX_HOME/memory/` |
| `<skill>/swarms/` | `$env:VORTEX_HOME/swarms/` |
| `<skill>/state/` | `$env:VORTEX_HOME/state/` |
| `<skill>/tasks/` | `$env:VORTEX_HOME/tasks/` |

What is NOT moved (per-skill, gets replaced on update by design):
`agents/`, `templates/`, the scripts, the docs, `_meta.json`.

### 12.5. System dependencies (one-time, per machine)

The engine is **pure .NET 10 / C++/CLI** — it does NOT need Python,
jq, or any scripting runtime. The single source of truth for the
engine's system dependencies is
[`_meta.json.winget_install_ids`](../../_meta.json). At the time of
writing, that list contains:

| Tool | winget ID | Required? | Used by |
|---|---|---|---|
| `sqlite3` | `SQLite.SQLite` | yes | Engine: `VectorHydrate` for memory persistence |
| `ffmpeg` | `Gyan.FFmpeg` | no | Generated audio deliverables (Foley, DSP, sample chopping) |

To install (or dry-run):

```powershell
# Dry-run: shows what's missing and the exact winget install commands
pwsh -NoProfile -File .\install-deps.ps1

# Install the required dep(s); y/N confirmation prompt before each run
pwsh -NoProfile -File .\install-deps.ps1 -Install

# Also install ffmpeg (for audio deliverables)
pwsh -NoProfile -File .\install-deps.ps1 -Install -IncludeOptional

# Skip the y/N prompt (script-driven use)
pwsh -NoProfile -File .\install-deps.ps1 -Install -Force
```

**CRITICAL for code agents:** when installing these, use
`winget install --id <winget_id>` — never pip, brew, apt, or choco.
`install-deps.ps1` is the canonical wrapper. The `_meta.json` field
`winget_install_ids` is the authoritative source.

If `sqlite3` is missing at runtime, the engine skips the memory
vector DB hydrate and writes a schema file at
`lib/vector_schema.sql` instead. The skill will still work — you
just lose the persistent memory feature. If `ffmpeg` is missing, the
engine will still run; only the generation of *audio deliverables*
will fail.

---

## 13. Engine Installation (from source, advanced / forkers only)

If you cloned this skill to fork it, or you need to run on a runtime
older than .NET 10, you can rebuild the engine from the upstream
C++/CLI source. The skill ships a helper:

```powershell
pwsh -NoProfile -File build.ps1                # download main.zip + build
pwsh -NoProfile -File build.ps1 -DotnetSrc 'C:\path\to\vortex-os-dotnet'
pwsh -NoProfile -File build.ps1 -Install        # build + install to user-scope
```

This downloads the source from
[Cloudmeru/vortex-os-dotnet](https://github.com/Cloudmeru/vortex-os-dotnet),
compiles it with MSVC v143 (`cl /clr:netcore /std:c++20`), and writes
the artifacts (`Vortex.dll` + `Vortex.psm1` + `Vortex.psd1` +
`ijwhost.dll`) into the skill root. To make your freshly built engine
active, copy the 4 files into the user-scope module folder yourself
(the install.ps1 script can do that — see `-Install` above).

If you have a local checkout of the .NET source repo, point the build
script at it:

```powershell
$env:VORTEX_DOTNET_SRC = 'C:\path\to\vortex-os-dotnet'
pwsh -NoProfile -File build.ps1
```

---

## 14. Summary — The LLM's Job

The LLM operating VORTEX-OS is the **Tier 0 General Manager / Human Liaison**. Your job is to:

1. **Receive** the user's master objective
2. **Clarify** if the request is vague
3. **Write** the objective to a file with proper structure
4. **Dispatch** via `--dispatch-master`
5. **Watch** for HITL halts and surface them to the user
6. **Watch** for Continuity Engine violations and explain them
7. **Relay** user decisions back to VORTEX-OS via `--hitl-approve` / `--hitl-deny`
8. **Report** final results to the user in natural language

**You are not a re-implementer of VORTEX-OS's logic. You are the human-facing liaison.**

---

## License

MIT

## Author

MiniMax Agent
