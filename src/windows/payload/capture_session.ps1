$ErrorActionPreference = 'Stop'

$obsPath = "C:\Program Files\obs-studio\bin\64bit\obs64.exe"

Write-Output "[CAPTURE] Restarting OBS streaming session..."

Get-Process obs64 -ErrorAction SilentlyContinue | Stop-Process -Force

Start-Sleep -Seconds 5

Start-Process $obsPath -ArgumentList "--startstreaming --minimize-to-tray"
