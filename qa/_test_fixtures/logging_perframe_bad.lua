-- Fixture for check_logging.ps1 -SelfTest — category (b) PER-FRAME.
-- Expected: 2 per-frame findings (the mod:info + the mod:warning in update()).
-- The annotated per-frame line and the non-update mod:info are suppressed.
local MOD_VERSION = "0.1.0-dev"

-- Non-per-frame mod:info — NOT flagged (outside any update body).
local function _boot()
    mod:info("[fx] boot ok")
end

-- Per-frame callback: mod.update fires every frame.
mod.update = function(dt)
    -- FLAG #1: mod:info every frame.
    mod:info("[fx] tick dt=%s", tostring(dt))
    -- FLAG #2: mod:warning every frame.
    mod:warning("[fx] still running")
    -- SUPPRESSED: explicit throttle acknowledged.
    mod:info("[fx] throttled") -- allow-perframe: rate-limited to 1/sec below
end
