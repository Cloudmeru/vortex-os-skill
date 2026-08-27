# PRD-10 — Multi-User / Shared VORTEX_HOME

**Status:** Draft · Phase 2 (user said "ok this is a good approach for team or multi coding agent run simultaneous")
**Owner:** VORTEX-OS maintainers
**Source:** `idea-future-recommendations.md` item 10

---

## 1. Context

VORTEX-OS is single-user-per-machine today. The default `VORTEX_HOME` is `%APPDATA%\Vortex-OS\` (or `$env:VORTEX_HOME` if set). When two engineers on the same machine — or, more importantly, when **multiple coding agents running in parallel** (the user's "simultaneous" case) — try to dispatch against the same `VORTEX_HOME`, three things break:

1. **Audit log corruption.** `memory/audit.jsonl` is an append-only file. Two writers appending at the same time can interleave or truncate each other.
2. **HITL checkpoint races.** `state/pending_approvals/<task_id>.json` is a write-replace file. Two operators approving the same checkpoint simultaneously can lose one approval.
3. **Deliverable manifest races.** `deliverables/<project>/.manifest.json` is read-then-written. Two packagers in parallel can produce inconsistent manifests.

The user said "this is a good approach for team or multi coding agent run simultaneous" — so they want the recommended design from `idea-future-recommendations.md` item 10:

- Document the "team use" pattern: set `VORTEX_HOME` to a network drive or a shared server
- Add file-locking around `memory/audit.jsonl` writes
- Add a "team" config layer: per-user audit log + shared deliverables pool

## 2. Goals

1. **Two engineers on the same machine, or two coding agents in parallel, can safely use the same `VORTEX_HOME`.** No silent data loss, no truncated writes, no orphan checkpoints.
2. **Per-user audit trail.** When Alice and Bob both dispatch against a shared `VORTEX_HOME`, each sees only their own actions in `--audit-trail --user alice` and the team sees both in `--audit-trail --all`.
3. **Shared deliverables.** The team still benefits from a single `deliverables/<project>/` that everyone can read.
4. **Network drives work.** Setting `VORTEX_HOME=\\fileserver\vortex$\team` is a supported configuration; locks and retries handle SMB latency.
5. **Backward-compatible.** Single-user setups (the vast majority) need zero config; the team mode is opt-in.

## 3. Non-goals

- **Real-time collaboration on the same dispatch.** Two operators approving the *same* HITL gate is still a race we don't try to win (last writer wins, with a warning).
- **Cross-`VORTEX_HOME` migration.** If a user wants to switch from per-user to shared, that's a `migrate-state.ps1` feature for a later phase.
- **A team server / service.** VORTEX-OS stays a file-system-only tool. No daemon, no socket server.
- **Quota / RBAC.** The network drive's ACL is the team boundary. We don't add our own.

## 4. Design

### 4.1 Config layer

A new file at `$VORTEX_HOME\.vortex\config.json` (auto-created on first run if missing):

```json
{
  "team_mode": false,
  "user_audit_log": false,
  "user_state": false,
  "user_tasks": false,
  "shared_deliverables": true,
  "file_locking": "advisory",
  "lock_retry_ms": 100,
  "lock_max_attempts": 50
}
```

| Field | Default | Meaning |
|---|---|---|
| `team_mode` | `false` | When `true`, enables all the per-user path sharding below. |
| `user_audit_log` | `false` | When `true`, audit goes to `memory/audit-$env:USERNAME.jsonl` instead of `memory/audit.jsonl`. |
| `user_state` | `false` | When `true`, per-user state lives under `state/$env:USERNAME/` (pending_approvals, decision_history, prompt_optimizations, etc.). |
| `user_tasks` | `false` | When `true`, per-user tasks under `tasks/$env:USERNAME/`. |
| `shared_deliverables` | `true` | When `true`, all users share `deliverables/<project>/`. Set `false` to make it per-user. |
| `file_locking` | `"advisory"` | `"advisory"` = best-effort locks with retries. `"mandatory"` = `FileShare.None` opens (only works on local NTFS / SMB; will fail on FAT / OneDrive ghost). |
| `lock_retry_ms` | `100` | Backoff between retry attempts. |
| `lock_max_attempts` | `50` | Max retries before giving up (5 seconds total at default). |

### 4.2 Bootstrap

`skill.ps1` (and the engine's `Vortex.Skill::Run`) reads the config at startup and **mutates the `Paths` struct** before any I/O. The engine-side change is one new function in `VortexCommon.h`:

```cpp
public ref class PathResolver abstract sealed {
public:
    // Apply a team-mode config to the resolved paths. Idempotent.
    static void ApplyTeamConfig(Paths^ p, JsonElement config) {
        if (!JsonX::GetBool(config, "team_mode", false)) return;
        String^ user = Environment::GetEnvironmentVariable("USERNAME");
        if (String::IsNullOrEmpty(user)) user = "anonymous";

        if (JsonX::GetBool(config, "user_audit_log", false)) {
            p->AuditLogFile = Path::Combine(p->MemoryDir, "audit-" + user + ".jsonl");
        }
        if (JsonX::GetBool(config, "user_state", false)) {
            String^ userState = Path::Combine(p->StateDir, user);
            p->StateDir = userState;
            p->PendingApprovalsDir = Path::Combine(userState, "pending_approvals");
            // re-derive any other subdirs that hang off StateDir
        }
        if (JsonX::GetBool(config, "user_tasks", false)) {
            p->TasksDir = Path::Combine(p->TasksDir, user);
        }
    }
};
```

`Paths` gains 2 new fields: `AuditLogFile` and `PendingApprovalsDir`. The audit / HITL writers use the new fields instead of computing paths from scratch.

### 4.3 File locking

A new helper in `VortexCommon.h`:

```cpp
public ref class FileLock abstract sealed {
public:
    // Read-with-lock: retries up to lock_max_attempts times.
    // Returns the file content as a String^ (or nullptr on failure).
    static String^ ReadWithLock(String^ path, int retryMs, int maxAttempts);

    // Write-with-lock: opens the file with FileShare::None, writes, closes.
    // Returns true on success, false on lock failure.
    static bool WriteWithLock(String^ path, String^ content, int retryMs, int maxAttempts);

    // Append-with-lock: opens in append mode with FileShare::None.
    static bool AppendWithLock(String^ path, String^ line, int retryMs, int maxAttempts);
};
```

The advisory lock is implemented as: open the file with `FileMode.Open, FileAccess.Read, FileShare.None` (or `FileAccess.Write, FileShare.None` for writes). On Windows / NTFS / SMB this prevents any other process from opening the file. Retry with the configured backoff.

**The engine's existing writers (audit log, HITL checkpoints, decision history) all switch to `FileLock::*` calls.** No other behavior change.

### 4.4 The team-mode setup wizard

A new script: `setup-team.ps1`. One-time, run once per `VORTEX_HOME`:

```powershell
pwsh -NoProfile -File .\setup-team.ps1

# Asks 3 questions:
#   1. Team mode? (yes/no)
#   2. Per-user audit log? (yes/no, default yes if team mode)
#   3. Per-user state? (yes/no, default yes if team mode)
# Writes .vortex/config.json and creates the per-user subdirs.
```

For a coding agent team, the recommended config is:

```json
{
  "team_mode": true,
  "user_audit_log": true,
  "user_state": true,
  "user_tasks": true,
  "shared_deliverables": true,
  "file_locking": "advisory",
  "lock_retry_ms": 100,
  "lock_max_attempts": 50
}
```

This way each coding agent (or each engineer) gets their own audit log + HITL state, but the team's deliverables pool is shared.

### 4.5 Audit-trail filter

A new flag on `--audit-trail`:

```powershell
# Show only the current user's actions (default in team mode)
pwsh -NoProfile -File .\skill.ps1 --audit-trail

# Show the full team's actions
pwsh -NoProfile -File .\skill.ps1 --audit-trail --all-users

# Show a specific user
pwsh -NoProfile -File .\skill.ps1 --audit-trail --user alice
```

In single-user mode (no `user_audit_log`), the filter is a no-op (always shows the one log).

## 5. API surface

### New commands (skill-side)

```powershell
# One-time team setup
pwsh -NoProfile -File .\setup-team.ps1

# New flag on existing --audit-trail
pwsh -NoProfile -File .\skill.ps1 --audit-trail --all-users
pwsh -NoProfile -File .\skill.ps1 --audit-trail --user alice

# Inspect the active team config
pwsh -NoProfile -File .\skill.ps1 --team-config
```

### New env var

```powershell
$env:VORTEX_TEAM_CONFIG  # path to a custom .vortex/config.json (default: $VORTEX_HOME\.vortex\config.json)
```

### New file in `VORTEX_HOME`

```
.vortex/
  config.json
  lock.log         # append-only log of lock failures (informational)
memory/
  audit.jsonl                    # if user_audit_log = false
  audit-alice.jsonl              # if user_audit_log = true
  audit-bob.jsonl
state/
  decision_history.json          # if user_state = false
  alice/
    decision_history.json        # if user_state = true
    pending_approvals/
    prompt_optimizations/
  bob/
    ...
```

## 6. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Mandatory locks on a OneDrive Files-On-Demand ghost folder deadlock the user | High | High | Default is "advisory". Detect OneDrive in `install.ps1` and warn loudly if `mandatory` is set. |
| Two operators approve the *same* HITL gate in the same millisecond | Low | Low | Last writer wins (as today). Log a warning to `lock.log` if a lock acquisition fails after 5 seconds; the operator sees it. |
| A network drive is unreachable when writing the audit log | Medium | Medium | Buffer the line in memory, retry 5s, write when reconnected. If still down after 60s, the line goes to `state/lost_audit_lines.jsonl` for manual recovery. |
| The `Paths` struct changes break the engine's existing writers | Low | High | Add the new fields with sensible defaults; existing writers fall back to the old paths unless `ApplyTeamConfig` is called. |
| The team-mode config is editable by anyone, and someone nukes it | Low | Low | Document the file as "treat as code"; ship a `setup-team.ps1 -Verify` that re-checks it. |

## 7. Acceptance criteria

1. `setup-team.ps1` writes a valid `.vortex/config.json` and creates the per-user subdirs.
2. Two PowerShell sessions running `--dispatch-master` in parallel on a shared `VORTEX_HOME` both succeed and produce non-interleaved audit logs.
3. `--audit-trail --user alice` shows only Alice's actions; `--audit-trail --all-users` shows everyone.
4. `FileLock::ReadWithLock` on a file that's locked by another process retries and eventually reads (or fails with a clear error after 5s).
5. `verify.ps1` adds a `tests/test_team_mode.ps1` that spawns two parallel dispatches and asserts both succeed.
6. `idea-future-recommendations.md` item 10 → ✅ status.

## 8. Effort

- `skill/setup-team.ps1`: ~100 lines
- `skill/skill.ps1` changes: ~150 lines (new --team-config, --audit-trail filter)
- `engine/VortexCommon.h` + `Decisions.{h,cpp}`: ~200 lines (FileLock + ApplyTeamConfig + new Paths fields)
- New tests: ~150 lines
- Docs: `references/INSTRUCTIONS.md` updated

**Total: ~600 lines. 1 PR (skill) + 1 PR (engine) + tag bump to 0.1.10. ~4-5 days for a single engineer.**

## 9. Open questions

- **Q1.** Should `setup-team.ps1` also offer to migrate an existing single-user `VORTEX_HOME` into the per-user subdirs? — *Recommend: yes, as a `-Migrate` flag. Reuses `migrate-state.ps1` machinery.*
- **Q2.** What happens when a per-user subdir exceeds 1 GB? — *Recommend: nothing automatic. Surface a warning in `--health` and let the user decide. No quota enforcement.*
- **Q3.** Should `lock.log` be rotated? — *Recommend: yes, at 10 MB. Simple `[IO.File]::Move(log, log + '.1')` after each startup if size > 10 MB.*
- **Q4.** Should the `user` env var fall back from `$env:USERNAME` to `$env:USER` (Linux/macOS) to `$env:USERDOMAIN\$env:USERNAME` (domain users)? — *Recommend: try `USERNAME` first, then `USER`, then `whoami`. Document the precedence.*
