# check_build_receipts.ps1 - staged/committed BuildOnly receipt gate (#1278, #1400).
#
# The gate validates only mods implicated by the selected diff (or -Mod). A mod
# enters the receipt contract when its runtime source, any normalized bundleV2
# output, or its receipt changes. Historical schema-2 receipts remain valid for
# global-only revalidation; every new BuildOnly receipt binds schema-3 output.
#
# Exit codes: 0 = valid/not applicable, 2 = missing or mismatched receipt.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$Range,
    [switch]$Staged,
    [string]$Mod,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }
$helperPath = Join-Path $PSScriptRoot '..\tools\ship\build-receipt.ps1'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    throw "Build receipt helpers are missing: $helperPath"
}
. $helperPath
$normalizationHelperPath = Join-Path $PSScriptRoot '..\tools\ship\build-output-normalization.ps1'
if (-not (Test-Path -LiteralPath $normalizationHelperPath -PathType Leaf)) {
    throw "Build-output normalization helpers are missing: $normalizationHelperPath"
}
. $normalizationHelperPath
$script:VtBuildReceiptGlobalPolicyPaths = @(
    '.gitattributes',
    'tools/mod-inventory.psd1',
    'tools/ship/bundle-authority.ps1',
    'tools/ship/build-output-normalization.ps1',
    'tools/ship/build-receipt.ps1',
    'tools/ship/bundle-output-set.ps1',
    'qa/check_bundle_authority.ps1',
    'qa/check_build_receipts.ps1'
)

function Get-VtBuildReceiptDiffContext {
    param([Parameter(Mandatory = $true)][string]$Root)

    if ($Staged) {
        $lines = Invoke-VtBuildGitCapture -RepoRoot $Root -Arguments @(
            'diff', '--cached', '--name-status', '--diff-filter=ACMRDT')
        return [pscustomobject]@{ Mode = 'index'; Head = 'INDEX'; Lines = @($lines) }
    }

    # The canonical BuildOnly post-build call passes -Mod without a range. It
    # must validate the just-written working-tree receipt even when source and
    # root rebuilt byte-identically and the new receipt is the only untracked
    # path (which ordinary `git diff HEAD` cannot see).
    if ($Mod -and -not $Range) {
        $lines = Invoke-VtBuildGitCapture -RepoRoot $Root -Arguments @(
            'diff', 'HEAD', '--name-status', '--diff-filter=ACMRDT')
        return [pscustomobject]@{ Mode = 'worktree'; Head = 'WORKTREE'; Lines = @($lines) }
    }

    $requestedRange = $Range
    if (-not $requestedRange -and $env:GITHUB_BASE_REF) {
        $requestedRange = "origin/$($env:GITHUB_BASE_REF)...HEAD"
    }
    if ($requestedRange) {
        $head = 'HEAD'
        if ($requestedRange -match '^.*?\.\.\.(.*)$' -and $matches[1]) { $head = $matches[1] }
        elseif ($requestedRange -match '^.*?\.\.(.*)$' -and $matches[1]) { $head = $matches[1] }
        $lines = Invoke-VtBuildGitCapture -RepoRoot $Root -Arguments @(
            'diff', '--name-status', '--diff-filter=ACMRDT', $requestedRange)
        return [pscustomobject]@{ Mode = 'commit'; Head = $head; Lines = @($lines) }
    }

    $dirty = Invoke-VtBuildGitCapture -RepoRoot $Root -Arguments @(
        'diff', 'HEAD', '--name-status', '--diff-filter=ACMRDT')
    # Ordinary local QA must not silently choose a committed context when an
    # untracked or ignored compiler-visible input exists. BuildOnly passes -Mod
    # and is already explicit; this closes the same gap for generic run_all.
    $inventoryPath = Join-Path $Root 'tools\mod-inventory.psd1'
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        throw "Build receipt inventory is missing: $inventoryPath"
    }
    $activeModPaths = [string[]]@((Import-PowerShellDataFile -Path $inventoryPath).Mods |
        ForEach-Object { [string]$_.Dir })
    $receiptScopePaths = @($activeModPaths) + @($script:VtBuildReceiptGlobalPolicyPaths)
    $untrackedArgs = @('-c', 'core.quotepath=false', 'ls-files', '--others',
        '--exclude-standard', '--') + @($receiptScopePaths)
    $ignoredArgs = @('-c', 'core.quotepath=false', 'ls-files', '--others', '--ignored',
        '--exclude-standard', '--') + @($receiptScopePaths)
    $untracked = Invoke-VtBuildGitCapture -RepoRoot $Root -Arguments $untrackedArgs
    $ignored = Invoke-VtBuildGitCapture -RepoRoot $Root -Arguments $ignoredArgs
    $workingLines = @($dirty)
    $workingLines += @($untracked | ForEach-Object { "A`t$_" })
    $workingLines += @($ignored | ForEach-Object { "A`t$_" })
    if ($workingLines.Count -gt 0) {
        return [pscustomobject]@{ Mode = 'worktree'; Head = 'WORKTREE'; Lines = @($workingLines) }
    }
    $recent = Invoke-VtBuildGitCapture -RepoRoot $Root -Arguments @(
        'diff', 'HEAD~1..HEAD', '--name-status', '--diff-filter=ACMRDT')
    return [pscustomobject]@{ Mode = 'commit'; Head = 'HEAD'; Lines = @($recent) }
}

function Convert-VtBuildReceiptChanges {
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
            # A copy keeps its source and adds its destination. Bind the new
            # path; parsing only field 2 silently loses cross-mod bundle copies.
            $changes += [pscustomobject]@{ Status = 'C'; Path = $parts[2].Replace('\', '/') }
        }
        else {
            $changes += [pscustomobject]@{ Status = $status; Path = $parts[1].Replace('\', '/') }
        }
    }
    return @($changes)
}

function Get-VtBuildReceiptTargets {
    param(
        [object[]]$Inventory,
        [object[]]$Changes,
        [string]$ExplicitMod,
        [string[]]$ReceiptBearingMods = @()
    )

    $targets = @{}
    $addTarget = {
        param([string]$ModName, [string]$Reason, [int]$MinimumSchema)
        if ([string]::IsNullOrWhiteSpace($ModName)) { return }
        if (-not $targets.ContainsKey($ModName)) {
            $targets[$ModName] = @{ MinimumSchema = 2; Reasons = @{} }
        }
        $target = $targets[$ModName]
        if ($MinimumSchema -gt [int]$target.MinimumSchema) {
            $target.MinimumSchema = $MinimumSchema
        }
        if (-not [string]::IsNullOrWhiteSpace($Reason)) { $target.Reasons[$Reason] = $true }
    }
    if ($ExplicitMod) {
        & $addTarget $ExplicitMod 'explicit BuildOnly target' 3
    }

    foreach ($change in @($Changes | Where-Object {
                $script:VtBuildReceiptGlobalPolicyPaths -ccontains $_.Path
            })) {
        foreach ($receiptBearingMod in @($ReceiptBearingMods)) {
            & $addTarget $receiptBearingMod "global receipt policy changed: $($change.Path)" 2
        }
    }
    foreach ($entry in $Inventory) {
        $dir = [string]$entry.Dir
        $prefix = "$dir/"
        $receiptPath = "$dir/$script:VtBuildReceiptFileName"
        foreach ($change in $Changes) {
            if (-not $change.Path.StartsWith($prefix, [System.StringComparison]::Ordinal)) { continue }
            $relative = $change.Path.Substring($prefix.Length)
            $statusAndPath = "$($change.Status) $($change.Path)"
            if ($change.Path -ceq $receiptPath) {
                & $addTarget $dir "receipt changed: $statusAndPath" 3
            }
            elseif ($relative.StartsWith('bundleV2/', [System.StringComparison]::Ordinal)) {
                & $addTarget $dir "bundle output changed: $statusAndPath" 3
            }
            elseif (Test-VtBuildReceiptRelevantPath -RelativePath $relative) {
                & $addTarget $dir "runtime source changed: $statusAndPath" 3
            }
        }
    }
    return @($targets.Keys | Sort-Object | ForEach-Object {
        $target = $targets[$_]
        [pscustomobject][ordered]@{
            Mod = $_
            Reasons = [string[]]@($target.Reasons.Keys | Sort-Object)
            MinimumSchema = [int]$target.MinimumSchema
        }
    })
}

function Read-VtBuildReceiptContextFileText {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$RepoPath
    )

    $repoPath = $RepoPath.Replace('\', '/').TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($repoPath) -or $repoPath -match '(^|/)\.\.(/|$)') {
        throw "Build receipt context path is invalid: '$RepoPath'."
    }
    if ($Context.Mode -eq 'worktree') {
        $path = Join-Path $Root ($repoPath.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
        return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    }
    $spec = if ($Context.Mode -eq 'index') { ":$repoPath" } else { "$($Context.Head):$repoPath" }
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& git -C $Root show $spec 2>$null | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -ne 0) { return $null }
    return ($lines -join "`n")
}

function Read-VtBuildReceiptContextText {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$ModName
    )
    return Read-VtBuildReceiptContextFileText -Root $Root -Context $Context `
        -RepoPath "$ModName/$script:VtBuildReceiptFileName"
}

function ConvertFrom-VtBuildReceiptDataText {
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

function Get-VtBuildReceiptContextInventoryEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$ModName
    )

    $text = Read-VtBuildReceiptContextFileText -Root $Root -Context $Context `
        -RepoPath 'tools/mod-inventory.psd1'
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw 'Build receipt context has no tools/mod-inventory.psd1.'
    }
    $inventory = ConvertFrom-VtBuildReceiptDataText -Text $text -Label 'Build receipt inventory'
    $entries = @($inventory.Mods | Where-Object { [string]$_.Dir -ceq $ModName })
    if ($entries.Count -ne 1) {
        throw "Build receipt context could not resolve exactly one inventory entry for '$ModName'."
    }
    Assert-VtBuildReceiptInventoryEntry -Entry $entries[0] -Mod $ModName
    return $entries[0]
}

function Get-VtBuildReceiptNormalizationPolicyForEntry {
    param([Parameter(Mandatory = $true)]$InventoryEntry)

    $constructor = Get-Command 'New-BuildOutputNormalizationPolicyProof' -ErrorAction Stop
    if ($constructor.Parameters.ContainsKey('ModEntry')) {
        return New-BuildOutputNormalizationPolicyProof -ModEntry $InventoryEntry
    }
    $exclusions = @($InventoryEntry.BuildArtifactExclusions | Where-Object { $null -ne $_ })
    return New-BuildOutputNormalizationPolicyProof -Exclusions $exclusions
}

function Test-VtBuildReceiptContext {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$ModName,
        [ValidateSet(2, 3)][int]$MinimumSchema = 2,
        [string]$ExpectedBuilderVersion
    )

    $errors = @()
    try {
        $receiptText = Read-VtBuildReceiptContextText -Root $Root -Context $Context -ModName $ModName
        if ([string]::IsNullOrWhiteSpace($receiptText)) {
            return @("${ModName}: missing $script:VtBuildReceiptFileName; rerun ship.ps1 -Mod $ModName -BuildOnly")
        }
        $receipt = ConvertFrom-VtBuildReceiptJson -Json $receiptText
        if ($Context.Mode -eq 'worktree') {
            $sourceMap = Get-VtBuildWorkingSourceMap -RepoRoot $Root -Mod $ModName
        }
        elseif ($Context.Mode -eq 'index') {
            $sourceMap = Get-VtBuildIndexSourceMap -RepoRoot $Root -Mod $ModName
        }
        else {
            $sourceMap = Get-VtBuildCommitSourceMap -RepoRoot $Root -Mod $ModName -Commit $Context.Head
        }
        $schema = if ([string]$receipt.schema -match '^\d+$') { [int]$receipt.schema } else { 0 }
        $proofArguments = @{
            Receipt = $receipt
            ExpectedMod = $ModName
            SourceMap = $sourceMap
            MinimumSchema = $MinimumSchema
        }
        if ($schema -ge 3) {
            # Schema 3 binds the policy and bundle inventory from the same Git
            # authority as the source/output proof. Schema 2 intentionally
            # retains its historical root-only validation path.
            $inventoryEntry = Get-VtBuildReceiptContextInventoryEntry `
                -Root $Root -Context $Context -ModName $ModName
            $authority = Assert-VtBundleAuthorityEntry -Entry $inventoryEntry
            if ($authority -ceq 'receipt' -and $MinimumSchema -lt 3) {
                $proofArguments.MinimumSchema = 3
            }
            $normalizationPolicy = Get-VtBuildReceiptNormalizationPolicyForEntry `
                -InventoryEntry $inventoryEntry
            if ($authority -ceq 'receipt') {
                # A receipt-authority commit intentionally has no Git-tracked
                # generated outputs. Validate the complete schema-3 map from
                # the receipt itself, and compare a materialized local build
                # whenever one is present in the working tree.
                $outputSet = Get-VtBuildReceiptDeclaredOutputSet `
                    -Receipt $receipt -ExpectedMod $ModName
                if ($Context.Mode -eq 'worktree') {
                    $bundleDirectory = Join-Path (Join-Path $Root $ModName) 'bundleV2'
                    if (Test-Path -LiteralPath $bundleDirectory -PathType Container) {
                        $materializedEntries = @(Get-ChildItem -LiteralPath $bundleDirectory -Force)
                        if ($materializedEntries.Count -gt 0) {
                            $outputSet = Get-VtBuildWorkingOutputSet -RepoRoot $Root -Mod $ModName `
                                -SourceMap $sourceMap -InventoryEntry $inventoryEntry
                        }
                    }
                }
            }
            elseif ($Context.Mode -eq 'worktree') {
                $outputSet = Get-VtBuildWorkingOutputSet -RepoRoot $Root -Mod $ModName `
                    -SourceMap $sourceMap -InventoryEntry $inventoryEntry
            }
            elseif ($Context.Mode -eq 'index') {
                $outputSet = Get-VtBuildIndexOutputSet -RepoRoot $Root -Mod $ModName `
                    -SourceMap $sourceMap -InventoryEntry $inventoryEntry
            }
            else {
                $outputSet = Get-VtBuildCommitOutputSet -RepoRoot $Root -Mod $ModName `
                    -Commit $Context.Head -SourceMap $sourceMap -InventoryEntry $inventoryEntry
            }
            $proofArguments.OutputSet = $outputSet
            $proofArguments.NormalizationPolicy = $normalizationPolicy
            if (-not [string]::IsNullOrWhiteSpace($ExpectedBuilderVersion)) {
                $proofArguments.ExpectedBuilderVersion = $ExpectedBuilderVersion
            }
        }
        else {
            if ($Context.Mode -eq 'worktree') {
                $rootProof = Get-VtBuildWorkingRootProof -RepoRoot $Root -Mod $ModName
            }
            elseif ($Context.Mode -eq 'index') {
                $rootProof = Get-VtBuildIndexRootProof -RepoRoot $Root -Mod $ModName
            }
            else {
                $rootProof = Get-VtBuildCommitRootProof -RepoRoot $Root -Mod $ModName -Commit $Context.Head
            }
            $proofArguments.RootProof = $rootProof
        }
        $result = Test-VtBuildReceiptProof @proofArguments
        if (-not $result.Ok) {
            foreach ($problem in $result.Problems) { $errors += "${ModName}: $problem" }
        }
    }
    catch {
        $errors += "${ModName}: $($_.Exception.Message)"
    }
    return @($errors)
}

function Remove-VtBuildReceiptFixtureTree {
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

function Invoke-VtBuildReceiptSelfTest {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2 build receipt " + [guid]::NewGuid().ToString('N'))
    $passed = 0
    # Hosted PR jobs export GITHUB_BASE_REF for the real checkout. The fixture
    # below is an intentionally standalone repository with no origin remote, so
    # inheriting that outer diff authority would make its generic local-context
    # case attempt `origin/<base>...HEAD` instead of exercising the worktree
    # path. Isolate the synthetic repository, then restore the caller exactly.
    $savedGithubBaseRef = $env:GITHUB_BASE_REF
    try {
        Remove-Item Env:GITHUB_BASE_REF -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'tools') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'example_mod\scripts') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'example_mod\bundleV2') | Out-Null
        $excludedSha256 = ('1' * 64)
        $inventoryText = "@{ Mods = @(@{ Dir='example_mod'; BundleAuthority='tracked'; RootBundle='aaaaaaaaaaaaaaaa.mod_bundle'; BuildArtifactExclusions=@(@{ Name='bbbbbbbbbbbbbbbb.mod_bundle'; Sha256='$excludedSha256'; Reason='fixture-only normalized output' }) }) }`n"
        [System.IO.File]::WriteAllText((Join-Path $tempRoot '.gitattributes'),
            "*.lua text eol=lf`n*.ps1 text eol=crlf`n")
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'tools\mod-inventory.psd1'), $inventoryText)
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'example_mod\scripts\main.lua'), "return 'v1'`n")
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'example_mod\example_mod.mod'), "return {}`n")
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'example_mod\itemV2.cfg'),
            "title = `"Example`";`npublished_id = 0L;`nvisibility = `"friends_only`";`n")
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'example_mod\CHANGELOG.md'), "# ignored metadata`n")
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'example_mod\.gitignore'), "local-runtime.bin`n")
        [System.IO.File]::WriteAllBytes((Join-Path $tempRoot 'example_mod\bundleV2\aaaaaaaaaaaaaaaa.mod_bundle'),
            [System.Text.Encoding]::UTF8.GetBytes('root-v1'))
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'example_mod\bundleV2\example_mod.mod'), "return {}`n")
        & git -C $tempRoot init --quiet
        & git -C $tempRoot config user.email 'fixture@example.invalid'
        & git -C $tempRoot config user.name 'Build Receipt Fixture'
        & git -C $tempRoot config core.autocrlf false
        & git -C $tempRoot add .
        & git -C $tempRoot commit --quiet -m initial
        if ($LASTEXITCODE -ne 0) { throw 'fixture initial commit failed' }

        # BuildOnly provenance is a read-only check. Even when a clean-filtered
        # blob already exists loose in the repository, the temporary object
        # store must not let `hash-object -w` freshen its real metadata.
        $mainRepoPath = 'example_mod/scripts/main.lua'
        $mainBlob = (& git -C $tempRoot hash-object "--path=$mainRepoPath" -- $mainRepoPath).Trim()
        if ($LASTEXITCODE -ne 0 -or $mainBlob -cnotmatch '^[0-9a-f]{40,64}$') {
            throw 'could not resolve fixture source blob for object-store isolation test'
        }
        $realObjectPath = Join-Path $tempRoot ('.git\objects\{0}\{1}' -f
            $mainBlob.Substring(0, 2), $mainBlob.Substring(2))
        if (-not (Test-Path -LiteralPath $realObjectPath -PathType Leaf)) {
            throw 'fixture source blob is not loose for object-store isolation test'
        }
        $oldObjectTime = [datetime]::SpecifyKind(
            [datetime]::ParseExact('2001-02-03T04:05:06', 'yyyy-MM-ddTHH:mm:ss',
                [System.Globalization.CultureInfo]::InvariantCulture),
            [System.DateTimeKind]::Utc)
        # Git for Windows marks loose objects read-only. Normalize this
        # disposable fixture file before backdating it so PS5.1 and PS7 execute
        # the same metadata-preservation assertion.
        [System.IO.File]::SetAttributes($realObjectPath, [System.IO.FileAttributes]::Normal)
        [System.IO.File]::SetLastWriteTimeUtc($realObjectPath, $oldObjectTime)
        $realObjectBytes = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($realObjectPath))
        $readOnlyProbeMap = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        if ($null -eq $readOnlyProbeMap -or
                [System.IO.File]::GetLastWriteTimeUtc($realObjectPath) -ne $oldObjectTime -or
                [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($realObjectPath)) -cne $realObjectBytes) {
            throw 'working source provenance mutated or freshened the repository object store'
        }
        $passed++

        # A relevant ignored local file is still visible to VMB, so it must
        # enter the working fingerprint and cannot silently contaminate a
        # schema 3 output proof.
        $withoutIgnored = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        foreach ($allowByDefaultPath in @('CHANGELOG.md', '.gitignore')) {
            if (@($withoutIgnored.Files | Where-Object { $_.Path -ceq $allowByDefaultPath }).Count -ne 1) {
                throw "arbitrary mod file was excluded by a path-name heuristic: $allowByDefaultPath"
            }
        }
        $ignoredRuntime = Join-Path $tempRoot 'example_mod\local-runtime.bin'
        [System.IO.File]::WriteAllBytes($ignoredRuntime, [byte[]](1, 2, 3, 4))
        $withIgnored = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        if ($withIgnored.Fingerprint -ceq $withoutIgnored.Fingerprint -or
                @($withIgnored.Files | Where-Object { $_.Path -ceq 'local-runtime.bin' }).Count -ne 1) {
            throw 'ignored runtime input was omitted from the working source fingerprint'
        }
        Remove-Item -LiteralPath $ignoredRuntime -Force
        $passed++

        # Dot-prefixed runtime paths remain compiler-visible because VMB gives
        # Stingray the complete mod source directory. Only the receipt itself is
        # excluded from its own source map.
        $hiddenDirectory = Join-Path $tempRoot 'example_mod\.hidden'
        New-Item -ItemType Directory -Path $hiddenDirectory | Out-Null
        $hiddenRuntime = Join-Path $hiddenDirectory 'runtime.lua'
        [System.IO.File]::WriteAllBytes($hiddenRuntime,
            [System.Text.Encoding]::UTF8.GetBytes("return 'hidden'`n"))
        $withHidden = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        if ($withHidden.Fingerprint -ceq $withoutIgnored.Fingerprint -or
                @($withHidden.Files | Where-Object { $_.Path -ceq '.hidden/runtime.lua' }).Count -ne 1) {
            throw 'hidden runtime input was omitted from the working source fingerprint'
        }
        Remove-Item -LiteralPath $hiddenRuntime -Force
        Remove-Item -LiteralPath $hiddenDirectory -Force
        $passed++

        $inventoryEntry = (Import-PowerShellDataFile -Path (Join-Path $tempRoot 'tools\mod-inventory.psd1')).Mods[0]
        $normalizationPolicy = Get-VtBuildReceiptNormalizationPolicyForEntry -InventoryEntry $inventoryEntry
        $builderVersion = '9.8.7-selftest'
        $cleanMap = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        $authorityRejected = $false
        try {
            Get-VtBuildWorkingOutputSet -RepoRoot $tempRoot -Mod 'example_mod' `
                -SourceMap $cleanMap -InventoryEntry @{
                    Dir = 'example_mod'
                    BundleAuthority = 'generated'
                    RootBundle = 'aaaaaaaaaaaaaaaa.mod_bundle'
                } | Out-Null
        }
        catch { $authorityRejected = ($_.Exception.Message -match "invalid BundleAuthority") }
        if (-not $authorityRejected) { throw 'unsupported bundle authority was accepted for a receipt proof' }
        $cleanOutput = Get-VtBuildWorkingOutputSet -RepoRoot $tempRoot -Mod 'example_mod' `
            -SourceMap $cleanMap -InventoryEntry $inventoryEntry
        $cleanRoot = Get-VtBuildWorkingRootProof -RepoRoot $tempRoot -Mod 'example_mod'
        $cleanReceipt = New-VtBuildReceipt -Mod 'example_mod' -SourceMap $cleanMap `
            -OutputSet $cleanOutput -BuilderVersion $builderVersion `
            -NormalizationPolicy $normalizationPolicy
        $cleanReceiptPath = Write-VtBuildReceipt -RepoRoot $tempRoot -Mod 'example_mod' -Receipt $cleanReceipt
        $receiptBytesBefore = [System.IO.File]::ReadAllBytes($cleanReceiptPath)
        $null = Write-VtBuildReceipt -RepoRoot $tempRoot -Mod 'example_mod' -Receipt $cleanReceipt
        $receiptBytesAfter = [System.IO.File]::ReadAllBytes($cleanReceiptPath)
        if ([System.Convert]::ToBase64String($receiptBytesBefore) -cne
                [System.Convert]::ToBase64String($receiptBytesAfter)) {
            throw 'identical source/output did not produce deterministic receipt bytes'
        }
        $roundTrip = ConvertFrom-VtBuildReceiptJson -Json (ConvertTo-VtBuildReceiptJson -Receipt $cleanReceipt)
        if ([int]$roundTrip.schema -ne 3 -or
                @($roundTrip.normalization_policy.excluded_outputs).Count -ne 1 -or
                [string]$roundTrip.normalization_policy.excluded_outputs[0].sha256 -cne $excludedSha256) {
            throw 'schema 3 receipt lost its nested normalization proof during JSON serialization'
        }
        $directValid = Test-VtBuildReceiptProof -Receipt $roundTrip -ExpectedMod 'example_mod' `
            -SourceMap $cleanMap -OutputSet $cleanOutput `
            -NormalizationPolicy $normalizationPolicy -ExpectedBuilderVersion $builderVersion `
            -MinimumSchema 3
        if (-not $directValid.Ok) { throw "working schema 3 proof failed: $($directValid.Problems -join '; ')" }
        $passed++

        # BuildOnly's explicit working-tree lane always requires schema 3.
        $savedMod = $script:Mod
        $script:Mod = 'example_mod'
        try { $explicitContext = Get-VtBuildReceiptDiffContext -Root $tempRoot }
        finally { $script:Mod = $savedMod }
        if ($explicitContext.Mode -cne 'worktree') {
            throw 'explicit BuildOnly target did not select the just-written working-tree receipt'
        }
        $contextErrors = @(Test-VtBuildReceiptContext -Root $tempRoot `
            -Context $explicitContext -ModName 'example_mod' -MinimumSchema 3 `
            -ExpectedBuilderVersion $builderVersion)
        if ($contextErrors.Count -ne 0) {
            throw "byte-identical first receipt failed: $($contextErrors -join '; ')"
        }
        $passed++

        # Schema 2 remains valid at minimum 2, but cannot satisfy a schema 3
        # target. Its historical root Git-blob proof remains unchanged.
        $schema2Receipt = [pscustomobject][ordered]@{
            schema = 2
            mod = 'example_mod'
            source_algorithm = 'git-blob-build-byte-map-sha256-v2'
            source_fingerprint_sha256 = [string]$cleanMap.Fingerprint
            source_files = @($cleanMap.Files | ForEach-Object {
                [pscustomobject][ordered]@{
                    path = [string]$_.Path
                    git_blob = [string]$_.GitBlob
                    build_sha256 = [string]$_.BuildSha256
                }
            })
            root_bundle = [string]$cleanRoot.Name
            root_bundle_git_blob = [string]$cleanRoot.GitBlob
            root_bundle_sha256 = [string]$cleanRoot.Sha256
        }
        $schema2Valid = Test-VtBuildReceiptProof -Receipt $schema2Receipt `
            -ExpectedMod 'example_mod' -SourceMap $cleanMap -RootProof $cleanRoot -MinimumSchema 2
        if (-not $schema2Valid.Ok) { throw "schema 2 compatibility failed: $($schema2Valid.Problems -join '; ')" }
        $schema2TooOld = Test-VtBuildReceiptProof -Receipt $schema2Receipt `
            -ExpectedMod 'example_mod' -SourceMap $cleanMap -RootProof $cleanRoot -MinimumSchema 3
        if ($schema2TooOld.Ok -or ($schema2TooOld.Problems -join '; ') -notmatch 'below required minimum schema 3') {
            throw 'schema 2 unexpectedly satisfied a schema 3 target'
        }
        $passed++

        # Legacy, unknown, malformed, and structurally extended receipts fail
        # closed with actionable schema/property diagnostics.
        $legacyReceipt = ConvertFrom-VtBuildReceiptJson -Json (ConvertTo-VtBuildReceiptJson -Receipt $schema2Receipt)
        $legacyReceipt.schema = 1
        $legacyReceipt.source_algorithm = 'git-blob-map-sha256-v1'
        $legacyResult = Test-VtBuildReceiptProof -Receipt $legacyReceipt -ExpectedMod 'example_mod' `
            -SourceMap $cleanMap -RootProof $cleanRoot
        if ($legacyResult.Ok -or ($legacyResult.Problems -join '; ') -notmatch 'legacy receipt schema 1') {
            throw 'legacy Git-blob-only receipt schema was not rejected clearly'
        }
        $unknownReceipt = ConvertFrom-VtBuildReceiptJson -Json (ConvertTo-VtBuildReceiptJson -Receipt $cleanReceipt)
        $unknownReceipt.schema = 4
        $unknownResult = Test-VtBuildReceiptProof -Receipt $unknownReceipt -ExpectedMod 'example_mod' `
            -SourceMap $cleanMap -OutputSet $cleanOutput -NormalizationPolicy $normalizationPolicy
        if ($unknownResult.Ok -or ($unknownResult.Problems -join '; ') -notmatch 'unsupported receipt schema') {
            throw 'unknown receipt schema was accepted'
        }
        $malformedResult = Test-VtBuildReceiptProof -Receipt ([pscustomobject]@{ schema = 3 }) `
            -ExpectedMod 'example_mod' -SourceMap $cleanMap -OutputSet $cleanOutput `
            -NormalizationPolicy $normalizationPolicy -MinimumSchema 3
        if ($malformedResult.Ok) { throw 'malformed schema 3 receipt was accepted' }
        $extendedReceipt = ConvertFrom-VtBuildReceiptJson -Json (ConvertTo-VtBuildReceiptJson -Receipt $cleanReceipt)
        $extendedReceipt | Add-Member -MemberType NoteProperty -Name commit -Value 'forbidden'
        $extendedResult = Test-VtBuildReceiptProof -Receipt $extendedReceipt -ExpectedMod 'example_mod' `
            -SourceMap $cleanMap -OutputSet $cleanOutput -NormalizationPolicy $normalizationPolicy
        if ($extendedResult.Ok -or ($extendedResult.Problems -join '; ') -notmatch 'unknown property') {
            throw 'schema 3 receipt accepted an unknown lifecycle property'
        }
        $passed++

        # Any current output mutation, including the canonical root, invalidates
        # the complete output proof even when source bytes remain unchanged.
        $rootPath = Join-Path $tempRoot 'example_mod\bundleV2\aaaaaaaaaaaaaaaa.mod_bundle'
        [System.IO.File]::WriteAllBytes($rootPath,
            [System.Text.Encoding]::UTF8.GetBytes('root-after-receipt'))
        $mutatedOutput = Get-VtBuildWorkingOutputSet -RepoRoot $tempRoot -Mod 'example_mod' `
            -SourceMap $cleanMap -InventoryEntry $inventoryEntry
        $rootInvalid = Test-VtBuildReceiptProof -Receipt $cleanReceipt -ExpectedMod 'example_mod' `
            -SourceMap $cleanMap -OutputSet $mutatedOutput -NormalizationPolicy $normalizationPolicy
        if ($rootInvalid.Ok -or ($rootInvalid.Problems -join '; ') -notmatch 'output|root bundle') {
            throw 'direct post-receipt root mutation was accepted'
        }
        [System.IO.File]::WriteAllBytes($rootPath,
            [System.Text.Encoding]::UTF8.GetBytes('root-v1'))
        $passed++

        # Under text eol=lf, CRLF and LF have the same Git-clean blob but are
        # different raw compiler inputs. Schema 3 must retain the raw-byte
        # source proof even though the normalized output set is unchanged.
        $lfMap = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        $mainPath = Join-Path $tempRoot 'example_mod\scripts\main.lua'
        [System.IO.File]::WriteAllBytes($mainPath,
            [System.Text.Encoding]::UTF8.GetBytes("return 'v1'`r`n"))
        $crlfMap = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        $lfEntry = @($lfMap.Files | Where-Object { $_.Path -ceq 'scripts/main.lua' })[0]
        $crlfEntry = @($crlfMap.Files | Where-Object { $_.Path -ceq 'scripts/main.lua' })[0]
        if ($lfEntry.GitBlob -cne $crlfEntry.GitBlob -or
                $lfEntry.BuildSha256 -ceq $crlfEntry.BuildSha256) {
            throw 'clean-equivalent raw-byte fixture did not preserve Git blob while changing build bytes'
        }
        $rawComparison = Compare-VtBuildSourceMaps -Expected $lfMap -Actual $crlfMap
        if ($rawComparison.Ok -or ($rawComparison.Problems -join '; ') -notmatch 'raw build bytes') {
            throw 'clean-equivalent raw source mutation was accepted during BuildOnly comparison'
        }
        $crlfReproducibility = Test-VtBuildWorkingSourceReproducibility -SourceMap $crlfMap
        if ($crlfReproducibility.Ok -or
                ($crlfReproducibility.Problems -join '; ') -notmatch 'cannot be reproduced') {
            throw 'working raw bytes that Git checkout cannot reproduce passed BuildOnly preflight'
        }
        $crlfOutput = Get-VtBuildWorkingOutputSet -RepoRoot $tempRoot -Mod 'example_mod' `
            -SourceMap $crlfMap -InventoryEntry $inventoryEntry
        $crlfReceipt = New-VtBuildReceipt -Mod 'example_mod' -SourceMap $crlfMap `
            -OutputSet $crlfOutput -BuilderVersion $builderVersion `
            -NormalizationPolicy $normalizationPolicy
        # Deliberately stage CRLF working bytes under an LF attribute. Git
        # materializes LF in the index, which must not validate the CRLF proof.
        & git -C $tempRoot -c core.safecrlf=false add example_mod/scripts/main.lua
        $canonicalIndexMap = Get-VtBuildIndexSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        $canonicalIndexOutput = Get-VtBuildIndexOutputSet -RepoRoot $tempRoot -Mod 'example_mod' `
            -SourceMap $canonicalIndexMap -InventoryEntry $inventoryEntry
        $notReproducible = Test-VtBuildReceiptProof -Receipt $crlfReceipt -ExpectedMod 'example_mod' `
            -SourceMap $canonicalIndexMap -OutputSet $canonicalIndexOutput `
            -NormalizationPolicy $normalizationPolicy -ExpectedBuilderVersion $builderVersion `
            -MinimumSchema 3
        if ($notReproducible.Ok -or ($notReproducible.Problems -join '; ') -notmatch 'raw build bytes') {
            throw 'raw BuildOnly bytes that staged Git cannot reproduce were accepted'
        }
        [System.IO.File]::WriteAllBytes($mainPath,
            [System.Text.Encoding]::UTF8.GetBytes("return 'v1'`n"))
        $passed++

        # Receipt-internal output, descriptor, builder, and policy tampering is
        # rejected independently of changes to the current checkout.
        $badOutput = ConvertFrom-VtBuildReceiptJson -Json (ConvertTo-VtBuildReceiptJson -Receipt $cleanReceipt)
        $badOutput.output_files[1].length = [long]$badOutput.output_files[1].length + 1
        $badOutputResult = Test-VtBuildReceiptProof -Receipt $badOutput -ExpectedMod 'example_mod' `
            -SourceMap $cleanMap -OutputSet $cleanOutput -NormalizationPolicy $normalizationPolicy
        if ($badOutputResult.Ok -or ($badOutputResult.Problems -join '; ') -notmatch 'output') {
            throw 'receipt output mismatch was accepted'
        }
        $badDescriptor = ConvertFrom-VtBuildReceiptJson -Json (ConvertTo-VtBuildReceiptJson -Receipt $cleanReceipt)
        $badDescriptor.descriptor.source_path = 'scripts/main.lua'
        $badDescriptorResult = Test-VtBuildReceiptProof -Receipt $badDescriptor -ExpectedMod 'example_mod' `
            -SourceMap $cleanMap -OutputSet $cleanOutput -NormalizationPolicy $normalizationPolicy
        if ($badDescriptorResult.Ok -or ($badDescriptorResult.Problems -join '; ') -notmatch 'descriptor source') {
            throw 'receipt descriptor mismatch was accepted'
        }
        $badBuilder = ConvertFrom-VtBuildReceiptJson -Json (ConvertTo-VtBuildReceiptJson -Receipt $cleanReceipt)
        $badBuilder.builder.name = 'OtherBuilder'
        $badBuilderResult = Test-VtBuildReceiptProof -Receipt $badBuilder -ExpectedMod 'example_mod' `
            -SourceMap $cleanMap -OutputSet $cleanOutput -NormalizationPolicy $normalizationPolicy
        if ($badBuilderResult.Ok -or ($badBuilderResult.Problems -join '; ') -notmatch 'receipt builder') {
            throw 'receipt builder-name mismatch was accepted'
        }
        $badVersionResult = Test-VtBuildReceiptProof -Receipt $cleanReceipt -ExpectedMod 'example_mod' `
            -SourceMap $cleanMap -OutputSet $cleanOutput -NormalizationPolicy $normalizationPolicy `
            -ExpectedBuilderVersion 'different-version'
        if ($badVersionResult.Ok -or ($badVersionResult.Problems -join '; ') -notmatch 'expected version') {
            throw 'expected builder-version mismatch was accepted'
        }
        $differentPolicy = New-BuildOutputNormalizationPolicyProof -Exclusions @()
        $badPolicyResult = Test-VtBuildReceiptProof -Receipt $cleanReceipt -ExpectedMod 'example_mod' `
            -SourceMap $cleanMap -OutputSet $cleanOutput -NormalizationPolicy $differentPolicy
        if ($badPolicyResult.Ok -or ($badPolicyResult.Problems -join '; ') -notmatch 'normalization policy') {
            throw "normalization-policy mismatch was accepted or misdiagnosed: $($badPolicyResult.Problems -join '; ')"
        }
        $tamperedPolicy = ConvertFrom-VtBuildReceiptJson -Json (ConvertTo-VtBuildReceiptJson -Receipt $cleanReceipt)
        $tamperedPolicy.normalization_policy.fingerprint_sha256 = ('0' * 64)
        $tamperedPolicyResult = Test-VtBuildReceiptProof -Receipt $tamperedPolicy -ExpectedMod 'example_mod' `
            -SourceMap $cleanMap -OutputSet $cleanOutput -NormalizationPolicy $normalizationPolicy
        if ($tamperedPolicyResult.Ok -or ($tamperedPolicyResult.Problems -join '; ') -notmatch 'fingerprint does not match') {
            throw 'self-inconsistent normalization proof was accepted'
        }

        # A schema 3 policy is a postcondition, not merely receipt metadata:
        # every exact excluded output must be absent from both the receipt map
        # and the current complete output set.
        $pollutedRecords = @($cleanOutput.Files | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; Length = $_.Length; Sha256 = $_.Sha256 }
        })
        $pollutedRecords += [pscustomobject]@{
            Name = 'bbbbbbbbbbbbbbbb.mod_bundle'
            Length = 20L
            Sha256 = $excludedSha256
        }
        $pollutedOutput = New-VtBundleOutputSet -Records $pollutedRecords `
            -ExpectedDescriptorName 'example_mod.mod' `
            -ExpectedRootBundle 'aaaaaaaaaaaaaaaa.mod_bundle' `
            -ExpectedDescriptorSha256 $cleanOutput.Descriptor.Sha256
        $constructorRejectedPollution = $false
        try {
            New-VtBuildReceipt -Mod 'example_mod' -SourceMap $cleanMap `
                -OutputSet $pollutedOutput -BuilderVersion $builderVersion `
                -NormalizationPolicy $normalizationPolicy | Out-Null
        }
        catch {
            $constructorRejectedPollution = $_.Exception.Message -match 'excluded output remains'
        }
        if (-not $constructorRejectedPollution) {
            throw 'schema 3 constructor accepted a policy-excluded output'
        }
        $pollutedReceipt = ConvertFrom-VtBuildReceiptJson -Json (ConvertTo-VtBuildReceiptJson -Receipt $cleanReceipt)
        $pollutedReceipt.output_files = @($pollutedOutput.Files | ForEach-Object {
            [pscustomobject][ordered]@{ filename = $_.Name; length = [long]$_.Length; sha256 = $_.Sha256 }
        })
        $pollutedReceipt.output_fingerprint_sha256 = $pollutedOutput.Fingerprint
        $pollutedResult = Test-VtBuildReceiptProof -Receipt $pollutedReceipt `
            -ExpectedMod 'example_mod' -SourceMap $cleanMap -OutputSet $pollutedOutput `
            -NormalizationPolicy $normalizationPolicy -MinimumSchema 3
        if ($pollutedResult.Ok -or ($pollutedResult.Problems -join '; ') -notmatch 'excluded output remains') {
            throw 'schema 3 validator accepted a policy-excluded output'
        }
        $passed++

        # A source edit invalidates schema 3 even if every output byte is still
        # the receipt output.
        $mainPath = Join-Path $tempRoot 'example_mod\scripts\main.lua'
        [System.IO.File]::WriteAllText($mainPath, "return 'changed-after-build'`n")
        $changedMap = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        $sourceInvalid = Test-VtBuildReceiptProof -Receipt $cleanReceipt -ExpectedMod 'example_mod' `
            -SourceMap $changedMap -OutputSet $cleanOutput -NormalizationPolicy $normalizationPolicy
        if ($sourceInvalid.Ok -or ($sourceInvalid.Problems -join '; ') -notmatch 'source bytes changed') {
            throw 'post-receipt source mutation was accepted'
        }
        [System.IO.File]::WriteAllText($mainPath, "return 'v1'`n")
        $passed++

        # Stage the exact receipt, then prove the index and commit output sets
        # come from Git objects rather than a subsequently mutated working file.
        $null = Write-VtBuildReceipt -RepoRoot $tempRoot -Mod 'example_mod' -Receipt $cleanReceipt
        & git -C $tempRoot add example_mod
        $indexMap = Get-VtBuildIndexSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        $indexOutput = Get-VtBuildIndexOutputSet -RepoRoot $tempRoot -Mod 'example_mod' `
            -SourceMap $indexMap -InventoryEntry $inventoryEntry
        $valid = Test-VtBuildReceiptProof -Receipt $cleanReceipt -ExpectedMod 'example_mod' `
            -SourceMap $indexMap -OutputSet $indexOutput -NormalizationPolicy $normalizationPolicy `
            -ExpectedBuilderVersion $builderVersion -MinimumSchema 3
        if (-not $valid.Ok) { throw "unchanged staged schema 3 snapshot failed: $($valid.Problems -join '; ')" }
        [System.IO.File]::WriteAllBytes($rootPath,
            [System.Text.Encoding]::UTF8.GetBytes('unstaged-root-mutation'))
        $indexOutputAfterMutation = Get-VtBuildIndexOutputSet -RepoRoot $tempRoot -Mod 'example_mod' `
            -SourceMap $indexMap -InventoryEntry $inventoryEntry
        if ([string]$indexOutputAfterMutation.Fingerprint -cne [string]$cleanOutput.Fingerprint) {
            throw 'index output reconstruction read mutated working output bytes'
        }
        $indexContext = [pscustomobject]@{ Mode = 'index'; Head = 'INDEX'; Lines = @() }
        $contextErrors = @(Test-VtBuildReceiptContext -Root $tempRoot -Context $indexContext `
            -ModName 'example_mod' -MinimumSchema 3 -ExpectedBuilderVersion $builderVersion)
        if ($contextErrors.Count -ne 0) {
            throw "staged end-to-end receipt gate failed: $($contextErrors -join '; ')"
        }
        & git -C $tempRoot commit --quiet -m buildonly
        if ($LASTEXITCODE -ne 0) { throw 'fixture BuildOnly commit failed' }
        $commitMap = Get-VtBuildCommitSourceMap -RepoRoot $tempRoot -Mod 'example_mod' -Commit 'HEAD'
        $commitOutput = Get-VtBuildCommitOutputSet -RepoRoot $tempRoot -Mod 'example_mod' `
            -Commit 'HEAD' -SourceMap $commitMap -InventoryEntry $inventoryEntry
        $committed = Test-VtBuildReceiptProof -Receipt $cleanReceipt -ExpectedMod 'example_mod' `
            -SourceMap $commitMap -OutputSet $commitOutput -NormalizationPolicy $normalizationPolicy `
            -MinimumSchema 3
        if (-not $committed.Ok) {
            throw "unchanged committed snapshot failed: $($committed.Problems -join '; ')"
        }
        $commitContext = [pscustomobject]@{ Mode = 'commit'; Head = 'HEAD'; Lines = @() }
        $contextErrors = @(Test-VtBuildReceiptContext -Root $tempRoot `
            -Context $commitContext -ModName 'example_mod' -MinimumSchema 3)
        if ($contextErrors.Count -ne 0) {
            throw "committed end-to-end receipt gate failed: $($contextErrors -join '; ')"
        }
        [System.IO.File]::WriteAllBytes($rootPath, [System.Text.Encoding]::UTF8.GetBytes('root-v1'))
        $passed++

        # Context validation also accepts historical schema 2 at minimum 2 and
        # does not require a schema 3 normalization proof.
        $null = Write-VtBuildReceipt -RepoRoot $tempRoot -Mod 'example_mod' -Receipt $schema2Receipt
        & git -C $tempRoot add example_mod/.build-receipt.json
        $schema2ContextErrors = @(Test-VtBuildReceiptContext -Root $tempRoot `
            -Context $indexContext -ModName 'example_mod' -MinimumSchema 2)
        if ($schema2ContextErrors.Count -ne 0) {
            throw "schema 2 context compatibility failed: $($schema2ContextErrors -join '; ')"
        }
        $schema2UpgradeErrors = @(Test-VtBuildReceiptContext -Root $tempRoot `
            -Context $indexContext -ModName 'example_mod' -MinimumSchema 3)
        if ($schema2UpgradeErrors.Count -eq 0 -or
                ($schema2UpgradeErrors -join '; ') -notmatch 'below required minimum schema 3') {
            throw 'schema 2 context unexpectedly satisfied a schema 3 target'
        }
        & git -C $tempRoot reset --quiet HEAD -- example_mod/.build-receipt.json
        $null = Write-VtBuildReceipt -RepoRoot $tempRoot -Mod 'example_mod' -Receipt $cleanReceipt
        $passed++

        # The index policy proof is reconstructed from the index inventory, so
        # a staged policy drift cannot borrow the working inventory's policy.
        $differentInventoryText = "@{ Mods = @(@{ Dir='example_mod'; BundleAuthority='tracked'; RootBundle='aaaaaaaaaaaaaaaa.mod_bundle'; BuildArtifactExclusions=@() }) }`n"
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'tools\mod-inventory.psd1'), $differentInventoryText)
        & git -C $tempRoot add tools/mod-inventory.psd1
        $policyContextErrors = @(Test-VtBuildReceiptContext -Root $tempRoot `
            -Context $indexContext -ModName 'example_mod' -MinimumSchema 3)
        if ($policyContextErrors.Count -eq 0 -or
                ($policyContextErrors -join '; ') -notmatch 'normalization policy') {
            throw 'staged normalization-policy drift was accepted by context validation'
        }
        & git -C $tempRoot reset --quiet HEAD -- tools/mod-inventory.psd1
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'tools\mod-inventory.psd1'), $inventoryText)
        $passed++

        # A staged root .gitattributes change can alter checkout bytes for every
        # mod without touching a mod-local path. Index materialization must use
        # the staged attributes, not the divergent working attributes.
        $attributesPath = Join-Path $tempRoot '.gitattributes'
        $originalAttributes = [System.IO.File]::ReadAllBytes($attributesPath)
        [System.IO.File]::WriteAllBytes($attributesPath,
            [System.Text.Encoding]::UTF8.GetBytes("*.lua text eol=crlf`n*.ps1 text eol=crlf`n"))
        & git -C $tempRoot add .gitattributes
        [System.IO.File]::WriteAllBytes($attributesPath, $originalAttributes)
        $savedStaged = $script:Staged
        $script:Staged = $true
        try { $attributeContext = Get-VtBuildReceiptDiffContext -Root $tempRoot }
        finally { $script:Staged = $savedStaged }
        $attributeChanges = Convert-VtBuildReceiptChanges -Lines $attributeContext.Lines
        $attributeTargets = @(Get-VtBuildReceiptTargets `
            -Inventory @($inventoryEntry) -Changes $attributeChanges `
            -ReceiptBearingMods @('example_mod'))
        if ($attributeTargets.Count -ne 1 -or $attributeTargets[0].Mod -cne 'example_mod' -or
                [int]$attributeTargets[0].MinimumSchema -ne 2 -or
                ($attributeTargets[0].Reasons -join '; ') -notmatch 'global receipt policy changed') {
            throw 'root .gitattributes change did not target the receipt-bearing mod'
        }
        $attributeErrors = @(Test-VtBuildReceiptContext -Root $tempRoot `
            -Context $attributeContext -ModName 'example_mod' `
            -MinimumSchema ([int]$attributeTargets[0].MinimumSchema) `
            -ExpectedBuilderVersion $builderVersion)
        if ($attributeErrors.Count -eq 0 -or ($attributeErrors -join '; ') -notmatch 'raw build bytes') {
            throw 'checkout-materialization-changing staged .gitattributes edit retained a stale receipt'
        }
        & git -C $tempRoot reset --quiet HEAD -- .gitattributes
        [System.IO.File]::WriteAllBytes($attributesPath, $originalAttributes)
        $passed++

        # Type changes must enter the target set, and non-regular staged runtime
        # inputs fail closed without requiring OS symlink privileges.
        $mainBlob = (& git -C $tempRoot rev-parse 'HEAD:example_mod/scripts/main.lua').Trim()
        & git -C $tempRoot update-index --cacheinfo 120000 $mainBlob 'example_mod/scripts/main.lua'
        if ($LASTEXITCODE -ne 0) { throw 'fixture index type change failed' }
        $script:Staged = $true
        try { $typeContext = Get-VtBuildReceiptDiffContext -Root $tempRoot }
        finally { $script:Staged = $savedStaged }
        $typeChanges = Convert-VtBuildReceiptChanges -Lines $typeContext.Lines
        if (@($typeChanges | Where-Object {
                    $_.Status -ceq 'T' -and $_.Path -ceq 'example_mod/scripts/main.lua'
                }).Count -ne 1) {
            throw 'regular-to-symlink Git type change was omitted from receipt diff context'
        }
        $typeTargets = @(Get-VtBuildReceiptTargets -Inventory @($inventoryEntry) `
            -Changes $typeChanges -ReceiptBearingMods @('example_mod'))
        if ($typeTargets.Count -ne 1 -or $typeTargets[0].Mod -cne 'example_mod' -or
                [int]$typeTargets[0].MinimumSchema -ne 3) {
            throw 'regular-to-symlink runtime change did not require schema 3'
        }
        $typeRejected = $false
        try { Get-VtBuildIndexSourceMap -RepoRoot $tempRoot -Mod 'example_mod' | Out-Null }
        catch { $typeRejected = ($_.Exception.Message -match 'non-regular staged runtime input') }
        if (-not $typeRejected) { throw 'staged symlink runtime input was accepted' }
        & git -C $tempRoot reset --quiet HEAD -- example_mod/scripts/main.lua
        $passed++

        # Generic local QA (no explicit -Mod) must select the working-tree
        # context when an untracked runtime input is the only change.
        $untrackedRuntime = Join-Path $tempRoot 'example_mod\scripts\untracked.lua'
        [System.IO.File]::WriteAllBytes($untrackedRuntime,
            [System.Text.Encoding]::UTF8.GetBytes("return 'untracked'`n"))
        $genericSavedMod = $script:Mod
        $genericSavedStaged = $script:Staged
        $script:Mod = $null
        $script:Staged = $false
        try { $untrackedContext = Get-VtBuildReceiptDiffContext -Root $tempRoot }
        finally {
            $script:Mod = $genericSavedMod
            $script:Staged = $genericSavedStaged
        }
        if ($untrackedContext.Mode -cne 'worktree') {
            throw 'ordinary local QA ignored an untracked runtime input'
        }
        $untrackedChanges = Convert-VtBuildReceiptChanges -Lines $untrackedContext.Lines
        $untrackedTargets = @(Get-VtBuildReceiptTargets -Inventory @($inventoryEntry) `
            -Changes $untrackedChanges -ReceiptBearingMods @('example_mod'))
        if ($untrackedTargets.Count -ne 1 -or $untrackedTargets[0].Mod -cne 'example_mod' -or
                [int]$untrackedTargets[0].MinimumSchema -ne 3) {
            throw 'ordinary local QA did not schema-3 target the mod owning an untracked runtime input'
        }
        $untrackedErrors = @(Test-VtBuildReceiptContext -Root $tempRoot `
            -Context $untrackedContext -ModName 'example_mod' -MinimumSchema 3 `
            -ExpectedBuilderVersion $builderVersion)
        if ($untrackedErrors.Count -eq 0 -or ($untrackedErrors -join '; ') -notmatch 'source added') {
            throw 'ordinary local QA accepted an untracked runtime input beside a stale receipt'
        }
        Remove-Item -LiteralPath $untrackedRuntime -Force
        $passed++

        # A relevant source mutation during a build changes the exact source map
        # and invalidates schema 3 even while the complete output set is stable.
        $duringBefore = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        [System.IO.File]::WriteAllText($mainPath, "return 'during-build'`n")
        $duringAfter = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        $duringComparison = Compare-VtBuildSourceMaps -Expected $duringBefore -Actual $duringAfter
        if ($duringComparison.Ok -or ($duringComparison.Problems -join '; ') -notmatch 'source|raw build bytes') {
            throw 'during-build source mutation was accepted'
        }
        $duringOutput = Get-VtBuildWorkingOutputSet -RepoRoot $tempRoot -Mod 'example_mod' `
            -SourceMap $duringAfter -InventoryEntry $inventoryEntry
        $duringInvalid = Test-VtBuildReceiptProof -Receipt $cleanReceipt -ExpectedMod 'example_mod' `
            -SourceMap $duringAfter -OutputSet $duringOutput `
            -NormalizationPolicy $normalizationPolicy -ExpectedBuilderVersion $builderVersion `
            -MinimumSchema 3
        if ($duringInvalid.Ok -or ($duringInvalid.Problems -join '; ') -notmatch 'source bytes changed') {
            throw 'during-build source mutation retained the old schema 3 receipt'
        }
        [System.IO.File]::WriteAllText($mainPath, "return 'v1'`n")
        $passed++

        # Staging a source edit after BuildOnly invalidates the reviewed schema
        # 3 receipt in both the direct proof and the end-to-end index context.
        [System.IO.File]::WriteAllText($mainPath, "return 'post-buildonly-edit'`n")
        & git -C $tempRoot add example_mod/scripts/main.lua
        $changedIndex = Get-VtBuildIndexSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        $changedIndexOutput = Get-VtBuildIndexOutputSet -RepoRoot $tempRoot -Mod 'example_mod' `
            -SourceMap $changedIndex -InventoryEntry $inventoryEntry
        $postBuildInvalid = Test-VtBuildReceiptProof -Receipt $cleanReceipt -ExpectedMod 'example_mod' `
            -SourceMap $changedIndex -OutputSet $changedIndexOutput `
            -NormalizationPolicy $normalizationPolicy -ExpectedBuilderVersion $builderVersion `
            -MinimumSchema 3
        if ($postBuildInvalid.Ok -or
                ($postBuildInvalid.Problems -join '; ') -notmatch 'source bytes changed') {
            throw 'post-BuildOnly staged source edit did not invalidate schema 3'
        }
        $postBuildContext = [pscustomobject]@{ Mode = 'index'; Head = 'INDEX'; Lines = @() }
        $postBuildErrors = @(Test-VtBuildReceiptContext -Root $tempRoot `
            -Context $postBuildContext -ModName 'example_mod' -MinimumSchema 3 `
            -ExpectedBuilderVersion $builderVersion)
        if ($postBuildErrors.Count -eq 0 -or
                ($postBuildErrors -join '; ') -notmatch 'source bytes changed') {
            throw 'staged end-to-end gate accepted a post-BuildOnly source edit'
        }
        & git -C $tempRoot reset --quiet HEAD -- example_mod/scripts/main.lua
        [System.IO.File]::WriteAllText($mainPath, "return 'v1'`n")
        $passed++

        # Schema 3 inventories every normalized bundleV2 output, including an
        # otherwise valid sidecar that schema 2 did not bind.
        $sidecarBefore = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        $sidecarPath = Join-Path $tempRoot 'example_mod\bundleV2\e7852992f40eb619.mod_bundle'
        [System.IO.File]::WriteAllBytes($sidecarPath,
            [System.Text.Encoding]::UTF8.GetBytes('tool-only-sidecar'))
        $sidecarAfter = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        if (-not (Compare-VtBuildSourceMaps -Expected $sidecarBefore -Actual $sidecarAfter).Ok) {
            throw 'optional bundle sidecar contaminated the runtime source map'
        }
        $sidecarOutput = Get-VtBuildWorkingOutputSet -RepoRoot $tempRoot -Mod 'example_mod' `
            -SourceMap $sidecarAfter -InventoryEntry $inventoryEntry
        $sidecarInvalid = Test-VtBuildReceiptProof -Receipt $cleanReceipt -ExpectedMod 'example_mod' `
            -SourceMap $sidecarAfter -OutputSet $sidecarOutput -NormalizationPolicy $normalizationPolicy
        if ($sidecarInvalid.Ok -or ($sidecarInvalid.Problems -join '; ') -notmatch 'unexpected') {
            throw 'new bundleV2 sidecar was omitted from the complete output proof'
        }
        Remove-Item -LiteralPath $sidecarPath -Force
        $passed++

        # Target selection carries both auditable reasons and the minimum schema.
        $targetInventory = @(@{ Dir = 'example_mod'; RootBundle = 'aaaaaaaaaaaaaaaa.mod_bundle' })
        foreach ($status in @('A', 'C', 'M', 'D', 'R', 'T')) {
            $deltaTargets = @(Get-VtBuildReceiptTargets -Inventory $targetInventory `
                -Changes @([pscustomobject]@{
                    Status = $status
                    Path = 'example_mod/bundleV2/e7852992f40eb619.mod_bundle'
                }) -ReceiptBearingMods @('example_mod'))
            if ($deltaTargets.Count -ne 1 -or $deltaTargets[0].Mod -cne 'example_mod' -or
                    [int]$deltaTargets[0].MinimumSchema -ne 3 -or
                    ($deltaTargets[0].Reasons -join '; ') -notmatch "bundle output changed: $status") {
                throw "bundleV2 $status delta did not require schema 3 with an auditable reason"
            }
        }
        $rawCopyChanges = @(Convert-VtBuildReceiptChanges -Lines @(
            "C100`tother_mod/scripts/seed.bin`texample_mod/bundleV2/e7852992f40eb619.mod_bundle"
        ))
        $rawCopyTargets = @(Get-VtBuildReceiptTargets -Inventory $targetInventory `
            -Changes $rawCopyChanges -ReceiptBearingMods @('example_mod'))
        if ($rawCopyChanges.Count -ne 1 -or $rawCopyChanges[0].Status -cne 'C' -or
                $rawCopyChanges[0].Path -cne 'example_mod/bundleV2/e7852992f40eb619.mod_bundle' -or
                $rawCopyTargets.Count -ne 1 -or [int]$rawCopyTargets[0].MinimumSchema -ne 3) {
            throw 'raw Git C100 destination bypassed schema 3 target selection'
        }
        foreach ($globalPath in @(
                '.gitattributes', 'tools/mod-inventory.psd1',
                'tools/ship/bundle-authority.ps1',
                'tools/ship/build-output-normalization.ps1',
                'tools/ship/build-receipt.ps1', 'tools/ship/bundle-output-set.ps1',
                'qa/check_bundle_authority.ps1',
                'qa/check_build_receipts.ps1')) {
            $globalTargets = @(Get-VtBuildReceiptTargets -Inventory $targetInventory `
                -Changes @([pscustomobject]@{ Status = 'M'; Path = $globalPath }) `
                -ReceiptBearingMods @('example_mod'))
            if ($globalTargets.Count -ne 1 -or $globalTargets[0].Mod -cne 'example_mod' -or
                    [int]$globalTargets[0].MinimumSchema -ne 2 -or
                    ($globalTargets[0].Reasons -join '; ') -notmatch 'global receipt policy changed') {
                throw "global-only policy delta did not preserve schema 2 eligibility: $globalPath"
            }
        }
        $sourceTargets = @(Get-VtBuildReceiptTargets -Inventory $targetInventory `
            -Changes @([pscustomobject]@{ Status = 'M'; Path = 'example_mod/scripts/main.lua' }) `
            -ReceiptBearingMods @('example_mod'))
        $receiptTargets = @(Get-VtBuildReceiptTargets -Inventory $targetInventory `
            -Changes @([pscustomobject]@{ Status = 'M'; Path = 'example_mod/.build-receipt.json' }) `
            -ReceiptBearingMods @('example_mod'))
        $explicitTargets = @(Get-VtBuildReceiptTargets -Inventory $targetInventory `
            -Changes @() -ExplicitMod 'example_mod' -ReceiptBearingMods @('example_mod'))
        foreach ($targetCase in @($sourceTargets, $receiptTargets, $explicitTargets)) {
            if ($targetCase.Count -ne 1 -or [int]$targetCase[0].MinimumSchema -ne 3 -or
                    @($targetCase[0].Reasons).Count -eq 0) {
                throw 'source, receipt, or explicit BuildOnly target lacked schema 3 reason metadata'
            }
        }
        $passed++

        # The constrained first-upload lane compare-and-swaps only the cfg ID.
        # Outputs stay byte-identical, but the old schema 3 receipt must fail
        # until a new BuildOnly receipt binds the positive-ID source bytes.
        $bootstrapCfg = Join-Path $tempRoot 'example_mod\itemV2.cfg'
        [System.IO.File]::WriteAllText($bootstrapCfg,
            "title = `"Example`";`npublished_id = 123456789L;`nvisibility = `"friends_only`";`n")
        $bootstrapMap = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        $bootstrapOutput = Get-VtBuildWorkingOutputSet -RepoRoot $tempRoot -Mod 'example_mod' `
            -SourceMap $bootstrapMap -InventoryEntry $inventoryEntry
        if ([string]$bootstrapOutput.Fingerprint -cne [string]$cleanOutput.Fingerprint -or
                [string]$bootstrapOutput.Root.Sha256 -cne [string]$cleanOutput.Root.Sha256) {
            throw 'first-upload ID-only fixture unexpectedly changed normalized output'
        }
        $staleBootstrap = Test-VtBuildReceiptProof -Receipt $cleanReceipt `
            -ExpectedMod 'example_mod' -SourceMap $bootstrapMap -OutputSet $bootstrapOutput `
            -NormalizationPolicy $normalizationPolicy -ExpectedBuilderVersion $builderVersion `
            -MinimumSchema 3
        if ($staleBootstrap.Ok -or
                ($staleBootstrap.Problems -join '; ') -notmatch 'source bytes changed') {
            throw 'first-upload ID-only cfg change retained a stale schema 3 receipt'
        }
        $bootstrapReceipt = New-VtBuildReceipt -Mod 'example_mod' `
            -SourceMap $bootstrapMap -OutputSet $bootstrapOutput `
            -BuilderVersion $builderVersion -NormalizationPolicy $normalizationPolicy
        $null = Write-VtBuildReceipt -RepoRoot $tempRoot -Mod 'example_mod' `
            -Receipt $bootstrapReceipt
        & git -C $tempRoot add example_mod/itemV2.cfg example_mod/.build-receipt.json
        $bootstrapIndexMap = Get-VtBuildIndexSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        $bootstrapIndexOutput = Get-VtBuildIndexOutputSet -RepoRoot $tempRoot -Mod 'example_mod' `
            -SourceMap $bootstrapIndexMap -InventoryEntry $inventoryEntry
        $bootstrapValid = Test-VtBuildReceiptProof -Receipt $bootstrapReceipt `
            -ExpectedMod 'example_mod' -SourceMap $bootstrapIndexMap `
            -OutputSet $bootstrapIndexOutput -NormalizationPolicy $normalizationPolicy `
            -ExpectedBuilderVersion $builderVersion -MinimumSchema 3
        if (-not $bootstrapValid.Ok) {
            throw "refreshed first-upload schema 3 receipt failed: $($bootstrapValid.Problems -join '; ')"
        }
        $bootstrapContext = [pscustomobject]@{ Mode = 'index'; Head = 'INDEX'; Lines = @() }
        $bootstrapErrors = @(Test-VtBuildReceiptContext -Root $tempRoot `
            -Context $bootstrapContext -ModName 'example_mod' -MinimumSchema 3 `
            -ExpectedBuilderVersion $builderVersion)
        if ($bootstrapErrors.Count -ne 0) {
            throw "refreshed first-upload end-to-end gate failed: $($bootstrapErrors -join '; ')"
        }
        & git -C $tempRoot commit --quiet -m bootstrap-id
        if ($LASTEXITCODE -ne 0) { throw 'fixture first-upload ID commit failed' }
        $passed++

        # JSON strings that merely look numeric are not schema or length
        # numbers. Accepting them makes the on-disk contract host/coercion
        # dependent and permits non-canonical receipts to pass validation.
        $stringSchema = ConvertFrom-VtBuildReceiptJson -Json (ConvertTo-VtBuildReceiptJson -Receipt $bootstrapReceipt)
        $stringSchema.schema = '3'
        $stringSchemaResult = Test-VtBuildReceiptProof -Receipt $stringSchema -ExpectedMod 'example_mod' `
            -SourceMap $bootstrapMap -OutputSet $bootstrapOutput -NormalizationPolicy $normalizationPolicy `
            -ExpectedBuilderVersion $builderVersion -MinimumSchema 3
        if ($stringSchemaResult.Ok -or
                ($stringSchemaResult.Problems -join '; ') -notmatch 'schema.*(integer|number|numeric)') {
            throw 'stringified receipt schema was accepted as a JSON number'
        }
        $stringLength = ConvertFrom-VtBuildReceiptJson -Json (ConvertTo-VtBuildReceiptJson -Receipt $bootstrapReceipt)
        $stringLength.output_files[0].length = [string]$stringLength.output_files[0].length
        $stringLengthResult = Test-VtBuildReceiptProof -Receipt $stringLength -ExpectedMod 'example_mod' `
            -SourceMap $bootstrapMap -OutputSet $bootstrapOutput -NormalizationPolicy $normalizationPolicy `
            -ExpectedBuilderVersion $builderVersion -MinimumSchema 3
        if ($stringLengthResult.Ok -or
                ($stringLengthResult.Problems -join '; ') -notmatch 'length.*(integer|number|numeric)') {
            throw 'stringified receipt output length was accepted as a JSON number'
        }
        $floatingSchema = ConvertFrom-VtBuildReceiptJson -Json (ConvertTo-VtBuildReceiptJson -Receipt $bootstrapReceipt)
        $floatingSchema.schema = [double]3
        $floatingSchemaResult = Test-VtBuildReceiptProof -Receipt $floatingSchema -ExpectedMod 'example_mod' `
            -SourceMap $bootstrapMap -OutputSet $bootstrapOutput -NormalizationPolicy $normalizationPolicy `
            -ExpectedBuilderVersion $builderVersion -MinimumSchema 3
        if ($floatingSchemaResult.Ok -or
                ($floatingSchemaResult.Problems -join '; ') -notmatch 'schema.*(integer|number|numeric)') {
            throw 'floating-point receipt schema was accepted as a JSON integer'
        }
        $floatingLength = ConvertFrom-VtBuildReceiptJson -Json (ConvertTo-VtBuildReceiptJson -Receipt $bootstrapReceipt)
        $floatingLength.output_files[0].length = [double]$floatingLength.output_files[0].length
        $floatingLengthResult = Test-VtBuildReceiptProof -Receipt $floatingLength -ExpectedMod 'example_mod' `
            -SourceMap $bootstrapMap -OutputSet $bootstrapOutput -NormalizationPolicy $normalizationPolicy `
            -ExpectedBuilderVersion $builderVersion -MinimumSchema 3
        if ($floatingLengthResult.Ok -or
                ($floatingLengthResult.Problems -join '; ') -notmatch 'length.*(integer|number|numeric)') {
            throw 'floating-point receipt output length was accepted as a JSON integer'
        }
        $passed++

        Write-Host "[check_build_receipts -SelfTest] PASS $passed behavioral fixtures" -ForegroundColor Green
        return 0
    }
    finally {
        if ($null -eq $savedGithubBaseRef) {
            Remove-Item Env:GITHUB_BASE_REF -ErrorAction SilentlyContinue
        }
        else {
            $env:GITHUB_BASE_REF = $savedGithubBaseRef
        }
        Remove-VtBuildReceiptFixtureTree -Path $tempRoot
    }
}

if ($SelfTest) { exit (Invoke-VtBuildReceiptSelfTest) }

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
try {
    $inventoryPath = Join-Path $root 'tools\mod-inventory.psd1'
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        throw "Build receipt inventory is missing: $inventoryPath"
    }
    $inventory = Import-PowerShellDataFile -Path $inventoryPath
    $context = Get-VtBuildReceiptDiffContext -Root $root
    $changes = Convert-VtBuildReceiptChanges -Lines $context.Lines
    $receiptBearingMods = @($inventory.Mods | Where-Object {
        $text = Read-VtBuildReceiptContextText -Root $root -Context $context -ModName ([string]$_.Dir)
        -not [string]::IsNullOrWhiteSpace($text)
    } | ForEach-Object { [string]$_.Dir })
    $targets = Get-VtBuildReceiptTargets -Inventory @($inventory.Mods) -Changes $changes `
        -ExplicitMod $Mod -ReceiptBearingMods $receiptBearingMods
    if ($targets.Count -eq 0) {
        if (-not $Quiet) { Write-Host '[check_build_receipts] OK - no BuildOnly receipt target in scope.' -ForegroundColor Green }
        exit 0
    }

    $errors = @()
    foreach ($target in $targets) {
        $modName = [string]$target.Mod
        if (@($inventory.Mods | Where-Object { [string]$_.Dir -ceq $modName }).Count -ne 1) {
            $errors += "${modName}: not an active inventoried mod"
            continue
        }
        $errors += @(Test-VtBuildReceiptContext -Root $root -Context $context `
            -ModName $modName -MinimumSchema ([int]$target.MinimumSchema))
    }
    if ($errors.Count -gt 0) {
        Write-Host '[check_build_receipts] ERRORS - BuildOnly source/output receipt mismatch (#1278, #1400):' -ForegroundColor Red
        foreach ($errorMessage in $errors) { Write-Host "  X $errorMessage" -ForegroundColor Red }
        Write-Host '  Re-run the canonical BuildOnly command after the final source edit, then stage source, complete bundleV2 output, and receipt together.' -ForegroundColor Yellow
        exit 2
    }
    if (-not $Quiet) {
        Write-Host "[check_build_receipts] OK - $($targets.Count) exact source/output receipt(s) match $($context.Head)." -ForegroundColor Green
    }
    exit 0
}
catch {
    Write-Host "[check_build_receipts] INFRASTRUCTURE ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 99
}
