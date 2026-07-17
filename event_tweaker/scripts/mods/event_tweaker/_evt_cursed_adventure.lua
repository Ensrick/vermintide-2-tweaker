local mod = get_mod("event_tweaker")

-- _evt_cursed_adventure.lua — curse package preload + cursed-sky lighting
--
-- Makes the package-bearing Chaos Wastes / Be'lakor curses (MANAGED_CURSES,
-- selected in _evt_selection.lua) actually run on a standard adventure
-- mission. Two hooks:
--   1. MutatorHandler._activate_mutator — a method called on the HOST (via
--      activate_mutators) AND on every CLIENT (via rpc_activate_mutator_client
--      -> activate_mutator), so each peer SYNC-loads the curse's resource
--      package locally, exactly as DeusRunState.set_event_mutators does per
--      peer. Clients need it too: spawn_network_unit replicates a husk whose
--      unit lives in that package. Sync load (Managers.package:load 4th arg
--      false) = ready before the first in-mission spawn; no async race.
--   2. CameraManager.shading_callback — per-frame ShadingEnvironment-var tint
--      for the active curse's Chaos god (profiles copied from
--      chaos_wastes_tweaker.lua:3247). Blends multiplicatively on the level's
--      baked atmosphere; the engine re-seeds every frame so it reverts for
--      free when no curse is active. Client-side cosmetic, no RPC.
-- Both are gated to the ADVENTURE mechanism so a real Chaos Wastes run (where
-- DeusRunState already loads the package and ct already tints) is untouched.
-- Checklist slug et-cursed-adventure-package-preload; see DEVELOPMENT.md
-- "Cursed Adventure" + CHANGELOG 0.4.14-dev for the full audit trail.
--
-- Owned by: event_tweaker.lua entry point (dofile'd last). Consumes mod._evt:
-- dbg, dbg_alert; requires event_tweaker_curses for CURSE_TO_GOD. All curse
-- runtime state (loaded-package set, active-god cache, sky profiles) is
-- file-local — the per-frame shading hook reads no mod._evt indirection.

local ET = mod._evt

local _dbg       = ET.dbg
local _dbg_alert = ET.dbg_alert

local Curses        = require("scripts/mods/event_tweaker/event_tweaker_curses")
local _CURSE_TO_GOD = Curses.CURSE_TO_GOD
local _MANAGED_CURSE = {}
for i = 1, #Curses.MANAGED_CURSES do
    _MANAGED_CURSE[Curses.MANAGED_CURSES[i].id] = true
end

local ET_CURSE_PKG_REF = "event_tweaker_curse_package"
local _loaded_curse_packages = {}   -- pkg_name -> true (our refs to balance)
local _active_curse_god = nil        -- cached for the per-frame shading hook

local function _is_adventure_mechanism()
    local mm = rawget(_G, "Managers") and Managers.mechanism
    if not mm or not mm.current_mechanism_name then return true end
    local ok, name = pcall(mm.current_mechanism_name, mm)
    if not ok then return true end
    return name == "adventure"
end

-- Recompute which Chaos god (if any) the currently-active curses theme, for
-- the sky tint. Cheap; called on activate/deactivate only. When several
-- curses of different gods are active, the lowest curse-name alphabetically
-- wins — DETERMINISTIC so every peer agrees on one tint (pairs() order is
-- unspecified and would diverge host vs client).
local function _refresh_active_curse_god()
    local gm = Managers.state and Managers.state.game_mode
    local handler = gm and gm._mutator_handler
    local active = handler and handler._active_mutators
    local candidates = {}
    if active then
        for name, _ in pairs(active) do
            if _CURSE_TO_GOD[name] then candidates[#candidates + 1] = name end
        end
    end
    table.sort(candidates)
    _active_curse_god = candidates[1] and _CURSE_TO_GOD[candidates[1]] or nil
    if ET.set_curse_session_active then
        local package_curse_active = false
        if active then
            for name in pairs(active) do
                if _MANAGED_CURSE[name] then
                    package_curse_active = true
                    break
                end
            end
        end
        ET.set_curse_session_active(package_curse_active)
    end
end

local function _maybe_preload_curse_package(name)
    if not _is_adventure_mechanism() then return end
    local MT = rawget(_G, "MutatorTemplates")
    local tmpl = MT and rawget(MT, name)
    if not (tmpl and tmpl.packages and next(tmpl.packages) and _CURSE_TO_GOD[name]) then
        return
    end
    local pm = rawget(_G, "Managers") and Managers.package
    if not pm then return end
    for _, pkg in ipairs(tmpl.packages) do
        if not _loaded_curse_packages[pkg] and not pm:has_loaded(pkg, ET_CURSE_PKG_REF) then
            local ok = pcall(pm.load, pm, pkg, ET_CURSE_PKG_REF, nil, false)  -- false = SYNC
            if ok then
                _loaded_curse_packages[pkg] = true
                _dbg("[curse] preloaded %s for %s", pkg, name)
            else
                _dbg_alert("[curse] FAILED to preload %s for %s", pkg, name)
            end
        end
    end
end

-- Hook BOTH the per-mutator activate (host loop + client RPC) and deactivate
-- so the package is ready before activation and the god cache stays current.
mod:hook("MutatorHandler", "_activate_mutator", function(func, self, name, ...)
    if _MANAGED_CURSE[name] and ET.set_curse_session_active then
        -- Close the join boundary before the mutator's start function can spawn
        -- its first package-owned network unit.
        ET.set_curse_session_active(true)
    end
    _maybe_preload_curse_package(name)
    local a, b = func(self, name, ...)
    if _CURSE_TO_GOD[name] then _refresh_active_curse_god() end
    -- Log EVERY mutator the handler activates (ours OR vanilla/Fatshark), so
    -- the log shows the full active set. Cross-reference with the
    -- [event-inject] line: a name here that also appears there is
    -- event_tweaker's; one here WITHOUT a matching inject is the base game's.
    _dbg("[mutator-active] '%s' (server=%s)", tostring(name), tostring(self._is_server))
    return a, b
end)
mod:hook("MutatorHandler", "_deactivate_mutator", function(func, self, name, ...)
    local a, b = func(self, name, ...)
    if _CURSE_TO_GOD[name] then _refresh_active_curse_god() end
    return a, b
end)

-- Hot-join safety. A client joining MID-mission instantiates already-spawned
-- curse husks during game-object sync, which the engine performs BEFORE it
-- sends the mutator-activate RPC (peer_states.lua) — so the _activate_mutator
-- load above would arrive too late and World.spawn_unit on the unloaded
-- package would hard-crash the joiner. MutatorHandler.init already knows the
-- mutator list at construction (host: the `mutators` arg; client: the
-- network-synced _initialized_mutator_map, populated BEFORE game objects), so
-- preload here too — on every peer, ahead of any husk. Belt-and-suspenders
-- with the _activate_mutator load (normal-join + host).
mod:hook_safe("MutatorHandler", "init", function(self, mutators)
    local names = {}
    if type(mutators) == "table" then
        for i = 1, #mutators do names[mutators[i]] = true end
    end
    local map = self._initialized_mutator_map
    if type(map) == "table" then
        -- Shape is engine-internal; harvest any string key OR value as a
        -- candidate mutator name (name-keyed or id->name, both covered).
        for k, v in pairs(map) do
            if type(k) == "string" then names[k] = true end
            if type(v) == "string" then names[v] = true end
        end
    end
    for name in pairs(names) do
        if _MANAGED_CURSE[name] and ET.set_curse_session_requested then
            ET.set_curse_session_requested(true)
        end
        _maybe_preload_curse_package(name)
    end
end)

-- Balance the package ref-count + clear the cache on mission exit (per peer).
-- Only drop an entry whose unload actually succeeded (a pcall failure on a
-- divergent ref must keep the entry so it isn't orphaned / silently leaked).
mod:hook_safe("StateIngame", "on_exit", function(self)
    local pm = rawget(_G, "Managers") and Managers.package
    if pm then
        for pkg in pairs(_loaded_curse_packages) do
            if pcall(pm.unload, pm, pkg, ET_CURSE_PKG_REF) then
                _loaded_curse_packages[pkg] = nil
            end
        end
    end
    _active_curse_god = nil
    if ET.set_curse_session_active then ET.set_curse_session_active(false) end
end)

-- Per-god multiplicative sky/atmosphere tints (copied verbatim from
-- chaos_wastes_tweaker.lua:3247 _CURSE_SKY_PROFILES, user-tuned values).
local _CURSE_SKY_PROFILES = {
    khorne = {
        skydome_tint_color = {1.32, 0.51, 0.44}, sun_color = {1.21, 0.76, 0.62},
        secondary_sun_color = {1.14, 0.65, 0.58}, ambient_tint = {1.04, 0.69, 0.62},
        ambient_tint_top = {1.14, 0.58, 0.51}, fog_color = {1.39, 0.48, 0.44},
        exposure_mul = 0.95,
    },
    nurgle = {
        skydome_tint_color = {0.78, 1.05, 0.55}, sun_color = {1.05, 1.02, 0.65},
        secondary_sun_color = {0.92, 0.98, 0.66}, ambient_tint = {0.88, 0.95, 0.68},
        ambient_tint_top = {0.82, 1.00, 0.60}, fog_color = {0.80, 1.05, 0.55},
        exposure_mul = 1.00,
    },
    tzeentch = {
        skydome_tint_color = {0.62, 0.76, 1.35}, sun_color = {1.39, 0.72, 0.44},
        secondary_sun_color = {1.28, 0.79, 0.55}, ambient_tint = {1.25, 0.86, 0.58},
        ambient_tint_top = {1.32, 0.76, 0.48}, fog_color = {0.76, 0.83, 1.21},
        exposure_mul = 1.04,
    },
    slaanesh = {
        skydome_tint_color = {1.35, 0.50, 1.15}, sun_color = {1.30, 0.85, 0.95},
        secondary_sun_color = {1.20, 0.65, 1.05}, ambient_tint = {1.15, 0.65, 1.05},
        ambient_tint_top = {1.30, 0.55, 1.20}, fog_color = {1.25, 0.40, 1.10},
        exposure_mul = 0.97,
    },
    belakor = {
        skydome_tint_color = {0.40, 0.25, 0.65}, sun_color = {0.50, 0.50, 0.85},
        secondary_sun_color = {0.55, 0.50, 0.90}, ambient_tint = {0.75, 0.65, 1.00},
        ambient_tint_top = {0.60, 0.55, 1.00}, fog_color = {0.40, 0.30, 0.75},
        exposure_mul = 0.92,
    },
}

local function _cursed_lighting_on()
    return mod:get("cursed_lighting") ~= false  -- default ON
end

if rawget(_G, "CameraManager") and rawget(_G, "ShadingEnvironment") then
    mod:hook_safe("CameraManager", "shading_callback", function(self, world, shading_env, viewport)
        -- Vanilla wraps its whole body in `if self._world == world` — only
        -- touch the shading_env of the world this camera owns (UI / preview /
        -- end-screen worlds also drive shading_callback). Mirror it.
        if self._world ~= world then return end
        if not _active_curse_god or not _cursed_lighting_on() then return end
        if not _is_adventure_mechanism() then return end  -- leave real CW runs to ct
        local profile = _CURSE_SKY_PROFILES[_active_curse_god]
        if not profile then return end
        local function mul_set(var)
            local t = profile[var]
            if not t then return end
            local v = ShadingEnvironment.vector3(shading_env, var)
            if v then
                ShadingEnvironment.set_vector3(shading_env, var,
                    Vector3(v.x * t[1], v.y * t[2], v.z * t[3]))
            end
        end
        mul_set("skydome_tint_color"); mul_set("sun_color")
        mul_set("secondary_sun_color"); mul_set("ambient_tint")
        mul_set("ambient_tint_top"); mul_set("fog_color")
        if profile.exposure_mul and profile.exposure_mul ~= 1.0 then
            local cur = ShadingEnvironment.scalar(shading_env, "exposure")
            if cur then
                ShadingEnvironment.set_scalar(shading_env, "exposure", cur * profile.exposure_mul)
            end
        end
    end)
end
