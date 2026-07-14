local mod = get_mod("gut_dev")

-- Issue #352. The 2025 THP consolidation did not replace the talent records: it
-- assigned each record a shared `display_name` (thp_tank/thp_linesman/etc.). The
-- talent view renders `talent.display_name or talent.name`, so selecting the
-- record's own canonical `name` restores Fatshark's career-specific localization
-- without changing its tree identity, description, buffs, or mechanics.
-- Source: hero_window_talents.lua:328; talent_settings.lua:25-57.
--
-- Keep this an exact allow-list. A broad `_thp_` match would also rename talents
-- injected by another mod and would make this client-side presentation option an
-- accidental compatibility mutation.
local TALENT_NAMES = {
    -- Kruber: Mercenary, Huntsman, Foot Knight, Grail Knight.
    "markus_mercenary_thp_linesman", "markus_mercenary_thp_smiter", "markus_mercenary_thp_tank",
    "markus_huntsman_thp_tank", "markus_huntsman_thp_smiter", "markus_huntsman_thp_linesman",
    "markus_knight_thp_tank", "markus_knight_thp_linesman", "markus_knight_thp_smiter",
    "markus_questing_knight_thp_tank", "markus_questing_knight_thp_smiter", "markus_questing_knight_thp_linesman",

    -- Bardin: Ranger Veteran, Ironbreaker, Slayer, Outcast Engineer.
    "bardin_ranger_thp_tank", "bardin_ranger_thp_linesman", "bardin_ranger_thp_smiter",
    "bardin_ironbreaker_thp_tank", "bardin_ironbreaker_thp_smiter", "bardin_ironbreaker_thp_linesman",
    "bardin_slayer_thp_linesman", "bardin_slayer_thp_smiter", "bardin_slayer_thp_ninjafencer",
    "bardin_engineer_thp_tank", "bardin_engineer_thp_linesman", "bardin_engineer_thp_smiter",

    -- Kerillian: Waystalker, Handmaiden, Shade, Sister of the Thorn.
    "kerillian_waywatcher_thp_ninjafencer", "kerillian_waywatcher_thp_linesman", "kerillian_waywatcher_thp_smiter",
    "kerillian_maidenguard_thp_linesman", "kerillian_maidenguard_thp_smiter", "kerillian_maidenguard_thp_tank",
    "kerillian_shade_thp_ninjafencer", "kerillian_shade_thp_smiter", "kerillian_shade_thp_linesman",
    "kerillian_thorn_sister_thp_ninjafencer", "kerillian_thorn_sister_thp_smiter", "kerillian_thorn_sister_thp_linesman",

    -- Saltzpyre: Witch Hunter Captain, Bounty Hunter, Zealot, Warrior Priest.
    "victor_witchhunter_thp_ninjafencer", "victor_witchhunter_thp_linesman", "victor_witchhunter_thp_smiter",
    "victor_bountyhunter_thp_ninjafencer", "victor_bountyhunter_thp_smiter", "victor_bountyhunter_thp_linesman",
    "victor_zealot_thp_linesman", "victor_zealot_thp_smiter", "victor_zealot_thp_tank",
    "victor_priest_thp_tank", "victor_priest_thp_linesman", "victor_priest_thp_smiter",

    -- Sienna: Battle Wizard, Pyromancer, Unchained, Necromancer.
    "sienna_adept_thp_tank", "sienna_adept_thp_smiter", "sienna_adept_thp_linesman",
    "sienna_scholar_thp_linesman", "sienna_scholar_thp_smiter", "sienna_scholar_thp_ninjafencer",
    "sienna_unchained_thp_tank", "sienna_unchained_thp_linesman", "sienna_unchained_thp_smiter",
    "sienna_necromancer_thp_linesman", "sienna_necromancer_thp_smiter", "sienna_necromancer_thp_ninjafencer",
}

local wanted = {}
for _, talent_name in ipairs(TALENT_NAMES) do
    wanted[talent_name] = true
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
    discover()
    for talent_name, talent in pairs(records) do
        local original = captured[talent_name]
        if enabled then
            -- `talent.name` is the original career-specific localization key.
            talent.display_name = talent.name
        elseif original and original.had_display_name then
            talent.display_name = original.display_name
        else
            talent.display_name = nil
        end
    end
end

local API = {
    expected_count = #TALENT_NAMES,
    apply = apply,
}

function API.validate(enabled)
    local count = discover()
    if count ~= #TALENT_NAMES then
        return string.format("expected %d canonical THP talents, found %d", #TALENT_NAMES, count)
    end
    for talent_name, talent in pairs(records) do
        local original = captured[talent_name]
        if enabled and talent.display_name ~= talent.name then
            return talent_name .. " does not use its canonical localization key"
        elseif not enabled and original then
            local expected = original.had_display_name and original.display_name or nil
            if talent.display_name ~= expected then
                return talent_name .. " did not restore its captured shared display key"
            end
        end
    end
end

apply(mod:get("gut_original_thp_names") and true or false)

return API
