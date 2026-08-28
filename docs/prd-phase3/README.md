# Phase 3 PRDs

VORTEX-OS phase 3 (the "memory phase" from `idea-future-recommendations.md`). Phase 3 is where the engine stops treating each project as a blank slate and starts learning from prior work.

**Scope:** Windows only, builds on phase 2.

**Prerequisite:** all 6 phase-2 PRDs (`docs/prd-phase2/`) must be implemented first. Phase 3 reads from the audit log (PRD-13), the cost log (PRD-12), the per-project manifests (PRD-08), and the per-user team shards (PRD-10). Building phase 3 before phase 2 is implementing fan-fiction about future data.

## Reading order

| # | PRD | Status | Depends on | User said |
|---|-----|--------|------------|-----------|
| 1 | [PRD-17: Cross-Project Memory & Lore](prd-17-cross-project-memory-lore.md) | Draft | PRD-08, PRD-12, PRD-13 | "built a prd for option 17 as phase 3" (2026-08-28) |

## High-level picture

```
                          ┌──────────────────────────────┐
                          │  Phase 2 deliverables (done) │
                          │  - audit.jsonl  (PRD-13)     │
                          │  - cost_log.jsonl (PRD-12)   │
                          │  - project _meta.json        │
                          │  - per-user shards (PRD-10)  │
                          └────────────┬─────────────────┘
                                       │
                                       │ raw event stream
                                       ▼
                          ┌──────────────────────────────┐
                          │  --compile-lore (new in 17)  │
                          │  background re-derivation    │
                          │  reads audit + cost + meta   │
                          │  writes memory/lore/*.json   │
                          └────────────┬─────────────────┘
                                       │
                                       │ derived artifacts
                                       ▼
                          ┌──────────────────────────────┐
                          │  $VORTEX_HOME/memory/lore/   │
                          │  - project/<slug>.json       │  "characters + plot + style"
                          │  - calibration.json          │  "word count tend 18% over"
                          │  - series/<series>.json      │  "ep1/2/3 progression"
                          └────────────┬─────────────────┘
                                       │
                                       │ injected as "operator notes"
                                       ▼
                          ┌──────────────────────────────┐
                          │  --with-lore on dispatch     │
                          │  next dispatch prompt sees:  │
                          │  "in your last 3 projects on  │
                          │   this archetype, you used   │
                          │   18% over the word budget.  │
                          │   here's a calibration."    │
                          └──────────────────────────────┘
```

## Implementation order (recommended)

1. **PRD-17 (cross-project memory & lore)** — engine + skill, ~1 quarter. The doc estimates "~1 quarter, genuinely hard problem" so plan around that. Builds on top of phase 2's data sources; no new event streams are introduced.

## What this phase does NOT do

- **No embeddings / vector search across projects.** The audit log + cost log are the raw data. A future PRD (post-phase 3) could add semantic search across projects via the vector store (PRD-14's hydrate step already writes `memory/vectors.json`).
- **No LLM-generated summaries.** Lore is derived (statistical + structured) not summarized. "I worked on character X last week" is a pointer, not a prose summary.
- **No cross-`VORTEX_HOME` lore.** Per-machine. A future PRD could add export/import for transferring lore between machines.
- **No SaaS / cloud lore sync.** Local file system only, same as the rest of VORTEX-OS.
- **No automatic prompt rewriting.** Lore is INJECTED into the prompt as operator notes; the engine's self-heal loop is the only thing that can rewrite prompts.

## How to use this folder

1. Read PRD-17 end-to-end. The "Design" section is the meat.
2. Resolve each "Open question" before implementation. The answers affect the file schemas in `memory/lore/`.
3. The acceptance criteria are the v0.3.x release checklist.
