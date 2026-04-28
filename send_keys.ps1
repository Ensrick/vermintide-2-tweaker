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
