-- Fixture for check_logging.ps1 -SelfTest — category (c) WARN-CHAT (Issue #240).
-- Expected: 1 warn-chat finding (the mod:warning inside _dbg_alert). The genuine
-- failure-path mod:warning in an ordinary guard is NOT flagged, and the
-- annotated in-helper warning is suppressed.
local MOD_VERSION = "0.1.0-dev"

-- FLAG: dbg/alert helper believed log-only routes through mod:warning, which
-- posts to CHAT under VMF default settings (mode 3). Should be pcall'd printf.
local function _dbg_alert(fmt, ...)
    mod:warning("[fx:dbg] " .. fmt, ...)
end

-- SUPPRESSED: intentional in-helper chat warning, acknowledged.
local function _loud_alert(fmt, ...)
    mod:warning("[fx] " .. fmt, ...) -- allow-warn-chat: genuine anomaly, chat wanted
end

-- NOT FLAGGED: genuine failure-path warning in an ordinary guard (_safe is not a
-- dbg/alert-named helper; chat visibility on a real fault is acceptable).
local function _safe(label, fn)
    local ok = pcall(fn)
    if not ok then
        mod:warning("[fx] %s failed", label)
    end
    return ok
end
