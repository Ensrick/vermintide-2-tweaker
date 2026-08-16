return function(H, repo_root)
    local Missions = dofile(repo_root .. "/event_tweaker/scripts/mods/event_tweaker/event_tweaker_missions.lua")

    local function fixtures()
        local levels = {
            dlc_dwarf_fest = {
                level_id = "dlc_dwarf_fest", act = "act_celebrate",
                packages = { "resource_packages/levels/dlcs/dwarf_fest/dlc_dwarf_fest" },
            },
            dlc_celebrate_crawl = {
                level_id = "dlc_celebrate_crawl", act = "act_celebrate",
                packages = { "resource_packages/levels/dlcs/celebrate/crawl" },
            },
            prologue = {
                level_id = "prologue", act = "prologue", game_mode = "tutorial",
                packages = { "resource_packages/levels/honduras/prologue" },
            },
            control_level = {
                level_id = "control_level", act = "act_1", packages = { "control" },
            },
        }
        local areas = { celebrate = { acts = { "act_celebrate" }, exclude_from_area_selection = true } }
        local acts = { act_celebrate = { sorting = 2 } }
        return levels, areas, acts
    end

    H.test("Event mission allowlist is closed to the three audited levels", function()
        H.equal(#Missions.ALLOWLIST, 3)
        H.equal(Missions.ALLOWLIST[1].id, "dlc_dwarf_fest")
        H.equal(Missions.ALLOWLIST[2].id, "dlc_celebrate_crawl")
        H.equal(Missions.ALLOWLIST[3].id, "prologue")
        H.equal(Missions.ALLOWLIST[1].projected, nil)
        H.equal(Missions.ALLOWLIST[2].projected, nil)
        H.equal(Missions.ALLOWLIST[3].projected, true)
        H.equal(Missions.ALLOWLIST[3].solo_only, true)
    end)

    H.test("Event mission filter enables both missions and preserves a control act", function()
        local levels = fixtures()
        local control = { levels.control_level }
        local original = { act_1 = control, act_celebrate = { { level_id = "future_event" } } }
        local enabled = {
            mission_dlc_dwarf_fest = true,
            mission_dlc_celebrate_crawl = true,
        }
        local out = Missions.filter_levels_by_act(original, levels, function(id) return enabled[id] end)
        H.equal(#out.act_celebrate, 2)
        H.equal(out.act_celebrate[1], levels.dlc_dwarf_fest)
        H.equal(out.act_celebrate[2], levels.dlc_celebrate_crawl)
        H.equal(out.act_1, control)
        H.equal(original.act_celebrate[1].level_id, "future_event")
    end)

    H.test("Event mission filter honors individual toggles and never admits a control", function()
        local levels = fixtures()
        local out = Missions.filter_levels_by_act({}, levels, function(id)
            return id == "mission_dlc_celebrate_crawl"
        end)
        H.equal(#out.act_celebrate, 1)
        H.equal(out.act_celebrate[1].level_id, "dlc_celebrate_crawl")
        H.equal(out.act_celebrate[1] == levels.control_level, false)
    end)

    H.test("Event mission filter changes only the selected celebrate area", function()
        local levels = fixtures()
        local control = { levels.control_level }
        local original = { act_1 = control, act_celebrate = { { level_id = "future_event" } } }
        local enabled = {
            mission_dlc_dwarf_fest = true,
            mission_dlc_celebrate_crawl = true,
        }
        local get = function(id) return enabled[id] end

        local helmgart, helmgart_applied = Missions.filter_levels_for_area(
            "helmgart", original, levels, get)
        H.equal(helmgart_applied, false)
        H.equal(helmgart, original)
        H.equal(helmgart.act_celebrate[1].level_id, "future_event")

        local unknown, unknown_applied = Missions.filter_levels_for_area(
            nil, original, levels, get)
        H.equal(unknown_applied, false)
        H.equal(unknown, original)

        local celebrate, celebrate_applied = Missions.filter_levels_for_area(
            Missions.AREA_KEY, original, levels, get)
        H.equal(celebrate_applied, true)
        H.equal(celebrate == original, false)
        H.equal(celebrate.act_1, control)
        H.equal(#celebrate.act_celebrate, 2)

        local malformed, malformed_applied = Missions.filter_levels_for_area(
            Missions.AREA_KEY, nil, levels, get)
        H.equal(malformed_applied, false)
        H.equal(malformed, nil)
    end)

    H.test("Event mission selected-area resolver covers both native parent shapes", function()
        local desktop = {
            parent = { get_selected_area_name = function() return Missions.AREA_KEY end },
        }
        local console = {
            _parent = { get_selected_area_name = function() return "helmgart" end },
        }
        H.equal(Missions.selected_area_name(desktop), Missions.AREA_KEY)
        H.equal(Missions.selected_area_name(console), "helmgart")
        H.equal(Missions.selected_area_name({ parent = {} }), nil)
        H.equal(Missions.selected_area_name({
            parent = { get_selected_area_name = function() error("foreign proxy") end },
        }), nil)
    end)

    H.test("Event Tweaker owns one hook per event-area and mission-list surface", function()
        local function read(path)
            local file = assert(io.open(path, "rb"))
            local source = file:read("*a")
            file:close()
            return source
        end
        local event_source = read(repo_root
            .. "/event_tweaker/scripts/mods/event_tweaker/_evt_missions.lua")
        local _, area_desktop = event_source:gsub(
            'mod:hook%("StartGameWindowAreaSelection", "_setup_area_widgets"', "")
        local _, area_console = event_source:gsub(
            'mod:hook%("StartGameWindowAreaSelectionConsoleV2", "_setup_area_widgets"', "")
        local _, mission_desktop = event_source:gsub(
            'mod:hook%("StartGameWindowMissionSelection", "_setup_level_acts"', "")
        local _, mission_console = event_source:gsub(
            'mod:hook%("StartGameWindowMissionSelectionConsole", "_setup_level_acts"', "")
        local _, presentation_desktop = event_source:gsub(
            'mod:hook%("StartGameWindowAreaSelection", "_set_area_presentation_info"', "")
        local _, presentation_console = event_source:gsub(
            'mod:hook%("StartGameWindowAreaSelectionConsoleV2", "_set_area_presentation_info"', "")
        H.equal(area_desktop, 1)
        H.equal(area_console, 1)
        H.equal(mission_desktop, 1)
        H.equal(mission_console, 1)
        H.equal(presentation_desktop, 1)
        H.equal(presentation_console, 1)
        H.truthy(event_source:find("Missions.selected_area_name(self)", 1, true))
        local _, area_adapter_calls = event_source:gsub("Missions%.run_area_setup%(", "")
        local _, mission_adapter_calls = event_source:gsub("Missions%.apply_levels_for_area%(", "")
        H.equal(area_adapter_calls, 1)
        H.equal(mission_adapter_calls, 1)
        H.truthy(event_source:find("area_hooks=%d mission_hooks=%d", 1, true))

    end)

    H.test("Event area setup keeps Campaign first and restores the stock descriptor", function()
        local campaign = {
            name = "helmgart", sort_order = 1, acts = { "act_1" },
            level_image = "area_icon_helmgart",
        }
        local stock_event = {
            name = Missions.AREA_KEY, sort_order = 0,
            exclude_from_area_selection = true,
            acts = { Missions.ACT_KEY }, level_image = "area_icon_bogenhafen",
        }
        local areas = {
            helmgart = campaign,
            celebrate = stock_event,
            dwarf_fest = {
                name = "dwarf_fest", sort_order = 0,
                exclude_from_area_selection = true,
                level_image = "area_icon_dwarf_fest",
            },
            dlc = { name = "dlc", sort_order = 7, acts = { "act_dlc" } },
        }
        local view = {}
        local signatures = {}
        local ok, err, emit, proof = Missions.run_area_setup(function(self)
            local transient = areas.celebrate
            H.equal(transient == stock_event, false)
            H.equal(transient.exclude_from_area_selection, false)
            H.equal(transient.sort_order, 8)
            H.equal(transient.level_image, "level_image_dlc_dwarf_fest")
            H.equal(areas.helmgart, campaign)
            self._active_area_widgets = {
                { content = { area_name = "helmgart" } },
                { content = { area_name = "dlc" } },
                { content = { area_name = Missions.AREA_KEY } },
            }
        end, view, "desktop", areas, signatures)

        H.equal(ok, true)
        H.equal(err, nil)
        H.equal(emit, true)
        H.equal(areas.celebrate, stock_event)
        H.equal(areas.helmgart, campaign)
        H.equal(stock_event.exclude_from_area_selection, true)
        H.equal(stock_event.sort_order, 0)
        H.equal(stock_event.level_image, "area_icon_bogenhafen")
        H.truthy(proof:find("call_ok=true", 1, true))
        H.truthy(proof:find("widgets=3 target=1 campaign_index=1 event_index=3", 1, true))
        H.truthy(proof:find("presentation_sort=8", 1, true))
        H.truthy(proof:find("presentation_icon=level_image_dlc_dwarf_fest", 1, true))
        H.truthy(proof:find("stock_identity=true", 1, true))
    end)

    H.test("Event area setup skips stale widgets after a failed native build", function()
        local stock_event = {
            name = Missions.AREA_KEY, sort_order = 0,
            exclude_from_area_selection = true, acts = { Missions.ACT_KEY },
        }
        local areas = {
            celebrate = stock_event,
            helmgart = { name = "helmgart", sort_order = 1, acts = { "act_1" } },
        }
        local view = {
            _active_area_widgets = {
                { content = { area_name = Missions.AREA_KEY } },
            },
        }
        local ok, err, emit, proof = Missions.run_area_setup(function()
            error("native build failed")
        end, view, "controller", areas, {})

        H.equal(ok, false)
        H.truthy(tostring(err):find("native build failed", 1, true))
        H.equal(emit, true)
        H.equal(areas.celebrate, stock_event)
        H.equal(stock_event.exclude_from_area_selection, true)
        H.truthy(proof:find("call_ok=false", 1, true))
        H.truthy(proof:find("widgets=skipped", 1, true))
        H.equal(proof:find("target=1", 1, true), nil)
    end)

    H.test("Events presentation uses the resident Feast icon without mutating stock", function()
        local stock_event = {
            name = Missions.AREA_KEY, sort_order = 0,
            exclude_from_area_selection = true,
            level_image = "area_icon_bogenhafen",
            acts = { Missions.ACT_KEY },
        }
        local campaign = {
            name = "helmgart", sort_order = 1,
            level_image = "area_icon_helmgart", acts = { "act_1" },
        }
        local areas = { celebrate = stock_event, helmgart = campaign }
        local presentation = Missions.event_area_presentation(areas)
        H.equal(presentation.exclude_from_area_selection, false)
        H.equal(presentation.sort_order, 2)
        H.equal(presentation.level_image, "level_image_dlc_dwarf_fest")
        H.equal(presentation.acts, stock_event.acts)
        H.equal(areas.celebrate, stock_event)
        H.equal(areas.helmgart, campaign)
    end)

    H.test("Events copy changes only the selected view widgets", function()
        local desktop = {
            _widgets_by_name = {
                area_title = { content = { text = "old title" } },
                description_text = { content = { text = "old description" } },
            },
        }
        H.equal(Missions.apply_event_area_copy(
            desktop, "desktop", "Events", "Special missions"), true)
        H.equal(desktop._widgets_by_name.area_title.content.text, "Events")
        H.equal(desktop._widgets_by_name.description_text.content.text, "Special missions")

        local controller = {
            _widgets_by_name = {
                area_title = { content = { text = "old title" } },
                area_desc = {
                    content = { text = "old description" },
                    style = { text = { localize = true } },
                },
            },
        }
        Missions.prepare_area_copy(controller, "controller", true)
        H.equal(controller._widgets_by_name.area_desc.style.text.localize, false)
        H.equal(Missions.apply_event_area_copy(
            controller, "controller", "Events", "Special missions"), true)
        Missions.prepare_area_copy(controller, "controller", false)
        H.equal(controller._widgets_by_name.area_desc.style.text.localize, true)
        H.equal(Missions.apply_event_area_copy({}, "desktop", "Events", "Special missions"), false)
    end)

    H.test("Event diagnostic deduplication is independent per UI surface", function()
        local signatures = {}
        H.equal(Missions.should_emit_for_surface(signatures, "desktop", "same"), true)
        H.equal(Missions.should_emit_for_surface(signatures, "controller", "same"), true)
        H.equal(Missions.should_emit_for_surface(signatures, "desktop", "same"), false)
        H.equal(Missions.should_emit_for_surface(signatures, "controller", "same"), false)
        H.equal(Missions.should_emit_for_surface(signatures, "desktop", "changed"), true)
        H.equal(Missions.should_emit_for_surface(signatures, "controller", "same"), false)
    end)

    H.test("Event mission observation reads back assigned view state", function()
        local levels = fixtures()
        local original = { act_1 = { levels.control_level } }
        local view = { _levels_by_act = original }
        local enabled = {
            mission_dlc_dwarf_fest = true,
            mission_dlc_celebrate_crawl = true,
        }
        local applied, assigned, observed = Missions.apply_levels_for_area(
            view, Missions.AREA_KEY, levels, function(id) return enabled[id] end)

        H.equal(applied, true)
        H.equal(assigned, true)
        H.equal(observed, view._levels_by_act)
        H.equal(observed == original, false)
        H.equal(#observed.act_celebrate, 2)
        H.truthy(Missions.celebrate_level_proof(observed):find(
            "count=2 ids=[dlc_dwarf_fest,dlc_celebrate_crawl]", 1, true))
    end)

    H.test("Event mission observation exposes a rejected assignment", function()
        local levels = fixtures()
        local original = { act_1 = { levels.control_level } }
        local proxy = setmetatable({}, {
            __index = function(_, key)
                if key == "_levels_by_act" then return original end
            end,
            __newindex = function() end,
        })
        local applied, assigned, observed = Missions.apply_levels_for_area(
            proxy, Missions.AREA_KEY, levels, function() return true end)

        H.equal(applied, true)
        H.equal(assigned, false)
        H.equal(observed, original)
        H.equal(Missions.celebrate_level_proof(observed), "count=missing ids=[]")
    end)

    H.test("Event mission contract ignores NetworkLookup and accepts the menu-read shape", function()
        local levels, areas, acts = fixtures()
        local ok, problems = Missions.validate_contract(levels, areas, acts)
        H.equal(ok, true)
        H.equal(#problems, 0)
    end)

    H.test("Event mission contract fails closed on missing menu-read tables", function()
        local levels, areas, acts = fixtures()
        levels.dlc_dwarf_fest = nil
        local ok, problems = Missions.validate_contract(levels, areas, acts)
        H.equal(ok, false)
        H.truthy(table.concat(problems, ";"):find("LevelSettings.dlc_dwarf_fest missing", 1, true))

        local levels2, areas2, acts2 = fixtures()
        areas2.celebrate.acts = {}
        local ok2, problems2 = Missions.validate_contract(levels2, areas2, acts2)
        H.equal(ok2, false)
        H.truthy(table.concat(problems2, ";"):find("AreaSettings.celebrate lacks act_celebrate", 1, true))

        local levels3, areas3, acts3 = fixtures()
        acts3.act_celebrate.sorting = nil
        local ok3, problems3 = Missions.validate_contract(levels3, areas3, acts3)
        H.equal(ok3, false)
        H.truthy(table.concat(problems3, ";"):find("ActSettings.act_celebrate.sorting not a number", 1, true))
    end)

    H.test("Campaign registration fallback is a no-op on a vanilla-complete install", function()
        local levels = fixtures()
        local unlockable = { "control_level", "dlc_dwarf_fest", "dlc_celebrate_crawl" }
        local game_acts = { act_celebrate = { "dlc_dwarf_fest", "dlc_celebrate_crawl" }, act_1 = { "control_level" } }
        local map_acts = { "act_1", "act_celebrate" }
        local appended = Missions.ensure_campaign_registration(levels, unlockable, game_acts, map_acts)
        H.equal(#appended, 0)
        H.equal(#unlockable, 3)
        H.equal(#game_acts.act_celebrate, 2)
        H.equal(#map_acts, 2)
    end)

    H.test("Campaign registration fallback appends missing entries idempotently", function()
        local levels = fixtures()
        local unlockable = { "control_level" }
        local game_acts = { act_1 = { "control_level" } }
        local map_acts = { "act_1" }
        local appended = Missions.ensure_campaign_registration(levels, unlockable, game_acts, map_acts)
        H.equal(#appended, 5)
        H.truthy(table.concat(appended, ";"):find("UnlockableLevels+dlc_dwarf_fest", 1, true))
        H.truthy(table.concat(appended, ";"):find("GameActs.act_celebrate+dlc_celebrate_crawl", 1, true))
        H.truthy(table.concat(appended, ";"):find("MapPresentationActs+act_celebrate", 1, true))
        H.equal(#unlockable, 3)
        H.equal(#game_acts.act_celebrate, 2)
        H.equal(#map_acts, 2)
        H.equal(game_acts.act_1[1], "control_level")

        local appended2 = Missions.ensure_campaign_registration(levels, unlockable, game_acts, map_acts)
        H.equal(#appended2, 0)
        H.equal(#unlockable, 3)
        H.equal(#game_acts.act_celebrate, 2)
        H.equal(#map_acts, 2)
    end)

    H.test("Projected Prologue is shown through a copy that never touches the source", function()
        local levels = fixtures()
        local entry = Missions.entry_for("prologue")
        local source = levels.prologue
        local projected = Missions.project_level(source, entry)

        H.equal(projected == source, false)
        H.equal(projected.act, Missions.ACT_KEY)
        H.equal(projected.level_id, "prologue")
        H.equal(projected.game_mode, "tutorial")
        H.equal(projected.packages, source.packages)
        H.equal(projected.act_presentation_order, Missions.PROJECTED_PRESENTATION_ORDER)

        H.equal(source.act, "prologue")
        H.equal(source.act_presentation_order, nil)
        H.equal(source.level_id, "prologue")
    end)

    H.test("A native allowlist entry is still passed through by identity", function()
        local levels = fixtures()
        local entry = Missions.entry_for("dlc_dwarf_fest")
        H.equal(Missions.project_level(levels.dlc_dwarf_fest, entry), levels.dlc_dwarf_fest)
        H.equal(Missions.project_level(nil, entry), nil)
    end)

    H.test("Projected Prologue keeps an inherited presentation order", function()
        local entry = Missions.entry_for("prologue")
        local source = {
            level_id = "prologue", act = "prologue", game_mode = "tutorial",
            act_presentation_order = 3, packages = { "pkg" },
        }
        H.equal(Missions.project_level(source, entry).act_presentation_order, 3)
    end)

    H.test("Enabling the Prologue adds the copy to the event act, not the source", function()
        local levels = fixtures()
        local out = Missions.filter_levels_by_act({}, levels, function(id)
            return id == "mission_prologue"
        end)
        H.equal(#out.act_celebrate, 1)
        H.equal(out.act_celebrate[1].level_id, "prologue")
        H.equal(out.act_celebrate[1] == levels.prologue, false)
        H.equal(out.act_celebrate[1].act, Missions.ACT_KEY)
        H.equal(levels.prologue.act, "prologue")
    end)

    H.test("Event mission contract accepts the Prologue in its own act and game mode", function()
        local levels, areas, acts = fixtures()
        local ok = Missions.validate_contract(levels, areas, acts)
        H.equal(ok, true)

        local moved, moved_areas, moved_acts = fixtures()
        moved.prologue.act = "act_celebrate"
        local moved_ok, moved_problems = Missions.validate_contract(moved, moved_areas, moved_acts)
        H.equal(moved_ok, false)
        H.truthy(table.concat(moved_problems, ";"):find("LevelSettings.prologue.act mismatch", 1, true))

        local retuned, retuned_areas, retuned_acts = fixtures()
        retuned.prologue.game_mode = "adventure"
        local retuned_ok, retuned_problems = Missions.validate_contract(retuned, retuned_areas, retuned_acts)
        H.equal(retuned_ok, false)
        H.truthy(table.concat(retuned_problems, ";"):find("LevelSettings.prologue.game_mode mismatch", 1, true))

        local unpackaged, unpackaged_areas, unpackaged_acts = fixtures()
        unpackaged.prologue.packages = {}
        local unpackaged_ok, unpackaged_problems = Missions.validate_contract(
            unpackaged, unpackaged_areas, unpackaged_acts)
        H.equal(unpackaged_ok, false)
        H.truthy(table.concat(unpackaged_problems, ";"):find("LevelSettings.prologue.packages empty", 1, true))
    end)

    H.test("Campaign registration never absorbs the projected Prologue", function()
        local levels = fixtures()
        local unlockable = { "control_level", "prologue" }
        local game_acts = { act_1 = { "control_level" }, prologue = { "prologue" } }
        local map_acts = { "act_1", "prologue" }
        local appended = Missions.ensure_campaign_registration(levels, unlockable, game_acts, map_acts)

        H.equal(table.concat(appended, ";"):find("prologue", 1, true), nil)
        H.equal(#game_acts.act_celebrate, 2)
        H.equal(#game_acts.prologue, 1)
        H.equal(#unlockable, 4)
        H.equal(levels.prologue.act, "prologue")
    end)

    H.test("Projected mission presentation never localizes a nil description", function()
        local levels = fixtures()
        local seen, calls = nil, 0
        local applied, restored = Missions.run_presentation_info(function(view, level_id)
            calls = calls + 1
            H.equal(level_id, "prologue")
            seen = levels.prologue.description_text
        end, { surface = "view" }, "prologue", levels, "evt_level_description_prologue")

        H.equal(calls, 1)
        H.equal(applied, true)
        H.equal(restored, true)
        H.equal(seen, "evt_level_description_prologue")
        H.equal(levels.prologue.description_text, nil)
    end)

    H.test("Projected mission presentation restores the source after a raising call", function()
        local levels = fixtures()
        local ok, err = pcall(Missions.run_presentation_info, function()
            error("native presentation failed")
        end, {}, "prologue", levels, "evt_level_description_prologue")

        H.equal(ok, false)
        H.truthy(tostring(err):find("native presentation failed", 1, true))
        H.equal(levels.prologue.description_text, nil)
    end)

    H.test("Projected mission presentation stands aside for everything else", function()
        local levels = fixtures()
        local calls = 0
        local function native() calls = calls + 1 end

        local native_applied = Missions.run_presentation_info(
            native, {}, "dlc_dwarf_fest", levels, "evt_level_description_prologue")
        H.equal(native_applied, false)

        local unselected = Missions.run_presentation_info(
            native, {}, nil, levels, "evt_level_description_prologue")
        H.equal(unselected, false)

        local no_id = Missions.run_presentation_info(native, {}, "prologue", levels, nil)
        H.equal(no_id, false)

        levels.prologue.description_text = "already_localized"
        local already = Missions.run_presentation_info(
            native, {}, "prologue", levels, "evt_level_description_prologue")
        H.equal(already, false)
        H.equal(levels.prologue.description_text, "already_localized")
        H.equal(calls, 4)
    end)

    H.test("Solo-only launch policy refuses a shared lobby and leaves others alone", function()
        H.equal(Missions.is_solo_only("prologue"), true)
        H.equal(Missions.is_solo_only("dlc_dwarf_fest"), false)
        H.equal(Missions.is_solo_only("helmgart"), false)

        H.equal(Missions.solo_launch_verdict("custom", "prologue", 1), "allow")
        H.equal(Missions.solo_launch_verdict("adventure_mode", "prologue", 1), "allow")
        H.equal(Missions.solo_launch_verdict("custom", "prologue", 2), "blocked_not_solo")
        H.equal(Missions.solo_launch_verdict("custom", "prologue", 4), "blocked_not_solo")
        H.equal(Missions.solo_launch_verdict("custom", "prologue", nil), "allow_unverified")

        H.equal(Missions.solo_launch_verdict("custom", "dlc_dwarf_fest", 4), "not_managed")
        H.equal(Missions.solo_launch_verdict("adventure", "prologue", 4), "not_managed")
        H.equal(Missions.solo_launch_verdict("weave_quick_play", "prologue", 4), "not_managed")
        H.equal(Missions.solo_launch_verdict("deed", "prologue", 4), "not_managed")
        H.equal(Missions.solo_launch_verdict("custom", nil, 1), "not_managed")
    end)

    H.test("Solo-only search config is hardened onto the private host path", function()
        local config = {
            mission_id = "prologue", private_game = false, always_host = false,
            quick_game = true, strict_matchmaking = true, dedicated_server = true,
            difficulty = "normal",
        }
        local applied, proof = Missions.harden_search_config(config)
        H.equal(applied, true)
        H.equal(config.private_game, true)
        H.equal(config.always_host, true)
        H.equal(config.quick_game, false)
        H.equal(config.strict_matchmaking, false)
        H.equal(config.dedicated_server, false)
        H.equal(config.join_method, "solo")
        H.equal(config.difficulty, "normal")
        H.equal(config.mission_id, "prologue")
        H.truthy(proof:find("private_game=true", 1, true))
        H.truthy(proof:find("always_host=true", 1, true))

        local untouched = { mission_id = "dlc_dwarf_fest", private_game = false, quick_game = true }
        H.equal(Missions.harden_search_config(untouched), false)
        H.equal(untouched.private_game, false)
        H.equal(untouched.quick_game, true)
        H.equal(untouched.join_method, nil)
        H.equal(Missions.harden_search_config(nil), false)
        H.equal(Missions.harden_search_config({}), false)
    end)

    H.test("Campaign registration fallback never registers a malformed level", function()
        local levels = fixtures()
        levels.dlc_dwarf_fest.packages = {}
        levels.dlc_celebrate_crawl = nil
        local unlockable = {}
        local game_acts = {}
        local map_acts = {}
        local appended = Missions.ensure_campaign_registration(levels, unlockable, game_acts, map_acts)
        H.equal(#appended, 0)
        H.equal(#unlockable, 0)
        H.equal(#map_acts, 0)
    end)
end
