# PRD-12 — Cost / Token Budgeting

**Status:** Draft · Phase 2 (user said "ok i agree")
**Owner:** VORTEX-OS maintainers
**Source:** `idea-future-recommendations.md` item 12

---

## 1. Context

The audit log records `duration_ms` and `tokens_out` (from `metrics.tokens_out` in the raw output JSON) but not `tokens_in`, not cost, and not per-project budget. The `inspector.governance` agent is meant to do "token velocity" governance, but the implementation is a stub.

For a multi-episode series with 7 deliverables × 5 episodes = 35 dispatches, an operator has no way to answer "are we on track to hit the $200 budget?" until the bill comes.

The user agreed to the recommendation from `idea-future-recommendations.md` item 12:

- `lib/CostTracker.cpp` records token counts per dispatch
- Per-project budget in `_meta.json` (e.g. `"budgets": {"max_tokens_per_dispatch": 50000}`)
- Alert (PENDING_HUMAN) when a dispatch exceeds 80% of budget

## 2. Goals

1. **Every dispatch records prompt + completion token counts** in a durable cost log.
2. **Per-project budgets** can be set in `_meta.json` and overridden via env var.
3. **Alerts at 80% and 100%** of budget — surfaced as PENDING_HUMAN gates (the operator decides whether to continue or stop).
4. **Cost reports** by project, day, agent, or dispatch — text table or JSON.
5. **No LLM provider is hard-coded.** Cost calculation reads from a per-model price table that the user can extend.
6. **Backward-compatible.** Projects without budgets work as today (no alerts, no gates).

## 3. Non-goals

- **Real-time price feeds.** The price table is a static file the user maintains.
- **Currency conversion.** All amounts are in USD; the user converts if needed.
- **Multi-tenant billing.** VORTEX-OS is a single-org tool. For team billing, use the shared `VORTEX_HOME` + a per-user cost rollup.
- **Invoice generation.** The cost log is the source of truth; the user exports it to their accounting system.

## 4. Design

### 4.1 The cost log

A new JSONL file at `$VORTEX_HOME/state/cost_log.jsonl`. One line per dispatch:

```json
{
  "ts": 1700000000,
  "task_id": "ep1_writer",
  "project": "trial_of_echoes",
  "agent": "writer.shift",
  "model": "MiniMax-Text-01",
  "tokens_in": 4521,
  "tokens_out": 1823,
  "total_tokens": 6344,
  "cost_usd": 0.0234,
  "duration_ms": 4500,
  "tags": ["episode-1", "script"]
}
```

Append-only. Locked (advisory) to support concurrent writers.

### 4.2 The price table

A JSON file at `$VORTEX_HOME/.vortex/model_prices.json` (auto-created on first use with sensible defaults):

```json
{
  "_comment": "Cost per 1K tokens in USD. Update this file when providers change pricing.",
  "models": {
    "MiniMax-Text-01":      { "in": 0.0008,  "out": 0.0024 },
    "MiniMax-Text-02":      { "in": 0.0010,  "out": 0.0030 },
    "MiniMax-Music":        { "in": 0.0,     "out": 0.05,   "per_request": true },
    "MiniMax-Hailuo-2.3":   { "in": 0.0,     "out": 0.30,   "per_request": true, "per_second": 0.05 },
    "MiniMax-H3":           { "in": 0.0,     "out": 0.50,   "per_request": true, "per_second": 0.08 },
    "MiniMax-Image":        { "in": 0.0,     "out": 0.04,   "per_request": true },
    "MiniMax-TTS":          { "in": 0.0,     "out": 0.02,   "per_request": true }
  },
  "default": { "in": 0.001, "out": 0.002 }
}
```

The cost calculator reads this file at startup. If a model isn't listed, the `default` is used (with a warning to the operator).

### 4.3 Per-project budgets

Three places budgets can live, in priority order:

1. **Env var (highest priority):**
   ```powershell
   $env:VORTEX_BUDGET_TOKENS_TOTAL = '500000'        # total tokens for this run
   $env:VORTEX_BUDGET_USD_TOTAL = '200.00'           # total USD for this run
   $env:VORTEX_BUDGET_TOKENS_PER_DISPATCH = '50000'  # per-dispatch cap
   $env:VORTEX_BUDGET_USD_PER_DISPATCH = '5.00'      # per-dispatch cap
   ```

2. **Project-level `_meta.json` (in the project root if it exists):**
   ```json
   {
     "name": "trial_of_echoes",
     "budgets": {
       "tokens_total": 500000,
       "usd_total": 200.00,
       "tokens_per_dispatch": 50000,
       "usd_per_dispatch": 5.00
     }
   }
   ```

3. **Global `$VORTEX_HOME/.vortex/budgets.json`:**
   ```json
   {
     "default_tokens_per_dispatch": 100000,
     "default_usd_per_dispatch": 10.00
   }
   ```

### 4.4 The 80% / 100% alert

After each dispatch, the cost tracker checks:

- `cost_so_far / usd_total >= 0.80` → **alert gate** (PENDING_HUMAN, severity MEDIUM)
  - Message: "Trial of Echoes has used 82% of its $200 budget ($164). Continue? (yes/no)"
- `cost_so_far / usd_total >= 1.00` → **hard gate** (PENDING_HUMAN, severity CRITICAL)
  - Message: "Trial of Echoes has exceeded its $200 budget ($214). Continue? (yes/no) — denying will abort the dispatch and freeze the deliverables."
- `dispatch_cost / usd_per_dispatch >= 0.80` → **per-dispatch warning** (logged, no gate)

The gate is implemented the same way the existing HITL gates work: write a checkpoint JSON, exit 203, the operator replies approve/deny.

### 4.5 The cost report

A new command: `--cost-report`:

```powershell
# All projects, all time
pwsh -NoProfile -File .\skill.ps1 --cost-report

# Per project
pwsh -NoProfile -File .\skill.ps1 --cost-report --project trial_of_echoes

# Per day
pwsh -NoProfile -File .\skill.ps1 --cost-report --since 7d

# Per agent
pwsh -NoProfile -File .\skill.ps1 --cost-report --agent writer.shift

# JSON output
pwsh -NoProfile -File .\skill.ps1 --cost-report --json
```

Sample output:

```
VORTEX-OS cost report
======================
Project: trial_of_echoes
Period: 2026-08-01 → 2026-08-27 (27 days)

  Agent            Dispatches   Tokens (in+out)   Cost (USD)
  ---------------  -----------  ----------------  -----------
  writer.shift            12         245,012      $  0.91
  audio-foley              3          18,200      $  1.50
  image-portrait           4          24,800      $  0.16
  code-typescript          2          61,440      $  0.18
  ---------------------  ----  ----------------  -----------
  TOTAL                   21         349,452      $  2.75

Budget: $200.00 (1.4% used)
```

### 4.6 Wiring into the dispatch pipeline

The engine's `DispatchV4::Run` is extended:

```cpp
int DispatchV4::Run(Paths^ p, String^ taskId, String^ agentName, String^ objectiveRef) {
    auto cost = CostTracker::For(p, taskId, agentName);

    // ... existing dispatch logic ...

    // After the worker reports metrics.tokens_in / tokens_out:
    cost.RecordTokens(rawIn, rawOut);

    // After every dispatch:
    cost.CheckBudget();   // raises PENDING_HUMAN gate at 80% / 100%

    return 0;
}
```

`CostTracker` is a new lib at `lib/CostTracker.{h,cpp}`. It owns:
- The path to the cost log file
- The price table (loaded once at construction)
- The current dispatch's running token count
- The cumulative project totals (read from the cost log on construction, updated as new lines are appended)
- The `CheckBudget()` method

## 5. API surface

### New commands (skill-side + engine-side)

```powershell
# Cost report
pwsh -NoProfile -File .\skill.ps1 --cost-report [--project <name>] [--since <Nd>] [--agent <name>] [--json]

# Cost record (for manual / one-off recording)
pwsh -NoProfile -File .\skill.ps1 --cost-record --task <id> --agent <name> --model <name> --tokens-in N --tokens-out N [--duration-ms N] [--tags t1,t2]

# Cost estimate (what would this dispatch cost given a prompt size?)
pwsh -NoProfile -File .\skill.ps1 --cost-estimate --model <name> --tokens-in N --tokens-out N

# Set / show budgets for a project
pwsh -NoProfile -File .\skill.ps1 --budget-set --project <name> --tokens-total N --usd-total N
pwsh -NoProfile -File .\skill.ps1 --budget-show --project <name>
```

### New env vars

```powershell
$env:VORTEX_BUDGET_TOKENS_TOTAL
$env:VORTEX_BUDGET_USD_TOTAL
$env:VORTEX_BUDGET_TOKENS_PER_DISPATCH
$env:VORTEX_BUDGET_USD_PER_DISPATCH
$env:VORTEX_MODEL_PRICES        # path to a custom model_prices.json (default: $VORTEX_HOME/.vortex/model_prices.json)
```

### New file in `VORTEX_HOME`

```
state/
  cost_log.jsonl
.vortex/
  model_prices.json
  budgets.json              # global defaults
```

## 6. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| The model_prices.json is stale and the cost report shows wrong numbers | High | Low | The report is advisory, not billing. The operator can override with a fresh prices file via `$env:VORTEX_MODEL_PRICES`. |
| An agent reports `tokens_in = 0` and the cost is 0 (model provider doesn't expose prompt tokens) | Medium | Low | Fall back to estimating `tokens_in` from the input text size (~1 token per 4 chars). Log a warning. |
| The 80% gate fires on every dispatch once the budget is hit (annoying) | Medium | Medium | Only fire the 80% gate ONCE per project per session (track `last_alert_ts` in memory; the operator dismisses once and doesn't see it again). |
| A malicious worker reports `tokens_in: -1` to manipulate the cost log | Low | Medium | The cost tracker validates: tokens must be non-negative integers. Out-of-range values are clamped to 0 with a warning. |
| The cost log grows unbounded (every dispatch for 5 years) | Medium | Low | Auto-rotate at 100 MB (move to `cost_log.1.jsonl`, `cost_log.2.jsonl`, ...). The report reads all of them transparently. |

## 7. Acceptance criteria

1. Every dispatch appends one line to `state/cost_log.jsonl` with prompt + completion tokens, cost_usd, and duration_ms.
2. Setting `$env:VORTEX_BUDGET_USD_TOTAL=10` on a project that hits $8 dispatches the next dispatch with a PENDING_HUMAN gate at MEDIUM severity.
3. Setting `$env:VORTEX_BUDGET_USD_TOTAL=10` on a project that hits $11 dispatches the next dispatch with a PENDING_HUMAN gate at CRITICAL severity.
4. `--cost-report` shows the running total, by agent and by project.
5. `--cost-estimate` calculates the projected cost for a given token count.
6. `verify.ps1` adds a `tests/test_cost_tracking.ps1` that runs 3 dispatches with mock metrics, asserts the cost log has 3 lines, and asserts the budget alert fires at 80%.
7. `idea-future-recommendations.md` item 12 → ✅ status.

## 8. Effort

- `engine/lib/CostTracker.{h,cpp}`: ~250 lines
- `engine/skill.cpp` + `DispatchV4.cpp` integration: ~80 lines
- `skill/skill.ps1` (new --cost-* commands): ~200 lines
- New `setup-cost.ps1` (one-time, generates the default model_prices.json + budgets.json): ~80 lines
- New tests: ~250 lines
- Docs: `references/INSTRUCTIONS.md` + new `references/cost-management.md`

**Total: ~860 lines. 2 PRs (engine + skill). Tag bump to 0.1.10. ~5-7 days for a single engineer.**

## 9. Open questions

- **Q1.** Should the budget gate be skip-able with a `--no-budget` flag? — *Recommend: yes, for tests and emergency overrides. The flag is logged to the audit log.*
- **Q2.** Should we integrate with a cost API (e.g. LiteLLM's cost tracker) for accurate prices? — *Recommend: no for v1. Static prices are enough; revisit if operators complain.*
- **Q3.** Should the cost log also track audio-seconds and image-count (for non-text models)? — *Recommend: yes. The cost log has `tokens_in` / `tokens_out` for text, but also `media_seconds` / `image_count` / `video_seconds` for non-text.*
- **Q4.** Should `--cost-report` support CSV export? — *Recommend: yes, add `--csv`.*
- **Q5.** What happens if the cost log file is corrupted? — *Recommend: the cost tracker reads the log line-by-line and skips lines that fail JSON parsing. The skip count is logged. The next dispatch writes a fresh valid line.*

## 10. Future work (not in this PRD)

- **Forecasting** — given the project's burn rate, project when the budget will be exhausted.
- **Per-team budgets** — for a shared `VORTEX_HOME`, allocate per-user budgets.
- **Budget approval workflow** — when a budget is exceeded, require an admin's approval to continue (vs. the operator's).
