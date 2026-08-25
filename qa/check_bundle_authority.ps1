# check_bundle_authority.ps1 - fail-closed bundleV2 authority gate (#1412).
#
# Validates receipt-authority repository state and both typed authority
# transitions. All current inventory rows remain tracked. ASCII-only for
# Windows PowerShell 5.1 parsing.

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
$authorityHelper = Join-Path $PSScriptRoot '..\tools\ship\bundle-authority.ps1'
$receiptHelper = Join-Path $PSScriptRoot '..\tools\ship\build-receipt.ps1'
$normalizationHelper = Join-Path $PSScriptRoot '..\tools\ship\build-output-normalization.ps1'
foreach ($helper in @($authorityHelper, $receiptHelper, $normalizationHelper)) {
    if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) {
        throw "Bundle-authority dependency is missing: $helper"
    }
    . $helper
}

function Invoke-VtBundleAuthorityGit {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& git -C $Root @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($code -ne 0 -and -not $AllowFailure) {
        throw "git $($Arguments -join ' ') failed ($code): $($lines -join ' | ')"
    }
    return [pscustomobject]@{ ExitCode = $code; Lines = [string[]]$lines }
}

function Convert-VtBundleAuthorityChanges {
    param([string[]]$Lines)

    $changes = @()
    foreach ($line in @($Lines)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = @($line -split "`t")
        if ($parts.Count -lt 2) { continue }
        $status = $parts[0].Substring(0, 1)
        if ($status -eq 'R' -and $parts.Count -ge 3) {
            $changes += [pscustomobject]@{ Status = 'D'; Path = $parts[1].Replace('\', '/') }
            $changes += [pscustomobject]@{ Status = 'A'; Path = $parts[2].Replace('\', '/') }
        }
        elseif ($status -eq 'C' -and $parts.Count -ge 3) {
            $changes += [pscustomobject]@{ Status = 'C'; Path = $parts[2].Replace('\', '/') }
        }
        else {
            $changes += [pscustomobject]@{ Status = $status; Path = $parts[1].Replace('\', '/') }
        }
    }
    return @($changes)
}

function Get-VtBundleAuthorityDiffContext {
    param([Parameter(Mandatory = $true)][string]$Root)

    if ($Staged) {
        $result = Invoke-VtBundleAuthorityGit -Root $Root -Arguments @(
            'diff', '--cached', '--name-status', '--diff-filter=ACMRDT')
        return [pscustomobject]@{
            Mode = 'index'; Base = 'HEAD'; Head = 'INDEX'; Lines = $result.Lines
        }
    }

    $requested = $Range
    if (-not $requested -and $env:GITHUB_BASE_REF) {
        $requested = "origin/$($env:GITHUB_BASE_REF)...HEAD"
    }
    if ($requested) {
        $base = $null
        $head = 'HEAD'
        if ($requested -match '^(.*?)\.\.\.(.*)$') {
            $left = $matches[1]
            if ($matches[2]) { $head = $matches[2] }
            $mergeBase = Invoke-VtBundleAuthorityGit -Root $Root -Arguments @('merge-base', $left, $head)
            if ($mergeBase.Lines.Count -ne 1) { throw "Cannot resolve merge base for '$requested'." }
            $base = ([string]$mergeBase.Lines[0]).Trim()
        }
        elseif ($requested -match '^(.*?)\.\.(.*)$') {
            $base = $matches[1]
            if ($matches[2]) { $head = $matches[2] }
        }
        else {
            $base = "$requested^"
            $head = $requested
        }
        $result = Invoke-VtBundleAuthorityGit -Root $Root -Arguments @(
            'diff', '--name-status', '--diff-filter=ACMRDT', $base, $head)
        return [pscustomobject]@{
            Mode = 'commit'; Base = $base; Head = $head; Lines = $result.Lines
        }
    }

    $dirty = Invoke-VtBundleAuthorityGit -Root $Root -Arguments @(
        'diff', 'HEAD', '--name-status', '--diff-filter=ACMRDT')
    if ($dirty.Lines.Count -gt 0) {
        return [pscustomobject]@{
            Mode = 'worktree'; Base = 'HEAD'; Head = 'WORKTREE'; Lines = $dirty.Lines
        }
    }
    # Even a Git-clean receipt-authority checkout can contain ignored local
    # build output. Keep ordinary local QA on the worktree so that materialized
    # output is compared with the receipt instead of disappearing from view.
    return [pscustomobject]@{
        Mode = 'worktree'; Base = 'HEAD'; Head = 'WORKTREE'; Lines = @()
    }
}

function Read-VtBundleAuthorityContextText {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('Base', 'Head')][string]$Side,
        [Parameter(Mandatory = $true)][string]$RepoPath
    )

    $path = $RepoPath.Replace('\', '/').TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($path) -or $path -match '(^|/)\.\.(/|$)') {
        throw "Invalid bundle-authority context path '$RepoPath'."
    }
    if ($Side -ceq 'Head' -and $Context.Mode -eq 'worktree') {
        $fullPath = Join-Path $Root ($path.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return $null }
        return [System.IO.File]::ReadAllText($fullPath, [System.Text.Encoding]::UTF8)
    }
    $spec = if ($Side -ceq 'Head' -and $Context.Mode -eq 'index') {
        ":$path"
    }
    else {
        $ref = if ($Side -ceq 'Base') { [string]$Context.Base } else { [string]$Context.Head }
        "${ref}:$path"
    }
    $result = Invoke-VtBundleAuthorityGit -Root $Root -Arguments @('show', $spec) -AllowFailure
    if ($result.ExitCode -ne 0) { return $null }
    return ($result.Lines -join "`n")
}

function ConvertFrom-VtBundleAuthorityDataText {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $Text, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw "$Label is not valid PowerShell data: $(@($parseErrors | ForEach-Object { $_.Message }) -join '; ')"
    }
    $rootHash = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.HashtableAst]
    }, $false)
    if ($null -eq $rootHash) { throw "$Label has no root hashtable." }
    try { return $rootHash.SafeGetValue() }
    catch { throw "$Label is not constant PowerShell data: $($_.Exception.Message)" }
}

function Get-VtBundleAuthorityContextInventory {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('Base', 'Head')][string]$Side
    )

    $text = Read-VtBundleAuthorityContextText -Root $Root -Context $Context -Side $Side `
        -RepoPath 'tools/mod-inventory.psd1'
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "$Side bundle-authority context lacks tools/mod-inventory.psd1."
    }
    return ConvertFrom-VtBundleAuthorityDataText -Text $text -Label "$Side bundle-authority inventory"
}

function Get-VtBundleAuthorityContextEntry {
    param(
        [Parameter(Mandatory = $true)]$Inventory,
        [Parameter(Mandatory = $true)][string]$Mod
    )

    $matches = @($Inventory.Mods | Where-Object { [string]$_.Dir -ceq $Mod })
    if ($matches.Count -ne 1) { return $null }
    return $matches[0]
}

function Get-VtBundleAuthorityGlobalIgnoreErrors {
    param(
        [Parameter(Mandatory = $true)]$Inventory,
        [AllowEmptyString()][string]$GitIgnoreText
    )

    $allowedRules = @{}
    foreach ($entry in @($Inventory.Mods)) {
        if ([string]$entry.BundleAuthority -ceq 'receipt') {
            $allowedRules[(Get-VtBundleAuthorityIgnoreRule -Mod ([string]$entry.Dir))] = $true
        }
    }
    $errors = @()
    [string[]]$ignoreLines = ConvertTo-VtBundleAuthorityTextLines -Text $GitIgnoreText
    foreach ($line in $ignoreLines) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#', [System.StringComparison]::Ordinal)) { continue }
        if ($trimmed -match '(?i)(^|/)bundleV2(/|$)' -and -not $allowedRules.ContainsKey($trimmed)) {
            $errors += "bundleV2 ignore rule is not one exact active receipt-authority scope: '$trimmed'"
        }
    }
    return @($errors)
}

function Get-VtBundleAuthorityReceiptOutputSet {
    param(
        [Parameter(Mandatory = $true)]$Receipt,
        [Parameter(Mandatory = $true)][string]$Mod
    )

    $records = @($Receipt.output_files | ForEach-Object {
        [pscustomobject]@{
            Name = [string]$_.filename
            Length = $_.length
            Sha256 = [string]$_.sha256
        }
    })
    return New-VtBundleOutputSet -Records $records `
        -ExpectedDescriptorName "$Mod.mod" `
        -ExpectedRootBundle ([string]$Receipt.root_bundle) `
        -ExpectedDescriptorSha256 ([string]$Receipt.descriptor.sha256)
}

function Get-VtBundleAuthorityContextSourceMap {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('Base', 'Head')][string]$Side,
        [Parameter(Mandatory = $true)][string]$Mod
    )

    if ($Side -ceq 'Head' -and $Context.Mode -eq 'worktree') {
        return Get-VtBuildWorkingSourceMap -RepoRoot $Root -Mod $Mod
    }
    if ($Side -ceq 'Head' -and $Context.Mode -eq 'index') {
        return Get-VtBuildIndexSourceMap -RepoRoot $Root -Mod $Mod
    }
    $commit = if ($Side -ceq 'Base') { [string]$Context.Base } else { [string]$Context.Head }
    return Get-VtBuildCommitSourceMap -RepoRoot $Root -Mod $Mod -Commit $commit
}

function Get-VtBundleAuthorityContextTrackedNames {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('Base', 'Head')][string]$Side,
        [Parameter(Mandatory = $true)][string]$Mod
    )

    if ($Side -ceq 'Head' -and $Context.Mode -in @('worktree', 'index')) {
        $result = Invoke-VtBundleAuthorityGit -Root $Root -Arguments @(
            '-c', 'core.quotepath=false', 'ls-files', '--stage', '--', "$Mod/bundleV2")
        return @($result.Lines)
    }
    $commit = if ($Side -ceq 'Base') { [string]$Context.Base } else { [string]$Context.Head }
    $result = Invoke-VtBundleAuthorityGit -Root $Root -Arguments @(
        '-c', 'core.quotepath=false', 'ls-tree', '-r', $commit, '--', "$Mod/bundleV2")
    return @($result.Lines)
}

function Get-VtBundleAuthorityContextTrackedOutputSet {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('Base', 'Head')][string]$Side,
        [Parameter(Mandatory = $true)][string]$Mod,
        [Parameter(Mandatory = $true)]$Entry,
        [Parameter(Mandatory = $true)]$SourceMap
    )

    $names = @(Get-VtBundleAuthorityContextTrackedNames -Root $Root -Context $Context -Side $Side -Mod $Mod)
    if ($names.Count -eq 0) { return $null }
    if ($Side -ceq 'Head' -and $Context.Mode -eq 'worktree') {
        return Get-VtBuildWorkingOutputSet -RepoRoot $Root -Mod $Mod `
            -SourceMap $SourceMap -InventoryEntry $Entry
    }
    if ($Side -ceq 'Head' -and $Context.Mode -eq 'index') {
        return Get-VtBuildIndexOutputSet -RepoRoot $Root -Mod $Mod `
            -SourceMap $SourceMap -InventoryEntry $Entry
    }
    $commit = if ($Side -ceq 'Base') { [string]$Context.Base } else { [string]$Context.Head }
    return Get-VtBuildCommitOutputSet -RepoRoot $Root -Mod $Mod -Commit $commit `
        -SourceMap $SourceMap -InventoryEntry $Entry
}

function Test-VtBundleAuthorityReceiptContext {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('Base', 'Head')][string]$Side,
        [Parameter(Mandatory = $true)][string]$Mod,
        [Parameter(Mandatory = $true)]$Entry,
        [switch]$UseMaterializedBuild
    )

    $errors = @()
    try {
        $receiptText = Read-VtBundleAuthorityContextText -Root $Root -Context $Context `
            -Side $Side -RepoPath "$Mod/.build-receipt.json"
        if ([string]::IsNullOrWhiteSpace($receiptText)) {
            throw 'receipt authority lacks .build-receipt.json'
        }
        $receipt = ConvertFrom-VtBuildReceiptJson -Json $receiptText
        $receiptOutput = Get-VtBundleAuthorityReceiptOutputSet -Receipt $receipt -Mod $Mod
        if ([string]$receipt.root_bundle -cne [string]$Entry.RootBundle) {
            $errors += "receipt root '$($receipt.root_bundle)' is not inventory RootBundle '$($Entry.RootBundle)'"
        }
        $sourceMap = Get-VtBundleAuthorityContextSourceMap -Root $Root -Context $Context `
            -Side $Side -Mod $Mod
        $policy = New-BuildOutputNormalizationPolicyProof -ModEntry $Entry
        $currentOutput = $receiptOutput
        $materialized = $false
        if ($UseMaterializedBuild -and $Side -ceq 'Head' -and
                $Context.Mode -in @('worktree', 'index')) {
            $bundleDirectory = Join-Path (Join-Path $Root $Mod) 'bundleV2'
            if (Test-Path -LiteralPath $bundleDirectory -PathType Container) {
                $entries = @(Get-ChildItem -LiteralPath $bundleDirectory -Force -ErrorAction Stop)
                if ($entries.Count -gt 0) {
                    $currentOutput = Get-VtBuildWorkingOutputSet -RepoRoot $Root -Mod $Mod `
                        -SourceMap $sourceMap -InventoryEntry $Entry
                    $materialized = $true
                }
            }
        }
        $proof = Test-VtBuildReceiptProof -Receipt $receipt -ExpectedMod $Mod `
            -SourceMap $sourceMap -OutputSet $currentOutput `
            -NormalizationPolicy $policy -MinimumSchema 3
        if (-not $proof.Ok) { $errors += @($proof.Problems) }
        return [pscustomobject][ordered]@{
            Ok = ($errors.Count -eq 0)
            Problems = @($errors)
            Receipt = $receipt
            OutputSet = $receiptOutput
            Proof = $proof
            MaterializedBuild = $materialized
        }
    }
    catch {
        $errors += $_.Exception.Message
        return [pscustomobject][ordered]@{
            Ok = $false
            Problems = @($errors)
            Receipt = $null
            OutputSet = $null
            Proof = [pscustomobject]@{ Ok = $false; Problems = @($errors) }
            MaterializedBuild = $false
        }
    }
}

function Test-VtBundleAuthorityRepository {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Context
    )

    $errors = @()
    $changes = @(Convert-VtBundleAuthorityChanges -Lines $Context.Lines)
    $baseInventory = Get-VtBundleAuthorityContextInventory -Root $Root -Context $Context -Side Base
    $headInventory = Get-VtBundleAuthorityContextInventory -Root $Root -Context $Context -Side Head
    $baseIgnore = Read-VtBundleAuthorityContextText -Root $Root -Context $Context -Side Base -RepoPath '.gitignore'
    $headIgnore = Read-VtBundleAuthorityContextText -Root $Root -Context $Context -Side Head -RepoPath '.gitignore'
    $headReceiptResults = @{}

    $errors += @(Get-VtBundleAuthorityGlobalIgnoreErrors `
        -Inventory $headInventory -GitIgnoreText $headIgnore)

    foreach ($entry in @($headInventory.Mods)) {
        $dir = [string]$entry.Dir
        $entryErrors = @(Get-VtBundleAuthorityEntryErrors -Entry $entry)
        foreach ($message in $entryErrors) { $errors += "${dir}: $message" }
        if ($entryErrors.Count -gt 0) { continue }
        $authority = [string]$entry.BundleAuthority
        $ignoreErrors = @(Get-VtBundleAuthorityIgnoreStateErrors -Mod $dir `
            -Authority $authority -GitIgnoreText $headIgnore)
        foreach ($message in $ignoreErrors) { $errors += "${dir}: $message" }
        if ($authority -ceq 'receipt') {
            $trackedNames = @(Get-VtBundleAuthorityContextTrackedNames -Root $Root `
                -Context $Context -Side Head -Mod $dir)
            if ($trackedNames.Count -gt 0) {
                $errors += "${dir}: receipt authority retains $($trackedNames.Count) tracked bundleV2 output(s)"
            }
            $receiptResult = Test-VtBundleAuthorityReceiptContext -Root $Root `
                -Context $Context -Side Head -Mod $dir -Entry $entry -UseMaterializedBuild
            $headReceiptResults[$dir] = $receiptResult
            foreach ($message in @($receiptResult.Problems)) { $errors += "${dir}: $message" }
        }
    }

    $allDirs = @(@($baseInventory.Mods | ForEach-Object { [string]$_.Dir }) +
        @($headInventory.Mods | ForEach-Object { [string]$_.Dir }) | Sort-Object -Unique)
    foreach ($dir in $allDirs) {
        $baseEntry = Get-VtBundleAuthorityContextEntry -Inventory $baseInventory -Mod $dir
        $headEntry = Get-VtBundleAuthorityContextEntry -Inventory $headInventory -Mod $dir
        if ($null -eq $baseEntry -or $null -eq $headEntry) { continue }
        if ([string]$baseEntry.BundleAuthority -ceq [string]$headEntry.BundleAuthority) { continue }

        $baseSource = Get-VtBundleAuthorityContextSourceMap -Root $Root -Context $Context -Side Base -Mod $dir
        $headSource = Get-VtBundleAuthorityContextSourceMap -Root $Root -Context $Context -Side Head -Mod $dir
        $baseTracked = Get-VtBundleAuthorityContextTrackedOutputSet -Root $Root -Context $Context `
            -Side Base -Mod $dir -Entry $baseEntry -SourceMap $baseSource
        $headTracked = Get-VtBundleAuthorityContextTrackedOutputSet -Root $Root -Context $Context `
            -Side Head -Mod $dir -Entry $headEntry -SourceMap $headSource

        $receiptResult = $null
        if ([string]$headEntry.BundleAuthority -ceq 'receipt') {
            if ($headReceiptResults.ContainsKey($dir)) { $receiptResult = $headReceiptResults[$dir] }
            else {
                $receiptResult = Test-VtBundleAuthorityReceiptContext -Root $Root -Context $Context `
                    -Side Head -Mod $dir -Entry $headEntry -UseMaterializedBuild
            }
        }
        elseif ([string]$baseEntry.BundleAuthority -ceq 'receipt') {
            $receiptResult = Test-VtBundleAuthorityReceiptContext -Root $Root -Context $Context `
                -Side Base -Mod $dir -Entry $baseEntry
        }

        $transition = Test-VtBundleAuthorityTransition -Mod $dir `
            -BaseEntry $baseEntry -HeadEntry $headEntry -Changes $changes `
            -BaseGitIgnoreText $baseIgnore -HeadGitIgnoreText $headIgnore `
            -BaseTrackedOutputSet $baseTracked -HeadTrackedOutputSet $headTracked `
            -ReceiptOutputSet $receiptResult.OutputSet -ReceiptProof $receiptResult.Proof
        foreach ($message in @($transition.Problems)) { $errors += "${dir}: $message" }
    }
    return @($errors)
}

function New-VtBundleAuthorityFixtureOutputSet {
    param([string]$RootSha = ('b' * 64), [string]$DescriptorSha = ('a' * 64))

    return New-VtBundleOutputSet -Records @(
        [pscustomobject]@{ Name = 'aaaaaaaaaaaaaaaa.mod_bundle'; Length = 8L; Sha256 = $RootSha },
        [pscustomobject]@{ Name = 'example_mod.mod'; Length = 4L; Sha256 = $DescriptorSha }
    ) -ExpectedDescriptorName 'example_mod.mod' `
        -ExpectedRootBundle 'aaaaaaaaaaaaaaaa.mod_bundle' `
        -ExpectedDescriptorSha256 $DescriptorSha
}

function Remove-VtBundleAuthorityFixtureTree {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $Path -Recurse -Force -File)) {
        Remove-Item -LiteralPath $file.FullName -Force
    }
    $directories = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -Directory |
        Sort-Object { $_.FullName.Length } -Descending)
    foreach ($directory in $directories) { Remove-Item -LiteralPath $directory.FullName -Force }
    Remove-Item -LiteralPath $Path -Force
}

function Write-VtBundleAuthorityFixtureText {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-VtBundleAuthoritySelfTest {
    $passed = 0
    $tracked = @{ Dir = 'example_mod'; BundleAuthority = 'tracked'; RootBundle = 'aaaaaaaaaaaaaaaa.mod_bundle' }
    $receipt = @{ Dir = 'example_mod'; BundleAuthority = 'receipt'; RootBundle = 'aaaaaaaaaaaaaaaa.mod_bundle' }
    if (@(Get-VtBundleAuthorityEntryErrors -Entry $tracked).Count -ne 0 -or
            @(Get-VtBundleAuthorityEntryErrors -Entry $receipt).Count -ne 0) {
        throw 'supported exact authority modes were rejected'
    }
    foreach ($bad in @(
        @{ Dir = 'example_mod'; RootBundle = 'aaaaaaaaaaaaaaaa.mod_bundle' },
        @{ Dir = 'example_mod'; BundleAuthority = 'generated'; RootBundle = 'aaaaaaaaaaaaaaaa.mod_bundle' },
        @{ Dir = 'example_mod'; BundleAuthority = 'Receipt'; RootBundle = 'aaaaaaaaaaaaaaaa.mod_bundle' }
    )) {
        if (@(Get-VtBundleAuthorityEntryErrors -Entry $bad).Count -eq 0) {
            throw 'missing, unsupported, or non-exact authority was accepted'
        }
    }
    $passed++

    $trackedPolicy = Get-VtBundleAuthorityDownstreamPolicy -Entry $tracked
    $receiptPolicy = Get-VtBundleAuthorityDownstreamPolicy -Entry $receipt
    if (-not $trackedPolicy.Publish -or -not $trackedPolicy.Deploy -or
            $receiptPolicy.Publish -or $receiptPolicy.Deploy -or
            -not $receiptPolicy.Build -or -not $receiptPolicy.Receipt) {
        throw 'downstream authority policy did not preserve tracked or disable receipt publication'
    }
    $receiptShipRejected = $false
    try { Assert-VtBundleAuthorityShipPreflight -Entry $receipt | Out-Null }
    catch { $receiptShipRejected = $_.Exception.Message -match 'disabled' }
    if (-not $receiptShipRejected) { throw 'receipt-authority ship was not rejected' }
    Assert-VtBundleAuthorityShipPreflight -Entry $receipt -BuildOnly | Out-Null
    $passed++

    $ignoreInventory = @{ Mods = @($tracked, $receipt) }
    $validIgnoreErrors = @(Get-VtBundleAuthorityGlobalIgnoreErrors `
        -Inventory $ignoreInventory -GitIgnoreText "/example_mod/bundleV2/`n")
    $broadIgnoreErrors = @(Get-VtBundleAuthorityGlobalIgnoreErrors `
        -Inventory $ignoreInventory -GitIgnoreText "**/bundleV2/`n/example_mod/bundleV2/`n")
    if ($validIgnoreErrors.Count -ne 0 -or $broadIgnoreErrors.Count -ne 1) {
        throw "global bundleV2 ignore scope was not enforced exactly (valid=$($validIgnoreErrors.Count), broad=$($broadIgnoreErrors.Count), errors=$($broadIgnoreErrors -join ' | '))"
    }
    $passed++

    $output = New-VtBundleAuthorityFixtureOutputSet
    $proof = [pscustomobject]@{ Ok = $true; Problems = @() }
    $baseIgnore = "# fixture`n"
    $headIgnore = "# fixture`n/example_mod/bundleV2/`n"
    $changes = @(
        [pscustomobject]@{ Status = 'M'; Path = 'tools/mod-inventory.psd1' },
        [pscustomobject]@{ Status = 'M'; Path = '.gitignore' },
        [pscustomobject]@{ Status = 'D'; Path = 'example_mod/bundleV2/aaaaaaaaaaaaaaaa.mod_bundle' },
        [pscustomobject]@{ Status = 'D'; Path = 'example_mod/bundleV2/example_mod.mod' }
    )
    $forward = Test-VtBundleAuthorityTransition -Mod example_mod `
        -BaseEntry $tracked -HeadEntry $receipt -Changes $changes `
        -BaseGitIgnoreText $baseIgnore -HeadGitIgnoreText $headIgnore `
        -BaseTrackedOutputSet $output -ReceiptOutputSet $output -ReceiptProof $proof
    if (-not $forward.Ok -or $forward.Direction -cne 'tracked-to-receipt') {
        throw "valid tracked-to-receipt transition failed: $($forward.Problems -join '; ')"
    }
    $passed++

    $inverseChanges = @(
        [pscustomobject]@{ Status = 'M'; Path = 'tools/mod-inventory.psd1' },
        [pscustomobject]@{ Status = 'M'; Path = '.gitignore' },
        [pscustomobject]@{ Status = 'A'; Path = 'example_mod/bundleV2/aaaaaaaaaaaaaaaa.mod_bundle' },
        [pscustomobject]@{ Status = 'A'; Path = 'example_mod/bundleV2/example_mod.mod' }
    )
    $inverse = Test-VtBundleAuthorityTransition -Mod example_mod `
        -BaseEntry $receipt -HeadEntry $tracked -Changes $inverseChanges `
        -BaseGitIgnoreText $headIgnore -HeadGitIgnoreText $baseIgnore `
        -HeadTrackedOutputSet $output -ReceiptOutputSet $output -ReceiptProof $proof
    if (-not $inverse.Ok -or $inverse.Direction -cne 'receipt-to-tracked') {
        throw "valid receipt-to-tracked transition failed: $($inverse.Problems -join '; ')"
    }
    $passed++

    $adversaries = @(
        @{ Name = 'schema-or-receipt-proof'; Args = @{ Changes=$changes; BaseGitIgnoreText=$baseIgnore; HeadGitIgnoreText=$headIgnore; BaseTrackedOutputSet=$output; ReceiptOutputSet=$output; ReceiptProof=[pscustomobject]@{ Ok=$false; Problems=@('schema 2 / source / policy / builder drift') } } },
        @{ Name = 'tracked-leftovers'; Args = @{ Changes=$changes; BaseGitIgnoreText=$baseIgnore; HeadGitIgnoreText=$headIgnore; BaseTrackedOutputSet=$output; HeadTrackedOutputSet=$output; ReceiptOutputSet=$output; ReceiptProof=$proof } },
        @{ Name = 'missing-scoped-ignore'; Args = @{ Changes=$changes; BaseGitIgnoreText=$baseIgnore; HeadGitIgnoreText=$baseIgnore; BaseTrackedOutputSet=$output; ReceiptOutputSet=$output; ReceiptProof=$proof } },
        @{ Name = 'overbroad-ignore-edit'; Args = @{ Changes=$changes; BaseGitIgnoreText=$baseIgnore; HeadGitIgnoreText="# changed`n/example_mod/bundleV2/`n"; BaseTrackedOutputSet=$output; ReceiptOutputSet=$output; ReceiptProof=$proof } },
        @{ Name = 'partial-deletion'; Args = @{ Changes=@($changes | Where-Object { $_.Path -cne 'example_mod/bundleV2/example_mod.mod' }); BaseGitIgnoreText=$baseIgnore; HeadGitIgnoreText=$headIgnore; BaseTrackedOutputSet=$output; ReceiptOutputSet=$output; ReceiptProof=$proof } },
        @{ Name = 'unrelated-output-deletion'; Args = @{ Changes=@($changes + [pscustomobject]@{ Status='D'; Path='example_mod/bundleV2/bbbbbbbbbbbbbbbb.mod_bundle' }); BaseGitIgnoreText=$baseIgnore; HeadGitIgnoreText=$headIgnore; BaseTrackedOutputSet=$output; ReceiptOutputSet=$output; ReceiptProof=$proof } },
        @{ Name = 'index-or-commit-split'; Args = @{ Changes=@($changes | Where-Object { $_.Path -cne '.gitignore' }); BaseGitIgnoreText=$baseIgnore; HeadGitIgnoreText=$headIgnore; BaseTrackedOutputSet=$output; ReceiptOutputSet=$output; ReceiptProof=$proof } },
        @{ Name = 'missing-prior-map'; Args = @{ Changes=$changes; BaseGitIgnoreText=$baseIgnore; HeadGitIgnoreText=$headIgnore; ReceiptOutputSet=$output; ReceiptProof=$proof } }
    )
    foreach ($case in $adversaries) {
        $arguments = @{
            Mod = 'example_mod'
            BaseEntry = $tracked
            HeadEntry = $receipt
        }
        foreach ($key in $case.Args.Keys) { $arguments[$key] = $case.Args[$key] }
        $result = Test-VtBundleAuthorityTransition @arguments
        if ($result.Ok) { throw "authority adversary '$($case.Name)' was accepted" }
        $passed++
    }

    $mutatedOutput = New-VtBundleAuthorityFixtureOutputSet -RootSha ('c' * 64)
    $changedReceipt = Test-VtBundleAuthorityTransition -Mod example_mod `
        -BaseEntry $tracked -HeadEntry $receipt -Changes $changes `
        -BaseGitIgnoreText $baseIgnore -HeadGitIgnoreText $headIgnore `
        -BaseTrackedOutputSet $output -ReceiptOutputSet $mutatedOutput -ReceiptProof $proof
    if ($changedReceipt.Ok -or ($changedReceipt.Problems -join '; ') -notmatch 'fingerprint|root') {
        throw 'same-shape wrong-content receipt output was accepted'
    }
    $passed++

    $badInverse = Test-VtBundleAuthorityTransition -Mod example_mod `
        -BaseEntry $receipt -HeadEntry $tracked -Changes $inverseChanges `
        -BaseGitIgnoreText $headIgnore -HeadGitIgnoreText $baseIgnore `
        -HeadTrackedOutputSet $mutatedOutput -ReceiptOutputSet $output -ReceiptProof $proof
    if ($badInverse.Ok) { throw 'receipt-to-tracked downgrade accepted non-exact restoration' }
    $passed++

    $caseCollisionRejected = $false
    try {
        New-VtBundleOutputSet -Records @(
            [pscustomobject]@{ Name='example_mod.mod'; Length=1L; Sha256=('a' * 64) },
            [pscustomobject]@{ Name='aaaaaaaaaaaaaaaa.mod_bundle'; Length=1L; Sha256=('b' * 64) },
            [pscustomobject]@{ Name='AAAAAAAAAAAAAAAA.mod_bundle'; Length=1L; Sha256=('c' * 64) }
        ) -ExpectedDescriptorName 'example_mod.mod' `
            -ExpectedRootBundle 'aaaaaaaaaaaaaaaa.mod_bundle' | Out-Null
    }
    catch { $caseCollisionRejected = $_.Exception.Message -match 'case-colliding' }
    if (-not $caseCollisionRejected) { throw 'case-colliding receipt output names were accepted' }
    $passed++

    # Exercise the real worktree/index/commit adapters. This catches a split
    # staged transition that pure models cannot, and proves ignored local build
    # output remains visible to ordinary Git-clean QA.
    $fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
        ('vt2-bundle-authority-' + [guid]::NewGuid().ToString('N'))
    try {
        $toolsDir = Join-Path $fixtureRoot 'tools'
        $modDir = Join-Path $fixtureRoot 'example_mod'
        $scriptDir = Join-Path $modDir 'scripts'
        $bundleDir = Join-Path $modDir 'bundleV2'
        New-Item -ItemType Directory -Path $toolsDir, $scriptDir, $bundleDir | Out-Null
        $inventoryPath = Join-Path $toolsDir 'mod-inventory.psd1'
        $ignorePath = Join-Path $fixtureRoot '.gitignore'
        $attributesPath = Join-Path $fixtureRoot '.gitattributes'
        $descriptorSourcePath = Join-Path $modDir 'example_mod.mod'
        $descriptorOutputPath = Join-Path $bundleDir 'example_mod.mod'
        $rootOutputPath = Join-Path $bundleDir 'aaaaaaaaaaaaaaaa.mod_bundle'
        $sourcePath = Join-Path $scriptDir 'main.lua'
        $trackedInventoryText = "@{ Mods = @(@{ Dir='example_mod'; BundleAuthority='tracked'; RootBundle='aaaaaaaaaaaaaaaa.mod_bundle'; BuildArtifactExclusions=@() }) }`n"
        $receiptInventoryText = $trackedInventoryText.Replace("'tracked'", "'receipt'")
        Write-VtBundleAuthorityFixtureText -Path $inventoryPath -Text $trackedInventoryText
        Write-VtBundleAuthorityFixtureText -Path $ignorePath -Text "# fixture`n"
        Write-VtBundleAuthorityFixtureText -Path $attributesPath -Text "* text eol=lf`n"
        Write-VtBundleAuthorityFixtureText -Path $descriptorSourcePath -Text "descriptor-v1`n"
        Write-VtBundleAuthorityFixtureText -Path $descriptorOutputPath -Text "descriptor-v1`n"
        Write-VtBundleAuthorityFixtureText -Path $rootOutputPath -Text "root-v1`n"
        Write-VtBundleAuthorityFixtureText -Path $sourcePath -Text "return 'v1'`n"
        Invoke-VtBundleAuthorityGit -Root $fixtureRoot -Arguments @('init', '--quiet') | Out-Null
        Invoke-VtBundleAuthorityGit -Root $fixtureRoot -Arguments @('config', 'user.email', 'fixture@example.invalid') | Out-Null
        Invoke-VtBundleAuthorityGit -Root $fixtureRoot -Arguments @('config', 'user.name', 'Bundle Authority Fixture') | Out-Null
        Invoke-VtBundleAuthorityGit -Root $fixtureRoot -Arguments @('add', '.') | Out-Null
        Invoke-VtBundleAuthorityGit -Root $fixtureRoot -Arguments @('commit', '--quiet', '-m', 'fixture base') | Out-Null

        $fixtureEntry = (Import-PowerShellDataFile -Path $inventoryPath).Mods[0]
        $fixtureSource = Get-VtBuildWorkingSourceMap -RepoRoot $fixtureRoot -Mod example_mod
        $fixtureOutput = Get-VtBuildWorkingOutputSet -RepoRoot $fixtureRoot -Mod example_mod `
            -SourceMap $fixtureSource -InventoryEntry $fixtureEntry
        $fixturePolicy = New-BuildOutputNormalizationPolicyProof -ModEntry $fixtureEntry
        $fixtureReceipt = New-VtBuildReceipt -Mod example_mod -SourceMap $fixtureSource `
            -OutputSet $fixtureOutput -BuilderVersion '9.8.7-authority-fixture' `
            -NormalizationPolicy $fixturePolicy
        Write-VtBuildReceipt -RepoRoot $fixtureRoot -Mod example_mod -Receipt $fixtureReceipt | Out-Null
        Invoke-VtBundleAuthorityGit -Root $fixtureRoot -Arguments @('add', 'example_mod/.build-receipt.json') | Out-Null
        Invoke-VtBundleAuthorityGit -Root $fixtureRoot -Arguments @('commit', '--quiet', '-m', 'tracked receipt base') | Out-Null

        $descriptorBytes = [System.IO.File]::ReadAllBytes($descriptorOutputPath)
        $rootBytes = [System.IO.File]::ReadAllBytes($rootOutputPath)
        Write-VtBundleAuthorityFixtureText -Path $inventoryPath -Text $receiptInventoryText
        Write-VtBundleAuthorityFixtureText -Path $ignorePath `
            -Text "# fixture`n/example_mod/bundleV2/`n"
        Invoke-VtBundleAuthorityGit -Root $fixtureRoot -Arguments @(
            'rm', '--quiet', 'example_mod/bundleV2/example_mod.mod',
            'example_mod/bundleV2/aaaaaaaaaaaaaaaa.mod_bundle') | Out-Null
        if (-not (Test-Path -LiteralPath $bundleDir -PathType Container)) {
            New-Item -ItemType Directory -Path $bundleDir | Out-Null
        }
        [System.IO.File]::WriteAllBytes($descriptorOutputPath, $descriptorBytes)
        [System.IO.File]::WriteAllBytes($rootOutputPath, $rootBytes)
        Invoke-VtBundleAuthorityGit -Root $fixtureRoot -Arguments @(
            'add', 'tools/mod-inventory.psd1', '.gitignore') | Out-Null
        $forwardLines = (Invoke-VtBundleAuthorityGit -Root $fixtureRoot -Arguments @(
            'diff', '--cached', '--name-status', '--diff-filter=ACMRDT')).Lines
        $forwardContext = [pscustomobject]@{
            Mode='index'; Base='HEAD'; Head='INDEX'; Lines=$forwardLines
        }
        $forwardErrors = @(Test-VtBundleAuthorityRepository -Root $fixtureRoot -Context $forwardContext)
        if ($forwardErrors.Count -ne 0) {
            throw "real staged tracked-to-receipt transition failed: $($forwardErrors -join '; ')"
        }
        [System.IO.File]::WriteAllBytes($rootOutputPath,
            [System.Text.Encoding]::UTF8.GetBytes("root-staged-drift`n"))
        $stagedMaterializedErrors = @(
            Test-VtBundleAuthorityRepository -Root $fixtureRoot -Context $forwardContext)
        if (($stagedMaterializedErrors -join '; ') -notmatch 'output|root') {
            throw 'staged receipt authority ignored a changed materialized build'
        }
        [System.IO.File]::WriteAllBytes($rootOutputPath, $rootBytes)
        $restoredForwardErrors = @(
            Test-VtBundleAuthorityRepository -Root $fixtureRoot -Context $forwardContext)
        if ($restoredForwardErrors.Count -ne 0) {
            throw "restored staged tracked-to-receipt transition failed: $($restoredForwardErrors -join '; ')"
        }
        Invoke-VtBundleAuthorityGit -Root $fixtureRoot -Arguments @(
            'commit', '--quiet', '-m', 'receipt authority') | Out-Null
        $passed++

        $steadyContext = [pscustomobject]@{
            Mode='worktree'; Base='HEAD'; Head='WORKTREE'; Lines=@()
        }
        $steadyErrors = @(Test-VtBundleAuthorityRepository -Root $fixtureRoot -Context $steadyContext)
        if ($steadyErrors.Count -ne 0) {
            throw "Git-clean receipt authority rejected its exact materialized build: $($steadyErrors -join '; ')"
        }
        [System.IO.File]::WriteAllBytes($rootOutputPath,
            [System.Text.Encoding]::UTF8.GetBytes("root-v2`n"))
        $mutatedErrors = @(Test-VtBundleAuthorityRepository -Root $fixtureRoot -Context $steadyContext)
        if (($mutatedErrors -join '; ') -notmatch 'output|root') {
            throw 'Git-clean receipt authority ignored a changed materialized build'
        }
        [System.IO.File]::WriteAllBytes($rootOutputPath, $rootBytes)
        $passed++

        Write-VtBundleAuthorityFixtureText -Path $inventoryPath -Text $trackedInventoryText
        Write-VtBundleAuthorityFixtureText -Path $ignorePath -Text "# fixture`n"
        Invoke-VtBundleAuthorityGit -Root $fixtureRoot -Arguments @(
            'add', 'tools/mod-inventory.psd1') | Out-Null
        $splitLines = (Invoke-VtBundleAuthorityGit -Root $fixtureRoot -Arguments @(
            'diff', '--cached', '--name-status', '--diff-filter=ACMRDT')).Lines
        $splitContext = [pscustomobject]@{
            Mode='index'; Base='HEAD'; Head='INDEX'; Lines=$splitLines
        }
        $splitErrors = @(Test-VtBundleAuthorityRepository -Root $fixtureRoot -Context $splitContext)
        if ($splitErrors.Count -eq 0) { throw 'index-split receipt-to-tracked transition was accepted' }

        Invoke-VtBundleAuthorityGit -Root $fixtureRoot -Arguments @('add', '.gitignore') | Out-Null
        Invoke-VtBundleAuthorityGit -Root $fixtureRoot -Arguments @(
            'add', '-f', 'example_mod/bundleV2/example_mod.mod',
            'example_mod/bundleV2/aaaaaaaaaaaaaaaa.mod_bundle') | Out-Null
        $inverseLines = (Invoke-VtBundleAuthorityGit -Root $fixtureRoot -Arguments @(
            'diff', '--cached', '--name-status', '--diff-filter=ACMRDT')).Lines
        $inverseContext = [pscustomobject]@{
            Mode='index'; Base='HEAD'; Head='INDEX'; Lines=$inverseLines
        }
        $inverseErrors = @(Test-VtBundleAuthorityRepository -Root $fixtureRoot -Context $inverseContext)
        if ($inverseErrors.Count -ne 0) {
            throw "real staged receipt-to-tracked transition failed: $($inverseErrors -join '; ')"
        }
        $passed++
    }
    finally {
        Remove-VtBundleAuthorityFixtureTree -Path $fixtureRoot
    }

    Write-Host "[check_bundle_authority -SelfTest] PASS $passed authority fixtures" -ForegroundColor Green
    return 0
}

if ($SelfTest) { exit (Invoke-VtBundleAuthoritySelfTest) }

try {
    $root = (Resolve-Path -LiteralPath $RepoRoot).Path
    $context = Get-VtBundleAuthorityDiffContext -Root $root
    $errors = @(Test-VtBundleAuthorityRepository -Root $root -Context $context)
    if ($errors.Count -gt 0) {
        Write-Host '[check_bundle_authority] ERRORS - bundle authority is incomplete or unsafe (#1412):' -ForegroundColor Red
        foreach ($message in $errors) { Write-Host "  X $message" -ForegroundColor Red }
        exit 2
    }
    if (-not $Quiet) {
        Write-Host '[check_bundle_authority] OK - exact tracked/receipt authority and typed transitions are coherent.' -ForegroundColor Green
    }
    exit 0
}
catch {
    Write-Host "[check_bundle_authority] INFRASTRUCTURE ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 99
}
