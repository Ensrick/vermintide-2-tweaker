# check_ps51_compatibility.ps1 - guards scripts promised to Windows PowerShell 5.1.
#
# Windows PowerShell 5.1 decodes a BOM-less script as the active ANSI code page.
# A UTF-8 em dash can therefore become a smart quote byte sequence and break the
# tokenizer before the script can set an encoding. Keep this deliberately small
# bootstrap/release target set byte-ASCII and execute the in-progress sentinel
# contract under both supported Windows hosts. Issue #85.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot ".." }
$repoRootPath = (Resolve-Path $RepoRoot).Path

$ps51Targets = @(
    "qa/check_ps51_compatibility.ps1",
    "qa/run_ps51_parse_matrix.ps1",
    "qa/check_in_progress.ps1",
    "qa/check_published_ids.ps1",
    "qa/check_promotion.ps1",
    "qa/check_mod_inventory.ps1",
    "qa/check_ci_hardening.ps1",
    "qa/run_all.ps1",
    "qa/run_selftests.ps1",
    "tools/ship/ship.ps1",
    "tools/ship/claim.ps1",
    "tools/github/protect-master.ps1"
)

function Test-AsciiTargetSet {
    param(
        [string]$Root,
        [string[]]$Targets
    )

    $problems = @()
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $rootPrefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar

    foreach ($relativePath in $Targets) {
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $rootFull $relativePath))
        if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $problems += "${relativePath}: target escapes repository root"
            continue
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            $problems += "${relativePath}: target is missing"
            continue
        }

        $bytes = [System.IO.File]::ReadAllBytes($fullPath)
        $line = 1
        for ($i = 0; $i -lt $bytes.Length; $i++) {
            $value = $bytes[$i]
            if ($value -gt 127) {
                $problems += ("{0}:{1}: non-ASCII byte 0x{2:X2} at offset {3}" -f $relativePath, $line, $value, $i)
                break
            }
            if ($value -eq 10) { $line++ }
        }
    }

    return @($problems)
}

function Invoke-HostScript {
    param(
        [string]$HostPath,
        [string]$ScriptPath,
        [string[]]$ScriptArguments
    )

    $hostArguments = @("-NoProfile")
    if ([System.IO.Path]::GetFileName($HostPath) -ieq "powershell.exe") {
        $hostArguments += @("-ExecutionPolicy", "Bypass")
    }
    $hostArguments += @("-File", $ScriptPath)
    $hostArguments += $ScriptArguments

    $priorPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = (& $HostPath @hostArguments 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $priorPreference
    }

    return @{
        ExitCode = $exitCode
        Output = $output
    }
}

function Get-Ps51ParseClosure {
    param([string]$Root)

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $rootPrefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    $seen = @{}

    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $rootFull "qa") -Filter "*.ps1" -File) {
        $queue.Enqueue($file.FullName)
    }
    foreach ($relativePath in @("tools/install-hooks.ps1", "tools/hooks/pre-commit.ps1")) {
        $queue.Enqueue((Join-Path $rootFull $relativePath))
    }

    while ($queue.Count -gt 0) {
        $fullPath = [System.IO.Path]::GetFullPath($queue.Dequeue())
        if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($seen.ContainsKey($fullPath)) { continue }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
        $seen[$fullPath] = $true

        $text = [System.IO.File]::ReadAllText($fullPath, [System.Text.Encoding]::UTF8)
        foreach ($match in [regex]::Matches($text, '["''](?<path>[^"'']+\.ps1)["'']')) {
            $literal = $match.Groups['path'].Value -replace '\\', [System.IO.Path]::DirectorySeparatorChar
            if ($literal -match '[*?]') { continue }
            if ($literal -match '^(qa|tools|\.github)[\\/]') {
                $candidate = Join-Path $rootFull $literal
            }
            else {
                $candidate = Join-Path (Split-Path $fullPath -Parent) $literal
            }
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $queue.Enqueue($candidate) }
        }
    }

    $relativePaths = @()
    foreach ($fullPath in $seen.Keys) {
        $relativePaths += ($fullPath.Substring($rootPrefix.Length) -replace '\\', '/')
    }
    return @($relativePaths | Sort-Object -Unique)
}

function Invoke-Ps51ParseMatrix {
    param(
        [string]$Root,
        [string[]]$RelativePaths
    )

    $powershell = Get-Command "powershell.exe" -ErrorAction SilentlyContinue
    if (-not $powershell) {
        return @{ ExitCode = 99; Output = "required host is unavailable: powershell.exe" }
    }

    $listPath = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-ps51-list-{0}.txt" -f ([guid]::NewGuid().ToString("N")))
    try {
        [System.IO.File]::WriteAllLines($listPath, $RelativePaths, [System.Text.Encoding]::ASCII)
        $helper = Join-Path $repoRootPath "qa/run_ps51_parse_matrix.ps1"
        return Invoke-HostScript -HostPath $powershell.Source -ScriptPath $helper -ScriptArguments @("-RepoRoot", $Root, "-ListPath", $listPath)
    }
    finally {
        if (Test-Path -LiteralPath $listPath) { Remove-Item -LiteralPath $listPath }
    }
}

function Write-Sentinel {
    param(
        [string]$Path,
        [string]$Started
    )

    $body = "- **Started:** ${Started}`r`n- **Session ID:** ps51-fixture`r`n"
    [System.IO.File]::WriteAllText($Path, $body, (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-SelfTest {
    $failures = @()
    $fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-ps51-{0}" -f ([guid]::NewGuid().ToString("N")))
    $claimDir = Join-Path $fixtureRoot ".in_progress"
    $modDir = Join-Path $fixtureRoot "fixture_mod"
    $sentinelPath = Join-Path $claimDir "fixture_mod.md"
    $asciiPath = Join-Path $fixtureRoot "ascii.ps1"
    $badPath = Join-Path $fixtureRoot "bad.ps1"
    $badParsePath = Join-Path $fixtureRoot "bad_parse.ps1"

    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
    New-Item -ItemType Directory -Path $claimDir | Out-Null
    New-Item -ItemType Directory -Path $modDir | Out-Null

    try {
        [System.IO.File]::WriteAllText($asciiPath, 'Write-Host "ok"', (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::WriteAllBytes($badPath, [byte[]](35, 32, 0xE2, 0x80, 0x94, 13, 10))

        $asciiResult = @(Test-AsciiTargetSet -Root $fixtureRoot -Targets @("ascii.ps1"))
        if ($asciiResult.Count -ne 0) {
            $failures += "ASCII fixture was rejected: $($asciiResult -join '; ')"
        }
        $badResult = @(Test-AsciiTargetSet -Root $fixtureRoot -Targets @("bad.ps1"))
        if ($badResult.Count -ne 1 -or $badResult[0] -notmatch 'non-ASCII byte') {
            $failures += "UTF-8 em-dash fixture was not rejected exactly once"
        }

        $prefix = [System.Text.Encoding]::ASCII.GetBytes('Write-Host "left ')
        $suffix = [System.Text.Encoding]::ASCII.GetBytes(' right"') + [byte[]](13, 10)
        $badParseBytes = [byte[]]($prefix + [byte[]](0xE2, 0x80, 0x94) + $suffix)
        [System.IO.File]::WriteAllBytes($badParsePath, $badParseBytes)
        $badParse = Invoke-Ps51ParseMatrix -Root $fixtureRoot -RelativePaths @("bad_parse.ps1")
        if ($badParse.ExitCode -ne 2 -or $badParse.Output -notmatch 'bad_parse\.ps1') {
            $failures += "PS5 parser did not reject the planted BOM-less UTF-8 source"
        }
        [System.IO.File]::WriteAllBytes($badParsePath, [byte[]]([byte[]](0xEF, 0xBB, 0xBF) + $badParseBytes))
        $bomParse = Invoke-Ps51ParseMatrix -Root $fixtureRoot -RelativePaths @("bad_parse.ps1")
        if ($bomParse.ExitCode -ne 0) {
            $failures += "PS5 parser rejected the equivalent UTF-8 BOM fixture"
        }

        $hosts = @()
        foreach ($hostName in @("powershell.exe", "pwsh.exe")) {
            $command = Get-Command $hostName -ErrorAction SilentlyContinue
            if (-not $command) {
                $failures += "required host is unavailable: $hostName"
            }
            else {
                $hosts += @{ Name = $hostName; Path = $command.Source }
            }
        }

        $inProgressScript = Join-Path $repoRootPath "qa/check_in_progress.ps1"
        $runAllScript = Join-Path $repoRootPath "qa/run_all.ps1"
        foreach ($hostInfo in $hosts) {
            if (Test-Path -LiteralPath $sentinelPath) { Remove-Item -LiteralPath $sentinelPath }
            $zero = Invoke-HostScript -HostPath $hostInfo.Path -ScriptPath $inProgressScript -ScriptArguments @("-RepoRoot", $fixtureRoot, "-SkipGitDiff")
            if ($zero.ExitCode -ne 0 -or $zero.Output -notmatch 'no in-flight claims') {
                $failures += "$($hostInfo.Name) zero-sentinel contract failed (exit $($zero.ExitCode))"
            }

            Write-Sentinel -Path $sentinelPath -Started ([DateTime]::UtcNow.ToString("o"))
            $fresh = Invoke-HostScript -HostPath $hostInfo.Path -ScriptPath $inProgressScript -ScriptArguments @("-RepoRoot", $fixtureRoot, "-SkipGitDiff")
            if ($fresh.ExitCode -ne 0 -or $fresh.Output -notmatch 'active claim\(s\), all fresh') {
                $failures += "$($hostInfo.Name) fresh-sentinel contract failed (exit $($fresh.ExitCode))"
            }

            Write-Sentinel -Path $sentinelPath -Started ([DateTime]::UtcNow.AddHours(-48).ToString("o"))
            $stale = Invoke-HostScript -HostPath $hostInfo.Path -ScriptPath $inProgressScript -ScriptArguments @("-RepoRoot", $fixtureRoot, "-SkipGitDiff")
            if ($stale.ExitCode -ne 1 -or $stale.Output -notmatch 'probably stale') {
                $failures += "$($hostInfo.Name) stale-sentinel contract failed (exit $($stale.ExitCode))"
            }

            [System.IO.File]::WriteAllText($sentinelPath, "- **Session ID:** malformed`r`n", (New-Object System.Text.UTF8Encoding($false)))
            $malformed = Invoke-HostScript -HostPath $hostInfo.Path -ScriptPath $inProgressScript -ScriptArguments @("-RepoRoot", $fixtureRoot, "-SkipGitDiff")
            if ($malformed.ExitCode -ne 2 -or $malformed.Output -notmatch 'missing required') {
                $failures += "$($hostInfo.Name) malformed-sentinel contract failed (exit $($malformed.ExitCode))"
            }

            $policy = Invoke-HostScript -HostPath $hostInfo.Path -ScriptPath $runAllScript -ScriptArguments @("-SelfTest", "-Quiet")
            if ($policy.ExitCode -ne 0 -or $policy.Output -notmatch '\[run_all:selftest\] PASS') {
                $failures += "$($hostInfo.Name) run_all policy self-test failed (exit $($policy.ExitCode))"
            }
        }
    }
    finally {
        foreach ($file in @($sentinelPath, $asciiPath, $badPath, $badParsePath)) {
            if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
        }
        foreach ($directory in @($claimDir, $modDir, $fixtureRoot)) {
            if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory }
        }
    }

    if ($failures.Count -gt 0) {
        Write-Host "[check_ps51_compatibility:selftest] FAILED" -ForegroundColor Red
        foreach ($failure in $failures) { Write-Host "  X $failure" -ForegroundColor Red }
        exit 2
    }

    Write-Host "[check_ps51_compatibility:selftest] PASS - ASCII guard and PS5/pwsh fixture matrix passed." -ForegroundColor Green
    exit 0
}

if ($SelfTest) { Invoke-SelfTest }

$problems = @(Test-AsciiTargetSet -Root $repoRootPath -Targets $ps51Targets)
if ($problems.Count -gt 0) {
    Write-Host "[check_ps51_compatibility] FAILED - PS5-targeted scripts must be byte-ASCII:" -ForegroundColor Red
    foreach ($problem in $problems) { Write-Host "  X $problem" -ForegroundColor Red }
    exit 2
}


$parseClosure = @(Get-Ps51ParseClosure -Root $repoRootPath)
$parseResult = Invoke-Ps51ParseMatrix -Root $repoRootPath -RelativePaths $parseClosure
if ($parseResult.ExitCode -ne 0) {
    Write-Host "[check_ps51_compatibility] FAILED - PS5 invocation closure does not parse:" -ForegroundColor Red
    Write-Host $parseResult.Output -ForegroundColor Red
    exit 2
}

if (-not $Quiet) {
    Write-Host ("[check_ps51_compatibility] OK - {0} bootstrap scripts are byte-ASCII; {1} invocation scripts parse under PS5." -f $ps51Targets.Count, $parseClosure.Count) -ForegroundColor Green
}
exit 0
