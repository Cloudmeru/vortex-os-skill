# audio-voice plugin -- TTS narration
# v0.3.5: defaults to mcode-tools synthesize_speech, falls back to SAPI TTS,
# then to silent WAV. The plugin ALWAYS produces a valid output file --
# the provider used is reported via Write-VortexPluginLog so the operator
# can see which path fired in the audit trail.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force

$inputs = Get-VortexPluginInput
$text = $inputs.text
$voice = if ($inputs.PSObject.Properties.Name -contains 'voice') { $inputs.voice } else { 'default' }
$format = if ($inputs.PSObject.Properties.Name -contains 'format') { $inputs.format } else { 'wav' }
Write-VortexPluginLog "audio-voice invoked: text_len=$($text.Length) voice=$voice format=$format"

# Build output path
$vortexHome = $env:VORTEX_HOME
if (-not $vortexHome) { $vortexHome = Join-Path $env:APPDATA 'Vortex-OS' }
$project = if ($env:VORTEX_PROJECT) { $env:VORTEX_PROJECT } else { 'default' }
$outDir = Join-Path $vortexHome 'deliverables' $project
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$ts = Get-Date -Format 'yyyyMMddHHmmss'
$outFile = Join-Path $outDir "voice_${ts}.${format}"

# Try mcode-tools first; fall back to SAPI TTS, then silent WAV
$result = Invoke-VortexWithFallback `
    -ToolName 'connector__matrix__synthesize_speech' `
    -Args @{ text = $text; voice_id = $voice; output_file = "voice_${ts}.${format}" } `
    -DownloadTo $outFile `
    -Fallback {
        param($a, $out)
        # Try SAPI TTS first; if that fails, write a silent WAV
        $text2 = $a.text
        $voice2 = if ($a.PSObject.Properties.Name -contains 'voice_id') { $a.voice_id } else { 'default' }
        New-VortexSapiTtsWav -Text $text2 -OutFile $out -Voice $voice2
    }

Write-VortexPluginLog "audio-voice: produced via $($result.Provider)"
Write-VortexPluginOutput @{ file = $result.File; format = $format; provider = $result.Provider }
