-- Career level-unlock policy, live UI refresh, and bounded diagnostics (#728).
--
-- The setting bypasses only ProgressionUnlocks.is_unlocked_for_profile. Vanilla
-- has already applied mechanism and DLC ownership gates before reaching this
-- function. Hero/profile occupancy remains owned by GameMechanismManager and is
-- deliberately not overridden.
local M = {}

local function bool_text(value)
    return value and "true" or "false"
end

local function safe_printf(...)
    if type(printf) == "function" then
        pcall(printf, ...)
    end
end

function M.install(mod)
    local unlock_decisions = {}
    local selection_summaries = {}
    local hero_summary_instance
    local character_selection_instance

    local function setting_enabled()
        return mod:get("unlock_all_careers") == true
    end

    local function log_unlock_decision(unlock_name, profile, level, enabled,
            unlocked, reason)
        local key = table.concat({
            tostring(unlock_name), tostring(profile), tostring(level),
            bool_text(enabled), bool_text(unlocked), tostring(reason),
        }, "|")
        if unlock_decisions[key] then return end
        unlock_decisions[key] = true
        safe_printf(
            "[crt:728] level_gate setting=%s unlock=%s profile=%s level=%s result=%s reason=%s",
            bool_text(enabled), tostring(unlock_name), tostring(profile),
            tostring(level), bool_text(unlocked), tostring(reason))
    end

    -- Consolidated owner for CRT's only ProgressionUnlocks hook. Preserve all
    -- four vanilla returns when disabled; UI callers consume reason/dlc/localized.
    mod:hook("ProgressionUnlocks", "is_unlocked_for_profile",
        function(func, unlock_name, profile, level)
            local enabled = setting_enabled()
            if enabled then
                log_unlock_decision(unlock_name, profile, level, true, true,
                    "crt_level_bypass")
                return true
            end
            local unlocked, reason, dlc_name, localized =
                func(unlock_name, profile, level)
            log_unlock_decision(unlock_name, profile, level, false,
                unlocked == true, reason)
            return unlocked, reason, dlc_name, localized
        end)

    mod:hook_safe("HeroWindowCharacterSummary", "on_enter", function(self)
        hero_summary_instance = self
    end)
    mod:hook_safe("HeroWindowCharacterSummary", "on_exit", function(self)
        if hero_summary_instance == self then hero_summary_instance = nil end
    end)

    mod:hook_safe("CharacterSelectionStateCharacter", "on_enter", function(self)
        character_selection_instance = self
    end)
    mod:hook_safe("CharacterSelectionStateCharacter", "on_exit", function(self)
        if character_selection_instance == self then
            character_selection_instance = nil
        end
    end)

    local function empire_profile_index()
        if type(SPProfiles) ~= "table" then return nil end
        for profile_index, profile in pairs(SPProfiles) do
            if type(profile) == "table"
                    and profile.display_name == "empire_soldier" then
                return profile_index
            end
        end
        return nil
    end

    local function profile_occupancy(self, profile_index)
        local available, reserved_by, party_id = nil, nil, nil
        pcall(function()
            local player = Managers.player:local_player()
            if not player then return end
            local peer_id = player:network_id()
            local _, resolved_party = Managers.party:get_party_from_unique_id(
                player:unique_id())
            party_id = resolved_party
            if Managers.mechanism and resolved_party then
                available = Managers.mechanism:profile_available_for_peer(
                    resolved_party, peer_id, profile_index)
            end
            local synchronizer = self and self.profile_synchronizer
            if synchronizer and synchronizer.get_profile_index_reservation
                    and resolved_party then
                reserved_by = synchronizer:get_profile_index_reservation(
                    resolved_party, profile_index)
            end
        end)
        return available, reserved_by, party_id
    end

    -- Runs only when vanilla rebuilds the character-selection grid (view enter,
    -- bot-order rebuild, or our explicit setting refresh), never per frame.
    mod:hook_safe("CharacterSelectionStateCharacter",
        "_setup_hero_selection_widgets", function(self)
            local profile_index = empire_profile_index()
            if not profile_index then return end
            local rows = {}
            for _, widget in ipairs(self._hero_widgets or {}) do
                local content = widget and widget.content
                local career = content and content.career_settings
                if career and career.profile_name == "empire_soldier" then
                    rows[#rows + 1] = string.format("%s:%s:%s",
                        tostring(career.name), bool_text(content.locked == true),
                        tostring(content.locked_reason))
                end
            end
            local available, reserved_by, party_id =
                profile_occupancy(self, profile_index)
            local digest = table.concat({
                bool_text(setting_enabled()), tostring(profile_index),
                tostring(party_id), tostring(available), tostring(reserved_by),
                table.concat(rows, ","),
            }, "|")
            if selection_summaries[digest] then return end
            selection_summaries[digest] = true
            safe_printf(
                "[crt:728] character_select setting=%s kruber_profile=%s party=%s available=%s reserved_by=%s careers=[%s]",
                bool_text(setting_enabled()), tostring(profile_index),
                tostring(party_id), tostring(available), tostring(reserved_by),
                table.concat(rows, ","))
        end)

    mod._crt_refresh_career_unlock_ui = function()
        local refreshed_summary, refreshed_selection = false, false
        if hero_summary_instance
                and hero_summary_instance._setup_hero_selection_widgets then
            refreshed_summary = pcall(
                hero_summary_instance._setup_hero_selection_widgets,
                hero_summary_instance)
        end
        local state = character_selection_instance
        if state and state._setup_hero_selection_widgets then
            refreshed_selection = pcall(
                state._setup_hero_selection_widgets, state)
            if refreshed_selection and state._selected_profile_index
                    and state._selected_career_index and state._select_hero then
                -- Rebuild replaces the widgets. Restore the current highlight
                -- without requesting a new profile or respawning the preview.
                pcall(state._select_hero, state, state._selected_profile_index,
                    state._selected_career_index, true, true)
            end
            if refreshed_selection and state._update_available_profiles then
                pcall(state._update_available_profiles, state)
            end
        end
        safe_printf(
            "[crt:728] ui_refresh setting=%s hero_summary=%s character_select=%s",
            bool_text(setting_enabled()), bool_text(refreshed_summary),
            bool_text(refreshed_selection))
        return refreshed_summary, refreshed_selection
    end

    safe_printf(
        "[crt:728] installed setting=%s scope=local_level_gate occupancy=vanilla",
        bool_text(setting_enabled()))
end

return M
