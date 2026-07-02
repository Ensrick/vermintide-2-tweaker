-- _gt_weave_unlock.lua (v0.2.108-dev)
-- ============================================================
-- One default-OFF, CLIENT-SIDE toggle ("gt_unlock_all_weaves"): unlock every
-- ranked weave in the Winds of Magic weave ladder so the player can pick and
-- play any weave without grinding the progression.
--
-- Mechanism: vanilla gates weave SELECTION and JOINING on
-- LevelUnlockUtils.weave_unlocked (level_unlock_settings.lua:490), which returns
-- true only for weaves you have COMPLETED (plus the next consecutive one). Every
-- weave surface routes through it:
--   * start_game_window_weave_list.lua:504        (host weave picker)
--   * start_game_state_settings_overview.lua:132  (selected-weave confirm)
--   * start_game_window_lobby_browser.lua:1229    (joining a weave lobby)
--   * lobby_item_list.lua:580                      (lobby-list entries)
-- so a single hook covers both hosting and joining. When the toggle is ON we
-- return true for any weave whose DLC the player OWNS -- we replicate vanilla's
-- own dlc gate (level_unlock_settings.lua:503-509), so this unlocks PROGRESSION
-- only and never bypasses the Winds of Magic paywall (repo CLAUDE.md "DLC
-- Ownership Gate" doctrine). Toggle off -> pure vanilla.
--
-- Source-verified 2026-06-19 against Vermintide-2-Source-Code. Single-hook
-- pre-flight (CLAUDE.md): grep confirmed gt has 0 existing hooks on
-- LevelUnlockUtils.weave_unlocked before adding this.
-- ============================================================

local mod = get_mod("gt_dev")

if rawget(_G, "LevelUnlockUtils") then
    mod:hook("LevelUnlockUtils", "weave_unlocked", function(func, statistics_db, player_stats_id, weave_name, ignore_dlc_check, num_players)
        if not mod:get("gt_unlock_all_weaves") then
            return func(statistics_db, player_stats_id, weave_name, ignore_dlc_check, num_players)
        end

        -- Toggle ON: treat the weave as unlocked, but keep vanilla's DLC gate so
        -- Winds of Magic ownership is still required (progression unlock, NOT a
        -- paid-content bypass). Mirrors level_unlock_settings.lua:503-509 exactly.
        local templates = rawget(_G, "WeaveSettings") and WeaveSettings.templates
        local weave_data = templates and templates[weave_name]
        if not weave_data then
            -- Unknown weave key: let vanilla handle it (it logs + returns false).
            return func(statistics_db, player_stats_id, weave_name, ignore_dlc_check, num_players)
        end

        if not ignore_dlc_check then
            local dlc_name = weave_data.dlc_name
            if dlc_name and Managers.unlock and not Managers.unlock:is_dlc_unlocked(dlc_name) then
                return false
            end
        end

        return true
    end)
end
