-- ============================================================================
-- SHARED LIBRARY -- two-channel debug helpers (issue 428 / issue 240)
-- ----------------------------------------------------------------------------
-- MASTER SOURCE: tools/shared_lib/_lib_debug.lua
-- DO NOT EDIT COPIES. Consumers are declared in tools/shared_lib/manifest.psd1
-- and synchronized by sync-shared-libs.ps1. The file is copied into each mod so
-- every Workshop bundle remains fully standalone; it is never a runtime
-- dependency on another mod.
-- ============================================================================
-- Factory API (frozen; evolve additively per PROJECT_STANDARDS.md section 9a):
--   local dbg, dbg_alert = new_debug_helpers(mod, "[my_mod:dbg]")
-- `dbg` is expected/confirmation traffic and respects VMF's debug-log gate.
-- `dbg_alert` reaches console-*.log even when mod logging is off, but never
-- enters chat. VMF mod:warning defaults to chat output (issue 240), so raw
-- printf is deliberate. Both printf calls are protected from format errors.
-- luacheck: globals printf

local function new_debug_helpers(mod, prefix)
    prefix = tostring(prefix or "[mod:dbg]")
    local function dbg(fmt, ...)
        mod:debug(prefix .. " " .. fmt, ...)
    end
    local function dbg_alert(fmt, ...)
        if not pcall(printf, prefix .. " " .. fmt, ...) then
            pcall(printf, prefix .. " (alert format error: %s)", tostring(fmt))
        end
    end
    return dbg, dbg_alert
end

return new_debug_helpers
