# Shared structural policy for issue #499. This file is deliberately offline:
# qa/check_diagnostic_ownership.ps1 supplies the source tree and the hosted
# lifecycle guard supplies the already-fetched open-issue set.

function ConvertTo-VtDiagnosticPath {
    param([string]$Path)
    return ([string]$Path).Replace('\', '/').TrimStart('/')
}

function Get-VtDiagnosticField {
    param($Entry, [string]$Name, $Default = $null)
    if ($Entry -is [System.Collections.IDictionary]) {
        if ($Entry.Contains($Name)) { return $Entry[$Name] }
        return $Default
    }
    $property = $Entry.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Get-VtProductionDiagnosticFiles {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $result = @()
    foreach ($directory in @(Get-ChildItem -LiteralPath $RepoRoot -Directory)) {
        if (-not (Test-Path -LiteralPath (Join-Path $directory.FullName ($directory.Name + '.mod')) -PathType Leaf)) {
            continue
        }
        $scripts = Join-Path $directory.FullName 'scripts\mods'
        if (-not (Test-Path -LiteralPath $scripts -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $scripts -Recurse -File -Filter '*.lua')) {
            if ($file.Name -notmatch '(?i)(probe|_diag_)') { continue }
            $root = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([char[]]@('\', '/')) + [IO.Path]::DirectorySeparatorChar
            $rootUri = New-Object Uri($root)
            $fileUri = New-Object Uri($file.FullName)
            $relative = [Uri]::UnescapeDataString($rootUri.MakeRelativeUri($fileUri).ToString())
            $result += ConvertTo-VtDiagnosticPath $relative
        }
    }
    return @($result | Sort-Object -Unique)
}

function Test-VtDiagnosticOwnership {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$RepoRoot,
        [string[]]$ExpectedStandingProbePaths = @(
            'general_tweaker/scripts/mods/general_tweaker/_gt_debug_probes.lua',
            'general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_debug_probes.lua'
        )
    )

    $failures = @()
    if ([int]$Manifest.Version -ne 1) { $failures += "unsupported manifest Version '$($Manifest.Version)'" }

    $expectedStanding = @($ExpectedStandingProbePaths | ForEach-Object { ConvertTo-VtDiagnosticPath $_ } | Sort-Object)
    $declaredStanding = @($Manifest.StandingProbePaths | ForEach-Object { ConvertTo-VtDiagnosticPath $_ } | Sort-Object)
    if (($expectedStanding -join "`n") -cne ($declaredStanding -join "`n")) {
        $failures += 'StandingProbePaths must be the exact reviewed standing-owner set'
    }

    $entries = @($Manifest.Entries)
    if ($entries.Count -eq 0) { $failures += 'manifest has no Entries' }
    $byPath = @{}
    foreach ($entry in $entries) {
        $path = ConvertTo-VtDiagnosticPath (Get-VtDiagnosticField $entry 'Path')
        if ([string]::IsNullOrWhiteSpace($path)) { $failures += 'registry entry has blank Path'; continue }
        if ($path -match '(^|/)\.\.?(/|$)' -or $path.StartsWith('/')) {
            $failures += "registry path is not repo-relative: $path"
            continue
        }
        if ($byPath.ContainsKey($path)) { $failures += "duplicate registry path: $path"; continue }
        $byPath[$path] = $entry

        $classification = [string](Get-VtDiagnosticField $entry 'Classification')
        if ($classification -notin @('standing', 'active_issue', 'permanent_policy', 'temporary_exception')) {
            $failures += "$path has invalid Classification '$classification'"
        }
        $fullPath = Join-Path $RepoRoot $path
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            $failures += "registered diagnostic missing: $path"
            continue
        }

        $isProbe = [IO.Path]::GetFileName($path) -match '(?i)probe'
        if ($isProbe -and $classification -eq 'standing') {
            if ($declaredStanding -notcontains $path) { $failures += "unapproved standing probe owner: $path" }
        }
        elseif ($isProbe) {
            if ((Get-VtDiagnosticField $entry 'LegacyProbe' $false) -ne $true -or [int](Get-VtDiagnosticField $entry 'RemovalIssue' 0) -ne 499) {
                $failures += "legacy probe lacks the shrinking #499 exception: $path"
            }
        }

        if ($classification -in @('active_issue', 'permanent_policy')) {
            $owner = ConvertTo-VtDiagnosticPath (Get-VtDiagnosticField $entry 'LoadOwner')
            $arming = [string](Get-VtDiagnosticField $entry 'Arming')
            $anchor = [string](Get-VtDiagnosticField $entry 'LoadAnchor')
            if ([string]::IsNullOrWhiteSpace($owner)) { $failures += "$path has no LoadOwner" }
            elseif (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $owner) -PathType Leaf)) {
                $failures += "$path LoadOwner is missing: $owner"
            }
            elseif ([string]::IsNullOrWhiteSpace($anchor)) { $failures += "$path has no LoadAnchor" }
            elseif (-not ([IO.File]::ReadAllText((Join-Path $RepoRoot $owner), [Text.Encoding]::UTF8).Contains($anchor))) {
                $failures += "$path LoadAnchor is absent from $owner"
            }
            if ($arming -notin @('automatic', 'command', 'lifecycle', 'mixed', 'library')) {
                $failures += "$path has invalid Arming '$arming'"
            }
            $rawBoundPath = [string](Get-VtDiagnosticField $entry 'BoundPath')
            $boundPath = if ([string]::IsNullOrWhiteSpace($rawBoundPath)) { $path } else { ConvertTo-VtDiagnosticPath $rawBoundPath }
            $bounds = @((Get-VtDiagnosticField $entry 'BoundAnchors' @()) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($bounds.Count -eq 0) { $failures += "$path has no finite BoundAnchors" }
            $boundFull = Join-Path $RepoRoot $boundPath
            if (-not (Test-Path -LiteralPath $boundFull -PathType Leaf)) {
                $failures += "$path BoundPath is missing: $boundPath"
            }
            else {
                $boundSource = [IO.File]::ReadAllText($boundFull, [Text.Encoding]::UTF8)
                foreach ($bound in $bounds) {
                    if (-not $boundSource.Contains($bound)) { $failures += "$path BoundAnchor is absent from $boundPath`: $bound" }
                }
            }
        }

        if ($classification -eq 'active_issue') {
            $issues = @((Get-VtDiagnosticField $entry 'Issues' @()) | ForEach-Object { [int]$_ } | Where-Object { $_ -gt 0 })
            $prefixes = @((Get-VtDiagnosticField $entry 'Prefixes' @()) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($issues.Count -eq 0) { $failures += "$path active_issue row has no Issues" }
            $stream = [string](Get-VtDiagnosticField $entry 'Stream')
            if ([string]::IsNullOrWhiteSpace($stream)) { $failures += "$path active_issue row has no Stream" }
            if ($prefixes.Count -eq 0) { $failures += "$path active_issue row has no Prefixes" }
            else {
                $aliases = @((Get-VtDiagnosticField $entry 'PrefixAliases' @()))
                $source = [IO.File]::ReadAllText($fullPath, [Text.Encoding]::UTF8)
                $prefixPath = ConvertTo-VtDiagnosticPath (Get-VtDiagnosticField $entry 'PrefixPath')
                if ($prefixPath -and (Test-Path -LiteralPath (Join-Path $RepoRoot $prefixPath) -PathType Leaf)) {
                    $source += "`n" + [IO.File]::ReadAllText((Join-Path $RepoRoot $prefixPath), [Text.Encoding]::UTF8)
                }
                foreach ($prefix in $prefixes) {
                    if (-not $source.Contains($prefix)) { $failures += "$path Prefix is absent from diagnostic/bound owner: $prefix" }
                    $numberMatch = [regex]::Match($prefix, '(\d+)')
                    $numberMatchesIssue = $numberMatch.Success -and ($issues -contains [int]$numberMatch.Groups[1].Value)
                    if (-not $numberMatchesIssue) {
                        $matchingAliases = @($aliases | Where-Object {
                            [string](Get-VtDiagnosticField $_ 'Prefix') -ceq $prefix -and
                            $issues -contains [int](Get-VtDiagnosticField $_ 'Issue' 0) -and
                            -not [string]::IsNullOrWhiteSpace([string](Get-VtDiagnosticField $_ 'Reason'))
                        })
                        if ($matchingAliases.Count -ne 1) {
                            $failures += "$path Prefix does not identify an active issue or one exact documented alias: $prefix"
                        }
                    }
                }
            }
            if ($stream -eq 'public' -and (Get-VtDiagnosticField $entry 'StableLegacy' $false) -ne $true) {
                $failures += "$path puts an issue diagnostic in a clean public stream"
            }
            if ((Get-VtDiagnosticField $entry 'StableLegacy' $false) -eq $true -and [int](Get-VtDiagnosticField $entry 'RemovalIssue' 0) -ne 499) {
                $failures += "$path public legacy exception is not owned by #499"
            }
        }
        elseif ($classification -eq 'permanent_policy') {
            if ([string]::IsNullOrWhiteSpace([string](Get-VtDiagnosticField $entry 'Role'))) { $failures += "$path permanent_policy row has no Role" }
        }
        elseif ($classification -eq 'temporary_exception') {
            if ([int](Get-VtDiagnosticField $entry 'RemovalIssue' 0) -ne 499) { $failures += "$path temporary exception is not owned by #499" }
            if ([string]::IsNullOrWhiteSpace([string](Get-VtDiagnosticField $entry 'Reason'))) { $failures += "$path temporary exception has no Reason" }
            if ([string]::IsNullOrWhiteSpace([string](Get-VtDiagnosticField $entry 'SunsetAction'))) { $failures += "$path temporary exception has no SunsetAction" }
        }
    }

    $discovered = @(Get-VtProductionDiagnosticFiles -RepoRoot $RepoRoot)
    foreach ($path in $discovered) {
        if (-not $byPath.ContainsKey($path)) { $failures += "unregistered production diagnostic: $path" }
    }
    foreach ($path in @($byPath.Keys | Sort-Object)) {
        if ($discovered -notcontains $path) { $failures += "registry row is outside the production diagnostic census: $path" }
    }

    return [pscustomobject]@{
        Failures = @($failures)
        Registered = $entries.Count
        Discovered = $discovered.Count
        Active = @($entries | Where-Object { (Get-VtDiagnosticField $_ 'Classification') -eq 'active_issue' }).Count
        Temporary = @($entries | Where-Object { (Get-VtDiagnosticField $_ 'Classification') -eq 'temporary_exception' }).Count
    }
}

function Test-VtDiagnosticIssueStates {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)]$OpenIssues
    )
    $open = @{}
    foreach ($issue in @($OpenIssues)) { $open[[int]$issue.number] = $true }
    $failures = @()
    foreach ($entry in @($Manifest.Entries | Where-Object { (Get-VtDiagnosticField $_ 'Classification') -eq 'active_issue' })) {
        foreach ($number in @((Get-VtDiagnosticField $entry 'Issues' @()))) {
            $issueNumber = [int]$number
            if (-not $open.ContainsKey($issueNumber)) {
                $failures += "active diagnostic references non-open issue #$issueNumber ($(Get-VtDiagnosticField $entry 'Path'))"
            }
        }
    }
    return @($failures)
}
