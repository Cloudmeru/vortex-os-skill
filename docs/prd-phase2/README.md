# Phase 2 PRDs

Six PRDs for VORTEX-OS phase 2 (the "capability phase" from `idea-future-recommendations.md`). Read in order — each PRD depends on the previous ones.

**Scope (revised 2026-08-27): Windows only.** Cross-platform support (item 8 options A/B/C) is deferred to v2.x per user direction.

## Reading order

| # | PRD | Status | Depends on | User said |
|---|-----|--------|------------|-----------|
| 1 | [PRD-08: Engine Unavailable — 3-Tier Fallback](prd-08-engine-unavailable-degraded-mode.md) | Draft | — | "explain if engine is unavailable can it still survive" — PRD revised 2026-08-27 to add Tier 3 (LLM-as-engine fallback) per user insight |
| 2 | [PRD-10: Multi-User / Shared VORTEX_HOME](prd-10-shared-vortex-home.md) | Draft | — | "ok this is a good approach" — agree |
| 3 | [PRD-11: Engine Plugin System](prd-11-plugin-system.md) | Draft | PRD-08 | "ok agree, suggest plugins, make prd first" |
| 4 | [PRD-12: Cost / Token Budgeting](prd-12-cost-token-budgeting.md) | Draft | — | "ok i agree" |
| 5 | [PRD-13: Audit Log Viewer](prd-13-audit-log-viewer.md) | Draft | PRD-08 | (numbered for phase 2) |
| 6 | [PRD-14: Streaming / Partial Results](prd-14-streaming-partial-results.md) | Draft | PRD-08, PRD-11 | (numbered for phase 2) |

## High-level picture

```
                        ┌─────────────────────────────┐
                        │ Tier 1: PowerShell shell     │
                        │ (always present, ~600 LoC)   │
                        │ 14 commands: --version,      │
                        │ --help, --health, --agents-*,│
                        │ --audit-trail, --hitl-*,     │
                        │ --decision-*, --package      │
                        │ Window-only, no install      │
                        └────────────┬────────────────┘
                                     │
                                     │ if Vortex.dll loads:
                                     ▼
                        ┌─────────────────────────────┐
                        │ Tier 2: C++/CLI engine       │
                        │ (Vortex.dll, 84 KB, v0.1.9)  │
                        │ 4-tier dispatch, Continuity  │
                        │ Engine, self-heal, SHA-1     │
                        │ WINDOWS ONLY                 │
                        └────────────┬────────────────┘
                                     │
                                     │ if engine unavailable
                                     │ AND in an LLM-coding-
                                     │ agent context (Mavis,
                                     │ Codex, Copilot):
                                     ▼
                        ┌─────────────────────────────┐
                        │ Tier 3: LLM-as-engine        │
                        │ (documented recipe only,     │
                        │  no code)                    │
                        │ The LLM reads SKILL.md,       │
                        │ agent manifests, templates,  │
                        │ decision history; drives the │
                        │ dispatch in-place            │
                        │ Slow but RESILIENT            │
                        └─────────────────────────────┘
```

## Implementation order (recommended)

If you approve all 6 PRDs, this is the suggested implementation order:

1. **PRD-08 (degraded mode)** — skill-side only, ~2-3 days, no engine changes. Unblocks the rest. *Highest priority because it's the foundation.*
2. **PRD-12 (cost tracking)** — engine + skill, ~5-7 days. Self-contained; doesn't depend on plugins.
3. **PRD-13 (audit viewer)** — engine + skill, ~1 week. Reads the richer audit log that PRD-12 writes.
4. **PRD-11 (plugin system)** — engine + skill, ~2-3 weeks. The biggest change. *Do this when you have a few weeks to focus on it.*
5. **PRD-14 (streaming)** — engine + skill, ~1 week. Builds on the plugin system.
6. **PRD-10 (shared VORTEX_HOME)** — engine + skill, ~4-5 days. Last because it's a team-scaling feature, not a per-user one.

**Total: ~2 months for one engineer, end-to-end. ~5K LoC of changes.**

## Tag plan

- v0.1.10 — PRD-08 + PRD-12 (engine + skill)
- v0.1.11 — PRD-13 (engine + skill)
- v0.2.0 — PRD-11 (engine + skill) — major architectural change
- v0.2.1 — PRD-14 (engine + skill)
- v0.2.2 — PRD-10 (engine + skill)

## Open architectural questions (to resolve before implementation)

These are cross-cutting questions that affect all 6 PRDs. Resolve them in `idea-future-recommendations.md` Q1–Q5 (or new Q6–Q10):

- **Q1 (new).** Is the PowerShell shell the source of truth for routing, with the engine as a loadable add-on? — *Yes (PRD-08 establishes this).*
- **Q2 (new).** Are plugins first-class, or are they an escape hatch? — *First-class (PRD-11). The engine has no hard-coded workers.*
- **Q3 (new).** Is the audit log a stream (one event per row) or a structured log (relations)? — *Stream (JSONL, one event per row). The viewer (PRD-13) re-constructs the relations on read.*
- **Q4 (new).** Is the cost log separate from the audit log or part of it? — *Separate (`state/cost_log.jsonl`). The audit log is the orchestration record; the cost log is the financial record. They share `task_id` for joining.*
- **Q5 (new).** Is the streaming view per-task or per-dispatch? — *Per-dispatch. A single dispatch = one T0→T1→T2→T3 tree = one stream.*

## What this phase does NOT do

- **No cloud / hosted service.** VORTEX-OS stays a local file-system tool.
- **No LLM provider lock-in.** Plugins can wrap any LLM; the engine doesn't care.
- **No web UI.** HTML output files are local; opening them in a browser is the closest thing.
- **No real-time LLM token streaming.** That's a separate feature.
- **No cross-machine dispatch.** Use shared VORTEX_HOME + manual coordination.
- **No SaaS billing / metering.** Cost log is the source of truth; user exports to their accounting system.
- **No Linux / macOS support** (Windows only, per user direction 2026-08-27). The cross-platform options A/B/C in `idea-future-recommendations.md` item 8 are explicitly deferred to v2.x.

## How to use this folder

1. Read PRD-08 first. It establishes the architecture for the rest.
2. Read each PRD's "Design" + "API surface" + "Acceptance criteria" sections. The "Open questions" are blockers — answer them before implementation.
3. Update each PRD's "Status" to "Approved" or "Rejected" as you decide.
4. After approval, the PRD becomes the implementation plan. Create a worktree per PRD, follow the acceptance criteria, and link the PR back to the PRD file.
