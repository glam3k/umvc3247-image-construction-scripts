$ErrorActionPreference = 'Stop'

$obsDir = "C:\Program Files\obs-studio\bin\64bit"
$obsExe = Join-Path $obsDir "obs64.exe"

Write-Output "[CAPTURE] Starting OBS..."

if (-not (Test-Path $obsExe)) {
    Write-Error "OBS not found at $obsExe"
    exit 1
}

Get-Process obs64 -ErrorAction SilentlyContinue | Stop-Process -Force

Start-Sleep -Seconds 3

Start-Process `
  -FilePath $obsExe `
  -WorkingDirectory $obsDir `
  -ArgumentList "--startstreaming --minimize-to-tray"

Write-Output "[CAPTURE] OBS launched"
