# PRD-17 — Cross-Project Memory & Knowledge

**Status:** Draft · Phase 3
**Owner:** VORTEX-OS maintainers
**Source:** `idea-future-recommendations.md` item 17 (revised 2026-08-28 — universal framing replaces the original narrative-only "lore" wording)

---

## 1. Context

Today, every VORTEX-OS project lives in its own `deliverables/<project>/` subfolder. The engine treats every dispatch as if it has never seen the operator before. Three concrete failures result, and they apply to **every project type** (code, video, audio, image, research, analysis, mockups, narrative), not just creative writing:

1. **Plugin / agent amnesia.** "I worked on a `client-acme` TypeScript project last week; here's what dependencies + build pattern I used" — not possible. The next dispatch re-discovers the operator's plugin + dependency preferences from scratch.
2. **No operator-level calibration.** "Across all your projects, you spend 73% of the budget on the audio-foley plugin and 18% on text-writer; the cost-per-deliverable averages $0.42" — invisible. Every dispatch re-discovers the operator's cost + token profile.
3. **No series template reuse.** "Across your 3 `brand-redesign_v1/v2/v3` projects, the deliverable count grew 12 → 18 → 24 and the test coverage went 60% → 73% → 84%; here's a similar iteration template" — impossible. The progression has to be hand-tuned per project.

The underlying primitive is the same in all three: **a derived "memory" store computed from existing data sources (audit log + cost log + per-project manifest + plugin output)**, read across projects. The data is already there from phase 2; we're just not reading it cross-project.

**Why now (phase 3, not phase 2):** phase 2 builds the per-project data sources (audit, cost, manifests). Phase 3 derives cross-project artifacts from those. Trying to do this in phase 2 would be implementing fan-fiction about future data.

**Why "memory" not "lore":** the original option-17 wording leaned on storytelling terms (characters, themes, diegetic clocks). Those fit narrative projects but are wrong for code / video / audio / research / design projects. The renamed concept covers all of them — the storage is "memory" (universal) and the schema includes per-plugin / per-domain fingerprints (universal).

## 2. Goals

1. **Project fingerprint per project** — `memory/derived/project/<slug>.json` captures deliverable type histogram, plugin usage, file-size profile, notable self-heal patches, common dependency / build patterns. Built from the audit log + project manifest + the deliverables themselves.
2. **Cross-project operator profile** — `memory/derived/operator.json` captures operator-level style stats (per-plugin cost, per-plugin token spend, common failure modes per plugin, typical chain patterns, HITL gate placement, dispatch cadence). Built from aggregating `memory/derived/project/*.json`.
3. **Series template** — `memory/derived/series/<series>.json` captures the progression pattern across a series (per-plugin deliverable count growth, cost growth, common dependency drift). Built from project fingerprints for projects whose name matches the series pattern.
4. **Inject into the dispatch prompt** — `--with-memory` flag on `skill.ps1` injects the relevant memory slices as "Prior projects context" at prompt-construction time. Mirrors the existing `--hint` injection path (PRD-14).
5. **Browse + query** — `Get-VortexMemory` PowerShell cmdlet surfaces the memory store to the operator.
6. **Idempotent + deterministic** — `--compile-memory` is safe to run repeatedly. Output is deterministic given the same inputs (so unit tests can snapshot the output).

## 3. Non-goals

- **No LLM-generated summaries.** Memory is *derived* (statistical + structured) not *summarized*. "I worked on a similar TypeScript project last week" is a pointer to the prior project's plugin fingerprint, not a prose paragraph. This is a deliberate scope cut — prose summarization is a different problem (a future "PRD-N: semantic memory" could add it).
- **No embeddings / vector search across projects.** Phase 2's vector hydrate (PRD-14) builds the per-deliverable vector store. Cross-project semantic search is a future PRD. PRD-17 is structured / keyed only.
- **No cross-`VORTEX_HOME` memory.** Per-machine. Export/import is a future PRD.
- **No automatic prompt rewriting.** Memory is *injected* as operator notes. The engine's self-heal loop (already in v0.1.x) is the only thing that can rewrite prompts. This keeps the memory store honest — it advises, it doesn't command.
- **No SaaS / cloud sync.** Local file system, same as the rest of VORTEX-OS.
- **No real-time updates.** Memory is computed on demand via `--compile-memory`. The dispatch does not wait for a re-derivation mid-flight.
- **No automatic plugin detection from deliverable contents.** We use the plugin name recorded in the audit log (per-deliverable). No LLM, no regex on file contents.

## 4. Design

### 4.1 The memory store

```
$VORTEX_HOME/memory/derived/
├── project/
│   ├── trial_of_echoes.json      # one per project
│   ├── cartographer_ep1.json
│   ├── cartographer_ep2.json
│   ├── client_acme.json
│   └── ...
├── series/
│   ├── cartographer.json          # one per detected series
│   └── ...
├── operator.json                  # one global file (operator profile)
└── index.json                      # quick lookup: project -> memory-file, last_compiled_at, schema_version
```

Each file is a JSON document (no DB — same philosophy as the audit log).

### 4.2 `project/<slug>.json` schema

Built from: `deliverables/<slug>/_meta.json` + `deliverables/<slug>/.manifest.json` + the audit log filtered to `project=<slug>` + the cost log filtered to the same.

```json
{
  "schema": "vortex.memory.project.v1",
  "project": "client_acme",
  "compiled_at": 1700000000,
  "compiled_from": {
    "audit_lines": 1247,
    "cost_lines": 12,
    "manifest_files": 14,
    "deliverable_files_scanned": 14
  },
  "stats": {
    "deliverables_total": 14,
    "tokens_total": 87421,
    "cost_usd_total": 0.84,
    "wall_clock_minutes": 142,
    "self_heal_cycles": 3,
    "hitl_gates": 2
  },
  "project_type_hint": "code-typescript",          // most-frequent plugin; ties to agents/ plugins
  "deliverable_type_histogram": {                  // extension -> count
    ".ts": 8,
    ".json": 3,
    ".md": 2,
    ".png": 1
  },
  "size_bytes_total": 287304,
  "size_bytes_per_deliverable_avg": 20522,
  "plugin_usage": {                                // plugin name -> deliverable count
    "code-typescript": 8,
    "text-editor": 3,
    "design-mockup": 1,
    "image-portrait": 2
  },
  "plugin_cost_breakdown_usd": {                   // plugin name -> cost
    "code-typescript": 0.62,
    "text-editor": 0.14,
    "design-mockup": 0.05,
    "image-portrait": 0.03
  },
  "common_components": [                            // top-N most-frequent deliverable stems
    "src/index.ts",
    "package.json",
    "README.md",
    "tsconfig.json"
  ],
  "common_failure_modes": ["tone_drift", "character_contradiction"],
  "notable_self_heals": [
    {
      "ts": 1700001234,
      "rule_violated": "tone_drift",
      "rule_fixed": "tightened tone instructions + 3 exemplar paragraphs",
      "plugin": "text-writer"
    }
  ],
  "episodes_in_series": null                        // populated for series projects
}
```

### 4.3 `operator.json` schema (was `calibration.json`)

Built by: aggregating `project/*.json` across the whole `memory/derived/project/` tree + the cost log.

```json
{
  "schema": "vortex.memory.operator.v1",
  "compiled_at": 1700000000,
  "projects_analyzed": 7,
  "per_plugin_stats": {
    "code-typescript": {
      "total_dispatches": 23,
      "total_cost_usd": 14.62,
      "avg_tokens_per_dispatch": 4128,
      "avg_duration_seconds": 12.4,
      "common_failure_modes": [
        { "mode": "tsc_error", "occurrences": 4, "fix_rate": 1.0 }
      ]
    },
    "text-writer": {
      "total_dispatches": 18,
      "total_cost_usd": 4.20,
      "avg_tokens_per_dispatch": 1823,
      "avg_duration_seconds": 4.5,
      "common_failure_modes": [
        { "mode": "tone_drift", "occurrences": 5, "fix_rate": 0.8 }
      ]
    },
    "audio-foley": {
      "total_dispatches": 11,
      "total_cost_usd": 0.88,
      "avg_tokens_per_dispatch": 200,
      "avg_duration_seconds": 1.2,
      "common_failure_modes": []
    }
  },
  "preferred_self_heal_patches": {
    "tone_drift": "tightened tone instructions + 3 exemplar paragraphs",
    "tsc_error": "add the missing import statement from the dependency graph"
  },
  "chain_patterns": [                              // top-N most-frequent plugin chains
    ["code-typescript", "test", "package"],
    ["text-writer", "text-editor", "package"]
  ],
  "hitl_gate_placement": {
    "after_plugin": "package",
    "severity_distribution": { "LOW": 1, "MEDIUM": 3, "HIGH": 8, "CRITICAL": 2 }
  },
  "dispatch_cadence": {
    "dispatches_per_day_avg": 2.3,
    "peak_hour_of_day_utc": 14,
    "peak_day_of_week": "Tuesday"
  },
  "calibration_notes": [
    "Operator spends 73% of budget on code-typescript + text-writer; audio/image plugins are 12%.",
    "Operator's tsc_error failures all self-heal on the first retry — no human intervention needed.",
    "Operator's tone_drift failures self-heal 80% of the time; the remaining 20% escalate to HITL.",
    "Operator's HITL gate sits consistently after the 'package' plugin."
  ]
}
```

### 4.4 `series/<series>.json` schema

Built by: scanning `project/*.json` for projects whose name matches the series pattern (e.g. `cartographer_*` or `client-acme_*`), then aggregating.

```json
{
  "schema": "vortex.memory.series.v1",
  "series": "client-acme",
  "compiled_at": 1700000000,
  "episodes": ["client_acme_q1", "client_acme_q2", "client_acme_q3", "client_acme_q4"],
  "progression": {
    "deliverable_count_per_ep": [12, 15, 18, 22],
    "cost_usd_per_ep": [0.62, 0.71, 0.84, 0.93],
    "self_heal_count_per_ep": [1, 0, 2, 1],
    "hitl_gates_per_ep": [1, 2, 1, 1]
  },
  "progression_dimension": "feature_count",         // what grows across iterations
  "common_components_drift": {                       // how dependencies evolve
    "react":  ["17.0.2", "18.2.0", "18.2.0", "19.0.0"],
    "vite":   ["4.5.0", "5.0.0", "5.2.0", "5.4.0"]
  },
  "recurring_components": [                          // present in every episode
    "package.json",
    "src/index.ts",
    "README.md"
  ],
  "recommended_template_for_new_project": "see references/series_client_acme_template.md"
}
```

### 4.5 The new CLI command

`--compile-memory [options]`:

| Flag | Effect |
|---|---|
| `--project <slug>` | Compile memory for one project only (default: all projects in `deliverables/`) |
| `--series <name>` | Compile memory for one series only (default: all series detected from project names) |
| `--operator` | Compile the global operator profile only |
| `--all` | Compile everything (default if no flag given) |
| `--dry-run` | Show what would be written; don't actually write |
| `--force` | Recompile even if `index.json` says the source data is unchanged |

Returns 0 on success, 1 on JSON parse error, 2 on missing source data.

### 4.6 The new PowerShell cmdlet

`Get-VortexMemory` in `Vortex.psm1`:

```powershell
function Get-VortexMemory {
    [CmdletBinding()]
    param(
        [string] $Project,                     # filter to one project's memory
        [string] $Series,                      # filter to one series
        [switch] $Operator,                    # show the global operator profile
        [ValidateSet('summary', 'detail', 'json')]
        [string] $As = 'summary',
        [switch] $Recompile                    # force a --compile-memory run first
    )
    # ... read $VORTEX_HOME\memory\derived\ ...
}
```

### 4.7 The dispatch integration

`--with-memory` flag on `skill.ps1` and the underlying `--dispatch-master` / `--dispatch-v4`:

- Engine reads `memory/derived/index.json` to find relevant project + series memory
- For a `--dispatch-master obj.md` where `ProjectName = "client_acme_q5"`:
  - Inject `memory/derived/series/client-acme.json` (progression + common_components_drift + recommended template)
  - Inject `memory/derived/project/client_acme_q4.json` (the prior iteration's plugin fingerprint + notable self-heals)
  - Inject `memory/derived/operator.json` if it exists
- The injection is appended to the prompt as a "Prior projects context" block, ABOVE the operator's `--hint` notes

Wired in the same place `decision_history.json` is currently injected (DispatchV4's prompt builder).

## 5. Acceptance criteria

1. `--compile-memory` on a fresh install with no prior data creates the empty `memory/derived/` tree (just `index.json` with `{"schema_version": "1", "compiled_at": ..., "projects": []}`).
2. `--compile-memory` after running 3 projects writes 3 `project/*.json` files + 1 `operator.json` + the `index.json` listing them.
3. `--compile-memory --project client_acme` recomputes only that project's memory and updates `index.json` accordingly.
4. `--compile-memory` is idempotent — running it twice in a row produces byte-identical output.
5. `Get-VortexMemory` returns the project fingerprint for one project; `Get-VortexMemory -Operator` returns the global stats.
6. `--dispatch-master --with-memory` injects the prior project + series + operator profile as "Prior projects context" into the prompt. Verified by a test that dispatches with and without `--with-memory` and diffs the prompt file.
7. The injected memory is bounded: max 4,000 tokens even for a heavy memory store. Beyond that, only the operator profile + the most-relevant project's plugin fingerprint is injected.
8. The memory store can be deleted (`rm -rf $VORTEX_HOME/memory/derived/`) and the engine continues to work — `--with-memory` silently no-ops.
9. `Get-VortexMemory -As json` returns valid JSON parseable by `ConvertFrom-Json`.
10. `--compile-memory --dry-run` prints the files it would write without actually writing them.
11. The operator profile correctly aggregates across at least 3 different project types (code, video, audio) — the `per_plugin_stats` block is non-empty for each.
12. Series detection works for both `client_acme_q1/q2/q3` (underscore-separated) and `cartographer_ep1/ep2/ep3` (different separator) — the same series detection heuristic handles both.

## 6. Open questions (resolve before implementation)

- **Q1.** What defines a "series"? Two proposals: (a) name-prefix matching (`cartographer_*` → series `cartographer`), (b) explicit `_meta.json` field `series: <name>`. **(a) is more zero-config; (b) is more explicit. Recommend (a) with (b) as an override.)**
- **Q2.** How do we extract `common_components` from a deliverable without an LLM call? The cheap path: take the top-N most-frequent deliverable stems (basename without extension, e.g. `src/index.ts` → `src/index`). The expensive path: LLM-extract. **Recommend cheap path; PRD-17 explicitly does no LLM summarization.**
- **Q3.** How often should `--compile-memory` run? Options: (a) on every dispatch (synchronous, slow), (b) via a background job (PRD-14's stream watcher could trigger it), (c) manually via `skill.ps1 --compile-memory`. **Recommend (c) only for v0.3.0; (b) is a future enhancement.**
- **Q4.** What happens if a project's audit log is corrupted? `--compile-memory` should log a warning and skip that project (don't fail the whole run).
- **Q5.** Should the memory store be encrypted at rest? Same answer as audit log + cost log: no, it's local-only. A future PRD could add encryption for shared-`VORTEX_HOME` team mode (PRD-10).
- **Q6.** What's the schema versioning policy? PRD-17 uses `vortex.memory.<type>.v1`. Future versions must add new fields, never rename or remove. The `schema` field is the version stamp. A `migrate-memory.ps1` script handles upgrades.
- **Q7.** What is the right `progression_dimension` value for a series? Options: `feature_count`, `complexity`, `episode_number`, `narrative_arc`, `version_number`. The compiler picks the most descriptive one automatically based on the per-episode stats. **Recommend automatic detection with override via `_meta.json`.**

## 7. Out of scope (deferred to a future PRD)

- **M-1. Semantic search across projects.** Use the vector store (PRD-14) to do RAG over prior project memory. Future PRD: "PRD-19: Cross-Project RAG".
- **M-2. LLM-generated prose summaries.** "I learned that your TypeScript projects tend to over-import lodash" — needs an LLM call per summary. Future PRD: "PRD-20: LLM-Derived Insights".
- **M-3. Cross-`VORTEX_HOME` memory sync.** Export/import a memory pack. Future PRD: "PRD-21: Memory Pack Distribution".
- **M-4. Auto-trigger on every dispatch.** `(b)` from Q3. Future PRD: "PRD-22: Background Memory Compilation".
- **M-5. Operator-edited memory.** "Forget what the engine learned about the `client_acme` plugin mix" — manual override. Future PRD: "PRD-23: Memory Override UI".
- **M-6. Per-domain project templates.** Code projects get a `tsconfig.json` template, video projects get an `ffmpeg` recipe, audio projects get a `sample rate / bit depth` profile. Future PRD: "PRD-24: Per-Domain Templates".

## 8. Risks

- **R-1. Memory becomes stale.** A project that hasn't been dispatched in 6 months will have stale self-heal notes. Mitigation: `compiled_at` + `--force` recompile. Future: auto-recompile on a TTL.
- **R-2. Memory injection makes prompts too long.** Without bounding, the memory store could push a 2,000-token prompt to 8,000 tokens. Mitigation: hard cap at 4,000 tokens + priority order (operator profile → most-recent-project → older projects → series).
- **R-3. Schema drift.** Adding `v2` schema without a migration breaks `Get-VortexMemory -As json` consumers. Mitigation: Q6 + `migrate-memory.ps1`.
- **R-4. Project-type hint is too coarse.** "code-typescript" is one bucket; the operator might have 5 different kinds of code projects (web app, CLI, library, mobile, infra). Mitigation: future PRD adds a `domain` field in `_meta.json` for finer granularity.
- **R-5. Common-failure-modes are noise across heterogeneous projects.** A "tone_drift" failure in a text-writer project and a "tsc_error" failure in a code-typescript project are listed together, which is misleading. Mitigation: scope `common_failure_modes` to a single `project_type_hint` (already in the schema).
