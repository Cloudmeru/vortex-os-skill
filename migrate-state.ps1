# =============================================================================
# migrate-state.ps1 — VORTEX-OS state migration (one-time, manual)
# =============================================================================
# VORTEX-OS v0.1.7+ writes its runtime state to `$env:VORTEX_HOME` (default
# `%APPDATA%\Vortex-OS`) instead of the skill folder. This script moves
# existing data from the skill folder to the new durable location so:
#
#   - audit logs, deliverables, swarms, HITL state, and memory survive skill
#     updates (the skill folder is mutable; VORTEX_HOME is durable)
#   - the data is shared across multiple skill instances on the same machine
#     (e.g. minimax code + hermes, both pointing at the default VORTEX_HOME)
#
# This script is INTENTIONALLY MANUAL — the engine v0.1.7 does NOT auto-migrate
# on first run. You run this ONCE after upgrading to skill v0.1.4+, then
# delete the orphan data in the skill folder whenever you want.
#
# What gets moved (idempotent — skips any subdir that already exists at
# the target):
#
#   <skill>/deliverables/   ->  $env:VORTEX_HOME/deliverables/
#   <skill>/memory/         ->  $env:VORTEX_HOME/memory/
#   <skill>/swarms/         ->  $env:VORTEX_HOME/swarms/
#   <skill>/state/          ->  $env:VORTEX_HOME/state/
#   <skill>/tasks/          ->  $env:VORTEX_HOME/tasks/
#
# What is left in the skill folder (these are per-skill, get replaced on
# update by design):
#
#   agents/    templates/    SKILL.md   README.md   _meta.json
#   INSTRUCTIONS.md  references/  skill.ps1  verify.ps1  install.ps1
#   install-deps.ps1  build.ps1  COMPATIBILITY.md  CHANGELOG.md  LICENSE
#
# Usage:
#   pwsh -NoProfile -File migrate-state.ps1
#   pwsh -NoProfile -File migrate-state.ps1 -VortexHome 'D:\my-data'   # override target
#   pwsh -NoProfile -File migrate-state.ps1 -WhatIf                     # dry-run
#   pwsh -NoProfile -File migrate-state.ps1 -DeleteSource               # also delete source after copy
#   pwsh -NoProfile -File migrate-state.ps1 -AdoptFlat                  # file legacy flat
#                                                                        # deliverables/ into
#                                                                        # deliverables/_unfiled/
# =============================================================================
[CmdletBinding()]
param(
    # Override the target VORTEX_HOME. Default: $env:VORTEX_HOME if set,
    # otherwise $env:APPDATA\Vortex-OS (which the engine also defaults to).
    [string] $VortexHome = $env:VORTEX_HOME,

    # Dry-run: print what would be done, don't actually copy.
    [switch] $WhatIf,

    # After a successful copy, also delete the source subdirs from the
    # skill folder. Off by default — we leave the source in place so
    # the operator can verify the migration before committing to it.
    [switch] $DeleteSource,

    # Adopt the legacy flat deliverables layout: move all top-level
    # files in $VORTEX_HOME\deliverables\ (from skill versions <= 0.1.4)
    # into $VORTEX_HOME\deliverables\_unfiled\ so the new per-project
    # subfolder layout can take over without losing data. Use this ONCE
    # after upgrading to skill v0.1.5+ if you have loose files in
    # deliverables\.
    [switch] $AdoptFlat
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
if (-not $here) { $here = (Get-Location).Path }

# --- 1. PS7+ guard -----------------------------------------------------------
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    throw "VORTEX-OS requires PowerShell 7+ (Core). Detected: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))."
}

# --- 2. Resolve source and target --------------------------------------------
if (-not $VortexHome) {
    $appData = [Environment]::GetFolderPath('ApplicationData')
    if (-not $appData) {
        throw "Could not resolve %APPDATA% and `$env:VORTEX_HOME is not set. Set one and re-run."
    }
    $VortexHome = Join-Path $appData 'Vortex-OS'
}

# The subdirs we move. Keys are the source subdir in the skill folder;
# values are the target subdir in VORTEX_HOME.
$moveMap = [ordered]@{
    'deliverables' = 'deliverables'
    'memory'       = 'memory'
    'swarms'       = 'swarms'
    'state'        = 'state'
    'tasks'        = 'tasks'
}

Write-Host "[vortex-os] Source: $here" -ForegroundColor Cyan
Write-Host "[vortex-os] Target: $VortexHome" -ForegroundColor Cyan
Write-Host ""

# --- 3. Pre-flight: check source + target state ------------------------------
$hasSourceData = $false
foreach ($sub in $moveMap.Keys) {
    $src = Join-Path $here $sub
    if (Test-Path $src) {
        $items = @(Get-ChildItem -LiteralPath $src -Recurse -Force -ErrorAction SilentlyContinue)
        if ($items.Count -gt 0) {
            $hasSourceData = $true
            Write-Host "  [src]   $sub : $($items.Count) item(s) in $src" -ForegroundColor Gray
        }
    }
}
if (-not $hasSourceData) {
    Write-Host "[vortex-os] No source data found in the skill folder. Nothing to migrate." -ForegroundColor Yellow
    return
}

$targetExists = $false
if (Test-Path $VortexHome) {
    $targetExists = $true
    Write-Host ""
    Write-Host "[vortex-os] WARNING: $VortexHome already exists." -ForegroundColor Yellow
    Write-Host "  Subdirs that already exist at the target will be SKIPPED (we never overwrite)." -ForegroundColor Yellow
}
if (-not $targetExists -and -not $WhatIf) {
    New-Item -ItemType Directory -Path $VortexHome -Force | Out-Null
    Write-Host "[vortex-os] Created $VortexHome" -ForegroundColor Green
}

# --- 4. Migrate (idempotent) -------------------------------------------------
$moved = 0
$skipped = 0
$errors = 0

foreach ($srcSub in $moveMap.Keys) {
    $tgtSub = $moveMap[$srcSub]
    $src = Join-Path $here $srcSub
    $tgt = Join-Path $VortexHome $tgtSub

    if (-not (Test-Path $src)) { continue }

    if (Test-Path $tgt) {
        Write-Host "  [skip] $srcSub  (target already exists: $tgt)" -ForegroundColor DarkYellow
        $skipped++
        continue
    }

    $srcCount = @(Get-ChildItem -LiteralPath $src -Recurse -Force -ErrorAction SilentlyContinue).Count
    if ($WhatIf) {
        Write-Host "  [whatif] $srcSub -> $tgt  ($srcCount item(s) would be copied)" -ForegroundColor Cyan
        $moved++
        continue
    }

    try {
        # Create target parent
        $parent = Split-Path $tgt -Parent
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        # Use Copy-Item -Recurse. This handles cross-drive and
        # OneDrive-backed paths more reliably than Move-Item.
        Copy-Item -LiteralPath $src -Destination $tgt -Recurse -Force
        Write-Host "  [copy] $srcSub -> $tgt  ($srcCount item(s))" -ForegroundColor Green
        $moved++

        if ($DeleteSource) {
            Remove-Item -LiteralPath $src -Recurse -Force
            Write-Host "  [del]  $srcSub removed from skill folder" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "  [ERR]  $srcSub : $($_.Exception.Message)" -ForegroundColor Red
        $errors++
    }
}

# --- 5. Summary ---------------------------------------------------------------
Write-Host ""
Write-Host "[vortex-os] Migration summary:" -ForegroundColor Cyan
Write-Host "  copied:    $moved"
Write-Host "  skipped:   $skipped  (target already existed)"
if ($errors -gt 0) { Write-Host "  errors:    $errors" -ForegroundColor Red }
if ($WhatIf) { Write-Host "  (dry-run; no files were moved)" -ForegroundColor Cyan }

if ($moved -gt 0 -and -not $WhatIf -and -not $DeleteSource) {
    Write-Host ""
    Write-Host "[vortex-os] The source data is still in the skill folder at:" -ForegroundColor Yellow
    foreach ($srcSub in $moveMap.Keys) {
        $src = Join-Path $here $srcSub
        if (Test-Path $src) { Write-Host "  $src" }
    }
    Write-Host ""
    Write-Host "Verify the migration by checking the target paths under $VortexHome." -ForegroundColor Yellow
    Write-Host "When you're satisfied, re-run with -DeleteSource to remove the originals:" -ForegroundColor Yellow
    Write-Host "  pwsh -NoProfile -File migrate-state.ps1 -DeleteSource" -ForegroundColor Yellow
}

# --- 6. -AdoptFlat: file legacy loose files into _unfiled/ ----------------
# For users upgrading from skill <= v0.1.4: the engine used to write
# deliverables to $VORTEX_HOME\deliverables\ (flat, no project subfolder).
# In v0.1.5+, new dispatches write to deliverables\<project>\. Existing
# flat files in deliverables\ are still there but invisible to the new
# per-project layout. -AdoptFlat moves them into deliverables\_unfiled\
# so the user can review and re-file them per project. Idempotent.
if ($AdoptFlat) {
    $flatDir = Join-Path $VortexHome 'deliverables'
    $unfiledDir = Join-Path $flatDir '_unfiled'

    if (-not (Test-Path $flatDir)) {
        Write-Host ""
        Write-Host "[vortex-os] -AdoptFlat: no deliverables\ folder at $flatDir; nothing to file." -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path $unfiledDir)) {
        if (-not $WhatIf) { New-Item -ItemType Directory -Path $unfiledDir -Force | Out-Null }
        Write-Host "[vortex-os] -AdoptFlat: created $unfiledDir" -ForegroundColor Green
    }

    $moved = 0
    $skipped = 0
    foreach ($f in Get-ChildItem -LiteralPath $flatDir -File -ErrorAction SilentlyContinue) {
        $dest = Join-Path $unfiledDir $f.Name
        if (Test-Path $dest) {
            $skipped++
            continue
        }
        if ($WhatIf) {
            Write-Host "[vortex-os]   (whatif) $f -> _unfiled\$($f.Name)" -ForegroundColor Cyan
            $moved++
        } else {
            Move-Item -LiteralPath $f.FullName -Destination $dest
            Write-Host "[vortex-os]   $f -> _unfiled\$($f.Name)" -ForegroundColor Green
            $moved++
        }
    }

    Write-Host ""
    Write-Host "[vortex-os] -AdoptFlat summary: moved=$moved skipped=$skipped" -ForegroundColor Cyan
    if ($moved -gt 0 -and -not $WhatIf) {
        Write-Host ""
        Write-Host "[vortex-os] Legacy files are now in $unfiledDir." -ForegroundColor Green
        Write-Host "  - review them with:  Get-ChildItem '$unfiledDir'" -ForegroundColor Gray
        Write-Host "  - file a file into a project:  Move-Item '$unfiledDir\<file>' '<projectDir>'" -ForegroundColor Gray
        Write-Host "  - or leave them in _unfiled/ as the v0.1.4-and-before archive" -ForegroundColor Gray
    }
}
