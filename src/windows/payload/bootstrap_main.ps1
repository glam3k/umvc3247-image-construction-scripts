$ErrorActionPreference = "Stop"

# =============================================================================
# PATHS / GLOBALS
# =============================================================================

$ArcadeRoot        = "C:\Arcade"
$ConfigPath        = Join-Path $ArcadeRoot "arcade-config.json"
$BootstrapLog      = Join-Path $ArcadeRoot "bootstrap.log"
$BootstrapFailed   = Join-Path $ArcadeRoot "bootstrap.failed"
$BootstrapComplete = Join-Path $ArcadeRoot "bootstrap.complete"
$ManualStepsPath   = Join-Path $ArcadeRoot "manual-steps.txt"
$ChocoExe          = "C:\ProgramData\chocolatey\bin\choco.exe"

# Runtime artifact names under C:\Arcade
$BootstrapPs1Name        = "bootstrap.ps1"
$StartArcadeModeName     = "Start-ArcadeMode.ps1"
$LaunchArcadeSessionName = "Launch-ArcadeSession.ps1"
$ArcadeShellName         = "ArcadeShell.ps1"
$ArmArcadeModeName       = "Arm-ArcadeMode.ps1"
$CaptureSessionName      = "Capture-Session.ps1"
$StartRTMPServerName     = "Start-RTMPServer.ps1"
$LaunchGamePs1Name       = "Launch-Game.ps1"
$PrepareGameFoldersName  = "Prepare-UMVC3-GameFolders.ps1"
$BackgroundImageName     = "background.jpg"

$LaunchGameCmdPath       = Join-Path $ArcadeRoot "Launch-Game.cmd"
$ExitGameCmdPath         = Join-Path $ArcadeRoot "Exit-Game.cmd"

# =============================================================================
# IMAGE PREP CONFIGURATION
# Edit these before running.
# =============================================================================

# Default to main for a copy/paste bootstrap flow.
# Pin to a commit SHA or tag when you need strict reproducibility.
$PayloadRef     = "main"
$PayloadBaseUrl = "https://raw.githubusercontent.com/glam3k/umvc3247-image-construction-scripts/$PayloadRef/src/windows/payload"

$GameUser         = "ArcadePlayer"
$GameUserPassword = "OverdraftAlarmThinly3!"

$LaunchOnLogin = $false

# Capture / RTMP
$CaptureEnabled            = $false
$CaptureResolution         = "1280x720"
$CaptureFramerate          = 30
$CaptureBitrateKbps        = 3000
$CaptureAudioBitrateKbps   = 128
$CaptureAudioDevice        = "Voicemeeter Out A2 (VB-Audio Voicemeeter VAIO)"
$CaptureGop                = 60
$CaptureRtmpUrl            = "rtmp://localhost:1935/arcade"

# Desired components
$InstallSteam       = $true
$InstallSunshine    = $true
$InstallFfmpeg      = $true
$InstallMediaMTX    = $true
$InstallViGEmBus    = $true
$InstallVirtualDisplayDriver = $true
$InstallVoicemeeter = $true
$InstallVBCable     = $false

# Scheduled tasks
$EnableRTMPTask    = $true
$EnableCaptureTask = $true

# Privacy / permissions
$MicrophoneAccessGlobal  = $true
$MicrophoneAccessDesktop = $true

# Pinned runtime asset URLs
$MediaMTXVersion = "v1.17.1"
$MediaMTXZipUrl  = "https://github.com/bluenviron/mediamtx/releases/download/v1.17.1/mediamtx_v1.17.1_windows_amd64.zip"
$ViGEmBusVersion = "v1.22.0"
$ViGEmBusInstallerUrl = "https://github.com/nefarius/ViGEmBus/releases/download/v1.22.0/ViGEmBus_1.22.0_x64_x86_arm64.exe"
$VirtualDisplayDriverUrl = "https://github.com/VirtualDrivers/Virtual-Display-Driver/releases/download/25.7.23/VDD.Control.25.7.23.zip"
$VoicemeeterZipUrl = "https://download.vb-audio.com/Download_CABLE/VoicemeeterSetup_v1122.zip"
$VBCableZipUrl     = "https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack45.zip"

# =============================================================================
# PAYLOAD FILE MANIFEST
# remote filename in repo -> local filename under C:\Arcade
# =============================================================================

$PayloadFiles = @(
    @{ Remote = "start_arcade_mode.ps1";     Local = $StartArcadeModeName },
    @{ Remote = "launch_arcade_session.ps1"; Local = $LaunchArcadeSessionName },
    @{ Remote = "arcade_shell.ps1";          Local = $ArcadeShellName },
    @{ Remote = "arm_arcade_mode.ps1";       Local = $ArmArcadeModeName },
    @{ Remote = "capture_session.ps1";       Local = $CaptureSessionName },
    @{ Remote = "start_rtmp_server.ps1";     Local = $StartRTMPServerName },
    @{ Remote = "Launch-Game.ps1";           Local = $LaunchGamePs1Name },
    @{ Remote = "Prepare-UMVC3-GameFolders.ps1"; Local = $PrepareGameFoldersName },
    @{ Remote = "background.jpg";            Local = $BackgroundImageName }
)

# =============================================================================
# HELPERS
# =============================================================================

function Write-Info {
    param([string]$Message)
    Write-Output "[BOOTSTRAP] $Message"
}

function Write-WarnStep {
    param([string]$Message)
    Write-Warning "[BOOTSTRAP] $Message"
}

function Fail-Step {
    param([string]$Message)

    try {
        $Message | Out-File -FilePath $BootstrapFailed -Encoding ascii -Force
    } catch {}

    Write-Error "[BOOTSTRAP] $Message"

    try { Stop-Transcript | Out-Null } catch {}

    exit 1
}

function Ensure-Directory {
    param([string]$Path)
    New-Item -Path $Path -ItemType Directory -Force | Out-Null
}

function Add-ManualStep {
    param([string]$Message)

    Add-Content -Path $ManualStepsPath -Value $Message
    Write-WarnStep $Message
}

function Test-Admin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Validate-Config {
    if ([string]::IsNullOrWhiteSpace($PayloadRef)) {
        Fail-Step "PayloadRef is blank. Set it to a branch, tag, or commit SHA first."
    }
    if ($GameUserPassword -eq "REPLACE_WITH_STRONG_PASSWORD") {
        Fail-Step "GameUserPassword is still a placeholder. Set a real password first."
    }
}

function Download-File {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Write-Info "Downloading $Url"

    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
    } catch {
        Fail-Step "Failed downloading $Url - $($_.Exception.Message)"
    }

    if (-not (Test-Path $Destination)) {
        Fail-Step "Download reported success but file missing: $Destination"
    }

    $Item = Get-Item $Destination -ErrorAction Stop
    if ($Item.Length -le 0) {
        Fail-Step "Downloaded file is empty: $Destination"
    }
}

function Expand-ZipToDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (Test-Path $Destination) {
        Remove-Item -Path $Destination -Recurse -Force
    }

    Ensure-Directory -Path $Destination

    try {
        Expand-Archive -Path $ZipPath -DestinationPath $Destination -Force
    } catch {
        Fail-Step "Failed expanding archive $ZipPath - $($_.Exception.Message)"
    }
}

function Write-ConfigFile {
    $Config = [ordered]@{
        payload_ref                  = $PayloadRef
        payload_base_url             = $PayloadBaseUrl

        game_user                    = $GameUser
        game_user_password           = $GameUserPassword
        launch_on_login              = $LaunchOnLogin

        capture_enabled              = $CaptureEnabled
        capture_resolution           = $CaptureResolution
        capture_framerate            = $CaptureFramerate
        capture_bitrate_kbps         = $CaptureBitrateKbps
        capture_audio_bitrate_kbps   = $CaptureAudioBitrateKbps
        capture_audio_device         = $CaptureAudioDevice
        capture_gop                  = $CaptureGop
        capture_rtmp_url             = $CaptureRtmpUrl

        install_steam                = $InstallSteam
        install_sunshine             = $InstallSunshine
        install_ffmpeg               = $InstallFfmpeg
        install_mediamtx             = $InstallMediaMTX
        install_vigem                = $InstallViGEmBus
        install_virtual_display      = $InstallVirtualDisplayDriver
        install_voicemeeter          = $InstallVoicemeeter
        install_vb_cable             = $InstallVBCable

        enable_rtmp_task             = $EnableRTMPTask
        enable_capture_task          = $EnableCaptureTask

        microphone_access_global     = $MicrophoneAccessGlobal
        microphone_access_desktop    = $MicrophoneAccessDesktop

        mediamtx_version             = $MediaMTXVersion
        mediamtx_zip_url             = $MediaMTXZipUrl
        vigem_version                = $ViGEmBusVersion
        vigem_installer_url          = $ViGEmBusInstallerUrl
        virtual_display_driver_url   = $VirtualDisplayDriverUrl
        voicemeeter_zip_url          = $VoicemeeterZipUrl
        vb_cable_zip_url             = $VBCableZipUrl
    }

    $Config | ConvertTo-Json -Depth 8 | Set-Content -Path $ConfigPath -Encoding UTF8
    Write-Info "Rewrote config at $ConfigPath"
}

function Get-Config {
    if (-not (Test-Path $ConfigPath)) {
        Fail-Step "Config missing at $ConfigPath"
    }

    try {
        return Get-Content $ConfigPath -Raw | ConvertFrom-Json
    } catch {
        Fail-Step "Failed to parse config at $ConfigPath - $($_.Exception.Message)"
    }
}

function Stage-Payload {
    foreach ($File in $PayloadFiles) {
        $Url         = "$PayloadBaseUrl/$($File.Remote)"
        $Destination = Join-Path $ArcadeRoot $File.Local
        Download-File -Url $Url -Destination $Destination
        Write-Info "Staged payload file $Destination"
    }
}

function Ensure-AudioServices {
    try {
        Set-Service AudioEndpointBuilder -StartupType Automatic
        Set-Service Audiosrv -StartupType Automatic
        Start-Service AudioEndpointBuilder -ErrorAction SilentlyContinue
        Start-Service Audiosrv -ErrorAction SilentlyContinue
        Write-Info "Audio services ensured"
    } catch {
        Fail-Step "Failed ensuring audio services - $($_.Exception.Message)"
    }
}

function Get-NvidiaSmiPath {
    $command = Get-Command "nvidia-smi.exe" -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $commonPaths = @(
        "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe",
        "C:\Windows\System32\nvidia-smi.exe"
    )

    return $commonPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Ensure-Chocolatey {
    if (Test-Path $ChocoExe) {
        Write-Info "Chocolatey already installed"
        return
    }

    Write-Info "Installing Chocolatey"
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    try {
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    } catch {
        Fail-Step "Chocolatey install failed - $($_.Exception.Message)"
    }

    if (-not (Test-Path $ChocoExe)) {
        Fail-Step "Chocolatey install completed but choco.exe not found at $ChocoExe"
    }
}

function Test-ChocoPackageInstalled {
    param([string]$PackageName)

    if (-not (Test-Path $ChocoExe)) { return $false }

    $output = & $ChocoExe list --local-only --exact $PackageName 2>$null
    return ($LASTEXITCODE -eq 0 -and ($output | Select-String -Pattern "^\Q$PackageName\E\s"))
}

function Ensure-ChocoPackage {
    param([string]$PackageName)

    if (Test-ChocoPackageInstalled -PackageName $PackageName) {
        Write-Info "Chocolatey package already installed: $PackageName"
        return
    }

    Write-Info "Installing Chocolatey package: $PackageName"
    & $ChocoExe install $PackageName -y --no-progress
    if ($LASTEXITCODE -ne 0) {
        Fail-Step "Chocolatey install failed for package $PackageName"
    }
}

function Ensure-GamePackages {
    param($Config)

    Ensure-Chocolatey

    if ($Config.install_steam)    { Ensure-ChocoPackage -PackageName "steam" }
    if ($Config.install_sunshine) { Ensure-ChocoPackage -PackageName "sunshine" }
}

function Ensure-StreamingPackages {
    param($Config)

    Ensure-Chocolatey

    if ($Config.install_ffmpeg)   { Ensure-ChocoPackage -PackageName "ffmpeg" }
}

function Check-NvidiaDriver {
    try {
        $nvidiaSmi = Get-NvidiaSmiPath

        if ($nvidiaSmi) {
            Write-Info "NVIDIA tooling found at $nvidiaSmi"
            $output = & $nvidiaSmi 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Info "nvidia-smi succeeded"
                $output | ForEach-Object { Write-Info "nvidia-smi: $_" }
            } else {
                Add-ManualStep "NVIDIA tooling exists at $nvidiaSmi but nvidia-smi failed. Verify the display driver is fully installed and reboot if needed."
            }
        } else {
            Add-ManualStep "NVIDIA tooling was not found. Manually install the NVIDIA driver, reboot, and verify nvidia-smi succeeds."
        }
    } catch {
        Write-WarnStep "NVIDIA driver check failed: $($_.Exception.Message)"
    }
}

function Ensure-MediaMTX {
    param($Config)

    if (-not $Config.install_mediamtx) {
        Write-Info "MediaMTX install disabled in config"
        return
    }

    $ExePath    = Join-Path $ArcadeRoot "mediamtx.exe"
    $YamlPath   = Join-Path $ArcadeRoot "mediamtx.yml"
    $ZipPath    = Join-Path $ArcadeRoot "mediamtx.zip"
    $ExtractDir = Join-Path $ArcadeRoot "mediamtx-extract"

    if (-not (Test-Path $ExePath)) {
        Write-Info "Downloading MediaMTX"
        Download-File -Url $Config.mediamtx_zip_url -Destination $ZipPath

        if (Test-Path $ExtractDir) {
            Remove-Item -Path $ExtractDir -Recurse -Force
        }
        Ensure-Directory -Path $ExtractDir

        try {
            Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force
        } catch {
            Fail-Step "Failed expanding MediaMTX archive - $($_.Exception.Message)"
        }

        $ExtractedExe = Get-ChildItem -Path $ExtractDir -Recurse -Filter "mediamtx.exe" | Select-Object -First 1
        if (-not $ExtractedExe) {
            Fail-Step "mediamtx.exe not found after extraction"
        }

        Copy-Item -Path $ExtractedExe.FullName -Destination $ExePath -Force
        Write-Info "Staged MediaMTX executable to $ExePath"
    } else {
        Write-Info "MediaMTX already staged"
    }

    if (-not (Test-Path $YamlPath)) {
@"
logLevel: info
rtmp: yes
rtmpAddress: :1935
paths:
  arcade:
    source: publisher
"@ | Set-Content -Path $YamlPath -Encoding ASCII
        Write-Info "Wrote default MediaMTX config to $YamlPath"
    } else {
        Write-Info "MediaMTX config already exists at $YamlPath"
    }
}

function Ensure-VirtualDisplayDriver {
    param($Config)

    if (-not $Config.install_virtual_display) {
        Write-Info "Virtual display driver staging disabled in config"
        return
    }

    $RootPath = Join-Path $ArcadeRoot "VirtualDisplayDriver"
    $ZipPath  = Join-Path $RootPath "VDD.Control.25.7.23.zip"
    $ExtractPath = Join-Path $RootPath "extracted"

    Ensure-Directory -Path $RootPath

    if (-not (Test-Path $ZipPath)) {
        Download-File -Url $Config.virtual_display_driver_url -Destination $ZipPath
    } else {
        Write-Info "Virtual display driver zip already staged"
    }

    Expand-ZipToDirectory -ZipPath $ZipPath -Destination $ExtractPath
    Add-ManualStep "Virtual display control package staged at $ExtractPath. Run the included installer manually, then verify Sunshine is targeting the correct display."
}

function Test-VoicemeeterInstalled {
    $candidates = @(
        "C:\Program Files (x86)\VB\Voicemeeter\voicemeeter8.exe",
        "C:\Program Files (x86)\VB\Voicemeeter\voicemeeter.exe"
    )
    return [bool]($candidates | Where-Object { Test-Path $_ } | Select-Object -First 1)
}

function Ensure-Voicemeeter {
    param($Config)

    if (-not $Config.install_voicemeeter) {
        Write-Info "Voicemeeter staging disabled in config"
        return
    }

    $RootPath = Join-Path $ArcadeRoot "Voicemeeter"
    $ZipPath  = Join-Path $RootPath "VoicemeeterSetup_v1122.zip"
    $ExtractPath = Join-Path $RootPath "extracted"

    Ensure-Directory -Path $RootPath

    if (-not (Test-Path $ZipPath)) {
        Download-File -Url $Config.voicemeeter_zip_url -Destination $ZipPath
    } else {
        Write-Info "Voicemeeter zip already staged"
    }

    Expand-ZipToDirectory -ZipPath $ZipPath -Destination $ExtractPath

    if (Test-VoicemeeterInstalled) {
        Write-Info "Voicemeeter already installed"
    } else {
        Add-ManualStep "Voicemeeter installer staged at $ExtractPath. Install it manually and reboot if required."
    }
}

function Test-VBCableInstalled {
    $common = @(
        "C:\Program Files\VB\CABLE\VBCABLE_ControlPanel.exe",
        "C:\Program Files (x86)\VB\CABLE\VBCABLE_ControlPanel.exe"
    )
    return [bool]($common | Where-Object { Test-Path $_ } | Select-Object -First 1)
}

function Ensure-VBCable {
    param($Config)

    if (-not $Config.install_vb_cable) {
        Write-Info "VB-Cable install disabled in config"
        return
    }

    $RootPath = Join-Path $ArcadeRoot "VBCable"
    $ZipPath  = Join-Path $RootPath "VBCABLE_Driver_Pack45.zip"
    $ExtractPath = Join-Path $RootPath "extracted"

    Ensure-Directory -Path $RootPath

    if (-not (Test-Path $ZipPath)) {
        Download-File -Url $Config.vb_cable_zip_url -Destination $ZipPath
    } else {
        Write-Info "VB-Cable zip already staged"
    }

    Expand-ZipToDirectory -ZipPath $ZipPath -Destination $ExtractPath

    if (Test-VBCableInstalled) {
        Write-Info "VB-Cable already installed"
    } else {
        Add-ManualStep "VB-Cable installer staged at $ExtractPath. Install it manually and reboot if required."
    }
}

function Ensure-MicrophonePrivacy {
    param($Config)

    try {
        $ConsentStoreRoot = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone"
        New-Item -Path $ConsentStoreRoot -Force | Out-Null

        if ($Config.microphone_access_global) {
            New-ItemProperty -Path $ConsentStoreRoot -Name "Value" -Value "Allow" -PropertyType String -Force | Out-Null
            Write-Info "Enabled global microphone access"
        }

        if ($Config.microphone_access_desktop) {
            $DesktopAppsPath = Join-Path $ConsentStoreRoot "NonPackaged"
            New-Item -Path $DesktopAppsPath -Force | Out-Null
            New-ItemProperty -Path $DesktopAppsPath -Name "Value" -Value "Allow" -PropertyType String -Force | Out-Null
            Write-Info "Enabled desktop app microphone access"
        }

        $TargetUserSids = @()

        try {
            $CurrentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            if (-not [string]::IsNullOrWhiteSpace($CurrentUserSid)) {
                $TargetUserSids += $CurrentUserSid
            }
        } catch {}

        try {
            $ArcadeUser = Get-LocalUser -Name $Config.game_user -ErrorAction SilentlyContinue
            if ($ArcadeUser -and $ArcadeUser.SID) {
                $TargetUserSids += $ArcadeUser.SID.Value
            }
        } catch {}

        $TargetUserSids = $TargetUserSids | Select-Object -Unique

        foreach ($Sid in $TargetUserSids) {
            $UserConsentStoreRoot = "Registry::HKEY_USERS\$Sid\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone"
            New-Item -Path $UserConsentStoreRoot -Force | Out-Null

            if ($Config.microphone_access_global) {
                New-ItemProperty -Path $UserConsentStoreRoot -Name "Value" -Value "Allow" -PropertyType String -Force | Out-Null
            }

            if ($Config.microphone_access_desktop) {
                $UserDesktopAppsPath = Join-Path $UserConsentStoreRoot "NonPackaged"
                New-Item -Path $UserDesktopAppsPath -Force | Out-Null
                New-ItemProperty -Path $UserDesktopAppsPath -Name "Value" -Value "Allow" -PropertyType String -Force | Out-Null
            }

            Write-Info "Enabled microphone access for user SID $Sid"
        }
    } catch {
        Write-WarnStep "Failed applying microphone privacy settings: $($_.Exception.Message)"
    }
}

function Ensure-ViGEmBus {
    param($Config)

    if (-not $Config.install_vigem) {
        Write-Info "ViGEmBus install disabled in config"
        return
    }

    $ViGEmRoot = Join-Path $ArcadeRoot "ViGEmBus"
    $InstallerName = Split-Path -Path $Config.vigem_installer_url -Leaf
    $InstallerPath = Join-Path $ViGEmRoot $InstallerName

    Ensure-Directory -Path $ViGEmRoot

    if (-not (Test-Path $InstallerPath)) {
        Write-Info "Downloading ViGEmBus installer"
        Download-File -Url $Config.vigem_installer_url -Destination $InstallerPath
    } else {
        Write-Info "ViGEmBus installer already staged"
    }

    Write-Info "Extracting ViGEmBus installer into $ViGEmRoot"
    & $InstallerPath /extract $ViGEmRoot
    if ($LASTEXITCODE -ne 0) {
        Fail-Step "ViGEmBus extraction failed with exit code $LASTEXITCODE"
    }

    $ExtractedRoot = Get-ChildItem -Path $ViGEmRoot -Directory | Where-Object {
        (Test-Path (Join-Path $_.FullName "ViGEmBus.inf")) -and
        (Test-Path (Join-Path $_.FullName "nefconw.exe"))
    } | Select-Object -First 1
    if (-not $ExtractedRoot) {
        Fail-Step "ViGEmBus extracted directory not found"
    }

    $InfPath     = Join-Path $ExtractedRoot.FullName "ViGEmBus.inf"
    $NefconwPath = Join-Path $ExtractedRoot.FullName "nefconw.exe"

    if (-not (Test-Path $InfPath))     { Fail-Step "ViGEmBus.inf not found at $InfPath" }
    if (-not (Test-Path $NefconwPath)) { Fail-Step "nefconw.exe not found at $NefconwPath" }

    Write-Info "Using extracted ViGEmBus payload from $($ExtractedRoot.FullName)"

    Push-Location $ExtractedRoot.FullName
    try {
        Write-Info "Removing existing ViGEmBus device nodes if present"
        .\nefconw.exe --remove-device-node --hardware-id Nefarius\ViGEmBus\Gen1 --class-guid 4D36E97D-E325-11CE-BFC1-08002BE10318 | Out-Null
        .\nefconw.exe --remove-device-node --hardware-id Root\ViGEmBus --class-guid 4D36E97D-E325-11CE-BFC1-08002BE10318 | Out-Null

        Write-Info "Creating ViGEmBus device node"
        .\nefconw.exe --create-device-node --hardware-id Nefarius\ViGEmBus\Gen1 --class-name System --class-guid 4D36E97D-E325-11CE-BFC1-08002BE10318 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Fail-Step "Failed creating ViGEmBus device node"
        }

        Write-Info "Installing ViGEmBus driver"
        .\nefconw.exe --install-driver --inf-path "ViGEmBus.inf" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Fail-Step "ViGEmBus driver install failed"
        }
    } finally {
        Pop-Location
    }

    Write-Info "ViGEmBus installation completed"
}

function Ensure-GameUser {
    param($Config)

    try {
        $existing = Get-LocalUser -Name $Config.game_user -ErrorAction SilentlyContinue
        if (-not $existing) {
            Write-Info "Creating game user $($Config.game_user)"
            $SecurePass = ConvertTo-SecureString $Config.game_user_password -AsPlainText -Force
            New-LocalUser -Name $Config.game_user -Password $SecurePass -FullName "Arcade Game User" -Description "Arcade session user" -PasswordNeverExpires | Out-Null
        } else {
            Write-Info "Game user already exists: $($Config.game_user)"
        }

        Remove-LocalGroupMember -Group "Administrators" -Member $Config.game_user -ErrorAction SilentlyContinue
        Add-LocalGroupMember -Group "Users" -Member $Config.game_user -ErrorAction SilentlyContinue
        Write-Info "Reconciled game user group membership"
    } catch {
        Fail-Step "Failed ensuring game user - $($_.Exception.Message)"
    }
}

function Ensure-ArcadePermissions {
    try {
        # Keep this broad for now since the runtime uses shared marker files.
        icacls $ArcadeRoot /grant "Everyone:(OI)(CI)F" /T | Out-Null
        Write-Info "Reconciled C:\Arcade permissions"
    } catch {
        Fail-Step "Failed applying C:\Arcade permissions - $($_.Exception.Message)"
    }
}

function Ensure-KioskMachinePolicies {
    $SystemPoliciesRoot = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    $PersonalizationPoliciesRoot = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"

    $PolicyWrites = @(
        @{ Path = $SystemPoliciesRoot; Name = "DisableCAD"; Value = 1; Description = "Disabled secure attention requirement at logon" },
        @{ Path = $SystemPoliciesRoot; Name = "HideFastUserSwitching"; Value = 1; Description = "Hid fast user switching" },
        @{ Path = $PersonalizationPoliciesRoot; Name = "NoLockScreen"; Value = 1; Description = "Disabled lock screen" }
    )

    foreach ($Policy in $PolicyWrites) {
        try {
            New-Item -Path $Policy.Path -Force | Out-Null
            Set-ItemProperty -Path $Policy.Path -Name $Policy.Name -Value $Policy.Value -Type DWord -Force
            Write-Info $Policy.Description
        } catch {
            Write-WarnStep "Could not apply kiosk policy $($Policy.Name): $($_.Exception.Message)"
        }
    }
}

function Ensure-GameUserProfile {
    param($Config)

    $ProfileRoot = Join-Path "C:\Users" $Config.game_user
    $NtuserPath = Join-Path $ProfileRoot "NTUSER.DAT"

    if (Test-Path $NtuserPath) {
        Write-Info "Arcade user profile already initialized at $ProfileRoot"
        return
    }

    try {
        $SecurePass = ConvertTo-SecureString $Config.game_user_password -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential($Config.game_user, $SecurePass)

        Write-Info "Initializing arcade user profile for $($Config.game_user)"
        $Process = Start-Process `
            -FilePath "powershell.exe" `
            -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"Start-Sleep -Seconds 3`"" `
            -Credential $Credential `
            -WorkingDirectory $ArcadeRoot `
            -PassThru

        $Process.WaitForExit()

        if (-not (Test-Path $NtuserPath)) {
            Add-ManualStep "Arcade user profile was not created automatically. Log in once as $($Config.game_user), then log back out before arming arcade mode."
        } else {
            Write-Info "Initialized arcade user profile at $ProfileRoot"
        }
    } catch {
        Add-ManualStep "Could not initialize the arcade user profile automatically: $($_.Exception.Message). Log in once as $($Config.game_user), then log back out before arming arcade mode."
    }
}

function Ensure-ScheduledTaskEx {
    param(
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][ValidateSet("Startup","LogOn")] [string]$TriggerMode,
        [string]$UserId = "",
        [bool]$Enabled = $true
    )

    try {
        $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$ScriptPath`""

        if ($TriggerMode -eq "Startup") {
            $Trigger   = New-ScheduledTaskTrigger -AtStartup
            $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        } else {
            $Trigger   = New-ScheduledTaskTrigger -AtLogOn -User $UserId
            $Principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType Interactive -RunLevel Limited
        }

        $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances Ignore
        Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force | Out-Null

        if ($Enabled) {
            Enable-ScheduledTask -TaskName $TaskName | Out-Null
        } else {
            Disable-ScheduledTask -TaskName $TaskName | Out-Null
        }

        Write-Info "Ensured scheduled task $TaskName"
    } catch {
        Fail-Step "Failed ensuring scheduled task ${TaskName} - $($_.Exception.Message)"
    }
}

function Ensure-ScheduledTasks {
    param($Config)

    Ensure-ScheduledTaskEx -TaskName "ArcadeRuntimeTask" `
        -ScriptPath (Join-Path $ArcadeRoot $StartArcadeModeName) `
        -TriggerMode "Startup" `
        -Enabled $false

    Ensure-ScheduledTaskEx -TaskName "ArcadeRTMPTask" `
        -ScriptPath (Join-Path $ArcadeRoot $StartRTMPServerName) `
        -TriggerMode "LogOn" `
        -UserId $Config.game_user `
        -Enabled ([bool]$Config.enable_rtmp_task)

    Ensure-ScheduledTaskEx -TaskName "ArcadeCaptureTask" `
        -ScriptPath (Join-Path $ArcadeRoot $CaptureSessionName) `
        -TriggerMode "LogOn" `
        -UserId $Config.game_user `
        -Enabled ([bool]$Config.enable_capture_task)
}

function Ensure-GameLaunchCommand {
    if (Test-Path $LaunchGameCmdPath) {
        Write-Info "Using existing game launcher at $LaunchGameCmdPath"
        return
    }

@"
@echo off
start /wait powershell.exe -ExecutionPolicy Bypass -NoProfile -File "C:\Arcade\Launch-Game.ps1"
"@ | Set-Content -Path $LaunchGameCmdPath -Encoding ASCII

    Write-Info "Wrote Launch-Game.cmd wrapper for Launch-Game.ps1"
}

function Ensure-ExitGamePlaceholder {
    if (Test-Path $ExitGameCmdPath) {
        Write-Info "Using existing exit handler at $ExitGameCmdPath"
        return
    }

@"
@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('Game exited', 'Arcade Test') | Out-Null"
"@ | Set-Content -Path $ExitGameCmdPath -Encoding ASCII

    Write-Info "Wrote placeholder Exit-Game.cmd"
}

function Ensure-MaintenanceFlag {
    $MaintenanceFlag = Join-Path $ArcadeRoot "maintenance.txt"
    if (-not (Test-Path $MaintenanceFlag)) {
        New-Item -Path $MaintenanceFlag -ItemType File -Force | Out-Null
        Write-Info "Created maintenance flag"
    } else {
        Write-Info "Maintenance flag already present"
    }
}

function Write-BootstrapCompleteMarker {
@"
Bootstrap completed: $(Get-Date -Format s)
Host: $env:COMPUTERNAME
"@ | Set-Content -Path $BootstrapComplete -Encoding ASCII
    Write-Info "Wrote bootstrap completion marker to $BootstrapComplete"
}

# =============================================================================
# MAIN
# =============================================================================

Ensure-Directory -Path $ArcadeRoot

Start-Transcript -Path $BootstrapLog -Append
try {
    if (-not (Test-Admin)) {
        Fail-Step "This script must be run as Administrator."
    }

    Remove-Item $BootstrapFailed -ErrorAction SilentlyContinue
    Set-Content -Path $ManualStepsPath -Value "Manual follow-up required after bootstrap:" -Encoding ASCII

    Write-Info "Starting bootstrap converge run"
    Validate-Config
    Write-ConfigFile
    $Config = Get-Config

    Stage-Payload
    Ensure-ArcadePermissions
    Ensure-KioskMachinePolicies
    Ensure-AudioServices
    Check-NvidiaDriver
    Ensure-Chocolatey
    Ensure-GamePackages -Config $Config
    Ensure-StreamingPackages -Config $Config
    Ensure-MediaMTX -Config $Config
    Ensure-GameUser -Config $Config
    Ensure-GameUserProfile -Config $Config
    Ensure-VirtualDisplayDriver -Config $Config
    Ensure-Voicemeeter -Config $Config
    Ensure-VBCable -Config $Config
    Ensure-MicrophonePrivacy -Config $Config
    Ensure-ViGEmBus -Config $Config
    Ensure-ScheduledTasks -Config $Config
    Ensure-GameLaunchCommand
    Ensure-ExitGamePlaceholder
    Ensure-MaintenanceFlag
    Add-ManualStep "After installing UMVC3 in Steam, run C:\Arcade\Prepare-UMVC3-GameFolders.ps1 to create the base and mod game folders."
    Add-ManualStep "When setup is complete, run C:\Arcade\Arm-ArcadeMode.ps1, then reboot to enter arcade mode."
    Write-BootstrapCompleteMarker

    Write-Info "Bootstrap converge run completed successfully"
    Write-Info "If an installer required a reboot, reboot manually and rerun this script."
    Write-Info "See $ManualStepsPath for manual follow-up work."
    Write-Info "If Sunshine/Steam/Voicemeeter/VB-Cable or the virtual display driver need manual setup, do that manually, then rerun this script."
}
catch {
    Fail-Step "Bootstrap failed: $($_.Exception.Message)"
}

try { Stop-Transcript | Out-Null } catch {}
