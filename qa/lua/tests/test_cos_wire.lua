return function(H, repo_root)
    local function read(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function load_wire()
        local hooks = {}
        local mock_mod = {
            _cos = { custom_skin_keys = { ct_test_skin = true } },
        }
        function mock_mod:hook(target, method, wrapper)
            hooks[tostring(target) .. ":" .. method] = wrapper
        end

        local chunk = assert(loadfile(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_wire.lua"))
        local env = setmetatable({ mod = mock_mod, printf = function() end }, { __index = _G })
        setfenv(chunk, env)
        chunk()
        return mock_mod, hooks
    end

    H.test("Cosmetics wire module is manifest-ordered after illusion registration", function()
        local entry = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
        local illusions = assert(entry:find('mod:dofile("scripts/mods/cosmetics_tweaker/_cos_illusions")', 1, true))
        local wire = assert(entry:find('mod:dofile("scripts/mods/cosmetics_tweaker/_cos_wire")', 1, true))
        H.truthy(illusions < wire)
        H.equal(entry:find('local function _wire_null_custom_skins', 1, true), nil)
    end)

    H.test("Cosmetics wire module registers every rpc_add_equipment sender", function()
        local mock_mod, hooks = load_wire()
        H.truthy(hooks["SimpleInventoryExtension:game_object_initialized"])
        H.truthy(hooks["SimpleInventoryExtension:_spawn_resynced_loadout"])
        H.truthy(hooks["GearUtils:hot_join_sync"])
        H.truthy(mock_mod._cos_skin_wire_surfaces.game_object_initialized)
        H.truthy(mock_mod._cos_skin_wire_surfaces.spawn_resynced_loadout)
        H.truthy(mock_mod._cos_skin_wire_surfaces.hot_join_sync)
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
end
