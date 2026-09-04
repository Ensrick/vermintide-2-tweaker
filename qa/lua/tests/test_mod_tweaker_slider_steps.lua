return function(Harness, repo_root)
    local function read(path)
        local f = assert(io.open(repo_root .. "/" .. path, "rb"))
        local s = f:read("*a")
        f:close()
        return s
    end

    local stable_files = {
        "gui_tweaker/scripts/mods/gui_tweaker/_mod_tweaker_view.lua",
        "gui_tweaker/scripts/mods/gui_tweaker/_mod_tweaker_state.lua",
    }

    local dev_files = {
        "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_view.lua",
        "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_state.lua",
    }

    local function with_state_interaction(body)
        local names = { "get_mod", "Keyboard", "Mouse", "Managers" }
        local saved = {}
        for i = 1, #names do saved[names[i]] = rawget(_G, names[i]) end
        local saved_clamp = math.clamp
        local fake_mod = {}
        function fake_mod:debug() end
        _G.get_mod = function() return fake_mod end
        _G.Keyboard = {
            LEFT = "left", RIGHT = "right", HOME = "home", END = "end",
            BACKSPACE = "backspace", DELETE = "delete",
            keystrokes = function() return {} end,
            released = function() return false end,
        }
        _G.Mouse = { released = function() return false end }
        _G.Managers = {}
        math.clamp = function(value, min, max)
            if value < min then return min end
            if value > max then return max end
            return value
        end

        local ok, err = pcall(function()
            local module_path = repo_root
                .. "/gui_tweaker/scripts/mods/gui_tweaker/_mod_tweaker_state_interaction.lua"
            local Interaction = assert(loadfile(module_path))()
            local State = {}
            Interaction.install(State, {
                defs = { list_sg = "list" },
                UIRenderer = {},
                UISceneGraph = { get_world_position = function() return { 0, 0, 0 } end },
                UIInverseScaleVectorToResolution = function(cursor) return cursor end,
                math = math,
                cat_set = function() end,
                play_click = function() end,
                play_hover = function() end,
            })
            body(State)
        end)

        for i = 1, #names do _G[names[i]] = saved[names[i]] end
        math.clamp = saved_clamp
        if not ok then error(err, 0) end
    end

    Harness.test("Mod Tweaker dev resolves foreign slider steps through the setting owner", function()
        for i = 1, #dev_files do
            local s = read(dev_files[i])
            Harness.truthy(s:match("base_power_level%s*=%s*25"), dev_files[i])
            Harness.truthy(s:match("starting_coins%s*=%s*25"), dev_files[i])
            Harness.truthy(s:match("cot_cost_amount%s*=%s*25"), dev_files[i])
            Harness.truthy(s:find("local _, owner_mod_id = _owner(category, setting_id)", 1, true), dev_files[i])
            Harness.truthy(s:find("_resolve_step(w, owner_mod_id", 1, true), dev_files[i])
            Harness.equal(s:find("_resolve_step(w, category and category.mod_id", 1, true), nil, dev_files[i])
        end
    end)

    Harness.test("stable resolves registered slider steps through each setting owner", function()
        for i = 1, #stable_files do
            local s = read(stable_files[i])
            Harness.truthy(s:match("base_power_level%s*=%s*25"), stable_files[i])
            Harness.truthy(s:match("starting_coins%s*=%s*25"), stable_files[i])
            Harness.truthy(s:match("cot_cost_amount%s*=%s*25"), stable_files[i])
            Harness.truthy(s:find("local function _resolve_owner_step", 1, true), stable_files[i])
            Harness.truthy(s:find("local _, owner_mod_id = _owner(category, effective_setting_id)", 1, true), stable_files[i])
            Harness.truthy(s:find("local step = _resolve_owner_step(w, category, setting_id, dec)", 1, true), stable_files[i])
            Harness.truthy(s:find("_issue389_step_receipt(category, setting_id, step)", 1, true), stable_files[i])
            Harness.truthy(s:find("[gut:issue389] route=", 1, true), stable_files[i])
            Harness.truthy(s:find('_printf("[gut:issue389] route=', 1, true), stable_files[i])
            Harness.truthy(s:find('rawget(mod, "_issue389_step_receipts")', 1, true), stable_files[i])
            Harness.truthy(s:find('rawset(mod, "_issue389_step_receipts", receipts)', 1, true), stable_files[i])
            Harness.equal(s:find('mod:info("[gut:issue389] route=', 1, true), nil, stable_files[i])
            Harness.equal(s:find("local _issue389_step_receipt_emitted", 1, true), nil, stable_files[i])
            Harness.equal(s:find("_resolve_step(w, category and category.mod_id", 1, true), nil, stable_files[i])
        end
    end)

    Harness.test("issue 389 runtime check drives both integrated presentation seams", function()
        local contracts = read("gui_tweaker/scripts/mods/gui_tweaker/_gut_mod_tweaker_contracts.lua")
        Harness.truthy(contracts:find('issue389_mod_tweaker_owner_aware_step', 1, true))
        Harness.truthy(contracts:find('mod_id = "gut_equipment"', 1, true))
        Harness.truthy(contracts:find('base_power_level = { mod_id = "cim" }', 1, true))
        Harness.truthy(contracts:find('View._resolve_owner_step', 1, true))
        Harness.truthy(contracts:find('View._synthesize_equipment', 1, true))
        Harness.truthy(contracts:find('View._build_node_row', 1, true))
        Harness.truthy(contracts:find('View._commit_edit', 1, true))
        Harness.truthy(contracts:find('View._handle_input', 1, true))
        Harness.truthy(contracts:find('installed typed-edit callback did not snap and stage Base Power 324 to 325', 1, true))
        Harness.truthy(contracts:find('installed increment callback did not snap and stage Base Power 324 to 350', 1, true))
        Harness.truthy(contracts:find('fake_view._pending.gut_equipment ~= nil', 1, true))
        Harness.truthy(contracts:find('State._resolve_owner_step', 1, true))
        Harness.truthy(contracts:find('State._build_node_row', 1, true))
        Harness.truthy(contracts:find('State._handle_input', 1, true))
        Harness.truthy(contracts:find('keep-state increment did not snap and stage Base Power 324 to 350', 1, true))
        Harness.truthy(contracts:find('keep-state decrement did not snap and stage Base Power 324 to 300', 1, true))
        Harness.truthy(contracts:find('regressed Trial Chest Cost step resolution', 1, true))
        Harness.truthy(contracts:find('keep transition did not use the standalone Mod Tweaker view', 1, true))
        Harness.equal(contracts:find('keep branch did not call transition_with_fade', 1, true), nil)
        Harness.truthy(contracts:find('without a source-qualified setting owner', 1, true))
        Harness.truthy(contracts:find('Base Power 324 did not snap to 325', 1, true))
        Harness.truthy(contracts:find('Base Power decrement from off-grid 324 did not land on 300', 1, true))
        Harness.truthy(contracts:find('Base Power increment from off-grid 324 did not land on 350', 1, true))
        Harness.truthy(contracts:find('Base Power did not clamp to authored max 950', 1, true))

        local entry = read("gui_tweaker/scripts/mods/gui_tweaker/gui_tweaker.lua")
        local verifier = read("gui_tweaker/scripts/mods/gui_tweaker/_gut_issue389_verifier.lua")
        Harness.truthy(entry:find('mod:dofile("scripts/mods/gui_tweaker/_gut_issue389_verifier").install(_RT_CHECKS)', 1, true))
        Harness.truthy(verifier:find('mod:command("verify_gut_slider_step"', 1, true))
        Harness.truthy(verifier:find('local wanted = "issue389_mod_tweaker_owner_aware_step"', 1, true))
        Harness.truthy(verifier:find('pcall(printf, "[gut:issue389] verify=PASS")', 1, true))
        Harness.truthy(verifier:find('[gut:issue389] verify=PASS', 1, true))
        Harness.equal(verifier:find('mod:info("[gut:issue389]', 1, true), nil)
        Harness.equal(verifier:find('mod:warning("[gut:issue389]', 1, true), nil)

        local inject = read("gui_tweaker/scripts/mods/gui_tweaker/_ba_heroview_inject.lua")
        Harness.truthy(entry:find('mod:command("mod_tweaker"', 1, true))
        Harness.equal(inject:find('mod:command("mod_tweaker"', 1, true), nil)
    end)

    Harness.test("dormant Hero-state installed input uses the min-anchored step grid", function()
        with_state_interaction(function(State)
            local function state_for(row)
                local state = {
                    _categories = { row._category },
                    _selected = 1,
                    _profile_buttons = {},
                    _tabs = {},
                    _rows = { row },
                    _max_scroll = 0,
                    stage_count = 0,
                }
                function state:stage_set(_, _, value)
                    self.stage_count = self.stage_count + 1
                    self.staged = value
                end
                return setmetatable(state, { __index = State })
            end

            local category = { mod_id = "gut_equipment" }
            local inc_row = {
                _wtype = "numeric", _setting_id = "base_power_level", _category = category,
                content = {
                    value = 324, min = 0, max = 950, num_decimals = 0, step = 25,
                    dec = {}, inc = { on_release = true },
                },
            }
            local inc_state = state_for(inc_row)
            inc_state:_handle_input(nil)
            Harness.equal(inc_row.content.value, 350)
            Harness.equal(inc_state.staged, 350)

            local dec_row = {
                _wtype = "numeric", _setting_id = "base_power_level", _category = category,
                content = {
                    value = 324, min = 0, max = 950, num_decimals = 0, step = 25,
                    dec = { on_release = true }, inc = {},
                },
            }
            local dec_state = state_for(dec_row)
            dec_state:_handle_input(nil)
            Harness.equal(dec_row.content.value, 300)
            Harness.equal(dec_state.staged, 300)

            -- Raw track position 57% maps to 67 in range 10..110. A decimal-only
            -- round would retain 67; the shared min-anchored 25 grid must select 60.
            local drag_row = {
                _wtype = "numeric", _setting_id = "offset_grid", _category = category,
                content = {
                    value = 10, min = 10, max = 110, num_decimals = 0, step = 25,
                    track_x = 0, track_w = 100, track_hs = { is_held = true },
                },
            }
            local drag_state = state_for(drag_row)
            drag_state.ui_scenegraph = {}
            local input = {
                get = function(_, key)
                    if key == "cursor" then return { 57, 0, 0 } end
                end,
            }
            drag_state:_handle_input(input)
            Harness.equal(drag_row.content.value, 60)
            Harness.equal(drag_state.stage_count, 0)
            drag_row.content.track_hs.is_held = false
            drag_row.content.track_hs.on_left_release = true
            drag_state:_handle_input(input)
            Harness.equal(drag_row.content.value, 60)
            Harness.equal(drag_state.staged, 60)
            Harness.equal(drag_state.stage_count, 1)
        end)
    end)

    Harness.test("stable no longer accepts VMF-invalid range third elements", function()
        for i = 1, 2 do
            local s = read(stable_files[i])
            Harness.equal(s:find("range and range[3]", 1, true), nil, stable_files[i])
        end
    end)
end
