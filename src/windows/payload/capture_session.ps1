$ErrorActionPreference = 'Stop'

$ArcadeRoot = 'C:\Arcade'
$ConfigPath = Join-Path $ArcadeRoot 'arcade-config.json'

$obsDir = "C:\Program Files\obs-studio\bin\64bit"
$obsExe = Join-Path $obsDir "obs64.exe"

if (-not (Test-Path $ConfigPath)) {
    Write-Error "[CAPTURE] arcade-config.json not found at $ConfigPath"
    exit 1
}

try {
    $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "[CAPTURE] Failed to parse arcade config - $($_.Exception.Message)"
    exit 1
}

if (-not ($Config.PSObject.Properties.Name -contains 'capture_enabled') -or -not [bool]$Config.capture_enabled) {
    Write-Output "[CAPTURE] capture_enabled is false; skipping capture startup"
    exit 0
}

Write-Output "[CAPTURE] Starting OBS..."

if (-not (Test-Path $obsExe)) {
    Write-Error "OBS not found at $obsExe"
    exit 1
}

Get-Process obs64 -ErrorAction SilentlyContinue | Stop-Process -Force

Start-Sleep -Seconds 3

# Clean up OBS safe-mode artifacts that can cause OBS to get stuck in safe mode
# on restart (see: https://www.reddit.com/r/obs/comments/1ff3teb/)
$obsAppData = Join-Path $env:APPDATA 'obs-studio'
$safeModeDir = Join-Path $obsAppData 'safe_mode'
$sentinelFile = Join-Path $obsAppData '.sentinel'

if (Test-Path $safeModeDir) {
    Write-Output "[CAPTURE] Removing OBS safe_mode directory..."
    cmd /c "rd /s /q ""$safeModeDir\"""
}
if (Test-Path $sentinelFile) {
    Write-Output "[CAPTURE] Removing OBS .sentinel file..."
    Remove-Item -Path $sentinelFile -Force -ErrorAction SilentlyContinue
}

Start-Process `
  -FilePath $obsExe `
  -WorkingDirectory $obsDir `
  -ArgumentList "--startstreaming --minimize-to-tray"

Write-Output "[CAPTURE] OBS launched"
