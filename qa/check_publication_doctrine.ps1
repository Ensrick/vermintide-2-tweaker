# check_publication_doctrine.ps1 -- rejects active documentation that teaches
# direct launcher publication, post-upload source landing, or stale restart
# guidance, including the setup guide's superseded shared-settings procedure.
# PROJECT_STANDARDS.md section 6.6 is the one owner.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

# Windows PowerShell 5.1's -File path initializes PSScriptRoot after parameter
# defaults. Resolve the optional root in the body, never from the caller's CWD.
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = [IO.Path]::GetDirectoryName($PSScriptRoot)
}

# #1025: only the clean-stable lighting document retains an exact legacy
# launcher path pending its separately authorized promotion. Removed prerelease
# rows are no longer exempt: a new path, changed path, copied occurrence or
# reintroduced root instruction is blocking. Never add rows to hide a failure.
$script:KnownLauncherPathDebt = @(
    [pscustomobject]@{
        Path = 'verminious_dreams_lighting/DEVELOPMENT.md'
        Line = '$exe = "C:\Users\danjo\source\repos\vermintide-2-tweaker\tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe"'
        Max = 1
    }
)

function Test-IsHardcodedLauncherPathLine {
    param([AllowEmptyString()][string]$Line)

    return $Line -match '(?i)vmb-launcher-main-current-[0-9]+' -or
        $Line -match '(?i)\b[A-Z]:\\[^\r\n]*VMBLauncher\.exe' -or
        $Line -match '(?i)(?:^|[\s`"''])tools[\\/]vmb-launcher[\\/][^\r\n]*VMBLauncher\.exe'
}

function Get-KnownLauncherPathDebtKey {
    param([string]$Path, [string]$Line)
    return $Path.Replace('\', '/') + "`n" + $Line.Trim()
}

function Get-KnownLauncherPathDebtMap {
    $map = @{}
    foreach ($row in $script:KnownLauncherPathDebt) {
        $key = Get-KnownLauncherPathDebtKey $row.Path $row.Line
        if ($map.ContainsKey($key)) { throw "duplicate launcher-path debt row: $($row.Path)" }
        $map[$key] = [int]$row.Max
    }
    return $map
}

function Get-KnownLauncherPathDebtCount {
    param([object[]]$Documents)

    $known = Get-KnownLauncherPathDebtMap
    $count = 0
    foreach ($document in $Documents) {
        if (Test-IsHistoricalDocument $document.Path) { continue }
        foreach ($line in @($document.Lines)) {
            if (-not (Test-IsHardcodedLauncherPathLine $line)) { continue }
            $key = Get-KnownLauncherPathDebtKey $document.Path $line
            if ($known.ContainsKey($key)) { $count++ }
        }
    }
    return $count
}

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

function Test-IsRawVmbBuildAdviceLine {
    param([AllowEmptyString()][string]$Line)

    # A complete raw build command has a target. A quoted command fragment in
    # checker/incident discussion is not an executable build instruction.
    $rawBuild = '(?i)(?:^|[\s\\/\x60"''(])vmb\.js(?:["''\x60])?\s+build\b\s+["'']?(?:<[^>\r\n]+>|[A-Za-z0-9_.-]+)'
    foreach ($sentence in ($Line -split '(?<=[.!?])\s+')) {
        if ($sentence -notmatch $rawBuild) { continue }
        # Sentence-local: a prohibition cannot hide a later affirmative command.
        if ($sentence -match "(?i)\b(?:do not|don't|never|prohibit\w*|unsupported|not supported|no longer (?:the )?supported)\b") { continue }
        return $true
    }
    return $false
}

function Test-IsUnguardedConfirmedUploadRecoveryParagraph {
    param([AllowEmptyString()][string]$Paragraph)

    # The actual owner advice wrapped across two lines. This narrow prose rule
    # shares existing active/historical scope; it is not a shell parser or an
    # incident-cause classifier. A confirmed upload does not prove deploy parity.
    if ($Paragraph -notmatch '(?i)\b(?:confirmed\s+upload|post-upload|deploy-verify\s+mismatch)\b') { return $false }
    foreach ($sentence in ($Paragraph -split '(?<=[.!?])\s+')) {
        # Do not let a prohibition in a different sentence hide affirmative advice.
        if ($sentence -match "(?i)\b(?:do not|don't|never|must not|forbidden|unsupported|not supported)\b") { continue }
        if ($sentence -match '(?i)\b(?:not a ship failure|do (?:one|a) local re-?deploy|re-?deploy\b.{0,80}\bthen continue)\b') { return $true }
    }
    return $false
}

function Get-PublicationOwnerLinkViolations {
    param([object[]]$Documents, [string]$Standards)

    $violations = @()
    $anchor = '#66-ship-doctrine-keyed-off-the-mod_version-suffix-canonical-2026-07-01'
    foreach ($path in @('CLAUDE.md', 'docs/PORTABLE_SETUP.md')) {
        $document = @($Documents | Where-Object { $_.Path.Replace('\', '/') -ieq $path })
        $prefix = if ($path -eq 'CLAUDE.md') { '' } else { '../' }
        $target = '](' + $prefix + 'PROJECT_STANDARDS.md' + $anchor + ')'
        $guide = if ($document.Count -eq 1) { @($document[0].Lines) -join "`n" } else { '' }
        if (-not $guide.Contains($target) -or
                -not $Standards.Contains('### 6.6 Ship doctrine: keyed off the MOD_VERSION suffix (canonical, 2026-07-01)')) {
            $violations += "${path}: invalid publication owner link"
        }
    }
    return @($violations)
}

function Get-DoctrineViolations {
    param([object[]]$Documents)

    $violations = @()
    $knownLauncherDebt = Get-KnownLauncherPathDebtMap
    $launcherDebtCounts = @{}
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

        # Root-guide recovery advice can wrap across lines. Only paragraphs
        # identifying a partial-upload/hash failure are recovery scope; ordinary
        # non-publishing build/deploy examples keep their existing contract.
        $rootRecoveryLines = @{}
        if ($document.Path.Replace('\', '/') -ieq 'CLAUDE.md') {
            $rootLines = @($document.Lines)
            for ($i = 0; $i -lt $rootLines.Count; $i++) {
                if ([string]::IsNullOrWhiteSpace($rootLines[$i])) { continue }
                $end = $i
                while ($end + 1 -lt $rootLines.Count -and
                        -not [string]::IsNullOrWhiteSpace($rootLines[$end + 1])) { $end++ }
                $paragraph = ($rootLines[$i..$end] -join ' ') -replace '\s+', ' '
                if ($paragraph -match '(?i)\b(?:hash mismatch|confirmed upload|post-upload)\b') {
                    for ($at = $i; $at -le $end; $at++) { $rootRecoveryLines[$at + 1] = $true }
                }
                $i = $end
            }
        }

        # #1025: catch the actual canonical-owner prose bypass even without a
        # launcher command. Existing historical exclusions apply before this scan.
        $recoveryLines = @($document.Lines)
        for ($i = 0; $i -lt $recoveryLines.Count; $i++) {
            if ([string]::IsNullOrWhiteSpace($recoveryLines[$i])) { continue }
            $end = $i
            while ($end + 1 -lt $recoveryLines.Count -and
                    -not [string]::IsNullOrWhiteSpace($recoveryLines[$end + 1])) { $end++ }
            $paragraph = ($recoveryLines[$i..$end] -join ' ') -replace '\s+', ' '

            # #1025: exact current prose contradictions, not a general version
            # blacklist. The historical exclusion above remains unchanged.
            $path = $document.Path.Replace('\', '/')
            if ($path -in @('CLAUDE.md', 'PROJECT_STANDARDS.md')) {
                if ($paragraph -match '(?i)publication probe requires VMBLauncher 0\.6\.[0-2]\b|VMBLauncher 0\.6\.[0-2]\b.{0,180}minimum accepted publication boundary') {
                    $violations += "$($document.Path):$($i + 1): stale launcher publication minimum"
                }
                if ($paragraph -match '(?i)prepared `?receipt`? mode is publication-only|Receipt authority skips every deploy target|receipt-gated publication consumer; deploy, updater/recovery consumption, and bootstrap remain disabled') {
                    $violations += "$($document.Path):$($i + 1): obsolete receipt deployment prohibition"
                }
            }
            if ($path -eq 'CLAUDE.md' -and $paragraph -match '(?i)Always check Workshop page file size after upload|if in doubt eyeball the Workshop page in Steam') {
                $violations += "$($document.Path):$($i + 1): obsolete manual Workshop verification"
            }
            if ($path -eq 'docs/PORTABLE_SETUP.md' -and $paragraph -match '(?i)approved side-by-side launcher 0\.6\.2 does not replace the existing default 0\.6\.1|pending 0\.6\.1 claims/artifacts must finish') {
                $violations += "$($document.Path):$($i + 1): obsolete launcher rollout instruction"
            }
            if (Test-IsUnguardedConfirmedUploadRecoveryParagraph $paragraph) {
                $violations += "$($document.Path):$($i + 1): unguarded confirmed-upload recovery advice"
            }
            $i = $end
        }

        $lineNumber = 0
        foreach ($line in @($document.Lines)) {
            $lineNumber++

            if ($document.Path.Replace('\', '/') -ieq 'CLAUDE.md' -and
                    $line -match '^\s*\.\\tools\\ship\\(?:claim|ship)\.ps1\b') {
                $violations += "$($document.Path):${lineNumber}: secondary ship recipe without owner cwd context"
            }

            if (Test-IsRawVmbBuildAdviceLine $line) {
                $violations += "$($document.Path):${lineNumber}: raw VMB build advice bypasses canonical ship"
            }

            if (Test-IsHardcodedLauncherPathLine $line) {
                $debtKey = Get-KnownLauncherPathDebtKey $document.Path $line
                if ($knownLauncherDebt.ContainsKey($debtKey)) {
                    $launcherDebtCounts[$debtKey] = 1 + [int]$launcherDebtCounts[$debtKey]
                    if ($launcherDebtCounts[$debtKey] -gt $knownLauncherDebt[$debtKey]) {
                        $violations += "$($document.Path):${lineNumber}: copied legacy launcher executable path"
                    }
                }
                else {
                    $violations += "$($document.Path):${lineNumber}: hardcoded launcher executable path"
                }
            }

            $command = $line -match "(?i)(?:VMBLauncher(?:\.exe)?|vmblauncher|&\s+\`?\$\w+)\s+(?:all|upload)\b"
            $standaloneAllAdvice = $line -match '(?i)(?:\bor\b|\buse\b|\brun\b|->)\s+(?:`all(?:\s|`|<)|all\s*<)'
            $explicitProhibition = $line -match "(?i)\b(?:do not|don't|never|prohibit|unsupported|not supported|cannot|can't|refus|reject|internal|without (?:the )?(?:hosted )?receipt|guard|only rewrites|called by|invokes)\b"

            if (($command -or $standaloneAllAdvice) -and -not $explicitProhibition) {
                $violations += "$($document.Path):${lineNumber}: direct launcher publication advice"
            }

            # #1025: neither current recovery guide may bypass the canonical
            # transaction after a partial upload. Separately frozen mod-document
            # CLI debt is not permission to teach a new recovery path here.
            $triageRunbook = $document.Path.Replace('\', '/') -ieq 'docs/BUG_TRIAGE_RUNBOOK.md'
            $directDeploy = $line -match '(?i)(?:VMBLauncher(?:\.exe)?|&\s+`?\$(?:(?:env:)?[A-Za-z_]\w*|\{env:[^}]+\}))\s+deploy\b'
            if (($triageRunbook -or $rootRecoveryLines.ContainsKey($lineNumber)) -and
                    $directDeploy -and -not $explicitProhibition) {
                $violations += "$($document.Path):${lineNumber}: direct launcher recovery bypass"
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

    foreach ($badLauncherLine in @(
        '$env:VT2_SHIP_VMB_LAUNCHER = "C:\Users\test\source\repos\vmb-launcher-main-current-20260728\bin\VMBLauncher.exe"',
        '$exe = "tools\vmb-launcher\bin\Release\VMBLauncher.exe"'
    )) {
        $fixture = @([pscustomobject]@{ Path = 'CLAUDE.md'; Lines = @($badLauncherLine) })
        if ((Get-DoctrineViolations $fixture) -notcontains
            'CLAUDE.md:1: hardcoded launcher executable path') {
            throw "planted hardcoded launcher path was not rejected: $badLauncherLine"
        }
    }
    $knownDebtFixture = @([pscustomobject]@{
        Path = $script:KnownLauncherPathDebt[0].Path
        Lines = @($script:KnownLauncherPathDebt[0].Line)
    })
    if ((Get-DoctrineViolations $knownDebtFixture).Count -ne 0 -or
            (Get-KnownLauncherPathDebtCount $knownDebtFixture) -ne 1) {
        throw 'exact frozen launcher-path debt was not isolated'
    }
    $copiedDebtFixture = @([pscustomobject]@{
        Path = $script:KnownLauncherPathDebt[0].Path
        Lines = @($script:KnownLauncherPathDebt[0].Line, $script:KnownLauncherPathDebt[0].Line)
    })
    if ((Get-DoctrineViolations $copiedDebtFixture) -notcontains
        ($script:KnownLauncherPathDebt[0].Path + ':2: copied legacy launcher executable path')) {
        throw 'copied frozen launcher-path debt was not rejected'
    }

    foreach ($retiredPath in @(
        'event_tweaker/DEVELOPMENT.md',
        'dynamic_cosmetic_portraits/DEVELOPMENT.md',
        'dynamic_cosmetic_portraits/CLAUDE.md',
        'verminious_dreams_lighting_dev/DEVELOPMENT.md'
    )) {
        $retired = @([pscustomobject]@{
            Path = $retiredPath
            Lines = @($script:KnownLauncherPathDebt[0].Line)
        })
        if ((Get-DoctrineViolations $retired) -notcontains
                (${retiredPath} + ':1: hardcoded launcher executable path') -or
                (Get-KnownLauncherPathDebtCount $retired) -ne 0) {
            throw "retired prerelease launcher-path debt was still exempt: $retiredPath"
        }
    }

    # #1025: exact active CWV examples, not synthetic replacements.
    foreach ($rawBuildLine in @(
        '3. Build: `node C:/Users/danjo/source/repos/vmb/vmb.js build character_weapon_variants --no-workshop --cwd`. Verify `bundleV2/` output has fresh files.',
        '- Build with `node vmb.js build <mod> --no-workshop --cwd`.',
        '- [ ] **Build:** `node C:/Users/danjo/source/repos/vmb/vmb.js build character_weapon_variants --no-workshop --cwd`',
        'node C:/Users/danjo/source/repos/vmb/vmb.js build character_weapon_variants --no-workshop --cwd',
        '- [ ] Built (`vmb.js build character_weapon_variants ...`).',
        'Run node "C:\legacy path\vmb.js" build character_weapon_variants.',
        'Do not run `node vmb.js build old_mod`. Run `node vmb.js build current_mod`.'
    )) {
        $rawBuildFixture = @([pscustomobject]@{ Path = 'mod/DEVELOPMENT.md'; Lines = @($rawBuildLine) })
        if ((Get-DoctrineViolations $rawBuildFixture) -notcontains
                'mod/DEVELOPMENT.md:1: raw VMB build advice bypasses canonical ship') {
            throw "planted complete raw VMB build advice was not rejected: $rawBuildLine"
        }
    }
    $rawBuildAllowed = @([pscustomobject]@{
        Path = 'CLAUDE.md'
        Lines = @(
            'The `node vmb.js build <mod> --no-workshop --cwd` invocations and the raw Stingray SDK compile pipeline that previously lived in this section are no longer the supported path.',
            'Never run `node vmb.js build example_mod` directly.',
            'Follow PROJECT_STANDARDS.md section 6.6 for claim, BuildOnly, review, merge, and ship.',
            'The checker has no raw `vmb.js build` predicate.'
        )
    })
    if ((Get-DoctrineViolations $rawBuildAllowed).Count -ne 0) {
        throw 'canonical/prohibited/fragment raw VMB evidence was rejected'
    }
    foreach ($historicalPath in @('mod/CHANGELOG.md', '_archive/BUILD.md', 'mod/_investigating/BUILD.md', 'mod/ROOT_CAUSE.md')) {
        $rawBuildHistory = @([pscustomobject]@{ Path = $historicalPath; Lines = @('Run node vmb.js build old_mod') })
        if ((Get-DoctrineViolations $rawBuildHistory).Count -ne 0) {
            throw "historical raw VMB evidence was scanned as active advice: $historicalPath"
        }
    }

    # #1025 R2: exact old owner bullet must not bypass the recovery guard.
    $oldOwnerRecovery = @([pscustomobject]@{
        Path = 'PROJECT_STANDARDS.md'
        Lines = @(
            '- A real deploy-verify mismatch after a CONFIRMED upload is a Steam reconcile',
            '  race, not a ship failure: do one local re-deploy, then continue.'
        )
    })
    if ((Get-DoctrineViolations $oldOwnerRecovery) -notcontains
            'PROJECT_STANDARDS.md:1: unguarded confirmed-upload recovery advice') {
        throw 'actual canonical-owner redeploy prose bypass was not rejected'
    }
    $guardedOwnerRecovery = @([pscustomobject]@{
        Path = 'PROJECT_STANDARDS.md'
        Lines = @(
            '- A deploy-verify mismatch after a confirmed upload is a failed transaction,',
            '  not automatic evidence of a Steam reconcile race. Preserve the authenticated',
            '  upload receipt, exact source/output/deployed hashes, and original error.',
            '  Diagnose and resume only through `tools\ship\ship.ps1` under the current',
            '  claim and exact-source/hosted authorization. If the claim or authorization',
            '  has expired, obtain a fresh reviewed candidate through the same',
            '  claim/build/review/merge/ship pipeline. Do not directly re-deploy or manually',
            '  write Workshop content.'
        )
    })
    if ((Get-DoctrineViolations $guardedOwnerRecovery).Count -ne 0) {
        throw 'canonical evidence-preserving recovery owner was rejected'
    }
    $recoveryProhibition = @([pscustomobject]@{
        Path = 'PROJECT_STANDARDS.md'
        Lines = @('After a confirmed upload, do not say a mismatch is not a ship failure or do one local re-deploy, then continue.')
    })
    if ((Get-DoctrineViolations $recoveryProhibition).Count -ne 0) {
        throw 'explicit confirmed-upload recovery prohibition was rejected'
    }
    $mixedRecovery = @([pscustomobject]@{
        Path = 'PROJECT_STANDARDS.md'
        Lines = @('Do not directly re-deploy. After a confirmed upload, do one local re-deploy, then continue.')
    })
    if ((Get-DoctrineViolations $mixedRecovery) -notcontains
            'PROJECT_STANDARDS.md:1: unguarded confirmed-upload recovery advice') {
        throw 'a separate prohibition masked affirmative recovery advice'
    }
    $nonPublishingBuild = @([pscustomobject]@{
        Path = 'CLAUDE.md'
        Lines = @('Non-publishing local build:', 'Run & $env:VT2_SHIP_VMB_LAUNCHER build example_mod.')
    })
    if ((Get-DoctrineViolations $nonPublishingBuild).Count -ne 0) {
        throw 'non-publishing canonical bare build guidance was rejected'
    }
    foreach ($historicalPath in @('mod/CHANGELOG.md', '_archive/BUILD.md', 'mod/_investigating/BUILD.md', 'mod/ROOT_CAUSE.md')) {
        $historicalRecovery = @([pscustomobject]@{ Path = $historicalPath; Lines = $oldOwnerRecovery[0].Lines })
        if ((Get-DoctrineViolations $historicalRecovery).Count -ne 0) {
            throw "historical confirmed-upload recovery evidence was scanned as active advice: $historicalPath"
        }
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

    foreach ($deployCommand in @(
        '`& $env:VT2_SHIP_VMB_LAUNCHER deploy <mod> --no-remote` once.',
        'Run VMBLauncher.exe deploy example_mod.',
        'Run & $exe deploy example_mod.',
        'Run & ${env:VT2_SHIP_VMB_LAUNCHER} deploy example_mod.'
    )) {
        $recoveryBypass = @([pscustomobject]@{
            Path = 'docs/BUG_TRIAGE_RUNBOOK.md'
            Lines = @('Deploy-verify hash mismatch after a confirmed upload: re-run', $deployCommand)
        })
        if ((Get-DoctrineViolations $recoveryBypass) -notcontains
            'docs/BUG_TRIAGE_RUNBOOK.md:2: direct launcher recovery bypass') {
            throw "planted direct recovery deploy bypass was not rejected: $deployCommand"
        }
        $prohibition = @([pscustomobject]@{
            Path = 'docs/BUG_TRIAGE_RUNBOOK.md'
            Lines = @('Do not use ' + $deployCommand)
        })
        if ((Get-DoctrineViolations $prohibition).Count -ne 0) {
            throw "explicit recovery prohibition was rejected: $deployCommand"
        }
        $rootRecovery = @([pscustomobject]@{
            Path = 'CLAUDE.md'
            Lines = @('A hash mismatch after a confirmed', 'upload needs recovery:', $deployCommand)
        })
        if ((Get-DoctrineViolations $rootRecovery) -notcontains
                'CLAUDE.md:3: direct launcher recovery bypass') {
            throw "planted root-guide recovery bypass was not rejected: $deployCommand"
        }
        $rootProhibition = @([pscustomobject]@{
            Path = 'CLAUDE.md'
            Lines = @('After a confirmed upload, preserve the evidence.', ('Do not use ' + $deployCommand))
        })
        if ((Get-DoctrineViolations $rootProhibition).Count -ne 0) {
            throw "explicit root-guide recovery prohibition was rejected: $deployCommand"
        }
    }
    $rootBareDeploy = @([pscustomobject]@{
        Path = 'CLAUDE.md'
        Lines = @('Non-publishing local deploy:', 'Run & $exe deploy example_mod.', '',
            'A hash mismatch after a confirmed upload requires canonical guarded recovery.')
    })
    if ((Get-DoctrineViolations $rootBareDeploy).Count -ne 0) {
        throw 'root recovery scope leaked into a separate non-publishing paragraph'
    }
    $canonicalRecovery = @([pscustomobject]@{
        Path = 'docs/BUG_TRIAGE_RUNBOOK.md'
        Lines = @(
            'Preserve the confirmed-upload receipt and exact file hashes.',
            'Do not use a direct launcher deploy or manual Steam content writes.',
            'Resume only through tools/ship/ship.ps1 with current authorization.'
        )
    })
    if ((Get-DoctrineViolations $canonicalRecovery).Count -ne 0) {
        throw 'canonical guarded recovery advice was rejected'
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

    # #1025: the actual conflicting secondary prose must not return.
    foreach ($case in @(
        @{ Path = 'CLAUDE.md'; Text = 'The publication probe requires VMBLauncher 0.6.0 plus the lease guards.'; Error = 'stale launcher publication minimum' },
        @{ Path = 'PROJECT_STANDARDS.md'; Text = 'VMBLauncher 0.6.0 plus machine-transaction-lease-v1 and crash-safe-upload-acl-journal-v1 is the minimum accepted publication boundary.'; Error = 'stale launcher publication minimum' },
        @{ Path = 'CLAUDE.md'; Text = 'The prepared `receipt` mode is publication-only: it never deploys.'; Error = 'obsolete receipt deployment prohibition' },
        @{ Path = 'CLAUDE.md'; Text = 'Receipt authority skips every deploy target and may only upload through its hosted receipt.'; Error = 'obsolete receipt deployment prohibition' },
        @{ Path = 'PROJECT_STANDARDS.md'; Text = 'Issue #1426 adds only its receipt-gated publication consumer; deploy, updater/recovery consumption, and bootstrap remain disabled.'; Error = 'obsolete receipt deployment prohibition' },
        @{ Path = 'CLAUDE.md'; Text = 'For friends_only/private items, if in doubt eyeball the Workshop page in Steam.'; Error = 'obsolete manual Workshop verification' },
        @{ Path = 'CLAUDE.md'; Text = 'Always check Workshop page file size after upload.'; Error = 'obsolete manual Workshop verification' },
        @{ Path = 'docs/PORTABLE_SETUP.md'; Text = 'The approved side-by-side launcher 0.6.2 does not replace the existing default 0.6.1 installation.'; Error = 'obsolete launcher rollout instruction' },
        @{ Path = 'docs/PORTABLE_SETUP.md'; Text = 'Pending 0.6.1 claims/artifacts must finish their existing publications.'; Error = 'obsolete launcher rollout instruction' },
        @{ Path = 'CLAUDE.md'; Text = '.\tools\ship\ship.ps1 -Mod <name>'; Error = 'secondary ship recipe without owner cwd context' }
    )) {
        $fixture = @([pscustomobject]@{ Path = $case.Path; Lines = @($case.Text) })
        if ((Get-DoctrineViolations $fixture) -notcontains ($case.Path + ':1: ' + $case.Error)) {
            throw "planted publication contradiction was not rejected: $($case.Text)"
        }
    }
    $ownerHeading = '### 6.6 Ship doctrine: keyed off the MOD_VERSION suffix (canonical, 2026-07-01)'
    $anchor = '#66-ship-doctrine-keyed-off-the-mod_version-suffix-canonical-2026-07-01'
    $ownerGuides = @(
        [pscustomobject]@{ Path = 'CLAUDE.md'; Lines = @('[Owner](PROJECT_STANDARDS.md' + $anchor + ')') },
        [pscustomobject]@{ Path = 'docs/PORTABLE_SETUP.md'; Lines = @('[Owner](../PROJECT_STANDARDS.md' + $anchor + ')') }
    )
    if ((Get-PublicationOwnerLinkViolations $ownerGuides $ownerHeading).Count -ne 0) {
        throw 'valid root/relative canonical owner links were rejected'
    }
    foreach ($badTarget in @('CLAUDE.md', 'PROJECT_STANDARDS.md#missing', ('../PROJECT_STANDARDS.md' + $anchor))) {
        $badGuides = @([pscustomobject]@{ Path = 'CLAUDE.md'; Lines = @('[Owner](' + $badTarget + ')') }, $ownerGuides[1])
        if ((Get-PublicationOwnerLinkViolations $badGuides $ownerHeading) -notcontains 'CLAUDE.md: invalid publication owner link') {
            throw "invalid publication owner link was not rejected: $badTarget"
        }
    }
    $currentAdvice = @([pscustomobject]@{
        Path = 'CLAUDE.md'
        Lines = @('VMBLauncher 0.6.3 is required. Receipt authority may use the separately hosted local_deploy boundary.',
            'Use bounded same-transaction logs and an authenticated hosted-result reread; follow PROJECT_STANDARDS.md section 6.6.')
    })
    if ((Get-DoctrineViolations $currentAdvice).Count -ne 0) {
        throw 'current launcher/receipt-local/authenticated-result guidance was rejected'
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
$violations += @(Get-PublicationOwnerLinkViolations $documents $standards)
foreach ($required in @(
    "Agent/headless publication is noninteractive.",
    "tools\ship\ship.ps1",
    "BuildOnly",
    "exact live default-branch",
    "Global\Ensrick.VMBLauncher.Transaction.v1",
    "VMBLauncher 0.6.3",
    "Owner resume/context check (#1025)",
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
    $remainingLauncherDebt = Get-KnownLauncherPathDebtCount $documents
    Write-Host "[check_publication_doctrine] OK -- active docs point at the noninteractive merge-first ship; $remainingLauncherDebt exact legacy launcher-path row(s) remain frozen." -ForegroundColor Green
}
exit 0
