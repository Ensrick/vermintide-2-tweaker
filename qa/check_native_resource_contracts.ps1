[CmdletBinding()]
param([switch]$Quiet, [switch]$SelfTest)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$manifestPath = Join-Path $here 'native_resource_contracts.psd1'

$patterns = [ordered]@{
    particle = [regex]'\b(?:World|ScriptWorld|[A-Za-z_][A-Za-z0-9_]*_api)\.(?:create_particles|create_particles_linked)\s*(?:,|\()'
    texture = [regex]'\b(?:Material\.set_texture|Unit\.set_texture_for_materials|[A-Za-z_][A-Za-z0-9_]*_api\.set_texture_for_materials|material_set_texture)\s*(?:,|\()'
    material_bind = [regex]'\b(?:Unit\.(?:set_all_materials|set_material|set_material_from_id)|[A-Za-z_][A-Za-z0-9_]*_api\.(?:set_all_materials|set_material|set_material_from_id)|unit_set_material)\s*(?:,|\()'
    gui_create = [regex]'\bWorld\.create_(?:screen|world)_gui\s*\('
    gui_lookup = [regex]'\b(?:Gui|gui_api)\.material\s*(?:,|\()'
    renderer_hook = [regex]'\bmod:hook\(\s*["'']UIRenderer["'']\s*,\s*["'']create["'']'
    shading = [regex]'\b(?:ShadingEnvironment\.(?:set_scalar|set_vector2|set_vector3|set_vector4|blend|apply|set_resource)|World\.set_shading_environment)\s*(?:,|\()'
    residency_proof = [regex]'\b(?:RESIDENCY|residency|RESOURCE_RESIDENCY|residency_contract)\.(?:resource_resident|material_resident|shading_environment_resident|texture_bind_resident|texture_set_resident|unit_materials_resident|gui_material_resident|filter_material_pairs)\s*\('
}

# A texture table handed to a synchronized WeaponAppearance consumer makes the
# library's one native Unit.set_texture_for_materials sink reachable. Counting
# only that sink lets a new descriptor silently widen the native boundary. The
# closed table-field key deliberately ignores locals such as
# `local textures = ...`, later assignments, and report fields such as
# `channels.textures = ...`.
$descriptorTexturePattern = [regex]'[,{;][\t \r\n]*textures[\t ]*='
$weaponAppearanceCallerPattern = [regex]::new(
    '(?i)\b(?:_?wa|[A-Za-z_][A-Za-z0-9_]*appearance[A-Za-z0-9_]*)' +
    '\.(?:apply|apply_report)\s*\(')

function Get-Key([string]$File, [string]$Kind) { return "$File|$Kind" }

function Convert-ToRepoRelativePath([string]$FullPath, [string]$RootPath = $root) {
    $rootPrefix = [IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/') +
        [IO.Path]::DirectorySeparatorChar
    $fullName = [IO.Path]::GetFullPath($FullPath)
    return $(if ($fullName.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        $fullName.Substring($rootPrefix.Length)
    } else { $fullName }).Replace('\', '/')
}

# Fast Lua token scrub for the census. The combined expression chooses the
# earliest token, so '--' inside a quoted/long string remains string content,
# while quotes inside an earlier comment remain comment content.
$script:luaCensusTokens = [regex]::new(
    '(?<long_comment>--\[(?<comment_level>=*)\[[\s\S]*?\]\k<comment_level>\])' +
    '|(?<line_comment>--[^\r\n]*)' +
    '|(?<long_string>\[(?<string_level>=*)\[[\s\S]*?\]\k<string_level>\])' +
    '|(?<double_string>"(?:\\[\s\S]|[^"\\])*")' +
    "|(?<single_string>'(?:\\[\s\S]|[^'\\])*')")

function Remove-LuaCommentsAndStrings {
    param([string]$Text, [switch]$KeepStrings)
    return $script:luaCensusTokens.Replace($Text, {
        param($match)
        $comment = $match.Groups['long_comment'].Success -or
            $match.Groups['line_comment'].Success
        if ($comment -or -not $KeepStrings) { return ' ' }
        return $match.Value
    })
}

function Get-WeaponAppearanceDescriptorRows {
    param($Manifest, [hashtable]$SourceByPath)

    $detected = @{}
    if ($null -eq $Manifest -or $null -eq $Manifest.Rows) { return $detected }
    $libraries = @($Manifest.Rows | Where-Object {
        ([string]$_.File).Replace('\', '/') -match '/_lib_weapon_appearance\.lua$'
    } | ForEach-Object { ([string]$_.File).Replace('\', '/') })
    $roots = @($libraries | ForEach-Object {
        $_.Substring(0, $_.LastIndexOf('/'))
    } | Sort-Object -Unique)
    if ($roots.Count -eq 0) { return $detected }

    $sources = @{}
    if ($null -ne $SourceByPath) {
        foreach ($path in $SourceByPath.Keys) {
            $sources[([string]$path).Replace('\', '/')] = [string]$SourceByPath[$path]
        }
    } else {
        foreach ($consumerRoot in $roots) {
            $fullRoot = Join-Path $root $consumerRoot
            if (-not (Test-Path -LiteralPath $fullRoot -PathType Container)) { continue }
            Get-ChildItem -LiteralPath $fullRoot -Recurse -File -Filter '*.lua' |
                ForEach-Object {
                    $relative = Convert-ToRepoRelativePath $_.FullName
                    if ($relative -notmatch '(^|/)(?:_archive|bundleV2|_test_fixtures|\.claude)(/|$)') {
                        $sources[$relative] = [IO.File]::ReadAllText(
                            $_.FullName, [Text.Encoding]::UTF8)
                    }
                }
        }
    }

    foreach ($relative in $sources.Keys) {
        $path = ([string]$relative).Replace('\', '/')
        if ($libraries -contains $path) { continue }
        $owned = $false
        foreach ($consumerRoot in $roots) {
            if ($path.StartsWith($consumerRoot + '/', [StringComparison]::OrdinalIgnoreCase)) {
                $owned = $true
                break
            }
        }
        if (-not $owned -or $path -match '(^|/)(?:_archive|bundleV2|_test_fixtures|\.claude)(/|$)') {
            continue
        }
        $codeOnly = Remove-LuaCommentsAndStrings ([string]$sources[$relative])
        # A texture-shaped table in a VMF data file is not shared-writer
        # reachability. Require the same module to call the WeaponAppearance
        # API; this is the bounded caller/descriptor closure #1125 asks the
        # census to pin. The library implementation itself is excluded above.
        if (-not $weaponAppearanceCallerPattern.IsMatch($codeOnly)) { continue }
        $count = $descriptorTexturePattern.Matches($codeOnly).Count
        if ($count -gt 0) {
            $detected[(Get-Key $path 'texture_descriptor')] = [pscustomobject]@{
                File=$path; Kind='texture_descriptor'; Count=$count
            }
        }
    }
    return $detected
}

function Get-DetectedRows {
    param($Manifest)
    $detected = @{}
    $needles = @(
        'World.create_particles', 'ScriptWorld.create_particles',
        '.create_particles', '.create_particles_linked',
        'Material.set_texture', 'Unit.set_texture_for_materials',
        '.set_texture_for_materials', 'material_set_texture',
        'Unit.set_all_materials', 'Unit.set_material', '.set_material',
        'unit_set_material', 'World.create_screen_gui', 'World.create_world_gui',
        'Gui.material', 'gui_api.material', 'UIRenderer',
        'ShadingEnvironment.', 'World.set_shading_environment',
        '.resource_resident', '.material_resident',
        '.shading_environment_resident', '.texture_bind_resident',
        '.texture_set_resident', '.unit_materials_resident',
        '.gui_material_resident', '.filter_material_pairs'
    )

    $files = @()
    $rg = Get-Command rg -ErrorAction SilentlyContinue
    if ($rg) {
        $rgArgs = @('--files-with-matches', '--fixed-strings',
            '--glob', '*/scripts/mods/**/*.lua',
            '--glob', '!**/_archive/**',
            '--glob', '!**/bundleV2/**',
            '--glob', '!**/_test_fixtures/**',
            '--glob', '!**/.claude/**')
        foreach ($needle in $needles) { $rgArgs += @('-e', $needle) }
        $rgArgs += '.'
        Push-Location $root
        try {
            $files = @(& $rg.Source @rgArgs | ForEach-Object {
                Get-Item -LiteralPath (Join-Path $root $_)
            })
        } finally {
            Pop-Location
        }
    } else {
        $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.lua' |
            Where-Object { $_.FullName -match '[\\/]scripts[\\/]mods[\\/]' })
    }

    $files | Where-Object {
        $relative = Convert-ToRepoRelativePath $_.FullName
        $_.Name -ne '_lib_resource_residency.lua' -and
        $relative -notmatch '(^|/)(?:_archive|bundleV2|_test_fixtures|\.claude)(/|$)'
    } | ForEach-Object {
        $relative = Convert-ToRepoRelativePath $_.FullName
        $source = [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8)
        $candidateKinds = @($patterns.Keys | Where-Object {
            $patterns[$_].IsMatch($source)
        })
        if ($candidateKinds.Count -eq 0) { return }
        $needsCode = @($candidateKinds | Where-Object { $_ -ne 'renderer_hook' }).Count -gt 0
        $needsHook = $candidateKinds -contains 'renderer_hook'
        $codeOnly = if ($needsCode) { Remove-LuaCommentsAndStrings $source } else { '' }
        $commentsStripped = if ($needsHook) {
            Remove-LuaCommentsAndStrings $source -KeepStrings
        } else { '' }
        foreach ($kind in $candidateKinds) {
            $scan = if ($kind -eq 'renderer_hook') { $commentsStripped } else { $codeOnly }
            $count = $patterns[$kind].Matches($scan).Count
            if ($count -gt 0) {
                $detected[(Get-Key $relative $kind)] = [pscustomobject]@{
                    File=$relative; Kind=$kind; Count=$count
                }
            }
        }
    }
    $descriptorRows = Get-WeaponAppearanceDescriptorRows -Manifest $Manifest
    foreach ($key in $descriptorRows.Keys) { $detected[$key] = $descriptorRows[$key] }
    return $detected
}

function Get-CensusFindings($Detected, $Manifest) {
    $findings = [System.Collections.Generic.List[string]]::new()
    $allowed = @{}; foreach ($policy in $Manifest.Policies) { $allowed[$policy] = $true }
    $declared = @{}
    foreach ($row in $Manifest.Rows) {
        $key = Get-Key ([string]$row.File) ([string]$row.Kind)
        if ($declared.ContainsKey($key)) { $findings.Add("duplicate manifest row $key"); continue }
        $declared[$key] = $row
        if (-not $allowed.ContainsKey([string]$row.Policy)) {
            $findings.Add("$key has unknown policy '$($row.Policy)'")
        }
        if ([int]$row.Count -lt 1) { $findings.Add("$key has invalid count '$($row.Count)'") }
        if ([string]::IsNullOrWhiteSpace([string]$row.Evidence)) {
            $findings.Add("$key has no evidence")
        } elseif ([string]$row.Evidence -like 'qa/*') {
            $evidencePath = Join-Path $root ([string]$row.Evidence)
            if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
                $findings.Add("$key evidence file is missing: $($row.Evidence)")
            }
        } elseif ([string]$row.Evidence -notmatch '^issue:#[0-9]+$') {
            $findings.Add("$key evidence must be a qa/ file or issue:#N")
        }
        if ([string]$row.Policy -eq 'deferred-legacy' -and [string]$row.Evidence -notmatch '^issue:#[0-9]+$') {
            $findings.Add("$key deferred legacy row must name its issue")
        }
    }
    foreach ($key in $Detected.Keys) {
        if (-not $declared.ContainsKey($key)) {
            $findings.Add("uncensused native boundary $key count=$($Detected[$key].Count)")
        } elseif ([int]$declared[$key].Count -ne [int]$Detected[$key].Count) {
            $findings.Add("count drift $key declared=$($declared[$key].Count) actual=$($Detected[$key].Count)")
        }
    }
    foreach ($key in $declared.Keys) {
        if (-not $Detected.ContainsKey($key)) { $findings.Add("stale manifest row $key") }
    }
    # A shared-V2 policy is not documentation by assertion: each protected
    # native-call file must also contain and declare a live shared proof. This
    # prevents a future census update from blessing an unsafe writer merely by
    # assigning the desired policy string.
    $nativeKinds = @{
        particle=$true; texture=$true; material_bind=$true; gui_create=$true
        renderer_hook=$true; shading=$true
    }
    foreach ($row in $Manifest.Rows) {
        $policy = [string]$row.Policy
        $kind = [string]$row.Kind
        $sharedV2 = $policy -eq 'shared-v2-strict' -or
            $policy -eq 'shared-v2-global-preserve-unknown'
        if ($sharedV2 -and $nativeKinds.ContainsKey($kind)) {
            $proofKey = Get-Key ([string]$row.File) 'residency_proof'
            $declaredProof = $declared.ContainsKey($proofKey)
            $detectedProof = $Detected.ContainsKey($proofKey)
            if (-not $declaredProof -or -not $detectedProof) {
                $findings.Add("$($row.File)|$kind claims $policy without a live residency_proof")
            }
        }
    }
    return @($findings)
}

function Invoke-SelfTest {
    $base = @{ Policies=@('shared-v2-strict','deferred-legacy'); Rows=@(
        @{ File='mod/scripts/mods/mod/a.lua'; Kind='texture'; Count=1; Policy='shared-v2-strict'; Evidence='qa/check_native_resource_contracts.ps1' }
        @{ File='mod/scripts/mods/mod/a.lua'; Kind='residency_proof'; Count=1; Policy='shared-v2-strict'; Evidence='qa/check_native_resource_contracts.ps1' }
    ) }
    $good = @{
        'mod/scripts/mods/mod/a.lua|texture' = [pscustomobject]@{Count=1}
        'mod/scripts/mods/mod/a.lua|residency_proof' = [pscustomobject]@{Count=1}
    }
    $drift = @{} + $good
    $drift['mod/scripts/mods/mod/a.lua|texture'] = [pscustomobject]@{Count=2}
    $new = @{} + $good
    $new['mod/scripts/mods/mod/b.lua|gui_create'] = [pscustomobject]@{Count=1}
    $missingProofManifest = @{ Policies=@('shared-v2-strict'); Rows=@(
        @{ File='mod/scripts/mods/mod/a.lua'; Kind='texture'; Count=1; Policy='shared-v2-strict'; Evidence='qa/check_native_resource_contracts.ps1' }
    ) }
    $missingProofDetected = @{
        'mod/scripts/mods/mod/a.lua|texture' = [pscustomobject]@{Count=1}
    }
    $descriptorManifest = @{ Policies=@('deferred-legacy'); Rows=@(
        @{ File='mod/scripts/mods/mod/_lib_weapon_appearance.lua'; Kind='texture'; Count=1; Policy='deferred-legacy'; Evidence='issue:#749' }
    ) }
    $descriptorSources = @{
        'mod/scripts/mods/mod/_lib_weapon_appearance.lua' = 'Unit.set_texture_for_materials(unit, slot, texture)'
        'mod/scripts/mods/mod/consumer.lua' = @'
local descriptor = {
    textures = { albedo = "textures/planted" },
}
WA.apply(unit, descriptor)
textures = resolve_textures()
channels.textures = true
'@
        'mod/scripts/mods/mod/gui_data.lua' = 'local row = { textures = {} }'
        'other/scripts/mods/other/not_a_consumer.lua' = 'local row = { textures = {} }'
    }
    $descriptorDetected = @{
        'mod/scripts/mods/mod/_lib_weapon_appearance.lua|texture' = [pscustomobject]@{Count=1}
    }
    $plantedDescriptorRows = Get-WeaponAppearanceDescriptorRows `
        -Manifest $descriptorManifest -SourceByPath $descriptorSources
    foreach ($key in $plantedDescriptorRows.Keys) {
        $descriptorDetected[$key] = $plantedDescriptorRows[$key]
    }
    $fakeRoot = Join-Path ([IO.Path]::GetTempPath()) '.claude\worktrees\agent'
    $insideRelative = Convert-ToRepoRelativePath (Join-Path $fakeRoot 'mod\scripts\mods\mod\a.lua') $fakeRoot
    $nestedRelative = Convert-ToRepoRelativePath (Join-Path $fakeRoot '.claude\worktrees\nested\mod\a.lua') $fakeRoot
    $checks = @(
        @{ Name='exact census passes'; Pass=(Get-CensusFindings $good $base).Count -eq 0 }
        @{ Name='count drift fails'; Pass=(Get-CensusFindings $drift $base).Count -gt 0 }
        @{ Name='new boundary fails'; Pass=(Get-CensusFindings $new $base).Count -gt 0 }
        @{ Name='stale row fails'; Pass=(Get-CensusFindings @{} $base).Count -gt 0 }
        @{ Name='shared policy without live proof fails'; Pass=(Get-CensusFindings $missingProofDetected $missingProofManifest).Count -gt 0 }
        @{ Name='planted consumer texture descriptor fails without an exact reachability row'; Pass=(
            (Get-CensusFindings $descriptorDetected $descriptorManifest) -contains
                'uncensused native boundary mod/scripts/mods/mod/consumer.lua|texture_descriptor count=1') }
        @{ Name='non-consumer texture descriptors stay outside the shared-writer closure'; Pass=(
            -not $descriptorDetected.ContainsKey('other/scripts/mods/other/not_a_consumer.lua|texture_descriptor') -and
            -not $descriptorDetected.ContainsKey('mod/scripts/mods/mod/gui_data.lua|texture_descriptor')) }
        @{ Name='parent .claude worktree path does not hide repository files'; Pass=$insideRelative -eq 'mod/scripts/mods/mod/a.lua' }
        @{ Name='nested .claude content remains repo-relative and excludable'; Pass=$nestedRelative -match '(^|/)\.claude(/|$)' }
        @{ Name='Lua scrub rejects particle prose and keeps World/API calls'; Pass=(
            $patterns.particle.Matches((Remove-LuaCommentsAndStrings @'
-- World.create_particles(world, "comment")
local text = "ScriptWorld.create_particles_linked(world, 'log')"
World.create_particles(world, effect, position)
world_api.create_particles(world, effect, position, rotation)
'@)).Count -eq 2) }
        @{ Name='Lua scrub rejects prose and keeps native calls'; Pass=(
            $patterns.material_bind.Matches((Remove-LuaCommentsAndStrings @'
-- Unit.set_all_materials(unit, "comment")
local text = "Unit.set_all_materials(unit, 'log')"
--[[ Unit.set_all_materials(unit, "block") ]]
pcall(Unit.set_all_materials, unit, material)
'@)).Count -eq 1) }
    )
    $ok = $true
    foreach ($check in $checks) {
        if (-not $check.Pass) { $ok = $false }
        if (-not $Quiet) { Write-Host ("  [{0}] {1}" -f ($(if($check.Pass){'PASS'}else{'FAIL'})), $check.Name) }
    }
    return $(if ($ok) { 0 } else { 2 })
}

Write-Host '=== check_native_resource_contracts ===' -ForegroundColor Cyan
if ($SelfTest) { exit (Invoke-SelfTest) }
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Write-Host '[native-resource-contracts] FAIL - manifest missing.' -ForegroundColor Red
    exit 2
}
$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
$findings = Get-CensusFindings (Get-DetectedRows $manifest) $manifest
if ($findings.Count -gt 0) {
    Write-Host "[native-resource-contracts] FAIL - $($findings.Count) census finding(s)." -ForegroundColor Red
    foreach ($finding in $findings) { Write-Host "  ! $finding" -ForegroundColor Red }
    exit 2
}
Write-Host "[native-resource-contracts] OK - $($manifest.Rows.Count) exact renderer-resource boundary row(s)." -ForegroundColor Green
exit 0
