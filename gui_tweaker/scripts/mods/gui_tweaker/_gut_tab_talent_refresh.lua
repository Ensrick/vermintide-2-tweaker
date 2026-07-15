-- Repair Chaos Wastes talent presentation after vanilla populates held Tab (#250).
-- This module owns no hook: #245's existing player-list update hook calls it so
-- gut has one composable owner for the shared UI method.
local mod = get_mod("gut")
local Policy = mod:dofile("scripts/mods/gui_tweaker/_gut_tab_talent_policy")
local logged = {}
local log_count = 0

local function is_deus()
    local mechanism = Managers and Managers.mechanism
    return mechanism and mechanism:current_mechanism_name() == "deus"
end

local function career_tree(player, profile_name)
    local career_name = player and player.career_name and player:career_name()
    local career = career_name and CareerSettings and CareerSettings[career_name]
    local tree_index = career and career.talent_tree_index
    return tree_index and TalentTrees and TalentTrees[profile_name]
        and TalentTrees[profile_name][tree_index], career_name
end

local function refresh(self)
    if self._active ~= true or not is_deus() then return 0 end

    local changed = 0
    for index, player_data in ipairs(self._players or {}) do
        local player = player_data.player
        local unit = player and player.player_unit
        local widget = self._player_list_widgets and self._player_list_widgets[index]
        if unit and widget and ALIVE[unit] then
            local extension = ScriptUnit.has_extension(unit, "talent_system")
            local profile_name = player:profile_display_name()
            local tree, career_name = career_tree(player, profile_name)
            if extension and tree then
                local original = extension:get_talent_ids()
                local normalized, duplicates, unmapped =
                    Policy.normalize(original, tree, TalentIDLookup)
                if Policy.needs_repair(original, normalized) then
                    local content = widget.content
                    local visible = content.is_build_visible ~= false
                    for tier = 1, Policy.TIERS do
                        local id = normalized[tier]
                        local talent = id and TalentUtils.get_talent_by_id(profile_name, id)
                        local icon = talent and talent.icon
                        local cell = content["talent_" .. tier]
                        if cell then
                            cell.talent = visible and icon and talent or nil
                            cell.icon = visible and icon or "icons_placeholder"
                        end
                    end
                    changed = changed + 1

                    local signature = tostring(career_name) .. ":"
                        .. Policy.fingerprint(original) .. ">"
                        .. Policy.fingerprint(normalized)
                    if not logged[signature] and log_count < Policy.MAX_LOGS then
                        logged[signature] = true
                        log_count = log_count + 1
                        mod:info("[gut:250] career=%s active=%s tiers=%s duplicates=%d unmapped=%d repair=%d/%d",
                            tostring(career_name), Policy.fingerprint(original),
                            Policy.fingerprint(normalized), duplicates, unmapped,
                            log_count, Policy.MAX_LOGS)
                    end
                end
            end
        end
    end
    return changed
end

return {
    policy = Policy,
    refresh = refresh,
    rt_checks = {
        {
            name = "issue250_deus_tab_talent_tier_normalization",
            fn = function()
                if Policy.TIERS ~= 6 or Policy.MAX_LOGS > 16 then
                    return "talent tier/log bounds drifted"
                end
                local tree = { { "a" }, { "b" }, { "c" }, {}, { "e" }, { "f" } }
                local lookup = {
                    a = { talent_id = 11 }, b = { talent_id = 22 },
                    c = { talent_id = 33 }, e = { talent_id = 55 },
                    f = { talent_id = 66 },
                }
                local result, duplicates = Policy.normalize(
                    { 11, 22, 33, 55, 66, 22 }, tree, lookup)
                if result[4] ~= nil or result[5] ~= 55 or result[6] ~= 66
                    or duplicates ~= 1 then
                    return "tier normalization policy failed"
                end
                return nil
            end,
        },
    },
}
