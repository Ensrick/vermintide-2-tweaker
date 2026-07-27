# tools/ship/claim.ps1
#
# SHIP / VERSION CLAIM BROKER -- atomic mutual exclusion for a mod's next build.
# Full rationale, usage, and stale policy: tools/ship/CLAIMS.md.
#
# THE PROBLEM IT KILLS: parallel Claude sessions on this machine repeatedly
# allocated the SAME next MOD_VERSION and uploaded competing bundles, forcing
# "reconciliation builds" (documented incidents: cosmetics 0.9.143 + 0.9.145,
# wt 0.12.273-beta, wt_dev 0.12.274-dev).
#
# WHAT IT DOES:
#   claim.ps1 -Mod <name>        atomically claims the mod AND allocates the next
#                                patch version (current MOD_VERSION, patch+1,
#                                preserving the -dev/-beta/-alpha/-rc suffix).
#   claim.ps1 -Mod <name> -Release   frees the claim.
#   claim.ps1 -Mod <name> -Verify -ExpectedVersion <v>   ship.ps1 gate hook.
#   claim.ps1 -SelfTest          offline contention/stale/allocate/release tests.
#
# THE LOCK: an atomic exclusive file create at
# %APPDATA%\VMBLauncher\ship_claims\<mod>.claim. This is the same machine-global
# authority VMBLauncher consults, so separate worktrees and nested launchers see
# one lock. The OS CREATE_NEW disposition guarantees exactly one racer's create
# succeeds; every other gets IOException.
#
# STALE POLICY: a claim older than -StaleHours (default 24h) is stale and may be
# broken by a new claimant (reported when it happens). Guards against a crashed
# session wedging a mod forever.
#
# Exit codes:
#   default (claim):  0 acquired / already-held-by-you   1 contention   2 error
#   -Release:         0 released (or nothing to release)  1 owner mismatch/could-not-remove
#   -Verify:          0 live+owner+version match   3 absent   4 version mismatch
#                     5 stale   6 owner mismatch   2 usage
#   -SelfTest:        0 all pass     2 regression
#
# ASCII only -- PowerShell parses .ps1 as Windows-1252 by default; never use
# em-dashes or box-drawing glyphs (same rule as ship.ps1).

[CmdletBinding()]
param(
    [string]$Mod,
    [switch]$Release,
    [switch]$Verify,
    [string]$ExpectedVersion,
    [switch]$SelfTest,
    [string]$RepoRoot,
    [string]$ClaimsDir,
    [string]$Session,
    [double]$StaleHours = 24,
    [switch]$Quiet,
    [switch]$ConditionalDeleteRaceWorker,
    [string]$RaceClaimPath,
    [string]$RaceReadyPath,
    [string]$RaceContinuePath
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Pure helpers, hoisted so -SelfTest exercises the SAME code the live broker
# runs. No side effects; every filesystem action lives in the operation
# functions below.
# ---------------------------------------------------------------------------

# Next patch version: MAJOR.MINOR.(PATCH+1), suffix preserved. Rejects anything
# that is not canonical 3-segment semver so a stale 4-segment version (e.g.
# 0.9.9.4-dev) is surfaced for normalization instead of silently mis-incremented
# (CLAUDE.md "Format: 3-segment semver only").
function Get-NextPatchVersion {
    param([string]$Version)
    if ($Version -notmatch '^(\d+)\.(\d+)\.(\d+)(-[A-Za-z]+)?$') {
        throw "MOD_VERSION '$Version' is not canonical 3-segment semver (MAJOR.MINOR.PATCH[-track]). Normalize it before claiming (CLAUDE.md 'Format: 3-segment semver only')."
    }
    $major = [int]$matches[1]
    $minor = [int]$matches[2]
    $patch = [int]$matches[3]
    $suffix = $matches[4]   # $null when absent -> renders empty in the string below
    return "$major.$minor.$($patch + 1)$suffix"
}

# Read MOD_VERSION from the mod's main lua, exactly as ship.ps1 Step 1 does. The
# lua lives at <mod>\scripts\mods\<mod>\<mod>.lua using the DIRECTORY name.
function Get-ClaimModVersion {
    param([string]$RepoRoot, [string]$Mod)
    $luaPath = Join-Path $RepoRoot (Join-Path $Mod "scripts\mods\$Mod\$Mod.lua")
    if (-not (Test-Path -LiteralPath $luaPath)) {
        throw "Mod source not found: $luaPath (is '$Mod' a valid mod directory name?)"
    }
    $txt = [System.IO.File]::ReadAllText($luaPath, [System.Text.Encoding]::UTF8)
    if ($txt -match 'MOD_VERSION\s*=\s*"([^"]+)"') { return $matches[1] }
    throw "No MOD_VERSION found in $luaPath."
}

function Get-MachineClaimsDir {
    param([string]$AppDataRoot)
    if ([string]::IsNullOrWhiteSpace($AppDataRoot)) {
        $AppDataRoot = $env:APPDATA
    }
    if ([string]::IsNullOrWhiteSpace($AppDataRoot)) {
        $AppDataRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
    }
    if ([string]::IsNullOrWhiteSpace($AppDataRoot)) {
        throw 'Cannot locate the roaming AppData directory for the machine-global ship claim authority.'
    }
    return [System.IO.Path]::Combine($AppDataRoot, 'VMBLauncher', 'ship_claims')
}

function Get-ClaimSessionId {
    param([string]$RepoRoot)

    # Prefer orchestrator identities that survive child PowerShell processes.
    # This is the owner credential consumed by verify/release, not decoration:
    # another Claude/Codex task must not be able to spend a same-version claim.
    if ($env:VT2_SHIP_SESSION_ID) { return "explicit:$($env:VT2_SHIP_SESSION_ID)" }
    if ($env:CLAUDE_SESSION_ID)   { return "claude:$($env:CLAUDE_SESSION_ID)" }
    if ($env:CODEX_THREAD_ID)     { return "codex:$($env:CODEX_THREAD_ID)" }

    # Manual shells do not have an orchestrator id. Use a deterministic
    # worktree identity so claim -> ship -> release works across child
    # processes, while a different clean worktree cannot consume the claim.
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        throw 'Cannot derive claim owner without RepoRoot.'
    }
    $normalized = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/').ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
        $digest = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }
    $hex = [System.BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant()
    return "worktree:$($hex.Substring(0, 16))"
}

function ConvertTo-ClaimTimestamp {
    param([datetime]$Utc)
    return $Utc.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertFrom-ClaimTimestamp {
    param([string]$Text)
    $dto = [datetimeoffset]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if ([datetimeoffset]::TryParse($Text, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dto)) {
        return $dto.UtcDateTime
    }
    return $null
}

function Test-ClaimStale {
    param([datetime]$CreatedUtc, [datetime]$NowUtc, [double]$StaleHours = 24)
    return [bool]((($NowUtc - $CreatedUtc).TotalHours) -ge $StaleHours)
}

function Format-ClaimContent {
    param([string]$Mod, [string]$Version, [string]$Session, [datetime]$CreatedUtc)
    return @(
        '# VT2 ship/version claim -- see tools/ship/CLAIMS.md',
        "mod = $Mod",
        "version = $Version",
        "session = $Session",
        "created = $(ConvertTo-ClaimTimestamp $CreatedUtc)"
    ) -join "`n"
}

# Parse a claim file into an object, or $null if missing / empty (mid-write) /
# corrupt / missing a required key. Readers treat $null as "not a valid live
# claim" and either back off (mid-write window) or break it (persistently bad).
function Read-ClaimFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = ''
    try { $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) } catch { return $null }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $map = @{}
    foreach ($line in ($raw -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $eq = $t.IndexOf('=')
        if ($eq -lt 1) { continue }
        $map[$t.Substring(0, $eq).Trim()] = $t.Substring($eq + 1).Trim()
    }
    foreach ($required in @('mod', 'version', 'session', 'created')) {
        if (-not $map.ContainsKey($required)) { return $null }
    }
    $created = ConvertFrom-ClaimTimestamp $map['created']
    if ($null -eq $created) { return $null }
    return [pscustomobject]@{
        Mod        = $map['mod']
        Version    = $map['version']
        Session    = $map['session']
        CreatedUtc = $created
        Raw        = $raw
    }
}

function Get-ClaimMutationMutexName {
    param([string]$Path)
    $normalized = [System.IO.Path]::GetFullPath($Path).ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $digest = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalized)) }
    finally { $sha.Dispose() }
    $hex = [System.BitConverter]::ToString($digest).Replace('-', '')
    return "Local\VT2ShipClaimMutation_$hex"
}

function Invoke-WithClaimMutationLock {
    param([string]$Path, [scriptblock]$Action, [int]$TimeoutMilliseconds = 10000)
    $mutex = New-Object System.Threading.Mutex($false, (Get-ClaimMutationMutexName $Path))
    $held = $false
    try {
        try { $held = $mutex.WaitOne($TimeoutMilliseconds) }
        catch [System.Threading.AbandonedMutexException] { $held = $true }
        if (-not $held) { throw "Timed out waiting for claim mutation lock: $Path" }
        return & $Action
    }
    finally {
        if ($held) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

# Delete only the exact bytes previously observed. Every broker create/replacement
# uses the same per-claim OS mutex, so a newer owner's claim cannot appear between
# this comparison and deletion.
function Remove-ClaimIfUnchanged {
    param([string]$Path, [string]$ExpectedRaw)
    return Invoke-WithClaimMutationLock -Path $Path -Action {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return [pscustomobject]@{ Deleted = $false; Changed = $true }
        }
        try { $currentRaw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) }
        catch { return [pscustomobject]@{ Deleted = $false; Changed = $true } }
        if (-not [string]::Equals($currentRaw, $ExpectedRaw, [System.StringComparison]::Ordinal)) {
            return [pscustomobject]@{ Deleted = $false; Changed = $true }
        }
        Remove-Item -LiteralPath $Path -Force
        return [pscustomobject]@{ Deleted = $true; Changed = $false }
    }
}

function Invoke-ClaimCreate {
    param([string]$Path, [string]$Mod, [string]$RepoRoot, [string]$Session, [datetime]$NowUtc)
    return Invoke-WithClaimMutationLock -Path $Path -Action {
        $stream = $null
        try {
            $stream = [System.IO.File]::Open(
                $Path,
                [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None)
        }
        catch [System.IO.IOException] {
            return [pscustomobject]@{ Created = $false; Version = $null }
        }

        $wrote = $false
        try {
            $version = Get-NextPatchVersion (Get-ClaimModVersion -RepoRoot $RepoRoot -Mod $Mod)
            $content = Format-ClaimContent -Mod $Mod -Version $version -Session $Session -CreatedUtc $NowUtc
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()
            $wrote = $true
            return [pscustomobject]@{ Created = $true; Version = $version }
        }
        finally {
            $stream.Dispose()
            if (-not $wrote) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
        }
    }
}

# ---------------------------------------------------------------------------
# Operation functions (filesystem side effects live here).
# ---------------------------------------------------------------------------

# Atomically acquire the claim for $Mod and allocate its next version. The
# CREATE_NEW open is the lock. A retry loop absorbs a lost stale-break race and a
# mid-write read window; persistent contention returns Ok=$false.
function Invoke-ClaimAcquire {
    param(
        [string]$ClaimsDir,
        [string]$Mod,
        [string]$RepoRoot,
        [string]$Session,
        [datetime]$NowUtc,
        [double]$StaleHours = 24,
        [int]$MaxAttempts = 6
    )
    if (-not (Test-Path -LiteralPath $ClaimsDir)) {
        New-Item -ItemType Directory -Path $ClaimsDir -Force | Out-Null
    }
    $claimPath = Join-Path $ClaimsDir "$Mod.claim"
    $brokeStale = $false

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $create = Invoke-ClaimCreate -Path $claimPath -Mod $Mod -RepoRoot $RepoRoot -Session $Session -NowUtc $NowUtc
        if ($create.Created) {
            return [pscustomobject]@{
                Ok = $true; Acquired = $true; Version = $create.Version
                ClaimPath = $claimPath; BrokeStale = $brokeStale; Held = $null
                Message = 'claimed'
            }
        }

        $rawReadable = $false
        $observedRaw = $null
        try {
            $observedRaw = [System.IO.File]::ReadAllText($claimPath, [System.Text.Encoding]::UTF8)
            $rawReadable = $true
        }
        catch { }
        $existing = Read-ClaimFile $claimPath
        if ($null -eq $existing) {
            # Empty/partial (a racer created but has not written yet) or corrupt.
            Start-Sleep -Milliseconds (40 * $attempt)
            if ($attempt -ge 3 -and $rawReadable) {
                $deleted = Remove-ClaimIfUnchanged -Path $claimPath -ExpectedRaw $observedRaw
                if ($deleted.Deleted) { $brokeStale = $true }
            }
            continue
        }
        if ($existing.Session -eq $Session -and -not (Test-ClaimStale $existing.CreatedUtc $NowUtc $StaleHours)) {
            return [pscustomobject]@{
                Ok = $true; Acquired = $false; Version = $existing.Version
                ClaimPath = $claimPath; BrokeStale = $false; Held = $existing
                Message = 'already held by this session'
            }
        }
        if (Test-ClaimStale $existing.CreatedUtc $NowUtc $StaleHours) {
            $deleted = Remove-ClaimIfUnchanged -Path $claimPath -ExpectedRaw $existing.Raw
            if ($deleted.Deleted) { $brokeStale = $true }
            continue
        }
        return [pscustomobject]@{
            Ok = $false; Acquired = $false; Version = $existing.Version
            ClaimPath = $claimPath; BrokeStale = $false; Held = $existing
            Message = 'held by another session'
        }
    }

    return [pscustomobject]@{
        Ok = $false; Acquired = $false; Version = $null
        ClaimPath = $claimPath; BrokeStale = $brokeStale; Held = (Read-ClaimFile $claimPath)
        Message = "could not acquire after $MaxAttempts attempts (persistent contention)"
    }
}

# Free the claim only for its exact owner. A foreign release must fail closed;
# otherwise another session can erase a live claim and race its upload.
function Invoke-ClaimRelease {
    param([string]$ClaimsDir, [string]$Mod, [string]$Session)
    $claimPath = Join-Path $ClaimsDir "$Mod.claim"
    if (-not (Test-Path -LiteralPath $claimPath)) {
        return [pscustomobject]@{ Ok = $true; Removed = $false; CrossSession = $false; Message = 'no claim to release'; Held = $null }
    }
    $existing = Read-ClaimFile $claimPath
    if ($null -eq $existing) {
        return [pscustomobject]@{ Ok = $false; Removed = $false; CrossSession = $false; Message = 'claim file is unreadable; wait for stale recovery or inspect it manually'; Held = $null }
    }
    $cross = [bool]($Session -and $existing.Session -ne $Session)
    if ($cross) {
        return [pscustomobject]@{
            Ok = $false; Removed = $false; CrossSession = $true
            Message = "claim belongs to session '$($existing.Session)', not '$Session'"
            Held = $existing
        }
    }
    $delete = Remove-ClaimIfUnchanged -Path $claimPath -ExpectedRaw $existing.Raw
    $removed = [bool]$delete.Deleted
    return [pscustomobject]@{
        Ok = $removed; Removed = $removed; CrossSession = $cross
        Message = $(if ($removed) { 'released' } else { "claim changed after ownership check; not removed" })
        Held = $existing
    }
}

# Read-only verification used by ship.ps1: is there a live, non-stale claim whose
# recorded version equals the source MOD_VERSION about to ship and whose owner
# equals the current orchestrator/worktree session?
function Test-ShipClaimState {
    param([string]$ClaimsDir, [string]$Mod, [string]$ExpectedVersion, [string]$ExpectedSession, [datetime]$NowUtc, [double]$StaleHours = 24)
    $claimPath = Join-Path $ClaimsDir "$Mod.claim"
    $existing = Read-ClaimFile $claimPath
    if ($null -eq $existing) { return @{ State = 'absent'; Claim = $null } }
    if (Test-ClaimStale $existing.CreatedUtc $NowUtc $StaleHours) { return @{ State = 'stale'; Claim = $existing } }
    if ($existing.Version -ne $ExpectedVersion) { return @{ State = 'mismatch'; Claim = $existing } }
    if ([string]::IsNullOrWhiteSpace($ExpectedSession) -or $existing.Session -ne $ExpectedSession) { return @{ State = 'owner_mismatch'; Claim = $existing } }
    return @{ State = 'ok'; Claim = $existing }
}

function Invoke-ConditionalDeleteRaceWorker {
    if (-not $RaceClaimPath -or -not $RaceReadyPath -or -not $RaceContinuePath) { return 2 }
    try { $observedRaw = [System.IO.File]::ReadAllText($RaceClaimPath, [System.Text.Encoding]::UTF8) }
    catch { return 3 }
    [System.IO.File]::WriteAllText($RaceReadyPath, 'ready', (New-Object System.Text.UTF8Encoding($false)))
    $deadline = (Get-Date).AddSeconds(15)
    while (-not (Test-Path -LiteralPath $RaceContinuePath) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 20
    }
    if (-not (Test-Path -LiteralPath $RaceContinuePath)) { return 4 }
    $delete = Remove-ClaimIfUnchanged -Path $RaceClaimPath -ExpectedRaw $observedRaw
    return $(if ($delete.Deleted) { 5 } else { 0 })
}

# ---------------------------------------------------------------------------
# Self-test (offline; exit 0 = OK, exit 2 = regression -- qa runner convention).
# Covers: atomic contention (two racing PROCESSES), stale-break, idempotent
# re-claim, allocate-increment, release, and the ship.ps1 verify contract.
# ---------------------------------------------------------------------------
function Invoke-ClaimSelfTest {
    $script:__ctpass = $true
    function Assert($cond, $desc) {
        $verdict = if ($cond) { 'PASS' } else { 'FAIL' }
        $colour = if ($cond) { 'Green' } else { 'Red' }
        Write-Host ("  [{0}] {1}" -f $verdict, $desc) -ForegroundColor $colour
        if (-not $cond) { $script:__ctpass = $false }
    }

    Write-Host "=== claim.ps1 -SelfTest ===" -ForegroundColor Cyan
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $nowRef = (Get-Date).ToUniversalTime()

    # --- pure allocate-increment ---
    Assert ((Get-NextPatchVersion '0.12.273-beta') -eq '0.12.274-beta') "patch increment preserves -beta (0.12.273-beta -> 0.12.274-beta)"
    Assert ((Get-NextPatchVersion '0.7.9-dev') -eq '0.7.10-dev') "patch increment preserves -dev, no rollover (0.7.9 -> 0.7.10)"
    Assert ((Get-NextPatchVersion '1.0.0') -eq '1.0.1') "clean stable version increments patch (1.0.0 -> 1.0.1)"
    Assert ((Get-NextPatchVersion '0.1.329-dev') -eq '0.1.330-dev') "large patch increments fine (0.1.329 -> 0.1.330)"
    $threw = $false; try { Get-NextPatchVersion '0.9.9.4-dev' | Out-Null } catch { $threw = $true }
    Assert $threw "4-segment version is rejected (must normalize first)"
    $threw2 = $false; try { Get-NextPatchVersion 'garbage' | Out-Null } catch { $threw2 = $true }
    Assert $threw2 "non-semver is rejected"

    # --- timestamp round-trip + staleness ---
    $rt = ConvertFrom-ClaimTimestamp (ConvertTo-ClaimTimestamp $nowRef)
    Assert ($null -ne $rt -and [math]::Abs(($rt - $nowRef).TotalSeconds) -lt 1.5) "ISO timestamp round-trips through UTC"
    Assert (Test-ClaimStale $nowRef.AddHours(-25) $nowRef 24) "25h-old claim is stale at 24h threshold"
    Assert (-not (Test-ClaimStale $nowRef.AddHours(-3) $nowRef 24)) "3h-old claim survives a normal PR/hosted-QA cycle"

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-claim-" + [guid]::NewGuid().ToString('N'))
    $fixRepo = Join-Path $tmp 'repo'
    $fixRepoB = Join-Path $tmp 'repo-b'
    $fixMod = 'fixturemod'
    $luaDir = Join-Path $fixRepo (Join-Path $fixMod "scripts\mods\$fixMod")
    $luaDirB = Join-Path $fixRepoB (Join-Path $fixMod "scripts\mods\$fixMod")
    [System.IO.Directory]::CreateDirectory($luaDir) | Out-Null
    [System.IO.Directory]::CreateDirectory($luaDirB) | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $luaDir "$fixMod.lua"), "local MOD_VERSION = `"0.1.5-dev`"`n", $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $luaDirB "$fixMod.lua"), "local MOD_VERSION = `"0.1.5-dev`"`n", $utf8NoBom)

    try {
        # --- one machine-global namespace, including nested launchers ---
        $fixtureAppData = Join-Path $tmp 'appdata'
        $machineDir = Get-MachineClaimsDir -AppDataRoot $fixtureAppData
        $expectedMachineDir = Join-Path $fixtureAppData 'VMBLauncher\ship_claims'
        Assert ($machineDir -eq $expectedMachineDir) "default authority is the VMBLauncher machine-global claims directory"
        Assert ($machineDir -ne (Join-Path $fixRepo '.ship_claims')) "default authority is not scoped to a source worktree"
        $outer = Invoke-ClaimAcquire -ClaimsDir $machineDir -Mod $fixMod -RepoRoot $fixRepo -Session 'nested-owner' -NowUtc $nowRef
        $nestedState = Test-ShipClaimState -ClaimsDir (Get-MachineClaimsDir -AppDataRoot $fixtureAppData) -Mod $fixMod -ExpectedVersion $outer.Version -ExpectedSession 'nested-owner' -NowUtc $nowRef
        Assert ($outer.Ok -and $nestedState.State -eq 'ok') "nested launcher resolves and verifies the outer machine-global claim"
        $outerRelease = Invoke-ClaimRelease -ClaimsDir $machineDir -Mod $fixMod -Session 'nested-owner'
        Assert ($outerRelease.Ok -and $outerRelease.Removed) "nested-authority fixture releases cleanly"

        # --- stable owner identity across child processes/worktrees ---
        $savedExplicit = $env:VT2_SHIP_SESSION_ID
        $savedClaude = $env:CLAUDE_SESSION_ID
        $savedCodex = $env:CODEX_THREAD_ID
        try {
            $env:VT2_SHIP_SESSION_ID = $null
            $env:CLAUDE_SESSION_ID = $null
            $env:CODEX_THREAD_ID = $null
            $ownerA1 = Get-ClaimSessionId -RepoRoot $fixRepo
            $ownerA2 = Get-ClaimSessionId -RepoRoot $fixRepo
            $ownerB = Get-ClaimSessionId -RepoRoot $fixRepoB
            Assert ($ownerA1 -eq $ownerA2 -and $ownerA1 -match '^worktree:[0-9a-f]{16}$') "manual owner is stable for one worktree"
            Assert ($ownerA1 -ne $ownerB) "different worktrees derive different owners"
            $env:CODEX_THREAD_ID = 'thread-fixture'
            Assert ((Get-ClaimSessionId -RepoRoot $fixRepo) -eq 'codex:thread-fixture') "Codex thread identity outranks worktree fallback"
            $env:CLAUDE_SESSION_ID = 'claude-fixture'
            Assert ((Get-ClaimSessionId -RepoRoot $fixRepo) -eq 'claude:claude-fixture') "Claude identity outranks Codex identity"
            $env:VT2_SHIP_SESSION_ID = 'explicit-fixture'
            Assert ((Get-ClaimSessionId -RepoRoot $fixRepo) -eq 'explicit:explicit-fixture') "explicit ship identity has highest priority"
        }
        finally {
            $env:VT2_SHIP_SESSION_ID = $savedExplicit
            $env:CLAUDE_SESSION_ID = $savedClaude
            $env:CODEX_THREAD_ID = $savedCodex
        }

        # --- allocate from fixture source ---
        $allocDir = Join-Path $tmp 'alloc'
        $a = Invoke-ClaimAcquire -ClaimsDir $allocDir -Mod $fixMod -RepoRoot $fixRepo -Session 'sess-alloc' -NowUtc $nowRef
        Assert ($a.Ok -and $a.Acquired) "acquire from clean state succeeds"
        Assert ($a.Version -eq '0.1.6-dev') "allocated version = source patch+1 (0.1.5-dev -> 0.1.6-dev)"
        Assert (Test-Path -LiteralPath $a.ClaimPath) "claim file written"

        # --- idempotent re-claim vs contention ---
        $idemDir = Join-Path $tmp 'idem'
        $first = Invoke-ClaimAcquire -ClaimsDir $idemDir -Mod $fixMod -RepoRoot $fixRepo -Session 'sess-x' -NowUtc $nowRef
        Assert ($first.Ok -and $first.Acquired) "first claim acquires"
        $again = Invoke-ClaimAcquire -ClaimsDir $idemDir -Mod $fixMod -RepoRoot $fixRepo -Session 'sess-x' -NowUtc $nowRef
        Assert ($again.Ok -and -not $again.Acquired) "same-session re-claim is idempotent (no re-allocation)"
        Assert ($again.Version -eq $first.Version) "idempotent re-claim returns the same version"
        $other = Invoke-ClaimAcquire -ClaimsDir $idemDir -Mod $fixMod -RepoRoot $fixRepo -Session 'sess-y' -NowUtc $nowRef
        Assert (-not $other.Ok) "different live session is refused (contention)"
        Assert ($other.Held -and $other.Held.Session -eq 'sess-x') "contention names the holding session"

        # --- stale break ---
        $staleDir = Join-Path $tmp 'stale'
        [System.IO.Directory]::CreateDirectory($staleDir) | Out-Null
        [System.IO.File]::WriteAllText(
            (Join-Path $staleDir "$fixMod.claim"),
            (Format-ClaimContent -Mod $fixMod -Version '0.9.9-dev' -Session 'old-session' -CreatedUtc $nowRef.AddHours(-25)),
            $utf8NoBom)
        $broke = Invoke-ClaimAcquire -ClaimsDir $staleDir -Mod $fixMod -RepoRoot $fixRepo -Session 'new-session' -NowUtc $nowRef
        Assert ($broke.Ok -and $broke.Acquired) "stale claim is broken and re-acquired"
        Assert ($broke.BrokeStale) "stale break is reported"
        Assert ($broke.Version -eq '0.1.6-dev') "re-acquired claim re-allocates from current source, not the stale version"

        # --- release (own + idempotent) ---
        $relDir = Join-Path $tmp 'rel'
        $r1 = Invoke-ClaimAcquire -ClaimsDir $relDir -Mod $fixMod -RepoRoot $fixRepo -Session 'sess-r' -NowUtc $nowRef
        Assert ($r1.Ok -and (Test-Path -LiteralPath (Join-Path $relDir "$fixMod.claim"))) "claim exists after acquire"
        $rel = Invoke-ClaimRelease -ClaimsDir $relDir -Mod $fixMod -Session 'sess-r'
        Assert ($rel.Ok -and $rel.Removed -and -not $rel.CrossSession) "own claim releases cleanly"
        Assert (-not (Test-Path -LiteralPath (Join-Path $relDir "$fixMod.claim"))) "claim file gone after release"
        $rel2 = Invoke-ClaimRelease -ClaimsDir $relDir -Mod $fixMod -Session 'sess-r'
        Assert ($rel2.Ok -and -not $rel2.Removed) "release is idempotent (no claim = no-op success)"
        $foreignDir = Join-Path $tmp 'foreign-release'
        $foreignClaim = Invoke-ClaimAcquire -ClaimsDir $foreignDir -Mod $fixMod -RepoRoot $fixRepo -Session 'owner-a' -NowUtc $nowRef
        $foreignRelease = Invoke-ClaimRelease -ClaimsDir $foreignDir -Mod $fixMod -Session 'owner-b'
        Assert ($foreignClaim.Ok -and -not $foreignRelease.Ok -and $foreignRelease.CrossSession) "foreign owner cannot release a live claim"
        Assert (Test-Path -LiteralPath (Join-Path $foreignDir "$fixMod.claim")) "foreign release leaves the owner's claim intact"

        # --- ship.ps1 verify contract ---
        $vDir = Join-Path $tmp 'verify'
        $v = Invoke-ClaimAcquire -ClaimsDir $vDir -Mod $fixMod -RepoRoot $fixRepo -Session 'sess-v' -NowUtc $nowRef
        $ver = $v.Version
        Assert ((Test-ShipClaimState -ClaimsDir $vDir -Mod $fixMod -ExpectedVersion $ver -ExpectedSession 'sess-v' -NowUtc $nowRef).State -eq 'ok') "verify OK when live claim owner and version match"
        Assert ((Test-ShipClaimState -ClaimsDir $vDir -Mod $fixMod -ExpectedVersion '9.9.9-dev' -ExpectedSession 'sess-v' -NowUtc $nowRef).State -eq 'mismatch') "verify reports mismatch on version divergence"
        Assert ((Test-ShipClaimState -ClaimsDir $vDir -Mod $fixMod -ExpectedVersion $ver -ExpectedSession 'sess-foreign' -NowUtc $nowRef).State -eq 'owner_mismatch') "same-version foreign owner cannot consume a claim"
        Assert ((Test-ShipClaimState -ClaimsDir $vDir -Mod 'nonesuch' -ExpectedVersion $ver -ExpectedSession 'sess-v' -NowUtc $nowRef).State -eq 'absent') "verify reports absent when no claim"
        Assert ((Test-ShipClaimState -ClaimsDir $vDir -Mod $fixMod -ExpectedVersion $ver -ExpectedSession 'sess-v' -NowUtc $nowRef.AddHours(25)).State -eq 'stale') "verify treats a 25h-old claim as stale"

        # --- adversarial delete-after-read races: replacement must survive ---
        foreach ($raceKind in @('unreadable', 'stale')) {
            $deleteRaceDir = Join-Path $tmp "delete-race-$raceKind"
            [System.IO.Directory]::CreateDirectory($deleteRaceDir) | Out-Null
            $deleteRaceClaim = Join-Path $deleteRaceDir "$fixMod.claim"
            $oldRaw = if ($raceKind -eq 'unreadable') {
                'persistently corrupt claim fixture'
            } else {
                Format-ClaimContent -Mod $fixMod -Version '0.0.1-dev' -Session 'expired-owner' -CreatedUtc $nowRef.AddHours(-25)
            }
            [System.IO.File]::WriteAllText($deleteRaceClaim, $oldRaw, $utf8NoBom)
            $ready = Join-Path $deleteRaceDir 'ready'
            $continue = Join-Path $deleteRaceDir 'continue'
            $workerArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -ConditionalDeleteRaceWorker -RaceClaimPath "{1}" -RaceReadyPath "{2}" -RaceContinuePath "{3}"' -f $PSCommandPath, $deleteRaceClaim, $ready, $continue
            $worker = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList $workerArgs
            $deadline = (Get-Date).AddSeconds(10)
            while (-not (Test-Path -LiteralPath $ready) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 20 }
            $replacement = Format-ClaimContent -Mod $fixMod -Version '0.1.6-dev' -Session "replacement-$raceKind" -CreatedUtc $nowRef
            [System.IO.File]::WriteAllText($deleteRaceClaim, $replacement, $utf8NoBom)
            [System.IO.File]::WriteAllText($continue, 'continue', $utf8NoBom)
            $worker.WaitForExit()
            $survivor = Read-ClaimFile $deleteRaceClaim
            Assert ($worker.ExitCode -eq 0 -and $survivor -and $survivor.Session -eq "replacement-$raceKind") "$raceKind delete-after-read race preserves the replacement owner's claim (multi-process)"
        }

        # --- atomic contention: two worktrees/processes, exactly one wins ---
        $raceDir = Join-Path $tmp 'race'
        $selfPath = $PSCommandPath
        $fmt = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Mod {1} -RepoRoot "{2}" -ClaimsDir "{3}" -Session {4} -Quiet'
        $p1 = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList ($fmt -f $selfPath, $fixMod, $fixRepo, $raceDir, 'race-a')
        $p2 = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList ($fmt -f $selfPath, $fixMod, $fixRepoB, $raceDir, 'race-b')
        $p1.WaitForExit(); $p2.WaitForExit()
        $codes = @($p1.ExitCode, $p2.ExitCode)
        $acquired = @($codes | Where-Object { $_ -eq 0 }).Count
        $contended = @($codes | Where-Object { $_ -eq 1 }).Count
        Assert ($acquired -eq 1) ("exactly one cross-worktree racing process acquires (exit codes: {0})" -f ($codes -join ','))
        Assert ($contended -eq 1) ("the other cross-worktree process reports contention exit 1 (exit codes: {0})" -f ($codes -join ','))
    }
    finally {
        if (Test-Path -LiteralPath $tmp) {
            Get-ChildItem -LiteralPath $tmp -Recurse -File | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
            Get-ChildItem -LiteralPath $tmp -Recurse -Directory |
                Sort-Object { $_.FullName.Length } -Descending |
                ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host ""
    if ($script:__ctpass) {
        Write-Host "[claim.ps1 -SelfTest] OK -- claim broker contracts intact." -ForegroundColor Green
        return 0
    }
    Write-Host "[claim.ps1 -SelfTest] FAILED -- claim broker regression." -ForegroundColor Red
    return 2
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------
if ($ConditionalDeleteRaceWorker) { exit (Invoke-ConditionalDeleteRaceWorker) }
if ($SelfTest) { exit (Invoke-ClaimSelfTest) }

if (-not $RepoRoot)  { $RepoRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
if (-not $ClaimsDir) { $ClaimsDir = Get-MachineClaimsDir }
$sessionId = if ($Session) { $Session } else { Get-ClaimSessionId -RepoRoot $RepoRoot }
$nowUtc = (Get-Date).ToUniversalTime()

if (-not $Mod) {
    Write-Host "Usage: claim.ps1 -Mod <name>                         (claim + allocate next version)" -ForegroundColor Yellow
    Write-Host "       claim.ps1 -Mod <name> -Release                (free the claim)" -ForegroundColor Yellow
    Write-Host "       claim.ps1 -Mod <name> -Verify -ExpectedVersion <v>   (ship.ps1 gate)" -ForegroundColor Yellow
    Write-Host "       claim.ps1 -SelfTest" -ForegroundColor Yellow
    exit 2
}

# --- verify (ship.ps1 gate hook) ---
if ($Verify) {
    if (-not $ExpectedVersion) {
        Write-Host "claim.ps1 -Verify requires -ExpectedVersion <MOD_VERSION>." -ForegroundColor Red
        exit 2
    }
    $state = Test-ShipClaimState -ClaimsDir $ClaimsDir -Mod $Mod -ExpectedVersion $ExpectedVersion -ExpectedSession $sessionId -NowUtc $nowUtc -StaleHours $StaleHours
    switch ($state.State) {
        'ok' {
            if (-not $Quiet) { Write-Host "OK -- live claim for '$Mod' matches v$ExpectedVersion." -ForegroundColor Green }
            exit 0
        }
        'absent' {
            if (-not $Quiet) { Write-Host "No live claim for '$Mod'." -ForegroundColor Red }
            exit 3
        }
        'mismatch' {
            if (-not $Quiet) { Write-Host "Claim for '$Mod' is v$($state.Claim.Version); source is v$ExpectedVersion." -ForegroundColor Red }
            exit 4
        }
        'stale' {
            if (-not $Quiet) { Write-Host "Claim for '$Mod' is STALE (older than $StaleHours h)." -ForegroundColor Red }
            exit 5
        }
        'owner_mismatch' {
            if (-not $Quiet) { Write-Host "Claim for '$Mod' belongs to '$($state.Claim.Session)'; current owner is '$sessionId'." -ForegroundColor Red }
            exit 6
        }
    }
}

# --- release ---
if ($Release) {
    $r = Invoke-ClaimRelease -ClaimsDir $ClaimsDir -Mod $Mod -Session $sessionId
    if ($r.Removed) {
        if (-not $Quiet) {
            Write-Host "Released claim for '$Mod'." -ForegroundColor Green
            if ($r.CrossSession) {
                Write-Host "  NOTE: that claim was created by session '$($r.Held.Session)', not this one." -ForegroundColor Yellow
            }
        }
    }
    elseif ($r.Ok) {
        if (-not $Quiet) { Write-Host "No claim to release for '$Mod'." -ForegroundColor DarkGray }
    }
    else {
        Write-Host "FAILED to release claim for '$Mod': $($r.Message)" -ForegroundColor Red
        if ($r.CrossSession -and $r.Held) {
            Write-Host "  Foreign live claims are never removed; coordinate with '$($r.Held.Session)' or wait for stale recovery." -ForegroundColor Yellow
        }
        exit 1
    }
    exit 0
}

# --- default: acquire ---
try {
    $r = Invoke-ClaimAcquire -ClaimsDir $ClaimsDir -Mod $Mod -RepoRoot $RepoRoot -Session $sessionId -NowUtc $nowUtc -StaleHours $StaleHours
}
catch {
    Write-Host ""
    Write-Host "CLAIM ERROR for '$Mod': $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

if ($r.Ok) {
    if ($Quiet) { exit 0 }
    Write-Host ""
    if ($r.Acquired) {
        Write-Host "==================== CLAIM ACQUIRED ====================" -ForegroundColor Green
    } else {
        Write-Host "================ CLAIM ALREADY HELD (you) ==============" -ForegroundColor Green
    }
    Write-Host ("  Mod              : {0}" -f $Mod)
    Write-Host ("  Allocated version: {0}" -f $r.Version)
    Write-Host ("  Session          : {0}" -f $sessionId)
    if ($r.BrokeStale) { Write-Host ("  (broke a stale claim older than {0} h)" -f $StaleHours) -ForegroundColor Yellow }
    Write-Host ""
    Write-Host ("  NEXT: set  local MOD_VERSION = `"{0}`"  in the mod's lua, then:" -f $r.Version)
    Write-Host ("        .\tools\ship\ship.ps1 -Mod {0}" -f $Mod)
    Write-Host ("  ship.ps1 auto-releases this claim on success; or free it early with")
    Write-Host ("        .\tools\ship\claim.ps1 -Mod {0} -Release" -f $Mod)
    Write-Host "=======================================================" -ForegroundColor Green
    exit 0
}

# contention
if (-not $Quiet) {
    Write-Host ""
    Write-Host "CLAIM DENIED: '$Mod' is already claimed by another session." -ForegroundColor Red
    if ($r.Held) {
        $ageH = [math]::Round((($nowUtc - $r.Held.CreatedUtc).TotalHours), 2)
        $staleIn = [math]::Round(($StaleHours - $ageH), 2)
        Write-Host ("  Held by session : {0}" -f $r.Held.Session)
        Write-Host ("  Since (UTC)     : {0}" -f (ConvertTo-ClaimTimestamp $r.Held.CreatedUtc))
        Write-Host ("  Their version   : {0}" -f $r.Held.Version)
        Write-Host ("  Age             : {0} h (breakable as stale in {1} h)" -f $ageH, $staleIn)
    } else {
        Write-Host ("  {0}" -f $r.Message)
    }
    Write-Host "  Coordinate with that session, or wait until it ships/releases." -ForegroundColor Yellow
}
exit 1
