# Phase 3 PRDs

VORTEX-OS phase 3 (the "memory phase" from `idea-future-recommendations.md`). Phase 3 is where the engine stops treating each project as a blank slate and starts learning from prior work across all domains (code, video, audio, image, research, design, narrative).

**Scope:** Windows only, builds on phase 2.

**Prerequisite:** all 6 phase-2 PRDs (`docs/prd-phase2/`) must be implemented first. Phase 3 reads from the audit log (PRD-13), the cost log (PRD-12), the per-project manifests (PRD-08), and the per-user team shards (PRD-10). Building phase 3 before phase 2 is implementing fan-fiction about future data.

## Reading order

| # | PRD | Status | Depends on | Notes |
|---|-----|--------|------------|-------|
| 1 | [PRD-17: Cross-Project Memory & Knowledge](prd-17-cross-project-memory.md) | Draft | PRD-08, PRD-12, PRD-13 | Revised 2026-08-28 — renamed from "memory & lore" to "memory & knowledge" to make the framing universal (code/video/audio/research), not just narrative. Folder renamed from `memory/lore/` to `memory/derived/`. CLI flags renamed from `--compile-lore` / `--with-lore` to `--compile-memory` / `--with-memory`. Cmdlet renamed from `Get-VortexLore` to `Get-VortexMemory`. |

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
                          │  --compile-memory (new in 17)│
                          │  background re-derivation    │
                          │  reads audit + cost + meta   │
                          │  writes memory/derived/*.json│
                          └────────────┬─────────────────┘
                                       │
                                       │ derived artifacts
                                       ▼
                          ┌──────────────────────────────┐
                          │  $VORTEX_HOME/memory/derived/ │
                          │  - project/<slug>.json       │  "plugin mix + common components + notable self-heals"
                          │  - operator.json             │  "per-plugin cost + failure modes + cadence"
                          │  - series/<series>.json      │  "iteration progression + dependency drift"
                          └────────────┬─────────────────┘
                                       │
                                       │ injected as "Prior projects context"
                                       ▼
                          ┌──────────────────────────────┐
                          │  --with-memory on dispatch    │
                          │  next dispatch prompt sees:  │
                          │  "in your last 3 TypeScript   │
                          │   projects, you used react +  │
                          │   vite 18.2.0. tsc_error self-│
                          │   heals on first retry.       │
                          │   here's the recommended      │
                          │   template for client_acme_q5."│
                          └──────────────────────────────┘
```

## What the memory looks like (universal examples, not narrative)

The old PRD framing was "characters + themes + diegetic clocks" — that's a narrative-only mental model. The renamed concept covers **all project types**:

- **Code project (`client_acme`)** — plugin usage histogram (code-typescript: 8, text-editor: 3, design-mockup: 1), common components (src/index.ts, package.json, README.md), per-plugin cost breakdown, dependency drift across iterations.
- **Video project (`short_film_2026`)** — plugin usage (video-hailuo: 4, audio-foley: 6, text-writer: 1), file-size profile (mp4: 280MB, srt: 4KB, json-manifest: 12KB), common components per iteration, audio/video sync failure modes.
- **Audio project (`ambient_pack_01`)** — plugin usage (audio-music: 8, audio-foley: 12), sample rate / bit depth profile, common failure modes (clipping, noise-floor).
- **Research project (`market_analysis_2026`)** — plugin usage (data-researcher: 1, data-analyst: 3, text-writer: 5), deliverable type histogram (md: 80%, csv: 15%, json: 5%), typical chain pattern.
- **Narrative project (`trial_of_echoes`)** — still works! Plugin usage (text-writer, audio-foley, image-portrait), characters-as-words, themes-as-strings — extracted from deliverables, not a separate concept.

The schemas are universal: every project gets a `project_type_hint`, a `deliverable_type_histogram`, a `plugin_usage` block. Narrative-specific fields (characters, themes) are simply NOT emitted for non-narrative projects. The schema is forward-compatible.

## Implementation order (recommended)

1. **PRD-17 (cross-project memory & knowledge)** — engine + skill, ~1 quarter. The doc estimates "~1 quarter, genuinely hard problem" so plan around that. Builds on top of phase 2's data sources; no new event streams are introduced.

## What this phase does NOT do

- **No embeddings / vector search across projects.** The audit log + cost log are the raw data. A future PRD (post-phase 3) could add semantic search across projects via the vector store (PRD-14's hydrate step already writes `memory/vectors.json`).
- **No LLM-generated summaries.** Memory is derived (statistical + structured) not summarized. "I worked on a similar TypeScript project last week" is a pointer, not a prose summary.
- **No cross-`VORTEX_HOME` memory.** Per-machine. A future PRD could add export/import for transferring memory between machines.
- **No SaaS / cloud memory sync.** Local file system only, same as the rest of VORTEX-OS.
- **No automatic prompt rewriting.** Memory is INJECTED into the prompt as operator notes; the engine's self-heal loop is the only thing that can rewrite prompts.

## How to use this folder

1. Read PRD-17 end-to-end. The "Design" section is the meat.
2. Resolve each "Open question" before implementation. The answers affect the file schemas in `memory/derived/`.
3. The acceptance criteria are the v0.3.x release checklist.
