local mod = get_mod("gut_dev")

-- Issue #352. The 2025 THP consolidation did not replace the talent records: it
-- assigned each record a shared `display_name` (thp_tank/thp_linesman/etc.). The
-- talent view renders `Localize(talent.display_name or talent.name)`. `name` is
-- only the internal record ID, so it cannot be used as a localization key. Supply
-- explicit, mod-owned backend keys for the 60 legacy English names instead,
-- without changing tree identity, description, buffs, or mechanics.
-- Source: scripts/ui/views/hero_view/windows/hero_window_talents.lua:328;
-- scripts/managers/talents/talent_settings_markus.lua:2425-2458.
--
-- Keep this an exact allow-list. A broad `_thp_` match would also rename talents
-- injected by another mod and would make this client-side presentation option an
-- accidental compatibility mutation.
local TALENT_DISPLAY_NAMES = {
    -- Kruber: Mercenary, Huntsman, Foot Knight, Grail Knight.
    { "markus_mercenary_thp_linesman", "Drillmaster" },
    { "markus_mercenary_thp_smiter", "Mercenary's Pride" },
    { "markus_mercenary_thp_tank", "Captain's Command" },
    { "markus_huntsman_thp_tank", "Taste of Victory" },
    { "markus_huntsman_thp_smiter", "Huntsman's Tally" },
    { "markus_huntsman_thp_linesman", "Taal's Bounty" },
    { "markus_knight_thp_tank", "Back Off, Ugly!" },
    { "markus_knight_thp_linesman", "Bloody Unstoppable!" },
    { "markus_knight_thp_smiter", "Templar's Rally" },
    { "markus_questing_knight_thp_tank", "Lady's Generosity" },
    { "markus_questing_knight_thp_smiter", "Lady's Wrath" },
    { "markus_questing_knight_thp_linesman", "Gift of the Grail" },

    -- Bardin: Ranger Veteran, Ironbreaker, Slayer, Outcast Engineer.
    { "bardin_ranger_thp_tank", "Roots Running Deep" },
    { "bardin_ranger_thp_linesman", "Ranger Reaper" },
    { "bardin_ranger_thp_smiter", "Hardy Heart" },
    { "bardin_ironbreaker_thp_tank", "Rock-Breaker" },
    { "bardin_ironbreaker_thp_smiter", "Grudge-Borne" },
    { "bardin_ironbreaker_thp_linesman", "Hearthguard" },
    { "bardin_slayer_thp_linesman", "Doomseeker" },
    { "bardin_slayer_thp_smiter", "Slayer's Fury" },
    { "bardin_slayer_thp_ninjafencer", "Infectious Fortitude" },
    { "bardin_engineer_thp_tank", "Engineer's Resolve" },
    { "bardin_engineer_thp_linesman", "Morgrim's Enthusiasm" },
    { "bardin_engineer_thp_smiter", "Pouch of the Good Stuff" },

    -- Kerillian: Waystalker, Handmaiden, Shade, Sister of the Thorn.
    { "kerillian_waywatcher_thp_ninjafencer", "Weavebond" },
    { "kerillian_waywatcher_thp_linesman", "Dryad's Thirst" },
    { "kerillian_waywatcher_thp_smiter", "Ariel's Boon" },
    { "kerillian_maidenguard_thp_linesman", "Spirit Echo" },
    { "kerillian_maidenguard_thp_smiter", "Martial Blessing" },
    { "kerillian_maidenguard_thp_tank", "Eternal Blossom" },
    { "kerillian_shade_thp_ninjafencer", "Bleak Vigour" },
    { "kerillian_shade_thp_smiter", "Khaine's Thirst" },
    { "kerillian_shade_thp_linesman", "Blood Kin" },
    { "kerillian_thorn_sister_thp_ninjafencer", "Weavebond" },
    { "kerillian_thorn_sister_thp_smiter", "Martial Blessing" },
    { "kerillian_thorn_sister_thp_linesman", "Eternal Blossom" },

    -- Saltzpyre: Witch Hunter Captain, Bounty Hunter, Zealot, Warrior Priest.
    { "victor_witchhunter_thp_ninjafencer", "Hunter's Ardour" },
    { "victor_witchhunter_thp_linesman", "Walking Judgement" },
    { "victor_witchhunter_thp_smiter", "Disciplinarian" },
    { "victor_bountyhunter_thp_ninjafencer", "Blood for Money" },
    { "victor_bountyhunter_thp_smiter", "Tithetaker" },
    { "victor_bountyhunter_thp_linesman", "Paymaster" },
    { "victor_zealot_thp_linesman", "Sigmar's Herald" },
    { "victor_zealot_thp_smiter", "Repent! Repent!" },
    { "victor_zealot_thp_tank", "Font of Zeal" },
    { "victor_priest_thp_tank", "Eternal Vigilance" },
    { "victor_priest_thp_linesman", "Slayer of the Wicked" },
    { "victor_priest_thp_smiter", "Blessed Hands" },

    -- Sienna: Battle Wizard, Pyromancer, Unchained, Necromancer.
    { "sienna_adept_thp_tank", "Confound" },
    { "sienna_adept_thp_smiter", "Spark Thief" },
    { "sienna_adept_thp_linesman", "Flame-Fettled" },
    { "sienna_scholar_thp_linesman", "Spark Smith" },
    { "sienna_scholar_thp_smiter", "Spirit-Binding" },
    { "sienna_scholar_thp_ninjafencer", "Fiery Fortitude" },
    { "sienna_unchained_thp_tank", "Soul Quench" },
    { "sienna_unchained_thp_linesman", "Reckless Rampage" },
    { "sienna_unchained_thp_smiter", "Burn-Bloom" },
    { "sienna_necromancer_thp_linesman", "Corpsemaker" },
    { "sienna_necromancer_thp_smiter", "Death Dealer" },
    { "sienna_necromancer_thp_ninjafencer", "Life Leeching" },
}

local wanted = {}
local display_keys = {}
local backend_localizations = {}
for _, row in ipairs(TALENT_DISPLAY_NAMES) do
    local talent_name, display_name = row[1], row[2]
    local display_key = "gut_original_thp_name_" .. talent_name
    wanted[talent_name] = true
    display_keys[talent_name] = display_key
    backend_localizations[display_key] = display_name
end

local captured = {}
local records = {}

local function discover()
    records = {}
    local all_talents = rawget(_G, "Talents")
    if type(all_talents) ~= "table" then
        return 0
    end

    for _, hero_talents in pairs(all_talents) do
        if type(hero_talents) == "table" then
            for _, talent in ipairs(hero_talents) do
                local talent_name = type(talent) == "table" and talent.name
                if wanted[talent_name] then
                    records[talent_name] = talent
                    if captured[talent_name] == nil then
                        captured[talent_name] = {
                            had_display_name = talent.display_name ~= nil,
                            display_name = talent.display_name,
                        }
                    end
                end
            end
        end
    end

    local count = 0
    for _ in pairs(records) do count = count + 1 end
    return count
end

local function apply(enabled)
    local count = discover()
    for talent_name, talent in pairs(records) do
        local original = captured[talent_name]
        if enabled then
            talent.display_name = display_keys[talent_name]
        elseif original and original.had_display_name then
            talent.display_name = original.display_name
        else
            talent.display_name = nil
        end
    end
    if rawget(_G, "printf") then
        printf("[gut:352] applied enabled=%s records=%d localizations=%d",
            tostring(enabled), count, #TALENT_DISPLAY_NAMES)
    end
end

local API = {
    expected_count = #TALENT_DISPLAY_NAMES,
    backend_localizations = backend_localizations,
    apply = apply,
}

function API.register_backend_localizations()
    local loc = Managers and Managers.localizer
    if not (loc and loc.append_backend_localizations) then
        return false
    end
    local ok = pcall(loc.append_backend_localizations, loc, backend_localizations)
    return ok
end

function API.validate(enabled)
    local count = discover()
    if count ~= #TALENT_DISPLAY_NAMES then
        return string.format("expected %d canonical THP talents, found %d", #TALENT_DISPLAY_NAMES, count)
    end
    for talent_name, talent in pairs(records) do
        local original = captured[talent_name]
        if enabled and talent.display_name ~= display_keys[talent_name] then
            return talent_name .. " does not use its explicit legacy-name localization key"
        elseif not enabled and original then
            local expected = original.had_display_name and original.display_name or nil
            if talent.display_name ~= expected then
                return talent_name .. " did not restore its captured shared display key"
            end
        end
    end
    local localize = rawget(_G, "Localize")
    if type(localize) == "function" then
        for display_key, display_name in pairs(backend_localizations) do
            local ok, resolved = pcall(localize, display_key)
            if not ok or resolved ~= display_name then
                return string.format("legacy localization unresolved: %s -> %s",
                    display_key, tostring(resolved))
            end
        end
    end
end

API.register_backend_localizations()
apply(mod:get("gut_original_thp_names") and true or false)

return API
