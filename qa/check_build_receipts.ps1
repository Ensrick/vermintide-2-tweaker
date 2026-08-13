# check_build_receipts.ps1 - staged/committed BuildOnly receipt gate (#1278).
#
# The gate validates only mods implicated by the selected diff (or -Mod). A mod
# enters the receipt contract when its runtime source, canonical root bundle, or
# receipt changes. Existing historical bundles need no mass migration, but every
# newly accepted BuildOnly root must carry the exact deterministic receipt.
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
    $untrackedArgs = @('-c', 'core.quotepath=false', 'ls-files', '--others',
        '--exclude-standard', '--') + @($activeModPaths)
    $ignoredArgs = @('-c', 'core.quotepath=false', 'ls-files', '--others', '--ignored',
        '--exclude-standard', '--') + @($activeModPaths)
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
    if ($ExplicitMod) { $targets[$ExplicitMod] = $true }
    if (@($Changes | Where-Object { $_.Path -ceq '.gitattributes' }).Count -gt 0) {
        foreach ($receiptBearingMod in @($ReceiptBearingMods)) {
            $targets[$receiptBearingMod] = $true
        }
    }
    foreach ($entry in $Inventory) {
        $dir = [string]$entry.Dir
        $prefix = "$dir/"
        $rootPath = "$dir/bundleV2/$($entry.RootBundle)"
        $receiptPath = "$dir/$script:VtBuildReceiptFileName"
        foreach ($change in $Changes) {
            if (-not $change.Path.StartsWith($prefix, [System.StringComparison]::Ordinal)) { continue }
            $relative = $change.Path.Substring($prefix.Length)
            if ($change.Path -ceq $rootPath -or $change.Path -ceq $receiptPath -or
                    (Test-VtBuildReceiptRelevantPath -RelativePath $relative)) {
                $targets[$dir] = $true
                break
            }
        }
    }
    return @($targets.Keys | Sort-Object)
}

function Read-VtBuildReceiptContextText {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$ModName
    )

    $repoPath = "$ModName/$script:VtBuildReceiptFileName"
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

function Test-VtBuildReceiptContext {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$ModName
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
            $rootProof = Get-VtBuildWorkingRootProof -RepoRoot $Root -Mod $ModName
        }
        elseif ($Context.Mode -eq 'index') {
            $sourceMap = Get-VtBuildIndexSourceMap -RepoRoot $Root -Mod $ModName
            $rootProof = Get-VtBuildIndexRootProof -RepoRoot $Root -Mod $ModName
        }
        else {
            $sourceMap = Get-VtBuildCommitSourceMap -RepoRoot $Root -Mod $ModName -Commit $Context.Head
            $rootProof = Get-VtBuildCommitRootProof -RepoRoot $Root -Mod $ModName -Commit $Context.Head
        }
        $result = Test-VtBuildReceiptProof -Receipt $receipt -ExpectedMod $ModName `
            -SourceMap $sourceMap -RootProof $rootProof
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
    try {
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'tools') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'example_mod\scripts') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'example_mod\bundleV2') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $tempRoot '.gitattributes'),
            "*.lua text eol=lf`n*.ps1 text eol=crlf`n")
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'tools\mod-inventory.psd1'),
            "@{ Mods = @(@{ Dir='example_mod'; RootBundle='aaaaaaaaaaaaaaaa.mod_bundle' }) }`n")
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'example_mod\scripts\main.lua'), "return 'v1'`n")
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'example_mod\example_mod.mod'), "return {}`n")
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'example_mod\itemV2.cfg'),
            "title = `"Example`";`npublished_id = 0L;`nvisibility = `"friends_only`";`n")
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'example_mod\CHANGELOG.md'), "# ignored metadata`n")
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'example_mod\.gitignore'), "local-runtime.bin`n")
        [System.IO.File]::WriteAllBytes((Join-Path $tempRoot 'example_mod\bundleV2\aaaaaaaaaaaaaaaa.mod_bundle'),
            [System.Text.Encoding]::UTF8.GetBytes('root-v1'))
        & git -C $tempRoot init --quiet
        & git -C $tempRoot config user.email 'fixture@example.invalid'
        & git -C $tempRoot config user.name 'Build Receipt Fixture'
        & git -C $tempRoot config core.autocrlf false
        & git -C $tempRoot add .
        & git -C $tempRoot commit --quiet -m initial
        if ($LASTEXITCODE -ne 0) { throw 'fixture initial commit failed' }

        # A relevant ignored local file is still visible to VMB, so it must
        # enter the working fingerprint and cannot silently contaminate a root.
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
        # excluded from its own map.
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

        # A first receipt for byte-identical clean source/root is still checked
        # against the working tree when BuildOnly invokes this gate with -Mod.
        $cleanMap = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        $cleanRoot = Get-VtBuildWorkingRootProof -RepoRoot $tempRoot -Mod 'example_mod'
        $cleanReceipt = New-VtBuildReceipt -Mod 'example_mod' -SourceMap $cleanMap -RootProof $cleanRoot
        $cleanReceiptPath = Write-VtBuildReceipt -RepoRoot $tempRoot -Mod 'example_mod' -Receipt $cleanReceipt
        $receiptBytesBefore = [System.IO.File]::ReadAllBytes($cleanReceiptPath)
        $null = Write-VtBuildReceipt -RepoRoot $tempRoot -Mod 'example_mod' -Receipt $cleanReceipt
        $receiptBytesAfter = [System.IO.File]::ReadAllBytes($cleanReceiptPath)
        if ([System.Convert]::ToBase64String($receiptBytesBefore) -cne
                [System.Convert]::ToBase64String($receiptBytesAfter)) {
            throw 'identical source/root did not produce deterministic receipt bytes'
        }
        $savedMod = $script:Mod
        $script:Mod = 'example_mod'
        try { $explicitContext = Get-VtBuildReceiptDiffContext -Root $tempRoot }
        finally { $script:Mod = $savedMod }
        if ($explicitContext.Mode -cne 'worktree') {
            throw 'explicit BuildOnly target did not select the just-written working-tree receipt'
        }
        $contextErrors = @(Test-VtBuildReceiptContext -Root $tempRoot `
            -Context $explicitContext -ModName 'example_mod')
        if ($contextErrors.Count -ne 0) {
            throw "byte-identical first receipt failed: $($contextErrors -join '; ')"
        }
        $passed++

        # Receipts from the Git-blob-only schema are not silently accepted by
        # the stronger raw-build-byte parser.
        $legacyReceipt = ConvertFrom-VtBuildReceiptJson -Json (ConvertTo-VtBuildReceiptJson -Receipt $cleanReceipt)
        $legacyReceipt.schema = 1
        $legacyReceipt.source_algorithm = 'git-blob-map-sha256-v1'
        $legacyResult = Test-VtBuildReceiptProof -Receipt $legacyReceipt -ExpectedMod 'example_mod' `
            -SourceMap $cleanMap -RootProof $cleanRoot
        if ($legacyResult.Ok -or ($legacyResult.Problems -join '; ') -notmatch 'legacy receipt schema 1') {
            throw 'legacy Git-blob-only receipt schema was not rejected clearly'
        }
        $passed++

        # A root mutation after a receipt is written must invalidate that
        # receipt even when the runtime source remains unchanged.
        [System.IO.File]::WriteAllBytes((Join-Path $tempRoot 'example_mod\bundleV2\aaaaaaaaaaaaaaaa.mod_bundle'),
            [System.Text.Encoding]::UTF8.GetBytes('root-after-receipt'))
        $mutatedRoot = Get-VtBuildWorkingRootProof -RepoRoot $tempRoot -Mod 'example_mod'
        $rootInvalid = Test-VtBuildReceiptProof -Receipt $cleanReceipt -ExpectedMod 'example_mod' `
            -SourceMap $cleanMap -RootProof $mutatedRoot
        if ($rootInvalid.Ok -or ($rootInvalid.Problems -join '; ') -notmatch 'root bundle') {
            throw 'direct post-receipt root mutation was accepted'
        }
        [System.IO.File]::WriteAllBytes((Join-Path $tempRoot 'example_mod\bundleV2\aaaaaaaaaaaaaaaa.mod_bundle'),
            [System.Text.Encoding]::UTF8.GetBytes('root-v1'))
        $passed++

        # Under text eol=lf, CRLF and LF have the same Git-clean blob but are
        # different raw build inputs. Pre/post BuildOnly comparison must see the
        # raw mutation, and a receipt made from the CRLF bytes must not validate
        # against the LF bytes that the staged blob will materialize on checkout.
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
        $crlfReceipt = New-VtBuildReceipt -Mod 'example_mod' -SourceMap $crlfMap -RootProof $cleanRoot
        & git -C $tempRoot add example_mod/scripts/main.lua
        $canonicalIndexMap = Get-VtBuildIndexSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        $canonicalIndexRoot = Get-VtBuildIndexRootProof -RepoRoot $tempRoot -Mod 'example_mod'
        $notReproducible = Test-VtBuildReceiptProof -Receipt $crlfReceipt -ExpectedMod 'example_mod' `
            -SourceMap $canonicalIndexMap -RootProof $canonicalIndexRoot
        if ($notReproducible.Ok -or ($notReproducible.Problems -join '; ') -notmatch 'raw build bytes') {
            throw 'raw BuildOnly bytes that staged Git cannot reproduce were accepted'
        }
        [System.IO.File]::WriteAllBytes($mainPath,
            [System.Text.Encoding]::UTF8.GetBytes("return 'v1'`n"))
        $passed++

        # Unchanged dirty source + generated root is accepted after staging.
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'example_mod\scripts\main.lua'), "return 'v2'`n")
        [System.IO.File]::WriteAllBytes((Join-Path $tempRoot 'example_mod\bundleV2\aaaaaaaaaaaaaaaa.mod_bundle'),
            [System.Text.Encoding]::UTF8.GetBytes('root-v2'))
        $before = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        $after = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        if (-not (Compare-VtBuildSourceMaps -Expected $before -Actual $after).Ok) {
            throw 'unchanged dirty working snapshot was rejected'
        }
        $root = Get-VtBuildWorkingRootProof -RepoRoot $tempRoot -Mod 'example_mod'
        $receipt = New-VtBuildReceipt -Mod 'example_mod' -SourceMap $after -RootProof $root
        $null = Write-VtBuildReceipt -RepoRoot $tempRoot -Mod 'example_mod' -Receipt $receipt
        & git -C $tempRoot add example_mod
        $indexMap = Get-VtBuildIndexSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        $indexRoot = Get-VtBuildIndexRootProof -RepoRoot $tempRoot -Mod 'example_mod'
        $valid = Test-VtBuildReceiptProof -Receipt $receipt -ExpectedMod 'example_mod' `
            -SourceMap $indexMap -RootProof $indexRoot
        if (-not $valid.Ok) { throw "unchanged staged snapshot failed: $($valid.Problems -join '; ')" }
        $indexContext = [pscustomobject]@{ Mode = 'index'; Head = 'INDEX'; Lines = @() }
        $contextErrors = @(Test-VtBuildReceiptContext -Root $tempRoot -Context $indexContext -ModName 'example_mod')
        if ($contextErrors.Count -ne 0) {
            throw "staged end-to-end receipt gate failed: $($contextErrors -join '; ')"
        }
        & git -C $tempRoot commit --quiet -m buildonly
        if ($LASTEXITCODE -ne 0) { throw 'fixture BuildOnly commit failed' }
        $commitMap = Get-VtBuildCommitSourceMap -RepoRoot $tempRoot -Mod 'example_mod' -Commit 'HEAD'
        $commitRoot = Get-VtBuildCommitRootProof -RepoRoot $tempRoot -Mod 'example_mod' -Commit 'HEAD'
        $committed = Test-VtBuildReceiptProof -Receipt $receipt -ExpectedMod 'example_mod' `
            -SourceMap $commitMap -RootProof $commitRoot
        if (-not $committed.Ok) {
            throw "unchanged committed snapshot failed: $($committed.Problems -join '; ')"
        }
        $commitContext = [pscustomobject]@{ Mode = 'commit'; Head = 'HEAD'; Lines = @() }
        $contextErrors = @(Test-VtBuildReceiptContext -Root $tempRoot `
            -Context $commitContext -ModName 'example_mod')
        if ($contextErrors.Count -ne 0) {
            throw "committed end-to-end receipt gate failed: $($contextErrors -join '; ')"
        }
        $passed++

        # The constrained first-upload lane compare-and-swaps only the cfg ID.
        # The root remains byte-identical, but the old receipt must fail until a
        # new BuildOnly receipt binds the positive-ID cfg bytes.
        $bootstrapCfg = Join-Path $tempRoot 'example_mod\itemV2.cfg'
        [System.IO.File]::WriteAllText($bootstrapCfg,
            "title = `"Example`";`npublished_id = 123456789L;`nvisibility = `"friends_only`";`n")
        $bootstrapMap = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        $bootstrapRoot = Get-VtBuildWorkingRootProof -RepoRoot $tempRoot -Mod 'example_mod'
        if ($bootstrapRoot.GitBlob -cne $root.GitBlob -or
                $bootstrapRoot.Sha256 -cne $root.Sha256) {
            throw 'first-upload ID-only fixture unexpectedly changed the canonical root'
        }
        $staleBootstrap = Test-VtBuildReceiptProof -Receipt $receipt `
            -ExpectedMod 'example_mod' -SourceMap $bootstrapMap -RootProof $bootstrapRoot
        if ($staleBootstrap.Ok -or
                ($staleBootstrap.Problems -join '; ') -notmatch 'source bytes changed') {
            throw 'first-upload ID-only cfg change retained a stale BuildOnly receipt'
        }
        $bootstrapReceipt = New-VtBuildReceipt -Mod 'example_mod' `
            -SourceMap $bootstrapMap -RootProof $bootstrapRoot
        $null = Write-VtBuildReceipt -RepoRoot $tempRoot -Mod 'example_mod' `
            -Receipt $bootstrapReceipt
        & git -C $tempRoot add example_mod/itemV2.cfg example_mod/.build-receipt.json
        $bootstrapIndexMap = Get-VtBuildIndexSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        $bootstrapIndexRoot = Get-VtBuildIndexRootProof -RepoRoot $tempRoot -Mod 'example_mod'
        $bootstrapValid = Test-VtBuildReceiptProof -Receipt $bootstrapReceipt `
            -ExpectedMod 'example_mod' -SourceMap $bootstrapIndexMap `
            -RootProof $bootstrapIndexRoot
        if (-not $bootstrapValid.Ok) {
            throw "refreshed first-upload receipt failed: $($bootstrapValid.Problems -join '; ')"
        }
        & git -C $tempRoot commit --quiet -m bootstrap-id
        if ($LASTEXITCODE -ne 0) { throw 'fixture first-upload ID commit failed' }
        $receipt = $bootstrapReceipt
        $indexRoot = $bootstrapIndexRoot
        $passed++

        # A root .gitattributes change can change checkout bytes for every mod
        # without touching a path under that mod. Every receipt-bearing mod must
        # therefore become a target, and the old receipt must fail if the new
        # attributes change materialization.
        $attributesPath = Join-Path $tempRoot '.gitattributes'
        $originalAttributes = [System.IO.File]::ReadAllBytes($attributesPath)
        [System.IO.File]::WriteAllBytes($attributesPath,
            [System.Text.Encoding]::UTF8.GetBytes("*.lua text eol=crlf`n*.ps1 text eol=crlf`n"))
        & git -C $tempRoot add .gitattributes
        # Deliberately diverge the working attributes back to LF after staging.
        # Index/commit materialization must use the exact staged attributes, not
        # whichever .gitattributes happens to be present in the caller checkout.
        [System.IO.File]::WriteAllBytes($attributesPath, $originalAttributes)
        $savedStaged = $script:Staged
        $script:Staged = $true
        try { $attributeContext = Get-VtBuildReceiptDiffContext -Root $tempRoot }
        finally { $script:Staged = $savedStaged }
        $attributeChanges = Convert-VtBuildReceiptChanges -Lines $attributeContext.Lines
        $attributeTargets = @(Get-VtBuildReceiptTargets `
            -Inventory @(@{ Dir = 'example_mod'; RootBundle = 'aaaaaaaaaaaaaaaa.mod_bundle' }) `
            -Changes $attributeChanges -ReceiptBearingMods @('example_mod'))
        if ($attributeTargets.Count -ne 1 -or $attributeTargets[0] -cne 'example_mod') {
            throw 'root .gitattributes change did not target the receipt-bearing mod'
        }
        $contextErrors = @(Test-VtBuildReceiptContext -Root $tempRoot `
            -Context $attributeContext -ModName 'example_mod')
        if ($contextErrors.Count -eq 0 -or ($contextErrors -join '; ') -notmatch 'raw build bytes') {
            throw 'checkout-materialization-changing root .gitattributes edit retained a stale receipt'
        }
        & git -C $tempRoot add .gitattributes
        $passed++

        # Type changes must enter the diff target set and non-regular staged
        # runtime inputs fail closed without requiring OS symlink privileges.
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
        $typeRejected = $false
        try { Get-VtBuildIndexSourceMap -RepoRoot $tempRoot -Mod 'example_mod' | Out-Null }
        catch { $typeRejected = ($_.Exception.Message -match 'non-regular staged runtime input') }
        if (-not $typeRejected) { throw 'staged symlink runtime input was accepted' }
        & git -C $tempRoot reset --quiet HEAD -- example_mod/scripts/main.lua
        $passed++

        # Generic local QA (no explicit -Mod) must still select a working-tree
        # context when an untracked runtime input is the only change.
        $untrackedRuntime = Join-Path $tempRoot 'example_mod\scripts\untracked.lua'
        [System.IO.File]::WriteAllBytes($untrackedRuntime,
            [System.Text.Encoding]::UTF8.GetBytes("return 'untracked'`n"))
        $savedMod = $script:Mod
        $script:Mod = $null
        try { $untrackedContext = Get-VtBuildReceiptDiffContext -Root $tempRoot }
        finally { $script:Mod = $savedMod }
        if ($untrackedContext.Mode -cne 'worktree') {
            throw 'ordinary local QA ignored an untracked runtime input'
        }
        $untrackedChanges = Convert-VtBuildReceiptChanges -Lines $untrackedContext.Lines
        $untrackedTargets = @(Get-VtBuildReceiptTargets `
            -Inventory @(@{ Dir = 'example_mod'; RootBundle = 'aaaaaaaaaaaaaaaa.mod_bundle' }) `
            -Changes $untrackedChanges -ReceiptBearingMods @('example_mod'))
        if ($untrackedTargets.Count -ne 1 -or $untrackedTargets[0] -cne 'example_mod') {
            throw 'ordinary local QA did not target the mod owning an untracked runtime input'
        }
        $contextErrors = @(Test-VtBuildReceiptContext -Root $tempRoot `
            -Context $untrackedContext -ModName 'example_mod')
        if ($contextErrors.Count -eq 0 -or ($contextErrors -join '; ') -notmatch 'source added') {
            throw 'ordinary local QA accepted an untracked runtime input beside a stale receipt'
        }
        Remove-Item -LiteralPath $untrackedRuntime -Force
        $passed++

        # A relevant source mutation during a build changes the exact map.
        $duringBefore = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'example_mod\scripts\main.lua'), "return 'during-build'`n")
        $duringAfter = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        if ((Compare-VtBuildSourceMaps -Expected $duringBefore -Actual $duringAfter).Ok) {
            throw 'during-build source mutation was accepted'
        }
        $passed++

        # Staging a source edit after BuildOnly invalidates the old receipt.
        & git -C $tempRoot add example_mod/scripts/main.lua
        $changedIndex = Get-VtBuildIndexSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        $invalid = Test-VtBuildReceiptProof -Receipt $receipt -ExpectedMod 'example_mod' `
            -SourceMap $changedIndex -RootProof $indexRoot
        if ($invalid.Ok -or ($invalid.Problems -join '; ') -notmatch 'source bytes changed') {
            throw 'post-BuildOnly staged source edit did not invalidate receipt'
        }
        $contextErrors = @(Test-VtBuildReceiptContext -Root $tempRoot -Context $indexContext -ModName 'example_mod')
        if ($contextErrors.Count -eq 0 -or ($contextErrors -join '; ') -notmatch 'source bytes changed') {
            throw 'staged end-to-end gate accepted a post-BuildOnly source edit'
        }
        $passed++

        # The source-plus-stale-root shape remains rejected by the old receipt.
        if ($invalid.Ok) { throw 'source plus stale root fixture was accepted' }
        $passed++

        # Optional/extra bundle sidecars are outside the source map; #1278 does
        # not alter the separate exact e785 normalization/count policy.
        $sidecarBefore = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        [System.IO.File]::WriteAllBytes((Join-Path $tempRoot 'example_mod\bundleV2\e7852992f40eb619.mod_bundle'),
            [System.Text.Encoding]::UTF8.GetBytes('tool-only-sidecar'))
        $sidecarAfter = Get-VtBuildWorkingSourceMap -RepoRoot $tempRoot -Mod 'example_mod'
        if (-not (Compare-VtBuildSourceMaps -Expected $sidecarBefore -Actual $sidecarAfter).Ok) {
            throw 'optional bundle sidecar contaminated the runtime source map'
        }
        $passed++

        Write-Host "[check_build_receipts -SelfTest] PASS $passed behavioral fixtures" -ForegroundColor Green
        return 0
    }
    finally {
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
        if (@($inventory.Mods | Where-Object { [string]$_.Dir -ceq $target }).Count -ne 1) {
            $errors += "${target}: not an active inventoried mod"
            continue
        }
        $errors += @(Test-VtBuildReceiptContext -Root $root -Context $context -ModName $target)
    }
    if ($errors.Count -gt 0) {
        Write-Host '[check_build_receipts] ERRORS - BuildOnly source/root receipt mismatch (#1278):' -ForegroundColor Red
        foreach ($errorMessage in $errors) { Write-Host "  X $errorMessage" -ForegroundColor Red }
        Write-Host '  Re-run the canonical BuildOnly command after the final source edit, then stage source, root bundle, and receipt together.' -ForegroundColor Yellow
        exit 2
    }
    if (-not $Quiet) {
        Write-Host "[check_build_receipts] OK - $($targets.Count) exact source/root receipt(s) match $($context.Head)." -ForegroundColor Green
    }
    exit 0
}
catch {
    Write-Host "[check_build_receipts] INFRASTRUCTURE ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 99
}
