-- Shared curse catalog. require'd (NOT read off a mod._field) — VMF loads this
-- localization file FIRST (before data + script), so a script-set field is nil
-- here. See event_tweaker_curses.lua's header.
local Curses = require("scripts/mods/event_tweaker/event_tweaker_curses")

local function en(s) return { en = s } end

local loc = {
    mod_description = en("Host-side picker for turning any built-in game mutator on for your lobby: difficulty modifiers, extra specials and hordes, winds of magic, dormant event mutators like Geheimnisnacht ritual sites and Khorne skull pickups, and the full adventure-safe Chaos Wastes set. Most of these only the host needs, but the Cursed Adventure curses bring Chaos Wastes curse mechanics and themed lighting onto normal missions, and those need every player in the lobby to run the mod."),

    -- Event presets (handle the active_events string magic some
    -- mutators inspect inside their server_start_function)
    event_preset = en("[working] Event Preset"),
    event_preset_tooltip = en("Pick a full seasonal event to run: it turns on the matching mutators and swaps the keep to its decorated Geheimnisnacht or Khorne's Skulls version, and changing it reloads the level for you. Leave it Off to hand-pick individual mutators below, which take effect on the next level load or when you run /event_apply. Host only."),
    preset_off                 = en("Off (no preset)"),
    preset_geheimnisnacht_2021 = en("Geheimnisnacht 2021 (ritual sites on that year's maps)"),
    preset_geheimnisnacht_2025 = en("Geheimnisnacht 2025 (ritual sites on that year's maps)"),
    preset_geheimnisnacht_2026 = en("Geheimnisnacht 2026 (ritual sites on that year's maps)"),
    preset_skulls_2023         = en("Khorne's Skulls 2023 (skull pickups; Hordes Galore at 5 stacks)"),
    preset_skulls_2026         = en("Khorne's Skulls 2026 (same as 2023; the 2026 update only adds cosmetics and portraits)"),

    -- v0.4.10-dev: opt-in switch to neutralize Fatshark's currently-live event.
    suppress_live_event         = en("[working] Suppress the game's live event"),
    suppress_live_event_tooltip = en("Turn off whatever seasonal event the game currently has live: the keep goes back to the plain inn, ritual sites stop spawning, and event lighting and dialogue stop. Your own preset and mutator choices still apply on top of that. Host only, and toggling it reloads the level."),

    -- issue 532: hold-Tab preview of the active mutators (option title carries the
    -- dev status tag; the runtime panel strings below do not, per LOCALIZATION §13).
    preview_active_mutators         = en("[untested] Preview Active Mutators on Tab"),
    preview_active_mutators_tooltip = en("While you hold Tab in the keep, show the mutators this lobby will activate (icon and name) on the right-hand pop-out panel, alongside Chaos Wastes Tweaker's starting-boons list if you run that mod. Reflects your Event Preset and mutator checkboxes. A curse a lobby peer without the mod would crash on is listed as skipped instead. Applies to your own screen only."),
    -- Runtime panel strings (not settings-option titles, so no dev status tag).
    evt_mutator_preview_header        = en("Active Mutators"),
    evt_mutator_preview_client_caveat = en("Your selection - the host's config decides"),

    -- Categories
    cat_difficulty = en("[working] Difficulty Modifiers"),
    cat_specials   = en("[working] Special / Elite Spawns"),
    cat_hordes     = en("[working] Hordes & Waves"),
    cat_atmosphere = en("[working] Atmosphere & Hazards"),
    cat_objectives = en("[working] Objective Modifiers"),
    cat_winds      = en("[working] Winds of Magic (Weave-style)"),
    cat_events     = en("[working] Live-Event Mutators (raw)"),
    -- Dynamic groups (ported from Deed Mutators Selector + Cursed Adventure).
    cat_other      = en("[untested] Other Mutators (Chaos Wastes / Deus / misc)"),
    cat_cursed     = en("[untested] Cursed Adventure: CW / Be'lakor curses (ALL players need the mod)"),
    cursed_lighting         = en("[untested] Cursed-sky lighting"),
    cursed_lighting_tooltip = en("Tints the mission's sky, sun, and fog with the active curse's Chaos god color (Khorne red, Nurgle green, Tzeentch blue, Belakor purple, Slaanesh pink). This is purely visual, only affects your own screen, and clears on its own when no curse is active."),
    -- issue 430: name used INSIDE the peer-parity chat notice (not a settings-UI
    -- option title, so it carries no dev status tag). The beacon echoes e.g.
    -- "[Events] Peer-parity: disabled Cursed Adventure curses. Missing Tweaker:
    -- Events: <peer>. ...". Kept short so the one-line notice stays readable.
    peer_parity_curse_feature_label = en("Cursed Adventure curses"),

    -- Difficulty modifiers
    mut_no_ammo                    = en("[working] No Ammo"),
    mut_no_ammo_tooltip            = en("Ranged weapons start empty, so you cannot use them."),
    mut_no_pickups                 = en("[working] No Pickups"),
    mut_no_pickups_tooltip         = en("Removes most pickups from the level, including potions, bombs, and ammo."),
    mut_player_dot                 = en("[working] Player DoT"),
    mut_player_dot_tooltip         = en("Players take steady damage over time, as if corrupted."),
    mut_instant_death              = en("[working] Instant Death"),
    mut_instant_death_tooltip     = en("Any damage you take downs you instantly. Very hardcore."),
    mut_no_respawn                 = en("[working] No Respawn"),
    mut_no_respawn_tooltip         = en("Players who die do not respawn for the rest of the mission."),
    mut_elite_run                  = en("[working] Elite Run"),
    mut_elite_run_tooltip          = en("Ordinary enemies are replaced with elites."),
    mut_shared_health_pool         = en("[working] Shared Health Pool"),
    mut_shared_health_pool_tooltip = en("The whole team shares a single health pool."),
    mut_whiterun                   = en("[working] Whiterun"),
    mut_whiterun_tooltip           = en("Take an arrow to the knee. A light novelty modifier."),
    mut_realism                    = en("[working] Realism"),
    mut_realism_tooltip            = en("Removes aim assist and hit indicators for a more realistic feel."),

    -- Specials
    mut_specials_frequency         = en("[working] Specials Frequency"),
    mut_specials_frequency_tooltip = en("Special enemies spawn more often."),
    mut_more_specials              = en("[working] More Specials"),
    mut_more_specials_tooltip      = en("Specials arrive in larger groups each time they spawn."),
    mut_same_specials              = en("[working] Same Specials"),
    mut_same_specials_tooltip      = en("Every special in a given wave is the same type."),
    mut_big_specials               = en("[working] Big Specials"),
    mut_big_specials_tooltip       = en("Special enemies are larger than normal."),
    mut_elite_specials             = en("[working] Elite Specials"),
    mut_elite_specials_tooltip     = en("Special enemies are replaced with elites."),
    mut_gutter_runner_mayhem       = en("[working] Gutter Runner Mayhem"),
    mut_gutter_runner_mayhem_tooltip = en("The only specials that spawn are Gutter Runner assassins."),
    mut_chaos_warriors_trickle     = en("[working] Chaos Warriors Trickle"),
    mut_chaos_warriors_trickle_tooltip = en("A steady trickle of Chaos Warriors joins the fight."),
    mut_mixed_horde                = en("[working] Mixed Horde"),
    mut_mixed_horde_tooltip        = en("Hordes contain enemies from both factions at once."),
    mut_multiple_bosses            = en("[working] Multiple Bosses"),
    mut_multiple_bosses_tooltip    = en("More than one boss can spawn in a mission."),
    mut_hordes_galore              = en("[working] Hordes Galore"),
    mut_hordes_galore_tooltip      = en("Hordes come almost continuously, at a much higher rate."),
    mut_powerful_elites            = en("[working] Powerful Elites"),
    mut_powerful_elites_tooltip    = en("Elite enemies are stronger than usual."),
    mut_skulking_sorcerer          = en("[working] Skulking Sorcerer"),
    mut_skulking_sorcerer_tooltip  = en("A roving sorcerer enemy stalks and harasses the team."),

    -- Hordes / waves
    mut_wave_of_plague_monks         = en("[working] Wave of Plague Monks"),
    mut_wave_of_plague_monks_tooltip = en("Plague Monk waves replace the standard hordes."),
    mut_wave_of_berzerkers           = en("[working] Wave of Berserkers"),
    mut_wave_of_berzerkers_tooltip   = en("Berserker waves replace the standard hordes."),
    mut_high_intensity               = en("[working] High Intensity"),
    mut_high_intensity_tooltip       = en("The spawn system runs hot, throwing more enemies at you overall."),
    mut_splitting_enemies            = en("[working] Splitting Enemies"),
    mut_splitting_enemies_tooltip    = en("Enemies split into smaller versions when they die."),
    mut_explosive_loot_rats          = en("[working] Explosive Loot Rats"),
    mut_explosive_loot_rats_tooltip  = en("Loot Rats explode when killed."),
    mut_bloodlust                    = en("[working] Bloodlust"),
    mut_bloodlust_tooltip            = en("Killing enemies grants a brief combat boost."),

    -- Atmosphere & hazards
    mut_night_mode                   = en("[working] Night Mode"),
    mut_night_mode_tooltip           = en("Darkens the level's lighting. It shows up as 'Geheimnisnacht Night Mode' in the in-game mutator list, but it only dims the lights and does not start the Geheimnisnacht event; uncheck it or run /event_clear to turn it off."),
    mut_darkness                     = en("[working] Darkness"),
    mut_darkness_tooltip             = en("Even heavier darkness, forcing you to rely on your torch."),
    mut_ticking_bomb                 = en("[working] Ticking Bomb"),
    mut_ticking_bomb_tooltip         = en("A bomb goes off periodically during the mission."),
    mut_flames                       = en("[working] Flames"),
    mut_flames_tooltip               = en("A fire hazard flares up from time to time."),
    mut_lightning_strike             = en("[working] Lightning Strike"),
    mut_lightning_strike_tooltip     = en("Lightning strikes the area from time to time."),
    mut_chasing_spirits              = en("[working] Chasing Spirits"),
    mut_chasing_spirits_tooltip      = en("Spectral pursuers chase the team through the level."),

    -- Objectives
    mut_escort                       = en("[working] Escort"),
    mut_escort_tooltip               = en("Adds an escort objective to the mission."),
    mut_slayer_curse                 = en("[working] Slayer Curse"),
    mut_slayer_curse_tooltip         = en("Adds a Slayer-themed curse mechanic to the mission."),
    mut_leash                        = en("[working] Leash"),
    mut_leash_tooltip                = en("Players are tethered together and cannot stray far apart."),

    -- Winds of magic
    mut_life_tooltip      = en("A healing-themed modifier."),
    mut_life              = en("[working] Wind: Life"),
    mut_metal             = en("[working] Wind: Metal"),
    mut_metal_tooltip     = en("A damage-resistance modifier."),
    mut_heavens           = en("[working] Wind: Heavens"),
    mut_heavens_tooltip   = en("Adds lightning effects."),
    mut_light             = en("[working] Wind: Light"),
    mut_light_tooltip     = en("Adds truesight effects."),
    mut_shadow            = en("[working] Wind: Shadow"),
    mut_shadow_tooltip    = en("Adds stealth effects."),
    mut_fire              = en("[working] Wind: Fire"),
    mut_fire_tooltip      = en("Adds burning effects."),
    mut_death             = en("[working] Wind: Death"),
    mut_death_tooltip     = en("Adds necromantic effects."),
    mut_beasts            = en("[working] Wind: Beasts"),
    mut_beasts_tooltip    = en("A Beastmen-themed modifier."),

    -- Live event mutators (raw)
    mut_geheimnisnacht_2021              = en("[working] Geheimnisnacht 2021"),
    mut_geheimnisnacht_2021_tooltip      = en("Spawns Geheimnisnacht ritual sites on that year's five maps when a matching Event Preset is picked. On its own without a preset the mutator runs, but no ritual sites appear."),
    mut_geheimnisnacht_2021_hard_mode    = en("[working] Geheimnisnacht Hard Mode"),
    mut_geheimnisnacht_2021_hard_mode_tooltip = en("Normally turns on when a player picks up the Geheimnisnacht side objective. Enable it here to force it on without the pickup."),
    mut_skulls_2023                      = en("[working] Khorne's Skulls 2023"),
    mut_skulls_2023_tooltip              = en("Spawns Khorne skull pickups; collecting five unleashes relentless hordes. It works on its own and needs no Event Preset."),

}

-- ============================================================
-- Dynamic mutator labels (ported from "Deed Mutators Selector")
-- + Cursed Adventure curse labels
-- ============================================================
-- The "Other Mutators" and "Cursed Adventure" groups in event_tweaker_data.lua
-- surface mutators that need loc keys. Rather than hand-write tooltips for
-- ~14 Chaos Wastes / Be'lakor mutators (risking fabricated mechanics — global
-- CLAUDE.md "Don't invent internals"), pull the GAME'S OWN localized strings
-- via Localize. Curated entries above are never overwritten (the `if not
-- loc[key]` guard wins).

local function _humanize(id)
    local words = {}
    for w in string.gmatch(id, "[^_]+") do
        words[#words + 1] = w:sub(1, 1):upper() .. w:sub(2)
    end
    return table.concat(words, " ")
end

-- nil / empty / unresolved "<...>" placeholder -> humanized id. Otherwise DOUBLE
-- every literal % (so VMF's string.format tooltip path + the
-- localization_format_safe regression test can't choke on an unfilled %s).
local function _safe(s, id)
    if type(s) ~= "string" or s == "" or s:find("^<") then
        return _humanize(id)
    end
    return (s:gsub("%%", "%%%%"))
end

do
    local MT = rawget(_G, "MutatorTemplates")
    local Loc = rawget(_G, "Localize")
    local broken = Curses.BROKEN_IN_ADVENTURE

    -- 1) "Other Mutators" — every displayable, non-package, non-hidden,
    --    non-broken mutator (mirrors the data file's cat_other predicate).
    if MT then
        for name, tmpl in pairs(MT) do
            if type(tmpl) == "table" and tmpl.display_name and tmpl.description
               and not tmpl.hide_from_player_ui and not broken[name]
               and not (tmpl.packages and next(tmpl.packages)) then
                local key = "mut_" .. name
                if not loc[key] then
                    local dn = Loc and Loc(tmpl.display_name) or nil
                    local de = Loc and Loc(tmpl.description) or nil
                    -- #301 dev status tag: runtime-discovered "Other Mutators"
                    -- entries are the Deed-Mutators-Selector port (added
                    -- 0.4.14-dev), never confirmed in-game -> [untested]. Title
                    -- only; the _tooltip line is untagged per doctrine.
                    loc[key]               = en("[untested] " .. _safe(dn, name) .. " [" .. name .. "]")
                    loc[key .. "_tooltip"] = en("[" .. name .. "] " .. _safe(de, name))
                end
            end
        end
    end

    -- 2) "Cursed Adventure" — the package-bearing managed curses, with a note
    --    that every player needs the mod (+ an experimental flag where it may
    --    be inert in adventure).
    local managed = Curses.MANAGED_CURSES
    if type(managed) == "table" then
        for i = 1, #managed do
            local c = managed[i]
            local key = "mut_" .. c.id
            local tmpl = MT and rawget(MT, c.id)
            local dn = Loc and tmpl and Loc(tmpl.display_name) or nil
            local de = Loc and tmpl and Loc(tmpl.description) or nil
            local flag = c.experimental and " (experimental)" or ""
            -- #301 dev status tag: Cursed Adventure curse titles are the
            -- experimental package-preload feature (added 0.4.14-dev), never
            -- confirmed in-game -> [untested]. Title only; tooltip untagged.
            loc[key]               = en("[untested] Curse: " .. _safe(dn, c.id) .. flag)
            loc[key .. "_tooltip"] = en("[" .. c.id .. "] " .. _safe(de, c.id)
                .. ". Chaos Wastes curse on a standard adventure map (god: " .. tostring(c.god)
                .. "). Needs ALL players to run the mod (clients load the curse package too)."
                .. (c.experimental and " Experimental: may be inert in adventure (no Deus economy/mission flow to pay off)." or ""))
        end
    end
end

return loc
