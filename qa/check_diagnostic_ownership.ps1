# Blocking issue #499 gate for production diagnostic ownership.
# Structural validation is fully offline. The hosted lifecycle guard separately
# checks active_issue rows against its already-fetched open-issue set.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$ManifestPath,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }
if (-not $ManifestPath) { $ManifestPath = Join-Path $PSScriptRoot 'diagnostic_ownership.psd1' }
. (Join-Path $RepoRoot 'tools\diagnostics\diagnostic_ownership_policy.ps1')

function Invoke-DiagnosticOwnershipSelfTest {
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('vt2-diagnostic-ownership-' + [guid]::NewGuid().ToString('N'))
    try {
        $modRoot = Join-Path $temp 'demo'
        $luaRoot = Join-Path $modRoot 'scripts\mods\demo'
        New-Item -ItemType Directory -Force -Path $luaRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $modRoot 'demo.mod') -Value 'return {}'
        Set-Content -LiteralPath (Join-Path $luaRoot 'demo.lua') -Value 'mod:dofile("scripts/mods/demo/_demo_diag_active")'
        Set-Content -LiteralPath (Join-Path $luaRoot '_demo_diag_active.lua') -Value @(
            'local MAX_RECORDS = 4',
            'printf("[demo:9] ready")',
            'printf("[demo:legacy7] ready")',
            'return {}'
        )
        Set-Content -LiteralPath (Join-Path $luaRoot '_demo_debug_probes.lua') -Value 'return {}'

        $activePath = 'demo/scripts/mods/demo/_demo_diag_active.lua'
        $standingPath = 'demo/scripts/mods/demo/_demo_debug_probes.lua'
        $good = @{
            Version = 1
            StandingProbePaths = @($standingPath)
            Entries = @(
                @{ Path=$activePath; Classification='active_issue'; Issues=@(9); Stream='friends_only'; Prefixes=@('[demo:9]'); LoadOwner='demo/scripts/mods/demo/demo.lua'; LoadAnchor='_demo_diag_active'; Arming='command'; BoundAnchors=@('local MAX_RECORDS = 4') },
                @{ Path=$standingPath; Classification='standing'; Stream='friends_only' }
            )
        }
        $positive = Test-VtDiagnosticOwnership -Manifest $good -RepoRoot $temp -ExpectedStandingProbePaths @($standingPath)
        if ($positive.Failures.Count -ne 0) { throw "positive fixture failed: $($positive.Failures -join '; ')" }
        if (@(Test-VtDiagnosticIssueStates -Manifest $good -OpenIssues @([pscustomobject]@{number=9})).Count -ne 0) {
            throw 'open active issue fixture failed'
        }

        Set-Content -LiteralPath (Join-Path $luaRoot '_demo_surprise_probe.lua') -Value 'return {}'
        $unknown = Test-VtDiagnosticOwnership -Manifest $good -RepoRoot $temp -ExpectedStandingProbePaths @($standingPath)
        if ($unknown.Failures -notmatch 'unregistered production diagnostic') { throw 'unknown probe path was not rejected' }
        Remove-Item -LiteralPath (Join-Path $luaRoot '_demo_surprise_probe.lua') -Force

        Set-Content -LiteralPath (Join-Path $luaRoot '_demo_diag_unregistered.lua') -Value 'return {}'
        $unregistered = Test-VtDiagnosticOwnership -Manifest $good -RepoRoot $temp -ExpectedStandingProbePaths @($standingPath)
        if ($unregistered.Failures -notmatch 'unregistered production diagnostic') { throw 'unregistered _diag_ owner was not rejected' }
        Remove-Item -LiteralPath (Join-Path $luaRoot '_demo_diag_unregistered.lua') -Force

        $closed = @(Test-VtDiagnosticIssueStates -Manifest $good -OpenIssues @())
        if ($closed -notmatch 'non-open issue #9') { throw 'closed mocked issue was not rejected' }

        $stable = @{
            Version=1; StandingProbePaths=@($standingPath); Entries=@(
                @{ Path=$activePath; Classification='active_issue'; Issues=@(9); Stream='public'; Prefixes=@('[demo:9]'); LoadOwner='demo/scripts/mods/demo/demo.lua'; LoadAnchor='_demo_diag_active'; Arming='command'; BoundAnchors=@('local MAX_RECORDS = 4') },
                @{ Path=$standingPath; Classification='standing'; Stream='friends_only' }
            )
        }
        if ((Test-VtDiagnosticOwnership $stable $temp @($standingPath)).Failures -notmatch 'clean public stream') {
            throw 'stable issue diagnostic was not rejected'
        }

        foreach ($field in @('Prefixes','LoadOwner','BoundAnchors')) {
            $row = @{} + $good.Entries[0]
            [void]$row.Remove($field)
            $bad = @{ Version=1; StandingProbePaths=@($standingPath); Entries=@($row,$good.Entries[1]) }
            if ((Test-VtDiagnosticOwnership $bad $temp @($standingPath)).Failures.Count -eq 0) {
                throw "missing $field metadata was not rejected"
            }
        }

        $alias = @{} + $good.Entries[0]
        $alias.Prefixes = @('[demo:legacy7]')
        $alias.PrefixAliases = @(@{Prefix='[demo:legacy7]';Issue=9;Reason='fixture legacy receipt'})
        $aliasResult = Test-VtDiagnosticOwnership @{Version=1;StandingProbePaths=@($standingPath);Entries=@($alias,$good.Entries[1])} $temp @($standingPath)
        if ($aliasResult.Failures.Count -ne 0) { throw 'documented prefix alias or standing owner was rejected' }

        $undocumentedAlias = @{} + $alias
        [void]$undocumentedAlias.Remove('PrefixAliases')
        $undocumentedResult = Test-VtDiagnosticOwnership @{Version=1;StandingProbePaths=@($standingPath);Entries=@($undocumentedAlias,$good.Entries[1])} $temp @($standingPath)
        if ($undocumentedResult.Failures -notmatch 'exact documented alias') { throw 'undocumented receipt alias was not rejected' }

        Write-Host '[check_diagnostic_ownership:selftest] PASS - census, metadata, stream, issue-state, alias, and standing-owner fixtures passed.' -ForegroundColor Green
        exit 0
    }
    finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
    }
}

if ($SelfTest) { Invoke-DiagnosticOwnershipSelfTest }

$manifest = Import-PowerShellDataFile -LiteralPath $ManifestPath
$report = Test-VtDiagnosticOwnership -Manifest $manifest -RepoRoot $RepoRoot
if ($report.Failures.Count -gt 0) {
    Write-Host "[check_diagnostic_ownership] FAIL: $($report.Failures.Count) ownership violation(s):" -ForegroundColor Red
    foreach ($failure in $report.Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 2
}
if (-not $Quiet) {
    Write-Host ("[check_diagnostic_ownership] OK: {0} production owners registered ({1} active issue, {2} temporary retirement)." -f $report.Registered,$report.Active,$report.Temporary) -ForegroundColor Green
}
exit 0
