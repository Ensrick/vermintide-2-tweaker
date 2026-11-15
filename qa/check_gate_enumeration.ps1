# check_gate_enumeration.ps1 - gates read tracked files, not the whole disk (WP-T-06).
#
# A gate that walks the repository root with a recursive Get-ChildItem also
# reads git-ignored scratch copies of mod trees (`.temp/`, `.claude/`), so a
# dirty developer checkout fails a gate that CI passes. This check fails when a
# qa/check_*.ps1 file contains a recursive Get-ChildItem on $repoRoot, $RepoRoot
# or $root and does not call Get-QATrackedFiles (qa/worktree_state.ps1), unless
# that line carries the comment `# enumeration-ok: <reason>`.
# Exit codes: 0 pass, 2 fail. ASCII only; Windows PowerShell 5.1 and PowerShell 7.

[CmdletBinding()]
param([switch]$Quiet, [switch]$SelfTest, [string]$QaDir = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($QaDir)) { $QaDir = $PSScriptRoot }

# Built from pieces so this file's own source never matches.
$script:walkCmdlet = [regex]('(?i)\bGet-' + 'ChildItem\b')
$script:recurseFlag = [regex]'(?i)(^|\s)-Recurse\b'
$script:rootVariable = [regex]'(?i)\$(?:repoRoot|root)\b'
$script:helperCall = [regex]('\bGet-' + 'QATrackedFiles\b')
$script:okComment = [regex]('#\s*enumeration-' + 'ok:\s*\S')

# Returns one finding per unannotated root walk in a file that never calls the helper.
function Get-GateEnumerationFindings {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $findings = @()
    if ($script:helperCall.IsMatch($Text)) { return $findings }
    $number = 0
    foreach ($line in ($Text -split "`r?`n")) {
        $number++
        if (-not $script:walkCmdlet.IsMatch($line)) { continue }
        if (-not $script:recurseFlag.IsMatch($line)) { continue }
        if (-not $script:rootVariable.IsMatch($line)) { continue }
        if ($script:okComment.IsMatch($line)) { continue }
        $findings += ('{0}:{1}: recursive walk of the repository root; use Get-QATrackedFiles or add "# enumeration-ok: <reason>"' -f $Name, $number)
    }
    return $findings
}

if ($SelfTest) {
    $walk = 'Get-' + 'ChildItem -Path $repoRoot -Filter "*.lua" -Recurse -File'
    $cases = @(
        @{ Name = 'a root walk without the helper fails'; Text = "function F {`n    $walk`n}"; Expect = 1 },
        @{ Name = 'a $RepoRoot walk fails (any case)'; Text = ('Get-' + 'ChildItem -LiteralPath $RepoRoot -Recurse'); Expect = 1 },
        @{ Name = 'a $root walk fails'; Text = ('$files = @(Get-' + 'ChildItem -LiteralPath $root -Recurse -File)'); Expect = 1 },
        @{ Name = 'a file that calls the helper passes'; Text = ("$walk`n" + 'Get-' + 'QATrackedFiles -RepoRoot $repoRoot'); Expect = 0 },
        @{ Name = 'an annotated walk passes'; Text = ("$walk  # enumeration-" + 'ok: build output under bundleV2'); Expect = 0 },
        @{ Name = 'an empty annotation does not count'; Text = ("$walk  # enumeration-" + 'ok:'); Expect = 1 },
        @{ Name = 'a walk of one mod folder passes'; Text = ('Get-' + 'ChildItem -Path $modDir -Filter "*.lua" -Recurse -File'); Expect = 0 },
        @{ Name = 'a non-recursive root listing passes'; Text = ('Get-' + 'ChildItem -LiteralPath $repoRoot -Directory'); Expect = 0 },
        @{ Name = 'a $rootPath walk is not a root variable'; Text = ('Get-' + 'ChildItem -LiteralPath $rootPath -Recurse'); Expect = 0 }
    )
    $failed = 0
    foreach ($case in $cases) {
        $count = @(Get-GateEnumerationFindings -Name 'fixture.ps1' -Text $case.Text).Count
        if ($count -eq $case.Expect) { if (-not $Quiet) { Write-Host "  [PASS] $($case.Name)" -ForegroundColor Green } }
        else { $failed++; Write-Host "  [FAIL] $($case.Name): expected $($case.Expect) finding(s), got $count" -ForegroundColor Red }
    }
    if ($failed -gt 0) { Write-Host "[check_gate_enumeration -SelfTest] FAILED ($failed)" -ForegroundColor Red; exit 2 }
    Write-Host "[check_gate_enumeration -SelfTest] OK - $($cases.Count) fixtures." -ForegroundColor Green
    exit 0
}

if (-not $Quiet) { Write-Host '=== check_gate_enumeration ===' -ForegroundColor Cyan }
$files = @(Get-ChildItem -LiteralPath $QaDir -Filter 'check_*.ps1' -File | Sort-Object Name)
$findings = @()
foreach ($file in $files) {
    $findings += @(Get-GateEnumerationFindings -Name ('qa/' + $file.Name) -Text ([IO.File]::ReadAllText($file.FullName)))
}
if ($findings.Count -gt 0) {
    Write-Host "[check_gate_enumeration] FAIL - $($findings.Count) gate walk(s) read git-ignored files:" -ForegroundColor Red
    foreach ($finding in $findings) { Write-Host "  ! $finding" -ForegroundColor Red }
    exit 2
}
Write-Host "[check_gate_enumeration] OK - $($files.Count) qa/check_*.ps1 file(s); no unannotated repository-root walk." -ForegroundColor Green
exit 0
