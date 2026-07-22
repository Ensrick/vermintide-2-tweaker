# check_hook_test_coverage.ps1 — hook / NetworkLookup diffs must ship a
# regression marker (issue #429).
#
# Rule: if a diff ADDS a `mod:hook(` / `mod:hook_safe(` line, or ADDS a
# `NetworkLookup.<x>[...] = ...` write, in a mod's lua, the change must be
# covered by a regression marker. Coverage is satisfied when ANY of:
#   1. the same diff also ADDS a `_rt_register(` line (a new regression entry), OR
#   2. the same diff carries an explicit `-- hook-test: <check_name>` comment
#      naming the covering check, OR
#   3. the mod already ships a regression suite (an `_rt_register(` exists in the
#      mod's on-disk lua) — the "mod's existing suite" clause.
#
# Because nearly every active mod already ships an `_rt_register` suite, clause 3
# means this gate fires narrowly: a mod that adds a hook / NetworkLookup write but
# has NO regression suite AND adds no marker. That is the exact gap worth
# surfacing (the singleton-hook / gated-registration invariants — CLAUDE.md
# NON-NEG #8, BUG_CLASSES § 29 — go unchecked). Statically matching a specific
# `_rt_register` to a specific hook is not possible (they register named
# source-pattern markers), so this is coverage-EXISTENCE, not per-hook proof.
#
# ADVISORY by design (wired Advisory in run_all.ps1; warn-only in pre-commit):
# it gathers signal, it does not block. `-- hook-test: <name>` is the escape.
#
# Diff source (in order):
#   -Staged                     -> `git diff --cached`   (pre-commit)
#   GITHUB_BASE_REF set (CI PR) -> `origin/<base>...HEAD` (unless -Range given)
#   otherwise                  -> `git diff <Range>`     (default HEAD~1..HEAD)
# If git is unavailable or the range can't be resolved, the check exits 0 — it
# never false-blocks on an indeterminate diff.
#
# Exit codes:
#   0 - clean / no relevant diff / indeterminate
#   1 - one or more added hooks / NetworkLookup writes lack coverage (advisory)
#   2 - self-test failure
#
# Self-test: `-SelfTest` drives synthetic diff text through the pure parser +
# decision function. Auto-discovered by qa/run_selftests.ps1.

[CmdletBinding()]
param(
    [string]$Range = "HEAD~1..HEAD",
    [switch]$Staged,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

# ---- pre-compiled regexes ----
$rxAddedHook    = [regex]'\bmod:hook(_safe)?\s*\('
$rxAddedNLWrite = [regex]'\bNetworkLookup\.\w+\s*\[[^\]]*\]\s*=(?!=)'
$rxRtRegister   = [regex]'\b_rt_register\s*\('
$rxHookTest     = [regex]'--\s*hook-test\s*:'

# A mod lua path: under a `<mod>/scripts/mods/...` subtree, `.lua`, not legacy /
# archive / build / reference.
function Test-ModLuaPath {
    param([string]$Path)
    $p = $Path.Replace('\','/')
    if ($p -notmatch '\.lua$') { return $false }
    if ($p -notmatch '/scripts/mods/') { return $false }
    if ($p -match '(^|/)tweaker/scripts/') { return $false }   # legacy SDK mod
    if ($p -match '(^|/)_archive/') { return $false }
    if ($p -match '(^|/)bundleV2/') { return $false }
    if ($p -match '(^|/)_test_fixtures/') { return $false }
    if ($p -match '_extract/') { return $false }
    if ($p -match '(^|/)Vermintide-2-Source-Code/' -or $p -match '(^|/)Darktide-Source-Code/') { return $false }
    return $true
}

function Get-ModFromPath {
    param([string]$Path)
    $p = $Path.Replace('\','/')
    return ($p -split '/')[0]
}

# Parse `git diff -U0` output into per-file records. PURE (self-testable): given
# the diff text, returns an array of records for the mod-lua files it touches.
#   @{ File; Mod; Hooks=@(<added lines>); NL=@(<added lines>); RtAdd; HookTest }
function Parse-Diff {
    param([string]$DiffText)
    $records = @{}
    $cur = $null
    foreach ($line in ($DiffText -split "`r?`n")) {
        if ($line.StartsWith('+++ ')) {
            $path = $line.Substring(4).Trim()
            if ($path -eq '/dev/null') { $cur = $null; continue }
            $path = $path -replace '^b/', ''
            if (Test-ModLuaPath $path) {
                if (-not $records.ContainsKey($path)) {
                    $records[$path] = [pscustomobject]@{
                        File = $path; Mod = (Get-ModFromPath $path)
                        Hooks = @(); NL = @(); RtAdd = $false; HookTest = $false
                    }
                }
                $cur = $records[$path]
            } else {
                $cur = $null
            }
            continue
        }
        if ($null -eq $cur) { continue }
        # added content only (skip the +++ header, handled above)
        if ($line.Length -ge 1 -and $line[0] -eq '+' -and -not $line.StartsWith('+++')) {
            $added = $line.Substring(1)
            if ($rxAddedHook.IsMatch($added))    { $cur.Hooks += $added.Trim() }
            if ($rxAddedNLWrite.IsMatch($added)) { $cur.NL    += $added.Trim() }
            if ($rxRtRegister.IsMatch($added))   { $cur.RtAdd = $true }
            if ($rxHookTest.IsMatch($added))     { $cur.HookTest = $true }
        }
    }
    return @($records.Values)
}

# Decide which records lack coverage. PURE. $SuiteMap: mod -> bool (mod already
# ships an _rt_register suite). A record needs coverage iff it added a hook or an
# NL write. It's covered iff RtAdd OR HookTest OR SuiteMap[mod].
function Get-CoverageFindings {
    param([object[]]$Records, [hashtable]$SuiteMap)
    $findings = @()
    foreach ($r in $Records) {
        $needs = ($r.Hooks.Count -gt 0) -or ($r.NL.Count -gt 0)
        if (-not $needs) { continue }
        $covered = $r.RtAdd -or $r.HookTest -or ($SuiteMap.ContainsKey($r.Mod) -and $SuiteMap[$r.Mod])
        if (-not $covered) { $findings += $r }
    }
    return @($findings)
}

# ---- git plumbing ----
function Invoke-GitText {
    param([string[]]$GitArgs)
    try {
        $out = & git @GitArgs 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return ($out -join "`n")
    } catch { return $null }
}

function Test-ModHasSuite {
    param([string]$Mod, [string]$RepoRoot)
    $modDir = Join-Path $RepoRoot $Mod
    if (-not (Test-Path $modDir)) { return $false }
    $files = Get-ChildItem -Path $modDir -Filter "*.lua" -Recurse -File -ErrorAction SilentlyContinue `
        | Where-Object { $_.FullName -replace '\\','/' -match '/scripts/mods/' }
    foreach ($f in $files) {
        try {
            $t = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
            if ($rxRtRegister.IsMatch($t)) { return $true }
        } catch { }
    }
    return $false
}

# ---- self-test ----
function Invoke-SelfTest {
    Write-Host "[check_hook_test_coverage] SELF-TEST" -ForegroundColor Cyan
    # Synthetic -U0 diff: 6 files exercising each branch.
    $diff = @'
diff --git a/mod_a/scripts/mods/mod_a/mod_a.lua b/mod_a/scripts/mods/mod_a/mod_a.lua
--- a/mod_a/scripts/mods/mod_a/mod_a.lua
+++ b/mod_a/scripts/mods/mod_a/mod_a.lua
@@ -10,0 +11,1 @@
+mod:hook("SomeClass", "method", function(func, self) return func(self) end)
diff --git a/mod_b/scripts/mods/mod_b/mod_b.lua b/mod_b/scripts/mods/mod_b/mod_b.lua
--- a/mod_b/scripts/mods/mod_b/mod_b.lua
+++ b/mod_b/scripts/mods/mod_b/mod_b.lua
@@ -20,0 +21,2 @@
+mod:hook_safe("OtherClass", "on_x", function(self) end)
+    _rt_register("mod_b_on_x_singleton", function() return true end)
diff --git a/mod_c/scripts/mods/mod_c/mod_c.lua b/mod_c/scripts/mods/mod_c/mod_c.lua
--- a/mod_c/scripts/mods/mod_c/mod_c.lua
+++ b/mod_c/scripts/mods/mod_c/mod_c.lua
@@ -30,0 +31,1 @@
+mod:hook("Cls", "m", function() end)  -- hook-test: check_mod_c_regression
diff --git a/mod_d/scripts/mods/mod_d/mod_d.lua b/mod_d/scripts/mods/mod_d/mod_d.lua
--- a/mod_d/scripts/mods/mod_d/mod_d.lua
+++ b/mod_d/scripts/mods/mod_d/mod_d.lua
@@ -40,0 +41,1 @@
+mod:hook("D", "m", function() end)
diff --git a/mod_e/scripts/mods/mod_e/mod_e.lua b/mod_e/scripts/mods/mod_e/mod_e.lua
--- a/mod_e/scripts/mods/mod_e/mod_e.lua
+++ b/mod_e/scripts/mods/mod_e/mod_e.lua
@@ -50,0 +51,1 @@
+    NetworkLookup.buff_templates[idx] = name
diff --git a/qa/check_x.ps1 b/qa/check_x.ps1
--- a/qa/check_x.ps1
+++ b/qa/check_x.ps1
@@ -1,0 +2,1 @@
+mod:hook("ignored", "not_a_mod_lua", function() end)
'@
    $records = Parse-Diff -DiffText $diff
    # mod_d has an existing suite; nobody else does.
    $suiteMap = @{ 'mod_d' = $true }
    $findings = Get-CoverageFindings -Records $records -SuiteMap $suiteMap
    $found = @($findings | ForEach-Object { $_.Mod } | Sort-Object)
    $expected = @('mod_a','mod_e')

    $checks = @(
        @{ Name = "5 mod-lua records parsed (qa/ .ps1 ignored)"; Pass = ($records.Count -eq 5) }
        @{ Name = "mod_a flagged (hook, no coverage, no suite)"; Pass = ($found -contains 'mod_a') }
        @{ Name = "mod_b clean (diff adds _rt_register)"; Pass = ($found -notcontains 'mod_b') }
        @{ Name = "mod_c clean (-- hook-test comment)"; Pass = ($found -notcontains 'mod_c') }
        @{ Name = "mod_d clean (existing suite)"; Pass = ($found -notcontains 'mod_d') }
        @{ Name = "mod_e flagged (NetworkLookup write, no coverage)"; Pass = ($found -contains 'mod_e') }
        @{ Name = "exactly {mod_a, mod_e} flagged"; Pass = (($found -join ',') -eq ($expected -join ',')) }
    )
    $allPass = $true
    foreach ($c in $checks) {
        $v = if ($c.Pass) { "PASS" } else { "FAIL"; }
        $col = if ($c.Pass) { "Green" } else { "Red" }
        Write-Host ("  [{0}] {1}" -f $v, $c.Name) -ForegroundColor $col
        if (-not $c.Pass) { $allPass = $false }
    }
    Write-Host ""
    if ($allPass) {
        Write-Host "[check_hook_test_coverage] SELF-TEST PASSED" -ForegroundColor Green
        return 0
    }
    Write-Host "[check_hook_test_coverage] SELF-TEST FAILED (found: $($found -join ', '))" -ForegroundColor Red
    return 2
}

# ---- main ----
Write-Host "=== check_hook_test_coverage ===" -ForegroundColor Cyan
if ($SelfTest) { exit (Invoke-SelfTest) }

$repoRoot = $null
$rr = Invoke-GitText @('rev-parse','--show-toplevel')
if ($rr) { $repoRoot = $rr.Trim() } else { $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }

# not a git work tree? indeterminate — never false-block.
$null = Invoke-GitText @('rev-parse','--is-inside-work-tree')
if ($LASTEXITCODE -ne 0) {
    if (-not $Quiet) { Write-Host "[check_hook_test_coverage] not a git work tree — skipping." -ForegroundColor DarkGray }
    exit 0
}

# choose the diff source
if ($Staged) {
    $diffArgs = @('diff','--cached','-U0','--no-color')
    $srcDesc = 'staged (git diff --cached)'
} elseif ($env:GITHUB_BASE_REF -and -not $PSBoundParameters.ContainsKey('Range')) {
    $base = $env:GITHUB_BASE_REF
    $diffArgs = @('diff','-U0','--no-color', "origin/$base...HEAD")
    $srcDesc = "CI PR (origin/$base...HEAD)"
} else {
    $diffArgs = @('diff','-U0','--no-color', $Range)
    $srcDesc = "range ($Range)"
}

$diffText = Invoke-GitText $diffArgs
if ($null -eq $diffText) {
    if (-not $Quiet) { Write-Host "[check_hook_test_coverage] could not compute diff for $srcDesc — skipping." -ForegroundColor DarkGray }
    exit 0
}

$records = Parse-Diff -DiffText $diffText
$relevant = @($records | Where-Object { $_.Hooks.Count -gt 0 -or $_.NL.Count -gt 0 })
if ($relevant.Count -eq 0) {
    Write-Host "[check_hook_test_coverage] OK — no added hooks / NetworkLookup writes in $srcDesc." -ForegroundColor Green
    exit 0
}

# build the suite map for the mods actually touched
$suiteMap = @{}
foreach ($mod in ($relevant.Mod | Sort-Object -Unique)) {
    $suiteMap[$mod] = Test-ModHasSuite -Mod $mod -RepoRoot $repoRoot
}

$findings = Get-CoverageFindings -Records $records -SuiteMap $suiteMap

Write-Host ""
if ($findings.Count -eq 0) {
    Write-Host "[check_hook_test_coverage] OK — all added hooks / NetworkLookup writes are covered ($srcDesc)." -ForegroundColor Green
    exit 0
}

Write-Host "[check_hook_test_coverage] ADVISORY: $($findings.Count) file(s) add a hook / NetworkLookup write with NO regression coverage ($srcDesc)." -ForegroundColor Yellow
Write-Host "  Add an `_rt_register(` entry for the new hook, or annotate the added line with `-- hook-test: <check_name>`." -ForegroundColor Yellow
Write-Host "  (CLAUDE.md NON-NEG #8 singleton-hook invariant / BUG_CLASSES § 29 gated-registration.)" -ForegroundColor Yellow
Write-Host ""
foreach ($r in $findings) {
    Write-Host ("  ! {0}  [mod {1}]" -f $r.File, $r.Mod) -ForegroundColor Yellow
    foreach ($h in $r.Hooks) { Write-Host ("      + hook: {0}" -f $h) -ForegroundColor DarkYellow }
    foreach ($n in $r.NL)    { Write-Host ("      + NetworkLookup write: {0}" -f $n) -ForegroundColor DarkYellow }
}
exit 1
