# check_mod_descriptor_line_endings.ps1 - protect tracked .mod descriptors.
#
# Git normalizes *.mod to LF, but a tool can rewrite a working copy to CRLF
# while `git status` still reports it as clean. Publication hashes raw staged
# bytes, so that hidden drift can invalidate an otherwise correct build. Keep
# every tracked descriptor LF-only, byte-identical to the index, and keep each
# root descriptor identical to its generated bundleV2 copy.
#
# Exit codes: 0 = clean, 2 = descriptor contract failure.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }

function Invoke-GitText([string]$Root, [string[]]$Arguments) {
    $output = @(& git -C $Root @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed in $Root"
    }
    return @($output | ForEach-Object { "$($_)".Trim() })
}

function Get-ByteHash([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Test-DescriptorContract([string]$Root) {
    $errors = New-Object System.Collections.Generic.List[string]
    $tracked = @(Invoke-GitText $Root @('ls-files', '--', '*.mod'))
    $trackedSet = @{}

    foreach ($relativePath in $tracked) {
        if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }
        $normalized = $relativePath.Replace('\', '/')
        $trackedSet[$normalized] = $true
        $fullPath = Join-Path $Root ($normalized.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            $errors.Add("tracked descriptor is missing: $normalized")
            continue
        }

        $bytes = [System.IO.File]::ReadAllBytes($fullPath)
        if ([Array]::IndexOf($bytes, [byte]13) -ge 0) {
            $errors.Add("descriptor contains CR bytes instead of LF-only text: $normalized")
        }

        $rawHash = @(Invoke-GitText $Root @('hash-object', '--no-filters', '--', $normalized))[0]
        $indexHash = @(Invoke-GitText $Root @('rev-parse', ":$normalized"))[0]
        if ($rawHash -ne $indexHash) {
            $errors.Add("raw descriptor bytes differ from the indexed blob: $normalized")
        }
    }

    foreach ($relativePath in $tracked) {
        $normalized = $relativePath.Replace('\', '/')
        if ($normalized -notmatch '^([^/]+)/([^/]+)\.mod$') { continue }
        $bundlePath = "$($matches[1])/bundleV2/$($matches[2]).mod"
        if (-not $trackedSet.ContainsKey($bundlePath)) { continue }

        $rootFull = Join-Path $Root ($normalized.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $bundleFull = Join-Path $Root ($bundlePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if ((Test-Path -LiteralPath $rootFull -PathType Leaf) -and
            (Test-Path -LiteralPath $bundleFull -PathType Leaf)) {
            $rootHash = Get-ByteHash ([System.IO.File]::ReadAllBytes($rootFull))
            $bundleHash = Get-ByteHash ([System.IO.File]::ReadAllBytes($bundleFull))
            if ($rootHash -ne $bundleHash) {
                $errors.Add("root and bundleV2 descriptors differ: $normalized != $bundlePath")
            }
        }
    }

    return @($errors)
}

function Assert-SelfTest([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "self-test failed: $Message" }
}

if ($SelfTest) {
    $fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-mod-descriptor-" + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path (Join-Path $fixture 'example/bundleV2') -Force | Out-Null
        & git -C $fixture init -q
        & git -C $fixture config user.email 'qa@example.invalid'
        & git -C $fixture config user.name 'VT2 QA'
        & git -C $fixture config core.autocrlf false
        [System.IO.File]::WriteAllBytes((Join-Path $fixture '.gitattributes'),
            [Text.Encoding]::ASCII.GetBytes("*.mod text eol=lf`n"))
        $lf = [Text.Encoding]::ASCII.GetBytes("return { name = 'example' }`n")
        [System.IO.File]::WriteAllBytes((Join-Path $fixture 'example/example.mod'), $lf)
        [System.IO.File]::WriteAllBytes((Join-Path $fixture 'example/bundleV2/example.mod'), $lf)
        & git -C $fixture add -- .
        & git -C $fixture commit -q -m fixture

        $clean = @(Test-DescriptorContract $fixture)
        Assert-SelfTest ($clean.Count -eq 0) 'LF root/bundle pair should pass'

        $crlf = [Text.Encoding]::ASCII.GetBytes("return { name = 'example' }`r`n")
        [System.IO.File]::WriteAllBytes((Join-Path $fixture 'example/example.mod'), $crlf)
        $hiddenDrift = @(Test-DescriptorContract $fixture)
        Assert-SelfTest (($hiddenDrift -join "`n") -match 'contains CR bytes') 'CR bytes were not detected'
        Assert-SelfTest (($hiddenDrift -join "`n") -match 'differ from the indexed blob') 'raw/index drift was not detected'

        [System.IO.File]::WriteAllBytes((Join-Path $fixture 'example/example.mod'), $lf)
        [System.IO.File]::WriteAllBytes((Join-Path $fixture 'example/bundleV2/example.mod'),
            [Text.Encoding]::ASCII.GetBytes("return { name = 'different' }`n"))
        $pairDrift = @(Test-DescriptorContract $fixture)
        Assert-SelfTest (($pairDrift -join "`n") -match 'root and bundleV2 descriptors differ') 'root/bundle drift was not detected'

        Write-Host '[check_mod_descriptor_line_endings -SelfTest] PASS' -ForegroundColor Green
        exit 0
    } finally {
        if (Test-Path -LiteralPath $fixture) {
            Remove-Item -LiteralPath $fixture -Recurse -Force
        }
    }
}

$problems = @(Test-DescriptorContract $RepoRoot)
if ($problems.Count -gt 0) {
    Write-Host '[check_mod_descriptor_line_endings] ERRORS:' -ForegroundColor Red
    foreach ($problem in $problems) { Write-Host "  - $problem" -ForegroundColor Red }
    exit 2
}

if (-not $Quiet) {
    Write-Host '[check_mod_descriptor_line_endings] OK - tracked .mod descriptors are LF-only, index-exact, and paired.' -ForegroundColor Green
}
exit 0
