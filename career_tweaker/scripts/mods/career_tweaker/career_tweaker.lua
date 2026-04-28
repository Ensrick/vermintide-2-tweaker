local mod = get_mod("crt")

local MOD_VERSION = "0.1.0-dev"
mod:info("Career Tweaker v%s loaded", MOD_VERSION)
mod:echo("Career Tweaker v" .. MOD_VERSION)

-- All 20 careers in the game.
local _ALL_CAREERS = {
    "dr_ironbreaker", "dr_slayer",  "dr_ranger",  "dr_engineer",
    "es_huntsman",    "es_knight",  "es_mercenary", "es_questingknight",
    "we_shade",       "we_maidenguard", "we_waywatcher", "we_thornsister",
    "wh_zealot",      "wh_bountyhunter", "wh_captain", "wh_priest",
    "bw_scholar",     "bw_adept",   "bw_unchained", "bw_necromancer",
}

-- ============================================================
-- Talent & Ability Swapping
-- ============================================================
-- Directly mutates the live TalentTrees global (which is read every time the
-- game looks up a talent by tier/index) and the CareerSettings activated_ability
-- / passive_ability fields (read by career_extension:init at level load).
-- All originals are saved before mutation so the function is safe to call
-- repeatedly -- it restores first, then re-applies the current settings.
--
-- KNOWN ISSUE: The talent picker UI does not refresh after swapping. The
-- underlying data is correct but the visual display is stale. Need to find
-- and hook the talent UI refresh function. (see WORK_ITEMS.md)
--
-- KNOWN ISSUE: Swapping a career whose ability is a weapon (e.g. GK blessed
-- blade) to a career that does not support it can crash. Ability swap is
-- wrapped in pcall for safety. (see WORK_ITEMS.md)

local _talent_swap_originals = {}  -- [career_name] = { tree, activated_ability, passive_ability }

local function apply_talent_swaps()
    if not CareerSettings or not TalentTrees then return end

    -- Restore all previous overrides to their originals
    for career_name, orig in pairs(_talent_swap_originals) do
        local cs = CareerSettings[career_name]
        if cs then
            local trees = TalentTrees[cs.profile_name]
            if trees then trees[cs.talent_tree_index] = orig.tree end
            cs.activated_ability = orig.activated_ability
            cs.passive_ability   = orig.passive_ability
        end
    end
    _talent_swap_originals = {}

    -- Apply current settings
    for _, career_name in ipairs(_ALL_CAREERS) do
        local src_name = mod:get("talent_swap_" .. career_name)
        if src_name and src_name ~= "none" then
            local cs  = CareerSettings[career_name]
            local src = CareerSettings[src_name]
            if cs and src then
                -- Save originals before first modification
                _talent_swap_originals[career_name] = {
                    tree              = TalentTrees[cs.profile_name] and TalentTrees[cs.profile_name][cs.talent_tree_index],
                    activated_ability = cs.activated_ability,
                    passive_ability   = cs.passive_ability,
                }

                -- Swap talent tree slot (read in-place by TalentTrees[profile][tree_idx][tier][col])
                local dst_trees = TalentTrees[cs.profile_name]
                local src_trees = TalentTrees[src.profile_name]
                if dst_trees and src_trees then
                    dst_trees[cs.talent_tree_index] = src_trees[src.talent_tree_index]
                end

                -- Swap career ability and passive (read by CareerUtils at level spawn)
                -- pcall protection: GK weapon-ability crash when swapping to a career
                -- that does not support weapon-based abilities (see WORK_ITEMS.md)
                local ok, err = pcall(function()
                    cs.activated_ability = src.activated_ability
                    cs.passive_ability   = src.passive_ability
                end)
                if not ok then
                    mod:warning("Failed to swap ability for %s <- %s: %s", career_name, src_name, tostring(err))
                end
            end
        end
    end
end

-- Career action injection is handled by weapon_tweaker (owns the unlock map).
-- If both mods are loaded, weapon_tweaker's patch_career_actions_on_weapons
-- runs on game state change and covers all unlocked weapons.

-- ============================================================
-- Melee weapons in ranged slot
-- ============================================================
local _original_slot_2_allowed = {}

local function apply_slot_settings()
    if not CareerSettings then return end

    local allow_melee_in_ranged = mod:get("allow_melee_in_ranged_slot")

    for career_name, cs in pairs(CareerSettings) do
        if type(cs) == "table" and cs.item_types_allowed_in_slot_2 then
            if not _original_slot_2_allowed[career_name] then
                -- Save original
                local orig = {}
                for _, v in ipairs(cs.item_types_allowed_in_slot_2) do
                    orig[#orig + 1] = v
                end
                _original_slot_2_allowed[career_name] = orig
            end

            -- Restore original
            local t = cs.item_types_allowed_in_slot_2
            while #t > 0 do table.remove(t) end
            for _, v in ipairs(_original_slot_2_allowed[career_name]) do
                t[#t + 1] = v
            end

            -- Apply setting if needed
            if allow_melee_in_ranged then
                local has_melee = false
                for _, v in ipairs(t) do
                    if v == "melee" then has_melee = true; break end
                end
                if not has_melee then
                    t[#t + 1] = "melee"
                end
            end
        end
    end
end

-- ============================================================
-- Lifecycle hooks
-- ============================================================

mod.on_game_state_changed = function(status, state_name)
    apply_slot_settings()
    apply_talent_swaps()
end

mod.on_setting_changed = function(setting_id)
    mod:echo("Setting changed: " .. tostring(setting_id))

    if setting_id == "allow_melee_in_ranged_slot" then
        apply_slot_settings()
    end

    if setting_id:find("^talent_swap_") then
        apply_talent_swaps()
    end

    -- enable_career_action_injection is handled by weapon_tweaker
end

-- ============================================================
-- Console command: crt status
-- ============================================================

mod:command("ct_status", "Show Career Tweaker version and active talent swaps", function()
    mod:echo("Career Tweaker v" .. MOD_VERSION)

    local any_swap = false
    for _, career_name in ipairs(_ALL_CAREERS) do
        local src = mod:get("talent_swap_" .. career_name)
        if src and src ~= "none" then
            mod:echo("  " .. career_name .. " <- " .. src)
            any_swap = true
        end
    end
    if not any_swap then
        mod:echo("  No talent swaps active")
    end

    local melee_in_ranged = mod:get("allow_melee_in_ranged_slot")
    mod:echo("  Melee in ranged slot: " .. tostring(melee_in_ranged or false))
end)
