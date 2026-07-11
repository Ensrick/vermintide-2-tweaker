local mod = get_mod("event_tweaker")
-- Shared curse + mutator/preset/DLC catalogs. require'd (NOT read off a
-- mod._field) because VMF loads this data file BEFORE the .lua script — a
-- script-set mod._field would be nil here. See the headers of
-- event_tweaker_curses.lua and event_tweaker_catalog.lua.
local Curses  = require("scripts/mods/event_tweaker/event_tweaker_curses")
local Catalog = require("scripts/mods/event_tweaker/event_tweaker_catalog")

-- Curated mutator catalog — the single shared copy in event_tweaker_catalog.lua
-- (v0.4.26-dev retired the hand-synced duplicate that used to live here).
local CATEGORIES = Catalog.CATEGORIES

-- ============================================================
-- DLC ownership gate (UI polish)
-- ============================================================
-- Same DLC-id maps as the injection-side gate (_evt_dlc.lua), shared via the
-- catalog module. The load-bearing gate lives at the injection hooks; this is
-- purely UI cleanup so the host doesn't see checkbox / dropdown options for
-- content they don't own. Failing closed (un-owned -> hidden) matches
-- vanilla store-page behavior for missing DLC. NB: ui_owns_dlc below fails
-- OPEN when Managers.unlock isn't up (data evaluates very early in VMF init),
-- unlike _evt_dlc.lua's fail-closed owns_dlc — that divergence is deliberate.
local DLC_BY_MUTATOR_UI = Catalog.DLC_BY_MUTATOR
local DLC_BY_PRESET_UI  = Catalog.DLC_BY_PRESET

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
-- adventure-crasher (Curses.BROKEN_IN_ADVENTURE — keep in lockstep with
-- _is_adventure_safe_mutator in _evt_selection.lua). Labels come from the game's
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
-- Hand-curated, package-bearing curses from Curses.MANAGED_CURSES
-- (event_tweaker_curses.lua). Activating one preloads its resource package on
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
