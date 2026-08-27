# PRD-14 — Streaming / Partial Results

**Status:** Draft · Phase 2
**Owner:** VORTEX-OS maintainers
**Source:** `idea-future-recommendations.md` item 14

---

## 1. Context

The engine buffers all deliverables until the end, then surfaces them. For a 7-deliverable episode that takes 8 minutes, the operator sees nothing for 8 minutes — no progress, no early feedback, no chance to redirect.

The recommendation: a `--stream` flag on `skill.ps1` that subscribes to a named pipe (or HTTP) and prints partial deliverables as they're generated. The engine writes each deliverable to `state/in_progress/<task_id>/<deliverable>.partial` as it completes; the operator can preview, give early feedback, or let it run.

The user numbered this for phase 2; the design here builds on PRD-08 (PowerShell shell is separable from the engine) and PRD-11 (plugin system, so streaming is a plugin-aware concept).

## 2. Goals

1. **The operator sees each deliverable the moment it's done**, not at the end of the dispatch.
2. **The operator can preview a `.partial` deliverable** in their default app (text editor for .md/.json, audio player for .wav, image viewer for .png, etc.).
3. **The operator can give early feedback** — type a 1-line note that gets injected into the next dispatch's prompt as a hint.
4. **The dispatch is fully reversible** — if the operator aborts mid-stream, the in-progress deliverables are deleted and the dispatch is marked "aborted by operator".
5. **The engine doesn't change its core dispatch logic.** A new `lib/StreamSink.{h,cpp}` is the only engine-side change.
6. **The skill shell subscribes to the stream** via FileSystemWatcher (no new transport protocol needed).

## 3. Non-goals

- **Real-time LLM token streaming.** The engine buffers the LLM response per-dispatch; it doesn't stream tokens. That's a different feature (and a different PRD).
- **A web UI for the stream.** The CLI output + FileSystemWatcher is enough for v1. Web UI is a future phase.
- **Cross-machine streaming.** The stream is local to the machine running the dispatch. (For cross-machine, use a shared VORTEX_HOME + a polling watcher; out of scope here.)
- **A push notification system.** No email / Slack / Discord alerts. Just the local stream.
- **Sub-second latency.** The stream emits per-deliverable, not per-LLM-token. Typical cadence: every 30s to 2min.

## 4. Design

### 4.1 The in-progress directory

When a dispatch starts, the engine creates `$VORTEX_HOME/state/in_progress/<task_id>/`. As each deliverable completes (or partially completes), the engine writes it there with a `.partial` suffix:

```
state/in_progress/ep2_writer/
  .started                # creation time, dispatch_id, agent
  01_script.partial.md    # the script, written as soon as the writer plugin finishes
  02_character_bible.partial.json
  03_soundscape.partial.wav
  ...
  .completed              # written last, signals dispatch done
```

When the dispatch is fully approved (Gate 3), the engine **moves** the partial files to `deliverables/<project>/<file>` and removes the in-progress directory.

### 4.2 The engine's StreamSink

A new lib at `lib/StreamSink.{h,cpp}`:

```cpp
public ref class StreamSink abstract sealed {
public:
    // Called by the engine when a dispatch starts.
    static void OnDispatchStart(Paths^ p, String^ taskId, String^ agent);

    // Called when a deliverable is produced (or updated).
    static void OnDeliverableReady(Paths^ p, String^ taskId, String^ deliverableName, String^ filePath);

    // Called when a deliverable is partially updated (e.g. an audio file being encoded in chunks).
    static void OnDeliverableProgress(Paths^ p, String^ taskId, String^ deliverableName, double percent);

    // Called when the dispatch completes (success or failure).
    static void OnDispatchEnd(Paths^ p, String^ taskId, String^ status);
};
```

The implementation just creates files in the right place. The skill shell's FileSystemWatcher sees the new files and reacts.

A side effect: `StreamSink` writes a small JSON manifest alongside each partial file:

```json
{
  "task_id": "ep2_writer",
  "deliverable": "01_script",
  "produced_at": 1700000000,
  "size_bytes": 12453,
  "is_partial": true,
  "agent": "writer.shift",
  "tokens_in": 4521,
  "tokens_out": 1823
}
```

This makes the stream self-describing.

### 4.3 The skill shell's streamer

A new module at `<skill>/lib/Vortex.Streamer.psm1`:

```powershell
# Start streaming a task
Start-VortexStream -TaskId ep2_writer [-AutoOpen]
# Subscribes to FileSystemWatcher on $VORTEX_HOME\state\in_progress\ep2_writer\
# As each .partial file appears:
#   1. Print a notification: "[stream] 01_script.md ready (12.4 KB) — open? (y/n/q)"
#   2. If y: invoke the OS handler (Start-Process file.md)
#   3. If q: stop streaming (dispatch continues in background)
# Optionally pass -AutoOpen to skip the prompt and auto-open each deliverable

# Send a hint to the next dispatch in the chain
Send-VortexHint -TaskId ep2_writer -Text "Tone is too dark in scene 2; lighten by 20%"

# Stop streaming
Stop-VortexStream -TaskId ep2_writer
```

### 4.4 The dispatch flag

```powershell
# Dispatch with streaming enabled
pwsh -NoProfile -File .\skill.ps1 --dispatch-master objectives\ep2.md --stream

# Dispatch + auto-open each deliverable
pwsh -NoProfile -File .\skill.ps1 --dispatch-master objectives\ep2.md --stream --auto-open

# Stream an already-running dispatch (attach to its in-progress dir)
pwsh -NoProfile -File .\skill.ps1 --stream ep2_writer
```

### 4.5 The hint channel

When the operator types a hint, it goes to `$VORTEX_HOME/state/in_progress/<task_id>/.hints.jsonl`:

```json
{"ts": 1700000123, "text": "Tone is too dark in scene 2; lighten by 20%"}
{"ts": 1700000145, "text": "Use the lighthouse foghorn for the dawn bell"}
```

The engine reads `.hints.jsonl` before each subsequent dispatch in the chain and injects them as "operator notes" in the prompt:

```
[Operator notes during dispatch]
- Tone is too dark in scene 2; lighten by 20%
- Use the lighthouse foghorn for the dawn bell
```

The plugin sees the operator's hints and can adjust accordingly.

### 4.6 Cleanup

A nightly cron-like task (run from the skill shell on first invocation of the day) cleans up:

- `state/in_progress/<task_id>/` directories where `.completed` exists and the dispatch is older than 7 days
- `state/in_progress/<task_id>/` directories where `.started` is older than 24h but no `.completed` (orphaned)

The cleanup is opt-in (`$env:VORTEX_STREAM_AUTO_CLEANUP=1`).

## 5. API surface

### New commands (skill-side)

```powershell
# Stream a dispatch
pwsh -NoProfile -File .\skill.ps1 --dispatch-master objectives\ep2.md --stream [--auto-open]

# Attach to an already-running dispatch
pwsh -NoProfile -File .\skill.ps1 --stream ep2_writer [--auto-open]

# Send a hint to the running dispatch
pwsh -NoProfile -File .\skill.ps1 --hint ep2_writer --text "Tone is too dark in scene 2"

# Stop streaming (the dispatch continues in the background)
pwsh -NoProfile -File .\skill.ps1 --stream-stop ep2_writer

# List all in-progress dispatches
pwsh -NoProfile -File .\skill.ps1 --stream-list
```

### New cmdlets in Vortex.psm1

```powershell
Import-Module Vortex
Start-VortexStream -TaskId ep2_writer [-AutoOpen]
Stop-VortexStream [-TaskId ep2_writer]  # -TaskId omitted = stop all
Send-VortexHint -TaskId ep2_writer -Text "..."
Get-VortexStream                        # lists in-progress dispatches
```

### New env var

```powershell
$env:VORTEX_STREAM_AUTO_CLEANUP   # 1 to enable nightly cleanup (default 0)
$env:VORTEX_STREAM_AUTO_OPEN      # 1 to auto-open every partial file (default 0)
$env:VORTEX_STREAM_NOTIFY         # path to a PowerShell script that gets called on each event (default unset)
```

### New file in `VORTEX_HOME`

```
state/
  in_progress/
    <task_id>/
      .started                # JSON: dispatch start
      .hints.jsonl            # operator hints (append-only)
      <deliverable>.partial   # one per deliverable, with sidecar .json
      .completed              # JSON: dispatch end
```

## 6. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| The operator's hint is interpreted as a directive and overrides the worker's intent | Medium | Medium | The engine injects hints as `[Operator notes during dispatch]` — clearly demarcated, not part of the task itself. The worker can ignore them. The audit log records the hint + the worker's response. |
| FileSystemWatcher is unreliable on network drives | High | Low | The skill shell falls back to polling every 2s if the watcher fails. The polling is cheap (one `Get-ChildItem` per cycle). |
| A streaming operator can't keep up with the events and gets overwhelmed | Medium | Low | Default is "prompt per event" (y/n/q). The `--auto-open` flag is opt-in. |
| The .partial files leak to the final deliverables (operator forgot the dispatch was streamed) | Low | High | When the dispatch is approved, the engine **moves** (not copies) the .partial files to the final destination. The in-progress dir is removed. The audit log records the move. |
| The streaming view shows the deliverable before the Continuity Engine has checked it | Medium | Medium | The .partial files are clearly marked (`*.partial.md` not `*.md`). The deliverable is only "promoted" to a real deliverable after Continuity Engine + HITL approval. The skill shell prints a warning when opening a .partial. |
| The streaming adds latency to the dispatch (FileSystemWatcher roundtrip) | Low | Low | The engine writes the partial file synchronously (it's a local file). The watcher just observes. The operator-side latency is only the OS handler opening the file. |

## 7. Acceptance criteria

1. `pwsh -NoProfile -File .\skill.ps1 --dispatch-master objectives\ep2.md --stream` prints a notification for each deliverable as it appears in `state/in_progress/ep2_writer/`.
2. The operator can type `y` to open the deliverable in their default app, or `q` to stop streaming.
3. The operator can send a hint via `--hint ep2_writer --text "..."` and the next dispatch in the chain sees it.
4. When the dispatch is approved (Gate 3), the partial files are moved to `deliverables/<project>/` and the in-progress dir is removed.
5. `--stream-list` shows all currently in-progress dispatches.
6. The engine's `StreamSink` is called from `DispatchV4::Run` without changing the existing dispatch logic.
7. `verify.ps1` adds a `tests/test_streaming.ps1` that starts a dispatch with `--stream`, simulates the engine writing a partial, and asserts the skill shell receives the notification.

## 8. Effort

- `engine/lib/StreamSink.{h,cpp}`: ~150 lines
- `engine/skill.cpp` + `DispatchV4.cpp` integration: ~80 lines
- `skill/lib/Vortex.Streamer.psm1`: ~300 lines
- `skill/skill.ps1` (new flags): ~100 lines
- New tests: ~200 lines
- Docs: `references/INSTRUCTIONS.md` updated, new `references/streaming.md`

**Total: ~830 lines. 2 PRs (engine + skill). Tag bump to 0.1.10. ~1 week for a single engineer.**

## 9. Open questions

- **Q1.** Should the operator's hint be visible to the worker as a "system message" or as "user message"? — *Recommend: user message. The worker can choose to ignore it; treating it as a system message would give it too much authority.*
- **Q2.** Should the stream be replayable (a "scrub" UI to see the partials in order)? — *Recommend: no for v1. The directory is the source of truth; the operator can `ls -lt` it.*
- **Q3.** Should the skill shell show a live progress bar (e.g. "deliverable 3 of 7, ETA 4 minutes")? — *Recommend: yes, but simple. Use the deliverable's index in the template's `deliverables[]` array to compute "X of N" + "estimated remaining" based on the average time of the previous deliverables.*
- **Q4.** Should multiple operators be able to stream the same dispatch? — *Recommend: yes, FileSystemWatcher supports multiple subscribers. The skill shell namespaces its hints by `$env:USERNAME` so they don't clobber each other.*
- **Q5.** Should the stream emit events over a named pipe so external tools can subscribe? — *Recommend: no for v1. The file-based stream is enough. A pipe-based version is a v0.3 follow-up.*

## 10. Future work (not in this PRD)

- **Web UI for the stream** (a small SPA that watches the in-progress dir and renders each deliverable as it arrives).
- **Auto-pause on operator hint** — if a hint is sent, pause the dispatch and wait for the operator's explicit `resume`.
- **LLM token streaming** — true real-time streaming of the LLM's output as it's generated (vs. per-deliverable).
- **Multi-machine dispatch** — run dispatch on machine A, stream on machine B via shared VORTEX_HOME + RPC.
