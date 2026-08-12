return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local module_path = root .. "_ct_bot_weapon_chest_owner.lua"
    local entry_path = root .. "chaos_wastes_tweaker_dev.lua"

local function read(path)
        if tostring(path):find("chaos_wastes_tweaker_dev.lua", 1, true) then
            return CTSource.expanded(repo_root)
        end
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    local function fixture()
        local hooks, order, settings = {}, {}, {}
        local uses, probe_watch = {}, {}
        local mod = {
            _ct_bot_economy = {},
        }

        function mod:hook(class_name, method_name, callback)
            H.equal(hooks[class_name .. "." .. method_name], nil,
                "duplicate hook " .. class_name .. "." .. method_name)
            hooks[class_name .. "." .. method_name] = callback
            order[#order + 1] = "hook:" .. class_name .. "." .. method_name
        end

        function mod:hook_safe(class_name, method_name, callback)
            H.equal(hooks[class_name .. "." .. method_name], nil,
                "duplicate safe hook " .. class_name .. "." .. method_name)
            hooks[class_name .. "." .. method_name] = callback
            order[#order + 1] = "safe:" .. class_name .. "." .. method_name
        end

        local function install(overrides)
            overrides = overrides or {}
            local owner = assert(loadfile(module_path))()
            return owner({
                mod = mod,
                effective_setting = overrides.effective_setting or function(id)
                    return settings[id]
                end,
                dbg = overrides.dbg or function() end,
                dbg_alert = overrides.dbg_alert or function() end,
                altar_uses = overrides.altar_uses or function()
                    return uses
                end,
                altar_max_uses = overrides.altar_max_uses or function()
                    return 2
                end,
                probe_collected_by_peers =
                    overrides.probe_collected_by_peers or function()
                        return "[]"
                    end,
                altar_probe_watch = overrides.altar_probe_watch or probe_watch,
            })
        end

        return mod, hooks, order, settings, uses, probe_watch, install
    end

    local function with_globals(values, body)
        local saved = {}
        for key, value in pairs(values) do
            saved[key] = rawget(_G, key)
            _G[key] = value
        end
        local ok, err = pcall(body)
        for key in pairs(values) do
            _G[key] = saved[key]
        end
        if not ok then error(err, 0) end
    end

    H.test("CT bot weapon chest owner replaces one complete registration boundary", function()
        local entry = read(entry_path)
        local owner = read(module_path)
        H.equal(count_plain(entry,
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_bot_weapon_chest_owner"), 1)
        H.equal(count_plain(entry,
            '\nmod:hook("DeusChestExtension", "open_chest"'), 0)
        H.equal(count_plain(owner,
            'mod:hook("DeusChestExtension", "open_chest"'), 1)
        H.equal(count_plain(owner, "_ct_consolidated_open_chest_hook"), 2)
        H.equal(count_plain(owner,
            'mod:hook("DeusChestExtension", "purchase"'), 1)
        H.equal(count_plain(owner,
            'mod:hook_safe("DeusChestExtension", "extensions_ready"'), 1)
        H.equal(count_plain(entry,
            'mod:hook("DeusRunController", "_check_set_completed"'), 1)
        H.equal(count_plain(entry,
            'mod:hook("DeusCursedChestView", "_on_button_pressed"'), 1)
    end)

    H.test("CT bot weapon chest owner installs exact hooks once and keeps public equip stable", function()
        local mod, hooks, order, _, _, _, install = fixture()
        H.equal(install(), true)
        H.deep_equal(order, {
            "safe:DeusChestExtension.extensions_ready",
            "hook:DeusChestExtension.purchase",
            "hook:DeusChestExtension.open_chest",
        })
        H.equal(type(hooks["DeusChestExtension.extensions_ready"]), "function")
        H.equal(type(hooks["DeusChestExtension.purchase"]), "function")
        H.equal(type(hooks["DeusChestExtension.open_chest"]), "function")
        H.equal(type(mod._ct_bot_equip_weapon), "function")
        local public = mod._ct_bot_equip_weapon
        H.equal(install(), false)
        H.equal(#order, 3)
        H.equal(mod._ct_bot_equip_weapon, public)
        H.equal(mod._ct_bot_weapon_chest_owner_installed, true)
    end)

    H.test("CT chest diagnostic subscription is once per live event manager", function()
        local _, hooks, _, _, _, _, install = fixture()
        install()
        local registrations = 0
        local function event_manager()
            return {
                register = function(self, subscriber, ...)
                    registrations = registrations + 1
                    H.equal(type(subscriber.player_pickup_deus_weapon_chest), "function")
                    H.equal(type(subscriber.chest_unlock_failed), "function")
                    H.equal(select("#", ...), 4)
                end,
            }
        end
        local first = event_manager()
        with_globals({
            Managers = { state = { event = first } },
        }, function()
            hooks["DeusChestExtension.extensions_ready"]({})
            hooks["DeusChestExtension.extensions_ready"]({})
            H.equal(registrations, 1)
            Managers.state.event = event_manager()
            hooks["DeusChestExtension.extensions_ready"]({})
            H.equal(registrations, 2)
        end)
    end)

    H.test("CT reusable altar purchase suppresses only intermediate collapse and restores Unit", function()
        local _, hooks, _, _, uses, _, install = fixture()
        install()
        local seen = {}
        local original_flow = function(unit, event)
            seen[#seen + 1] = event
        end
        with_globals({
            Unit = { flow_event = original_flow },
        }, function()
            local self = {
                _go_id = 8,
                _chest_type = "upgrade",
                unit = {},
            }
            hooks["DeusChestExtension.purchase"](function(ext)
                Unit.flow_event(ext.unit, "lua_update_collected")
                Unit.flow_event(ext.unit, "lua_update_upgrade")
            end, self)
            H.deep_equal(seen, { "lua_update_upgrade" })
            H.equal(Unit.flow_event, original_flow)

            uses[8] = 1
            hooks["DeusChestExtension.purchase"](function(ext)
                Unit.flow_event(ext.unit, "lua_update_collected")
            end, self)
            H.deep_equal(seen, {
                "lua_update_upgrade",
                "lua_update_collected",
            })
            H.equal(Unit.flow_event, original_flow)
        end)
    end)

    H.test("CT consolidated open chest restores grant cost on vanilla error", function()
        local mod, hooks, _, _, _, _, install = fixture()
        install()
        mod._ct_bot_altar_cost = 77
        with_globals({
            DEUS_CHEST_TYPES = {
                power_up = "power_up",
                swap_melee = "swap_melee",
                swap_ranged = "swap_ranged",
                upgrade = "upgrade",
            },
        }, function()
            local self = {
                _rarity = "rare",
                _chest_type = "power_up",
                get_purchase_cost = function()
                    return 123
                end,
            }
            local ok = pcall(hooks["DeusChestExtension.open_chest"],
                function()
                    H.equal(mod._ct_bot_altar_cost, 123)
                    error("vanilla failed")
                end, self)
            H.equal(ok, false)
            H.equal(mod._ct_bot_altar_cost, 77)
        end)
    end)

    H.test("CT consolidated open chest preserves boon no-repeat bookkeeping", function()
        local mod, hooks, _, settings, _, _, install = fixture()
        settings.bots_mirror_host_weapon_upgrades = false
        install()
        with_globals({
            DEUS_CHEST_TYPES = {
                power_up = "power_up",
                swap_melee = "swap_melee",
                swap_ranged = "swap_ranged",
                upgrade = "upgrade",
            },
        }, function()
            local self = {
                _rarity = "rare",
                _chest_type = "power_up",
                _stored_purchase = { name = "test_boon" },
                get_purchase_cost = function()
                    return 10
                end,
            }
            hooks["DeusChestExtension.open_chest"](function() end, self)
            H.equal(mod._ct_boon_altar_taken_boons.test_boon, true)
        end)
    end)
end
