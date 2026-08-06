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
    [string]$RepoRoot,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = Join-Path $scriptDir '..' }
function Read-FileUtf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

function Get-CanonicalModDirectories([string]$root) {
    $inventoryPath = Join-Path $root 'tools\mod-inventory.psd1'
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        throw "canonical mod inventory not found: $inventoryPath"
    }
    $inventory = Import-PowerShellDataFile -LiteralPath $inventoryPath
    return @($inventory.Mods | ForEach-Object { [string]$_.Dir })
}

function Find-ModLuas([string]$root, [string[]]$modDirectories) {
    $files = @()
    foreach ($modName in @($modDirectories)) {
        # Inventory-owned top-level roots are the authority. Never recurse from
        # the repository root: a valid nested worktree may contain a complete
        # second checkout under .claude/worktrees and is not another mod.
        $sourceRoot = Join-Path $root (Join-Path $modName 'scripts\mods')
        if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { continue }
        foreach ($lua in Get-ChildItem -LiteralPath $sourceRoot -Filter '*.lua' -Recurse -File -ErrorAction SilentlyContinue) {
            if ($lua.FullName -like '*.lua.processed') { continue }
            $files += [pscustomobject]@{
                FullName = $lua.FullName
                Name = $lua.Name
                ModName = $modName
            }
        }
    }
    return $files
}

function Get-CommandInventory([string]$root, [string[]]$modDirectories) {
    $commands = @{}
    foreach ($lua in Find-ModLuas -root $root -modDirectories $modDirectories) {
        $modName = $lua.ModName
        $text = Read-FileUtf8 $lua.FullName

        # Match: mod:command("name", ...) - captures the literal string name.
        # Permissive on whitespace; dynamic-key forms remain intentional.
        foreach ($m in [regex]::Matches($text, 'mod:command\s*\(\s*"([^"]+)"')) {
            $cmd = $m.Groups[1].Value
            $lineNum = ([regex]::Matches($text.Substring(0, $m.Index), "`n")).Count + 1
            if (-not $commands.ContainsKey($cmd)) {
                $commands[$cmd] = @{ mods = @(); sites = @() }
            }
            if ($commands[$cmd].mods -notcontains $modName) {
                $commands[$cmd].mods += $modName
            }
            $commands[$cmd].sites += "${modName}:$($lua.Name):$lineNum"
        }
    }
    return $commands
}

function Get-CommandCollisions($commands) {
    # Dev/stable twins intentionally share commands and are mutually exclusive.
    $collisions = @()
    foreach ($cmd in $commands.Keys) {
        $entry = $commands[$cmd]
        $baseMods = @($entry.mods | ForEach-Object { $_ -replace '_dev$', '' } | Sort-Object -Unique)
        if ($baseMods.Count -gt 1) {
            $collisions += [pscustomobject]@{
                Name = $cmd
                Mods = $entry.mods -join ', '
                Sites = $entry.sites
            }
        }
    }
    return $collisions
}

function Invoke-CommandCollisionSelfTest {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-command-collision-' + [guid]::NewGuid().ToString('N'))
    $script:__ccPass = $true
    function Assert($condition, [string]$description) {
        $verdict = if ($condition) { 'PASS' } else { 'FAIL' }
        Write-Host "  [$verdict] $description"
        if (-not $condition) { $script:__ccPass = $false }
    }
    function Write-Fixture([string]$relativePath, [string]$content) {
        $path = Join-Path $tmp $relativePath
        [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path)) | Out-Null
        [System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)
    }
    try {
        Write-Fixture 'tools\mod-inventory.psd1' "@{ Mods = @(@{ Dir = 'mod_a' }, @{ Dir = 'mod_b' }) }"
        Write-Fixture 'mod_a\scripts\mods\mod_a\a.lua' 'mod:command("alpha", "", function() end)'
        Write-Fixture 'mod_a\scripts\mods\mod_a\a_second.lua' 'mod:command("alpha", "", function() end)'
        Write-Fixture 'mod_b\scripts\mods\mod_b\b.lua' 'mod:command("beta", "", function() end)'
        Write-Fixture '.claude\worktrees\copy\mod_b\scripts\mods\mod_b\b.lua' 'mod:command("alpha", "", function() end)'

        $mods = @(Get-CanonicalModDirectories -root $tmp)
        $commands = Get-CommandInventory -root $tmp -modDirectories $mods
        $collisions = @(Get-CommandCollisions $commands)
        Assert ($mods.Count -eq 2) 'canonical roots come from tools/mod-inventory.psd1'
        Assert ($commands['alpha'].mods.Count -eq 1) 'nested worktree copy is not a pseudo-mod'
        Assert ($commands['alpha'].sites.Count -eq 2) 'same-owner registrations retain existing owner policy and evidence'
        Assert ($collisions.Count -eq 0) 'nested copy and same-owner sites do not create a cross-mod collision'

        Write-Fixture 'mod_b\scripts\mods\mod_b\b.lua' 'mod:command("alpha", "", function() end)'
        $commands = Get-CommandInventory -root $tmp -modDirectories $mods
        $collisions = @(Get-CommandCollisions $commands)
        Assert ($collisions.Count -eq 1) 'real duplicate across canonical mod owners still fails'
        Assert ($collisions[0].Name -eq 'alpha') 'real collision reports the exact command'
        Assert ($collisions[0].Mods -match 'mod_a' -and $collisions[0].Mods -match 'mod_b') 'real collision reports both owners'
    }
    finally {
        if (Test-Path -LiteralPath $tmp) { [System.IO.Directory]::Delete($tmp, $true) }
    }
    if (-not $script:__ccPass) { exit 2 }
    Write-Host '[check_command_collisions -SelfTest] OK' -ForegroundColor Green
    exit 0
}

if ($SelfTest) { Invoke-CommandCollisionSelfTest }

$repoRoot = (Resolve-Path $RepoRoot).Path
$modDirectories = @(Get-CanonicalModDirectories -root $repoRoot)
$commands = Get-CommandInventory -root $repoRoot -modDirectories $modDirectories
$collisions = @(Get-CommandCollisions $commands)

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
