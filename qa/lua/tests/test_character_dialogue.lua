return function(Harness, repo_root)
    local policy = dofile(repo_root .. "/character_dialogue/scripts/mods/character_dialogue/_cd_policy.lua")
    local browser = dofile(repo_root .. "/character_dialogue/scripts/mods/character_dialogue/_cd_browser.lua")
    local preview = dofile(repo_root .. "/character_dialogue/scripts/mods/character_dialogue/_cd_preview_policy.lua")
    local dialogue_ui = dofile(repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_dialogue.lua")

    local dialogue = { sound_events_n = 3, sound_events = { "a", "b", "c" } }

    Harness.test("cd dialogue groups close and line states retain false", function()
        Harness.equal("kruber", dialogue_ui.next_expanded(nil, "kruber"))
        Harness.equal(nil, dialogue_ui.next_expanded("kruber", "kruber"))
        Harness.equal("bardin", dialogue_ui.next_expanded("kruber", "bardin"))

        Harness.equal(true, dialogue_ui.next_line_state(nil))
        Harness.equal(false, dialogue_ui.next_line_state(true))
        Harness.equal(nil, dialogue_ui.next_line_state(false))

        Harness.equal(true, policy.parse_override_state("enable"))
        Harness.equal(false, policy.parse_override_state("disable"))
        Harness.equal(nil, policy.parse_override_state("default"))
    end)

    Harness.test("cd policy leaves unmodified groups on vanilla path", function()
        local index, used = policy.choose_index(dialogue, {}, function() return 1 end, function() return true end)
        Harness.equal(nil, index)
        Harness.equal(false, used)
    end)

    Harness.test("cd policy bounds rejection and skips disabled lines", function()
        local order, cursor = { 1, 2, 3 }, 0
        local index, used = policy.choose_index(dialogue, { a = false }, function()
            cursor = cursor + 1
            return order[cursor]
        end, function(i) return i == 3 end)
        Harness.equal(3, index)
        Harness.equal(true, used)
        Harness.equal(3, cursor)
    end)

    Harness.test("cd explicit enable bypasses vanilla line filter", function()
        local cursor = 0
        local index = policy.choose_index(dialogue, { b = true }, function()
            cursor = cursor + 1
            return cursor
        end, function() return false end)
        Harness.equal(2, index)
    end)

    Harness.test("cd all-disabled groups are suppressible", function()
        Harness.equal(true, policy.all_disabled(dialogue, { a = false, b = false, c = false }))
        Harness.equal(false, policy.all_disabled(dialogue, { a = false, b = true, c = false }))
        Harness.equal(false, policy.all_disabled(dialogue, { a = false, c = false }))
    end)

    Harness.test("cd catalogue contains unique stable events", function()
        local path = repo_root .. "/character_dialogue/scripts/mods/character_dialogue/character_dialogue_catalogue.lua"
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a")
        f:close()
        local seen, count = {}, 0
        for event in source:gmatch('{"([^"]+)",') do
            Harness.equal(nil, seen[event], "duplicate dialogue event: " .. event)
            seen[event], count = true, count + 1
        end
        Harness.equal(34327, count)
    end)

    Harness.test("cd catalogue carries authored clip durations", function()
        local entries = dofile(repo_root .. "/character_dialogue/scripts/mods/character_dialogue/character_dialogue_catalogue.lua")
        local index = browser.build_index(entries)
        local timed = 0
        for i = 1, #entries do
            Harness.truthy(type(entries[i][5]) == "number" and entries[i][5] > 0,
                "missing authored duration for " .. tostring(entries[i][1]))
            timed = timed + 1
        end
        Harness.equal(34327, timed)
        Harness.equal(entries[1][5], browser.duration_for(index, entries[1][1], 4.5))
        Harness.equal(4.5, browser.duration_for(index, "not_catalogued", 4.5))
    end)

    Harness.test("cd browser groups by speaker and searches without flattening", function()
        local entries = {
            { "pes_hello", "subtitle_one", "heroes", "empire_soldier_keep" },
            { "pdr_hello", "subtitle_two", "heroes", "dwarf_ranger_keep" },
            { "ebb_attack", "enemy line", "enemy_group", "enemy_beastmen_vo" },
            { "nik_keep", "npc line", "ambient", "npc_keep" },
        }
        local groups = browser.groups(entries, "")
        local counts = {}
        for i = 1, #groups do counts[groups[i].id] = groups[i].count end
        Harness.equal(1, counts.kruber)
        Harness.equal(1, counts.bardin)
        Harness.equal(1, counts.enemy)
        Harness.equal(1, counts.npc)
        local filtered = browser.groups(entries, "subtitle_two")
        local kept = 0
        for i = 1, #filtered do if filtered[i].count > 0 then kept = kept + 1 end end
        Harness.equal(1, kept)
        Harness.equal(1, filtered[2].count, "search must retain Bardin grouping")
    end)

    Harness.test("cd production catalogue groups every event with exact hero ownership", function()
        local entries = dofile(repo_root .. "/character_dialogue/scripts/mods/character_dialogue/character_dialogue_catalogue.lua")
        local groups = browser.groups(entries, "")
        local counts, total = {}, 0
        for i = 1, #groups do counts[groups[i].id] = groups[i].count; total = total + groups[i].count end
        Harness.equal(34326, total)
        Harness.equal(6008, counts.kruber)
        Harness.equal(6247, counts.bardin)
        Harness.equal(5841, counts.kerillian)
        Harness.equal(6056, counts.saltzpyre)
        Harness.equal(5688, counts.sienna)
        Harness.equal(false, browser.is_browsable({ "dummy", "", "pbw_crater_dummy", "bright_wizard_crater" }))
        Harness.equal(true, browser.is_browsable({ "nde_real_dummy_event", "", "", "" }))
        Harness.equal("enemy", browser.speaker_for({ "ebh_boss_line", "", "", "dwarf_ranger_ground_zero" }),
            "source container must not misclassify an enemy as Bardin")
    end)

    Harness.test("cd pages have stable identity and a hard allocation cap", function()
        local entries = {}
        for i = 1, 100 do entries[i] = { "pes_line_" .. i, "s" .. i, "g", "empire_soldier", i / 10 } end
        local page, total = browser.page(entries, "kruber", "", 10, 9999)
        Harness.equal(100, total)
        Harness.equal(browser.PAGE_LIMIT, #page)
        Harness.equal("pes_line_11", page[1].id)
        Harness.equal(page[1].event, page[1].id)
        Harness.equal(1.1, page[1].duration)
        local index = browser.build_index(entries)
        local indexed, indexed_total = browser.index_page(index, "kruber", "", 10, 9999)
        Harness.equal(total, indexed_total)
        Harness.deep_equal(page, indexed)
        Harness.equal(100, index.total)
    end)

    Harness.test("cd virtual window bounds visible widget count", function()
        local groups = browser.groups({ { "pes_one", "", "", "empire_soldier" } }, "")
        groups[1].count = 34327
        local window = browser.window(groups, "kruber", 34327, 100000, 640, 2)
        Harness.truthy(window.count <= math.ceil(640 / browser.ROW_HEIGHT) + 4)
        Harness.equal(34328, window.logical_count)
    end)

    Harness.test("cd focus identity survives rebuild or reconciles deterministically", function()
        local index, id = browser.reconcile_focus({ "a", "b", "c" }, "b")
        Harness.equal(2, index); Harness.equal("b", id)
        index, id = browser.reconcile_focus({ "x", "y" }, "b")
        Harness.equal(1, index); Harness.equal("x", id)
    end)

    Harness.test("cd preview state has one owner and bounded lifecycle transitions", function()
        local state, stop_old = preview.transition({}, "play", "event_a")
        Harness.equal("event_a", state.event); Harness.equal(false, stop_old)
        state, stop_old = preview.transition(state, "play", "event_b")
        Harness.equal("event_b", state.event); Harness.equal(true, stop_old)
        state = preview.transition(state, "pause")
        Harness.equal(true, state.paused)
        state = preview.transition(state, "resume")
        Harness.equal(false, state.paused)
        state, stop_old = preview.transition(state, "stop")
        Harness.equal(nil, state.event); Harness.equal(true, stop_old)
        Harness.equal(0, preview.progress(0, 4))
        Harness.equal(0.5, preview.progress(2, 4))
        Harness.equal(1, preview.progress(20, 4))
        Harness.equal(0, preview.progress(2, 0))
    end)

    Harness.test("cd Mod Tweaker integration is grouped virtual media UI", function()
        local view_path = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_view_interaction.lua"
        local f = assert(io.open(view_path, "rb")); local source = f:read("*a"); f:close()
        view_path = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_view.lua"
        f = assert(io.open(view_path, "rb")); source = source .. f:read("*a"); f:close()
        local ui_path = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_dialogue.lua"
        f = assert(io.open(ui_path, "rb")); local ui = f:read("*a"); f:close()
        Harness.truthy(source:find("DialogueUI%.build"), "virtual browser build missing")
        Harness.truthy(source:find("DialogueUI%.refresh_window"), "scroll recycling missing")
        Harness.truthy(source:find("DialogueUI%.stop%(%)"), "view lifecycle cleanup missing")
        Harness.truthy(ui:find("create_dialogue_row"), "one-row media controls missing")
        Harness.truthy(ui:find("state_hotspot"), "per-line state control missing")
        Harness.truthy(ui:find("media_hotspot"), "single same-row media control missing")
        Harness.equal(nil, ui:find("play_hotspot", 1, true), "detached play control remains")
        Harness.equal(nil, ui:find("pause_hotspot", 1, true), "detached pause control remains")
        Harness.truthy(ui:find("media_is_playing"), "media glyph state missing")
        Harness.truthy(ui:find("progress_fill"), "active-row progress update missing")
        Harness.truthy(ui:find("value%.stop%(%)"), "collapse cleanup missing")
        local zero_pos = ui:find("if line_count == 0 then", 1, true)
        local stop_pos = zero_pos and ui:find("value.stop()", zero_pos, true)
        local clear_pos = zero_pos and ui:find("view._dialogue_expanded = nil", zero_pos, true)
        Harness.truthy(stop_pos and clear_pos and stop_pos < clear_pos and (clear_pos - zero_pos) < 500,
            "search-driven collapse must stop before clearing the active group")
        Harness.truthy(ui:find("browser_reconcile_focus"), "stable focus is not consumed by runtime")
        Harness.truthy(ui:find("query_changed"), "filter rebuild focus reconciliation missing")
        Harness.truthy(ui:find('get%("move_up"'), "controller vertical focus missing")
        Harness.truthy(ui:find('get%("move_left"'), "controller control focus missing")
        Harness.truthy(ui:find('get%("confirm"'), "controller activation missing")
    end)

    Harness.test("cd polls one Wwise owner with exact elapsed milliseconds", function()
        local cd_path = repo_root .. "/character_dialogue/scripts/mods/character_dialogue/character_dialogue.lua"
        local f = assert(io.open(cd_path, "rb")); local cd = f:read("*a"); f:close()
        local ui_path = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_dialogue.lua"
        f = assert(io.open(ui_path, "rb")); local ui = f:read("*a"); f:close()
        Harness.truthy(cd:find("WwiseWorld%.get_playing_elapsed"), "exact Wwise elapsed poll missing")
        Harness.truthy(cd:find("elapsed_ms / 1000", 1, true), "Wwise milliseconds are not converted to seconds")
        Harness.truthy(cd:find("WwiseWorld%.is_playing"), "Wwise completion authority missing")
        Harness.truthy(ui:find("value%.preview_state%(%)"), "single frame-level preview poll missing")
        local _, polls = ui:gsub("preview_state", "")
        Harness.equal(1, polls, "preview state must be polled once, not per visible row")
    end)

    Harness.test("cd owns the browser API and does not allocate a 34k dropdown", function()
        local path = repo_root .. "/character_dialogue/scripts/mods/character_dialogue/character_dialogue.lua"
        local f = assert(io.open(path, "rb")); local source = f:read("*a"); f:close()
        Harness.truthy(source:find("browser_groups"))
        Harness.truthy(source:find("browser_page"))
        Harness.truthy(source:find("browser_reconcile_focus"))
        Harness.truthy(source:find('type = "dialogue_browser"'))
        Harness.equal(nil, source:find("dialogue_options"), "legacy full dropdown allocator remains")
    end)

    Harness.test("cd resolves Fatshark module-local hook targets before VMF hook install", function()
        local path = repo_root .. "/character_dialogue/scripts/mods/character_dialogue/character_dialogue.lua"
        local f = assert(io.open(path, "rb")); local source = f:read("*a"); f:close()
        local require_pos = source:find('local DialogueQueries = require%("scripts/entity_system/systems/dialogues/dialogue_queries"%)')
        local hook_pos = source:find('mod:hook%(DialogueQueries, "get_filtered_dialogue_event_index"')
        Harness.truthy(require_pos, "DialogueQueries module require missing")
        Harness.truthy(hook_pos, "DialogueQueries hook missing")
        Harness.truthy(require_pos < hook_pos, "DialogueQueries must resolve before VMF hook install")
    end)
end
