return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"

local function read(name)
        if tostring(name):find("chaos_wastes_tweaker_dev.lua", 1, true) then
            return CTSource.expanded(repo_root)
        end
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local diag = read("_ct_diag_skull52.lua")
    local entry = read("chaos_wastes_tweaker_dev.lua")

    H.test("CT #52 Tower skull diagnostic is source-backed, not pickup-backed", function()
        H.truthy(diag:find('TARGET_LEVEL = "dlc_wizards_tower"', 1, true))
        H.truthy(diag:find("flow_callback_on_tower_skull_found", 1, true))
        H.truthy(diag:find("on_tower_skull_found", 1, true))
        H.truthy(diag:find('if not rawget(_G, "_ct_skull52_flow_wrapped") then M.install() end', 1, true))
        H.equal(diag:find("Pickups.level_events.gargoyle_head", 1, true), nil)
        H.equal(diag:find("mission_restore_the_gargoyle_heads", 1, true), nil)
        H.truthy(diag:find("not a guessed", 1, true))
    end)

    H.test("CT #52 object-set census records Adventure-vs-Deus comparison fields", function()
        for _, needle in ipairs({
            "mode=%s key=%s base=%s level_name=%s object_sets=%d spawned=%d cap=%d",
            "source=GameModeHelper.get_object_sets",
            "set=%s spawned=%s units=%d kind=%s suspect=%d",
            "LevelResource.unit_data",
            "unit_sample level_name=%s set=%s index=%s data=%s",
            "injected_base_from_key",
        }) do
            H.truthy(diag:find(needle, 1, true), "missing #52 diagnostic field: " .. needle)
        end
    end)

    H.test("CT #52 realized-level lifecycle separates spawn identity teardown and transition", function()
        for _, needle in ipairs({
            'mod:hook_safe("StateIngame", "_create_level"',
            'mod:hook("StateIngame", "_teardown_level"',
            'mod:hook_safe("GameModeManager", "_set_flow_object_set_enabled"',
            "lifecycle phase=%s index=%s live=%s identity_source=%s strong=%s sets=%s debug=%s",
            "missing=%d disappeared_since_create=%d interactables=%d identity_candidates=%d",
            "transition_mismatch selected_key=%s base=%s runtime_key=%s",
            "local ok, err = pcall(M.level_snapshot, self, \"pre_teardown\")",
            "active = nil",
        }) do
            H.truthy(diag:find(needle, 1, true), "missing #52 lifecycle field: " .. needle)
        end
    end)

    H.test("CT #52 production entry routes both modes through the target-scoped gate", function()
        local hook_start = assert(entry:find('mod:hook(_gmh, "get_object_sets"', 1, true))
        local observe_call = assert(entry:find("pcall(mod._ct_diag_skull52.observe_object_sets", hook_start, true))
        local deus_gate = assert(entry:find('if game_mode_key == "deus"', hook_start, true))
        local mutation = assert(entry:find('spawned_object_sets[#spawned_object_sets + 1] = "adventure"', hook_start, true))
        local finalize_call = assert(entry:find("pcall(mod._ct_diag_skull52.finalize_selection", hook_start, true))
        H.truthy(observe_call < deus_gate, "#52 observation must precede the Deus-only #156 mutation")
        H.truthy(deus_gate < mutation and mutation < finalize_call,
            "lifecycle selection must use the final array passed to AsyncLevelSpawner")
        H.equal(entry:find("pcall(mod._ct_diag_skull52.census", hook_start, true), nil,
            "entry must use the target-scoped observation surface")
    end)

    H.test("CT #52 fake level proves each lifecycle outcome is observable", function()
        local nil_sentinel = {}
        local global_names = {
            "get_mod", "printf", "Managers", "Level", "Unit", "ScriptUnit",
            "LevelResource", "LevelSettings", "_ct_skull52_flow_wrapped",
            "flow_callback_on_tower_skull_found",
        }
        local saved = {}
        for _, name in ipairs(global_names) do
            local value = rawget(_G, name)
            saved[name] = value == nil and nil_sentinel or value
        end

        local ok, err = pcall(function()
            local lines, hooks = {}, {}
            local original_flow_calls = 0
            local current_key = "dlc_wizards_tower"
            local units = {
                [11] = {
                    alive = true,
                    debug_name = "tower_skull_collectible",
                    data = { interaction_data = {
                        interaction_type = "tower_skull",
                        hud_description = "tower_skull_desc",
                        hud_interaction_action = "interaction_action_pick_up",
                    } },
                    interactable = true,
                },
                -- Index 12 is deliberately absent: selected by its spawned set but
                -- missing from the realized level.
            }
            local fake_mod = { info = function() end }
            function fake_mod:hook_safe(class_name, method_name, fn)
                hooks[class_name .. "." .. method_name] = fn
            end
            function fake_mod:hook(class_name, method_name, fn)
                hooks[class_name .. "." .. method_name] = fn
            end

            _G.get_mod = function() return fake_mod end
            _G.printf = function(fmt, ...)
                lines[#lines + 1] = string.format(fmt, ...)
            end
            _G.Managers = { level_transition_handler = {
                get_current_level_keys = function() return current_key end,
                get_current_level_key = function() return current_key end,
            } }
            _G.LevelSettings = {
                dlc_wizards_tower = { level_name = "tower/world" },
                inn_level = { level_name = "inn/world" },
            }
            _G.Level = { unit_by_index = function(_, index) return units[index] end }
            _G.Unit = {
                alive = function(unit) return unit.alive end,
                debug_name = function(unit) return unit.debug_name end,
                get_data = function(unit, a, b)
                    local value = unit.data and unit.data[a]
                    return b and type(value) == "table" and value[b] or value
                end,
            }
            _G.ScriptUnit = {
                has_extension = function(unit) return unit.interactable and {} or nil end,
            }
            _G.LevelResource = {
                unit_data = function(_, index) return { index = index } end,
            }
            _G.flow_callback_on_tower_skull_found = function(_, marker)
                original_flow_calls = original_flow_calls + 1
                return "original", marker
            end
            _G._ct_skull52_flow_wrapped = nil

            local chunk = assert(loadfile(root .. "_ct_diag_skull52.lua"))
            local module = chunk()
            local adventure_observed = module.observe_object_sets("tower/world", "adventure", {
                adventure = { type = "", units = { 11, 12 } },
            }, { "adventure" }, function() return nil end)
            H.truthy(adventure_observed)
            H.truthy(module.finalize_selection({ "adventure" }))

            H.truthy(hooks["StateIngame._create_level"])
            H.truthy(hooks["StateIngame._teardown_level"])
            H.truthy(hooks["GameModeManager._set_flow_object_set_enabled"])
            hooks["StateIngame._create_level"]({ level = {} })

            local deus_observed = module.observe_object_sets("tower/world", "deus", {
                adventure = { type = "", units = { 11, 12 } },
            }, {}, function() return "dlc_wizards_tower" end)
            H.truthy(deus_observed)
            H.truthy(module.finalize_selection({ "adventure" }))
            hooks["StateIngame._create_level"]({ level = {} })

            units[11] = nil
            local vanilla_teardown_called = false
            hooks["StateIngame._teardown_level"](function(_, marker)
                vanilla_teardown_called = true
                H.equal(marker, "forwarded")
            end, { level = {} }, "forwarded")
            H.truthy(vanilla_teardown_called)

            -- Teardown clears the session, so a later unrelated level cannot
            -- inherit Tower state or emit mismatch noise.
            current_key = "inn_level"
            H.equal(module.level_snapshot({ level = {} }, "after_teardown"), false)
            H.equal(module.observe_object_sets("inn/world", "adventure", {}, {}, function() return nil end), false)

            local text = table.concat(lines, "\n")
            H.truthy(text:find("mode=adventure key=dlc_wizards_tower", 1, true))
            H.truthy(text:find("mode=deus key=dlc_wizards_tower", 1, true))
            H.truthy(text:find("phase=post_create", 1, true))
            H.truthy(text:find("interaction_type=tower_skull", 1, true))
            H.truthy(text:find("expected=2 live=1 missing=1", 1, true))
            H.truthy(text:find("disappeared_since_create=1", 1, true))
            H.truthy(text:find("phase=selection_final key=dlc_wizards_tower mode=deus raw_selected=0 final_selected=1 changed=1", 1, true))
            H.truthy(text:find("adventure(raw=false,final=true", 1, true))

            -- The same entry surface rejects a Tower-time hero sublevel.
            current_key = "dlc_wizards_tower"
            H.equal(module.observe_object_sets("heroes/kruber", "deus", {}, {},
                function() return "dlc_wizards_tower" end), false)

            -- A transition mismatch clears active state immediately.
            H.truthy(module.observe_object_sets("tower/world", "deus", {
                adventure = { type = "", units = { 12 } },
            }, { "adventure" }, function() return "dlc_wizards_tower" end))
            current_key = "inn_level"
            H.equal(module.level_snapshot({ level = {} }, "transition_check"), false)
            H.equal(module.level_snapshot({ level = {} }, "transition_check_again"), false)
            text = table.concat(lines, "\n")
            H.truthy(text:find("transition_mismatch", 1, true))

            -- Force the diagnostic itself to raise at teardown. Vanilla still
            -- runs exactly once, arguments survive, and active state is cleared.
            current_key = "dlc_wizards_tower"
            H.truthy(module.observe_object_sets("tower/world", "deus", {
                adventure = { type = "", units = { 12 } },
            }, { "adventure" }, function() return "dlc_wizards_tower" end))
            _G.Managers.level_transition_handler.get_current_level_keys = function()
                error("forced diagnostic failure")
            end
            local destroy_calls = 0
            hooks["StateIngame._teardown_level"](function(_, marker)
                destroy_calls = destroy_calls + 1
                H.equal(marker, "safe")
            end, { level = {} }, "safe")
            H.equal(destroy_calls, 1)
            _G.Managers.level_transition_handler.get_current_level_keys = function() return current_key end
            H.equal(module.level_snapshot({ level = {} }, "after_failed_probe"), false)

            -- Saturate every per-session producer. Strong skull identities sort
            -- ahead of generic interactables, summaries retain budget, callback
            -- logging caps at 12, and the wrapped vanilla callback always runs.
            current_key = "dlc_wizards_tower_khorne_path1"
            _G.LevelSettings[current_key] = { level_name = "tower/world_variant" }
            local many_sets, many_spawned = {}, {}
            for i = 1, 40 do
                local set_name = "flow_set_" .. tostring(i)
                local index = 100 + i
                many_sets[set_name] = { type = "flow", units = { index } }
                many_spawned[#many_spawned + 1] = set_name
                units[index] = {
                    alive = true,
                    debug_name = "generic_interactable_" .. tostring(i),
                    data = { interaction_data = { interaction_type = "player_generic" } },
                    interactable = true,
                }
            end
            units[140].debug_name = "tower_skull_priority_candidate"
            units[140].data.interaction_data.interaction_type = "tower_skull"
            H.truthy(module.observe_object_sets("tower/world_variant", "deus", many_sets, many_spawned,
                function() return "dlc_wizards_tower" end))
            H.truthy(module.finalize_selection(many_spawned))
            for i = 1, 40 do
                local set_name = "flow_set_" .. tostring(i)
                hooks["GameModeManager._set_flow_object_set_enabled"]({},
                    { flow_set_enabled = false, units = many_sets[set_name].units }, false, set_name)
            end
            hooks["StateIngame._create_level"]({ level = {} })
            for i = 1, 14 do
                local a, b = _G.flow_callback_on_tower_skull_found({ ordinal = i }, "flow-return")
                H.equal(a, "original")
                H.equal(b, "flow-return")
            end
            units[140] = nil
            hooks["StateIngame._teardown_level"](function() end, { level = {} })
            H.equal(original_flow_calls, 14)
            text = table.concat(lines, "\n")
            H.truthy(text:find("index=140 live=true identity_source=live strong=true", 1, true))
            H.truthy(text:find("index=140 live=false identity_source=post_create strong=true", 1, true))
            H.truthy(text:find("phase=pre_teardown key=dlc_wizards_tower_khorne_path1", 1, true))
            H.truthy(text:find("ordinal=12 cap=12", 1, true))
            H.equal(text:find("ordinal=13 cap=12", 1, true), nil)
        end)

        for _, name in ipairs(global_names) do
            local value = saved[name]
            if value == nil_sentinel then
                rawset(_G, name, nil)
            else
                rawset(_G, name, value)
            end
        end
        if not ok then error(err) end
    end)

    H.test("CT #52 diagnostic is bounded, deduplicated, and log-only", function()
        H.truthy(diag:find("local CENSUS_RECORD_CAP_TOTAL = 320", 1, true))
        H.truthy(diag:find("local CENSUS_RECORD_CAP_PER_SESSION = 160", 1, true))
        H.truthy(diag:find("local LIFECYCLE_RECORD_CAP_TOTAL = 256", 1, true))
        H.truthy(diag:find("local LIFECYCLE_RECORD_CAP_PER_SESSION = 128", 1, true))
        H.truthy(diag:find("local SAMPLE_CAP_PER_SET = 4", 1, true))
        H.truthy(diag:find("local IDENTITY_CAP_PER_PHASE = 32", 1, true))
        H.truthy(diag:find("local FLOW_SET_CAP_PER_SESSION = 32", 1, true))
        H.truthy(diag:find("local FLOW_CALLBACK_CAP_PER_SESSION = 12", 1, true))
        H.truthy(diag:find("records >= CENSUS_RECORD_CAP_TOTAL", 1, true))
        H.truthy(diag:find("lifecycle_records >= LIFECYCLE_RECORD_CAP_TOTAL", 1, true))
        H.truthy(diag:find("[ct:skull52]", 1, true))
        H.equal(diag:find("mod:echo", 1, true), nil, "diagnostic must not pollute chat")
        H.equal(diag:find("mod:info", 1, true), nil, "diagnostic must use engine printf only")
        H.equal(diag:find("mod:command", 1, true), nil, "diagnostic must not require a command")
    end)

    H.test("CT #52 diagnostic is modular and the #156 behavior hook remains single-owner", function()
        H.truthy(entry:find('mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_skull52")', 1, true))
        H.truthy(entry:find("pcall(mod._ct_diag_skull52.install)", 1, true))
        H.truthy(entry:find("pcall(mod._ct_diag_skull52.observe_object_sets, level_name, game_mode_key,", 1, true))
        H.truthy(entry:find("pcall(mod._ct_diag_skull52.finalize_selection, spawned_object_sets)", 1, true))
        H.truthy(entry:find('spawned_object_sets[#spawned_object_sets + 1] = "adventure"', 1, true))
        H.equal(entry:find("collectibles are the `gargoyle_head`", 1, true), nil)
    end)

    H.test("CT #52 regression check is registered with the /ct_regression_test suite", function()
        -- The pinned live-test card says "the #52 diagnostic checks must pass";
        -- without this registration the suite passes while proving nothing about
        -- #52. Register at the wiring site, direct-reference pattern like
        -- issue533_native_tab_diagnostics_armed / issue458_start_shrine_config.
        local install_at = assert(entry:find("pcall(mod._ct_diag_skull52.install)", 1, true))
        local reg_at = assert(
            entry:find('_rt_register("issue52_skull_diag_installed", mod._ct_diag_skull52.regression)', 1, true),
            "#52 M.regression must be registered via _rt_register at the skull52 wiring site")
        H.truthy(install_at < reg_at, "registration must follow the module install at the wiring site")
        -- The registered function must exist in the module and honor the
        -- _rt_register contract (string = FAIL; falls through to nil = PASS).
        H.truthy(diag:find("function M.regression()", 1, true))
        H.truthy(diag:find('return "#52 diagnostic record caps drifted"', 1, true))
        H.truthy(diag:find('return "#52 diagnostic lifecycle missing"', 1, true))
    end)
end
