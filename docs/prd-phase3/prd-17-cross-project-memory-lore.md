# PRD-17 — Cross-Project Memory & Lore

**Status:** Draft · Phase 3
**Owner:** VORTEX-OS maintainers
**Source:** `idea-future-recommendations.md` item 17

---

## 1. Context

Today, each VORTEX-OS project lives in its own `deliverables/<project>/` subfolder. The engine treats every dispatch as if it has never seen the operator before. Three concrete failures result:

1. **Character / plot amnesia.** "I worked on `<previous_project>` last week, here's what I learned about this character archetype" — not possible. The next dispatch re-derives characters from scratch.
2. **No cross-project style calibration.** "Across all your projects, you tend to write 18% over the requested word count" — invisible. Every dispatch re-discovers the operator's word-count tendency from scratch.
3. **No series template reuse.** "Across the 3-episode Cartographer arc, the water-damage clock advanced 10% / 20% / 30% — here's a similar diegetic-clock template for your new project" — impossible. The diegetic clock has to be hand-tuned per project.

The underlying primitive is the same in all three: **a derived "memory" store computed from existing data sources (audit log + cost log + project meta)**. The data is already there from phase 2; we're just not reading it cross-project.

**Why now (phase 3, not phase 2):** phase 2 builds the per-project data sources (audit, cost, manifests). Phase 3 derives cross-project artifacts from those. Trying to do this in phase 2 would be implementing fan-fiction about future data.

## 2. Goals

1. **Project lore per project** — `memory/lore/project/<slug>.json` captures characters, plot beats, style fingerprint, and notable self-heal patches. Built from the audit log + the project manifest + the deliverables.
2. **Cross-project calibration** — `memory/lore/calibration.json` captures operator-level style stats (word count tendency, prompt length tendency, common failure modes). Built from aggregating `memory/lore/project/*.json`.
3. **Series template** — `memory/lore/series/<series>.json` captures the progression pattern across a series (e.g. the Cartographer arc). Built from project lore for projects whose name matches the series pattern (e.g. `cartographer_ep1`, `cartographer_ep2`, `cartographer_ep3`).
4. **Inject into the dispatch prompt** — `--with-lore` flag on `skill.ps1` injects the relevant lore slices as "operator notes" at prompt-construction time. Mirrors the existing `--hint` injection path (PRD-14).
5. **Browse + query** — `Get-VortexLore` PowerShell cmdlet surfaces the lore store to the operator.
6. **Idempotent + deterministic** — `--compile-lore` is safe to run repeatedly. Output is deterministic given the same inputs (so unit tests can snapshot the output).

## 3. Non-goals

- **No LLM-generated summaries.** Lore is *derived* (statistical + structured) not *summarized*. "I worked on character X last week" is a pointer to the prior project + the relevant character.json fragment, not a prose paragraph. This is a deliberate scope cut — prose summarization is a different problem (a future "PRD-N: semantic memory" could add it).
- **No embeddings / vector search across projects.** Phase 2's vector hydrate (PRD-14) builds the per-deliverable vector store. Cross-project semantic search is a future PRD. PRD-17 is structured / keyed only.
- **No cross-`VORTEX_HOME` lore.** Per-machine. Export/import is a future PRD.
- **No automatic prompt rewriting.** Lore is *injected* as operator notes. The engine's self-heal loop (already in v0.1.x) is the only thing that can rewrite prompts. This keeps the lore store honest — it advises, it doesn't command.
- **No SaaS / cloud sync.** Local file system, same as the rest of VORTEX-OS.
- **No real-time updates.** Lore is computed on demand via `--compile-lore`. The dispatch does not wait for a re-derivation mid-flight.

## 4. Design

### 4.1 The lore store

```
$VORTEX_HOME/memory/lore/
├── project/
│   ├── trial_of_echoes.json      # per-project artifact
│   ├── cartographer_ep1.json
│   ├── cartographer_ep2.json
│   └── ...
├── series/
│   ├── cartographer.json          # one per detected series
│   └── ...
├── calibration.json               # one global file
└── index.json                     # quick lookup: project -> lore-file, last_compiled_at
```

Each file is a JSON document (no DB — same philosophy as the audit log).

### 4.2 `project/<slug>.json` schema

Built from: `deliverables/<slug>/_meta.json` + `deliverables/<slug>/.manifest.json` + the audit log filtered to `project=<slug>` + the cost log filtered to the same.

```json
{
  "schema": "vortex.lore.project.v1",
  "project": "trial_of_echoes",
  "compiled_at": 1700000000,
  "compiled_from": {
    "audit_lines": 1247,
    "cost_lines": 12,
    "manifest_files": 14
  },
  "stats": {
    "deliverables_total": 14,
    "tokens_total": 87421,
    "cost_usd_total": 0.84,
    "wall_clock_minutes": 142,
    "self_heal_cycles": 3,
    "hitl_gates": 2
  },
  "style_fingerprint": {
    "word_count_actual_avg": 1842,
    "word_count_target_avg": 1500,        // pulled from the objective.md
    "word_count_overrun_pct": 22.8,
    "avg_prompt_tokens": 412,
    "common_failure_modes": ["tone_drift", "character_contradiction"]
  },
  "notable_self_heals": [
    {
      "ts": 1700001234,
      "rule_violated": "tone_drift",
      "rule_fixed": "tightened tone instructions + 3 exemplar paragraphs",
      "worker": "writer.shift"
    }
  ],
  "characters": [                          // pulled from deliverable *.json files
    {
      "name": "Director Hale",
      "appearances": 3,
      "first_seen": 1700000100,
      "last_seen": 1700001200
    }
  ],
  "themes": ["dossier discovery", "official corruption"],  // pulled from deliverables/
  "episodes_in_series": null               // null for stand-alone projects
}
```

### 4.3 `series/<series>.json` schema

Built by: scanning `project/*.json` for projects whose name matches the series pattern, then aggregating.

```json
{
  "schema": "vortex.lore.series.v1",
  "series": "cartographer",
  "compiled_at": 1700000000,
  "episodes": ["cartographer_ep1", "cartographer_ep2", "cartographer_ep3"],
  "progression": {
    "word_count_growth_pct": [0, 8, 15],       // ep1 → ep2 → ep3
    "self_heal_count_per_ep": [1, 0, 2],
    "hitl_gates_per_ep": [1, 2, 1]
  },
  "diegetic_clocks": {
    "water_damage_clock": [10, 20, 30],        // per episode, in pct
    "director_hale_awareness": [0, 50, 100]
  },
  "recurring_themes": ["map provenance", "physical decay"],
  "recurring_characters": [
    {
      "name": "Director Hale",
      "appearances_across_series": 9,
      "evolution_notes": "started naive, became complicit, ended disillusioned"
    }
  ],
  "recommended_template_for_new_project": "see references/series_cartographer_template.md"
}
```

### 4.4 `calibration.json` schema

Built by: aggregating `project/*.json` across the whole `memory/lore/project/` tree.

```json
{
  "schema": "vortex.lore.calibration.v1",
  "compiled_at": 1700000000,
  "projects_analyzed": 7,
  "operator_stats": {
    "avg_word_count_overrun_pct": 18.4,
    "avg_prompt_tokens": 387,
    "common_failure_modes": [
      { "mode": "tone_drift", "occurrences": 9, "fix_rate": 0.89 },
      { "mode": "character_contradiction", "occurrences": 4, "fix_rate": 1.0 }
    ],
    "preferred_self_heal_patches": {
      "tone_drift": "tightened tone instructions + 3 exemplar paragraphs",
      "character_contradiction": "re-state prior episode's character traits verbatim"
    }
  },
  "calibration_notes": [
    "Operator tends to write 18% over word budget — pre-emptively trim 15% in the prompt.",
    "Operator's character_contradiction failures all self-heal on the first retry — no human intervention needed.",
    "Operator's tone_drift failures self-heal 89% of the time; the remaining 11% escalate to HITL."
  ]
}
```

### 4.5 The new CLI command

`--compile-lore [options]`:

| Flag | Effect |
|---|---|
| `--project <slug>` | Compile lore for one project only (default: all projects in `deliverables/`) |
| `--series <name>` | Compile lore for one series only (default: all series detected from project names) |
| `--calibration` | Compile the global calibration only |
| `--all` | Compile everything (default if no flag given) |
| `--dry-run` | Show what would be written; don't actually write |
| `--force` | Recompile even if `index.json` says the source data is unchanged |

Returns 0 on success, 1 on JSON parse error, 2 on missing source data.

### 4.6 The new PowerShell cmdlet

`Get-VortexLore` in `Vortex.psm1`:

```powershell
function Get-VortexLore {
    [CmdletBinding()]
    param(
        [string] $Project,                     # filter to one project's lore
        [string] $Series,                      # filter to one series
        [switch] $Calibration,                 # show the global calibration
        [ValidateSet('summary', 'detail', 'json')]
        [string] $As = 'summary',
        [switch] $Recompile                    # force a --compile-lore run first
    )
    # ... read $VORTEX_HOME\memory\lore\ ...
}
```

### 4.7 The dispatch integration

`--with-lore` flag on `skill.ps1` and the underlying `--dispatch-master` / `--dispatch-v4`:

- Engine reads `memory/lore/index.json` to find relevant project + series lore
- For a `--dispatch-master obj.md` where `ProjectName = "cartographer_ep4"`:
  - Inject `memory/lore/series/cartographer.json` (diegetic clocks + recurring characters + recommended template)
  - Inject `memory/lore/project/cartographer_ep3.json` (the prior episode's style fingerprint + notable self-heals)
  - Inject `memory/lore/calibration.json` if it exists
- The injection is appended to the prompt as a "Prior projects context" block, ABOVE the operator's `--hint` notes

Wired in the same place `decision_history.json` is currently injected (DispatchV4's prompt builder).

## 5. Acceptance criteria

1. `--compile-lore` on a fresh install with no prior data creates the empty `memory/lore/` tree (just `index.json` with `{"compiled_at": ..., "projects": []}`).
2. `--compile-lore` after running 3 projects writes 3 `project/*.json` files + 1 `calibration.json` + the `index.json` listing them.
3. `--compile-lore --project trial_of_echoes` recomputes only that project's lore and updates `index.json` accordingly.
4. `--compile-lore` is idempotent — running it twice in a row produces byte-identical output.
5. `Get-VortexLore` returns the project lore for one project; `Get-VortexLore -Calibration` returns the global stats.
6. `--dispatch-master --with-lore` injects the prior project + series + calibration as "Prior projects context" into the prompt. Verified by a test that dispatches with and without `--with-lore` and diffs the prompt file.
7. The injected lore is bounded: max 4,000 tokens even for a heavy lore store. Beyond that, only the calibration + the most-relevant project's style_fingerprint is injected.
8. The lore store can be deleted (`rm -rf $VORTEX_HOME/memory/lore/`) and the engine continues to work — `--with-lore` silently no-ops.
9. `Get-VortexLore -As json` returns valid JSON parseable by `ConvertFrom-Json`.
10. `--compile-lore --dry-run` prints the files it would write without actually writing them.

## 6. Open questions (resolve before implementation)

- **Q1.** What defines a "series"? Two proposals: (a) name-prefix matching (`cartographer_*` → series `cartographer`), (b) explicit `_meta.json` field `series: <name>`. **(a) is more zero-config; (b) is more explicit. Recommend (a) with (b) as an override.)**
- **Q2.** How do we extract "characters" from a deliverable without an LLM call? The cheap path: scan the deliverable file for capitalized proper-noun phrases. The expensive path: LLM-extract. **Recommend cheap path; PRD-17 explicitly does no LLM summarization.**
- **Q3.** How often should `--compile-lore` run? Options: (a) on every dispatch (synchronous, slow), (b) via a background job (PRD-14's stream watcher could trigger it), (c) manually via `skill.ps1 --compile-lore`. **Recommend (c) only for v0.3.0; (b) is a future enhancement.**
- **Q4.** What happens if a project's audit log is corrupted? `--compile-lore` should log a warning and skip that project (don't fail the whole run).
- **Q5.** Should the lore store be encrypted at rest? Same answer as audit log + cost log: no, it's local-only. A future PRD could add encryption for shared-`VORTEX_HOME` team mode (PRD-10).
- **Q6.** What's the schema versioning policy? PRD-17 uses `vortex.lore.<type>.v1`. Future versions must add new fields, never rename or remove. The `schema` field is the version stamp. A `migrate-lore.ps1` script handles upgrades.

## 7. Out of scope (deferred to a future PRD)

- **L-1. Semantic search across projects.** Use the vector store (PRD-14) to do RAG over prior project lore. Future PRD: "PRD-19: Cross-Project RAG".
- **L-2. LLM-generated prose summaries.** "I learned that your protagonist tends to be skeptical of authority" — needs an LLM call per summary. Future PRD: "PRD-20: LLM-Derived Insights".
- **L-3. Cross-`VORTEX_HOME` lore sync.** Export/import a lore pack. Future PRD: "PRD-21: Lore Pack Distribution".
- **L-4. Auto-trigger on every dispatch.** `(b)` from Q3. Future PRD: "PRD-22: Background Lore Compilation".
- **L-5. Operator-edited lore.** "Forget what the engine learned about Director Hale" — manual override. Future PRD: "PRD-23: Lore Override UI".

## 8. Risks

- **R-1. Lore becomes stale.** A project that hasn't been dispatched in 6 months will have stale self-heal notes. Mitigation: `compiled_at` + `--force` recompile. Future: auto-recompile on a TTL.
- **R-2. Lore injection makes prompts too long.** Without bounding, the lore store could push a 2,000-token prompt to 8,000 tokens. Mitigation: hard cap at 4,000 tokens + priority order (calibration → most-recent-project → older projects → series).
- **R-3. Schema drift.** Adding `v2` schema without a migration breaks `Get-VortexLore -As json` consumers. Mitigation: Q6 + `migrate-lore.ps1`.
- **R-4. The "characters" extraction is brittle.** Scanning for capitalized phrases catches false positives (city names, brand names). Mitigation: scope to the deliverable's prose-only files; skip code + JSON.
