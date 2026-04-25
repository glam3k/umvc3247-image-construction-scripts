# UMVC3247 Image Prep

This directory contains the image-preparation assets for the `umvc3247` application.

Its purpose is to help create a reusable Windows AMI that already contains the app-specific runtime environment needed by the UMVC3247 deployment flow.

This directory is intentionally separate from the generic station provisioning repo. The provisioning/orchestrator launches AMIs and manages stations. This directory is responsible for preparing the contents and runtime behavior of the AMI itself.

## What This Directory Is For

This directory is used when building or updating a golden image for the UMVC3247 workflow.

It is responsible for:

- bootstrapping a fresh Windows seed machine
- downloading and running the image-prep payload scripts
- creating the arcade user and local runtime structure
- setting up the kiosk/session scripts used by this application
- preparing the machine so it can later be captured as a reusable AMI

It is not responsible for:

- provisioning EC2 instances in production
- selecting AMIs by tag
- generic station lifecycle management

That responsibility lives in the separate provisioning/orchestrator repo.

## Directory Layout

- [bootstrap.xml](/Users/glam3k/projects/umvc3247/images/bootstrap.xml)
  Thin launcher run on a fresh Windows machine. It writes the local config JSON, downloads the payload scripts from the configured gist/raw URL, and runs the main bootstrap script.

- [payload/bootstrap_main.ps1](/Users/glam3k/projects/umvc3247/images/payload/bootstrap_main.ps1)
  Main image-prep script. Installs/configures the machine-level pieces and writes first-boot completion markers.

- [payload/start_arcade_mode.ps1](/Users/glam3k/projects/umvc3247/images/payload/start_arcade_mode.ps1)
  Machine-level watchdog script.

- [payload/launch_arcade_session.ps1](/Users/glam3k/projects/umvc3247/images/payload/launch_arcade_session.ps1)
  Arcade user logon/session setup script.

- [payload/arcade_shell.ps1](/Users/glam3k/projects/umvc3247/images/payload/arcade_shell.ps1)
  Fullscreen arcade shell/launcher UI.

- [payload/arm_arcade_mode.ps1](/Users/glam3k/projects/umvc3247/images/payload/arm_arcade_mode.ps1)
  Manual arming script used to switch from setup mode to arcade mode.

## How The Bootstrap Flow Works

The intended entrypoint is a portable PowerShell bootstrap script that can be copied onto a fresh machine and run directly.

The bootstrap flow pulls the payload scripts from GitHub by default using the `main` branch.

For stricter reproducibility, change `PayloadRef` in [payload/bootstrap_main.ps1](/Users/glam3k/projects/umvc3247/images/payload/bootstrap_main.ps1:34) to a tag or commit SHA before building the image.

It does the following:

1. Creates `C:\Arcade`
2. Writes `C:\Arcade\arcade-config.json`
3. Checks whether `C:\Arcade\bootstrap.complete` already exists
4. If the marker exists, it exits
5. If the marker does not exist, it downloads the payload scripts from the configured raw URL base
6. Runs `C:\Arcade\Bootstrap-Main.ps1`

The payload scripts are written to:

- `C:\Arcade\Bootstrap-Main.ps1`
- `C:\Arcade\Start-ArcadeMode.ps1`
- `C:\Arcade\Launch-ArcadeSession.ps1`
- `C:\Arcade\ArcadeShell.ps1`
- `C:\Arcade\Arm-ArcadeMode.ps1`

The payload scripts read settings from:

- `C:\Arcade\arcade-config.json`

## Configuration Model

This image-prep flow uses a small configuration block near the top of [payload/bootstrap_main.ps1](/Users/glam3k/projects/umvc3247/images/payload/bootstrap_main.ps1:33):

- `PayloadRef`
- `GameUser`
- `GameUserPassword`
- `CaptureEnabled` (bool, default `$false`)
- `CaptureResolution` (e.g. `"1280x720"`)
- `CaptureFramerate` (int, e.g. `30`)
- `CaptureBitrateKbps` (int, e.g. `3000`)
- `CaptureAudioDevice` (string, name from `ffmpeg -list_devices`)
- `CaptureGop` (int, keyframe interval, e.g. `60`)
Edit those values directly before using the image-prep flow.

For v1 simplicity:

- `GameUser` and `GameUserPassword` can be fixed defaults
- Cloudflare values can be left blank
- if Cloudflare values are blank, the DDNS step skips cleanly

## What The Main Bootstrap Does

The main bootstrap currently handles:

- enabling Windows audio services
- checking NVIDIA driver readiness with `nvidia-smi` when available
- installing Chocolatey if needed
- installing Steam and Sunshine
- installing `ffmpeg` via Chocolatey
- staging MediaMTX under `C:\Arcade`
- downloading/extracting/installing pinned ViGEmBus `v1.22.0` with the Windows Server workaround path
- staging the Virtual Display Driver zip under `C:\Arcade\VirtualDisplayDriver`
- staging the Voicemeeter zip under `C:\Arcade\Voicemeeter`
- staging the VB-Cable zip under `C:\Arcade\VBCable`
- creating the arcade user
- registering the startup/logon tasks used by the kiosk flow
- creating a placeholder `C:\Arcade\Launch-Game.cmd`
- writing `C:\Arcade\manual-steps.txt`
- writing `C:\Arcade\bootstrap.complete`

## Important Manual Steps

The bootstrap does not fully complete the image by itself. Some things are intentionally still manual because they are flaky or interactive.

### 1. NVIDIA driver installation

The bootstrap does not download or install an NVIDIA driver yet.

Instead it:

- checks whether `nvidia-smi.exe` exists
- runs `nvidia-smi` if it is present
- logs a manual follow-up step if the command is missing or fails

If the machine does not already have a working NVIDIA driver, you must manually install it, reboot if required, and verify:

```powershell
nvidia-smi
```

### 2. Virtual display and display selection

This image flow assumes the target application may need a virtual display/headless display path.

You may need to manually:

- install the staged virtual display driver from `C:\Arcade\VirtualDisplayDriver\extracted`
- verify the correct display is active
- point Sunshine at the correct display device id

### 3. Sunshine first-time setup

Sunshine generally needs first-time manual setup.

You must:

- launch Sunshine
- set the username/password or other required auth settings
- configure the correct display capture device
- verify Moonlight can connect

### 4. Steam login

The bootstrap installs Steam, but you still need to:

- launch Steam
- log in
- complete Steam Guard / 2FA
- verify future boots keep the account usable

### 5. Streaming add-ons

The bootstrap stages these under `C:\Arcade` for manual install if they are not already present:

- `C:\Arcade\Voicemeeter\extracted`
- `C:\Arcade\VBCable\extracted`

Install them manually and reboot if required.

### 6. Game install and launcher

You must manually:

- install the game
- verify it launches
- update `C:\Arcade\Launch-Game.cmd` to launch the real game instead of the placeholder test dialog

## Suggested Image Build Process

### Phase 1: Seed Machine

1. Launch a fresh Windows Server 2022 machine.
2. Copy or run [bootstrap.xml](/Users/glam3k/projects/umvc3247/images/bootstrap.xml) on that machine.
3. Wait for the bootstrap to complete.

Useful checks:

```powershell
Get-ChildItem C:\Arcade
Get-Content C:\Arcade\bootstrap-launcher.log -Tail 100
Get-Content C:\Arcade\bootstrap.log -Tail 200
Test-Path C:\Arcade\bootstrap.complete
```

### Phase 2: Manual Setup

After bootstrap:

1. Review `C:\Arcade\manual-steps.txt`
2. If needed, manually install the NVIDIA driver and verify `nvidia-smi`
3. Reboot if any driver or audio installer requires it
4. Install/configure the virtual display if needed
5. Install Voicemeeter and/or VB-Cable if your capture path needs them
6. Verify audio is working
7. Complete Sunshine first-run setup
8. Point Sunshine at the correct display device
9. Launch Steam and log in
10. Install the game
11. Replace `C:\Arcade\Launch-Game.cmd` with the real game launcher

### Phase 3: Arcade Mode Validation

Once the machine is configured:

1. Run:

```powershell
C:\Arcade\Arm-ArcadeMode.ps1
```

2. Reboot
3. Validate that:
   - `ArcadePlayer` autologs in
   - Sunshine starts
   - Steam starts
   - the arcade shell appears
   - the game launches from `Launch-Game.cmd`
   - if the game exits, the shell remains and allows relaunch

### Phase 4: Capture The AMI

When the machine behaves correctly:

1. Perform any final cleanup
2. If appropriate for your Windows image workflow, run EC2Launch sysprep
3. Shut down the machine
4. Create the AMI
5. Tag the AMI clearly for the provisioning/orchestrator repo to consume

## Runtime Assumptions Of The Finished Image

A successfully prepared image should already contain:

- drivers
- Sunshine
- Steam
- app/game-specific configuration
- arcade shell/session scripts
- any autologon/kiosk behavior required by the UMVC3247 app

The provisioning/orchestrator repo should be able to assume the AMI is already ready and should not need to know how it was prepared.

## Notes On Simplicity Vs Security

For the current v1 direction:

- fixed strong baked-in `ArcadePlayer` credentials are acceptable
- fixed Sunshine credentials are acceptable
- Cloudflare config should remain optional
- the priority is getting a stable end-to-end image first

Hardening can be added later once the overall flow is stable.
