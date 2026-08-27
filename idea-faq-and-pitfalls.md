# VORTEX-OS — FAQ & Common Pitfalls

> **Status:** Living document. Add to it whenever you hit something that took longer than 5 minutes to figure out.
> **Audience:** Anyone using or maintaining VORTEX-OS.
> **Scope:** Both [`vortex-os-dotnet`](https://github.com/Cloudmeru/vortex-os-dotnet) and [`vortex-os-skill`](https://github.com/Cloudmeru/vortex-os-skill).

This is the "stuff I wish someone had told me earlier" document. If you're stuck on something, look here first.

---

## Table of contents

- [Installation](#installation)
- [Data location](#data-location)
- [Runtime](#runtime)
- [The engine (C++/CLI)](#the-engine-ccli)
- [The skill (PowerShell)](#the-skill-powershell)
- [HITL gates](#hitl-gates)
- [OneDrive + Windows quirks](#onedrive--windows-quirks)
- [GitHub Actions / releases](#github-actions--releases)
- [Performance](#performance)
- [Security](#security)

---

## Installation

### Q: I just cloned the skill. What's the first command?

```powershell
cd path\to\vortex-os-skill
pwsh -NoProfile -File .\verify.ps1
```

This:
1. Checks the engine is installed (downloads it if not)
2. Verifies the system deps (`sqlite3` is required; `ffmpeg` is optional)
3. Runs all 8 checks (file presence, JSON validity, branding, agent discovery, agent lint, help banner, engine installation, tool check)

If everything is green, you're ready to dispatch. See `SKILL.md` for the Quick Start.

### Q: `winget` is not on my PATH. What do I do?

`winget` ships with Windows 10 1809+ and all Windows 11. If it's missing, install the **App Installer** from the Microsoft Store. After install, open a new PowerShell session and `winget --version` should work.

For older Windows (pre-1809), `winget` is not available. The skill's `install-deps.ps1` will print a clear "winget not on PATH" error in that case. The fix is to upgrade Windows or install `winget` manually.

### Q: The engine install fails with "Cannot find path" or "Access denied"

This is almost always **OneDrive Files-On-Demand** redirecting your `Documents` folder to `C:\Users\<user>\OneDrive\Documents`. The default `Documents\PowerShell\Modules` path then points to a "ghost" folder that exists in the registry but has no actual content.

**Fix:** the skill's `install.ps1` has a sentinel-subdir probe that detects this and falls back to the non-OneDrive path. If install still fails:

```powershell
# Check the path the engine would use
pwsh -NoProfile -File .\install.ps1 -Verbose

# If it says it's using the OneDrive path, override VORTEX_MODULE_PATH:
$env:VORTEX_MODULE_PATH = "$HOME\Documents\PowerShell\Modules"
pwsh -NoProfile -File .\install.ps1

# Or, if your OneDrive is broken, force the engine to use a different location:
$env:VORTEX_MODULE_PATH = 'D:\PowerShell\Modules'
pwsh -NoProfile -File .\install.ps1
```

### Q: I have both PS5 and PS7 installed. Which does the skill use?

The skill uses `pwsh` (PowerShell 7+). Make sure `pwsh` is on `PATH` (it should be if you installed PS7 with the default options). Run `pwsh --version` to verify.

If you have a `powershell` (no `pwsh`) command that runs PS5, the engine's `Vortex.psd1` will fail to load with a "compatible PowerShell editions" error. Use `pwsh` (not `powershell`) explicitly.

---

## Data location

### Q: Where are my deliverables?

By default: `%APPDATA%\Vortex-OS\deliverables\<project>\` (where `<project>` is auto-derived from the objective file path or your `-Project` flag).

```powershell
# Quick way to find all your project deliverables:
Get-ChildItem "$env:APPDATA\Vortex-OS\deliverables" -Directory

# Or, with a custom VORTEX_HOME:
Get-ChildItem "$env:VORTEX_HOME\deliverables" -Directory
```

### Q: I overwrote my project by accident. Can I recover?

**No** (the engine refuses to overwrite, so this shouldn't happen). If you want to redo a project, use `-Project <name>_v2` or `-Project <name>_redo`. The previous deliverables stay at the original project folder.

### Q: I have data in `deliverables/` (flat) from an old install. How do I move it?

```powershell
pwsh -NoProfile -File .\migrate-state.ps1 -AdoptFlat
```

This moves all loose files from `deliverables/` (top-level) into `deliverables/_unfiled/`. From there, you can manually file them into specific project folders.

### Q: Two code agents are writing to the same `VORTEX_HOME` simultaneously. Is that safe?

**No.** Both agents would write to the same `memory/audit.jsonl` and `state/` files. Lines can interleave. If you need strict single-writer semantics, set different `$env:VORTEX_HOME` for each instance.

For read-only access (one agent writes, the other reads), this is safe.

### Q: I want to start fresh. How do I uninstall?

There's no `uninstall.ps1` yet (roadmap item #7). For now, manually:

```powershell
# Delete the engine
Remove-Item -Recurse -Force "$HOME\Documents\PowerShell\Modules\Vortex"

# Optional: also delete all user data
Remove-Item -Recurse -Force "$env:APPDATA\Vortex-OS"

# Optional: uninstall system deps (if you don't need them for anything else)
winget uninstall SQLite.SQLite
winget uninstall Gyan.FFmpeg   # if you installed it
```

The `.gitignore` in the skill folder has `*.dll`, so re-cloning the skill won't accidentally re-introduce engine artifacts.

---

## Runtime

### Q: The engine writes 4 files to my project deliverables folder, but the audio comes out silent

This is a known issue with `--agents-discover` (which doesn't actually generate any deliverables — it's a meta-command that lists the available agents). To generate deliverables, use `--dispatch-master` with an objective file:

```powershell
# This just lists agents (no deliverables)
pwsh -NoProfile -File .\skill.ps1 --agents-discover

# This actually generates deliverables
pwsh -NoProfile -File .\skill.ps1 --dispatch-master my_project\objective.md
```

### Q: My project deliverables folder has old files from a previous run

By design — the engine refuses to overwrite. To redo, use `-Project <name>_v2` or manually delete the project's `deliverables/<project>/` folder.

### Q: I dispatch and the engine immediately returns with no output

This usually means the engine crashed silently. Check:

```powershell
# 1. Is the engine installed?
Get-ChildItem "$HOME\Documents\PowerShell\Modules\Vortex" -Directory

# 2. Try running the same command via skill.ps1 (not direct engine call)
pwsh -NoProfile -File .\skill.ps1 --version

# 3. Check VORTEX_HOME exists
Test-Path "$env:APPDATA\Vortex-OS"
```

If the engine version prints `VORTEX-OS Vortex.dll 0.1.8 (C++/CLI on PowerShell 7+, .NET 10)`, the engine is loaded. If your dispatch returns nothing, the issue is in the dispatcher (which is a stub — see roadmap item #1).

### Q: Can I run two `skill.ps1` invocations at the same time (e.g. dispatching two projects in parallel)?

**Yes, but the engine is shared.** Both invocations would load the same `Vortex.dll` (PowerShell modules are process-scoped, but you can have multiple `pwsh` processes). The state is shared if `$VORTEX_HOME` is the same. Two parallel dispatches to the same project would race; two parallel dispatches to different projects are safe.

For real parallelism, use separate `pwsh` processes (the skill spawns a new one per invocation anyway).

---

## The engine (C++/CLI)

### Q: I changed a `.cpp` file in the engine. How do I rebuild?

```powershell
cd vortex-os-dotnet
pwsh -NoProfile -File src\build.ps1
```

This invokes `cl.exe` / `link.exe` with the right flags (`/clr:netcore /std:c++20 /EHa /O2`). The build output is `Vortex.dll` + `ijwhost.dll` at the repo root, plus the updated `Vortex.psd1` / `Vortex.psm1`.

### Q: Build fails with `'LibDir' is not a member of 'Vortex::Paths'`

You're on an old commit. `LibDir` was removed in v0.1.7 (when storage was split into SkillDir + HomeDir). The replacement is `p->SkillDir + "/lib"` for the rare cases that need it.

### Q: Build fails with `'Lib' is not a member of 'System::String'`

You're missing the `L` prefix on a string literal:

```cpp
// Wrong:
String^ foo = gcnew String("hello");

// Right:
String^ foo = gcnew String(L"hello");
```

`String^` is .NET's `System.String`, which uses UTF-16 (wide chars) on Windows. String literals must be `L"..."` (wide) not `"..."` (narrow).

### Q: I get C2039 'X' is not a member of 'Vortex::Paths' for some field I added

When you add a field to the `Paths` struct in `VortexCommon.h`, you also need to:
1. Update all `PathResolver::Resolve` overloads to set the new field
2. Update `EnsureRuntimeDirs` if it's a directory
3. Update the project structure documentation

Forgetting any of these causes a linker error or a runtime "field not initialized" bug.

---

## The skill (PowerShell)

### Q: The skill reports the engine isn't installed, but it IS installed (I see the folder)

Two common causes:

1. **The engine version is in `$HOME\Documents\PowerShell\Modules\Vortex\<ver>\` but the version folder name has a `v` prefix** (e.g. `Vortex\v0.1.7\`). The skill expects `<ver>` (no prefix). Re-install with:
   ```powershell
   pwsh -NoProfile -File .\install.ps1
   ```
   which will install the correct versioned folder.

2. **`$HOME\Documents` is OneDrive-redirected** (see [the OneDrive section](#onedrive--windows-quirks)). The skill probes PSModulePath for the first writable per-user entry.

### Q: I get "The module 'Vortex' could not be loaded" when I try `Import-Module Vortex`

Two common causes:

1. **PowerShell 5 (not 7).** Run `pwsh --version` to verify. The engine is .NET 10 and only PS7+ can load it.

2. **The engine's `Vortex.psd1` can't find `Vortex.dll` or `ijwhost.dll`.** All 4 files must be in the same folder. Check:
   ```powershell
   Get-ChildItem "$HOME\Documents\PowerShell\Modules\Vortex\0.1.8"
   ```
   You should see `Vortex.dll`, `Vortex.psm1`, `Vortex.psd1`, `ijwhost.dll`. If any are missing, re-install.

### Q: `auto-update.ps1` says "Up to date" but I know there's a newer release

The cache file at `$VORTEX_HOME/state/auto-update-check.json` is caching the "no update" result for 6 hours. Bypass with:

```powershell
pwsh -NoProfile -File .\auto-update.ps1 -Force
```

### Q: My `-Project` flag is being ignored — the engine still uses the auto-derived name

`-Project` is read at the very start of `skill.ps1` and sets `$env:VORTEX_PROJECT` BEFORE the module is loaded. If you're calling the engine directly (not through `skill.ps1`), the env var isn't set. Either:

1. Use `skill.ps1 -Project <name> --dispatch-master ...` (preferred)
2. Or set `$env:VORTEX_PROJECT` before invoking the engine manually

---

## HITL gates

### Q: My dispatch is hanging on a gate but I don't see any prompt

The gate pause is a `PENDING_HUMAN` event. The skill prints it to the host. If you don't see it, your terminal may have scrollback cut off, or you may be in a non-interactive context (CI runner, background process, etc.).

**Fix:** check the engine's audit log for the pending gate:

```powershell
Get-Content "$env:APPDATA\Vortex-OS\memory\audit.jsonl" | Select-String "PENDING_HUMAN" | Select-Object -Last 1
```

This shows the last gate that's waiting for input. To approve it:

```powershell
pwsh -NoProfile -File .\skill.ps1 --hitl-approve <task_id>
```

### Q: I want to add a new HITL gate to my project. How?

The engine currently supports 3 severity levels: `LOW`, `HIGH`, `CRITICAL`. The sample prompts use them like this:

- `HIGH` — script approval, final pack approval
- `CRITICAL` — moral-hinge gates (e.g. "do you want to put the protagonist in mortal danger?")

To add a custom gate in a sample prompt, just say: "After the engine drafts the X line, surface a PENDING_HUMAN gate with task_id=X, severity=Y, and a clear in-character explanation." The engine will pause and surface the gate.

(For real production, you'd need the actual gate code in the C++ engine — see roadmap item #1.)

### Q: Can I batch-approve multiple gates in one invocation?

Not currently. The engine pauses on each gate. You'd have to:
1. `pwsh -File skill.ps1 --hitl-approve <gate1>`
2. Wait for the next gate
3. `pwsh -File skill.ps1 --hitl-approve <gate2>`
4. ...

(For batch-approval, see the "approve and continue" pattern in the agent's response when a gate is surfaced — the engine could read a "pre-approve" list from `$env:VORTEX_PRE_APPROVE` in a future version. Roadmap item.)

---

## OneDrive + Windows quirks

### Q: My `Documents` folder is in `C:\Users\<user>\OneDrive\Documents` (not `C:\Users\<user>\Documents`). How does this affect VORTEX-OS?

OneDrive Files-On-Demand is the default on Windows 10/11 with OneDrive configured. It makes `Test-Path` lie — the folder shows as "exists" but `Get-ChildItem` returns nothing because nothing is synced locally yet.

**The skill handles this** in `install.ps1` by:
1. Probing each PSModulePath entry with a sentinel subdir
2. Falling back to the first non-OneDrive entry

But other commands (e.g. `Get-Module Vortex -ListAvailable`) may still fail because PSModulePath points to the OneDrive ghost. If that happens:

```powershell
# Force the engine to use a non-OneDrive path:
$env:VORTEX_MODULE_PATH = 'D:\PowerShell\Modules'
pwsh -NoProfile -File .\install.ps1
```

Or, fix the OneDrive redirect:
1. OneDrive Settings → Sync and backup → Advanced settings → uncheck "Files On-Demand"

### Q: `Test-Path` returns False for a folder I just created under `Documents\PowerShell\Modules`

OneDrive Files-On-Demand. The folder exists in the OneDrive cloud but hasn't synced locally. The fix is to either:
1. Open the folder in File Explorer and wait for it to sync
2. Use `[IO.Directory]::Exists()` instead of `Test-Path` (the .NET method is more reliable)

The skill's `install.ps1` and `install-deps.ps1` use `[IO.Directory]::CreateDirectory` (not `New-Item`) to work around this.

### Q: I get "path too long" errors on deeply-nested project paths

Windows has a 260-character MAX_PATH limit by default. Long project names + deep subdirs can hit this. Workarounds:

1. Move the project to a shallower path (e.g. `D:\projects\foo\` instead of `C:\Users\<user>\Documents\My Projects\foo\`)
2. Enable long path support in Windows 10/11 (group policy: "Enable Win32 long paths")
3. Use shorter project names (the `Slugify` helps)

### Q: The PowerShell execution policy blocks the skill scripts

If you get "File ... cannot be loaded because running scripts is disabled on this system", run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

`RemoteSigned` allows local scripts to run without a signature (good for development). For locked-down environments, `AllSigned` is stricter but requires every script to be signed.

---

## GitHub Actions / releases

### Q: The release workflow fails with "softprops/action-gh-release@v2: 403 Resource not accessible by integration"

The default `GITHUB_TOKEN` is read-only. The release workflow needs `contents: write` (and optionally `packages: write`) permission. The fix is in `.github/workflows/release.yml`:

```yaml
permissions:
  contents: write
  packages: write
```

### Q: The CI build fails with "Vortex.dll: The process cannot access the file because it is being used by another process"

A previous `Vortex.dll` is still loaded in the runner's PowerShell process. The fix is to run each test in a fresh `pwsh` process:

```yaml
- name: Smoke-test the engine
  run: pwsh -NoProfile -Command "Import-Module ./Vortex.psd1 -Force; ..."
```

The `pwsh -Command` form spawns a new process; `Import-Module -Force` reloads the DLL.

### Q: The PSGallery publish step is skipped

The release workflow has `if: env.PSGALLERY_API_KEY != ''`. If the secret isn't set, the step is skipped. To enable, set `PSGALLERY_API_KEY` in the repo's secrets (Settings → Secrets and variables → Actions → New repository secret).

---

## Performance

### Q: The engine takes a long time to dispatch

Common causes:

1. **First run on a fresh machine** — the engine download takes ~2 seconds. Subsequent runs are instant.
2. **The `auto-update.ps1` rate-limit cache is stale** — it makes a GitHub call. Should be cached for 6h. If it's been longer than 6h since the last check, the call adds ~500ms.
3. **Many swarm files** — the engine creates a lot of intermediate files in `$VORTEX_HOME/swarms/<id>/`. For long-running projects, this directory can have many files. Performance is usually fine but watch for the 260-char path limit.

### Q: `verify.ps1` is slow

The verifier does:
- 1 GitHub API call (for engine install, if needed)
- ~8 file-system checks
- 3 engine invocations (for `--agents-discover`, `--agents-lint --all`, `--version`)
- 1 winget check (only if `install-deps.ps1` is called separately)

Total: ~3 seconds on a fast machine, ~10 seconds on a slow one. If it's much slower, check that `auto-update.ps1`'s GitHub call isn't hanging (try `winget --version` to see if winget itself is slow).

### Q: The audit log is huge (10+ MB). Can I trim it?

`memory/audit.jsonl` is append-only forever. For long-running projects, it can grow. There's no rotation in v0.1.x. Workarounds:

1. Manually rotate: rename `audit.jsonl` to `audit_2026-08.jsonl` and the engine will start a new one
2. Set up a scheduled task that rotates monthly
3. Wait for roadmap item (audit log rotation)

---

## Security

### Q: Is it safe to run `skill.ps1` on a project I downloaded from the internet?

The skill's install flow downloads the engine from `Cloudmeru/vortex-os-dotnet/releases` (verified by GitHub's release signature). The engine's `.dll` is loaded into the PowerShell process, so it has the same trust level as PS7 itself. The skill scripts are also signed (or should be) by the maintainer.

**The dispatch step is where the trust boundary is.** When you `--dispatch-master` an objective, the engine invokes LLM workers that generate content. The output is written to `$VORTEX_HOME/deliverables/<project>/` which you control. As long as you don't pipe the LLM output to `Invoke-Expression` or similar, the dispatch is sandboxed.

**Red flags** (don't do these):
- `--dispatch-master <objective.md>` from an untrusted source without reading the objective file first
- Pre-authorizing a "continue" gate (the moral-hinge gate) for an objective you haven't reviewed
- Setting `$env:VORTEX_HOME` to a network share or world-writable directory

### Q: The engine can shell out to the user's PowerShell. How is that sandboxed?

It isn't. The engine is a class library; it has no inherent sandbox. If a worker (a PowerShell script invoked by the engine) does `Invoke-Expression` or runs a downloaded script, it has the same trust as the user running `skill.ps1`. The Continuity Engine + Self-Healing Optimizer catch *content* violations (e.g. "this scene uses a banned word"), not *behavior* violations (e.g. "this script deletes a file").

If you need true sandboxing (e.g. for running untrusted objectives), use a container:
```powershell
docker run --rm -v ${PWD}:/work -v vortex-data:/vortex-home mcr.microsoft.com/powershell pwsh -File /work/skill.ps1 ...
```

This is a roadmap item (#15 — container support).

### Q: The engine stores user data in `%APPDATA%`. Who can see it?

`%APPDATA%\Vortex-OS\` is owned by the current user and is not world-readable by default. Other users on the same machine cannot read it. Other processes running as the same user (including any code you run) can read it. If the machine is compromised, the attacker has the same access as you.

For sensitive projects, consider:
- Setting `$env:VORTEX_HOME` to an encrypted folder (e.g. via VeraCrypt or BitLocker)
- Using a container with a read-only filesystem

---

## See also

- [`idea-future-recommendations.md`](./idea-future-recommendations.md) — what to build next
- [`idea-architecture-decisions.md`](./idea-architecture-decisions.md) — why we built it this way
- `references/INSTRUCTIONS.md` — the operator playbook
- `SKILL.md` — the entry point for code agents
- `README.md` — the user-facing overview

---

*Last updated: 2026-08-27. Current versions: `vortex-os-skill` v0.1.6, `vortex-os-dotnet` v0.1.8.*
