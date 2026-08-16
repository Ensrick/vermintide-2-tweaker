return function(H, repo_root)
    local Musket = dofile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_preview.lua")
    local Cim = dofile(repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_forge_preview_policy.lua")
    local Bridge = dofile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_package_bridge.lua")

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

    local function descriptor_for(item, mode, canonical_key)
        if not Musket.matches_item(item, canonical_key) then return nil end
        return {
            item_key = Musket.ITEM_KEY,
            mode = mode == "melee" and "melee" or "ranged",
            right_hand_unit = {
                unit = Musket.UNIT,
                unit_3p = Musket.UNIT_3P,
                package = Musket.PREVIEW_PACKAGE_ALIAS,
            },
            fallback = { right_hand_unit = {
                unit_3p = Musket.PREVIEW_PACKAGE_ALIAS,
            } },
            materials = { preview = Musket.PREVIEW_MATERIAL },
            textures = Musket.TEXTURES,
        }
    end

    H.test("CWV #474 resolves one textured Old Musket preview descriptor", function()
        local descriptor = descriptor_for({
            backend_id = "cwv_es_musket_old_001",
            skin = Musket.SKIN_KEY,
        }, "melee")
        H.equal(descriptor.item_key, Musket.ITEM_KEY)
        H.equal(descriptor.right_hand_unit.unit_3p, Musket.UNIT_3P)
        H.equal(descriptor.right_hand_unit.package, Musket.PREVIEW_PACKAGE_ALIAS)
        H.equal(descriptor.materials.preview, Musket.PREVIEW_MATERIAL)
        H.equal(#descriptor.textures, 3)
        H.equal(Musket.resource_mode(descriptor, registry()), "custom")
        H.equal(Cim.authored_mode(descriptor, Musket.resource_mode, registry()), "custom")
    end)

    H.test("CWV #474 bridges custom package lifecycle to the material owner", function()
        local bridge = Bridge.new(Musket)
        local calls = {}
        local callback = function() calls.callback = true end
        local manager = {}
        local function next_call(self, package_name, reference_name, passed_callback,
                asynchronous, prioritize)
            calls.self = self
            calls.package_name = package_name
            calls.reference_name = reference_name
            calls.passed_callback = passed_callback
            calls.asynchronous = asynchronous
            calls.prioritize = prioritize
            return "forwarded", false
        end

        local first, second = bridge.load(next_call, manager, Musket.UNIT_3P,
            "LootItemUnitPreviewer", callback, true, true)
        H.equal(first, "forwarded")
        H.equal(second, false)
        H.equal(calls.self, manager)
        H.equal(calls.package_name, Musket.NETWORK_PACKAGE_ALIAS_3P)
        H.equal(calls.reference_name, "LootItemUnitPreviewer")
        H.equal(calls.passed_callback, callback)
        H.equal(calls.asynchronous, true)
        H.equal(calls.prioritize, true)

        calls = {}
        H.equal(bridge.unload(next_call, manager, Musket.UNIT,
            "SimpleInventoryExtension"), "forwarded")
        H.equal(calls.package_name, Musket.NETWORK_PACKAGE_ALIAS_1P)
        H.equal(calls.reference_name, "SimpleInventoryExtension")

        calls = {}
        H.equal(bridge.has_loaded(next_call, manager, Musket.UNIT_3P,
            "HeroPreviewer"), "forwarded")
        H.equal(calls.package_name, Musket.NETWORK_PACKAGE_ALIAS_3P)
        H.equal(calls.reference_name, "HeroPreviewer")
        H.equal(bridge.has_pair(Musket.UNIT), true)
    end)

    H.test("CWV #474 package bridge leaves unrelated packages byte-for-byte unchanged", function()
        local bridge = Bridge.new(Musket)
        local vanilla = "units/weapons/player/wpn_empire_sword_t1/wpn_empire_sword_t1"
        local seen
        local function next_call(_, package_name) seen = package_name return 19 end
        H.equal(bridge.load(next_call, {}, vanilla, "ref", nil, false, false), 19)
        H.equal(seen, vanilla)
        H.equal(bridge.alias(vanilla), nil)
        H.equal(bridge.is_custom(vanilla), false)
    end)

    H.test("CWV #474 recognizes CIM UUID items through the canonical cwv_key stamp", function()
        local descriptor = descriptor_for({
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
        local descriptor = descriptor_for(item, "ranged")
        H.truthy(descriptor)
        H.equal(descriptor.item_key, Musket.ITEM_KEY)

        -- The shared CWV resolver can also pass the canonical identity
        -- explicitly when a preview wrapper has dropped CustomData.
        descriptor = descriptor_for({
            ItemInstanceId = item.ItemInstanceId,
            key = "es_handgun",
        }, "melee", Musket.ITEM_KEY)
        H.truthy(descriptor)
        H.equal(descriptor.mode, "melee")

        H.equal(descriptor_for({
            ItemInstanceId = item.ItemInstanceId,
            key = "es_handgun",
        }, "ranged"), nil)
    end)

    H.test("CWV #474 falls back safely when a custom preview resource is absent", function()
        local descriptor = descriptor_for({ key = Musket.ITEM_KEY }, "ranged")
        local can_get = registry({ ["unit:" .. Musket.UNIT_3P] = false })
        local mode, reason = Musket.resource_mode(descriptor, can_get)
        H.equal(mode, "fallback")
        H.equal(reason, "custom_unit_missing")
        H.equal(Cim.authored_mode(descriptor, Musket.resource_mode, can_get), "fallback")
    end)

    H.test("CWV #474 fails closed when neither custom nor fallback resources exist", function()
        local descriptor = descriptor_for({ key = Musket.ITEM_KEY }, "ranged")
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
        H.equal(descriptor_for({ key = "es_handgun" }, "ranged"), nil)
    end)

    H.test("CIM authored policy is safe when CWV is missing or unsupported", function()
        H.equal(Cim.authored_mode(nil, nil, registry()), nil)
        H.equal(Cim.authored_mode({}, function() error("bad companion") end, registry()), nil)
    end)

    H.test("CIM #882 centers only ranged properties previews", function()
        local native = { -0.85, 3, 0.05 }
        local ranged = Cim.properties_preview_position("ranged", native)
        H.equal(ranged[1], 0)
        H.equal(ranged[2], 3)
        H.equal(ranged[3], 0.05)
        H.equal(native[1], -0.85)
        H.equal(Cim.properties_preview_position("melee", native), nil)
        H.equal(Cim.properties_preview_position("ranged", nil), nil)
        H.equal(Cim.properties_preview_position("ranged", {}), nil)

        H.equal(Cim.overview_preview_x(true, -0.8, false), 0.8)
        H.equal(Cim.overview_preview_x(true, -0.8, true), -0.8)
        H.equal(Cim.overview_preview_x(false, -0.8, false), -0.8)
        H.equal(Cim.overview_preview_x(nil, -0.8, false), -0.8)
        H.equal(Cim.overview_preview_x(true, nil, false), nil)
    end)

    H.test("CIM #882 runtime installs one active-only zoom-durable correction", function()
        local Runtime = dofile(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_forge_preview.lua")
        local hook
        local constructor_hooks = {}
        local set_position
        local logged = 0
        local active = true
        local ok, reason = Runtime.install({
            mod = {
                hook = function(_, class_name, method_name, callback)
                    H.equal(method_name, "_create_item_previewer")
                    H.equal(constructor_hooks[class_name], nil,
                        "runtime duplicated a constructor hook")
                    constructor_hooks[class_name] = callback
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
        hook = constructor_hooks.HeroWindowWeaveProperties
        H.equal(type(hook), "function")
        H.equal(type(constructor_hooks.HeroWindowWeaveForgeWeapons), "function")
        H.equal(constructor_hooks.HeroWindowWeaveForgeOverview, nil,
            "Overview is composed into the existing mission-safety hook")
        H.equal(type(Runtime.invoke_constructor), "function")

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

    H.test("CIM #882 accepts retail callable-table vector constructors", function()
        local Runtime = dofile(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_forge_preview.lua")
        local hook
        local set_position
        local Vector3 = setmetatable({}, {
            __call = function(_, x, y, z) return x + y + z end,
        })
        local Vector3Box = setmetatable({}, {
            __call = function(_, value) return { value = value } end,
        })
        local ok = Runtime.install({
            mod = { hook = function(_, _, _, callback) hook = callback end },
            policy = Cim,
            is_active = function() return true end,
            unit_api = {
                alive = function() return true end,
                world_position = function() return 10 end,
                set_local_position = function(_, _, value) set_position = value end,
            },
            vector3 = Vector3,
            vector3_box = Vector3Box,
            printf = function() end,
        })
        H.equal(ok, true)
        local previewer = hook(function()
            return { _spawn_position = { -0.85, 3, 0 }, _link_unit = {} }
        end, {}, {}, { data = { key = "es_longbow", slot_type = "ranged" } })
        H.equal(set_position, 10.85)
        H.equal(previewer._unit_start_position_boxed.value, 10.85)
    end)

    H.test("CIM #882 constructor failure leaves preview state untouched", function()
        local Runtime = dofile(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_forge_preview.lua")
        local hook
        local writes = 0
        local logged = 0
        H.equal(Runtime.install({
            mod = { hook = function(_, _, _, callback) hook = callback end },
            policy = Cim,
            is_active = function() return true end,
            unit_api = {
                alive = function() return true end,
                world_position = function() return 10 end,
                set_local_position = function() writes = writes + 1 end,
            },
            vector3 = {},
            vector3_box = function(value) return value end,
            printf = function() logged = logged + 1 end,
        }), true)
        local native = { -0.85, 3, 0 }
        local previewer = { _spawn_position = native, _link_unit = {} }
        hook(function() return previewer end, {}, {}, {
            data = { key = "es_longbow", slot_type = "ranged" },
        })
        H.equal(writes, 0)
        H.equal(previewer._spawn_position, native)
        H.equal(previewer._unit_start_position_boxed, nil)
        H.equal(logged, 1)
    end)

    H.test("CIM #882 runtime reload refreshes policy through one stable hook", function()
        local Runtime = dofile(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_forge_preview.lua")
        local hook, registrations = nil, 0
        local constructor_hooks = {}
        local mod = {
            hook = function(_, class_name, method_name, callback)
                H.equal(method_name, "_create_item_previewer")
                registrations = registrations + 1
                constructor_hooks[class_name] = callback
            end,
        }
        local set_position
        local function deps(policy)
            return {
                mod = mod,
                policy = policy,
                is_active = function() return true end,
                unit_api = {
                    alive = function() return true end,
                    world_position = function() return 10 end,
                    set_local_position = function(_, _, value)
                        set_position = value
                    end,
                },
                vector3 = function(x) return x end,
                vector3_box = function(value) return { value = value } end,
                printf = function() end,
            }
        end
        local function policy(target_x)
            return {
                properties_preview_position = function()
                    return { target_x, 3, 0 }
                end,
            }
        end

        H.equal(Runtime.install(deps(policy(1))), true)
        H.equal(Runtime.install(deps(policy(2))), true)
        H.equal(registrations, 2)
        hook = constructor_hooks.HeroWindowWeaveProperties
        local previewer = hook(function()
            return { _spawn_position = { 0, 3, 0 }, _link_unit = {} }
        end, {}, {}, { data = { key = "es_longbow", slot_type = "ranged" } })
        H.equal(set_position, 12)
        H.equal(previewer._spawn_position[1], 2)
        H.equal(previewer._unit_start_position_boxed.value, 12)
    end)

    H.test("CIM #882 production correction is construction-only and zoom durable", function()
        local root = repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
        local entry_file = assert(io.open(root .. "crafting_in_modded_dev.lua", "rb"))
        local entry = entry_file:read("*a")
        entry_file:close()
        local runtime_file = assert(io.open(root .. "_cim_forge_preview.lua", "rb"))
        local runtime = runtime_file:read("*a")
        runtime_file:close()
        local safety_file = assert(io.open(root .. "_cim_mission_forge_safety.lua", "rb"))
        local safety = safety_file:read("*a")
        safety_file:close()
        local owner_file = assert(io.open(root .. "_cim_forge_preview_owner.lua", "rb"))
        local owner = owner_file:read("*a")
        owner_file:close()
        H.truthy(entry:find('mod:dofile(\n    "scripts/mods/crafting_in_modded_dev/_cim_forge_preview")', 1, true))
        H.truthy(entry:find("scripts/mods/crafting_in_modded_dev/_cim_forge_preview_owner", 1, true))
        H.truthy(owner:find("state.preview_runtime.install_runtime(", 1, true))
        H.truthy(runtime:find('deps.mod:hook("HeroWindowWeaveProperties", "_create_item_previewer"', 1, true))
        H.truthy(runtime:find("state.properties_callback = function(func, self, viewport_widget, item, ...)", 1, true))
        H.equal(runtime:find('deps.mod:hook("HeroWindowWeaveForgeOverview", "_create_item_previewer"', 1, true), nil)
        H.truthy(safety:find('preview_runtime.invoke_constructor(mod, "overview", func, self,', 1, true))
        H.truthy(runtime:find('deps.mod:hook("HeroWindowWeaveForgeWeapons", "_create_item_previewer"', 1, true))
        H.truthy(runtime:find("current.policy.properties_preview_position", 1, true))
        H.truthy(runtime:find("previewer._unit_start_position_boxed = adjusted_box", 1, true))
        H.truthy(runtime:find("if not current.is_active() or not previewer then", 1, true))
        H.truthy(runtime:find("pcall(current.vector3, dx, dy, dz)", 1, true))
    end)

    H.test("CIM #882 overview separates by viewport role, not item slot type", function()
        local path = repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
            .. "_cim_mission_forge_safety.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("definition.content._cim882_mirrored_viewport = invert_rendering == true", 1, true))
        H.truthy(source:find("content._cim882_mirrored_viewport == true", 1, true))
        H.truthy(source:find("overview_preview_x(\n            mirrored_viewport", 1, true))
        H.equal(source:find("overview_preview_x(\n            data and data.slot_type", 1, true), nil)
        H.truthy(source:find("[cim:882] mission overview secondary preview mirrored", 1, true))
    end)

    H.test("CWV #474 pose installer covers BOTH previewer classes and consumes once", function()
        -- The keep inventory previewer is MenuWorldPreviewer, whose methods are
        -- COPIES of HeroPreviewer taken at class-definition time
        -- (foundation/scripts/util/class.lua:51-57) and whose own
        -- `_update_units_visibility` override (menu_world_previewer.lua:315)
        -- can bypass the base entry. A HeroPreviewer-only hook is the base-class
        -- trap; the installer must register the derived class alongside.
        local Pose = dofile(repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_preview_pose.lua")
        local hooks = {}
        local fake_mod = {
            hook = function(_, class_name, method_name, callback)
                H.equal(method_name, "_update_units_visibility")
                H.equal(hooks[class_name], nil,
                    "duplicate hook registration on " .. tostring(class_name))
                hooks[class_name] = callback
            end,
        }
        local events = {}
        local previous_unit = rawget(_G, "Unit")
        rawset(_G, "Unit", {
            alive = function(value) return value ~= nil end,
            animation_event = function(_, event) events[#events + 1] = event end,
        })
        local ok, err = pcall(function()
            Pose.install(fake_mod, nil, function() end, nil)
            H.truthy(hooks.HeroPreviewer, "HeroPreviewer registration missing")
            H.truthy(hooks.MenuWorldPreviewer,
                "MenuWorldPreviewer registration missing (base-class hook trap, #474)")

            local previewer = {
                character_unit = { "character" },
                _wielded_slot_type = "ranged",
                _item_info_by_slot = {
                    ranged = { name = "cwv_es_musket_old", backend_id = "bid-1" },
                },
                _equipment_units = {},
                _loading_done = false,
            }
            H.truthy(Pose.arm(previewer, {
                character_unit = previewer.character_unit,
                item_name = "cwv_es_musket_old",
                backend_id = "bid-1",
                slot_type = "ranged",
                slot_index = 2,
                stance = "ranged",
                wield_event = "wield_test_event",
            }))
            -- Simulate the keep previewer's real call shape: the derived
            -- wrapper delegates through super (menu_world_previewer.lua:320),
            -- so BOTH wrappers can observe the same _loading_done edge. The
            -- pending record must be consumed exactly once.
            hooks.MenuWorldPreviewer(function(self, dt)
                return hooks.HeroPreviewer(function(inner)
                    inner._loading_done = true
                end, self, dt)
            end, previewer, 0.016)
            H.equal(#events, 1, "pose must fire exactly once across the double delivery")
            H.equal(events[1], "wield_test_event")
            H.equal(previewer._cwv_old_musket_pose_pending, nil,
                "the pending record must be consumed")
        end)
        rawset(_G, "Unit", previous_unit)
        if not ok then error(err, 0) end
    end)

    H.test("CWV #474 installs Old Musket in the generic preview lease bridge", function()
        local path = repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("{ _om.greataxe, _om.crowbill_family, _om.old_musket_preview, _om.profile_package_wire }", 1, true))
        -- #1159: the lease registration stays in the entry, but its two preview
        -- CONSUMERS (the illusion-browser descriptor lookup and the per-unit
        -- appearance reconcile) moved verbatim into the keep/menu preview-surface
        -- owner. Read them where they now live rather than weakening the gate.
        local owner_path = repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_menu_preview_owner.lua"
        local owner_file = assert(io.open(owner_path, "rb"))
        local owner = owner_file:read("*a")
        owner_file:close()
        H.truthy(owner:find("_om._old_musket_preview_descriptor(item)", 1, true))
		H.truthy(owner:find("_om.old_musket_appearance.reconcile(unit,", 1, true))
    end)
end
