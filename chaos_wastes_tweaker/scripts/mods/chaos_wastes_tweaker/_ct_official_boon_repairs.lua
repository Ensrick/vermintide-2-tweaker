-- Selective official boon repairs: #144, #288, #342 and #259.
-- Owner: official CT entry point. Hook-free: the entry's existing singleton
-- callbacks delegate here. No registration/catalog/pool changes are made.
-- Donor: ct_dev tree a179354e99d03879656a42eecdaadef15e3bb414:
-- _ct_meta_trait_boons.lua, _ct_boon_balance.lua, _ct_combat_hooks.lua.
return function(mod, ctx)
    local R = {}
    local effective_setting = assert(ctx.effective_setting, "effective setting reader required")
    local parry_policy = assert(ctx.parry_policy, "registered parry policy required")
    local anath_originals
    local add_receipts = 0
    local morgrim_receipts = 0

    local function pack(...)
        return { n = select("#", ...), ... }
    end

    -- #144: the native controller's update function can lose its perk after
    -- equip/wield churn. Reconcile that SAME native perk; no new buff identity.
    -- [src: morris_buff_settings.lua:1003-1009,3093; buff_extension.lua:794]
    function R.reconcile_vaul(unit, buff, params) -- luacheck: ignore params
        local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
        local inv_ext = ScriptUnit.has_extension(unit, "inventory_system")
        if not (buff_ext and inv_ext) then return end
        local perk_name = (buff.template and buff.template.buff_to_add) or "deus_always_blocking_buff"
        local equipment = inv_ext:equipment()
        local wielded = equipment and equipment.wielded and equipment.wielded.slot_type
        local melee = wielded == "melee"
        local locked = buff_ext:has_buff_type("deus_always_blocking_lock_out") and true or false
        local want = melee and not locked
        local has_perk = buff_ext:has_buff_type(perk_name) and true or false
        if want and not has_perk then
            buff.buff_id = buff_ext:add_buff(perk_name)
        elseif not want and has_perk then
            if buff.buff_id then buff_ext:remove_buff(buff.buff_id) end
            buff.buff_id = nil
        end
    end

    function R.register_vaul_reconciler()
        local bft = rawget(_G, "BuffFunctionTemplates")
        if not (bft and type(bft.functions) == "table") then return false end
        bft.functions.ct_vauls_anvil_reconcile = R.reconcile_vaul
        return true
    end

    -- Call only for ct_boon_vauls_anvil's detached cloned sub-buffs, before
    -- writing the existing power-up/runtime templates. Never modify the native
    -- always_blocking source. Missing function registry keeps the native update.
    function R.wire_vaul_clone(buffs)
        if not R.register_vaul_reconciler() then return false end
        local changed = false
        for _, sub in ipairs(buffs or {}) do
            if type(sub) == "table" and sub.buff_to_add == "deus_always_blocking_buff"
                and (sub.update_func == "always_blocking_update"
                    or sub.update_func == "ct_vauls_anvil_reconcile") then
                sub.update_func = "ct_vauls_anvil_reconcile"
                changed = true
            end
        end
        return changed
    end

    function R.anath_entries()
        local entries = {}
        local wt = rawget(_G, "WeaponTraits")
        if wt and wt.buff_templates and wt.buff_templates.deus_ammo_pickup_reload_speed then
            entries[#entries + 1] = { id = "weapon_traits", tbl = wt.buff_templates,
                key = "deus_ammo_pickup_reload_speed" }
        end
        local bt = rawget(_G, "BuffTemplates")
        if bt and bt.deus_ammo_pickup_reload_speed then
            entries[#entries + 1] = { id = "buff_templates", tbl = bt,
                key = "deus_ammo_pickup_reload_speed" }
        end
        return entries
    end

    -- #288: two registries may arrive on different frames and have distinct
    -- originals. Enforce every available entry on each native add-boundary retry.
    -- Negative reload_speed shortens hold time; no pickup event is retained.
    -- [src: buff_tweak_data.lua:225; weapon_unit_extension.lua:966;
    -- buff_extension.lua:1431-1432]
    function R.apply_anath()
        local entries = R.anath_entries()
        if #entries == 0 then return false end
        anath_originals = anath_originals or { templates = {} }
        local replacement = anath_originals.replacement
        if not replacement then
            replacement = { buffs = { {
                name = "deus_ammo_pickup_reload_speed_permanent",
                stat_buff = "reload_speed", multiplier = -0.5, max_stacks = 1,
            } } }
            anath_originals.replacement = replacement
        end
        for _, entry in ipairs(entries) do
            if not anath_originals.templates[entry.id] then
                local original = entry.tbl[entry.key]
                if original == replacement then
                    original = anath_originals.templates.weapon_traits
                        or anath_originals.templates.buff_templates
                end
                if original and original ~= replacement then
                    anath_originals.templates[entry.id] = original
                end
            end
            entry.tbl[entry.key] = replacement
        end
        if mod._ct_apply_evidence then mod._ct_apply_evidence.call("anath_registry", "registry applied/read back") end
        return true
    end

    function R.revert_anath()
        if not anath_originals then return end
        for _, entry in ipairs(R.anath_entries()) do
            entry.tbl[entry.key] = anath_originals.templates[entry.id] or entry.tbl[entry.key]
        end
        anath_originals = nil
        if mod._ct_apply_evidence then mod._ct_apply_evidence.call("anath_registry", "registry restored/read back") end
    end

    function R.sync_anath()
        if effective_setting("tweak_anath_raema_permanent") then
            return R.apply_anath()
        end
        return R.revert_anath()
    end

    function R.before_add_buff(template_name)
        if template_name ~= "deus_ammo_pickup_reload_speed"
            or not effective_setting("tweak_anath_raema_permanent") then return end
        R.apply_anath()
        if add_receipts < 8 then
            add_receipts = add_receipts + 1
            local bt = rawget(_G, "BuffTemplates")
            local sub = bt and bt[template_name] and bt[template_name].buffs
                and bt[template_name].buffs[1]
            pcall(printf, "[ct:288] add parent=%s child=%s stat=%s mult=%s event=%s n=%d",
                tostring(template_name), tostring(sub and sub.name), tostring(sub and sub.stat_buff),
                tostring(sub and sub.multiplier), tostring(sub and sub.event), add_receipts)
        end
    end

    function R.strip_parry()
        local runtime_buffs = rawget(_G, "BuffTemplates")
        local registered = rawget(_G, "DeusPowerUps")
        if not (runtime_buffs and registered) then return false end
        return parry_policy.strip(runtime_buffs, registered)
    end

    -- #259 transaction core. Capture the complete tuple including nil holes;
    -- restore exact raw instance fields before rethrowing the original error.
    local function morgrim_transaction(func, projectile_context, ...)
        local buff_ext = projectile_context.buff_extension
        local saved_apply = rawget(buff_ext, "apply_buffs_to_value")
        local saved_perk = rawget(buff_ext, "has_buff_perk")
        local original_apply = buff_ext.apply_buffs_to_value
        local original_perk = buff_ext.has_buff_perk
        buff_ext.apply_buffs_to_value = function(self, value, stat_name, ...)
            if stat_name == "not_consume_grenade" then return value, false end
            return original_apply(self, value, stat_name, ...)
        end
        buff_ext.has_buff_perk = function(self, perk_name, ...)
            if perk_name == "free_grenade"
                and not original_perk(self, "rewield_grenade_on_throw") then return false end
            return original_perk(self, perk_name, ...)
        end
        local result = pack(pcall(func, projectile_context, ...))
        buff_ext.apply_buffs_to_value = saved_apply
        buff_ext.has_buff_perk = saved_perk
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
    end

    function R.fire_charged_projectile(func, projectile_context, ...)
        if not effective_setting("rv_no_save_morgrim")
            or not projectile_context or projectile_context.item_name ~= "holy_hand_grenade"
            or not projectile_context.is_grenade or projectile_context.grenade_thrown then
            return func(projectile_context, ...)
        end
        local buff_ext = projectile_context.buff_extension
        if not (buff_ext and type(buff_ext.apply_buffs_to_value) == "function"
            and type(buff_ext.has_buff_perk) == "function") then
            return func(projectile_context, ...)
        end
        local result = pack(morgrim_transaction(func, projectile_context, ...))
        if morgrim_receipts < 24 then
            morgrim_receipts = morgrim_receipts + 1
            local perk_ok, endless = pcall(buff_ext.has_buff_perk, buff_ext, "rewield_grenade_on_throw")
            pcall(printf, "[ct:morgrim259] saved=%s endless_bombs=%s n=%d",
                tostring(projectile_context.free_grenade == true),
                tostring(perk_ok and endless and true or false), morgrim_receipts)
        end
        return unpack(result, 1, result.n)
    end

    function R.register_regressions(register)
        register("vauls_anvil_reconciler_144", function()
            local bft = rawget(_G, "BuffFunctionTemplates")
            if not (bft and bft.functions) then return "skip: buff function registry unavailable" end
            if bft.functions.ct_vauls_anvil_reconcile ~= R.reconcile_vaul then
                return "#144 registered reconciler missing or replaced"
            end
            local templates = rawget(_G, "DeusPowerUpTemplates")
            local template = templates and templates.ct_boon_vauls_anvil
            local buffs = template and template.buff_template and template.buff_template.buffs
            if not buffs then return "skip: Vaul controller clone not registered yet" end
            for _, sub in ipairs(buffs) do
                if sub.buff_to_add == "deus_always_blocking_buff" then
                    if sub.update_func ~= "ct_vauls_anvil_reconcile" then
                        return "#144 clone still uses native non-reconciling update"
                    end
                    return
                end
            end
            return "#144 controller clone has no native perk child"
        end)
        register("anath_raema_registry_retry_288", function()
            if not effective_setting("tweak_anath_raema_permanent") then return end
            R.apply_anath()
            local entries = R.anath_entries()
            if #entries ~= 2 then return "skip: both reload registries are keep-only" end
            if not (anath_originals and anath_originals.templates.weapon_traits
                and anath_originals.templates.buff_templates) then
                return "#288 independent registry originals missing"
            end
            for _, entry in ipairs(entries) do
                local sub = entry.tbl[entry.key].buffs and entry.tbl[entry.key].buffs[1]
                if not (sub and sub.stat_buff == "reload_speed" and sub.multiplier == -0.5
                    and sub.event == nil) then return "#288 permanent reload template mismatch" end
            end
        end)
        register("parry_cooldowns_registered_342", function()
            return parry_policy.residual_report(rawget(_G, "BuffTemplates"), rawget(_G, "DeusPowerUps"))
        end)
        register("morgrim_exact_restore_259", function()
            -- Isolated objects only: exercise the production transaction without
            -- mutating live settings, globals, templates, or player extensions.
            for _, inherited in ipairs({ false, true }) do
                local original_apply = function(_, value) return value, true end
                local original_perk = function(_, name) return name == "free_grenade" end
                local methods = { apply_buffs_to_value = original_apply, has_buff_perk = original_perk }
                local ext = inherited and setmetatable({}, { __index = methods }) or methods
                local context = { buff_extension = ext }
                local result = pack(morgrim_transaction(function(c)
                    local value, kept = c.buff_extension:apply_buffs_to_value(0, "not_consume_grenade")
                    assert(value == 0 and kept == false and not c.buff_extension:has_buff_perk("free_grenade"))
                    return "first", nil, "third", nil
                end, context))
                if result.n ~= 4 or result[1] ~= "first" or result[2] ~= nil
                    or result[3] ~= "third" or result[4] ~= nil then return "#259 return tuple collapsed" end
                local raw_apply, raw_perk
                if not inherited then raw_apply, raw_perk = original_apply, original_perk end
                if rawget(ext, "apply_buffs_to_value") ~= raw_apply
                    or rawget(ext, "has_buff_perk") ~= raw_perk then return "#259 success restore mismatch" end
                local token = {}
                local ok, err = pcall(morgrim_transaction, function() error(token) end, context)
                if ok or err ~= token or rawget(ext, "apply_buffs_to_value") ~= raw_apply
                    or rawget(ext, "has_buff_perk") ~= raw_perk then return "#259 error restore mismatch" end
            end
        end)
    end

    mod._ct_official_boon_repairs = R
    mod._ct_vauls_anvil_reconcile = R.reconcile_vaul
    mod._ct128_strip_parry_cooldowns = R.strip_parry
    mod._ct342_parry_cooldown_policy = parry_policy
    R.register_vaul_reconciler()
    if ctx.rt_register then R.register_regressions(ctx.rt_register) end
    return R
end
