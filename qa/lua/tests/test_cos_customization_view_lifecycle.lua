-- Boundary + behaviour guard for the #1159 HeroWindowItemCustomization view
-- lifecycle owner (_cos_customization_view_lifecycle.lua).
--
-- The load-bearing property this file exists to pin: `_send_la_apply` is
-- FORWARD-DECLARED in the entry and only assigned ~2400 lines below the install
-- call, so the owner must resolve it through a getter AT DRAIN TIME. The last
-- test asserts the getter still returns nil at install time and the real sender
-- at drain time. That is a signal the fix cannot move: converting the getter
-- back into an install-time value makes the drain receive nil, and the same
-- assertion that proves the getter works is the one that catches the regression.
return function(H, repo_root)
    local function read(relative)
        local file = assert(io.open(repo_root .. "/" .. relative, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end
    local function occurrences(haystack, needle)
        local count, offset = 0, 1
        while true do
            local at = haystack:find(needle, offset, true)
            if not at then return count end
            count, offset = count + 1, at + #needle
        end
    end

    local entry = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
    local module_relative = "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_customization_view_lifecycle.lua"
    local source = read(module_relative)
    local owner_install =
        'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_customization_view_lifecycle").install(mod, {'

    H.test("cos view lifecycle installs exactly once at the former inline position", function()
        H.equal(occurrences(entry, owner_install), 1)
        local at_owner = entry:find(owner_install, 1, true)
        local at_session = entry:find(
            '"scripts/mods/cosmetics_tweaker/_cos_offhand_session_state").new({', 1, true)
        local at_picker = entry:find(
            '"scripts/mods/cosmetics_tweaker/_cos_offhand_picker").install(mod, {', 1, true)
        H.truthy(at_session and at_picker)
        -- After the session state it reverts through, before the picker that
        -- writes the backend id it clears.
        H.truthy(at_session < at_owner)
        H.truthy(at_owner < at_picker)
    end)

    H.test("cos view lifecycle owns all three customization-view hooks exclusively", function()
        for _, method in ipairs({ "_create_preview_widget", "_update_environment", "on_exit" }) do
            local pair = '"HeroWindowItemCustomization", "' .. method .. '"'
            -- VMF silently drops a second registration on the same (Class,
            -- method) pair, so a re-inlined copy would shadow the owner rather
            -- than fail loudly. The entry-side absence row is the real guard.
            H.equal(occurrences(entry, pair), 0)
            H.equal(occurrences(source, pair), 1)
        end
    end)

    H.test("cos view lifecycle crossing locals stay entry-owned accessors", function()
        H.equal(occurrences(entry, "get_send_la_apply = function() return _send_la_apply end,"), 1)
        H.truthy(entry:find("get_active_customization_backend_id = function()", 1, true))
        H.truthy(entry:find("set_active_customization_backend_id = function(value)", 1, true))
        H.truthy(entry:find("local _active_customization_backend_id", 1, true))
        H.equal(source:find("local _send_la_apply", 1, true), nil)
        H.equal(source:find("local _active_customization_backend_id", 1, true), nil)
        -- Re-dofile'ing a sibling would build a SECOND instance of a stateful
        -- module (mod:dofile is not a singleton), so every handle arrives via deps.
        H.equal(occurrences(source, 'mod:dofile("'), 0)
    end)

    H.test("cos view lifecycle does not overlap its sibling view owners", function()
        -- Four other modules hook this same class on disjoint methods.
        for _, foreign in ipairs({ "_setup_illusions", "_handle_input", "_state_draw_overview",
                                   "_enable_craft_button", "_on_illusion_index_pressed", "on_enter" }) do
            H.equal(source:find('"HeroWindowItemCustomization", "' .. foreign .. '"', 1, true), nil)
        end
        H.equal(occurrences(source, "network_register"), 0)
        H.equal(occurrences(source, "network_send"), 0)
        H.truthy(source:find("Owned by:", 1, true))
        H.truthy(source:find("Consumed via:", 1, true))
    end)

    -- ------------------------------------------------------------- behaviour
    -- One shared engine stub + install, re-used by the behaviour tests below.
    local hooks, mod = {}, {}
    function mod:hook_safe(class_name, method_name, fn)
        H.equal(class_name, "HeroWindowItemCustomization")
        hooks[method_name] = fn
    end
    function mod:hook(class_name, method_name, fn)
        H.equal(class_name, "HeroWindowItemCustomization")
        hooks[method_name] = fn
    end
    function mod:info() end

    local worlds = {}
    local function world_store(w) worlds[w] = worlds[w] or {}; return worlds[w] end
    local repoints, residency_asks, restores, drains = {}, {}, {}, {}
    local picker_closed, resident, wields = false, true, {}
    -- The entry-side local the owner must NOT capture by value. nil at install
    -- time, exactly as in the real entry file.
    local entry_send_la_apply = nil

    local inventory = {
        wielded_slot = "slot_melee",
        _equipment = { slots = { slot_melee = {}, slot_ranged = {} } },
        wield = function(_, slot) wields[#wields + 1] = slot end,
    }
    -- The engine surface is installed ONLY for the duration of a single test and
    -- then restored. These stubs must never leak into sibling test files -- the
    -- #1145 regression-check tests build their own fake globals and a leftover
    -- _G.Managers / _G.World here silently rewires them.
    local engine = {
        DamageUtils = { is_in_inn = false },
        ShadingEnvironment = { scalar = function() return 1.0 end },
        Application = { can_get = function() return true end },
        World = {
            has_data = function(w, key) return world_store(w)[key] ~= nil end,
            get_data = function(w, key) return world_store(w)[key] end,
            set_data = function(w, key, value) world_store(w)[key] = value end,
            set_shading_environment = function(_w, _env, name) repoints[#repoints + 1] = name; return true end,
        },
        Unit = { alive = function() return true end },
        ScriptUnit = { has_extension = function() return inventory end },
        Managers = { player = {} },
    }
    local function with_engine(body)
        local saved = {}
        for name, stub in pairs(engine) do saved[name] = rawget(_G, name); _G[name] = stub end
        local ok, err = pcall(body)
        for name in pairs(engine) do _G[name] = saved[name] end
        if not ok then error(err, 0) end
    end

    local deps = {
        resource_residency = {
            shading_environment_resident = function(name, application, _unused, tag)
                residency_asks[#residency_asks + 1] = { name = name, tag = tag, application = application }
                return resident
            end,
        },
        local_player_safe = function() return { player_unit = {} } end,
        glow_picker = { is_open = function() return true end, close = function() picker_closed = true end },
        la_persist = { marker = "la-persist" },
        offhand_commit = {
            drain = function(_mod, queue, persist, sender, alive)
                drains[#drains + 1] = { queue = queue, persist = persist, sender = sender, alive = alive }
                return 1
            end,
        },
        offhand_session_state = {
            restore = function(bid, baseline) restores[#restores + 1] = { bid = bid, baseline = baseline } end,
        },
        dbg = function() end,
        dbg_alert = function() end,
        trace = function() end,
        get_send_la_apply = function() return entry_send_la_apply end,
        get_active_customization_backend_id = function() return mod.__bid end,
        set_active_customization_backend_id = function(value) mod.__bid = value end,
    }

    local installed = assert(loadfile(repo_root .. "/" .. module_relative))().install(mod, deps)

    local function view_for(world, style)
        return { _preview_widget = {
            element = { pass_data = { { world = world } } },
            style = { viewport = style or {} },
            content = {},
        } }
    end
    local keep_world, mission_world, unlit_world = {}, {}, {}
    local keep_view = view_for(keep_world)
    local mission_view = view_for(mission_world, { shading_environment = "environment/ui_hdr" })
    local unlit_view = view_for(unlit_world, { shading_environment = "environment/ui_hdr" })
    world_store(mission_world).shading_environment = { env = true }
    world_store(unlit_world).shading_environment = { env = true }

    H.test("cos view lifecycle install registers three hooks and reports success", function()
        H.equal(installed, true)
        H.truthy(hooks._create_preview_widget and hooks._update_environment and hooks.on_exit)
    end)

    H.test("cos view lifecycle keep path is a pure pass-through", function() with_engine(function()
        engine.DamageUtils.is_in_inn = true
        hooks._create_preview_widget(keep_view)
        H.equal(#residency_asks, 0)
        H.equal(#repoints, 0)
        engine.DamageUtils.is_in_inn = false
    end) end)

    H.test("cos view lifecycle re-points a resident mission preview env", function() with_engine(function()
        hooks._create_preview_widget(mission_view)
        H.equal(#residency_asks, 1)
        H.equal(residency_asks[1].name, "environment/ui_store_preview")
        H.equal(residency_asks[1].tag, "cos_mission_item_preview")
        H.equal(residency_asks[1].application, engine.Application)
        H.equal(#repoints, 1)
        H.equal(repoints[1], "environment/ui_store_preview")
        H.equal(world_store(mission_world).cos_preview_env_repointed, true)
    end) end)

    H.test("cos view lifecycle leaves a non-resident env unpointed", function() with_engine(function()
        resident = false
        hooks._create_preview_widget(unlit_view)
        H.equal(#repoints, 1)
        H.equal(world_store(unlit_world).cos_preview_env_repointed, nil)
        resident = true
    end) end)

    H.test("cos view lifecycle blend target follows the re-point flag", function() with_engine(function()
        local seen = {}
        local function vanilla(_self, env, force_default)
            seen[#seen + 1] = { env = env, force_default = force_default }
        end
        -- Re-pointed: vanilla's per-weapon variation goes through untouched.
        hooks._update_environment(vanilla, mission_view, "weapons_default_01", false)
        H.equal(seen[1].env, "weapons_default_01")
        H.equal(seen[1].force_default, false)
        -- Not re-pointed: pinned to "default", which is the #228 AV guard.
        hooks._update_environment(vanilla, unlit_view, "weapons_default_01", false)
        H.equal(seen[2].force_default, true)
        engine.DamageUtils.is_in_inn = true
        hooks._update_environment(vanilla, keep_view, "weapons_default_01", false)
        H.equal(seen[3].force_default, false)
        engine.DamageUtils.is_in_inn = false
    end) end)

    H.test("cos view lifecycle exit reverts an un-Applied offhand pick", function() with_engine(function()
        mod.__bid = "bid-1"
        mod._offhand_baseline = { ["bid-1"] = { option = "baseline" } }
        mod._offhand_committed = {}
        mod._pending_la_emit_on_exit = { pending = true }
        hooks.on_exit({ _item_backend_id = "bid-1" })
        H.equal(mod.__bid, nil)
        H.truthy(picker_closed)
        H.equal(#restores, 1)
        H.equal(restores[1].bid, "bid-1")
        -- No Apply this session, so the queued peer broadcast is dropped.
        H.equal(#drains, 0)
        H.equal(mod._offhand_baseline["bid-1"], nil)
        H.equal(mod._offhand_committed["bid-1"], nil)
    end) end)

    H.test("cos view lifecycle exit drain resolves the LA sender at call time", function() with_engine(function()
        -- Precondition: the sender is still unassigned, so an install-time
        -- by-value hand-off would have passed nil.
        H.equal(deps.get_send_la_apply(), nil)
        entry_send_la_apply = function() end
        mod.__bid = "bid-2"
        mod._offhand_baseline = {}
        mod._offhand_committed = { ["bid-2"] = true }
        mod._pending_la_emit_on_exit = { pending = true }
        hooks.on_exit({ _item_backend_id = "bid-2" })
        H.equal(#drains, 1)
        H.equal(drains[1].sender, entry_send_la_apply)
        H.equal(drains[1].persist, deps.la_persist)
        H.equal(mod._pending_la_emit_on_exit, nil)
        -- A drained emit pulse-wields the other slot and back so the committed
        -- mesh respawns; vanilla wield short-circuits on the same slot.
        H.equal(table.concat(wields, ","), "slot_ranged,slot_melee")
    end) end)
end
