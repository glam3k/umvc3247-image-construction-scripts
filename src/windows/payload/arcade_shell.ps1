$ErrorActionPreference = "Continue"

$LaunchGamePath  = "C:\Arcade\Launch-Game.cmd"
$ExitGamePath    = "C:\Arcade\Exit-Game.cmd"
$GameFlagPath    = "C:\Arcade\game.running"
$GameExe         = "umvc3"
$HeartbeatPath   = "C:\Arcade\arcade-shell.heartbeat"
$BackgroundImage = "C:\Arcade\background.jpg"
$ConfigPath      = "C:\Arcade\arcade-config.json"
$Log             = "C:\Arcade\arcade-shell.log"

$Pumvc3SpecialInstructionsPath = "C:\Arcade\pmvc3_special_instructions.txt"
$Pumvc3Helper120Path           = "C:\Arcade\Games\Umvc3_PMVC3\"
$Pumvc3Helper143Path           = "C:\Arcade\Games\Umvc3_PMVC3\"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.DirectoryServices.AccountManagement

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Focus {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public static IntPtr FindWindowByPid(uint pid) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((hWnd, lParam) => {
            uint windowPid;
            GetWindowThreadProcessId(hWnd, out windowPid);
            if (windowPid == pid && IsWindowVisible(hWnd)) {
                found = hWnd;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
"@

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KbHook {
    const int WH_KEYBOARD_LL = 13;
    const int WM_KEYDOWN     = 0x100;
    const int WM_SYSKEYDOWN  = 0x104;
    [StructLayout(LayoutKind.Sequential)]
    struct KBDLL { public uint vk, sc, fl, t; public IntPtr ex; }
    [DllImport("user32.dll")]   static extern IntPtr SetWindowsHookEx(int id, Proc fn, IntPtr hmod, uint tid);
    [DllImport("user32.dll")]   static extern bool   UnhookWindowsHookEx(IntPtr h);
    [DllImport("user32.dll")]   static extern IntPtr CallNextHookEx(IntPtr h, int n, IntPtr wp, IntPtr lp);
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string n);
    public delegate IntPtr Proc(int n, IntPtr wp, IntPtr lp);
    static Proc _fn; static IntPtr _h;
    public static void Install() {
        _fn = Callback;
        using (var p = System.Diagnostics.Process.GetCurrentProcess())
        using (var m = p.MainModule)
            _h = SetWindowsHookEx(WH_KEYBOARD_LL, _fn, GetModuleHandle(m.ModuleName), 0);
    }
    public static void Uninstall() { if (_h != IntPtr.Zero) { UnhookWindowsHookEx(_h); _h = IntPtr.Zero; } }
    static IntPtr Callback(int n, IntPtr wp, IntPtr lp) {
        if (n >= 0 && (wp == (IntPtr)WM_KEYDOWN || wp == (IntPtr)WM_SYSKEYDOWN)) {
            var kb = (KBDLL)Marshal.PtrToStructure(lp, typeof(KBDLL));
            if (kb.vk == 91 || kb.vk == 92) return (IntPtr)1;
        }
        return CallNextHookEx(_h, n, wp, lp);
    }
}
"@

function Log($msg) { Add-Content -Path $Log -Value ("[{0}] {1}" -f (Get-Date), $msg) }
function Update-Heartbeat { (Get-Date -Format o) | Set-Content -Path $HeartbeatPath -Encoding ASCII }

# Game is considered running if EITHER the flag file exists OR the process is alive.
# This handles the case where the launcher script fails and deletes game.running
# before the game process actually exits (cold boot race with Steam re-init).
function Test-GameRunning {
    if (Test-Path $GameFlagPath) { return $true }
    return [bool](Get-Process -Name $GameExe -ErrorAction SilentlyContinue)
}

$Config = $null
if (Test-Path $ConfigPath) {
    try { $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch { Log "Failed to read config: $($_.Exception.Message)" }
}
$LaunchOnLogin = $Config -and ($Config.PSObject.Properties.Name -contains "launch_on_login") -and [bool]$Config.launch_on_login

function Apply-GameState($running) {
    $LaunchBtn.Visible   = -not $running
    $ExitGameBtn.Visible = $running
    $Form.SendToBack()
}

function Start-Game {
    if (!(Test-Path $LaunchGamePath)) {
        [System.Windows.Forms.MessageBox]::Show("Launch script not found at $LaunchGamePath", "Arcade", "OK", "Warning") | Out-Null
        return
    }
    Log "Launching game"
    $Form.SendToBack()
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$LaunchGamePath`""
    # Button state follows the flag file; poller will flip to EXIT GAME when game.running appears
}

function Stop-Game {
    if (!(Test-Path $ExitGamePath)) {
        [System.Windows.Forms.MessageBox]::Show("Exit script not found at $ExitGamePath", "Arcade", "OK", "Warning") | Out-Null
        return
    }
    Log "Exiting game"
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$ExitGamePath`""
    # Button state follows the flag file; poller will flip to LAUNCH GAME when game.running disappears
}

function Recenter-Game {
    $proc = Get-Process -Name "umvc3" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) { Log "Recenter: umvc3 not running"; return }
    $hwnd = [Win32Focus]::FindWindowByPid([uint32]$proc.Id)
    if ($hwnd -eq [IntPtr]::Zero) { Log "Recenter: no visible window found for pid $($proc.Id)"; return }
    [Win32Focus]::SetWindowPos($hwnd, [IntPtr]::Zero, 0, 0, 0, 0, 0x0041)
    [Win32Focus]::ShowWindow($hwnd, 5)
    [Win32Focus]::SetForegroundWindow($hwnd)
    $Form.SendToBack()
    Log "Recentered umvc3 window (pid=$($proc.Id) hwnd=$hwnd) to 0,0"
}

function Force-Kill-Game {
    $procs = Get-Process -Name "umvc3" -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Stop-Process -Force
        Log "Force killed umvc3.exe"
    } else {
        Log "Force kill: umvc3 not running"
    }
    if (Test-Path $GameFlagPath) {
        Remove-Item -Force $GameFlagPath
        Log "Cleared game.running after force kill"
    }
}

function Open-Steam {
    $exe = @("C:\Program Files (x86)\Steam\steam.exe","C:\Program Files\Steam\steam.exe") |
           Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($exe) { Start-Process $exe } else { Log "Steam not found" }
}

function Show-AdminExit {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = "Administrator Authentication"
    $dlg.Size            = New-Object System.Drawing.Size(360, 170)
    $dlg.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false; $dlg.TopMost = $true

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Administrator password:"; $lbl.Location = New-Object System.Drawing.Point(12, 15); $lbl.AutoSize = $true

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.UseSystemPasswordChar = $true; $tb.Location = New-Object System.Drawing.Point(12, 38); $tb.Width = 320

    $okBtn = New-Object System.Windows.Forms.Button
    $okBtn.Text = "Log Out"; $okBtn.Location = New-Object System.Drawing.Point(12, 80); $okBtn.Width = 100
    $okBtn.Add_Click({
        $ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext(
            [System.DirectoryServices.AccountManagement.ContextType]::Machine)
        if ($ctx.ValidateCredentials("Administrator", $tb.Text)) {
            Log "Admin logout authorized"; $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK; $dlg.Close()
        } else {
            [System.Windows.Forms.MessageBox]::Show("Incorrect password.", "Access Denied", "OK", "Error") | Out-Null
            $tb.Clear(); $tb.Focus()
        }
    })

    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = "Cancel"; $cancelBtn.Location = New-Object System.Drawing.Point(120, 80); $cancelBtn.Width = 80
    $cancelBtn.Add_Click({ $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $dlg.Close() })

    $dlg.Controls.AddRange(@($lbl, $tb, $okBtn, $cancelBtn))
    $dlg.AcceptButton = $okBtn; $dlg.CancelButton = $cancelBtn

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { logoff.exe }
}

function Show-AdminPowerShell {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = "Administrator Authentication"
    $dlg.Size            = New-Object System.Drawing.Size(360, 170)
    $dlg.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false; $dlg.TopMost = $true

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Administrator password:"; $lbl.Location = New-Object System.Drawing.Point(12, 15); $lbl.AutoSize = $true

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.UseSystemPasswordChar = $true; $tb.Location = New-Object System.Drawing.Point(12, 38); $tb.Width = 320

    $okBtn = New-Object System.Windows.Forms.Button
    $okBtn.Text = "Open"; $okBtn.Location = New-Object System.Drawing.Point(12, 80); $okBtn.Width = 100
    $okBtn.Add_Click({
        $ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext(
            [System.DirectoryServices.AccountManagement.ContextType]::Machine)
        if ($ctx.ValidateCredentials("Administrator", $tb.Text)) {
            Log "Admin PowerShell opened"
            $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK; $dlg.Close()
        } else {
            [System.Windows.Forms.MessageBox]::Show("Incorrect password.", "Access Denied", "OK", "Error") | Out-Null
            $tb.Clear(); $tb.Focus()
        }
    })

    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = "Cancel"; $cancelBtn.Location = New-Object System.Drawing.Point(120, 80); $cancelBtn.Width = 80
    $cancelBtn.Add_Click({ $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $dlg.Close() })

    $dlg.Controls.AddRange(@($lbl, $tb, $okBtn, $cancelBtn))
    $dlg.AcceptButton = $okBtn; $dlg.CancelButton = $cancelBtn

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:AdminShellProc = Start-Process "powershell.exe" -ArgumentList "-NoExit -ExecutionPolicy Bypass" -PassThru
        $Form.SendToBack()
    }
}

function Open-Pumvc3SpecialInstructions {
    if (Test-Path $Pumvc3SpecialInstructionsPath) {
        Start-Process "notepad.exe" -ArgumentList "`"$Pumvc3SpecialInstructionsPath`""
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Instructions file not found at $Pumvc3SpecialInstructionsPath",
            "PMVC3 Special Instructions",
            "OK",
            "Warning"
        ) | Out-Null
        Log "PMVC3 special instructions file not found: $Pumvc3SpecialInstructionsPath"
    }
}

function Open-Pumvc3Helper120 {
    if (Test-Path $Pumvc3Helper120Path) {
        Start-Process -FilePath $Pumvc3Helper120Path
        Log "Opened PMVC3 1.20 Helper"
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Helper executable not found at $Pumvc3Helper120Path",
            "PMVC3 1.20 Helper",
            "OK",
            "Warning"
        ) | Out-Null
        Log "PMVC3 1.20 Helper not found: $Pumvc3Helper120Path"
    }
}

function Open-Pumvc3Helper143 {
    if (Test-Path $Pumvc3Helper143Path) {
        Start-Process -FilePath $Pumvc3Helper143Path
        Log "Opened PMVC3 1.4.3 Helper"
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Helper executable not found at $Pumvc3Helper143Path",
            "PMVC3 1.4.3 Helper",
            "OK",
            "Warning"
        ) | Out-Null
        Log "PMVC3 1.4.3 Helper not found: $Pumvc3Helper143Path"
    }
}

# -- UI --
$Form = New-Object System.Windows.Forms.Form
$Form.Text            = "Arcade"
$Form.WindowState     = [System.Windows.Forms.FormWindowState]::Maximized
$Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$Form.TopMost         = $false
$Form.BackColor       = [System.Drawing.Color]::Black
$Form.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
$Form.KeyPreview      = $true

if (Test-Path $BackgroundImage) {
    try {
        $Form.BackgroundImage       = [System.Drawing.Image]::FromFile($BackgroundImage)
        $Form.BackgroundImageLayout = [System.Windows.Forms.ImageLayout]::Stretch
    } catch { Log "Failed to load background: $($_.Exception.Message)" }
}

$LaunchBtn = New-Object System.Windows.Forms.Button
$LaunchBtn.Text      = "LAUNCH GAME"
$LaunchBtn.Font      = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
$LaunchBtn.Size      = New-Object System.Drawing.Size(380, 120)
$LaunchBtn.Location  = New-Object System.Drawing.Point(44, 80)
$LaunchBtn.BackColor = [System.Drawing.Color]::FromArgb(33, 150, 243)
$LaunchBtn.ForeColor = [System.Drawing.Color]::White
$LaunchBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$LaunchBtn.FlatAppearance.BorderSize = 0
$LaunchBtn.Add_Click({ Start-Game })
$Form.Controls.Add($LaunchBtn)

$ExitGameBtn = New-Object System.Windows.Forms.Button
$ExitGameBtn.Text      = "EXIT GAME"
$ExitGameBtn.Font      = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
$ExitGameBtn.Size      = New-Object System.Drawing.Size(380, 120)
$ExitGameBtn.Location  = New-Object System.Drawing.Point(44, 80)
$ExitGameBtn.BackColor = [System.Drawing.Color]::FromArgb(183, 28, 28)
$ExitGameBtn.ForeColor = [System.Drawing.Color]::White
$ExitGameBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$ExitGameBtn.FlatAppearance.BorderSize = 0
$ExitGameBtn.Visible   = $false
$ExitGameBtn.Add_Click({ Stop-Game })
$Form.Controls.Add($ExitGameBtn)

$SteamBtn = New-Object System.Windows.Forms.Button
$SteamBtn.Text      = "STEAM"
$SteamBtn.Font      = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Regular)
$SteamBtn.Size      = New-Object System.Drawing.Size(180, 56)
$SteamBtn.Location  = New-Object System.Drawing.Point(44, 220)
$SteamBtn.BackColor = [System.Drawing.Color]::FromArgb(23, 26, 33)
$SteamBtn.ForeColor = [System.Drawing.Color]::White
$SteamBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$SteamBtn.FlatAppearance.BorderSize = 0
$SteamBtn.Add_Click({ Open-Steam })
$Form.Controls.Add($SteamBtn)

$ForceKillBtn = New-Object System.Windows.Forms.Button
$ForceKillBtn.Text      = "FORCE KILL"
$ForceKillBtn.Font      = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Regular)
$ForceKillBtn.Size      = New-Object System.Drawing.Size(180, 56)
$ForceKillBtn.Location  = New-Object System.Drawing.Point(236, 220)
$ForceKillBtn.BackColor = [System.Drawing.Color]::FromArgb(230, 81, 0)
$ForceKillBtn.ForeColor = [System.Drawing.Color]::White
$ForceKillBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$ForceKillBtn.FlatAppearance.BorderSize = 0
$ForceKillBtn.Add_Click({ Force-Kill-Game })
$Form.Controls.Add($ForceKillBtn)

$RecenterBtn = New-Object System.Windows.Forms.Button
$RecenterBtn.Text      = "RECENTER"
$RecenterBtn.Font      = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Regular)
$RecenterBtn.Size      = New-Object System.Drawing.Size(180, 56)
$RecenterBtn.Location  = New-Object System.Drawing.Point(428, 220)
$RecenterBtn.BackColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
$RecenterBtn.ForeColor = [System.Drawing.Color]::White
$RecenterBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$RecenterBtn.FlatAppearance.BorderSize = 0
$RecenterBtn.Add_Click({ Recenter-Game })
$Form.Controls.Add($RecenterBtn)

$AdminBtn = New-Object System.Windows.Forms.Button
$AdminBtn.Text      = "Admin Exit"
$AdminBtn.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
$AdminBtn.Size      = New-Object System.Drawing.Size(100, 28)
$AdminBtn.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$AdminBtn.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
$AdminBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$AdminBtn.FlatAppearance.BorderSize = 0
$AdminBtn.Add_Click({ Show-AdminExit })
$Form.Controls.Add($AdminBtn)

$PsBtn = New-Object System.Windows.Forms.Button
$PsBtn.Text      = "PowerShell"
$PsBtn.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
$PsBtn.Size      = New-Object System.Drawing.Size(100, 28)
$PsBtn.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$PsBtn.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
$PsBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$PsBtn.FlatAppearance.BorderSize = 0
$PsBtn.Add_Click({ Show-AdminPowerShell })
$Form.Controls.Add($PsBtn)

$Pumvc3InstructionsBtn = New-Object System.Windows.Forms.Button
$Pumvc3InstructionsBtn.Text      = "PMVC3 Special Instructions"
$Pumvc3InstructionsBtn.Font      = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Regular)
$Pumvc3InstructionsBtn.Size      = New-Object System.Drawing.Size(372, 56)
$Pumvc3InstructionsBtn.Location  = New-Object System.Drawing.Point(44, 288)
$Pumvc3InstructionsBtn.BackColor = [System.Drawing.Color]::FromArgb(55, 55, 55)
$Pumvc3InstructionsBtn.ForeColor = [System.Drawing.Color]::White
$Pumvc3InstructionsBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$Pumvc3InstructionsBtn.FlatAppearance.BorderSize = 0
$Pumvc3InstructionsBtn.Add_Click({ Open-Pumvc3SpecialInstructions })
$Form.Controls.Add($Pumvc3InstructionsBtn)

$Pumvc3Helper120Btn = New-Object System.Windows.Forms.Button
$Pumvc3Helper120Btn.Text      = "PMVC3 1.20 Helper"
$Pumvc3Helper120Btn.Font      = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Regular)
$Pumvc3Helper120Btn.Size      = New-Object System.Drawing.Size(180, 56)
$Pumvc3Helper120Btn.Location  = New-Object System.Drawing.Point(44, 356)
$Pumvc3Helper120Btn.BackColor = [System.Drawing.Color]::FromArgb(88, 101, 242)
$Pumvc3Helper120Btn.ForeColor = [System.Drawing.Color]::White
$Pumvc3Helper120Btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$Pumvc3Helper120Btn.FlatAppearance.BorderSize = 0
$Pumvc3Helper120Btn.Add_Click({ Open-Pumvc3Helper120 })
$Form.Controls.Add($Pumvc3Helper120Btn)

$Pumvc3Helper143Btn = New-Object System.Windows.Forms.Button
$Pumvc3Helper143Btn.Text      = "PMVC3 1.4.3 Helper"
$Pumvc3Helper143Btn.Font      = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Regular)
$Pumvc3Helper143Btn.Size      = New-Object System.Drawing.Size(180, 56)
$Pumvc3Helper143Btn.Location  = New-Object System.Drawing.Point(236, 356)
$Pumvc3Helper143Btn.BackColor = [System.Drawing.Color]::FromArgb(88, 101, 242)
$Pumvc3Helper143Btn.ForeColor = [System.Drawing.Color]::White
$Pumvc3Helper143Btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$Pumvc3Helper143Btn.FlatAppearance.BorderSize = 0
$Pumvc3Helper143Btn.Add_Click({ Open-Pumvc3Helper143 })
$Form.Controls.Add($Pumvc3Helper143Btn)

# -- Timers --
$HeartbeatTimer = New-Object System.Windows.Forms.Timer
$HeartbeatTimer.Interval = 10000
$HeartbeatTimer.Add_Tick({ Update-Heartbeat })

# Poll game.running flag file — single source of truth for button state
$script:WasRunning    = $false
$script:AdminShellProc = $null   # tracked while admin PS window is open
$GameStateTimer = New-Object System.Windows.Forms.Timer
$GameStateTimer.Interval = 2000
$GameStateTimer.Add_Tick({
    $running = Test-GameRunning
    if ($running -ne $script:WasRunning) {
        $script:WasRunning = $running
        Apply-GameState $running
    }
    # Clear admin shell tracking once the process exits
    if ($script:AdminShellProc -and $script:AdminShellProc.HasExited) {
        $script:AdminShellProc = $null
    }
})

# -- Events --
$Form.Add_Shown({
    $h = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
    $AdminBtn.Location = New-Object System.Drawing.Point(16, ($h - 46))
    $PsBtn.Location    = New-Object System.Drawing.Point(124, ($h - 46))
    # Clear stale flag from a previous crash/reboot
    Remove-Item $GameFlagPath -ErrorAction SilentlyContinue
    Update-Heartbeat
    $HeartbeatTimer.Start()
    $GameStateTimer.Start()
    [KbHook]::Install()
    if ($LaunchOnLogin) {
        Log "launch_on_login enabled; auto-launching game"
        Start-Game
    }
})

$Form.Add_Activated({
    $Form.SendToBack()
})

$Form.Add_FormClosing({ $_.Cancel = $true })
$Form.Add_KeyDown({
    if ($_.Alt     -and $_.KeyCode -eq [System.Windows.Forms.Keys]::F4)     { $_.Handled = $true }
    if ($_.Control -and $_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $_.Handled = $true }
})

[System.Windows.Forms.Application]::Run($Form)
[KbHook]::Uninstall()
