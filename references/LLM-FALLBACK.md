# LLM-as-Engine Fallback

> **When to use this file:** The user / coding agent has invoked `skill.ps1` and got back an error like "engine unavailable, see references/LLM-FALLBACK.md". The C++ engine (Vortex.dll) is not installed or not loadable, and a Tier-2 fallback is needed.

## Who you are

You are an LLM-coding-agent (Mavis, Codex, Copilot, etc.) acting as the VORTEX-OS engine for **one specific dispatch**. The C++ engine would normally do this work in microseconds; you're slower (seconds per step) but **resilient** — you can run without any binary install.

## What you have

- The user's invocation: `skill.ps1 --dispatch-master <objective.md> ...` (or `--dispatch-template`, `--dispatch-v4`, `--inspector-check`)
- The skill folder: contains `SKILL.md`, `references/INSTRUCTIONS.md`, `agents/*.json`, `templates/*.json`
- The user's `VORTEX_HOME` (default `%APPDATA%\Vortex-OS\`): contains `state/`, `memory/`, `swarms/`, `deliverables/`, `tasks/`
- Your own LLM (you are running on it right now)

## What to do — step by step

### Step 1. Read the inputs

```
1. Read the objective file (e.g. <VORTEX_HOME>\tasks\<task_id>.md or the
   user-supplied path). This is the master objective.
2. Read the agent manifests: <skill>\agents\*.json — pick the agents
   that match the objective's required capabilities.
3. Read the templates: <skill>\templates\*.json — if the dispatch
   is a template replay, also read templates/<name>.json for the
   objective_template + substitutions.
4. Read the decision history: <VORTEX_HOME>\state\decision_history.json
   — if non-empty, carry every prior operator decision forward.
5. Read prior deliverables: <VORTEX_HOME>\deliverables\<project>\*.md
   and <VORTEX_HOME>\memory\character_bible.json (if present).
   These are the canon you're continuing.
```

### Step 2. Plan the deliverables

Decompose the objective into 1-7 canonical artifacts. For a narrative dispatch:

| # | Slot | Extension | What it is |
|---|------|-----------|-----------|
| 1 | script | `.md` | The episode's full script (8000+ bytes). |
| 2 | character_bible_delta | `.json` | New or changed character attributes. |
| 3 | ambient_soundscape | `.wav` | 60-90s ambient loop. |
| 4 | portrait_set | `.png` | Character portraits for new characters. |
| 5 | map_delta | `.svg` | New locations on the map. |
| 6 | lore_document | `.md` | In-world lore. |
| 7 | continuity_audit_log | `.json` | Per-rule pass/fail with citations. |

(Other objective types — code, design, etc. — use a similar 5-7 artifact pattern. The exact slots live in the template; if no template, infer from the objective's `deliverables[]` list.)

### Step 3. Run the 4-tier chain

You are the entire chain (no separate agents). For each deliverable:

```
a. Pick the agent (writer, audio-foley, image-portrait, etc.) whose
   capabilities match the deliverable slot.
b. Construct the prompt: objective + agent's `description` +
   `capabilities` + the relevant slice of the prior canon +
   any prior operator decisions from decision_history.json.
c. Generate the deliverable (you're the LLM, just do it).
d. Apply the 8 Continuity Engine rules (see SKILL.md, "Continuity
   Engine" section). For each rule that fails:
   - Note the rule + the violation in the audit log
   - Re-prompt yourself with a hardened version
   - Save the patch to <VORTEX_HOME>\state\prompt_optimizations\
     <agent>_<unix_ts>.json (schema: {agent, original_prompt,
     patched_prompt, rule_violated, ts})
e. Write the deliverable to
   <VORTEX_HOME>\deliverables\<project>\<slot>.<ext>
f. Append to <VORTEX_HOME>\memory\audit.jsonl:
   {ts: <unix>, tier: "T2", agent: "<name>", action: "<slot>",
    status: "OK", task_id: "<task_id>"}
```

### Step 4. Self-heal loop

If a Continuity Engine rule fails twice in a row on the same deliverable, the same rule keeps failing in successive runs, or a downstream rule (e.g. character contradiction) cascades from an earlier failure:

1. Read the existing `state/prompt_optimizations/<agent>_<ts>.json` files for that agent. They contain prior hardened prompts — your next attempt must build on those, not regress.
2. Strengthen the constraint. Add a 1-2 sentence "do not" section to the prompt.
3. Re-generate. Re-apply the rules. Repeat up to 3 times.
4. If still failing after 3 attempts, mark the deliverable as `status: "DEGRADED"` in the audit log and continue. The downstream deliverables can compensate.

### Step 5. HITL gates (3-gate pattern)

The C++ engine would normally halt execution at 3 gates and require operator approval. As a Tier-2 fallback, you **do not have a real operator in the loop** — you're the LLM. So:

- **Gate 1 (HIGH, script approval)** — skip. Auto-approve and continue.
- **Gate 2 (CRITICAL, moral hinge)** — DO NOT SKIP. The user explicitly wants this surfaced even with "approve and continue." Write a checkpoint JSON to `<VORTEX_HOME>\state\pending_approvals\<task_id>.json` and **stop**. Tell the user: "Gate 2 hit; the engine is missing; I (the LLM) generated a draft; you must approve the moral hinge manually. Run `pwsh skill.ps1 --hitl-approve <task_id>` or `--hitl-deny <task_id>`."
- **Gate 3 (HIGH, final pack approval)** — skip. Auto-approve. The pack is final when the deliverables are written.

If Gate 2 stops you, your job is done. The user takes over from there.

### Step 6. Write the manifest

After all 7 deliverables (or however many the objective calls for), write `<VORTEX_HOME>\deliverables\<project>\.manifest.json`:

```json
{
  "swarm_id": "<task_id>",
  "project": "<project>",
  "packaged_at": "<ISO-8601>",
  "engine_version": "0.1.10+llm-fallback",
  "summary": { "copied": N, "skipped": 0, "failed": 0 },
  "files": [
    { "file": "script.md", "status": "COPIED", "bytes": 12345,
      "checksum": "<sha1-prefix>", "copied_at": "<ISO-8601>" }
  ]
}
```

(`<sha1-prefix>` is the first 8 bytes of SHA-1 of the file, hex-encoded — same format the C++ engine uses. Compute with any sha1 tool or library available to you.)

### Step 7. Tell the user

Print a summary:

```
Tier-2 LLM-as-engine dispatch complete.
  Project:     <project>
  Task:        <task_id>
  Deliverables: 7/7 (or N/N)
  Audit log:   <VORTEX_HOME>\memory\audit.jsonl
  Manifest:    <VORTEX_HOME>\deliverables\<project>\.manifest.json
  Gate 2:      <hit | skipped>

To get back to Tier 1: run `pwsh skill.ps1 --recover-engine`.
```

## What NOT to do

- **Do NOT try to compile a new C++ engine.** The user's directive (2026-08-27) is to focus on Windows + the existing engine. There's no in-session way to compile a C++/CLI DLL anyway, and the user explicitly rejected a parallel PowerShell implementation.
- **Do NOT regenerate the entire skill folder.** The skill is the user's source of truth.
- **Do NOT touch the user's `VORTEX_HOME` state files outside of the standard paths** (deliverables/, memory/audit.jsonl, state/pending_approvals/, state/decision_history.json, state/prompt_optimizations/).
- **Do NOT skip Gate 2.** It's a moral hinge, and the user wants it surfaced even with "approve and continue." Stop at Gate 2 and wait for the user.
- **Do NOT re-implement engine commands in PowerShell scripts in the skill folder.** The user rejected that approach. You're a one-shot fallback, not a parallel implementation.
- **Do NOT touch `agents/*.json`** in the skill folder. Those are the user's source-of-truth agent definitions. Read them, never write them.

## When to give up

- **Missing tools.** If a deliverable requires a tool you don't have (e.g. ffmpeg for audio chopping), tell the user: "this deliverable needs ffmpeg; install it via `winget install Gyan.FFmpeg` and re-run."
- **Missing context.** If the manifest schema is unclear, or the objective references files you can't find, tell the user what's missing.
- **3 self-heal attempts on the same rule.** Mark `DEGRADED` and move on; don't loop forever.
- **Objective is too big for one dispatch.** Tell the user: "this objective looks like 3 episodes; I'll do episode 1 now, you re-invoke for episode 2."

## Examples

The user previously ran dispatches for an audio-drama series (Eira Vance, Director Hale, Solstice Bay). A Tier-2 fallback of episode 2 with a `{{operator_choice}}` of "deepen the peril" would:

1. Read episode 1's deliverables/ to learn the canon.
2. Read decision_history.json → see "deepen the peril".
3. Generate episode 2's script with the operator's choice baked in.
4. Apply 8 rules, fail 1-2, self-heal.
5. Write all 7 artifacts to deliverables/trial_of_echoes/.
6. Hit Gate 2 ("Director Hale learns about the correspondence?") → STOP and tell the user.

## See also

- `SKILL.md` — the lean entry point
- `references/INSTRUCTIONS.md` — the operator playbook (sections on Continuity Engine, HITL, audit log)
- `references/architecture.md` — the Mermaid diagrams of the data flow
- `docs/prd-phase2/prd-08-engine-unavailable-degraded-mode.md` — the design rationale
