<#
.SYNOPSIS
  Agent-bridge watcher: materialize [agent:*] console-log frames into files (issue #1338).

.DESCRIPTION
  Retail VMF mods cannot write files; the console log is the outbound channel.
  gt_dev's _gt_agent_bridge.lua emits framed engine-printf lines; this watcher
  tails the newest Vermintide 2 console log and writes them to an inbox
  directory an external Claude session reads with plain file tools.

  Protocol (kept in sync with _gt_agent_bridge.lua):
    [agent:hb] seq=N t=... state=... level=... pos=... hp=...  -> stream.log + latest-hb.txt
    [agent:dump:<seq>] BEGIN <path>                            -> opens frame <seq>
    [agent:d] <payload line>                                   -> body of the open frame
    [agent:dump:<seq>] END                                     -> writes dump-<seq>.txt
    [agent] / [agent:probe] anything else                      -> stream.log

  Leave running in a terminal while the game is up. Ctrl+C to stop. Handles
  log rotation (new session = new console-*.log) by re-selecting the newest
  file and restarting from offset 0.

.PARAMETER IntervalSeconds
  Poll interval. Default 1.

.PARAMETER OutDir
  Inbox directory. Default: %APPDATA%\Fatshark\Vermintide 2\agent_bridge
#>
[CmdletBinding()]
param(
    [double]$IntervalSeconds = 1,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
$logsdir = Join-Path $env:APPDATA 'Fatshark\Vermintide 2\console_logs'
if (-not $OutDir) { $OutDir = Join-Path $env:APPDATA 'Fatshark\Vermintide 2\agent_bridge' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$streamPath = Join-Path $OutDir 'stream.log'
$latestHbPath = Join-Path $OutDir 'latest-hb.txt'

Write-Host "[agent-bridge] watching $logsdir -> $OutDir (Ctrl+C to stop)"

$curFile = $null
$offset = 0
$carry = ''            # partial trailing line between polls
$frameSeq = $null      # open dump frame seq
$frameHeader = $null
$frameLines = @()

function Get-NewestLog {
    Get-ChildItem -Path $logsdir -Filter 'console-*.log' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
}

while ($true) {
    try {
        $newest = Get-NewestLog
        if ($newest) {
            if ($curFile -ne $newest.FullName) {
                $curFile = $newest.FullName
                $offset = 0
                $carry = ''
                $frameSeq = $null
                Write-Host "[agent-bridge] tailing $curFile"
            }
            $fs = [System.IO.File]::Open($curFile, 'Open', 'Read', 'ReadWrite')
            try {
                if ($fs.Length -gt $offset) {
                    $fs.Seek($offset, 'Begin') | Out-Null
                    $buf = New-Object byte[] ($fs.Length - $offset)
                    $read = $fs.Read($buf, 0, $buf.Length)
                    $offset += $read
                    $chunk = $carry + [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
                    $lines = $chunk -split "`n"
                    # Last element is either '' (chunk ended on newline) or a partial line.
                    $carry = $lines[-1]
                    for ($i = 0; $i -lt $lines.Length - 1; $i++) {
                        $line = $lines[$i].TrimEnd("`r")
                        if ($line -notmatch '\[agent[\]:]') { continue }
                        # Strip any engine-logger prefix before our marker.
                        $payload = $line -replace '^.*?(?=\[agent)', ''
                        Add-Content -Path $streamPath -Value $payload
                        if ($payload -match '^\[agent:hb\]') {
                            Set-Content -Path $latestHbPath -Value $payload
                        }
                        elseif ($payload -match '^\[agent:dump:(\d+)\] BEGIN (.*)$') {
                            $frameSeq = $Matches[1]
                            $frameHeader = $Matches[2]
                            $frameLines = @()
                        }
                        elseif ($payload -match '^\[agent:d\] (.*)$') {
                            if ($null -ne $frameSeq) { $frameLines += $Matches[1] }
                        }
                        elseif ($payload -match '^\[agent:dump:(\d+)\] END') {
                            if ($frameSeq -eq $Matches[1]) {
                                $dumpPath = Join-Path $OutDir ("dump-{0}.txt" -f $frameSeq)
                                Set-Content -Path $dumpPath -Value (@("-- $frameHeader") + $frameLines)
                                Write-Host "[agent-bridge] wrote $dumpPath ($($frameLines.Count) lines)"
                            }
                            $frameSeq = $null
                        }
                    }
                }
            }
            finally { $fs.Dispose() }
        }
    }
    catch {
        Write-Host "[agent-bridge] poll error: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $IntervalSeconds
}
