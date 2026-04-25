$base = "https://raw.githubusercontent.com/glam3k/umvc3247-image-construction-scripts/main/src/windows/payload"
$files = @{
    "Bootstrap-Main.ps1"       = "bootstrap_main.ps1"
    "Start-ArcadeMode.ps1"     = "start_arcade_mode.ps1"
    "Launch-ArcadeSession.ps1" = "launch_arcade_session.ps1"
    "ArcadeShell.ps1"          = "arcade_shell.ps1"
    "Arm-ArcadeMode.ps1"       = "arm_arcade_mode.ps1"
}
foreach ($dest in $files.Keys) {
    Write-Host "Updating $dest"
    Invoke-WebRequest -Uri "$base/$($files[$dest])" -OutFile "C:\Arcade\$dest" -UseBasicParsing
}
Write-Host "All payload files updated."
