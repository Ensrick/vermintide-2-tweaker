return function(H, repo_root)
    local root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local install = assert(loadfile(root .. "_cim_temper_runtime.lua"))()
    local install_direct_owner = assert(loadfile(root
        .. "_cim_direct_craft_owner.lua"))()
    local install_seed_owner = assert(loadfile(root
        .. "_cim_athanor_seed_owner.lua"))()
    local contract = assert(loadfile(root
        .. "_cim_synthetic_item_contract.lua"))()
    local cwv_acquisition = assert(loadfile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_acquisition.lua"))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function deep_clone(value, seen)
        if type(value) ~= "table" then return value end
        seen = seen or {}
        if seen[value] then return seen[value] end
        local copy = {}
        seen[value] = copy
        for key, child in pairs(value) do
            copy[deep_clone(key, seen)] = deep_clone(child, seen)
        end
        return copy
    end

    local token_sequence = 0
    local function ownership_token(backend_id, item_key)
        token_sequence = token_sequence + 1
        local provider = item_key:sub(1, 4) == "cwv_" and "cwv" or "vanilla"
        local payload = {
            ItemId = item_key,
            ItemInstanceId = backend_id,
            CustomData = {
                cim_acquisition_key = item_key,
                cim_provider = provider,
                rarity = "modded",
                power_level = "300",
                traits = "[]",
                properties = "{}",
            },
        }
        local record = {
            backend_id = backend_id,
            item_key = item_key,
            rarity = "modded",
            power_level = 300,
            traits = {},
            properties = {},
            provider = provider,
            _mirror_master = {},
        }
        if provider == "cwv" then payload.CustomData.cwv_key = item_key end
        return assert(contract.mirror_ownership_token(
            backend_id, item_key, "test-nonce-" .. token_sequence,
            payload, record))
    end

    local function make_mod()
        local mod = { hooks = {}, safe_hooks = {}, messages = {}, checks = {} }
        function mod:hook(_, method, fn) self.hooks[method] = fn end
        function mod:hook_safe(_, method, fn) self.safe_hooks[method] = fn end
        function mod:echo(message) self.messages[#self.messages + 1] = message end
        function mod:warning(message) self.messages[#self.messages + 1] = message end
        return mod
    end

    local function context(mod, overrides)
        overrides = overrides or {}
        return {
            mod = mod,
            is_active = overrides.is_active or function() return true end,
            contract = overrides.contract or contract,
            rt_register = overrides.rt_register or function(name, fn)
                mod.checks[name] = fn
            end,
            get_cwv_seed_identity_provider =
                overrides.get_cwv_seed_identity_provider
                or function() return nil, "mod_absent" end,
            transaction = overrides.transaction or {
                action_for = function(item)
                    return item.rarity == "default" and "craft" or "apply"
                end,
                copy_payload = function(payload) return payload end,
            },
            get_forged_record = overrides.get_forged_record
                or function() return nil end,
            get_item_master = overrides.get_item_master,
            get_raw_mirror_item = overrides.get_raw_mirror_item,
            loadout = overrides.loadout or {
                discard_item_draft = function() end,
                apply_item_draft = function() return true, true end,
                item_draft_payload = function()
                    return { properties = {}, traits = {} }
                end,
            },
            bulk_accessory_craft = { craft_all = function() return 0 end },
            craft_accessory = function() return false end,
            inject_item = overrides.inject_item or function(data, backend_id)
                return true, nil, ownership_token(backend_id, data.item_key)
            end,
            rollback_item = overrides.rollback_item or function() return true end,
            refresh_backend = overrides.refresh_backend,
            register_craft = overrides.register_craft,
            note_craft = overrides.note_craft,
            guid = overrides.guid or function() return "new-bid" end,
            print_line = overrides.print_line or function() end,
        }
    end

    local function with_globals(item, body, item_master_list)
        local old = {
            Managers = rawget(_G, "Managers"),
            Application = rawget(_G, "Application"),
            ItemMasterList = rawget(_G, "ItemMasterList"),
            Localize = rawget(_G, "Localize"),
            cjson = rawget(_G, "cjson"),
        }
        rawset(_G, "Managers", {
            backend = {
                get_interface = function() return {
                    get_item_from_id = function(...)
                        if type(item) == "function" then return item(...) end
                        return item
                    end,
                } end,
                get_backend_mirror = function() return { remove_item = function() end } end,
            },
        })
        rawset(_G, "Application", { guid = function() return "new-bid" end })
        rawset(_G, "ItemMasterList", item_master_list or {})
        rawset(_G, "Localize", function(key) return key end)
        rawset(_G, "cjson", { encode = function() return "{}" end })
        local ok, err = pcall(body)
        for key, value in pairs(old) do rawset(_G, key, value) end
        if old.Managers == nil then rawset(_G, "Managers", nil) end
        if old.Application == nil then rawset(_G, "Application", nil) end
        if old.ItemMasterList == nil then rawset(_G, "ItemMasterList", nil) end
        if old.Localize == nil then rawset(_G, "Localize", nil) end
        if old.cjson == nil then rawset(_G, "cjson", nil) end
        if not ok then error(err, 0) end
    end

    -- Load the two legacy mirror-writing entry chunks against their real
    -- production transaction owner. Engine globals stay scoped to the body so
    -- these behavioral tests cannot leak fake backend state into another suite.
    local function with_craft_surface_globals(mod, item_master_list,
            saveweapon_mod, body)
        local keys = {
            "get_mod", "ItemMasterList", "SPProfiles", "Application",
            "Managers", "printf", "WeaponProperties", "WeaponTraits",
            "BackendUtils", "HeroWindowCraftingInventory",
        }
        local saved = {}
        for _, key in ipairs(keys) do saved[key] = rawget(_G, key) end
        local old_contains = table.contains
        local guid_index, refreshes, dirties = 0, 0, 0
        local poison_mirror = {
            add_item = function() error("entrypoint bypassed canonical injector") end,
            remove_item = function() error("entrypoint used identity-blind rollback") end,
        }
        local items = {
            get_item_from_id = function(_, backend_id)
                local mapped = mod._cim_test_items_by_id
                    and mod._cim_test_items_by_id[backend_id]
                if type(mapped) == "function" then return mapped(backend_id) end
                if mapped ~= nil then return mapped end
                return { backend_id = backend_id, key = "es_sword", rarity = "modded" }
            end,
            _refresh = function() refreshes = refreshes + 1 end,
        }
        rawset(_G, "get_mod", function(name)
            if name == "SaveWeapon" then return saveweapon_mod end
            return mod
        end)
        rawset(_G, "ItemMasterList", item_master_list)
        rawset(_G, "SPProfiles", { { careers = { { name = "es_mercenary" } } } })
        rawset(_G, "Application", { guid = function()
            guid_index = guid_index + 1
            return "surface-bid-" .. guid_index
        end })
        rawset(_G, "Managers", {
            player = { local_player = function()
                return {
                    profile_index = function() return 1 end,
                    career_index = function() return 1 end,
                }
            end },
            backend = {
                get_backend_mirror = function() return poison_mirror end,
                get_interface = function(_, name)
                    if name == "crafting" then
                        return { _backend_mirror = poison_mirror }
                    end
                    return items
                end,
                dirtify_interfaces = function() dirties = dirties + 1 end,
            },
        })
        rawset(_G, "printf", function() end)
        rawset(_G, "WeaponProperties", { properties = { prop_ok = {} } })
        rawset(_G, "WeaponTraits", { traits = { trait_ok = {} } })
        rawset(_G, "BackendUtils", nil)
        rawset(_G, "HeroWindowCraftingInventory", nil)
        table.contains = function(values, needle)
            for _, value in ipairs(values or {}) do
                if value == needle then return true end
            end
            return false
        end
        local ok, err = pcall(body, {
            refreshes = function() return refreshes end,
            dirties = function() return dirties end,
        })
        table.contains = old_contains
        for _, key in ipairs(keys) do rawset(_G, key, saved[key]) end
        if not ok then error(err, 0) end
    end

    local function make_craft_surface_mod()
        local mod = make_mod()
        mod._cim_synthetic_item_contract = contract
        mod._cim_rt_register = function(name, check) mod.checks[name] = check end
        mod.settings = { forged_weapons = {} }
        function mod:get(key)
            if key == "base_power_level" then return 300 end
            return self.settings[key]
        end
        function mod:info(message, ...)
            self.messages[#self.messages + 1] = string.format(message, ...)
        end
        function mod:warning(message, ...)
            self.messages[#self.messages + 1] = string.format(message, ...)
        end
        function mod:command() end
        function mod:dofile(path)
            if path:find("_cim_direct_craft_owner", 1, true) then
                return install_direct_owner
            end
            if path:find("_cim_template_selector", 1, true) then
                return {
                    set_identity_contract = function() end,
                    set_canonical_key_resolver = function() end,
                    inject = function(items) return items end,
                }
            end
            if path:find("_cim_template_catalog", 1, true) then
                return { build = function()
                    return {}, {
                        total = 0, cwv = 0, eligible = 0, suppressed = 0,
                        rejected_providers = {},
                    }
                end }
            end
            if path:find("_cim_craft_dispatch", 1, true) then
                return assert(loadfile(root .. "_cim_craft_dispatch.lua"))()
            end
            if path:find("_cim_salvage_local_boundary", 1, true) then
                return { execute = function()
                    return { selected = 0, owned = 0, deleted = 0, foreign = 0 }
                end }
            end
            return nil
        end
        return mod
    end

    local function cwv_seed_fixture(suffix)
        local item_key = "cwv_es_dual_swords"
        local donor_key = "we_dual_wield_swords"
        local backend_id = item_key .. "_" .. suffix
        local seed_entry = {
            key = donor_key, name = donor_key,
            cwv_variant = true,
            cwv_definition = false,
            cwv_key = item_key,
            rarity = "default",
            mod_data = {
                backend_id = backend_id,
                ItemInstanceId = backend_id,
                rarity = "default",
                power_level = 5,
                traits = {},
                properties = {},
                CustomData = {
                    rarity = "default",
                    power_level = "5",
                    traits = "[]",
                    properties = "{}",
                },
            },
        }
        local live = {
            IsModItem = true,
            CreatedBy = "character_weapon_variants",
            backend_id = backend_id,
            ItemInstanceId = backend_id,
            key = donor_key,
            ItemId = donor_key,
            rarity = "default",
            power_level = 5,
            traits = {},
            properties = {},
            CustomData = {
                rarity = "default",
                power_level = "5",
                traits = "[]",
                properties = "{}",
            },
            data = seed_entry,
        }
        local master = {
            [item_key] = {
                name = donor_key,
                key = donor_key,
                cwv_variant = true,
                cwv_definition = true,
                cwv_key = item_key,
                slot_type = "melee",
                can_wield = { "es_mercenary" },
                template = "dual_wield_swords_template_1",
                item_type = "cwv_es_dual_swords",
                inventory_icon = "icon_wpn_we_sword_01_t1_dual",
            },
        }
        local protected = assert(cwv_acquisition.protect_seed_identity(
            backend_id, item_key, seed_entry, master[item_key]))
        local ledger = { [backend_id] = protected }
        local fixture = {
            item_key = item_key,
            donor_key = donor_key,
            backend_id = backend_id,
            live = live,
            selected = {
                backend_id = backend_id,
                key = donor_key,
                rarity = "default",
                data = seed_entry,
            },
            master = master,
        }
        fixture.provider = cwv_acquisition.new_seed_identity_provider({
            registered_keys = { [item_key] = master[item_key] },
            get_protected_seed_ids = function() return ledger end,
            get_item_master_list = function() return master end,
            get_backend_item = function(id)
                H.equal(id, backend_id)
                return live
            end,
        })
        return fixture
    end

    return {
        root = root,
        install = install,
        install_direct_owner = install_direct_owner,
        install_seed_owner = install_seed_owner,
        contract = contract,
        cwv_acquisition = cwv_acquisition,
        read = read,
        deep_clone = deep_clone,
        ownership_token = ownership_token,
        make_mod = make_mod,
        context = context,
        with_globals = with_globals,
        with_craft_surface_globals = with_craft_surface_globals,
        make_craft_surface_mod = make_craft_surface_mod,
        cwv_seed_fixture = cwv_seed_fixture,
    }
end
