# check_publication_receipt.ps1 - offline schema/capability fixtures for #724.

[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'tools\ship\publication-receipt.ps1')

if (-not $SelfTest) {
    Write-Host '[check_publication_receipt] Use -SelfTest for offline fixtures.'
    exit 0
}

$script:passed = 0
$script:failed = 0
function Assert-PublicationFixture {
    param([bool]$Condition, [string]$Name)
    if ($Condition) {
        $script:passed++
        if (-not $Quiet) { Write-Host "  [PASS] $Name" -ForegroundColor Green }
    }
    else {
        $script:failed++
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
    }
}

$goodCapability = Test-VmbLauncherPublicationCapabilityOutput -Lines @(
    'capability_schema=1',
    'version=0.6.0',
    'publication_receipt_schema=3',
    'capabilities=hosted-publication-receipt-v3,locked-upload-snapshot-v1,git-commit-blob-snapshot-v1,constrained-first-upload-bootstrap-v1,machine-transaction-lease-v1,crash-safe-upload-acl-journal-v1'
)
Assert-PublicationFixture $goodCapability.Ok 'accepts launcher 0.6.0 with every publication capability'
$oldCapability = Test-VmbLauncherPublicationCapabilityOutput -Lines @(
    'capability_schema=1',
    'version=0.5.9',
    'publication_receipt_schema=3',
    'capabilities=hosted-publication-receipt-v3,locked-upload-snapshot-v1,git-commit-blob-snapshot-v1,constrained-first-upload-bootstrap-v1'
)
Assert-PublicationFixture (-not $oldCapability.Ok) 'rejects launcher 0.5.9 before release mutation even with its complete legacy capability set'
$partialCapability = Test-VmbLauncherPublicationCapabilityOutput -Lines @(
    'capability_schema=1',
    'version=0.6.0',
    'publication_receipt_schema=3',
    'capabilities=hosted-publication-receipt-v3,locked-upload-snapshot-v1,git-commit-blob-snapshot-v1,constrained-first-upload-bootstrap-v1,machine-transaction-lease-v1'
)
Assert-PublicationFixture (-not $partialCapability.Ok) 'rejects launcher 0.6.0 without crash-safe ACL recovery capability'

$wocReceiptAsset = Get-WorkshopPublicationReceiptAssetName -Mod 'weapons_of_chaos'
Assert-PublicationFixture ($wocReceiptAsset -ceq 'publication-receipt-weapons_of_chaos.json') 'WOC receipt coordinate uses canonical lowercase source folder'
$uppercaseRejected = $false
try {
    $null = Get-WorkshopPublicationReceiptAssetName -Mod 'WOC'
}
catch {
    $uppercaseRejected = $true
}
Assert-PublicationFixture $uppercaseRejected 'receipt asset helper rejects uppercase manifest identifiers'

$publishReleaseSource = [System.IO.File]::ReadAllText(
    (Join-Path $repoRoot 'tools\publish-release\publish-release.ps1'))
$folderBoundProducer = $publishReleaseSource -match
    '\$assetName\s*=\s*Get-WorkshopPublicationReceiptAssetName\s+-Mod\s+\$receiptInput\.Folder'
$modIdBoundProducer = $publishReleaseSource -match
    'publication-receipt-\$\(\$receiptInput\.ModId\)\.json'
Assert-PublicationFixture ($folderBoundProducer -and -not $modIdBoundProducer) 'release producer binds receipt name to folder rather than WOC-style ModId'

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-publication-receipt-" + [guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($temp) | Out-Null
try {
    $mod = 'modx'
    $modRoot = Join-Path $temp $mod
    $bundleRoot = Join-Path $modRoot 'bundleV2'
    $luaRoot = Join-Path $modRoot 'scripts\mods\modx'
    $toolsRoot = Join-Path $temp 'tools'
    [System.IO.Directory]::CreateDirectory($bundleRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($luaRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($toolsRoot) | Out-Null
    $inventoryPath = Join-Path $toolsRoot 'mod-inventory.psd1'
    $inventoryText = "@{ Mods = @( @{ Dir = 'modx'; ModId = 'modx'; Name = 'Mod X'; BundleAuthority = 'tracked'; RootBundle = 'root.mod_bundle' } ) }`n"
    [System.IO.File]::WriteAllText(
        $inventoryPath, $inventoryText, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText(
        (Join-Path $modRoot 'itemV2.cfg'),
        "title = `"Mod X v1.2.3-dev`";`npreview = `"preview.jpg`";`nvisibility = `"private`";`npublished_id = 123L;`n")
    [System.IO.File]::WriteAllBytes(
        (Join-Path $modRoot 'preview.jpg'),
        [System.Text.Encoding]::UTF8.GetBytes('preview-v1'))
    [System.IO.File]::WriteAllText((Join-Path $modRoot 'modx.mod'), 'descriptor')
    [System.IO.File]::WriteAllText((Join-Path $bundleRoot 'modx.mod'), 'descriptor')
    [System.IO.File]::WriteAllText((Join-Path $bundleRoot 'root.mod_bundle'), 'bundle')
    [System.IO.File]::WriteAllText((Join-Path $luaRoot 'modx.lua'), 'local MOD_VERSION = "1.2.3-dev"')
    & git -C $temp init -q
    & git -C $temp config user.email 'qa@example.invalid'
    & git -C $temp config user.name 'Publication QA'
    & git -C $temp config core.autocrlf false
    & git -C $temp add .
    & git -C $temp commit -q -m 'commit-a'
    if ($LASTEXITCODE -ne 0) { throw 'Could not create publication commit fixture A.' }
    $commitA = (& git -C $temp rev-parse HEAD).Trim()

    $commitInventory = Get-PublicationCommitInventory `
        -RepoRoot $temp -SourceCommit $commitA
    Assert-PublicationFixture (
        @($commitInventory.Mods).Count -eq 1 -and
        [string]$commitInventory.Mods[0].BundleAuthority -ceq 'tracked' -and
        [string]$commitInventory.Mods[0].RootBundle -ceq 'root.mod_bundle'
    ) 'source-commit inventory is parsed as constant immutable data'
    [System.IO.File]::WriteAllText(
        $inventoryPath,
        "@{ Mods = @( @{ Dir = 'modx'; ModId = 'modx'; Name = 'Dirty'; BundleAuthority = 'receipt'; RootBundle = 'evil.mod_bundle' } ) }`n",
        [System.Text.UTF8Encoding]::new($false))
    $commitInventoryAfterDirtyEdit = Get-PublicationCommitInventory `
        -RepoRoot $temp -SourceCommit $commitA
    Assert-PublicationFixture (
        [string]$commitInventoryAfterDirtyEdit.Mods[0].BundleAuthority -ceq 'tracked' -and
        [string]$commitInventoryAfterDirtyEdit.Mods[0].RootBundle -ceq 'root.mod_bundle'
    ) 'dirty worktree inventory cannot alter source-commit publication authority'
    [System.IO.File]::WriteAllText(
        $inventoryPath, $inventoryText, [System.Text.UTF8Encoding]::new($false))

    $authorization = [pscustomobject]@{ mode = 'hosted_qa' }
    $receipt = New-WorkshopPublicationReceipt `
        -RepoRoot $temp `
        -Repository 'Ensrick/vermintide-2-tweaker' `
        -ReleaseTag 'mods-2026-07-26' `
        -ReceiptAssetName 'publication-receipt-modx.json' `
        -Mod $mod `
        -Version '1.2.3-dev' `
        -Owner 'codex:724' `
        -SourceCommit $commitA `
        -AuthorizationEvidence $authorization

    Assert-PublicationFixture ("$($receipt.schema)" -eq '3') 'receipt schema is 3'
    Assert-PublicationFixture ("$($receipt.item_cfg_git_blob)" -match '^[0-9a-f]{40}$' -and
        @($receipt.bundle_files | Where-Object { "$($_.git_blob)" -notmatch '^[0-9a-f]{40}$' }).Count -eq 0) 'cfg and every bundle proof are exact source-commit blobs'
    Assert-PublicationFixture ($receipt.preview_file.present -and
        "$($receipt.preview_file.path)" -eq 'preview.jpg' -and
        "$($receipt.preview_file.sha256)" -match '^[0-9a-f]{64}$' -and
        "$($receipt.preview_file.git_blob)" -match '^[0-9a-f]{40}$') 'receipt binds exact preview blob, name, length, and SHA-256'
    $boundHash = "$($receipt.preview_file.sha256)"

    # Move HEAD and mutate the working tree after receipt issuance. A second
    # proof for commit A must still return commit A's exact object bytes.
    [System.IO.File]::WriteAllText((Join-Path $modRoot 'preview.jpg'), 'preview-v2')
    [System.IO.File]::WriteAllText((Join-Path $bundleRoot 'modx.mod'), 'descriptor-v2')
    & git -C $temp add .
    & git -C $temp commit -q -m 'commit-b'
    $commitB = (& git -C $temp rev-parse HEAD).Trim()
    [System.IO.File]::WriteAllText((Join-Path $modRoot 'preview.jpg'), 'preview-uncommitted-v3')
    $commitAProof = Get-PublicationPreviewProof -RepoRoot $temp -SourceCommit $commitA -Mod $mod
    Assert-PublicationFixture ($commitA -ne $commitB -and
        "$($commitAProof.sha256)" -eq $boundHash) 'HEAD/working-tree commit swap cannot change the receipt-selected preview blob'

    [System.IO.File]::WriteAllText(
        (Join-Path $modRoot 'itemV2.cfg'),
        "title = `"Mod X v1.2.3-dev`";`npreview = `"..\\outside.jpg`";`nvisibility = `"private`";`npublished_id = 123L;`n")
    [System.IO.File]::WriteAllText((Join-Path $temp 'outside.jpg'), 'outside')
    & git -C $temp add .
    & git -C $temp commit -q -m 'traversal'
    $traversalCommit = (& git -C $temp rev-parse HEAD).Trim()
    $traversalProof = Get-PublicationPreviewProof -RepoRoot $temp -SourceCommit $traversalCommit -Mod $mod
    Assert-PublicationFixture ("$($traversalProof.path)" -eq 'preview.jpg' -and
        $traversalProof.present) 'preview traversal is rejected and safe in-mod fallback is bound'

    [System.IO.File]::WriteAllText(
        (Join-Path $modRoot 'itemV2.cfg'),
        "title = `"Mod X v1.2.3-dev`";`npreview = `"preview.jpg`";`nvisibility = `"private`";`npublished_id = 0L;`n")
    & git -C $temp add .
    & git -C $temp commit -q -m 'first-upload'
    $firstUploadCommit = (& git -C $temp rev-parse HEAD).Trim()
    $firstUploadReceipt = New-WorkshopPublicationReceipt `
        -RepoRoot $temp `
        -Repository 'Ensrick/vermintide-2-tweaker' `
        -ReleaseTag 'mods-2026-07-26' `
        -ReceiptAssetName 'publication-receipt-modx.json' `
        -Mod $mod `
        -Version '1.2.3-dev' `
        -Owner 'codex:724' `
        -SourceCommit $firstUploadCommit `
        -AuthorizationEvidence $authorization
    Assert-PublicationFixture ("$($firstUploadReceipt.purpose)" -eq 'workshop_bootstrap' -and
        "$($firstUploadReceipt.item_cfg_git_blob)" -match '^[0-9a-f]{40}$') 'first-upload receipt keeps exact blob authority and uses the constrained bootstrap purpose'
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

if ($script:failed -gt 0) {
    Write-Host "[check_publication_receipt] FAILED -- $script:failed fixture(s) failed." -ForegroundColor Red
    exit 2
}
if (-not $Quiet) {
    Write-Host "[check_publication_receipt] OK -- $script:passed offline fixtures passed." -ForegroundColor Green
}
exit 0
