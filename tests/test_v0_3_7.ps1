#Requires -Version 7.0
<#
.SYNOPSIS
    v0.3.7 acceptance tests for the install + path-forwarding fixes.

.DESCRIPTION
    Closes G21 (install.ps1 crashes when VORTEX_HOME is unset) and G22
    (skill.ps1 forwards relative template paths verbatim so the engine can't
    find them from its module-folder CWD).

    Each test reproduces the exact failure mode in isolation.

    Tests:
      G22. install.ps1 with VORTEX_HOME unset does NOT throw "Cannot bind
            argument to parameter 'Path' because it is null"
      G23. skill.ps1 --dispatch-template <relative-path> finds the template
            (does NOT bail with "Usage: skill.exe --dispatch-template ...")

    Exits 0 on success, 1 on any failure.
#>
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$skillPath = Join-Path $root 'skill.ps1'
$installPath = Join-Path $root 'install.ps1'
if (-not (Test-Path $skillPath)) { throw "skill.ps1 not found at $skillPath" }
if (-not (Test-Path $installPath)) { throw "install.ps1 not found at $installPath" }

$g_pass = 0
$g_fail = 0
function Check {
    param([string]$Label, [scriptblock]$Test)
    $result = & $Test
    if ($result) {
        $script:g_pass++
        Write-Host "  PASS  $Label"
    } else {
        $script:g_fail++
        Write-Host "  FAIL  $Label" -ForegroundColor Red
    }
}

# -----------------------------------------------------------------------
# G22: install.ps1 with VORTEX_HOME unset does NOT throw
# "Cannot bind argument to parameter 'Path' because it is null"
#
# Before the fix, line 104 referenced the undefined local $vortexHome
# (lowercase, no $env: prefix) even though line 53-55 set $env:VORTEX_HOME.
# The error fired on the cache-file path resolution before the GitHub
# release lookup could run.
# -----------------------------------------------------------------------
Write-Host "[G22] install.ps1 with VORTEX_HOME unset"
Write-Host "==========================================="
$installOut = (& pwsh -NoProfile -Command "
    Remove-Item Env:\VORTEX_HOME -ErrorAction SilentlyContinue
    & '$installPath' *>&1
    exit 0
" 2>&1 | Out-String)
Write-Host "--- raw install.ps1 output ---"
$installOut.Split("`n") | ForEach-Object { Write-Host "  $_" }

Check "G22: install.ps1 does NOT throw 'Cannot bind argument to parameter Path'" {
    $installOut -notmatch "Cannot bind argument to parameter 'Path' because it is null"
}
Check "G22: install.ps1 gets past the cache-file resolution" {
    # After the fix, install.ps1 should either succeed (no-op install) or
    # progress to the network call. The first thing it prints AFTER the
    # cache resolution is "[vortex-os] Resolving latest release of ..." or
    # "[vortex-os] v$Version already installed at ..." or
    # "[vortex-os] Using cached latest release:".
    $installOut -match "Resolving latest release|already installed|Using cached latest release"
}

# -----------------------------------------------------------------------
# G23: skill.ps1 --dispatch-template <relative-path> finds the template
#
# Before the fix, Import-Module Vortex changed the .NET CurrentDirectory
# to the Vortex module folder. The engine's File::Exists on the relative
# path returned false (path was relative to the module folder, not the
# skill folder), and the engine bailed with "Usage: skill.exe ...".
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[G23] skill.ps1 --dispatch-template <relative-path>"
Write-Host "====================================================="
$scratchG23 = Join-Path $env:TEMP "vortex-g23-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
$g23Out = (& pwsh -NoProfile -Command "
    \$env:VORTEX_HOME = '$scratchG23'
    \$env:VORTEX_NO_AUTO_UPDATE = '1'
    New-Item -ItemType Directory -Path \$env:VORTEX_HOME -Force | Out-Null
    Set-Location '$root'
    & '.\skill.ps1' --dispatch-template '.\templates\iteration_pattern.json' 2>&1
" 2>&1 | Out-String)
Write-Host "--- raw skill.ps1 output ---"
$g23Out.Split("`n") | ForEach-Object { Write-Host "  $_" }

Check "G23: skill.ps1 does NOT bail with 'Usage: skill.exe --dispatch-template'" {
    $g23Out -notmatch "Usage: skill.exe --dispatch-template"
}
Check "G23: skill.ps1 prints the 'Template:' banner" {
    $g23Out -match "Template: "
}

# -----------------------------------------------------------------------
# G25: SDK + all plugins parse as PowerShell (v0.3.7)
# The v0.3.5 plugin-sdk had a `$status:` scope-qualifier parse error
# at line 328 that broke EVERY plugin invocation silently. We now
# parse-check the SDK + every plugin before shipping.
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[G25] PowerShell parse check on plugin SDK + all plugin invoke.ps1"
$parseFiles = @()
$parseFiles += Get-ChildItem -Path (Join-Path $PSScriptRoot '..\plugin-sdk') -Filter '*.psm1' -ErrorAction SilentlyContinue
$parseFiles += Get-ChildItem -Path (Join-Path $PSScriptRoot '..\plugins') -Filter 'invoke.ps1' -Recurse -ErrorAction SilentlyContinue
$parseFiles += Get-ChildItem -Path (Join-Path $PSScriptRoot '..\plugins') -Filter '*.psm1' -Recurse -ErrorAction SilentlyContinue
$parseErrCount = 0
$parseFilesChecked = 0
foreach ($f in $parseFiles) {
    $parseFilesChecked++
    $perr = $null
    $ptok = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$ptok, [ref]$perr) | Out-Null
    if ($perr -and $perr.Count -gt 0) {
        $parseErrCount += $perr.Count
        Write-Host "  PARSE ERROR in $($f.FullName):" -ForegroundColor Red
        $perr | ForEach-Object { Write-Host "    Line $($_.Extent.StartLineNumber): $($_.Message)" -ForegroundColor Red }
    }
}
Write-Host "  parse-checked $parseFilesChecked files, $parseErrCount errors"
Check "G25: SDK + plugins parse with zero errors" { $parseErrCount -eq 0 }

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "================================="
Write-Host "Passed: $g_pass    Failed: $g_fail"
Write-Host ""
if ($g_fail -gt 0) {
    Write-Host "TESTS FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "ALL TESTS PASSED" -ForegroundColor Green
exit 0
