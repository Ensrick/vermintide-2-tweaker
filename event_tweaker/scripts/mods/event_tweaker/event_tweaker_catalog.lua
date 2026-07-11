-- ============================================================
-- event_tweaker — shared mutator / preset / DLC-gate catalog
-- ============================================================
-- Single source of truth for the curated mutator catalog, the event presets,
-- and the DLC-gating maps. required by BOTH the script-side modules AND
-- event_tweaker_data.lua.
--
-- WHY A SHARED require()'d MODULE (not a mod._field, and not two copies):
--   VMF loads a mod's files in the order localization -> data -> script (the
--   mod_script runs LAST), so anything the script assigns to mod._X is nil
--   when _data.lua evaluates. A module pulled in via require() is evaluated
--   once (by whichever file gets there first) and cached, so every file sees
--   the same tables regardless of load order. Same pattern as
--   event_tweaker_curses.lua (see its header for the burn history).
--   Before v0.4.26-dev the catalog lived as TWO hand-synced copies
--   (MUTATOR_CATALOG in the script, CATEGORIES in the data file), each with a
--   "keep in sync" warning; this module retires that failure mode.

local M = {}

-- ============================================================
-- Curated mutator catalog
-- ============================================================
-- Each entry's mutator name is the literal string registered in
-- NetworkLookup.mutator_templates (see scripts/settings/mutators/
-- mutator_<name>.lua in the unpacked source). All names listed here are
-- confirmed present year-round via DLCUtils.append("mutators") in
-- scripts/settings/mutator_settings.lua plus the various DLC
-- *_common_settings.lua files (mutators_batch_01/02/04, geheimnisnacht_2021,
-- skulls_2023). Vanilla clients have these in their lookup table too, so the
-- mutator-activate RPC works without modded clients.
M.CATEGORIES = {
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
M.EVENT_PRESETS = {
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
    -- 2026 = same mutator + hub as prior years; only the active_events
    -- string differs (drives the year's 5-map list in geheimnisnacht_
    -- utils.lua:43-49: farmlands, dlc_wizards_tower, catacombs, bell,
    -- ussingen). Added v0.4.11-dev once Fatshark shipped the 2026 maps.
    geheimnisnacht_2026 = {
        active_events = { "geheimnisnacht_2026" },
        mutators      = { "geheimnisnacht_2021" },
        hub_level     = "inn_level_halloween",
    },
    skulls_2023 = {
        active_events = { "skulls_2023" },
        mutators      = { "skulls_2023" },
        hub_level     = "inn_level_skulls",
    },
    -- skulls_2026: vanilla skulls mutator is unchanged (no mutator_
    -- skulls_2026 file in source — Fatshark only added cosmetics +
    -- portraits for 2026, not new gameplay). active_events string set
    -- for consistency; the skulls mutator is self-contained and doesn't
    -- inspect active_events.
    skulls_2026 = {
        active_events = { "skulls_2026" },
        mutators      = { "skulls_2023" },
        hub_level     = "inn_level_skulls",
    },
}

-- ============================================================
-- DLC-gate maps
-- ============================================================
-- DLC IDs taken from DLCSettings in
-- scripts/settings/dlc_settings.lua:274 (geheimnisnacht_2021),
-- :576 (geheimnisnacht_2025), :287 (skulls_2023), :597 (skulls_2026),
-- :606 (geheimnisnacht_2026). Consumed by TWO deliberately different
-- ownership predicates: the injection-side gate in _evt_dlc.lua (fails
-- CLOSED when Managers.unlock isn't up) and the UI-side gate in
-- event_tweaker_data.lua (fails OPEN — data evaluates very early in VMF
-- init, and the injection gate is the load-bearing one).
M.DLC_BY_MUTATOR = {
    geheimnisnacht_2021             = "geheimnisnacht_2021",
    geheimnisnacht_2021_hard_mode   = "geheimnisnacht_2021",
    skulls_2023                     = "skulls_2023",
}

M.DLC_BY_PRESET = {
    geheimnisnacht_2021 = "geheimnisnacht_2021",
    -- 2025 / 2026 presets inject the 2021 mutator and the year-specific
    -- active_events string (the ritual-site engine keys off it via
    -- string.find in geheimnisnacht_utils.lua:103). Both DLCs need to
    -- be owned for the preset to do anything useful; gate on the
    -- seasonal-content DLC (geheimnisnacht_<year>).
    geheimnisnacht_2025 = "geheimnisnacht_2025",
    geheimnisnacht_2026 = "geheimnisnacht_2026",
    skulls_2023         = "skulls_2023",
    skulls_2026         = "skulls_2026",
}

return M
