$ErrorActionPreference = "Continue"

$ShellScriptPath = "C:\Arcade\ArcadeShell.ps1"
$Log             = "C:\Arcade\arcade-session.log"
$VoicemeeterCandidates = @(
    "C:\Program Files (x86)\VB\Voicemeeter\voicemeeter8.exe",
    "C:\Program Files (x86)\VB\Voicemeeter\voicemeeter.exe"
)

function Log($msg) {
    Add-Content -Path $Log -Value ("[{0}] {1}" -f (Get-Date), $msg)
}

function Set-KioskPolicy {
    $sys = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System"
    $exp = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    New-Item -Path $sys -Force | Out-Null
    New-Item -Path $exp -Force | Out-Null
    # Disable common Ctrl+Alt+Del escape paths for the arcade user session.
    Set-ItemProperty -Path $sys -Name DisableTaskMgr        -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $sys -Name DisableLockWorkstation -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $sys -Name DisableChangePassword -Value 1 -Type DWord -Force
    # Suppress Win key and Run dialog
    Set-ItemProperty -Path $exp -Name NoWinKeys             -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $exp -Name NoRun                 -Value 1 -Type DWord -Force
}

function Ensure-Steam {
    if (Get-Process -Name "steam" -ErrorAction SilentlyContinue) {
        Log "Steam already running"
        return
    }

    $candidate = "C:\Program Files (x86)\Steam\steam.exe"
    if (Test-Path $candidate) {
        Log "Starting Steam (Warm-up mode)..."
        Start-Process $candidate -ArgumentList "-silent"

        # Wait for the process to actually appear
        $timeout = 20
        while (!(Get-Process "Steam" -ErrorAction SilentlyContinue) -and $timeout -gt 0) {
            Start-Sleep -Seconds 1
            $timeout--
        }

        # CRITICAL: This 10s buffer lets Steam finish its "Checking for updates"
        # and initialize the API so the mods can "talk" to it immediately.
        Log "Waiting 10s for Steam API stability..."
        Start-Sleep -Seconds 10
        return
    }
    Log "Steam executable not found"
}

function Ensure-Voicemeeter {
    if (Get-Process -Name "voicemeeter8", "voicemeeter" -ErrorAction SilentlyContinue) {
        Log "Voicemeeter already running"
        return
    }

    $candidate = $VoicemeeterCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $candidate) {
        Log "Voicemeeter executable not found"
        return
    }

    try {
        Log "Starting Voicemeeter..."
        Start-Process -FilePath $candidate

        $timeout = 15
        while (!(Get-Process -Name "voicemeeter8", "voicemeeter" -ErrorAction SilentlyContinue) -and $timeout -gt 0) {
            Start-Sleep -Seconds 1
            $timeout--
        }

        if (Get-Process -Name "voicemeeter8", "voicemeeter" -ErrorAction SilentlyContinue) {
            Log "Voicemeeter started"
        } else {
            Log "Voicemeeter did not appear after launch attempt"
        }
    } catch {
        Log "Failed to start Voicemeeter: $($_.Exception.Message)"
    }
}

Log "Arcade session starting"
Set-KioskPolicy
Ensure-Voicemeeter
Ensure-Steam

# Remove any stale game.running flag left by a crash or hard reboot
$GameFlagPath = "C:\Arcade\game.running"
if (Test-Path $GameFlagPath) {
    Remove-Item -Force $GameFlagPath
    Log "Cleared stale game.running flag from previous session"
}

# This process IS the user's shell - it must never exit while the session is active
while ($true) {
    try {
        Log "Launching arcade shell"
        & $ShellScriptPath
        Log "Arcade shell exited unexpectedly; restarting in 5 seconds"
    } catch {
        Log "Arcade shell error: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 5
}
