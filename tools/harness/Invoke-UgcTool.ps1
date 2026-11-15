#requires -Version 7
<#
.SYNOPSIS
  Runs the SDK's ugc_tool.exe for one item config and answers its modding-EULA prompt (WP-H-07).

.DESCRIPTION
  ugc_tool asks the Vermintide 2 modding EULA question on stdin and exits 1 "You did not agree to the EULA"
  without an answer. Like VMB (vmb/scripts/tools/uploader.js: it writes 'y' when the output contains
  "Vermintide 2 End User License Agreement"), this script watches the tool's output, writes 'y' once the prompt
  appears, then closes stdin. The tool's output is echoed. The published id is taken from item.cfg
  (published_id = <n>L;) or else from the tool's "publisher_id: <n>" line, which it prints as a signed 32-bit
  integer (read as unsigned, as VMB does).

.OUTPUTS
  [pscustomobject] ExitCode, Answered (the EULA prompt was seen and answered), PublishedId (string or $null),
  Output.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $UgcTool,
    [Parameter(Mandatory)] [string] $Config,
    [Parameter(Mandatory)] [string] $WorkingDirectory,
    [int] $TimeoutSeconds = 600
)
$ErrorActionPreference = 'Stop'
$psi = [System.Diagnostics.ProcessStartInfo]::new($UgcTool)
foreach ($a in '-c', $Config, '-x') { $psi.ArgumentList.Add($a) }
$psi.WorkingDirectory = $WorkingDirectory
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$p = [System.Diagnostics.Process]::Start($psi)
$errTask = $p.StandardError.ReadToEndAsync()
$seen = [System.Text.StringBuilder]::new()
$buffer = [char[]]::new(4096)
$answered = $false
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
try {
    while ($true) {
        $read = $p.StandardOutput.ReadAsync($buffer, 0, $buffer.Length)
        $left = [int][math]::Max(1, ($deadline - (Get-Date)).TotalMilliseconds)
        if (-not $read.Wait($left)) { $p.Kill($true); throw "ugc_tool timed out after $TimeoutSeconds s" }
        $n = $read.Result
        if ($n -le 0) { break }
        $chunk = [string]::new($buffer, 0, $n)
        Write-Host -NoNewline $chunk
        [void]$seen.Append($chunk)
        if (-not $answered -and $seen.ToString().Contains('Vermintide 2 End User License Agreement')) {
            $p.StandardInput.Write('y')
            $p.StandardInput.Flush()
            $p.StandardInput.Close()
            $answered = $true
        }
    }
    $p.WaitForExit()
    $output = $seen.ToString() + $errTask.GetAwaiter().GetResult()
    $id = $null
    $cfgId = [regex]::Match([System.IO.File]::ReadAllText($Config), '(?m)^published_id = (\d+)L;')
    if ($cfgId.Success) { $id = $cfgId.Groups[1].Value }
    else {
        $printed = [regex]::Match($output, 'publisher_id: (-?\d+)')
        if ($printed.Success) { $id = [string]([uint32]([int64]$printed.Groups[1].Value -band 0xFFFFFFFFL)) }
    }
    [pscustomobject]@{ ExitCode = $p.ExitCode; Answered = $answered; PublishedId = $id; Output = $output }
}
finally { $p.Dispose() }
