return function(H, repo_root)
    local fixture = assert(loadfile(repo_root
        .. "/qa/lua/tests/_cim_temper_fixture.lua"))()(H, repo_root)
    local root = fixture.root
    local install = fixture.install
    local install_seed_owner = fixture.install_seed_owner
    local contract = fixture.contract
    local read = fixture.read
    local deep_clone = fixture.deep_clone
    local ownership_token = fixture.ownership_token
    local make_mod = fixture.make_mod
    local context = fixture.context
    local with_globals = fixture.with_globals
    local cwv_seed_fixture = fixture.cwv_seed_fixture

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

    H.test("CIM #1141 button labels resolve through mod localization with exact fallback", function()
        local localization = assert(loadfile(root
            .. "crafting_in_modded_dev_localization.lua"))()
        local expected = {
            temper_button_apply = "APPLY",
            temper_button_craft = "CRAFT",
            temper_button_unavailable = "UNAVAILABLE",
            temper_button_craft_accessories = "CRAFT MODDED ACCESSORIES",
        }
        for key, text in pairs(expected) do
            H.equal(type(localization[key]), "table", key)
            H.equal(localization[key].en, text, key)
            H.equal(text:find("\226\128\148", 1, true), nil, key .. " carries an em dash")
        end

        -- A resolved localization string wins; an unresolved key, VMF's
        -- <key> marker, or a throwing localizer falls back to the exact text.
        local mod = make_mod()
        local strings = { temper_button_apply = "Apply staged changes" }
        mod.localize = function(self, key)
            H.equal(self, mod)
            return strings[key] or ("<" .. key .. ">")
        end
        local temper = install(context(mod))
        H.equal(temper.button_label("temper_button_apply"), "Apply staged changes")
        H.equal(temper.button_label("temper_button_craft"), "CRAFT")
        H.equal(temper.button_label("temper_button_unavailable"), "UNAVAILABLE")
        H.equal(temper.button_label("temper_button_craft_accessories"),
            "CRAFT MODDED ACCESSORIES")
        mod.localize = function() error("localizer unavailable") end
        H.equal(temper.button_label("temper_button_apply"), "APPLY")
        mod.localize = nil
        H.equal(temper.button_label("temper_button_craft"), "CRAFT")

        -- The Weapon Select handoff reads the same localized Craft label.
        local craft_mod = make_mod()
        craft_mod.localize = function(_, key)
            return key == "temper_button_craft" and "Craft copy" or ("<" .. key .. ">")
        end
        local craft_temper = install(context(craft_mod))
        install_seed_owner({
            mod = craft_mod,
            is_active = function() return true end,
            contract = contract,
            get_temper_state = function() return craft_temper end,
            get_master = function() return nil end,
            clone = deep_clone,
            localize = function(key) return key end,
        })
        local button = { content = { button_hotspot = {} } }
        craft_mod.hooks._update_equip_button_status(
            function() error("custom route must not call vanilla") end,
            { _selected_item_id = "es_sword", _viewport_data = { equip_button = button } },
            nil, false)
        H.equal(button.content.title_text, "Craft copy")
        H.equal(button.content.button_hotspot.disable_button, false)
    end)
end
