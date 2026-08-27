#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Push-Location 'C:\latihan\vortex-os-skill'

# Stage all changes
git add -A

# Show what we're committing
$staged = git diff --cached --stat
Write-Host "--- Staged for commit ---" -ForegroundColor Cyan
Write-Host $staged
Write-Host "-------------------------" -ForegroundColor Cyan

# Commit message (lowercase -m is required by git; -M is invalid)
$msg = "feat: v0.1.7 -- walkthrough, uninstall.ps1, references/architecture.md, 3 idea docs, episode_pattern template`n`n- walkthrough/  : 11-slide HTML walkthrough (palette #18, Times New Roman), index.html viewer, record-to-mp4.ps1 (Edge + ffmpeg)`n- uninstall.ps1 : clean removal (dry-run by default; -Engine, -State, -All)`n- references/architecture.md : 7 Mermaid diagrams + component reference`n- idea-future-recommendations.md : 18 prioritized items + 12 gaps + 5 questions`n- idea-architecture-decisions.md : 15 ADRs (engine choice, two-root storage, etc.)`n- idea-faq-and-pitfalls.md : 30+ Q&As across 10 categories`n- templates/episode_pattern.json : Golden Path template (engine reads via --dispatch-template, supported in v0.1.9)`n- SKILL.md : version bump, anatomy table includes walkthrough + idea docs`n- CHANGELOG.md : full v0.1.7 entry"

git commit -m $msg
if ($LASTEXITCODE -ne 0) { throw "git commit failed: $LASTEXITCODE" }

# Push
git push origin main
if ($LASTEXITCODE -ne 0) { throw "git push failed: $LASTEXITCODE" }

# Show the new head
git log --oneline -3
Pop-Location
