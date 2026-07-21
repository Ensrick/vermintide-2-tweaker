# check_native_resource_safety.ps1
#
# Native Stingray resource calls can terminate below Lua. A pcall is not a
# safety boundary for missing particles/materials, dead renderers, or invalid
# package lifetime. Any NEW call site therefore needs an explicit, searchable
# source annotation tied to an offline regression check:
#
#   -- resource-safety: cim_947_addaioth_context_gate
#   World.create_particles(...)
#
# The token must also occur somewhere under qa/. This is intentionally a diff
# gate: the existing source census remains tracked by issues #282/#749, while
# every new or moved native boundary is prevented from silently expanding it.
#
# Exit 0: clean / indeterminate. Exit 2: uncovered risky call or self-test fail.

[CmdletBinding()]
param(
    [string]$Range = 'HEAD~1..HEAD',
    [switch]$Staged,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

$riskPatterns = [ordered]@{
    particles = [regex]'\b(?:World|ScriptWorld)\.(?:create_particles|create_particles_linked)\s*\('
    gui       = [regex]'\bWorld\.create_(?:screen|world)_gui\s*\('
    texture   = [regex]'\b(?:Material\.set_texture|Unit\.set_texture_for_materials)\s*\('
    package   = [regex]'\bManagers\.package:(?:load|unload)\s*\('
}
$markerPattern = [regex]'--\s*resource-safety\s*:\s*([A-Za-z0-9_.#:-]+)'

function Test-ModLuaPath {
    param([string]$Path)
    $p = $Path.Replace('\', '/')
    if ($p -notmatch '\.lua$' -or $p -notmatch '/scripts/mods/') { return $false }
    if ($p -match '(^|/)tweaker/scripts/' -or $p -match '(^|/)_archive/') { return $false }
    if ($p -match '(^|/)bundleV2/' -or $p -match '(^|/)_test_fixtures/') { return $false }
    return $true
}

function Parse-NativeResourceDiff {
    param([string]$DiffText)

    $records = @{}
    $current = $null
    foreach ($line in ($DiffText -split "`r?`n")) {
        if ($line.StartsWith('+++ ')) {
            $path = $line.Substring(4).Trim() -replace '^b/', ''
            if ($path -ne '/dev/null' -and (Test-ModLuaPath $path)) {
                if (-not $records.ContainsKey($path)) {
                    $records[$path] = [pscustomobject]@{
                        File = $path
                        Calls = [System.Collections.Generic.List[object]]::new()
                        Markers = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                    }
                }
                $current = $records[$path]
            } else {
                $current = $null
            }
            continue
        }
        if ($null -eq $current -or -not $line.StartsWith('+') -or $line.StartsWith('+++')) { continue }

        $added = $line.Substring(1)
        $trimmed = $added.TrimStart()
        $marker = $markerPattern.Match($added)
        if ($marker.Success) { $null = $current.Markers.Add($marker.Groups[1].Value) }
        if ($trimmed.StartsWith('--')) { continue }

        foreach ($kind in $riskPatterns.Keys) {
            if ($riskPatterns[$kind].IsMatch($added)) {
                $current.Calls.Add([pscustomobject]@{ Kind = $kind; Text = $added.Trim() })
            }
        }
    }
    return @($records.Values)
}

function Get-NativeResourceFindings {
    param([object[]]$Records, [string]$QaCorpus)

    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $Records) {
        if ($record.Calls.Count -eq 0) { continue }
        $markers = @($record.Markers)
        if ($markers.Count -eq 0) {
            $findings.Add([pscustomobject]@{
                File = $record.File; Reason = 'missing source annotation'; Missing = @(); Calls = @($record.Calls)
            })
            continue
        }

        $missing = @($markers | Where-Object {
            $escaped = [regex]::Escape($_)
            -not [regex]::IsMatch(
                $QaCorpus,
                "(?<![A-Za-z0-9_.#:-])$escaped(?![A-Za-z0-9_.#:-])",
                [Text.RegularExpressions.RegexOptions]::CultureInvariant
            )
        })
        if ($missing.Count -gt 0) {
            $findings.Add([pscustomobject]@{
                File = $record.File; Reason = 'annotation has no qa/ evidence'; Missing = $missing; Calls = @($record.Calls)
            })
        }
    }
    return @($findings)
}

function Invoke-GitText {
    param([string[]]$GitArgs)
    try {
        $out = & git @GitArgs 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return ($out -join "`n")
    } catch { return $null }
}

function Get-QaCorpus {
    param([string]$RepoRoot)
    $qa = Join-Path $RepoRoot 'qa'
    if (-not (Test-Path -LiteralPath $qa -PathType Container)) { return '' }
    $parts = [System.Collections.Generic.List[string]]::new()
    Get-ChildItem -LiteralPath $qa -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.lua', '.ps1', '.psd1', '.md') } |
        ForEach-Object {
            try { $parts.Add([IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8)) } catch { }
        }
    return ($parts -join "`n")
}

function Invoke-SelfTest {
    $diff = @'
diff --git a/mod_a/scripts/mods/mod_a/a.lua b/mod_a/scripts/mods/mod_a/a.lua
--- a/mod_a/scripts/mods/mod_a/a.lua
+++ b/mod_a/scripts/mods/mod_a/a.lua
@@ -1,0 +2,1 @@
+World.create_particles(world, effect, position)
diff --git a/mod_b/scripts/mods/mod_b/b.lua b/mod_b/scripts/mods/mod_b/b.lua
--- a/mod_b/scripts/mods/mod_b/b.lua
+++ b/mod_b/scripts/mods/mod_b/b.lua
@@ -1,0 +2,2 @@
+-- resource-safety: mod_b_particle_residency
+ScriptWorld.create_particles_linked(world, effect, unit, 0)
diff --git a/mod_c/scripts/mods/mod_c/c.lua b/mod_c/scripts/mods/mod_c/c.lua
--- a/mod_c/scripts/mods/mod_c/c.lua
+++ b/mod_c/scripts/mods/mod_c/c.lua
@@ -1,0 +2,2 @@
+-- resource-safety: mod_c_missing_test
+Managers.package:load(path, ref)
diff --git a/mod_d/scripts/mods/mod_d/d.lua b/mod_d/scripts/mods/mod_d/d.lua
--- a/mod_d/scripts/mods/mod_d/d.lua
+++ b/mod_d/scripts/mods/mod_d/d.lua
@@ -1,0 +2,4 @@
+-- resource-safety: mod_d_gui_texture_guard
+World.create_screen_gui(world, "material", material)
+Material.set_texture(handle, slot, texture)
+Unit.set_texture_for_materials(unit, slot, texture)
diff --git a/qa/lua/tests/fixture.lua b/qa/lua/tests/fixture.lua
--- a/qa/lua/tests/fixture.lua
+++ b/qa/lua/tests/fixture.lua
@@ -1,0 +2,1 @@
+-- ignored by source parser
'@
    $records = Parse-NativeResourceDiff $diff
    # The suffix entry proves that evidence matching is token-exact rather than
    # accepting a longer identifier which merely contains the annotation.
    $corpus = 'mod_b_particle_residency mod_c_missing_test_suffix mod_d_gui_texture_guard'
    $findings = Get-NativeResourceFindings $records $corpus
    $byFile = @($findings.File | Sort-Object)
    $d = @($records | Where-Object File -like 'mod_d/*')[0]

    $checks = @(
        @{ Name = 'four mod source records parsed'; Pass = ($records.Count -eq 4) }
        @{ Name = 'unannotated particle call fails'; Pass = ($byFile -contains 'mod_a/scripts/mods/mod_a/a.lua') }
        @{ Name = 'annotated and covered particle call passes'; Pass = ($byFile -notcontains 'mod_b/scripts/mods/mod_b/b.lua') }
        @{ Name = 'annotation without exact qa token evidence fails'; Pass = ($byFile -contains 'mod_c/scripts/mods/mod_c/c.lua') }
        @{ Name = 'one marker covers the three guarded native calls'; Pass = ($byFile -notcontains 'mod_d/scripts/mods/mod_d/d.lua' -and $d.Calls.Count -eq 3) }
        @{ Name = 'qa fixture is not parsed as production source'; Pass = (-not ($records.File -like 'qa/*')) }
    )
    $ok = $true
    foreach ($check in $checks) {
        if (-not $check.Pass) { $ok = $false }
        if (-not $Quiet) {
            $status = if ($check.Pass) { 'PASS' } else { 'FAIL' }
            Write-Host ("  [{0}] {1}" -f $status, $check.Name)
        }
    }
    if ($ok) { return 0 }
    return 2
}

Write-Host '=== check_native_resource_safety ===' -ForegroundColor Cyan
if ($SelfTest) { exit (Invoke-SelfTest) }

$repoRoot = Invoke-GitText @('rev-parse', '--show-toplevel')
if (-not $repoRoot) {
    if (-not $Quiet) { Write-Host '[check_native_resource_safety] not a git worktree; skipping.' -ForegroundColor DarkGray }
    exit 0
}
$repoRoot = $repoRoot.Trim()

if ($Staged) {
    $diffArgs = @('diff', '--cached', '-U0', '--no-color')
    $source = 'staged diff'
} elseif ($env:GITHUB_BASE_REF -and -not $PSBoundParameters.ContainsKey('Range')) {
    $diffArgs = @('diff', '-U0', '--no-color', "origin/$($env:GITHUB_BASE_REF)...HEAD")
    $source = "origin/$($env:GITHUB_BASE_REF)...HEAD"
} else {
    $diffArgs = @('diff', '-U0', '--no-color', $Range)
    $source = $Range
}

$diffText = Invoke-GitText $diffArgs
if ($null -eq $diffText) {
    if (-not $Quiet) { Write-Host "[check_native_resource_safety] cannot resolve $source; skipping." -ForegroundColor DarkGray }
    exit 0
}

$records = Parse-NativeResourceDiff $diffText
$risky = @($records | Where-Object { $_.Calls.Count -gt 0 })
if ($risky.Count -eq 0) {
    Write-Host "[check_native_resource_safety] OK - no new native resource boundaries in $source." -ForegroundColor Green
    exit 0
}

$findings = Get-NativeResourceFindings $records (Get-QaCorpus $repoRoot)
if ($findings.Count -eq 0) {
    Write-Host "[check_native_resource_safety] OK - $($risky.Count) changed source file(s) carry linked resource-safety evidence." -ForegroundColor Green
    exit 0
}

Write-Host "[check_native_resource_safety] FAIL - $($findings.Count) native resource boundary file(s) lack explicit regression evidence." -ForegroundColor Red
Write-Host 'Add `-- resource-safety: <stable_test_token>` beside the boundary and use that exact token in qa/.' -ForegroundColor Yellow
foreach ($finding in $findings) {
    Write-Host ("  ! {0}: {1}" -f $finding.File, $finding.Reason) -ForegroundColor Red
    if ($finding.Missing.Count -gt 0) { Write-Host ("      missing qa token(s): {0}" -f ($finding.Missing -join ', ')) -ForegroundColor Yellow }
    foreach ($call in $finding.Calls) { Write-Host ("      [{0}] {1}" -f $call.Kind, $call.Text) -ForegroundColor DarkYellow }
}
exit 2
