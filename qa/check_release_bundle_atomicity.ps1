# check_release_bundle_atomicity.ps1 - blocking source/bundle atomicity gate.
#
# Issue #724 repeatedly reached protected master with a mod's runtime source,
# MOD_VERSION, itemV2.cfg, or newest CHANGELOG release changed while the mod's
# compiled root bundle stayed byte-identical.  The later bundle-only repair PRs
# proved the missing invariant: releasable source and its generated root bundle
# must land in one reviewed change set.
#
# This check is diff-scoped. It intentionally allows docs/tests-only changes and
# bundle-only additions/modifications. Deletions require a new exact retirement
# trailer in the newest release, and an active canonical root cannot be deleted.
# A split-mod stable promotion may omit a
# root bundle only when it is metadata-only AND is explicitly sanctioned by the
# existing VT2-Promotion trailer (or VT2_PROMOTION=1 locally). Runtime source is
# never exempted by that trailer.
# Two narrow itemV2 exceptions cover metadata that BuildOnly proves does not
# compile into the root: an exact title synchronization, and the mandatory
# first-upload `published_id = 0L` -> positive-ID reconciliation. Both require
# unchanged MOD_VERSION and otherwise byte-identical cfg content. Any other
# cfg, runtime, or newest-release identity delta still requires the root bundle.
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
$bundleAuthorityHelper = Join-Path $PSScriptRoot '..\tools\ship\bundle-authority.ps1'
if (-not (Test-Path -LiteralPath $bundleAuthorityHelper -PathType Leaf)) {
    throw "Bundle-authority helpers are missing: $bundleAuthorityHelper"
}
. $bundleAuthorityHelper

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

function ConvertFrom-ReleaseAtomicityDataText {
    param([string]$Text, [string]$Label)
    if ([string]::IsNullOrWhiteSpace($Text)) { throw "$Label is missing." }
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $Text, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw "$Label is invalid PowerShell data: $(@($parseErrors | ForEach-Object { $_.Message }) -join '; ')"
    }
    $rootHash = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.HashtableAst]
    }, $false)
    if ($null -eq $rootHash) { throw "$Label has no root hashtable." }
    try { return $rootHash.SafeGetValue() }
    catch { throw "$Label is not constant PowerShell data: $($_.Exception.Message)" }
}

function Get-ReleaseAtomicityAuthorityTransitions {
    param([object]$Context, [string]$Root)

    $baseInventory = ConvertFrom-ReleaseAtomicityDataText `
        -Text (Read-ContextText $Context 'tools/mod-inventory.psd1' Base $Root) `
        -Label 'base mod inventory'
    $headInventory = ConvertFrom-ReleaseAtomicityDataText `
        -Text (Read-ContextText $Context 'tools/mod-inventory.psd1' Head $Root) `
        -Label 'head mod inventory'
    $transitions = @{}
    foreach ($headEntry in @($headInventory.Mods)) {
        $dir = [string]$headEntry.Dir
        $baseEntries = @($baseInventory.Mods | Where-Object { [string]$_.Dir -ceq $dir })
        if ($baseEntries.Count -ne 1) { continue }
        $baseEntry = $baseEntries[0]
        $baseAuthority = Assert-VtBundleAuthorityEntry -Entry $baseEntry
        $headAuthority = Assert-VtBundleAuthorityEntry -Entry $headEntry
        if ($baseAuthority -ceq 'tracked' -and $headAuthority -ceq 'receipt') {
            $transitions[$dir] = 'tracked-to-receipt'
        }
        elseif ($baseAuthority -ceq 'receipt' -and $headAuthority -ceq 'tracked') {
            $transitions[$dir] = 'receipt-to-tracked'
        }
    }
    return $transitions
}

function Get-ReleaseAtomicityHeadReceiptDirs {
    param([object]$Context, [string]$Root)

    $headInventory = ConvertFrom-ReleaseAtomicityDataText `
        -Text (Read-ContextText $Context 'tools/mod-inventory.psd1' Head $Root) `
        -Label 'head mod inventory'
    $receiptDirs = @{}
    foreach ($entry in @($headInventory.Mods)) {
        $authority = Assert-VtBundleAuthorityEntry -Entry $entry
        if ($authority -ceq 'receipt') { $receiptDirs[[string]$entry.Dir] = $true }
    }
    return $receiptDirs
}

function Get-TopReleaseVersion([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $match = [regex]::Match($Text, '(?m)^##\s+v?(?<version>\d+\.\d+\.\d+(?:\.\d+)?(?:-[A-Za-z0-9+.-]+)?)\b')
    if (-not $match.Success) { return $null }
    return $match.Groups['version'].Value
}

function Get-TopReleaseSection([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $match = [regex]::Match($Text,
        '(?ms)^##\s+v?\d+\.\d+\.\d+(?:\.\d+)?(?:-[A-Za-z0-9+.-]+)?\b.*?(?=^##\s+|\z)')
    if (-not $match.Success) { return '' }
    return $match.Value
}

function Get-DeclaredBundleRetirements([string]$Text) {
    $declared = @{}
    $section = Get-TopReleaseSection $Text
    if (-not $section) { return $declared }
    $matches = [regex]::Matches($section,
        '(?im)^\s*(?:[-*]\s*)?VT2-Bundle-Retirement:\s*`?(?<name>[A-Fa-f0-9]{16}\.mod_bundle)`?\s*$')
    foreach ($match in $matches) {
        $declared[$match.Groups['name'].Value.ToLowerInvariant()] = $true
    }
    return $declared
}

function Get-ModVersionFromText([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $match = [regex]::Match($Text, 'MOD_VERSION\s*=\s*"(?<version>[^"]+)"')
    if (-not $match.Success) { return $null }
    return $match.Groups['version'].Value
}

function Test-ExactCfgTitleSync {
    param(
        [string]$BaseCfg,
        [string]$HeadCfg,
        [string]$BaseVersion,
        [string]$HeadVersion
    )
    if ([string]::IsNullOrWhiteSpace($BaseCfg) -or
            [string]::IsNullOrWhiteSpace($HeadCfg) -or
            [string]::IsNullOrWhiteSpace($BaseVersion) -or
            $BaseVersion -ne $HeadVersion) {
        return $false
    }
    $pattern = '(?m)^(?<prefix>\s*title\s*=\s*")(?<title>[^"]+)(?<suffix>"\s*;\s*)$'
    $baseMatches = [regex]::Matches($BaseCfg, $pattern)
    $headMatches = [regex]::Matches($HeadCfg, $pattern)
    if ($baseMatches.Count -ne 1 -or $headMatches.Count -ne 1) { return $false }
    $baseTitle = $baseMatches[0].Groups['title'].Value
    $headTitle = $headMatches[0].Groups['title'].Value
    if ($baseTitle -eq $headTitle) { return $false }
    $baseStem = [regex]::Replace($baseTitle, '\s+v\d+(?:\.\d+){1,3}(?:-[A-Za-z0-9+.-]+)?$', '')
    if ($baseStem -eq $baseTitle -or $headTitle -ne "$baseStem v$HeadVersion") { return $false }
    $replaceTitle = {
        param($match)
        return $match.Groups['prefix'].Value + '__VT2_TITLE__' + $match.Groups['suffix'].Value
    }
    # git-show line joining omits the terminal newline while worktree reads
    # retain it; normalize only line endings and that transport artifact.
    $baseNormalized = ($BaseCfg -replace "`r`n", "`n").TrimEnd([char[]]@("`r", "`n"))
    $headNormalized = ($HeadCfg -replace "`r`n", "`n").TrimEnd([char[]]@("`r", "`n"))
    $baseSkeleton = [regex]::Replace($baseNormalized, $pattern, $replaceTitle)
    $headSkeleton = [regex]::Replace($headNormalized, $pattern, $replaceTitle)
    return $baseSkeleton -ceq $headSkeleton
}

function Test-ExactCfgBootstrapPublishedIdSync {
    param(
        [string]$BaseCfg,
        [string]$HeadCfg,
        [string]$BaseVersion,
        [string]$HeadVersion
    )
    if ([string]::IsNullOrWhiteSpace($BaseCfg) -or
            [string]::IsNullOrWhiteSpace($HeadCfg) -or
            [string]::IsNullOrWhiteSpace($BaseVersion) -or
            $BaseVersion -cne $HeadVersion) {
        return $false
    }
    $pattern = '(?m)^(?<prefix>[ \t]*published_id[ \t]*=[ \t]*)(?<id>\d+)(?<suffix>L[ \t]*;[ \t]*)$'
    $baseMatches = [regex]::Matches($BaseCfg, $pattern)
    $headMatches = [regex]::Matches($HeadCfg, $pattern)
    if ($baseMatches.Count -ne 1 -or $headMatches.Count -ne 1) { return $false }
    if ($baseMatches[0].Groups['id'].Value -cne '0' -or
            $headMatches[0].Groups['id'].Value -cnotmatch '^[1-9]\d*$') {
        return $false
    }
    $replaceId = {
        param($match)
        return $match.Groups['prefix'].Value + '__VT2_PUBLISHED_ID__' +
            $match.Groups['suffix'].Value
    }
    # git-show line joining omits the terminal newline while worktree reads
    # retain it; normalize only line endings and that transport artifact.
    $baseNormalized = ($BaseCfg -replace "`r`n", "`n").TrimEnd([char[]]@("`r", "`n"))
    $headNormalized = ($HeadCfg -replace "`r`n", "`n").TrimEnd([char[]]@("`r", "`n"))
    $baseSkeleton = [regex]::Replace($baseNormalized, $pattern, $replaceId)
    $headSkeleton = [regex]::Replace($headNormalized, $pattern, $replaceId)
    return $baseSkeleton -ceq $headSkeleton
}

function Test-RuntimePath([string]$RelativePath) {
    $rawRelative = $RelativePath.Replace('\', '/').TrimStart('/')
    while ($rawRelative.StartsWith('./', [System.StringComparison]::Ordinal)) {
        $rawRelative = $rawRelative.Substring(2)
    }
    # Issue #1278: this deterministic provenance sidecar describes runtime
    # inputs but is not itself consumed by VMB or the game.
    if ($rawRelative -ceq '.build-receipt.json') { return $false }
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
        [hashtable]$TrustedPromotions,
        [hashtable]$TrustedTitleSyncs,
        [hashtable]$TrustedBootstrapIdSyncs,
        [hashtable]$DeclaredBundleRetirements,
        [hashtable]$AuthorityTransitions = @{},
        [hashtable]$ReceiptAuthorityDirs = @{}
    )
    $errors = @()
    if ($null -eq $DeclaredBundleRetirements) { $DeclaredBundleRetirements = @{} }
    if ($null -eq $TrustedTitleSyncs) { $TrustedTitleSyncs = @{} }
    if ($null -eq $TrustedBootstrapIdSyncs) { $TrustedBootstrapIdSyncs = @{} }
    $deletionErrors = @{}

    # Bundle-only reconciliation remains valid, but deletion is never ordinary
    # generated-output churn.  A sibling bundle may retire only through a new,
    # exact trailer in the newest CHANGELOG release.  The active canonical root
    # remains mandatory while its mod is present in mod-inventory.psd1.
    foreach ($change in @($Changes)) {
        if ($change.Status -ne 'D' -or
                $change.Path -notmatch '^(?<dir>[^/]+)/bundleV2/(?<name>[A-Fa-f0-9]{16}\.mod_bundle)$') {
            continue
        }
        $dir = $matches['dir']
        $name = $matches['name'].ToLowerInvariant()
        $key = "$dir/$name".ToLowerInvariant()
        $active = @($Mods | Where-Object { [string]$_.Dir -ieq $dir }) | Select-Object -First 1
        $isActiveRoot = $active -and ([string]$active.RootBundle -ieq $name)
        $isTrackedToReceipt = $AuthorityTransitions.ContainsKey($dir) -and
            [string]$AuthorityTransitions[$dir] -ceq 'tracked-to-receipt'
        if ($isTrackedToReceipt) { continue }
        if ($isActiveRoot) {
            $errors += "${dir}: active canonical root bundle cannot be deleted: $($change.Path)"
            $deletionErrors[$key] = $true
        } elseif (-not $DeclaredBundleRetirements.ContainsKey($key)) {
            $errors += "${dir}: tracked bundle deletion lacks a new newest-release 'VT2-Bundle-Retirement: $name' trailer: $($change.Path)"
            $deletionErrors[$key] = $true
        }
    }

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
        if ($AuthorityTransitions.ContainsKey($dir) -and
                [string]$AuthorityTransitions[$dir] -ceq 'tracked-to-receipt') {
            # The shared #1412 contract validates the exact all-output delete,
            # scoped ignore, schema-3 receipt map, and atomic inventory flip.
            # This is a typed authority transition, never ordinary retirement.
            continue
        }
        if ($ReceiptAuthorityDirs.ContainsKey($dir)) {
            # Receipt-authority runtime/output atomicity is validated against
            # its schema-3 receipt by the shared #1412 gate.
            continue
        }

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

        $rootDeletionKey = "$dir/$rootBundle".ToLowerInvariant()
        if ($deletionErrors.ContainsKey($rootDeletionKey)) { continue }

        $trustedMetadataOnlyPromotion = $runtimeHits.Count -eq 0 -and
            ([string]$mod.Stream -eq 'stable') -and
            $TrustedPromotions.ContainsKey($dir) -and [bool]$TrustedPromotions[$dir]
        if ($trustedMetadataOnlyPromotion) { continue }

        $trustedTitleOnlySync = $runtimeHits.Count -eq 0 -and
            $metadataHits.Count -eq 1 -and
            $metadataHits[0] -ieq "$dir/itemV2.cfg" -and
            $TrustedTitleSyncs.ContainsKey($dir) -and [bool]$TrustedTitleSyncs[$dir]
        if ($trustedTitleOnlySync) { continue }

        $trustedBootstrapIdOnlySync = $runtimeHits.Count -eq 0 -and
            $metadataHits.Count -eq 1 -and
            $metadataHits[0] -ieq "$dir/itemV2.cfg" -and
            $TrustedBootstrapIdSyncs.ContainsKey($dir) -and
            [bool]$TrustedBootstrapIdSyncs[$dir]
        if ($trustedBootstrapIdOnlySync) { continue }

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
        $titleSyncs = @{}; foreach ($name in @($case.TrustedTitleSyncs)) { $titleSyncs[[string]$name] = $true }
        $bootstrapIdSyncs = @{}; foreach ($name in @($case.TrustedBootstrapIdSyncs)) { $bootstrapIdSyncs[[string]$name] = $true }
        $retired = @{}; foreach ($path in @($case.DeclaredBundleRetirements | Where-Object { $_ })) {
            $retired[([string]$path).ToLowerInvariant()] = $true
        }
        $actual = @(Test-ReleaseBundleAtomicity -Mods $mods -Changes $changes `
            -TopReleaseChanged $top -TrustedPromotions $trusted `
            -TrustedTitleSyncs $titleSyncs -TrustedBootstrapIdSyncs $bootstrapIdSyncs `
            -DeclaredBundleRetirements $retired)
        $expected = [int]$case.ExpectedErrors
        if ($actual.Count -ne $expected) {
            throw "fixture '$($case.Name)' expected $expected error(s), got $($actual.Count): $($actual -join '; ')"
        }
        $passed++
    }
    if ((Get-TopReleaseVersion "# x`n## v1.2.3-dev (date)`n") -ne '1.2.3-dev') { throw 'top release parser lost optional v prefix' }
    $retirements = Get-DeclaredBundleRetirements "# x`n## 1.2.3-dev`n- VT2-Bundle-Retirement: ``cccccccccccccccc.mod_bundle```n`n## 1.2.2-dev`n- VT2-Bundle-Retirement: ``dddddddddddddddd.mod_bundle```n"
    if (-not $retirements.ContainsKey('cccccccccccccccc.mod_bundle') -or $retirements.ContainsKey('dddddddddddddddd.mod_bundle')) {
        throw 'bundle retirement parser did not stay within the newest release section'
    }
    if (Test-RuntimePath 'DEVELOPMENT.md') { throw 'markdown doc classified as runtime' }
    if (Test-RuntimePath '.build-receipt.json') { throw 'BuildOnly receipt classified as runtime source' }
    if (-not (Test-RuntimePath 'scripts/mods/example_mod/example_mod.lua')) { throw 'Lua source not classified as runtime' }
    $baseCfg = 'title = "Example v1.2.2-dev";' + "`n" + 'visibility = "friends_only";'
    $headCfg = 'title = "Example v1.2.3-dev";' + "`n" + 'visibility = "friends_only";'
    if (-not (Test-ExactCfgTitleSync $baseCfg $headCfg '1.2.3-dev' '1.2.3-dev')) { throw 'exact title-only sync was rejected' }
    $visibilityChanged = 'title = "Example v1.2.3-dev";' + "`n" + 'visibility = "public";'
    if (Test-ExactCfgTitleSync $baseCfg $visibilityChanged '1.2.3-dev' '1.2.3-dev') { throw 'title plus visibility change was trusted' }
    if (Test-ExactCfgTitleSync $baseCfg $headCfg '1.2.3-dev' '1.2.4-dev') { throw 'title sync with changed MOD_VERSION was trusted' }
    $wrongVersion = 'title = "Example v1.2.2-dev";' + "`n" + 'visibility = "friends_only";'
    if (Test-ExactCfgTitleSync $baseCfg $wrongVersion '1.2.3-dev' '1.2.3-dev') { throw 'title-only wrong-version sync was trusted' }
    $bootstrapBase = 'title = "Example";' + "`n" + 'published_id = 0L;' + "`n" + 'visibility = "friends_only";'
    $bootstrapHead = 'title = "Example";' + "`n" + 'published_id = 123456789L;' + "`n" + 'visibility = "friends_only";'
    if (-not (Test-ExactCfgBootstrapPublishedIdSync $bootstrapBase $bootstrapHead '1.2.3-dev' '1.2.3-dev')) {
        throw 'exact first-upload published_id sync was rejected'
    }
    $bootstrapTitleChanged = 'title = "Changed";' + "`n" + 'published_id = 123456789L;' + "`n" + 'visibility = "friends_only";'
    if (Test-ExactCfgBootstrapPublishedIdSync $bootstrapBase $bootstrapTitleChanged '1.2.3-dev' '1.2.3-dev') {
        throw 'first-upload published_id plus title change was trusted'
    }
    $bootstrapVisibilityChanged = 'title = "Example";' + "`n" + 'published_id = 123456789L;' + "`n" + 'visibility = "public";'
    if (Test-ExactCfgBootstrapPublishedIdSync $bootstrapBase $bootstrapVisibilityChanged '1.2.3-dev' '1.2.3-dev') {
        throw 'first-upload published_id plus visibility change was trusted'
    }
    $positiveBase = 'title = "Example";' + "`n" + 'published_id = 1L;' + "`n" + 'visibility = "friends_only";'
    if (Test-ExactCfgBootstrapPublishedIdSync $positiveBase $bootstrapHead '1.2.3-dev' '1.2.3-dev') {
        throw 'positive-to-positive published_id change was trusted'
    }
    if (Test-ExactCfgBootstrapPublishedIdSync $bootstrapBase $bootstrapHead '1.2.3-dev' '1.2.4-dev') {
        throw 'first-upload published_id sync with changed MOD_VERSION was trusted'
    }
    $authorityTransitionErrors = @(Test-ReleaseBundleAtomicity -Mods $mods -Changes @(
            [pscustomobject]@{ Status='M'; Path='tools/mod-inventory.psd1' },
            [pscustomobject]@{ Status='M'; Path='.gitignore' },
            [pscustomobject]@{ Status='M'; Path='example_mod/scripts/main.lua' },
            [pscustomobject]@{ Status='D'; Path='example_mod/bundleV2/aaaaaaaaaaaaaaaa.mod_bundle' }
        ) -TopReleaseChanged @{} -TrustedPromotions @{} -TrustedTitleSyncs @{} `
        -TrustedBootstrapIdSyncs @{} -DeclaredBundleRetirements @{} `
        -AuthorityTransitions @{ example_mod='tracked-to-receipt' })
    if ($authorityTransitionErrors.Count -ne 0) {
        throw "validated tracked-to-receipt transition was treated as ordinary retirement: $($authorityTransitionErrors -join '; ')"
    }
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

    $authorityTransitions = Get-ReleaseAtomicityAuthorityTransitions `
        -Context $context -Root $root
    $receiptAuthorityDirs = Get-ReleaseAtomicityHeadReceiptDirs `
        -Context $context -Root $root
    if ($authorityTransitions.Count -gt 0 -or $receiptAuthorityDirs.Count -gt 0) {
        # Standalone atomicity runs must not trust a mode flip merely because
        # it looks like one. Execute the complete shared authority gate in a
        # child host so its script-level exit remains isolated.
        $authorityGate = Join-Path $PSScriptRoot 'check_bundle_authority.ps1'
        if (-not (Test-Path -LiteralPath $authorityGate -PathType Leaf)) {
            throw "Bundle-authority gate is missing: $authorityGate"
        }
        $hostExecutable = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $authorityArguments = @('-NoLogo', '-NoProfile', '-NonInteractive')
        if ([System.IO.Path]::GetFileName($hostExecutable) -ieq 'powershell.exe') {
            $authorityArguments += @('-ExecutionPolicy', 'Bypass')
        }
        $authorityArguments += @('-File', $authorityGate, '-RepoRoot', $root, '-Quiet')
        if ($Staged) { $authorityArguments += '-Staged' }
        elseif ($Range) { $authorityArguments += @('-Range', $Range) }
        & $hostExecutable @authorityArguments
        if ($LASTEXITCODE -ne 0) {
            Write-Host '[check_release_bundle_atomicity] ERROR - typed bundle-authority transition failed its shared #1412 contract.' -ForegroundColor Red
            exit 2
        }
    }

    $inventoryPath = Join-Path $root 'tools\mod-inventory.psd1'
    $inventory = Import-PowerShellDataFile -Path $inventoryPath
    $mods = @($inventory.Mods)

    $topReleaseChanged = @{}
    $declaredBundleRetirements = @{}
    foreach ($mod in $mods) {
        $path = "$($mod.Dir)/CHANGELOG.md"
        if (@($changes | Where-Object { $_.Path -ieq $path }).Count -eq 0) { continue }
        $before = Get-TopReleaseVersion (Read-ContextText $context $path 'Base' $root)
        $after = Get-TopReleaseVersion (Read-ContextText $context $path 'Head' $root)
        $topReleaseChanged[[string]$mod.Dir] = ($before -ne $after)
    }

    $deletedBundleDirs = @($changes | Where-Object {
        $_.Status -eq 'D' -and $_.Path -match '^(?<dir>[^/]+)/bundleV2/[A-Fa-f0-9]{16}\.mod_bundle$'
    } | ForEach-Object { if ($_.Path -match '^(?<dir>[^/]+)/') { $matches['dir'] } } | Sort-Object -Unique)
    foreach ($dir in $deletedBundleDirs) {
        $changelogPath = "$dir/CHANGELOG.md"
        $before = Get-DeclaredBundleRetirements (Read-ContextText $context $changelogPath 'Base' $root)
        $after = Get-DeclaredBundleRetirements (Read-ContextText $context $changelogPath 'Head' $root)
        foreach ($name in $after.Keys) {
            if (-not $before.ContainsKey($name)) {
                $declaredBundleRetirements["$dir/$name".ToLowerInvariant()] = $true
            }
        }
    }

    $trustedPromotions = @{}
    $trustedTitleSyncs = @{}
    $trustedBootstrapIdSyncs = @{}
    foreach ($mod in $mods) {
        $dir = [string]$mod.Dir
        $cfgPath = "$dir/itemV2.cfg"
        if (@($changes | Where-Object { $_.Path -ieq $cfgPath }).Count -eq 0) { continue }
        $luaPath = "$dir/scripts/mods/$dir/$dir.lua"
        $baseCfg = Read-ContextText $context $cfgPath 'Base' $root
        $headCfg = Read-ContextText $context $cfgPath 'Head' $root
        $baseVersion = Get-ModVersionFromText (Read-ContextText $context $luaPath 'Base' $root)
        $headVersion = Get-ModVersionFromText (Read-ContextText $context $luaPath 'Head' $root)
        if (Test-ExactCfgTitleSync $baseCfg $headCfg $baseVersion $headVersion) {
            $trustedTitleSyncs[$dir] = $true
        }
        if (Test-ExactCfgBootstrapPublishedIdSync `
                $baseCfg $headCfg $baseVersion $headVersion) {
            $trustedBootstrapIdSyncs[$dir] = $true
        }
    }
    if ($env:VT2_PROMOTION -eq '1') {
        if ($env:GITHUB_ACTIONS) {
            # Issue #676: CI promotion authority is emitted only after the live
            # PR label, maintainer timeline actor, exact version, and head SHA
            # pass check_promotion_authorization.ps1. Never trust a branch-owned
            # commit trailer as authority.
            $authorized = @("$($env:VT2_PROMOTION_DIRS)" -split ';' | ForEach-Object { $_.Trim().TrimEnd('/', '\') } | Where-Object { $_ })
            foreach ($dir in $authorized) {
                if (@($mods | Where-Object { $_.Stream -eq 'stable' -and $_.Dir -eq $dir }).Count -gt 0) {
                    $trustedPromotions[$dir] = $true
                }
            }
        } else {
            foreach ($mod in $mods | Where-Object { $_.Stream -eq 'stable' }) { $trustedPromotions[[string]$mod.Dir] = $true }
        }
    }

    $errors = @(Test-ReleaseBundleAtomicity -Mods $mods -Changes $changes `
        -TopReleaseChanged $topReleaseChanged -TrustedPromotions $trustedPromotions `
        -TrustedTitleSyncs $trustedTitleSyncs `
        -TrustedBootstrapIdSyncs $trustedBootstrapIdSyncs `
        -DeclaredBundleRetirements $declaredBundleRetirements `
        -AuthorityTransitions $authorityTransitions `
        -ReceiptAuthorityDirs $receiptAuthorityDirs)
    if ($errors.Count -gt 0) {
        Write-Host '[check_release_bundle_atomicity] ERRORS - releasable mod changes and root bundles must land atomically (#724):' -ForegroundColor Red
        foreach ($message in $errors) { Write-Host "  X $message" -ForegroundColor Red }
        Write-Host '  Build with the serialized VMB path, commit the exact root bundle in the same PR, then rerun QA.' -ForegroundColor Yellow
        Write-Host '  Bundle-only additions/modifications and docs/tests-only changes remain valid. Deletions require a new exact VT2-Bundle-Retirement trailer; active roots cannot be deleted.' -ForegroundColor Yellow
        Write-Host '  VT2-Promotion exempts only stable metadata-only promotions; exact title-only and first-upload 0L-to-positive-ID synchronizations are separately validated.' -ForegroundColor Yellow
        exit 2
    }
    if (-not $Quiet) { Write-Host '[check_release_bundle_atomicity] OK - every releasable mod delta has its exact root bundle delta.' -ForegroundColor Green }
    exit 0
} finally {
    Pop-Location
}
