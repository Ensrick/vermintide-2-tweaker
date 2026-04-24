local mod = get_mod("career_tweaker")

local MOD_VERSION = "0.1.0-dev"
mod:info("Career Tweaker v%s loaded", MOD_VERSION)
mod:echo("Career Tweaker v" .. MOD_VERSION)

local ALL_CAREERS = {
    "dr_ironbreaker", "dr_slayer", "dr_ranger", "dr_engineer",
    "es_huntsman", "es_knight", "es_mercenary", "es_questingknight",
    "we_shade", "we_maidenguard", "we_waywatcher", "we_thornsister",
    "wh_zealot", "wh_bountyhunter", "wh_captain", "wh_priest",
    "bw_scholar", "bw_adept", "bw_unchained", "bw_necromancer",
}

local talent_swap_originals = {}
local original_slot_2_allowed = {}

local function apply_slot_settings()
    if not CareerSettings then
        return
    end

    local allow_melee_in_ranged = mod:get("allow_melee_in_ranged_slot")

    for career_name, settings in pairs(CareerSettings) do
        if type(settings) == "table" and settings.item_types_allowed_in_slot_2 then
            if not original_slot_2_allowed[career_name] then
                local original = {}
                for _, value in ipairs(settings.item_types_allowed_in_slot_2) do
                    original[#original + 1] = value
                end
                original_slot_2_allowed[career_name] = original
            end

            local slot_list = settings.item_types_allowed_in_slot_2
            while #slot_list > 0 do
                table.remove(slot_list)
            end

            for _, value in ipairs(original_slot_2_allowed[career_name]) do
                slot_list[#slot_list + 1] = value
            end

            if allow_melee_in_ranged then
                local has_melee = false
                for _, value in ipairs(slot_list) do
                    if value == "melee" then
                        has_melee = true
                        break
                    end
                end

                if not has_melee then
                    slot_list[#slot_list + 1] = "melee"
                end
            end
        end
    end
end

local function apply_talent_swaps()
    if not CareerSettings or not TalentTrees then
        return
    end

    for career_name, original in pairs(talent_swap_originals) do
        local settings = CareerSettings[career_name]
        if settings then
            local trees = TalentTrees[settings.profile_name]
            if trees then
                trees[settings.talent_tree_index] = original.tree
            end
            settings.activated_ability = original.activated_ability
            settings.passive_ability = original.passive_ability
        end
    end
    talent_swap_originals = {}

    for _, career_name in ipairs(ALL_CAREERS) do
        local source_name = mod:get("talent_swap_" .. career_name)
        if source_name and source_name ~= "none" then
            local settings = CareerSettings[career_name]
            local source = CareerSettings[source_name]
            if settings and source then
                talent_swap_originals[career_name] = {
                    tree = TalentTrees[settings.profile_name] and TalentTrees[settings.profile_name][settings.talent_tree_index],
                    activated_ability = settings.activated_ability,
                    passive_ability = settings.passive_ability,
                }

                local destination_trees = TalentTrees[settings.profile_name]
                local source_trees = TalentTrees[source.profile_name]
                if destination_trees and source_trees then
                    destination_trees[settings.talent_tree_index] = source_trees[source.talent_tree_index]
                end

                settings.activated_ability = source.activated_ability
                settings.passive_ability = source.passive_ability
            end
        end
    end
end

mod.on_game_state_changed = function()
    apply_slot_settings()
    apply_talent_swaps()
end

mod.on_setting_changed = function(setting_id)
    if setting_id == "allow_melee_in_ranged_slot" then
        apply_slot_settings()
    elseif setting_id and setting_id:find("^talent_swap_") then
        apply_talent_swaps()
    end
end

mod:hook("ProfileSynchronizer", "get_profile_index_reservation", function(func, self, party_id, profile_index)
    if mod:get("allow_duplicate_careers") then
        return nil, nil
    end
    return func(self, party_id, profile_index)
end)

mod:hook("ProfileSynchronizer", "try_reserve_profile_for_peer", function(func, self, party_id, peer_id, profile_index, career_index)
    local result = func(self, party_id, peer_id, profile_index, career_index)
    if result then
        return true
    end
    if mod:get("allow_duplicate_careers") then
        return true
    end
    return false
end)

mod:hook("ProfileSynchronizer", "is_free_in_lobby", function(func, profile_index, lobby_data, optional_party_id)
    if mod:get("allow_duplicate_careers") then
        return true
    end
    return func(profile_index, lobby_data, optional_party_id)
end)
