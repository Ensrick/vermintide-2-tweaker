return function(H, repo_root)
    local root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local install = assert(loadfile(root .. "_cim_temper_runtime.lua"))()
    local synthetic_contract = assert(loadfile(
        root .. "_cim_synthetic_item_contract.lua"))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local value = file:read("*a")
        file:close()
        return value
    end

    local function make_mod()
        local mod = { hooks = {}, safe_hooks = {}, messages = {} }
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
            contract = overrides.contract or synthetic_contract,
            transaction = overrides.transaction or {
                action_for = function(item)
                    return item.rarity == "default" and "craft" or "apply"
                end,
                copy_payload = function(payload) return payload end,
            },
            loadout = overrides.loadout or {
                discard_item_draft = function() end,
                apply_item_draft = function() return true, true end,
                item_draft_payload = function()
                    return { properties = {}, traits = {} }
                end,
            },
            bulk_accessory_craft = { craft_all = function() return 0 end },
            craft_accessory = function() return false end,
            inject_item = overrides.inject_item or function() return true end,
        }
    end

    local function with_globals(item, body, printer)
        local old = {
            Managers = rawget(_G, "Managers"),
            Application = rawget(_G, "Application"),
            ItemMasterList = rawget(_G, "ItemMasterList"),
            Localize = rawget(_G, "Localize"),
            printf = rawget(_G, "printf"),
        }
        rawset(_G, "Managers", {
            backend = {
                get_interface = function() return {
                    get_item_from_id = function() return item end,
                } end,
                get_backend_mirror = function() return { remove_item = function() end } end,
            },
        })
        rawset(_G, "Application", { guid = function() return "new-bid" end })
        rawset(_G, "ItemMasterList", {})
        rawset(_G, "Localize", function(key) return key end)
        if printer ~= nil then rawset(_G, "printf", printer) end
        local ok, err = pcall(body)
        for key, value in pairs(old) do rawset(_G, key, value) end
        if old.Managers == nil then rawset(_G, "Managers", nil) end
        if old.Application == nil then rawset(_G, "Application", nil) end
        if old.ItemMasterList == nil then rawset(_G, "ItemMasterList", nil) end
        if old.Localize == nil then rawset(_G, "Localize", nil) end
        rawset(_G, "printf", old.printf)
        if not ok then error(err, 0) end
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

    H.test("CIM #1141 contextual label distinguishes Apply from Craft", function()
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
        H.equal(label, "APPLY")
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
        local mod = make_mod()
        local applied, discarded, injected, synced = 0, 0, 0, 0
        local loadout = {
            apply_item_draft = function() applied = applied + 1; return true, true end,
            discard_item_draft = function() discarded = discarded + 1 end,
            item_draft_payload = function() error("Apply must not mint") end,
        }
        install(context(mod, {
            loadout = loadout,
            inject_item = function() injected = injected + 1; return true end,
        }))
        local window = {
            _career_name = "es_mercenary",
            _params = {},
            _selected_item = function()
                return { data = { key = "es_sword" } }, "owned-bid"
            end,
            _sync_backend_loadout = function() synced = synced + 1 end,
        }
        with_globals({ rarity = "modded", key = "es_sword" }, function()
            mod.hooks._upgrade_magic_level(function() error("vanilla") end, window)
        end)
        H.equal(applied, 1)
        H.equal(discarded, 1)
        H.equal(injected, 0)
        H.equal(synced, 1)
    end)

    H.test("CIM #1141 blacksmith Craft mints from draft without Apply", function()
        local mod = make_mod()
        local applied, injected = 0, 0
        mod._cim_register_craft = function(_, data)
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
                return true
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
    end)

    H.test("CIM #1141 Blacksmith Craft preserves CWV identity over vanilla alias", function()
        local mod = make_mod()
        local registered, injected, receipt, noted, receipt_count
        receipt_count = 0
        mod._cim_register_craft = function(_, data)
            registered = data.item_key
            return true
        end
        mod._cim_base_power = function() return 300 end
        mod._cim_note_craft_bid = function(backend_id) noted = backend_id end
        install(context(mod, {
            loadout = {
                apply_item_draft = function() error("CWV template must Craft") end,
                discard_item_draft = function() end,
                item_draft_payload = function()
                    return { properties = { crit_chance = 1 }, traits = { "trait" } }
                end,
            },
            inject_item = function(data)
                injected = data.item_key
                return true
            end,
        }))
        local window = {
            _career_name = "es_mercenary",
            _params = { selected_slot_name = "slot_melee" },
            _selected_item = function()
                return { data = { key = "we_dual_wield_swords" } },
                    "cwv_es_dual_swords_001"
            end,
        }
        -- This is the live failure shape from Rain's log: the engine-facing key
        -- is Kerillian's donor, while the Blacksmith backend id owns Kruber's
        -- exact Imperial Dual Swords identity.
        with_globals({
            rarity = "default",
            key = "we_dual_wield_swords",
            ItemId = "we_dual_wield_swords",
        }, function()
            for _ = 1, 10 do
                mod.hooks._upgrade_magic_level(function() error("vanilla") end, window)
            end
        end, function(format, ...)
            receipt_count = receipt_count + 1
            receipt = string.format(format, ...)
        end)
        H.equal(injected, "cwv_es_dual_swords")
        H.equal(registered, "cwv_es_dual_swords")
        H.equal(noted, "new-bid")
        H.truthy(receipt:find(
            "raw=we_dual_wield_swords canonical=cwv_es_dual_swords result=registered",
            1, true))
        H.equal(receipt_count, 8)
    end)

    H.test("CIM #1141 entry injects the shared identity contract", function()
        local entry = read(root .. "crafting_in_modded_dev.lua")
        H.truthy(entry:find("contract = mod._cim_synthetic_item_contract,", 1, true))
        local runtime = read(root .. "_cim_temper_runtime.lua")
        H.truthy(runtime:find("state.contract.canonical_item_key(live_item, backend_id)",
            1, true))
        H.equal(runtime:find("live_item and (live_item.key or live_item.ItemId)\n                or item_data", 1, true), nil)
        H.truthy(runtime:find("[cim:1141] temper_craft backend=", 1, true))
        H.truthy(runtime:find("state.issue1141_receipts < 8", 1, true))
    end)
end
