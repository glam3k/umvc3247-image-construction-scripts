#================================================================
# Start-RTMPServer.ps1
# Starts MediaMTX for the local arcade streaming pipeline.
# Intended to run at ArcadePlayer logon.
#================================================================

$ErrorActionPreference = 'Stop'

$ArcadeRoot = 'C:\Arcade'
$ExePath    = Join-Path $ArcadeRoot 'mediamtx.exe'
$ConfigPath = Join-Path $ArcadeRoot 'arcade-config.json'
$MediaMTXConfigPath = Join-Path $ArcadeRoot 'mediamtx.yml'
$LogPath    = Join-Path $ArcadeRoot 'mediamtx.log'
$ErrLogPath = Join-Path $ArcadeRoot 'mediamtx-error.log'

function Fail([string]$Message) {
    Write-Error $Message
    exit 1
}

function Write-Info([string]$Message) {
    Write-Output "[RTMP] $Message"
}

if (-not (Test-Path $ExePath)) {
    Fail "[RTMP] mediamtx.exe not found at $ExePath"
}

if (-not (Test-Path $ConfigPath)) {
    Fail "[RTMP] arcade-config.json not found at $ConfigPath"
}

if (-not (Test-Path $MediaMTXConfigPath)) {
    Fail "[RTMP] mediamtx.yml not found at $MediaMTXConfigPath"
}

try {
    $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Fail "[RTMP] Failed to parse arcade config - $($_.Exception.Message)"
}

if (-not ($Config.PSObject.Properties.Name -contains 'capture_enabled') -or -not [bool]$Config.capture_enabled) {
    Write-Info "capture_enabled is false; skipping MediaMTX startup"
    exit 0
}

try {
    "" | Out-File -FilePath $LogPath -Encoding ascii -Force
    "" | Out-File -FilePath $ErrLogPath -Encoding ascii -Force
}
catch {
    Fail "[RTMP] Cannot write log files - $($_.Exception.Message)"
}

$existing = Get-Process -Name 'mediamtx' -ErrorAction SilentlyContinue
if ($existing) {
    Write-Info "mediamtx is already running. PID(s): $($existing.Id -join ', ')"
    exit 0
}

# IMPORTANT: mediamtx expects the config path as a positional argument,
# not "-c <path>".
$argList = @($MediaMTXConfigPath)

Write-Info "Starting MediaMTX"
Write-Info "Exe: $ExePath"
Write-Info "Config: $MediaMTXConfigPath"

try {
    $proc = Start-Process `
        -FilePath $ExePath `
        -ArgumentList $argList `
        -RedirectStandardOutput $LogPath `
        -RedirectStandardError $ErrLogPath `
        -WindowStyle Hidden `
        -PassThru

    Start-Sleep -Seconds 3

    if ($proc.HasExited) {
        Fail "[RTMP] MediaMTX exited immediately (exit code $($proc.ExitCode)). See $LogPath and $ErrLogPath"
    }

    Write-Info "MediaMTX running - PID $($proc.Id)"
    Write-Info "stdout -> $LogPath"
    Write-Info "stderr -> $ErrLogPath"
}
catch {
    Fail "[RTMP] Failed to start MediaMTX - $($_.Exception.Message)"
}
