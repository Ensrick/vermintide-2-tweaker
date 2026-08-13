return function(H, repo_root)
    local root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local install = assert(loadfile(root .. "_cim_temper_runtime.lua"))()

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

    local function with_globals(item, body)
        local old = {
            Managers = rawget(_G, "Managers"),
            Application = rawget(_G, "Application"),
            ItemMasterList = rawget(_G, "ItemMasterList"),
            Localize = rawget(_G, "Localize"),
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
        local ok, err = pcall(body)
        for key, value in pairs(old) do rawset(_G, key, value) end
        if old.Managers == nil then rawset(_G, "Managers", nil) end
        if old.Application == nil then rawset(_G, "Application", nil) end
        if old.ItemMasterList == nil then rawset(_G, "ItemMasterList", nil) end
        if old.Localize == nil then rawset(_G, "Localize", nil) end
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
end
