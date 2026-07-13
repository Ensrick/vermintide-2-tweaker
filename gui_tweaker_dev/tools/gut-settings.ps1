<#
.SYNOPSIS
  Write gut_mod_settings.toml from a Tweaker: GUI /export_settings log dump.

.DESCRIPTION
  Retail VMF mods cannot read or write arbitrary files, so "Tweaker: GUI" exports its
  settings by printing TOML to the console log (prefix [gut:toml]). This script
  parses the newest (or a given) console log, extracts the most recent
  BEGIN..END block, and writes it to:
      %APPDATA%\Fatshark\Vermintide 2\gut_mod_settings.toml
  This is a backup/reference snapshot; the retail game cannot read it back.

  Snapshot flow:
    in-game  ->  /export_settings        (dumps TOML to the log)
    desktop  ->  .\gut-settings.ps1      (writes the .toml snapshot from the log)

.PARAMETER LogPath
  A specific console log to parse. Default: newest console-*.log under the V2 log dir.

.PARAMETER OutPath
  Where to write the .toml. Default: %APPDATA%\Fatshark\Vermintide 2\gut_mod_settings.toml
#>
[CmdletBinding()]
param(
    [string]$LogPath,
    [string]$OutPath
)

$ErrorActionPreference = 'Stop'
$v2dir   = Join-Path $env:APPDATA 'Fatshark\Vermintide 2'
$logsdir = Join-Path $v2dir 'console_logs'
if (-not $OutPath) { $OutPath = Join-Path $v2dir 'gut_mod_settings.toml' }

if (-not $LogPath) {
    $newest = Get-ChildItem -Path $logsdir -Filter 'console-*.log' -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $newest) { throw "No console-*.log found under $logsdir" }
    $LogPath = $newest.FullName
}
Write-Host "Reading log : $LogPath"

# Keep only [gut:toml] lines, strip everything up to and including the prefix.
$tomlLines = Get-Content -LiteralPath $LogPath |
    Where-Object { $_ -match '\[gut:toml\] ' } |
    ForEach-Object { $_ -replace '^.*?\[gut:toml\] ', '' }

if (-not $tomlLines) { throw "No [gut:toml] lines in the log. Run /export_settings in-game first." }

# Take the LAST BEGIN..END block (most recent export), dropping the marker lines.
$beginIdx = ($tomlLines | Select-String -Pattern '^===== BEGIN ' -SimpleMatch:$false |
             Select-Object -Last 1).LineNumber
$endIdx   = ($tomlLines | Select-String -Pattern '^===== END '   -SimpleMatch:$false |
             Select-Object -Last 1).LineNumber
if ($beginIdx -and $endIdx -and $endIdx -gt $beginIdx) {
    # Select-String LineNumber is 1-based; content is between the markers (exclusive).
    $body = $tomlLines[$beginIdx..($endIdx - 2)]
} else {
    # No markers (older export) -> use everything.
    $body = $tomlLines
}

# De-duplicate consecutive blank lines, trim trailing blanks.
$text = ($body -join "`r`n").TrimEnd() + "`r`n"

if (Test-Path -LiteralPath $OutPath) {
    $bak = "$OutPath.bak"
    Copy-Item -LiteralPath $OutPath -Destination $bak -Force
    Write-Host "Backed up existing -> $bak"
}
Set-Content -LiteralPath $OutPath -Value $text -Encoding UTF8 -NoNewline
Write-Host "Wrote       : $OutPath  ($(( $body | Measure-Object).Count) lines)"
Write-Host "Snapshot only: retail Vermintide cannot read or apply this file."
