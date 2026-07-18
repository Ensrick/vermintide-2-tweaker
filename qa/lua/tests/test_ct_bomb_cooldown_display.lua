return function(H, repo_root)
    local base = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local module_path = base .. "_ct_bomb_cooldown_display.lua"
    local main_path = base .. "chaos_wastes_tweaker_dev.lua"
    local balance_path = base .. "_ct_boon_balance.lua"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function load_isolated()
        local saved = {
            get_mod = _G.get_mod,
            BuffTemplates = _G.BuffTemplates,
            Managers = _G.Managers,
            ScriptUnit = _G.ScriptUnit,
            printf = _G.printf,
        }
        local fake_mod = {}
        function fake_mod:network_register(channel, callback)
            self.channel = channel
            self.callback = callback
        end
        function fake_mod:network_send(...)
            self.sent = { ... }
        end
        _G.get_mod = function() return fake_mod end
        _G.BuffTemplates = {}
        _G.printf = function() end

        local ok, module_or_error = pcall(assert(loadfile(module_path)))
        return ok, module_or_error, fake_mod, saved
    end

    local function restore(saved)
        _G.get_mod = saved.get_mod
        _G.BuffTemplates = saved.BuffTemplates
        _G.Managers = saved.Managers
        _G.ScriptUnit = saved.ScriptUnit
        _G.printf = saved.printf
    end

    H.test("CT #357 registers four client-local cooldown templates", function()
        local ok, module, fake_mod, saved = load_isolated()
        local test_ok, failure = pcall(function()
            H.truthy(ok, tostring(module))
            H.truthy(module.install(7))
            H.equal(fake_mod.channel, "ct_bomb_cooldown_display_v1")
            local count = 0
            for boon_name, spec in pairs(module.boons) do
                count = count + 1
                H.truthy(module.valid_payload(boon_name, 15))
                local sub = _G.BuffTemplates[spec.template].buffs[1]
                H.equal(sub.icon, spec.icon)
                H.equal(sub.is_cooldown, true)
                H.equal(sub.duration, 1)
            end
            H.equal(count, 4)
            H.equal(module.valid_payload("boon_supportbomb_strenght_01", 15), false)
            H.equal(module.valid_payload("boon_supportbomb_crit_01", 0), false)
            H.equal(module.valid_payload("boon_supportbomb_crit_01", 0 / 0), false)
        end)
        restore(saved)
        if not test_ok then error(failure, 0) end
    end)

    H.test("CT #357 accepts the display RPC only from the host", function()
        local ok, module, fake_mod, saved = load_isolated()
        local test_ok, failure = pcall(function()
            H.truthy(ok, tostring(module))
            H.truthy(module.install(7))
            local applications = {}
            local extension = {
                add_buff = function(_, template, params)
                    applications[#applications + 1] = { template, params.external_optional_duration }
                end,
            }
            _G.ScriptUnit = { has_extension = function() return extension end }
            _G.Managers = {
                state = { network = { network_client = { server_peer_id = "host-peer" } } },
                player = {
                    local_player = function() return { player_unit = "local-unit" } end,
                },
            }

            fake_mod.callback("forged-peer", 7, "boon_supportbomb_crit_01", 20)
            fake_mod.callback("host-peer", 6, "boon_supportbomb_crit_01", 20)
            fake_mod.callback("host-peer", 7, "boon_supportbomb_crit_01", 0)
            H.equal(#applications, 0)
            fake_mod.callback("host-peer", 7, "boon_supportbomb_crit_01", 20)
            H.equal(#applications, 1)
            H.equal(applications[1][2], 20)
        end)
        restore(saved)
        if not test_ok then error(failure, 0) end
    end)

    H.test("CT #357 sends one fixed owner-targeted payload and clients cannot send", function()
        local ok, module, fake_mod, saved = load_isolated()
        local test_ok, failure = pcall(function()
            H.truthy(ok, tostring(module))
            H.truthy(module.install(7))
            local owner = {
                network_id = function() return "owner-peer" end,
                is_player_controlled = function() return true end,
            }
            _G.Managers = {
                player = {
                    is_server = true,
                    owner = function() return owner end,
                },
            }
            H.equal(module.notify_allowed("owner-unit", "boon_supportbomb_speed_01", 30), true)
            H.deep_equal(fake_mod.sent, {
                "ct_bomb_cooldown_display_v1", "owner-peer", 7,
                "boon_supportbomb_speed_01", 30,
            })

            fake_mod.sent = nil
            _G.Managers.player.is_server = false
            H.equal(module.notify_allowed("owner-unit", "boon_supportbomb_speed_01", 30), false)
            H.equal(fake_mod.sent, nil)
        end)
        restore(saved)
        if not test_ok then error(failure, 0) end
    end)

    H.test("CT #357 display follows the allowed gate without changing gameplay timing", function()
        local main = read(balance_path) .. read(main_path)
        local stamp = assert(main:find("buff._ct_last_bubble_t = t", 1, true))
        local notify = assert(main:find(
            "mod._ct_bomb_cooldown_display.notify_allowed(owner_unit, name, interval)",
            stamp, true))
        local vanilla = assert(main:find("return func(owner_unit, buff, params, ...)", notify, true))
        H.truthy(stamp < notify and notify < vanilla)
        H.truthy(main:find("if interval and interval > 0 and buff then", 1, true))

        local module_source = read(module_path)
        H.equal(module_source:find("NetworkLookup.buff_templates[", 1, true), nil)
        H.truthy(module_source:find("external_optional_duration = interval", 1, true))
        -- The runtime regression check moved to _ct_regression.lua (OOP W5 suite
        -- extraction); it is registered from there via mod._ct_rt_register.
        H.truthy(read(base .. "_ct_regression.lua"):find(
            "issue357_bomb_bubble_cooldown_display", 1, true))
    end)
end
