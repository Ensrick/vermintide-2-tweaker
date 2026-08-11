-- Guards the #1159 boon-offer view owner extraction: everything ct does to WHERE
-- the offered-boon widgets sit in the shrine (DeusShopView) and the Chest of
-- Trials (DeusCursedChestView) moved VERBATIM out of the ct_dev entry into
-- _ct_boon_offer_view_owner.lua.
--
-- ONE contiguous chunk moved (old entry lines 2711-3104) and the installer sits
-- at the exact line it occupied, so unlike the previous ct slices there is no
-- load-order deviation to argue about at all - the ordering assertion here is
-- simply that the install site is still between the boon-generation hook above
-- it and the curse-mutator hook below it.
--
-- Almost everything below is executable rather than textual: the module is
-- loaded for real and installed against a recording stub, so a dropped hook, a
-- by-value _dbg bind, a swallowed vanilla update, a lost price passenger, or a
-- reflow that stops reproducing vanilla's own row spacing fails here instead of
-- in a Chaos Wastes shrine.
return function(H, repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local module_path = root .. "_ct_boon_offer_view_owner.lua"

    local function read(name)
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    -- Comment-stripped view of a source, for the "this vocabulary must not
    -- appear" assertions. The owner's header DISCUSSES its neighbours by name -
    -- that is the point of the header - so those checks have to run against code
    -- only or they would forbid documenting the boundary they exist to protect.
    -- Quoted strings are skipped so a `--` inside a literal cannot truncate.
    local function code_only(source)
        local out, i, n = {}, 1, #source
        while i <= n do
            local c = source:sub(i, i)
            if source:sub(i, i + 3) == "--[[" then
                local close = source:find("]]", i + 4, true)
                i = close and (close + 2) or (n + 1)
            elseif source:sub(i, i + 1) == "--" then
                local nl = source:find("\n", i, true)
                i = nl or (n + 1)
            elseif c == '"' or c == "'" then
                local quote = c
                out[#out + 1] = c
                i = i + 1
                while i <= n do
                    local ch = source:sub(i, i)
                    out[#out + 1] = ch
                    if ch == "\\" then
                        out[#out + 1] = source:sub(i + 1, i + 1)
                        i = i + 2
                    elseif ch == quote or ch == "\n" then
                        i = i + 1
                        break
                    else
                        i = i + 1
                    end
                end
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
        return table.concat(out)
    end

    local entry = read("chaos_wastes_tweaker_dev.lua")
    local owner = read("_ct_boon_offer_view_owner.lua")
    local owner_code = code_only(owner)

    -- Geometry the moved code hard-codes. Row height 194 is power_up_root's own
    -- height in both defs files; -20000 is the off-window park position.
    local ROW_H = 194
    local HIDDEN_Y = -20000

    -- ------------------------------------------------------------------
    -- Executable fixture: load the real module and install it against a
    -- recording mod stub. The module only registers callbacks at load time, so
    -- nothing here reaches the engine.
    -- ------------------------------------------------------------------
    local function fixture(overrides)
        overrides = overrides or {}
        local hooks, order, dofiles, logs = {}, {}, {}, {}
        local mod = {}

        function mod:hook(class_name, method_name, callback)
            local key = class_name .. "." .. method_name
            H.equal(hooks[key], nil, "duplicate hook " .. key)
            hooks[key] = callback
            order[#order + 1] = "hook:" .. key
        end

        function mod:hook_safe(class_name, method_name, callback)
            local key = class_name .. "." .. method_name
            H.equal(hooks[key], nil, "duplicate safe hook " .. key)
            hooks[key] = callback
            order[#order + 1] = "safe:" .. key
        end

        function mod:dofile(path)
            dofiles[#dofiles + 1] = path
            error("the boon-offer view owner must not load any module: " .. tostring(path))
        end

        function mod:info(fmt, ...) logs[#logs + 1] = { "info", fmt } end
        function mod:warning(fmt, ...) logs[#logs + 1] = { "warning", fmt } end

        local ctx = { dbg = function() end }
        for key, value in pairs(overrides) do
            if value == "\0drop" then ctx[key] = nil else ctx[key] = value end
        end

        local installer = assert(loadfile(module_path))()
        local returned = installer(mod, ctx)
        return mod, hooks, order, dofiles, logs, returned
    end

    -- The moved code reads engine globals and VT2's math.clamp extension. Swap
    -- stubs in for the duration of a test and always restore, so the suite stays
    -- order-independent.
    local function with_globals(globals, body)
        local names = { "UIWidget", "UISceneGraph", "UIInverseScaleVectorToResolution", "Mouse" }
        local saved, saved_clamp = {}, math.clamp
        for _, name in ipairs(names) do saved[name] = rawget(_G, name) end

        -- UIWidget.init returns the definition itself: it already carries the
        -- content.{track,thumb}_hotspot tables and style.thumb.offset the frame
        -- pass writes, which is exactly the shape the real widget exposes.
        _G.UIWidget = { init = function(definition) return definition end }
        _G.UISceneGraph = { get_world_position = function() return { 0, 0, 0 } end }
        _G.UIInverseScaleVectorToResolution = function(cursor) return cursor end
        _G.Mouse = nil
        math.clamp = function(value, min, max)
            if value < min then return min end
            if value > max then return max end
            return value
        end

        for name, value in pairs(globals) do _G[name] = value end
        local ok, err = pcall(body)
        for _, name in ipairs(names) do _G[name] = saved[name] end
        math.clamp = saved_clamp
        if not ok then error(err, 0) end
    end

    -- A shop view carrying `count` offers, shaped the way the build hook reads it.
    local function shop_view(count)
        local offers, widgets = {}, {}
        for i = 1, count do
            widgets[i] = { offset = { 0, 0, 0 } }
            offers[i] = { widget = widgets[i] }
        end
        return {
            _shop_item_widgets = widgets,
            _shop_items = { power_ups = offers },
            _widgets = {},
            _shop_type = "shop_khorne",
        }, widgets
    end

    local function chest_view(count)
        local widgets = {}
        for i = 1, count do widgets[i] = { offset = { 0, 0, 0 } } end
        return { _power_up_widgets = widgets, _widgets = {} }, widgets
    end

    -- ------------------------------------------------------------------
    -- Module shape
    -- ------------------------------------------------------------------
    H.test("boon-offer view owner is a named ctx installer, not an anonymous chunk", function()
        H.truthy(owner:find("local function install(mod, ctx)", 1, true))
        H.truthy(owner:find("\nreturn install\n", 1, true))
        H.equal(count_plain(owner, "return function("), 0)
    end)

    H.test("owner is dofile'd exactly once by the entry", function()
        H.equal(count_plain(entry,
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_offer_view_owner"), 1)
    end)

    H.test("owner owns no command, no RPC and no regression check", function()
        H.equal(count_plain(owner, "mod:command"), 0)
        H.equal(count_plain(owner, "mod:network_register"), 0)
        H.equal(count_plain(owner, "_rt_register("), 0)
    end)

    H.test("the install site kept the position the moved code occupied", function()
        -- No load-order deviation exists only while the installer still sits
        -- between the boon-generation hook above it and the curse runtime below
        -- it. Since 0.7.334-dev that curse runtime is itself an owner
        -- (_ct_node_entry_owner), so the neighbour below is its install site -
        -- which sits at the exact line the curse hook block used to occupy.
        -- Since 0.7.336-dev the offer GENERATION hook is itself an owner
        -- (_ct_run_creation_owner, which carries it because the boon-altar
        -- no-repeat ledger it filters against is per-run state setup_run creates),
        -- so the neighbour above is that owner's install site - which sits at the
        -- exact line the generation hook used to occupy.
        local gen_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner", 1, true))
        H.equal(count_plain(entry,
            'mod:hook("DeusPowerUpUtils", "generate_random_power_ups"'), 0)
        local install_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_offer_view_owner", 1, true))
        local curse_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_node_entry_owner", 1, true))
        H.truthy(gen_at < install_at, "offer GENERATION must still register before the owner")
        H.truthy(install_at < curse_at, "the owner must still install before the curse runtime")
    end)

    -- ------------------------------------------------------------------
    -- Hook cardinality and placement
    -- ------------------------------------------------------------------
    H.test("owner registers exactly its four hooks, with the original verbs and order", function()
        local _, hooks, order, dofiles = fixture()
        H.deep_equal(order, {
            "safe:DeusShopView._create_ui_elements",
            "safe:DeusCursedChestView.create_ui_elements",
            "hook:DeusShopView.update",
            "hook:DeusCursedChestView.update",
        })
        H.deep_equal(dofiles, {})
        H.truthy(hooks["DeusShopView._create_ui_elements"])
        H.truthy(hooks["DeusCursedChestView.create_ui_elements"])
        H.truthy(hooks["DeusShopView.update"])
        H.truthy(hooks["DeusCursedChestView.update"])
    end)

    H.test("the four hooks left the entry and live only in the owner", function()
        for _, needle in ipairs({
            'mod:hook_safe("DeusShopView", "_create_ui_elements"',
            'mod:hook_safe("DeusCursedChestView", "create_ui_elements"',
            'mod:hook("DeusShopView", "update"',
            'mod:hook("DeusCursedChestView", "update"',
        }) do
            H.equal(count_plain(entry, needle), 0, "entry must not re-register " .. needle)
            H.equal(count_plain(owner, needle), 1, "owner must register " .. needle .. " once")
        end
    end)

    H.test("the moved file-local left the entry entirely", function()
        -- fix_arc_nan had ZERO references outside the moved region before the
        -- split. A copy left behind would shadow nothing and drift silently.
        H.equal(count_plain(entry, "fix_arc_nan"), 0)
        H.truthy(owner:find("local function fix_arc_nan", 1, true))
        H.equal(count_plain(entry, "mod._ct_boon_scroll_setup"), 0)
        H.equal(count_plain(owner, "mod._ct_boon_scroll_setup ="), 1)
    end)

    -- ------------------------------------------------------------------
    -- Boundaries against the three neighbouring view owners
    -- ------------------------------------------------------------------
    H.test("owner stays on its own (Class, method) pairs", function()
        -- VMF silently drops a second registration on a pair, so a hook here on
        -- any neighbour's method would ship one of the two features dead.
        for _, needle in ipairs({
            '"_get_power_up_costs"', '"_update_shop_widgets"', '"_init_power_up_widget"',
            '"_on_power_up_bought"', '"_on_button_pressed"',
        }) do
            H.equal(count_plain(owner, "mod:hook(\"DeusShopView\", " .. needle), 0)
            H.equal(count_plain(owner, "mod:hook_safe(\"DeusShopView\", " .. needle), 0)
            H.equal(count_plain(owner, "mod:hook(\"DeusCursedChestView\", " .. needle), 0)
            H.equal(count_plain(owner, "mod:hook_safe(\"DeusCursedChestView\", " .. needle), 0)
        end
        -- #211 grant-source provenance is not layout: it stays in the entry.
        H.equal(count_plain(entry, 'mod:hook("DeusCursedChestView", "_on_button_pressed"'), 1)
        H.equal(count_plain(owner, "_ct_grant_source"), 0)
    end)

    H.test("owner is layout only: no price policy, no offer generation, no tooltip", function()
        -- It must be able to lay out whatever the pool produced, so its CODE may
        -- not read a setting, a price, or a boon identity - only #boon_widgets.
        -- Checked against the comment-stripped source: the header names these
        -- neighbours on purpose, and forbidding the words there would forbid
        -- documenting the boundary.
        H.equal(count_plain(owner_code, "effective_setting"), 0)
        H.equal(count_plain(owner_code, "generate_random_power_ups"), 0)
        H.equal(count_plain(owner_code, "get_power_up_costs"), 0)
        H.equal(count_plain(owner_code, "_ct_boon_preview"), 0)
        -- The stripper must actually be stripping, or every line above is vacuous.
        H.truthy(count_plain(owner, "generate_random_power_ups") > 0,
            "the header is expected to name the offer-generation neighbour")
        H.truthy(count_plain(owner_code, "mod._ct_boon_scroll_setup") > 0,
            "code_only must keep real code")
    end)

    -- ------------------------------------------------------------------
    -- ctx contract
    -- ------------------------------------------------------------------
    H.test("install refuses a missing or malformed ctx at load time", function()
        local installer = assert(loadfile(module_path))()
        H.equal(pcall(installer, {}, nil), false, "nil ctx must assert")
        H.equal(pcall(installer, {}, "nope"), false, "non-table ctx must assert")
        H.equal(pcall(function() return fixture({ dbg = "\0drop" }) end), false,
            "a dropped ctx.dbg must assert")
    end)

    H.test("_dbg is late-bound, so a by-value regression fails", function()
        -- The wrapper's target is assigned only AFTER install. A by-value bind
        -- would freeze nil here and the blessing dump would throw on first open.
        local target
        local seen = {}
        local _, hooks = fixture({ dbg = function(...) return target(...) end })
        target = function(fmt) seen[#seen + 1] = fmt end
        with_globals({}, function()
            local view = shop_view(2)
            hooks["DeusShopView._create_ui_elements"](view, {}, {}, { "blessing_of_power" })
        end)
        H.equal(#seen, 1, "the blessing dump must reach the late-bound _dbg exactly once")
        H.truthy(seen[1]:find("DeusShopView opened", 1, true))
    end)

    H.test("a non-table blessings argument skips the dump entirely", function()
        local calls = 0
        local _, hooks = fixture({ dbg = function() calls = calls + 1 end })
        with_globals({}, function()
            hooks["DeusShopView._create_ui_elements"](shop_view(2), {}, {}, nil)
        end)
        H.equal(calls, 0)
    end)

    -- ------------------------------------------------------------------
    -- The degenerate-arc repair
    -- ------------------------------------------------------------------
    H.test("a lone widget's NaN arc offset is centred, on both views", function()
        local nan = 0 / 0
        H.truthy(nan ~= nan, "the fixture needs a real NaN to exercise the x ~= x test")
        local _, hooks = fixture()
        with_globals({}, function()
            local view, widgets = shop_view(1)
            widgets[1].offset = { nan, nan, 0 }
            hooks["DeusShopView._create_ui_elements"](view, {}, {}, nil)
            H.equal(widgets[1].offset[1], 0)
            H.equal(widgets[1].offset[2], 0)

            local cview, cwidgets = chest_view(1)
            cwidgets[1].offset = { nan, nan, 0 }
            hooks["DeusCursedChestView.create_ui_elements"](cview)
            H.equal(cwidgets[1].offset[1], 0)
            H.equal(cwidgets[1].offset[2], 0)
        end)
    end)

    H.test("a healthy or multi-widget arc is left exactly as vanilla built it", function()
        local nan = 0 / 0
        local _, hooks = fixture()
        with_globals({}, function()
            local view, widgets = shop_view(2)
            widgets[1].offset = { nan, nan, 0 }
            widgets[2].offset = { 5, 7, 0 }
            hooks["DeusShopView._create_ui_elements"](view, {}, {}, nil)
            H.truthy(widgets[1].offset[1] ~= widgets[1].offset[1],
                "the repair is deliberately scoped to the 1-widget case")
            H.equal(widgets[2].offset[1], 5)
            H.equal(widgets[2].offset[2], 7)
        end)
    end)

    -- ------------------------------------------------------------------
    -- The two price passengers that share the build hook
    -- ------------------------------------------------------------------
    H.test("the build hook dispatches to both price modules when they exist", function()
        local mod, hooks = fixture()
        local decorated, enforced = 0, 0
        mod._ct_start_shrine_runtime = { decorate_shop = function() decorated = decorated + 1 end }
        mod._ct_boon_pricing_runtime = { enforce_shop = function() enforced = enforced + 1 end }
        with_globals({}, function()
            hooks["DeusShopView._create_ui_elements"](shop_view(2), {}, {}, nil)
        end)
        H.equal(decorated, 1)
        H.equal(enforced, 1)
    end)

    H.test("the build hook is a no-op for price when the modules have not loaded", function()
        -- Both modules are dofile'd LATER in the entry than this installer, so
        -- the nil guards are the load-order contract, not decoration.
        local mod, hooks = fixture()
        H.equal(mod._ct_start_shrine_runtime, nil)
        H.equal(mod._ct_boon_pricing_runtime, nil)
        with_globals({}, function()
            hooks["DeusShopView._create_ui_elements"](shop_view(2), {}, {}, nil)
        end)
    end)

    -- ------------------------------------------------------------------
    -- Scroll engagement and the reflow geometry
    -- ------------------------------------------------------------------
    H.test("an offer count that fits the vanilla arc stays 100% vanilla", function()
        local _, hooks = fixture()
        with_globals({}, function()
            local view = shop_view(4) -- the shop's vanilla capacity
            hooks["DeusShopView._create_ui_elements"](view, {}, {}, nil)
            H.equal(view._ct_boon_scroll, nil, "no scroll state below the cap")
            H.equal(#view._widgets, 0, "no scrollbar widget may be injected")
        end)
    end)

    H.test("an over-cap shop engages the scrollbar with vanilla row spacing", function()
        local _, hooks = fixture()
        with_globals({}, function()
            local view, widgets = shop_view(6)
            hooks["DeusShopView._create_ui_elements"](view, {}, {}, nil)

            local st = view._ct_boon_scroll
            H.truthy(st, "6 offers over a 4-row window must engage")
            H.equal(st.count, 6)
            H.equal(st.visible, 4)
            H.equal(st.top, 1)
            H.equal(st.max_top, 3)
            H.equal(st.track_h, 4 * ROW_H)
            H.equal(#view._widgets, 1, "exactly one scrollbar widget is injected")
            H.equal(view._widgets[1], st.scrollbar_widget)
            H.equal(st.scrollbar_widget.scenegraph_id, "power_up_root")

            -- Vanilla's own 4-row offsets are 291/97/-97/-291; the reflow must
            -- reproduce them exactly so an engaged view is visually unchanged.
            for i, expected in ipairs({ 291, 97, -97, -291 }) do
                H.equal(widgets[i].offset[1], 0, "the arc's x-sway must be flattened")
                H.equal(widgets[i].offset[2], expected)
            end
            for i = 5, 6 do
                H.equal(widgets[i].offset[2], HIDDEN_Y, "off-window rows park off-screen")
            end
        end)
    end)

    H.test("an over-cap cursed chest engages on its own 3-row window", function()
        local _, hooks = fixture()
        with_globals({}, function()
            local view, widgets = chest_view(5)
            hooks["DeusCursedChestView.create_ui_elements"](view)

            local st = view._ct_boon_scroll
            H.truthy(st)
            H.equal(st.visible, 3)
            H.equal(st.max_top, 3)
            for i, expected in ipairs({ 194, 0, -194 }) do
                H.equal(widgets[i].offset[2], expected)
            end
            H.equal(widgets[4].offset[2], HIDDEN_Y)
            H.equal(widgets[5].offset[2], HIDDEN_Y)
        end)
    end)

    H.test("off-window rows are hidden by position, never by disabling vanilla's hotspot", function()
        -- vanilla's own update owns content.button_hotspot.disable_button;
        -- writing it here would fight the view every frame. The moved comment
        -- explains that, so the assertion is against code only.
        H.equal(count_plain(owner_code, "disable_button"), 0)
        H.truthy(count_plain(owner, "disable_button") > 0,
            "the moved code is expected to document why it does not touch that field")
    end)

    H.test("a view with no _widgets array degrades to no-scroll instead of throwing", function()
        local _, hooks, _, _, logs = fixture()
        with_globals({}, function()
            local view = shop_view(6)
            view._widgets = nil
            hooks["DeusShopView._create_ui_elements"](view, {}, {}, nil)
            H.equal(view._ct_boon_scroll, nil)
        end)
        local warned = false
        for _, entry_log in ipairs(logs) do
            if entry_log[1] == "warning" then warned = true end
        end
        H.truthy(warned, "the degrade path must report itself")
    end)

    -- ------------------------------------------------------------------
    -- The per-frame pass behind the two wrapping update hooks
    -- ------------------------------------------------------------------
    local function wheel_view(count, delta)
        local view = shop_view(count)
        view.input_service = function()
            return { get = function(_, key)
                if key == "scroll_axis" then return { y = delta } end
                return nil
            end }
        end
        return view
    end

    H.test("the wheel scrolls one row per notch and clamps at both ends", function()
        local _, hooks = fixture()
        with_globals({}, function()
            local view = wheel_view(6, -1) -- negative y = wheel down = scroll down
            hooks["DeusShopView._create_ui_elements"](view, {}, {}, nil)
            local vanilla = 0
            local inner = function() vanilla = vanilla + 1 end

            hooks["DeusShopView.update"](inner, view, 0.016, 1)
            H.equal(view._ct_boon_scroll.top, 2)
            hooks["DeusShopView.update"](inner, view, 0.016, 1)
            H.equal(view._ct_boon_scroll.top, 3)
            hooks["DeusShopView.update"](inner, view, 0.016, 1)
            H.equal(view._ct_boon_scroll.top, 3, "top must clamp at max_top, never run off the list")
            H.equal(vanilla, 3, "vanilla update runs every frame regardless")

            -- and the reflow follows the new top
            local widgets = view._shop_item_widgets
            H.equal(widgets[1].offset[2], HIDDEN_Y)
            H.equal(widgets[3].offset[2], 291)
        end)
    end)

    H.test("both update wrappers call vanilla exactly once even when the frame pass throws", function()
        -- guard-is-not-bail (PROJECT_STANDARDS 4.2): a broken scroll state must
        -- cost the scrollbar, never the view.
        local _, hooks = fixture()
        with_globals({}, function()
            for _, key in ipairs({ "DeusShopView.update", "DeusCursedChestView.update" }) do
                local calls = 0
                local inner = function() calls = calls + 1 end
                -- scrollbar_widget present but shapeless: content indexing throws.
                local view = { _ct_boon_scroll = { widgets = {}, scrollbar_widget = {} } }
                hooks[key](inner, view, 0.016, 1)
                H.equal(calls, 1, key .. " must still run vanilla")
                H.equal(view._ct_boon_scroll, nil, key .. " must disable scroll for that view")
            end
        end)
    end)

    H.test("a view that never engaged is a cheap no-op every frame", function()
        local _, hooks = fixture()
        with_globals({}, function()
            local calls = 0
            local inner = function() calls = calls + 1 end
            local view = shop_view(3)
            hooks["DeusShopView._create_ui_elements"](view, {}, {}, nil)
            hooks["DeusShopView.update"](inner, view, 0.016, 1)
            H.equal(calls, 1)
            H.equal(view._ct_boon_scroll, nil)
        end)
    end)
end
