# VORTEX-OS Walkthrough

11-slide HTML walkthrough for the VORTEX-OS skill. Read time: ~5 minutes.

## Files

| File | Purpose |
|------|---------|
| `index.html` | Auto-advancing viewer with keyboard nav (←/→/space, A = autoplay) |
| `slides/slide-01.html` … `slide-11.html` | Individual 960×540 slides |
| `slides/imgs/*.jpg` | Hero illustrations (generated, then downloaded) |
| `record-to-mp4.ps1` | PowerShell recipe: capture slides + ffmpeg to MP4 |

## How to view

**Option 1 — open in a browser:**

```powershell
# Windows
Start-Process 'C:\latihan\vortex-os-skill\walkthrough\index.html'
```

Then:
- `→` / `Space` — next slide
- `←` — previous slide
- `Home` / `End` — first / last
- `A` — toggle 6-second autoplay

**Option 2 — local web server (if you want to share on the LAN):**

```powershell
Push-Location 'C:\latihan\vortex-os-skill\walkthrough'
pwsh -NoProfile -Command '$h = [System.Net.HttpListener]::new(); $h.Prefixes.Add("http://localhost:8765/"); $h.Start(); Write-Host "Open http://localhost:8765/  (Ctrl+C to stop)"; while ($h.IsListening) { $ctx = $h.GetContext(); $req = $ctx.Request; $res = $ctx.Response; $path = $req.Url.LocalPath.TrimStart("/"); if (-not $path) { $path = "index.html" }; $full = Join-Path (Get-Location) $path; if (Test-Path $full) { $bytes = [System.IO.File]::ReadAllBytes($full); $res.ContentLength64 = $bytes.Length; $res.OutputStream.Write($bytes, 0, $bytes.Length) }; $res.Close() }'
```

## How to record as MP4

The slides are designed for screen recording. Three options, simplest first:

### Option A — PowerPoint screen recording (no extra tools)

1. Open `index.html` in Edge or Chrome.
2. Press `F11` to go fullscreen.
3. Press `A` to start autoplay (6s per slide = 66s total).
4. Use Windows Game Bar (`Win + G` → "Capture" → "Start recording").
5. Press `Win + Alt + R` again to stop. The MP4 lands in `Videos\Captures\`.

### Option B — ffmpeg + a screenshot loop (PowerShell)

Requires `ffmpeg` on PATH (install with `winget install Gyan.FFmpeg` if needed).

```powershell
# record-to-mp4.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$slides = Get-ChildItem -Path (Join-Path $root 'slides') -Filter 'slide-*.html' | Sort-Object Name
$tmp = Join-Path $env:TEMP "vortex-walkthrough-frames"
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

# Capture each slide with headless Edge
$i = 0
foreach ($slide in $slides) {
    $frame = Join-Path $tmp ("frame-{0:D4}.png" -f $i)
    & 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' `
        --headless=new `
        --disable-gpu `
        --window-size=960,540 `
        --screenshot=$frame `
        --hide-scrollbars `
        "file:///$($slide.FullName -replace '\\','/')"
    Start-Sleep -Milliseconds 500
    $i++
}

# Stitch into MP4 (6s per slide = 1/6 fps, but use 1 fps for smoothness)
ffmpeg -y -framerate 1 -i "$tmp/frame-%04d.png" -c:v libx264 -pix_fmt yuv420p -r 30 "$root\vortex-os-walkthrough.mp4"

# Optional: cleanup
Remove-Item -Recurse -Force $tmp
Write-Host "Wrote: $root\vortex-os-walkthrough.mp4"
```

> **Tip**: the headless screenshot in Edge produces 1 frame per call. The script above captures 11 frames total; ffmpeg stretches them to 30 fps. If you want a real 6-seconds-per-slide pacing, add `-vf "tpad=stop_duration=5:stop_mode=add:color=black"` before the output file (each frame is held 5 extra seconds).

### Option C — Playwright (most reliable, but adds Python)

If you already have Playwright installed (`pip install playwright && playwright install chromium`):

```python
# record.py
from playwright.sync_api import sync_playwright
from pathlib import Path
import subprocess, sys

root = Path(__file__).parent
slides = sorted((root / 'slides').glob('slide-*.html'))
frames_dir = root / 'frames'
frames_dir.mkdir(exist_ok=True)

with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page(viewport={'width': 960, 'height': 540})
    for i, slide in enumerate(slides):
        page.goto(f'file://{slide.resolve()}')
        page.wait_for_load_state('networkidle')
        page.screenshot(path=str(frames_dir / f'frame-{i:04d}.png'))
    browser.close()

subprocess.run([
    'ffmpeg', '-y', '-framerate', '1', '-i', str(frames_dir / 'frame-%04d.png'),
    '-vf', 'tpad=stop_duration=5:stop_mode=add:color=black,fps=30',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
    str(root / 'vortex-os-walkthrough.mp4')
], check=True)
```

## Slide index

| # | Type | Title |
|---|------|-------|
| 01 | Cover | VORTEX-OS — Self-Bootstrapping Multi-Agent Creative Orchestrator |
| 02 | TOC | What this walkthrough covers |
| 03 | Section divider | 01 — The Problem |
| 04 | Content | Why multi-agent pipelines are hard |
| 05 | Section divider | 02 — Architecture |
| 06 | Content | Two-tier storage keeps your work safe |
| 07 | Content | From zero to first dispatch in one command |
| 08 | Section divider | 03 — Dispatch & HITL |
| 09 | Content | 3 gates, one operator checkpoint, no autopilot |
| 10 | Content | Continuity Engine + Self-Healing Optimizer |
| 11 | Closing | What to try first |

## Source / generation

- Slides: hand-built HTML, inline CSS, Times New Roman, palette #18 (铂金白金) from `html-presentation-generator`
- Hero images: `connector__matrix__generate_image` (5 prompts, 16:9, 1K)
- Architecture diagrams: inline SVG, no external tooling
- The corresponding engine-side Mermaid diagrams live in `references/architecture.md`
