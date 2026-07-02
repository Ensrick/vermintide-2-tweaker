# check_cross_mod_deps.ps1 — enforce the standalone invariant (MOD_DEPENDENCIES.md).
#
# Every mod must LOAD + FUNCTION standalone; cross-mod features are optional and
# must nil-guard before any dereference. This check FAILS on any UNGATED inline
# cross-mod dereference:
#     get_mod("OtherMod").field        get_mod("OtherMod"):method()
# These crash when OtherMod is absent. Safe patterns (NOT flagged):
#     local x = get_mod("X"); if x then x.field end     (captured + nil-checked)
#     (get_mod("X") or {}):method()                      (or-guarded)
# Self-references (a file dereferencing get_mod of its OWN mod id) are skipped —
# the mod is always present in its own files. Suppress a verified-safe line with a
# trailing  -- cross-mod-ok  comment.
#
# Exit 0 = clean, 2 = violation(s). Wired into run_all.ps1.

param([switch]$Quiet)

$here = $PSScriptRoot
$repoRoot = Split-Path $here -Parent
$skip = @('_archive', 'bundleV2', '.temp', '.git', 'test_fixtures', 'node_modules', 'tools\luacheck')

$derefPattern = 'get_mod\(\s*["'']([A-Za-z0-9_\-]+)["'']\s*\)\s*[\.:]\w'
$ownPattern   = 'get_mod\(\s*["'']([A-Za-z0-9_\-]+)["'']\s*\)'

$violations = @()
Get-ChildItem -Path $repoRoot -Recurse -Filter *.lua -File | ForEach-Object {
    $f = $_
    $rel = $f.FullName.Substring($repoRoot.Length + 1)
    foreach ($s in $skip) { if ($rel -like "*$s*") { return } }
    $lines = [System.IO.File]::ReadAllLines($f.FullName)

    # The file's OWN mod id = first get_mod("...") it contains (the header
    # `local mod = get_mod("id")`). Chained derefs of this id are self-references.
    $ownId = $null
    foreach ($line in $lines) {
        $m = [regex]::Match($line, $ownPattern)
        if ($m.Success) { $ownId = $m.Groups[1].Value; break }
    }

    $n = 0
    foreach ($line in $lines) {
        $n++
        $trim = $line.TrimStart()
        if ($trim.StartsWith('--')) { continue }       # comment line
        if ($line -match 'cross-mod-ok') { continue }   # explicit suppression
        $m = [regex]::Match($line, $derefPattern)
        if ($m.Success) {
            $id = $m.Groups[1].Value
            if ($id -eq $ownId) { continue }            # self-reference (always resident)
            $violations += [pscustomobject]@{ File = $rel; Line = $n; Id = $id; Text = $trim }
        }
    }
}

if ($violations.Count -eq 0) {
    if (-not $Quiet) { Write-Host "[check_cross_mod_deps] OK -- no ungated inline cross-mod derefs." -ForegroundColor Green }
    exit 0
}

Write-Host "[check_cross_mod_deps] FAIL -- $($violations.Count) ungated inline cross-mod deref(s):" -ForegroundColor Red
foreach ($v in $violations) {
    Write-Host ("  {0}:{1}  (get_mod `"{2}`")  {3}" -f $v.File, $v.Line, $v.Id, $v.Text) -ForegroundColor Yellow
}
Write-Host "Fix: capture + nil-check  ->  local x = get_mod('X'); if x then x.field end" -ForegroundColor DarkYellow
Write-Host "  or wrap  ->  (get_mod('X') or {}):method()" -ForegroundColor DarkYellow
Write-Host "  or, if verified-safe, append  -- cross-mod-ok  to the line." -ForegroundColor DarkYellow
Write-Host "See MOD_DEPENDENCIES.md (the standalone invariant)." -ForegroundColor DarkYellow
exit 2
