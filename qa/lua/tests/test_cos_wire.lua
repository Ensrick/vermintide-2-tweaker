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
            _semantic_calls = {},
        }
        mock_mod._cos_send_custom_skin_hands = function(unit, item, skin, edge)
            mock_mod._semantic_calls[#mock_mod._semantic_calls + 1] = {
                unit = unit, item = item, skin = skin, edge = edge,
            }
        end
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
        H.equal(type(mock_mod._cos_wire_safe_custom_skin), "function")

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

    H.test("Cosmetics wire publishes semantic custom identity before numeric null", function()
        local mock_mod, hooks = load_wire()
        local slot = {
            skin = "ct_test_skin",
            item_data = { key = "es_test_weapon" },
        }
        local equipment = { slots = { slot_melee = slot } }
        local seen_during_vanilla
        hooks["SimpleInventoryExtension:game_object_initialized"](
            function(_, _, _)
                seen_during_vanilla = slot.skin
            end,
            { _equipment = equipment }, "owner-unit", 17)

        H.equal(#mock_mod._semantic_calls, 1)
        H.equal(mock_mod._semantic_calls[1].unit, "owner-unit")
        H.equal(mock_mod._semantic_calls[1].item, slot.item_data)
        H.equal(mock_mod._semantic_calls[1].skin, "ct_test_skin")
        H.equal(mock_mod._semantic_calls[1].edge, "game_object_initialized")
        H.equal(seen_during_vanilla, nil)
        H.equal(slot.skin, "ct_test_skin")
    end)

    H.test("Cosmetics resync publishes vanilla state so stale custom hands clear", function()
        local mock_mod, hooks = load_wire()
        local extension = { _unit = "respawned-unit" }
        local equipment = {
            skin = nil,
            item_data = { key = "es_test_weapon" },
        }
        local vanilla_called = false
        hooks["SimpleInventoryExtension:_spawn_resynced_loadout"](
            function()
                vanilla_called = true
            end,
            extension, equipment, false)

        H.equal(vanilla_called, true)
        H.equal(#mock_mod._semantic_calls, 1)
        H.equal(mock_mod._semantic_calls[1].unit, "respawned-unit")
        H.equal(mock_mod._semantic_calls[1].skin, nil)
        H.equal(mock_mod._semantic_calls[1].edge, "spawn_resynced_loadout")
    end)

    H.test("Cosmetics wire policy owns the GameSession custom-skin substitution", function()
        local mock_mod = load_wire()
        local safe, subbed = mock_mod._cos_wire_safe_custom_skin("ct_test_skin", "offline_test")
        H.equal(safe, "n/a")
        H.equal(subbed, true)

        local vanilla, vanilla_subbed = mock_mod._cos_wire_safe_custom_skin(
            "wh_sword_skin_01", "offline_test")
        H.equal(vanilla, "wh_sword_skin_01")
        H.equal(vanilla_subbed, false)

        -- #1159 wave 14: the fourth #421 encode surface (the GameSession sender)
        -- moved out of the entry with its CosmeticUtils.update_cosmetic_slot
        -- hook. The consumer moved; the contract did not, so follow the code.
        local base = "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        local loadout_safety = read(base .. "_cos_la_loadout_safety.lua")
        H.truthy(loadout_safety:find("mod._cos_wire_safe_custom_skin(", 1, true))
        H.truthy(loadout_safety:find(
            "mod._cos_skin_wire_surfaces.update_cosmetic_slot = true", 1, true))
        local entry = read(base .. "cosmetics_tweaker.lua")
        H.equal(entry:find("mod._cos_skin_wire_surfaces.update_cosmetic_slot = true", 1, true), nil,
            "the surface registry write travels with its hook, never duplicated in the entry")
    end)

    H.test("Cosmetics wire wrapper restores custom skin when vanilla raises", function()
        local mock_mod = load_wire()
        local custom = { skin = "ct_test_skin" }
        local ok, err = pcall(mock_mod._cos_wire_null_custom_skins, { custom }, function()
            error("synthetic vanilla encode failure")
        end, "offline_error_test")
        H.equal(ok, false)
        H.truthy(tostring(err):find("synthetic vanilla encode failure", 1, true))
        H.equal(custom.skin, "ct_test_skin")
    end)

    H.test("Cosmetics #421 diagnostic covers catalog policy sender surfaces and live slot", function()
        local diagnostics = read(
            "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_diagnostics.lua")
        H.truthy(diagnostics:find('mod:command("cos_421_diag"', 1, true))
        H.truthy(diagnostics:find("[cos:421:diag] summary", 1, true))
        for _, marker in ipairs({
            "catalog key=", "surface=", "diagnostic GameSession",
            "diagnostic rpc_add_equipment", "live slot=",
        }) do
            H.truthy(diagnostics:find(marker, 1, true))
        end
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
