-- Central GUT diagnostics home (PROJECT_STANDARDS 2.2b). Issue-specific probes
-- live here while open and are retired when their issue closes.
local mod = get_mod("gut_dev")
local Policy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_scoreboard_policy")
local HolderPolicy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_career_hud_holder_policy")
local M = { rt_checks = {} }

local HERO_CAREERS = {
    "bw_adept", "bw_necromancer", "bw_scholar", "bw_unchained",
    "dr_engineer", "dr_ironbreaker", "dr_ranger", "dr_slayer",
    "es_huntsman", "es_knight", "es_mercenary", "es_questingknight",
    "we_maidenguard", "we_shade", "we_thornsister", "we_waywatcher",
    "wh_bountyhunter", "wh_captain", "wh_priest", "wh_zealot",
}

local CAP = 4
local records = 0
local pending_frames = 0
local pending_attempt = 0
local holder_records = 0

local function _catalog()
    local helper = rawget(_G, "ScoreboardHelper")
    if type(helper) ~= "table" then return nil, "ScoreboardHelper missing" end
    local result = Policy.inspect_catalog(helper.scoreboard_topic_stats,
        helper.scoreboard_grouped_topic_stats)
    return result, helper
end

local function _emit_static(reason)
    if records >= CAP then return false end
    records = records + 1
    local catalog, helper = _catalog()
    local external = get_mod("reikland-scoreboard") ~= nil
    if not catalog then
        printf("[gut:272] probe=%d/%d reason=%s helper=missing external_tab_scoreboard=%s",
            records, CAP, tostring(reason), tostring(external))
        return false
    end
    printf("[gut:272] probe=%d/%d reason=%s topics=%d grouped=%d engine_num=%s malformed=%d duplicate=%d unresolved=%d external_tab_scoreboard=%s",
        records, CAP, tostring(reason), catalog.topic_count, catalog.grouped_count,
        tostring(helper.num_stats_per_player), catalog.malformed_count,
        catalog.duplicate_count, catalog.unresolved_count, tostring(external))
    printf("[gut:272] native_topics=%s",
        table.concat(catalog.names, ","))
    local definitions = rawget(_G, "StatisticsDefinitions")
    local coverage = Policy.inspect_hotjoin_coverage(
        helper.scoreboard_topic_stats,
        definitions and definitions.player)
    printf("[gut:272] hotjoin covered=%d gaps=%s unresolved=%s",
        #coverage.covered, table.concat(coverage.gaps, ","),
        table.concat(coverage.unresolved, ","))
    printf("[gut:272] requested_gap custom_accumulation=friendly_fire_damage,healing_amount,melee_damage,ranged_damage native_extra=aidings,times_revived persistent_only=times_friend_healed")
    return true
end

local function _emit_live(reason)
    if records >= CAP then return true end
    local managers = rawget(_G, "Managers")
    local player_manager = managers and managers.player
    local state = managers and managers.state
    local network = state and state.network
    local db = player_manager and player_manager.statistics_db and player_manager:statistics_db()
    local synchronizer = network and network.profile_synchronizer
    local helper = rawget(_G, "ScoreboardHelper")
    if not db or not synchronizer or type(helper) ~= "table"
            or type(helper.get_grouped_topic_statistics) ~= "function" then
        return false
    end

    local ok, players = pcall(helper.get_grouped_topic_statistics,
        db, synchronizer, nil)
    if not ok or type(players) ~= "table" then
        records = records + 1
        printf("[gut:272] probe=%d/%d reason=%s live_snapshot=error detail=%s",
            records, CAP, tostring(reason), tostring(players))
        return true
    end
    records = records + 1
    local snapshot = Policy.inspect_snapshot(players)
    local tab = rawget(_G, "IngamePlayerListUI")
    local ending = rawget(_G, "EndViewStateScore")
    printf("[gut:272] probe=%d/%d reason=%s live_snapshot=ready players=%d scores=%d malformed_players=%d nonnumeric=%d tab_class=%s end_class=%s",
        records, CAP, tostring(reason), snapshot.player_count,
        snapshot.score_count, snapshot.malformed_players,
        snapshot.nonnumeric_scores, tostring(type(tab) == "table"),
        tostring(type(ending) == "table"))
    return true
end

function M.capture(reason)
    _emit_static(reason or "manual")
    return _emit_live(reason or "manual")
end

local function _emit_holder_catalog(reason)
    if holder_records >= 2 then return end
    holder_records = holder_records + 1
    local settings = rawget(_G, "UISettings")
    local result = HolderPolicy.inspect(HERO_CAREERS,
        settings and settings.hud_inventory_panel_data)
    printf("[gut:442] holder census reason=%s careers=%d dedicated=%d fallback=%d malformed=%d missing_default=%s textures=%s",
        tostring(reason), result.career_count, result.dedicated_count,
        result.fallback_count, result.malformed_count,
        tostring(result.missing_default), table.concat(result.texture_ids, ","))
    printf("[gut:442] dedicated=%s fallback_needing_unique_art=%s seam=UISettings.hud_inventory_panel_data/EquipmentUI.background_panel",
        table.concat(result.dedicated, ","), table.concat(result.fallback, ","))
end

mod:command("gut_scoreboard_probe", "Capture bounded scoreboard capability diagnostics (#272)", function()
    M.capture("command")
end)

local prev_all_mods_loaded = mod.on_all_mods_loaded
mod.on_all_mods_loaded = function(...)
    if prev_all_mods_loaded then prev_all_mods_loaded(...) end
    _emit_static("all_mods_loaded")
    _emit_holder_catalog("all_mods_loaded")
end

local prev_game_state_changed = mod.on_game_state_changed
mod.on_game_state_changed = function(status, state_name)
    if prev_game_state_changed then prev_game_state_changed(status, state_name) end
    if status == "enter" and state_name == "StateIngame" then
        pending_frames = 180
        pending_attempt = 0
    end
end

local prev_update = mod.update
mod.update = function(dt)
    if prev_update then prev_update(dt) end
    if pending_frames <= 0 then return end
    pending_frames = pending_frames - 1
    pending_attempt = pending_attempt + 1
    if pending_attempt % 15 == 0 and _emit_live("StateIngame") then
        pending_frames = 0
    elseif pending_frames == 0 and records < CAP then
        records = records + 1
        printf("[gut:272] probe=%d/%d reason=StateIngame live_snapshot=not_ready attempts=%d",
            records, CAP, pending_attempt)
    end
end

M.rt_checks[#M.rt_checks + 1] = {
    name = "issue272_scoreboard_inventory_diagnostics",
    fn = function()
        local catalog, helper = _catalog()
        if not catalog then return helper end
        if catalog.topic_count ~= 11 or catalog.grouped_count ~= 11 then
            return string.format("vanilla scoreboard catalog drifted: topics=%d grouped=%d",
                catalog.topic_count, catalog.grouped_count)
        end
        if catalog.malformed_count ~= 0 or catalog.duplicate_count ~= 0
                or catalog.unresolved_count ~= 0 then
            return string.format("scoreboard catalog malformed=%d duplicate=%d unresolved=%d",
                catalog.malformed_count, catalog.duplicate_count,
                catalog.unresolved_count)
        end
        if helper.num_stats_per_player ~= catalog.grouped_count then
            return string.format("num_stats_per_player=%s grouped=%d",
                tostring(helper.num_stats_per_player), catalog.grouped_count)
        end
        local definitions = rawget(_G, "StatisticsDefinitions")
        local coverage = Policy.inspect_hotjoin_coverage(
            helper.scoreboard_topic_stats,
            definitions and definitions.player)
        if #coverage.unresolved ~= 0 then
            return "scoreboard hot-join definitions unresolved: "
                .. table.concat(coverage.unresolved, ",")
        end
        if #coverage.gaps ~= 1 or coverage.gaps[1] ~= "damage_dealt_bosses" then
            return "scoreboard hot-join gap drifted: " .. table.concat(coverage.gaps, ",")
        end
    end,
}

M.rt_checks[#M.rt_checks + 1] = {
    name = "issue442_career_hud_holder_capability",
    fn = function()
        local settings = rawget(_G, "UISettings")
        local result = HolderPolicy.inspect(HERO_CAREERS,
            settings and settings.hud_inventory_panel_data)
        if result.career_count ~= 20 then
            return "hero career catalog drifted: " .. tostring(result.career_count)
        end
        if result.missing_default or result.malformed_count ~= 0 then
            return string.format("holder catalog malformed=%d missing_default=%s",
                result.malformed_count, tostring(result.missing_default))
        end
        if result.dedicated_count ~= 2
                or table.concat(result.dedicated, ",") ~= "dr_engineer,wh_priest" then
            return "vanilla dedicated-holder catalog drifted: "
                .. table.concat(result.dedicated, ",")
        end
    end,
}

return M
