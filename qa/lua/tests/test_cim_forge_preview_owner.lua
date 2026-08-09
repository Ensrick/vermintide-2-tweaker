return function(H, repo_root)
    local root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local owner_path = root .. "_cim_forge_preview_owner.lua"
    local entry_path = root .. "crafting_in_modded_dev.lua"

    local function read(path)
        local file = io.open(path, "rb")
        if not file then return nil end
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

    local function fixture(active)
        local hooks, order, logs = {}, {}, {}
        local mod = {}
        local function record(kind, class_name, method_name, callback)
            local key = class_name .. "." .. method_name
            H.equal(hooks[key], nil, "duplicate hook " .. key)
            hooks[key] = { kind = kind, callback = callback }
            order[#order + 1] = key
        end
        function mod:hook(class_name, method_name, callback)
            record("hook", class_name, method_name, callback)
        end
        function mod:hook_safe(class_name, method_name, callback)
            record("hook_safe", class_name, method_name, callback)
        end

        local policy = {
            authored_mode = function(descriptor, resource_mode, can_get)
                return resource_mode(descriptor, can_get)
            end,
            unit_loadable = function(path, can_get)
                if can_get("package", path) then return true, "package" end
                if can_get("unit", path) then return true, "resident_unit" end
                return false, "missing"
            end,
        }
        local runtime_state = {}
        local runtime = {
            install_runtime = function(target_mod, received_policy, is_active)
                H.equal(target_mod, mod)
                runtime_state.policy = received_policy
                runtime_state.is_active = is_active
                runtime_state.install_calls = (runtime_state.install_calls or 0) + 1
                if runtime_state.installed then return true, "refreshed" end
                target_mod:hook("HeroWindowWeaveProperties", "_create_item_previewer",
                    function(func, self, ...)
                        if runtime_state.is_active() then
                            return runtime_state.policy.runtime_value or "adjusted"
                        end
                        return func(self, ...)
                    end)
                runtime_state.installed = true
                return true
            end,
        }
        local resolved_mods = {}
        local function install(policy_override)
            return assert(loadfile(owner_path))()({
                mod = mod,
                is_active = function() return active.value end,
                preview_policy = policy_override or policy,
                preview_runtime = runtime,
                get_mod = function(id) return resolved_mods[id] end,
                print_line = function(...)
                    logs[#logs + 1] = { ... }
                end,
            })
        end
        return mod, hooks, order, logs, resolved_mods, install, runtime_state
    end

    local function with_preview_globals(body)
        local names = { "Application", "ItemMasterList", "WeaponSkins", "BackendUtils" }
        local saved = {}
        for _, name in ipairs(names) do saved[name] = rawget(_G, name) end
        local availability = {}
        _G.Application = {
            can_get = function(kind, path)
                return availability[kind .. ":" .. tostring(path)] == true
            end,
        }
        _G.ItemMasterList = {
            sword = { display_unit = "display_sword" },
        }
        _G.WeaponSkins = { skins = {} }
        _G.BackendUtils = {
            get_item_units = function()
                return { left_hand_unit = "held_sword" }
            end,
        }
        local ok, err = pcall(body, availability)
        for _, name in ipairs(names) do rawset(_G, name, saved[name]) end
        if not ok then error(err, 0) end
    end

    H.test("CIM forge preview owner replaces one contiguous entry boundary", function()
        local entry = assert(read(entry_path))
        local owner = assert(read(owner_path))
        H.equal(count_plain(entry,
            "scripts/mods/crafting_in_modded_dev/_cim_forge_preview_owner"), 1)
        H.equal(count_plain(entry, 'mod:hook("LootItemUnitPreviewer"'), 0)
        H.equal(count_plain(entry, 'mod:hook_safe("LootItemUnitPreviewer"'), 0)
        H.equal(count_plain(owner, 'mod:hook("LootItemUnitPreviewer"'), 3)
        H.equal(count_plain(owner, 'mod:hook_safe("LootItemUnitPreviewer"'), 1)
        H.equal(count_plain(owner, "state.preview_runtime.install_runtime("), 1)
    end)

    H.test("CIM forge preview owner preserves exact hook order and is idempotent", function()
        local active = { value = false }
        local mod, hooks, order, _, _, install, runtime_state = fixture(active)
        H.equal(install(), true)
        H.deep_equal(order, {
            "LootItemUnitPreviewer._spawn_link_unit",
            "LootItemUnitPreviewer._load_item_units",
            "HeroWindowWeaveProperties._create_item_previewer",
            "LootItemUnitPreviewer.spawn_units",
            "LootItemUnitPreviewer.update",
        })
        H.equal(hooks["LootItemUnitPreviewer.update"].kind, "hook_safe")
        H.equal(install(), false)
        H.equal(#order, 5)
        H.equal(runtime_state.install_calls, 2,
            "reload must refresh the installed preview dispatcher")
        H.equal(mod._cim_forge_preview_owner_installed, true)
        H.equal(type(mod._cim_forge_preview_unsafe), "function")
        H.equal(type(mod._cim_forge_authored_preview_mode), "function")
    end)

    H.test("CIM forge preview owner reloads a distinct placement policy without a sixth hook", function()
        local active = { value = true }
        local _, hooks, order, _, _, install = fixture(active)
        local first = {
            runtime_value = "first-policy",
            authored_mode = function() return nil, "first", false end,
            unit_loadable = function() return true, "first" end,
        }
        local second = {
            runtime_value = "second-policy",
            authored_mode = function() return nil, "second", false end,
            unit_loadable = function() return true, "second" end,
        }
        H.equal(install(first), true)
        local callback = hooks[
            "HeroWindowWeaveProperties._create_item_previewer"].callback
        H.equal(callback(function() return "native" end, {}), "first-policy")

        H.equal(install(second), false)
        H.equal(#order, 5)
        H.equal(callback(function() return "native" end, {}), "second-policy",
            "the original installed callback must consume the refreshed policy")
    end)

    H.test("CIM forge preview guard accepts package or resident unit and fails closed", function()
        with_preview_globals(function(availability)
            local active = { value = true }
            local mod, _, _, logs, resolved, install = fixture(active)
            install()
            H.equal(mod._cim_forge_preview_unsafe(nil), true)
            H.equal(mod._cim_forge_preview_unsafe({ key = "unknown" }), true)
            H.equal(#logs, 2)
            H.equal(mod._cim_forge_preview_unsafe({ key = "unknown" }), true)
            H.equal(#logs, 2, "unsafe warning must be once per item identity")

            availability["unit:display_sword"] = true
            availability["unit:held_sword_3p"] = true
            H.equal(mod._cim_forge_preview_unsafe({ key = "sword" }), false)
            availability["unit:held_sword_3p"] = false
            availability["package:held_sword_3p"] = true
            H.equal(mod._cim_forge_preview_unsafe({ key = "sword" }), false)

            resolved.character_weapon_variants = {
                _cwv_resolve_preview_descriptor = function() return { id = "authored" } end,
                _cwv_preview_descriptor = {
                    resource_mode = function() return "custom", "resident" end,
                },
            }
            local mode, reason, authored = mod._cim_forge_authored_preview_mode({}, function() end)
            H.equal(mode, "custom")
            H.equal(reason, "resident")
            H.equal(authored, true)
            H.equal(mod._cim_forge_preview_unsafe({ key = "missing_but_authored" }), false)
        end)
    end)

    H.test("CIM forge preview hooks read the active accessor at callback time", function()
        with_preview_globals(function(availability)
            local active = { value = false }
            local _, hooks, _, _, _, install = fixture(active)
            install()
            local calls = 0
            local spawn = hooks["LootItemUnitPreviewer._spawn_link_unit"].callback
            local result = spawn(function(self, item)
                calls = calls + 1
                return "native"
            end, {}, nil)
            H.equal(result, "native")
            H.equal(calls, 1)

            active.value = true
            result = spawn(function()
                calls = calls + 1
                return "unsafe-native"
            end, {}, nil)
            H.equal(result, nil)
            H.equal(calls, 1, "unsafe active preview must not reach native spawn")

            availability["unit:display_sword"] = true
            availability["unit:held_sword_3p"] = true
            result = spawn(function()
                calls = calls + 1
                return "safe-native"
            end, {}, { key = "sword" })
            H.equal(result, "safe-native")
            H.equal(calls, 2)
        end)
    end)

    local vanilla_path = "C:/Users/danjo/source/repos/Vermintide-2-Source-Code/"
        .. "scripts/ui/views/hero_view/loot_item_unit_previewer.lua"
    local vanilla = read(vanilla_path)
    H.test_if(vanilla ~= nil,
        "CIM forge preview owner targets the decompiled load-spawn-update lifecycle",
        function()
            H.truthy(vanilla:find("LootItemUnitPreviewer._load_item_units = function", 1, true))
            H.truthy(vanilla:find("self:load_package(left_unit)", 1, true))
            H.truthy(vanilla:find("LootItemUnitPreviewer._spawn_link_unit = function", 1, true))
            H.truthy(vanilla:find("World.spawn_unit(world, unit_name", 1, true))
            H.truthy(vanilla:find("LootItemUnitPreviewer.spawn_units = function", 1, true))
            H.truthy(vanilla:find("self._spawned_units = units", 1, true))
            H.truthy(vanilla:find("LootItemUnitPreviewer.update = function", 1, true))
            H.truthy(vanilla:find("if self._zoom_dirty then", 1, true))
        end,
        "optional decompiled vanilla source is unavailable")

    local properties_path = "C:/Users/danjo/source/repos/Vermintide-2-Source-Code/"
        .. "scripts/ui/views/hero_view/windows/weave_forge/"
        .. "hero_window_weave_properties.lua"
    local properties = read(properties_path)
    H.test_if(properties ~= nil,
        "CIM forge preview owner targets the decompiled properties constructor",
        function()
            H.truthy(properties:find(
                "HeroWindowWeaveProperties._create_item_previewer = function",
                1, true))
            H.truthy(properties:find("LootItemUnitPreviewer:new(item, preview_position",
                1, true))
        end,
        "optional decompiled vanilla properties source is unavailable")
end
