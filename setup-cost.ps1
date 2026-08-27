# =============================================================================
# setup-cost.ps1 — VORTEX-OS cost tracking one-time setup
# =============================================================================
# Generates the default model_prices.json + budgets.json at
# $VORTEX_HOME\.vortex\ so the engine's CostTracker can find them.
# Idempotent: re-running overwrites the defaults but preserves any custom
# edits the user has made.
#
# Usage:
#   pwsh -NoProfile -File .\setup-cost.ps1
#   pwsh -NoProfile -File .\setup-cost.ps1 -WhatIf
#   $env:VORTEX_BUDGET_USD_TOTAL=200; pwsh -NoProfile -File .\setup-cost.ps1
# =============================================================================
[CmdletBinding()]
param(
    [string] $VortexHome = $env:VORTEX_HOME
)

$ErrorActionPreference = 'Stop'
if (-not $VortexHome) { $VortexHome = Join-Path $env:APPDATA 'Vortex-OS' }

$vortexDir = Join-Path $VortexHome '.vortex'
if (-not (Test-Path $vortexDir)) {
    New-Item -ItemType Directory -Path $vortexDir -Force | Out-Null
}

# ---- 1. model_prices.json ---------------------------------------------------
$pricesFile = Join-Path $vortexDir 'model_prices.json'
$pricesDefault = @'
{
  "_comment": "Cost per 1K tokens in USD. Edit this file to add or update model prices. Unknown models fall back to the 'default' entry.",
  "models": {
    "MiniMax-Text-01":      { "in": 0.0008, "out": 0.0024 },
    "MiniMax-Text-02":      { "in": 0.0010, "out": 0.0030 },
    "MiniMax-Music":        { "in": 0.0,    "out": 0.05,  "per_request": true },
    "MiniMax-Hailuo-2.3":   { "in": 0.0,    "out": 0.30,  "per_request": true, "per_second": 0.05 },
    "MiniMax-H3":           { "in": 0.0,    "out": 0.50,  "per_request": true, "per_second": 0.08 },
    "MiniMax-Image":        { "in": 0.0,    "out": 0.04,  "per_request": true },
    "MiniMax-TTS":          { "in": 0.0,    "out": 0.02,  "per_request": true }
  },
  "default": { "in": 0.001, "out": 0.002 }
}
'@
if (Test-Path $pricesFile) {
    Write-Host "  ~ model_prices.json already exists at $pricesFile" -ForegroundColor DarkYellow
} else {
    Set-Content -Path $pricesFile -Value $pricesDefault -Encoding UTF8
    Write-Host "  + Wrote $pricesFile" -ForegroundColor Green
}

# ---- 2. budgets.json (global defaults; per-project overrides go in <project>/_meta.json) -
$budgetsFile = Join-Path $vortexDir 'budgets.json'
$envBudget = $env:VORTEX_BUDGET_USD_TOTAL
$envTokens = $env:VORTEX_BUDGET_TOKENS_TOTAL
$budgetsDefault = @"
{
  "_comment": "Global default budget. Override per-project via skill.ps1 --budget-set or per-env via \$env:VORTEX_BUDGET_USD_TOTAL / \$env:VORTEX_BUDGET_TOKENS_TOTAL. 0 means no budget (no alerts).",
  "default_usd_total": $envBudget,
  "default_tokens_total": $envTokens
}
"@
if (Test-Path $budgetsFile) {
    Write-Host "  ~ budgets.json already exists at $budgetsFile" -ForegroundColor DarkYellow
} else {
    Set-Content -Path $budgetsFile -Value $budgetsDefault -Encoding UTF8
    Write-Host "  + Wrote $budgetsFile (usd_total=$envBudget tokens_total=$envTokens)" -ForegroundColor Green
}

Write-Host ""
Write-Host "VORTEX-OS cost tracking setup complete." -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Set a project budget:  pwsh skill.ps1 -Project trial_of_echoes --budget-set --project trial_of_echoes --usd-total 200"
Write-Host "  2. Run a dispatch:        pwsh skill.ps1 -Project trial_of_echoes --dispatch-master objectives\ep1.md"
Write-Host "  3. View the cost report:  pwsh skill.ps1 --cost-report --project trial_of_echoes"
Write-Host "  4. JSON for CI:           pwsh skill.ps1 --cost-report --project trial_of_echoes --json"
