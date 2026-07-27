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
        local active = { name = "game_settings_vote" }
        H.equal(Policy.active_vote(active), active)
        H.equal(Policy.active_vote(nil), nil)
        H.equal(Policy.active_vote(false), nil)
        H.equal(Policy.active_vote(17), nil)
        H.equal(Policy.active_vote("game_settings_vote"), nil)
    end)

    H.test("GUT issue 700 promoted template localizes its HUD title without mutating vanilla", function()
        local vote_options = {
            { text = "popup_choice_accept" },
            { text = "dlc1_3_1_decline" },
        }
        local original = {
            text = "game_settings_vote",
            ingame_vote = false,
            priority = 110,
            vote_options = vote_options,
        }
        local promoted = Policy.promote_template(original, "Change Mission?")

        H.equal(original.ingame_vote, false)
        H.equal(original.modify_title_text, nil)
        H.equal(promoted.ingame_vote, true)
        H.equal(promoted.text, "game_settings_vote")
        H.equal(promoted.priority, 110)
        H.equal(promoted.vote_options, vote_options)
        H.equal(promoted.vote_options[1].text, "popup_choice_accept")
        H.equal(promoted.vote_options[2].text, "dlc1_3_1_decline")
        H.equal(type(promoted.modify_title_text), "function")
        H.equal(promoted.modify_title_text(""), "Change Mission?")
        H.equal(promoted._gut700_title_input, "")
        H.equal(promoted._gut700_title_output, "Change Mission?")
        H.equal(promoted._gut700_promoted, true)

        local authored = function(title) return title .. "!" end
        local preserved = Policy.promote_template({
            text = "game_settings_vote",
            modify_title_text = authored,
        }, "Change Mission?")
        H.equal(preserved.modify_title_text("Start Game"), "Start Game!")
        local blank_authored = Policy.promote_template({
            text = "game_settings_vote",
            modify_title_text = function() return "" end,
        }, "Change Mission?")
        H.equal(blank_authored.modify_title_text(""), "Change Mission?")
        local internal_authored = Policy.promote_template({
            text = "game_settings_vote",
            modify_title_text = function() return "another_internal_key" end,
        }, "Change Mission?")
        H.equal(internal_authored.modify_title_text(""), "Change Mission?")
        local throwing_authored = Policy.promote_template({
            text = "game_settings_vote",
            modify_title_text = function() error("localization drift") end,
        }, "Change Mission?")
        H.equal(throwing_authored.modify_title_text(""), "Change Mission?")
        H.equal(Policy.promote_template(original, nil), nil)
        H.equal(Policy.promote_template(original, "gut_mission_vote_title"), nil)
        H.equal(Policy.promote_template(original, "<gut_mission_vote_title>"), nil)
        H.equal(Policy.promote_template(original, "another_internal_key"), nil)
        H.equal(Policy.promote_template(original, "game_settings_vote"), nil)
        H.equal(Policy.promote_template(nil), nil)
    end)

    H.test("GUT issue 700 classifies the final title boundary", function()
        H.equal(Policy.usable_title("Change Mission?", "game_settings_vote"), true)
        H.equal(Policy.usable_title("", "game_settings_vote"), false)
        H.equal(Policy.usable_title("game_settings_vote", "game_settings_vote"), false)
        H.equal(Policy.usable_title("<game_settings_vote>", "game_settings_vote"), false)
        H.equal(Policy.usable_title("another_internal_key", "game_settings_vote"), false)
        H.equal(Policy.usable_title("<another_internal_key>", "game_settings_vote"), false)
        H.equal(Policy.usable_title("  another_internal_key  ",
            "game_settings_vote"), false)
        H.equal(Policy.title_boundary("game_settings_vote", "", "Change Mission?",
            "Change Mission?").result, "PASS")
        H.equal(Policy.title_boundary("game_settings_vote", "", "Change Mission?",
            "").result, "WIDGET_BLANK")
        H.equal(Policy.title_boundary("game_settings_vote", "Start Game", "",
            "").result, "MODIFIER_BLANK")
        H.equal(Policy.title_boundary("game_settings_vote", "", "", "").result,
            "SOURCE_BLANK")
    end)

    H.test("GUT issue 700 preserves complete wrapper tuples including nil holes", function()
        local packed = Policy.pack_returns("first", nil, "third", nil)
        H.equal(packed.n, 4)
        H.equal(packed[1], "first")
        H.equal(packed[2], nil)
        H.equal(packed[3], "third")
        H.equal(packed[4], nil)

        local forwarded = Policy.pack_returns(Policy.forward_returns(packed))
        H.equal(forwarded.n, 4)
        H.equal(forwarded[1], "first")
        H.equal(forwarded[2], nil)
        H.equal(forwarded[3], "third")
        H.equal(forwarded[4], nil)
        local malformed = Policy.pack_returns(Policy.forward_returns(false))
        H.equal(malformed.n, 1)
        H.equal(malformed[1], nil)
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
        H.truthy(source:find("VotePolicy.promote_template(active_template, resolved_title)", 1, true),
            "per-vote input/HUD/title promotion missing")
        H.truthy(source:find('mod:hook_safe("IngameVotingUI", "start_vote"', 1, true),
            "bounded final-title diagnostic hook missing")
        H.truthy(source:find("_gut700_reported_votes", 1, true),
            "one-record-per-vote diagnostic bound missing")
        H.truthy(source:find(
            'pcall(mod.localize, mod, "gut_mission_vote_title")', 1, true),
            "dedicated localized title fallback missing")
        H.truthy(source:find("pcall(localize, source_key)", 1, true),
            "native localization must fail closed")
        H.truthy(source:find('type(active_template) == "table"', 1, true),
            "malformed active-template guard missing")
        H.truthy(source:find('type(active_voting) ~= "table"', 1, true),
            "malformed diagnostic vote guard missing")
        H.truthy(source:find("VotePolicy.active_vote(candidate)", 1, true),
            "promotion must normalize malformed active-vote shapes")
        local _, pack_count = source:gsub(
            "VotePolicy%.pack_returns%(", "")
        H.equal(pack_count, 2,
            "both full wrappers must pack the complete return tuple")
        local _, forwarded_return_count = source:gsub(
            "return VotePolicy%.forward_returns%(returns%)", "")
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
        H.truthy(source:find(
            'type(ingame_voting_ui.start_vote) ~= "function"', 1, true),
            "runtime regression must validate the final HUD title surface")
        H.truthy(source:find(
            "local title_ok, localized_title = pcall(", 1, true))
        H.truthy(source:find(
            'mod.localize, mod, "gut_mission_vote_title")', 1, true),
            "verification localization must remain protected")
        H.equal(source:find(
            'local localized_title = mod:localize("gut_mission_vote_title")',
            1, true), nil, "unprotected verification localization must stay absent")
        H.equal(source:find("NetworkLookup.voting_types[", 1, true), nil,
            "bridge must not append or replace NetworkLookup voting types")
    end)
end
