local mod = get_mod("event_tweaker")

-- ============================================================
-- Mutator catalog (kept in sync with event_tweaker.lua's copy)
-- ============================================================
-- Each entry's mutator name is the literal string registered in
-- NetworkLookup.mutator_templates (see scripts/settings/mutators/
-- mutator_<name>.lua in the unpacked source). All names listed
-- here are confirmed present year-round via DLCUtils.append("mutators")
-- in scripts/settings/mutator_settings.lua plus the various DLC
-- *_common_settings.lua files. Vanilla clients have these in their
-- lookup table too, so the mutator-activate RPC works without modded
-- clients. NB: keep this list in sync with event_tweaker.lua's
-- MUTATOR_CATALOG — both files iterate over it.
local CATEGORIES = {
    {
        id = "cat_difficulty",
        mutators = {
            "no_ammo", "no_pickups", "player_dot", "instant_death",
            "no_respawn", "elite_run", "shared_health_pool",
            "whiterun", "realism",
        },
    },
    {
        id = "cat_specials",
        mutators = {
            "specials_frequency", "more_specials", "same_specials",
            "big_specials", "elite_specials", "gutter_runner_mayhem",
            "chaos_warriors_trickle", "mixed_horde", "multiple_bosses",
            "hordes_galore", "powerful_elites", "skulking_sorcerer",
        },
    },
    {
        id = "cat_hordes",
        mutators = {
            "wave_of_plague_monks", "wave_of_berzerkers", "high_intensity",
            "splitting_enemies", "explosive_loot_rats", "bloodlust",
        },
    },
    {
        id = "cat_atmosphere",
        mutators = {
            "night_mode", "darkness", "ticking_bomb",
            "flames", "lightning_strike", "chasing_spirits",
        },
    },
    {
        id = "cat_objectives",
        mutators = { "escort", "slayer_curse", "leash" },
    },
    {
        id = "cat_winds",
        mutators = {
            "life", "metal", "heavens", "light",
            "shadow", "fire", "death", "beasts",
        },
    },
    {
        id = "cat_events",
        mutators = {
            "geheimnisnacht_2021", "geheimnisnacht_2021_hard_mode",
            "skulls_2023",
        },
    },
}

local function build_mutator_widgets(mutators)
    local widgets = {}
    for i = 1, #mutators do
        local id = mutators[i]
        widgets[#widgets + 1] = {
            setting_id    = "mut_" .. id,
            type          = "checkbox",
            default_value = false,
            tooltip       = mod:localize("mut_" .. id .. "_tooltip"),
        }
    end
    return widgets
end

local widgets = {
    {
        setting_id    = "event_preset",
        type          = "dropdown",
        default_value = "off",
        tooltip       = mod:localize("event_preset_tooltip"),
        options = {
            { text = mod:localize("preset_off"),                 value = "off" },
            { text = mod:localize("preset_geheimnisnacht_2021"), value = "geheimnisnacht_2021" },
            { text = mod:localize("preset_geheimnisnacht_2025"), value = "geheimnisnacht_2025" },
            { text = mod:localize("preset_skulls_2023"),         value = "skulls_2023" },
        },
    },
}

for i = 1, #CATEGORIES do
    local cat = CATEGORIES[i]
    widgets[#widgets + 1] = {
        setting_id  = cat.id,
        type        = "group",
        sub_widgets = build_mutator_widgets(cat.mutators),
    }
end

return {
    name = "Tweaker: Events",
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = { widgets = widgets },
}
