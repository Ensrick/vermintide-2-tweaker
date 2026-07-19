return function(H, repo_root)
    local function read(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function load_wire(with_cosmetic_utils)
        local hooks = {}
        local mock_mod = {
            _cos = { custom_skin_keys = { ct_test_skin = true } },
        }
        local chunk = assert(loadfile(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_wire.lua"))
        -- Match VMF dofile: no injected file-global `mod`. The returned module
        -- must receive its owner explicitly from the entry point.
        local env = { printf = function() end }
        if with_cosmetic_utils then
            env.CosmeticUtils = {
                is_weapon_slot = function(slot)
                    return slot == "slot_melee" or slot == "slot_ranged"
                end,
                get_weapon_skin_name = function(slot, optional_skin_id)
                    local weapon_skins = env.NetworkLookup.weapon_skins
                    return weapon_skins[optional_skin_id or 1]
                end,
            }
        end
        setmetatable(env, { __index = _G })
        function mock_mod:hook(target, method, wrapper)
            local target_name = target == env.CosmeticUtils and "CosmeticUtils" or tostring(target)
            hooks[target_name .. ":" .. method] = wrapper
        end
        setfenv(chunk, env)
        local wire = chunk()
        H.equal(type(wire), "table")
        H.equal(type(wire.install), "function")
        H.truthy(wire.install(mock_mod))
        return mock_mod, hooks, wire, env
    end

    H.test("Cosmetics wire module is manifest-ordered after illusion registration", function()
        local entry = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
        local illusions = assert(entry:find('mod:dofile("scripts/mods/cosmetics_tweaker/_cos_illusions")', 1, true))
        local wire = assert(entry:find('mod:dofile("scripts/mods/cosmetics_tweaker/_cos_wire")', 1, true))
        H.truthy(illusions < wire)
        H.truthy(entry:find('_cos_wire.install(mod)', wire, true))
        H.truthy(entry:find('assert(_cos_wire.install(mod) == true', wire, true))
        H.equal(entry:find('local function _wire_null_custom_skins', 1, true), nil)
    end)

    H.test("Cosmetics wire installer rejects missing dependencies", function()
        local chunk = assert(loadfile(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_wire.lua"))
        setfenv(chunk, setmetatable({}, { __index = _G }))
        local wire = chunk()
        H.equal(pcall(wire.install, {}), false)
        H.equal(pcall(wire.install, { _cos = {} }), false)
        H.equal(pcall(wire.install, { _cos = { custom_skin_keys = {} } }), false)
    end)

    H.test("Cosmetics wire module registers every rpc_add_equipment sender", function()
        local mock_mod, hooks, wire = load_wire()
        H.truthy(hooks["SimpleInventoryExtension:game_object_initialized"])
        H.truthy(hooks["SimpleInventoryExtension:_spawn_resynced_loadout"])
        H.truthy(hooks["GearUtils:hot_join_sync"])
        H.truthy(mock_mod._cos_skin_wire_surfaces.game_object_initialized)
        H.truthy(mock_mod._cos_skin_wire_surfaces.spawn_resynced_loadout)
        H.truthy(mock_mod._cos_skin_wire_surfaces.hot_join_sync)

        -- Reinstall is safe during VMF hot reload and does not stack hooks.
        H.truthy(wire.install(mock_mod))
        local count = 0
        for _ in pairs(hooks) do count = count + 1 end
        H.equal(count, 3)
    end)

    H.test("Cosmetics wire module registers session-score skin decode floor when CosmeticUtils exists", function()
        local mock_mod, hooks, wire = load_wire(true)
        H.truthy(hooks["CosmeticUtils:get_weapon_skin_name"])
        H.truthy(mock_mod._cos_skin_wire_surfaces.get_weapon_skin_name)
        H.equal(type(mock_mod._cos_wire_safe_get_weapon_skin_name), "function")

        H.truthy(wire.install(mock_mod))
        local count = 0
        for _ in pairs(hooks) do count = count + 1 end
        H.equal(count, 4)
    end)

    H.test("Cosmetics wire wrapper nulls only custom skins and restores all state", function()
        local mock_mod = load_wire()
        local custom = { skin = "ct_test_skin" }
        local vanilla = { skin = "wh_sword_skin_01" }
        local seen_custom, seen_vanilla
        local a, b, c, d = mock_mod._cos_wire_null_custom_skins(
            { custom, vanilla },
            function()
                seen_custom = custom.skin
                seen_vanilla = vanilla.skin
                return "a", "b", "c", "d"
            end,
            "offline_test"
        )
        H.equal(seen_custom, nil)
        H.equal(seen_vanilla, "wh_sword_skin_01")
        H.equal(custom.skin, "ct_test_skin")
        H.equal(vanilla.skin, "wh_sword_skin_01")
        H.equal(a, "a")
        H.equal(b, "b")
        H.equal(c, "c")
        H.equal(d, "d")
    end)

    H.test("Cosmetics receiver floor degrades unknown weapon skin index to nil", function()
        local mock_mod, hooks, wire, env = load_wire(true)
        env.NetworkLookup = {
            weapon_skins = {
                [1] = "n/a",
                [2] = "vanilla_skin",
            },
        }

        local called = false
        local result = hooks["CosmeticUtils:get_weapon_skin_name"](
            function()
                called = true
                error("strict vanilla decode should not run for an unknown id")
            end,
            "slot_melee",
            924
        )
        H.equal(result, nil)
        H.equal(called, false)

        local vanilla = hooks["CosmeticUtils:get_weapon_skin_name"](
            function(slot, optional_skin_id)
                return env.NetworkLookup.weapon_skins[optional_skin_id or 1]
            end,
            "slot_melee",
            2
        )
        H.equal(vanilla, "vanilla_skin")

        local pose = hooks["CosmeticUtils:get_weapon_skin_name"](
            function()
                return "pose-path-still-vanilla"
            end,
            "slot_pose",
            924
        )
        H.equal(pose, "pose-path-still-vanilla")
    end)
end
