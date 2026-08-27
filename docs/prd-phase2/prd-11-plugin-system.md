# PRD-11 — Engine Plugin System

**Status:** Draft · Phase 2 (user said "ok agree, suggest me several plugins. if possible, convert all current possibilities to plugin. so you have core engine, then plugin system. make prd first")
**Owner:** VORTEX-OS maintainers
**Source:** `idea-future-recommendations.md` item 11

---

## 1. Context

The engine's "worker" types — writer, audio, image, code, video, researcher, analyst, designer — are hard-coded in the C++/CLI source. To add a new worker type, you fork the engine, write a new `lib/Workers/<name>.cpp`, add it to `build.ps1`, and ship a new release. That's a 3-day cycle for a single engineer.

The user's ask: **convert all current possibilities to plugins, so we have a core engine + plugin system.** Plugins are PowerShell scripts that the engine loads at runtime. Adding a new worker becomes a 30-minute cycle (write a 50-line .ps1, drop it in `plugins/`, restart the skill).

This also unlocks the **option C strategy** from PRD-08: with a plugin system, the same engine core can run any LLM provider (MiniMax, OpenAI, Anthropic, local models), any image gen, any audio gen, any code gen — the engine doesn't care. The community can write plugins without touching the engine source.

## 2. Goals

1. **A new worker type ships in 30 minutes, not 3 days.** Write a 50-line .ps1, drop it in `plugins/`, done.
2. **The engine core stays small and stable.** Workers move out of the C++ source into plugins.
3. **Plugins are first-class discoverable.** `--plugins-list` shows what ships + what the user has installed; `--plugins-info <name>` dumps the manifest.
4. **Plugins can be either PowerShell scripts OR executable binaries.** The contract is the JSON-in / JSON-out interface, not the implementation language.
5. **The 8 current worker types (writer, audio, image, code, video, researcher, analyst, designer) ship as reference plugins** so the engine has zero hard-coded workers.
6. **A plugin can be a "shim"** that wraps a non-PowerShell tool — e.g. an `ffmpeg` plugin that doesn't need any LLM, just calls the local ffmpeg binary.

## 3. Non-goals

- **A web-based plugin registry.** Plugins are local files in `plugins/`. The community shares them via GitHub, npm, whatever — not via a VORTEX-OS-managed marketplace.
- **Plugin signing / sandboxing.** A plugin is just code the user runs. We document the trust model: "only install plugins from sources you trust." Future phase may add a permissions model.
- **Hot-reload.** Plugins are loaded at skill startup. Editing a plugin requires re-invoking the skill.
- **Plugin-to-plugin composition.** A plugin is a single worker. The 4-tier chain (planner → supervisor → shift → workers) stays in the engine.
- **Replacing the engine's 4-tier dispatch logic.** That's the orchestrator's job, not a plugin's.

## 4. Design

### 4.1 Plugin contract

A plugin is a folder with two files:

```
plugins/
  audio-foley/
    plugin.json         # manifest: name, version, capabilities, inputs, outputs
    invoke.ps1          # the worker (or a launcher for a binary)
```

`plugin.json`:

```json
{
  "name": "audio-foley",
  "version": "1.0.0",
  "author": "VORTEX-OS",
  "license": "MIT",
  "description": "Generate foley sound effects (footsteps, fabric, impacts) from natural-language prompts.",
  "capability": "audio",
  "inputs": {
    "prompt":     { "type": "string",  "required": true,  "description": "Natural-language description of the sound" },
    "duration_s": { "type": "integer", "required": false, "default": 5, "description": "Length of the output in seconds" },
    "format":     { "type": "string",  "required": false, "default": "wav", "enum": ["wav", "mp3", "flac"] }
  },
  "outputs": {
    "file": { "type": "string", "description": "Absolute path to the generated audio file" },
    "duration_s": { "type": "number", "description": "Actual duration in seconds" }
  },
  "command": {
    "type": "powershell",
    "entry": "invoke.ps1",
    "timeout_s": 300
  },
  "env": {
    "VORTEX_PLUGIN_NAME":     "audio-foley",
    "VORTEX_PLUGIN_VERSION":  "1.0.0",
    "VORTEX_PLUGIN_INPUTS":   "<json-string-of-inputs>"
  }
}
```

The engine invokes the plugin by:

1. Reading `plugin.json` to find `command.entry` and `command.timeout_s`.
2. Setting the `VORTEX_PLUGIN_*` env vars.
3. Writing the inputs to a temp file at `$VORTEX_HOME/state/plugin_inputs/<name>_<ts>.json`.
4. Running the command (PowerShell script, binary, or anything else).
5. Reading the output JSON from `$VORTEX_HOME/state/plugin_outputs/<name>_<ts>.json` (the plugin writes it before exiting).
6. Returning the output to the 4-tier chain.

### 4.2 Discovery

Two plugin locations, in priority order:

1. `$VORTEX_HOME/plugins/` — user-scope (survives skill updates)
2. `<skill_folder>/plugins/` — skill-scope (ships with the skill; replaced on update)

The engine scans both on startup and merges them. Conflicts (same `name` in both) → user-scope wins, with a warning logged.

### 4.3 The 8 reference plugins to ship

The user asked for "all current possibilities" as plugins. Here are the 8 + 2 wrap-style ones:

| Plugin name | Capability | What it does | LLM / tool |
|---|---|---|---|
| `text-writer` | text | Long-form prose (chapters, articles, scripts). | MiniMax LLM |
| `text-editor` | text | Polish / rephrase / summarize an existing text. | MiniMax LLM |
| `audio-foley` | audio | Sound effects from natural-language prompts. | MiniMax music |
| `audio-music` | audio | Background music loops. | MiniMax music |
| `audio-voice` | audio | Voice-over / narration. | MiniMax TTS |
| `image-portrait` | image | Character portraits. | MiniMax image |
| `image-cover` | image | Cover art for the deliverable. | MiniMax image |
| `image-map` | image | Map / location art. | MiniMax image |
| `code-typescript` | code | TypeScript code generation. | MiniMax LLM |
| `code-python` | code | Python code generation. | MiniMax LLM |
| `video-hailuo` | video | Cinematic video clips. | MiniMax-H3 / Hailuo-2.3 |
| `video-animator` | video | Animation / motion graphics. | MiniMax-H3 |
| `data-researcher` | research | Web search + document analysis. | MiniMax LLM + search API |
| `data-analyst` | data | Data crunching, chart generation. | MiniMax LLM + Python (subprocess) |
| `design-mockup` | design | UI mockups, design specs. | MiniMax image |
| `media-ffmpeg` | media | Local ffmpeg wrapper (audio chopping, format conversion). | ffmpeg binary (no LLM) |
| `media-sqlite` | data | Local SQLite wrapper (memory persistence). | sqlite3 binary (no LLM) |

That's 17 plugins. They all share the same JSON-in / JSON-out contract.

**After this lands, the engine has zero hard-coded worker types.** A new worker is a 30-minute job.

### 4.4 The engine's new role

The engine stops dispatching to specific worker implementations. Instead it:

1. Parses the agent manifest's `implements` field (already a string) and looks up the matching plugin.
2. Wraps the plugin invocation in a HITL checkpoint if `high_stakes: true`.
3. Pipes the output through the Continuity Engine (the only thing the engine still does directly).
4. Writes the result to `swarms/active_<id>/deliverables/`.
5. Logs to `memory/audit.jsonl`.

The engine shrinks (we remove the worker .cpp files) and the plugin system grows. Net code is roughly the same, but the boundary is much cleaner.

### 4.5 Plugin SDK

A tiny PowerShell module at `<skill_folder>/plugin-sdk/Vortex.Plugin.psm1` that gives plugin authors:

```powershell
# Read the inputs the engine wrote
Import-Module Vortex.Plugin
$inputs = Get-VortexPluginInput

# Validate the required inputs
Test-VortexPluginInput -Schema $manifest.inputs

# Do the work (call any LLM / tool)
$result = Invoke-MiniMaxLLM -Prompt $inputs.prompt

# Write the output
Write-VortexPluginOutput -File $outputPath -DurationS $result.duration
```

`Vortex.Plugin.psm1` is ~150 lines of PowerShell that wraps the temp-file + env-var I/O. Plugin authors don't need to know the file paths; they just call `Get-VortexPluginInput` / `Write-VortexPluginOutput`.

## 5. API surface

### New commands (skill-side + engine-side)

```powershell
# List installed plugins
pwsh -NoProfile -File .\skill.ps1 --plugins-list

# Dump a plugin's manifest
pwsh -NoProfile -File .\skill.ps1 --plugins-info audio-foley

# Test a plugin (runs it with sample inputs)
pwsh -NoProfile -File .\skill.ps1 --plugin-test audio-foley --input '{"prompt":"footsteps on gravel","duration_s":5}'

# Install a plugin from a GitHub URL (downloads + drops into $VORTEX_HOME/plugins/)
pwsh -NoProfile -File .\skill.ps1 --plugin-install https://github.com/somebody/vortex-plugin-foo

# Remove a user-scope plugin
pwsh -NoProfile -File .\skill.ps1 --plugin-remove audio-foley
```

### New env vars

```powershell
$env:VORTEX_PLUGIN_TIMEOUT  # default plugin timeout in seconds (default 300)
$env:VORTEX_PLUGIN_PATH      # extra directory to scan for plugins (default: $VORTEX_HOME/plugins + <skill>/plugins)
```

### File layout

```
VORTEX_HOME/
  plugins/                  # user-scope (created on first use)
    <user-installed-plugin>/plugin.json + invoke.ps1
  state/
    plugin_inputs/          # temp input files (auto-cleaned after 24h)
    plugin_outputs/         # temp output files (auto-cleaned after 24h)
    plugin_logs/            # plugin stdout/stderr (auto-cleaned after 7d)

<skill_folder>/
  plugins/                  # skill-scope (ships with the skill)
    text-writer/plugin.json + invoke.ps1
    text-editor/plugin.json + invoke.ps1
    audio-foley/plugin.json + invoke.ps1
    ... (17 plugins total)
  plugin-sdk/
    Vortex.Plugin.psm1      # the SDK plugin authors import
```

## 6. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A buggy plugin crashes the engine | High | High | The engine invokes plugins via `Process::Start` with stdout/stderr captured. A plugin crash logs to `state/plugin_logs/` and the engine treats it as a worker failure (fail-closed: the dispatch aborts, the operator is alerted). |
| Plugins become a security liability (a user installs a malicious plugin from the internet) | High | High | Document the trust model: "plugins run with the same privileges as the skill." Future phase may add a permission manifest (`{"permissions": ["network", "filesystem:read", "filesystem:write"]}`) and a sandbox. |
| Plugin contract drift | Medium | Medium | The contract is in `<skill>/plugin-sdk/Vortex.Plugin.psm1`. Bump its `MAJOR` version on breaking changes; document the migration path. |
| The 17 reference plugins are a lot of code to maintain | High | Medium | Each plugin is ~50 lines of PowerShell + a 30-line JSON. Total: ~1300 lines for all 17. Shared helpers in `plugin-sdk/Vortex.Plugin.psm1` keep them DRY. |
| Plugins can't easily be cross-platform (a Windows-only plugin breaks on Linux) | Medium | Low | Plugin authors document their platform requirements in `plugin.json` (`"platforms": ["windows", "linux"]`). The engine warns at startup if a plugin's platforms don't include the current OS. |
| A user accidentally ships a binary plugin (e.g. an .exe) and can't run it on macOS | Low | Low | Same as above. Document the platform check. |

## 7. Acceptance criteria

1. `--plugins-list` shows all 17 reference plugins + any user-installed ones.
2. A new user can copy any of the 17 reference plugin folders to `$VORTEX_HOME/plugins/`, and it works identically.
3. `--plugin-test audio-foley --input '{"prompt":"footsteps on gravel","duration_s":3}'` invokes the plugin and returns a result JSON.
4. The engine has zero worker .cpp files. All dispatch goes through plugins.
5. `verify.ps1` runs every reference plugin in `--plugin-test` mode (with mock inputs) and asserts the output schema is valid.
6. `idea-future-recommendations.md` item 11 → ✅ status. The engine binary shrinks by ~30% (worker code moves out).

## 8. Effort

- New `<skill>/plugin-sdk/Vortex.Plugin.psm1`: ~150 lines
- 17 reference plugins × 80 lines each: ~1400 lines
- Engine changes: remove worker dispatch, add plugin invocation, add plugin discovery. ~400 lines in `skill.cpp` + `lib/PluginInvoker.{h,cpp}` (new).
- New tests: ~300 lines (one per plugin + a regression test for the engine).
- Docs: `references/INSTRUCTIONS.md` updated with a "Writing a plugin" section; new `references/plugin-author-guide.md`.

**Total: ~2200 lines, but spread across 17 small files (plugins) + 1 new lib. 2 PRs (skill + engine). Tag bump to v0.2.0 (this is a major architectural change). ~2-3 weeks for a single engineer.**

## 9. Open questions

- **Q1.** Should plugins be installable from PSGallery (`Install-Module VortexPlugin.<name>`) in addition to GitHub URLs? — *Recommend: yes, but as a v0.2.x follow-up. Start with GitHub URLs.*
- **Q2.** Should the engine cache plugin manifests at startup (so a misbehaving plugin can't slow down the routing layer)? — *Recommend: yes, load all manifests in <100ms before any dispatch.*
- **Q3.** What's the plugin version policy? — *Recommend: semantic versioning. The engine pins a MAJOR version range (e.g. `^1.0.0`); breaking changes bump MAJOR.*
- **Q4.** Should plugins be able to chain (one plugin's output is another's input)? — *Recommend: no, not yet. The 4-tier chain in the engine is the composition layer. If a use case emerges, add it in v0.3.*
- **Q5.** Should the engine ship a default set of plugins, or only the core + let users install the workers they need? — *Recommend: ship all 17. The skill is most useful as a complete multi-domain orchestration tool; forcing users to install 17 plugins is friction.*

## 10. Suggested rollout

- **v0.2.0** — Engine core + plugin system + 5 reference plugins (text-writer, audio-foley, image-portrait, code-typescript, media-ffmpeg). Validate the contract.
- **v0.2.1** — Add the remaining 12 reference plugins.
- **v0.2.2** — Add `--plugin-install` (GitHub URL) and `--plugin-test`.
- **v0.2.3** — Community plugin showcase (a curated list in `docs/community-plugins.md`).
- **v0.3.x** — Plugin permissions, sandboxing, PSGallery publish.
