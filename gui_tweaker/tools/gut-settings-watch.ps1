<#
.SYNOPSIS
  Background watcher: auto-write gut_mod_settings.toml whenever Tweaker: GUI exports.

.DESCRIPTION
  VMF mods can read files but not write them. This watcher is the "write" half:
  it polls the newest Vermintide 2 console log and, whenever it sees a fresh
  [gut:toml] BEGIN..END block (the mod emits one on /gut_export_settings AND
  automatically when you close the Mod Tweaker after changing a setting), it
  writes that TOML to:
      %APPDATA%\Fatshark\Vermintide 2\gut_mod_settings.toml

  So the round-trip becomes seamless:
    in-game  : change settings in the Mod Tweaker, close it (or /gut_export_settings)
    watcher  : commits gut_mod_settings.toml automatically
    you      : edit the .toml by hand any time
    in-game  : restart or /gut_reload_config to load the file back

  Leave this running in a terminal while you play. Ctrl+C to stop. It only writes
  when the exported content actually changes, and backs up the previous file to
  gut_mod_settings.toml.bak.

.PARAMETER IntervalSeconds
  Poll interval. Default 3.

.PARAMETER OutPath
  Override the output path (default: %APPDATA%\Fatshark\Vermintide 2\gut_mod_settings.toml).
#>
[CmdletBinding()]
param(
    [int]$IntervalSeconds = 3,
    [string]$OutPath
)

$ErrorActionPreference = 'Stop'
$v2dir   = Join-Path $env:APPDATA 'Fatshark\Vermintide 2'
$logsdir = Join-Path $v2dir 'console_logs'
if (-not $OutPath) { $OutPath = Join-Path $v2dir 'gut_mod_settings.toml' }

function Get-LatestTomlBlock {
    $newest = Get-ChildItem -Path $logsdir -Filter 'console-*.log' -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $newest) { return $null }
    $lines = Get-Content -LiteralPath $newest.FullName |
             Where-Object { $_ -match '\[gut:toml\] ' } |
             ForEach-Object { $_ -replace '^.*?\[gut:toml\] ', '' }
    if (-not $lines) { return $null }
    $b = ($lines | Select-String -Pattern '^===== BEGIN ' | Select-Object -Last 1).LineNumber
    $e = ($lines | Select-String -Pattern '^===== END '   | Select-Object -Last 1).LineNumber
    if (-not ($b -and $e -and $e -gt $b)) { return $null }
    return (($lines[$b..($e - 2)] -join "`r`n").TrimEnd() + "`r`n")
}

Write-Host "gut settings watcher running. Out: $OutPath"
Write-Host "Watching $logsdir every ${IntervalSeconds}s. Ctrl+C to stop."
$last = if (Test-Path -LiteralPath $OutPath) { Get-Content -LiteralPath $OutPath -Raw } else { '' }

while ($true) {
    try {
        $block = Get-LatestTomlBlock
        if ($block -and $block -ne $last) {
            if (Test-Path -LiteralPath $OutPath) {
                Copy-Item -LiteralPath $OutPath -Destination "$OutPath.bak" -Force
            }
            Set-Content -LiteralPath $OutPath -Value $block -Encoding UTF8 -NoNewline
            $last = $block
            $stamp = (Get-Date).ToString('HH:mm:ss')
            Write-Host "[$stamp] wrote gut_mod_settings.toml ($(($block -split "`n").Count) lines)"
        }
    } catch {
        Write-Warning $_.Exception.Message
    }
    Start-Sleep -Seconds $IntervalSeconds
}
