# C1 probe: does a child process with a redirected USERPROFILE/APPDATA see a redirected CSIDL_APPDATA?
# Child-process environment only. Nothing persistent. No game, no GUI.
param([string]$Fake = 'docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts/C1_fake_profile')
$code = @'
Add-Type -Namespace C1 -Name Shell -MemberDefinition '[DllImport("shell32.dll", CharSet=CharSet.Unicode)] public static extern bool SHGetSpecialFolderPathW(IntPtr hwnd, System.Text.StringBuilder path, int csidl, bool create);'
$sb = New-Object System.Text.StringBuilder 520
[void][C1.Shell]::SHGetSpecialFolderPathW([IntPtr]::Zero, $sb, 0x1a, $false)
"SHGetSpecialFolderPathW(CSIDL_APPDATA) = $($sb.ToString())"
"dotnet GetFolderPath(ApplicationData)  = $([Environment]::GetFolderPath('ApplicationData'))"
"env APPDATA = $env:APPDATA ; env USERPROFILE = $env:USERPROFILE"
'@
function Run-Child([hashtable]$envOverride, [string]$label) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command -'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    foreach ($k in $envOverride.Keys) { $psi.EnvironmentVariables[$k] = $envOverride[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.WriteLine($code); $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
    "--- $label"; $out.Trim()
}
Run-Child @{} 'baseline (inherited env)'
Run-Child @{ APPDATA = "$Fake\AppData\Roaming" } 'APPDATA only redirected'
Run-Child @{ USERPROFILE = $Fake } 'USERPROFILE only redirected'
Run-Child @{ USERPROFILE = $Fake; APPDATA = "$Fake\AppData\Roaming" } 'USERPROFILE + APPDATA redirected'
