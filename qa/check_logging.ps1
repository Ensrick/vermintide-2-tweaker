# check_logging.ps1 — static logging-hygiene scan for active-mod Lua files.
#
# Encodes PROJECT_STANDARDS.md § 3.6 (Debug logging + "Chat-echo policy" matrix)
# and docs/BUG_CLASSES.md § 17 (chat-echo spam + Variant B, Issue #240). Three
# advisory sub-checks, each with a false-positive-safe suppression path:
#
#   (a) ECHO       — a `mod:echo(` call in one of the § 3.6 / BUG_CLASSES § 17
#       "NEVER" contexts, i.e. the sites those docs say to audit against the
#       chat-echo matrix: (1) module-load top-level (not inside any function) that
#       is NOT the dev/alpha/beta/0.x banner (`mod:echo(... MOD_VERSION ...)`);
#       (2) an `on_setting_changed` / `on_enabled` / `on_disabled` lifecycle body;
#       (3) a hook callback body (`mod:hook`/`mod:hook_safe` inline `function`).
#       Echoes inside ordinary functions and `mod:command`/keybind handler bodies
#       are NOT flagged — § 3.6 sanctions user-invoked replies, and a static tool
#       cannot trace a reply routed through a private helper without a call graph;
#       flagging them all buries the signal. This favors precision (some routine
#       echoes in ordinary helpers are missed — a safe false negative). Several
#       § 3.6 rows are legitimately OK inside these contexts (a high-impact
#       `on_setting_changed` toggle, an `on_disabled` documented-limitation
#       notice, ct's "Granted N boons" hook reply) — annotate those with an inline
#       `-- allow-echo: <reason>` (same line or line directly above).
#
#   (b) PER-FRAME  — a `mod:info(` / `mod:warning(` call inside a per-frame
#       callback (`function update`, `mod.update`, `X.update`/`X:update`, or an
#       inline `mod:hook*(..., "update", function...)`). These fire every frame;
#       gate behind a state-change guard or move out of the hot path. Suppress an
#       intentional throttled/one-shot site with `-- allow-perframe: <reason>`.
#
#   (c) WARN-CHAT  — a `mod:warning(` call inside a debug/alert HELPER
#       (`_dbg_alert`, `_spawn_dbg_alert`, a `dbg`/`alert`-named helper — NOT a
#       `chat`-named one). This is the Issue #240 class: `mod:warning` is BELIEVED
#       log-only but VMF `logging.lua` defaults `warning` to mode 3
#       (`send_to_chat = mode >= 2`), so a "log-only alert" helper spams chat. The
#       sanctioned form is pcall-guarded raw `printf` (et v0.7.25-dev, #240).
#       Genuine failure-path `mod:warning` (in ordinary guards, `_safe`, etc.) is
#       NOT flagged — chat visibility is arguably wanted there. Suppress an
#       intentional in-helper chat warning with `-- allow-warn-chat: <reason>`.
#
# Existing hygiene debt is advisory by result: ordinary findings exit 1, which
# Standard policy reports without blocking. Issue #427's monotonic warn-chat
# floor is blocking: any warning-backed diagnostic helper outside the exact
# three public stable-stream promotion debts exits 2.
#
# Detection scope mirrors check_unpack_safety.ps1: `*.lua` under each active mod's
# `scripts/` subtree; skips tweaker/ (legacy), _archive, *_extract, bundleV2,
# reference clones, fixtures. Comment- and string-blanking (block comments incl.
# --[=[ ]=], quoted spans) runs before keyword/call matching so keywords in prose
# or literals never count. Scope membership uses a per-line Lua block-depth
# counter (function/if/for/while/do vs end) with per-kind "floors" and a function-
# nesting counter (module-top = no function open); it is a heuristic, not a
# parser, but it is validated against the live repo (vdl's ~100 command echoes
# report clean).
#
# Exit codes:
#   0 - no findings
#   1 - one or more advisory findings (echo / per-frame / warn-chat)
#   2 - hard error, self-test failure, or new #427 warn-chat regression
#
# Self-test: `-SelfTest` runs the synthetic fixtures under qa/_test_fixtures/ and
# asserts per-category finding counts. Auto-discovered by qa/run_selftests.ps1.

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [switch]$Quiet,
    [switch]$SelfTest,
    [switch]$WarnChatRegression
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path $RepoRoot).Path

# Issue #427 migration floor. These are the three public stable-stream helpers
# whose dev twins are already console-only; they may disappear through an
# authorized promotion, but no new warning-backed diagnostic helper may enter
# any stream. Keying on both relative path and source text means an additional
# helper in one of these files is not silently grandfathered.
$legacyWarnChatDebt = @{
    'chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua|mod:warning("[ct:dbg] " .. fmt, ...)' = $true
    'general_tweaker/scripts/mods/general_tweaker/general_tweaker.lua|mod:warning("[gt:dbg] " .. fmt, ...)' = $true
    'verminious_dreams_lighting/scripts/mods/verminious_dreams_lighting/verminious_dreams_lighting.lua|mod:warning("[vdl:dbg] " .. fmt, ...)' = $true
}

function Read-FileUtf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

# ---- pre-compiled regexes ----
$rxEcho      = [regex]'\bmod:echo\s*\('
$rxInfo      = [regex]'\bmod:info\s*\('
$rxWarning   = [regex]'\bmod:warning\s*\('
$rxModVer    = [regex]'\bMOD_VERSION\b'
$rxHookAny   = [regex]'\bmod:hook\w*\s*\('
$rxHookUpd   = [regex]'\bmod:hook\w*\s*\([^)]*["'']update["'']'
# A mod:warning whose message literal opens with a debug tag ("[cosmetics:dbg] ...",
# "[dbg] ..."). #427: helper-shaped detection alone missed direct prefix-tagged
# warnings in sibling modules (cosmetics_tweaker\_la_okri.lua carried two for five
# audit passes). The author's own :dbg tag is the intent signal -- it is a
# diagnostic, so it must not reach chat, whatever scope it sits in.
$rxWarnDbgTag = [regex]'\bmod:warning\s*\(\s*["'']\s*\[[A-Za-z_][\w\-]*:dbg\]|\bmod:warning\s*\(\s*["'']\s*\[dbg\]'

# escape comments (accepted on the flagged line OR the line directly above)
$rxAllowEcho = [regex]'--\s*allow-echo\s*:'
$rxAllowFrame= [regex]'--\s*allow-perframe\s*:'
$rxAllowWarn = [regex]'--\s*allow-warn-chat\s*:'

# function-definition name extraction (first match wins)
$rxDefLocal  = [regex]'\blocal\s+function\s+([A-Za-z_][\w]*)'
$rxDefNamed  = [regex]'\bfunction\s+([A-Za-z_][\w\.:]*)\s*\('
$rxDefAssign = [regex]'([A-Za-z_][\w\.:]*)\s*=\s*function\b'

# scope classifiers (applied to an extracted function name)
$rxLifecycle  = [regex]'(?i)(^|[\.:])(on_setting_changed|on_enabled|on_disabled)$'
$rxUpdateName = [regex]'(?i)(^|[\.:])update$'
$rxAlertName  = [regex]'(?i)(dbg|alert|log_only|warn_log|diag)'
$rxChatName   = [regex]'(?i)chat'

# block-depth token counters (run on comment/string-stripped code)
$rxTokFunction = [regex]'\bfunction\b'
$rxTokIf       = [regex]'\bif\b'
$rxTokFor      = [regex]'\bfor\b'
$rxTokWhile    = [regex]'\bwhile\b'
$rxTokDo       = [regex]'\bdo\b'
$rxTokEnd      = [regex]'\bend\b'

# ---- file collection (mirrors check_unpack_safety.ps1) ----
function Get-ScanFiles {
    param([string]$Root)
    Get-ChildItem -Path $Root -Filter "*.lua" -Recurse -File -ErrorAction SilentlyContinue `
        | Where-Object {
            $p = $_.FullName
            $isActive = $p -match "\\scripts\\"
            $notExcluded = $p -notlike "*\_archive\*" `
                       -and $p -notlike "*\bundleV2\*" `
                       -and $p -notlike "*\.build\*" `
                       -and $p -notlike "*\.temp\*" `
                       -and $p -notlike "*\_tmp\*" `
                       -and $p -notlike "*\.spawn_tweaks_ref\*" `
                       -and $p -notlike "*\tweaker\*" `
                       -and $p -notlike "*\_test_fixtures\*" `
                       -and $p -notlike "*\sample_*\*" `
                       -and $p -notlike "*\Vermintide-2-Source-Code\*" `
                       -and $p -notlike "*\Darktide-Source-Code\*" `
                       -and $p -notlike "*\_*_extract\*" `
                       -and $p -notlike "*\.claude\*"
            return $isActive -and $notExcluded
        }
}

# Strip a line's comment tail + string interiors, tracking multi-line block
# comments. Returns @{ Code = <code-only text>; InBlock; BlockCloser }. Same
# state machine as check_unpack_safety.ps1's Scan-File loop.
function Get-CodePart {
    param([string]$Line, [bool]$InBlock, [string]$BlockCloser)
    $work = $Line
    if ($InBlock) {
        $ci = $work.IndexOf($BlockCloser)
        if ($ci -lt 0) { return @{ Code = ""; InBlock = $true; BlockCloser = $BlockCloser } }
        $work = $work.Substring($ci + $BlockCloser.Length)
        $InBlock = $false
        $BlockCloser = ""
    }
    # Blank string-literal interiors FIRST, before splitting on `--`. A string may
    # itself contain `--` (e.g. "...intercept while popup already up -- skipping..."):
    # splitting on that `--` first would truncate the string mid-literal, leaving an
    # unterminated (un-blanked) span whose keywords (`while`, `if`, `end`, …) leak
    # into the block-depth counter and desync every scope below it.
    $work = [regex]::Replace($work, '"[^"]*"', '""')
    $work = [regex]::Replace($work, "'[^']*'", "''")

    $codePart = $work
    $cIdx = $work.IndexOf('--')
    if ($cIdx -ge 0) {
        $codePart = $work.Substring(0, $cIdx)
        $rest = $work.Substring($cIdx + 2)
        $open = [regex]::Match($rest, '^(=*)\[')
        if ($open.Success) {
            $closer = "]" + $open.Groups[1].Value + "]"
            $afterOpen = $rest.Substring($open.Length)
            if ($afterOpen.IndexOf($closer) -lt 0) {
                $InBlock = $true
                $BlockCloser = $closer
            }
        }
    }
    return @{ Code = $codePart; InBlock = $InBlock; BlockCloser = $BlockCloser }
}

function Get-FuncName {
    param([string]$Code)
    $m = $rxDefLocal.Match($Code);  if ($m.Success) { return $m.Groups[1].Value }
    $m = $rxDefNamed.Match($Code);  if ($m.Success) { return $m.Groups[1].Value }
    $m = $rxDefAssign.Match($Code); if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

# Does this stripped line open a function scope? (any of the three def forms, or
# an inline callback such as `mod:command(...)`/`mod:hook(...)` with `function`)
function Test-OpensFunction {
    param([string]$Code)
    return $rxTokFunction.IsMatch($Code)
}

function Get-Delta {
    param([string]$Code)
    $open = $rxTokFunction.Matches($Code).Count `
          + $rxTokIf.Matches($Code).Count `
          + $rxTokFor.Matches($Code).Count `
          + $rxTokWhile.Matches($Code).Count
    # bare `do` block opener — but the `do` on a for/while line is that loop's
    # `do` (already counted via for/while), so only count `do` when the line has
    # neither for nor while.
    if (-not ($rxTokFor.IsMatch($Code) -or $rxTokWhile.IsMatch($Code))) {
        $open += $rxTokDo.Matches($Code).Count
    }
    $close = $rxTokEnd.Matches($Code).Count
    return ($open - $close)
}

# ---- per-file scan ----
# Returns an array of finding rows: @{ File; Line; Category; Text }.
function Scan-LoggingFile {
    param([string]$Path)
    $findings = @()
    try {
        $text = Read-FileUtf8 $Path
    } catch {
        throw "I/O failure reading ${Path}: $_"
    }
    # fast bail — nothing to scan
    if (-not ($rxEcho.IsMatch($text) -or $rxInfo.IsMatch($text) -or $rxWarning.IsMatch($text))) {
        return ,$findings
    }

    $lines = $text -split "`r?`n"
    $depth = 0
    $neverFloor  = $null      # innermost § 3.6 "NEVER" echo scope (lifecycle / hook body)
    $updateFloor = $null      # innermost per-frame (update) scope
    $alertFloor  = $null      # innermost dbg/alert helper scope
    $inBlock = $false
    $blockCloser = ""

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $raw = $lines[$i]
        $prev = if ($i -gt 0) { $lines[$i - 1] } else { "" }

        $strip = Get-CodePart -Line $raw -InBlock $inBlock -BlockCloser $blockCloser
        $code = $strip.Code
        $inBlock = $strip.InBlock
        $blockCloser = $strip.BlockCloser
        if ([string]::IsNullOrEmpty($code)) { continue }

        $depthBefore = $depth

        # ---- scope-open detection (set floors at depthBefore, shallowest wins) ----
        $funcName   = Get-FuncName -Code $code
        $opensFunc  = Test-OpensFunction -Code $code
        # NEVER echo scope: an on_setting_changed/on_enabled/on_disabled body, or
        # a hook callback body (inline `mod:hook*(...) function`).
        $isLifecycle = $funcName -and $rxLifecycle.IsMatch($funcName)
        $isHookBody  = $opensFunc -and $rxHookAny.IsMatch($code)
        $isUpdate    = ($funcName -and $rxUpdateName.IsMatch($funcName)) -or $rxHookUpd.IsMatch($code)
        $isAlert     = $funcName -and $rxAlertName.IsMatch($funcName) -and -not $rxChatName.IsMatch($funcName)

        if (($isLifecycle -or $isHookBody) -and $null -eq $neverFloor) { $neverFloor = $depthBefore }
        if ($isUpdate -and $null -eq $updateFloor) { $updateFloor = $depthBefore }
        if ($isAlert  -and $null -eq $alertFloor)  { $alertFloor  = $depthBefore }

        # ---- violation detection (uses floor state AFTER opens, BEFORE close) ----
        # (a) echo in a NEVER context: module-load top-level (depth 0, not the
        #     MOD_VERSION dev banner), or inside a lifecycle / hook-body scope.
        if ($rxEcho.IsMatch($code)) {
            $inNever = ($null -ne $neverFloor) -or ($depthBefore -eq 0)
            $suppressed = (-not $inNever) `
                -or $rxModVer.IsMatch($code) `
                -or $rxAllowEcho.IsMatch($raw) -or $rxAllowEcho.IsMatch($prev)
            if (-not $suppressed) {
                $findings += [pscustomobject]@{ File = $Path; Line = $i + 1; Category = 'echo'; Text = $raw.Trim() }
            }
        }
        # (b) per-frame info/warning
        if ($null -ne $updateFloor -and ($rxInfo.IsMatch($code) -or $rxWarning.IsMatch($code))) {
            if (-not ($rxAllowFrame.IsMatch($raw) -or $rxAllowFrame.IsMatch($prev))) {
                $findings += [pscustomobject]@{ File = $Path; Line = $i + 1; Category = 'perframe'; Text = $raw.Trim() }
            }
        }
        # (c) warning inside a dbg/alert helper (Issue #240 class). Skip if the
        #     same line was already flagged per-frame to avoid double-reporting.
        if ($null -ne $alertFloor -and $rxWarning.IsMatch($code) -and $null -eq $updateFloor) {
            if (-not ($rxAllowWarn.IsMatch($raw) -or $rxAllowWarn.IsMatch($prev))) {
                $findings += [pscustomobject]@{ File = $Path; Line = $i + 1; Category = 'warn-chat'; Text = $raw.Trim() }
            }
        }
        # (d) self-tagged debug warning ("[<mod>:dbg] ...") ANYWHERE, not just inside a
        #     helper -- the (c) rule only sees helper-shaped sites. Skip when (b) or (c)
        #     already flagged this line so a site is never counted twice.
        # `$code` has string interiors blanked (see Get-CodePart), so the tag is only
        # visible in `$raw`; require the CALL in $code so a commented-out line is inert.
        if ($rxWarning.IsMatch($code) -and $rxWarnDbgTag.IsMatch($raw) -and ($null -eq $alertFloor) -and ($null -eq $updateFloor)) {
            if (-not ($rxAllowWarn.IsMatch($raw) -or $rxAllowWarn.IsMatch($prev))) {
                $findings += [pscustomobject]@{ File = $Path; Line = $i + 1; Category = 'warn-chat'; Text = $raw.Trim() }
            }
        }

        # ---- apply block-depth delta, then close any scope that has ended ----
        $depth += (Get-Delta -Code $code)
        if ($depth -lt 0) { $depth = 0 }   # never underflow on a stray/miscounted end
        if ($null -ne $neverFloor  -and $depth -le $neverFloor)  { $neverFloor  = $null }
        if ($null -ne $updateFloor -and $depth -le $updateFloor) { $updateFloor = $null }
        if ($null -ne $alertFloor  -and $depth -le $alertFloor)  { $alertFloor  = $null }
    }
    return ,$findings
}

# Derive a mod short-name from a scan path: the directory segment before \scripts\.
function Get-ModName {
    param([string]$Path, [string]$Root)
    $rel = $Path
    if ($rel.StartsWith($Root)) { $rel = $rel.Substring($Root.Length).TrimStart('\','/') }
    $rel = $rel.Replace('\','/')
    $idx = $rel.IndexOf('/scripts/')
    if ($idx -gt 0) { return $rel.Substring(0, $idx) }
    return ($rel -split '/')[0]
}

function Get-UnexpectedWarnChatRows {
    param([object[]]$Rows, [string]$Root)
    $unexpected = @()
    foreach ($row in @($Rows | Where-Object { $_.Category -eq 'warn-chat' })) {
        $rel = $row.File
        if ($rel.StartsWith($Root)) { $rel = $rel.Substring($Root.Length).TrimStart('\','/') }
        $rel = $rel.Replace('\','/').ToLowerInvariant()
        $key = $rel + '|' + $row.Text.Trim()
        if (-not $legacyWarnChatDebt.ContainsKey($key)) { $unexpected += $row }
    }
    return $unexpected
}

# ---- self-test ----
function Invoke-SelfTest {
    $fixDir = Join-Path $PSScriptRoot "_test_fixtures"
    if (-not (Test-Path $fixDir)) {
        Write-Host "[check_logging -SelfTest] FAIL: $fixDir does not exist." -ForegroundColor Red
        return 2
    }
    # Expected finding counts per category per fixture.
    $cases = @(
        @{ Path = "logging_echo_bad.lua";     Echo = 2; Frame = 0; Warn = 0; Desc = "hook-body + on_setting_changed echo flagged; command / dev-banner / annotated echo suppressed" },
        @{ Path = "logging_perframe_bad.lua"; Echo = 0; Frame = 2; Warn = 0; Desc = "mod:info + mod:warning in update() flagged; annotated one suppressed" },
        @{ Path = "logging_warn_helper_bad.lua"; Echo = 0; Frame = 0; Warn = 1; Desc = "mod:warning in _dbg_alert flagged; genuine-guard warning + annotated one suppressed" },
        @{ Path = "logging_warn_dbgtag_bad.lua"; Echo = 0; Frame = 0; Warn = 1; Desc = "self-tagged [x:dbg] mod:warning outside any helper flagged; annotated one + untagged player-facing warning suppressed" },
        @{ Path = "logging_string_dash.lua";  Echo = 1; Frame = 0; Warn = 0; Desc = "`--`-in-string with a `while` keyword must not desync scope; command echoes stay clean" },
        @{ Path = "logging_clean.lua";        Echo = 0; Frame = 0; Warn = 0; Desc = "all sanctioned forms — zero findings" }
    )
    $allPass = $true
    foreach ($c in $cases) {
        $f = Join-Path $fixDir $c.Path
        if (-not (Test-Path $f)) {
            Write-Host "  X $($c.Path): missing fixture file" -ForegroundColor Red
            $allPass = $false
            continue
        }
        $rows = Scan-LoggingFile -Path $f
        $ge = @($rows | Where-Object { $_.Category -eq 'echo' }).Count
        $gf = @($rows | Where-Object { $_.Category -eq 'perframe' }).Count
        $gw = @($rows | Where-Object { $_.Category -eq 'warn-chat' }).Count
        $ok = ($ge -eq $c.Echo) -and ($gf -eq $c.Frame) -and ($gw -eq $c.Warn)
        $verdict = if ($ok) { "PASS" } else { "FAIL" }
        $colour  = if ($ok) { "Green" } else { "Red" }
        Write-Host ("  [{0}] {1} -- echo={2}/{3} frame={4}/{5} warn={6}/{7}" -f `
            $verdict, $c.Path, $ge, $c.Echo, $gf, $c.Frame, $gw, $c.Warn) -ForegroundColor $colour
        if (-not $ok) { Write-Host "        $($c.Desc)" -ForegroundColor DarkYellow; $allPass = $false }
    }

    # The #427 floor is monotonic: the exact three stable-stream debts are
    # tolerated until promotion, their removal is clean, and either a new path
    # or a second warning helper in a grandfathered file is blocking.
    $knownPath = Join-Path $repoRoot 'general_tweaker\scripts\mods\general_tweaker\general_tweaker.lua'
    $known = [pscustomobject]@{ File = $knownPath; Line = 49; Category = 'warn-chat'; Text = 'mod:warning("[gt:dbg] " .. fmt, ...)' }
    $newText = [pscustomobject]@{ File = $knownPath; Line = 50; Category = 'warn-chat'; Text = 'mod:warning("[gt:new-diagnostic] " .. fmt, ...)' }
    $newPath = [pscustomobject]@{ File = (Join-Path $repoRoot 'event_tweaker\scripts\mods\event_tweaker\event_tweaker.lua'); Line = 20; Category = 'warn-chat'; Text = 'mod:warning("[event:dbg] " .. fmt, ...)' }
    $floorOk = (@(Get-UnexpectedWarnChatRows -Rows @($known) -Root $repoRoot).Count -eq 0) `
        -and (@(Get-UnexpectedWarnChatRows -Rows @() -Root $repoRoot).Count -eq 0) `
        -and (@(Get-UnexpectedWarnChatRows -Rows @($known, $newText, $newPath) -Root $repoRoot).Count -eq 2)
    Write-Host ("  [{0}] warn-chat migration floor -- exact legacy accepted; removal accepted; new sites rejected" -f $(if ($floorOk) { 'PASS' } else { 'FAIL' })) -ForegroundColor $(if ($floorOk) { 'Green' } else { 'Red' })
    if (-not $floorOk) { $allPass = $false }
    Write-Host ""
    if ($allPass) {
        Write-Host "[check_logging -SelfTest] OK -- all $($cases.Count) fixture verdicts match." -ForegroundColor Green
        return 0
    }
    Write-Host "[check_logging -SelfTest] FAILED -- heuristic/scope regression. Inspect fixtures + Scan-LoggingFile." -ForegroundColor Red
    return 2
}

# ---- main ----
Write-Host "=== check_logging ===" -ForegroundColor Cyan

if ($SelfTest) { exit (Invoke-SelfTest) }

# The issue-specific gate does not need the echo/per-frame census. Pre-filter to
# files that contain a live `mod:warning` token, then reuse the exact same scoped
# scanner for warn-chat classification. This keeps pre-commit/targeted runs fast
# without introducing a second, weaker parser.
if ($WarnChatRegression) {
    $warnRows = @()
    $hardError = $false
    foreach ($f in @(Get-ScanFiles -Root $repoRoot)) {
        try {
            $text = Read-FileUtf8 $f.FullName
            if (-not $rxWarning.IsMatch($text)) { continue }
            $rows = Scan-LoggingFile -Path $f.FullName
            foreach ($row in $rows) {
                if ($row.Category -eq 'warn-chat') { $warnRows += $row }
            }
        } catch {
            Write-Host ("  X {0}: {1}" -f $f.FullName, $_) -ForegroundColor Red
            $hardError = $true
        }
    }
    if ($hardError) {
        Write-Host "[check_logging -WarnChatRegression] ERROR -- one or more candidate files failed to scan." -ForegroundColor Red
        exit 2
    }
    $unexpected = @(Get-UnexpectedWarnChatRows -Rows $warnRows -Root $repoRoot)
    if ($unexpected.Count -gt 0) {
        Write-Host "[check_logging -WarnChatRegression] FAILED -- $($unexpected.Count) new warning-backed diagnostic helper(s)." -ForegroundColor Red
        foreach ($row in $unexpected) {
            $rel = $row.File
            if ($rel.StartsWith($repoRoot)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
            Write-Host ("  ! {0}:{1}`n      {2}" -f $rel, $row.Line, $row.Text) -ForegroundColor Red
        }
        exit 2
    }
    Write-Host "[check_logging -WarnChatRegression] OK -- no new warning-backed diagnostic helpers; legacy stable promotion debt remaining=$($warnRows.Count)." -ForegroundColor Green
    exit 0
}

$all = @()
$hardError = $false
$files = @(Get-ScanFiles -Root $repoRoot)
foreach ($f in $files) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart('\','/')
    if (-not $Quiet) { Write-Host "Checking $rel" -ForegroundColor DarkGray }
    try {
        $rows = Scan-LoggingFile -Path $f.FullName
    } catch {
        Write-Host ("  X {0}: {1}" -f $rel, $_) -ForegroundColor Red
        $hardError = $true
        continue
    }
    foreach ($r in $rows) { $all += $r }
}

Write-Host ""
if ($hardError) {
    Write-Host "[check_logging] ERROR -- one or more files failed to scan." -ForegroundColor Red
    exit 2
}

$warnRows = @($all | Where-Object { $_.Category -eq 'warn-chat' })
$unexpectedWarnRows = @(Get-UnexpectedWarnChatRows -Rows $warnRows -Root $repoRoot)
if ($unexpectedWarnRows.Count -gt 0) {
    Write-Host "[check_logging] FAILED -- $($unexpectedWarnRows.Count) new warning-backed diagnostic helper(s) exceed the #427 migration floor." -ForegroundColor Red
    foreach ($row in $unexpectedWarnRows) {
        $rel = $row.File
        if ($rel.StartsWith($repoRoot)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
        Write-Host ("  ! {0}:{1}`n      {2}" -f $rel, $row.Line, $row.Text) -ForegroundColor Red
    }
    exit 2
}

if ($all.Count -eq 0) {
    Write-Host "[check_logging] OK -- no logging-hygiene findings." -ForegroundColor Green
    exit 0
}

# ---- report: counts per mod, then file:line detail per category ----
$byMod = $all | Group-Object { Get-ModName -Path $_.File -Root $repoRoot } | Sort-Object Name
Write-Host "[check_logging] ADVISORY findings: $($all.Count) (echo=$(@($all | Where-Object Category -eq 'echo').Count), per-frame=$(@($all | Where-Object Category -eq 'perframe').Count), warn-chat=$(@($all | Where-Object Category -eq 'warn-chat').Count))" -ForegroundColor Yellow
Write-Host ""
Write-Host "Per-mod counts:" -ForegroundColor Yellow
foreach ($g in $byMod) {
    $e = @($g.Group | Where-Object Category -eq 'echo').Count
    $p = @($g.Group | Where-Object Category -eq 'perframe').Count
    $w = @($g.Group | Where-Object Category -eq 'warn-chat').Count
    Write-Host ("  {0,-32} total={1,-3} echo={2} per-frame={3} warn-chat={4}" -f $g.Name, $g.Count, $e, $p, $w) -ForegroundColor Yellow
}
Write-Host ""

$labels = @{
    'echo'      = "mod:echo outside the § 3.6 chat-echo allowances (route routine diagnostics through _dbg log-only; annotate a legit reply with -- allow-echo: <reason>)"
    'perframe'  = "mod:info/mod:warning inside a per-frame update() body (gate on a state change or move off the hot path; annotate with -- allow-perframe: <reason>)"
    'warn-chat' = "mod:warning inside a dbg/alert helper posts to CHAT under VMF defaults (Issue #240; use pcall-guarded printf for log-only; annotate an intentional chat alert with -- allow-warn-chat: <reason>)"
}
foreach ($cat in @('echo','perframe','warn-chat')) {
    $rows = @($all | Where-Object Category -eq $cat)
    if ($rows.Count -eq 0) { continue }
    Write-Host "[$cat] $($labels[$cat])" -ForegroundColor Yellow
    foreach ($r in $rows) {
        $rel = $r.File
        if ($rel.StartsWith($repoRoot)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
        Write-Host ("  ! {0}:{1}" -f $rel, $r.Line) -ForegroundColor Yellow
        Write-Host ("      $($r.Text)") -ForegroundColor DarkYellow
    }
    Write-Host ""
}
exit 1
