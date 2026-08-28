# Changelog

All notable changes to the VORTEX-OS skill package are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.3.5] - 2026-08-28

### Added
- **mcode-tools → fallback chain** in `plugin-sdk/Vortex.Plugin.psm1`.
  Every media plugin (image-cover, image-portrait, image-map,
  audio-voice, audio-music, audio-foley, video-hailuo, video-animator)
  now defaults to the cloud-hosted `mcode-tools` connector and falls
  back to a local alternative when mcode-tools is unavailable,
  unauthenticated, or errors. The plugin ALWAYS produces a valid
  output file matching its contract — the operator can see in the
  audit log which provider produced each asset.
- **New SDK helpers** in `Vortex.Plugin.psm1`:
  - `Get-VortexMcodeToolsPath` / `Test-VortexMcodeToolsAvailable` — locate and probe the mcode-tools CLI.
  - `Invoke-VortexMcodeConnector` — call `mcode-tools connector call <tool> --args <json>` and parse the result.
  - `Get-VortexAssetUrl` / `Save-VortexAssetFromUrl` / `Invoke-VortexDownloadAsset` — fetch a temp URL for a returned `node_id` and download to a local path.
  - `Invoke-VortexMcodeConnectorAsync` — submit + poll for `submit_video_generation` / `query_video_generation`.
  - `Invoke-VortexWithFallback` — top-level: try mcode-tools, fall back to a scriptblock on failure.
  - `New-VortexPlaceholderPng`, `New-VortexSilentWav`, `New-VortexSapiTtsWav`, `New-VortexFfmpegToneWav`, `New-VortexFfmpegColorFrameMp4` — the local fallback implementations.
- **`fallback_chain` field** added to the 8 media plugin.json files
  so the engine / operator / user can see the primary + fallback
  chain at a glance (e.g. `mcode-tools` -> `local-sapi-tts` ->
  `local-silent` for audio-voice).

### Changed
- **8 media plugin `invoke.ps1` files rewritten** to use
  `Invoke-VortexWithFallback`. The previous versions wrote a 1x1 PNG /
  silent WAV / placeholder text stub; the new versions try
  mcode-tools first and only fall back to a local generator if
  mcode-tools is unavailable.
- **`SKILL.md` "Trigger Conditions"** now includes a "media
  production with graceful degradation" bullet so the LLM knows
  the skill will keep producing output even if mcode-tools is
  offline. The plugin-sdk row in the anatomy table now lists the
  new fallback helpers.
- **`Vortex.Plugin.psm1` version header** bumped to v0.3.5.

### No engine change
- Engine v0.3.0 is still the minimum version; v0.3.5 is skill-side
  only. The mcode-tools pipeline is a plugin-side detail — the
  engine doesn't need to know about it.

## [0.3.4] - 2026-08-28

### Added
- **`agents/media-stack.json`** (NEW, 4.6 KB) -- Tier 3 worker manifest
  that bundles the 7 shipped media plugins (`image-cover`,
  `image-portrait`, `audio-voice`, `audio-music`, `video-hailuo`,
  `video-animator`, `media-ffmpeg`) into one dispatchable roster. The
  engine can now dispatch a multi-deliverable media production
  (tutorial video, ad cut, narrated slide deck, social clip) without
  the LLM having to compose a manifest by hand. Closes the "no media
  producer in `agents/`" gap.
- **`templates/media-tutorial-video.json`** (NEW, 6.1 KB) -- Golden
  Path template for "one source markdown / script -> finished media
  deliverable." Defines the canonical 5-step flow (storyboard, hero
  images, voiceover, BGM, final MP4), the 3 HITL gates (script,
  visual+audio assembly, final pack), and 5 self-heal targets (tone
  drift, style drift, color drift, pacing mismatch, audio level
  mismatch). Ships with 3 dispatch examples (recipe shortcut, explicit
  template dispatch, hand-written master objective).
- **Media-production bullet** in `trigger.when_to_use` (_meta.json)
  and a matching bullet in the "Trigger Conditions" section in
  SKILL.md. The skill now explicitly advertises
  "multi-step media production" as a supported use case so the LLM's
  trigger-detection has a concrete match for "build me a video" /
  "make an ad" / "turn this markdown into a tutorial" prompts.
- **Recipe row in the SKILL.md command table** for
  `pwsh skill.ps1 --dispatch-template templates\media-tutorial-video.json`
  so the LLM has a one-line copy-paste starting point.

### Changed
- **Added boundary #8 to `references/INSTRUCTIONS.md` §8 "Important
  Boundaries"** and a matching paragraph in the SKILL.md "Trigger
  Conditions" section: **"Never bypass the skill when the user
  explicitly invoked it."** When the user writes `/VORTEX-OS`, "use
  vortex-os", or any other explicit invocation, the LLM MUST
  dispatch through the engine. The only acceptable bypass is an
  explicit "skip the orchestration layer" or "do it directly"
  phrase from the user. Closes the "agent decided to bypass" gap
  that caused the media-tutorial-video miss in the prior session.
- **SKILL.md "Trigger Conditions" section** now includes the
  "multi-step media production" bullet between the existing
  "multi-domain work" and "hierarchical task decomposition" bullets,
  so the LLM scanning the trigger list sees "video" as a
  first-class use case.

### No engine change
- Engine v0.3.0 is still the minimum version; v0.3.4 is skill-side
  only. The `media-stack` manifest + `media-tutorial-video` template
  are read by the existing `--dispatch-template` + plugin loader; no
  engine wiring change was needed.
- The engine-side follow-up (a built-in `--recipe media-tutorial-video`
  shortcut baked into the engine) is the next enhancement if you want
  a one-line dispatch without writing the template path. Tracked for
  engine v0.3.5 if requested.

## [0.3.3] - 2026-08-28

### Changed
- **Shrunk the skill description** in `_meta.json` (~600 chars) and
  `SKILL.md` frontmatter (~300 chars). The previous descriptions repeated
  the long use-it / don't-use-it bullet lists that already live in
  `trigger.when_to_use` and the "Trigger Conditions" section. The new
  description is the minimum an agent needs to know what the skill is:
  *self-bootstrapping PowerShell skill that drives the .NET 10 engine
  to orchestrate multi-agent work pipelines with a 4-tier chain of
  command, continuity enforcement, HITL approval, and per-agent audit
  log; v0.3.0+ adds a cross-project memory layer.*

### No behavioral change
- Engine wiring, CLI commands, install flow, and all other files are
  unchanged from v0.3.2.

## [0.3.2] - 2026-08-28

### Removed
- **`docs/`** (9 files: 7 phase-2 PRDs, README, PRD-17). Engineering
  design material that was shipped in the working tree for traceability.
  Moved to the platform wiki; the v0.3.2 release artifact no longer
  contains it. All prior commits still reference these files in git
  history (`git log --all -- 'docs/prd-phase2/*'` etc. works as before).
- **`idea-architecture-decisions.md`**, **`idea-faq-and-pitfalls.md`**,
  **`idea-future-recommendations.md`** — the design notebook (15 ADRs,
  30+ Q&As, 18 future-recommendation items). Same wiki migration. The
  v0.3.1 verification_status summary of the major v0.1.x–v0.3.0
  decisions stays in `_meta.json` so the platform metadata block still
  carries the long-form audit trail.

### Changed
- **`.gitignore`** now excludes `docs/` and `idea-*.md`. The shipped
  `templates/*.json` exception (added in v0.3.1) is preserved.
- **`SKILL.md` anatomy table** — the three `idea-*.md` rows are replaced
  with a `CHANGELOG.md` pointer so the LLM knows where to find the
  per-version history.
- **`_meta.json` `files` block** — `future_recommendations`,
  `architecture_decisions`, `faq_and_pitfalls` are set to `null` to
  signal "moved to wiki, see CHANGELOG for the per-version record".

### Engine dependency
- No engine change. v0.3.2 is skill-side cleanup only; v0.3.0 is still
  the minimum engine version. Safe to install over v0.3.1.

## [0.3.1] - 2026-08-28

### Changed
- **Universal reword of all user-facing skill docs.** Every narrative-specific
  example has been replaced with a domain-agnostic one so the skill reads as a
  general orchestration tool, not a narrative / worldbuilding one.

  Concretely:
  - `SKILL.md` description + trigger conditions + storage example + anatomy
    table + install + command reference all rewritten in universal terms.
  - `README.md` storage diagram, 4-Tier chain (T3 workers are now described as
    pluggable per project — research / video / data audit each get a different
    crew), and command reference rewired.
  - `_meta.json` description, capabilities (added 5 memory-related),
    `trigger.when_to_use`, tags (dropped `narrative` / `worldbuilding`, added
    `cross-project-memory` / `data-pipeline` / `research-pipeline` /
    `design-system` / `constraint-enforcement`), `verification_status` (new
    v0.3.1 entry + v0.3.0 cross-project memory details), and `version` bumped
    to 0.3.1.
  - `references/INSTRUCTIONS.md` "When To Invoke" section, the §4.1 continuity
    example (was: "Mara's prosthetic left hand"), and the §10 end-to-end
    walkthrough (was: "When Ocean Meets Sky / Mara on her porch / 1994"; now:
    "release_v2_3_0 release readiness report"). Added a new §6.5
    "Cross-Project Memory" section documenting the engine v0.3.0 memory layer.
  - `references/architecture.md` Mermaid diagrams: 4-tier chain example
    ("episode 2 script.md" → "release_v2/objective.md"), T3 worker labels
    (added `data` and `researcher`), storage split example (was:
    "scene1.md / soundscape.wav"; now: "research_notes.md / data_pipeline.py"),
    dispatch + HITL flow ("Keeper spoke a full sentence" → "dashboard drifted
    from the brand palette"), and lifecycle state ("script gate" → "artifact
    gate", "next episode" → "next iteration").
  - `walkthrough/slides/slide-{02,04,08,09,10}.html` and
    `walkthrough/README.md` index — "moral-hinge rule" → "operator checkpoint",
    "the protagonist is on the wrong ship" → "the schema dropped a required
    column", "Episode 2+" → "iteration 2+", "characters contradict each other,
    lore is forgotten" → "outputs drift, contracts contradict each other,
    constraints are forgotten", "all 7 deliverables are bundled" → "all N
    deliverables are bundled".
  - `templates/iteration_pattern.json` (NEW, 6.1 KB) — universal Golden Path
    template (release trains, research programs, audit cycles, design-system
    evolutions, product lineups, report series, etc.). The original
    `templates/episode_pattern.json` still ships as a working narrative
    example for users who already have a workflow pointed at it.

### Engine dependency
- No engine change. This release is skill-side docs only; the v0.3.0 engine
  binary is still the minimum version (it ships the cross-project memory
  features referenced in the rewritten docs). Safe to install over v0.3.0.

## [0.3.0] - 2026-08-28

### Added
- **`Get-VortexMemory` cmdlet** in `Vortex.psm1` -- browse the
  cross-project memory store. `-Project <slug>` returns one project's
  fingerprint, `-Series <name>` returns a series template, `-Operator`
  returns the global profile. `-As detail` prints the full JSON,
  `-As json` returns the raw string for `ConvertFrom-Json`.
- **`skill.ps1` help text** now lists the new MEMORY section
  (`--compile-memory`, `--memory-show`). The `--compile-memory`
  flag is passed through to the engine; the skill side just adds the
  "Up to date" check.

### Changed
- **No behavioral change** to the skill routing for v0.3.0. The
  `--with-memory` dispatch flag is deferred to v0.3.1 (needs the
  prompt-construction wiring in DispatchV4).

### Engine dependency
- Requires [vortex-os-dotnet v0.3.0](https://github.com/Cloudmeru/vortex-os-dotnet/releases/tag/v0.3.0)
  which ships the `lib/Memory.{h,cpp}` compiler, the
  `--compile-memory` + `--memory-show` CLI commands, and the
  `Memory::ReadForInjection` slice for the future `--with-memory`
  prompt integration.

## [0.2.3] - 2026-08-28

### Added
- **`install-powershell7.ps1`** (~7 KB) — bootstrap PowerShell 7+ from a
  Windows PowerShell 5.1 prompt. Downloads the official Microsoft PS7
  MSI to a temp folder and runs it with `/quiet /norestart`. Per-user
  install (no UAC, no reboot) on Windows 10 1809+ and Server 2019+.
  Required for G9 — a fresh Windows install with only PS5.1 can now
  self-bootstrap.
- **`lib/vector_schema.sql`** (~2.5 KB) — the SQLite schema for the
  vector store (3 tables: `vector_embeddings`, `vector_meta`,
  `vector_index_meta`). Was referenced by `Commands::VectorHydrate`
  but never shipped; the hydrate step used to silently no-op. Now
  the engine actually creates the DB on a clean install.
- **`install_fallbacks` field in `_meta.json`** — the choco / scoop /
  direct-URL alternatives for each dep, so a locked-down corporate
  machine with no winget has a documented install path.
- **11 new PowerShell cmdlets** in `Vortex.psm1` (G11):
  `Get-VortexDecision`, `Send-VortexDecision`, `Get-VortexCostReport`,
  `Get-VortexProjectBudget`, `Set-VortexProjectBudget`,
  `Get-VortexAgentGraph`, `Test-VortexAgent`, `Start-VortexPackage`,
  `Get-VortexStream`, `Send-VortexStreamHint`, `Get-VortexTeamConfig`,
  `Invoke-VortexVectorHydrate`. Plus the existing `Get-VortexVersion`
  from G5.
- **`Get-VortexVersion` cmdlet** — reads `ModuleVersion` from
  `Vortex.psd1` so callers don't have to shell out to
  `skill.ps1 --version`.

### Changed
- **`auto-update.ps1` + `install.ps1` cache read** (G8): at the start
  of the install flow, both scripts read `state/auto-update-check.json`
  and skip the GitHub call if the cache is < 6h old. The cache also
  persists the asset URLs so even the asset lookup is short-circuited.
  A fresh install + re-install within 6h no longer re-resolves the
  release from GitHub.
- **`install-deps.ps1` package manager priority** (G10): if winget is
  not on PATH, the script walks `winget > choco > scoop > direct` in
  order and uses the first one available. The `install_fallbacks`
  field in `_meta.json` documents the choco / scoop / direct-URL
  alternatives for each dep.
- **Better PS5.1 error message** in `Vortex.psm1` (G9): the throw on
  `PowerShellVersion` < 7 now points the operator at
  `install-powershell7.ps1` so a fresh Windows install knows how to
  bootstrap itself.
- **Skill `.gitignore` tightened** (G6): added `Vortex.dll`,
  `Vortex.psm1`, `Vortex.psd1`, `ijwhost.dll` to the ignore list so a
  contributor who accidentally runs `src/build.ps1` from inside the
  skill folder doesn't pollute the repo. Also added `*.tmp`, `*.bak`,
  `*.orig`, `ehthumbs.db`, `ehthumbs_vista.db`.

### Engine dependency
- Requires [vortex-os-dotnet v0.2.3](https://github.com/Cloudmeru/vortex-os-dotnet/releases/tag/v0.2.3)
  which adds the `Get-VortexVersion` cmdlet, the `--vector-hydrate`
  command, the `worker.packager` audit lines, the FileLock-based
  Inspector write, and the `RunChecks` refactor (G7).

## [0.2.2] - 2026-08-27

### Added
- **Multi-user team mode (PRD-10).** When two or more operators share a
  VORTEX_HOME, each one gets their own per-user shards for the audit log,
  HITL pending approvals, in-progress dispatches, and tasks. Deliverables
  stay shared so the team can see everyone's output in one place.
- **`setup-team.ps1`** — interactive + `-Yes` + `-Verify` modes. Writes
  `$VORTEX_HOME/.vortex/config.json` (the engine reads it at startup) and
  creates the per-user subdirs under `state/`, `memory/`, `tasks/`.
- **`lib/Vortex.Streamer.psm1`** — the operator-facing streaming console.
  - `Start-VortexStream -TaskId <id>` — attaches a FileSystemWatcher (with
    a 2s polling fallback) to `state/<user>/in_progress/<id>/` and prompts
    y/n/q for each new `.partial` file.
  - `Stop-VortexStream -TaskId <id>` — detach.
  - `Send-VortexHint -TaskId <id> -Text "..."` — append to `.hints.jsonl`.
  - `Get-VortexStream` — list all in-progress dispatches.
- **`skill.ps1` short-circuits** the streaming flags (`--stream-list`,
  `--stream <id>`, `--stream-stop <id>`, `--hint <id> --text "..."`) so
  they don't need to round-trip through the engine for every keystroke.
  `--stream-list` delegates to the engine so the output matches the
  canonical `(no in-progress dispatches)` line.

### Changed
- **`--audit-trail`** now accepts `--user <name>` and `--all-users`
  filters so an operator can inspect their own shard or the team-wide
  audit trail across all users.
- **`--stream-list` output** adds an `in_progress: <path>` line so the
  operator knows where the `.partial` files live (and so the test harness
  can assert the path).

### Engine dependency
- Requires [vortex-os-dotnet v0.2.2](https://github.com/Cloudmeru/vortex-os-dotnet/releases/tag/v0.2.2)
  which adds `--team-config`, `--stream-list`, `--stream`, `--stream-stop`,
  `--hint`, `--stream-finalize`, the `FileLock` + `StreamSink` libs, and
  per-user sharding via `PathResolver::ApplyTeamConfig`. The engine reads
  `.vortex/config.json` at startup and re-resolves paths if team mode
  changes between runs.

## [0.2.1] - 2026-08-27

### Added
- **11 additional reference plugins** under `plugins/` (total 17 plugins):
  - `audio-music` — background music loops
  - `audio-voice` — text-to-speech narration
  - `image-cover` — cover art
  - `image-map` — map / location art
  - `code-python` — Python code generation
  - `video-hailuo` — cinematic video clips
  - `video-animator` — animation / motion graphics
  - `data-researcher` — web research + report synthesis
  - `data-analyst` — data crunching + chart generation
  - `design-mockup` — UI mockups + design notes
  - `media-sqlite` — local SQLite wrapper (no LLM)

### Engine dependency
- Requires [vortex-os-dotnet v0.2.1](https://github.com/Cloudmeru/vortex-os-dotnet/releases/tag/v0.2.1)
  which adds the `--plugin-install <github-url>` command. Download + install
  community plugins from any GitHub repo that follows the plugin contract.

## [0.2.0] - 2026-08-27

### Added
- **Engine plugin system (PRD-11).** The engine now discovers and invokes
  user-installed plugins instead of hard-coding worker types. A new worker
  is now a 30-minute PowerShell plugin instead of a 3-day engine fork.
- **`plugins/` directory with 6 reference plugins** (each is a
  `plugin.json` manifest + `invoke.ps1` worker):
  - `text-writer` / `text-editor` — LLM-backed prose generation and editing
  - `audio-foley` — foley sound effects (stub: silent WAV so the
    contract is satisfied without an API key)
  - `image-portrait` — character portraits (stub: 1x1 PNG)
  - `code-typescript` — TypeScript code generation via MiniMax-Text-01
  - `media-ffmpeg` — pure-PowerShell shim around the local ffmpeg binary
    (no LLM)
- **`plugin-sdk/Vortex.Plugin.psm1`** — the SDK for plugin authors.
  Exports 5 functions: `Get-VortexPluginInput`, `Test-VortexPluginInput`,
  `Write-VortexPluginOutput`, `Invoke-MiniMaxLLM`, `Write-VortexPluginLog`.
- **New engine commands**: `--plugins-list`, `--plugins-info <name>`,
  `--plugin-test <name>`, `--plugin-remove <name>`, `--plugin-invoke <name>`.
- **New PowerShell cmdlet**: `Get-VortexPlugin` (alias for
  `--plugins-list` / `--plugins-info`).
- **Plugin discovery**: two scopes merged with user-scope-wins
  (`$VORTEX_HOME/plugins/` overrides `<skill>/plugins/`).
- **Plugin audit**: every `plugin_invoke` + `plugin_test` is logged to
  `memory/audit.jsonl` with `gate_id=<plugin name>` for the audit viewer.

### Engine dependency
- Requires [vortex-os-dotnet v0.2.0](https://github.com/Cloudmeru/vortex-os-dotnet/releases/tag/v0.2.0)
  (auto-updated on next `skill.ps1` invocation, or run
  `skill.ps1 --recover-engine` to force the install).

### Compatibility
- v0.2.0 engine is forward-compatible with v0.1.x skills (the 5 new
  commands are no-ops for older clients).
- v0.2.0 skill is forward-compatible with v0.1.x engines (older
  engines don't know about the plugin commands, but every existing
  command still works unchanged).

## [0.1.12] - 2026-08-27

### Added
- **`lib/Vortex.AuditViewer.psm1`** (new, ~13 KB). The PowerShell
  viewer for the VORTEX-OS audit log. Exports `Get-VortexAuditTrail` with
  six output formats (`table` / `tree` / `selfheal` / `hitl` / `json`
  / `html`) and five filters (`-Project` / `-Task` / `-Agent` /
  `-Severity` / `-Since` / `-Last`). The viewer reads
  `$env:VORTEX_HOME\memory\audit.jsonl` and is fully backward-compatible
  with the v0.1.10 log schema (missing fields are returned as empty).
- **`--AuditFormat` flag on `skill.ps1`.** Short-circuits `--audit-trail`
  to the viewer before the engine's basic dump can mix with the rich
  output. Single-word flag (no alias needed). Default format is `table`.
- **`--project=<slug>`, `--task=<id>`, `--agent=<name>`, `--severity=<lvl>`,
  `--since=<iso>`, `--last=<n>` filters.** All forwarded to the
  viewer's `-Project` / `-Task` / `-Agent` / `-Severity` / `-Since`
  / `-Last` parameters.

### Changed
- **Removed `[string] $Project` from `skill.ps1`.** It was greedily
  binding the engine's `--project` arg (a known PowerShell param-auto-
  binding pitfall), which broke `--cost-report --project <slug>` and
  other dispatch commands. Project name is now communicated exclusively
  via `$env:VORTEX_PROJECT` (read by the engine in `ResolveProjectName`).
- **`skill.ps1` version bump** to 0.1.12. Requires engine v0.1.11+ for
  the new audit fields (older engines still work — the viewer treats
  missing fields as empty).
- **`SKILL.md` + `_meta.json` + `CHANGELOG.md` version bump** to 0.1.12.

### Engine dependency
- Requires [vortex-os-dotnet v0.1.11](https://github.com/Cloudmeru/vortex-os-dotnet/releases/tag/v0.1.11)
  (auto-updated on next `skill.ps1` invocation, or run
  `skill.ps1 --recover-engine` to force the install).

### Compatibility
- v0.1.11 engine is forward-compatible with v0.1.10 viewers (the
  extra fields are simply ignored).
- v0.1.12 viewer is backward-compatible with v0.1.10 engines (missing
  fields are returned as empty strings / empty arrays).

## [0.1.10] - 2026-08-27

### Added
- **`--health` flag on `skill.ps1`.** Prints the active tier (engine
  available / not available) and recovery hints. Exits 0 regardless
  of engine state. Works even when the engine is missing.
- **`--recover-engine` flag on `skill.ps1`.** Retries `install.ps1` and
  re-detects the engine. Use `--recover-engine -Force` to skip the 6h
  auto-update rate-limit cache. Useful when the initial install failed
  (network blip, GitHub rate-limit, OneDrive ghost) and you want to
  retry without manually re-running `install.ps1`.
- **`--no-engine` flag on `skill.ps1`.** Forces Tier 1 (engine) to be
  considered unavailable even if installed. Used for testing the Tier 2
  (LLM-as-engine) path.
- **`references/LLM-FALLBACK.md`** (163 lines) — the Tier 2 recipe. When
  the engine is unavailable and the dispatcher is an LLM-coding-agent,
  the LLM reads this file to act as the engine for one dispatch. The
  recipe is procedural, deterministic, and walks through reading the
  objective, planning the deliverables, running the 4-tier chain, the
  self-heal loop, the 3-gate HITL pattern (with the CRITICAL moral
  hinge that must NOT be auto-approved), and writing the manifest.
- **`verify.ps1` v0.1.10 file-I/O checks** (4 new checks, run before
  the engine verify): LLM-FALLBACK.md exists and is >= 50 lines;
  `skill.ps1` declares `$Health`, `$RecoverEngine`, `$NoEngine`; `--health`
  reports `AVAILABLE`; `--no-engine` shows the Tier 2 banner with the
  LLM-FALLBACK pointer. If any of these fail, the engine verify is
  skipped (no point running it if the skill is broken).

### Changed
- **Version bump** to 0.1.10.
- **`skill.ps1` routing refactored.** The PowerShell shell remains
  strictly a thin routing layer; no parallel PowerShell implementation
  of any command (per user direction). New: `Show-Tier2Banner` function
  (defined at the top of the script for hoisting) prints a clear error
  when the engine is missing and points the user to `--recover-engine`
  and the LLM-FALLBACK recipe. The auto-update + install + import
  + dispatch flow is preserved.
- **`_meta.json`** version 0.1.7 → 0.1.10; added `llm_fallback_recipe`
  file entry and 3 new capabilities (`engine-health-check`,
  `engine-recovery`, `llm-fallback-recipe`).

### Architecture note (per user direction 2026-08-27)
- The earlier 3-tier design (PowerShell shell + C++ engine + LLM
  fallback) had a "Tier 1 PowerShell-only re-implementation of 14
  commands" idea. **This was rejected** by the user because a parallel
  PowerShell implementation of the same commands would be a second
  engine to maintain — no shared code, no shared tests, long-term
  divergence risk.
- The 2-tier design is now canonical: **Tier 1 = the C++ engine
  (always required for production). Tier 2 = the LLM-as-engine
  fallback (recipe only, for the rare case the engine is missing and
  the dispatcher is an LLM-coding-agent).**
- The PowerShell `skill.ps1` is now strictly routing: find / install
  / load the engine; forward argv; show the Tier 2 banner if the
  engine is missing. No `lib/PS-Only/*.ps1` exists.

### Compatibility
- **No engine change** required. Engine v0.1.9 (or newer) is unchanged.
- The 33 PowerShell end-to-end tests in
  `vortex-os-dotnet/tests/test_engine.ps1` still pass.
- The engine verify at the end of `verify.ps1` still runs and reports
  the same checks as v0.1.7.

## [0.1.7] - 2026-08-22

### Added
- **`walkthrough/`** — visual HTML walkthrough. 11 slides, Times New Roman, palette #18 (铂金白金). Open `walkthrough/index.html` in a browser, or run `walkthrough/record-to-mp4.ps1` to stitch into an MP4 via headless Edge + ffmpeg. ~5-minute read.
- **`uninstall.ps1`** — clean removal. Dry-run by default; flags `-Engine` (remove engine + module from `Documents\PowerShell\Modules\Vortex`), `-State` (remove `%APPDATA%\Vortex-OS`), `-All` (both). The skill folder itself is never auto-deleted — the operator removes it by hand.
- **`references/architecture.md`** — 7 Mermaid architecture diagrams (big picture, 4-tier chain, storage split, install flow, dispatch + HITL flow, auto-update, data lifecycle) plus a component-by-component reference table. The companion to the prose in `references/INSTRUCTIONS.md`.
- **`idea-future-recommendations.md`** — 18 prioritized next-version items, 12 known gaps, 5 open questions. The Phase 1 plan that drove the v0.1.7 work.
- **`idea-architecture-decisions.md`** — 15 Architecture Decision Records (engine choice = .NET 10 C++/CLI, two-root storage, user-scope install, self-bootstrapping, per-project subfolders, etc.). Supersedes earlier design discussions.
- **`idea-faq-and-pitfalls.md`** — 30+ Q&As across 10 categories (install, storage, HITL, self-heal, manifest, audio, etc.). The "why does it do X?" file.
- **`templates/episode_pattern.json`** — Golden Path template for episode-style dispatches. Read by the engine when `--dispatch-template` is passed (engine-side support lands in v0.1.9).
- **`SKILL.md` Skill Anatomy table** now lists the walkthrough, the 3 idea docs, the Mermaid reference, `uninstall.ps1`, and the templates folder.

### Changed
- **Version bump** to 0.1.7.

## [0.1.6] - 2026-08-22

### Changed
- **Skill description rewritten to be capability-driven and universal.**
  The frontmatter `description` and `_meta.json.description` no
  longer mention specific products (VibeOS, WebSims, Hailuo,
  ffmpeg, MiniMax, named universes) — they describe the
  orchestration capabilities (4-tier chain, continuity
  enforcement, self-healing prompts, HITL approval, per-agent
  audit log, episodic Golden Path templates) and the observable
  prompt characteristics that should trigger the skill
  (multi-domain work, continuity requirements, HITL needs,
  audit requirements, long-running scope, in-house execution).
  This makes the skill detect the right prompts regardless of
  the specific product / domain the user is working in.
- **`SKILL.md` body** — the "Trigger Conditions" section
  rewritten to match the new capability-driven framing.
- **`display_name`** updated from "Native Autonomous Studio
  Command Center" to "Multi-Agent Orchestration Engine" (the
  product-specific framing is gone; the new name describes
  the orchestration pattern, not the use case).

## [0.1.5] — 2026-08-22

### Added
- **`auto-update.ps1`** — engine self-updater. Queries GitHub for
  the latest `vortex-os-dotnet` release (rate-limited to once per
  6h per `VORTEX_HOME`) and calls `install.ps1` if a newer
  version is available. Called automatically by `skill.ps1` on
  every invocation. Opt out with `$env:VORTEX_NO_AUTO_UPDATE=1`.
  Bypass the rate limit with `-Force`. Dry-run with `-DryRun`.
- **`-Project` parameter on `skill.ps1`** — overrides the project
  name. The engine writes deliverables to
  `$VORTEX_HOME\deliverables\<project>\` instead of the flat
  root. The project name is also auto-derived from
  `$env:VORTEX_PROJECT`, the parent dir of `--dispatch-master`,
  or the objective's filename if no other source.
- **`-AdoptFlat` switch on `migrate-state.ps1`** — moves legacy
  flat `deliverables/` files (from skill <= v0.1.4) into
  `deliverables/_unfiled/` so the new per-project layout can
  take over without losing data.

### Changed
- **Deliverables are now grouped by project** (engine v0.1.8).
  Outputs from a dispatch land in
  `$VORTEX_HOME/deliverables/<project>/` instead of the flat
  `deliverables/` root. The project name is auto-derived from
  the objective file path, the `-Project` flag, or
  `$env:VORTEX_PROJECT`. Multiple sessions of the same project
  no longer clobber each other. The engine refuses to overwrite
  existing deliverables; the user must pick a new project name
  (e.g. `-Project trial_of_echoes_v2`) or manually clear the
  project's deliverables folder first.
- **`SKILL.md` updated** with a new "Where is my data stored?"
  section that shows the per-project layout, plus a new
  "Auto-update of the .NET engine" section.
- **`_meta.json`** gets a new `auto_update` field and a richer
  `data_location.deliverables_layout` field.

## [0.1.4] — 2026-08-22

### Changed (BREAKING for the data location, INTENTIONAL)
- **Runtime state now lives in `$env:VORTEX_HOME`** (default
  `%APPDATA%\Vortex-OS\`), not in the skill folder. The engine
  v0.1.7 splits its root paths into two: `SkillDir` (mutable,
  where `agents/` + `templates/` live) and `HomeDir` (durable,
  where `state/` + `memory/` + `swarms/` + `deliverables/` +
  `tasks/` live). The skill folder is now just the "installer +
  manifest" — your deliverables, audit log, swarms, HITL state,
  and memory are durable and live outside the skill.
- **User deliverables survive skill updates.** When you re-clone
  the skill (or pull a new version), nothing under
  `%APPDATA%\Vortex-OS\` is touched. The `git pull` only replaces
  the scripts, the agent manifests, and the docs.
- **Multiple skill instances on the same machine share state.**
  If you have the VORTEX-OS skill deployed to both `minimax code`
  and `hermes` on the same Windows host, they read and write the
  same `%APPDATA%\Vortex-OS\` (since both fall back to the
  same default). A dispatch from one agent shows up in the audit
  log the other agent reads.
- **`SKILL.md` and `INSTRUCTIONS.md` updated** to document
  `VORTEX_HOME`, the new `data_location` field, the migration
  strategy, and the new `migrate-state.ps1` script.

### Added
- **`migrate-state.ps1`** — one-time manual migration. Copies
  legacy `deliverables/`, `memory/`, `swarms/`, `state/`,
  `tasks/` from the skill folder to `$env:VORTEX_HOME`.
  Idempotent (skips subdirs that already exist at the target).
  Supports `-WhatIf` (dry-run) and `-DeleteSource` (remove the
  originals after verifying the copy).
- **`_meta.json.data_location`** field describing the new
  two-root model.

### Migration
- **Engine does NOT auto-migrate.** Run `migrate-state.ps1` once
  after upgrading to skill v0.1.4+. Old data is left in place
  after migration so the operator can verify before deleting.

## [0.1.3] — 2026-08-22

### Changed
- **System dependencies are now winget-only.** The previous
  `_meta.json.system_tools` listed `python3`, `jq`, `sqlite3`,
  `ffmpeg` as generic tool names. Code agents reading that list
  sometimes routed the install through `pip` (which is wrong for
  Windows + wrong for a .NET-only project). The skill now exposes
  `_meta.json.winget_install_ids` with the exact `winget` package
  IDs (`SQLite.SQLite`, `Gyan.FFmpeg`) so the install goes through
  Windows Package Manager, not pip / brew / apt.
- **Dropped dead tool checks from the engine.** `jq` and `python3`
  were in the verifier's "Tool check" step, but the engine is pure
  .NET 10 / C++/CLI and never invokes them. The check now lists
  only `sqlite3` (required, for VectorHydrate) and `ffmpeg`
  (optional, for generated audio deliverables). The engine v0.1.6
  release picks up this change.

### Added
- **`install-deps.ps1`** — a winget-based dep installer. Dry-run by
  default; pass `-Install` to actually install. Reads the dep list
  from `_meta.json.winget_install_ids` (single source of truth).
  Skips deps already on PATH. Prompts for confirmation before
  running `winget install` unless `-Force` is passed.

## [0.1.2] — 2026-08-22

### Changed
- **Skill structure follows the Mavis/Claude 3-level loading convention.**
  `INSTRUCTIONS.md` (the 19 KB operator playbook) moved to
  `references/INSTRUCTIONS.md` so the agent can load it on demand
  instead of every time the skill triggers. `SKILL.md` is now the
  lean entry point with a clear "Skill Anatomy" map pointing at every
  other file and its purpose.
- `SKILL.md` frontmatter description rewritten to be more
  discoverable: more trigger words (multi-agent orchestration,
  hierarchical task decomposition, MiniMax native media, continuity
  enforcement, auditable LLM, HITL, narrative series, procedural
  media), tighter scope statement, and clearer do-not-trigger list.
- Added a **Quick Start** callout at the top of `SKILL.md` so a code
  agent (minimax code, hermes, etc.) can fire `verify.ps1` and
  `skill.ps1 --agents-discover` without reading the rest of the file.
- Added a **Skill Anatomy** table mapping every file in the repo to
  its purpose + when to read it. Cross-references `README.md` (user
  overview) and `COMPATIBILITY.md` (multi-code-agent contract).
- Added a **Command reference** one-liner table so the agent doesn't
  have to dig through `README.md` for the common commands.

### Migration notes
- Existing agents / scripts that read `INSTRUCTIONS.md` directly
  should update their path to `references/INSTRUCTIONS.md`. The
  `_meta.json.llm_instructions` field already points to the new path.
- The 14-section structure of the operator playbook is unchanged —
  only the path moved. No content was deleted or rearranged.

## [0.1.1] — 2026-08-22

### Changed (BREAKING for the bundled-engine layout)
- The skill no longer bundles the .NET 10 C++/CLI engine
  (`Vortex.dll`, `Vortex.psm1`, `Vortex.psd1`, `ijwhost.dll`). Those
  four files are now downloaded from the public GitHub release of
  [Cloudmeru/vortex-os-dotnet](https://github.com/Cloudmeru/vortex-os-dotnet)
  the first time the skill runs, and installed to a PowerShell
  user-scope module folder. **No admin / system changes are required.**
- `skill.ps1` and `verify.ps1` are now **self-bootstrapping**: they
  detect a missing engine and run the installer before dispatching.
  Re-runs are free; the install is idempotent.
- The install path is derived from `$env:PSModulePath` + the canonical
  `$HOME\Documents\PowerShell\Modules` and gracefully falls back on
  machines with OneDrive-redirected Documents folders.
- The skill sets `$env:VORTEX_SKILL_ROOT` to the skill folder so the
  engine knows where `agents/`, `state/`, `memory/`, and
  `deliverables/` live. This matches the bash version's
  `cd $(dirname $0) && pwd` semantics and means state files end up
  in the skill folder rather than in the user-scope module folder.

### Added
- `install.ps1` — the engine installer. Downloads the 4 engine files
  from `GET https://api.github.com/repos/Cloudmeru/vortex-os-dotnet/releases/latest`
  (unauthenticated; 60 req/hr per IP, fine for one install). Idempotent.
  Honors `$env:VORTEX_VERSION` and `$env:VORTEX_MODULE_PATH` for pinning
  and custom install locations.
- `COMPATIBILITY.md` — documentation for code agents (minimax code,
  hermes, aider, continue.dev, cline, Claude Code, GitHub Copilot
  Coding Agent) on how to drive the skill. Documents the 4-line install
  contract: any agent that can spawn a `pwsh` child process can use
  VORTEX-OS — no SDK, no auth, no registration.
- `_meta.json.install.*` fields describing the self-bootstrapping flow
  for code agents that introspect the package.

### Removed
- Bundled `Vortex.dll`, `Vortex.psm1`, `Vortex.psd1`, `ijwhost.dll` from
  the skill repo. These are now downloaded at install time from the
  upstream release. (They remain in the .NET source repo as build
  outputs and as release assets.)
- The `lib\*.h` files (those are .NET engine source, not part of the
  skill anymore). The verifier was updated accordingly (see
  `vortex-os-dotnet` 0.1.2 release notes).

## [0.1.0] — 2026-08-22

### Added
- Initial release of the VORTEX-OS skill package. Bundled the .NET 10
  C++/CLI engine + 3 supervisor/inspector agent manifests + a one-shot
  CLI (`skill.ps1`) and a post-upload verifier (`verify.ps1`).
- 4-tier agent orchestration: General Manager → Store Supervisor →
  Shift Supervisor → Crew, with HITL gating at every high-stakes
  action.
- Skill ships a one-shot CLI that talks to the bundled
  `Vortex.dll` engine.
