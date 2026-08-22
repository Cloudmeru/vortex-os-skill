# =============================================================================
# skill.ps1 — VORTEX-OS dispatcher entry point (PowerShell 7+)
# =============================================================================
# Drop-in replacement for the old `./skill.sh` / `skill.exe` CLI. Loads the
# Vortex.psm1 module and forwards every argument to the C++/CLI dispatcher.
#
# Usage (any of these work):
#   pwsh -NoProfile -File .\skill.ps1 --agents-discover
#   pwsh -NoProfile -File .\skill.ps1 --dispatch-master my_project\objective.md
#   .\skill.ps1 --hitl-approve package_websim      (PS7 only; PS5 not supported)
#
# After this script runs once, the module stays loaded in the session:
#   PS> . .\skill.ps1            # dot-source for REPL use
#   PS> Get-VortexAgent
#   PS> Get-VortexHitlPending
#   PS> Approve-VortexHitl -TaskId package_websim
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Arguments
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Load the module (which Add-Types Vortex.dll). Idempotent.
Import-Module (Join-Path $here 'Vortex.psd1') -Force

# Forward every argument to the C++/CLI dispatcher. When invoked with no
# args, the dispatcher prints the help banner and returns 0.
$rc = Invoke-Vortex -Arguments $Arguments
exit $rc
