# editor.stitch plugin -- ffmpeg-based scene stitcher + audio mixer.
# v0.3.6: director.cinematic calls this once per dispatch as the
# packager step. Defaults to local ffmpeg (no mcode-tools call needed --
# this is a pure local post-production step).
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sdkPath = Join-Path $PSScriptRoot '..\..\plugin-sdk\Vortex.Plugin.psm1'
Import-Module $sdkPath -Force

$inputs = Get-VortexPluginInput
$scenesManifest = $inputs.scenes_manifest
$videoDir      = $inputs.scene_video_dir
$voiceDir      = if ($inputs.PSObject.Properties.Name -contains 'scene_voice_dir') { $inputs.scene_voice_dir } else { '' }
$bgmFile       = if ($inputs.PSObject.Properties.Name -contains 'bgm_file') { $inputs.bgm_file } else { '' }
$volVoice      = if ($inputs.PSObject.Properties.Name -contains 'volume_voice_db') { [double]$inputs.volume_voice_db } else { 0 }
$volBgm        = if ($inputs.PSObject.Properties.Name -contains 'volume_bgm_db') { [double]$inputs.volume_bgm_db } else { -12 }
$crossfadeS    = if ($inputs.PSObject.Properties.Name -contains 'crossfade_s') { [double]$inputs.crossfade_s } else { 0.5 }

Write-VortexPluginLog "editor.stitch invoked: manifest='$scenesManifest' video_dir='$videoDir' voice_dir='$voiceDir' bgm='$bgmFile' crossfade=${crossfadeS}s"

# Locate ffmpeg
$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ffmpeg) {
    Write-VortexPluginLog "ffmpeg not on PATH -- placeholder-text fallback"
    $vortexHome = $env:VORTEX_HOME
    if (-not $vortexHome) { $vortexHome = Join-Path $env:APPDATA 'Vortex-OS' }
    $project = if ($env:VORTEX_PROJECT) { $env:VORTEX_PROJECT } else { 'default' }
    $outDir = Join-Path $vortexHome 'deliverables' $project
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $outFile = if ($inputs.PSObject.Properties.Name -contains 'output') { $inputs.output } else { Join-Path $outDir "${project}-final.mp4" }
    "VORTEX-OS editor.stitch fallback: ffmpeg not on PATH" | Set-Content -LiteralPath $outFile -Encoding UTF8
    Write-VortexPluginOutput @{ file = $outFile; duration_s = 0; scene_count = 0; command = 'fallback-text'; provider = 'local-placeholder-text' }
    return
}

# Load the scene manifest
if (-not (Test-Path -LiteralPath $scenesManifest)) { throw "scenes_manifest not found: $scenesManifest" }
$scenes = Get-Content -LiteralPath $scenesManifest -Raw | ConvertFrom-Json
if (-not $scenes -or $scenes.Count -eq 0) { throw "scenes_manifest is empty" }
Write-VortexPluginLog "loaded $($scenes.Count) scenes from manifest"

# Resolve the per-scene video paths
$sceneVideos = @()
foreach ($s in $scenes) {
    $basename = Split-Path -Leaf $s.deliverable_refs.video
    $path = Join-Path $videoDir $basename
    if (-not (Test-Path -LiteralPath $path)) {
        throw "scene video not found: $path (scene $($s.index))"
    }
    $sceneVideos += $path
}
Write-VortexPluginLog "found $($sceneVideos.Count) scene video files"

# Build output path
$vortexHome = $env:VORTEX_HOME
if (-not $vortexHome) { $vortexHome = Join-Path $env:APPDATA 'Vortex-OS' }
$project = if ($env:VORTEX_PROJECT) { $env:VORTEX_PROJECT } else { 'default' }
$outDir = Join-Path $vortexHome 'deliverables' $project
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$outFile = if ($inputs.PSObject.Properties.Name -contains 'output') { $inputs.output } else { Join-Path $outDir "${project}-final.mp4" }

# Build a temp working dir for the intermediate concat list + audio tracks
$tmpDir = Join-Path $env:TEMP ("vortex-stitch-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

try {
    # ---------------------------------------------------------------------
    # Step 1: Build a single concatenated voiceover track + a single BGM
    #         track (looped to match duration). Then amix them.
    # ---------------------------------------------------------------------
    $voiceParts = @()
    if ($voiceDir -and (Test-Path -LiteralPath $voiceDir)) {
        foreach ($s in $scenes) {
            $basename = Split-Path -Leaf $s.deliverable_refs.voiceover
            $p = Join-Path $voiceDir $basename
            if (Test-Path -LiteralPath $p) { $voiceParts += $p }
        }
    }
    Write-VortexPluginLog "voiceover files: $($voiceParts.Count)"

    $voiceTrack = if ($voiceParts.Count -gt 0) {
        # Concatenate voiceover parts
        $concatList = Join-Path $tmpDir 'voice_concat.txt'
        $sb = [System.Text.StringBuilder]::new()
        foreach ($p in $voiceParts) { [void]$sb.AppendLine("file '$($p -replace '\\','/')'") }
        Set-Content -LiteralPath $concatList -Value $sb.ToString() -Encoding UTF8
        $concatOut = Join-Path $tmpDir 'voice_full.wav'
        $args = @('-y', '-f', 'concat', '-safe', '0', '-i', $concatList, '-c', 'copy', $concatOut)
        $proc = Start-Process -FilePath $ffmpeg -ArgumentList $args -NoNewWindow -PassThru -Wait
        if ($proc.ExitCode -ne 0) { throw "ffmpeg voice concat failed (exit=$($proc.ExitCode))" }
        $concatOut
    } else { $null }

    # Total runtime in seconds (sum of scene durations)
    $totalDur = ($scenes | Measure-Object -Property duration_s -Sum).Sum
    Write-VortexPluginLog "total target duration: ${totalDur}s"

    # Build audio mix command if we have voiceover OR BGM
    $mixedAudio = $null
    if ($voiceTrack -or ($bgmFile -and (Test-Path -LiteralPath $bgmFile))) {
        $filterParts = @()
        $inputs_ = @()
        if ($voiceTrack) {
            $inputs_ += @('-i', $voiceTrack)
            $voiceIdx = $inputs_.Count / 2 - 1   # 0-based
            $filterParts += "[$voiceIdx]volume=$([Math]::Pow(10, $volVoice/20))[v]"
        }
        if ($bgmFile -and (Test-Path -LiteralPath $bgmFile)) {
            $bgmIdx = $inputs_.Count / 2
            $filterParts += "[$bgmIdx]volume=$([Math]::Pow(10, $volBgm/20)),aloop=loop=-1:size=2e9[bgm]"
        }
        $amixInputs = @()
        if ($voiceTrack) { $amixInputs += '[v]' }
        if ($bgmFile -and (Test-Path -LiteralPath $bgmFile)) { $amixInputs += '[bgm]' }
        $filterComplex = ($filterParts -join ';') + ';' + ($amixInputs -join '') + "amix=inputs=$($amixInputs.Count):duration=first:normalize=0[aout]"

        $filterFile = Join-Path $tmpDir 'audio_filter.txt'
        Set-Content -LiteralPath $filterFile -Value $filterComplex -Encoding UTF8

        $mixedAudio = Join-Path $tmpDir 'mixed_audio.wav'
        $args = @('-y') + $inputs_ + @('-filter_complex', $filterComplex, '-map', '[aout]', '-c:a', 'aac', '-b:a', '192k', $mixedAudio)
        Write-VortexPluginLog "audio mix command: ffmpeg $($args -join ' ')"
        $proc = Start-Process -FilePath $ffmpeg -ArgumentList $args -NoNewWindow -PassThru -Wait
        if ($proc.ExitCode -ne 0) {
            Write-VortexPluginLog "audio mix failed (exit=$($proc.ExitCode)) -- continuing with video-only output"
            $mixedAudio = $null
        }
    }

    # ---------------------------------------------------------------------
    # Step 2: Stitch the scene videos with xfade transitions
    # ---------------------------------------------------------------------
    # Build a complex xfade filter chain. For N scenes we have N-1 xfades.
    # We use ffmpeg's xfade filter with offset = sum(durations[0..i]) - crossfade
    $filterParts = @()
    $labels = @()
    for ($i = 0; $i -lt $sceneVideos.Count; $i++) {
        $labels += "[v$i]"
    }
    $runningLabel = 'v0'
    $cumDur = [double]$scenes[0].duration_s
    for ($i = 1; $i -lt $sceneVideos.Count; $i++) {
        $nextLabel = "x$i"
        $transition = $scenes[$i].transition_in
        $xfadeType = switch ($transition) {
            'fade'      { 'fade' }
            'crossfade' { 'fade' }   # both use the same xfade filter; 'fade' is essentially crossfade
            default     { 'fade' }
        }
        $offset = $cumDur - $crossfadeS
        if ($offset -lt 0) { $offset = 0 }
        $filterParts += "[$runningLabel][v$i]xfade=transition=$xfadeType:duration=$crossfadeS:offset=$offset[$nextLabel]"
        $runningLabel = $nextLabel
        $cumDur += [double]$scenes[$i].duration_s
    }
    $filterComplex = $filterParts -join ';'

    $videoOnly = Join-Path $tmpDir 'video_only.mp4'
    $args = @('-y')
    foreach ($v in $sceneVideos) { $args += @('-i', $v) }
    $args += @('-filter_complex', $filterComplex, '-map', "[$runningLabel]", '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-r', '24', $videoOnly)

    $cmdStr = 'ffmpeg ' + ($args -join ' ')
    Write-VortexPluginLog "stitch command: $cmdStr"
    $proc = Start-Process -FilePath $ffmpeg -ArgumentList $args -NoNewWindow -PassThru -Wait
    if ($proc.ExitCode -ne 0) {
        Write-VortexPluginLog "xfade stitch failed (exit=$($proc.ExitCode)) -- falling back to plain concat"
        # Fallback: plain concat (no transitions)
        $concatList = Join-Path $tmpDir 'video_concat.txt'
        $sb = [System.Text.StringBuilder]::new()
        foreach ($p in $sceneVideos) { [void]$sb.AppendLine("file '$($p -replace '\\','/')'") }
        Set-Content -LiteralPath $concatList -Value $sb.ToString() -Encoding UTF8
        $args = @('-y', '-f', 'concat', '-safe', '0', '-i', $concatList, '-c:v', 'libx264', '-pix_fmt', 'yuv420p', $videoOnly)
        $cmdStr = 'ffmpeg ' + ($args -join ' ')
        $proc = Start-Process -FilePath $ffmpeg -ArgumentList $args -NoNewWindow -PassThru -Wait
        if ($proc.ExitCode -ne 0) { throw "ffmpeg plain concat also failed (exit=$($proc.ExitCode))" }
    }

    # ---------------------------------------------------------------------
    # Step 3: Mux the video with the mixed audio (or copy video-only)
    # ---------------------------------------------------------------------
    if ($mixedAudio -and (Test-Path -LiteralPath $mixedAudio)) {
        $args = @('-y', '-i', $videoOnly, '-i', $mixedAudio, '-c:v', 'copy', '-c:a', 'aac', '-shortest', $outFile)
        $cmdStr = 'ffmpeg ' + ($args -join ' ')
        Write-VortexPluginLog "final mux command: $cmdStr"
        $proc = Start-Process -FilePath $ffmpeg -ArgumentList $args -NoNewWindow -PassThru -Wait
        if ($proc.ExitCode -ne 0) { throw "ffmpeg final mux failed (exit=$($proc.ExitCode))" }
    } else {
        # Just copy the video-only output to the final location
        Copy-Item -LiteralPath $videoOnly -Destination $outFile -Force
        $cmdStr = "ffmpeg (video-only, no audio) -> $outFile"
    }

    # Probe the final duration
    $finalDur = 0
    $ffprobe = (Get-Command ffprobe -ErrorAction SilentlyContinue).Source
    if ($ffprobe) {
        $probeOut = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $outFile
        $finalDur = [double]$probeOut
    }

    Write-VortexPluginLog "wrote: $outFile (duration=${finalDur}s, scenes=$($sceneVideos.Count))"
    Write-VortexPluginOutput @{
        file        = (Resolve-Path -LiteralPath $outFile).Path
        duration_s  = $finalDur
        scene_count = $sceneVideos.Count
        command     = $cmdStr
        provider    = 'local-ffmpeg'
    }
} finally {
    # Clean up temp dir
    if (Test-Path -LiteralPath $tmpDir) {
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
