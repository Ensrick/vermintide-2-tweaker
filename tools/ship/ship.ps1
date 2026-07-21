# tools/ship/ship.ps1
#
# CANONICAL one-shot RELEASE path for a single VT2 mod in this monorepo:
#   build + deploy + Workshop upload + GitHub release + hash/upload verification
#   + GitHub-issue status labeling (verify-fix[-coop] / diagnostics-armed, issue #326).
#
# Prefer this over hand-chaining `VMBLauncher.exe all <mod>` and
# `tools\publish-release\publish-release.ps1` separately. It runs both, then
# PROVES the deploy and upload actually transferred (the two steps that silently
# lie) so a release can't be quietly skipped.
#
# Usage:
#   .\tools\ship\ship.ps1 -Mod general_tweaker_dev
#   .\tools\ship\ship.ps1 -Mod chaos_wastes_tweaker -AllowPublic        # public Workshop item
#   .\tools\ship\ship.ps1 -Mod gui_tweaker_dev -NoRemote                # skip the PC-B push
#   .\tools\ship\ship.ps1 -Mod gui_tweaker_dev -SkipGitHub              # local ship only, no GH release
#   .\tools\ship\ship.ps1 -Mod gui_tweaker_dev -BuildOnly               # hidden, serialized bundle build
#
# WHY THIS SCRIPT EXISTS -- hard-won facts encoded below (do not "simplify" them away):
#
#  * `VMBLauncher.exe all <mod>` = build + deploy + upload. `deploy` is a
#    hash-verified LOCAL copy of `<mod>\bundleV2\*.mod_bundle` + the `.mod` into
#    `...\steamapps\workshop\content\552500\<published_id>\`. `upload` is the
#    ugc_tool push to the Steam Workshop SERVER. Public mods require
#    `--allow-public`; `--no-remote` skips the remote (PC-B) deploy target.
#
#  * ugc_tool prints "Upload finished" and exits 0 EVEN WHEN NOTHING TRANSFERRED.
#    "Upload finished" tells you nothing. The SOURCE OF TRUTH is
#    `C:\Program Files (x86)\Steam\logs\workshop_log.txt`:
#       "Uploaded new content ( ManifestID <N> ) for item <id>"  = real push
#       "No content change detected for item <id>"               = server already had it
#    (acceptable only when the local deploy hashes already match the server bundle).
#
#  * `published_id` lives in `<mod>\itemV2.cfg` as `published_id = <N>L;`.
#
#  * Step 3 releases ONLY the shipped mod to GitHub (issues #436/#493):
#    `publish-release.ps1 -Mods <mod> -SkipBuild`. Sibling zips and manifest
#    entries carry over from the existing release, so a sibling's mid-edit WIP
#    can neither fail this ship nor publish a mislabeled asset. The release-tag
#    probe never assumes the day's tag exists, and it must stay behind
#    Invoke-NativeProbe (issue #489: native stderr + redirection kills PS 5.1).
#
#  * TEST REFRESH (user ruling 2026-07-13): the author tests the hash-verified
#    local deploy directly and does not need to restart Steam. Volunteer testers
#    refresh through the dev collection by unsubscribing/resubscribing. In both
#    cases the newest console log's [<id>:LOAD] version is the final authority.
#
# Every step fails loudly (red message + non-zero exit) on the first problem.
#
# NOTE: comments + strings are ASCII only -- PowerShell parses .ps1 as Windows-1252
# by default and mangles em-dashes / box-drawing glyphs (memory:
# feedback_ps5_getcontent_utf8). Use '-' and '=' for separators, never Unicode.

[CmdletBinding()]
param(
    [string]$Mod,
    [switch]$AllowPublic,
    [switch]$NoRemote,
    [switch]$SkipGitHub,
    [switch]$BuildOnly,
    [switch]$NoClaim,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$lifecycleMethodPolicy = Join-Path $PSScriptRoot '..\verify\lifecycle_method_policy.ps1'
if (-not (Test-Path -LiteralPath $lifecycleMethodPolicy -PathType Leaf)) {
    throw "Shared lifecycle method policy not found: $lifecycleMethodPolicy"
}
. $lifecycleMethodPolicy

$launcherPathHelpers = Join-Path $PSScriptRoot '..\vmb-launcher-path.ps1'
if (-not (Test-Path -LiteralPath $launcherPathHelpers -PathType Leaf)) {
    throw "Shared VMBLauncher path helpers not found: $launcherPathHelpers"
}
. $launcherPathHelpers

function Fail {
    param([string]$Message)
    Write-Host ""
    Write-Host "SHIP FAILED: $Message" -ForegroundColor Red
    # Write-Error for a proper error record, but don't let it throw a second time
    # (global ErrorActionPreference is Stop); the explicit exit is the real signal.
    Write-Error $Message -ErrorAction Continue
    exit 1
}

# ---------------------------------------------------------------------------
# Pure helpers, hoisted so `-SelfTest` exercises the SAME code the live ship
# runs: the native-probe guard (issue #489) + step 6 labeling (issue #326).
# ---------------------------------------------------------------------------

# Native-command probe whose FAILURE is an expected branch (issue #489).
# Under stream redirection (agent-driven ships run `ship.ps1 ... 2>&1` / `*>`),
# Windows PowerShell 5.1 wraps native stderr into ErrorRecords, and with the
# script-global $ErrorActionPreference = 'Stop' the FIRST stderr line (e.g.
# `gh release view` on a tag that does not exist yet -- "release not found")
# becomes a TERMINATING error that kills the ship mid-run. pwsh 7.2+ does not
# have the trap, but ships must survive both hosts. So: scope EAP to Continue
# for the call, discard stderr, and let the EXIT CODE be the only signal.
# Never assume a release tag exists -- probe with this and branch on the code.
function Invoke-NativeProbe {
    param([scriptblock]$Command)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Command 2>$null | Out-Null } finally { $ErrorActionPreference = $prev }
    return $LASTEXITCODE
}

function Invoke-NativeCapture {
    param([scriptblock]$Command)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& $Command 2>&1 | ForEach-Object { $_.ToString() })
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prev
    }
    return [pscustomobject]@{ ExitCode = $code; Lines = $lines }
}

# Issue #829: a console-subsystem executable launched from a desktop agent process can ask
# Windows to allocate a visible console even when the executable selected its
# own headless code path. Start VMBLauncher with explicit no-window process
# flags and redirected streams so `ship.ps1` remains genuinely unattended in
# terminals, CI, and desktop automation. Output is replayed after exit; the
# launcher's exit code remains authoritative.
function ConvertTo-ShipWindowsArgument {
    param([AllowEmptyString()][string]$Value)
    if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) {
        [void]$builder.Append(('\' * ($backslashes * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-ShipLauncherNoWindow {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [switch]$ReplayOutput
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = (($ArgumentList | ForEach-Object { ConvertTo-ShipWindowsArgument ([string]$_) }) -join ' ')
    $workingRoot = if (-not [string]::IsNullOrWhiteSpace([string]$repoRoot)) {
        $repoRoot
    } else {
        (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    }
    $startInfo.WorkingDirectory = $workingRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw "Failed to start headless launcher: $FilePath" }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $lines = @()
        if (-not [string]::IsNullOrEmpty($stdout)) { $lines += @($stdout -split "`r?`n" | Where-Object { $_ -ne '' }) }
        if (-not [string]::IsNullOrEmpty($stderr)) { $lines += @($stderr -split "`r?`n" | Where-Object { $_ -ne '' }) }
        if ($ReplayOutput) { $lines | ForEach-Object { Write-Host $_ } }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Lines = $lines }
    }
    finally {
        $process.Dispose()
    }
}

function Test-ShipPathEqual {
    param([string]$Left, [string]$Right)
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
    $leftFull = [System.IO.Path]::GetFullPath($Left).TrimEnd('\', '/')
    $rightFull = [System.IO.Path]::GetFullPath($Right).TrimEnd('\', '/')
    return [string]::Equals($leftFull, $rightFull, [System.StringComparison]::OrdinalIgnoreCase)
}

# Return the primary checkout that owns the shared git common directory. This
# is dependency discovery only: source is never read or built from this root.
# A linked worktree's common directory is <primary>\.git.
function Get-ShipPrimaryWorktreeRoot {
    param([string]$RepoRoot)
    return Get-VmbLauncherPrimaryWorktreeRoot -RepoRoot $RepoRoot
}

function Get-ShipConfiguredProjectRoot {
    param([string]$SettingsPath)
    return Get-VmbLauncherConfiguredProjectRoot -SettingsPath $SettingsPath
}

function Resolve-ShipLauncherPath {
    param(
        [string]$RepoRoot,
        [string]$ExplicitPath,
        [string]$ConfiguredProjectRoot,
        [string]$PrimaryWorktreeRoot
    )

    return Resolve-ApprovedVmbLauncherPath `
        -RepoRoot $RepoRoot `
        -ConfiguredProjectRoot $ConfiguredProjectRoot `
        -PrimaryWorktreeRoot $PrimaryWorktreeRoot `
        -EnvironmentPath $ExplicitPath
}

function Test-ShipVmbRcForRoot {
    param([string]$VmbRcPath, [string]$RepoRoot)
    if (-not (Test-Path -LiteralPath $VmbRcPath -PathType Leaf)) {
        return [pscustomobject]@{ Ok = $false; Message = "missing .vmbrc: $VmbRcPath" }
    }
    try {
        $config = [System.IO.File]::ReadAllText($VmbRcPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]@{ Ok = $false; Message = "invalid JSON in $VmbRcPath ($($_.Exception.Message))" }
    }
    $modsDirRaw = if ($null -ne $config) { [string]$config.mods_dir } else { '' }
    if ([string]::IsNullOrWhiteSpace($modsDirRaw)) {
        return [pscustomobject]@{ Ok = $false; Message = "$VmbRcPath has no non-empty mods_dir" }
    }
    $resolvedModsDir = if ([System.IO.Path]::IsPathRooted($modsDirRaw)) {
        [System.IO.Path]::GetFullPath($modsDirRaw)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $modsDirRaw))
    }
    if (-not (Test-ShipPathEqual $resolvedModsDir $RepoRoot)) {
        return [pscustomobject]@{
            Ok = $false
            Message = "unsafe mods_dir '$modsDirRaw' resolves to '$resolvedModsDir', not invoking root '$RepoRoot'"
        }
    }
    return [pscustomobject]@{ Ok = $true; Message = "mods_dir resolves to invoking root" }
}

function Resolve-ShipVmbRcPath {
    param(
        [string]$RepoRoot,
        [string]$ExplicitPath,
        [string]$ConfiguredProjectRoot,
        [string]$PrimaryWorktreeRoot
    )

    $localPath = Join-Path $RepoRoot '.vmbrc'
    if (Test-Path -LiteralPath $localPath -PathType Leaf) {
        $check = Test-ShipVmbRcForRoot -VmbRcPath $localPath -RepoRoot $RepoRoot
        if (-not $check.Ok) { throw "Invoking worktree .vmbrc is unusable: $($check.Message)" }
        return [pscustomobject]@{ Path = $localPath; Source = 'invoking worktree'; NeedsStaging = $false }
    }

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $explicitFull = [System.IO.Path]::GetFullPath($ExplicitPath)
        $check = Test-ShipVmbRcForRoot -VmbRcPath $explicitFull -RepoRoot $RepoRoot
        if (-not $check.Ok) { throw "VT2_SHIP_VMBRC is unusable: $($check.Message)" }
        return [pscustomobject]@{ Path = $explicitFull; Source = 'VT2_SHIP_VMBRC'; NeedsStaging = $true }
    }

    $candidates = @(
        [pscustomobject]@{ Path = $(if ($ConfiguredProjectRoot) { Join-Path $ConfiguredProjectRoot '.vmbrc' } else { $null }); Source = 'VMBLauncher configured ProjectRoot' },
        [pscustomobject]@{ Path = $(if ($PrimaryWorktreeRoot) { Join-Path $PrimaryWorktreeRoot '.vmbrc' } else { $null }); Source = 'primary git worktree' },
        [pscustomobject]@{ Path = (Join-Path $RepoRoot '.vmbrc.example'); Source = 'tracked portable template' }
    )
    $seen = @{}
    $rejected = @()
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate.Path)) { continue }
        $full = [System.IO.Path]::GetFullPath([string]$candidate.Path)
        $key = $full.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $check = Test-ShipVmbRcForRoot -VmbRcPath $full -RepoRoot $RepoRoot
        if ($check.Ok) {
            return [pscustomobject]@{ Path = $full; Source = $candidate.Source; NeedsStaging = $true }
        }
        $rejected += $check.Message
    }
    throw ("No approved .vmbrc can bind mods_dir to the invoking worktree. " + ($rejected -join '; ') +
           ". Set VT2_SHIP_VMBRC to a valid config whose mods_dir resolves to this checkout.")
}

# VMB requires the exact filename <ProjectRoot>\.vmbrc. For a clean linked
# worktree, stage only the machine-local config bytes for the launcher window,
# then remove them in finally. Existing local config is never overwritten.
function Invoke-WithShipVmbRc {
    param(
        [string]$RepoRoot,
        [pscustomobject]$Resolution,
        [scriptblock]$Action
    )
    $target = Join-Path $RepoRoot '.vmbrc'
    if (-not $Resolution.NeedsStaging) {
        & $Action
        return
    }
    if (Test-Path -LiteralPath $target) {
        throw "Refusing to overwrite existing worktree config: $target"
    }
    $created = $false
    try {
        [System.IO.File]::WriteAllBytes($target, [System.IO.File]::ReadAllBytes($Resolution.Path))
        $created = $true
        $check = Test-ShipVmbRcForRoot -VmbRcPath $target -RepoRoot $RepoRoot
        if (-not $check.Ok) { throw "Staged .vmbrc validation failed: $($check.Message)" }
        & $Action
    }
    finally {
        if ($created -and (Test-Path -LiteralPath $target)) {
            Remove-Item -LiteralPath $target
            if (Test-Path -LiteralPath $target) {
                throw "CRITICAL: could not remove transient worktree config: $target"
            }
        }
    }
}

# Run one action with VMBLauncher's machine-global ProjectRoot bound to the
# repository that owns this copy of ship.ps1 (issue #647). Multiple git
# worktrees share %APPDATA%\VMBLauncher\settings.json; trusting its last GUI
# value let a ship launched from worktree A build stale source from worktree B.
# Preserve the file byte-for-byte and restore it in finally on both success and
# failure. Callers validate the bound identity before invoking `all`.
function Invoke-WithBoundLauncherProjectRoot {
    param(
        [string]$SettingsPath,
        [string]$ProjectRoot,
        [scriptblock]$Action,
        [string]$MutexName = 'Local\Ensrick.VT2Tweaker.VMBLauncher.ProjectRoot'
    )

    $mutex = New-Object System.Threading.Mutex($false, $MutexName)
    $hasMutex = $false
    try {
        try { $hasMutex = $mutex.WaitOne([System.TimeSpan]::FromSeconds(30)) }
        catch [System.Threading.AbandonedMutexException] { $hasMutex = $true }
        if (-not $hasMutex) {
            throw "Another ship owns the VMBLauncher ProjectRoot binding lock. Wait for it to finish, then retry."
        }

        if (-not (Test-Path -LiteralPath $SettingsPath)) {
            throw "VMBLauncher settings not found: $SettingsPath"
        }

        $originalBytes = [System.IO.File]::ReadAllBytes($SettingsPath)
        $restoreFailure = $null
        try {
            $originalText = [System.Text.Encoding]::UTF8.GetString($originalBytes)
            # ConvertFrom-Json treats a decoded U+FEFF as payload under some
            # PowerShell/.NET combinations. Accept the ordinary UTF-8 BOM at
            # the machine-owned settings boundary, while still restoring the
            # original bytes exactly after the temporary ProjectRoot binding.
            if ($originalText.Length -gt 0 -and $originalText[0] -eq [char]0xFEFF) {
                $originalText = $originalText.Substring(1)
            }
            try { $settings = $originalText | ConvertFrom-Json }
            catch { throw "VMBLauncher settings are not valid JSON: $SettingsPath ($($_.Exception.Message))" }

            if ($null -eq $settings) {
                throw "VMBLauncher settings decoded to null: $SettingsPath"
            }
            if ($settings.PSObject.Properties.Name -contains 'ProjectRoot') {
                $settings.ProjectRoot = $ProjectRoot
            }
            else {
                $settings | Add-Member -NotePropertyName ProjectRoot -NotePropertyValue $ProjectRoot
            }

            $boundText = $settings | ConvertTo-Json -Depth 20
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($SettingsPath, $boundText, $utf8NoBom)

            $roundTrip = ([System.IO.File]::ReadAllText($SettingsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json).ProjectRoot
            $expected = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
            $actual = if ($roundTrip) { [System.IO.Path]::GetFullPath([string]$roundTrip).TrimEnd('\', '/') } else { '' }
            if (-not [string]::Equals($actual, $expected, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "VMBLauncher ProjectRoot binding failed: expected '$expected', read back '$actual'."
            }

            & $Action
        }
        finally {
            try {
                [System.IO.File]::WriteAllBytes($SettingsPath, $originalBytes)
                $restored = [System.IO.File]::ReadAllBytes($SettingsPath)
                if ($restored.Length -ne $originalBytes.Length) {
                    throw "restored byte length $($restored.Length) != original $($originalBytes.Length)"
                }
                for ($i = 0; $i -lt $originalBytes.Length; $i++) {
                    if ($restored[$i] -ne $originalBytes[$i]) {
                        throw "restored byte mismatch at offset $i"
                    }
                }
            }
            catch {
                $restoreFailure = $_.Exception.Message
            }
            if ($restoreFailure) {
                throw "CRITICAL: could not restore VMBLauncher settings exactly after temporary ProjectRoot binding: $restoreFailure"
            }
        }
    }
    finally {
        if ($hasMutex) {
            try { $mutex.ReleaseMutex() } catch { }
        }
        $mutex.Dispose()
    }
}

# Pure identity comparison used by the live preflight and offline fixtures.
# Path, version, source commit, and Workshop id must all describe the invoking
# checkout before VMBLauncher is allowed to build/deploy/upload (issue #647).
function Test-ShipIdentityValues {
    param(
        [string]$ExpectedModDir,
        [string]$ResolvedModDir,
        [string]$ExpectedVersion,
        [string]$ResolvedVersion,
        [string]$ExpectedCommit,
        [string]$ResolvedCommit,
        [string]$ExpectedPublishedId,
        [string]$ResolvedPublishedId
    )

    $expectedPath = [System.IO.Path]::GetFullPath($ExpectedModDir).TrimEnd('\', '/')
    $resolvedPath = [System.IO.Path]::GetFullPath($ResolvedModDir).TrimEnd('\', '/')
    if (-not [string]::Equals($expectedPath, $resolvedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return @{ Ok = $false; Message = "root mismatch: invoking '$expectedPath', launcher resolved '$resolvedPath'" }
    }
    if ($ExpectedVersion -ne $ResolvedVersion) {
        return @{ Ok = $false; Message = "version mismatch: invoking '$ExpectedVersion', launcher resolved '$ResolvedVersion'" }
    }
    if ($ExpectedCommit -ne $ResolvedCommit) {
        return @{ Ok = $false; Message = "source mismatch: invoking commit '$ExpectedCommit', launcher resolved '$ResolvedCommit'" }
    }
    if ($ExpectedPublishedId -ne $ResolvedPublishedId) {
        return @{ Ok = $false; Message = "published_id mismatch: invoking '$ExpectedPublishedId', launcher resolved '$ResolvedPublishedId'" }
    }
    return @{ Ok = $true; Message = 'bound identity matches invoking checkout' }
}

# Compare one built artifact with its deployed copy (issue #646). Steam may
# rewrite the textual VMB descriptor from LF to CRLF after deployment. That is
# representation-equivalent, but every other byte remains significant. Normalize
# only CRLF pairs and only for the exact `.mod` extension; `.mod_bundle` and all
# other artifacts retain the byte-exact SHA-256 contract.
function Get-DescriptorComparableHash {
    param([string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $normalized = New-Object byte[] $bytes.Length
    $writeIndex = 0
    for ($readIndex = 0; $readIndex -lt $bytes.Length; $readIndex++) {
        if (($bytes[$readIndex] -eq 13) -and
            (($readIndex + 1) -lt $bytes.Length) -and
            ($bytes[$readIndex + 1] -eq 10)) {
            continue
        }
        $normalized[$writeIndex] = $bytes[$readIndex]
        $writeIndex++
    }

    if ($writeIndex -ne $normalized.Length) {
        $trimmed = New-Object byte[] $writeIndex
        if ($writeIndex -gt 0) {
            [System.Buffer]::BlockCopy($normalized, 0, $trimmed, 0, $writeIndex)
        }
        $normalized = $trimmed
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($normalized))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Test-DeployFileEquivalent {
    param([string]$SourcePath, [string]$DeployedPath)

    if ([System.IO.Path]::GetExtension($SourcePath) -ieq '.mod') {
        return ((Get-DescriptorComparableHash -Path $SourcePath) -eq
                (Get-DescriptorComparableHash -Path $DeployedPath))
    }

    return ((Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash -eq
            (Get-FileHash -LiteralPath $DeployedPath -Algorithm SHA256).Hash)
}

# Dev-stream = MOD_VERSION carries a release-track suffix. Only dev-stream
# ships run explicit lifecycle-transition automation; a clean stable promotion
# re-ships already-labeled work.
function Test-DevStreamVersion {
    param([string]$Version)
    return [bool]($Version -match '-(dev|alpha|beta|rc)\b')
}

# Top `## ` entry of a newest-first CHANGELOG. Returns @{ Header; Entry } or
# $null when the file has no version header at all.
function Get-TopChangelogEntry {
    param([string[]]$Lines)
    $first = -1; $second = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*##\s+\S') {
            if ($first -lt 0) { $first = $i } else { $second = $i; break }
        }
    }
    if ($first -lt 0) { return $null }
    $endEx = if ($second -ge 0) { $second } else { $Lines.Count }
    return @{
        Header = $Lines[$first].Trim()
        Entry  = ($Lines[$first..($endEx - 1)] -join "`n")
    }
}

# Decide what (if anything) to label from a shipped entry. Returns
# @{ Skip; Label; Refs; Coop; CoopRequired }.
# `Coop` is only the legacy heuristic/reminder.
#   * loc-sweep headers are skipped: their #N refs are tag CONTEXT, not
#     shipped work (same heuristic as qa/check_issue_status_labels.ps1).
#   * Tooling/docs entries are never auto-labeled. The live-test labels exist
#     only to build the user's in-game queue; repository work closes from
#     deterministic evidence instead.
#   * Label choice is ENTRY-level via exactly one explicit lifecycle marker;
#     missing or mixed intent fails closed before any GitHub mutation.
#   * `verify-fix-coop` is retired. Co-op is `verify-fix` or
#     `diagnostics-armed` plus `coop-required`, derived from the current live
#     test card after solo work is passed/exhausted.
function Get-ShipLabelPlan {
    param([string]$Header, [string]$Entry)
    if ($Header -match '(?i)(localization|loc sweep|status-tag doctrine|menu wording|localization audit|loc audit)') {
        return @{ Skip = 'loc-sweep'; Label = $null; Refs = @(); Coop = $false; CoopRequired = $false; RepositoryLabels = @() }
    }
    $repositoryLabels = if ($Header -match '(?i)\[(?:docs|documentation)\]') { @('tooling', 'documentation') }
        elseif ($Header -match '(?i)\[tooling\]') { @('tooling') }
        else { @() }
    if ($repositoryLabels.Count -gt 0) {
        return @{ Skip = 'tooling-entry'; Label = $null; Refs = @(); Coop = $false; CoopRequired = $false; RepositoryLabels = @() }
    }
    if ($Header -match '(?i)\[verify-fix-coop\]') {
        return @{ Skip = 'retired-lifecycle-marker'; Label = $null; Refs = @(); Coop = $false; CoopRequired = $false; RepositoryLabels = @() }
    }
    $explicit = @()
    if ($Header -match '(?i)\[not-started\]') { $explicit += 'not-started' }
    if ($Header -match '(?i)\[verify-fix\]') { $explicit += 'verify-fix' }
    if ($Header -match '(?i)\[(?:diagnostics-armed|diag)\]') { $explicit += 'diagnostics-armed' }
    $explicit = @($explicit | Select-Object -Unique)
    $coopRequired = [bool]($Header -match '(?i)\[coop-required\]')
    $coop = [bool]($Entry -match '(?i)(host *[/+] *(1 *)?client|non-\w+ +peer|husk|hot.join|2\+? *(player|tester|people)|two player|both peers|client CTD|CTDs? +a +client|desync|wire.safe|send.queue)')
    $numSet = @{}
    foreach ($m in [regex]::Matches($Entry, '#(\d+)')) { $numSet[[int]$m.Groups[1].Value] = $true }
    $refs = @($numSet.Keys | Sort-Object)
    if ($refs.Count -eq 0) { return @{ Skip = 'no-refs'; Label = $null; Refs = @(); Coop = $coop; CoopRequired = $coopRequired; RepositoryLabels = $repositoryLabels } }
    if ($explicit.Count -eq 0) { return @{ Skip = 'missing-lifecycle-marker'; Label = $null; Refs = $refs; Coop = $coop; CoopRequired = $coopRequired; RepositoryLabels = $repositoryLabels } }
    if ($explicit.Count -ne 1) { return @{ Skip = 'ambiguous-lifecycle-marker'; Label = $null; Refs = $refs; Coop = $coop; CoopRequired = $coopRequired; RepositoryLabels = $repositoryLabels } }
    $label = $explicit[0]
    return @{ Skip = $null; Label = $label; Refs = $refs; Coop = $coop; CoopRequired = $coopRequired; RepositoryLabels = $repositoryLabels }
}

$LifecycleLabels = @('not-started', 'verify-fix', 'diagnostics-armed')
$RetiredLifecycleLabels = @('Fixed', 'verify-fix-coop')

# Return the one lifecycle label that should survive and every competing label
# to remove in the same `gh issue edit` invocation. Retired lifecycle labels
# are removed opportunistically. An existing coop verification is never
# downgraded by an unmarked later ship.
function Get-LifecycleEditPlan {
    param([string[]]$Existing, [string]$Requested, [bool]$FailedVerificationEvidence = $false)
    $existingVerify = if ($Existing -contains 'verify-fix') { 'verify-fix' } else { $null }
    if ($Requested -eq 'diagnostics-armed' -and $existingVerify -and -not $FailedVerificationEvidence) {
        return @{ Target = $existingVerify; Remove = @(); Add = $false; BlockedDowngrade = $true }
    }
    $target = $Requested
    $remove = @($Existing | Where-Object {
        (($LifecycleLabels -contains $_) -and $_ -ne $target) -or ($RetiredLifecycleLabels -contains $_)
    } | Select-Object -Unique)
    return @{ Target = $target; Remove = $remove; Add = -not ($Existing -contains $target); BlockedDowngrade = $false }
}

# Preserve an existing co-op routing qualifier when a later diagnostics ship
# omits the redundant changelog marker. An unmarked diagnostics update must
# never silently downgrade a known two-player capture to a solo playtest.
# The qualifier is removed only when the issue leaves diagnostics entirely.
function Get-CoopQualifierEditPlan {
    param([string[]]$Existing, [string]$LifecycleTarget, [bool]$ExplicitlyRequired)
    $hasExisting = $Existing -contains 'coop-required'
    $want = $LifecycleTarget -in @('diagnostics-armed', 'verify-fix') -and $ExplicitlyRequired
    return @{
        Want = $want
        Add = $want -and -not $hasExisting
        Remove = $hasExisting -and -not $want
    }
}

# Pure, combined issue-transition decision. This is the single pre-mutation
# boundary used by live ship and offline fixtures: selected method, repository
# routing, topology, downgrade evidence, lifecycle edit, and qualifier edit are
# evaluated together so independently-correct helpers cannot compose unsafely.
function Get-ShipIssueTransitionDecision {
    param(
        [string[]]$Existing,
        [string]$Requested,
        [bool]$CoopRequired,
        [string[]]$RepositoryLabels,
        $Comments,
        [string]$Body
    )

    $effectiveLabels = @($Existing) + @($RepositoryLabels)
    $isRepositoryOnly = Test-VtRepositoryOnlyLabels $effectiveLabels
    if ($isRepositoryOnly) {
        return @{ Ok = $false; Reason = 'tooling-issue-not-auto-labeled'; IsRepositoryOnly = $true }
    }
    if (($Existing -contains 'blocked') -and $Requested -ne 'not-started') {
        return @{ Ok = $false; Reason = 'blocked-issue-not-ready'; IsRepositoryOnly = $false }
    }

    $selection = Get-VtLifecycleMethodSelection -Comments $Comments -Body $Body
    if ($Requested -in @('diagnostics-armed', 'verify-fix') -and -not $selection.Valid) {
        return @{ Ok = $false; Reason = 'invalid-current-live-test-card'; Selection = $selection; IsRepositoryOnly = $false }
    }

    $failedVerification = Test-VtFailedVerificationEvidence $selection.Method
    $edit = Get-LifecycleEditPlan -Existing $Existing -Requested $Requested -FailedVerificationEvidence $failedVerification
    if ($edit.BlockedDowngrade) {
        return @{ Ok = $false; Reason = 'unevidenced-verify-downgrade'; Selection = $selection; Edit = $edit; IsRepositoryOnly = $isRepositoryOnly }
    }

    $target = $edit.Target
    $methodRequiresCoop = $selection.Valid -and (Test-VtMethodRequiresCoop $selection.Method)

    $coopEdit = Get-CoopQualifierEditPlan -Existing $Existing -LifecycleTarget $target -ExplicitlyRequired $methodRequiresCoop
    return @{
        Ok = $true
        Reason = $null
        Selection = $selection
        Edit = $edit
        CoopEdit = $coopEdit
        IsRepositoryOnly = $isRepositoryOnly
        MethodRequiresCoop = $methodRequiresCoop
    }
}

# Offline self-test of the step-6 logic + the issue-#489 native-probe guard
# (qa-script convention: exit 0 = OK, exit 2 = regression). Runnable standalone
# (`ship.ps1 -SelfTest`) and via qa/run_selftests.ps1. Network/gh interaction
# is NOT covered here -- that path prints every decision at live-ship time for
# hand-correction.
function Invoke-ShipSelfTest {
    $script:__stpass = $true
    function Assert($cond, $desc) {
        $verdict = if ($cond) { 'PASS' } else { 'FAIL' }
        $colour  = if ($cond) { 'Green' } else { 'Red' }
        Write-Host ("  [{0}] {1}" -f $verdict, $desc) -ForegroundColor $colour
        if (-not $cond) { $script:__stpass = $false }
    }

    Assert (Test-DevStreamVersion '0.7.225-dev')  "dev suffix ships labels (0.7.225-dev)"
    Assert (Test-DevStreamVersion '0.2.1-beta')   "beta suffix ships labels (0.2.1-beta)"
    Assert (-not (Test-DevStreamVersion '1.0.0')) "clean stable version does NOT auto-label (1.0.0)"
    Assert (-not (Test-DevStreamVersion '(unknown)')) "unknown version does NOT auto-label"

    $cl = @(
        '# Changelog',
        '',
        '## 0.7.222-dev (2026-07-04) - #294 (crash) FIXED: non-resident pickup CTD',
        '',
        '- **#294 (crash) FIXED.** Details. Separate latent bug tracked as #322.',
        '',
        '## 0.7.221-dev (2026-07-04) - older entry referencing #288',
        '',
        '- old work on #288.'
    )
    $top = Get-TopChangelogEntry -Lines $cl
    Assert ($null -ne $top) "top entry found in a normal changelog"
    Assert ($top.Header -like '*0.7.222-dev*') "top header is the NEWEST version"
    Assert ($top.Entry -notmatch '#288') "entry text does not bleed into the second entry"
    Assert ($null -eq (Get-TopChangelogEntry -Lines @('no headers', 'here'))) "changelog without '## ' headers returns null"

    $plan = Get-ShipLabelPlan -Header ($top.Header + ' [verify-fix]') -Entry $top.Entry
    Assert ($null -eq $plan.Skip) "fix entry is not skipped"
    Assert ($plan.Label -eq 'verify-fix') "fix entry labels verify-fix"
    Assert (($plan.Refs -join ',') -eq '294,322') "refs harvested, deduped, sorted (294,322)"

    $planD = Get-ShipLabelPlan -Header '## 0.7.225-dev - #144 [diag] retire trace, add [ct:vaul] probe' -Entry 'probe work for #144'
    Assert ($planD.Label -eq 'diagnostics-armed') "probe-marker header labels diagnostics-armed"

    $planC = Get-ShipLabelPlan -Header '## 0.7.226-dev - #586 [verify-fix-coop] peer fix' -Entry 'host/client work for #586'
    Assert ($planC.Skip -eq 'retired-lifecycle-marker') "retired verify-fix-coop marker fails closed"

    $planDC = Get-ShipLabelPlan -Header '## 0.7.227-dev - #600 [diag] [coop-required] wire probe' -Entry 'probe #600'
    Assert ($planDC.Label -eq 'diagnostics-armed') "coop diagnostic keeps diagnostics-armed as its lifecycle"
    Assert ($planDC.CoopRequired) "coop diagnostic requests the orthogonal coop-required qualifier"

    $planSmell = Get-ShipLabelPlan -Header '## 0.7.228-dev - #601 [verify-fix] peer fix' -Entry 'host/client fix for #601'
    Assert ($planSmell.Label -eq 'verify-fix') "coop-smelling prose alone does not silently change lifecycle intent"
    Assert ($planSmell.Coop -and -not $planSmell.CoopRequired) "coop smell remains a review reminder"

    $life = Get-LifecycleEditPlan -Existing @('bug', 'not-started', 'diagnostics-armed') -Requested 'verify-fix'
    Assert ($life.Target -eq 'verify-fix') "verify request becomes the sole lifecycle target"
    Assert (($life.Remove -join ',') -eq 'not-started,diagnostics-armed') "verify transition removes all competing lifecycle labels"
    Assert ($life.Add) "missing lifecycle target is added"

    $keepCoop = Get-LifecycleEditPlan -Existing @('verify-fix', 'verify-fix-coop', 'not-started') -Requested 'verify-fix'
    Assert ($keepCoop.Target -eq 'verify-fix') "retired coop lifecycle cannot survive a verify transition"
    Assert (($keepCoop.Remove -join ',') -eq 'verify-fix-coop,not-started') "verify transition retires old and competing labels"

    $retiredCleanup = Get-LifecycleEditPlan -Existing @('Fixed', 'not-started', 'diagnostics-armed') -Requested 'verify-fix'
    Assert ($retiredCleanup.Target -eq 'verify-fix') "requested canonical lifecycle replaces invalid open labels"
    Assert (($retiredCleanup.Remove -join ',') -eq 'Fixed,not-started,diagnostics-armed') "retired and competing lifecycle labels are removed atomically"

    $blockedDowngrade = Get-LifecycleEditPlan -Existing @('verify-fix') -Requested 'diagnostics-armed'
    Assert ($blockedDowngrade.BlockedDowngrade -and $blockedDowngrade.Target -eq 'verify-fix') "verify-to-diagnostics downgrade requires failed-verification evidence"
    $allowedDowngrade = Get-LifecycleEditPlan -Existing @('verify-fix') -Requested 'diagnostics-armed' -FailedVerificationEvidence $true
    Assert (-not $allowedDowngrade.BlockedDowngrade -and $allowedDowngrade.Target -eq 'diagnostics-armed') "evidenced failed verification permits diagnostics transition"

    $keepDiagCoop = Get-CoopQualifierEditPlan -Existing @('diagnostics-armed', 'coop-required') -LifecycleTarget 'diagnostics-armed' -ExplicitlyRequired $false
    Assert (-not $keepDiagCoop.Want -and -not $keepDiagCoop.Add -and $keepDiagCoop.Remove) "solo card strips stale coop-required routing"

    $addDiagCoop = Get-CoopQualifierEditPlan -Existing @('diagnostics-armed') -LifecycleTarget 'diagnostics-armed' -ExplicitlyRequired $true
    Assert ($addDiagCoop.Want -and $addDiagCoop.Add -and -not $addDiagCoop.Remove) "explicit coop diagnostic adds missing qualifier"

    $removeStaleCoop = Get-CoopQualifierEditPlan -Existing @('coop-required') -LifecycleTarget 'verify-fix' -ExplicitlyRequired $false
    Assert (-not $removeStaleCoop.Want -and -not $removeStaleCoop.Add -and $removeStaleCoop.Remove) "leaving diagnostics removes stale coop-required qualifier"

    $combinedBody = "## CURRENT LIVE TEST`n`n**Build/banner:** v1.2.3-dev, confirm ``[wt:LOAD]```n**Topology:** Solo`n`n1. Equip Kruber's Mace in the Keep.`n`n**Expected:** Kruber's Mace behaves normally."
    $combinedDiagnostic = Get-ShipIssueTransitionDecision -Existing @('diagnostics-armed', 'tooling') -Requested 'diagnostics-armed' -CoopRequired $false -RepositoryLabels @('tooling') -Comments @() -Body $combinedBody
    Assert (-not $combinedDiagnostic.Ok -and $combinedDiagnostic.Reason -eq 'tooling-issue-not-auto-labeled') "ship never auto-labels tooling work"

    $combinedVerifyBodyOnly = Get-ShipIssueTransitionDecision -Existing @('diagnostics-armed') -Requested 'verify-fix' -CoopRequired $false -Comments @() -Body $combinedBody
    Assert (-not $combinedVerifyBodyOnly.Ok -and $combinedVerifyBodyOnly.Reason -eq 'invalid-current-live-test-card') "live-test labels never accept an issue-body fallback"

    $soloMethod = @([pscustomobject]@{ body = $combinedBody })
    $combinedRepositoryCoop = Get-ShipIssueTransitionDecision -Existing @('verify-fix', 'tooling') -Requested 'verify-fix' -CoopRequired $false -RepositoryLabels @('tooling') -Comments $soloMethod -Body ''
    Assert (-not $combinedRepositoryCoop.Ok -and $combinedRepositoryCoop.Reason -eq 'tooling-issue-not-auto-labeled') "combined transition rejects repository-only live testing"

    $coopCard = "## CURRENT LIVE TEST`n`n**Build/banner:** v1.2.3-dev, confirm ``[wt:LOAD]```n**Topology:** Co-op (host and one client)`n**Solo status:** Passed; remote view remains.`n`n1. Host equips Kruber's Mace.`n2. The joining player observes it.`n`n**Expected:** Both players see Kruber's Mace."
    $coopMethod = @([pscustomobject]@{ body = $coopCard })
    $combinedPreserveCoop = Get-ShipIssueTransitionDecision -Existing @('verify-fix-coop') -Requested 'verify-fix' -CoopRequired $false -Comments $coopMethod -Body ''
    Assert ($combinedPreserveCoop.Ok -and $combinedPreserveCoop.Edit.Target -eq 'verify-fix' -and $combinedPreserveCoop.CoopEdit.Want) "co-op card uses verify-fix plus coop-required and retires old lifecycle"

    $failedDiagnostic = @([pscustomobject]@{ body = $combinedBody.Replace("**Expected:**", "Verification still fails on the deployed build.`n`n**Expected:**") })
    $combinedDowngrade = Get-ShipIssueTransitionDecision -Existing @('verify-fix') -Requested 'diagnostics-armed' -CoopRequired $false -Comments $failedDiagnostic -Body ''
    Assert ($combinedDowngrade.Ok -and $combinedDowngrade.Edit.Target -eq 'diagnostics-armed') "combined transition permits an evidenced failed-verification downgrade"

    $existingCoopDiagnostic = Get-ShipIssueTransitionDecision -Existing @('diagnostics-armed', 'coop-required') -Requested 'diagnostics-armed' -CoopRequired $false -Comments $coopMethod -Body ''
    Assert ($existingCoopDiagnostic.Ok -and $existingCoopDiagnostic.CoopEdit.Want) "combined transition preserves an existing co-op diagnostic qualifier"

    $planL = Get-ShipLabelPlan -Header '## 0.12.204-dev - Localization: applied dev status-tag doctrine (#301)' -Entry 'refs #74 #108 as tag context'
    Assert ($planL.Skip -eq 'loc-sweep') "loc-sweep header is skipped"

    $planT = Get-ShipLabelPlan -Header '## 0.1.3-dev - #602 [tooling] [verify-fix] release check' -Entry 'tool-only work #602'
    Assert ($planT.Skip -eq 'tooling-entry') "explicit tooling work is never auto-labeled"
    $planDocs = Get-ShipLabelPlan -Header '## 0.1.4-dev - #661 [docs] [verify-fix] lifecycle documentation' -Entry 'documentation work #661'
    Assert ($planDocs.Skip -eq 'tooling-entry') "docs work is never auto-labeled"
    $runtimeDocumentation = Get-ShipIssueTransitionDecision -Existing @('bug', 'documentation', 'verify-fix', 'Tweaker: Weapons', 'CWV', 'cross-mod', '0-critical', 'WOC') -Requested 'verify-fix' -CoopRequired $false -RepositoryLabels @() -Comments $soloMethod -Body ''
    Assert ($runtimeDocumentation.Ok -and -not $runtimeDocumentation.IsRepositoryOnly) "#661-shaped runtime issue stays in the playtest route"

    $missingIntent = Get-ShipLabelPlan -Header '## 0.1.4-dev - #603 partial implementation' -Entry 'partial work #603'
    Assert ($missingIntent.Skip -eq 'missing-lifecycle-marker') "unmarked work cannot receive an inferred verify lifecycle"
    $ambiguousIntent = Get-ShipLabelPlan -Header '## 0.1.5-dev - #604 [diag] [verify-fix] mixed' -Entry 'mixed work #604'
    Assert ($ambiguousIntent.Skip -eq 'ambiguous-lifecycle-marker') "mixed lifecycle markers fail closed"
    $explicitBeatsProse = Get-ShipLabelPlan -Header '## 0.1.6-dev - #605 [verify-fix-coop] fix diagnostic output' -Entry 'host/client #605'
    Assert ($explicitBeatsProse.Skip -eq 'retired-lifecycle-marker') "retired lifecycle intent fails closed"

    $planN = Get-ShipLabelPlan -Header '## 0.1.2-dev - housekeeping' -Entry 'no issue references here'
    Assert ($planN.Skip -eq 'no-refs') "entry without #N refs is a no-op"

    # Issue #489: the native-probe guard. A native command that writes stderr
    # and exits nonzero (the `gh release view <missing tag>` shape) must NOT
    # throw under EAP=Stop -- on PS 5.1 with redirected streams the unguarded
    # `2>&1 | Out-Null` pattern raised a terminating NativeCommandError and
    # killed the ship mid-run. The exit code must come through faithfully.
    $probeThrew = $false; $probeCode = $null
    try { $probeCode = Invoke-NativeProbe { cmd /c "echo probe-stderr 1>&2 & exit 7" } }
    catch { $probeThrew = $true }
    Assert (-not $probeThrew) "native probe does not throw on stderr + nonzero exit (issue #489)"
    Assert ($probeCode -eq 7) "native probe propagates the failure exit code (7)"
    Assert ((Invoke-NativeProbe { cmd /c "exit 0" }) -eq 0) "native probe returns 0 on success"
    Assert ($ErrorActionPreference -eq 'Stop') "native probe restores ErrorActionPreference to Stop"

    # Issue #646: Steam normalizes textual `.mod` descriptors to CRLF. The
    # deploy gate accepts that one representation difference without weakening
    # the byte-exact contract for compiled bundles or hiding real text changes.
    $compareDir = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-ship-646-" + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($compareDir) | Out-Null
    try {
        $lfMod = Join-Path $compareDir 'source.mod'
        $crlfMod = Join-Path $compareDir 'deployed.mod'
        $changedMod = Join-Path $compareDir 'changed.mod'
        $standaloneCrBaseMod = Join-Path $compareDir 'standalone-cr-base.mod'
        $standaloneCrMod = Join-Path $compareDir 'standalone-cr.mod'
        $lfBundle = Join-Path $compareDir 'source.mod_bundle'
        $crlfBundle = Join-Path $compareDir 'deployed.mod_bundle'

        $lfText = "name = `"example`";`npackage = `"example`";`n"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($lfMod, $lfText, $utf8NoBom)
        [System.IO.File]::WriteAllText($crlfMod, $lfText.Replace("`n", "`r`n"), $utf8NoBom)
        [System.IO.File]::WriteAllText($changedMod, $lfText.Replace('example";', 'different";'), $utf8NoBom)
        [System.IO.File]::WriteAllBytes($standaloneCrBaseMod, [byte[]](110, 97, 109, 101, 120, 10))
        [System.IO.File]::WriteAllBytes($standaloneCrMod, [byte[]](110, 97, 109, 101, 13, 120, 10))
        [System.IO.File]::WriteAllBytes($lfBundle, [byte[]](65, 10, 66))
        [System.IO.File]::WriteAllBytes($crlfBundle, [byte[]](65, 13, 10, 66))

        Assert (Test-DeployFileEquivalent $lfMod $crlfMod) "LF/CRLF-only .mod descriptor difference is equivalent (issue #646)"
        Assert (-not (Test-DeployFileEquivalent $lfMod $changedMod)) "real .mod descriptor content change still fails"
        Assert (-not (Test-DeployFileEquivalent $standaloneCrBaseMod $standaloneCrMod)) "standalone CR is not normalized away"
        Assert (-not (Test-DeployFileEquivalent $lfBundle $crlfBundle)) ".mod_bundle comparison remains byte-exact"
        Assert (Test-DeployFileEquivalent $lfBundle $lfBundle) "byte-identical bundle still passes"
    }
    finally {
        if (Test-Path $compareDir) {
            Get-ChildItem -LiteralPath $compareDir -File | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName
            }
            Remove-Item -LiteralPath $compareDir
        }
    }

    # Issues #436/#493 interface contract + the 2026-07-13 param-stomp incident:
    # step 3 passes `-Mods $Mod` to publish-release.ps1, so that script MUST
    # declare the [string[]]$Mods parameter -- and must never assign to a
    # case-insensitive twin: PowerShell variable names are CASE-INSENSITIVE, so
    # an inventory assignment to $mods silently OVERWRITES the $Mods parameter
    # (live failure 2026-07-13: the filter validator saw 19 inventory hashtables
    # instead of the single shipped mod name and the release step aborted).
    $pubPath = Join-Path $PSScriptRoot '..\publish-release\publish-release.ps1'
    $pubTxt = if (Test-Path $pubPath) { [System.IO.File]::ReadAllText($pubPath, [System.Text.Encoding]::UTF8) } else { '' }
    Assert ($pubTxt -match '(?m)^\s*\[string\[\]\]\$Mods\b') "publish-release.ps1 declares [string[]]`$Mods (issues #436/#493)"
    Assert ($pubTxt -match '(?m)^\s*\[string\]\$LauncherPath\b' -and
        $pubTxt -match '(?m)^\s*\[string\]\$LauncherSource\b' -and
        $pubTxt -match '(?m)^\s*\[string\]\$LauncherApprovalAnchor\b') "publish-release.ps1 declares the exact launcher approval interface (issue #683)"
    Assert ($pubTxt -match 'Resolve-ApprovedVmbLauncherPath') "publish-release.ps1 revalidates the shared approved-launcher contract (issue #683)"
    Assert (-not ($pubTxt -cmatch '(?m)^\s*\$mods\s*=')) "publish-release.ps1 never assigns lowercase `$mods (param-stomp guard, 2026-07-13)"
    Assert ($pubTxt -match 'Resolve-GitHubReleaseByTag' -and $pubTxt -match 'Publish-GitHubReleaseAssetsById') "publish-release owns exact-tag fallback and release-id mutation (issue #651)"
    $shipSource = [System.IO.File]::ReadAllText($PSCommandPath, [System.Text.Encoding]::UTF8)
    $legacyTagProbe = 'gh release ' + 'view $tag'
    $legacyTagUpload = 'gh release ' + 'upload $tag'
    Assert ($shipSource.IndexOf($legacyTagProbe, [System.StringComparison]::Ordinal) -lt 0) "ship wrapper has no duplicate release-by-tag existence probe (issue #651)"
    Assert ($shipSource.IndexOf($legacyTagUpload, [System.StringComparison]::Ordinal) -lt 0) "ship wrapper delegates existing-release mutation to release-id tooling (issue #651)"
    Assert ($shipSource -match 'CreateNoWindow\s*=\s*\$true') "VMBLauncher process creation explicitly suppresses visible console windows"
    Assert ($shipSource -match 'ProcessWindowStyle\]::Hidden') "VMBLauncher process window style is hidden"
    Assert ($shipSource -match 'Invoke-ShipLauncherNoWindow -FilePath \$launcher') "identity and release calls use the no-window launcher boundary"
    $rawLauncherCall = '& $' + 'launcher @launcherArgs'
    Assert ($shipSource.IndexOf($rawLauncherCall, [System.StringComparison]::Ordinal) -lt 0) "release path never invokes VMBLauncher through the raw PowerShell call operator"

    $hostExe = (Get-Process -Id $PID).Path
    $hiddenProbe = Invoke-ShipLauncherNoWindow -FilePath $hostExe -ArgumentList @(
        '-NoProfile', '-Command', '[Console]::Out.Write("ship-hidden-probe")'
    )
    Assert ($hiddenProbe.ExitCode -eq 0) "no-window process boundary preserves native exit code"
    Assert (($hiddenProbe.Lines -join '') -eq 'ship-hidden-probe') "no-window process boundary captures redirected output"

    # Issue #647: multiple worktrees share one VMBLauncher settings file. The
    # ship wrapper must bind ProjectRoot only for the launcher window, restore
    # the original bytes on success/failure, and reject any identity mismatch.
    $bindingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-ship-647-" + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($bindingDir) | Out-Null
    try {
        $settingsPath = Join-Path $bindingDir 'settings.json'
        $mutexProbePath = Join-Path $bindingDir 'mutex-probe.ps1'
        $testMutexName = 'Local\Ensrick.VT2Tweaker.ShipSelfTest.' + [guid]::NewGuid().ToString('N')
        $originalSettings = [string][char]0xFEFF + "{`r`n  `"ProjectRoot`": `"C:\\old-root`",`r`n  `"Sentinel`": `"preserve exactly`"`r`n}`r`n"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($settingsPath, $originalSettings, $utf8NoBom)
        $mutexProbeSource = @'
param([string]$Name, [string]$Expected)
$m = New-Object System.Threading.Mutex($false, $Name)
$got = $false
try {
    try { $got = $m.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $got = $true }
    $state = if ($got) { 'free' } else { 'busy' }
    if ($state -ne $Expected) { exit 2 }
    exit 0
}
finally {
    if ($got) { try { $m.ReleaseMutex() } catch { } }
    $m.Dispose()
}
'@
        [System.IO.File]::WriteAllText($mutexProbePath, $mutexProbeSource, $utf8NoBom)
        $originalSettingsBytes = [System.IO.File]::ReadAllBytes($settingsPath)

        $seenPath = Join-Path $bindingDir 'seen-root.txt'
        Invoke-WithBoundLauncherProjectRoot -SettingsPath $settingsPath -ProjectRoot $bindingDir -MutexName $testMutexName -Action {
            $seenBoundRoot = ([System.IO.File]::ReadAllText($settingsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json).ProjectRoot
            [System.IO.File]::WriteAllText($seenPath, [string]$seenBoundRoot, $utf8NoBom)
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mutexProbePath -Name $testMutexName -Expected busy
            if ($LASTEXITCODE -ne 0) { throw 'named ship mutex was not held during the bound action' }
        }
        $seenBoundRoot = [System.IO.File]::ReadAllText($seenPath, [System.Text.Encoding]::UTF8)
        Assert ($seenBoundRoot -eq $bindingDir) "launcher action sees the invoking worktree root (issue #647)"
        $afterSuccess = [System.IO.File]::ReadAllBytes($settingsPath)
        Assert (($afterSuccess.Length -eq $originalSettingsBytes.Length) -and
                (([System.BitConverter]::ToString($afterSuccess)) -eq ([System.BitConverter]::ToString($originalSettingsBytes)))) "global launcher settings restore byte-exactly after success"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mutexProbePath -Name $testMutexName -Expected free
        Assert ($LASTEXITCODE -eq 0) "named ship mutex releases after successful action"

        $threwExpected = $false
        try {
            Invoke-WithBoundLauncherProjectRoot -SettingsPath $settingsPath -ProjectRoot $bindingDir -MutexName $testMutexName -Action {
                throw 'fixture action failure'
            }
        }
        catch { $threwExpected = ($_.Exception.Message -match 'fixture action failure') }
        Assert $threwExpected "bound launcher action propagates its failure"
        $afterFailure = [System.IO.File]::ReadAllBytes($settingsPath)
        Assert (($afterFailure.Length -eq $originalSettingsBytes.Length) -and
                (([System.BitConverter]::ToString($afterFailure)) -eq ([System.BitConverter]::ToString($originalSettingsBytes)))) "global launcher settings restore byte-exactly after failure"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mutexProbePath -Name $testMutexName -Expected free
        Assert ($LASTEXITCODE -eq 0) "named ship mutex releases after failed action"

        $identity = Test-ShipIdentityValues 'C:\repo\mod' 'c:\repo\mod' '1.2.3-dev' '1.2.3-dev' 'abc123' 'abc123' '42' '42'
        Assert $identity.Ok "matching root/version/source/id identity passes"
        Assert (-not (Test-ShipIdentityValues 'C:\repo-a\mod' 'C:\repo-b\mod' '1.2.3-dev' '1.2.3-dev' 'abc123' 'abc123' '42' '42').Ok) "different worktree root aborts"
        Assert (-not (Test-ShipIdentityValues 'C:\repo\mod' 'C:\repo\mod' '1.2.3-dev' '1.2.2-dev' 'abc123' 'abc123' '42' '42').Ok) "different MOD_VERSION aborts"
        Assert (-not (Test-ShipIdentityValues 'C:\repo\mod' 'C:\repo\mod' '1.2.3-dev' '1.2.3-dev' 'abc123' 'def456' '42' '42').Ok) "different source commit aborts"
        Assert (-not (Test-ShipIdentityValues 'C:\repo\mod' 'C:\repo\mod' '1.2.3-dev' '1.2.3-dev' 'abc123' 'abc123' '42' '43').Ok) "different published_id aborts"
    }
    finally {
        if (Test-Path $bindingDir) {
            Get-ChildItem -LiteralPath $bindingDir -File | ForEach-Object { Remove-Item -LiteralPath $_.FullName }
            Remove-Item -LiteralPath $bindingDir
        }
    }

    # Clean linked worktrees do not contain the ignored launcher checkout or
    # .vmbrc. Dependency fallback may supply only those machine-local bytes;
    # mods_dir and the later launcher identity probe must still bind source to
    # the invoking worktree. Every temporary file must be cleaned on failure.
    $dependencyDir = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-ship-deps-" + [guid]::NewGuid().ToString('N'))
    $fixtureRepo = Join-Path $dependencyDir 'invoking'
    $fixtureConfigured = Join-Path $dependencyDir 'configured'
    [System.IO.Directory]::CreateDirectory($fixtureRepo) | Out-Null
    [System.IO.Directory]::CreateDirectory($fixtureConfigured) | Out-Null
    try {
        $missingLauncherRejected = $false
        try {
            Resolve-ShipLauncherPath -RepoRoot $fixtureRepo -ExplicitPath '' -ConfiguredProjectRoot $null -PrimaryWorktreeRoot $null | Out-Null
        }
        catch { $missingLauncherRejected = ($_.Exception.Message -match 'not found') }
        Assert $missingLauncherRejected "clean worktree fails closed when no approved launcher exists"

        $launcherRelative = 'tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe'
        $configuredLauncher = Join-Path $fixtureConfigured $launcherRelative
        [System.IO.Directory]::CreateDirectory((Split-Path $configuredLauncher -Parent)) | Out-Null
        [System.IO.File]::WriteAllBytes($configuredLauncher, [byte[]](1, 2, 3))
        $launcherFound = Resolve-ShipLauncherPath -RepoRoot $fixtureRepo -ExplicitPath '' -ConfiguredProjectRoot $fixtureConfigured -PrimaryWorktreeRoot $null
        Assert ((Test-ShipPathEqual $launcherFound.Path $configuredLauncher) -and $launcherFound.Source -eq 'VMBLauncher configured ProjectRoot') "configured worktree supplies launcher bytes without supplying source"

        $badExplicitLauncherRejected = $false
        try {
            Resolve-ShipLauncherPath -RepoRoot $fixtureRepo -ExplicitPath (Join-Path $dependencyDir 'missing.exe') -ConfiguredProjectRoot $fixtureConfigured -PrimaryWorktreeRoot $null | Out-Null
        }
        catch { $badExplicitLauncherRejected = ($_.Exception.Message -match 'VT2_SHIP_VMB_LAUNCHER') }
        Assert $badExplicitLauncherRejected "invalid explicit launcher fails instead of silently falling back"

        $missingRcRejected = $false
        try {
            Resolve-ShipVmbRcPath -RepoRoot $fixtureRepo -ExplicitPath '' -ConfiguredProjectRoot $null -PrimaryWorktreeRoot $null | Out-Null
        }
        catch { $missingRcRejected = ($_.Exception.Message -match 'No approved .vmbrc') }
        Assert $missingRcRejected "clean worktree fails closed when no approved .vmbrc exists"

        $wrongRc = Join-Path $fixtureConfigured '.vmbrc'
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($wrongRc, '{ "mods_dir": "mods" }', $utf8NoBom)
        $wrongRootRejected = $false
        try {
            Resolve-ShipVmbRcPath -RepoRoot $fixtureRepo -ExplicitPath $wrongRc -ConfiguredProjectRoot $null -PrimaryWorktreeRoot $null | Out-Null
        }
        catch { $wrongRootRejected = ($_.Exception.Message -match 'not invoking root') }
        Assert $wrongRootRejected "candidate .vmbrc that redirects to another source root is rejected"

        [System.IO.File]::WriteAllText($wrongRc, "{`r`n  `"mods_dir`": `".`",`r`n  `"sentinel`": `"preserve bytes`"`r`n}`r`n", $utf8NoBom)
        $rcResolution = Resolve-ShipVmbRcPath -RepoRoot $fixtureRepo -ExplicitPath '' -ConfiguredProjectRoot $fixtureConfigured -PrimaryWorktreeRoot $null
        Assert ($rcResolution.NeedsStaging -and $rcResolution.Source -eq 'VMBLauncher configured ProjectRoot') "configured .vmbrc is selected only for transient staging"

        $stagedMarker = Join-Path $dependencyDir 'staged-seen.txt'
        Invoke-WithShipVmbRc -RepoRoot $fixtureRepo -Resolution $rcResolution -Action {
            if (Test-Path -LiteralPath (Join-Path $fixtureRepo '.vmbrc') -PathType Leaf) {
                [System.IO.File]::WriteAllText($stagedMarker, 'yes', $utf8NoBom)
            }
        }
        Assert (Test-Path -LiteralPath $stagedMarker -PathType Leaf) "transient .vmbrc exists during launcher action"
        Assert (-not (Test-Path -LiteralPath (Join-Path $fixtureRepo '.vmbrc'))) "transient .vmbrc is removed after successful action"

        $stageFailurePropagated = $false
        try {
            Invoke-WithShipVmbRc -RepoRoot $fixtureRepo -Resolution $rcResolution -Action { throw 'planted launcher failure' }
        }
        catch { $stageFailurePropagated = ($_.Exception.Message -match 'planted launcher failure') }
        Assert $stageFailurePropagated "transient-config wrapper propagates launcher failure"
        Assert (-not (Test-Path -LiteralPath (Join-Path $fixtureRepo '.vmbrc'))) "transient .vmbrc is removed after failed action"

        $localRc = Join-Path $fixtureRepo '.vmbrc'
        $localRcText = "{`r`n  `"mods_dir`": `".`",`r`n  `"local`": true`r`n}`r`n"
        [System.IO.File]::WriteAllText($localRc, $localRcText, $utf8NoBom)
        $localBytesBefore = [System.IO.File]::ReadAllBytes($localRc)
        $localResolution = Resolve-ShipVmbRcPath -RepoRoot $fixtureRepo -ExplicitPath $wrongRc -ConfiguredProjectRoot $fixtureConfigured -PrimaryWorktreeRoot $null
        Invoke-WithShipVmbRc -RepoRoot $fixtureRepo -Resolution $localResolution -Action { }
        $localBytesAfter = [System.IO.File]::ReadAllBytes($localRc)
        Assert (-not $localResolution.NeedsStaging) "existing invoking-worktree .vmbrc wins over fallback candidates"
        Assert (([System.BitConverter]::ToString($localBytesBefore)) -eq ([System.BitConverter]::ToString($localBytesAfter))) "existing invoking-worktree .vmbrc remains byte-exact"
    }
    finally {
        if (Test-Path $dependencyDir) {
            Get-ChildItem -LiteralPath $dependencyDir -Recurse -File | ForEach-Object { Remove-Item -LiteralPath $_.FullName }
            Get-ChildItem -LiteralPath $dependencyDir -Recurse -Directory |
                Sort-Object { $_.FullName.Length } -Descending |
                ForEach-Object { Remove-Item -LiteralPath $_.FullName }
            Remove-Item -LiteralPath $dependencyDir
        }
    }

    # Issue #591: this is an ordering invariant, not merely a documentation
    # promise. Both offline gates must execute before the launcher can perform
    # its first build/deploy/upload action.
    $selfTxt = [System.IO.File]::ReadAllText($PSCommandPath, [System.Text.Encoding]::UTF8)
    $quickPos = $selfTxt.IndexOf('& $quickGate -Quick -SkipLua -Quiet')
    $lintPos = $selfTxt.IndexOf('& $modLint $Mod -Quiet')
    $launcherCallMarker = 'Invoke-ShipLauncherNoWindow -FilePath $' + 'launcher'
    $launcherPos = $selfTxt.LastIndexOf($launcherCallMarker)
    Assert ($quickPos -ge 0) "ship source invokes the fast headless QA gate (issue #591)"
    Assert ($lintPos -ge 0) "ship source invokes target-mod lint (issue #591)"
    Assert ($launcherPos -ge 0 -and $quickPos -lt $launcherPos -and $lintPos -lt $launcherPos) "both headless gates precede launcher build/deploy/upload"

    # Parallel-session collision guard: the ship/version claim gate must be
    # present, must precede the launcher, and must expose the -NoClaim escape
    # hatch. The banner marker is concatenated so it appears literally only once
    # (in the gate banner), not here.
    $claimGateMarker = 'SHIP/VERSION ' + 'CLAIM GATE'
    $claimGatePos = $selfTxt.IndexOf($claimGateMarker)
    # LastIndexOf: compare against the MAIN-BODY launcher call, not the earlier
    # self-test assertions.
    $launcherMainPos = $selfTxt.LastIndexOf($launcherCallMarker)
    Assert ($claimGatePos -ge 0) "ship source contains the ship/version claim gate (parallel-session collision guard)"
    Assert ($claimGatePos -ge 0 -and $launcherMainPos -ge 0 -and $claimGatePos -lt $launcherMainPos) "claim gate precedes launcher build/deploy/upload"
    Assert ($selfTxt.IndexOf('-Verify -ExpectedVersion $modVersion') -ge 0) "claim gate verifies the claim against the source MOD_VERSION"
    Assert ($selfTxt.IndexOf('6 { Fail "Ship claim for') -ge 0) "claim gate rejects a same-version foreign owner"
    Assert ($selfTxt.IndexOf('Claim broker missing') -ge 0) "missing claim broker fails closed"
    Assert ($selfTxt.IndexOf('-Mod $Mod -Release -Quiet') -ge 0) "ship auto-releases the claim on success"
    Assert ($selfTxt -match '(?m)^\s*\[switch\]\$NoClaim\b') "ship exposes the -NoClaim solo-session escape hatch"
    Assert ($selfTxt -match '(?m)^\s*\[switch\]\$BuildOnly\b') "ship exposes the canonical hidden build-only path"
    Assert ($selfTxt.IndexOf('-SkipBundleAtomicity:$BuildOnly') -ge 0) "build-only preflight defers bundle atomicity until after generation"
    Assert ($selfTxt.IndexOf('-SkipCustomUnitBundleReachability:$BuildOnly') -ge 0) "build-only preflight defers compiled custom-unit reachability until after generation"
    Assert ($selfTxt.IndexOf('qa\check_custom_unit_bundle_reachability.ps1') -ge 0) "build-only runs custom-unit reachability after generation"
    Assert ($selfTxt.IndexOf("@('build', `$Mod, '--clean')") -ge 0) "build-only invokes VMBLauncher's clean build action"
    Assert ($selfTxt.IndexOf('BUILD-ONLY COMPLETE') -ge 0) "build-only exits before deploy/upload/release handling"

    Write-Host ""
    if ($script:__stpass) {
        Write-Host "[ship.ps1 -SelfTest] OK -- ship helper contracts intact." -ForegroundColor Green
        return 0
    } else {
        Write-Host "[ship.ps1 -SelfTest] FAILED -- ship helper regression." -ForegroundColor Red
        return 2
    }
}

if ($SelfTest) { exit (Invoke-ShipSelfTest) }
if (-not $Mod) { Fail "Usage: ship.ps1 -Mod <name> [-AllowPublic] [-NoRemote] [-SkipGitHub] [-BuildOnly]  (or ship.ps1 -SelfTest)" }
if ($BuildOnly -and ($AllowPublic -or $NoRemote -or $SkipGitHub)) {
    Fail "-BuildOnly cannot be combined with -AllowPublic, -NoRemote, or -SkipGitHub because it never deploys, uploads, or publishes."
}

# ---------------------------------------------------------------------------
# Step 1: resolve paths + parse published_id and MOD_VERSION
# ---------------------------------------------------------------------------
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modDir   = Join-Path $repoRoot $Mod
if (-not (Test-Path $modDir)) { Fail "Mod directory not found: $modDir" }

$cfgPath = Join-Path $modDir 'itemV2.cfg'
if (-not (Test-Path $cfgPath)) { Fail "itemV2.cfg not found: $cfgPath" }
# Read as UTF-8 explicitly -- PS 5.1 Get-Content -Raw uses the system code page.
$cfgTxt = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8)
if ($cfgTxt -notmatch 'published_id\s*=\s*(\d+)L') {
    Fail "No published_id found in $cfgPath (mod not yet uploaded to Workshop?)"
}
$publishedId = $matches[1]

# ---------------------------------------------------------------------------
# Preflight (issue #344): refuse to ship while ANY itemV2.cfg carries a wrong or
# colliding published_id. An upload with a crossed id HIJACKS another mod's
# Workshop item (2026-07-05: gut_dev's cfg transiently carried ct_dev's id and
# the ship pushed gut content onto ct_dev's item). Same check the pre-commit
# gate runs, moved to BEFORE ugc_tool ever sees a cfg.
# ---------------------------------------------------------------------------
$idCheck = Join-Path $repoRoot 'qa\check_published_ids.ps1'
if (Test-Path $idCheck) {
    & $idCheck
    if ($LASTEXITCODE -ne 0) {
        Fail "check_published_ids FAILED -- fix the cfg id(s) above before shipping. A crossed id hijacks another mod's Workshop item (issue #344)."
    }
}

$luaPath    = Join-Path $modDir "scripts\mods\$Mod\$Mod.lua"
$modVersion = '(unknown)'
# The in-game load line uses the mod's INTERNAL short id (e.g. "gut", "gt", "ct"),
# which is not the directory name. Parse it from the lua's "[<id>:LOAD]" marker so
# the restart-reminder tells the user the exact token to grep for. Fall back to the
# dir name if no marker is present.
$loadTag = $Mod
if (Test-Path $luaPath) {
    $luaTxt = [System.IO.File]::ReadAllText($luaPath, [System.Text.Encoding]::UTF8)
    if ($luaTxt -match 'MOD_VERSION\s*=\s*"([^"]+)"') { $modVersion = $matches[1] }
    if ($luaTxt -match '\[(\w+):LOAD\]')              { $loadTag = $matches[1] }
}

# ---------------------------------------------------------------------------
# SHIP/VERSION CLAIM GATE (parallel-session collision guard). Full rationale +
# usage: tools/ship/CLAIMS.md. Runs BEFORE the QA gates and before any
# build/deploy/upload so a missing/mismatched claim fails fast and cheap.
#
# Parallel Claude sessions on this machine repeatedly allocated the SAME next
# MOD_VERSION and uploaded competing bundles (cosmetics 0.9.143 + 0.9.145, wt
# 0.12.273-beta, wt_dev 0.12.274-dev), each forcing a reconciliation build.
# claim.ps1 is an atomic per-mod lock that also records the allocated version;
# this gate refuses to ship unless a LIVE claim exists whose version and owner
# match the source MOD_VERSION and current task. Its own claim is auto-released
# on ship success.
#
# -NoClaim skips the gate (loud warning) for a solo session or an urgent fix.
# Without that explicit override, missing tooling and every coordination-state
# failure are fail-closed before VMB can build, deploy, or upload.
# ---------------------------------------------------------------------------
if ($NoClaim) {
    Write-Host ""
    Write-Host "  !! -NoClaim: skipping the ship/version claim gate. Safe ONLY in a solo" -ForegroundColor Yellow
    Write-Host "     session -- parallel sessions can collide on MOD_VERSION and upload" -ForegroundColor Yellow
    Write-Host "     competing bundles (see tools/ship/CLAIMS.md)." -ForegroundColor Yellow
}
else {
    $claimScript = Join-Path $PSScriptRoot 'claim.ps1'
    if (-not (Test-Path -LiteralPath $claimScript)) {
        Fail "Claim broker missing at $claimScript. Refusing an unguarded ship; restore tools/ship/claim.ps1 or use the explicit -NoClaim emergency override."
    }
    else {
        & $claimScript -Mod $Mod -Verify -ExpectedVersion $modVersion -Quiet
        $claimExit = $LASTEXITCODE
        switch ($claimExit) {
            0 { Write-Host "  OK -- live ship claim for $Mod matches v$modVersion." -ForegroundColor Green }
            3 { Fail "No live ship claim for '$Mod'. Run:  .\tools\ship\claim.ps1 -Mod $Mod  (it allocates the next version -- set MOD_VERSION to the value it prints, then re-ship). Solo session: re-run ship.ps1 with -NoClaim. See tools/ship/CLAIMS.md." }
            4 { Fail "Ship claim for '$Mod' does not match the source MOD_VERSION ($modVersion). Another session likely allocated a different version. Reconcile: .\tools\ship\claim.ps1 -Mod $Mod -Release  then re-claim and re-bump. See tools/ship/CLAIMS.md." }
            5 { Fail "Ship claim for '$Mod' is STALE (older than 2h). Re-claim with .\tools\ship\claim.ps1 -Mod $Mod (a fresh claimant breaks a stale claim), set MOD_VERSION to the printed value, then re-ship. See tools/ship/CLAIMS.md." }
            6 { Fail "Ship claim for '$Mod' has the right version but belongs to another task/worktree. This process cannot consume it. Coordinate with the owner or wait for stale recovery; do not use -NoClaim while parallel work is active." }
            default { Fail "Ship claim verification failed (claim.ps1 exit $claimExit). See tools/ship/CLAIMS.md; -NoClaim overrides in a solo session." }
        }
    }
}

$commitProbe = Invoke-NativeCapture { & git -C $repoRoot rev-parse HEAD }
if ($commitProbe.ExitCode -ne 0 -or $commitProbe.Lines.Count -eq 0) {
    Fail "Cannot resolve the invoking checkout's source commit at $repoRoot. Shipping requires a git worktree identity (issue #647)."
}
$sourceCommit = ([string]$commitProbe.Lines[-1]).Trim()

# ---------------------------------------------------------------------------
# Promotion red gate (issue #327): shipping one of the five STABLE split dirs
# must pass qa/check_promotion.ps1 BLOCKING (defense-in-depth against player-facing
# lifecycle metadata, unsanctioned pre-release suffixes, and version monotonicity vs the
# stable CHANGELOG). Advisory scans warned for weeks while two promotions each
# leaked a checklist step to public subscribers - hence a hard gate. A
# user-NAMED suffixed public version (issue #328 ruling) ships with
# $env:VT2_SUFFIX_OK = '1'.
# ---------------------------------------------------------------------------
$promoGate = Join-Path $repoRoot 'qa\check_promotion.ps1'
$stableSplitDirs = @('chaos_wastes_tweaker', 'crafting_in_modded', 'general_tweaker', 'gui_tweaker', 'verminious_dreams_lighting')
if (($stableSplitDirs -contains $Mod) -and (Test-Path $promoGate)) {
    & $promoGate -Mod $Mod
    if ($LASTEXITCODE -ne 0) {
        Fail "check_promotion FAILED -- this stable/public target did not clear the promotion gate (issue #327). Fix the findings above (or VT2_SUFFIX_OK=1 for a user-named suffixed public version) and re-ship."
    }
}

$launcherSettings = Join-Path $env:APPDATA 'VMBLauncher\settings.json'
if (-not (Test-Path -LiteralPath $launcherSettings -PathType Leaf)) {
    Fail "VMBLauncher settings not found: $launcherSettings"
}
try {
    $configuredProjectRoot = Get-ShipConfiguredProjectRoot -SettingsPath $launcherSettings
    $primaryWorktreeRoot = Get-ShipPrimaryWorktreeRoot -RepoRoot $repoRoot
    $launcherResolution = Resolve-ShipLauncherPath `
        -RepoRoot $repoRoot `
        -ExplicitPath $env:VT2_SHIP_VMB_LAUNCHER `
        -ConfiguredProjectRoot $configuredProjectRoot `
        -PrimaryWorktreeRoot $primaryWorktreeRoot
    $vmbRcResolution = Resolve-ShipVmbRcPath `
        -RepoRoot $repoRoot `
        -ExplicitPath $env:VT2_SHIP_VMBRC `
        -ConfiguredProjectRoot $configuredProjectRoot `
        -PrimaryWorktreeRoot $primaryWorktreeRoot
}
catch {
    Fail $_.Exception.Message
}
$launcher = $launcherResolution.Path

# ---------------------------------------------------------------------------
# Headless red gate (issues #590/#591): exercise the same fast, host-runnable
# QA tier used by local development before the launcher is allowed to build,
# deploy, or upload anything.  Previously most QA ran only at commit/CI time,
# so a direct ship could put a statically-invalid build on Workshop first.
#
# -Quick includes pure Lua 5.1 unit tests; -SkipLua skips only the slow advisory
# luacheck pass.  Target lint keeps its established severity ladder: duplicate
# hook errors block, heuristic warnings remain visible but non-blocking.
# ---------------------------------------------------------------------------
$quickGate = Join-Path $repoRoot 'qa\run_all.ps1'
if (-not (Test-Path $quickGate)) {
    Fail "Headless QA gate not found: $quickGate"
}

Write-Host ""
Write-Host "==> Headless preflight (fast QA + Lua 5.1 units)" -ForegroundColor Cyan
& $quickGate -Quick -SkipLua -SkipBundleAtomicity:$BuildOnly -SkipCustomUnitBundleReachability:$BuildOnly -Quiet
if ($LASTEXITCODE -ne 0) {
    Fail "Headless QA FAILED -- no build, deploy, or upload was attempted (issue #591)."
}

$modLint = Join-Path $repoRoot 'tools\mod-lint\lint-mod.ps1'
if (-not (Test-Path $modLint)) {
    Fail "Target-mod lint gate not found: $modLint"
}

Write-Host ""
Write-Host "==> Target-mod preflight lint ($Mod)" -ForegroundColor Cyan
& $modLint $Mod -Quiet
$modLintExit = $LASTEXITCODE
if ($modLintExit -ge 2) {
    Fail "Target-mod lint FAILED -- no build, deploy, or upload was attempted (issue #591)."
}
if ($modLintExit -eq 1) {
    Write-Host "Target-mod lint reported advisory warnings; shipping may continue." -ForegroundColor Yellow
}

$workshopRoot = 'C:\Program Files (x86)\Steam\steamapps\workshop\content\552500'
$deployDir    = Join-Path $workshopRoot $publishedId
$workshopLog  = 'C:\Program Files (x86)\Steam\logs\workshop_log.txt'

Write-Host ""
$operationLabel = if ($BuildOnly) { 'Building bundle for' } else { 'Shipping' }
Write-Host "==> $operationLabel $Mod  (v$modVersion, published_id $publishedId)" -ForegroundColor Cyan
Write-Host "    repo root : $repoRoot"
Write-Host "    launcher  : $launcher ($($launcherResolution.Source))"
Write-Host "    .vmbrc    : $($vmbRcResolution.Path) ($($vmbRcResolution.Source))"
Write-Host "    deploy dir: $deployDir"
if ($AllowPublic) { Write-Host "    --allow-public : ON (public Workshop item)" -ForegroundColor Yellow }
if ($NoRemote)    { Write-Host "    --no-remote    : ON (skipping PC-B push)" }

# ---------------------------------------------------------------------------
# Step 2: build + deploy + upload via VMBLauncher
# ---------------------------------------------------------------------------
$launcherArgs = if ($BuildOnly) { @('build', $Mod, '--clean') } else { @('all', $Mod) }
if (-not $BuildOnly -and $AllowPublic) { $launcherArgs += '--allow-public' }
if (-not $BuildOnly -and $NoRemote)    { $launcherArgs += '--no-remote' }
$launcherArgs += @('--config', $launcherSettings)

Write-Host ""
Write-Host "==> VMBLauncher $($launcherArgs -join ' ')" -ForegroundColor Cyan
# Do NOT pipe the launcher's pipeline output through Select-Object/head -- that
# trips the PowerShell broken-pipe quirk that reports $LASTEXITCODE = -1 on a
# clean exit. VMBLauncher keeps its established `all` semantics; the wrapper
# only stages validated machine-local tooling, binds the shared ProjectRoot,
# and validates source identity before allowing it to run.
try {
    Invoke-WithShipVmbRc -RepoRoot $repoRoot -Resolution $vmbRcResolution -Action {
        Invoke-WithBoundLauncherProjectRoot -SettingsPath $launcherSettings -ProjectRoot $repoRoot -Action {
            # Ask the launcher which mod it resolved while the temporary binding is
            # active. Abort before `all` (therefore before deploy/upload) if root,
            # version, source commit, or Workshop identity differs from Step 1.
            $info = Invoke-ShipLauncherNoWindow -FilePath $launcher `
                -ArgumentList @('info', $Mod, '--no-banner', '--config', $launcherSettings)
            if ($info.ExitCode -ne 0) {
                throw "VMBLauncher identity probe failed (exit $($info.ExitCode)): $($info.Lines -join ' | ')"
            }
            $resolvedModDir = $null
            foreach ($line in $info.Lines) {
                if ($line -match '^Mod folder:\s*(.+?)\s*$') { $resolvedModDir = $matches[1]; break }
            }
            if (-not $resolvedModDir) {
                throw "VMBLauncher identity probe did not report 'Mod folder': $($info.Lines -join ' | ')"
            }

            $resolvedLuaPath = Join-Path $resolvedModDir "scripts\mods\$Mod\$Mod.lua"
            $resolvedCfgPath = Join-Path $resolvedModDir 'itemV2.cfg'
            if (-not (Test-Path -LiteralPath $resolvedLuaPath) -or -not (Test-Path -LiteralPath $resolvedCfgPath)) {
                throw "VMBLauncher resolved incomplete source at '$resolvedModDir'."
            }
            $resolvedLua = [System.IO.File]::ReadAllText($resolvedLuaPath, [System.Text.Encoding]::UTF8)
            $resolvedVersion = if ($resolvedLua -match 'MOD_VERSION\s*=\s*"([^"]+)"') { $matches[1] } else { '(unknown)' }
            $resolvedCfg = [System.IO.File]::ReadAllText($resolvedCfgPath, [System.Text.Encoding]::UTF8)
            $resolvedPublishedId = if ($resolvedCfg -match 'published_id\s*=\s*(\d+)L') { $matches[1] } else { '(unknown)' }
            $resolvedRoot = Split-Path $resolvedModDir -Parent
            $resolvedCommitProbe = Invoke-NativeCapture { & git -C $resolvedRoot rev-parse HEAD }
            $resolvedCommit = if ($resolvedCommitProbe.ExitCode -eq 0 -and $resolvedCommitProbe.Lines.Count -gt 0) {
                ([string]$resolvedCommitProbe.Lines[-1]).Trim()
            } else { '(unknown)' }

            $identity = Test-ShipIdentityValues `
                -ExpectedModDir $modDir -ResolvedModDir $resolvedModDir `
                -ExpectedVersion $modVersion -ResolvedVersion $resolvedVersion `
                -ExpectedCommit $sourceCommit -ResolvedCommit $resolvedCommit `
                -ExpectedPublishedId $publishedId -ResolvedPublishedId $resolvedPublishedId
            if (-not $identity.Ok) {
                throw "Ship identity invariant FAILED: $($identity.Message). No build/deploy/upload was attempted."
            }
            Write-Host "  OK -- ProjectRoot, MOD_VERSION, source commit, and published_id match the invoking checkout." -ForegroundColor Green

            $launcherRun = Invoke-ShipLauncherNoWindow -FilePath $launcher `
                -ArgumentList $launcherArgs -ReplayOutput
            $launcherExit = $launcherRun.ExitCode
            if ($launcherExit -ne 0) {
                $launcherOperation = if ($BuildOnly) { 'build' } else { 'all' }
                throw "VMBLauncher '$launcherOperation $Mod' exited $launcherExit (see output above)."
            }
        }
    }
}
catch {
    Fail $_.Exception.Message
}

if ($BuildOnly) {
    $bundleGate = Join-Path $repoRoot 'qa\check_release_bundle_atomicity.ps1'
    if (-not (Test-Path -LiteralPath $bundleGate -PathType Leaf)) {
        Fail "Post-build bundle atomicity gate not found: $bundleGate"
    }
    & $bundleGate -Quiet
    if ($LASTEXITCODE -ne 0) {
        Fail "Build completed, but the generated root bundle did not satisfy release atomicity. No deploy or upload was attempted."
    }
    $unitReachabilityGate = Join-Path $repoRoot 'qa\check_custom_unit_bundle_reachability.ps1'
    if (-not (Test-Path -LiteralPath $unitReachabilityGate -PathType Leaf)) {
        Fail "Post-build custom-unit reachability gate not found: $unitReachabilityGate"
    }
    & $unitReachabilityGate -Quiet
    if ($LASTEXITCODE -ne 0) {
        Fail "Build completed, but one or more custom unit resources are still absent from the compiled bundle. No deploy or upload was attempted."
    }
    Write-Host ""
    Write-Host "BUILD-ONLY COMPLETE -- bundle generated; atomicity and custom-unit reachability verified; no deploy, upload, GitHub release, or lifecycle edit was attempted." -ForegroundColor Green
    exit 0
}

# ---------------------------------------------------------------------------
# Mid-ship id-stomp detector (issue #344): in the 2026-07-05 incident the cfg
# was CORRECT when this script read it (the banner printed the canonical id)
# and a foreign id was written into it DURING the launcher window, so ugc_tool
# uploaded to the wrong Workshop item while the ship summary looked clean.
# Re-read the cfg and compare against the ship-start id; scream if it moved.
# ---------------------------------------------------------------------------
$cfgTxtAfter = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8)
if ($cfgTxtAfter -match 'published_id\s*=\s*(\d+)L' -and $matches[1] -ne $publishedId) {
    Fail ("published_id CHANGED mid-ship: read $publishedId at ship start, cfg now carries $($matches[1]). " +
          "ugc_tool may have uploaded to the WRONG Workshop item -- check workshop_log.txt for BOTH ids " +
          "and re-verify both items' content before doing anything else (issue #344).")
}

# ---------------------------------------------------------------------------
# Step 3: GitHub release (vt2-mod-updater consumers) unless -SkipGitHub
# ---------------------------------------------------------------------------
$githubStatus = 'SKIPPED'
if (-not $SkipGitHub) {
    $tag       = "mods-$(Get-Date -Format yyyy-MM-dd)"
    $pubScript = Join-Path $repoRoot 'tools\publish-release\publish-release.ps1'
    if (-not (Test-Path $pubScript)) { Fail "publish-release.ps1 not found at $pubScript" }

    Write-Host ""
    Write-Host "==> GitHub release (tag $tag) -- THIS mod only (issues #436/#493)" -ForegroundColor Cyan

    # Per-mod release (issues #436/#493): pass -Mods $Mod so publish-release
    # stages ONLY this mod's zip and carries every sibling's manifest entry over
    # from the release's existing manifest. Rebuilding/restaging all 18+ mods
    # here let any sibling's mid-edit WIP fail THIS ship (#493) and published
    # sibling zips whose version label was never actually shipped (#436).
    # -SkipBuild because step 2's `VMBLauncher all` built this bundle seconds
    # ago -- re-building here would race mid-ship source edits; the GitHub asset
    # must be byte-identical to the bundle that just went to the Workshop.
    #
    # publish-release owns exact-tag resolution and mutation.  Its issue #651
    # path distinguishes absent/unavailable/degraded states, falls back through
    # a bounded releases-list lookup on transient tag-route failure, and updates
    # an existing release through its numeric id.  Do not duplicate a tag probe
    # here: a 503 must never be misclassified as "release absent" by ship.ps1.
    try {
        & $pubScript -Tag $tag -Mods $Mod -SkipBuild `
            -LauncherPath $launcherResolution.Path `
            -LauncherSource $launcherResolution.Source `
            -LauncherApprovalAnchor $launcherResolution.ApprovalAnchor
    }
    catch {
        Fail "publish-release.ps1 failed: $($_.Exception.Message)"
    }
    $githubStatus = "OK ($tag)"
}

# ---------------------------------------------------------------------------
# Step 4: VERIFY DEPLOY -- byte-exact bundles; newline-normalized .mod descriptor
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Verifying deploy (SHA256 bundleV2 vs Workshop content folder)" -ForegroundColor Cyan
$bundleDir = Join-Path $modDir 'bundleV2'
if (-not (Test-Path $bundleDir)) { Fail "bundleV2 missing at $bundleDir (build did not produce output)" }
if (-not (Test-Path $deployDir)) {
    Fail "Deploy folder missing: $deployDir -- are you SUBSCRIBED to this mod on Workshop? (deploy can't create it)"
}

$mismatches = @()
$checked    = 0
$normalizedDescriptors = 0
foreach ($f in Get-ChildItem $bundleDir -File) {
    $target = Join-Path $deployDir $f.Name
    if (-not (Test-Path $target)) {
        $mismatches += "  $($f.Name): MISSING in deploy folder"
        continue
    }
    $srcHash = (Get-FileHash -Algorithm SHA256 -Path $f.FullName).Hash
    $dstHash = (Get-FileHash -Algorithm SHA256 -Path $target).Hash
    $checked++
    if ($srcHash -ne $dstHash) {
        if (Test-DeployFileEquivalent -SourcePath $f.FullName -DeployedPath $target) {
            $normalizedDescriptors++
            Write-Host "  OK -- $($f.Name): descriptor differs only by LF/CRLF line endings." -ForegroundColor DarkGreen
        }
        else {
            $mismatches += "  $($f.Name): src $($srcHash.Substring(0,12)).. != deploy $($dstHash.Substring(0,12)).."
        }
    }
}

$deployOk = ($mismatches.Count -eq 0)
if (-not $deployOk) {
    Write-Host "  DEPLOY HASH MISMATCH (Steam likely reconciled the folder back to a cached manifest):" -ForegroundColor Red
    $mismatches | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Fail "Deploy verification failed: $($mismatches.Count) file(s) differ between $bundleDir and $deployDir."
}
$normalizationNote = if ($normalizedDescriptors -gt 0) {
    "; $normalizedDescriptors textual .mod descriptor(s) line-ending-equivalent"
} else { '' }
Write-Host ("  OK -- {0} file(s) verified (bundles byte-exact{1})." -f $checked, $normalizationNote) -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 5: VERIFY UPLOAD -- scan recent workshop_log.txt for this published_id
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Verifying upload (workshop_log.txt)" -ForegroundColor Cyan
$uploadStatus = 'NONE'   # NONE | UPLOADED | NOCHANGE
$matchedLine  = ''
if (-not (Test-Path $workshopLog)) {
    Fail "workshop_log.txt not found at $workshopLog -- cannot confirm the upload transferred."
}
$cutoff = (Get-Date).AddMinutes(-5)
$tail   = Get-Content $workshopLog -Tail 40
foreach ($line in $tail) {
    if ($line -notmatch '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]') { continue }
    $ts = $null
    try { $ts = [datetime]::ParseExact($matches[1], 'yyyy-MM-dd HH:mm:ss', $null) } catch { continue }
    if ($ts -lt $cutoff) { continue }
    if ($line -notmatch [regex]::Escape($publishedId)) { continue }
    if ($line -match 'Uploaded new content') {
        $uploadStatus = 'UPLOADED'; $matchedLine = $line   # strongest signal -- keep scanning, UPLOADED wins
    }
    elseif ($line -match 'No content change' -and $uploadStatus -ne 'UPLOADED') {
        $uploadStatus = 'NOCHANGE'; $matchedLine = $line
    }
}

switch ($uploadStatus) {
    'UPLOADED' {
        Write-Host "  OK -- new content pushed to Workshop." -ForegroundColor Green
        Write-Host "    $matchedLine"
    }
    'NOCHANGE' {
        # Acceptable ONLY because step 4 already proved the deploy hashes match the
        # server bundle (step 4 hard-fails otherwise, so we can't reach here stale).
        if (-not $deployOk) {
            Fail "workshop_log shows 'No content change' but deploy hashes did NOT match -- bundle is stale/divergent."
        }
        Write-Host "  OK -- server already had this exact bundle (no-op upload; deploy hashes matched)." -ForegroundColor Green
        Write-Host "    $matchedLine"
    }
    default {
        Fail "No fresh (<5 min) workshop_log line for item $publishedId. Upload may not have transferred -- inspect $workshopLog."
    }
}

# ---------------------------------------------------------------------------
# Step 6: STATUS-LABEL the shipped issues (issue #326 mechanization)
# ---------------------------------------------------------------------------
# Doctrine (PROJECT_STANDARDS section 11): when a fix or probe ships, the
# matching status label (not-started / verify-fix / diagnostics-armed) goes on the issue in
# the SAME pass. This step mechanizes it: harvest every #N referenced in the
# CHANGELOG entry just shipped and add the label via gh. Heuristics, printed
# per issue so the user can correct a misjudgment by hand:
#   * Dev-stream ships only (-dev/-alpha/-beta/-rc suffix). A clean stable
#     promotion re-ships work that was labeled when its dev build shipped.
#   * Loc-sweep entries (header matches the localization-doctrine pattern) are
#     skipped: their #N refs are tag CONTEXT, not shipped work (same heuristic
#     as qa/check_issue_status_labels.ps1).
#   * [docs]/[tooling] entries never mutate tracker labels.
#   * Label choice is ENTRY-level and explicit: exactly one of [not-started],
#     [verify-fix], or [diagnostics-armed]/[diag]. Prose never supplies a
#     default, and missing/mixed intent fails closed. Co-op routing is derived
#     from the validated CURRENT LIVE TEST card.
#     A MIXED entry (fix for one issue, probe for
#     another) gets one label for all refs -- correct the odd one out by hand.
#   * CLOSED and non-existent numbers are skipped (footnote "#2"-style false
#     positives resolve to nothing).
# This step NEVER fails the ship -- the upload already succeeded. Any labeling
# problem is a yellow warning for manual follow-up.
Write-Host ""
Write-Host "==> Status-labeling shipped issues (PROJECT_STANDARDS section 11 / issue #326)" -ForegroundColor Cyan
$labelSummary = @()
try {
    $ghRepo = 'Ensrick/vermintide-2-tweaker'
    if ($modVersion -eq '(unknown)') {
        Write-Host "  WARNING: MOD_VERSION unknown -- cannot tell dev from stable; label the shipped issues by hand." -ForegroundColor Yellow
        $labelSummary += 'SKIPPED (version unknown) -- label by hand'
    }
    elseif (-not (Test-DevStreamVersion $modVersion)) {
        Write-Host "  clean-version (stable) ship -- skipping: labels were applied when the dev build shipped." -ForegroundColor DarkGray
        $labelSummary += 'skipped (stable promotion)'
    }
    else {
        $ghReady = $false
        if (Get-Command gh -ErrorAction SilentlyContinue) {
            # Probe guard (issue #489): an unauthenticated gh writes to stderr,
            # which under redirection + EAP=Stop threw on PS 5.1 and skipped
            # labeling with a misleading "gh unavailable" warning.
            $ghReady = ((Invoke-NativeProbe { gh auth status }) -eq 0)
        }
        $clPath = Join-Path $modDir 'CHANGELOG.md'
        if (-not $ghReady) {
            Write-Host "  WARNING: gh not installed/authenticated -- label the shipped issues by hand (verify-fix / diagnostics-armed)." -ForegroundColor Yellow
            $labelSummary += 'SKIPPED (gh unavailable) -- label by hand'
        }
        elseif (-not (Test-Path $clPath)) {
            Write-Host "  WARNING: no CHANGELOG.md at $clPath -- nothing to parse; label by hand if this ship fixed an issue." -ForegroundColor Yellow
            $labelSummary += 'SKIPPED (no CHANGELOG.md)'
        }
        else {
            # Top `## ` entry = the entry being shipped (CHANGELOGs are newest-first).
            $clLines = [System.IO.File]::ReadAllText($clPath, [System.Text.Encoding]::UTF8) -split "`r?`n"
            $top = Get-TopChangelogEntry -Lines $clLines
            if (-not $top) {
                Write-Host "  WARNING: no '## ' entry in CHANGELOG.md -- nothing to label." -ForegroundColor Yellow
                $labelSummary += 'SKIPPED (no CHANGELOG entry)'
            }
            else {
                $clHeader = $top.Header
                $plan = Get-ShipLabelPlan -Header $top.Header -Entry $top.Entry
                if ($plan.Skip) {
                    $reason = switch ($plan.Skip) {
                        'loc-sweep' { 'its refs are tag context, not shipped work' }
                        'no-refs' { 'the entry has no issue references' }
                        'missing-lifecycle-marker' { 'the header must name exactly one of [not-started], [verify-fix], or [diagnostics-armed]/[diag]' }
                        'ambiguous-lifecycle-marker' { 'the header names more than one lifecycle' }
                        'retired-lifecycle-marker' { '[verify-fix-coop] is retired; use [verify-fix] and a co-op CURRENT LIVE TEST card' }
                        'tooling-entry' { 'tooling/docs issues are verified autonomously and never enter the in-game queue' }
                        default { 'unknown label-plan rejection' }
                    }
                    $color = if ($plan.Skip -in @('loc-sweep', 'no-refs')) { 'DarkGray' } else { 'Yellow' }
                    Write-Host "  $($plan.Skip) entry ($clHeader) -- $reason; no issue labels mutated." -ForegroundColor $color
                    $labelSummary += "skipped ($($plan.Skip) entry)"
                }
                else {
                    $statusLabel = $plan.Label
                    $issueRefs = $plan.Refs
                    if ($issueRefs.Count -gt 0) {
                        Write-Host "  entry : $clHeader"
                        Write-Host "  label : $statusLabel (entry-level intent -- correct by hand if the entry is mixed fix+diag)"
                        foreach ($n in $issueRefs) {
                            $json = & gh issue view $n --repo $ghRepo --json state,labels,body,comments,url 2>$null
                            $meta = $null
                            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($json)) {
                                try { $meta = $json | ConvertFrom-Json } catch { $meta = $null }
                            }
                            if (-not $meta) {
                                Write-Host ("  - #{0}: not an issue (footnote / PR / typo) -- skipped" -f $n) -ForegroundColor DarkGray
                                continue
                            }
                            if ($meta.state -ne 'OPEN') {
                                Write-Host ("  - #{0}: {1} -- skipped" -f $n, $meta.state) -ForegroundColor DarkGray
                                continue
                            }
                            $existing = @()
                            if ($meta.labels) { $existing = @($meta.labels | ForEach-Object { $_.name }) }
                            $decision = Get-ShipIssueTransitionDecision -Existing $existing -Requested $statusLabel -CoopRequired ([bool]$plan.CoopRequired) -RepositoryLabels @($plan.RepositoryLabels) -Comments $meta.comments -Body ([string]$meta.body)
                            if (-not $decision.Ok) {
                                $reasonText = switch ($decision.Reason) {
                                    'invalid-current-live-test-card' { 'newest exact CURRENT LIVE TEST card is missing or invalid' }
                                    'unevidenced-verify-downgrade' { 'verify-to-diagnostics downgrade lacks failed-verification evidence in the selected replacement method' }
                                    'tooling-issue-not-auto-labeled' { 'tooling/docs work never receives live-test labels from ship automation' }
                                    'blocked-issue-not-ready' { 'blocked issues must remain not-started and outside the live-test queue' }
                                    default { "transition policy rejected '$($decision.Reason)'" }
                                }
                                Write-Host ("  ! #{0}: {1}; no labels mutated" -f $n, $reasonText) -ForegroundColor Yellow
                                $labelSummary += ("#{0} BLOCKED {1}" -f $n, $decision.Reason)
                                continue
                            }

                            $selection = $decision.Selection
                            $edit = $decision.Edit
                            $isRepositoryOnly = $decision.IsRepositoryOnly
                            $removeLabels = @($edit.Remove)
                            # The validated card is authoritative. A non-ready target strips
                            # stale coop-required; a co-op ready card adds it only after the
                            # card records solo as passed/exhausted.
                            $coopEdit = $decision.CoopEdit
                            $wantCoopQualifier = $coopEdit.Want
                            if ($coopEdit.Remove) { $removeLabels += 'coop-required' }
                            $editArgs = @()
                            if ($edit.Add) { $editArgs += @('--add-label', $edit.Target) }
                            if ($coopEdit.Add) { $editArgs += @('--add-label', 'coop-required') }
                            foreach ($labelToRemove in ($removeLabels | Select-Object -Unique)) { $editArgs += @('--remove-label', $labelToRemove) }
                            $editOk = $true
                            if ($editArgs.Count -gt 0) {
                                if ($coopEdit.Add) {
                                    & gh label create 'coop-required' --repo $ghRepo --color 'D93F0B' --description 'Testing or diagnostics requires 2+ players' --force 2>$null | Out-Null
                                    if ($LASTEXITCODE -ne 0) { $editOk = $false }
                                }
                                if ($editOk) {
                                    $transitionEvidence = "Lifecycle transition evidence: shipped entry '$clHeader' validated the newest exact CURRENT LIVE TEST card; target lifecycle '$($edit.Target)'."
                                    & gh issue comment $n --repo $ghRepo --body $transitionEvidence 2>$null | Out-Null
                                    $editOk = ($LASTEXITCODE -eq 0)
                                }
                                if ($editOk) {
                                    & gh issue edit $n --repo $ghRepo @editArgs 2>$null | Out-Null
                                    $editOk = ($LASTEXITCODE -eq 0)
                                }
                            }
                            if ($editOk) {
                                $qualifierText = if ($wantCoopQualifier) { " + 'coop-required'" } else { '' }
                                Write-Host ("  + #{0}: lifecycle '{1}'{2}; competing lifecycle labels removed" -f $n, $edit.Target, $qualifierText) -ForegroundColor Green
                                $methodSummary = if ($isRepositoryOnly) { 'autonomous method validated' } else { 'runtime method validated' }
                                $labelSummary += ("#{0} ->{1}{2} ({3})" -f $n, $edit.Target, $(if ($wantCoopQualifier) { '+coop-required' } else { '' }), $methodSummary)
                            } else {
                                Write-Host ("  ! #{0}: lifecycle evidence comment or issue edit failed; inspect before retry" -f $n) -ForegroundColor Yellow
                                $labelSummary += ("#{0} FAILED lifecycle transition" -f $n)
                            }
                        }
                    }
                }
            }
        }
    }
}
catch {
    Write-Host "  WARNING: status-labeling step errored ($($_.Exception.Message)) -- label the shipped issues by hand." -ForegroundColor Yellow
    $labelSummary += 'ERRORED -- label by hand'
}

# ---------------------------------------------------------------------------
# Step 7: success summary
# ---------------------------------------------------------------------------
$uploadHuman = if ($uploadStatus -eq 'UPLOADED') { 'Uploaded new content' } else { 'No content change (server up to date)' }
Write-Host ""
Write-Host "==================== SHIP SUCCESS ====================" -ForegroundColor Green
Write-Host ("  Mod          : {0}" -f $Mod)
Write-Host ("  Version      : v{0}" -f $modVersion)
Write-Host ("  Published ID : {0}" -f $publishedId)
Write-Host ("  Deploy hash  : OK ({0} file(s) verified; {1} normalized descriptor(s))" -f $checked, $normalizedDescriptors)
Write-Host ("  Upload       : {0}" -f $uploadHuman)
Write-Host ("  GitHub       : {0}" -f $githubStatus)
$labelsHuman = if ($labelSummary.Count -gt 0) { $labelSummary -join '; ' } else { 'none' }
Write-Host ("  Labels       : {0}" -f $labelsHuman)
Write-Host "======================================================" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 8: test refresh + loaded-version reminder
# ---------------------------------------------------------------------------
$bar = ('=' * 72)
Write-Host ""
Write-Host $bar -ForegroundColor Yellow
Write-Host "  TEST BUILD READY" -ForegroundColor Yellow
Write-Host $bar -ForegroundColor Yellow
Write-Host "  Author/PC-A: test the hash-verified local deploy; no Steam restart" -ForegroundColor Yellow
Write-Host "  is required. Volunteer testers: unsubscribe/resubscribe through" -ForegroundColor Yellow
Write-Host "  the dev collection to refresh the Workshop build." -ForegroundColor Yellow
Write-Host "" -ForegroundColor Yellow
Write-Host "    Confirm the running build via the NEWEST log under" -ForegroundColor Yellow
Write-Host "       %APPDATA%\Fatshark\Vermintide 2\console_logs\" -ForegroundColor Yellow
Write-Host ("    look for:  [{0}:LOAD] v{1}" -f $loadTag, $modVersion) -ForegroundColor Yellow
Write-Host $bar -ForegroundColor Yellow

# ---------------------------------------------------------------------------
# Release the ship/version claim: the upload + deploy verified, so v$modVersion
# is spent and the mod is free for the next session to claim (tools/ship/CLAIMS.md).
# ---------------------------------------------------------------------------
if (-not $NoClaim) {
    $claimScript = Join-Path $PSScriptRoot 'claim.ps1'
    if (Test-Path -LiteralPath $claimScript) {
        & $claimScript -Mod $Mod -Release -Quiet
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host ("  Ship claim for {0} released." -f $Mod) -ForegroundColor DarkGray
        }
        else {
            Write-Host ""
            Write-Host ("  NOTE: could not auto-release the ship claim for {0}. A foreign owner is never removed; inspect it with .\tools\ship\claim.ps1 -Mod {0}." -f $Mod) -ForegroundColor Yellow
        }
    }
}

exit 0
