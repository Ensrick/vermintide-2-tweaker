# bundle-authority.ps1 - fail-closed bundleV2 authority control plane (#1412).
#
# This file owns the exact inventory modes and the typed transition contract.
# Receipt authority may publish only through the independently validated
# schema-3 receipt path. Deployment, updater, and recovery remain tracked-only.
# ASCII-only for Windows PowerShell 5.1 parsing.

$script:VtBundleAuthorityModes = @('tracked', 'receipt')

function Get-VtBundleAuthorityObjectValue {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Get-VtBundleAuthorityEntryErrors {
    param([Parameter(Mandatory = $true)]$Entry)

    $errors = @()
    $dir = [string](Get-VtBundleAuthorityObjectValue -InputObject $Entry -Name 'Dir')
    $authority = [string](Get-VtBundleAuthorityObjectValue -InputObject $Entry -Name 'BundleAuthority')
    $rootBundle = [string](Get-VtBundleAuthorityObjectValue -InputObject $Entry -Name 'RootBundle')

    if ([string]::IsNullOrWhiteSpace($dir) -or $dir -cnotmatch '^[a-z0-9][a-z0-9_]*$') {
        $errors += "invalid bundle-authority directory: '$dir'"
    }
    if ($script:VtBundleAuthorityModes -cnotcontains $authority) {
        $errors += "invalid BundleAuthority for ${dir}: '$authority' (expected 'tracked' or 'receipt')"
    }
    if ($rootBundle -cnotmatch '^[0-9a-f]{16}\.mod_bundle$') {
        $errors += "invalid RootBundle for ${dir}: '$rootBundle'"
    }
    return @($errors)
}

function Assert-VtBundleAuthorityEntry {
    param([Parameter(Mandatory = $true)]$Entry)

    $errors = @(Get-VtBundleAuthorityEntryErrors -Entry $Entry)
    if ($errors.Count -gt 0) {
        throw "Invalid bundle-authority inventory entry: $($errors -join '; ')"
    }
    return [string](Get-VtBundleAuthorityObjectValue -InputObject $Entry -Name 'BundleAuthority')
}

function Get-VtBundleAuthorityIgnoreRule {
    param([Parameter(Mandatory = $true)][string]$Mod)

    if ($Mod -cnotmatch '^[a-z0-9][a-z0-9_]*$') {
        throw "Cannot construct a bundle-authority ignore rule for invalid mod directory '$Mod'."
    }
    return "/$Mod/bundleV2/"
}

function ConvertTo-VtBundleAuthorityTextLines {
    param([AllowEmptyString()][string]$Text)

    if ($null -eq $Text) { return ,([string[]]@()) }
    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    if ($normalized.EndsWith("`n", [System.StringComparison]::Ordinal)) {
        $normalized = $normalized.Substring(0, $normalized.Length - 1)
    }
    if ($normalized.Length -eq 0) { return ,([string[]]@()) }
    return ,([string[]][regex]::Split($normalized, "`n"))
}

function Get-VtBundleAuthorityIgnoreStateErrors {
    param(
        [Parameter(Mandatory = $true)][string]$Mod,
        [Parameter(Mandatory = $true)][ValidateSet('tracked', 'receipt')][string]$Authority,
        [AllowEmptyString()][string]$GitIgnoreText
    )

    $rule = Get-VtBundleAuthorityIgnoreRule -Mod $Mod
    $count = @((ConvertTo-VtBundleAuthorityTextLines -Text $GitIgnoreText) |
        Where-Object { $_ -ceq $rule }).Count
    if ($Authority -ceq 'receipt' -and $count -ne 1) {
        return @("receipt authority requires exactly one scoped ignore rule '$rule' (found $count)")
    }
    if ($Authority -ceq 'tracked' -and $count -ne 0) {
        return @("tracked authority forbids scoped ignore rule '$rule' (found $count)")
    }
    return @()
}

function Get-VtBundleAuthorityIgnoreTransitionErrors {
    param(
        [Parameter(Mandatory = $true)][string]$Mod,
        [Parameter(Mandatory = $true)][ValidateSet('tracked-to-receipt', 'receipt-to-tracked')][string]$Direction,
        [AllowEmptyString()][string]$BaseText,
        [AllowEmptyString()][string]$HeadText
    )

    $errors = @()
    $rule = Get-VtBundleAuthorityIgnoreRule -Mod $Mod
    [string[]]$baseLines = ConvertTo-VtBundleAuthorityTextLines -Text $BaseText
    [string[]]$headLines = ConvertTo-VtBundleAuthorityTextLines -Text $HeadText
    [string[]]$withoutRule = @()

    if ($Direction -ceq 'tracked-to-receipt') {
        $errors += @(Get-VtBundleAuthorityIgnoreStateErrors -Mod $Mod -Authority tracked -GitIgnoreText $BaseText)
        $errors += @(Get-VtBundleAuthorityIgnoreStateErrors -Mod $Mod -Authority receipt -GitIgnoreText $HeadText)
        $withoutRule = @($headLines | Where-Object { $_ -cne $rule })
        if (($baseLines -join "`n") -cne ($withoutRule -join "`n")) {
            $errors += 'tracked-to-receipt must add only its exact scoped ignore rule to .gitignore'
        }
    }
    else {
        $errors += @(Get-VtBundleAuthorityIgnoreStateErrors -Mod $Mod -Authority receipt -GitIgnoreText $BaseText)
        $errors += @(Get-VtBundleAuthorityIgnoreStateErrors -Mod $Mod -Authority tracked -GitIgnoreText $HeadText)
        $withoutRule = @($baseLines | Where-Object { $_ -cne $rule })
        if (($withoutRule -join "`n") -cne ($headLines -join "`n")) {
            $errors += 'receipt-to-tracked must remove only its exact scoped ignore rule from .gitignore'
        }
    }
    return @($errors)
}

function Get-VtBundleAuthorityOutputPaths {
    param(
        [Parameter(Mandatory = $true)][string]$Mod,
        [Parameter(Mandatory = $true)]$OutputSet
    )

    return @($OutputSet.Files | ForEach-Object {
        $name = [string](Get-VtBundleAuthorityObjectValue -InputObject $_ -Name 'Name')
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = [string](Get-VtBundleAuthorityObjectValue -InputObject $_ -Name 'filename')
        }
        "$Mod/bundleV2/$name"
    })
}

function Compare-VtBundleAuthorityOutputIdentities {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $errors = @()
    if ([string]$Expected.Algorithm -cne [string]$Actual.Algorithm) {
        $errors += "$Label output algorithm differs"
    }
    if ([string]$Expected.Fingerprint -cne [string]$Actual.Fingerprint) {
        $errors += "$Label complete output fingerprint differs"
    }
    if ([string]$Expected.Root.Name -cne [string]$Actual.Root.Name -or
            [string]$Expected.Root.Sha256 -cne [string]$Actual.Root.Sha256) {
        $errors += "$Label canonical root identity differs"
    }
    if ([string]$Expected.Descriptor.Name -cne [string]$Actual.Descriptor.Name -or
            [string]$Expected.Descriptor.Sha256 -cne [string]$Actual.Descriptor.Sha256) {
        $errors += "$Label descriptor identity differs"
    }
    return @($errors)
}

function Test-VtBundleAuthorityTransition {
    param(
        [Parameter(Mandatory = $true)][string]$Mod,
        [Parameter(Mandatory = $true)]$BaseEntry,
        [Parameter(Mandatory = $true)]$HeadEntry,
        [Parameter(Mandatory = $true)][object[]]$Changes,
        [AllowEmptyString()][string]$BaseGitIgnoreText,
        [AllowEmptyString()][string]$HeadGitIgnoreText,
        $BaseTrackedOutputSet,
        $HeadTrackedOutputSet,
        $ReceiptOutputSet,
        $ReceiptProof
    )

    $problems = @()
    $problems += @(Get-VtBundleAuthorityEntryErrors -Entry $BaseEntry)
    $problems += @(Get-VtBundleAuthorityEntryErrors -Entry $HeadEntry)
    $baseAuthority = [string](Get-VtBundleAuthorityObjectValue -InputObject $BaseEntry -Name 'BundleAuthority')
    $headAuthority = [string](Get-VtBundleAuthorityObjectValue -InputObject $HeadEntry -Name 'BundleAuthority')
    $baseDir = [string](Get-VtBundleAuthorityObjectValue -InputObject $BaseEntry -Name 'Dir')
    $headDir = [string](Get-VtBundleAuthorityObjectValue -InputObject $HeadEntry -Name 'Dir')
    if ($baseDir -cne $Mod -or $headDir -cne $Mod) {
        $problems += "bundle-authority transition entries must both resolve exact mod '$Mod'"
    }

    if ($baseAuthority -ceq $headAuthority) {
        return [pscustomobject][ordered]@{
            Ok = ($problems.Count -eq 0)
            IsTransition = $false
            Direction = ''
            Problems = @($problems)
        }
    }

    $direction = if ($baseAuthority -ceq 'tracked' -and $headAuthority -ceq 'receipt') {
        'tracked-to-receipt'
    }
    elseif ($baseAuthority -ceq 'receipt' -and $headAuthority -ceq 'tracked') {
        'receipt-to-tracked'
    }
    else {
        ''
    }
    if (-not $direction) {
        $problems += "unsupported BundleAuthority transition '$baseAuthority' -> '$headAuthority'"
        return [pscustomobject][ordered]@{
            Ok = $false; IsTransition = $true; Direction = ''; Problems = @($problems)
        }
    }

    $problems += @(Get-VtBundleAuthorityIgnoreTransitionErrors -Mod $Mod `
        -Direction $direction -BaseText $BaseGitIgnoreText -HeadText $HeadGitIgnoreText)

    $inventoryChanges = @($Changes | Where-Object {
        [string](Get-VtBundleAuthorityObjectValue -InputObject $_ -Name 'Path') -ceq 'tools/mod-inventory.psd1'
    })
    if ($inventoryChanges.Count -ne 1 -or
            [string](Get-VtBundleAuthorityObjectValue -InputObject $inventoryChanges[0] -Name 'Status') -cne 'M') {
        $problems += 'authority transition requires one atomic modification of tools/mod-inventory.psd1'
    }
    $ignoreChanges = @($Changes | Where-Object {
        [string](Get-VtBundleAuthorityObjectValue -InputObject $_ -Name 'Path') -ceq '.gitignore'
    })
    if ($ignoreChanges.Count -ne 1 -or
            [string](Get-VtBundleAuthorityObjectValue -InputObject $ignoreChanges[0] -Name 'Status') -cne 'M') {
        $problems += 'authority transition requires one atomic modification of .gitignore'
    }

    if ($null -eq $ReceiptProof -or -not [bool]$ReceiptProof.Ok) {
        $details = if ($null -ne $ReceiptProof) { @($ReceiptProof.Problems) -join '; ' } else { 'missing proof' }
        $problems += "authority transition requires an exact schema-3 receipt proof: $details"
    }
    if ($null -eq $ReceiptOutputSet) {
        $problems += 'authority transition requires the receipt complete output set'
    }

    $expectedOutputSet = $null
    $actualOutputSet = $null
    $expectedStatus = ''
    if ($direction -ceq 'tracked-to-receipt') {
        if ($null -eq $BaseTrackedOutputSet) {
            $problems += 'tracked-to-receipt lacks the prior tracked complete output set'
        }
        else {
            $expectedOutputSet = $BaseTrackedOutputSet
            $actualOutputSet = $ReceiptOutputSet
        }
        if ($null -ne $HeadTrackedOutputSet) {
            $problems += 'receipt authority retains tracked generated outputs'
        }
        $expectedStatus = 'D'
    }
    else {
        if ($null -eq $HeadTrackedOutputSet) {
            $problems += 'receipt-to-tracked lacks the restored tracked complete output set'
        }
        else {
            $expectedOutputSet = $ReceiptOutputSet
            $actualOutputSet = $HeadTrackedOutputSet
        }
        if ($null -ne $BaseTrackedOutputSet) {
            $problems += 'receipt transition base unexpectedly contains tracked generated outputs'
        }
        $expectedStatus = 'A'
    }
    if ($null -ne $expectedOutputSet -and $null -ne $actualOutputSet) {
        $problems += @(Compare-VtBundleAuthorityOutputIdentities -Expected $expectedOutputSet `
            -Actual $actualOutputSet -Label $direction)
    }

    if ($null -ne $expectedOutputSet) {
        $expectedPaths = [string[]]@(Get-VtBundleAuthorityOutputPaths -Mod $Mod -OutputSet $expectedOutputSet)
        [System.Array]::Sort($expectedPaths, [System.StringComparer]::Ordinal)
        $prefix = "$Mod/bundleV2/"
        $outputChanges = @($Changes | Where-Object {
            $candidatePath = [string](Get-VtBundleAuthorityObjectValue -InputObject $_ -Name 'Path')
            $candidatePath.StartsWith($prefix, [System.StringComparison]::Ordinal)
        })
        $actualPaths = @()
        foreach ($change in $outputChanges) {
            $status = [string](Get-VtBundleAuthorityObjectValue -InputObject $change -Name 'Status')
            $path = [string](Get-VtBundleAuthorityObjectValue -InputObject $change -Name 'Path')
            if ($status -cne $expectedStatus) {
                $problems += "$direction has unexpected output change '$status $path'"
            }
            $actualPaths += $path
        }
        [string[]]$sortedActualPaths = @($actualPaths)
        [System.Array]::Sort($sortedActualPaths, [System.StringComparer]::Ordinal)
        if (($expectedPaths -join [char]0) -cne ($sortedActualPaths -join [char]0)) {
            $problems += "$direction output changes are not exactly the receipt-bound prior output map"
        }
    }

    return [pscustomobject][ordered]@{
        Ok = ($problems.Count -eq 0)
        IsTransition = $true
        Direction = $direction
        Problems = @($problems)
    }
}

function Get-VtBundleAuthorityDownstreamPolicy {
    param([Parameter(Mandatory = $true)]$Entry)

    $authority = Assert-VtBundleAuthorityEntry -Entry $Entry
    $tracked = $authority -ceq 'tracked'
    return [pscustomobject][ordered]@{
        Authority = $authority
        Build = $true
        Receipt = $true
        Normalize = $true
        Publish = $true
        Deploy = $tracked
        Update = $tracked
        Recover = $tracked
    }
}

function Assert-VtBundleAuthorityShipPreflight {
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [switch]$BuildOnly
    )

    $policy = Get-VtBundleAuthorityDownstreamPolicy -Entry $Entry
    if (-not $BuildOnly -and -not $policy.Publish) {
        throw "BundleAuthority '$($policy.Authority)' does not permit Workshop publication."
    }
    return $policy
}
