# =============================================================================
# verify.ps1 — VORTEX-OS post-upload verification (PowerShell 7+)
# =============================================================================
# Loads Vortex.psm1 and invokes Vortex.Verify::Run() against the package root.
# Returns exit code 0 on full success, 1 on any failure.
#
# Usage:
#   pwsh -NoProfile -File .\verify.ps1
#   .\verify.ps1
# =============================================================================
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

Import-Module (Join-Path $here 'Vortex.psd1') -Force

# Vortex.Verify returns 0 on success, 1 on failure. The C++/CLI side also
# writes a human-readable summary (✓ / ✗) to stdout.
$rc = [Vortex.Verify]::Run($here)
exit $rc
