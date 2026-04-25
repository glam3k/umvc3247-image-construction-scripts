# Launch-Game.ps1
# Selects a mod folder, hot-swaps the Steam junction, launches UMVC3,
# and manages the game.running marker used by the kiosk shell.

# --- CONFIGURATION ---
$steamGameDir = "C:\Program Files (x86)\Steam\steamapps\common\Ultimate Marvel VS. Capcom 3"
$arcadeBaseDir = "C:\Arcade\Games"
$steamExe      = "C:\Program Files (x86)\Steam\Steam.exe"
$markerFile    = "C:\Arcade\game.running"

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32GameFocus {
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

# --- 1. KILL STEAM (unlock files for junction swap) ---
if (Get-Process "Steam" -ErrorAction SilentlyContinue) {
    Stop-Process -Name "Steam" -Force
    Start-Sleep -Seconds 2
}

# --- 2. MOD SELECTOR ---
Add-Type -AssemblyName System.Windows.Forms
$folders = Get-ChildItem -Path $arcadeBaseDir -Directory
$form = New-Object System.Windows.Forms.Form
$form.Text = "UMVC3 Selector"; $form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(300, ($folders.Count * 40 + 100))
$y = 50
foreach ($f in $folders) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $f.Name; $btn.Location = New-Object System.Drawing.Point(50, $y)
    $btn.Size = New-Object System.Drawing.Size(180, 30); $btn.Tag = $f.FullName
    $btn.Add_Click({ $script:selectedFolder = $this.Tag; $form.Close() })
    $form.Controls.Add($btn); $y += 40
}
$form.ShowDialog() | Out-Null
if (-not $script:selectedFolder) { exit 1 }

# --- 3. JUNCTION SWAP ---
if (Test-Path $steamGameDir) { cmd /c rmdir "$steamGameDir" }
cmd /c mklink /J "$steamGameDir" "$script:selectedFolder"

# --- 4. LAUNCH AND MONITOR ---
New-Item -Path $markerFile -ItemType File -Force | Out-Null

try {
    Write-Host "Waking up Steam..." -ForegroundColor Cyan
    Start-Process -FilePath $steamExe -ArgumentList "-silent"
    Start-Sleep -Seconds 5

    Write-Host "Launching Game..." -ForegroundColor Green
    $gameExe = Join-Path $steamGameDir "umvc3.exe"
    Start-Process -FilePath $gameExe -WorkingDirectory $steamGameDir

    # --- PHASE 1: WAIT FOR PROCESS (up to 45s) ---
    $detected = $false
    for ($i = 0; $i -lt 45; $i++) {
        $proc = Get-Process "umvc3" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($proc) {
            $detected = $true
            Write-Host "Process detected. Forcing focus..." -ForegroundColor Green
            Start-Sleep -Seconds 3
            $hwnd = [Win32GameFocus]::FindWindowByPid([uint32]$proc.Id)
            if ($hwnd -ne [IntPtr]::Zero) {
                [Win32GameFocus]::SetWindowPos($hwnd, [IntPtr]::Zero, 0, 0, 0, 0, 0x0041)
                [Win32GameFocus]::ShowWindow($hwnd, 5)
                [Win32GameFocus]::SetForegroundWindow($hwnd)
            }
            break
        }
        Start-Sleep -Seconds 1
    }

    if (-not $detected) { throw "Launch timed out after 45s." }

    # --- PHASE 2: MONITOR FOR EXIT ---
    # Wall-clock absence detection instead of consecutive-miss counter.
    # On cold boot Steam performs "install verification" after the junction swap,
    # which kills the directly-launched umvc3.exe and relaunches it itself.
    # That gap can exceed 15s. We only declare the game truly gone if it has
    # been absent for $requiredAbsenceSecs continuous wall-clock seconds.
    $requiredAbsenceSecs = 20
    $lastSeenTime = Get-Date

    while ($true) {
        if (Get-Process "umvc3" -ErrorAction SilentlyContinue) {
            $lastSeenTime = Get-Date
            Start-Sleep -Seconds 2
        } else {
            $elapsed = [int]((Get-Date) - $lastSeenTime).TotalSeconds
            if ($elapsed -ge $requiredAbsenceSecs) {
                Write-Host "Game absent for $elapsed s. Closing." -ForegroundColor Magenta
                break
            }
            Write-Host "Process absent for ${elapsed}s / ${requiredAbsenceSecs}s — waiting for Steam hand-off" -ForegroundColor Gray
            Start-Sleep -Seconds 1
        }
    }
}
finally {
    Remove-Item -Path $markerFile -Force -ErrorAction SilentlyContinue
}
