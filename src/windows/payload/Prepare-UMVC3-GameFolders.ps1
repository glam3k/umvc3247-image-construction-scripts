$ErrorActionPreference = "Stop"

$steamGamePath = "C:\Program Files (x86)\Steam\steamapps\common\ULTIMATE MARVEL VS. CAPCOM 3"
$gamesRoot     = "C:\Arcade\Games"
$targetBase    = Join-Path $gamesRoot "UMVC3_base"
$modFolders    = @("UMVC3_CommunityEdition", "UMVC3_PMVC3", "UMVC3_Super", "UMVC3_ExEdition")

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Fail-Step {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $gamesRoot)) {
    New-Item -ItemType Directory -Path $gamesRoot -Force | Out-Null
    Write-Host "Created $gamesRoot directory." -ForegroundColor Green
}

if (-not (Test-Path $steamGamePath)) {
    Fail-Step "Steam game path not found at $steamGamePath. Install UMVC3 through Steam first."
}

if (-not (Test-Path $targetBase)) {
    New-Item -ItemType Directory -Path $targetBase -Force | Out-Null
}

Write-Info "Copying game from Steam to $targetBase..."
Copy-Item -Path (Join-Path $steamGamePath "*") -Destination $targetBase -Recurse -Force

foreach ($modName in $modFolders) {
    $modPath = Join-Path $gamesRoot $modName

    if (-not (Test-Path $modPath)) {
        New-Item -ItemType Directory -Path $modPath -Force | Out-Null
    }

    Write-Info "Linking files for $modName..."

    Get-ChildItem -Path $targetBase -Recurse | ForEach-Object {
        $relPath = $_.FullName.Substring($targetBase.Length)
        $destPath = "$modPath$relPath"

        if ($_.PSIsContainer) {
            if (-not (Test-Path $destPath)) {
                New-Item -ItemType Directory -Path $destPath -Force | Out-Null
            }
        } else {
            if (-not (Test-Path $destPath)) {
                fsutil hardlink create "$destPath" "$($_.FullName)" | Out-Null
            }
        }
    }
}

Write-Host "Applying LZX compression to save space..." -ForegroundColor Yellow
compact /c /s /exe:lzx "$gamesRoot\*" | Out-Null

Write-Host "Setup complete. Arcade game folders are ready." -ForegroundColor Green
