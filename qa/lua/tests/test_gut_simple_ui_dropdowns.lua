return function(H, repo_root)
    -- #314 phase 2: fitted Simple UI dropdown lists. The pure layout policy is
    -- covered directly; the runtime owner is driven through a minimal object
    -- model that keeps Simple UI 2.1.2's instance-field call order (parent
    -- update_base hover test, downward option placement, then each option's
    -- before_update -> disabled gate -> hover test; release iterates options
    -- by their extended_bounds).
    local mod_root = repo_root .. "/gui_tweaker_dev/"
    local scripts = mod_root .. "scripts/mods/gui_tweaker_dev/"
    local Policy = assert(loadfile(scripts .. "_gut_simple_ui_bounds_policy.lua"))()

    local function rows_union(layout, x1, x2)
        local union
        for index = layout.first, layout.last do
            local bottom = Policy.row_bottom(layout, index)
            union = union or { x1, x2, bottom, bottom + layout.row }
            union[3] = math.min(union[3], bottom)
            union[4] = math.max(union[4], bottom + layout.row)
        end
        return union
    end

    H.test("GUT #314 dropdown layout opens downward, upward, or scrolls to the selection", function()
        local down = Policy.dropdown_layout(900, 30, 1080, 5, 2, 3, nil)
        H.equal(down.direction, "down")
        H.equal(down.visible, 5)
        H.equal(Policy.row_bottom(down, 1), 868, "matches the upstream first-row placement")
        H.equal(Policy.row_bottom(down, 5), 748)
        H.deep_equal(Policy.dropdown_bounds(down, 10, 110, true), { 10, 110, 748, 930 })
        H.deep_equal(Policy.dropdown_bounds(down, 10, 110, false), { 10, 110, 900, 930 })

        local up = Policy.dropdown_layout(60, 30, 1080, 8, 2, 1, nil)
        H.equal(up.direction, "up")
        H.equal(up.visible, 8)
        H.equal(Policy.row_bottom(up, 8), 92, "the last row sits on the control's top edge")
        H.equal(Policy.row_bottom(up, 1), 302, "rows keep top-to-bottom reading order")
        H.deep_equal(Policy.dropdown_bounds(up, 0, 50, true), { 0, 50, 60, 332 })

        local long = Policy.dropdown_layout(300, 30, 400, 20, 2, 18, nil)
        H.equal(long.direction, "down", "the roomier side wins when neither fits")
        H.equal(long.visible, 9)
        H.equal(long.first, 10)
        H.equal(long.last, 18, "opening reveals the selected option")
        H.equal(Policy.row_bottom(long, 9), nil, "a scrolled-out row has no placement")
        H.equal(Policy.row_bottom(long, 10), 268)
        local scrolled = Policy.dropdown_layout(300, 30, 400, 20, 2, 18,
            Policy.scroll_step(long.scroll, 99, long.max_scroll))
        H.equal(scrolled.last, 20, "scrolling clamps at the end of the list")
        H.equal(Policy.dropdown_layout(300, 30, 400, 20, 2, 18, -4).first, 1)
        H.equal(Policy.dropdown_layout(300, 30, 400, 20, 2, 2, nil).first, 1,
            "a selection inside the first page does not scroll")

        local cramped = Policy.dropdown_layout(10, 30, 45, 4, 2, 1, nil)
        H.equal(cramped.visible, 1, "a dropdown with no room still shows one row")
        local low = Policy.dropdown_layout(-20, 30, 1080, 6, 2, 1, nil)
        H.equal(low.direction, "up", "a control below the screen recovers upward")
        H.equal(low.visible, 6)
    end)

    H.test("GUT #314 dropdown hit box equals exactly the rendered rows plus the control", function()
        local cases = {
            Policy.dropdown_layout(900, 30, 1080, 5, 2, 3, nil),
            Policy.dropdown_layout(60, 30, 1080, 8, 2, 1, nil),
            Policy.dropdown_layout(300, 30, 400, 20, 2, 18, nil),
            Policy.dropdown_layout(300, 24, 400, 20, 4, 1, 7),
        }
        for _, layout in ipairs(cases) do
            local box = Policy.dropdown_bounds(layout, 5, 95, true)
            local rows = rows_union(layout, 5, 95)
            if layout.direction == "down" then
                H.equal(box[3], rows[3], "down: the hit box ends at the lowest rendered row")
                H.equal(box[4], layout.top, "down: the hit box starts at the control's top")
                H.equal(rows[4], layout.bottom - layout.border, "down: the first row hangs below the gap")
            else
                H.equal(box[4], rows[4], "up: the hit box ends at the highest rendered row")
                H.equal(box[3], layout.bottom, "up: the hit box starts at the control's bottom")
                H.equal(rows[3], layout.top + layout.border, "up: the last row rests above the gap")
            end
            H.equal(layout.last - layout.first + 1, layout.visible)
        end
    end)

    H.test("GUT #314 dropdown policy fails closed and maps the wheel", function()
        H.equal(Policy.dropdown_layout(10, 0, 100, 4, 2, 1, nil), nil)
        H.equal(Policy.dropdown_layout(10, 30, 0, 4, 2, 1, nil), nil)
        H.equal(Policy.dropdown_layout(10, 30, 100, 2.5, 2, 1, nil), nil)
        H.equal(Policy.dropdown_layout(nil, 30, 100, 4, 2, 1, nil), nil)
        H.equal(Policy.row_bottom(nil, 1), nil)
        H.equal(Policy.dropdown_bounds(nil, 0, 1, true), nil)
        H.equal(Policy.scroll_step(nil, 1, 3), 0)
        H.equal(Policy.wheel_step(1), -1, "wheel up reveals earlier rows")
        H.equal(Policy.wheel_step(-1), 1, "wheel down reveals later rows")
        H.equal(Policy.wheel_step(0), 0)
        H.equal(Policy.wheel_step("x"), 0)
    end)

    -- Minimal Simple UI object model -------------------------------------
    local function in_bounds(p, b)
        return b[1] <= p[1] and p[1] <= b[2] and b[3] <= p[2] and p[2] <= b[4]
    end

    local function new_option(index, parent, cursor)
        local option = { _type = "dropdown_item", index = index, parent = parent,
            position = { 0, 0 }, size = { 0, 0 }, visible = true, hovered = false }
        function option.bounds(self)
            return { self.position[1], self.position[1] + self.size[1],
                self.position[2], self.position[2] + self.size[2] }
        end
        function option.extended_bounds(self) return self.bounds(self) end
        function option.before_update() end
        function option.update(self)
            self.before_update(self)
            if self.disabled then return end
            self.hovered = in_bounds(cursor(), self.extended_bounds(self))
        end
        function option.release(self)
            if self.disabled then return end
            if self.parent and self.index then self.parent:select_index(self.index) end
        end
        return option
    end

    local function new_dropdown(position, indices, selected, cursor)
        local dropdown = { _type = "dropdown", position = position, size = { 100, 30 },
            visible = true, z_order = 1, index = selected, options = {}, dropped = false,
            clicked = false, hovered = false, rendered = 0, selections = {} }
        for _, index in ipairs(indices) do
            dropdown.options[#dropdown.options + 1] = new_option(index, dropdown, cursor)
        end
        function dropdown.bounds(self)
            return { self.position[1], self.position[1] + self.size[1],
                self.position[2], self.position[2] + self.size[2] }
        end
        function dropdown.update_base(self)
            self.hovered = in_bounds(cursor(), self.extended_bounds(self))
        end
        -- Upstream order (simple_ui.lua:2128-2154): base update, place every
        -- option downward, then run each option's update.
        function dropdown.update(self)
            self.update_base(self)
            if self.dropped then
                local border = 2 * UIResolutionScale()
                for _, option in pairs(self.options) do
                    option.position = { self.position[1], self.position[2] - border - self.size[2] * option.index }
                    option.size = self.size
                    option.visible = true
                    option.update(option)
                end
            end
            return self.clicked or self.dropped
        end
        function dropdown.extended_bounds(self)
            local bounds = self.bounds(self)
            if self.dropped then bounds[3] = bounds[3] - self.size[2] * #self.options end
            return bounds
        end
        function dropdown.render(self)
            self.rendered = 0
            if not self.dropped then return end
            for _, option in pairs(self.options) do
                if option.visible then self.rendered = self.rendered + 1 end
            end
        end
        function dropdown.release(self, point)
            if self.clicked then self.dropped = not self.dropped end
            for _, option in pairs(self.options) do
                if in_bounds(point, option.extended_bounds(option)) then option.release(option) end
            end
        end
        function dropdown.select_index(self, index)
            self.index = index
            self.selections[#self.selections + 1] = index
        end
        return dropdown
    end

    local function new_window(name, position, size)
        return { name = name, position = position, size = size, visible = true, z_order = 1, widgets = {} }
    end

    local GLOBAL_NAMES = { "get_mod", "UIResolution", "UIResolutionScale", "Mouse", "printf", "Vector3" }

    local function with_simple_ui(opts, body)
        opts = opts or {}
        local state = { logs = {}, wheel = 0, cursor = { 0, 0 }, scale = opts.scale or 1 }
        local fake_mod = { settings = { gut_simple_ui_fit_dropdowns = opts.fit } }
        function fake_mod:dofile(path) return assert(loadfile(mod_root .. path .. ".lua"))() end
        function fake_mod:get(id) return self.settings[id] end
        fake_mod.registered = {}
        fake_mod._gut_rt_register = function(name) fake_mod.registered[#fake_mod.registered + 1] = name end
        local simple_ui = { windows = { list = {} }, is_enabled = function() return true end }
        local values = {
            get_mod = function(name)
                if name == "gut_dev" then return fake_mod end
                if name == "SimpleUI" then return simple_ui end
            end,
            UIResolution = function() return 1920, 1080 end,
            UIResolutionScale = function() return state.scale end,
            Mouse = {
                axis_index = function(name) return "index:" .. name end,
                axis_id = function(name) return "id:" .. name end,
                axis = function(id)
                    if id == "index:wheel" then return { 0, state.wheel, 0 } end
                    if id == "id:cursor" then return { state.cursor[1], state.cursor[2], 0 } end
                    error("unexpected axis " .. tostring(id))
                end,
            },
            printf = function(fmt, ...) state.logs[#state.logs + 1] = string.format(fmt, ...) end,
            Vector3 = opts.vector3,
        }
        if opts.opaque_axes then
            values.Mouse.axis = function(id)
                if id == "index:wheel" then return { px = 0, py = state.wheel } end
                return { px = state.cursor[1], py = state.cursor[2] }
            end
        end
        local previous = {}
        for _, name in ipairs(GLOBAL_NAMES) do
            previous[name] = rawget(_G, name)
            rawset(_G, name, values[name])
        end
        local ok, err = pcall(function()
            local compat = assert(loadfile(scripts .. "_gut_simple_ui_compat.lua"))()
            local cursor = function() return state.cursor end
            body({ compat = compat, mod = fake_mod, state = state, simple_ui = simple_ui, cursor = cursor })
        end)
        for _, name in ipairs(GLOBAL_NAMES) do rawset(_G, name, previous[name]) end
        if not ok then error(err, 0) end
    end

    local function indices(n)
        local list = {}
        for i = 1, n do list[i] = i end
        return list
    end

    local function visible_union(dropdown)
        local union
        for _, option in pairs(dropdown.options) do
            if option.visible then
                local b = option.bounds(option)
                union = union or { b[1], b[2], b[3], b[4] }
                union[1], union[2] = math.min(union[1], b[1]), math.max(union[2], b[2])
                union[3], union[4] = math.min(union[3], b[3]), math.max(union[4], b[4])
            end
        end
        return union
    end

    H.test("GUT #314 a low dropdown opens upward with a hit box equal to its rendered rows", function()
        with_simple_ui({}, function(env)
            local window = new_window("list", { 0, 0 }, { 400, 400 })
            local dropdown = new_dropdown({ 20, 60 }, indices(40), 35, env.cursor)
            window.widgets[1] = dropdown
            env.simple_ui.windows.list[1] = window
            env.mod.update(0.016)
            H.equal(env.compat.phase, 2)
            H.truthy(env.compat.dropdowns, "the child owner is wired")
            H.truthy(env.compat.dropdowns.state_of(dropdown), "the live dropdown is installed")

            dropdown.dropped = true
            dropdown.update(dropdown)
            dropdown.render(dropdown)
            local layout = env.compat.dropdowns.state_of(dropdown).layout
            H.equal(layout.direction, "up")
            H.equal(layout.last, 35, "opening reveals the selected option")
            H.equal(dropdown.rendered, layout.visible, "only the fitted rows render")
            H.equal(dropdown.options[35].visible, true)
            H.equal(dropdown.options[35].position[2], Policy.row_bottom(layout, 35))
            H.equal(dropdown.options[1].visible, false, "scrolled-out rows are hidden")
            H.equal(dropdown.options[1].disabled, true, "and cannot be clicked")
            H.truthy(dropdown.options[1].position[2] < -1000, "and are parked off-screen")
            local box = dropdown.extended_bounds(dropdown)
            H.deep_equal(box, Policy.dropdown_bounds(layout, 20, 120, true))
            local rows = visible_union(dropdown)
            H.equal(box[4], rows[4], "the hit box ends exactly at the highest rendered row")
            H.equal(box[1], rows[1])
            H.equal(box[2], rows[2])
            H.truthy(box[4] <= 1080, "the open list stays on screen")

            -- Click resolution goes through the same option bounds upstream uses.
            local row20 = Policy.row_bottom(layout, 20)
            dropdown.release(dropdown, { 70, row20 + 15 })
            H.equal(dropdown.index, 20, "a visible row is selected at its rendered position")
            dropdown.release(dropdown, { 70, 60 - 2 - 15 })
            H.equal(dropdown.index, 20, "the upstream (off-list) position of a hidden row selects nothing")
            H.deep_equal(dropdown.selections, { 20 })
        end)
    end)

    H.test("GUT #314 the wheel scrolls only over the open list and reopening resets", function()
        with_simple_ui({}, function(env)
            local window = new_window("list", { 0, 0 }, { 400, 400 })
            local dropdown = new_dropdown({ 20, 60 }, indices(40), 35, env.cursor)
            window.widgets[1] = dropdown
            env.simple_ui.windows.list[1] = window
            env.mod.update(0.016)
            dropdown.dropped = true
            dropdown.update(dropdown)
            local dropdowns = env.compat.dropdowns
            local first = dropdowns.state_of(dropdown).layout.first
            H.truthy(first > 1)

            env.state.cursor = { 50, 500 }
            env.state.wheel = 1
            dropdown.update(dropdown)
            H.equal(dropdowns.state_of(dropdown).layout.first, first - 1, "wheel up reveals the previous option")
            H.equal(dropdown.options[first - 1].visible, true)
            env.state.wheel = -1
            dropdown.update(dropdown)
            H.equal(dropdowns.state_of(dropdown).layout.first, first, "wheel down reveals the next option")

            env.state.cursor = { 900, 900 }
            env.state.wheel = 1
            dropdown.update(dropdown)
            H.equal(dropdowns.state_of(dropdown).layout.first, first, "the wheel is ignored away from the list")

            env.state.cursor = { 50, 500 }
            env.state.wheel = -1
            for _ = 1, 99 do dropdown.update(dropdown) end
            H.equal(dropdowns.state_of(dropdown).layout.last, 40, "scrolling clamps at the end")
            env.state.wheel = 0

            dropdown.dropped = false
            dropdown.update(dropdown)
            H.deep_equal(dropdown.extended_bounds(dropdown), { 20, 120, 60, 90 }, "closed: plain control bounds")
            H.equal(dropdown.options[1].disabled, nil, "closing restores every parked row")
            dropdown.dropped = true
            dropdown.update(dropdown)
            H.equal(dropdowns.state_of(dropdown).layout.last, 35, "reopening reveals the selection again")
        end)
    end)

    H.test("GUT #314 consumer flags and callbacks survive hiding and re-chaining", function()
        with_simple_ui({}, function(env)
            local window = new_window("list", { 0, 0 }, { 400, 400 })
            local dropdown = new_dropdown({ 20, 60 }, indices(40), 35, env.cursor)
            window.widgets[1] = dropdown
            env.simple_ui.windows.list[1] = window
            local consumer_calls = 0
            dropdown.options[2].disabled = true
            dropdown.options[2].before_update = function() consumer_calls = consumer_calls + 1 end
            env.mod.update(0.016)
            dropdown.dropped = true
            dropdown.update(dropdown)
            H.equal(dropdown.options[2].visible, false)
            H.equal(consumer_calls, 1, "the consumer's before_update still runs on a hidden row")

            env.state.cursor = { 50, 500 }
            env.state.wheel = 1
            for _ = 1, 40 do dropdown.update(dropdown) end
            env.state.wheel = 0
            H.equal(dropdown.options[2].visible, true, "scrolling to the top reveals row 2")
            H.equal(dropdown.options[2].disabled, true, "a consumer-disabled option stays disabled")
            H.equal(dropdown.options[3].disabled, nil, "a plain option is re-enabled")

            dropdown.options[3].before_update = function() consumer_calls = consumer_calls + 10 end
            env.mod.update(0.016)
            dropdown.update(dropdown)
            H.truthy(consumer_calls >= 52, "a reassigned before_update is re-chained and still runs")
            H.equal(dropdown.options[3].position[2],
                Policy.row_bottom(env.compat.dropdowns.state_of(dropdown).layout, 3))
        end)
    end)

    H.test("GUT #314 turning the option off leaves Simple UI dropdowns upstream", function()
        with_simple_ui({ fit = false }, function(env)
            local window = new_window("list", { 0, 0 }, { 400, 400 })
            local dropdown = new_dropdown({ 20, 60 }, indices(40), 35, env.cursor)
            window.widgets[1] = dropdown
            env.simple_ui.windows.list[1] = window
            env.mod.update(0.016)
            H.equal(env.compat.dropdowns.state_of(dropdown), nil, "nothing is installed while off")
            dropdown.dropped = true
            dropdown.update(dropdown)
            H.equal(dropdown.options[40].position[2], 60 - 2 - 30 * 40, "upstream placement stands")
            H.deep_equal(dropdown.extended_bounds(dropdown), { 20, 120, 60 - 1200, 90 })
        end)
        with_simple_ui({}, function(env)
            local window = new_window("list", { 0, 0 }, { 400, 400 })
            local dropdown = new_dropdown({ 20, 60 }, indices(40), 35, env.cursor)
            window.widgets[1] = dropdown
            env.simple_ui.windows.list[1] = window
            env.mod.update(0.016)
            dropdown.dropped = true
            dropdown.update(dropdown)
            H.equal(dropdown.options[1].disabled, true)
            env.mod.settings.gut_simple_ui_fit_dropdowns = false
            env.mod.update(0.016)
            dropdown.update(dropdown)
            H.equal(dropdown.options[1].disabled, nil, "switching off mid-session re-enables parked rows")
            H.equal(dropdown.options[1].visible, true)
            H.equal(dropdown.options[1].position[2], 60 - 2 - 30, "and upstream placement returns")
            H.deep_equal(dropdown.extended_bounds(dropdown), { 20, 120, 60 - 1200, 90 })
            env.mod.settings.gut_simple_ui_fit_dropdowns = true
            env.mod.update(0.016)
            dropdown.update(dropdown)
            H.equal(dropdown.options[1].disabled, true, "switching back on fits again")
        end)
    end)

    H.test("GUT #314 UI scale, sparse indices and engine vector accessors are honored", function()
        with_simple_ui({ scale = 2 }, function(env)
            local window = new_window("list", { 0, 0 }, { 400, 400 })
            local dropdown = new_dropdown({ 20, 900 }, { 1, 2, 5 }, 1, env.cursor)
            window.widgets[1] = dropdown
            env.simple_ui.windows.list[1] = window
            env.mod.update(0.016)
            dropdown.dropped = true
            dropdown.update(dropdown)
            local layout = env.compat.dropdowns.state_of(dropdown).layout
            H.equal(layout.border, 4, "the row gap follows UIResolutionScale like upstream")
            H.equal(layout.count, 5, "the highest option index bounds the list")
            H.equal(dropdown.options[3].position[2], 900 - 4 - 30 * 5, "index 5 keeps its upstream slot")
        end)
        local vector3 = { x = function(v) return v.px end, y = function(v) return v.py end }
        with_simple_ui({ vector3 = vector3, opaque_axes = true }, function(env)
            local window = new_window("list", { 0, 0 }, { 400, 400 })
            local dropdown = new_dropdown({ 20, 60 }, indices(40), 35, env.cursor)
            window.widgets[1] = dropdown
            env.simple_ui.windows.list[1] = window
            env.mod.update(0.016)
            dropdown.dropped = true
            dropdown.update(dropdown)
            local first = env.compat.dropdowns.state_of(dropdown).layout.first
            env.state.cursor = { 50, 500 }
            env.state.wheel = 1
            dropdown.update(dropdown)
            H.equal(env.compat.dropdowns.state_of(dropdown).layout.first, first - 1,
                "wheel and cursor are read through Vector3.x/y when the engine supplies them")
        end)
    end)

    H.test("GUT #314 runtime check is registered, passes once, and a failing child never costs window recovery", function()
        with_simple_ui({}, function(env)
            H.deep_equal(env.mod.registered, { "issue314_simple_ui_phase2" })
            local check = env.compat.dropdowns.rt_checks[1]
            H.equal(check.name, "issue314_simple_ui_phase2")
            H.equal(check.fn(), nil)
            H.equal(check.fn(), nil)
            local receipts = 0
            for _, line in ipairs(env.state.logs) do
                if line:find("[gut:314] runtime phase=2 verdict=PASS", 1, true) then receipts = receipts + 1 end
            end
            H.equal(receipts, 1)

            local window = new_window("stranded", { -40, 30 }, { 400, 300 })
            env.simple_ui.windows.list[1] = window
            env.compat.dropdowns.tick = function() error("child exploded") end
            env.mod.update(0.016)
            H.deep_equal(window.position, { 0, 30 }, "phase-1 confinement still ran")
        end)
    end)
end
