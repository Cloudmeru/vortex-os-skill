# VORTEX-OS Skill — Code Agent Compatibility

> The VORTEX-OS skill is **host-agnostic**. Any code agent that can spawn
> a PowerShell 7+ child process can drive it. This page lists the agents
> known to work, the install pattern for each, and the minimal contract
> a code agent must satisfy to use the skill.

---

## The install contract (in 4 lines)

A code agent only needs to be able to do this:

```powershell
Set-Location '<path to vortex-os-skill>'
pwsh -NoProfile -File .\skill.ps1 <any vortex args>
```

The first invocation **auto-installs** the engine (downloads from the
public GitHub release of `Cloudmeru/vortex-os-dotnet`, installs to
user-scope, no admin). Subsequent invocations are instant. Exit code
is the engine's exit code.

That's it. No registration, no auth, no system changes.

---

## Verified code agents

| Code Agent | Tested | How the agent invokes the skill |
|---|---|---|
| **minimax code** | ✅ | `pwsh -NoProfile -File ./skill.ps1 --agents-discover` (via the agent's run-shell tool) |
| **hermes** | ✅ (same install pattern) | `pwsh -NoProfile -File ./skill.ps1 ...` |
| **aider** | ✅ (manual, same pattern) | Add a shell alias in `.aider.conf.yml`, or call via the bash tool |
| **continue.dev** | ✅ (manual, same pattern) | Bind a slash command to a PowerShell run |
| **cline** | ✅ (manual, same pattern) | Add a `pwsh` command to the allowed-execute list |
| **Claude Code** | ✅ (manual, same pattern) | `!pwsh -NoProfile -File ./skill.ps1 ...` (Bash tool) |
| **GitHub Copilot Coding Agent** | ✅ (manual, same pattern) | In a workflow step: `pwsh -NoProfile -File ./skill.ps1 ...` |

> **For code agents reading this skill:** if you need to install
> system dependencies, use `winget install --id <winget_id>` — the
> canonical wrapper is `install-deps.ps1` in the skill folder. The
> authoritative list is at `_meta.json.winget_install_ids`. Do **not**
> route these through pip / brew / apt / choco — VORTEX-OS is a
> .NET-only project and does not need Python, jq, or any scripting
> runtime.

> **Verified** here means "we have actually driven `skill.ps1` from this
> agent class on a fresh Windows host and observed `verify.ps1` report
> `ALL VERIFICATION CHECKS PASSED` end to end." Other agents that can
> shell out to `pwsh` work the same way — there is no per-agent
> registration or hookup.

---

## What "compatible" means

A code agent is compatible with the VORTEX-OS skill when it can do all
of these:

1. **Spawn a PowerShell 7+ (Core) child process.** PowerShell 5
   (Windows PowerShell) is **not** supported because `Vortex.dll` targets
   .NET 10, which PS5 cannot load. Check that `pwsh.exe` is on `PATH`
   (or `$env:PWSH` points to it).
2. **Pass arguments to that process.** `pwsh -NoProfile -File skill.ps1
   --agents-discover` — standard `pwsh -File <script> <args>` semantics.
3. **Read the process's stdout and exit code.** `skill.ps1` writes the
   engine's output to stdout; the engine's exit code is the script's
   exit code.
4. **Persist working directory between invocations.** Not required for
   correctness (skill.ps1 is self-contained), but agents that maintain
   their own cwd get a slightly faster path because `$env:VORTEX_SKILL_ROOT`
   is set from the script's own `$PSScriptRoot`.

If your agent supports these four, it can use VORTEX-OS. There is no
host-specific glue code, no SDK to import, no manifest to register.

---

## How a code agent should drive the skill

### Step 1 — discover

```powershell
pwsh -NoProfile -File ./skill.ps1 --agents-discover
```

Returns 3 agents (`supervisor.store`, `supervisor.shift`,
`inspector.governance`) on stdout. Exit 0.

### Step 2 — lint

```powershell
pwsh -NoProfile -File ./skill.ps1 --agents-lint --all
```

Returns `LINT_OK: <path>` for each agent. Exit 0.

### Step 3 — write an objective to a file

The dispatcher expects a master objective as a file path. The agent
should write the user's natural-language objective to a temp file
(any path the agent can read back) and pass that path to
`--dispatch-master`. See `references/INSTRUCTIONS.md` §2 for a complete example.

### Step 4 — dispatch

```powershell
pwsh -NoProfile -File ./skill.ps1 --dispatch-master "<path-to-objective.md>"
```

This returns control to the agent after a few minutes (or seconds for
simple objectives). The engine writes intermediate state to
`<skill-folder>\state\`, `<skill-folder>\swarms\`,
`<skill-folder>\deliverables\`, etc.

### Step 5 — handle HITL halts

If the engine prints `PENDING_HUMAN: task_id=...` and exits with code
203, the agent must:

1. Surface the halt to the human user verbatim.
2. Wait for an `Approve <task_id>` or `Deny <task_id>` reply.
3. Re-invoke the skill with `--hitl-approve <task_id>` or
   `--hitl-deny <task_id>`.

The agent **must never auto-approve** even if the user has said "do
whatever you want" earlier — the HITL gate is the last line of defense
against runaway actions.

### Step 6 — collect results

```powershell
pwsh -NoProfile -File ./skill.ps1 --audit-trail
Get-ChildItem ./deliverables/
pwsh -NoProfile -File ./skill.ps1 --hitl-status
```

---

## Common pitfalls for code agents

| Pitfall | What happens | Fix |
|---|---|---|
| Code agent runs `pwsh` (PS5) instead of `pwsh` (PS7 Core) | Engine fails to load (`Add-Type` rejects .NET 10 DLL) | Use `pwsh` (the PS7+ binary), never the legacy `powershell` |
| Code agent is on Linux/macOS | `.NET 10 + C++/CLI + Windows-only ijwhost.dll` | Engine is Windows-only today; use a Windows runner (or wait for a future cross-platform build) |
| Code agent can't reach `api.github.com` | `install.ps1` fails with HTTP error | Configure a proxy via `$env:HTTPS_PROXY` or pre-stage the engine files into the user-scope module folder manually |
| Code agent has `$env:PSModulePath` locked to a OneDrive-broken path | `Import-Module Vortex` by name fails | `skill.ps1` and `verify.ps1` already handle this — they fall back to importing by full path and scan `$HOME\Documents\PowerShell\Modules` as well |
| Code agent tries to `Import-Module ./Vortex.psd1` from the skill folder | The skill no longer bundles `Vortex.psd1` (it's in user-scope) | `Import-Module Vortex` (no path) — the install step makes that work |

---

## Adding a new code agent

To verify a new code agent works with VORTEX-OS:

1. Clone this repo into a clean working directory.
2. From that directory, run `pwsh -NoProfile -File ./verify.ps1`.
   Confirm the verifier reports `ALL VERIFICATION CHECKS PASSED` and
   the engine was auto-installed.
3. Run `pwsh -NoProfile -File ./skill.ps1 --agents-discover`. Confirm
   3 agent rows on stdout.
4. Document the install pattern in this file (table above).
5. Open a PR.

There is no host SDK, no API key, no registration, no agent-specific
glue. If the agent can spawn `pwsh`, it works.
