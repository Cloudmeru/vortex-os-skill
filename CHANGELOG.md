# Changelog

All notable changes to the VORTEX-OS skill package are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
