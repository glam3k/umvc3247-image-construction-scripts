#================================================================
# Capture-Session.ps1
# Captures desktop video + Voicemeeter audio and publishes to RTMP.
# MUST run in the ArcadePlayer console/Sunshine session.
#================================================================

$ErrorActionPreference = 'Stop'

$ArcadeRoot = 'C:\Arcade'
$ConfigPath = Join-Path $ArcadeRoot 'arcade-config.json'
$FfmpegPath = 'C:\ProgramData\chocolatey\bin\ffmpeg.exe'

function Fail-Step {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

function Write-Info {
    param([string]$Message)
    Write-Output "[CAPTURE] $Message"
}

if (-not (Test-Path $FfmpegPath)) {
    Fail-Step "[CAPTURE] ffmpeg not found at $FfmpegPath"
}

if (-not (Test-Path $ConfigPath)) {
    Fail-Step "[CAPTURE] Config missing $ConfigPath"
}

try {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Fail-Step "[CAPTURE] Failed to parse config $ConfigPath - $($_.Exception.Message)"
}

if (-not $config.capture_enabled) {
    Write-Info "Disabled via config - exiting"
    exit 0
}

$resolution = $config.capture_resolution
if (-not $resolution) { $resolution = '1280x720' }

$framerate = $config.capture_framerate
if (-not $framerate) { $framerate = 30 }

$bitrateK = $config.capture_bitrate_kbps
if (-not $bitrateK) { $bitrateK = 3000 }

$gop = $config.capture_gop
if (-not $gop) { $gop = 60 }

$audioBitrate = $config.capture_audio_bitrate_kbps
if (-not $audioBitrate) { $audioBitrate = 128 }

$audioDev = $config.capture_audio_device
if (-not $audioDev) { $audioDev = 'Voicemeeter Out A2 (VB-Audio Voicemeeter VAIO)' }

$videoEncoder = $config.capture_video_encoder
if (-not $videoEncoder) { $videoEncoder = 'h264_nvenc' }

$rtmpUrl = $config.capture_rtmp_url
if (-not $rtmpUrl) { $rtmpUrl = 'rtmp://localhost:1935/arcade' }

$args = @(
    '-f', 'gdigrab',
    '-framerate', "$framerate",
    '-video_size', "$resolution",
    '-i', 'desktop',
    '-f', 'dshow',
    '-i', "audio=$audioDev",
    '-c:v', "$videoEncoder",
    '-preset', 'p4',
    '-tune', 'll',
    '-pix_fmt', 'yuv420p',
    '-b:v', "${bitrateK}k",
    '-maxrate', "${bitrateK}k",
    '-bufsize', "$($bitrateK * 2)k",
    '-g', "$gop",
    '-c:a', 'aac',
    '-b:a', "${audioBitrate}k",
    '-f', 'flv',
    $rtmpUrl
)

Write-Info "Starting capture publish"
Write-Info "IMPORTANT: must run in ArcadePlayer console/Sunshine session"
Write-Info "ffmpeg: $FfmpegPath"
Write-Info "audio device: $audioDev"
Write-Info "video encoder: $videoEncoder"
Write-Info "rtmp url: $rtmpUrl"
Write-Info "args: $($args -join ' ')"

# For debugging: run ffmpeg directly so we can see real stderr/stdout.
& $FfmpegPath @args

$exitCode = $LASTEXITCODE
Write-Info "ffmpeg exit code: $exitCode"

if ($exitCode -ne 0) {
    Fail-Step "[CAPTURE] ffmpeg failed with exit code $exitCode"
}
