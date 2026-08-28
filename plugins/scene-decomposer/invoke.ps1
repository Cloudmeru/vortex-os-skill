# scene-decomposer plugin -- reads a source document and produces a
# structured scene manifest + production bible.
#
# v0.3.6: primary path is the MiniMax LLM (text generation) which
# returns a JSON scene list. Fallback is a deterministic rule-based
# splitter (H2 -> H3 -> blank-paragraph).
#
# The director.cinematic agent calls this once per dispatch; the
# resulting production_bible.json + scenes.json is read by every
# downstream worker so all clips share characters / palette / voice /
# aspect.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force

$inputs = Get-VortexPluginInput
$sourcePath = $inputs.source_markdown
$title = if ($inputs.PSObject.Properties.Name -contains 'title') { $inputs.title } else { [System.IO.Path]::GetFileNameWithoutExtension($sourcePath) }
$targetDur = if ($inputs.PSObject.Properties.Name -contains 'target_duration_s') { [int]$inputs.target_duration_s } else { 60 }
$maxSceneS = if ($inputs.PSObject.Properties.Name -contains 'max_scene_s') { [int]$inputs.max_scene_s } else { 8 }
$aspect = if ($inputs.PSObject.Properties.Name -contains 'aspect') { $inputs.aspect } else { '16:9' }
$style  = if ($inputs.PSObject.Properties.Name -contains 'style') { $inputs.style } else { 'cinematic' }
$palette = if ($inputs.PSObject.Properties.Name -contains 'palette') { $inputs.palette } else { 'cool teal and warm amber, low contrast' }
$voice = if ($inputs.PSObject.Properties.Name -contains 'voice') { $inputs.voice } else { 'default' }
$charactersIn = if ($inputs.PSObject.Properties.Name -contains 'characters') { $inputs.characters } else { '' }

Write-VortexPluginLog "scene-decomposer invoked: source='$sourcePath' target=${targetDur}s max_scene=${maxSceneS}s aspect=$aspect"

# Read the source
if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "source_markdown not found: $sourcePath"
}
$source = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8
$sourceLen = $source.Length
Write-VortexPluginLog "source length: $sourceLen chars"

# Compute output paths under the project's state dir
$vortexHome = $env:VORTEX_HOME
if (-not $vortexHome) { $vortexHome = Join-Path $env:APPDATA 'Vortex-OS' }
$project = if ($env:VORTEX_PROJECT) { $env:VORTEX_PROJECT } else { 'default' }
$stateDir = Join-Path $vortexHome 'state' $project 'production'
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
$biblePath  = Join-Path $stateDir 'production_bible.json'
$scenesPath = Join-Path $stateDir 'scenes.json'
$manifestPath = $scenesPath   # canonical output

# ---------------------------------------------------------------------------
# Path 1: MiniMax LLM (primary) -- ask the LLM to return a JSON scene list
# ---------------------------------------------------------------------------
$provider = 'rule-based'
$scenes = $null
$bible = $null

if ($env:MINIMAX_API_KEY -or $env:VORTEX_MINIMAX_API_KEY) {
    try {
        Write-VortexPluginLog "trying MiniMax LLM path (max_scene=${maxSceneS}s, target=${targetDur}s)"
        $systemPrompt = @"
You are a cinematic scene director. Given a source document, a target total duration, and a max scene duration, produce a JSON object with two top-level keys:

1. "production_bible" -- a single object describing the project's visual + audio + narrative continuity:
   {
     "title": "<title>",
     "style": "<style hint, e.g. 'cinematic'>",
     "palette": "<color palette hint, e.g. 'cool teal and warm amber, low contrast'>",
     "voice": "<voice preset>",
     "aspect": "<aspect ratio>",
     "characters": [
       { "name": "<character name>", "description": "<one-sentence visual + personality description>", "voice": "<voice preset>" }
     ]
   }

2. "scenes" -- a JSON array of scenes. Each scene is:
   {
     "index": <1-based integer>,
     "duration_s": <integer between 4 and max_scene_s>,
     "title": "<short scene title>",
     "visual_brief": "<2-3 sentence description of what the camera sees, including character positions and palette hint>",
     "audio_brief": "<the spoken copy or sound design notes for this scene>",
     "transition_in": "<cut | fade | crossfade>",
     "transition_out": "<cut | fade | crossfade>",
     "characters": [<character names present in this scene>],
     "deliverable_refs": {
       "hero": "imgs/scene-<NN>-hero.png",
       "voiceover": "audio/scene-<NN>-voiceover.wav",
       "video": "video/scene-<NN>-clip.mp4"
     }
   }

Hard rules:
- Total scene durations should sum to approximately target_duration_s (+/- 10%).
- Each scene must be >= 4s and <= max_scene_s.
- The same character appearing in multiple scenes must have the SAME description across scenes (copy verbatim).
- The palette hint MUST appear (verbatim) in every visual_brief that involves a real-world setting.
- The voice preset MUST be the same for every scene that has audio.
- Return ONLY the JSON object. No prose, no markdown fences.
"@
        $userPrompt = @"
target_duration_s: $targetDur
max_scene_s: $maxSceneS
aspect: $aspect
style: $style
palette: $palette
voice: $voice
pre_defined_characters:
$($charactersIn | Out-String)

source:
$source
"@
        $llmOut = Invoke-MiniMaxLLM -SystemPrompt $systemPrompt -Prompt $userPrompt -Model 'MiniMax-Text-01' -MaxTokens 4096
        # Strip markdown code fences if the LLM added them
        $clean = $llmOut -replace '(?s)^```(?:json)?\s*', '' -replace '(?s)\s*```\s*$', ''
        $obj = $clean | ConvertFrom-Json
        $bible  = $obj.production_bible
        $scenes = $obj.scenes
        if (-not $bible -or -not $scenes) { throw "LLM response missing production_bible or scenes" }
        $provider = 'minimax-llm'
        Write-VortexPluginLog "LLM produced $($scenes.Count) scenes"
    } catch {
        Write-VortexPluginLog "MiniMax LLM path failed: $($_.Exception.Message) -- falling back to rule-based"
    }
}

# ---------------------------------------------------------------------------
# Path 2: rule-based fallback -- split on H2, then H3, then blank-paragraph
# ---------------------------------------------------------------------------
if (-not $scenes -or -not $bible) {
    Write-VortexPluginLog "using rule-based fallback (H2 -> H3 -> blank-paragraph splitter)"

    # Split the source on H2 headings first, then H3 if no H2, then blank lines
    $h2Pattern = '(?m)^##\s+'
    $h3Pattern = '(?m)^###\s+'
    $paragraphPattern = '(?m)^$'

    $sections = @()
    if ($source -match $h2Pattern) {
        # Split on H2, keep the H2 header as the first line of each section
        $sections = [regex]::Split($source, $h2Pattern) | Where-Object { $_.Trim() } | ForEach-Object {
            $lines = $_ -split "`r?`n"
            $header = $lines[0].Trim()
            $body = ($lines[1..($lines.Count-1)] -join "`n").Trim()
            [pscustomobject]@{ title = $header; body = $body }
        }
    } elseif ($source -match $h3Pattern) {
        $sections = [regex]::Split($source, $h3Pattern) | Where-Object { $_.Trim() } | ForEach-Object {
            $lines = $_ -split "`r?`n"
            $header = $lines[0].Trim()
            $body = ($lines[1..($lines.Count-1)] -join "`n").Trim()
            [pscustomobject]@{ title = $header; body = $body }
        }
    } else {
        # Split on blank-line paragraphs
        $sections = ($source -split "`r?`n`r?`n") | Where-Object { $_.Trim() } | ForEach-Object {
            $firstLine = ($_ -split "`r?`n")[0].Trim()
            if ($firstLine.Length -gt 80) { $firstLine = $firstLine.Substring(0, 77) + '...' }
            [pscustomobject]@{ title = $firstLine; body = $_.Trim() }
        }
    }
    if (-not $sections -or $sections.Count -eq 0) {
        # Last-ditch: one big section
        $sections = @([pscustomobject]@{ title = $title; body = $source })
    }

    # Allocate target duration proportionally to section length (with a min 4s and max maxSceneS)
    $totalChars = ($sections | Measure-Object -Property body -Sum).Sum
    if ($totalChars -le 0) { $totalChars = 1 }
    $scenes = @()
    $i = 0
    foreach ($sec in $sections) {
        $i++
        $alloc = [int][Math]::Round(($sec.body.Length / $totalChars) * $targetDur)
        $alloc = [Math]::Max(4, [Math]::Min($maxSceneS, $alloc))
        # Extract the first sentence as the audio brief
        $firstSentence = ($sec.body -split '(?<=[.!?])\s+')[0]
        if ($firstSentence.Length -gt 280) { $firstSentence = $firstSentence.Substring(0, 277) + '...' }
        $scenes += [pscustomobject]@{
            index          = $i
            duration_s     = $alloc
            title          = $sec.title
            visual_brief   = "$style shot of: $($sec.title). Palette: $palette. Aspect: $aspect."
            audio_brief    = $firstSentence
            transition_in  = if ($i -eq 1) { 'cut' } else { 'crossfade' }
            transition_out = if ($i -eq $sections.Count) { 'fade' } else { 'crossfade' }
            characters     = @()
            deliverable_refs = @{
                hero      = "imgs/scene-$(('{0:D2}' -f $i))-hero.png"
                voiceover = "audio/scene-$(('{0:D2}' -f $i))-voiceover.wav"
                video     = "video/scene-$(('{0:D2}' -f $i))-clip.mp4"
            }
        }
    }
    $bible = [pscustomobject]@{
        title   = $title
        style   = $style
        palette = $palette
        voice   = $voice
        aspect  = $aspect
        characters = @()
    }
}

# ---------------------------------------------------------------------------
# Persist the bible + scenes
# ---------------------------------------------------------------------------
$bible  | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $biblePath  -Encoding UTF8
$scenes | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $scenesPath -Encoding UTF8

$totalDur = ($scenes | Measure-Object -Property duration_s -Sum).Sum
Write-VortexPluginLog "wrote: $biblePath, $scenesPath (provider=$provider, scenes=$($scenes.Count), total=${totalDur}s)"

Write-VortexPluginOutput @{
    manifest_path    = $manifestPath
    scene_count      = $scenes.Count
    total_duration_s = $totalDur
    provider         = $provider
}
