return function(H, repo_root)
    local root = repo_root .. "/modded_progression/scripts/mods/modded_progression/"
    local State = assert(loadfile(root .. "_mp_fresh_profile_state.lua"))()
    local Runtime = assert(loadfile(root .. "_mp_fresh_profile_runtime.lua"))()
    local CLASS = "BackendInterfaceItemPlayfab"

    local function read_source(relative)
        local file = assert(io.open(repo_root .. relative, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(value, needle)
        local total, start = 0, 1
        while true do
            local found = value:find(needle, start, true)
            if not found then return total end
            total = total + 1
            start = found + #needle
        end
    end

    local function deep_equal(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for key, value in pairs(a) do
            if not deep_equal(value, b[key]) then return false end
        end
        for key in pairs(b) do
            if a[key] == nil then return false end
        end
        return true
    end

    local function slot_types(overrides)
        local table_ = {
            slot_melee = { "melee" }, slot_ranged = { "ranged" }, slot_necklace = { "necklace" },
            slot_ring = { "ring" }, slot_trinket_1 = { "trinket" }, slot_hat = { "hat" },
            slot_skin = { "skin" }, slot_frame = { "frame" }, slot_pose = { "weapon_pose" },
        }
        for key, value in pairs(overrides or {}) do table_[key] = value end
        return table_
    end

    local function native_class()
        local class = {}
        for _, method in ipairs(Runtime.routed_methods()) do class[method] = function() end end
        class.has_item = function() end
        return class
    end

    -- A small but shape-faithful engine world: two careers, plentiful gear,
    -- default cosmetics, one magic item, one pose, one weapon skin.
    local function world()
        local all = { "es_mercenary", "dr_slayer" }
        local iml = {
            es_2h_sword = { slot_type = "melee", item_type = "melee", rarity = "plentiful", can_wield = { "es_mercenary" } },
            es_1h_sword = { slot_type = "melee", item_type = "melee", rarity = "plentiful", can_wield = { "es_mercenary" } },
            es_blunderbuss = { slot_type = "ranged", item_type = "ranged", rarity = "plentiful", can_wield = { "es_mercenary" } },
            es_magic_sword = { slot_type = "melee", item_type = "melee", rarity = "magic", can_wield = { "es_mercenary" } },
            dr_dual_wield_axes = { slot_type = "melee", item_type = "melee", rarity = "plentiful", can_wield = { "dr_slayer" } },
            dr_2h_axe = { slot_type = "melee", item_type = "melee", rarity = "plentiful", can_wield = { "dr_slayer" } },
            necklace = { slot_type = "necklace", item_type = "necklace", rarity = "plentiful", can_wield = all },
            necklace_02 = { slot_type = "necklace", item_type = "necklace", rarity = "plentiful", can_wield = all },
            ring = { slot_type = "ring", item_type = "ring", rarity = "plentiful", can_wield = all },
            trinket = { slot_type = "trinket", item_type = "trinket", rarity = "plentiful", can_wield = all },
            es_hat_0000 = { slot_type = "hat", item_type = "hat", rarity = "plentiful", can_wield = { "es_mercenary", "dr_slayer" } },
            mercenary_hat_0000 = { slot_type = "hat", item_type = "hat", rarity = "plentiful", can_wield = { "es_mercenary" } },
            slayer_hat_0000 = { slot_type = "hat", item_type = "hat", rarity = "plentiful", can_wield = { "dr_slayer" } },
            skin_es_mercenary = { slot_type = "skin", item_type = "skin", rarity = "plentiful", can_wield = { "es_mercenary" } },
            skin_dr_slayer = { slot_type = "skin", item_type = "skin", rarity = "plentiful", can_wield = { "dr_slayer" } },
            frame_0000 = { slot_type = "frame", item_type = "frame", rarity = "default", can_wield = all },
            frame_promo = { slot_type = "frame", item_type = "frame", rarity = "promo", can_wield = all },
            fancy_hat = { slot_type = "hat", item_type = "hat", rarity = "exotic", can_wield = { "es_mercenary" } },
            es_2h_sword_pose_01 = { slot_type = "weapon_pose", item_type = "weapon_pose", parent = "es_2h_sword" },
            es_2h_sword_skin_gold = { slot_type = "weapon_skin", item_type = "weapon_skin", rarity = "exotic" },
        }
        local careers = {
            es_mercenary = { playfab_name = "es_1", base_skin = "skin_es_mercenary",
                item_slot_types_by_slot_name = slot_types() },
            dr_slayer = { playfab_name = "dr_2", base_skin = "skin_dr_slayer",
                item_slot_types_by_slot_name = slot_types({ slot_ranged = { "melee", "ranged" } }) },
            empire_soldier_tutorial = { base_skin = "skin_es_mercenary" },
        }
        local globals = {
            ItemMasterList = iml,
            CareerSettings = careers,
            DeusDefaultLoadout = {
                es_mercenary = { slot_melee = "deus_es_2h_sword", slot_ranged = "deus_es_blunderbuss" },
                dr_slayer = { slot_melee = "deus_dr_dual_wield_axes", slot_ranged = "deus_dr_2h_axe" },
            },
            DeusStartingWeaponTypeMapping = {
                es_2h_sword = "deus_es_2h_sword", es_1h_sword = "deus_es_1h_sword",
                es_blunderbuss = "deus_es_blunderbuss", dr_dual_wield_axes = "deus_dr_dual_wield_axes",
                dr_2h_axe = "deus_dr_2h_axe",
            },
            MIN_POWER_LEVEL = 0,
            MIN_POWER_LEVEL_CAP = 200,
            PowerLevelFromLevelSettings = { power_level_per_level = 10, starting_power_level = 185 },
            InventorySettings = {
                MAX_NUM_CUSTOM_LOADOUTS = 3,
                bot_loadout_allowed_mechanisms = { adventure = true },
                bot_loadout_allowed_game_modes = { inn = true, adventure = true },
            },
            PlayerData = { loadout_selection = { bot_equipment = {} } },
            WeaponSkins = {
                skins = { es_2h_sword_skin_gold = {} },
                matching_weapon_skin_item_key = function() return "es_2h_sword" end,
            },
            CosmeticUtils = {
                is_cosmetic_item = function(item_type)
                    return item_type == "hat" or item_type == "skin" or item_type == "frame"
                end,
            },
            [CLASS] = native_class(),
        }
        return globals
    end

    local function harness(opts)
        opts = opts or {}
        local T = {
            globals = opts.globals or world(),
            storage = opts.storage or {},
            hooks = {},
            logs = {},
            checks = {},
            realm = true,
            setting = "fresh",
            emporium = {},
            emporium_rev = 1,
            emporium_fail = false,
            fail_set = false,
            managers = {
                state = { game_mode = { game_mode_key = function() return "inn" end } },
                mechanism = { current_mechanism_name = function() return "adventure" end },
            },
        }
        local mod = {}
        T.instance_hooks = {}
        function mod:hook(target, method, callback)
            if type(target) == "table" then
                -- VMF instance hook: a separate chain on the instance table.
                T.instance_hooks[target] = T.instance_hooks[target] or {}
                assert(T.instance_hooks[target][method] == nil, "duplicate instance hook " .. method)
                T.instance_hooks[target][method] = callback
                return
            end
            assert(T.hooks[target .. "." .. method] == nil, "duplicate hook " .. method)
            T.hooks[target .. "." .. method] = callback
        end
        function mod:get(key) return T.storage[key] end
        function mod:set(key, value)
            if T.fail_set then error("planted persistence failure") end
            T.storage[key] = State.copy(value)
        end
        T.mod = mod
        T.R = Runtime.install(mod, {
            state = State,
            rt_register = function(name, fn) T.checks[name] = fn end,
            print_log = function(fmt, ...)
                T.logs[#T.logs + 1] = string.format(fmt, ...)
            end,
            is_modded_realm = function() return T.realm end,
            starting_state = function() return T.setting end,
            global = function(name) return T.globals[name] end,
            managers = function() return T.managers end,
            emporium_inventory = function()
                if T.emporium_fail then error("planted emporium failure") end
                return T.emporium
            end,
            emporium_revision = function() return T.emporium_rev end,
        })
        function T.call(method, native, self, ...)
            local hook = assert(T.hooks[CLASS .. "." .. method], "hook missing: " .. method)
            return hook(native, self, ...)
        end
        function T.count_logs(needle)
            local total = 0
            for _, line in ipairs(T.logs) do
                if line:find(needle, 1, true) then total = total + 1 end
            end
            return total
        end
        return T
    end

    local function native_self()
        return { _backend_mirror = {
            _inventory_items = { official_sword = { ItemId = "es_1h_sword", power_level = 300 } },
            _career_data = { es_mercenary = { { slot_melee = "official_sword" } } },
            _unlocked_cosmetics = { fancy_hat = "official_hat" },
        }, _loadouts = { es_mercenary = { slot_melee = "official_sword" } } }
    end

    local function native(marker)
        return function() return marker end
    end

    local function item_key_of(view_items, backend_id)
        local item = view_items[backend_id]
        return item and item.key
    end

    H.test("MP #840 starter item power derives from the source power constants", function()
        H.equal(Runtime.starter_item_power(0, 200, 10, 185), 5)
        H.equal(Runtime.starter_item_power(0, nil, 10, 185), 0)
        H.equal(Runtime.starter_item_power(3, nil, nil, nil), 3)
        H.equal(Runtime.starter_item_power(0, 100, 10, 185), 0)
    end)

    H.test("MP #840 profile envelope resets malformed records one generation forward", function()
        local first, reason = State.normalize(nil)
        H.equal(first.generation, 1)
        H.equal(reason, "initial")
        local repaired, why = State.normalize({ schema = 1, generation = 4, slices = "bad" })
        H.equal(repaired.generation, 5)
        H.equal(why, "malformed")
        local stale = { schema = 1, generation = 2, slices = { items = { generation = 1, revision = 1,
            inventory = {}, cosmetics = {}, careers = {} } } }
        H.equal(State.items_slice(stale), nil)
        stale.slices.items.generation = 2
        H.truthy(State.items_slice(stale))
    end)

    H.test("MP #840 seed is source-derived, career-aware, and seeds once per generation", function()
        local T = harness()
        local self = native_self()
        local items = T.call("get_all_backend_items", native("native-items"), self)
        H.truthy(items ~= "native-items")
        local loadouts = T.call("get_loadout", native("native-loadout"), self)
        local merc, slayer = loadouts.es_mercenary, loadouts.dr_slayer
        H.equal(item_key_of(items, merc.slot_melee), "es_2h_sword")
        H.equal(item_key_of(items, merc.slot_ranged), "es_blunderbuss")
        H.equal(item_key_of(items, merc.slot_necklace), "necklace")
        H.equal(item_key_of(items, merc.slot_ring), "ring")
        H.equal(item_key_of(items, merc.slot_trinket_1), "trinket")
        H.equal(merc.slot_hat, "mercenary_hat_0000")
        H.equal(merc.slot_skin, "skin_es_mercenary")
        H.equal(merc.slot_frame, "frame_0000")
        H.equal(merc.slot_pose, nil)
        H.equal(item_key_of(items, slayer.slot_ranged), "dr_2h_axe")
        H.equal(item_key_of(items, slayer.slot_melee), "dr_dual_wield_axes")
        H.equal(slayer.slot_hat, "slayer_hat_0000")
        H.equal(loadouts.empire_soldier_tutorial, nil)
        H.equal(items[merc.slot_melee].power_level, 5)
        H.equal(items[merc.slot_melee].rarity, "plentiful")
        H.deep_equal(items[merc.slot_melee].properties, {})
        H.equal(items[merc.slot_melee].data, T.globals.ItemMasterList.es_2h_sword)
        H.equal(T.call("get_loadout_item_id", native("native-id"), self, "es_mercenary", "slot_hat"),
            T.call("get_backend_id_from_cosmetic_item", native("native-cos"), self, "mercenary_hat_0000"))
        H.equal(T.call("get_loadout_item_id", native("native-id"), self, "es_mercenary", "slot_melee"), merc.slot_melee)
        H.equal(T.call("sum_best_power_levels", native(999), self), 25)
        H.equal(T.call("get_default_loadouts", native("native-default"), self, "es_mercenary"), nil)

        local stored = T.storage[State.SETTING_KEY]
        H.equal(stored.generation, 1)
        H.equal(stored.slices.items.generation, 1)
        H.equal(stored.slices.items.revision, 1)
        H.equal(T.count_logs("seed generation=1"), 1)
        H.equal(T.count_logs("route state=active"), 1)

        local again = harness({ globals = T.globals, storage = T.storage })
        again.call("get_all_backend_items", native("native-items"), self)
        H.equal(again.count_logs("seed generation="), 0)
        H.equal(again.storage[State.SETTING_KEY].slices.items.revision, 1)
        H.equal(again.R.state_token(), "active")
    end)

    H.test("MP #840 every routing condition restores official reads and writes", function()
        local T = harness()
        local self = native_self()
        H.truthy(T.call("get_loadout", native("native"), self) ~= "native")
        H.equal(T.R.state_token(), "active")

        T.realm = false
        H.equal(T.call("get_loadout", native("native"), self), "native")
        H.equal(T.call("set_loadout_item", native("native-write"), self, "x", "es_mercenary", "slot_melee"), "native-write")
        H.equal(T.R.state_token(), "official:realm")
        T.realm = true
        H.truthy(T.call("get_loadout", native("native"), self) ~= "native")
        H.equal(T.R.state_token(), "active")

        T.setting = "level_35"
        H.equal(T.call("get_all_backend_items", native("native"), self), "native")
        H.equal(T.R.state_token(), "official:setting")
        T.setting = "fresh"
        H.truthy(T.call("get_all_backend_items", native("native"), self) ~= "native")
        H.equal(T.R.state_token(), "active")

        T.R.set_enabled(false)
        H.equal(T.call("get_all_backend_items", native("native"), self), "native")
        H.equal(T.R.state_token(), "official:disabled")
        T.R.set_enabled(true)

        H.truthy(T.call("get_all_backend_items", native("native"), self) ~= "native")
        H.equal(T.R.state_token(), "active")
        H.equal(T.count_logs("route state=official:realm"), 1)
        H.equal(T.count_logs("route state=official:setting"), 1)
        H.equal(T.count_logs("route state=official:disabled"), 1)
        H.equal(T.count_logs("route state=active"), 4)
        H.equal(T.count_logs("seed generation="), 1)

        local a, b, c = T.call("get_loadout_item_id", function() return 1, nil, 3 end, self, "x", "slot_melee")
        T.realm = false
        a, b, c = T.call("get_loadout_item_id", function() return 1, nil, 3 end, self, "x", "slot_melee")
        H.equal(a, 1)
        H.equal(b, nil)
        H.equal(c, 3)
    end)

    H.test("MP #840 boot-time method resolution failure fails closed with no hooks", function()
        local globals = world()
        globals[CLASS].get_loadout = nil
        local T = harness({ globals = globals })
        H.equal(T.R.resolved, false)
        H.equal(T.R.reason, "missing:get_loadout")
        H.equal(next(T.hooks), nil)
        H.equal(T.R.active(), false)
        H.equal(T.R.state_token(), "official:unresolved")
        H.equal(T.count_logs("route unresolved reason=missing:get_loadout"), 1)
        H.equal(T.storage[State.SETTING_KEY], nil)
        H.truthy(T.checks.mp840_fresh_route_methods_resolved())

        globals[CLASS] = nil
        local none = harness({ globals = globals })
        H.equal(none.R.reason, "class_missing")
        H.equal(next(none.hooks), nil)
    end)

    H.test("MP #840 writes commit to the profile and never touch the native interface", function()
        local T = harness()
        local self = native_self()
        local snapshot = State.copy(self)
        T.emporium = {
            spare_sword = { ItemId = "es_1h_sword", ItemInstanceId = "spare_sword", CustomData = { power_level = "12" } },
            magic_sword = { ItemId = "es_magic_sword", ItemInstanceId = "magic_sword" },
            fancy = { ItemId = "fancy_hat", ItemInstanceId = "fancy" },
        }
        T.emporium_rev = 2
        local native_writes = 0
        local function native_write() native_writes = native_writes + 1; return "native" end

        H.equal(T.call("set_loadout_item", native_write, self, "spare_sword", "es_mercenary", "slot_melee"), true)
        H.equal(T.call("get_loadout", native_write, self).es_mercenary.slot_melee, "spare_sword")
        H.equal(T.storage[State.SETTING_KEY].slices.items.revision, 2)
        H.equal(T.call("set_loadout_item", native_write, self, "fancy", "es_mercenary", "slot_hat"), true)
        H.equal(T.call("get_loadout", native_write, self).es_mercenary.slot_hat, "fancy_hat")
        H.equal(T.call("get_loadout_item_id", native_write, self, "es_mercenary", "slot_hat"), "fancy")
        H.equal(T.call("set_loadout_item", native_write, self, "magic_sword", "es_mercenary", "slot_melee"), false)
        H.equal(T.call("set_loadout_item", native_write, self, "nope", "es_mercenary", "slot_melee"), false)
        H.equal(T.call("set_loadout_item", native_write, self, "spare_sword", "unknown_career", "slot_melee"), false)
        H.equal(T.call("get_loadout", native_write, self).es_mercenary.slot_melee, "spare_sword")

        T.call("add_loadout", native_write, self, "es_mercenary")
        H.equal(#T.call("get_career_loadouts", native_write, self, "es_mercenary"), 2)
        H.equal(T.call("get_selected_career_loadout", native_write, self, "es_mercenary"), 2)
        H.equal(T.call("set_loadout_item", native_write, self, "spare_sword", "es_mercenary", "slot_melee", 2), true)
        local by_loadout = T.call("equipped_by_loadout", native_write, self, "spare_sword")
        H.equal(by_loadout.es_mercenary.num_loadouts, 2)
        H.equal(#T.call("is_equipped_by_any_loadout", native_write, self, "spare_sword"), 2)
        T.globals.PlayerData.loadout_selection.bot_equipment.es_mercenary = 2
        H.equal(T.call("get_bot_loadout", native_write, self).es_mercenary.slot_melee, "spare_sword")
        H.equal(T.call("get_loadout_item_id", native_write, self, "es_mercenary", "slot_melee", true), "spare_sword")
        T.call("set_loadout_index", native_write, self, "es_mercenary", 1)
        H.equal(T.call("get_selected_career_loadout", native_write, self, "es_mercenary"), 1)
        T.call("add_loadout", native_write, self, "es_mercenary")
        T.call("add_loadout", native_write, self, "es_mercenary")
        H.equal(#T.call("get_career_loadouts", native_write, self, "es_mercenary"), 3)
        T.call("delete_loadout", native_write, self, "es_mercenary", 3)
        T.call("delete_loadout", native_write, self, "es_mercenary", 2)
        T.call("delete_loadout", native_write, self, "es_mercenary", 1)
        H.equal(#T.call("get_career_loadouts", native_write, self, "es_mercenary"), 1)

        H.equal(native_writes, 0)
        H.truthy(deep_equal(self, snapshot), "native interface or mirror mutated by routed writes")
        H.equal(T.count_logs("write_rejected"), 0)
        H.equal(T.R.state_token(), "active")
        H.equal(T.checks.mp840_fresh_route_write_never_touches_native(), nil)
    end)

    H.test("MP #840 failure injection leaves official state and the profile byte-identical", function()
        local T = harness()
        local self = native_self()
        local snapshot = State.copy(self)
        T.emporium = { spare_sword = { ItemId = "es_1h_sword", ItemInstanceId = "spare_sword" } }
        T.emporium_rev = 2
        local native_calls = 0
        local function native_fn() native_calls = native_calls + 1; return "native" end
        H.truthy(T.call("get_all_backend_items", native_fn, self) ~= "native")
        local stored_before = State.copy(T.storage[State.SETTING_KEY])
        local loadout_before = T.call("get_loadout", native_fn, self)

        T.fail_set = true
        H.equal(T.call("set_loadout_item", native_fn, self, "spare_sword", "es_mercenary", "slot_melee"), false)
        T.fail_set = false
        H.truthy(deep_equal(T.storage[State.SETTING_KEY], stored_before), "persisted profile changed after a failed write")
        H.truthy(deep_equal(T.call("get_loadout", native_fn, self), loadout_before), "in-memory loadout changed after a failed write")
        H.equal(T.count_logs("write_rejected method=set_loadout_item"), 1)
        H.equal(T.R.state_token(), "active")
        H.equal(native_calls, 0)

        T.emporium_rev = 3
        T.emporium_fail = true
        H.equal(T.call("get_all_backend_items", native_fn, self), "native")
        H.equal(native_calls, 1)
        H.equal(T.R.state_token(), "official:fault")
        H.equal(T.R.faulted, "get_all_backend_items")
        H.equal(T.count_logs("route state=official:fault stage=get_all_backend_items"), 1)
        T.emporium_fail = false
        H.equal(T.call("get_loadout", native_fn, self), "native")
        H.equal(T.call("set_loadout_item", native_fn, self, "spare_sword", "es_mercenary", "slot_melee"), "native")
        H.equal(native_calls, 3)
        H.truthy(deep_equal(self, snapshot), "native state mutated across failure injection")
        H.truthy(deep_equal(T.storage[State.SETTING_KEY], stored_before), "profile changed by a faulted route")

        H.truthy(T.R.reset())
        H.equal(T.R.faulted, nil)
        H.equal(T.storage[State.SETTING_KEY].generation, 2)
        H.equal(next(T.storage[State.SETTING_KEY].slices), nil)
        H.truthy(T.call("get_all_backend_items", native_fn, self) ~= "native")
        H.equal(T.count_logs("seed generation=2"), 1)
        H.equal(T.storage[State.SETTING_KEY].slices.items.generation, 2)
    end)

    H.test("MP #840 fresh view carries durable Emporium grants instead of a mirror overlay", function()
        local T = harness()
        local self = native_self()
        T.emporium = {
            fancy = { ItemId = "fancy_hat", ItemInstanceId = "fancy" },
            pose = { ItemId = "es_2h_sword_pose_01", ItemInstanceId = "pose" },
            gold = { ItemId = "es_2h_sword_skin_gold", ItemInstanceId = "gold" },
            ghost = { ItemId = "not_an_item", ItemInstanceId = "ghost" },
        }
        T.emporium_rev = 5
        local fakes = T.call("get_all_fake_backend_items", native("native"), self)
        H.equal(fakes.fancy.key, "fancy_hat")
        H.equal(T.call("get_backend_id_from_cosmetic_item", native("native"), self, "fancy_hat"), "fancy")
        H.equal(T.call("get_unlocked_weapon_poses", native("native"), self).es_2h_sword.es_2h_sword_pose_01, "pose")
        H.equal(fakes.gold.ItemId, "es_2h_sword")
        H.equal(fakes.gold.skin, "es_2h_sword_skin_gold")
        H.equal(fakes.ghost, nil)
        H.equal(T.call("get_all_backend_items", native("native"), self).gold, fakes.gold)
        H.equal(self._backend_mirror._unlocked_cosmetics.fancy_hat, "official_hat")

        T.call("set_loadout_item", native("native"), self, "pose", "es_mercenary", "slot_pose")
        H.equal(T.call("get_loadout_item_id", native("native"), self, "es_mercenary", "slot_pose"), "pose")
        T.call("set_weapon_pose_skin", native("native"), self, "es_2h_sword", "gold")
        H.equal(T.call("get_equipped_weapon_pose_skin", native("native"), self, "es_2h_sword"), "es_2h_sword_skin_gold")
        H.equal(T.call("get_equipped_weapon_pose_skins", native("native"), self).es_2h_sword, "es_2h_sword_skin_gold")
    end)

    H.test("MP #840 seed reports unresolved slots instead of inventing items", function()
        local globals = world()
        globals.DeusDefaultLoadout = nil
        globals.CareerSettings.we_shade = { playfab_name = "we_1", base_skin = "missing_skin",
            item_slot_types_by_slot_name = slot_types() }
        -- The shared wield-by-all list (CanWieldAllItemTemplates) covers the
        -- new career; no weapon, hat, or skin does.
        local shared = globals.ItemMasterList.frame_0000.can_wield
        shared[#shared + 1] = "we_shade"
        local profile = State.new_profile(nil)
        local slice, report = State.seed_items(profile, {
            item_master_list = globals.ItemMasterList, career_settings = globals.CareerSettings,
            deus_mapping = globals.DeusStartingWeaponTypeMapping, item_power_level = 5,
        })
        H.equal(report.careers, 3)
        H.equal(report.sources.plentiful_fallback, 4)
        H.equal(report.sources.deus_default, nil)
        H.equal(report.missing, 4)
        H.equal(slice.careers.we_shade.loadouts[1].slot_melee, nil)
        H.equal(slice.careers.we_shade.loadouts[1].slot_hat, nil)
        H.equal(slice.careers.we_shade.loadouts[1].slot_skin, nil)
        H.equal(slice.inventory[State.ID_PREFIX .. "g1_we_shade_slot_necklace"].ItemId, "necklace")
        H.equal(slice.careers.we_shade.loadouts[1].slot_frame, "frame_0000")
        local items = State.hydrate(slice, { item_master_list = globals.ItemMasterList }).items
        for _, item in pairs(items) do
            H.truthy(item.rarity ~= "magic")
        end
    end)

    H.test("MP #840 production entry routes once and keeps unrouted slices visibly unavailable", function()
        local main = read_source("/modded_progression/scripts/mods/modded_progression/modded_progression.lua")
        local runtime = read_source("/modded_progression/scripts/mods/modded_progression/_mp_fresh_profile_runtime.lua")
        H.equal(count_plain(main, '_mp_fresh_profile_runtime").install(mod, {'), 1)
        H.equal(count_plain(main, 'mod:hook("BackendInterfaceItemPlayfab"'), 2)
        H.truthy(main:find('mod:hook("BackendInterfaceItemPlayfab", "has_item"', 1, true))
        H.truthy(main:find('mod:hook("BackendInterfaceItemPlayfab", "has_weapon_illusion"', 1, true))
        for _, method in ipairs(Runtime.routed_methods()) do
            H.equal(count_plain(runtime, 'mod:hook(Runtime.CLASS, "' .. method .. '"'), 1, method)
            H.equal(main:find('"' .. method .. '"', 1, true), nil, method .. " must not be hooked in the entry point")
        end
        H.equal(#Runtime.routed_methods(), #Runtime.READ_METHODS + #Runtime.LOOKUP_METHODS + #Runtime.WRITE_METHODS)
        H.equal(count_plain(runtime, "mod:hook(instance, method, wrappers[method])"), 1)
        H.truthy(main:find('mod:hook("LevelEndViewBase", "init", _with_eac_off_unless_fresh)', 1, true))
        H.truthy(main:find('mod:hook("HeroWindowItemCustomization", "_enable_craft_button", _with_eac_off_unless_fresh)', 1, true))
        H.truthy(main:find('mod:hook("HeroWindowItemCustomization", "_update_state_craft_button", _with_eac_off_unless_fresh)', 1, true))
        H.truthy(main:find('if entry_type ~= "quest" and FreshProfile.active() then', 1, true))
        H.truthy(main:find('if self._achievement_layout_type == "achievements" and FreshProfile.active() then', 1, true))
        H.truthy(main:find('return false, "fresh_routed"', 1, true))
        H.truthy(main:find("FreshProfile.reset()", 1, true))
        H.truthy(main:find("FreshProfile.tick()", 1, true))
        H.truthy(main:find("function mod.on_disabled() FreshProfile.set_enabled(false) end", 1, true))
        H.equal(count_plain(main, "mark_seeded("), 1)
        H.truthy(main:find("-- TODO step 1.b: implement", 1, true))
        H.equal(runtime:find("_backend_mirror:", 1, true), nil)
        H.equal(runtime:find("mod:echo", 1, true), nil)
        H.equal(runtime:find("mod:info", 1, true), nil)
    end)

    -- ------------------------------------------------------------
    -- #1637: spawn lookups under the route
    -- ------------------------------------------------------------
    local function seeded_ids(T, self)
        local loadouts = T.call("get_loadout", native("native-loadout"), self)
        return loadouts.es_mercenary, loadouts.dr_slayer
    end

    H.test("MP #1637 get_item_from_id answers from the Fresh view, continues the chain on a miss, delegates when inactive", function()
        local T = harness()
        local self = native_self()
        local merc = seeded_ids(T, self)
        local chain_calls = {}
        local function chain(_, backend_id)
            chain_calls[#chain_calls + 1] = backend_id
            return backend_id == "cim_template_1" and { key = "template" } or nil
        end
        local record = T.call("get_item_from_id", chain, self, merc.slot_melee)
        H.equal(record.key, "es_2h_sword")
        H.equal(record.backend_id, merc.slot_melee)
        H.equal(record.data, T.globals.ItemMasterList.es_2h_sword)
        H.equal(record.power_level, 5)
        H.deep_equal(record.properties, {})
        H.deep_equal(record.traits, {})
        H.equal(#chain_calls, 0)
        -- A native id is not in the Fresh view: the chain continues and, with
        -- its routed tail, answers nil instead of the official record.
        H.equal(T.call("get_item_from_id", chain, self, "official_sword"), nil)
        H.deep_equal(chain_calls, { "official_sword" })
        -- A sibling's synthetic id still resolves through the chain.
        H.equal(T.call("get_item_from_id", chain, self, "cim_template_1").key, "template")
        H.equal(T.call("get_item_from_id", chain, self, nil), nil)
        H.equal(T.R.state_token(), "active")

        T.setting = "level_35"
        H.equal(T.call("get_item_from_id", function() return "native-record" end, self, merc.slot_melee), "native-record")
        H.equal(T.R.state_token(), "official:setting")
        T.setting = "fresh"

        -- A handler throw latches the fault and delegates, like every route_read.
        T.emporium_rev = 9
        T.emporium_fail = true
        H.equal(T.call("get_item_from_id", function() return "native-record" end, self, merc.slot_melee), "native-record")
        H.equal(T.R.faulted, "get_item_from_id")
        H.equal(T.count_logs("route state=official:fault stage=get_item_from_id"), 1)
    end)

    H.test("MP #1637 loadout ids the Fresh view cannot resolve fall back to the seeded career default", function()
        local T = harness()
        local self = native_self()
        local merc = seeded_ids(T, self)
        local default_melee = merc.slot_melee
        H.equal(State.default_equipment_id(T.R.view(), "es_mercenary", "slot_melee"), default_melee)
        H.equal(State.default_equipment_id(T.R.view(), "es_mercenary", "slot_hat"), nil)

        -- Plant an id the view cannot resolve (a vanished Emporium grant or a
        -- corrupt record) in the persisted loadout and reload the profile.
        local stored = T.storage[State.SETTING_KEY]
        stored.slices.items.careers.es_mercenary.loadouts[1].slot_melee = "ghost_melee"
        stored.slices.items.careers.es_mercenary.loadouts[1].slot_necklace = "ghost_necklace"
        stored.slices.items.careers.dr_slayer.loadouts[1].slot_melee = "ghost_slayer"
        local again = harness({ globals = T.globals, storage = T.storage })
        H.equal(again.call("get_loadout_item_id", native("native-id"), self, "es_mercenary", "slot_melee"), default_melee)
        local record = again.call("get_item_from_id", function() return nil end, self, default_melee)
        H.equal(record.key, "es_2h_sword")
        H.equal(again.call("get_loadout_item_id", native("native-id"), self, "es_mercenary", "slot_necklace"),
            State.ID_PREFIX .. "g1_es_mercenary_slot_necklace")
        H.equal(again.count_logs("slot_fallback career=es_mercenary slot=slot_melee unresolved:ghost_melee to=" .. default_melee), 1)
        again.call("get_loadout_item_id", native("native-id"), self, "es_mercenary", "slot_melee")
        H.equal(again.count_logs("slot_fallback career=es_mercenary"), 2)
        -- Cosmetic slots and resolvable ids are untouched.
        H.equal(again.call("get_loadout_item_id", native("native-id"), self, "es_mercenary", "slot_hat"),
            again.call("get_backend_id_from_cosmetic_item", native("native-cos"), self, "mercenary_hat_0000"))
        H.equal(again.call("get_loadout_item_id", native("native-id"), self, "es_mercenary", "slot_ranged"), merc.slot_ranged)
        H.equal(again.call("get_loadout", native("native-loadout"), self).es_mercenary.slot_melee, "ghost_melee")

        -- No seeded default left (the seed row itself vanished): nil, as vanilla
        -- answers for an empty slot.
        local view = again.R.view()
        view.items[State.ID_PREFIX .. "g1_dr_slayer_slot_melee"] = nil
        local id, reason = State.loadout_item_id(view, "dr_slayer", "slot_melee", {})
        H.equal(id, nil)
        H.equal(reason, "unresolved:ghost_slayer")
        H.equal(State.loadout_item_id(view, "dr_slayer", "slot_ranged", {}), State.ID_PREFIX .. "g1_dr_slayer_slot_ranged")
    end)

    local function fake_backend(instance)
        return { backend = { _interfaces = { items = instance } } }
    end

    H.test("MP #1637 instance shadows of routed methods are joined so sibling instance hooks cannot bypass the route", function()
        local T = harness()
        local self = native_self()
        local merc = seeded_ids(T, self)
        local instance = setmetatable({ _backend_mirror = self._backend_mirror }, { __index = T.globals[CLASS] })
        T.managers.backend = fake_backend(instance).backend
        H.deep_equal(T.R.instance_shadows(instance), {})
        T.R.tick()
        H.equal(next(T.instance_hooks), nil)

        -- A sibling hooks the INSTANCE: VMF leaves a raw field whose chain
        -- ends at vanilla, bypassing every class hook.
        local vanilla_calls = 0
        rawset(instance, "get_loadout_item_id", function() vanilla_calls = vanilla_calls + 1; return "native-id" end)
        rawset(instance, "get_loadout", function() return { es_mercenary = { slot_melee = "native-id" } } end)
        rawset(instance, "set_loadout_item", function() return "native-write" end)
        H.deep_equal(T.R.instance_shadows(instance), { "get_loadout", "get_loadout_item_id", "set_loadout_item" })
        T.R.tick()
        local joined = T.instance_hooks[instance]
        H.truthy(joined.get_loadout_item_id and joined.get_loadout and joined.set_loadout_item)
        H.equal(joined.get_item_from_id, nil)
        H.equal(joined.get_all_backend_items, nil)
        H.equal(T.count_logs("instance_join methods=get_loadout,get_loadout_item_id,set_loadout_item"), 1)

        -- The joined wrapper is the class wrapper: the same decision on both paths.
        local id = joined.get_loadout_item_id(rawget(instance, "get_loadout_item_id"), instance, "es_mercenary", "slot_melee")
        H.equal(id, merc.slot_melee)
        H.equal(vanilla_calls, 0)
        local write = joined.set_loadout_item(rawget(instance, "set_loadout_item"), instance,
            merc.slot_ranged, "es_mercenary", "slot_ranged")
        H.equal(write, true)
        H.equal(T.call("get_loadout", native("native"), self).es_mercenary.slot_ranged, merc.slot_ranged)
        T.realm = false
        H.equal(joined.get_loadout_item_id(rawget(instance, "get_loadout_item_id"), instance, "es_mercenary", "slot_melee"), "native-id")
        H.equal(vanilla_calls, 1)
        T.realm = true

        -- Idempotent per (instance, method); a later shadow joins on a later tick.
        T.R.tick()
        H.equal(T.count_logs("instance_join"), 1)
        rawset(instance, "get_item_from_id", function() return "native-record" end)
        H.equal(T.checks.mp840_fresh_route_instance_shadows_joined(), "instance shadow not joined: get_item_from_id")
        T.R.tick()
        H.equal(T.checks.mp840_fresh_route_instance_shadows_joined(), nil)
        H.equal(T.count_logs("instance_join methods=get_item_from_id"), 1)
        H.equal(joined.get_item_from_id(rawget(instance, "get_item_from_id"), instance, merc.slot_melee).key, "es_2h_sword")
        H.equal(joined.get_item_from_id(rawget(instance, "get_item_from_id"), instance, "official_sword"), "native-record")

        -- A replaced interface object starts its own join; the old one is not re-hooked.
        local replacement = setmetatable({}, { __index = T.globals[CLASS] })
        rawset(replacement, "get_loadout_item_id", function() return "native-id" end)
        T.managers.backend = fake_backend(replacement).backend
        T.R.tick()
        H.truthy(T.instance_hooks[replacement].get_loadout_item_id)
        H.equal(T.instance_hooks[replacement].get_loadout, nil)
        H.equal(T.count_logs("instance_join"), 3)

        -- Unavailable backend: the check reports it instead of passing vacuously.
        T.managers.backend = nil
        H.equal(T.checks.mp840_fresh_route_instance_shadows_joined(), "items interface unavailable")
        T.R.tick()
        H.equal(T.count_logs("instance_join"), 3)

        -- An unresolved route never hooks an instance.
        local globals = world()
        globals[CLASS].get_item_from_id = nil
        local unresolved = harness({ globals = globals })
        unresolved.managers.backend = fake_backend(instance).backend
        unresolved.R.tick()
        H.equal(next(unresolved.instance_hooks), nil)
        H.equal(unresolved.R.reason, "missing:get_item_from_id")
    end)

    H.test("MP #1637 spawn lookup check proves resolution under the route and delegation when inactive", function()
        local T = harness()
        local self = native_self()
        seeded_ids(T, self)
        H.equal(T.checks.mp840_fresh_route_spawn_lookup_closed(), nil)
        H.equal(T.count_logs("seed generation="), 1, "the fixture profile must never persist or re-seed")
        H.equal(T.storage[State.SETTING_KEY].slices.items.revision, 1)

        -- Inactive: the wrappers must hand the native lookup back untouched.
        T.setting = "level_35"
        H.equal(T.checks.mp840_fresh_route_spawn_lookup_closed(), nil)
        H.equal(T.R.state_token(), "official:setting")
        T.setting = "fresh"

        -- The live view loses a playable career's melee weapon and its seeded
        -- default: the route answers nil and the check names the slot.
        H.equal(T.checks.mp840_fresh_route_spawn_lookup_closed(), nil)
        local view = T.R.view()
        view.items[State.ID_PREFIX .. "g1_es_mercenary_slot_melee"] = nil
        H.equal(T.checks.mp840_fresh_route_spawn_lookup_closed(), "live route: es_mercenary slot_melee answered no id")

        -- A playable career without a weapon in the seed is a failure, not a skip.
        local globals = world()
        globals.ItemMasterList.dr_dual_wield_axes = nil
        globals.ItemMasterList.dr_2h_axe = nil
        local broken = harness({ globals = globals })
        broken.call("get_loadout", native("native"), native_self())
        H.equal(broken.checks.mp840_fresh_route_spawn_lookup_closed(), "fixture profile: dr_slayer slot_ranged answered no id")

        -- A record missing a native field is reported by name.
        local T2 = harness()
        T2.call("get_loadout", native("native"), native_self())
        local live = T2.R.view()
        live.items[State.ID_PREFIX .. "g1_dr_slayer_slot_melee"].traits = nil
        problem = T2.checks.mp840_fresh_route_spawn_lookup_closed()
        H.equal(problem, "live route: dr_slayer slot_melee id=" .. State.ID_PREFIX .. "g1_dr_slayer_slot_melee missing traits")
        local bad_globals = world()
        bad_globals[CLASS].get_loadout = nil
        local unresolved = harness({ globals = bad_globals })
        H.equal(unresolved.checks.mp840_fresh_route_spawn_lookup_closed(), "items interface route unresolved: missing:get_loadout")
    end)

    H.test("MP #1637 starting state defaults to the official inventory until a player opts into Fresh", function()
        local main = read_source("/modded_progression/scripts/mods/modded_progression/modded_progression.lua")
        local data = read_source("/modded_progression/scripts/mods/modded_progression/modded_progression_data.lua")
        H.equal(count_plain(main, 'mod:get("starting_state") or "level_35"'), 1)
        H.equal(main:find('or "fresh"', 1, true), nil)
        H.equal(count_plain(data, 'default_value = "level_35"'), 1)
        H.equal(data:find('default_value = "fresh"', 1, true), nil)
        H.truthy(data:find('text = "start_fresh",%s+value = "fresh"'), "Fresh must stay selectable")
    end)
end
