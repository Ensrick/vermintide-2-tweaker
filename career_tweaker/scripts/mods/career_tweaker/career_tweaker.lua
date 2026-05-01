local mod = get_mod("crt")

local MOD_VERSION = "0.2.3-dev"
mod:info("Career Tweaker v%s loaded", MOD_VERSION)
mod:echo("Career Tweaker v" .. MOD_VERSION)

local ok, balance = pcall(mod.dofile, mod, "scripts/mods/career_tweaker/career_tweaker_balance")
if not ok then
    mod:error("Failed to load balance module: %s", tostring(balance))
    balance = { apply = function() end, restore = function() end, active_count = function() return 0 end }
end

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

local _talent_swap_originals = {}

-- Weapon-based abilities that crash when swapped to a different character.
local _WEAPON_ABILITY_CAREERS = {
    es_questingknight = true,
}

local _talent_window_instance = nil

mod:hook_safe("HeroWindowTalents", "on_enter", function(self)
    _talent_window_instance = self
end)

mod:hook_safe("HeroWindowTalents", "on_exit", function(self)
    _talent_window_instance = nil
end)

local function refresh_talent_ui()
    if _talent_window_instance then
        pcall(function()
            _talent_window_instance:_update_talent_sync(false)
        end)
    end
end

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
                _talent_swap_originals[career_name] = {
                    tree              = TalentTrees[cs.profile_name] and TalentTrees[cs.profile_name][cs.talent_tree_index],
                    activated_ability = cs.activated_ability,
                    passive_ability   = cs.passive_ability,
                }

                -- Swap talent tree
                local dst_trees = TalentTrees[cs.profile_name]
                local src_trees = TalentTrees[src.profile_name]
                if dst_trees and src_trees then
                    dst_trees[cs.talent_tree_index] = src_trees[src.talent_tree_index]
                end

                -- Swap ability/passive — skip weapon-based abilities on cross-character swaps
                local skip_ability = _WEAPON_ABILITY_CAREERS[src_name] and cs.profile_name ~= src.profile_name
                if skip_ability then
                    mod:info("Skipping ability swap for %s <- %s (weapon-based ability)", career_name, src_name)
                else
                    cs.activated_ability = src.activated_ability
                    cs.passive_ability   = src.passive_ability
                end
            end
        end
    end

    refresh_talent_ui()
end

-- Career action injection is handled by weapon_tweaker (owns the unlock map).

-- ============================================================
-- Lifecycle hooks
-- ============================================================

mod.on_game_state_changed = function(status, state_name)
    apply_talent_swaps()
    balance.apply()
end

mod.on_setting_changed = function(setting_id)
    mod:echo("Setting changed: " .. tostring(setting_id))

    if setting_id:find("^talent_swap_") then
        apply_talent_swaps()
    end

    if setting_id:find("^balance_") then
        balance.apply()
    end
end

mod.on_disabled = function()
    balance.restore()
end

-- ============================================================
-- Console command: crt status
-- ============================================================

mod:command("ct_status", "Show Career Tweaker version and active swaps/balance mods", function()
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

    local bal_count = balance.active_count()
    mod:echo("  Balance mods active: " .. tostring(bal_count))
end)
