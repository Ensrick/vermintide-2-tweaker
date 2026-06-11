# check_command_collisions.ps1 — flags chat command names registered by 2+ mods.
#
# VT2 chat commands are GLOBAL (per memory reference_vt2_chat_command_syntax.md).
# When two mods both call `mod:command("foo", ...)`, only the first wins; the
# rest fail silently except for an `[ERROR] (command):` log line. This check
# catches such collisions at QA time instead of at runtime.
#
# See qa/CHECKS.md row #X (added 2026-05-23) and GitHub Issue #11.
#
# Exit codes: 0 = pass (no collisions), 1 = warnings, 2 = collisions found.

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path $RepoRoot).Path

function Read-FileUtf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

function Find-ModLuas {
    Get-ChildItem -Path $repoRoot -Filter "*.lua" -Recurse -File -ErrorAction SilentlyContinue `
        | Where-Object {
            $p = $_.FullName
            $p -notlike "*\_archive\*" `
                -and $p -notlike "*\bundleV2\*" `
                -and $p -notlike "*\.build\*" `
                -and $p -notlike "*\.temp\*" `
                -and $p -notlike "*\.spawn_tweaks_ref\*" `
                -and $p -notlike "*\tweaker\*" `
                -and $p -notlike "*\sample_*\*" `
                -and $p -notlike "*\Vermintide-2-Source-Code\*" `
                -and $p -notlike "*\misc-vermintide-mods\*" `
                -and $p -notlike "*.lua.processed"
        }
}

function Get-ModNameForPath([string]$path) {
    # Path looks like: <repo>/<mod>/scripts/mods/<mod>/<file>.lua
    # Walk path segments and find the one immediately under repo root.
    $rel = $path.Substring($repoRoot.Length).TrimStart('\','/')
    return ($rel -split '[\\/]')[0]
}

# Collect all command registrations: { name => @{ mods = @(...), sites = @(...) } }
$commands = @{}

foreach ($lua in Find-ModLuas) {
    $modName = Get-ModNameForPath $lua.FullName
    $text = Read-FileUtf8 $lua.FullName

    # Match: mod:command("name", ...) — captures the literal string name.
    # Permissive on whitespace, doesn't match dynamic-key forms (those are rare
    # and intentional — we only care about literal collisions).
    foreach ($m in [regex]::Matches($text, 'mod:command\s*\(\s*"([^"]+)"')) {
        $cmd = $m.Groups[1].Value
        # Line number for the report
        $offset = $m.Index
        $lineNum = ([regex]::Matches($text.Substring(0, $offset), "`n")).Count + 1

        if (-not $commands.ContainsKey($cmd)) {
            $commands[$cmd] = @{ mods = @(); sites = @() }
        }
        if ($commands[$cmd].mods -notcontains $modName) {
            $commands[$cmd].mods += $modName
        }
        $commands[$cmd].sites += "${modName}:$($lua.Name):$lineNum"
    }
}

# Find collisions: any command name owned by 2+ distinct BASE mods.
# audit 2026-06-07: dev/stable twins (`<mod>` and `<mod>_dev`) are SEPARATE VMF
# registrations that coexist by design (see CLAUDE.md "Dev/stable split workflow")
# and legitimately share every command name — a tester runs one stream at a time.
# Treating those as collisions hard-failed run_all on 140 expected duplicates and
# masked genuine cross-mod collisions. Collapse a trailing `_dev` so only DISTINCT
# base mods count. (The only `_dev` dirs are the four public-mod dev clones, all of
# the form `<base>_dev`, so the strip is unambiguous.)
$collisions = @()
foreach ($cmd in $commands.Keys) {
    $entry = $commands[$cmd]
    $baseMods = @($entry.mods | ForEach-Object { $_ -replace '_dev$', '' } | Sort-Object -Unique)
    if ($baseMods.Count -gt 1) {
        $collisions += [PSCustomObject]@{
            Name = $cmd
            Mods = $entry.mods -join ", "
            Sites = $entry.sites
        }
    }
}

# Report
Write-Host ""
if (-not $Quiet) {
    Write-Host "[check_command_collisions] Scanned $($commands.Count) unique command names across $(($commands.Values | ForEach-Object { $_.mods } | Sort-Object -Unique).Count) mods." -ForegroundColor DarkGray
}

if ($collisions.Count -eq 0) {
    Write-Host "[check_command_collisions] OK — no cross-mod command collisions." -ForegroundColor Green
    exit 0
}

Write-Host "[check_command_collisions] ERRORS — $($collisions.Count) command name(s) registered by multiple mods:" -ForegroundColor Red
foreach ($c in $collisions | Sort-Object -Property Name) {
    Write-Host "  X /$($c.Name) — registered by [$($c.Mods)]" -ForegroundColor Red
    foreach ($s in $c.Sites) {
        Write-Host "      $s" -ForegroundColor DarkRed
    }
}
Write-Host ""
Write-Host "Recommendation: rename per-mod with a short-id prefix (e.g. /ct_foo, /wt_foo)." -ForegroundColor DarkYellow
Write-Host "Reference: GitHub Issue #11, memory reference_vt2_chat_command_syntax.md." -ForegroundColor DarkYellow
exit 2
