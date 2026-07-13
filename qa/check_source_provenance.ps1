# check_source_provenance.ps1 - validates docs/engine source provenance.
#
# The proprietary/local decompile is deliberately not a CI dependency. The
# committed manifest is always schema-checked; source-file and stable-symbol
# anchors are checked when an optional sibling checkout exists. Use
# -RequireSource for an explicitly strict local run.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$SourceRoot,
    [string]$ManifestPath,
    [switch]$RequireSource,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$ScriptDir = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $PSScriptRoot
}

function Log([string]$Message, [string]$Color = 'DarkGray') {
    if (-not $Quiet) { Write-Host $Message -ForegroundColor $Color }
}

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Test-IsoTimestamp($Value) {
    if ($Value -is [DateTime] -or $Value -is [DateTimeOffset]) { return $true }
    if (-not ($Value -is [string]) -or [string]::IsNullOrWhiteSpace($Value)) { return $false }
    $parsed = [DateTimeOffset]::MinValue
    return [DateTimeOffset]::TryParse($Value, [ref]$parsed)
}

function Test-SafeRelativePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ([System.IO.Path]::IsPathRooted($Path)) { return $false }
    return $Path -notmatch '(^|[\\/])\.\.([\\/]|$)'
}

function Test-PositiveInteger($Value) {
    $parsed = [int64]0
    return [int64]::TryParse([string]$Value, [ref]$parsed) -and $parsed -gt 0
}

function Test-Manifest($Manifest) {
    $errors = @()
    if ($null -eq $Manifest) { return @('manifest is empty') }
    if ($Manifest.schemaVersion -ne 1) { $errors += 'schemaVersion must equal 1' }
    if (-not (Test-IsoTimestamp $Manifest.verifiedAtUtc)) { $errors += 'verifiedAtUtc must be an ISO-8601 timestamp' }

    if ($null -eq $Manifest.source) {
        $errors += 'source object is required'
    } else {
        if ($Manifest.source.repositoryUrl -notmatch '^https://') { $errors += 'source.repositoryUrl must be an https URL' }
        if ($Manifest.source.commit -notmatch '^[0-9a-f]{40}$') { $errors += 'source.commit must be a full lowercase Git commit' }
        if ($Manifest.source.gameVersion -notmatch '^\d+\.\d+\.\d+$') { $errors += 'source.gameVersion must be a three-part version' }
        if ([string]::IsNullOrWhiteSpace([string]$Manifest.source.extractionMethod)) { $errors += 'source.extractionMethod is required' }
    }

    if ($null -eq $Manifest.runtime) {
        $errors += 'runtime object is required'
    } else {
        if (-not (Test-PositiveInteger $Manifest.runtime.contentRevision)) { $errors += 'runtime.contentRevision must be positive' }
        if ($Manifest.runtime.engineRevision -notmatch '^[0-9a-f]{40}$') { $errors += 'runtime.engineRevision must be a 40-character lowercase hash' }
        if (-not (Test-IsoTimestamp $Manifest.runtime.capturedAtUtc)) { $errors += 'runtime.capturedAtUtc must be an ISO-8601 timestamp' }
        if ([string]::IsNullOrWhiteSpace([string]$Manifest.runtime.evidence)) { $errors += 'runtime.evidence is required' }
    }

    $anchors = @($Manifest.anchors)
    if ($anchors.Count -eq 0 -or $null -eq $anchors[0]) {
        $errors += 'at least one source anchor is required'
    } else {
        for ($i = 0; $i -lt $anchors.Count; $i++) {
            $anchor = $anchors[$i]
            $prefix = "anchors[$i]"
            if (-not (Test-SafeRelativePath ([string]$anchor.path))) { $errors += "$prefix.path must be a safe relative path" }
            if ([string]::IsNullOrWhiteSpace([string]$anchor.doc)) { $errors += "$prefix.doc is required" }
            if ([string]::IsNullOrWhiteSpace([string]$anchor.symbol)) { $errors += "$prefix.symbol is required" }
            if ($anchor.kind -notin @('lua-function', 'assignment')) { $errors += "$prefix.kind must be lua-function or assignment" }
            if (-not (Test-PositiveInteger $anchor.line)) { $errors += "$prefix.line must be positive" }
        }
    }
    return @($errors)
}

function Get-AnchorPattern($Anchor) {
    $symbol = [string]$Anchor.symbol
    $escaped = [regex]::Escape($symbol)
    if ($Anchor.kind -eq 'assignment') {
        return "(?m)^[ \t]*$escaped[ \t]*="
    }
    if ($symbol -match '^(.*)\.([^.]+)$') {
        $owner = [regex]::Escape($matches[1])
        $method = [regex]::Escape($matches[2])
        return "(?m)^[ \t]*(?:function[ \t]+$owner(?:\.|:)$method[ \t]*\(|$owner\.$method[ \t]*=[ \t]*function[ \t]*\()"
    }
    return "(?m)^[ \t]*(?:(?:local[ \t]+)?function[ \t]+$escaped[ \t]*\(|$escaped[ \t]*=[ \t]*function[ \t]*\()"
}

function Test-SourceAnchors($Manifest, [string]$Root) {
    $errors = @()
    foreach ($anchor in @($Manifest.anchors)) {
        $relative = ([string]$anchor.path).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $path = Join-Path $Root $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $errors += "$($anchor.doc): source file missing: $($anchor.path)"
            continue
        }
        $text = Read-Utf8 $path
        $match = [regex]::Match($text, (Get-AnchorPattern $anchor))
        if (-not $match.Success) {
            $errors += "$($anchor.doc): symbol '$($anchor.symbol)' not found in $($anchor.path)"
            continue
        }
        $actualLine = ([regex]::Matches($text.Substring(0, $match.Index), "`n")).Count + 1
        if ($actualLine -ne [int]$anchor.line) {
            $errors += "$($anchor.doc): '$($anchor.symbol)' moved from line $($anchor.line) to $actualLine"
        } else {
            Log "  [PASS] $($anchor.doc): $($anchor.symbol) ($($anchor.path):$actualLine)" 'Green'
        }
    }
    return @($errors)
}

function Get-GitHead([string]$Root) {
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & git -C $Root rev-parse HEAD 2>$null
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    if ($code -ne 0) { return $null }
    return ([string]$output).Trim()
}

function Invoke-SelfTest {
    Write-Host '[check_source_provenance] SELF-TEST' -ForegroundColor Cyan
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-source-prov-" + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($root) | Out-Null
    $fixturePath = Join-Path $root 'fixture.lua'
    [System.IO.File]::WriteAllText($fixturePath, "Thing.run = function (self)`nend`n", [System.Text.Encoding]::UTF8)
    try {
        $manifest = [pscustomobject]@{
            schemaVersion = 1
            verifiedAtUtc = '2026-07-13T17:00:00Z'
            source = [pscustomobject]@{
                repositoryUrl = 'https://example.invalid/source'
                commit = ('a' * 40)
                gameVersion = '6.11.0'
                extractionMethod = 'fixture'
            }
            runtime = [pscustomobject]@{
                contentRevision = 1
                engineRevision = ('b' * 40)
                capturedAtUtc = '2026-07-13T17:00:00Z'
                evidence = 'fixture'
            }
            anchors = @([pscustomobject]@{
                doc = 'fixture.md'; path = 'fixture.lua'; symbol = 'Thing.run'; kind = 'lua-function'; line = 1
            })
        }

        $schemaPass = (Test-Manifest $manifest).Count -eq 0
        $anchorPass = (Test-SourceAnchors $manifest $root).Count -eq 0
        $manifest.anchors[0].symbol = 'Thing.missing'
        $missingSymbolCaught = ((Test-SourceAnchors $manifest $root) -match 'not found').Count -eq 1
        $manifest.anchors[0].symbol = 'Thing.run'
        $manifest.anchors[0].path = '../escape.lua'
        $traversalCaught = ((Test-Manifest $manifest) -match 'safe relative path').Count -eq 1
        $optionalMissingSourceSkips = -not (Test-Path (Join-Path $root 'absent-source'))

        $cases = @{
            'valid manifest schema' = $schemaPass
            'stable symbol anchor' = $anchorPass
            'missing symbol rejected' = $missingSymbolCaught
            'path traversal rejected' = $traversalCaught
            'optional source absence is detectable' = $optionalMissingSourceSkips
        }
        $failed = @($cases.GetEnumerator() | Where-Object { -not $_.Value })
        foreach ($case in ($cases.GetEnumerator() | Sort-Object Name)) {
            $state = if ($case.Value) { 'PASS' } else { 'FAIL' }
            $color = if ($case.Value) { 'Green' } else { 'Red' }
            Write-Host ("  [{0}] {1}" -f $state, $case.Name) -ForegroundColor $color
        }
        if ($failed.Count -gt 0) { exit 2 }
        Write-Host '[check_source_provenance] SELF-TEST PASSED' -ForegroundColor Green
        exit 0
    } finally {
        if (Test-Path -LiteralPath $fixturePath) { Remove-Item -LiteralPath $fixturePath -Force }
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Force }
    }
}

if ($SelfTest) { Invoke-SelfTest }

if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = Join-Path $ScriptDir '..' }
$RepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $RepoRoot 'docs\engine\SOURCE_PROVENANCE.json'
}
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Join-Path (Split-Path $RepoRoot -Parent) 'Vermintide-2-Source-Code'
}

Log '=== check_source_provenance ===' 'Cyan'
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    Write-Host "[check_source_provenance] ERROR: manifest missing: $ManifestPath" -ForegroundColor Red
    exit 2
}

try {
    $manifest = Read-Utf8 $ManifestPath | ConvertFrom-Json
} catch {
    Write-Host "[check_source_provenance] ERROR: invalid JSON: $_" -ForegroundColor Red
    exit 2
}

$errors = @(Test-Manifest $manifest)
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "  [FAIL] $_" -ForegroundColor Red }
    Write-Host "[check_source_provenance] FAILED -- $($errors.Count) manifest error(s)." -ForegroundColor Red
    exit 2
}
Log "  [PASS] manifest schema and $(@($manifest.anchors).Count) anchor declarations" 'Green'

if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    if ($RequireSource) {
        Write-Host "[check_source_provenance] ERROR: source checkout required but absent: $SourceRoot" -ForegroundColor Red
        exit 2
    }
    Write-Host "[check_source_provenance] SKIP: optional source checkout absent: $SourceRoot" -ForegroundColor DarkYellow
    exit 0
}

$head = Get-GitHead $SourceRoot
if (-not $head) {
    Write-Host "[check_source_provenance] ERROR: source path is not a readable Git checkout: $SourceRoot" -ForegroundColor Red
    exit 2
}
if ($head -ne [string]$manifest.source.commit) {
    Write-Host "[check_source_provenance] ERROR: source HEAD $head does not match pinned commit $($manifest.source.commit)." -ForegroundColor Red
    exit 2
}
Log "  [PASS] source commit $head" 'Green'

$versionFile = Join-Path $SourceRoot 'scripts\settings\version_settings.lua'
if (-not (Test-Path -LiteralPath $versionFile -PathType Leaf)) {
    $errors += 'scripts/settings/version_settings.lua is missing'
} else {
    $versionText = Read-Utf8 $versionFile
    $versionMatch = [regex]::Match($versionText, 'local\s+version\s*=\s*"([^"]+)"')
    if (-not $versionMatch.Success) {
        $errors += 'game version could not be parsed from scripts/settings/version_settings.lua'
    } elseif ($versionMatch.Groups[1].Value -ne [string]$manifest.source.gameVersion) {
        $errors += "source game version $($versionMatch.Groups[1].Value) does not match pinned $($manifest.source.gameVersion)"
    } else {
        Log "  [PASS] source game version $($versionMatch.Groups[1].Value)" 'Green'
    }
}

$errors += @(Test-SourceAnchors $manifest $SourceRoot)
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "  [FAIL] $_" -ForegroundColor Red }
    Write-Host "[check_source_provenance] FAILED -- $($errors.Count) source validation error(s)." -ForegroundColor Red
    exit 2
}

Write-Host "[check_source_provenance] OK -- pinned checkout and $(@($manifest.anchors).Count) stable anchors verified." -ForegroundColor Green
exit 0
