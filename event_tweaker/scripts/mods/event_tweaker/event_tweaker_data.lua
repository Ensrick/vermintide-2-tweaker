local mod = get_mod("event_tweaker")
-- Shared curse catalog. require'd (NOT read off a mod._field) because VMF loads
-- this data file BEFORE the .lua script — a script-set mod._field would be nil
-- here. See event_tweaker_curses.lua's header.
local Curses = require("scripts/mods/event_tweaker/event_tweaker_curses")

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

-- ============================================================
-- DLC ownership gate (UI polish)
-- ============================================================
-- Mirrors DLC_BY_MUTATOR / DLC_BY_PRESET in event_tweaker.lua. The
-- load-bearing gate lives at the injection hooks; this is purely UI
-- cleanup so the host doesn't see checkbox / dropdown options for
-- content they don't own. Failing closed (un-owned -> hidden) matches
-- vanilla store-page behavior for missing DLC.
-- DLC IDs cited in event_tweaker.lua (DLCSettings entries:
-- dlc_settings.lua:274, :576, :287).
local DLC_BY_MUTATOR_UI = {
    geheimnisnacht_2021             = "geheimnisnacht_2021",
    geheimnisnacht_2021_hard_mode   = "geheimnisnacht_2021",
    skulls_2023                     = "skulls_2023",
}

local DLC_BY_PRESET_UI = {
    geheimnisnacht_2021 = "geheimnisnacht_2021",
    geheimnisnacht_2025 = "geheimnisnacht_2025",
    geheimnisnacht_2026 = "geheimnisnacht_2026",
    skulls_2023         = "skulls_2023",
    skulls_2026         = "skulls_2026",
}

local function ui_owns_dlc(dlc_id)
    if not dlc_id then
        return true
    end
    local um = rawget(_G, "Managers") and Managers.unlock
    if not um then
        -- Mod-data is evaluated very early in VMF init; if the unlock
        -- manager isn't up yet, show the widget. The injection-site
        -- gate in event_tweaker.lua is the load-bearing one and will
        -- still drop un-owned content there.
        return true
    end
    if um.dlc_exists and not um:dlc_exists(dlc_id) then
        return false
    end
    return um:is_dlc_unlocked(dlc_id)
end

local function build_mutator_widgets(mutators)
    local widgets = {}
    for i = 1, #mutators do
        local id = mutators[i]
        local dlc = rawget(DLC_BY_MUTATOR_UI, id)
        if ui_owns_dlc(dlc) then
            widgets[#widgets + 1] = {
                setting_id    = "mut_" .. id,
                type          = "checkbox",
                default_value = false,
                tooltip       = "mut_" .. id .. "_tooltip",
            }
        end
    end
    return widgets
end

local PRESET_OPTIONS = {
    { text = "preset_off",                 value = "off" },
    { text = "preset_geheimnisnacht_2021", value = "geheimnisnacht_2021" },
    { text = "preset_geheimnisnacht_2025", value = "geheimnisnacht_2025" },
    { text = "preset_geheimnisnacht_2026", value = "geheimnisnacht_2026" },
    { text = "preset_skulls_2023",         value = "skulls_2023" },
    { text = "preset_skulls_2026",         value = "skulls_2026" },
}

local function filtered_preset_options()
    local out = {}
    for i = 1, #PRESET_OPTIONS do
        local opt = PRESET_OPTIONS[i]
        local dlc = rawget(DLC_BY_PRESET_UI, opt.value)
        if ui_owns_dlc(dlc) then
            out[#out + 1] = opt
        end
    end
    return out
end

local widgets = {
    {
        setting_id    = "event_preset",
        type          = "dropdown",
        default_value = "off",
        tooltip       = "event_preset_tooltip",
        options       = filtered_preset_options(),
    },
    -- v0.4.10-dev: opt-in switch that flips the three live-event hooks from
    -- additive (pass Fatshark's events through, append ours) to subtractive
    -- (drop Fatshark's first, then append ours). Lets the host neutralize
    -- the currently-live Fatshark event without waiting it out.
    -- Defaults off so prior pass-through behavior survives the upgrade.
    {
        setting_id    = "suppress_live_event",
        type          = "checkbox",
        default_value = false,
        tooltip       = "suppress_live_event_tooltip",
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

-- ============================================================
-- "Other Mutators" group — dynamic discovery
-- (ported from "Deed Mutators Selector", Workshop 3579882542)
-- ============================================================
-- Walk the live MutatorTemplates global and surface every registered mutator
-- the engine flags player-facing (display_name + description) that ISN'T in a
-- curated category, ISN'T package-bearing (those go in Cursed Adventure), ISN'T
-- a Fatshark-hidden internal (hide_from_player_ui), and ISN'T a known
-- adventure-crasher (mod._ET_CURSE_BROKEN — keep in lockstep with
-- _is_adventure_safe_mutator in event_tweaker.lua). Labels come from the game's
-- own localized strings, registered dynamically in event_tweaker_localization.
do
    local curated = {}
    for i = 1, #CATEGORIES do
        for j = 1, #CATEGORIES[i].mutators do
            curated[CATEGORIES[i].mutators[j]] = true
        end
    end
    local broken = Curses.BROKEN_IN_ADVENTURE
    local MT = rawget(_G, "MutatorTemplates")
    if MT then
        local extra = {}
        for name, tmpl in pairs(MT) do
            if not curated[name] and not broken[name] and type(tmpl) == "table"
               and tmpl.display_name and tmpl.description
               and not tmpl.hide_from_player_ui
               and not (tmpl.packages and next(tmpl.packages)) then
                extra[#extra + 1] = name
            end
        end
        table.sort(extra)
        local sub = {}
        for i = 1, #extra do
            sub[#sub + 1] = {
                setting_id    = "mut_" .. extra[i],
                type          = "checkbox",
                default_value = false,
                tooltip       = "mut_" .. extra[i] .. "_tooltip",
            }
        end
        if #sub > 0 then
            widgets[#widgets + 1] = { setting_id = "cat_other", type = "group", sub_widgets = sub }
        end
    end
end

-- ============================================================
-- "Cursed Adventure" group — Chaos Wastes / Be'lakor curses
-- ============================================================
-- Hand-curated, package-bearing curses surfaced via mod._ET_MANAGED_CURSES
-- (set in event_tweaker.lua). Activating one preloads its resource package on
-- every peer + applies the cursed-sky tint. ⚠ Unlike the rest of the mod,
-- these require EVERY player in the lobby to run event_tweaker (clients need
-- the package for replicated curse units). The `cursed_lighting` toggle leads
-- the group.
do
    local managed = Curses.MANAGED_CURSES
    if type(managed) == "table" and #managed > 0 then
        local sub = {
            { setting_id = "cursed_lighting", type = "checkbox", default_value = true,
              tooltip = "cursed_lighting_tooltip" },
        }
        for i = 1, #managed do
            local c = managed[i]
            local dlc = rawget(DLC_BY_MUTATOR_UI, c.id)  -- usually nil (CW/Be'lakor are free)
            if ui_owns_dlc(dlc) then
                sub[#sub + 1] = {
                    setting_id    = "mut_" .. c.id,
                    type          = "checkbox",
                    default_value = false,
                    tooltip       = "mut_" .. c.id .. "_tooltip",
                }
            end
        end
        widgets[#widgets + 1] = { setting_id = "cat_cursed", type = "group", sub_widgets = sub }
    end
end

return {
    name = "Tweaker: Events",
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = { widgets = widgets },
}
