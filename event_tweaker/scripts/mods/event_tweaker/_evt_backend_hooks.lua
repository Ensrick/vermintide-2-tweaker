local mod = get_mod("event_tweaker")

-- _evt_backend_hooks.lua — the three live-event backend hooks
--
-- The mod's whole injection surface: get_special_events / get_active_events on
-- BackendInterfaceLiveEventsPlayfab and get_level_variation_data on
-- BackendManagerPlayFab. All three are consulted at level-load time only
-- (mid-load changes are handled by _evt_apply.lua's level reload). Both
-- live-events functions live on BackendInterfaceLiveEventsPlayfab; there is
-- only one interface implementation (no derived classes), so the string-form
-- mod:hook patches the prototype that all instances see through __index lookup.
--
-- get_special_events feeds GameModeBase.append_live_event_mutators
-- (game_mode_base.lua:264) AND DialogueSystem.on_add_extension at
-- dialogue_system.lua:196-212. The dialogue system reads `event_data.name`
-- and uses it as a key in `_global_context`, so the injected entry MUST
-- include a non-nil string `name` or the game crashes on startup ("table
-- index is nil") — checklist slug special-events-name-required.
--
-- Owned by: event_tweaker.lua entry point (dofile'd after _evt_selection).
-- Consumes mod._evt: gather_mutators, gather_active_events,
-- suppress_live_event, merge_lists, active_preset.

local ET = mod._evt

local active_preset       = ET.active_preset
local gather_mutators     = ET.gather_mutators
local gather_active_events = ET.gather_active_events
local suppress_live_event = ET.suppress_live_event
local merge_lists         = ET.merge_lists

mod:hook("BackendInterfaceLiveEventsPlayfab", "get_special_events", function (func, self)
    local original = func(self)
    local suppress = suppress_live_event()
    -- Suppress wins over Fatshark's list: drop their entries entirely so
    -- append_live_event_mutators sees only ours. Defense-in-depth — also
    -- short-circuits the DialogueSystem read path so no Fatshark event
    -- ambient dialogue plays.
    if suppress then
        original = nil
    end
    local mutators = gather_mutators()
    if #mutators == 0 then
        -- Original is either Fatshark's list (suppress off) or nil
        -- (suppress on with no injection of our own). Log the pass-through so
        -- the log unambiguously shows event_tweaker injected NOTHING and what
        -- (if anything) Fatshark is serving — distinguishes "ET caused it" from
        -- "a real live event" when debugging.
        local orig = {}
        if type(original) == "table" then
            for i = 1, #original do
                local e = original[i]
                orig[i] = (type(e) == "table" and tostring(e.name)) or tostring(e)
            end
        end
        mod:debug("[event-inject] injecting NOTHING (no preset/mutator/curse selected); suppress=%s; Fatshark special_events pass-through=[%s]",
            tostring(suppress), table.concat(orig, ","))
        return original or {}
    end
    -- Use the preset name if one is selected (matches the active_events
    -- string), else a synthetic identifier. Either way it must be a
    -- string — see comment above.
    local preset_pick = mod:get("event_preset")
    local injected_name = (preset_pick and preset_pick ~= "off")
        and preset_pick
        or "event_tweaker_custom"
    -- v0.4.2 defensive logging: log every injected mutator + the preset name.
    -- Helps diagnose unexpected mutator interactions (e.g. "Horn of Magnus had
    -- no pickups" → was a special_event injection accidentally appending an
    -- incompatible mutator?). Fires once per get_special_events call, which
    -- happens on mission load + keep transitions. v0.4.10-dev added the
    -- `suppress=` field so leak-through is verifiable from the log.
    mod:info("[event-inject] preset=%s suppress=%s injecting %d mutator(s): [%s]",
        tostring(injected_name), tostring(suppress), #mutators, table.concat(mutators, ","))
    local injected = {
        {
            name         = injected_name,
            weekly_event = "append",
            mutators     = mutators,
        },
    }
    return merge_lists(original, injected)
end)

mod:hook("BackendInterfaceLiveEventsPlayfab", "get_active_events", function (func, self)
    local original = func(self)
    if suppress_live_event() then
        -- Drop Fatshark's strings so mutator_geheimnisnacht_2021's
        -- `string.find(live_event, "geheimnisnacht_%d+")` ritual-site
        -- lookup (geheimnisnacht_2025/geheimnisnacht_utils.lua) gets
        -- no match and the ritual-site engine stays dormant.
        original = nil
    end
    local extra = gather_active_events()
    if not extra then
        return original or {}
    end
    return merge_lists(original, extra)
end)

-- Hub decoration. Vanilla Geheimnisnacht / Skulls / Anniversary decorate the
-- keep by swapping the entire keep level file (inn_level_halloween,
-- inn_level_skulls, etc.) — the decorations are baked geometry, not runtime
-- spawns. The active level is decided by AdventureMechanism.get_starting_level
-- (adventure_mechanism.lua:625), which reads
-- `Managers.backend:get_level_variation_data().hub_level`. Hook that single
-- entry point so every consumer (StateIngame's keep flow events, interactions,
-- carousel) sees the override consistently.
--
-- Timing caveat: get_starting_level is queried at game launch and on each
-- keep-load. Changing the preset after the keep is already loaded won't swap
-- the keep — the user has to either restart the game OR start a mission and
-- return.
mod:hook("BackendManagerPlayFab", "get_level_variation_data", function (func, self)
    local original = func(self) or {}
    local preset = active_preset()
    local want_hub
    if preset and preset.hub_level then
        want_hub = preset.hub_level
    elseif suppress_live_event() then
        -- v0.4.10-dev: when suppress is on with no preset, pin keep to the
        -- vanilla default (adventure_mechanism.lua:7 HUB_LEVEL_NAME).
        -- adventure_mechanism's get_starting_level (line 627) reads our
        -- merged.hub_level instead of Fatshark's seasonal one, so the keep
        -- decoration reverts cleanly.
        want_hub = "inn_level"
    end
    if not want_hub then
        return original
    end
    -- Don't mutate the original — it's possibly the cached EMPTY_TABLE.
    local merged = table.clone(original)
    merged.hub_level = want_hub
    return merged
end)
