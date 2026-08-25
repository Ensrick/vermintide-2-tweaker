# check_vmb_launcher_path.ps1
#
# Offline regressions for issues #683 and #1400. The canonical ship and
# standalone release paths must share one approved VMBLauncher resolver, retain
# a live executable lease from approval through process exit, and record proof
# for the exact immutable executable bytes that were launched.

[CmdletBinding()]
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$pathHelpers = Join-Path $repoRoot 'tools\vmb-launcher-path.ps1'
$manifestHelpers = Join-Path $repoRoot 'tools\publish-release\release-manifest.ps1'

$failures = New-Object 'System.Collections.Generic.List[string]'
function Assert-Contract {
    param([bool]$Condition, [string]$Description)
    if ($Condition) {
        Write-Host "  [PASS] $Description" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
        $failures.Add($Description)
    }
}

function Assert-Rejected {
    param([scriptblock]$Action, [string]$Pattern, [string]$Description)
    $rejected = $false
    try { & $Action | Out-Null }
    catch { $rejected = $_.Exception.Message -match $Pattern }
    Assert-Contract $rejected $Description
}

function Test-IsFileAccessDenial {
    param([System.Exception]$Exception)
    $current = $Exception
    while ($null -ne $current) {
        if ($current -is [System.IO.IOException] -or
                $current -is [System.UnauthorizedAccessException]) {
            return $true
        }
        $current = $current.InnerException
    }
    return $false
}

function Assert-IoDenied {
    param([scriptblock]$Action, [string]$Description)
    $denied = $false
    $detail = 'operation unexpectedly succeeded'
    try { & $Action | Out-Null }
    catch {
        $denied = Test-IsFileAccessDenial -Exception $_.Exception
        $detail = $_.Exception.GetType().FullName + ': ' + $_.Exception.Message
    }
    Assert-Contract $denied $Description
    if (-not $denied) { Write-Host "    diagnostic: $detail" -ForegroundColor DarkYellow }
}

function Assert-IoAllowed {
    param([scriptblock]$Action, [string]$Description)
    $allowed = $true
    $detail = $null
    try { & $Action | Out-Null }
    catch {
        $allowed = $false
        $detail = $_.Exception.GetType().FullName + ': ' + $_.Exception.Message
    }
    Assert-Contract $allowed $Description
    if (-not $allowed) { Write-Host "    diagnostic: $detail" -ForegroundColor DarkYellow }
}

function New-LeaseProofCopy {
    param([Parameter(Mandatory = $true)]$Proof)
    return [pscustomobject][ordered]@{
        schema = $Proof.schema
        requested_path = $Proof.requested_path
        canonical_path = $Proof.canonical_path
        file_id = $Proof.file_id
        length = $Proof.length
        sha256 = $Proof.sha256
        version = $Proof.version
    }
}

function Test-LeaseProofEqual {
    param($Left, $Right)
    $names = @(
        'schema', 'requested_path', 'canonical_path', 'file_id',
        'length', 'sha256', 'version')
    if ($null -eq $Left -or $null -eq $Right) { return $false }
    if ((@($Left.PSObject.Properties.Name) -join ',') -cne ($names -join ',') -or
            (@($Right.PSObject.Properties.Name) -join ',') -cne ($names -join ',')) {
        return $false
    }
    foreach ($name in $names) {
        $leftValue = $Left.$name
        $rightValue = $Right.$name
        if ($leftValue.GetType() -ne $rightValue.GetType()) { return $false }
        if ($leftValue -is [string]) {
            if ([string]$leftValue -cne [string]$rightValue) { return $false }
        }
        elseif ($leftValue -ne $rightValue) { return $false }
    }
    return $true
}

function Remove-TestJunction {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -ne $item) { $item.Delete() }
}

Write-Host '=== check_vmb_launcher_path ===' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $pathHelpers -PathType Leaf)) {
    Write-Host "[check_vmb_launcher_path] ERROR -- missing $pathHelpers" -ForegroundColor Red
    exit 2
}
if (-not (Test-Path -LiteralPath $manifestHelpers -PathType Leaf)) {
    Write-Host "[check_vmb_launcher_path] ERROR -- missing $manifestHelpers" -ForegroundColor Red
    exit 2
}
. $pathHelpers
. $manifestHelpers

$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
$fixtureRoot = Join-Path $tempRoot ("vt2-launcher-683-" + [guid]::NewGuid().ToString('N'))
$invokingRoot = Join-Path $fixtureRoot 'clean-worktree'
$configuredRoot = Join-Path $fixtureRoot 'configured-project'
$primaryRoot = Join-Path $fixtureRoot 'primary-worktree'
$outsiderRoot = Join-Path $fixtureRoot 'outside-approved-roots'
$relative = 'tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe'
$activeLeases = New-Object 'System.Collections.Generic.List[object]'
$junctionPaths = New-Object 'System.Collections.Generic.List[string]'

[System.IO.Directory]::CreateDirectory($invokingRoot) | Out-Null
[System.IO.Directory]::CreateDirectory($configuredRoot) | Out-Null
[System.IO.Directory]::CreateDirectory($primaryRoot) | Out-Null
[System.IO.Directory]::CreateDirectory($outsiderRoot) | Out-Null

try {
    # cmd.exe is a self-contained, versioned Windows executable that remains
    # runnable after copying. A copied pwsh.exe is not self-contained because
    # its managed payload is resolved relative to the executable.
    $hostExecutable = [System.Environment]::GetEnvironmentVariable('ComSpec')
    if ([string]::IsNullOrWhiteSpace($hostExecutable)) {
        $hostExecutable = Join-Path $env:SystemRoot 'System32\cmd.exe'
    }
    Assert-Contract (Test-Path -LiteralPath $hostExecutable -PathType Leaf) 'versioned child-process fixture executable is available'

    $configuredLauncher = Join-Path $configuredRoot $relative
    [System.IO.Directory]::CreateDirectory((Split-Path $configuredLauncher -Parent)) | Out-Null
    Copy-Item -LiteralPath $hostExecutable -Destination $configuredLauncher

    $settingsPath = Join-Path $fixtureRoot 'settings.json'
    $settingsJson = @{ ProjectRoot = $configuredRoot } | ConvertTo-Json
    [System.IO.File]::WriteAllText($settingsPath, $settingsJson, (New-Object System.Text.UTF8Encoding($false)))
    $configuredFromSettings = Get-VmbLauncherConfiguredProjectRoot -SettingsPath $settingsPath
    Assert-Contract (Test-VmbLauncherPathEqual $configuredFromSettings $configuredRoot) 'configured ProjectRoot is read exactly'

    $fallback = Resolve-ApprovedVmbLauncherPath `
        -RepoRoot $invokingRoot `
        -ConfiguredProjectRoot $configuredFromSettings `
        -PrimaryWorktreeRoot $primaryRoot
    Assert-Contract (Test-VmbLauncherPathEqual $fallback.Path $configuredLauncher) 'clean worktree resolves the external configured launcher'
    Assert-Contract ($fallback.Source -eq 'VMBLauncher configured ProjectRoot') 'clean-worktree fallback retains configured-root provenance'

    $handoff = Resolve-ApprovedVmbLauncherPath `
        -RepoRoot $invokingRoot `
        -RequestedPath $fallback.Path `
        -RequestedSource $fallback.Source `
        -RequestedApprovalAnchor $fallback.ApprovalAnchor `
        -ConfiguredProjectRoot $primaryRoot `
        -PrimaryWorktreeRoot $primaryRoot
    Assert-Contract ((Test-VmbLauncherPathEqual $handoff.Path $fallback.Path) -and
        $handoff.Source -eq $fallback.Source -and
        (Test-VmbLauncherPathEqual $handoff.ApprovalAnchor $configuredRoot)) 'ship-to-release exact approval snapshot revalidates despite mutable configured-root drift'

    $version = Get-VmbLauncherVersion -LauncherPath $handoff.Path
    $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($configuredLauncher)
    $expectedVersion = "$($versionInfo.ProductVersion)".Trim()
    if (-not $expectedVersion) { $expectedVersion = "$($versionInfo.FileVersion)".Trim() }
    Assert-Contract (-not [string]::IsNullOrWhiteSpace($version)) 'validated launcher exposes real version metadata'
    Assert-Contract ($version -ceq $expectedVersion) 'compatibility version wrapper reads the exact approved executable'

    # The primary lease proof is both a schema/type contract and the capability
    # handed through the same runspace to every process launch.
    $leaseOutput = @(Enter-VmbLauncherExecutableLease `
        -LauncherPath $configuredLauncher -RequireDirectPath)
    Assert-Contract ($leaseOutput.Count -eq 1 -and
        $null -ne $leaseOutput[0].Proof -and
        $leaseOutput[0].Stream -is [System.IO.FileStream]) 'direct-path lease entry returns only the live lease capability'
    $lease = $leaseOutput[-1]
    $activeLeases.Add($lease)
    $proof = $lease.Proof
    $proofNames = @($proof.PSObject.Properties | ForEach-Object { [string]$_.Name })
    $expectedProofNames = @(
        'schema', 'requested_path', 'canonical_path', 'file_id',
        'length', 'sha256', 'version')
    Assert-Contract (($proofNames -join ',') -ceq ($expectedProofNames -join ',')) 'lease proof exposes exactly the ordered schema-1 field set'
    Assert-Contract ($proof.schema -is [int] -and [int]$proof.schema -eq 1) 'lease proof schema is exactly Int32 1'
    Assert-Contract ($proof.length -is [long] -and [long]$proof.length -gt 0) 'lease proof length is a positive Int64'
    Assert-Contract ($proof.requested_path -is [string] -and
        $proof.canonical_path -is [string] -and
        $proof.file_id -is [string] -and
        $proof.sha256 -is [string] -and
        $proof.version -is [string]) 'lease proof path, identity, hash, and version fields are exact strings'
    Assert-Contract ([string]$proof.file_id -cmatch '^[0-9a-f]{8}:[0-9a-f]{16}$') 'lease proof file identity has the canonical volume-and-file format'
    Assert-Contract ([string]$proof.sha256 -cmatch '^[0-9a-f]{64}$') 'lease proof SHA-256 is canonical lowercase hex'
    Assert-Contract ($lease.Stream -is [System.IO.FileStream] -and
        $lease.Stream.CanRead -and -not $lease.Disposed) 'lease retains a readable live FileStream capability'

    $pathIdentity = Get-VmbLauncherPathIdentity -Path $configuredLauncher
    $expectedHash = (Get-FileHash -LiteralPath $configuredLauncher -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Contract ((Test-VmbLauncherPathEqual $proof.requested_path $configuredLauncher) -and
        (Test-VmbLauncherPathEqual $proof.canonical_path $configuredLauncher) -and
        $proof.file_id -ceq $pathIdentity.file_id -and
        $proof.length -eq $pathIdentity.length -and
        $proof.sha256 -ceq $expectedHash -and
        $proof.version -ceq $expectedVersion) 'lease proof binds the exact requested path, canonical file identity, bytes, and version'

    $caseOnlyExpectedPath = $configuredLauncher.ToUpperInvariant()
    $caseProof = Assert-VmbLauncherExecutableLease `
        -Lease $lease -ExpectedRequestedPath $caseOnlyExpectedPath -VerifyContent
    Assert-Contract (Test-LeaseProofEqual $caseProof $proof) 'case-only expected-path variation preserves the exact lease proof'

    $siblingLauncher = Join-Path (Split-Path $configuredLauncher -Parent) 'sibling\VMBLauncher.exe'
    [System.IO.Directory]::CreateDirectory((Split-Path $siblingLauncher -Parent)) | Out-Null
    Copy-Item -LiteralPath $hostExecutable -Destination $siblingLauncher
    Assert-Rejected {
        Assert-VmbLauncherExecutableLease -Lease $lease -ExpectedRequestedPath $siblingLauncher
    } 'requested path differs from the approved path' 'an existing sibling expected path cannot match the leased path'

    $prefixLauncher = $configuredLauncher + '.prefix'
    Copy-Item -LiteralPath $hostExecutable -Destination $prefixLauncher
    Assert-Rejected {
        Assert-VmbLauncherExecutableLease -Lease $lease -ExpectedRequestedPath $prefixLauncher
    } 'requested path differs from the approved path' 'an existing lexical-prefix expected path cannot match the leased path'

    $sameRunspaceHandoff = & {
        param($BorrowedLease, [string]$ExpectedPath, $OriginalStream)
        $borrowedProof = Assert-VmbLauncherExecutableLease `
            -Lease $BorrowedLease -ExpectedRequestedPath $ExpectedPath -VerifyContent
        return [pscustomobject]@{
            Proof = $borrowedProof
            SameStream = [object]::ReferenceEquals($BorrowedLease.Stream, $OriginalStream)
        }
    } -BorrowedLease $lease -ExpectedPath $configuredLauncher -OriginalStream $lease.Stream
    Assert-Contract ($sameRunspaceHandoff.SameStream -and
        (Test-LeaseProofEqual $sameRunspaceHandoff.Proof $proof)) 'same-runspace handoff preserves the live stream object and exact proof'

    $childRun = Invoke-VmbLauncherProcess `
        -Lease $lease `
        -ArgumentList @('/d', '/c', 'echo', 'lease-child-ok') `
        -WorkingDirectory $fixtureRoot
    Assert-Contract ($childRun.ExitCode -eq 0 -and
        @($childRun.Lines) -contains 'lease-child-ok') 'leased executable starts a real child process and captures its successful output'
    Assert-Contract (Test-LeaseProofEqual $childRun.ExecutableProof $proof) 'child-process result returns the exact preapproved executable proof'

    $nullStreamForgery = [pscustomobject]@{
        Proof = New-LeaseProofCopy -Proof $proof
        Stream = $null
        Disposed = $false
    }
    Assert-Rejected {
        Assert-VmbLauncherExecutableLease -Lease $nullStreamForgery -VerifyContent
    } 'missing, disposed, or unreadable' 'a forged lease without the held FileStream is rejected'

    $forgedBackingPath = Join-Path $fixtureRoot 'forged-backing.exe'
    Copy-Item -LiteralPath $hostExecutable -Destination $forgedBackingPath
    $forgedBackingLease = Enter-VmbLauncherExecutableLease -LauncherPath $forgedBackingPath
    $activeLeases.Add($forgedBackingLease)
    $wrongHandleForgery = [pscustomobject]@{
        Proof = New-LeaseProofCopy -Proof $proof
        Stream = $forgedBackingLease.Stream
        Disposed = $false
    }
    Assert-Rejected {
        Assert-VmbLauncherExecutableLease -Lease $wrongHandleForgery -VerifyContent
    } 'live handle identity differs from its lease proof' 'a forged lease pairing valid proof with a different live file handle is rejected'
    Exit-VmbLauncherExecutableLease -Lease $forgedBackingLease

    $extraFieldProof = New-LeaseProofCopy -Proof $proof
    $extraFieldProof | Add-Member -NotePropertyName injected -NotePropertyValue 'forged'
    $extraFieldForgery = [pscustomobject]@{
        Proof = $extraFieldProof
        Stream = $lease.Stream
        Disposed = $false
    }
    Assert-Rejected {
        Assert-VmbLauncherExecutableLease -Lease $extraFieldForgery
    } 'malformed or non-canonical' 'a proof with an injected field is rejected even when paired with the live stream'

    $savedLength = [long]$lease.Proof.length
    $lease.Proof.length = [int]$savedLength
    Assert-Rejected {
        Assert-VmbLauncherExecutableLease -Lease $lease
    } 'malformed or non-canonical' 'a live lease mutated to a non-Int64 length is rejected'
    $lease.Proof.length = [long]$savedLength

    $savedSha256 = [string]$lease.Proof.sha256
    $lease.Proof.sha256 = ('0' * 64)
    Assert-Rejected {
        Assert-VmbLauncherExecutableLease -Lease $lease -VerifyContent
    } 'content or version differs from its lease proof' 'a live lease mutated to a false but well-formed SHA-256 is rejected'
    $lease.Proof.sha256 = $savedSha256
    Assert-Contract (Test-LeaseProofEqual `
        (Assert-VmbLauncherExecutableLease -Lease $lease -VerifyContent) $proof) 'restoring the exact proof restores valid lease verification'

    Exit-VmbLauncherExecutableLease -Lease $lease
    Assert-Rejected {
        Assert-VmbLauncherExecutableLease -Lease $lease -VerifyContent
    } 'missing, disposed, or unreadable' 'a disposed lease cannot be reused'

    # FileShare.Read must make all mutation classes fail while held, without
    # leaving a permanent lock once the lease is released.
    $mutationLauncher = Join-Path $fixtureRoot 'mutation-target.exe'
    $replacementSource = Join-Path $fixtureRoot 'replacement-source.exe'
    $deniedReplacementBackup = Join-Path $fixtureRoot 'denied-replacement-backup.exe'
    $allowedReplacementBackup = Join-Path $fixtureRoot 'allowed-replacement-backup.exe'
    $renamedLauncher = Join-Path $fixtureRoot 'mutation-renamed.exe'
    Copy-Item -LiteralPath $hostExecutable -Destination $mutationLauncher
    Copy-Item -LiteralPath $hostExecutable -Destination $replacementSource
    $mutationLease = Enter-VmbLauncherExecutableLease -LauncherPath $mutationLauncher
    $activeLeases.Add($mutationLease)
    $mutationProof = Assert-VmbLauncherExecutableLease -Lease $mutationLease -VerifyContent

    Assert-IoDenied {
        $writer = [System.IO.File]::Open(
            $mutationLauncher,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Write,
            ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        $writer.Dispose()
    } 'opening the leased executable for write is denied while held'
    Assert-IoDenied {
        [System.IO.File]::Delete($mutationLauncher)
    } 'deleting the leased executable is denied while held'
    Assert-IoDenied {
        [System.IO.File]::Move($mutationLauncher, $renamedLauncher)
    } 'renaming the leased executable is denied while held'
    Assert-IoDenied {
        [System.IO.File]::Replace(
            $replacementSource, $mutationLauncher, $deniedReplacementBackup, $true)
    } 'replacing the leased executable is denied while held'
    Assert-Contract ((Test-Path -LiteralPath $mutationLauncher -PathType Leaf) -and
        (Test-Path -LiteralPath $replacementSource -PathType Leaf) -and
        (Test-LeaseProofEqual `
            (Assert-VmbLauncherExecutableLease -Lease $mutationLease -VerifyContent) `
            $mutationProof)) 'denied mutation attempts leave the held file and proof unchanged'

    Exit-VmbLauncherExecutableLease -Lease $mutationLease
    Assert-IoAllowed {
        $writer = [System.IO.File]::Open(
            $mutationLauncher,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Write,
            ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        $writer.Dispose()
    } 'write access is restored after lease release'
    Assert-IoAllowed {
        [System.IO.File]::Move($mutationLauncher, $renamedLauncher)
        [System.IO.File]::Move($renamedLauncher, $mutationLauncher)
    } 'rename access is restored after lease release'
    Assert-IoAllowed {
        [System.IO.File]::Replace(
            $replacementSource, $mutationLauncher, $allowedReplacementBackup, $true)
    } 'replacement access is restored after lease release'
    Assert-IoAllowed {
        [System.IO.File]::Delete($mutationLauncher)
    } 'delete access is restored after lease release'

    $alteredLauncher = Join-Path $fixtureRoot 'same-version-altered-bytes.exe'
    Copy-Item -LiteralPath $hostExecutable -Destination $alteredLauncher
    $appendStream = [System.IO.File]::Open(
        $alteredLauncher,
        [System.IO.FileMode]::Append,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None)
    try { $appendStream.WriteByte([byte]0xA5) }
    finally { $appendStream.Dispose() }
    $originalLease = Enter-VmbLauncherExecutableLease -LauncherPath $configuredLauncher
    $activeLeases.Add($originalLease)
    $alteredLease = Enter-VmbLauncherExecutableLease -LauncherPath $alteredLauncher
    $activeLeases.Add($alteredLease)
    Assert-Contract ($originalLease.Proof.version -ceq $alteredLease.Proof.version -and
        $originalLease.Proof.sha256 -cne $alteredLease.Proof.sha256 -and
        $originalLease.Proof.length -ne $alteredLease.Proof.length) 'same-version executable bytes with a one-byte alteration produce a distinct SHA-256 proof'
    Exit-VmbLauncherExecutableLease -Lease $alteredLease
    Exit-VmbLauncherExecutableLease -Lease $originalLease

    # Enter without direct-path enforcement intentionally proves the handle's
    # canonical target. Subsequent path disappearance or junction retargeting
    # must invalidate that lease, while approved resolution rejects the escape.
    $junctionTargetOne = Join-Path $outsiderRoot 'junction-target-one'
    $junctionTargetTwo = Join-Path $outsiderRoot 'junction-target-two'
    [System.IO.Directory]::CreateDirectory($junctionTargetOne) | Out-Null
    [System.IO.Directory]::CreateDirectory($junctionTargetTwo) | Out-Null
    $junctionTargetOneExe = Join-Path $junctionTargetOne 'VMBLauncher.exe'
    $junctionTargetTwoExe = Join-Path $junctionTargetTwo 'VMBLauncher.exe'
    Copy-Item -LiteralPath $hostExecutable -Destination $junctionTargetOneExe
    Copy-Item -LiteralPath $hostExecutable -Destination $junctionTargetTwoExe
    $junctionPath = Join-Path $fixtureRoot 'lease-junction'
    $junctionPaths.Add($junctionPath)
    New-Item -ItemType Junction -Path $junctionPath -Target $junctionTargetOne | Out-Null
    $junctionRequested = Join-Path $junctionPath 'VMBLauncher.exe'
    $junctionLease = Enter-VmbLauncherExecutableLease -LauncherPath $junctionRequested
    $activeLeases.Add($junctionLease)
    $junctionTargetIdentity = Get-VmbLauncherPathIdentity -Path $junctionTargetOneExe
    Assert-Contract ((Test-VmbLauncherPathEqual `
            $junctionLease.Proof.requested_path $junctionRequested) -and
        (Test-VmbLauncherPathEqual `
            $junctionLease.Proof.canonical_path $junctionTargetOneExe) -and
        $junctionLease.Proof.file_id -ceq $junctionTargetIdentity.file_id) 'direct lease entry through a junction records the lexical request and canonical target identity'

    Remove-TestJunction -Path $junctionPath
    Assert-Contract (-not (Test-Path -LiteralPath $junctionRequested)) 'junction disappearance removes the lexical requested path while its target handle remains held'
    Assert-Rejected {
        Assert-VmbLauncherExecutableLease -Lease $junctionLease -VerifyContent
    } '(cannot find|could not find|no longer resolves|part of the path|does not exist)' 'junction disappearance invalidates the live lease proof'

    New-Item -ItemType Junction -Path $junctionPath -Target $junctionTargetTwo | Out-Null
    Assert-Rejected {
        Assert-VmbLauncherExecutableLease -Lease $junctionLease -VerifyContent
    } 'no longer resolves to its leased executable' 'junction retargeting to same bytes at a different identity invalidates the live lease proof'
    Exit-VmbLauncherExecutableLease -Lease $junctionLease
    Assert-Rejected {
        Enter-VmbLauncherExecutableLease -LauncherPath $junctionRequested -RequireDirectPath
    } 'refuses a reparse-point path component' 'direct-path lease entry rejects a junction component'

    $escapeConfiguredRoot = Join-Path $fixtureRoot 'junction-configured-project'
    $escapePublishParent = Join-Path $escapeConfiguredRoot 'tools\vmb-launcher\bin\Release\net9.0-windows\win-x64'
    $escapeTarget = Join-Path $outsiderRoot 'resolver-junction-target'
    [System.IO.Directory]::CreateDirectory($escapePublishParent) | Out-Null
    [System.IO.Directory]::CreateDirectory($escapeTarget) | Out-Null
    Copy-Item -LiteralPath $hostExecutable -Destination (Join-Path $escapeTarget 'VMBLauncher.exe')
    $escapePublishJunction = Join-Path $escapePublishParent 'publish'
    $junctionPaths.Add($escapePublishJunction)
    New-Item -ItemType Junction -Path $escapePublishJunction -Target $escapeTarget | Out-Null
    Assert-Rejected {
        Resolve-ApprovedVmbLauncherPath `
            -RepoRoot $invokingRoot `
            -ConfiguredProjectRoot $escapeConfiguredRoot
    } 'refuses a reparse-point path component' 'approved resolver rejects a configured-root junction escape'

    $outsideLauncher = Join-Path $outsiderRoot 'VMBLauncher.exe'
    Copy-Item -LiteralPath $hostExecutable -Destination $outsideLauncher
    Assert-Rejected {
        Resolve-ApprovedVmbLauncherPath `
            -RepoRoot $invokingRoot `
            -RequestedPath $outsideLauncher `
            -ConfiguredProjectRoot $configuredFromSettings `
            -PrimaryWorktreeRoot $primaryRoot
    } 'not an approved machine-local candidate' 'existing but unapproved explicit launcher path fails closed'

    Assert-Rejected {
        Resolve-ApprovedVmbLauncherPath `
            -RepoRoot $invokingRoot `
            -RequestedPath $configuredLauncher `
            -RequestedSource 'invoking worktree' `
            -RequestedApprovalAnchor $configuredRoot `
            -ConfiguredProjectRoot $configuredFromSettings `
            -PrimaryWorktreeRoot $primaryRoot
    } 'source/provenance mismatch' 'launcher path/source provenance mismatch fails closed'

    $emptyRoot = Join-Path $fixtureRoot 'no-launcher'
    [System.IO.Directory]::CreateDirectory($emptyRoot) | Out-Null
    Assert-Rejected {
        Resolve-ApprovedVmbLauncherPath -RepoRoot $emptyRoot
    } 'not found in any approved' 'standalone fallback fails closed without an approved launcher'

    $missingOverride = Join-Path $fixtureRoot 'missing-explicit.exe'
    Assert-Rejected {
        Resolve-ApprovedVmbLauncherPath `
            -RepoRoot $invokingRoot `
            -ConfiguredProjectRoot $configuredFromSettings `
            -EnvironmentPath $missingOverride
    } 'VT2_SHIP_VMB_LAUNCHER points to a missing file' 'invalid environment override never silently falls back'

    $shipPath = Join-Path $repoRoot 'tools\ship\ship.ps1'
    $publishPath = Join-Path $repoRoot 'tools\publish-release\publish-release.ps1'
    $runAllPath = Join-Path $repoRoot 'qa\run_all.ps1'
    $pathHelperText = [System.IO.File]::ReadAllText($pathHelpers, [System.Text.Encoding]::UTF8)
    $shipText = [System.IO.File]::ReadAllText($shipPath, [System.Text.Encoding]::UTF8)
    $publishText = [System.IO.File]::ReadAllText($publishPath, [System.Text.Encoding]::UTF8)
    $runAllText = [System.IO.File]::ReadAllText($runAllPath, [System.Text.Encoding]::UTF8)

    $proofBeforePos = $pathHelperText.IndexOf('$proofBefore = Assert-VmbLauncherExecutableLease')
    $processStartPos = $pathHelperText.IndexOf('$process.Start()', $proofBeforePos + 1)
    $processWaitPos = $pathHelperText.IndexOf('$process.WaitForExit()', $processStartPos + 1)
    $proofAfterPos = $pathHelperText.IndexOf('$proofAfter = Assert-VmbLauncherExecutableLease', $processWaitPos + 1)
    Assert-Contract ($proofBeforePos -ge 0 -and
        $processStartPos -gt $proofBeforePos -and
        $processWaitPos -gt $processStartPos -and
        $proofAfterPos -gt $processWaitPos -and
        $pathHelperText.Contains('$proofBefore = Assert-VmbLauncherExecutableLease -Lease $Lease -VerifyContent') -and
        $pathHelperText.Contains('$proofAfter = Assert-VmbLauncherExecutableLease -Lease $Lease -VerifyContent') -and
        $pathHelperText.Contains('$startInfo.FileName = [string]$proofBefore.canonical_path')) 'process helper verifies the lease before Start, launches its canonical handle path, and re-verifies after WaitForExit'

    Assert-Contract ($publishText -match '(?m)^\s*\[string\]\$LauncherPath\b' -and
        $publishText -match '(?m)^\s*\[string\]\$LauncherSource\b' -and
        $publishText -match '(?m)^\s*\[string\]\$LauncherApprovalAnchor\b' -and
        $publishText -match '(?m)^\s*\[object\]\$LauncherExecutableLease\b') 'release publisher declares path provenance plus the live executable-lease handoff'
    Assert-Contract ($publishText.Contains('$effectiveLauncherLease = $LauncherExecutableLease') -and
        $publishText.Contains('-Lease $LauncherExecutableLease') -and
        $publishText.Contains('-ExpectedRequestedPath $launcherResolution.Path') -and
        $publishText.Contains('-LauncherPath $launcherResolution.Path -RequireDirectPath') -and
        $publishText.Contains('$builderVersion = [string]$builderProof.version') -and
        $publishText.Contains('-Lease $effectiveLauncherLease')) 'release publisher verifies a borrowed live lease, owns a direct standalone lease, and derives builder identity from proof'
    Assert-Contract ($publishText -notmatch 'Get-VmbLauncherVersion\b' -and
        $publishText -notmatch '(?m)&\s*\$launcher(?=\s|$)') 'release publisher has no obsolete version lookup or raw launcher invocation'

    $shipRuntimeMarker = $shipText.IndexOf('$launcherExecutableLease = $null')
    $shipRuntimeText = if ($shipRuntimeMarker -ge 0) {
        $shipText.Substring($shipRuntimeMarker)
    } else { '' }
    $shipLeaseEnterPos = $shipRuntimeText.IndexOf('$launcherExecutableLease = Enter-VmbLauncherExecutableLease')
    $shipCapabilityPos = $shipRuntimeText.IndexOf('Assert-VmbLauncherPublicationCapability')
    Assert-Contract ($shipLeaseEnterPos -ge 0 -and
        $shipCapabilityPos -gt $shipLeaseEnterPos -and
        $shipRuntimeText.Contains('-LauncherPath $launcher -RequireDirectPath') -and
        $shipRuntimeText.Contains('Invoke-ShipLauncherNoWindow -LauncherExecutableLease $launcherExecutableLease') -and
        $shipRuntimeText.Contains('-LauncherExecutableLease $launcherExecutableLease') -and
        $shipRuntimeText.Contains('Exit-VmbLauncherExecutableLease -Lease $launcherExecutableLease')) 'ship acquires one direct live lease before capability checks and reuses it through build, release, upload, and cleanup'
    Assert-Contract ($shipRuntimeText -notmatch 'Get-VmbLauncherVersion\b' -and
        $shipRuntimeText -notmatch '(?m)&\s*\$launcher(?=\s|$)') 'ship runtime has no obsolete version lookup or raw launcher invocation'
    Assert-Contract ($shipRuntimeText.Contains('-LauncherPath $launcherResolution.Path') -and
        $shipRuntimeText.Contains('-LauncherSource $launcherResolution.Source') -and
        $shipRuntimeText.Contains('-LauncherApprovalAnchor $launcherResolution.ApprovalAnchor') -and
        $shipRuntimeText.Contains('-LauncherExecutableLease $launcherExecutableLease')) 'ship passes the exact approved path snapshot and same live lease to release publishing'
    Assert-Contract ($runAllText -match '(?m)^Run-Check "vmb_launcher_path_host_matrix".*run_vmb_launcher_path_host_matrix\.ps1.*-Policy ''Blocking''\s*$') 'full QA invokes the dual-host launcher contract as a blocking check'
}
finally {
    foreach ($openLease in $activeLeases) {
        try { Exit-VmbLauncherExecutableLease -Lease $openLease }
        catch { Write-Warning "Could not release launcher fixture lease: $($_.Exception.Message)" }
    }
    foreach ($junctionPathToRemove in $junctionPaths) {
        try { Remove-TestJunction -Path $junctionPathToRemove }
        catch { Write-Warning "Could not remove launcher fixture junction '$junctionPathToRemove': $($_.Exception.Message)" }
    }

    $fixtureFull = [System.IO.Path]::GetFullPath($fixtureRoot)
    $safeFixture = $fixtureFull.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        ([System.IO.Path]::GetFileName($fixtureFull) -like 'vt2-launcher-683-*')
    if (-not $safeFixture) {
        throw "Refusing fixture cleanup outside the expected temp root: $fixtureFull"
    }
    if (Test-Path -LiteralPath $fixtureFull) {
        Get-ChildItem -LiteralPath $fixtureFull -Recurse -File | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force
        }
        Get-ChildItem -LiteralPath $fixtureFull -Recurse -Directory |
            Sort-Object { $_.FullName.Length } -Descending |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
        Remove-Item -LiteralPath $fixtureFull -Force
    }
}

if ($failures.Count -gt 0) {
    Write-Host "[check_vmb_launcher_path] FAILED -- $($failures.Count) contract regression(s)." -ForegroundColor Red
    exit 2
}
Write-Host '[check_vmb_launcher_path] OK -- launcher provenance and executable-lease contracts pass.' -ForegroundColor Green
exit 0
