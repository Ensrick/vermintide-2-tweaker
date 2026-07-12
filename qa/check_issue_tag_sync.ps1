# check_issue_tag_sync.ps1 - loc-tag <-> GitHub-label CROSS-SURFACE sync scan
# (issue #326, part 2).
#
# Doctrine: LOCALIZATION_STANDARD.md section 13.4 ("[Issue N] must reference an
# OPEN issue ... a tag naming a closed issue is stale and must be corrected")
# + PROJECT_STANDARDS.md section 11 ("Dev localization tags move with the
# issue"). The dev option-title tags and the GitHub status labels describe the
# SAME state on two surfaces; this check asserts they agree. It complements
# qa/check_issue_status_labels.ps1, which only covers the TOP CHANGELOG entry
# of each mod - this is the recurring whole-surface guard.
#
# This is a WARNING-ONLY, NON-BLOCKING advisory scan (wired into run_all.ps1
# under -Policy 'Advisory', exactly like check_loc_tags.ps1). It NEVER fails
# the gate. It reports four things:
#
#   (a) STALE TAG - a loc `[Issue N]` where N is a CLOSED or NON-EXISTENT
#       issue (section 13.4: correct the tag in the same pass as the close).
#
#   (b) UNPAIRED - a `[verify-fix]` or `[diag]` tag with NO `[Issue N]` in the
#       same leading tag run. Section 13.2: `[verify-fix]` co-occurs with the
#       `[Issue N]` of the issue being verified; without one it cannot be
#       cross-checked against any GitHub label.
#
#   (c) LABEL MISSING - a `[verify-fix]` / `[diag]` tag paired with
#       `[Issue N...]`, but NONE of the referenced OPEN issues carries the
#       matching GitHub label (`verify-fix` / `diagnostics-armed`). The label
#       was forgotten when the fix/probe shipped (or the tag is wrong).
#       With multiple numbers in one `[Issue ...]` tag, AT LEAST ONE carrying
#       the label counts as in-sync (deliberately low false-positive).
#
#   (d) TAG MISSING (the vice-versa direction) - an OPEN issue carries
#       `verify-fix` / `diagnostics-armed` but no dev option title pairs the
#       matching `[verify-fix]` / `[diag]` tag with that issue's `[Issue N]`.
#       CAVEAT: this is LEGITIMATE when the shipped fix has no menu surface to
#       hang a tag on (crash fixes, internal plumbing - section 13.3/13.8
#       exemptions). Issues labeled `tooling` are exempted outright (repo
#       tooling has no loc surface at all). Review once and dismiss; that is
#       what an advisory check is for. Because most hits ARE legitimate, this
#       direction is reported COMPACTLY (one line per status label with the
#       issue numbers inline), unlike (a)-(c) which get a line per finding.
#
# HEURISTICS (documented so future edits stay conservative):
#
#   * Same single-literal loc-entry parsing as check_loc_tags.ps1 (forms
#     `key = { en = "V" }` / `key = en("V")` / `loc.key = { en = "V" }` plus
#     the multi-line table form). Dynamic/concatenated strings (wt's runtime
#     tag emitter, ct_dev's post-process loop) are NOT captured - by design.
#
#   * Only the LEADING run of `[...]` bracket groups is read; an
#     uppercase-leading display prefix (`[CW]`, `[Big Rebalance]`) ends the
#     run. Unknown-vocab tag-like groups continue the run but are not
#     harvested here (they are check_loc_tags.ps1's finding, not ours).
#
#   * STABLE mod dirs (the five unsuffixed `_dev` siblings) are skipped:
#     any tag there is a promotion LEAK, already flagged by check_loc_tags;
#     sync-checking a leak would double-report it.
#
#   * Issue metadata comes from ONE `gh issue list --state all` call (fast,
#     no per-issue round-trips). A referenced number absent from that page is
#     re-checked with a single `gh issue view` before being called
#     non-existent (guards the --limit page size and PR-numbered typos).
#
# OFFLINE / UNAUTHENTICATED: if `gh` is not installed or not authenticated,
# the check prints a notice and exits 0. It NEVER fails when it cannot reach
# GitHub.
#
# Exit codes:
#   0 - clean (all surfaces in sync), OR gh unavailable (never fail offline)
#   1 - one or more advisory WARNINGS - NEVER blocks (Advisory in run_all).
#   2 - hard error (a file failed to read, or -SelfTest regression).
#
# Self-test: pass `-SelfTest` to exercise the pure (no-network) logic - loc
# parsing, tag-run harvesting, and the sync decision matrix against synthetic
# issue metadata. Exit 0 = wired correctly; exit 2 = regression.

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path $RepoRoot).Path
$GhRepo   = 'Ensrick/vermintide-2-tweaker'

# ---- tag <-> GitHub-label pairs under sync enforcement ----
# Label       : display name for messages.
# TagLabels   : labels that SATISFY the tag->label direction (c). A [verify-fix]
#               loc tag is satisfied by verify-fix, verify-fix-coop (2+ testers,
#               user rule 2026-07-11), or Fixed (user-verified; tag is
#               transitional until the post-fix pass retags to [working]).
# ExpectLabels: labels that DEMAND a loc tag in the label->tag direction (d).
#               Fixed is deliberately absent - a Fixed issue's option title
#               should already carry [working]/[untested], not [verify-fix].
$SyncPairs = @(
    @{ Tag = 'verify-fix'; Label = 'verify-fix';        TagLabels = @('verify-fix', 'verify-fix-coop', 'Fixed'); ExpectLabels = @('verify-fix', 'verify-fix-coop'); FlagProp = 'HasVerifyFix' },
    @{ Tag = 'diag';       Label = 'diagnostics-armed'; TagLabels = @('diagnostics-armed');                      ExpectLabels = @('diagnostics-armed');              FlagProp = 'HasDiag' }
)
# Issues with this label have no loc surface -> exempt from direction (d).
$ViceVersaExemptLabels = @('tooling')

# ---- sanctioned non-Issue tags (section 13.1 + 13.8) that CONTINUE a tag run ----
$KnownExactTags = @('untested', 'working', 'diag', 'crash', 'verify-fix', 'needs animations', 'needs offsets')
$KnownExactSet = @{}
foreach ($t in $KnownExactTags) { $KnownExactSet[$t] = $true }

# ---- stable mod dirs (section 13.5) - skipped (their tags are LEAKS) ----
$StableModDirs = @('chaos_wastes_tweaker', 'crafting_in_modded', 'general_tweaker', 'gui_tweaker', 'verminious_dreams_lighting')
$StableSet = @{}
foreach ($d in $StableModDirs) { $StableSet[$d] = $true }

# ---- per-line loc-entry regexes (mirrors check_loc_tags.ps1) ----
$rxFormA = [regex]'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{\s*en\s*=\s*"((?:[^"\\]|\\.)*)"'
$rxFormB = [regex]'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*en\s*\(\s*"((?:[^"\\]|\\.)*)"\s*\)'
$rxFormC = [regex]'^\s*loc\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{\s*en\s*=\s*"((?:[^"\\]|\\.)*)"'
$rxKeyOpen    = [regex]'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{\s*(--.*)?$'
$rxLocKeyOpen = [regex]'^\s*loc\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{\s*(--.*)?$'
$rxBareEn     = [regex]'^\s*en\s*=\s*"((?:[^"\\]|\\.)*)"'

# Sanctioned [Issue ...] format (section 13.2) + the tag-like shapes that keep
# a run going without being harvested (check_loc_tags flags those as vocab).
$rxIssueKnown       = [regex]'^Issue \d+(\s*[,&]\s*\d+)*$'
$rxNeedsAnimVariant = [regex]'^needs animations(\s.*)?$'
$rxLowerTag         = [regex]'^[a-z][a-z0-9 \-]*$'
$rxIssueLike        = [regex]'^[Ii]ssue\b'
$rxDigits           = [regex]'\d+'

function Read-FileUtf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

# Parse the LEADING run of bracket groups from a value string into the sync
# facts we need: issue numbers + verify-fix/diag presence.
# Returns @{ IssueNums = @(int...); HasVerifyFix = bool; HasDiag = bool }.
function Get-TagRunFacts([string]$s) {
    $nums = @()
    $hasVf = $false
    $hasDiag = $false
    $i = 0
    $n = $s.Length
    while ($i -lt $n) {
        while ($i -lt $n -and $s[$i] -eq ' ') { $i++ }
        if ($i -ge $n -or $s[$i] -ne '[') { break }
        $close = $s.IndexOf(']', $i)
        if ($close -lt 0) { break }
        $inner = $s.Substring($i + 1, $close - $i - 1).Trim()
        if ($rxIssueKnown.IsMatch($inner)) {
            foreach ($m in $rxDigits.Matches($inner)) { $nums += [int]$m.Value }
        }
        elseif ($inner -eq 'verify-fix') { $hasVf = $true }
        elseif ($inner -eq 'diag')       { $hasDiag = $true }
        elseif ($KnownExactSet.ContainsKey($inner) -or $rxNeedsAnimVariant.IsMatch($inner)) {
            # other sanctioned tag - continue the run
        }
        elseif ($rxLowerTag.IsMatch($inner) -or $rxIssueLike.IsMatch($inner)) {
            # tag-like unknown vocab - check_loc_tags' finding; run continues
        }
        else {
            break   # NOT-TAG: display name begins here
        }
        $i = $close + 1
    }
    return @{ IssueNums = @($nums | Sort-Object -Unique); HasVerifyFix = $hasVf; HasDiag = $hasDiag }
}

# Scan one loc text -> rows @{ Line; Key; IssueNums; HasVerifyFix; HasDiag }
# (only rows that carry at least one sync-relevant fact).
function Scan-Text {
    param([string]$Text)
    $rows = @()
    $lines = $Text -split "`r?`n"
    $pendingKey = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $key = $null; $val = $null

        $m = $rxFormA.Match($line)
        if (-not $m.Success) { $m = $rxFormB.Match($line) }
        if (-not $m.Success) { $m = $rxFormC.Match($line) }
        if ($m.Success) {
            $key = $m.Groups[1].Value
            $val = $m.Groups[2].Value
            $pendingKey = $null
        } else {
            $ko = $rxKeyOpen.Match($line)
            if (-not $ko.Success) { $ko = $rxLocKeyOpen.Match($line) }
            if ($ko.Success) { $pendingKey = $ko.Groups[1].Value; continue }
            $be = $rxBareEn.Match($line)
            if ($be.Success -and $pendingKey) {
                $key = $pendingKey
                $val = $be.Groups[1].Value
                $pendingKey = $null
            } else {
                continue
            }
        }

        if ($val -notmatch '^\s*\[') { continue }
        $facts = Get-TagRunFacts $val
        if ($facts.IssueNums.Count -eq 0 -and -not $facts.HasVerifyFix -and -not $facts.HasDiag) { continue }
        $rows += [pscustomobject]@{
            Line = $i + 1; Key = $key
            IssueNums = $facts.IssueNums; HasVerifyFix = $facts.HasVerifyFix; HasDiag = $facts.HasDiag
        }
    }
    # NOTE: plain return (no comma trick) - every call site wraps with @(),
    # and @() around a comma-returned array NESTS it (count becomes 1).
    return $rows
}

# ---- the PURE sync decision matrix (network-free; self-testable) ----
# $LocRows: rows from Scan-Text + Mod/Rel columns.
# $IssueMeta: hashtable [int]N -> @{ State = 'OPEN'|'CLOSED'; Labels = @(...) };
#             a referenced N ABSENT from the table = non-existent issue.
# Returns finding rows @{ Kind; Issue; Mod; Rel; Line; Key; Detail }.
function Get-SyncFindings {
    param([array]$LocRows, [hashtable]$IssueMeta)
    $rows = @()

    # directions (a)-(c): loc tags -> issues
    foreach ($r in $LocRows) {
        foreach ($n in $r.IssueNums) {
            if (-not $IssueMeta.ContainsKey($n)) {
                $rows += [pscustomobject]@{ Kind = 'stale'; Issue = $n; Mod = $r.Mod; Rel = $r.Rel; Line = $r.Line; Key = $r.Key
                    Detail = "[Issue $n] names a NON-EXISTENT issue (typo / PR number?)" }
            } elseif ($IssueMeta[$n].State -ne 'OPEN') {
                $rows += [pscustomobject]@{ Kind = 'stale'; Issue = $n; Mod = $r.Mod; Rel = $r.Rel; Line = $r.Line; Key = $r.Key
                    Detail = "[Issue $n] names a CLOSED issue (section 13.4: correct the tag)" }
            }
        }
        foreach ($p in $SyncPairs) {
            if (-not $r.($p.FlagProp)) { continue }
            if ($r.IssueNums.Count -eq 0) {
                $upDetail = if ($p.Tag -eq 'diag') {
                    "[diag] with no [Issue N] in the same tag run (section 13.1 says 'almost always paired' - fine for standing diagnostics; review once)"
                } else {
                    "[$($p.Tag)] with no [Issue N] in the same tag run (section 13.2 mandates the pairing)"
                }
                $rows += [pscustomobject]@{ Kind = 'unpaired'; Issue = 0; Mod = $r.Mod; Rel = $r.Rel; Line = $r.Line; Key = $r.Key
                    Detail = $upDetail }
                continue
            }
            $openRefs = @($r.IssueNums | Where-Object { $IssueMeta.ContainsKey($_) -and $IssueMeta[$_].State -eq 'OPEN' })
            if ($openRefs.Count -eq 0) { continue }   # every ref already flagged stale above
            $carrying = @($openRefs | Where-Object { $im = $IssueMeta[$_].Labels; @($p.TagLabels | Where-Object { $im -contains $_ }).Count -gt 0 })
            if ($carrying.Count -eq 0) {
                $rows += [pscustomobject]@{ Kind = 'label-missing'; Issue = $openRefs[0]; Mod = $r.Mod; Rel = $r.Rel; Line = $r.Line; Key = $r.Key
                    Detail = "[$($p.Tag)] paired with [Issue $($openRefs -join ' & ')] but none carries a '$($p.TagLabels -join "' / '")' GitHub label" }
            }
        }
    }

    # direction (d): issue labels -> loc tags (vice versa)
    foreach ($n in @($IssueMeta.Keys | Sort-Object)) {
        $meta = $IssueMeta[$n]
        if ($meta.State -ne 'OPEN') { continue }
        $exempt = @($meta.Labels | Where-Object { $ViceVersaExemptLabels -contains $_ }).Count -gt 0
        if ($exempt) { continue }
        foreach ($p in $SyncPairs) {
            $carried = @($p.ExpectLabels | Where-Object { $meta.Labels -contains $_ })
            if ($carried.Count -eq 0) { continue }
            $tagged = @($LocRows | Where-Object { $_.($p.FlagProp) -and $_.IssueNums -contains $n })
            if ($tagged.Count -eq 0) {
                $rows += [pscustomobject]@{ Kind = 'tag-missing'; Issue = $n; Mod = ''; Rel = ''; Line = 0; Key = ''; Label = $p.Label; Tag = $p.Tag
                    Detail = "open issue #$n carries '$($carried -join "' + '")' but no dev option title pairs [$($p.Tag)] with [Issue $n] (fine if the fix has no menu surface - section 13.3)" }
            }
        }
    }

    # Plain return, same reason as Scan-Text: call sites wrap with @().
    return $rows
}

# ---- file collection (mirrors check_loc_tags.ps1, minus stable dirs) ----
function Get-ScanFiles {
    param([string]$Root)
    Get-ChildItem -Path $Root -Filter "*_localization.lua" -Recurse -File -ErrorAction SilentlyContinue `
        | Where-Object {
            $p = $_.FullName
            $isUnderMod = $p -match "\\scripts\\mods\\"
            $notExcluded = $p -notlike "*\_archive\*" `
                       -and $p -notlike "*\bundleV2\*" `
                       -and $p -notlike "*\.build\*" `
                       -and $p -notlike "*\.temp\*" `
                       -and $p -notlike "*\_tmp\*" `
                       -and $p -notlike "*\.spawn_tweaks_ref\*" `
                       -and $p -notlike "*\tweaker\*" `
                       -and $p -notlike "*\weapon_tweaker_dev\*" `
                       -and $p -notlike "*\_test_fixtures\*" `
                       -and $p -notlike "*\sample_*\*" `
                       -and $p -notlike "*\Vermintide-2-Source-Code\*" `
                       -and $p -notlike "*\Darktide-Source-Code\*" `
                       -and $p -notlike "*\_*_extract\*"
            return $isUnderMod -and $notExcluded
        }
}

function Get-ModDirName([string]$filePath) {
    $dir = Split-Path $filePath -Parent
    for ($i = 0; $i -lt 3; $i++) { $dir = Split-Path $dir -Parent }
    return (Split-Path $dir -Leaf)
}

# ---- gh helpers (network) ----
function Test-GhReady {
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) { return $false }
    & gh auth status 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# One-shot fetch of every issue's state+labels. Returns hashtable or $null on
# failure. --limit 1000 comfortably covers the repo (~330 issues, 2026-07);
# the per-number Resolve-MissingIssue fallback below guards the page edge.
function Get-AllIssueMeta {
    $json = & gh issue list --repo $GhRepo --state all --limit 1000 --json number,state,labels 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) { return $null }
    try {
        $map = @{}
        foreach ($o in ($json | ConvertFrom-Json)) {
            $labels = @()
            if ($o.labels) { $labels = @($o.labels | ForEach-Object { $_.name }) }
            $map[[int]$o.number] = @{ State = $o.state; Labels = $labels }
        }
        return $map
    } catch { return $null }
}

# A referenced number absent from the list page gets ONE view before being
# declared non-existent. Adds to $Map in place when it resolves.
function Resolve-MissingIssue {
    param([hashtable]$Map, [int]$Number)
    $json = & gh issue view $Number --repo $GhRepo --json state,labels 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) { return }
    try {
        $o = $json | ConvertFrom-Json
        $labels = @()
        if ($o.labels) { $labels = @($o.labels | ForEach-Object { $_.name }) }
        $Map[$Number] = @{ State = $o.state; Labels = $labels }
    } catch { }
}

# ---- self-test (pure parsing + decision matrix, no network) ----
function Invoke-SelfTest {
    $script:__stpass = $true
    function Assert($cond, $desc) {
        $verdict = if ($cond) { 'PASS' } else { 'FAIL' }
        $colour  = if ($cond) { 'Green' } else { 'Red' }
        Write-Host ("  [{0}] {1}" -f $verdict, $desc) -ForegroundColor $colour
        if (-not $cond) { $script:__stpass = $false }
    }

    $fixture = @"
return {
    mod_name = { en = "My Mod" },
    opt_a = { en = "[verify-fix] [Issue 101] Feature A" },
    opt_b = { en = "[Issue 102 & 103] Feature B" },
    opt_c = { en = "[diag] [Issue 104] Feature C" },
    opt_d = { en = "[verify-fix] Feature D unpaired" },
    opt_e = { en = "[untested] Feature E no refs" },
    opt_f = { en = "[CW] [Issue 105] display prefix ends the run" },
    opt_g = {
        en = "[working] [Issue 106] Multi-line form G",
    },
    opt_h = en("[Issue 999] Feature H names a ghost"),
}
"@
    $rows = @(Scan-Text -Text $fixture)
    Assert ($rows.Count -eq 6) "6 sync-relevant rows parsed (a,b,c,d,g,h; e/f/mod_name skipped) - got $($rows.Count)"
    $a = $rows | Where-Object { $_.Key -eq 'opt_a' }
    Assert ($a -and $a.HasVerifyFix -and ($a.IssueNums -contains 101)) "opt_a: [verify-fix] paired with 101"
    $b = $rows | Where-Object { $_.Key -eq 'opt_b' }
    Assert ($b -and ($b.IssueNums.Count -eq 2) -and -not $b.HasVerifyFix -and -not $b.HasDiag) "opt_b: multi-number [Issue 102 & 103], no status tags"
    $d = $rows | Where-Object { $_.Key -eq 'opt_d' }
    Assert ($d -and $d.HasVerifyFix -and ($d.IssueNums.Count -eq 0)) "opt_d: unpaired [verify-fix]"
    $g = $rows | Where-Object { $_.Key -eq 'opt_g' }
    Assert ($g -and ($g.IssueNums -contains 106)) "opt_g: multi-line table form binds en to its key"
    Assert (-not ($rows | Where-Object { $_.IssueNums -contains 105 })) "opt_f: [CW] prefix ends the run; 105 NOT harvested"

    # decorate rows with Mod/Rel like the main pass does
    foreach ($r in $rows) {
        $r | Add-Member -NotePropertyName Mod -NotePropertyValue 'fixture_mod' -Force
        $r | Add-Member -NotePropertyName Rel -NotePropertyValue 'fixture.lua' -Force
    }

    $meta = @{
        101 = @{ State = 'OPEN';   Labels = @('bug', 'verify-fix') }          # in sync
        102 = @{ State = 'CLOSED'; Labels = @('bug') }                         # stale (closed)
        103 = @{ State = 'OPEN';   Labels = @('bug') }                         # plain [Issue N] - fine
        104 = @{ State = 'OPEN';   Labels = @('bug') }                         # [diag] but no diagnostics-armed
        106 = @{ State = 'OPEN';   Labels = @() }                              # [working]+[Issue N] - not ours to judge
        201 = @{ State = 'OPEN';   Labels = @('bug', 'verify-fix') }           # vice-versa: no loc tag
        202 = @{ State = 'OPEN';   Labels = @('tooling', 'verify-fix') }       # vice-versa: tooling exempt
        203 = @{ State = 'OPEN';   Labels = @('bug', 'diagnostics-armed') }    # vice-versa: no [diag] tag
        204 = @{ State = 'CLOSED'; Labels = @('bug', 'verify-fix') }           # closed - vice-versa ignores
    }                                                                          # 999 absent = non-existent

    $f = @(Get-SyncFindings -LocRows $rows -IssueMeta $meta)
    $stale        = @($f | Where-Object { $_.Kind -eq 'stale' })
    $unpaired     = @($f | Where-Object { $_.Kind -eq 'unpaired' })
    $labelMissing = @($f | Where-Object { $_.Kind -eq 'label-missing' })
    $tagMissing   = @($f | Where-Object { $_.Kind -eq 'tag-missing' })

    Assert ($stale.Count -eq 2) "2 stale tags (closed #102 + ghost #999) - got $($stale.Count)"
    Assert (($stale | Where-Object { $_.Issue -eq 102 }) -and ($stale | Where-Object { $_.Issue -eq 999 })) "stale set is exactly {102, 999}"
    Assert ($unpaired.Count -eq 1 -and $unpaired[0].Key -eq 'opt_d') "1 unpaired [verify-fix] (opt_d)"
    Assert ($labelMissing.Count -eq 1 -and $labelMissing[0].Issue -eq 104) "1 label-missing ([diag] on #104 without diagnostics-armed)"
    Assert ($tagMissing.Count -eq 2) "2 tag-missing (vice versa: #201 + #203; #202 tooling-exempt, #204 closed) - got $($tagMissing.Count)"
    Assert (($tagMissing | Where-Object { $_.Issue -eq 201 }) -and ($tagMissing | Where-Object { $_.Issue -eq 203 })) "tag-missing set is exactly {201, 203}"
    Assert (-not ($f | Where-Object { $_.Issue -eq 101 -and $_.Kind -ne 'stale' })) "in-sync #101 produces no finding"

    Write-Host ""
    if ($script:__stpass) {
        Write-Host "[check_issue_tag_sync -SelfTest] OK -- parser + sync matrix intact." -ForegroundColor Green
        return 0
    } else {
        Write-Host "[check_issue_tag_sync -SelfTest] FAILED -- logic regression." -ForegroundColor Red
        return 2
    }
}

# ---- main ----
Write-Host "=== check_issue_tag_sync ===" -ForegroundColor Cyan

if ($SelfTest) { exit (Invoke-SelfTest) }

if (-not (Test-GhReady)) {
    Write-Host "[check_issue_tag_sync] gh not installed or not authenticated - skipping (offline, non-blocking)." -ForegroundColor DarkYellow
    exit 0
}

# Pass 1: harvest sync-relevant loc rows from every non-stable mod.
$locRows = @()
$hardError = $false
foreach ($f in @(Get-ScanFiles -Root $repoRoot)) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
    $modName = Get-ModDirName $f.FullName
    if ($StableSet.ContainsKey($modName)) {
        if (-not $Quiet) { Write-Host "Skipping $modName (STABLE - tags there are leaks, check_loc_tags' finding) - $rel" -ForegroundColor DarkGray }
        continue
    }
    try {
        $rows = @(Scan-Text -Text (Read-FileUtf8 $f.FullName))
    } catch {
        Write-Host ("  X {0}: {1}" -f $rel, $_) -ForegroundColor Red
        $hardError = $true
        continue
    }
    if (-not $Quiet) { Write-Host "Scanning $modName - $rel ($($rows.Count) tagged row(s))" -ForegroundColor DarkGray }
    foreach ($r in $rows) {
        $locRows += ($r | Add-Member -NotePropertyName Mod -NotePropertyValue $modName -PassThru `
                        | Add-Member -NotePropertyName Rel -NotePropertyValue $rel -PassThru)
    }
}

if ($hardError) {
    Write-Host ""
    Write-Host "[check_issue_tag_sync] ERROR -- one or more files failed to scan." -ForegroundColor Red
    exit 2
}

# Pass 2: one-shot issue metadata + per-number fallback for absent refs.
$issueMeta = Get-AllIssueMeta
if (-not $issueMeta) {
    Write-Host "[check_issue_tag_sync] gh issue list failed - skipping (transient, non-blocking)." -ForegroundColor DarkYellow
    exit 0
}
$referenced = @($locRows | ForEach-Object { $_.IssueNums } | Sort-Object -Unique)
foreach ($n in $referenced) {
    if (-not $issueMeta.ContainsKey($n)) { Resolve-MissingIssue -Map $issueMeta -Number $n }
}

# Pass 3: decide + report.
$findings = @(Get-SyncFindings -LocRows $locRows -IssueMeta $issueMeta)

Write-Host ""
if ($findings.Count -eq 0) {
    Write-Host "[check_issue_tag_sync] OK -- loc [Issue N]/[verify-fix]/[diag] tags and GitHub status labels are in sync." -ForegroundColor Green
    exit 0
}

$stale        = @($findings | Where-Object { $_.Kind -eq 'stale' })
$unpaired     = @($findings | Where-Object { $_.Kind -eq 'unpaired' })
$labelMissing = @($findings | Where-Object { $_.Kind -eq 'label-missing' })
$tagMissing   = @($findings | Where-Object { $_.Kind -eq 'tag-missing' })

Write-Host ("[check_issue_tag_sync] WARNINGS: {0} (stale tag: {1}, unpaired: {2}, label missing: {3}, tag missing: {4}) -- advisory, non-blocking." `
    -f $findings.Count, $stale.Count, $unpaired.Count, $labelMissing.Count, $tagMissing.Count) -ForegroundColor Yellow

if ($stale.Count -gt 0) {
    Write-Host "  -- STALE TAG (loc [Issue N] names a closed/non-existent issue; section 13.4 - correct the tag):" -ForegroundColor Yellow
    foreach ($r in $stale)        { Write-Host ("  ! {0}:{1}  {2}  {3}" -f $r.Rel, $r.Line, $r.Key, $r.Detail) -ForegroundColor Yellow }
}
if ($unpaired.Count -gt 0) {
    Write-Host "  -- UNPAIRED ([verify-fix]/[diag] with no [Issue N] to sync against; section 13.2):" -ForegroundColor Yellow
    foreach ($r in $unpaired)     { Write-Host ("  ! {0}:{1}  {2}  {3}" -f $r.Rel, $r.Line, $r.Key, $r.Detail) -ForegroundColor Yellow }
}
if ($labelMissing.Count -gt 0) {
    Write-Host "  -- LABEL MISSING (loc says a fix/probe shipped; the GitHub issue does not):" -ForegroundColor Yellow
    foreach ($r in $labelMissing) { Write-Host ("  ! {0}:{1}  {2}  {3}" -f $r.Rel, $r.Line, $r.Key, $r.Detail) -ForegroundColor Yellow }
}
if ($tagMissing.Count -gt 0) {
    # Compact by design: most of these are legitimate (crash fixes / internal
    # plumbing have no menu widget to tag - section 13.3/13.8 exemptions), so a
    # line per issue would drown the actionable directions above. One line per
    # status label, issue numbers inline.
    Write-Host "  -- TAG MISSING (GitHub says a fix/probe shipped; no dev option title carries the matching tag)." -ForegroundColor Yellow
    Write-Host "     Often legitimate: no menu surface to tag (section 13.3/13.8 exemptions). Compact listing:" -ForegroundColor DarkYellow
    foreach ($p in $SyncPairs) {
        $nums = @($tagMissing | Where-Object { $_.Label -eq $p.Label } | ForEach-Object { $_.Issue } | Sort-Object -Unique)
        if ($nums.Count -gt 0) {
            Write-Host ("  ! '{0}' without a paired [{1}] loc tag -- {2} issue(s): #{3}" -f $p.Label, $p.Tag, $nums.Count, ($nums -join ', #')) -ForegroundColor Yellow
        }
    }
}
exit 1
