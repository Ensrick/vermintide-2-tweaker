# REVIEW: Safety review (2026-05-01)
# - Window targeting: Looks up by exact title "Vermintide 2" via FindWindow with null class.
#   Risk: if any other window has the title "Vermintide 2" (e.g. a browser tab pinned with
#   that exact title) it would receive the keystrokes instead. Low real-world risk but worth
#   knowing. Consider ALSO matching the class name or process name as a guard.
# - SetForegroundWindow then SendKeys: standard SendKeys interface — keystrokes go to whatever
#   window actually has focus when SendWait fires, not necessarily $hwnd if focus stealing is
#   blocked by Windows. The 200ms Start-Sleep mitigates but does not guarantee.
# - $Keys is unbounded — accepts any SendKeys-formatted string. Caller is trusted (this is a
#   dev tool); no injection vector since the script is invoked locally.
# - Behavior on "VT2 not found": exit 1 cleanly. Good.
# - keybd_event Add-Type is declared but never used — the script exclusively uses
#   System.Windows.Forms.SendKeys. Dead code; safe to remove the InputSender class declaration.
# Verdict: SAFE for the intended dev-iteration use case (sending console commands, etc.).
# No risk of unintended keystroke replay beyond the user's own typing into another window
# named exactly "Vermintide 2".
param(
    [Parameter(Mandatory=$true)]
    [string]$Keys
)

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class InputSender {
    [DllImport("user32.dll")]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    public const uint KEYEVENTF_KEYUP = 0x0002;
}
"@

Add-Type -AssemblyName System.Windows.Forms

$hwnd = [InputSender]::FindWindow($null, "Vermintide 2")
if ($hwnd -eq [IntPtr]::Zero) {
    Write-Host "ERROR: Vermintide 2 window not found"
    exit 1
}

[InputSender]::SetForegroundWindow($hwnd)
Start-Sleep -Milliseconds 200
[System.Windows.Forms.SendKeys]::SendWait($Keys)
Write-Host "Sent: $Keys"
