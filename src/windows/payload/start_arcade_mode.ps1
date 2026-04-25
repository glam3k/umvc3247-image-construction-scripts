$ErrorActionPreference = "Continue"

$ArcadeEnabledFlag = "C:\Arcade\arcade_mode.enabled"
$MaintenanceFlag   = "C:\Arcade\maintenance.txt"
$HeartbeatPath     = "C:\Arcade\arcade-shell.heartbeat"
$Log               = "C:\Arcade\arcade-mode.log"
$HeartbeatMaxAge   = 45
$StartupGraceSec   = 180

function Log($msg) {
    Add-Content -Path $Log -Value ("[{0}] {1}" -f (Get-Date), $msg)
}

function Test-SunshineRunning {
    return [bool](Get-Process -Name "sunshine" -ErrorAction SilentlyContinue)
}

function Test-ShellHealthy {
    if (!(Test-Path $HeartbeatPath)) { return $false }
    $AgeSeconds = ((Get-Date) - (Get-Item $HeartbeatPath).LastWriteTime).TotalSeconds
    return ($AgeSeconds -le $HeartbeatMaxAge)
}

Log "Arcade runtime watchdog starting"

if (Test-Path $MaintenanceFlag) { Log "Maintenance mode enabled; exiting"; exit 0 }
if (!(Test-Path $ArcadeEnabledFlag)) { Log "Arcade mode not enabled yet; exiting"; exit 0 }

Log "Arcade mode enabled; watchdog active"
Log "Startup grace period: $StartupGraceSec seconds"
Start-Sleep -Seconds $StartupGraceSec

while ($true) {
    Start-Sleep -Seconds 15

    if (Test-Path $MaintenanceFlag) { Log "Maintenance mode enabled during runtime; exiting"; exit 0 }
    if (-not (Test-SunshineRunning)) {
        Log "Sunshine is not running; rebooting to recover clean state"
        shutdown.exe /r /t 5 /c "Arcade session recovery"
        exit 0
    }
    if (-not (Test-ShellHealthy)) {
        Log "Arcade shell heartbeat missing or stale; rebooting to recover clean state"
        shutdown.exe /r /t 5 /c "Arcade session recovery"
        exit 0
    }
}
