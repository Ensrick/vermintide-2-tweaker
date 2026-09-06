return function(Harness, repo_root)
    local policy = dofile(repo_root .. "/character_dialogue/scripts/mods/character_dialogue/_cd_policy.lua")
    local browser = dofile(repo_root .. "/character_dialogue/scripts/mods/character_dialogue/_cd_browser.lua")
    local preview = dofile(repo_root .. "/character_dialogue/scripts/mods/character_dialogue/_cd_preview_policy.lua")
    local residency = dofile(repo_root .. "/character_dialogue/scripts/mods/character_dialogue/_cd_preview_residency.lua")
    local dialogue_ui = dofile(repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_dialogue.lua")
    local transcript = dofile(repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_dialogue_transcript.lua")

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

    Harness.test("cd 931 groups conversations by stem in play order", function()
        Harness.equal("pbw_taunt_warlord", browser.conversation_for({ "pbw_taunt_warlord_02" }))
        Harness.equal("pes_no_ordinal", browser.conversation_for({ "pes_no_ordinal" }),
            "an event without a trailing ordinal is its own conversation")
        Harness.equal(2, browser.line_order({ "pbw_taunt_warlord_02" }))
        Harness.equal(0, browser.line_order({ "pes_no_ordinal" }))

        -- Deliberately out of order, and ordinal 10 present so a STRING sort
        -- would wrongly place it before 2.
        local entries = {
            { "pes_talk_10", "s10", "g", "empire_soldier", 1 },
            { "pes_talk_02", "s02", "g", "empire_soldier", 1 },
            { "pes_talk_01", "s01", "g", "empire_soldier", 1 },
        }
        local index = browser.build_conversation_index(entries, {})
        local page = browser.conversation_page(index, "pes_talk", "", 0, 99)
        Harness.equal(3, #page)
        Harness.equal("pes_talk_01", page[1].event, "play order is numeric, not lexical")
        Harness.equal("pes_talk_02", page[2].event)
        Harness.equal("pes_talk_10", page[3].event)
        Harness.equal("Markus Kruber", page[1].speaker_label,
            "rows carry the character name now that headers are stems")
    end)

    Harness.test("cd 931 hero variants of one topic sort adjacent", function()
        -- Lexically pbw < pes < pwh, so a naive sort would interleave these with
        -- any unrelated stem sharing a prefix. Topic-first keeps the exchange together.
        local entries = {
            { "pwh_hub_conversation_01", "a", "g", "witch_hunter", 1 },
            { "pbw_alpha_unrelated_01", "b", "g", "bright_wizard", 1 },
            { "pbw_hub_conversation_01", "c", "g", "bright_wizard", 1 },
        }
        local index = browser.build_conversation_index(entries, {})
        local groups = browser.conversation_groups(index, "")
        Harness.equal(3, #groups)
        Harness.equal("pbw_alpha_unrelated", groups[1].id, "topic ordering, not raw stem ordering")
        Harness.equal("pbw_hub_conversation", groups[2].id)
        Harness.equal("pwh_hub_conversation", groups[3].id,
            "both speakers' halves of hub_conversation land next to each other")
    end)

    Harness.test("cd 931 search matches spoken words, not just the codename", function()
        local entries = {
            { "pwh_hub_conversation_01", "sub_tingle", "g", "witch_hunter", 1 },
            { "pes_unrelated_01", "sub_other", "g", "empire_soldier", 1 },
        }
        -- tuple[2] is a localization KEY. Without resolved prose a player
        -- searching what they HEARD can never match; that was the #605 report.
        local bare = browser.build_conversation_index(entries, {})
        Harness.equal(0, #browser.conversation_groups(bare, "does it tingle"),
            "key-only index cannot match spoken words")

        local index = browser.build_conversation_index(entries,
            { pwh_hub_conversation_01 = "Does it tingle, Saltzpyre?" })
        local groups = browser.conversation_groups(index, "does it tingle")
        Harness.equal(1, #groups, "transcript search finds the line")
        Harness.equal("pwh_hub_conversation", groups[1].id)
        -- The codename must keep working too: notfuegonasus asked for BOTH.
        Harness.equal(1, #browser.conversation_groups(index, "hub_conversation"),
            "codename search must still work alongside transcript search")
        local page = browser.conversation_page(index, "pwh_hub_conversation", "tingle", 0, 99)
        Harness.equal("Does it tingle, Saltzpyre?", page[1].transcript,
            "resolved prose rides the page item for inline display")
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

    Harness.test("cd 998 isolation owners mute once and restore only on last release", function()
        local empty = preview.isolation_new()
        local one, act = preview.isolation_acquire(empty, preview.PREVIEW_OWNER)
        Harness.equal("mute", act, "first owner in must mute")
        Harness.truthy(one ~= empty, "membership change returns a new set")

        local again, act_again = preview.isolation_acquire(one, preview.PREVIEW_OWNER)
        Harness.equal("none", act_again)
        Harness.equal(one, again, "re-acquire is identity: no phantom double-hold")

        local both, act_manual = preview.isolation_acquire(one, preview.MANUAL_OWNER)
        Harness.equal("none", act_manual, "second owner joins an existing mute silently")

        local manual_only, act_release = preview.isolation_release(both, preview.PREVIEW_OWNER)
        Harness.equal("none", act_release, "releasing one of two owners must NOT restore")
        Harness.equal(true, manual_only[preview.MANUAL_OWNER],
            "disabling the preview owner preserves manual ownership")

        local none_left, act_last = preview.isolation_release(manual_only, preview.MANUAL_OWNER)
        Harness.equal("restore", act_last, "last owner out restores the saved volumes")
        Harness.equal(nil, next(none_left))

        local same, act_absent = preview.isolation_release(none_left, preview.PREVIEW_OWNER)
        Harness.equal("none", act_absent)
        Harness.equal(none_left, same, "releasing a non-holder is identity: no double restore")
    end)

    Harness.test("cd 998 preview lifecycle edges never leak or flicker the mute", function()
        -- Behavioral session simulator over the REAL policy: an engine stand-in
        -- counts the mute/restore actions the runtime would apply to Wwise.
        local function session()
            local owners, counts = preview.isolation_new(), { mute = 0, restore = 0 }
            local function apply(owner, edge)
                if edge == "acquire" then
                    local next_owners, action = preview.isolation_acquire(owners, owner)
                    owners = next_owners
                    if action == "mute" then counts.mute = counts.mute + 1 end
                elseif edge == "release" then
                    local next_owners, action = preview.isolation_release(owners, owner)
                    owners = next_owners
                    if action == "restore" then counts.restore = counts.restore + 1 end
                end
            end
            return {
                preview_event = function(event, auto)
                    apply(preview.PREVIEW_OWNER, preview.isolation_edge(event, auto))
                end,
                manual = function(edge) apply(preview.MANUAL_OWNER, edge) end,
                held = function() return next(owners) ~= nil end,
                counts = counts,
            }
        end

        -- Play then natural completion / manual stop: exactly one mute+restore.
        local s = session()
        s.preview_event("play", true)
        s.preview_event("stop", true)
        Harness.equal(1, s.counts.mute); Harness.equal(1, s.counts.restore)
        Harness.equal(false, s.held(), "termination must leave no owner behind")

        -- Pause and resume hold ownership: no volume flicker mid-session.
        s = session()
        s.preview_event("play", true)
        s.preview_event("pause", true)
        s.preview_event("resume", true)
        Harness.equal(1, s.counts.mute); Harness.equal(0, s.counts.restore)
        s.preview_event("stop", true)
        Harness.equal(1, s.counts.restore)

        -- Replacement holds the token across the swap: one mute total, and the
        -- restore count stays zero until the real stop (no flicker, no leak).
        s = session()
        s.preview_event("play", true)
        s.preview_event("replace", true)
        Harness.equal(0, s.counts.restore, "replacement must not flicker restore->mute")
        s.preview_event("play", true)
        Harness.equal(1, s.counts.mute, "re-acquire after a held replace is not a second mute")
        s.preview_event("stop", true)
        Harness.equal(1, s.counts.restore)

        -- A play attempt that dies after the replacement teardown releases.
        s = session()
        s.preview_event("play", true)
        s.preview_event("replace", true)
        s.preview_event("play_failed", true)
        Harness.equal(1, s.counts.restore); Harness.equal(false, s.held())

        -- Toggle disabled: playback drives no isolation at all.
        s = session()
        s.preview_event("play", false)
        s.preview_event("stop", false)
        Harness.equal(0, s.counts.mute); Harness.equal(0, s.counts.restore)

        -- Disabling the toggle mid-session restores once; the later natural
        -- stop must not double-restore.
        s = session()
        s.preview_event("play", true)
        s.preview_event("disable", false)
        Harness.equal(1, s.counts.restore)
        s.preview_event("stop", false)
        Harness.equal(1, s.counts.restore, "stop after disable must not restore twice")

        -- Composition: manual isolation survives the whole preview session and
        -- the disable edge; only the manual release restores.
        s = session()
        s.manual("acquire")
        s.preview_event("play", true)
        s.preview_event("disable", false)
        s.preview_event("stop", false)
        Harness.equal(0, s.counts.restore, "manual ownership must survive preview teardown")
        s.manual("release")
        Harness.equal(1, s.counts.mute); Harness.equal(1, s.counts.restore)
    end)

    Harness.test("cd issue 881 maps only audited Morris dialogue to one bounded package", function()
        Harness.equal("resource_packages/dlcs/morris_ingame", residency.MORRIS_PACKAGE)
        Harness.equal("character_dialogue_preview", residency.REFERENCE)
        Harness.equal(residency.MORRIS_PACKAGE,
            residency.package_for_source("hero_conversations_dlc_morris_ingame"))
        Harness.equal(residency.MORRIS_PACKAGE,
            residency.package_for_source("hero_conversations_dlc_morris_extras"))
        Harness.equal(residency.MORRIS_PACKAGE,
            residency.package_for_source("hero_conversations_dlc_morris_pat_tower"))
        Harness.equal(nil, residency.package_for_source("hero_conversations_dlc_holly"))
        Harness.equal(nil, residency.package_for_source("hub_conversations_morris"))
        Harness.equal(nil, residency.package_for_source(nil))
    end)

    Harness.test("cd issue 881 replaces one pending click and bounds package wait", function()
        local state = residency.new_state()
        local action, event, package_name = residency.request(state, "first",
            "hero_conversations_dlc_morris_ingame", false, false)
        Harness.equal("load", action); Harness.equal(nil, event)
        Harness.equal(residency.MORRIS_PACKAGE, package_name)
        state.acquired = true

        action = residency.request(state, "second",
            "hero_conversations_dlc_morris_pat_tower", false, true)
        Harness.equal("pending", action)
        Harness.equal("second", state.pending_event, "latest click must replace the pending event")
        action = residency.poll(state, 0.25, false, true)
        Harness.equal("pending", action)
        action, event = residency.poll(state, 0.25, true, false)
        Harness.equal("ready", action); Harness.equal("second", event)
        Harness.equal(nil, state.pending_event)

        action, event = residency.request(state, "resident",
            "hero_conversations_dlc_morris_extras", true, false)
        Harness.equal("direct", action); Harness.equal("resident", event)

        action = residency.request(state, "timeout",
            "hero_conversations_dlc_morris_ingame", false, true)
        Harness.equal("pending", action)
        action, event = residency.poll(state, residency.TIMEOUT_SECONDS, false, true)
        Harness.equal("failed", action); Harness.equal("timeout", event)
        Harness.equal(nil, state.pending_event)

        action, event = residency.request(state, "vanilla",
            "hero_conversations_dlc_holly", false, false)
        Harness.equal("direct", action); Harness.equal("vanilla", event)
        residency.cancel(state)
        Harness.equal(nil, state.package); Harness.equal(false, state.acquired)
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

    -- ------------------------------------------------------------------
    -- #880 mouseover transcript preview popups. These tests drive the REAL
    -- DialogueUI.build over the REAL browser policy with engine-free stubs:
    -- rows come back carrying the popup binding the shared #207 hover
    -- pipeline consumes (_tip_title / _tip_desc / _tip_prefer_below).
    -- ------------------------------------------------------------------
    local ROW_H = browser.ROW_HEIGHT

    local function make_entries(count)
        local entries = {}
        for i = 1, count do
            local id = string.format("pes_line_%02d", i)
            entries[i] = { id, "sub_" .. id, "pes_group_" .. math.ceil(i / 4), "empire_soldier", 2.5 }
        end
        return entries
    end

    local function make_localizer(book, counter)
        return function(key)
            counter.calls = counter.calls + 1
            local hit = book[key]
            if hit ~= nil then return hit end
            return "<" .. key .. ">"
        end
    end

    -- #605 Mirrors the PRODUCTION v4 contract: groups are conversation stems and
    -- page items carry speaker_label + resolved transcript. `localize` is
    -- optional and, when given, builds the transcript map exactly as the mod
    -- does, so search-by-spoken-words is exercised against real policy code.
    local function make_api(entries, localize)
        local transcripts = {}
        if localize then
            for i = 1, #entries do
                local key = entries[i][2]
                if type(key) == "string" and key ~= "" then
                    local ok, text = pcall(localize, key)
                    if ok and type(text) == "string" and text ~= "" and text ~= key
                       and text:sub(1, 1) ~= "<" then
                        transcripts[entries[i][1]] = text
                    end
                end
            end
        end
        local index = browser.build_conversation_index(entries, transcripts)
        return {
            version = 4,
            browser_groups = function(query) return browser.conversation_groups(index, query or "") end,
            browser_page = function(stem, query, offset, limit)
                return browser.conversation_page(index, stem, query or "", offset, limit)
            end,
            browser_window = browser.window,
            browser_reconcile_focus = browser.reconcile_focus,
            browser_row_height = browser.ROW_HEIGHT,
            get_line_state = function() return nil end,
            stop = function() end,
        }
    end

    local function make_defs()
        local function pop(base)
            local y = base[2] - ROW_H
            base[2] = y
            return y
        end
        return {
            create_dialogue_row = function(text, state_text_value, base)
                pop(base)
                return { content = { label = text, state_text = state_text_value,
                    state_hotspot = {}, media_hotspot = {}, row_hs = {} }, style = {} }
            end,
            create_group_header = function(text, _, base)
                pop(base)
                return { content = { label = text, hotspot = {} }, style = {} }
            end,
            create_section_title = function(text, base)
                pop(base)
                return { content = { label = text }, style = {} }
            end,
            -- #998 the automatic-isolation Yes/No control row.
            create_checkbox = function(text, base)
                pop(base)
                return {
                    content = { label = text, flag = false, hotspot = {}, dec = {}, inc = {} },
                    style = { label = { text_color = { 255, 255, 255, 255 } } },
                }
            end,
        }
    end

    local function make_view(localize)
        local view = {
            _rows = {}, _search_str = "", _scroll_y = 0,
            _visible_h = ROW_H * 8,
            _dialogue_localize = localize,
            _pending = {},
        }
        function view:get_staged(_, id, live)
            if self._pending[id] ~= nil then return self._pending[id] end
            return live
        end
        function view:stage_set(_, id, value) self._pending[id] = value end
        function view:_recompute_scroll_bounds() self._max_scroll = 1000000000 end
        return view
    end

    -- DialogueUI.build reads get_mod (cd api + gut's dofile for the transcript
    -- binder) and math.clamp. Stub both, restore both, rethrow on failure.
    local function with_build_env(api, body)
        local saved_get_mod = rawget(_G, "get_mod")
        local saved_clamp = math.clamp
        local owner = { character_dialogue_api = api, get = function() end,
            set = function() end, on_settings_batch_changed = function() end }
        _G.get_mod = function(id)
            if id == "character_dialogue" then return owner end
            if id == "gut_dev" then
                return { dofile = function(_, path)
                    return dofile(repo_root .. "/gui_tweaker_dev/" .. path .. ".lua")
                end }
            end
            return nil
        end
        if not saved_clamp then
            math.clamp = function(value, lower, upper)
                if value < lower then return lower end
                if value > upper then return upper end
                return value
            end
        end
        local ok, err = pcall(body)
        _G.get_mod = saved_get_mod
        math.clamp = saved_clamp
        if not ok then error(err, 0) end
    end

    local function run_build(view, api)
        view._rows = {}
        dialogue_ui.build(view, { mod_id = "character_dialogue" }, make_defs())
    end

    Harness.test("cd 880 hover popup binds the row under the cursor across scroll offsets", function()
        local entries = make_entries(40)
        local book = {}
        for i = 1, #entries do book[entries[i][2]] = "Spoken line " .. i end
        local counter = { calls = 0 }
        local api = make_api(entries)
        with_build_env(api, function()
            local view = make_view(make_localizer(book, counter))
            view._dialogue_expanded = "pes_line"
            for _, scroll in ipairs({ 0, 5 * ROW_H, 20 * ROW_H }) do
                view._scroll_y = scroll
                run_build(view, api)
                local first = view._dialogue_virtual_first
                local last = view._dialogue_virtual_last
                local line_rows = 0
                for i = 1, #view._rows do
                    local row = view._rows[i]
                    if row._is_dialogue_line then
                        line_rows = line_rows + 1
                        -- one visible group (kruber), so line offset = sequence - 2
                        local entry = entries[row._dialogue_sequence - 1]
                        Harness.equal(entry[1], row._dialogue_event)
                        Harness.equal(entry[1], row._tip_title, "popup title names the row's event")
                        Harness.truthy(row._tip_desc and row._tip_desc:find(book[entry[2]], 1, true) == 1,
                            "transcript must lead the popup body")
                        Harness.equal(true, row._tip_prefer_below, "popup anchors under the hovered row")
                    end
                end
                Harness.truthy(line_rows > 0, "window must contain line rows at scroll " .. scroll)
                Harness.truthy(line_rows <= math.ceil(view._visible_h / ROW_H) + 4,
                    "popup binding stays bounded by the virtual window")
                -- cursor simulation: the row occupying the cursor band is the
                -- catalogue entry the popup must describe.
                local target_sequence = first + 2
                Harness.truthy(target_sequence >= 2 and target_sequence <= last, "target must be a line row")
                local cursor_y = (-42 - (target_sequence - 1) * ROW_H) + ROW_H / 2
                local under
                for i = 1, #view._rows do
                    local row = view._rows[i]
                    local y = row._list_y or 0
                    if cursor_y >= y and cursor_y < y + ROW_H then under = row; break end
                end
                Harness.truthy(under, "a row must occupy the cursor band at scroll " .. scroll)
                Harness.equal(target_sequence, under._dialogue_sequence)
                Harness.equal(true, under._is_dialogue_line)
                local expected = entries[target_sequence - 1]
                Harness.equal(expected[1], under._dialogue_event, "row under cursor maps to the right entry")
                Harness.truthy(under._tip_desc:find(book[expected[2]], 1, true) == 1,
                    "row under cursor carries that entry's transcript")
            end
        end)
    end)

    Harness.test("cd 880 popup binds transcript with speaker metadata and suppresses unresolved keys", function()
        local echo = function(key) return key end
        Harness.equal(nil, transcript.resolve("k", nil), "missing localizer suppresses")
        Harness.equal(nil, transcript.resolve(nil, echo), "missing key suppresses")
        Harness.equal(nil, transcript.resolve("", echo), "empty key suppresses")
        Harness.equal(nil, transcript.resolve("k", echo), "raw key echo suppresses")
        Harness.equal(nil, transcript.resolve("k", function() return "<k>" end), "marker suppresses")
        Harness.equal(nil, transcript.resolve("k", function() error("boom") end), "localizer error suppresses")
        Harness.equal(nil, transcript.resolve("k", function() return 7 end), "non-string result suppresses")
        Harness.equal("Hello", transcript.resolve("k", function() return "Hello" end))
        Harness.equal("T\n\nMarkus Kruber - grp", transcript.compose("T", "Markus Kruber", "grp"))
        Harness.equal("T", transcript.compose("T", nil, nil))
        Harness.equal("T\n\nMarkus Kruber", transcript.compose("T", "Markus Kruber", ""))
        Harness.equal("T\n\ngrp", transcript.compose("T", "", "grp"))

        -- #605 One conversation stem (pes_line), three ordinals: resolved,
        -- marker-only, and key-echo. Grouping is by stem now, so three distinct
        -- stems would put these in three separate one-line groups.
        local entries = {
            { "pes_line_01", "sub_pes_line_01", "pes_talk", "empire_soldier", 2 },
            { "pes_line_02", "sub_pes_line_02", "pes_talk", "empire_soldier", 2 },
            { "pes_line_03", "sub_pes_line_03", "pes_talk", "empire_soldier", 2 },
        }
        local counter = { calls = 0 }
        local localize = function(key)
            counter.calls = counter.calls + 1
            if key == "sub_pes_line_01" then return "We march to war." end
            if key == "sub_pes_line_03" then return key end
            return "<" .. key .. ">"
        end
        local api = make_api(entries, localize)
        with_build_env(api, function()
            local view = make_view(localize)
            view._dialogue_expanded = "pes_line"
            run_build(view, api)
            local by_event, group_rows = {}, 0
            for i = 1, #view._rows do
                local row = view._rows[i]
                if row._is_dialogue_line then by_event[row._dialogue_event] = row end
                if row._is_dialogue_group then
                    group_rows = group_rows + 1
                    Harness.equal(nil, row._tip_desc, "group headers never carry the popup")
                end
            end
            local bound = by_event.pes_line_01
            Harness.truthy(bound and bound._tip_desc, "resolved subtitle must bind")
            Harness.equal("pes_line_01", bound._tip_title)
            Harness.equal("We march to war.\n\nMarkus Kruber - pes_talk", bound._tip_desc,
                "body = transcript, then speaker label - dialogue group")
            Harness.equal(nil, bound._tip_desc:find("pes_line_01", 1, true),
                "body must not restate the event id (the popup title owns it)")
            Harness.equal(true, bound._tip_prefer_below)
            Harness.truthy(by_event.pes_line_02, "unresolved line must still be in the window")
            Harness.equal(nil, by_event.pes_line_02._tip_desc, "marker key must not bind")
            Harness.equal(nil, by_event.pes_line_02._tip_prefer_below)
            Harness.equal(nil, by_event.pes_line_03._tip_desc, "echoed key must not bind")
            Harness.truthy(group_rows > 0)
        end)
    end)

    Harness.test("cd 880 popup reuses one widget and binds nothing in the hover path", function()
        local entries = make_entries(40)
        local book = {}
        for i = 1, #entries do book[entries[i][2]] = "Line " .. i end
        local counter = { calls = 0 }
        local api = make_api(entries)
        with_build_env(api, function()
            local view = make_view(make_localizer(book, counter))
            view._dialogue_expanded = "pes_line"
            run_build(view, api)
            local line_rows = {}
            for i = 1, #view._rows do
                local row = view._rows[i]
                if row._is_dialogue_line then line_rows[#line_rows + 1] = row end
            end
            local calls_after_build = counter.calls
            Harness.equal(#line_rows, calls_after_build, "one localize call per visible line row at build time")
            Harness.truthy(calls_after_build < #entries, "resolution is window-bounded, never catalogue-wide")
            -- N hover cycles: the capture path only READS the bound fields, and
            -- re-binding an unchanged (row, event) is a no-op.
            local sample = line_rows[1]
            local before = sample._tip_desc
            for _ = 1, 100 do
                for i = 1, #line_rows do
                    local _ = line_rows[i]._tip_desc
                end
                transcript.bind_row(sample, { event = sample._dialogue_event, subtitle = "ignored" },
                    "Markus Kruber", make_localizer(book, counter))
            end
            Harness.equal(calls_after_build, counter.calls, "no localizer traffic across 100 hover cycles")
            Harness.truthy(rawequal(before, sample._tip_desc), "bound body string is reused, not rebuilt")
        end)
        -- The popup WIDGET stays the view's single #207 tooltip: the dialogue
        -- modules never create their own, and both twin surfaces thread the
        -- #880 under-row anchor through the SAME shared layout call.
        local function slurp(rel)
            local f = assert(io.open(repo_root .. rel, "rb")); local s = f:read("*a"); f:close(); return s
        end
        local ui = slurp("/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_dialogue.lua")
        local binder_src = slurp("/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_dialogue_transcript.lua")
        Harness.equal(nil, ui:find("create_tooltip_popup", 1, true), "dialogue renderer must not own a popup widget")
        Harness.equal(nil, binder_src:find("create_tooltip_popup", 1, true), "binder must not own a popup widget")
        local view_src = slurp("/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_view_interaction.lua")
        local state_src = slurp("/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_state_interaction.lua")
        Harness.truthy(view_src:find("row._tip_prefer_below", 1, true), "standalone view must thread the #880 anchor")
        Harness.truthy(state_src:find("row._tip_prefer_below", 1, true), "hero-state twin must thread the #880 anchor")
        local defs_src = slurp("/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions.lua")
        local factory_pos = defs_src:find("local function create_dialogue_row", 1, true)
        local factory_end = defs_src:find("local function _append_highlight", 1, true)
        Harness.truthy(factory_pos and factory_end and factory_pos < factory_end)
        local row_hs_pos = defs_src:find('content_id = "row_hs"', factory_pos, true)
        Harness.truthy(row_hs_pos and row_hs_pos < factory_end,
            "dialogue rows need the hover-only row_hs capture surface")
        Harness.truthy(defs_src:find("prefer_below", 1, true), "layout_tooltip must accept the under-row anchor")
    end)

    Harness.test("cd 880 popup hides on leave and cannot target unbound rows", function()
        local entries = make_entries(6)
        local counter = { calls = 0 }
        local localize = make_localizer({ sub_pes_line_01 = "Only the first line speaks." }, counter)
        local api = make_api(entries)
        with_build_env(api, function()
            local view = make_view(localize)
            view._dialogue_expanded = "pes_line"
            run_build(view, api)
            -- Production capture predicate (twin _draw loops): a row is the popup
            -- target only while hovered AND carrying a non-empty body.
            local function popup_target(rows, cursor_y)
                for i = 1, #rows do
                    local row = rows[i]
                    local y = row._list_y or 0
                    local hovered = cursor_y ~= nil and cursor_y >= y and cursor_y < y + ROW_H
                    local rc = row.content
                    if rc and rc.row_hs then rc.row_hs.is_hover = hovered end
                    if rc and rc.hotspot then rc.hotspot.is_hover = hovered end
                end
                local target
                for i = 1, #rows do
                    local row = rows[i]
                    if row._tip_desc and row._tip_desc ~= "" then
                        local rc = row.content
                        if (rc.row_hs and rc.row_hs.is_hover) or (rc.hotspot and rc.hotspot.is_hover) then
                            target = row
                        end
                    end
                end
                return target
            end
            local bound_row, silent_row, header_row
            for i = 1, #view._rows do
                local row = view._rows[i]
                if row._dialogue_event == "pes_line_01" then bound_row = row end
                if row._dialogue_event == "pes_line_02" then silent_row = row end
                if row._is_dialogue_group then header_row = row end
            end
            Harness.truthy(bound_row and bound_row._tip_desc, "first line must bind")
            Harness.truthy(rawequal(bound_row, popup_target(view._rows, bound_row._list_y + ROW_H / 2)),
                "hovering the bound row targets its popup")
            Harness.equal(nil, popup_target(view._rows, 500), "cursor off every band hides the popup")
            Harness.equal(nil, popup_target(view._rows, nil), "no cursor hides the popup")
            Harness.truthy(silent_row, "second line must be in the window")
            Harness.equal(nil, silent_row._tip_desc)
            Harness.equal(nil, popup_target(view._rows, silent_row._list_y + ROW_H / 2),
                "hovering an unresolved line never shows a popup")
            Harness.truthy(header_row)
            Harness.equal(nil, popup_target(view._rows, header_row._list_y + ROW_H / 2),
                "hovering the group header never shows a popup")
            -- Collapse: a rebuild without an expanded group leaves zero
            -- popup-capable rows, so a stale popup cannot survive recycling.
            view._dialogue_expanded = nil
            run_build(view, api)
            for i = 1, #view._rows do
                Harness.equal(nil, view._rows[i]._tip_desc, "collapsed windows carry no transcript bindings")
            end
        end)
    end)

    -- ------------------------------------------------------------------
    -- #998 automatic-isolation control row. Drives the REAL DialogueUI over
    -- the REAL browser policy with an api v5 stand-in whose setter records
    -- calls, so the Yes/No control's rendering, sequence shift, and click
    -- semantics are exercised engine-free.
    -- ------------------------------------------------------------------
    local function make_isolation_api(entries)
        local api = make_api(entries)
        local store = { value = false, sets = 0 }
        api.version = 6
        api.isolation_setting = { version = 1, setting_id = "auto_isolation" }
        api.get_auto_isolation = function() return store.value end
        api.set_auto_isolation = function(v)
            store.value = v == true
            store.sets = store.sets + 1
            return store.value
        end
        api.auto_isolation_label = function() return "Isolate Audio During Playback" end
        return api, store
    end

    Harness.test("cd 998 window planner reserves lead control rows exactly", function()
        local groups = browser.groups({ { "pes_one", "", "", "empire_soldier" } }, "")
        local without = browser.window(groups, "kruber", 10, 0, 640, 2)
        local with_lead = browser.window(groups, "kruber", 10, 0, 640, 2, 1)
        Harness.equal(without.logical_count + 1, with_lead.logical_count)
        Harness.equal(without.expanded_line_start + 1, with_lead.expanded_line_start)
        Harness.equal(without.content_height + browser.ROW_HEIGHT, with_lead.content_height)
        local legacy = browser.window(groups, "kruber", 10, 0, 640, 2, nil)
        Harness.equal(without.logical_count, legacy.logical_count,
            "an absent lead count keeps the pre-998 planner")
    end)

    Harness.test("cd 998 Dialogue tab renders one draft-only isolation control", function()
        local entries = make_entries(6)
        local api, store = make_isolation_api(entries)
        local saved_printf = rawget(_G, "printf")
        _G.printf = function() end
        local ok, err = pcall(function()
            with_build_env(api, function()
                local view = make_view()
                view._dialogue_expanded = "pes_line"
                run_build(view, api)

                -- Row 1 is the control; the single group header lands at 2 and
                -- the expanded lines shift down by the one lead row.
                local control = view._rows[1]
                Harness.equal(true, control._dialogue_isolation)
                Harness.equal(false, control.content.flag, "control mirrors the stored No default")
                Harness.equal(1, control._dialogue_sequence)
                local header, line_rows = nil, 0
                for i = 1, #view._rows do
                    local row = view._rows[i]
                    if row._is_dialogue_group then header = row end
                    if row._is_dialogue_line and not row._dialogue_isolation then
                        line_rows = line_rows + 1
                        Harness.equal(entries[row._dialogue_sequence - 2][1], row._dialogue_event,
                            "line rows must map through the lead-shifted sequence")
                    end
                end
                Harness.truthy(header, "group header must render below the control")
                Harness.equal(2, header._dialogue_sequence)
                Harness.equal(6, line_rows)
                Harness.equal(1 + 1 + 6, view._dialogue_logical_count)

                -- Whole-row click stages once per press; it never calls the
                -- persistent API. Actual Apply composition has its own suite.
                control.content.hotspot.on_release = true
                Harness.equal(true, dialogue_ui.handle_row(view, control))
                Harness.equal(0, store.sets)
                Harness.equal(false, store.value)
                Harness.equal(true, control.content.flag)
                Harness.equal(false, dialogue_ui.handle_row(view, control),
                    "a held press must not re-toggle")
                Harness.equal(0, store.sets)
                control.content.hotspot.on_release = nil
                dialogue_ui.handle_row(view, control)
                control.content.hotspot.on_release = true
                Harness.equal(true, dialogue_ui.handle_row(view, control))
                Harness.equal(false, store.value, "second press toggles back to No")

                -- Draft false wins over an external live flip.
                store.value = true
                dialogue_ui.refresh_row(control, view)
                Harness.equal(false, control.content.flag)

                -- An empty search keeps the control and appends the notice.
                store.value = false
                view._search_str = "match_nothing_zzz"
                view._dialogue_expanded = nil
                run_build(view, api)
                Harness.equal(true, view._rows[1]._dialogue_isolation,
                    "empty result set must not evict the control row")
                Harness.equal(true, view._rows[2]._readonly, "no-match notice appends beneath it")
            end)
        end)
        _G.printf = saved_printf
        if not ok then error(err, 0) end
    end)

    Harness.test("cd 998 api without the isolation surface renders the pre-998 tab", function()
        local entries = make_entries(4)
        local api = make_api(entries)
        with_build_env(api, function()
            local view = make_view()
            view._dialogue_expanded = "pes_line"
            run_build(view, api)
            Harness.equal(nil, view._rows[1]._dialogue_isolation,
                "a v4 api must not grow a control row")
            Harness.equal(1 + 4, view._dialogue_logical_count)
            for i = 1, #view._rows do
                local row = view._rows[i]
                if row._is_dialogue_line then
                    Harness.equal(entries[row._dialogue_sequence - 1][1], row._dialogue_event)
                end
            end
        end)
    end)
end
