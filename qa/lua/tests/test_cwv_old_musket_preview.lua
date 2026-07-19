return function(H, repo_root)
    local Musket = dofile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_preview.lua")
    local Cim = dofile(repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_forge_preview_policy.lua")

    local function registry(overrides)
        local ready = {
            ["unit:" .. Musket.UNIT_3P] = true,
            ["unit:" .. Musket.PREVIEW_PACKAGE_ALIAS] = true,
            ["package:" .. Musket.PREVIEW_PACKAGE_ALIAS] = true,
            ["material:" .. Musket.PREVIEW_MATERIAL] = true,
        }
        for _, binding in ipairs(Musket.TEXTURES) do
            ready["texture:" .. binding.texture] = true
        end
        for key, value in pairs(overrides or {}) do ready[key] = value end
        return function(kind, path) return ready[kind .. ":" .. path] == true end
    end

    H.test("CWV #474 resolves one textured Old Musket preview descriptor", function()
        local transform = { position = { 1, 2, 3 }, scale = { 1, 1, 1 } }
        local descriptor = Musket.resolve({
            backend_id = "cwv_es_musket_old_001",
            skin = Musket.SKIN_KEY,
        }, "melee", transform)
        H.equal(descriptor.item_key, Musket.ITEM_KEY)
        H.equal(descriptor.unit_3p, Musket.UNIT_3P)
        H.equal(descriptor.package, Musket.PREVIEW_PACKAGE_ALIAS)
        H.equal(descriptor.material, Musket.PREVIEW_MATERIAL)
        H.equal(#descriptor.textures, 3)
        H.equal(descriptor.transform, transform)
        H.equal(Musket.resource_mode(descriptor, registry()), "custom")
        H.equal(Cim.authored_mode(descriptor, Musket.resource_mode, registry()), "custom")
    end)

    H.test("CWV #474 recognizes CIM UUID items through the canonical cwv_key stamp", function()
        local descriptor = Musket.resolve({
            backend_id = "91dc52f9-a-cim-uuid",
            data = { cwv_key = Musket.ITEM_KEY },
        }, "ranged")
        H.truthy(descriptor)
        H.equal(descriptor.item_key, Musket.ITEM_KEY)
    end)

    H.test("CWV #484 resolves reconstructed UUID mirrors through exact CIM identity", function()
        local item = {
            ItemInstanceId = "48400000-0000-4000-8000-000000000484",
            key = "es_handgun",
            data = { key = "es_handgun" },
            CustomData = {
                cim_acquisition_key = Musket.ITEM_KEY,
                cwv_key = Musket.ITEM_KEY,
            },
        }
        local descriptor = Musket.resolve(item, "ranged")
        H.truthy(descriptor)
        H.equal(descriptor.item_key, Musket.ITEM_KEY)

        -- The shared CWV resolver can also pass the canonical identity
        -- explicitly when a preview wrapper has dropped CustomData.
        descriptor = Musket.resolve({
            ItemInstanceId = item.ItemInstanceId,
            key = "es_handgun",
        }, "melee", nil, Musket.ITEM_KEY)
        H.truthy(descriptor)
        H.equal(descriptor.mode, "melee")

        H.equal(Musket.resolve({
            ItemInstanceId = item.ItemInstanceId,
            key = "es_handgun",
        }, "ranged"), nil)
    end)

    H.test("CWV #474 falls back safely when a custom preview resource is absent", function()
        local descriptor = Musket.resolve({ key = Musket.ITEM_KEY }, "ranged")
        local can_get = registry({ ["unit:" .. Musket.UNIT_3P] = false })
        local mode, reason = Musket.resource_mode(descriptor, can_get)
        H.equal(mode, "fallback")
        H.equal(reason, "custom_unit_missing")
        H.equal(Cim.authored_mode(descriptor, Musket.resource_mode, can_get), "fallback")
    end)

    H.test("CWV #474 fails closed when neither custom nor fallback resources exist", function()
        local descriptor = Musket.resolve({ key = Musket.ITEM_KEY }, "ranged")
        local can_get = registry({
            ["unit:" .. Musket.UNIT_3P] = false,
            ["unit:" .. Musket.PREVIEW_PACKAGE_ALIAS] = false,
            ["package:" .. Musket.PREVIEW_PACKAGE_ALIAS] = false,
        })
        local mode = Musket.resource_mode(descriptor, can_get)
        H.equal(mode, nil)
        H.equal(Cim.authored_mode(descriptor, Musket.resource_mode, can_get), nil)
    end)

    H.test("CIM #481 accepts an LA shield resident in a master bundle", function()
        local shield = "units/Kruber_shield/custom_shield_3p"
        local ok, source = Cim.unit_loadable(shield, function(kind, path)
            return kind == "unit" and path == shield
        end)
        H.equal(ok, true)
        H.equal(source, "resident_unit")
    end)

    H.test("CIM preview policy preserves vanilla package controls", function()
        local vanilla = "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1_3p"
        local ok, source = Cim.unit_loadable(vanilla, function(kind, path)
            return kind == "package" and path == vanilla
        end)
        H.equal(ok, true)
        H.equal(source, "package")
        H.equal(Musket.resolve({ key = "es_handgun" }, "ranged"), nil)
    end)

    H.test("CIM authored policy is safe when CWV is missing or unsupported", function()
        H.equal(Cim.authored_mode(nil, nil, registry()), nil)
        H.equal(Cim.authored_mode({}, function() error("bad companion") end, registry()), nil)
    end)

    H.test("CIM #404 centers only ranged properties previews", function()
        local native = { -0.85, 3, 0.05 }
        local ranged = Cim.properties_preview_position("ranged", native)
        H.equal(ranged[1], 0)
        H.equal(ranged[2], 3)
        H.equal(ranged[3], 0.05)
        H.equal(native[1], -0.85)
        H.equal(Cim.properties_preview_position("melee", native), nil)
        H.equal(Cim.properties_preview_position("ranged", nil), nil)
        H.equal(Cim.properties_preview_position("ranged", {}), nil)
    end)

    H.test("CIM #404 runtime installs one active-only zoom-durable correction", function()
        local Runtime = dofile(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_forge_preview.lua")
        local hook
        local set_position
        local logged = 0
        local active = true
        local ok, reason = Runtime.install({
            mod = {
                hook = function(_, class_name, method_name, callback)
                    H.equal(class_name, "HeroWindowWeaveProperties")
                    H.equal(method_name, "_create_item_previewer")
                    H.equal(hook, nil, "runtime registered more than one hook")
                    hook = callback
                end,
            },
            policy = Cim,
            is_active = function() return active end,
            unit_api = {
                alive = function() return true end,
                world_position = function() return 10 end,
                set_local_position = function(_, _, position) set_position = position end,
            },
            vector3 = function(x, y, z) return x + y + z end,
            vector3_box = function(value) return { value = value } end,
            printf = function() logged = logged + 1 end,
        })
        H.equal(ok, true)
        H.equal(reason, nil)
        H.equal(type(hook), "function")

        local previewer = hook(function()
            return { _spawn_position = { -0.85, 3, 0.05 }, _link_unit = {} }
        end, {}, {}, { data = { key = "es_longbow", slot_type = "ranged" } })
        H.equal(previewer._spawn_position[1], 0)
        H.equal(set_position, 10.85)
        H.equal(previewer._unit_start_position_boxed.value, 10.85)
        H.equal(logged, 1)

        active = false
        set_position = nil
        hook(function()
            return { _spawn_position = { -0.85, 3, 0 }, _link_unit = {} }
        end, {}, {}, { data = { key = "es_longbow", slot_type = "ranged" } })
        H.equal(set_position, nil)

        H.equal(Runtime.install({}), false)
    end)

    H.test("CIM #404 production correction is construction-only and zoom durable", function()
        local root = repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
        local entry_file = assert(io.open(root .. "crafting_in_modded_dev.lua", "rb"))
        local entry = entry_file:read("*a")
        entry_file:close()
        local runtime_file = assert(io.open(root .. "_cim_forge_preview.lua", "rb"))
        local runtime = runtime_file:read("*a")
        runtime_file:close()
        H.truthy(entry:find('mod:dofile(\n    "scripts/mods/crafting_in_modded_dev/_cim_forge_preview")', 1, true))
        H.truthy(entry:find("_FORGE_PREVIEW.install_runtime(", 1, true))
        H.truthy(runtime:find('deps.mod:hook("HeroWindowWeaveProperties", "_create_item_previewer"', 1, true))
        H.truthy(runtime:find("deps.policy.properties_preview_position", 1, true))
        H.truthy(runtime:find("previewer._unit_start_position_boxed = deps.vector3_box(adjusted)", 1, true))
        H.truthy(runtime:find("if not deps.is_active() or not previewer then return previewer end", 1, true))
    end)

    H.test("CWV #474 installs Old Musket in the generic preview lease bridge", function()
        local path = repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("{ _om.greataxe, _om.crowbill_family, _om.old_musket_preview, _om.profile_package_wire }", 1, true))
        H.truthy(source:find("_om._old_musket_preview_descriptor(item)", 1, true))
        H.truthy(source:find("_om._apply_old_musket_transform(unit, \"3p\", preview_mode)", 1, true))
    end)
end
