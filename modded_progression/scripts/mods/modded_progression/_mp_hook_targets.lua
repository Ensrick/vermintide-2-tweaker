-- _mp_hook_targets.lua - issue #1671 live check that every mp hook target exists.
--
-- VMF resolves a string class with rawget(_G, name) and refuses a hook whose
-- method is absent: it logs "trying to hook function or method that doesn't
-- exist" and the handler never runs [VMF core/hooks.lua get_object_reference,
-- generic_hook]. Game 6.12.0 removed IngameUI.not_in_modded, the Spoils of War
-- hotkey gate mp overrode to true from 0.2.0-dev [src 6.11.3 c5e4968b:
-- scripts/ui/views/ingame_ui.lua:381, ingame_ui_settings.lua:818]; the hotkey
-- now names can_open_loot [src 6.13.0: ingame_ui_settings.lua:818,
-- ingame_ui.lua:381-382]. mp 0.2.41-dev drops that hook instead of retargeting
-- it: game 6.13.0 greys both chest Open buttons on the same read_only_backend
-- flag [src 6.13.0: scripts/ui/views/hero_view/states/hero_view_state_loot.lua
-- :1193-1199, press gate :1577], and mp neither awards nor opens containers locally
-- (_mp_loot_diag.lua LOCAL_CONTAINER_AWARD/OPEN_IMPLEMENTED = false), so an
-- open loot screen would give the player nothing.
--
-- TARGETS mirrors every mp hook site whose class and method are both string
-- literals; qa/lua/tests/test_mp_hook_targets_resolve.lua fails when they
-- drift. Symbolic targets (the #840 runtime's Runtime.CLASS rows and the #1637
-- instance join) are checked by mp840_fresh_route_methods_resolved.

local M = {}

M.CHECK_NAME = "mp1671_hook_targets_resolve"

-- Vanilla methods mp used to hook that the game removed. A TARGETS row that
-- names one of these is a dead hook and fails the check.
M.RETIRED = {
    ["IngameUI.not_in_modded"] = "removed by game 6.12.0 (#1671)",
}

M.TARGETS = {
    { "AchievementManager", "trigger_event" },
    { "BackendInterfaceItemPlayfab", "has_item" },
    { "BackendInterfaceItemPlayfab", "has_weapon_illusion" },
    { "BackendInterfaceLootPlayfab", "generate_end_of_level_loot" },
    { "BackendInterfaceLootPlayfab", "loot_chest_rewards_request_cb" },
    { "BackendInterfaceLootPlayfab", "open_loot_chest" },
    { "BackendInterfacePeddlerPlayFab", "claim_login_rewards" },
    { "BackendInterfacePeddlerPlayFab", "exchange_chips" },
    { "BackendInterfacePeddlerPlayFab", "get_chips" },
    { "BackendInterfacePeddlerPlayFab", "get_filtered_items" },
    { "BackendInterfacePeddlerPlayFab", "get_peddler_stock" },
    { "BackendInterfaceQuestsPlayfab", "claim_multiple_quest_rewards" },
    { "BackendInterfaceQuestsPlayfab", "claim_quest_rewards" },
    { "BackendInterfaceQuestsPlayfab", "get_daily_quest_update_time" },
    { "BackendInterfaceQuestsPlayfab", "get_quest_by_key" },
    { "BackendInterfaceQuestsPlayfab", "get_quest_key" },
    { "BackendInterfaceQuestsPlayfab", "get_quest_rewards" },
    { "BackendInterfaceQuestsPlayfab", "get_quests" },
    { "BackendInterfaceQuestsPlayfab", "get_weekly_quest_update_time" },
    { "BackendInterfaceQuestsPlayfab", "update_quests" },
    { "BackendManagerPlayFab", "playfab_api_error" },
    { "BackendManagerPlayFab", "playfab_eac_error" },
    { "HeroViewStateAchievements", "_claim_multiple_quest_rewards" },
    { "HeroViewStateAchievements", "_claim_quest_reward" },
    { "HeroViewStateAchievements", "_create_entries" },
    { "HeroViewStateAchievements", "_handle_claim_all_challenges" },
    { "HeroViewStateStore", "_populate_item_widget" },
    { "HeroViewStateStore", "_populate_pose_item" },
    { "HeroWindowItemCustomization", "_enable_craft_button" },
    { "HeroWindowItemCustomization", "_update_state_craft_button" },
    { "LevelEndViewBase", "init" },
    { "PlayFabRequestQueue", "enqueue" },
    { "QuestManager", "_increment_quest_stats" },
    { "QuestManager", "get_data_by_id" },
    { "StoreItemPurchasePopup", "_create_ui_elements" },
    { "StoreItemPurchasePopup", "_populate_item_widget" },
    { "StoreLoginRewardsPopup", "_claim_rewards" },
    { "StoreLoginRewardsPopup", "_create_ui_elements" },
    { "StoreWindowFeatured", "_get_default_featured_grid_content" },
    { "StoreWindowItemList", "_update_item_list" },
    { "StoreWindowItemPreview", "_set_unlock_button_states" },
    { "StoreWindowItemPreview", "_sync_presentation_item" },
    { "StoreWindowItemPreview", "_sync_products_version" },
    { "StoreWindowPanel", "_sync_player_wallet" },
}

-- Pure census. `lookup(class_name)` returns the live class table or nil.
-- A class that is not loaded yet is deferred (VMF delays that hook too), never
-- a failure; a loaded class without the method, or a retired row, is missing.
function M.census(lookup, targets)
    local report = { resolved = 0, missing = {}, deferred = {} }
    local deferred_seen = {}
    for _, row in ipairs(targets or M.TARGETS) do
        local class_name, method = row[1], row[2]
        local key = class_name .. "." .. method
        local class = lookup(class_name)
        if M.RETIRED[key] then
            report.missing[#report.missing + 1] = key .. " (" .. M.RETIRED[key] .. ")"
        elseif type(class) ~= "table" then
            if not deferred_seen[class_name] then
                deferred_seen[class_name] = true
                report.deferred[#report.deferred + 1] = class_name
            end
        elseif type(class[method]) ~= "function" then
            report.missing[#report.missing + 1] = key
        else
            report.resolved = report.resolved + 1
        end
    end
    return report
end

function M.failure(report)
    if #report.missing == 0 then return nil end
    return "hook target missing: " .. table.concat(report.missing, ", ")
end

function M.install(deps)
    local rt_register = assert(deps.rt_register, "rt_register is required")
    local print_log = assert(deps.print_log, "print_log is required")
    local lookup = assert(deps.lookup, "lookup is required")
    rt_register(M.CHECK_NAME, function()
        local report = M.census(lookup)
        pcall(print_log, "[mp:1671] hook targets resolved=%d missing=%d deferred=%d " ..
            "deferred_classes=%s", report.resolved, #report.missing, #report.deferred,
            #report.deferred > 0 and table.concat(report.deferred, ",") or "none")
        return M.failure(report)
    end)
end

return M
