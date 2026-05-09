local mod = get_mod("event_tweaker")

local MOD_VERSION = "0.3.0-dev"
mod:info("Tweaker: Events v%s loaded", MOD_VERSION)
mod:echo("Tweaker: Events v" .. MOD_VERSION)

-- ============================================================
-- Mutator catalog (kept in sync with event_tweaker_data.lua's copy)
-- ============================================================
-- Names match NetworkLookup.mutator_templates entries registered
-- year-round via DLCUtils.append("mutators") in mutator_settings.lua
-- plus DLC common settings (mutators_batch_01/02/04, geheimnisnacht_2021,
-- skulls_2023). NB: keep this list in sync with event_tweaker_data.lua
-- — both iterate over it. (No cross-file require because VMF mod-script /
-- mod-data load order isn't documented and the sibling tweaker mods all
-- keep state file-local.)
local MUTATOR_CATALOG = {
    { id = "cat_difficulty", mutators = {
        "no_ammo", "no_pickups", "player_dot", "instant_death",
        "no_respawn", "elite_run", "shared_health_pool",
        "whiterun", "realism",
    }},
    { id = "cat_specials", mutators = {
        "specials_frequency", "more_specials", "same_specials",
        "big_specials", "elite_specials", "gutter_runner_mayhem",
        "chaos_warriors_trickle", "mixed_horde", "multiple_bosses",
        "hordes_galore", "powerful_elites", "skulking_sorcerer",
    }},
    { id = "cat_hordes", mutators = {
        "wave_of_plague_monks", "wave_of_berzerkers", "high_intensity",
        "splitting_enemies", "explosive_loot_rats", "bloodlust",
    }},
    { id = "cat_atmosphere", mutators = {
        "night_mode", "darkness", "ticking_bomb",
        "flames", "lightning_strike", "chasing_spirits",
    }},
    { id = "cat_objectives", mutators = { "escort", "slayer_curse", "leash" }},
    { id = "cat_winds", mutators = {
        "life", "metal", "heavens", "light",
        "shadow", "fire", "death", "beasts",
    }},
    { id = "cat_events", mutators = {
        "geheimnisnacht_2021", "geheimnisnacht_2021_hard_mode",
        "skulls_2023",
    }},
}

-- ============================================================
-- Event presets
-- ============================================================
-- A preset bundles two pieces of fabricated live-event state:
--   active_events  -- list of event-name strings; some mutator
--                     server_start_function calls do string.find
--                     against these. mutator_geheimnisnacht_2021
--                     uses this to decide which 5 maps spawn
--                     ritual sites (see scripts/settings/dlcs/
--                     geheimnisnacht_2025/geheimnisnacht_utils.lua).
--   mutators       -- name strings to inject into the lobby's
--                     mutator list via append_live_event_mutators.
-- skulls_2023's mutator does NOT inspect active_events — it spawns
-- skull pickups unconditionally inside its own server_start_function.
-- We still set active_events for completeness / future-proofing.
local EVENT_PRESETS = {
    geheimnisnacht_2021 = {
        active_events = { "geheimnisnacht_2021" },
        mutators      = { "geheimnisnacht_2021" },
        -- Pre-baked decorated keep level loaded by AdventureMechanism on startup.
        -- Names confirmed in scripts/settings/level_settings.lua: inn_level_halloween,
        -- inn_level_skulls, inn_level_celebrate, inn_level_sonnstill.
        hub_level = "inn_level_halloween",
    },
    geheimnisnacht_2025 = {
        active_events = { "geheimnisnacht_2025" },
        mutators      = { "geheimnisnacht_2021" },
        hub_level     = "inn_level_halloween",
    },
    skulls_2023 = {
        active_events = { "skulls_2023" },
        mutators      = { "skulls_2023" },
        hub_level     = "inn_level_skulls",
    },
}

-- ============================================================
-- Selection accumulators
-- ============================================================

local function active_preset()
    local pick = mod:get("event_preset")
    if not pick or pick == "off" then
        return nil
    end
    return EVENT_PRESETS[pick]
end

-- Walks MUTATOR_CATALOG and returns a flat list of mutator names
-- whose individual checkboxes are on.
local function selected_individual_mutators()
    local out = {}
    for ci = 1, #MUTATOR_CATALOG do
        local cat = MUTATOR_CATALOG[ci]
        for mi = 1, #cat.mutators do
            local id = cat.mutators[mi]
            if mod:get("mut_" .. id) then
                out[#out + 1] = id
            end
        end
    end
    return out
end

-- Combine preset mutators + individual checkbox mutators, deduped.
local function gather_mutators()
    local seen = {}
    local out = {}
    local function add(name)
        if not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end

    local preset = active_preset()
    if preset and preset.mutators then
        for i = 1, #preset.mutators do
            add(preset.mutators[i])
        end
    end

    local individual = selected_individual_mutators()
    for i = 1, #individual do
        add(individual[i])
    end

    return out
end

local function gather_active_events()
    local preset = active_preset()
    if not preset or not preset.active_events then
        return nil
    end
    return preset.active_events
end

-- ============================================================
-- List merge helper
-- ============================================================

local function merge_lists(original, extra)
    if not extra or #extra == 0 then
        return original
    end
    if not original or #original == 0 then
        return extra
    end
    local merged = table.clone(original)
    for i = 1, #extra do
        merged[#merged + 1] = extra[i]
    end
    return merged
end

-- ============================================================
-- Hooks
-- ============================================================
-- Both functions live on BackendInterfaceLiveEventsPlayfab. There is
-- only one interface implementation (no derived classes), so the
-- string-form mod:hook patches the prototype that all instances see
-- through __index lookup.
--
-- get_special_events feeds GameModeBase.append_live_event_mutators
-- (game_mode_base.lua:264) AND DialogueSystem.on_add_extension at
-- dialogue_system.lua:196-212. The dialogue system reads
-- `event_data.name` and uses it as a key in `_global_context`, so
-- the injected entry MUST include a non-nil string `name` or the
-- game crashes on startup ("table index is nil").

mod:hook("BackendInterfaceLiveEventsPlayfab", "get_special_events", function (func, self)
    local original = func(self)
    local mutators = gather_mutators()
    if #mutators == 0 then
        return original
    end
    -- Use the preset name if one is selected (matches the active_events
    -- string), else a synthetic identifier. Either way it must be a
    -- string — see comment above.
    local preset_pick = mod:get("event_preset")
    local injected_name = (preset_pick and preset_pick ~= "off")
        and preset_pick
        or "event_tweaker_custom"
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
    local extra = gather_active_events()
    if not extra then
        return original
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
    if not preset or not preset.hub_level then
        return original
    end
    -- Don't mutate the original — it's possibly the cached EMPTY_TABLE.
    local merged = table.clone(original)
    merged.hub_level = preset.hub_level
    return merged
end)

-- ============================================================
-- Diagnostic commands
-- ============================================================

local function dump_list(label, list)
    if not list or #list == 0 then
        mod:echo("[event] %s: <empty>", label)
        return
    end
    for i = 1, #list do
        local v = list[i]
        if type(v) == "table" then
            local muts = v.mutators and table.concat(v.mutators, ",") or ""
            local lvls = v.level_keys and table.concat(v.level_keys, ",") or "all"
            mod:echo("[event] %s[%d]: weekly_event=%s mutators={%s} levels={%s}",
                label, i, tostring(v.weekly_event), muts, lvls)
        else
            mod:echo("[event] %s[%d]: %s", label, i, tostring(v))
        end
    end
end

mod:command("event_probe", "Dump live-event state from the host's backend interface", function()
    local interface = Managers.backend and Managers.backend:get_interface("live_events")
    if not interface then
        mod:echo("[event] no live_events interface yet")
        return
    end
    dump_list("active_events", interface:get_active_events())
    dump_list("special_events", interface:get_special_events())
    dump_list("weekly_events", interface:get_weekly_events())
    mod:echo("[event] preset: %s", tostring(mod:get("event_preset")))
    local muts = gather_mutators()
    mod:echo("[event] would-inject mutators: {%s}", table.concat(muts, ","))
end)

mod:command("event_active", "List currently-active mutators in the loaded game mode", function()
    local game_mode = Managers.state and Managers.state.game_mode
    local handler = game_mode and game_mode._mutator_handler
    if not handler then
        mod:echo("[event] no mutator_handler (not in a level?)")
        return
    end
    local active = handler:activated_mutators()
    local n = 0
    for name, _ in pairs(active) do
        n = n + 1
        mod:echo("[event] active mutator: %s", name)
    end
    if n == 0 then
        mod:echo("[event] no active mutators")
    end
end)

mod:command("event_clear", "Uncheck every individual mutator (preset untouched)", function()
    local n = 0
    for ci = 1, #MUTATOR_CATALOG do
        local cat = MUTATOR_CATALOG[ci]
        for mi = 1, #cat.mutators do
            local id = cat.mutators[mi]
            if mod:get("mut_" .. id) then
                mod:set("mut_" .. id, false, false)
                n = n + 1
            end
        end
    end
    mod:echo("[event] cleared %d mutators", n)
end)
