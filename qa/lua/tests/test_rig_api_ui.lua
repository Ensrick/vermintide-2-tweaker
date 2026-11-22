-- test_rig_api_ui.lua: offline tests of the rig's helper group lib/ui.lua (T.open_view, T.close_view, T.widget,
-- T.press), WP-H-06 group "UI".
--
-- Boots the real bootstrap and driver with the real group in plan.libs inside the simulated game of
-- _rig_driver_env.lua, plus a stub IngameUI: handle_transition runs a transition table like
-- ingame_ui_settings.lua's (hero_view_force, exit_menu), the hero view's overview state appears two frames after it
-- opens, applies its layout on its first update after that, and from then on every frame reads and clears its
-- exit_button's on_release and then closes the view, as HeroViewStateOverview does. This proves the helpers' control flow and evidence lines only, never that the game's
-- UI reacts the same way: that is what qa/runtime/plans/api-selftest.json is for.
return function(H, repo_root)
    local E = assert(loadfile(repo_root .. "/qa/lua/tests/_rig_driver_env.lua"))()(H, repo_root)
    local tag, first = E.tag, E.first

    local function ui_world(env, opts)
        opts = opts or {}
        local w = { transitions = {}, in_coroutine = {} }
        local exit_button = { name = "exit_button", content = { button_hotspot = {} } }
        -- Like HeroViewStateOverview: on_enter only asks for layout 1 (set_layout stores the index,
        -- hero_view_state_overview.lua:246-258, 362-364); the state's update applies it first (_update_set_layout,
        -- :609-616, :366-411), so close_on_exit() is nil until the state's first update after it appeared.
        local overview = {
            NAME = "HeroViewStateOverview",
            _widgets_by_name = { exit_button = exit_button, plain = { content = { hotspot = {} } } },
            close_on_exit = function(self) return self._close_on_exit end,
            get_selected_game_mode_index = function(self) return self._selected_game_mode_index end,
        }
        local function enter_overview()
            overview._close_on_exit, overview._selected_game_mode_index, overview._wanted_layout_index = nil, nil, 1
            w.state = overview
        end
        w.exit_button, w.overview = exit_button, overview
        local hero_view = { current_state = function() return w.state end }
        local ui = { views = { hero_view = hero_view } }
        local transitions = {
            hero_view_force = function(self) self.current_view = "hero_view" end,
            exit_menu = function(self) self.current_view = nil end,
        }
        function ui.handle_transition(self, name, params)
            if coroutine.running() then
                w.in_coroutine[#w.in_coroutine + 1] = name
            end
            assert(transitions[name], "Missing transition to " .. tostring(name))
            w.transitions[#w.transitions + 1] = name .. (params and params.menu_state_name and (":" .. params.menu_state_name) or "")
            if opts.refuse then
                return
            end
            transitions[name](self, params)
            w.state = nil
            if name == "hero_view_force" then
                w.state_in = 2
            end
        end
        w.ui = ui
        env.Managers.ui = { ingame_ui = function(self) return ui end }
        env.Managers.backend = { get_backend_mirror = function() return { _career_data = {}, _career_data_mirror = {} } end }
        -- one frame of the hero view's update: the overview's own update (layout first, then the exit press, read only
        -- when the layout closes on exit, :783-786), then a state due this frame appears (its update comes next frame)
        w.frame = function()
            if w.state == overview then
                if overview._wanted_layout_index then
                    overview._close_on_exit, overview._selected_game_mode_index = true, overview._wanted_layout_index
                    overview._wanted_layout_index = nil
                end
                if overview._close_on_exit and not opts.ignore_press and exit_button.content.button_hotspot.on_release then
                    exit_button.content.button_hotspot.on_release = false
                    ui:handle_transition("exit_menu")
                end
            end
            if w.state_in then
                w.state_in = w.state_in - 1
                if w.state_in <= 0 then
                    w.state_in = nil
                    enter_overview()
                end
            end
        end
        return w
    end

    local function run(cases, opts)
        local plan = E.make_plan(cases, { libs = { E.lib_entry("ui") } })
        local object, env, lines = E.boot(plan)
        local w = ui_world(env, opts)
        H.truthy(E.run_to_end(object, env, nil, w.frame), "run completed")
        return lines, w
    end

    H.test("rig api-selftest case api_ui: open, press exit_button, reopen, T.close_view in the simulated UI", function()
        local lines, w = run({ { id = "api-ui", src = E.read(repo_root .. "/qa/runtime/_rig/api_ui.lua") } })
        H.truthy(first(lines, tag .. "CASE END id=api%-ui verdict=PASS"), "api-ui passes: " .. tostring(first(lines, tag .. "CASE END id=api%-ui")))
        H.equal(table.concat(w.transitions, ","), "hero_view_force:overview,exit_menu,hero_view_force:overview,exit_menu",
            "open, closed by the press, open, closed by T.close_view")
        H.truthy(first(lines, tag .. "VIEW OPEN id=api%-ui view=hero_view transition=hero_view_force"), "VIEW OPEN line")
        H.truthy(first(lines, tag .. "PRESS id=api%-ui widget=exit_button hotspot=button_hotspot field=on_release cleared=true"), "PRESS line")
        H.truthy(first(lines, tag .. "VIEW CLOSE id=api%-ui view=hero_view by=T.close_view"), "VIEW CLOSE line")
        H.equal(table.concat(w.in_coroutine, ","), "", "every transition ran in the main update")
    end)

    -- The rig's INCONCLUSIVE (lead run 20261122-024431-api-selftest-09002eef) came from reading close_on_exit in the
    -- frame the state appeared; the stub must reproduce that, or the PASS above proves nothing about the wait.
    H.test("rig api_ui precondition: close_on_exit read before the overview's first update is nil (the rig's INCONCLUSIVE)", function()
        local lines = run({ { id = "early", src = [[
return { run = function(T)
    local view = T.open_view("hero_view", { menu_state_name = "overview" })
    local state = T.wait_until(function()
        local current = view:current_state()
        return current and current._widgets_by_name and current
    end, 5, "state")
    T.require(state:close_on_exit(), "this overview layout closes the view on exit")
end }
]] } }, { ignore_press = true })
        H.truthy(first(lines, tag .. "CASE END id=early verdict=INCONCLUSIVE .*this overview layout closes the view on exit"),
            "early read: " .. tostring(first(lines, tag .. "CASE END id=early")))
    end)

    H.test("rig T.open_view: a view the case left open is closed at cleanup, also after an ERROR", function()
        local lines, w = run({
            { id = "left-open", src = "return { run = function(T) T.open_view('hero_view') end }" },
            { id = "boom", src = "return { run = function(T) T.open_view('hero_view') error('planted error with the view open') end }" },
        }, { ignore_press = true })
        H.truthy(first(lines, tag .. "CASE END id=left%-open verdict=PASS"), "left-open passes")
        H.truthy(first(lines, tag .. "VIEW CLOSE id=left%-open view=hero_view by=cleanup"), "closed at cleanup")
        H.truthy(first(lines, tag .. "CASE END id=boom verdict=ERROR .*planted error with the view open"), "ERROR reported")
        H.truthy(first(lines, tag .. "VIEW CLOSE id=boom view=hero_view by=cleanup"), "closed at cleanup after the ERROR")
        H.equal(w.ui.current_view, nil, "no view open at the end")
    end)

    H.test("rig T.open_view: missing view, missing transition or a refused transition is INCONCLUSIVE", function()
        local lines = run({
            { id = "no-view", src = "return { run = function(T) T.open_view('nope_view') end }" },
            { id = "no-transition", src = "return { run = function(T) T.open_view('hero_view', nil, 'nope') end }" },
        })
        H.truthy(first(lines, tag .. "CASE END id=no%-view verdict=INCONCLUSIVE .*view nope_view exists"), "unknown view")
        H.truthy(first(lines, tag .. "CASE END id=no%-transition verdict=INCONCLUSIVE .*transition nope accepted %(.*Missing transition to nope"), "unknown transition")
        local refused = run({ { id = "refused", src = "return { run = function(T) T.open_view('hero_view', nil, nil, 1) end }" } }, { refuse = true })
        H.truthy(first(refused, tag .. "CASE END id=refused verdict=INCONCLUSIVE .*view hero_view opened through hero_view_force"), "refused transition")
    end)

    H.test("rig T.widget / T.press: lookups, a press nobody reads, and the widget-first form", function()
        local lines, w = run({
            { id = "press", src = [[
return { run = function(T)
    T.open_view("hero_view")
    local state = T.wait_until(function() return Managers.ui:ingame_ui().views.hero_view:current_state() end, 5, "state")
    T.expect(T.widget(state, "plain") ~= nil, "T.widget on a state")
    local cleared = T.press(state, "plain", nil, nil, 3)
    T.expect_eq(cleared, false, "nobody reads the plain widget's hotspot")
    T.expect_eq(T.widget(state, "plain").content.hotspot.on_release, false, "an unread press is reset")
    T.expect_eq(T.press(T.widget(state, "exit_button"), "button_hotspot", "on_right_click", 2), false, "widget-first form with a field")
end }
]] },
            { id = "no-widget", src = "return { run = function(T) T.widget({ _widgets_by_name = {} }, 'nope') end }" },
            { id = "no-hotspot", src = "return { run = function(T) T.press({ content = {} }, 'nope') end }" },
        }, { ignore_press = true })
        H.truthy(first(lines, tag .. "CASE END id=press verdict=PASS asserts=4 failed=0"), "press passes: " .. tostring(first(lines, tag .. "CASE END id=press")))
        H.truthy(first(lines, tag .. "PRESS id=press widget=plain hotspot=hotspot field=on_release cleared=false"), "PRESS line of the unread press")
        H.truthy(first(lines, tag .. "PRESS id=press widget=exit_button hotspot=button_hotspot field=on_right_click cleared=false"), "PRESS line of the widget-first form")
        H.equal(w.exit_button.content.button_hotspot.on_right_click, false, "the right-click field was reset too")
        H.truthy(first(lines, tag .. "CASE END id=no%-widget verdict=INCONCLUSIVE .*widget nope exists"), "missing widget")
        H.truthy(first(lines, tag .. "CASE END id=no%-hotspot verdict=INCONCLUSIVE .*hotspot nope of widget"), "missing hotspot")
    end)
end
