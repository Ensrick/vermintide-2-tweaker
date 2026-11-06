-- Non-discovered fragment consumed by test_ct_official_verify_rollup.lua.
-- The loader must execute these actual production overlay paths, never copies
-- embedded in this test or the live repository's unchanged implementation.
return function(H, load_production)
    local prefix = "chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/"
    local function pack(...) return { n = select("#", ...), ... } end
    local function fixture(values, additions)
        local env = setmetatable(additions or {}, { __index = _G })
        env._G = env
        env.printf = function() end
        local installer, actual = load_production(prefix .. "_ct_official_boon_repairs.lua", env)
        assert(type(actual) == "string" and actual:gsub("\\", "/"):find("/chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/", 1, true))
        local policy, policy_actual = load_production(prefix .. "_ct_parry_cooldown_policy.lua", env)
        assert(policy_actual:gsub("\\", "/"):find("/chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/", 1, true))
        local mod = {}
        local registrations = {}
        local repairs = installer(mod, {
            effective_setting = function(id) return values[id] end,
            parry_policy = policy,
            rt_register = function(name, callback) registrations[name] = callback end,
        })
        return repairs, env, mod, registrations
    end

    H.test("CT144 cloned Vaul callback reconciles melee and lockout without source mutation", function()
        local values = {}
        local present, locked, wielded, adds, removes = false, false, "melee", 0, 0
        local ext = {
            has_buff_type = function(_, name)
                if name == "deus_always_blocking_lock_out" then return locked end
                return present
            end,
            add_buff = function(_, name)
                assert(name == "deus_always_blocking_buff")
                adds, present = adds + 1, true
                return adds
            end,
            remove_buff = function(_, id)
                assert(type(id) == "number")
                removes, present = removes + 1, false
            end,
        }
        local inventory = { equipment = function() return { wielded = { slot_type = wielded } } end }
        local repairs, env = fixture(values, {
            BuffFunctionTemplates = { functions = {} },
            ScriptUnit = { has_extension = function(_, system)
                if system == "buff_system" then return ext end
                if system == "inventory_system" then return inventory end
            end },
        })
        local source = { buff_to_add = "deus_always_blocking_buff", update_func = "always_blocking_update" }
        local clone = { buff_to_add = source.buff_to_add, update_func = source.update_func }
        assert(repairs.wire_vaul_clone({ clone }))
        assert(source.update_func == "always_blocking_update")
        local callback = env.BuffFunctionTemplates.functions[clone.update_func]
        assert(callback == repairs.reconcile_vaul)
        local buff = { template = clone }
        callback("unit", buff)
        callback("unit", buff)
        assert(present and adds == 1 and removes == 0)
        wielded = "ranged"
        callback("unit", buff)
        assert(not present and removes == 1 and buff.buff_id == nil)
        wielded, locked = "melee", true
        callback("unit", buff)
        assert(not present and adds == 1)
        locked = false
        callback("unit", buff)
        assert(present and adds == 2)
        locked = true
        callback("unit", buff)
        assert(not present and removes == 2)
        env.ScriptUnit.has_extension = function() return nil end
        callback("unit", buff)
        assert(adds == 2 and removes == 2)
    end)

    H.test("CT144 missing function registry never leaves clone naming an absent callback", function()
        local repairs = fixture({}, { BuffFunctionTemplates = false })
        local clone = { buff_to_add = "deus_always_blocking_buff", update_func = "always_blocking_update" }
        assert(repairs.wire_vaul_clone({ clone }) == false)
        assert(clone.update_func == "always_blocking_update")
    end)

    H.test("CT288 add boundary retries late registry and restores distinct original objects", function()
        local values = { tweak_anath_raema_permanent = true }
        local first, second = { source = "trait" }, { source = "runtime" }
        local repairs, env = fixture(values, {
            WeaponTraits = { buff_templates = { deus_ammo_pickup_reload_speed = first } },
            BuffTemplates = {},
        })
        repairs.sync_anath()
        local replacement = env.WeaponTraits.buff_templates.deus_ammo_pickup_reload_speed
        local sub = replacement.buffs[1]
        assert(sub.multiplier == -0.5 and sub.stat_buff == "reload_speed" and sub.event == nil)
        env.BuffTemplates.deus_ammo_pickup_reload_speed = second
        repairs.before_add_buff("unrelated_buff")
        assert(env.BuffTemplates.deus_ammo_pickup_reload_speed == second)
        repairs.before_add_buff("deus_ammo_pickup_reload_speed")
        assert(env.BuffTemplates.deus_ammo_pickup_reload_speed == replacement)
        repairs.before_add_buff("deus_ammo_pickup_reload_speed")
        values.tweak_anath_raema_permanent = false
        repairs.sync_anath()
        assert(env.WeaponTraits.buff_templates.deus_ammo_pickup_reload_speed == first)
        assert(env.BuffTemplates.deus_ammo_pickup_reload_speed == second)
    end)

    H.test("CT288 late registry derived from patched earlier registry never preserves replacement as original", function()
        local original = { source = "shared native" }
        local repairs, env = fixture({ tweak_anath_raema_permanent = true }, {
            WeaponTraits = { buff_templates = { deus_ammo_pickup_reload_speed = original } }, BuffTemplates = {},
        })
        repairs.apply_anath()
        env.BuffTemplates.deus_ammo_pickup_reload_speed = env.WeaponTraits.buff_templates.deus_ammo_pickup_reload_speed
        repairs.before_add_buff("deus_ammo_pickup_reload_speed")
        repairs.revert_anath()
        assert(env.WeaponTraits.buff_templates.deus_ammo_pickup_reload_speed == original)
        assert(env.BuffTemplates.deus_ammo_pickup_reload_speed == original)
    end)

    H.test("CT342 production strip follows registered rarities and retains native cooldown references", function()
        local proc = { cooldown_buff = "native_cd" }
        local native_cd = { duration = 8 }
        local skulls_cd = { duration = 10 }
        local repairs, env, mod, registrations = fixture({}, {
            BuffTemplates = {
                arbitrary_runtime_key = { buffs = { proc } },
                native_cd = { buffs = { native_cd } },
                boon_skulls_03_cooldown = { buffs = { skulls_cd } },
            },
            DeusPowerUps = { modded_rarity = { static_blade = { buff_name = "arbitrary_runtime_key" } } },
        })
        assert(mod._ct128_strip_parry_cooldowns == repairs.strip_parry)
        assert(repairs.strip_parry())
        assert(proc.cooldown_buff == "native_cd" and native_cd.duration == 0 and skulls_cd.duration == 0)
        assert(registrations.parry_cooldowns_registered_342() == nil)
        env.BuffTemplates.native_cd = nil
        local ok = repairs.strip_parry()
        assert(ok == false and type(registrations.parry_cooldowns_registered_342()) == "string")
    end)

    H.test("CT259 Morgrim wrapper restores explicit and inherited methods and every nil-hole return", function()
        for _, explicit_apply in ipairs({ false, true }) do
            for _, explicit_perk in ipairs({ false, true }) do
                for _, endless in ipairs({ false, true }) do
                    local apply = function(_, value, name, marker)
                        assert(name == "other_stat" and marker == "marker")
                        return value + 1, nil, "native-tail"
                    end
                    local perk = function(_, name, marker)
                        if name == "rewield_grenade_on_throw" then return endless end
                        if name == "free_grenade" then return true end
                        assert(name == "other_perk" and marker == "marker")
                        return "perk-first", nil, "perk-tail"
                    end
                    local methods = { apply_buffs_to_value = apply, has_buff_perk = perk }
                    local ext = setmetatable({}, { __index = methods })
                    if explicit_apply then ext.apply_buffs_to_value = apply end
                    if explicit_perk then ext.has_buff_perk = perk end
                    local raw_apply, raw_perk = rawget(ext, "apply_buffs_to_value"), rawget(ext, "has_buff_perk")
                    local repairs = fixture({ rv_no_save_morgrim = true })
                    local context = { item_name = "holy_hand_grenade", is_grenade = true, buff_extension = ext }
                    local result = pack(repairs.fire_charged_projectile(function(c, ...)
                        local args = pack(...)
                        assert(args.n == 4 and args[1] == "arg-first" and args[2] == nil and args[3] == "arg-third")
                        local denied = pack(c.buff_extension:apply_buffs_to_value(0, "not_consume_grenade"))
                        assert(denied.n == 2 and denied[1] == 0 and denied[2] == false)
                        assert(c.buff_extension:has_buff_perk("free_grenade") == endless)
                        local forwarded = pack(c.buff_extension:apply_buffs_to_value(4, "other_stat", "marker"))
                        assert(forwarded.n == 3 and forwarded[1] == 5 and forwarded[2] == nil and forwarded[3] == "native-tail")
                        forwarded = pack(c.buff_extension:has_buff_perk("other_perk", "marker"))
                        assert(forwarded.n == 3 and forwarded[1] == "perk-first" and forwarded[3] == "perk-tail")
                        return "first", nil, "third", nil
                    end, context, "arg-first", nil, "arg-third", nil))
                    assert(result.n == 4 and result[1] == "first" and result[2] == nil and result[3] == "third" and result[4] == nil)
                    assert(rawget(ext, "apply_buffs_to_value") == raw_apply and rawget(ext, "has_buff_perk") == raw_perk)
                    local token = {}
                    local ok, err = pcall(repairs.fire_charged_projectile, function(c)
                        assert(c.buff_extension:has_buff_perk("free_grenade") == endless)
                        error(token)
                    end, context)
                    assert(not ok and err == token)
                    assert(rawget(ext, "apply_buffs_to_value") == raw_apply and rawget(ext, "has_buff_perk") == raw_perk)
                end
            end
        end
    end)

    H.test("CT259 nonmatching contexts and disabled setting are exact native pass-throughs", function()
        local settings = { rv_no_save_morgrim = false }
        local repairs = fixture(settings)
        local ext = { apply_buffs_to_value = function() end, has_buff_perk = function() end }
        local contexts = {
            { item_name = "holy_hand_grenade", is_grenade = true, buff_extension = ext },
            { item_name = "frag_grenade", is_grenade = true, buff_extension = ext },
            { item_name = "holy_hand_grenade", is_grenade = false, buff_extension = ext },
            { item_name = "holy_hand_grenade", is_grenade = true, grenade_thrown = true, buff_extension = ext },
        }
        for i, context in ipairs(contexts) do
            if i > 1 then settings.rv_no_save_morgrim = true end
            local old_apply, old_perk = ext.apply_buffs_to_value, ext.has_buff_perk
            local result = pack(repairs.fire_charged_projectile(function(c)
                assert(c == context and ext.apply_buffs_to_value == old_apply and ext.has_buff_perk == old_perk)
                return nil, "second", nil
            end, context))
            assert(result.n == 3 and result[1] == nil and result[2] == "second" and result[3] == nil)
        end
    end)

    H.test("CT259 named regression exercises production transaction with isolated state", function()
        local _, _, _, registrations = fixture({})
        assert(registrations.morgrim_exact_restore_259() == nil)
    end)
end
