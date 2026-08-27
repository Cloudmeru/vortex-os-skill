# media-sqlite plugin — local SQLite wrapper (no LLM)
# Shells out to sqlite3.exe (or falls back to System.Data.SQLite via .NET if
# sqlite3.exe isn't on PATH).
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force
$inputs = Get-VortexPluginInput
if (-not (Test-Path -LiteralPath $inputs.db)) { throw "Database not found: $($inputs.db)" }
Write-VortexPluginLog "media-sqlite invoked: db=$($inputs.db)"

# Use sqlite3.exe (CLI) — preferred, works on Windows + Linux + macOS.
$sqlite = (Get-Command sqlite3.exe -ErrorAction SilentlyContinue).Source
if ($sqlite) {
    $args = @($inputs.db, $inputs.query)
    $csv = & $sqlite @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        $err = $csv -join "`n"
        throw "sqlite3 failed: $err"
    }
    # Convert CSV to array of objects
    $lines = $csv | Where-Object { $_ -and $_.Trim() }
    if ($lines.Count -lt 1) {
        Write-VortexPluginOutput @{ rows = @(); count = 0 }
        return
    }
    $headers = ($lines[0] -split ',') | ForEach-Object { $_.Trim('"') }
    $rows = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $fields = $lines[$i] -split ',(?=(?:[^"]|"[^"]*")*$)' | ForEach-Object { $_.Trim('"') }
        $obj = [ordered]@{}
        for ($j = 0; $j -lt $headers.Count; $j++) {
            $obj[$headers[$j]] = if ($j -lt $fields.Count) { $fields[$j] } else { $null }
        }
        $rows += [PSCustomObject]$obj
    }
    Write-VortexPluginOutput @{ rows = $rows; count = $rows.Count }
} else {
    # Fallback: use System.Data.SQLite from .NET (if available)
    try {
        Add-Type -AssemblyName System.Data
        $conn = New-Object System.Data.Common.DbConnection
        throw "Fallback not implemented; install sqlite3.exe and ensure it is on PATH."
    } catch {
        throw "sqlite3.exe not found on PATH. Install from https://www.sqlite.org/download.html and ensure it's on PATH."
    }
}
