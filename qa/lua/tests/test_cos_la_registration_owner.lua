-- Transactional Loremaster's Armoury registration coverage (#428/#2).
return function(H, repo_root)
    local owner_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_registration_owner.lua"
    local lookup_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_lib_network_lookup.lua"
    local bridge_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua"

    local Owner = assert(loadfile(owner_path))()
    local Lookup = assert(loadfile(lookup_path))()

    local function copy(source)
        local result = {}
        for key, value in pairs(source or {}) do result[key] = value end
        return result
    end

    local function dense(names, strict)
        local lookup = {}
        for i = 1, #names do
            lookup[i] = names[i]
            lookup[names[i]] = i
        end
        if strict then
            setmetatable(lookup, {
                __index = function(_, key) error("strict read: " .. tostring(key)) end,
                __newindex = function(_, key) error("strict write: " .. tostring(key)) end,
            })
        end
        return lookup
    end

    local function build_fixture(options)
        options = options or {}
        local item_master_list = options.item_master_list or {
            vanilla_hat = { key = "vanilla_hat", name = "vanilla_hat", unit = "units/hat", slot_type = "hat" },
            vanilla_skin = { key = "vanilla_skin", name = "vanilla_skin", unit = "units/skin", slot_type = "skin" },
            foreign_iml = { key = "foreign_iml" },
        }
        local skin_list = options.skin_list or {
            Zeta_Armor = {
                swap_hand = "armor", kind = "unit", cosmetic_key = "vanilla_skin",
                new_units = { "units/zeta", "units/zeta_3p" },
            },
            Alpha_Hat = {
                swap_hand = "hat", kind = "unit",
                new_units = { "units/hat", "units/alpha_3p" },
            },
        }
        local network_lookup = options.network_lookup or {
            inventory_packages = dense({ "base_package" }, options.strict),
            item_names = dense({ "base_item" }, options.strict),
        }
        local backend_mod_items = { keep_backend = { marker = "backend" } }
        local new_masterlist_entries = { keep_master = true }
        local mirror = {
            _inventory_items = { keep_inventory = { marker = "inventory" } },
            _fake_inventory_items = { keep_fake = { marker = "fake" } },
            _unlocked_cosmetics = { keep_unlock = "keep_backend" },
        }
        local general = { backend_mirror_persisted = true }
        local item_interface = {
            _items = { keep_interface = { marker = "interface" } },
            _dirty = false,
        }
        local persistent = {
            backend_mod_items = backend_mod_items,
            new_masterlist_entries = new_masterlist_entries,
            backend_mirror_more_items = mirror,
            more_items_general_data = general,
        }
        local mil = {
            add_calls = 0,
            remove_calls = 0,
        }
        function mil:persistent_table(name)
            if options.missing_persistent == name then return nil end
            return persistent[name]
        end
        function mil:add_mod_items_to_local_backend(entries)
            self.add_calls = self.add_calls + 1
            if options.replace_mirror_fields then
                mirror._inventory_items = { replacement = true }
                mirror._fake_inventory_items = { replacement = true }
                mirror._unlocked_cosmetics = { replacement = true }
                item_interface._items = { replacement = true }
            end
            for i = 1, #entries do
                local entry = entries[i]
                local backend_id = entry.mod_data.backend_id
                if not (options.skip_backend_row and i == #entries) then
                    local backend_item = { backend_id = backend_id, data = entry }
                    backend_mod_items[backend_id] = backend_item
                    mirror._inventory_items[backend_id] = backend_item
                    mirror._unlocked_cosmetics[entry.name] = backend_id
                    item_interface._items[backend_id] = backend_item
                end
                item_interface._dirty = true
                if options.mil_throw_at == i then error("MIL planted failure") end
            end
        end
        function mil:remove_mod_items_from_local_backend()
            self.remove_calls = self.remove_calls + 1
            return false -- models the equipped-item refusal in upstream MIL
        end

        local bridge = {
            registered = true, -- authored Cosmetics rows may already be ready
            la_registered = false,
            localization = { authored_name = "Authored" },
            backend_to_armoury = { authored_item = "Authored_Variant" },
            backend_to_vanilla = { authored_item = "authored_base" },
            armoury_to_backend = { Authored_Variant = "authored_item" },
            unit_path_to_clones = { stale = { "stale_clone" } },
            la_offhand_options_by_weapon_type = { stale = {} },
            _la_offhand_resolution = { stale = {} },
            la_path_to_parent_package = { stale = "stale_parent" },
        }

        local function clone_entry(vanilla_key, la_key, backend_id, name_override,
                localization, iml)
            local original = rawget(iml, vanilla_key)
            if not original then return nil end
            local entry = copy(original)
            entry.key = backend_id
            entry.name = name_override or backend_id
            entry.display_name = backend_id .. "_name"
            entry.cos_la_armoury_key = la_key
            entry.cos_la_vanilla_key = vanilla_key
            entry.mod_data = {
                backend_id = backend_id,
                ItemInstanceId = backend_id,
            }
            localization[entry.display_name] = la_key .. " (LA)"
            return entry
        end

        local deps = {
            bridge = bridge,
            network_lookup_lib = Lookup,
            get_la = options.get_la or function() return { SKIN_LIST = skin_list } end,
            get_mil = options.get_mil or function() return mil end,
            get_item_master_list = options.get_item_master_list
                or function() return item_master_list end,
            get_network_lookup = options.get_network_lookup
                or function() return network_lookup end,
            get_managers = function()
                if options.missing_backend then return {} end
                local backend = { _interfaces = { items = item_interface } }
                if options.missing_item_interface then
                    backend._interfaces.items = nil
                else
                    function backend:get_interface(name)
                        if options.backend_get_error then error("backend getter") end
                        return name == "items" and item_interface or nil
                    end
                end
                return { backend = backend }
            end,
            build_unit_index = function(iml)
                local index = {}
                for key, entry in pairs(iml) do
                    if type(entry) == "table" and type(entry.unit) == "string"
                            and not index[entry.unit] then
                        index[entry.unit] = key
                    end
                end
                return index
            end,
            pick_vanilla_key = function(variant, index)
                for i = 1, #(variant.new_units or {}) do
                    local key = index[variant.new_units[i]]
                    if key then return key, variant.new_units[i] end
                end
                return nil
            end,
            build_clone_entry = clone_entry,
            plan_offhand_options = function(plan)
                plan.la_offhand_options_by_weapon_type.family = {
                    left_hand_unit = { { name = "planned" } },
                }
                plan._la_offhand_resolution.planned = { source = "fixture" }
                return true
            end,
            plan_parent_packages = function()
                return { ["units/zeta"] = "packages/zeta" }
            end,
            fault = options.fault,
        }

        local owner = Owner.new(deps)
        local function state()
            return {
                iml = copy(item_master_list),
                inventory_packages = copy(network_lookup.inventory_packages or {}),
                item_names = copy(network_lookup.item_names or {}),
                backend = copy(backend_mod_items),
                master = copy(new_masterlist_entries),
                mirror_inventory = copy(mirror._inventory_items),
                mirror_fake = copy(mirror._fake_inventory_items),
                mirror_unlock = copy(mirror._unlocked_cosmetics),
                interface_items = copy(item_interface._items),
                interface_dirty = item_interface._dirty,
                localization = copy(bridge.localization),
                backend_to_armoury = copy(bridge.backend_to_armoury),
                backend_to_vanilla = copy(bridge.backend_to_vanilla),
                armoury_to_backend = copy(bridge.armoury_to_backend),
                unit_path_to_clones = copy(bridge.unit_path_to_clones),
                options = copy(bridge.la_offhand_options_by_weapon_type),
                resolution = copy(bridge._la_offhand_resolution),
                parents = copy(bridge.la_path_to_parent_package),
                registered = bridge.registered,
                la_registered = bridge.la_registered,
            }
        end
        return {
            owner = owner,
            deps = deps,
            bridge = bridge,
            mil = mil,
            item_master_list = item_master_list,
            network_lookup = network_lookup,
            backend_mod_items = backend_mod_items,
            mirror = mirror,
            item_interface = item_interface,
            state = state,
        }
    end

    H.test("LA registration commits sorted strict lookups and readiness last", function()
        local fixture = build_fixture({ strict = true })
        local ok, reason, plan = fixture.owner.register_all()
        H.equal(ok, true)
        H.equal(reason, "registered")
        H.equal(#plan.entries, 2)
        H.equal(fixture.bridge.la_registered, true)
        H.equal(fixture.bridge.registered, true)
        H.equal(fixture.network_lookup.inventory_packages[2], "units/alpha_3p")
        H.equal(fixture.network_lookup.inventory_packages[3], "units/hat")
        H.equal(fixture.network_lookup.inventory_packages[4], "units/zeta")
        H.equal(fixture.network_lookup.inventory_packages[5], "units/zeta_3p")
        H.truthy(fixture.bridge.backend_to_armoury.authored_item,
            "authored bridge rows must survive the LA merge")
        H.equal(fixture.bridge.unit_path_to_clones.stale, nil,
            "LA-derived replacement tables must drop stale rows")
        H.truthy(fixture.item_master_list.vanilla_hat_LA_Alpha_Hat)
        H.truthy(fixture.backend_mod_items.vanilla_hat_LA_Alpha_Hat)
        H.equal(fixture.mil.remove_calls, 0)

        local second_ok, second_reason = fixture.owner.register_all()
        H.equal(second_ok, true)
        H.equal(second_reason, "already_registered")
        H.equal(fixture.mil.add_calls, 1)
    end)

    H.test("LA registration rejects sparse asymmetric and missing lookups pre-mutation", function()
        local cases = {
            function(f)
                f.network_lookup.inventory_packages = {
                    [1] = "base", base = 1, [3] = "hole", hole = 3,
                }
            end,
            function(f)
                f.network_lookup.item_names["base_item"] = 9
            end,
            function(f)
                f.network_lookup.inventory_packages = nil
            end,
        }
        for i = 1, #cases do
            local fixture = build_fixture()
            cases[i](fixture)
            fixture.deps.get_network_lookup = function()
                return fixture.network_lookup
            end
            fixture.owner = Owner.new(fixture.deps)
            local before = fixture.state()
            local ok = fixture.owner.register_all()
            H.equal(ok, false)
            H.deep_equal(fixture.state(), before)
            H.equal(fixture.mil.add_calls, 0)
        end
    end)

    H.test("LA registration rejects a foreign IML owner before MIL", function()
        local fixture = build_fixture()
        fixture.item_master_list.vanilla_hat_LA_Alpha_Hat = {
            cos_la_armoury_key = "Foreign_Hat",
            cos_la_vanilla_key = "vanilla_hat",
        }
        local before = fixture.state()
        local ok, reason = fixture.owner.register_all()
        H.equal(ok, false)
        H.truthy(reason:find("iml_conflict:", 1, true))
        H.deep_equal(fixture.state(), before)
        H.equal(fixture.mil.add_calls, 0)
    end)

    H.test("LA registration rejects foreign MIL and bridge owners before mutation", function()
        local backend_fixture = build_fixture()
        backend_fixture.backend_mod_items.vanilla_hat_LA_Alpha_Hat = {
            data = { cos_la_armoury_key = "Foreign_Hat" },
        }
        local backend_before = backend_fixture.state()
        local backend_ok, backend_reason = backend_fixture.owner.register_all()
        H.equal(backend_ok, false)
        H.truthy(backend_reason:find("mil_backend_conflict:", 1, true))
        H.deep_equal(backend_fixture.state(), backend_before)
        H.equal(backend_fixture.mil.add_calls, 0)

        local bridge_fixture = build_fixture()
        bridge_fixture.bridge.armoury_to_backend.Alpha_Hat = "foreign_item"
        local bridge_before = bridge_fixture.state()
        local bridge_ok, bridge_reason = bridge_fixture.owner.register_all()
        H.equal(bridge_ok, false)
        H.truthy(bridge_reason:find("bridge_conflict:", 1, true))
        H.deep_equal(bridge_fixture.state(), bridge_before)
        H.equal(bridge_fixture.mil.add_calls, 0)
    end)

    H.test("LA registration fails closed for missing LA MIL IML and persistent state", function()
        local cases = {
            { get_la = function() return nil end, reason = "la_missing" },
            { get_mil = function() return nil end, reason = "mil_missing" },
            { get_item_master_list = function() return nil end, reason = "iml_missing" },
            { missing_persistent = "backend_mod_items", reason = "mil_persistent_table_missing" },
            { missing_persistent = "new_masterlist_entries", reason = "mil_persistent_table_missing" },
            { missing_persistent = "backend_mirror_more_items", reason = "mil_persistent_table_missing" },
            { missing_backend = true, reason = "backend_missing" },
            { missing_item_interface = true, reason = "backend_items_missing" },
            { backend_get_error = true, reason = "backend_items_read_failed" },
        }
        for i = 1, #cases do
            local fixture = build_fixture(cases[i])
            local ok, reason = fixture.owner.register_all()
            H.equal(ok, false)
            H.equal(reason, cases[i].reason)
            H.equal(fixture.mil.add_calls, 0)
        end
    end)

    H.test("LA registration rolls back a mid-batch MIL throw without remove", function()
        local fixture = build_fixture({ mil_throw_at = 2 })
        local before = fixture.state()
        local ok, reason = fixture.owner.register_all()
        H.equal(ok, false)
        H.truthy(reason:find("commit_failed:", 1, true))
        H.deep_equal(fixture.state(), before)
        H.equal(fixture.mil.remove_calls, 0,
            "rollback must not use MIL removal, which refuses equipped items")
    end)

    H.test("LA registration rolls back every commit stage and then retries cleanly", function()
        local stages = {
            "after_mil", "after_iml", "after_inventory_packages",
            "after_item_names", "after_bridge", "after_registered",
        }
        for i = 1, #stages do
            local armed = true
            local fixture = build_fixture({
                fault = function(stage)
                    if armed and stage == stages[i] then error("fault:" .. stage) end
                end,
            })
            local before = fixture.state()
            local ok = fixture.owner.register_all()
            H.equal(ok, false, stages[i])
            H.deep_equal(fixture.state(), before, stages[i] .. " rollback")
            H.equal(fixture.mil.remove_calls, 0)

            armed = false
            local retry_ok = fixture.owner.register_all()
            H.equal(retry_ok, true, stages[i] .. " retry")
            H.equal(fixture.bridge.la_registered, true)
        end
    end)

    H.test("LA registration detects silent MIL rejection and restores mirrors", function()
        local fixture = build_fixture({ skip_backend_row = true })
        local before = fixture.state()
        local ok, reason = fixture.owner.register_all()
        H.equal(ok, false)
        H.truthy(reason:find("mil_backend_row_missing:", 1, true))
        H.deep_equal(fixture.state(), before)
    end)

    H.test("LA registration restores exact mirror field identity after replacement", function()
        local fixture = build_fixture({ replace_mirror_fields = true, mil_throw_at = 1 })
        local inventory = fixture.mirror._inventory_items
        local fake = fixture.mirror._fake_inventory_items
        local unlocked = fixture.mirror._unlocked_cosmetics
        local interface_items = fixture.item_interface._items
        local before = fixture.state()
        local ok = fixture.owner.register_all()
        H.equal(ok, false)
        H.equal(fixture.mirror._inventory_items, inventory)
        H.equal(fixture.mirror._fake_inventory_items, fake)
        H.equal(fixture.mirror._unlocked_cosmetics, unlocked)
        H.equal(fixture.item_interface._items, interface_items)
        H.deep_equal(fixture.state(), before)
    end)

    H.test("LA registration plan is invariant to source insertion order", function()
        local alpha = {
            Alpha_Hat = {
                swap_hand = "hat", kind = "unit",
                new_units = { "units/hat", "units/alpha_3p" },
            },
            Zeta_Armor = {
                swap_hand = "armor", kind = "unit", cosmetic_key = "vanilla_skin",
                new_units = { "units/zeta", "units/zeta_3p" },
            },
        }
        local zeta = {}
        zeta.Zeta_Armor = alpha.Zeta_Armor
        zeta.Alpha_Hat = alpha.Alpha_Hat
        local first = build_fixture({ skin_list = alpha })
        local second = build_fixture({ skin_list = zeta })
        H.equal(first.owner.register_all(), true)
        H.equal(second.owner.register_all(), true)
        H.deep_equal(copy(first.network_lookup.inventory_packages),
            copy(second.network_lookup.inventory_packages))
        H.deep_equal(copy(first.network_lookup.item_names),
            copy(second.network_lookup.item_names))
    end)

    H.test("production LA bridge register_all executes the transactional owner", function()
        local names = {
            "get_mod", "ItemMasterList", "NetworkLookup", "Managers",
            "Application", "WeaponSkins", "printf", "rawset",
        }
        local saved = {}
        for i = 1, #names do
            local name = names[i]
            saved[name] = rawget(_G, name)
        end
        local saved_clone = table.clone

        local backend_mod_items = {}
        local persistent = {
            backend_mod_items = backend_mod_items,
            new_masterlist_entries = {},
            more_items_general_data = {},
            backend_mirror_more_items = {},
        }
        local mil = {}
        function mil:persistent_table(name) return persistent[name] end
        function mil:add_mod_items_to_local_backend(entries)
            for i = 1, #entries do
                local entry = entries[i]
                backend_mod_items[entry.mod_data.backend_id] = {
                    backend_id = entry.mod_data.backend_id,
                    data = entry,
                }
            end
        end
        local la = {
            SKIN_LIST = {
                Actual_Hat = {
                    swap_hand = "hat",
                    kind = "unit",
                    new_units = { "units/actual_hat", "units/actual_hat_3p" },
                },
            },
        }
        local la_dependency = la
        local mod = {
            _cos_network_lookup = Lookup,
            _cos_la_registration_owner_module = Owner,
        }
        function mod:info() end
        function mod:echo() end
        function mod:dofile(path)
            if path:find("_la_shield_parity", 1, true) then
                return {
                    KRUBER_SHIELD_ITEM_TYPES = {},
                    KRUBER_SHIELD_FAMILIES = {},
                    add_compatible_targets = function() return false end,
                    find_receiver_gaps = function() return {} end,
                    magic_texture_receiver = function() return nil end,
                }
            end
            if path:find("_cos_la_option_icon_policy", 1, true) then
                return {
                    new_target_option = function(fields, target)
                        local result = copy(fields)
                        result.target_item_type = target
                        return result
                    end,
                }
            end
            if path:find("_cos_la_gate_recovery", 1, true) then
                return { new = function() return {} end }
            end
            if path:find("_lib_resource_residency", 1, true) then return {} end
            error("unexpected bridge dependency: " .. tostring(path))
        end

        local ok, failure = xpcall(function()
            _G.ItemMasterList = {
                aaa_actual_hat = {
                    key = "aaa_actual_hat", name = "aaa_actual_hat",
                    unit = "units/actual_hat", slot_type = "hat",
                },
                actual_hat = {
                    key = "actual_hat", name = "actual_hat",
                    unit = "units/actual_hat", slot_type = "hat",
                },
            }
            _G.NetworkLookup = {
                inventory_packages = dense({ "base_package" }, true),
                item_names = dense({ "base_item" }, true),
            }
            _G.Managers = { backend = { _interfaces = { items = { _dirty = false } } } }
            _G.Application = nil
            _G.WeaponSkins = nil
            _G.printf = nil
            _G.get_mod = function(name)
                if name == "cosmetics_tweaker" then return mod end
                if name == "Loremasters-Armoury" then return la_dependency end
                if name == "MoreItemsLibrary" then return mil end
                return nil
            end
            table.clone = function(source) return copy(source) end

            local Bridge = assert(loadfile(bridge_path))()
            local registered, reason = Bridge.register_all()
            H.equal(registered, true)
            H.equal(reason, "registered")
            H.equal(Bridge.la_registered, true)
            H.truthy(rawget(ItemMasterList, "aaa_actual_hat_LA_Actual_Hat"),
                "lexically first IML alias must deterministically own a shared unit")
            H.truthy(rawget(backend_mod_items, "aaa_actual_hat_LA_Actual_Hat"))
            H.truthy(rawget(NetworkLookup.inventory_packages, "units/actual_hat"))
            H.truthy(rawget(NetworkLookup.inventory_packages, "units/actual_hat_3p"))
            H.truthy(rawget(NetworkLookup.item_names, "aaa_actual_hat_LA_Actual_Hat"))

            la_dependency = nil
            local gate_ready, gate_reason = Bridge.install_apply_gate()
            H.equal(gate_ready, false)
            H.equal(gate_reason, "la_missing")

            la_dependency = "malformed-la"
            gate_ready, gate_reason = Bridge.install_apply_gate()
            H.equal(gate_ready, false)
            H.equal(gate_reason, "la_missing")

            la_dependency = la
            gate_ready, gate_reason = Bridge.install_apply_gate()
            H.equal(gate_ready, false)
            H.equal(gate_reason, "la_apply_not_ready")

            local original_apply = function() return "native-apply" end
            local discarded_writes = 0
            la_dependency = setmetatable({}, {
                __index = function(_, key)
                    if key == "apply_new_skin_from_texture" then return original_apply end
                end,
                __newindex = function(_, key)
                    if key == "apply_new_skin_from_texture" then
                        discarded_writes = discarded_writes + 1
                        return
                    end
                end,
            })
            gate_ready, gate_reason = Bridge.install_apply_gate()
            H.equal(gate_ready, false)
            H.equal(gate_reason, "la_apply_not_ready")
            H.equal(discarded_writes, 0,
                "raw readiness must reject an inherited API before proxy assignment")
            H.equal(rawget(la_dependency, "apply_new_skin_from_texture"), nil)
            H.equal(Bridge._gate_installed, false)

            local throwing_proxy_writes = 0
            la_dependency = setmetatable({}, {
                __index = function(_, key)
                    if key == "apply_new_skin_from_texture" then return original_apply end
                end,
                __newindex = function()
                    throwing_proxy_writes = throwing_proxy_writes + 1
                    error("assignment proxy rejected gate")
                end,
            })
            gate_ready, gate_reason = Bridge.install_apply_gate()
            H.equal(gate_ready, false)
            H.equal(gate_reason, "la_apply_not_ready")
            H.equal(throwing_proxy_writes, 0,
                "raw readiness must not invoke an inherited assignment proxy")
            H.equal(Bridge._gate_installed, false)

            la_dependency = la
            la.apply_new_skin_from_texture = original_apply
            local builtin_rawset = rawset
            _G.rawset = function(target, key, value)
                if target == la and key == "apply_new_skin_from_texture" then
                    return target
                end
                return builtin_rawset(target, key, value)
            end
            gate_ready, gate_reason = Bridge.install_apply_gate()
            _G.rawset = builtin_rawset
            H.equal(gate_ready, false)
            H.equal(gate_reason, "la_apply_install_rejected")
            H.equal(Bridge._original_apply, nil)
            H.equal(Bridge._gate_fn, nil)
            H.equal(Bridge._gate_installed, false)
            H.equal(rawget(la, "apply_new_skin_from_texture"), original_apply)

            _G.rawset = function(target, key, value)
                if target == la and key == "apply_new_skin_from_texture" then
                    error("raw gate write rejected")
                end
                return builtin_rawset(target, key, value)
            end
            gate_ready, gate_reason = Bridge.install_apply_gate()
            _G.rawset = builtin_rawset
            H.equal(gate_ready, false)
            H.truthy(gate_reason:find("la_apply_install_failed:", 1, true))
            H.truthy(gate_reason:find("raw gate write rejected", 1, true))
            H.equal(Bridge._original_apply, nil)
            H.equal(Bridge._gate_fn, nil)
            H.equal(Bridge._gate_installed, false)
            H.equal(rawget(la, "apply_new_skin_from_texture"), original_apply)

            gate_ready, gate_reason = Bridge.install_apply_gate()
            H.equal(gate_ready, true)
            H.equal(gate_reason, "installed")
            H.equal(rawget(la, "apply_new_skin_from_texture"), Bridge._gate_fn)
            H.truthy(Bridge._gate_fn ~= original_apply)

            gate_ready, gate_reason = Bridge.install_apply_gate()
            H.equal(gate_ready, true)
            H.equal(gate_reason, "already_installed")
            Bridge.uninstall_apply_gate()
            H.equal(la.apply_new_skin_from_texture, original_apply)
        end, debug.traceback)

        for i = 1, #names do rawset(_G, names[i], saved[names[i]]) end
        table.clone = saved_clone
        if not ok then error(failure, 0) end
    end)

    H.test("production LA bridge delegates the real registration boundary", function()
        local source = assert(io.open(bridge_path, "rb")):read("*a")
        H.truthy(source:find("REGISTRATION_OWNER.new({", 1, true))
        H.truthy(source:find("plan_offhand_options = plan_offhand_options", 1, true))
        H.equal(source:find("local idx = #NetworkLookup.item_names + 1", 1, true), nil)
        H.equal(source:find("M.pre_register_la_inventory_packages()", 1, true), nil)
    end)
end
