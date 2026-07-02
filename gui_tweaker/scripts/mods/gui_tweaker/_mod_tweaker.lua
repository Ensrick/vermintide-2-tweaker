local mod = get_mod("gut")

-- Mod Tweaker: controller + public API surface.
-- v0.1 scaffold. Wires the registry/persistence module (_mod_tweaker_settings),
-- the view class (_mod_tweaker_view), and exposes a single ModTweaker handle
-- that other mods reach via `get_mod("gut").mod_tweaker`. The view itself
-- doesn't render yet — that's tasks #6-8. This task just stands up the API
-- surface so dogfood / regression hooks can land in parallel.

local ModTweaker = {}

-- Two-helper debug telemetry (PROJECT_STANDARDS § 3.6). gui_tweaker.lua wires
-- both halves via init_dbg(...) before the ESC entry hooks fire.
local _dbg = function() end
local _dbg_alert = function() end

function ModTweaker.init_dbg(dbg, dbg_alert)
    if type(dbg) == "function" then _dbg = dbg end
    if type(dbg_alert) == "function" then _dbg_alert = dbg_alert end
end

local Settings = mod:dofile("scripts/mods/gui_tweaker/_mod_tweaker_settings")

-- ---------------------------------------------------------------
-- Public API — addressed via get_mod("gut").mod_tweaker:<method>(...).
-- ---------------------------------------------------------------

function ModTweaker:register_category(def)
    local ok, err = Settings.register_category(def)
    if not ok then
        _dbg_alert("[mt] register_category rejected: %s", tostring(err))
    end
    return ok, err
end

function ModTweaker:is_registered(mod_id)
    return Settings.is_registered(mod_id)
end

function ModTweaker:list_categories()
    return Settings.list_categories()
end

function ModTweaker:get_category(mod_id)
    return Settings.get_category(mod_id)
end

function ModTweaker:get(mod_id, setting_id)
    return Settings.get(mod_id, setting_id)
end

function ModTweaker:set(mod_id, setting_id, value)
    return Settings.set(mod_id, setting_id, value)
end

-- Install entry point: wires debug + propagates to sub-modules. Returns the
-- handle table so the owner module can publish it onto `mod`.
function ModTweaker.install(dbg, dbg_alert)
    ModTweaker.init_dbg(dbg, dbg_alert)
    Settings.init_dbg(dbg, dbg_alert)
    _dbg("[mt] installed")
    return ModTweaker
end

return ModTweaker
