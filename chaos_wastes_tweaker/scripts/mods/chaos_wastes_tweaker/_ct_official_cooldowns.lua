-- Selected official #357/#358 cooldown integration.
-- Owned by chaos_wastes_tweaker.lua; installed once after effective settings exist.
-- The entry point keeps the single ProcFunctions hook registrations and dispatches
-- to these wrappers. Presentation never owns gameplay timing or NetworkLookup.
-- Donor: _ct_combat_hooks.lua Manann .349 state machine and
-- _ct_boon_balance.lua accepted support-bomb proc branch, Dev tree a179354e.
return function(mod, ctx)
    local effective_setting = assert(ctx.effective_setting)
    local schema = assert(ctx.rpc_schema)
    local display = mod._ct_bomb_cooldown_display or mod:dofile(
        "scripts/mods/chaos_wastes_tweaker/_ct_bomb_cooldown_display")
    mod._ct_bomb_cooldown_display = display
    display.install(schema)

    local MANANN_TEMPEST_COOLDOWN_S = 8.0
    local MAX_MANANN_GENERATION = 2147483647
    local MAX_DISPLAY_ERRORS = 4
    local manann_t = setmetatable({}, { __mode = "k" })
    local display_errors = 0
    local api = {}

    local function notify(owner_unit, name, interval, generation)
        local current = mod._ct_bomb_cooldown_display
        if not (current and type(current.notify_allowed) == "function") then return end
        local ok, err = pcall(current.notify_allowed, owner_unit, name, interval, generation)
        if not ok and display_errors < MAX_DISPLAY_ERRORS then
            display_errors = display_errors + 1
            if type(printf) == "function" then
                pcall(printf, "[ct:cooldown-display] notification failure (%d/%d): %s",
                    display_errors, MAX_DISPLAY_ERRORS, tostring(err))
            end
        end
    end

    -- _ct_consolidated_chain_lightning_cooldown_dispatch: called by the entry's
    -- existing table hook. A surviving unit keeps monotonic generations even if
    -- the game clock rewinds, while its old-clock authoritative deadlines reset.
    function api.chain_lightning(func, owner_unit, buff, params, world, param_order)
        local template = buff and buff.template
        local template_name = template and template.name
        local is_boon = type(template_name) == "string"
            and string.find(template_name, "^power_up_ct_boon_manann_tempest_") ~= nil
        local is_trait = template_name == "deus_crit_chain_lightning"
        if not (is_boon or is_trait)
            or not effective_setting("tweak_manann_tempest_cooldown") then
            return func(owner_unit, buff, params, world, param_order)
        end

        local hit_unit = params[param_order.attacked_unit]
        local first_hit = params[param_order.first_hit]
        local critical = params[param_order.is_critical_strike]
        if not (ALIVE[owner_unit] and ALIVE[hit_unit] and first_hit and critical) then
            return func(owner_unit, buff, params, world, param_order)
        end

        local t = (Managers and Managers.time and Managers.time:time("game")) or 0
        local bucket = manann_t[owner_unit]
        if not bucket then
            bucket = {
                boon_next_t = 0, trait_next_t = 0,
                boon_generation = 0, trait_generation = 0, last_game_t = t,
            }
            manann_t[owner_unit] = bucket
        end
        if t < (bucket.last_game_t or t) then
            bucket.boon_next_t = 0
            bucket.trait_next_t = 0
        end
        bucket.last_game_t = t
        local key = is_boon and "boon_next_t" or "trait_next_t"
        if t < bucket[key] then return end
        bucket[key] = t + MANANN_TEMPEST_COOLDOWN_S

        local generation_key = is_boon and "boon_generation" or "trait_generation"
        local generation
        if bucket[generation_key] < MAX_MANANN_GENERATION then
            bucket[generation_key] = bucket[generation_key] + 1
            generation = bucket[generation_key]
        end
        if generation then
            notify(owner_unit, is_boon and "manann_boon" or "manann_trait",
                MANANN_TEMPEST_COOLDOWN_S, generation)
        end
        return func(owner_unit, buff, params, world, param_order)
    end

    -- #357 requires the existing Dev #120 accepted support-bomb gate as its
    -- functional base. Public has no hook on this proc yet. The entry installs
    -- exactly one table hook and delegates here; rejected procs emit no receipt.
    function api.grenade_explode_buff_area(func, owner_unit, buff, params, ...)
        local interval = effective_setting("bomb_boon_cooldown")
        if interval and interval > 0 and buff then
            local t = Managers and Managers.time and Managers.time:time("game")
            if t then
                local name = buff.template and buff.template.name or "?"
                local last = buff._ct_last_bubble_t
                if last and (t - last) < interval then return end
                buff._ct_last_bubble_t = t
                notify(owner_unit, name, interval)
                pcall(printf, "[ct-bomb-boon] supportbomb '%s' proc allowed (min interval %ds)",
                    tostring(name), interval)
            end
        end
        return func(owner_unit, buff, params, ...)
    end

    function api.update(dt)
        local tick = mod._ct_manann_ready_tick
        if type(tick) == "function" then tick(dt) end
    end

    function api.on_disabled()
        return display.hide_manann_displays()
    end

    mod._ct_official_cooldowns = api
    if ctx.rt_register then
        ctx.rt_register("issue357_owner_cooldown_display", function()
            return display.regression_check(schema)
        end)
        ctx.rt_register("issue358_manann_tempest_cooldown_display", function()
            return display.regression_check_manann(schema)
        end)
    end
    return api
end
