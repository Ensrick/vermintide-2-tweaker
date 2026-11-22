#requires -Version 7
<#
.SYNOPSIS
  For the owner only: registers the rig's nightly task DISABLED (WP-H-11 step 4). Agents never run this.

.DESCRIPTION
  Fills the placeholders of Vt2RigNightly.task.xml (pythonw.exe, the launcher, the rig root, this checkout, the current
  user) and registers the task with Register-ScheduledTask, then makes sure it is disabled. Enabling it is a separate,
  deliberate step: Task Scheduler > Vt2RigNightly > Enable, or Enable-ScheduledTask -TaskName Vt2RigNightly.

  -OutFile writes the filled XML and registers nothing (used by tools/harness/tests/Nightly.Tests.ps1).
#>
[CmdletBinding()]
param(
    [string] $RigRoot = (Join-Path $env:LOCALAPPDATA 'vt2-harness'),
    [string] $PythonW = '',
    [string] $OutFile = ''
)
$ErrorActionPreference = 'Stop'
if (-not $PythonW) {
    $cmd = Get-Command pythonw.exe -ErrorAction SilentlyContinue
    if ($cmd) { $PythonW = $cmd.Source }
    else {
        $py = Get-Command py.exe -ErrorAction SilentlyContinue
        if ($py) { $exe = & $py.Source -3 -c "import sys; print(sys.executable)"; $PythonW = Join-Path (Split-Path $exe) 'pythonw.exe' }
    }
}
if (-not $PythonW -or -not (Test-Path -LiteralPath $PythonW)) { throw 'pythonw.exe not found; pass -PythonW <path>' }
$here = $PSScriptRoot
$repo = (Resolve-Path -LiteralPath (Join-Path $here '..\..\..')).Path
function ConvertTo-XmlText([string] $s) { [System.Security.SecurityElement]::Escape($s) }
$xml = [System.IO.File]::ReadAllText((Join-Path $here 'Vt2RigNightly.task.xml'))
$xml = $xml.Replace('{{PYTHONW}}', (ConvertTo-XmlText $PythonW)).Replace('{{LAUNCHER}}', (ConvertTo-XmlText (Join-Path $here 'nightly_launch.pyw')))
$xml = $xml.Replace('{{RIGROOT}}', (ConvertTo-XmlText $RigRoot)).Replace('{{WORKDIR}}', (ConvertTo-XmlText $repo)).Replace('{{USER}}', (ConvertTo-XmlText "$env:USERDOMAIN\$env:USERNAME"))
if ($xml -match '\{\{') { throw 'an unfilled placeholder remains in the task XML' }
if ($xml -notmatch '<Enabled>false</Enabled>\s*<Hidden>') { throw 'the task definition must stay disabled by default' }
if ($OutFile) { [System.IO.File]::WriteAllText($OutFile, $xml, [System.Text.UTF8Encoding]::new($false)); Write-Host "wrote $OutFile (not registered)"; return }
Register-ScheduledTask -TaskName 'Vt2RigNightly' -Xml $xml -Force | Out-Null
Disable-ScheduledTask -TaskName 'Vt2RigNightly' | Out-Null
Write-Host 'registered Vt2RigNightly, DISABLED. Enable it yourself when you want nightly runs: Enable-ScheduledTask -TaskName Vt2RigNightly'
