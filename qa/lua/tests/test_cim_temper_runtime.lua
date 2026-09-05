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

    H.test("CIM #1141 runtime owns one contextual label, cancel, and commit hook", function()
        local mod = make_mod()
        install(context(mod))
        H.truthy(mod.safe_hooks._set_essence_upgrade_cost)
        H.truthy(mod.safe_hooks.on_exit)
        H.truthy(mod.hooks._upgrade_magic_level)
        local before = mod._cim_temper_runtime_state
        install(context(mod))
        H.equal(mod._cim_temper_runtime_state, before)
    end)

    H.test("CIM #1141 Weapon Select hands either protected seed band to Properties", function()
        for _, suffix in ipairs({ "000", "001" }) do
            local fixture = cwv_seed_fixture(suffix)
            local mod = make_mod()
            local injected = 0
            local temper = install(context(mod, {
                get_cwv_seed_identity_provider = function()
                    return fixture.provider
                end,
                register_craft = function() return true end,
                note_craft = function() end,
                inject_item = function(data, backend_id)
                    injected = injected + 1
                    return true, nil, ownership_token(backend_id, data.item_key)
                end,
            }))
            install_seed_owner({
                mod = mod,
                is_active = function() return true end,
                contract = contract,
                get_temper_state = function() return temper end,
                get_item_from_key = function()
                    error("CWV must not use donor-key native lookup")
                end,
                get_master = function(key) return fixture.master[key] end,
                clone = deep_clone,
                localize = function(key) return key end,
            })

            local content = {
                key = fixture.item_key,
                locked = true,
                backend_id = nil,
                button_hotspot = { is_selected = true },
            }
            local native_locked
            local window = {
                _scrollbars = { weapons = { list_widgets = {
                    { content = content },
                } } },
                _viewport_data = {
                    widget = {},
                    equip_button = { content = { button_hotspot = {} } },
                },
                _widgets_by_name = {
                    viewport_level_value = { content = {} },
                    viewport_level_title = { content = {} },
                    viewport_power_value = { content = {} },
                    viewport_power_title = { content = {} },
                    viewport_title = { content = {} },
                    viewport_sub_title = { content = {} },
                },
                _create_item_previewer = function(_, _, item)
                    H.equal(item, fixture.live)
                    return { destroy = function() end }
                end,
                _setup_weapon_stats = function(_, item)
                    H.equal(item, fixture.live)
                end,
                _selected_item_id = fixture.item_key,
            }
            window._set_presentation_locked_state = function(self, locked)
                return mod.hooks._set_presentation_locked_state(
                    function(_, native_value) native_locked = native_value end,
                    self, locked)
            end
            window._update_equip_button_status = function(self, equipable, equipped)
                return mod.hooks._update_equip_button_status(
                    function() error("custom route must not call vanilla") end,
                    self, equipable, equipped)
            end
            window._present_item = function(self, item_key, activate_spin)
                return mod.hooks._present_item(
                    function() error("custom route must not call vanilla") end,
                    self, item_key, activate_spin)
            end
            with_globals(fixture.live, function()
                mod.hooks._sync_backend_loadout(function()
                    content.locked, content.backend_id = true, nil
                end, window)
                H.equal(content.locked, false)
                H.equal(content.backend_id, fixture.backend_id)
                H.equal(window._selected_backend_id, fixture.backend_id)
                H.equal(window._viewport_data.equip_button.content
                    .button_hotspot.disable_button, false)

                mod.hooks._on_list_index_selected(
                    function() error("custom route must not call vanilla") end,
                    window, 1)
                H.equal(window._selected_backend_id, fixture.backend_id)
                H.equal(window._viewport_data.item, fixture.live)
                H.equal(window._selected_item_locked, false)
                H.equal(native_locked, false)
                H.equal(window._viewport_data.equip_button.content.title_text,
                    "CRAFT")
                H.equal(window._viewport_data.equip_button.content
                    .button_hotspot.disable_button, false)

                local properties = {
                    _career_name = "es_mercenary",
                    _params = { selected_item = window._viewport_data.item },
                    _selected_item = function(self)
                        local item = self._params.selected_item
                        return item, item and item.backend_id
                    end,
                }
                mod.hooks._upgrade_magic_level(
                    function() error("custom route must not call vanilla") end,
                    properties)
            end, fixture.master)
            H.equal(injected, 1)
        end
    end)

    H.test("CIM #1141 Weapon Select fails closed for absent throwing or tampered CWV authority", function()
        local fixture = cwv_seed_fixture("001")
        local cases = {
            {
                name = "absent",
                provider = function() return nil, "mod_absent" end,
            },
            {
                name = "throwing",
                provider = function() error("provider exploded") end,
            },
            {
                name = "tampered",
                provider = function()
                    return {
                        schema = fixture.provider.schema,
                        owner = fixture.provider.owner,
                        capability = fixture.provider.capability,
                        resolve = function(_, backend_id)
                            return fixture.provider:resolve(backend_id)
                        end,
                        sample = function(_, item_key)
                            local sample, reason = fixture.provider:sample(item_key)
                            if sample then
                                sample = deep_clone(sample)
                                sample.proof.fingerprint = "tampered-fingerprint"
                            end
                            return sample, reason
                        end,
                    }
                end,
            },
        }
        for _, case in ipairs(cases) do
            local mod = make_mod()
            local temper = install(context(mod, {
                get_cwv_seed_identity_provider = case.provider,
            }))
            install_seed_owner({
                mod = mod,
                is_active = function() return true end,
                contract = contract,
                get_temper_state = function() return temper end,
                get_item_from_key = function()
                    error("CWV must not use donor-key native lookup")
                end,
                get_master = function(key) return fixture.master[key] end,
                clone = deep_clone,
                localize = function(key) return key end,
            })

            local native_locked
            local content = {
                key = fixture.item_key,
                locked = false,
                backend_id = "stale-seed-id",
                button_hotspot = { is_selected = true },
            }
            local window = {
                _scrollbars = { weapons = { list_widgets = {
                    { content = content },
                } } },
                _viewport_data = {
                    widget = {},
                    equip_button = { content = { button_hotspot = {} } },
                },
                _widgets_by_name = {
                    viewport_level_value = { content = {} },
                    viewport_level_title = { content = {} },
                    viewport_power_value = { content = {} },
                    viewport_power_title = { content = {} },
                    viewport_title = { content = {} },
                    viewport_sub_title = { content = {} },
                },
                _selected_item_id = fixture.item_key,
                _selected_backend_id = "stale-seed-id",
                _create_item_previewer = function()
                    return { destroy = function() end }
                end,
                _setup_weapon_stats = function() end,
            }
            window._set_presentation_locked_state = function(self, locked)
                return mod.hooks._set_presentation_locked_state(
                    function(_, native_value) native_locked = native_value end,
                    self, locked)
            end
            window._update_equip_button_status = function(self, equipable, equipped)
                return mod.hooks._update_equip_button_status(
                    function() error("custom route must not call vanilla") end,
                    self, equipable, equipped)
            end
            window._present_item = function(self, item_key, activate_spin)
                return mod.hooks._present_item(
                    function() error("custom route must not call vanilla") end,
                    self, item_key, activate_spin)
            end

            with_globals(fixture.live, function()
                mod.hooks._sync_backend_loadout(function()
                    content.locked, content.backend_id = false, "stale-seed-id"
                end, window)
                H.equal(content.locked, true, case.name)
                H.equal(content.backend_id, nil, case.name)
                H.equal(window._selected_backend_id, nil, case.name)
                H.equal(window._viewport_data.equip_button.content
                    .button_hotspot.disable_button, true, case.name)

                mod.hooks._on_list_index_selected(
                    function() error("custom route must not call vanilla") end,
                    window, 1)
                H.equal(window._selected_backend_id, nil, case.name)
                H.equal(window._selected_item_locked, true, case.name)
                H.equal(native_locked, true, case.name)
                H.equal(window._viewport_data.equip_button.content.title_text,
                    "CRAFT", case.name)
                H.equal(window._viewport_data.equip_button.content
                    .button_hotspot.disable_button, true, case.name)

                local clicks = 0
                if window._selected_backend_id
                        and not window._viewport_data.equip_button.content
                            .button_hotspot.disable_button then
                    clicks = clicks + 1
                end
                H.equal(clicks, 0, case.name)
            end, fixture.master)
        end
    end)

    H.test("CIM #1141 production contains post-add refresh and exact rollback", function()
        local entry = read(root .. "crafting_in_modded_dev.lua")
        H.truthy(entry:find("Application.guid, mirror_record", 1, true))
        H.truthy(entry:find("contract.inject_and_refresh_mirror_item(",
            1, true))
        H.truthy(entry:find("mirror_record, refresh_backend", 1, true))
        local _, shared_commits = entry:gsub("commit%(weapon_data", "")
        H.equal(shared_commits, 2,
            "weapon and accessory entry paths must share token-aware commit")
        H.equal(entry:find("get_backend_mirror():remove_item(new_", 1, true),
            nil, "entry paths must not use identity-blind rollback")
        H.truthy(entry:find("already_in, bid, w, master", 1, true),
            "saved restore must prove an occupied backend identity")
        local runtime = read(root .. "_cim_temper_runtime.lua")
        H.truthy(runtime:find("state.get_item_master", 1, true))
    end)

    H.test("CIM #1141 direct craft entry paths share the guarded commit owner", function()
        local mod = make_mod()
        local validations = 0
        local owner = install_direct_owner({
            mod = mod,
            contract = {
                validate_temper_owned_instance = function(
                        item, backend_id, record, master)
                    validations = validations + 1
                    return item == "item" and backend_id == "bid"
                        and record == "record" and master == "master",
                        "identity_rejected"
                end,
            },
        })
        local ok, reason = owner.commit({}, "bid", {})
        H.equal(ok, false)
        H.equal(reason, "transaction_unavailable")

        local seen
        mod._cim_temper_runtime_state = {
            commit_craft = function(data, backend_id, evidence)
                seen = { data, backend_id, evidence }
                return true, "registered"
            end,
        }
        local data, evidence = {}, {}
        ok, reason = owner.commit(data, "bid", evidence)
        H.equal(ok, true)
        H.equal(reason, "registered")
        H.deep_equal(seen, { data, "bid", evidence })

        mod._cim_temper_runtime_state.commit_craft = function()
            error("commit exploded")
        end
        ok, reason = owner.commit({}, "bid", {})
        H.equal(ok, false)
        H.truthy(reason:find("transaction_exception:", 1, true))
        H.truthy(reason:find("commit exploded", 1, true))

        ok, reason = owner.validate_saved_occupant(
            "item", "bid", "record", "master")
        H.equal(ok, true)
        H.equal(reason, nil)
        H.equal(validations, 1)
        ok, reason = owner.validate_saved_occupant(
            "foreign", "bid", "record", "master")
        H.equal(ok, false)
        H.equal(reason, "identity_rejected")
    end)

    H.test("CIM #1141 standard forge uses canonical commit and token rollback", function()
        local mod = make_craft_surface_mod()
        local injected, registered, rollbacks, rollback_refreshes = 0, 0, 0, 0
        local payloads, evidence_seen = {}, {}
        install(context(mod, {
            inject_item = function(data, backend_id)
                injected = injected + 1
                payloads[#payloads + 1] = data
                return true, nil, ownership_token(backend_id, data.item_key),
                    function()
                        rollbacks = rollbacks + 1
                        return true
                    end
            end,
            register_craft = function(_, data)
                registered = registered + 1
                if registered == 2 then return false, "save rejected" end
                return true, data
            end,
            refresh_backend = function()
                rollback_refreshes = rollback_refreshes + 1
                return true
            end,
            note_craft = function() end,
            print_line = function(_, _, source_backend_id, raw_item_key)
                evidence_seen[#evidence_seen + 1] = {
                    source_backend_id, raw_item_key,
                }
            end,
        }))

        local master = {
            es_sword = {
                key = "es_sword", slot_type = "melee", item_type = "weapon",
                rarity = "default", can_wield = { "es_mercenary" },
            },
        }
        with_craft_surface_globals(mod, master, nil, function()
            assert(loadfile(root .. "standard_forge.lua"))()
            mod._cim_craft_via_synth({ melee = true }, "weapon")
            mod._cim_craft_via_synth({ melee = true }, "weapon")
        end)

        H.equal(injected, 2)
        H.equal(registered, 2)
        H.equal(rollbacks, 1)
        H.equal(rollback_refreshes, 1)
        H.equal(payloads[1].item_key, "es_sword")
        H.equal(payloads[1].career_name, "es_mercenary")
        H.equal(payloads[1].via_mirror, true)
        H.equal(evidence_seen[1][2], "es_sword")
        local saw_failure = false
        for _, message in ipairs(mod.messages) do
            if message:find("craft transaction FAILED", 1, true)
                    and message:find("save rejected", 1, true) then
                saw_failure = true
            end
        end
        H.truthy(saw_failure, "standard forge must surface transaction rejection")
    end)

    H.test("CIM #1141 standard forge preserves both real CWV seed bands", function()
        for _, suffix in ipairs({ "000", "001" }) do
            local fixture = cwv_seed_fixture(suffix)
            local mod = make_craft_surface_mod()
            mod._cim_test_items_by_id = {
                [fixture.backend_id] = fixture.live,
            }
            local commits, evidence = {}, {}
            install(context(mod, {
                get_cwv_seed_identity_provider = function()
                    return fixture.provider
                end,
                inject_item = function(data, backend_id)
                    commits[#commits + 1] = data.item_key
                    return true, nil, ownership_token(
                        backend_id, data.item_key)
                end,
                register_craft = function(_, data) return true, data end,
                note_craft = function() end,
                print_line = function(_, _, source_backend_id, raw_item_key)
                    evidence[#evidence + 1] = {
                        source_backend_id, raw_item_key,
                    }
                end,
            }))

            with_craft_surface_globals(mod, fixture.master, nil, function()
                assert(loadfile(root .. "standard_forge.lua"))()
                mod._cim_standard_forge_active = true
                local crafting = {
                    _last_id = 0,
                    _craft_requests = {},
                    _backend_mirror = {},
                    _get_valid_recipe = function()
                        return { name = "craft_weapon" }, {
                            fixture.backend_id,
                        }
                    end,
                }
                mod.hooks.craft(
                    function() error("custom forge must not call vanilla") end,
                    crafting, "es_mercenary", { fixture.backend_id },
                    "craft_weapon")
            end)

            H.deep_equal(commits, { fixture.item_key }, suffix)
            H.equal(evidence[1][1], fixture.backend_id, suffix)
            H.equal(evidence[1][2], fixture.donor_key, suffix)
        end
    end)

    H.test("CIM #1141 standard forge rejects unauthenticated CWV seeds", function()
        local fixture = cwv_seed_fixture("001")
        local cases = {
            {
                name = "absent",
                provider = function() return nil, "mod_absent" end,
            },
            {
                name = "tampered",
                provider = function()
                    return {
                        schema = fixture.provider.schema,
                        owner = fixture.provider.owner,
                        capability = fixture.provider.capability,
                        resolve = function(_, backend_id)
                            local proof, reason = fixture.provider:resolve(backend_id)
                            if proof then
                                proof = deep_clone(proof)
                                proof.fingerprint = "tampered"
                            end
                            return proof, reason
                        end,
                        sample = function(_, item_key)
                            return fixture.provider:sample(item_key)
                        end,
                    }
                end,
            },
        }
        for _, case in ipairs(cases) do
            local mod = make_craft_surface_mod()
            mod._cim_test_items_by_id = {
                [fixture.backend_id] = fixture.live,
            }
            local injections, persisted = 0, 0
            install(context(mod, {
                get_cwv_seed_identity_provider = case.provider,
                inject_item = function()
                    injections = injections + 1
                    return true
                end,
                register_craft = function()
                    persisted = persisted + 1
                    return true
                end,
            }))
            local unrelated = { state = "older-complete" }
            local in_flight = { state = "in-flight" }
            local crafting
            with_craft_surface_globals(mod, fixture.master, nil, function(surface)
                assert(loadfile(root .. "standard_forge.lua"))()
                mod._cim_standard_forge_active = true
                crafting = {
                    _last_id = 40,
                    _craft_requests = { [7] = unrelated, [40] = in_flight },
                    _backend_mirror = {},
                    _get_valid_recipe = function()
                        return { name = "craft_weapon" }, {
                            fixture.backend_id,
                        }
                    end,
                }
                local craft_id, completion = mod.hooks.craft(
                    function() error("custom forge must not call vanilla") end,
                    crafting, "es_mercenary", { fixture.backend_id },
                    "craft_weapon")
                H.equal(craft_id, nil, case.name)
                H.equal(completion, false, case.name)
                H.equal(crafting._last_id, 41, case.name)
                H.equal(crafting._craft_requests[41], nil,
                    case.name .. " must not publish a completed request")
                H.equal(crafting._craft_requests[7], unrelated,
                    case.name .. " must preserve unrelated requests")
                H.equal(crafting._craft_requests[40], in_flight,
                    case.name .. " must preserve the prior in-flight request")
                H.equal(surface.dirties(), 0,
                    case.name .. " must not invalidate presentation")
            end)
            H.equal(injections, 0, case.name)
            H.equal(persisted, 0, case.name)
            local rejected = false
            for _, message in ipairs(mod.messages) do
                if message:find(
                        "Cannot resolve selected CWV Blacksmith weapon", 1, true) then
                    rejected = true
                end
            end
            H.equal(rejected, true, case.name)
        end
    end)

    H.test("CIM #1141 standard forge canonical rejection is not a completed craft", function()
        local mod = make_craft_surface_mod()
        local injection_attempts, persisted, noted = 0, 0, 0
        local published_rows = {}
        mod._cim_test_items_by_id = {
            ["ordinary-seed"] = {
                backend_id = "ordinary-seed",
                key = "es_sword",
                rarity = "default",
                data = {
                    key = "es_sword", name = "es_sword",
                    slot_type = "melee", item_type = "weapon",
                    rarity = "default", can_wield = { "es_mercenary" },
                },
            },
        }
        install(context(mod, {
            inject_item = function()
                injection_attempts = injection_attempts + 1
                return nil, "canonical injection rejected"
            end,
            register_craft = function()
                persisted = persisted + 1
                return true
            end,
            note_craft = function() noted = noted + 1 end,
        }))
        local master = {
            es_sword = {
                key = "es_sword", name = "es_sword",
                slot_type = "melee", item_type = "weapon",
                rarity = "default", can_wield = { "es_mercenary" },
            },
        }
        local unrelated = { state = "older-complete" }
        local in_flight = { state = "in-flight" }
        with_craft_surface_globals(mod, master, nil, function(surface)
            assert(loadfile(root .. "standard_forge.lua"))()
            mod._cim_standard_forge_active = true
            local crafting = {
                _last_id = 90,
                _craft_requests = { [12] = unrelated, [90] = in_flight },
                _backend_mirror = published_rows,
                _get_valid_recipe = function()
                    return { name = "craft_weapon" }, {
                        "ordinary-seed",
                    }
                end,
            }
            local craft_id, completion = mod.hooks.craft(
                function() error("custom forge must not call vanilla") end,
                crafting, "es_mercenary", { "ordinary-seed" },
                "craft_weapon")
            H.equal(craft_id, nil)
            H.equal(completion, false)
            H.equal(crafting._last_id, 91)
            H.equal(crafting._craft_requests[91], nil,
                "rejected transaction must not look complete")
            H.equal(crafting._craft_requests[12], unrelated,
                "rejection must preserve unrelated requests")
            H.equal(crafting._craft_requests[90], in_flight,
                "rejection must preserve the prior in-flight request")
            H.equal(surface.dirties(), 0,
                "rejected transaction must not invalidate presentation")
        end)
        H.equal(injection_attempts, 1)
        H.equal(next(published_rows), nil,
            "rejected injector must not publish a mirror row")
        H.equal(persisted, 0)
        H.equal(noted, 0)
        local rejected = false
        for _, message in ipairs(mod.messages) do
            if message:find("craft transaction FAILED", 1, true)
                    and message:find("canonical injection rejected", 1, true) then
                rejected = true
            end
        end
        H.equal(rejected, true)
    end)

    H.test("CIM #1141 standard forge pre-commit rejection is not a completed craft", function()
        local ordinary_master = {
            es_sword = {
                key = "es_sword", name = "es_sword",
                slot_type = "melee", item_type = "weapon",
                rarity = "default", can_wield = { "es_mercenary" },
            },
        }
        local cases = {
            {
                name = "no career",
                backend_id = "ordinary-seed",
                master = ordinary_master,
                item = {
                    backend_id = "ordinary-seed", key = "es_sword",
                    rarity = "default", data = ordinary_master.es_sword,
                },
                arrange = function()
                    Managers.player.local_player = function() return nil end
                end,
                message = "no local career resolved",
            },
            {
                name = "invalid slot",
                backend_id = "material-seed",
                master = {
                    crafting_material_scrap = {
                        key = "crafting_material_scrap",
                        name = "crafting_material_scrap",
                        slot_type = "crafting_material",
                        item_type = "crafting_material",
                        rarity = "default",
                        can_wield = { "es_mercenary" },
                    },
                },
                item = function()
                    return {
                        backend_id = "material-seed",
                        key = "crafting_material_scrap",
                        rarity = "default",
                        data = {
                            key = "crafting_material_scrap",
                            slot_type = "crafting_material",
                        },
                    }
                end,
                message = "isn't a weapon/jewellery slot",
            },
            {
                name = "no eligible item",
                backend_id = "missing-seed",
                master = {},
                item = function() return nil end,
                message = "No eligible items for career",
            },
        }

        for _, case in ipairs(cases) do
            local mod = make_craft_surface_mod()
            mod._cim_test_items_by_id = {
                [case.backend_id] = case.item,
            }
            local injections, persisted, noted = 0, 0, 0
            install(context(mod, {
                inject_item = function()
                    injections = injections + 1
                    error(case.name .. " must reject before injection")
                end,
                register_craft = function()
                    persisted = persisted + 1
                    error(case.name .. " must reject before persistence")
                end,
                note_craft = function() noted = noted + 1 end,
            }))
            local older = { state = "older-complete" }
            local in_flight = { state = "in-flight" }
            with_craft_surface_globals(mod, case.master, nil, function(surface)
                assert(loadfile(root .. "standard_forge.lua"))()
                mod._cim_standard_forge_active = true
                if case.arrange then case.arrange() end
                local crafting = {
                    _last_id = 70,
                    _craft_requests = { [3] = older, [70] = in_flight },
                    _backend_mirror = {},
                    _get_valid_recipe = function()
                        return { name = "craft_weapon" }, {
                            case.backend_id,
                        }
                    end,
                }
                local craft_id, completion = mod.hooks.craft(
                    function() error("custom forge must not call vanilla") end,
                    crafting, "es_mercenary", { case.backend_id },
                    "craft_weapon")
                H.equal(craft_id, nil, case.name)
                H.equal(completion, false, case.name)
                H.equal(crafting._last_id, 71, case.name)
                H.equal(crafting._craft_requests[71], nil,
                    case.name .. " must not publish a completed request")
                H.equal(crafting._craft_requests[3], older,
                    case.name .. " must preserve older requests")
                H.equal(crafting._craft_requests[70], in_flight,
                    case.name .. " must preserve the prior in-flight request")
                H.equal(surface.dirties(), 0,
                    case.name .. " must not invalidate presentation")
            end)
            H.equal(injections, 0, case.name)
            H.equal(persisted, 0, case.name)
            H.equal(noted, 0, case.name)
            local saw_message = false
            for _, message in ipairs(mod.messages) do
                if message:find(case.message, 1, true) then
                    saw_message = true
                end
            end
            H.equal(saw_message, true, case.name)
        end
    end)

    H.test("CIM #1141 standard forge preserves legacy silent-drop completion", function()
        local mod = make_craft_surface_mod()
        local master = {
            es_sword = {
                key = "es_sword", name = "es_sword",
                slot_type = "melee", item_type = "weapon",
                rarity = "default", can_wield = { "es_mercenary" },
            },
        }
        local unrelated = { state = "pending" }
        with_craft_surface_globals(mod, master, nil, function(surface)
            assert(loadfile(root .. "standard_forge.lua"))()
            mod._cim_standard_forge_active = true
            local crafting = {
                _last_id = 5,
                _craft_requests = { [2] = unrelated },
                _backend_mirror = {},
                _get_valid_recipe = function() return nil end,
            }
            local craft_id, completion = mod.hooks.craft(
                function() error("active forge must not call vanilla") end,
                crafting, "es_mercenary", { "ordinary-seed" },
                "unknown_recipe")
            H.equal(craft_id, 6)
            H.equal(completion.name, "cim_noop")
            H.deep_equal(crafting._craft_requests[6], {})
            H.equal(crafting._craft_requests[2], unrelated)
            H.equal(surface.dirties(), 0)
        end)
    end)

    H.test("CIM #1141 SaveWeapon import commits atomically and contains rollback", function()
        local mod = make_craft_surface_mod()
        local injected, registered, rollbacks, rollback_refreshes = 0, 0, 0, 0
        local evidence_by_key = {}
        install(context(mod, {
            inject_item = function(data, backend_id)
                injected = injected + 1
                return true, nil, ownership_token(backend_id, data.item_key),
                    function()
                        rollbacks = rollbacks + 1
                        return true
                    end
            end,
            register_craft = function(_, data)
                registered = registered + 1
                if data.item_key == "dr_1h_axe" then
                    return false, "save rejected"
                end
                return true, data
            end,
            refresh_backend = function()
                rollback_refreshes = rollback_refreshes + 1
                return true
            end,
            note_craft = function() end,
            print_line = function(_, _, source_backend_id, raw_item_key)
                if source_backend_id then
                    evidence_by_key[raw_item_key] = source_backend_id
                end
            end,
        }))

        local saveweapon = {
            get = function(_, key)
                if key ~= "saved_items" then return nil end
                return {
                    es_sword_11 = "false/nil/trait_ok/prop_ok",
                    dr_1h_axe_12 = "true/nil/trait_ok/prop_ok",
                }
            end,
            get_item_name_from_save_id = function(_, save_id)
                if save_id == "es_sword_11" then return "es_sword" end
                if save_id == "dr_1h_axe_12" then return "dr_1h_axe" end
            end,
        }
        local master = {
            es_sword = { key = "es_sword", slot_type = "melee" },
            dr_1h_axe = { key = "dr_1h_axe", slot_type = "melee" },
        }
        local surface
        with_craft_surface_globals(mod, master, saveweapon, function(state)
            surface = state
            assert(loadfile(root .. "saveweapon_import.lua"))()
            mod._cim_saveweapon_import()
        end)

        H.equal(injected, 2)
        H.equal(registered, 2)
        H.equal(rollbacks, 1)
        H.equal(rollback_refreshes, 1)
        H.equal(surface.refreshes(), 1)
        H.equal(surface.dirties(), 1)
        H.equal(evidence_by_key.es_sword, "es_sword_11")
        H.equal(evidence_by_key.dr_1h_axe, "dr_1h_axe_12")
        local summary
        for _, message in ipairs(mod.messages) do
            if message:find("SaveWeapon import:", 1, true) then summary = message end
        end
        H.truthy(summary and summary:find("1 imported", 1, true))
        H.truthy(summary and summary:find("1 invalid", 1, true))
    end)

    H.test("CIM #1141 contextual label rejects unowned Apply and permits Craft", function()
        local function label_for(item)
            local mod = make_mod()
            install(context(mod))
            local window = {
                _widgets_by_name = {
                    upgrade_button = {
                        content = { button_hotspot = {} },
                        style = {
                            price_icon = { color = { 255 } },
                            price_icon_disabled = { color = { 255 } },
                        },
                    },
                    upgrade_essence_warning = { content = { visible = true } },
                },
                _selected_item = function()
                    return { data = { key = "es_sword" } }, "selected-bid"
                end,
            }
            with_globals(item, function()
                mod.safe_hooks._set_essence_upgrade_cost(window)
            end)
            return window._widgets_by_name.upgrade_button.content.title_text,
                window._widgets_by_name.upgrade_essence_warning.content.visible
        end

        local label, warning = label_for({ rarity = "modded", key = "es_sword" })
        H.equal(label, "UNAVAILABLE")
        H.equal(warning, false)
        label = label_for({ rarity = "default", key = "es_sword" })
        H.equal(label, "CRAFT")
    end)

    H.test("CIM #1117 bulk accessory label suppresses and restores native arrow", function()
        local mod = make_mod()
        install(context(mod))
        local selected = nil
        local function text_style(offset, default_offset)
            return { offset = offset, default_offset = default_offset }
        end
        local button = {
            content = {
                button_hotspot = {},
                icon = "athanor_icon_upgrade",
            },
            style = {
                title_text = text_style({ -15, 1, 6 }, { 20, 0, 6 }),
                title_text_disabled = text_style({ -16, 1, 6 }, { 20, 0, 6 }),
                title_text_shadow = text_style({ -13, -1, 5 }, { 22, -2, 5 }),
                price_icon = { color = { 255 } },
                price_icon_disabled = { color = { 255 } },
            },
        }
        local window = {
            _widgets_by_name = {
                upgrade_button = button,
                upgrade_essence_warning = { content = { visible = true } },
            },
            _selected_item = function()
                if not selected then return nil, nil end
                return { data = { key = "es_sword" } }, "selected-bid"
            end,
        }

        with_globals({ rarity = "default", key = "es_sword" }, function()
            mod.safe_hooks._set_essence_upgrade_cost(window)
            H.equal(button.content.title_text, "CRAFT MODDED ACCESSORIES")
            H.equal(button.content.icon, nil)
            H.deep_equal(button.style.title_text.offset, { 20, 0, 6 })
            H.deep_equal(button.style.title_text_disabled.offset, { 20, 0, 6 })
            H.deep_equal(button.style.title_text_shadow.offset, { 22, -2, 5 })

            selected = true
            mod.safe_hooks._set_essence_upgrade_cost(window)
            H.equal(button.content.title_text, "CRAFT")
            H.equal(button.content.icon, "athanor_icon_upgrade")

            selected = nil
            mod.safe_hooks._set_essence_upgrade_cost(window)
            H.equal(button.content.icon, nil)
        end)
    end)

    H.test("CIM #1141 leaving Temper Item discards only its keyed draft", function()
        local mod = make_mod()
        local seen = {}
        install(context(mod, {
            loadout = {
                discard_item_draft = function(career_name, backend_id)
                    seen[#seen + 1] = career_name .. "|" .. backend_id
                end,
                apply_item_draft = function() return true, false end,
                item_draft_payload = function() return nil end,
            },
        }))
        mod.safe_hooks.on_exit({
            _career_name = "es_mercenary",
            _selected_item = function() return {}, "owned-bid" end,
        })
        H.deep_equal(seen, { "es_mercenary|owned-bid" })
    end)

    H.test("CIM #1141 Apply targets the owned instance and never crafts", function()
        local backend_id, item_key = "owned-bid", "es_sword"
        local master = {
            key = item_key,
            name = item_key,
            slot_type = "melee",
            can_wield = { "es_mercenary" },
            template = "one_handed_sword_template_1",
            item_type = "one_handed_sword",
            inventory_icon = "icon_wpn_emp_sword_01_t1",
        }
        local record = assert(contract.normalize_record(backend_id, {
            item_key = item_key,
            rarity = "modded",
            power_level = 300,
            traits = {},
            properties = {},
            via_mirror = true,
        }, master))
        local payload, payload_error, mirror_record =
            contract.build_mirror_payload(record, master,
                function() return "{}" end)
        H.equal(payload_error, nil)
        local mirror = { _inventory_items = {} }
        function mirror:add_item(id, item)
            self._inventory_items[id] = item
            item.backend_id, item.key, item.data = id, item.ItemId, master
            item.rarity, item.power_level = "modded", 300
            item.traits, item.properties = {}, {}
        end
        function mirror:remove_item(id) self._inventory_items[id] = nil end
        H.truthy(contract.inject_mirror_item(mirror, backend_id, payload,
            function() return "owned-vanilla-apply-nonce" end, mirror_record))
        local live = mirror._inventory_items[backend_id]
        local presented = deep_clone(live)

        local mod = make_mod()
        local applied, discarded, injected, synced = 0, 0, 0, 0
        local loadout = {
            apply_item_draft = function() applied = applied + 1; return true, true end,
            discard_item_draft = function() discarded = discarded + 1 end,
            item_draft_payload = function() error("Apply must not mint") end,
        }
        install(context(mod, {
            loadout = loadout,
            get_forged_record = function(id)
                H.equal(id, backend_id)
                return record
            end,
            get_item_master = function(key)
                H.equal(key, item_key)
                return master
            end,
            get_raw_mirror_item = function(id)
                H.equal(id, backend_id)
                return live
            end,
            inject_item = function() injected = injected + 1; return true end,
        }))
        local window = {
            _career_name = "es_mercenary",
            _params = {},
            _selected_item = function()
                return presented, backend_id
            end,
            _sync_backend_loadout = function() synced = synced + 1 end,
        }
        with_globals(presented, function()
            mod.hooks._upgrade_magic_level(function() error("vanilla") end, window)
        end, { [item_key] = master })
        H.equal(applied, 1)
        H.equal(discarded, 1)
        H.equal(injected, 0)
        H.equal(synced, 1)
    end)

    H.test("CIM #1141 unowned vanilla and foreign rows cannot show or execute Apply", function()
        local cases = {
            { name = "vanilla exotic", rarity = "exotic" },
            { name = "vanilla veteran", rarity = "unique" },
            { name = "foreign modded", rarity = "modded" },
        }
        for _, case in ipairs(cases) do
            local mod = make_mod()
            local applied, drafted, injected = 0, 0, 0
            install(context(mod, {
                get_forged_record = function() return nil end,
                loadout = {
                    apply_item_draft = function()
                        applied = applied + 1
                        return true, true
                    end,
                    discard_item_draft = function() end,
                    item_draft_payload = function()
                        drafted = drafted + 1
                        return { properties = {}, traits = {} }
                    end,
                },
                inject_item = function()
                    injected = injected + 1
                    return true
                end,
            }))
            local item = {
                backend_id = "foreign-bid",
                key = "es_sword",
                rarity = case.rarity,
                data = { key = "es_sword", name = "es_sword" },
            }
            local button = {
                content = { button_hotspot = {} },
                style = {
                    price_icon = { color = { 255 } },
                    price_icon_disabled = { color = { 255 } },
                },
            }
            local window = {
                _career_name = "es_mercenary",
                _params = {},
                _widgets_by_name = {
                    upgrade_button = button,
                    upgrade_essence_warning = { content = {} },
                },
                _selected_item = function()
                    return item, item.backend_id
                end,
            }
            with_globals(item, function()
                mod.safe_hooks._set_essence_upgrade_cost(window)
                H.equal(button.content.title_text, "UNAVAILABLE", case.name)
                H.equal(button.content.button_hotspot.disable_button, true,
                    case.name)
                mod.hooks._upgrade_magic_level(
                    function() error("vanilla") end, window)
            end, { es_sword = item.data })
            H.equal(applied, 0, case.name)
            H.equal(drafted, 0, case.name)
            H.equal(injected, 0, case.name)
            H.truthy(mod.messages[#mod.messages]:find(
                "owned_record_required_for_apply", 1, true), case.name)
        end
    end)

    H.test("CIM #1141 persisted Apply rejects missing or mismatched ownership surfaces", function()
        local backend_id, item_key = "owned-bid", "es_sword"
        local master = {
            key = item_key, name = item_key, slot_type = "melee",
            can_wield = { "es_mercenary" },
            template = "one_handed_sword_template_1",
            item_type = "one_handed_sword",
            inventory_icon = "icon_wpn_emp_sword_01_t1",
        }
        local record = assert(contract.normalize_record(backend_id, {
            item_key = item_key, rarity = "modded", power_level = 300,
            traits = {}, properties = {}, via_mirror = true,
        }, master))
        local presented = {
            backend_id = backend_id, key = item_key, rarity = "modded",
            power_level = 300, traits = {}, properties = {}, data = master,
        }
        local cases = {
            { name = "missing raw", raw = nil, resolved_master = master },
            { name = "missing master", raw = presented, resolved_master = nil },
            {
                name = "mismatched raw",
                raw = {
                    backend_id = backend_id, key = "foreign_sword",
                    ItemId = "foreign_sword", data = master,
                },
                resolved_master = master,
            },
        }
        for _, case in ipairs(cases) do
            local mod = make_mod()
            local applied = 0
            install(context(mod, {
                get_forged_record = function() return record end,
                get_item_master = function() return case.resolved_master end,
                get_raw_mirror_item = function() return case.raw end,
                loadout = {
                    apply_item_draft = function()
                        applied = applied + 1
                        return true, true
                    end,
                    discard_item_draft = function() end,
                    item_draft_payload = function() error("must remain inert") end,
                },
            }))
            local button = {
                content = { button_hotspot = {} },
                style = {
                    price_icon = { color = { 255 } },
                    price_icon_disabled = { color = { 255 } },
                },
            }
            local window = {
                _career_name = "es_mercenary",
                _params = {},
                _widgets_by_name = {
                    upgrade_button = button,
                    upgrade_essence_warning = { content = {} },
                },
                _selected_item = function() return presented, backend_id end,
            }
            with_globals(presented, function()
                mod.safe_hooks._set_essence_upgrade_cost(window)
                H.equal(button.content.title_text, "UNAVAILABLE", case.name)
                H.equal(button.content.button_hotspot.disable_button, true,
                    case.name)
                mod.hooks._upgrade_magic_level(
                    function() error("vanilla") end, window)
            end, { [item_key] = master })
            H.equal(applied, 0, case.name)
        end
    end)

    H.test("CIM #1141 blacksmith Craft mints from draft without Apply", function()
        local mod = make_mod()
        local applied, injected, registered = 0, 0, 0
        mod._cim_register_craft = function(_, data)
            registered = registered + 1
            H.equal(data.item_key, "es_sword")
            H.equal(data.traits[1], "new_trait")
            return true
        end
        mod._cim_base_power = function() return 300 end
        local loadout = {
            apply_item_draft = function() applied = applied + 1; return true end,
            discard_item_draft = function() end,
            item_draft_payload = function()
                return { properties = { crit_chance = 1 }, traits = { "new_trait" } }
            end,
        }
        install(context(mod, {
            loadout = loadout,
            inject_item = function(data)
                injected = injected + 1
                H.equal(data.rarity, "modded")
                return true, nil, ownership_token("new-bid", data.item_key)
            end,
        }))
        local window = {
            _career_name = "es_mercenary",
            _params = { selected_slot_name = "slot_melee" },
            _selected_item = function()
                return { data = { key = "es_sword" } }, "blacksmith-bid"
            end,
        }
        with_globals({ rarity = "default", key = "es_sword" }, function()
            mod.hooks._upgrade_magic_level(function() error("vanilla") end, window)
        end)
        H.equal(applied, 0)
        H.equal(injected, 1)
        H.equal(registered, 1)
        H.truthy(mod.messages[#mod.messages]:find(
            "Crafted new melee: es_sword", 1, true))
    end)

    H.test("CIM #1141 installed hook preserves exact CWV seed identity for both bands", function()
        for _, suffix in ipairs({ "000", "001" }) do
            local fixture = cwv_seed_fixture(suffix)
            local mod = make_mod()
            mod._cim_base_power = function() return 300 end
            local provider_calls, injected, registered, noted = 0, 0, 0, 0
            local printed = {}
            local records = {}
            local mirror = { _inventory_items = {} }
            function mirror:add_item(backend_id, item)
                local row = fixture.master[item.ItemId]
                self._inventory_items[backend_id] = item
                item.backend_id, item.key, item.data = backend_id, item.ItemId, row
                item.rarity, item.power_level = "modded", 300
                item.traits, item.properties = {}, {}
            end
            function mirror:remove_item(backend_id)
                self._inventory_items[backend_id] = nil
            end
            install(context(mod, {
                get_cwv_seed_identity_provider = function()
                    provider_calls = provider_calls + 1
                    return fixture.provider
                end,
                inject_item = function(data, backend_id)
                    injected = injected + 1
                    H.equal(data.item_key, fixture.item_key)
                    local master_row = fixture.master[data.item_key]
                    local normalized, normalize_error = contract.gate_record(
                        "mirror_injection", backend_id, data, master_row)
                    H.equal(normalize_error, nil)
                    local payload, payload_error, mirror_record =
                        contract.build_mirror_payload(normalized, master_row,
                            function() return "{}" end)
                    H.equal(payload_error, nil)
                    return contract.inject_mirror_item(mirror, backend_id,
                        payload, function() return "installed-chain-nonce" end,
                        mirror_record)
                end,
                register_craft = function(backend_id, data)
                    registered = registered + 1
                    H.equal(backend_id, "new-bid")
                    H.equal(data.item_key, fixture.item_key)
                    records[backend_id] = assert(contract.normalize_record(
                        backend_id, data, fixture.master[data.item_key]))
                    return true, records[backend_id]
                end,
                get_forged_record = function(backend_id)
                    return records[backend_id]
                end,
                note_craft = function(backend_id)
                    noted = noted + 1
                    H.equal(backend_id, "new-bid")
                end,
                print_line = function(fmt, ...)
                    printed[#printed + 1] = string.format(fmt, ...)
                end,
            }))
            local window = {
                _career_name = "es_mercenary",
                _params = { selected_slot_name = "slot_melee" },
                _selected_item = function()
                    return fixture.selected, fixture.backend_id
                end,
            }
            with_globals(fixture.live, function()
                mod.hooks._upgrade_magic_level(
                    function() error("vanilla") end, window)
                local check = mod.checks.issue1141_temper_blacksmith_exact_identity
                H.truthy(check)
                H.equal(check(), nil)
            end, fixture.master)
            H.equal(provider_calls, 4)
            H.equal(injected, 1)
            H.equal(registered, 1)
            H.equal(noted, 1)
            H.equal(records["new-bid"].item_key, fixture.item_key)
            H.equal(records["new-bid"].owner, contract.OWNER)
            H.equal(mirror._inventory_items["new-bid"].ItemId,
                fixture.item_key)
            H.equal(mirror._inventory_items["new-bid"].CustomData.cwv_key,
                fixture.item_key)
            H.equal(mirror._inventory_items["new-bid"].CustomData.cim_injection_owner,
                contract.OWNER)
            H.truthy(printed[1]:find(
                "canonical=" .. fixture.item_key, 1, true))
            H.truthy(mod.messages[#mod.messages]:find(
                fixture.item_key, 1, true))
        end
    end)

    H.test("CIM #1141 exact owned CWV instance applies without consulting seed provider", function()
        local fixture = cwv_seed_fixture("001")
        local backend_id = "owned-cwv-bid"
        local record = assert(contract.normalize_record(backend_id, {
            item_key = fixture.item_key,
            rarity = "modded",
            power_level = 300,
            traits = {},
            properties = {},
            via_mirror = true,
        }, fixture.master[fixture.item_key]))
        local payload, _, mirror_record = contract.build_mirror_payload(
            record, fixture.master[fixture.item_key], function() return "{}" end)
        local mirror = { _inventory_items = {} }
        function mirror:add_item(id, item)
            self._inventory_items[id] = item
            item.backend_id, item.key = id, item.ItemId
            item.data = fixture.master[fixture.item_key]
            item.rarity, item.power_level = "modded", 300
            item.traits, item.properties = {}, {}
        end
        function mirror:remove_item(id) self._inventory_items[id] = nil end
        H.truthy(contract.inject_mirror_item(mirror, backend_id, payload,
            function() return "owned-apply-nonce" end, mirror_record))
        local live = mirror._inventory_items[backend_id]
        local presented = deep_clone(live)

        local mod = make_mod()
        local applied, injected, provider_calls = 0, 0, 0
        install(context(mod, {
            get_forged_record = function(id)
                H.equal(id, backend_id)
                return record
            end,
            get_raw_mirror_item = function(id)
                H.equal(id, backend_id)
                return live
            end,
            get_cwv_seed_identity_provider = function()
                provider_calls = provider_calls + 1
                error("owned Apply must not consult seed provider")
            end,
            loadout = {
                apply_item_draft = function()
                    applied = applied + 1
                    return true, true
                end,
                discard_item_draft = function() end,
                item_draft_payload = function() error("Apply must not mint") end,
            },
            inject_item = function()
                injected = injected + 1
                return true
            end,
        }))
        local window = {
            _career_name = "es_mercenary",
            _params = {},
            _selected_item = function() return presented, backend_id end,
            _sync_backend_loadout = function() end,
        }
        with_globals(presented, function()
            mod.hooks._upgrade_magic_level(function() error("vanilla") end,
                window)
        end, fixture.master)
        H.equal(applied, 1)
        H.equal(injected, 0)
        H.equal(provider_calls, 0)
    end)

    H.test("CIM #1141 unowned modded CWV row cannot take generic Apply", function()
        local fixture = cwv_seed_fixture("001")
        fixture.live.rarity = "modded"
        fixture.live.CustomData.rarity = "modded"
        fixture.live.data.rarity = "modded"
        fixture.live.data.mod_data.rarity = "modded"
        fixture.live.data.mod_data.CustomData.rarity = "modded"
        local selected = {
            backend_id = fixture.backend_id,
            key = fixture.donor_key,
            cwv_key = fixture.item_key,
            rarity = "modded",
            data = fixture.live.data,
        }
        local mod = make_mod()
        local generic_calls, applied, guid_calls, inject_calls = 0, 0, 0, 0
        install(context(mod, {
            transaction = {
                action_for = function()
                    generic_calls = generic_calls + 1
                    return "apply"
                end,
                copy_payload = function(payload) return payload end,
            },
            get_cwv_seed_identity_provider = function()
                return fixture.provider
            end,
            loadout = {
                apply_item_draft = function()
                    applied = applied + 1
                    return true, true
                end,
                discard_item_draft = function() end,
                item_draft_payload = function() return {} end,
            },
            guid = function() guid_calls = guid_calls + 1; return "new-bid" end,
            inject_item = function()
                inject_calls = inject_calls + 1
                return true
            end,
        }))
        local window = {
            _career_name = "es_mercenary",
            _params = {},
            _selected_item = function() return selected, fixture.backend_id end,
        }
        with_globals(fixture.live, function()
            mod.hooks._upgrade_magic_level(function() end, window)
        end, fixture.master)
        H.equal(generic_calls, 0)
        H.equal(applied, 0)
        H.equal(guid_calls, 0)
        H.equal(inject_calls, 0)
        H.truthy(mod.messages[#mod.messages]:find(
            "Temper action rejected", 1, true))
    end)

    H.test("CIM #1141 ordinary and immutable sources never query CWV", function()
        local function run(selected, live)
            local mod = make_mod()
            local provider_calls, guid_calls, inject_calls = 0, 0, 0
            install(context(mod, {
                get_cwv_seed_identity_provider = function()
                    provider_calls = provider_calls + 1
                    error("ordinary source must not query CWV")
                end,
                guid = function()
                    guid_calls = guid_calls + 1
                    return "new-bid"
                end,
                inject_item = function(data, backend_id)
                    inject_calls = inject_calls + 1
                    return true, nil, ownership_token(backend_id, data.item_key)
                end,
                register_craft = function() return true end,
            }))
            local window = {
                _career_name = "es_mercenary",
                _params = {},
                _selected_item = function() return selected, "source-bid" end,
            }
            with_globals(live, function()
                mod.hooks._upgrade_magic_level(function() end, window)
            end)
            return provider_calls, guid_calls, inject_calls, mod.messages
        end

        local provider_calls, guid_calls, inject_calls = run(
            { data = { key = "es_sword" } },
            { key = "es_sword", rarity = "default" })
        H.equal(provider_calls, 0)
        H.equal(guid_calls, 1)
        H.equal(inject_calls, 1)

        provider_calls, guid_calls, inject_calls = run(
            { data = { key = "woc_blightreaper" } },
            { key = "woc_blightreaper", rarity = "default" })
        H.equal(provider_calls, 0)
        H.equal(guid_calls, 0)
        H.equal(inject_calls, 0)
    end)

    H.test("CIM #1141 CWV contradictions reject before GUID or injection", function()
        local fixture = cwv_seed_fixture("001")
        local function rejected(selected, backend_item)
            local mod = make_mod()
            local guid_calls, inject_calls = 0, 0
            install(context(mod, {
                get_cwv_seed_identity_provider = function()
                    return fixture.provider
                end,
                guid = function()
                    guid_calls = guid_calls + 1
                    return "new-bid"
                end,
                inject_item = function()
                    inject_calls = inject_calls + 1
                    return true
                end,
                register_craft = function() return true end,
            }))
            local window = {
                _career_name = "es_mercenary",
                _params = {},
                _selected_item = function()
                    return selected, fixture.backend_id
                end,
            }
            with_globals(backend_item, function()
                mod.hooks._upgrade_magic_level(function() end, window)
            end)
            H.equal(guid_calls, 0)
            H.equal(inject_calls, 0)
            H.truthy(mod.messages[#mod.messages]:find(
                "Temper action rejected", 1, true))
        end

        rejected(fixture.selected, function() error("live read failed") end)
        rejected({
            backend_id = fixture.backend_id,
            key = fixture.donor_key,
            rarity = "default",
            cwv_key = fixture.item_key,
            data = {
                key = fixture.donor_key,
                CustomData = { cwv_key = "cwv_es_longsword" },
            },
        }, fixture.live)
        rejected({
            backend_id = fixture.backend_id,
            key = "bw_1h_sword",
            rarity = "default",
            cwv_key = fixture.item_key,
        }, fixture.live)
    end)

    H.test("CIM #1141 commit contains invalid proof and persistence failures", function()
        local function run(options)
            local mod = make_mod()
            local rollbacks, registers, notes, refreshes = 0, 0, 0, 0
            local token = ownership_token("new-bid", "cwv_es_dual_swords")
            local state = install(context(mod, {
                contract = options.contract or contract,
                inject_item = function()
                    return true, nil, options.token == false and {} or token,
                        function()
                            rollbacks = rollbacks + 1
                            if options.rollback_throw then error("rollback threw") end
                            if options.rollback_nil then return nil end
                            if options.rollback_false then return false, "rollback denied" end
                            return true
                        end
                end,
                register_craft = function()
                    registers = registers + 1
                    if options.register_throw then error("register threw") end
                    if options.register_false then return false, "register denied" end
                    return true
                end,
                note_craft = function() notes = notes + 1 end,
                refresh_backend = function()
                    refreshes = refreshes + 1
                    if options.refresh_throw then error("refresh threw") end
                    if options.refresh_false then return false, "refresh denied" end
                    return true
                end,
            }))
            local ok, reason = state.commit_craft({
                item_key = "cwv_es_dual_swords",
            }, "new-bid", {})
            return ok, reason, rollbacks, registers, notes, refreshes
        end

        local ok, reason, rollbacks, registers, notes, refreshes = run({
            token = false,
        })
        H.equal(ok, false)
        H.truthy(reason:find("rollback=complete", 1, true))
        H.equal(rollbacks, 1)
        H.equal(registers, 0)
        H.equal(notes, 0)
        H.equal(refreshes, 1)

        for _, option in ipairs({ "register_false", "register_throw" }) do
            local scenario = { [option] = true }
            ok, reason, rollbacks, registers, notes, refreshes = run(scenario)
            H.equal(ok, false)
            H.equal(rollbacks, 1)
            H.equal(registers, 1)
            H.equal(notes, 0)
            H.equal(refreshes, 1)
        end

        ok, reason, rollbacks = run({ register_false = true, rollback_nil = true })
        H.equal(ok, false)
        H.truthy(reason:find("rollback_failed:rejected", 1, true))
        H.equal(rollbacks, 1)

        for _, option in ipairs({ "refresh_throw", "refresh_false" }) do
            local scenario = { register_false = true, [option] = true }
            ok, reason, rollbacks, registers, notes, refreshes = run(scenario)
            H.equal(ok, false)
            H.truthy(reason:find("rollback_failed:post%-rollback%-refresh"))
            H.equal(rollbacks, 1)
            H.equal(registers, 1)
            H.equal(notes, 0)
            H.equal(refreshes, 1)
        end

        local throwing_contract = {}
        for key, value in pairs(contract) do throwing_contract[key] = value end
        throwing_contract.validate_mirror_ownership_token = function()
            error("validator threw")
        end
        ok, reason, rollbacks, registers = run({ contract = throwing_contract })
        H.equal(ok, false)
        H.truthy(reason:find("rollback=complete", 1, true))
        H.equal(rollbacks, 1)
        H.equal(registers, 0)
    end)

    H.test("CIM #1141 receipts are capped at eight", function()
        local mod = make_mod()
        local lines = {}
        local state = install(context(mod, {
            inject_item = function() return nil, "rejected" end,
            register_craft = function() return true end,
            print_line = function(fmt, ...)
                lines[#lines + 1] = string.format(fmt, ...)
            end,
        }))
        for index = 1, 12 do
            state.commit_craft({ item_key = "es_sword" },
                "new-bid-" .. index, {})
        end
        H.equal(#lines, 8)
        H.truthy(lines[8]:find("receipt=8/8", 1, true))
    end)
end
