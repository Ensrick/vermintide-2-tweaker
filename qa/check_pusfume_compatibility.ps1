# check_pusfume_compatibility.ps1 -- preserve the Pusfume non-interference boundary.

param(
    [switch]$Quiet,
    [switch]$SelfTest
)

$requiredDocs = @{
    'PROJECT_STANDARDS.md' = @(
        '## 9b. Pusfume non-interference',
        'Pusfume project-manager Sol instance',
        'pusfume-compat-reviewed'
    )
    'docs/CROSS_MOD_ARCHITECTURE.md' = @(
        '### External compatibility target: Pusfume',
        'Optional Tweaker behavior fails toward vanilla',
        'no new dependency or failure mode'
    )
    'docs/REGRESSION_CHECKLIST.md' = @(
        '### Pusfume remains independent of Tweaker mods',
        'Disable or remove the changed Tweaker mod',
        'Do not mutate or disable Pusfume'
    )
}

function Get-MissingDoctrine([hashtable]$Documents) {
    $missing = @()
    foreach ($path in $requiredDocs.Keys) {
        $content = [string]$Documents[$path]
        foreach ($phrase in $requiredDocs[$path]) {
            if (-not $content.Contains($phrase)) {
                $missing += "$path missing: $phrase"
            }
        }
    }
    return @($missing)
}

function Get-UnreviewedLuaReferences([object[]]$Sources) {
    $findings = @()
    foreach ($source in $Sources) {
        $lineNumber = 0
        foreach ($line in @($source.Lines)) {
            $lineNumber++
            if ($line -match '(?i)\bpusfume\b' -and $line -notmatch 'pusfume-compat-reviewed') {
                $findings += "$($source.Path):$lineNumber"
            }
        }
    }
    return @($findings)
}

if ($SelfTest) {
    $goodDocs = @{}
    foreach ($path in $requiredDocs.Keys) {
        $goodDocs[$path] = ($requiredDocs[$path] -join "`n")
    }
    if ((Get-MissingDoctrine $goodDocs).Count -ne 0) { throw 'compliant doctrine fixture failed' }

    $badDocs = @{} + $goodDocs
    $badDocs['PROJECT_STANDARDS.md'] = 'missing'
    if ((Get-MissingDoctrine $badDocs).Count -eq 0) { throw 'missing doctrine fixture passed' }

    $badSource = @([pscustomobject]@{ Path = 'mod.lua'; Lines = @('local career = "pusfume"') })
    if ((Get-UnreviewedLuaReferences $badSource).Count -ne 1) { throw 'unreviewed source fixture passed' }

    $goodSource = @([pscustomobject]@{ Path = 'mod.lua'; Lines = @('local career = "pusfume" -- pusfume-compat-reviewed') })
    if ((Get-UnreviewedLuaReferences $goodSource).Count -ne 0) { throw 'review annotation fixture failed' }

    if (-not $Quiet) { Write-Host '[check_pusfume_compatibility] SELFTEST OK' -ForegroundColor Green }
    exit 0
}

$repoRoot = Split-Path $PSScriptRoot -Parent
$documents = @{}
foreach ($path in $requiredDocs.Keys) {
    $fullPath = Join-Path $repoRoot $path
    $documents[$path] = if (Test-Path -LiteralPath $fullPath) {
        [System.IO.File]::ReadAllText($fullPath, [System.Text.Encoding]::UTF8)
    } else {
        ''
    }
}

$sources = @()
Get-ChildItem -LiteralPath $repoRoot -Recurse -Filter '*.lua' -File | ForEach-Object {
    $relative = $_.FullName.Substring($repoRoot.Length + 1)
    if ($relative -match '^(?:_archive|bundleV2|\.temp|tools|qa)[\\/]') { return }
    if ($relative -match '[\\/]bundleV2[\\/]') { return }
    $sources += [pscustomobject]@{
        Path = $relative
        Lines = [System.IO.File]::ReadAllLines($_.FullName, [System.Text.Encoding]::UTF8)
    }
}

$errors = @()
$errors += Get-MissingDoctrine $documents
$errors += Get-UnreviewedLuaReferences $sources

if ($errors.Count -gt 0) {
    Write-Host "[check_pusfume_compatibility] FAIL -- $($errors.Count) doctrine violation(s):" -ForegroundColor Red
    foreach ($errorText in $errors) { Write-Host "  $errorText" -ForegroundColor Yellow }
    Write-Host 'Direct Lua integration needs a same-line pusfume-compat-reviewed annotation and the live compatibility matrix.' -ForegroundColor DarkYellow
    exit 2
}

if (-not $Quiet) {
    Write-Host '[check_pusfume_compatibility] OK -- doctrine present; no unreviewed direct Lua references.' -ForegroundColor Green
}
exit 0
