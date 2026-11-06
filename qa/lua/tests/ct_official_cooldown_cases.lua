-- Loaded only by test_ct_official_verify_rollup.lua. Every production load is
-- delegated to that harness's path-proven overlay loader, never source slicing.
return function(H, load_production)
    local prefix = "chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/"
    local function pack(...)
        return { n = select("#", ...), ... }
    end
    local function fixture()
        local w = { now = 0, settings = {
            tweak_manann_tempest_cooldown = true, bomb_boon_cooldown = 10,
        }, sends = {}, callbacks = {}, checks = {}, logs = {}, buffs = {}, next_id = 1 }
        w.unit, w.hit = {}, {}
        w.owner = { player_unit = w.unit, local_player = true,
            network_id = function() return "owner-peer" end,
            is_player_controlled = function() return true end }
        local ext = {}
        function ext:has_buff_type(name) return w.buffs[name] ~= nil end
        function ext:get_buff_type(name) return w.buffs[name] end
        function ext:remove_buff(id)
            for name, b in pairs(w.buffs) do
                if b.id == id then w.buffs[name] = nil; return 1 end
            end
            return 0
        end
        function ext:add_buff(name, params)
            local id = w.next_id
            w.next_id = id + 1
            w.buffs[name] = { id = id, buff_type = name,
                duration = params and params.external_optional_duration }
            return id
        end
        function ext:active_buffs()
            local list = {}
            for _, buff in pairs(w.buffs) do list[#list + 1] = buff end
            return list, #list
        end
        w.ext = ext
        local mod = {}
        function mod:get(id) return w.settings[id] end
        mod._ct_effective_setting = function(id) return w.settings[id] end
        function mod:network_register(name, callback) w.callbacks[name] = callback end
        function mod:network_send(...) w.sends[#w.sends + 1] = pack(...) end
        local env = setmetatable({
            BuffTemplates = {}, NetworkLookup = { buff_templates = {} },
            ALIVE = { [w.unit] = true, [w.hit] = true },
            printf = function(fmt, ...) w.logs[#w.logs + 1] = string.format(fmt, ...) end,
            get_mod = function(id) assert(id == "ct"); return mod end,
            ScriptUnit = { has_extension = function(unit)
                if unit == w.unit then return ext end
            end },
        }, { __index = _G })
        env._G = env
        env.Managers = {
            time = { time = function() return w.now end },
            mechanism = { server_peer_id = function() return "host-peer" end },
            player = { is_server = true,
                owner = function(_, unit) if unit == w.unit then return w.owner end end,
                local_player_safe = function() return w.owner end },
        }
        function mod:dofile(path)
            local module, actual = load_production("chaos_wastes_tweaker/" .. path .. ".lua", env)
            assert(actual:gsub("\\", "/"):find("/chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/", 1, true), actual)
            return module
        end
        local installer, actual = load_production(prefix .. "_ct_official_cooldowns.lua", env)
        assert(actual:gsub("\\", "/"):find("/chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/", 1, true), actual)
        w.api = installer(mod, { effective_setting = mod._ct_effective_setting, rpc_schema = 2,
            rt_register = function(name, check) w.checks[name] = check end })
        w.mod, w.env, w.display = mod, env, mod._ct_bomb_cooldown_display
        w.order = { attacked_unit = 1, first_hit = 2, is_critical_strike = 3 }
        w.params = { w.hit, true, true }
        return w
    end

    H.test("CT official cooldown wrappers preserve pass-through tuples and separate accepted buckets", function()
        local w = fixture()
        local calls = 0
        local native = function(owner, buff, params, world, order)
            calls = calls + 1
            assert(owner == w.unit and params == w.params and order == w.order)
            return "first", nil, "third", nil
        end
        local trait = { template = { name = "deus_crit_chain_lightning" } }
        local boon = { template = { name = "power_up_ct_boon_manann_tempest_unique" } }
        local got = pack(w.api.chain_lightning(native, w.unit, trait, w.params, nil, w.order))
        assert(got.n == 4 and got[1] == "first" and got[2] == nil and got[3] == "third")
        assert(w.display.generation_for(w.unit, "manann_trait") == 1)
        assert(w.display.deadline_for(w.unit, "manann_trait") == 8)
        w.now = 1
        assert(pack(w.api.chain_lightning(native, w.unit, trait, w.params, nil, w.order)).n == 0)
        assert(calls == 1 and w.display.deadline_for(w.unit, "manann_trait") == 8)
        w.api.chain_lightning(native, w.unit, boon, w.params, nil, w.order)
        assert(calls == 2 and w.display.generation_for(w.unit, "manann_boon") == 1)
        w.now = 9
        w.api.chain_lightning(native, w.unit, trait, w.params, nil, w.order)
        assert(w.display.generation_for(w.unit, "manann_trait") == 2)
        w.now = 0.1
        w.api.chain_lightning(native, w.unit, trait, w.params, nil, w.order)
        assert(calls == 4 and w.display.generation_for(w.unit, "manann_trait") == 3)
        assert(w.display.deadline_for(w.unit, "manann_trait") == 8.1)
        w.settings.tweak_manann_tempest_cooldown = false
        got = pack(w.api.chain_lightning(native, w.unit, trait, w.params, nil, w.order))
        assert(got.n == 4 and calls == 5)
        w.settings.tweak_manann_tempest_cooldown = true
        w.params[3] = false
        w.api.chain_lightning(native, w.unit, trait, w.params, nil, w.order)
        assert(calls == 6 and w.display.generation_for(w.unit, "manann_trait") == 3)
    end)

    H.test("CT official accepted bomb gate stamps once and preserves nilable args and returns", function()
        local w = fixture()
        w.owner.local_player = false
        local buff = { template = { name = "boon_supportbomb_crit_01" } }
        local calls = 0
        local native = function(owner, actual_buff, params, ...)
            calls = calls + 1
            local args = pack(...)
            assert(owner == w.unit and actual_buff == buff and args.n == 3)
            assert(args[1] == "a" and args[2] == nil and args[3] == "c")
            return nil, "two", nil, "four"
        end
        local got = pack(w.api.grenade_explode_buff_area(native, w.unit, buff, {}, "a", nil, "c"))
        assert(got.n == 4 and got[2] == "two" and got[4] == "four")
        assert(buff._ct_last_bubble_t == 0 and #w.sends == 1)
        assert(w.sends[1].n == 5 and w.sends[1][2] == "owner-peer" and w.sends[1][3] == 2)
        w.now = 1
        assert(pack(w.api.grenade_explode_buff_area(native, w.unit, buff, {}, "a", nil, "c")).n == 0)
        assert(calls == 1 and #w.sends == 1 and buff._ct_last_bubble_t == 0)
        w.now = 10
        w.api.grenade_explode_buff_area(native, w.unit, buff, {}, "a", nil, "c")
        assert(calls == 2 and #w.sends == 2 and buff._ct_last_bubble_t == 10)
        w.settings.bomb_boon_cooldown = 0
        w.now = 11
        w.api.grenade_explode_buff_area(native, w.unit, buff, {}, "a", nil, "c")
        assert(calls == 3 and #w.sends == 2 and buff._ct_last_bubble_t == 10)
    end)

    H.test("CT official cooldown presentation faults cannot suppress an allowed native proc", function()
        local w = fixture()
        w.mod._ct_bomb_cooldown_display = { notify_allowed = function() error("HUD churn") end }
        local buff = { template = { name = "deus_crit_chain_lightning" } }
        local calls = 0
        for i = 1, 8 do
            w.now = i * 9
            local got = pack(w.api.chain_lightning(function()
                calls = calls + 1; return 1, nil, 3
            end, w.unit, buff, w.params, nil, w.order))
            assert(got.n == 3 and got[3] == 3)
        end
        assert(calls == 8 and #w.logs == 4)
    end)

    H.test("CT official display channel rejects forged schema payload and stale generations", function()
        local w = fixture()
        local receive = assert(w.callbacks.ct_bomb_cooldown_display_v1)
        for _, args in ipairs({
            { "foreign", 2, "manann_trait", 8, 1 },
            { "host-peer", 1, "manann_trait", 8, 1 },
            { "host-peer", 2, "foreign", 8, 1 },
            { "host-peer", 2, "manann_trait", 8, 0 },
            { "host-peer", 2, "manann_trait", 8, 1.5 },
            { "host-peer", 2, "manann_trait", 8, 2147483648 },
            { "host-peer", 2, "manann_trait", 0, 1 },
        }) do receive(unpack(args, 1, 5)) end
        assert(w.display.generation_for(w.unit, "manann_trait") == nil)
        receive("host-peer", 2, "manann_trait", 8, 1)
        assert(w.display.deadline_for(w.unit, "manann_trait") == 8)
        w.now = 7
        receive("host-peer", 2, "manann_trait", 8, 2)
        assert(w.display.deadline_for(w.unit, "manann_trait") == 15)
        w.now = 8
        receive("host-peer", 2, "manann_trait", 8, 2)
        receive("host-peer", 2, "manann_trait", 8, 1)
        assert(w.display.deadline_for(w.unit, "manann_trait") == 15)
        w.buffs.deus_crit_chain_lightning = { id = 999, buff_type = "deus_crit_chain_lightning" }
        w.now = 16
        assert(w.display.reconcile_manann_ready())
        assert(w.display.deadline_for(w.unit, "manann_trait") == nil)
        receive("host-peer", 2, "manann_trait", 8, 2)
        assert(w.display.deadline_for(w.unit, "manann_trait") == nil)
        assert(w.display.generation_for(w.unit, "manann_trait") == 2)
        assert(w.buffs.ct_manann_ready_display_trait)
    end)

    H.test("CT official Manann hide reacquire and ticker keep semantic deadline without lookup rows", function()
        local w = fixture()
        w.buffs.deus_crit_chain_lightning = { id = 999, buff_type = "deus_crit_chain_lightning" }
        w.api.update(0.5)
        assert(w.buffs.ct_manann_ready_display_trait)
        assert(w.display.notify_allowed(w.unit, "manann_trait", 8, 1))
        assert(w.buffs.ct_manann_cooldown_display_trait and not w.buffs.ct_manann_ready_display_trait)
        assert(w.api.on_disabled())
        assert(not w.buffs.ct_manann_cooldown_display_trait)
        assert(w.display.deadline_for(w.unit, "manann_trait") == 8)
        w.now = 3
        w.api.update(0.5)
        assert(w.buffs.ct_manann_cooldown_display_trait.duration == 5)
        w.settings.tweak_manann_tempest_cooldown = false
        w.api.update(0.5)
        assert(not w.buffs.ct_manann_cooldown_display_trait)
        w.settings.tweak_manann_tempest_cooldown = true
        w.now = 4
        w.api.update(0.5)
        assert(w.buffs.ct_manann_cooldown_display_trait.duration == 4)
        w.buffs.deus_crit_chain_lightning = nil
        w.api.update(0.5)
        assert(not w.buffs.ct_manann_cooldown_display_trait)
        assert(next(w.env.NetworkLookup.buff_templates) == nil)
        assert(w.checks.issue357_owner_cooldown_display() == nil)
        assert(w.checks.issue358_manann_tempest_cooldown_display() == nil)
    end)
end
