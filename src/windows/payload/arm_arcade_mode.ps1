$ConfigPath        = "C:\Arcade\arcade-config.json"
$ArcadeEnabledFlag = "C:\Arcade\arcade_mode.enabled"
$MaintenanceFlag   = "C:\Arcade\maintenance.txt"
$WinLogon          = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

$Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

Write-Host "[ARCADE] Arming arcade mode"

# Autologon
Set-ItemProperty $WinLogon -Name AutoAdminLogon   -Value "1"
Set-ItemProperty $WinLogon -Name DefaultUserName   -Value $Config.game_user
Set-ItemProperty $WinLogon -Name DefaultPassword   -Value $Config.game_user_password
Set-ItemProperty $WinLogon -Name DefaultDomainName -Value $env:COMPUTERNAME

# Replace ArcadePlayer's shell via their NTUSER.DAT
# The user must have logged in at least once so the profile exists
$Ntuser = "C:\Users\$($Config.game_user)\NTUSER.DAT"
if (!(Test-Path $Ntuser)) {
    Write-Error "[ARCADE] NTUSER.DAT not found at $Ntuser"
    Write-Error "[ARCADE] Log in as $($Config.game_user) at least once before arming, then log back out"
    exit 1
}

Write-Host "[ARCADE] Loading $($Config.game_user) registry hive"
reg load "HKU\ArcadeTemp" $Ntuser 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "[ARCADE] Could not load hive - ensure $($Config.game_user) is fully logged out first"
    exit 1
}

try {
    $ShellKey = "Registry::HKU\ArcadeTemp\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
    $ShellCmd = 'powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "C:\Arcade\Launch-ArcadeSession.ps1"'
    New-Item -Path $ShellKey -Force | Out-Null
    Set-ItemProperty -Path $ShellKey -Name Shell -Value $ShellCmd -Type String -Force
    Write-Host "[ARCADE] Custom shell set for $($Config.game_user)"
} finally {
    # Force GC before unload - open handles prevent unload
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    Start-Sleep -Milliseconds 500
    reg unload "HKU\ArcadeTemp" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "[ARCADE] Hive unload failed - run 'reg unload HKU\ArcadeTemp' manually before rebooting"
    }
}

New-Item -Path $ArcadeEnabledFlag -ItemType File -Force | Out-Null
Remove-Item $MaintenanceFlag -ErrorAction SilentlyContinue

Write-Host "[ARCADE] Arcade mode armed"
Write-Host "[ARCADE] Ensure C:\Arcade\Launch-Game.cmd uses 'start /wait' so game exit is detected"
Write-Host "[ARCADE] Reboot when ready"
