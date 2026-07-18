return function(H, repo_root)
    local policy_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mission_vote_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    H.test("GUT issue 700 promotes only live Adventure game-settings votes", function()
        H.equal(Policy.needs_ingame_hud(
            "game_settings_vote", "adventure", "military", false), true)
        H.equal(Policy.needs_ingame_hud(
            "game_settings_vote", "adventure", "dlc_dwarf_whaling", false), true)

        H.equal(Policy.needs_ingame_hud(
            "game_settings_vote", "adventure", "inn_level", true), false)
        H.equal(Policy.needs_ingame_hud(
            "game_settings_vote", "deus", "military", false), false)
        H.equal(Policy.needs_ingame_hud(
            "game_settings_vote", "adventure", nil, false), false)
        H.equal(Policy.needs_ingame_hud(
            "kick_player", "adventure", "military", false), false)
    end)

    H.test("GUT issue 700 keeps the bridge and runtime check wired", function()
        local module_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mission_map.lua"
        local file = assert(io.open(module_path, "rb"))
        local source = file:read("*a")
        file:close()

        H.truthy(source:find('mod:hook("VoteManager", "_server_start_vote"', 1, true),
            "VoteManager server vote-start hook missing")
        H.truthy(source:find('mod:hook("VoteManager", "_start_vote_base"', 1, true),
            "VoteManager client vote-start hook missing")
        H.truthy(source:find("template.ingame_vote = true", 1, true),
            "per-vote input/HUD promotion missing")
        H.truthy(source:find('type(active_template) == "table"', 1, true),
            "malformed active-template guard missing")
        H.truthy(source:find("local function _pack_returns(...)", 1, true),
            "full-wrapper return packing missing")
        local _, forwarded_return_count = source:gsub(
            "return unpack%(returns, 1, returns%.n%)", "")
        H.equal(forwarded_return_count, 2,
            "both full wrappers must preserve the complete return tuple")
        H.truthy(source:find("issue700_mission_vote_client_popup", 1, true),
            "runtime regression registration missing")
        H.truthy(source:find("verify_gut_mission_vote", 1, true),
            "verification command missing")
        H.truthy(source:find("_gut_consolidated_server_vote_start_hook", 1, true),
            "server singleton-hook marker missing")
        H.truthy(source:find("_gut_consolidated_client_vote_start_hook", 1, true),
            "client singleton-hook marker missing")
    end)
end
