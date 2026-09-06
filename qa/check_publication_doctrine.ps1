# check_publication_doctrine.ps1 -- rejects active documentation that teaches
# direct launcher publication, post-upload source landing, or stale restart
# guidance, including the setup guide's superseded shared-settings procedure.
# PROJECT_STANDARDS.md section 6.6 is the one owner.

[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

function Test-IsHistoricalDocument {
    param([string]$RelativePath)

    $path = $RelativePath.Replace("\", "/")
    if ($path -match "(?i)(^|/)(?:_archive|memory|_investigating|bundleV2)/") {
        return $true
    }

    $leaf = [IO.Path]::GetFileName($path)
    return $leaf -match "(?i)^(?:CHANGELOG|POSTMORTEMS|STATUS|TODO)\.md$" -or
        $leaf -match "(?i)(?:AUDIT|ROOT_CAUSE|LOG_ANALYSIS|INVESTIGATION|DIAGNOSIS|HANDOFF)"
}

function Get-DoctrineViolations {
    param([object[]]$Documents)

    $violations = @()
    foreach ($document in $Documents) {
        if (Test-IsHistoricalDocument $document.Path) { continue }

        # #1025: this is a current setup-guide contract, not a global phrase
        # blacklist. Historical incident/recovery descriptions remain evidence.
        if ($document.Path.Replace('\', '/') -ieq 'docs/PORTABLE_SETUP.md') {
            $setup = (@($document.Lines) -join "`n") -replace '\s+', ' '
            if ($setup -match '(?i)upload doctrine (?:remains|is) in `?CLAUDE\.md') {
                $violations += "$($document.Path): publication doctrine points to a non-owner"
            }
            foreach ($sentence in ($setup -split '(?<=[.!?])\s+')) {
                # Negated instructions and the private-config replacement are
                # valid. Check sentence-by-sentence so a correct prohibition
                # cannot mask a separate affirmative restoration instruction.
                if ($sentence -match "(?i)\b(?:never|do not|does not|must not|no longer|forbidden)\b") { continue }
                $shared = '(?:shared|global|original)\s+(?:(?:VMBLauncher|launcher)\s+)?settings(?:\s+file|\.json)?'
                $mutation = '(?:rewrit\w*|rewrot\w*|restor\w*|retarget\w*)'
                $sharedMutation = $sentence -match "(?i)\b$shared\b.{0,120}\b$mutation\b" -or
                    $sentence -match "(?i)\b$mutation\b.{0,120}\b$shared\b"
                $oldBinding = $sentence -match '(?i)\bwrapper\s+temporarily\s+binds\b' -and
                    $sentence -notmatch '(?i)\bprivate\b'
                if ($sharedMutation -or $oldBinding) {
                    $violations += "$($document.Path): shared launcher settings mutation advice"
                    break
                }
            }
        }

        $lineNumber = 0
        foreach ($line in @($document.Lines)) {
            $lineNumber++
            $command = $line -match "(?i)(?:VMBLauncher(?:\.exe)?|vmblauncher|&\s+\`?\$\w+)\s+(?:all|upload)\b"
            $standaloneAllAdvice = $line -match '(?i)(?:\bor\b|\buse\b|\brun\b|->)\s+(?:`all(?:\s|`|<)|all\s*<)'
            $explicitProhibition = $line -match "(?i)\b(?:do not|don't|never|prohibit|unsupported|not supported|cannot|can't|refus|reject|internal|without (?:the )?(?:hosted )?receipt|guard|only rewrites|called by|invokes)\b"

            if (($command -or $standaloneAllAdvice) -and -not $explicitProhibition) {
                $violations += "$($document.Path):${lineNumber}: direct launcher publication advice"
            }

            if ($line -match "(?i)after every upload[^\r\n]*restart\s+(?:VT2|Steam|the game|game)\b") {
                $violations += "$($document.Path):${lineNumber}: stale post-upload restart advice"
            }

            if ($line -match "(?i)(?:after (?:an? )?(?:upload|publishing|publication)[^\r\n]*\b(?:commit|push|pull request)\b|\b(?:commit|push|pull request)\b[^\r\n]*after (?:the )?(?:upload|publishing|publication))") {
                $violations += "$($document.Path):${lineNumber}: post-upload source landing advice"
            }
        }
    }
    return @($violations)
}

function Get-ActiveDocuments {
    param([string]$Root)

    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd("\", "/")
    $documents = @()
    foreach ($file in Get-ChildItem -LiteralPath $rootPath -Recurse -Filter "*.md" -File) {
        $relative = $file.FullName.Substring($rootPath.Length + 1).Replace("\", "/")
        if (Test-IsHistoricalDocument $relative) { continue }
        $documents += [pscustomobject]@{
            Path = $relative
            Lines = [IO.File]::ReadAllLines($file.FullName, [Text.Encoding]::UTF8)
        }
    }
    return @($documents)
}

if ($SelfTest) {
    $good = @(
        [pscustomobject]@{
            Path = "CLAUDE.md"
            Lines = @(
                "Follow PROJECT_STANDARDS.md section 6.6.",
                "Do not use VMBLauncher.exe all for publication.",
                "PC-A uses the hash-verified deploy without restarting Steam."
            )
        }
    )
    if ((Get-DoctrineViolations $good).Count -ne 0) {
        throw "compliant publication doctrine fixture was rejected"
    }

    $direct = @([pscustomobject]@{
        Path = "mod/DEVELOPMENT.md"
        Lines = @("Run VMBLauncher.exe all example_mod")
    })
    if ((Get-DoctrineViolations $direct) -notcontains
        "mod/DEVELOPMENT.md:1: direct launcher publication advice") {
        throw "planted direct-all advice was not rejected"
    }

    $standaloneAll = @([pscustomobject]@{
        Path = "DEVELOPMENT.md"
        Lines = @('Loop: build -> deploy (or `all <mod>`), then test.')
    })
    if ((Get-DoctrineViolations $standaloneAll) -notcontains
        "DEVELOPMENT.md:1: direct launcher publication advice") {
        throw "planted standalone-all advice was not rejected"
    }

    $restart = @([pscustomobject]@{
        Path = "docs/REGRESSION_CHECKLIST.md"
        Lines = @("After every upload, restart VT2 and inspect chat.")
    })
    if ((Get-DoctrineViolations $restart) -notcontains
        "docs/REGRESSION_CHECKLIST.md:1: stale post-upload restart advice") {
        throw "planted stale restart advice was not rejected"
    }

    $postUploadCommit = @([pscustomobject]@{
        Path = "tools/publish-release/README.md"
        Lines = @("After publishing, commit and push the source.")
    })
    if ((Get-DoctrineViolations $postUploadCommit) -notcontains
        "tools/publish-release/README.md:1: post-upload source landing advice") {
        throw "planted post-upload commit advice was not rejected"
    }

    $history = @([pscustomobject]@{
        Path = "mod/CHANGELOG.md"
        Lines = @("Run VMBLauncher.exe upload old_mod")
    })
    if ((Get-DoctrineViolations $history).Count -ne 0) {
        throw "historical evidence was scanned as live doctrine"
    }

    $privateSetup = @([pscustomobject]@{
        Path = 'docs/PORTABLE_SETUP.md'
        Lines = @(
            'Upload doctrine is owned by PROJECT_STANDARDS.md section 6.6.',
            'Canonical ship never rewrites shared launcher settings.',
            'Do not retarget or restore the shared settings file.',
            'Each launcher child receives the same private --config bound to the invoking worktree.',
            'The private file is removed during cleanup.'
        )
    })
    if ((Get-DoctrineViolations $privateSetup).Count -ne 0) {
        throw 'private-config setup instructions were rejected'
    }
    foreach ($badSettingsAdvice in @(
        @('The launcher is invoked with the exact --config path that the', 'wrapper temporarily binds.'),
        @('Multiple git worktrees share the same launcher settings, so the wrapper', 'temporarily binds ProjectRoot to the repository containing the invoked script.'),
        @('The', 'original settings file is restored byte-for-byte in a finally block on both', 'success and failure.'),
        @('The wrapper temporarily rewrites the shared launcher settings file.'),
        @('Canonical ship never rewrites shared launcher settings.', 'The original settings file is restored after success or failure.')
    )) {
        $fixture = @([pscustomobject]@{ Path = 'docs/PORTABLE_SETUP.md'; Lines = $badSettingsAdvice })
        if ((Get-DoctrineViolations $fixture) -notcontains
            'docs/PORTABLE_SETUP.md: shared launcher settings mutation advice') {
            throw "planted shared-settings advice was not rejected: $($badSettingsAdvice -join ' ')"
        }
    }
    $wrongOwner = @([pscustomobject]@{
        Path = 'docs/PORTABLE_SETUP.md'
        Lines = @('Build, deploy, and upload doctrine remains in `CLAUDE.md`.')
    })
    if ((Get-DoctrineViolations $wrongOwner) -notcontains
        'docs/PORTABLE_SETUP.md: publication doctrine points to a non-owner') {
        throw 'planted non-owner setup pointer was not rejected'
    }
    foreach ($referencePath in @('mod/CHANGELOG.md', 'docs/BUG_CLASSES.md', '_archive/PORTABLE_SETUP.md')) {
        $reference = @([pscustomobject]@{
            Path = $referencePath
            Lines = @('The original settings file is restored byte-for-byte.')
        })
        if ((Get-DoctrineViolations $reference).Count -ne 0) {
            throw "setup-only guard leaked into reference evidence: $referencePath"
        }
    }

    if (-not $Quiet) {
        Write-Host "[check_publication_doctrine] SELFTEST OK"
    }
    exit 0
}

$repoPath = (Resolve-Path -LiteralPath $RepoRoot).Path
$documents = @(Get-ActiveDocuments $repoPath)
$violations = @(Get-DoctrineViolations $documents)

$standardsPath = Join-Path $repoPath "PROJECT_STANDARDS.md"
$standards = if (Test-Path -LiteralPath $standardsPath) {
    [IO.File]::ReadAllText($standardsPath, [Text.Encoding]::UTF8)
}
else {
    ""
}
foreach ($required in @(
    "Agent/headless publication is noninteractive.",
    "tools\ship\ship.ps1",
    "BuildOnly",
    "exact live default-branch",
    "Global\Ensrick.VMBLauncher.Transaction.v1",
    "VMBLauncher 0.6.0",
    "never rewrites shared launcher settings",
    "Do not run a parallel retry",
    "manually reset SDK ACLs"
)) {
    if (-not $standards.Contains($required)) {
        $violations += "PROJECT_STANDARDS.md: missing canonical token: $required"
    }
}

if ($violations.Count -gt 0) {
    Write-Host "[check_publication_doctrine] FAIL -- $($violations.Count) violation(s):" -ForegroundColor Red
    foreach ($violation in $violations) {
        Write-Host "  $violation" -ForegroundColor Yellow
    }
    Write-Host "Publication doctrine is owned by PROJECT_STANDARDS.md section 6.6." -ForegroundColor DarkYellow
    exit 2
}

if (-not $Quiet) {
    Write-Host "[check_publication_doctrine] OK -- active docs point at the noninteractive merge-first ship." -ForegroundColor Green
}
exit 0
