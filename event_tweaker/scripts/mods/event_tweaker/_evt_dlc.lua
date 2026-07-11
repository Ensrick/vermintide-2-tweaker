local mod = get_mod("event_tweaker")

-- _evt_dlc.lua — DLC ownership gate (injection side, fail-closed)
--
-- Modded mods may unlock vanilla progression but must NOT bypass paid DLC
-- paywalls. Mutators / presets that ship as DLC are gated at the injection
-- sites so the lobby never receives content the host doesn't own. (The
-- vanilla level-load path refuses to load the map anyway; without this gate,
-- picking a DLC preset you don't own produces a confusing failure instead of
-- a clean "not owned" no-op.) Vanilla gate pattern:
-- Managers.unlock:is_dlc_unlocked(dlc_id), pre-checked with dlc_exists so an
-- unknown id doesn't trip the fassert in UnlockManager.is_dlc_unlocked
-- (unlock_manager.lua:527). The DLC-id maps live in event_tweaker_catalog.lua
-- (shared with the data file's fail-OPEN UI-side twin, ui_owns_dlc — the
-- divergent nil-Managers fallback there is deliberate; see the catalog header).
--
-- Owned by: event_tweaker.lua entry point (dofile'd before _evt_selection).
-- Consumed via mod._evt exports: owns_dlc, mutator_allowed, preset_allowed.

local ET = mod._evt

local Catalog        = require("scripts/mods/event_tweaker/event_tweaker_catalog")
local DLC_BY_MUTATOR = Catalog.DLC_BY_MUTATOR
local DLC_BY_PRESET  = Catalog.DLC_BY_PRESET

local function owns_dlc(dlc_id)
    if not dlc_id then
        return true
    end
    local um = rawget(_G, "Managers") and Managers.unlock
    if not um then
        -- Unlock manager not constructed yet. Fail closed: if we can't
        -- verify ownership, don't inject. Hooks rerun on every level
        -- load, so once Managers.unlock exists the gate evaluates normally.
        return false
    end
    if um.dlc_exists and not um:dlc_exists(dlc_id) then
        return false
    end
    return um:is_dlc_unlocked(dlc_id)
end

local function mutator_allowed(mutator_id)
    local dlc = rawget(DLC_BY_MUTATOR, mutator_id)
    return owns_dlc(dlc)
end

local function preset_allowed(preset_id)
    local dlc = rawget(DLC_BY_PRESET, preset_id)
    return owns_dlc(dlc)
end

ET.owns_dlc = owns_dlc
ET.mutator_allowed = mutator_allowed
ET.preset_allowed = preset_allowed
