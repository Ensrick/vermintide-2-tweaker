# check_patch_day.ps1 - the patch-day canary as one command (WP-T-04). Run it after every game update, before
# anything ships: it says which hook targets and icon names no longer exist in the updated game.
#
# Parts, one summary line each:
#   decompile   the decompiled vanilla source it checks against ($env:VT2_DECOMPILE_ROOT, else
#               ../Vermintide-2-Source-Code next to this checkout or next to its primary checkout), with its
#               short HEAD and newest commit subject. Absent: everything is SKIP and the exit code is 0.
#   hooks       qa/patchday/hook_targets.py: literal mod:hook("Class", "method") targets that no longer resolve
#               (whole class(X, Parent) chain); qa/patchday/hook_allowlist.txt lists the expected misses.
#   icons       qa/patchday/icon_atlas.py: literal icon = "<name>" values missing from every icon atlas;
#               qa/patchday/icon_allowlist.txt lists the expected misses.
#   self-tests  both scripts' --self-test: a planted IngameUI.not_in_modded hook and a planted icon must fail.
#   integration qa/check_integration.ps1 when it exists (WP-T-03).
#   lua         the offline Lua suite (qa/check_lua_unit_tests.ps1); -SkipLua leaves it out.
# Exit 2 when any part fails, else 0. Read-only. Not part of the pre-commit hook or hosted CI: the hosted runner has
# no decompile (card guardrail). Procedure: docs/BUG_TRIAGE_RUNBOOK.md "Game update procedure".

[CmdletBinding()]
param(
    [string]$DecompileRoot = '',
    [string]$Python = '',
    [switch]$SkipLua
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$results = [System.Collections.Generic.List[object]]::new()
function Add-Part([string]$Name, [string]$Status, [string]$Detail) { $results.Add([pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail }) }
function Write-Summary {
    foreach ($r in $results) { Write-Host ('[patch_day] {0,-11} {1,-4} {2}' -f $r.Name, $r.Status, $r.Detail) }
}

# ---------- decompile root ----------
$candidates = @()
if ($DecompileRoot) { $candidates += $DecompileRoot }
elseif ($env:VT2_DECOMPILE_ROOT) { $candidates += $env:VT2_DECOMPILE_ROOT }
else {
    $candidates += (Join-Path $repoRoot '..\Vermintide-2-Source-Code')
    try {
        $common = (& git -C $repoRoot rev-parse --path-format=absolute --git-common-dir 2>$null)
        if ($common) { $candidates += (Join-Path (Split-Path (Split-Path $common)) 'Vermintide-2-Source-Code') }
    } catch { }
}
$decompile = $null
foreach ($c in $candidates) { if ($c -and (Test-Path -LiteralPath (Join-Path $c 'scripts') -PathType Container)) { $decompile = (Resolve-Path -LiteralPath $c).Path; break } }
if (-not $decompile) {
    Add-Part 'decompile' 'SKIP' "no decompile found (tried: $($candidates -join '; ')); set VT2_DECOMPILE_ROOT"
    foreach ($n in 'hooks', 'icons', 'self-tests', 'integration', 'lua') { Add-Part $n 'SKIP' 'no decompile' }
    Write-Summary
    exit 0
}
$head = (& git -C $decompile rev-parse --short HEAD 2>$null)
$subject = (& git -C $decompile log -1 --format=%s 2>$null)
Add-Part 'decompile' 'OK' "$decompile at $(if ($head) { $head } else { 'not a git checkout' })$(if ($subject) { ": $subject" })"

# ---------- Python 3.9+ ----------
$py = $null; $pyPrefix = @()
$tries = if ($Python) { ,@($Python, @()) } else { @(@('py', @('-3')), @('python3', @()), @('python', @())) }
foreach ($t in $tries) {
    $cmd = Get-Command -Name $t[0] -ErrorAction SilentlyContinue
    if (-not $cmd) { continue }
    & $cmd.Source @($t[1]) -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 3)' 2>$null
    if ($LASTEXITCODE -eq 0) { $py = $cmd.Source; $pyPrefix = @($t[1]); break }
}
function Invoke-PatchScript([string]$Script, [string[]]$Arguments) {
    $out = & $py @pyPrefix -I (Join-Path $repoRoot "qa\patchday\$Script") --decompile $decompile --repo $repoRoot @Arguments 2>&1
    [pscustomobject]@{ Code = $LASTEXITCODE; Lines = @($out | ForEach-Object { "$_" }) }
}

if (-not $py) {
    foreach ($n in 'hooks', 'icons', 'self-tests') { Add-Part $n 'FAIL' 'Python 3.9+ not found (tried py -3, python3, python)' }
}
else {
    $hooks = Invoke-PatchScript 'hook_targets.py' @()
    $hookLine = @($hooks.Lines | Where-Object { $_ -match '^hook targets: ' })[-1]
    foreach ($l in @($hooks.Lines | Where-Object { $_ -match '^UNRESOLVED ' })) { Write-Host "  $l" }
    Add-Part 'hooks' $(if ($hooks.Code -eq 0) { 'OK' } else { 'FAIL' }) $(if ($hookLine) { $hookLine } else { "exit $($hooks.Code): $($hooks.Lines -join ' ')" })

    $icons = Invoke-PatchScript 'icon_atlas.py' @()
    $iconLine = @($icons.Lines | Where-Object { $_ -match '^icon names: ' })[-1]
    foreach ($l in @($icons.Lines | Where-Object { $_ -match '^MISSING-IN-ATLAS ' })) { Write-Host "  $l" }
    Add-Part 'icons' $(if ($icons.Code -eq 0) { 'OK' } else { 'FAIL' }) $(if ($iconLine) { $iconLine } else { "exit $($icons.Code): $($icons.Lines -join ' ')" })

    $st1 = Invoke-PatchScript 'hook_targets.py' @('--self-test')
    $st2 = Invoke-PatchScript 'icon_atlas.py' @('--self-test')
    Add-Part 'self-tests' $(if ($st1.Code -eq 0 -and $st2.Code -eq 0) { 'OK' } else { 'FAIL' }) "planted hook: $(@($st1.Lines)[-1]) | planted icon: $(@($st2.Lines)[-1])"
}

$integration = Join-Path $repoRoot 'qa\check_integration.ps1'
if (Test-Path -LiteralPath $integration) {
    & pwsh -NoProfile -NonInteractive -File $integration 2>&1 | Select-Object -Last 3 | ForEach-Object { Write-Host "  $_" }
    Add-Part 'integration' $(if ($LASTEXITCODE -eq 0) { 'OK' } else { 'FAIL' }) "qa/check_integration.ps1 exit $LASTEXITCODE"
}
else { Add-Part 'integration' 'SKIP' 'qa/check_integration.ps1 not in this checkout yet (WP-T-03)' }

if ($SkipLua) { Add-Part 'lua' 'SKIP' '-SkipLua' }
else {
    $luaOut = & pwsh -NoProfile -NonInteractive -File (Join-Path $repoRoot 'qa\check_lua_unit_tests.ps1') 2>&1
    $luaCode = $LASTEXITCODE
    $luaLine = @($luaOut | ForEach-Object { "$_" } | Where-Object { $_ -match '\[lua_unit_tests\]' })[-1]
    Add-Part 'lua' $(if ($luaCode -eq 0) { 'OK' } else { 'FAIL' }) $(if ($luaLine) { $luaLine } else { "qa/check_lua_unit_tests.ps1 exit $luaCode" })
}

Write-Summary
if (@($results | Where-Object { $_.Status -eq 'FAIL' }).Count) { exit 2 }
exit 0
