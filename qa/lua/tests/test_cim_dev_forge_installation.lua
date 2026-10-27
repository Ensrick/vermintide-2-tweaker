return function(H, repo_root)
    local F = assert(loadfile(repo_root .. "/qa/lua/fixtures/cim_dev_apply_installed.lua"))()
    local function no_apply(f)
        H.truthy(f.mod._cim_illusion_swap_provider == nil
            and f.mod._cim_illusion_apply_presentation_owner == nil
            and f.hooks["HeroWindowItemCustomization._enable_craft_button"] == nil
            and f.hooks["HeroWindowItemCustomization._on_illusion_index_pressed"] == nil
            and f.checks.issue1465_illusion_apply_presentation == nil,
            "known incomplete Forge must deny new Apply UI/check/owner/provider")
    end
    local function last_blocked(f)
        local row = f.errors[#f.errors]
        H.equal(row[1], "Failed to load illusion_swap: %s")
        H.truthy(row[2]:find("required Forge installer incomplete", 1, true))
    end
    H.test("Dev Apply actual whole Forge prerequisite retains native UI and ordered once binding", function()
        local f = F.installed(repo_root)
        H.equal(#f.errors, 0)
        f.window:_on_illusion_index_pressed(2, false, false)
        H.equal(f.window._widgets_by_name.craft_button.content.visible, true)
        H.equal(f.window._widgets_by_name.craft_button.content.button_hotspot.disable_button, false)
        H.equal(f.window._menu_input_description.generic_actions, f.actions.item_setting)
        H.equal(f.env.GameSettingsDevelopment.read_only_backend, true)
        local counts, at = {}, {}
        for i, name in ipairs(f.loads) do counts[name] = (counts[name] or 0) + 1; at[name] = i end
        local prefix = "scripts/mods/crafting_in_modded_dev/"
        for _, name in ipairs({ "_cim_illusion_apply_presentation", "_lib_local_illusion_apply", "standard_forge", "illusion_swap" }) do
            H.equal(counts[prefix .. name], 1, name)
        end
        H.truthy(at[prefix .. "_cim_illusion_apply_presentation"] < at[prefix .. "standard_forge"])
        H.truthy(at[prefix .. "_lib_local_illusion_apply"] < at[prefix .. "standard_forge"])
        H.truthy(at[prefix .. "standard_forge"] < at[prefix .. "illusion_swap"])
        local order = {}; for i, name in ipairs(f.order) do order[name] = i end
        H.truthy(order["hook:HeroWindowItemCustomization._update_state_craft_button"]
            < order["hook:HeroWindowItemCustomization._update_property_option"])
        H.truthy(order["command:mirror_dump"] < order["hook:HeroWindowItemCustomization._enable_craft_button"])
        H.truthy(order["hook:HeroWindowItemCustomization._on_illusion_index_pressed"]
            < order["check:issue1465_illusion_apply_presentation"])
        H.truthy(loadstring(f.entry), "whole Dev entry compiles under native200locals")
    end)
    H.test("Dev Apply required Forge failure cannot publish complete capability", function()
        local f = F.installed(repo_root, { fail_hook = "HeroWindowItemCustomization._update_state_craft_button",
            failure = "dev144-required-forge-state-error" })
        H.equal(f.hooks["HeroWindowItemCustomization._update_state_craft_button"], nil)
        no_apply(f)
        H.equal(#f.errors, 2)
        H.equal(f.errors[1][1], "Failed to load standard_forge: %s")
        H.equal(f.errors[1][2], "dev144-required-forge-state-error")
        last_blocked(f)
    end)
    H.test("Dev Apply whole Forge prerequisite rejects early and late actual body failure", function()
        local early = F.installed(repo_root, { after_load = function(name, module)
            if name == "scripts/mods/crafting_in_modded_dev/_cim_illusion_apply_presentation" then
                local bind = module.bind
                module.bind = function(mod, ...)
                    local capsule = bind(mod, ...)
                    mod._cim_synthetic_item_contract = nil
                    return capsule
                end
            end
        end })
        H.equal(early.hooks["HeroWindowItemCustomization._update_state_craft_button"], nil)
        no_apply(early); last_blocked(early)
        local late = F.installed(repo_root, { fail_hook = "HeroWindowCrafting.update", failure = "late-Forge-error" })
        H.equal(type(late.hooks["HeroWindowItemCustomization._update_state_craft_button"]), "function")
        no_apply(late); H.equal(late.errors[1][2], "late-Forge-error"); last_blocked(late)
    end)
    H.test("Dev Apply private missing or duplicate state handoff cannot complete Forge", function()
        for _, duplicate in ipairs({ false, true }) do
            local f = F.installed(repo_root, { after_load = function(name, module)
                if name == "scripts/mods/crafting_in_modded_dev/_cim_illusion_apply_presentation" then
                    local bind = module.bind
                    module.bind = function(...)
                        local capsule = bind(...)
                        local state = capsule.install_forge_state
                        capsule.install_forge_state = function() if duplicate then state(); state() end end
                        return capsule
                    end
                end
            end })
            no_apply(f); last_blocked(f)
            H.equal(type(f.hooks["HeroWindowItemCustomization._update_state_craft_button"]), duplicate and "function" or "nil")
        end
    end)
    H.test("Dev Apply empty false and nil-hole actual Forge loaders stay incomplete", function()
        for _, mode in ipairs({ "empty", "false", "holes" }) do
            local f = F.installed(repo_root, { forge_loader = function()
                if mode == "false" then return false end
                if mode == "holes" then return nil, "tail", nil end
            end })
            H.equal(f.hooks["HeroWindowItemCustomization._update_state_craft_button"], nil)
            no_apply(f); H.equal(#f.errors, 1); last_blocked(f)
        end
    end)
    H.test("Dev Apply repeated failed private attempt denies new UI not prior provider revocation", function()
        local f, token = F.installed(repo_root), {}
        local provider, owner = f.mod._cim_illusion_swap_provider, f.mod._cim_illusion_apply_presentation_owner
        local enable = f.hooks["HeroWindowItemCustomization._enable_craft_button"]
        local ok, err = f.capsule.install_forge_loaded(true, function() error(token, 0) end)
        H.equal(ok, false); H.equal(err, token)
        ok, err = pcall(f.capsule.install, f.mod, owner, f.mod._cim_rt_register)
        H.equal(ok, false); H.truthy(err:find("required Forge installer incomplete", 1, true))
        H.truthy(rawequal(f.mod._cim_illusion_swap_provider, provider))
        H.truthy(rawequal(f.mod._cim_illusion_apply_presentation_owner, owner))
        H.truthy(rawequal(f.hooks["HeroWindowItemCustomization._enable_craft_button"], enable))
    end)
    local function loader_fixture(f, module, body, getter_error, override)
        local proto, vmf, errors = {}, {}, {}
        local mod = { error = function(_, ...) errors[#errors + 1] = { ... } end }
        local e = setmetatable({ VMFMod = proto, Script = { callstack = function() return "test-callstack" end },
            print = function() end, get_mod = function(id) H.equal(id, "VMF"); return vmf end,
            dofile = function(p) H.equal(p, "scripts/mods/crafting_in_modded_dev/" .. module); return body() end,
            xpcall = function(fn, handler, ...)
                local args = { n = select("#", ...), ... }
                return xpcall(function() return fn(unpack(args, 1, args.n)) end, handler)
            end,
        }, { __index = _G })
        local chunk = assert(loadstring(f.source.vmf_safe_calls, "@vmf/modules/core/safe_calls.lua"))
        setfenv(chunk, e); chunk()
        setmetatable(mod, { __index = function(_, key)
            if key == "dofile" and getter_error then error(getter_error, 0) end
            if key == "dofile" and override then return override end
            return proto[key]
        end })
        local name = module == "standard_forge" and "sf" or "is"
        local a = assert(f.entry:find("local _ok_" .. name .. ", _err_" .. name .. " = ", 1, true))
        local b = assert(f.entry:find("\nif not _ok_" .. name, a, true))
        local assignment = f.entry:sub(a, b - 1)
        local expression = assignment:sub(assert(assignment:find(" = ", 1, true)) + 3)
        local supply = assert(loadstring("return function(mod, _CIM_APPLY) return " .. expression .. " end"))()
        return function() return supply(mod, f.capsule) end, errors
    end
    H.test("Dev Apply exact full VMF and entry adapters preserve every loader tuple", function()
        local f = F.installed(repo_root)
        local modules, prefix = f.shared_modules, "scripts/mods/crafting_in_modded_dev/"
        local function pack(...) return { n = select("#", ...), ... } end
        for _, module in ipairs({ "standard_forge", "illusion_swap" }) do
            f.capsule = modules[prefix .. "_cim_illusion_apply_presentation"].bind({ hook = function() end }, modules[prefix .. "_lib_local_illusion_apply"])
            local supply, errors = loader_fixture(f, module, function() error("chunk-failure", 0) end)
            local results = pack(supply())
            H.equal(results.n, 1); H.equal(results[1], true)
            H.equal(#errors, 1); H.equal(errors[1][2], "(dofile)"); H.equal(errors[1][3], "chunk-failure")
            supply = loader_fixture(f, module, function() return nil, "tail", nil end)
            results = pack(supply()); H.equal(results.n, 4); H.equal(results[1], true)
            H.equal(results[2], nil); H.equal(results[3], "tail"); H.equal(results[4], nil)
            supply = loader_fixture(f, module, function() return false end)
            results = pack(supply()); H.equal(results.n, 2); H.equal(results[1], true); H.equal(results[2], false)
            supply = loader_fixture(f, module, function() return function(actual)
                H.equal(actual, f.capsule)
                if module == "standard_forge" then actual.install_forge_state() end
                return "installed", nil, false, "tail"
            end end)
            results = pack(supply()); H.equal(results.n, 5); H.equal(results[1], true)
            H.equal(results[2], "installed"); H.equal(results[3], nil); H.equal(results[4], false); H.equal(results[5], "tail")
        end
    end)
    H.test("Dev Apply exact entry getter method and installer errors keep raw identities", function()
        local f = F.installed(repo_root)
        local getter, method, install = {}, {}, {}
        for _, module in ipairs({ "standard_forge", "illusion_swap" }) do
            local supply = loader_fixture(f, module, function() end, getter)
            local ok, err = pcall(supply); H.equal(ok, false); H.equal(err, getter)
            supply = loader_fixture(f, module, function() end, nil, function() error(method, 0) end)
            ok, err = supply(); H.equal(ok, false); H.equal(err, method)
            supply = loader_fixture(f, module, function() return function() error(install, 0) end end)
            ok, err = supply(); H.equal(ok, false); H.equal(err, install)
        end
    end)
    H.test("Dev Apply raw host shape stays exact through successful and failed installation", function()
        local function snapshot(t)
            local row = { meta = getmetatable(t), cells = {} }
            for k, v in next, t do row.cells[k] = v end
            return row
        end
        local function unchanged(t, row)
            H.truthy(rawequal(getmetatable(t), row.meta))
            for k, v in next, row.cells do H.truthy(rawequal(rawget(t, k), v), tostring(k)) end
            for k, v in next, t do H.truthy(rawequal(rawget(row.cells, k), v), tostring(k)) end
        end
        local globals, modules = snapshot(_G), snapshot(package.loaded)
        F.installed(repo_root)
        F.installed(repo_root, { fail_hook = "HeroWindowItemCustomization._update_state_craft_button" })
        unchanged(_G, globals); unchanged(package.loaded, modules)
    end)
end
