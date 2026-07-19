return function(H, repo_root)
    local path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_crt_talent_selection.lua"
    local Selection = assert(loadfile(path))()

    H.test("CRT talent menu recognizes an unchanged selection", function()
        local current = { 1, 2, 3, 1, 2, 3 }
        local opened = Selection.snapshot(current)
        H.equal(Selection.equal(opened, current), true)
        current[2] = 1
        H.equal(opened[2], 2)
        H.equal(Selection.equal(opened, current), false)
    end)

    H.test("CRT talent menu comparison rejects added removed and invalid rows", function()
        H.equal(Selection.equal({ [1] = 1, [3] = 2 }, { [1] = 1, [3] = 2 }), true)
        H.equal(Selection.equal({ [1] = 1 }, { [1] = 1, [2] = 0 }), false)
        H.equal(Selection.equal({ [1] = 1, [2] = 0 }, { [1] = 1 }), false)
        H.equal(Selection.equal(nil, { 1 }), false)
    end)

    H.test("CRT loads the no-op guard without loading talent transposition", function()
        local entry_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker.lua"
        local guard_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/_crt_talent_menu_guard.lua"
        local dormant_swap_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/_crt_talent_swap.lua"
        local entry_file = assert(io.open(entry_path, "rb"))
        local entry_source = entry_file:read("*a")
        entry_file:close()
        local guard_file = assert(io.open(guard_path, "rb"))
        local guard_source = guard_file:read("*a")
        guard_file:close()
        local dormant_swap_file = assert(io.open(dormant_swap_path, "rb"))
        local dormant_swap_source = dormant_swap_file:read("*a")
        dormant_swap_file:close()

        H.truthy(entry_source:find(
            'mod.dofile, mod, "scripts/mods/career_tweaker/_crt_talent_menu_guard"',
            1,
            true
        ))
        H.equal(entry_source:find(
            'mod.dofile, mod, "scripts/mods/career_tweaker/_crt_talent_swap"',
            1,
            true
        ), nil)
        H.truthy(guard_source:find(
            'mod:hook("HeroWindowTalents", "on_exit"',
            1,
            true
        ))
        H.truthy(guard_source:find(
            'mod:hook("HeroWindowTalentsConsole", "on_exit"',
            1,
            true
        ))
        H.equal(dormant_swap_source:find('mod:hook("HeroWindowTalents"', 1, true), nil)
        H.equal(dormant_swap_source:find('mod:hook_safe("HeroWindowTalents"', 1, true), nil)
    end)

    H.test("CRT no-op guard skips only unchanged desktop and controller closes", function()
        local guard_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/_crt_talent_menu_guard.lua"
        local hooks = {}
        local fake_mod = { _crt = {} }
        function fake_mod:dofile()
            return Selection
        end
        function fake_mod:hook_safe(class_name, method_name, callback)
            hooks[class_name .. "." .. method_name] = callback
        end
        function fake_mod:hook(class_name, method_name, callback)
            hooks[class_name .. "." .. method_name] = callback
        end

        local old_get_mod = _G.get_mod
        local old_printf = _G.printf
        _G.get_mod = function() return fake_mod end
        _G.printf = function() end
        local ok, err = pcall(function()
            assert(loadfile(guard_path))()
        end)
        _G.get_mod = old_get_mod
        _G.printf = old_printf
        H.truthy(ok, tostring(err))

        local desktop = { _selected_talents = { 1, 2, 3 }, ui_animator = {} }
        hooks["HeroWindowTalents.on_enter"](desktop)
        H.equal(fake_mod._crt.talent_window_instance, desktop)
        local delegated = 0
        local result = hooks["HeroWindowTalents.on_exit"](function()
            delegated = delegated + 1
            return "vanilla"
        end, desktop, {})
        H.equal(result, nil)
        H.equal(delegated, 0)
        H.equal(desktop.ui_animator, nil)
        H.equal(fake_mod._crt.talent_window_instance, nil)

        local changed = { _selected_talents = { 1, 2, 3 }, ui_animator = {} }
        hooks["HeroWindowTalents.on_enter"](changed)
        changed._selected_talents[2] = 1
        result = hooks["HeroWindowTalents.on_exit"](function()
            delegated = delegated + 1
            return "vanilla"
        end, changed, {})
        H.equal(result, "vanilla")
        H.equal(delegated, 1)

        local controller = { _selected_talents = { 2, 2, 2 }, ui_animator = {} }
        hooks["HeroWindowTalentsConsole.on_enter"](controller)
        hooks["HeroWindowTalentsConsole.on_exit"](function()
            delegated = delegated + 1
        end, controller, {})
        H.equal(delegated, 1)
        H.equal(controller.ui_animator, nil)
        H.equal(fake_mod._crt.talent_menu_noop_skips, 2)
    end)
end
