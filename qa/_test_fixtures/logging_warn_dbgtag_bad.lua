-- Fixture for check_logging.ps1 -SelfTest — category (d) WARN-CHAT via SELF-TAG (#427).
-- Rule (c) only sees warnings inside a dbg/alert-NAMED helper. This fixture covers
-- the shape that slipped past it for five audit passes: a direct, prefix-tagged
-- mod:warning in an ordinary sibling module (cosmetics_tweaker\_la_okri.lua).
-- Expected: 1 warn-chat finding. The annotated tagged warning is suppressed, and a
-- genuine untagged player-facing warning is NOT flagged.
local MOD_VERSION = "0.1.0-dev"

local function _apply(_key) return true end
local function _register_tab() return true end

-- FLAG: the author's own `[fx:dbg]` tag says this is a diagnostic, but mod:warning
-- posts it to CHAT under VMF defaults. No enclosing dbg-named helper, so only the
-- self-tag can catch it.
mod:hook("SomeClass", "some_method", function(func, self)
    local ok, result = pcall(func, self)
    if not ok then
        mod:warning("[fx:dbg] filter errored: %s", tostring(result))
    end
    return result
end)

-- SUPPRESSED: tagged, but the chat placement is acknowledged as intentional.
local function _scrub(key)
    local ok, err = pcall(_apply, key)
    if not ok then
        mod:warning("[fx:dbg] mutation failed for %s: %s", tostring(key), tostring(err)) -- allow-warn-chat: host must see this
    end
end

-- NOT FLAGGED: genuine player-facing warning, no :dbg tag. A functional qualifier
-- the player needs (PROJECT_STANDARDS rule 11) is valid chat content.
local function _register()
    local ok, err = pcall(_register_tab)
    if not ok then
        mod:warning("[fx] Dialogue tab registration failed: %s", tostring(err))
    end
end
