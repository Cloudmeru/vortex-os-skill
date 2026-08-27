# PRD-13 — Audit Log Viewer

**Status:** Draft · Phase 2
**Owner:** VORTEX-OS maintainers
**Source:** `idea-future-recommendations.md` item 13

---

## 1. Context

`memory/audit.jsonl` is a JSONL file. Each line is a single event:

```json
{"ts": 1700000000, "tier": "T1", "agent": "supervisor.store", "action": "decompose", "status": "OK", ...}
{"ts": 1700000001, "tier": "T2", "agent": "shift.qa", "action": "continuity_check", "status": "FAIL: tone_drift", ...}
{"ts": 1700000002, "tier": "T2", "agent": "shift.qa", "action": "self_heal", "status": "OK", "rule_violated": "tone_drift", "prompt_patch": "..."}
{"ts": 1700000003, "tier": "T3", "agent": "writer.shift", "action": "draft", "status": "OK", "tokens_out": 1823}
```

Reading this directly with `Get-Content` is fine for a single dispatch, but multi-dispatch analysis is painful. An operator trying to understand "what happened on the trial_of_echoes project last Tuesday" has to:

1. Read the whole file
2. Filter by `project` (not currently recorded!)
3. Filter by date / time
4. Identify the T0→T1→T2→T3 chain for each task
5. Find the self-heal cycles (rule violated → rule fixed)
6. Find the HITL gate interactions

The recommendation: a `Get-VortexAuditTrail` PowerShell cmdlet that filters, renders as a tree, and highlights interesting events.

## 2. Goals

1. **Filter by any combination of:** project, time range, agent, severity, task_id, status, action.
2. **Tree view** of the T0→T1→T2→T3 chain for a single task — makes the orchestration visible.
3. **Self-heal highlighting** — group `rule_violated` events with the subsequent `rule_fixed` events and show the prompt patch.
4. **HITL highlighting** — show all `pending_approval` events and their resolutions.
5. **Multiple output formats** — text table (default), JSON, HTML.
6. **Backward-compatible** — the existing `--audit-trail` flag still works as the "last 50 events" view; `Get-VortexAuditTrail` is the new rich cmdlet.

## 3. Non-goals

- **A web UI.** The HTML output is a self-contained file the user can open in a browser; not a live dashboard.
- **Real-time streaming.** `--audit-trail` reads the current state. Streaming is PRD-14.
- **Cross-`VORTEX_HOME` queries.** The viewer reads one `audit.jsonl` (or the per-user file from PRD-10).
- **A SQL backend.** The viewer is PowerShell + `ConvertFrom-Json`. The audit log stays JSONL.

## 4. Design

### 4.1 Schema additions to the audit log

The current audit log doesn't record `project` or `episode_number`. The engine's writers (DispatchV4, Inspector, etc.) need to add these fields. This is a small backward-compatible change — old log lines still parse, new ones have more fields.

New fields per event (all optional, all backward-compatible):

| Field | Type | When |
|---|---|---|
| `project` | string | Always (from `p->ProjectName`) |
| `episode_number` | int | When `p->ProjectName` matches a series template (e.g. `trial_of_echoes_ep2` → 2) |
| `task_id` | string | When the event is task-scoped (most are) |
| `severity` | string | "INFO" / "WARN" / "ERROR" / "CRITICAL" |
| `rule_violated` | string | Inspector FAIL events |
| `rule_fixed` | string | Self-heal success events |
| `gate_id` | string | HITL events (e.g. "gate2_moral_hinge") |
| `tags` | string[] | Free-form (e.g. `["episode-1", "script"]`) |

### 4.2 The new cmdlet

`Get-VortexAuditTrail` is added to `Vortex.psm1`:

```powershell
function Get-VortexAuditTrail {
    [CmdletBinding()]
    param(
        [string] $Project,
        [string] $Task,
        [string] $Agent,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'CRITICAL')]
        [string] $Severity,
        [datetime] $Since,
        [datetime] $Until,
        [int] $Last = 50,
        [ValidateSet('table', 'tree', 'json', 'html')]
        [string] $As = 'table',
        [switch] $SelfHealOnly,
        [switch] $HitlOnly
    )
    # ... read $VORTEX_HOME\memory\audit.jsonl, filter, render ...
}
```

### 4.3 The tree view

For a single task, the tree shows the T0→T1→T2→T3 chain:

```
Task: ep2_writer (project: trial_of_echoes, episode 2)
Started: 2026-08-25 14:32:01, Duration: 4m 23s
Status:  OK

T0 General Manager
  └─ T1 supervisor.store
       ├─ T2 shift.tactical
       │    ├─ T3 writer.shift            [OK]   1823 tokens,  4.5s
       │    ├─ Continuity Engine          [OK]   8/8 rules passed
       │    └─ HITL gate 1 (HIGH)         [OK]   operator approved
       └─ T2 shift.audio
            └─ T3 audio-foley             [OK]   3 files, 12.4s

Self-heal cycles:  0
HITL gates:        1 (gate 1: approved)
Total cost (USD):  $0.18
```

### 4.4 Self-heal highlight view

`Get-VortexAuditTrail -SelfHealOnly`:

```
Self-heal cycles in trial_of_echoes
===================================

[1] 2026-08-25 14:32:15  Continuity Engine
    Rule violated:  tone_drift
    Worker:         writer.shift
    Dispatch:       ep1_draft
    Patch applied:  tightened tone instructions, added 3 exemplar paragraphs
    Re-dispatch:    ep1_draft_retry
    Result:         PASS (8/8 rules)
    Tokens spent:   1,420 (patch) + 1,823 (re-draft)

[2] 2026-08-25 15:01:33  Continuity Engine
    Rule violated:  character_contradiction
    Worker:         writer.shift
    Dispatch:       ep2_draft
    Patch applied:  re-stated the prior episode's character traits verbatim
    Re-dispatch:    ep2_draft_retry
    Result:         PASS (8/8 rules)
    Tokens spent:   980 (patch) + 2,103 (re-draft)

Total: 2 self-heal cycles, 6,326 tokens spent on retries
```

### 4.5 HITL view

`Get-VortexAuditTrail -HitlOnly`:

```
HITL gate interactions in trial_of_echoes
=========================================

[gate_1_script]    Severity: HIGH      Status: APPROVED
  Asked:      2026-08-25 14:35:01  "Approve the script for media generation?"
  Approved:   2026-08-25 14:38:42  (3m 41s wait)
  Operator:   "approve and continue"

[gate_2_moral_hinge]   Severity: CRITICAL   Status: APPROVED
  Asked:      2026-08-25 14:42:01  "Deepen the peril: should Director Hale learn about the correspondence?"
  Approved:   2026-08-25 14:50:11  (8m 10s wait)
  Operator:   "deepen the peril"
  Recorded to: state/decision_history.json  (entry #3)

[gate_3_final]     Severity: HIGH      Status: APPROVED
  Asked:      2026-08-25 14:55:33  "Approve the final pack for delivery?"
  Approved:   2026-08-25 14:55:51  (18s wait)
  Operator:   "approve"
```

### 4.6 HTML output

A self-contained HTML file with embedded CSS, a sortable table, and a Mermaid.js flowchart of the tree. ~50 KB max, no external dependencies.

## 5. API surface

### New cmdlet (skill-side, exported from Vortex.psm1)

```powershell
# Module import
Import-Module Vortex
Get-Command Get-VortexAuditTrail | Format-List

# All events for a project
Get-VortexAuditTrail -Project trial_of_echoes

# Last 24 hours, all projects
Get-VortexAuditTrail -Since (Get-Date).AddDays(-1)

# Self-heal cycles only
Get-VortexAuditTrail -Project trial_of_echoes -SelfHealOnly

# HITL gate interactions only
Get-VortexAuditTrail -Project trial_of_echoes -HitlOnly

# Tree view of a single task
Get-VortexAuditTrail -Task ep2_writer -As tree

# JSON output for piping
Get-VortexAuditTrail -Project trial_of_echoes -As json | ConvertFrom-Json | Where-Object severity -eq CRITICAL

# HTML report
Get-VortexAuditTrail -Project trial_of_echoes -As html -Last 200 | Out-File audit.html
Start-Process audit.html
```

### New flag on skill.ps1 (thin alias)

```powershell
# Same as Get-VortexAuditTrail -As table -Last 50
pwsh -NoProfile -File .\skill.ps1 --audit-trail

# New: filter
pwsh -NoProfile -File .\skill.ps1 --audit-trail --project trial_of_echoes --since 7d
pwsh -NoProfile -File .\skill.ps1 --audit-trail --task ep2_writer --as tree
pwsh -NoProfile -File .\skill.ps1 --audit-trail --self-heal-only
pwsh -NoProfile -File .\skill.ps1 --audit-trail --hitl-only
```

## 6. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Reading the entire audit log is slow for years-long projects | Medium | Low | The log rotates at 100 MB (PRD-12). The viewer reads the current + last rotation by default. The `-AllLogs` flag reads everything but is rare. |
| The tree view doesn't render well for deeply-nested dispatches (rare but possible) | Low | Low | Truncate at depth 5 with a `+ N more events` note. |
| Backward incompatibility — old audit lines don't have `project` / `episode_number` | High | Low | All new fields are optional. The viewer treats `null` / missing as "unknown" and shows a `—` placeholder. |
| Users abuse the HTML output to leak data (e.g. a customer name in a HITL message) | Low | Low | The HTML output is a local file; the user controls where it goes. No new leak surface. |
| Filtering by `since` is ambiguous (UTC vs local) | Medium | Low | The cmdlet treats `-Since` and `-Until` as local time and converts to UTC for comparison. The output timestamps are local. |

## 7. Acceptance criteria

1. `Get-VortexAuditTrail -Project <name>` returns events filtered to that project, sorted by `ts` ascending.
2. `Get-VortexAuditTrail -Task <id> -As tree` shows the T0→T1→T2→T3 chain with self-heal and HITL annotations.
3. `Get-VortexAuditTrail -SelfHealOnly` shows only events where `rule_violated` or `rule_fixed` is set, grouped by cycle.
4. `Get-VortexAuditTrail -HitlOnly` shows only events where `gate_id` is set, with the ask / approval / operator / wait time.
5. `Get-VortexAuditTrail -As json` emits valid JSON that round-trips through `ConvertFrom-Json` and back.
6. `Get-VortexAuditTrail -As html` produces a self-contained file that opens in a browser with no external dependencies.
7. `--audit-trail --project <name> --since 7d --self-heal-only` (the skill.ps1 flag form) returns the same data as the cmdlet.
8. `verify.ps1` adds a `tests/test_audit_viewer.ps1` that generates a synthetic audit log, runs the cmdlet, and asserts the output.

## 8. Effort

- `engine/skill.cpp` + `lib/Inspector.cpp` + `lib/DispatchV4.cpp` (add 8 new fields to the audit events): ~50 lines
- `skill/skill.ps1` (new flags on `--audit-trail`): ~150 lines
- New `skill/Vortex.AuditViewer.psm1` (the cmdlet + 3 view formatters): ~500 lines
- HTML output template: ~200 lines of PowerShell that emits the HTML
- New tests: ~250 lines
- Docs: `references/INSTRUCTIONS.md` updated, new `references/audit-viewer.md`

**Total: ~1150 lines. 2 PRs (engine + skill). Tag bump to 0.1.10. ~1 week for a single engineer.**

## 9. Open questions

- **Q1.** Should the HTML output be a single file or split per-task? — *Recommend: single file with a task navigator.*
- **Q2.** Should the tree view include cost data (from PRD-12)? — *Recommend: yes, but only if the cost log exists. Otherwise show "—".*
- **Q3.** Should the viewer be able to detect "anomalies" (e.g. a task with 10 self-heal cycles in a row)? — *Recommend: no for v1. The viewer is read-only; anomaly detection is a follow-up.*
- **Q4.** Should the viewer integrate with the plugin system (PRD-11) so a "self-heal explainer" plugin can render a richer view? — *Recommend: no, the viewer is generic. Custom visualizations can be built on top of the JSON output.*
- **Q5.** Should `Get-VortexAuditTrail` work without the engine (degraded mode, PRD-08)? — *Recommend: yes, fully PowerShell.*
