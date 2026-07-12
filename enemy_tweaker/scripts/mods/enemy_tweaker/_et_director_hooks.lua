local mod = get_mod("enemy_tweaker")

-- _et_director_hooks.lua — ConflictDirector init/refresh re-apply chain
--
-- The two hooks that (re)apply every spawn-side mutation whenever the engine
-- (re)builds its Current* settings tables: mission load (init) and zone
-- boundary / mid-mission director switch (refresh_conflict_director_patches).
-- Order inside each hook is load-bearing: difficulty mimic REPLACES the
-- Current* tables, then faction-swap / horde-size mutate the fresh tables in
-- place — reversing them silently drops the swap.
--
-- Owned by: enemy_tweaker.lua entry point (dofile'd after every provider it
-- consumes: _et_horde_presets, _et_swaps, _et_mimic, _et_roaming,
-- _et_champion_warlord). Exposes mod._et_last_refresh_at / _trigger for
-- /et_verify_refresh (issue #18).

local ET = mod._et
local _spawn_dbg = ET.spawn_dbg
local _hook_wrap = ET.hook_wrap
local _mult      = ET.mult

local _backup_compositions   = ET.backup_compositions
local _restore_compositions  = ET.restore_compositions
local _apply_horde_preset    = ET.apply_horde_preset
local _apply_horde_size_to_current_horde_settings = ET.apply_horde_size_to_chs
local _apply_roaming_size_multiplier = ET.apply_roaming_size_multiplier
local _build_swap_map        = ET.build_swap_map
local _build_faction_swap_map = ET.build_faction_swap_map
local _apply_faction_swap_to_current_horde_settings = ET.apply_faction_swap_to_chs
local _apply_champion_breed_overrides = ET.apply_champion_breed_overrides
local _apply_difficulty_mimic = ET.apply_difficulty_mimic

_hook_wrap("ConflictDirector", "init", "ConflictDirector.init", function(func, self, ...)
    local result = func(self, ...)

    _backup_compositions()
    _restore_compositions()
    _apply_horde_preset()
    _apply_roaming_size_multiplier()
    _build_swap_map()
    _build_faction_swap_map()
    _apply_champion_breed_overrides()                                            -- v0.7.18-dev: Champion elite-pool stat retune (idempotent)
    _apply_difficulty_mimic(self)
    _apply_faction_swap_to_current_horde_settings()
    _apply_horde_size_to_current_horde_settings()                                -- v0.7.9-dev: scale the live clone

    local horde_mult,   _   = _mult("horde_size_multiplier")
    local event_mult,   _e  = _mult("event_size_multiplier")
    local roaming_mult, _r  = _mult("roaming_size_multiplier")
    local patrol_mult,  _p  = _mult("patrol_size_multiplier")
    mod:info("[et:init] compositions applied (preset=%s horde=%.1f event=%.1f roaming=%.1f patrol=%.1f)",
        tostring(mod:get("horde_preset")), horde_mult, event_mult, roaming_mult, patrol_mult)
    _spawn_dbg("init", "ConflictDirector.init complete: cd=%s",
        tostring(self and self.current_conflict_settings))
    return result
end)

-- refresh_conflict_director_patches runs whenever the active conflict
-- director changes (zone boundary override, mid-mission switches). It
-- rebuilds CurrentHordeSettings via table.clone(director.horde), so any
-- faction-swap rewrites from a previous CD are lost — re-apply after.
-- Order: difficulty mimic first (replaces Current* tables), then faction-swap
-- (mutates CurrentHordeSettings in place).
-- Issue #18: log applied-reason so /et_verify_refresh and post-mortems can
-- see what drove each reseed (engine = zone-boundary native, on_enabled =
-- our toggle-back-on path, on_setting_changed:<id> = mid-session VMF edit).
mod._et_last_refresh_at      = nil
mod._et_last_refresh_trigger = nil
_hook_wrap("ConflictDirector", "refresh_conflict_director_patches",
        "refresh_conflict_director_patches", function(func, self, ...)
    local trigger = (...)
    if type(trigger) ~= "string" then trigger = "engine" end
    func(self, ...)
    _apply_difficulty_mimic(self)
    _apply_faction_swap_to_current_horde_settings()
    _apply_horde_size_to_current_horde_settings()                                -- v0.7.9-dev: re-scale freshly-cloned CHS
    -- v0.6.0-dev: re-apply roaming size on every CD refresh too. Without
    -- this the mid-mission zone-boundary CD switch (Athel Yenlui etc.)
    -- would revert SizeOfInterestPoint to vanilla until the next mission.
    _apply_roaming_size_multiplier()
    mod._et_last_refresh_at      = os.time()
    mod._et_last_refresh_trigger = trigger
    mod:info("[et:refresh] applied (trigger=%s cd=%s)", trigger,
        tostring(self and self.current_conflict_settings))
    _spawn_dbg("refresh", "refresh_conflict_director_patches trigger=%s", trigger)
end)
