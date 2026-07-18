# check_release_bundle_atomicity.ps1 - blocking source/bundle atomicity gate.
#
# Issue #724 repeatedly reached protected master with a mod's runtime source,
# MOD_VERSION, itemV2.cfg, or newest CHANGELOG release changed while the mod's
# compiled root bundle stayed byte-identical.  The later bundle-only repair PRs
# proved the missing invariant: releasable source and its generated root bundle
# must land in one reviewed change set.
#
# This check is diff-scoped. It intentionally allows docs/tests-only changes and
# bundle-only reconciliation changes. A split-mod stable promotion may omit a
# root bundle only when it is metadata-only AND is explicitly sanctioned by the
# existing VT2-Promotion trailer (or VT2_PROMOTION=1 locally). Runtime source is
# never exempted by that trailer.
#
# Exit codes: 0 = clean/indeterminate, 2 = atomicity error.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$Range,
    [switch]$Staged,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }

function Normalize-RepoPath([string]$Path) {
    if ($null -eq $Path) { return '' }
    return $Path.Replace('\', '/').TrimStart([char[]]@('.', '/'))
}

function Convert-NameStatusLines([string[]]$Lines) {
    $changes = @()
    foreach ($line in @($Lines)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = @($line -split "`t")
        if ($parts.Count -lt 2) { continue }
        $status = $parts[0]
        if ($status -match '^R' -and $parts.Count -ge 3) {
            $changes += [pscustomobject]@{ Status = 'D'; Path = (Normalize-RepoPath $parts[1]) }
            $changes += [pscustomobject]@{ Status = 'A'; Path = (Normalize-RepoPath $parts[2]) }
        } else {
            $changes += [pscustomobject]@{ Status = $status.Substring(0, 1); Path = (Normalize-RepoPath $parts[1]) }
        }
    }
    return @($changes)
}

function Invoke-GitLines([string[]]$GitArgs) {
    try {
        $output = @(& git @GitArgs 2>$null)
        if ($LASTEXITCODE -ne 0) { return $null }
        # Preserve a successful empty result as an empty String[] instead of
        # allowing PowerShell's pipeline unrolling to collapse it to $null.
        # Get-DiffContext uses $null exclusively for an indeterminate/failed
        # git command, while an empty worktree diff must fall through to the
        # latest committed diff.
        return ,([string[]]$output)
    } catch {
        return $null
    }
}

function Get-DiffContext {
    if ($Staged) {
        $lines = Invoke-GitLines @('diff', '--cached', '--name-status', '--diff-filter=ACMRD')
        return [pscustomobject]@{ Mode='index'; Base='HEAD'; Head='INDEX'; LogRange=$null; Lines=$lines }
    }

    if ($Range) {
        $left = $null; $right = 'HEAD'; $logRange = $Range
        if ($Range -match '^(.*?)\.\.\.(.*)$') {
            $left = $matches[1]; if ($matches[2]) { $right = $matches[2] }
            $mergeBase = Invoke-GitLines @('merge-base', $left, $right)
            if ($null -eq $mergeBase -or $mergeBase.Count -eq 0) { return $null }
            $left = "$($mergeBase[0])".Trim()
        } elseif ($Range -match '^(.*?)\.\.(.*)$') {
            $left = $matches[1]; if ($matches[2]) { $right = $matches[2] }
        } else {
            $left = "$Range^"
            $right = $Range
            $logRange = "$left..$right"
        }
        $lines = Invoke-GitLines @('diff', '--name-status', '--diff-filter=ACMRD', $Range)
        return [pscustomobject]@{ Mode='commit'; Base=$left; Head=$right; LogRange=$logRange; Lines=$lines }
    }

    if ($env:GITHUB_BASE_REF) {
        return Get-DiffContextForRange "origin/$($env:GITHUB_BASE_REF)...HEAD"
    }

    $dirty = Invoke-GitLines @('diff', 'HEAD', '--name-status', '--diff-filter=ACMRD')
    if ($null -eq $dirty) { return $null }
    if ($dirty.Count -gt 0) {
        return [pscustomobject]@{ Mode='worktree'; Base='HEAD'; Head='WORKTREE'; LogRange=$null; Lines=$dirty }
    }

    $recent = Invoke-GitLines @('diff', 'HEAD~1..HEAD', '--name-status', '--diff-filter=ACMRD')
    return [pscustomobject]@{ Mode='commit'; Base='HEAD~1'; Head='HEAD'; LogRange='HEAD~1..HEAD'; Lines=$recent }
}

function Get-DiffContextForRange([string]$RequestedRange) {
    $savedRange = $script:requestedRange
    try {
        $script:requestedRange = $RequestedRange
        $left = $null; $right = 'HEAD'
        if ($RequestedRange -match '^(.*?)\.\.\.(.*)$') {
            $left = $matches[1]; if ($matches[2]) { $right = $matches[2] }
            $mergeBase = Invoke-GitLines @('merge-base', $left, $right)
            if ($null -eq $mergeBase -or $mergeBase.Count -eq 0) { return $null }
            $left = "$($mergeBase[0])".Trim()
        } elseif ($RequestedRange -match '^(.*?)\.\.(.*)$') {
            $left = $matches[1]; if ($matches[2]) { $right = $matches[2] }
        } else {
            $left = "$RequestedRange^"; $right = $RequestedRange
        }
        $lines = Invoke-GitLines @('diff', '--name-status', '--diff-filter=ACMRD', $RequestedRange)
        return [pscustomobject]@{ Mode='commit'; Base=$left; Head=$right; LogRange="$left..$right"; Lines=$lines }
    } finally {
        $script:requestedRange = $savedRange
    }
}

function Read-GitObjectText([string]$Spec) {
    $lines = Invoke-GitLines @('show', $Spec)
    if ($null -eq $lines) { return $null }
    return ($lines -join "`n")
}

function Read-ContextText([object]$Context, [string]$Path, [ValidateSet('Base','Head')][string]$Side, [string]$Root) {
    $norm = Normalize-RepoPath $Path
    if ($Context.Mode -eq 'index') {
        if ($Side -eq 'Base') { return Read-GitObjectText "HEAD:$norm" }
        return Read-GitObjectText ":$norm"
    }
    if ($Context.Mode -eq 'worktree') {
        if ($Side -eq 'Base') { return Read-GitObjectText "HEAD:$norm" }
        $full = Join-Path $Root ($norm.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
        return [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
    }
    $commit = if ($Side -eq 'Base') { $Context.Base } else { $Context.Head }
    return Read-GitObjectText "${commit}:$norm"
}

function Get-TopReleaseVersion([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $match = [regex]::Match($Text, '(?m)^##\s+v?(?<version>\d+\.\d+\.\d+(?:\.\d+)?(?:-[A-Za-z0-9+.-]+)?)\b')
    if (-not $match.Success) { return $null }
    return $match.Groups['version'].Value
}

function Test-RuntimePath([string]$RelativePath) {
    $rel = Normalize-RepoPath $RelativePath
    if ($rel -match '^bundleV2/') { return $false }
    if ($rel -in @('CHANGELOG.md', 'itemV2.cfg', '.gitignore')) { return $false }
    if ($rel -match '(^|/)(tests?|test_fixtures|fixtures)(/|$)') { return $false }
    if ([System.IO.Path]::GetExtension($rel).ToLowerInvariant() -eq '.md') { return $false }
    if ([System.IO.Path]::GetFileName($rel) -match '^(?i:preview|thumbnail)(?:[._-].*)?\.(png|jpe?g|dds)$') { return $false }
    return $true
}

function Test-ReleaseBundleAtomicity {
    param(
        [object[]]$Mods,
        [object[]]$Changes,
        [hashtable]$TopReleaseChanged,
        [hashtable]$TrustedPromotions
    )
    $errors = @()
    foreach ($mod in @($Mods)) {
        $dir = [string]$mod.Dir
        $rootBundle = [string]$mod.RootBundle
        if ([string]::IsNullOrWhiteSpace($rootBundle)) {
            $errors += "${dir}: inventory has no RootBundle identity"
            continue
        }
        $prefix = "$dir/"
        $modChanges = @($Changes | Where-Object { $_.Path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) })
        if ($modChanges.Count -eq 0) { continue }

        $rootPath = "$dir/bundleV2/$rootBundle"
        $rootUpdated = @($modChanges | Where-Object {
            $_.Path -ieq $rootPath -and $_.Status -in @('A','M')
        }).Count -gt 0

        $runtimeHits = @()
        foreach ($change in $modChanges) {
            $relative = $change.Path.Substring($prefix.Length)
            if (Test-RuntimePath $relative) { $runtimeHits += $change.Path }
        }

        $metadataHits = @()
        if (@($modChanges | Where-Object { $_.Path -ieq "$dir/itemV2.cfg" }).Count -gt 0) {
            $metadataHits += "$dir/itemV2.cfg"
        }
        if ($TopReleaseChanged.ContainsKey($dir) -and [bool]$TopReleaseChanged[$dir]) {
            $metadataHits += "$dir/CHANGELOG.md (newest release identity changed)"
        }

        if ($runtimeHits.Count -eq 0 -and $metadataHits.Count -eq 0) { continue }
        if ($rootUpdated) { continue }

        $trustedMetadataOnlyPromotion = $runtimeHits.Count -eq 0 -and
            ([string]$mod.Stream -eq 'stable') -and
            $TrustedPromotions.ContainsKey($dir) -and [bool]$TrustedPromotions[$dir]
        if ($trustedMetadataOnlyPromotion) { continue }

        $triggers = @($runtimeHits) + @($metadataHits)
        $errors += "${dir}: release/runtime delta lacks root bundle '$rootPath'; trigger(s): $($triggers -join ', ')"
    }
    return @($errors)
}

function Invoke-SelfTest {
    $fixturePath = Join-Path $PSScriptRoot 'fixtures\release_bundle_atomicity\cases.psd1'
    if (-not (Test-Path -LiteralPath $fixturePath -PathType Leaf)) { throw "fixture missing: $fixturePath" }
    $fixture = Import-PowerShellDataFile -Path $fixturePath
    $mods = @(
        @{ Dir='example_mod'; RootBundle='aaaaaaaaaaaaaaaa.mod_bundle'; Stream='single' },
        @{ Dir='stable_mod'; RootBundle='bbbbbbbbbbbbbbbb.mod_bundle'; Stream='stable' }
    )
    $passed = 0
    foreach ($case in @($fixture.Cases)) {
        $changes = @($case.Changes | ForEach-Object {
            [pscustomobject]@{ Status = if ($_.Status) { [string]$_.Status } else { 'M' }; Path = [string]$_.Path }
        })
        $top = @{}; foreach ($name in @($case.TopReleaseChanged)) { $top[[string]$name] = $true }
        $trusted = @{}; foreach ($name in @($case.TrustedPromotions)) { $trusted[[string]$name] = $true }
        $actual = @(Test-ReleaseBundleAtomicity -Mods $mods -Changes $changes -TopReleaseChanged $top -TrustedPromotions $trusted)
        $expected = [int]$case.ExpectedErrors
        if ($actual.Count -ne $expected) {
            throw "fixture '$($case.Name)' expected $expected error(s), got $($actual.Count): $($actual -join '; ')"
        }
        $passed++
    }
    if ((Get-TopReleaseVersion "# x`n## v1.2.3-dev (date)`n") -ne '1.2.3-dev') { throw 'top release parser lost optional v prefix' }
    if (Test-RuntimePath 'DEVELOPMENT.md') { throw 'markdown doc classified as runtime' }
    if (-not (Test-RuntimePath 'scripts/mods/example_mod/example_mod.lua')) { throw 'Lua source not classified as runtime' }
    $emptyGit = Invoke-GitLines @('diff', 'HEAD', '--name-only', '--', '__release_atomicity_fixture_path_that_does_not_exist__')
    if ($null -eq $emptyGit -or $emptyGit.Count -ne 0) { throw 'successful empty git output collapsed into indeterminate state' }
    Write-Host "[check_release_bundle_atomicity -SelfTest] PASS $passed fixture cases" -ForegroundColor Green
    return 0
}

if ($SelfTest) { exit (Invoke-SelfTest) }

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
Push-Location $root
try {
    $context = if ($Range) { Get-DiffContextForRange $Range } else { Get-DiffContext }
    if ($null -eq $context -or $null -eq $context.Lines) {
        if (-not $Quiet) { Write-Host '[check_release_bundle_atomicity] SKIP - git diff context indeterminate.' -ForegroundColor DarkYellow }
        exit 0
    }
    $changes = @(Convert-NameStatusLines $context.Lines)
    if ($changes.Count -eq 0) {
        if (-not $Quiet) { Write-Host '[check_release_bundle_atomicity] OK - no changed files in scope.' -ForegroundColor Green }
        exit 0
    }

    $inventoryPath = Join-Path $root 'tools\mod-inventory.psd1'
    $inventory = Import-PowerShellDataFile -Path $inventoryPath
    $mods = @($inventory.Mods)

    $topReleaseChanged = @{}
    foreach ($mod in $mods) {
        $path = "$($mod.Dir)/CHANGELOG.md"
        if (@($changes | Where-Object { $_.Path -ieq $path }).Count -eq 0) { continue }
        $before = Get-TopReleaseVersion (Read-ContextText $context $path 'Base' $root)
        $after = Get-TopReleaseVersion (Read-ContextText $context $path 'Head' $root)
        $topReleaseChanged[[string]$mod.Dir] = ($before -ne $after)
    }

    $trustedPromotions = @{}
    if ($env:VT2_PROMOTION -eq '1') {
        foreach ($mod in $mods | Where-Object { $_.Stream -eq 'stable' }) { $trustedPromotions[[string]$mod.Dir] = $true }
    } elseif ($context.LogRange) {
        foreach ($line in @(Invoke-GitLines @('log', '--format=%(trailers:key=VT2-Promotion,valueonly)', $context.LogRange))) {
            $value = "$line".Trim().TrimEnd('/'); if ($value) { $trustedPromotions[$value] = $true }
        }
    }

    $errors = @(Test-ReleaseBundleAtomicity -Mods $mods -Changes $changes -TopReleaseChanged $topReleaseChanged -TrustedPromotions $trustedPromotions)
    if ($errors.Count -gt 0) {
        Write-Host '[check_release_bundle_atomicity] ERRORS - releasable mod changes and root bundles must land atomically (#724):' -ForegroundColor Red
        foreach ($message in $errors) { Write-Host "  X $message" -ForegroundColor Red }
        Write-Host '  Build with the serialized VMB path, commit the exact root bundle in the same PR, then rerun QA.' -ForegroundColor Yellow
        Write-Host '  Bundle-only reconciliation PRs and docs/tests-only changes remain valid. VT2-Promotion only exempts stable metadata-only promotions.' -ForegroundColor Yellow
        exit 2
    }
    if (-not $Quiet) { Write-Host '[check_release_bundle_atomicity] OK - every releasable mod delta has its exact root bundle delta.' -ForegroundColor Green }
    exit 0
} finally {
    Pop-Location
}
