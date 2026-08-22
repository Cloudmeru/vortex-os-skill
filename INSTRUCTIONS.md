# INSTRUCTIONS — VORTEX-OS Operator's Knowledge Base

> **For LLMs and operators using VORTEX-OS**
> This is the complete operational contract: when to invoke it, how to invoke it, how to handle every event, how to recover from every error, and what the boundaries are.

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
Import-Module .\Vortex.psd1
Get-VortexAgent
Get-VortexHitlPending
Approve-VortexHitl -TaskId package_websim
```

> **Engine sources:** The C++/CLI engine that powers these cmdlets lives in
> [Cloudmeru/vortex-os-dotnet](https://github.com/Cloudmeru/vortex-os-dotnet).
> The skill bundles a prebuilt `Vortex.dll` so the one-shot CLI works
> out of the box. See §12 for the PSGallery install path and §13 for
> building from source.

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
it loads `Vortex.psm1` which `Add-Type`s the C++/CLI class library
`Vortex.dll` into PowerShell 7+'s existing .NET 10 CLR.

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

Or, from a persistent PS7+ session:
```powershell
Import-Module .\Vortex.psd1
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

## 12. Engine Installation (PSGallery, future)

The C++/CLI engine that powers VORTEX-OS will eventually be published to
the PowerShell Gallery as the `Vortex` module. Once published, you can
opt to use the gallery version instead of the bundled binaries:

```powershell
# Install the engine from PSGallery (PowerShell 7+ Core required)
Install-Module -Name Vortex -Scope CurrentUser

# Remove the bundled engine so the skill picks up the gallery one
Remove-Item .\Vortex.dll, .\Vortex.psm1, .\Vortex.psd1, .\ijwhost.dll
```

Or, more conveniently, use the helper:

```powershell
pwsh -NoProfile -File build.ps1 psgallery
```

The `psgallery` subcommand runs `Install-Module Vortex` for you, then
prints instructions for removing the bundled binaries.

---

## 13. Engine Installation (from source)

If you cloned this skill to fork it, or you need to run on a runtime
older than .NET 10, you can rebuild the engine from the upstream
C++/CLI source. The skill ships a helper:

```powershell
pwsh -NoProfile -File build.ps1
```

This downloads the source from
[Cloudmeru/vortex-os-dotnet](https://github.com/Cloudmeru/vortex-os-dotnet),
compiles it with MSVC v143 (`cl /clr:netcore /std:c++20`), and copies
the artifacts back next to the skill.

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
