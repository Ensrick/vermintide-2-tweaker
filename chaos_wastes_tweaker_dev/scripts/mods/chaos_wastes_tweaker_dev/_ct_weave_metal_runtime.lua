-- _ct_weave_metal_runtime.lua -- host-owned Metal wind curse adapter (#253).
-- Default-off, chat-command gated, hidden from the curse menu.
--
-- First bounded slice of "Weave winds as Chaos Wastes curses" (design:
-- WEAVE_CURSE_FEASIBILITY_253.md, "Metal first"). Three seams, all singletons:
--
-- 1. (MutatorHandler, init) pre-hook. GameModeManager builds one handler per
--    mission from the game mode's composed list [src: game_mode_manager.lua:85-99];
--    the host handler initializes and activates every entry
--    [src: mutator_handler.lua:27-48,102-111], activation sends
--    rpc_activate_mutator_client keyed by NetworkLookup.mutator_templates
--    [src: mutator_handler.lua:697-702], the initialized map is shared state
--    [src: mutator_handler.lua:95-99], and hot join replays every active mutator
--    [src: mutator_handler.lua:148-170; game_mode_manager.lua:920]. Appending
--    `metal` to a COPY of that list before init therefore keeps vanilla transport
--    authoritative: no CT RPC, lookup entry, package load or setting transport.
--    Host-only, Deus-mechanism-only [src: game_mechanism_manager.lua:666].
-- 2. Table-form hook on the WRAPPED MutatorTemplates.metal.server.start_function,
--    the form the handler calls [src: mutator_handler.lua:678-682]. While a CT
--    level context is armed the vanilla body is not called, so the template's
--    only global Weave-manager read [src: mutator_metal.lua:58-63] never runs in
--    Chaos Wastes; its two writes (data.wind_strength, data.buff_system) are
--    supplied from the explicit CT context instead. The global Weave manager is
--    never read, replaced or stubbed here (a textual invariant enforces the
--    absence). The skipped default server-start wrapper only handles
--    template.remove_pickups [src: mutator_templates.lua:107-132,260-268], which
--    Metal does not declare (the regression check asserts it). Outside a CT level
--    (real Weaves) vanilla runs untouched.
-- 3. (MutatorHandler, destroy) safe hook. Armor is applied by the wrapped
--    initialize/start defaults and restored exactly by the wrapped stop default
--    [src: mutator_templates.lua:36-73,134-138,246-250], which destroy drives for
--    every active mutator [src: mutator_handler.lua:60-83,705-746]. The adapter
--    snapshots the eleven breeds' primary_armor_category before init and proves
--    restoration after destroy, then drops its per-level context.
--
-- Metal stores wind_strength but never reads it [src: mutator_metal.lua:61 is the
-- sole reference], so the strength knob is carried for Weave-contract parity.
-- The node curse, graph, map, curse panel and reward contracts are untouched;
-- Metal here is an extra mission mutator, not a counted curse.
--
-- Owned by: chaos_wastes_tweaker_dev.lua entry point. Consumed via: one
-- mod:dofile installer call `({ mod = mod })`; guarded by
-- qa/lua/tests/test_ct_weave_metal_runtime_owner.lua and the
-- /ct_regression_test check `issue253_metal_wind_adapter`.
return function(ctx)
    assert(type(ctx) == "table", "CT weave metal runtime requires context")
    local mod = assert(ctx.mod, "CT weave metal runtime requires mod")
    local Policy = ctx.policy or (type(mod.dofile) == "function"
        and mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_weave_metal_policy"))
    assert(type(Policy) == "table", "CT weave metal runtime requires policy")

    -- Engine seams default to the live game; tests inject doubles.
    local function managers()
        return rawget(_G, "Managers")
    end
    local templates = ctx.templates or function()
        return rawget(_G, "MutatorTemplates")
    end
    local breeds = ctx.breeds or function()
        return rawget(_G, "Breeds")
    end
    local lookup = ctx.lookup or function()
        local network_lookup = rawget(_G, "NetworkLookup")
        return type(network_lookup) == "table" and network_lookup.mutator_templates or nil
    end
    local mechanism_name = ctx.mechanism_name or function()
        local live = managers()
        local mechanism = live and live.mechanism
        if type(mechanism) ~= "table" or type(mechanism.current_mechanism_name) ~= "function" then
            return nil
        end
        local ok, name = pcall(mechanism.current_mechanism_name, mechanism)
        return ok and name or nil
    end
    local is_server = ctx.is_server or function()
        local live = managers()
        return (live and live.player and live.player.is_server) == true
    end
    local buff_system = ctx.buff_system or function()
        local live = managers()
        local entity = live and live.state and live.state.entity
        if type(entity) ~= "table" or type(entity.system) ~= "function" then return nil end
        local ok, system = pcall(entity.system, entity, "buff_system")
        return ok and system or nil
    end
    local get_setting = ctx.get_setting or function(id)
        local ok, value = pcall(mod.get, mod, id)
        if ok then return value end
        return nil
    end
    local set_setting = ctx.set_setting or function(id, value)
        pcall(mod.set, mod, id, value)
    end
    local log = ctx.log or function(fmt, ...)
        pcall(printf, fmt, ...)
    end

    -- Idempotent: a second install never registers a second hook.
    if mod._ct_weave_metal_state then
        return mod._ct_weave_metal_state
    end

    local state = {
        installed = true,
        command = Policy.COMMAND,
        hook_pairs = {
            "MutatorHandler.init",
            "MutatorHandler.destroy",
            "MutatorTemplates.metal.server.start_function",
        },
        enabled = Policy.DEFAULT_ENABLED,
        enabled_at_boot = Policy.DEFAULT_ENABLED,
        exposed_in_menu = Policy.EXPOSED_IN_MENU,
        strength = Policy.effective_strength(get_setting(Policy.STRENGTH_SETTING)),
        bridged = false,
        level = nil,
        activations = 0,
        starts = 0,
        teardowns = 0,
        restored_ok = 0,
        restored_bad = 0,
        skipped = {},
        errors = 0,
        last_error = nil,
        ERROR_CAP = 4,
        log_rows = 0,
        LOG_CAP = 16,
        last = nil,
    }
    mod._ct_weave_metal_state = state

    local function bounded_log(fmt, ...)
        if state.log_rows >= state.LOG_CAP then return end
        state.log_rows = state.log_rows + 1
        log(fmt, ...)
    end

    local function record_error(kind, err)
        state.errors = state.errors + 1
        state.last_error = tostring(err)
        if state.errors <= state.ERROR_CAP then
            log("[ct:253:metal] %s %d/%d err=%s", kind, state.errors, state.ERROR_CAP, tostring(err))
        end
    end

    local function metal_template()
        local catalog = templates()
        local template = type(catalog) == "table" and catalog[Policy.MUTATOR] or nil
        return type(template) == "table" and template or nil
    end

    -- hook-test: issue253_metal_wind_adapter
    -- _ct_consolidated_metal_server_start_hook (singleton on this server table).
    local function ensure_bridge()
        if state.bridged then return true end
        local template = metal_template()
        local metal_server = template and template.server
        if type(metal_server) ~= "table" or type(metal_server.start_function) ~= "function" then
            return false
        end
        mod:hook(metal_server, "start_function", function(func, context, data, ...)
            local level = state.level
            if not (level and level.context and type(data) == "table") then
                return func(context, data, ...)
            end
            data.wind_strength = level.context.wind_strength
            data.buff_system = buff_system()
            level.started = true
            state.starts = state.starts + 1
            bounded_log("[ct:253:metal] start wind=%s strength=%d buff_system=%s",
                tostring(level.context.wind), level.context.wind_strength,
                tostring(data.buff_system ~= nil))
        end)
        state.bridged = true
        return true
    end

    -- Decision + per-level record. Returns the new list or nil plus a reason.
    local function prepare_level(mutators, server)
        state.level = nil
        local mechanism = mechanism_name()
        local list, reason = Policy.compose_mutators(mutators, {
            enabled = state.enabled,
            is_server = server == true,
            mechanism = mechanism,
        })
        if not list then
            state.skipped[reason] = (state.skipped[reason] or 0) + 1
            return nil, reason
        end
        if not ensure_bridge() then
            state.skipped.bridge_missing = (state.skipped.bridge_missing or 0) + 1
            return nil, "bridge_missing"
        end
        local names = Policy.armor_breeds(metal_template())
        local snapshot, count = Policy.snapshot_armor(breeds(), names)
        state.level = {
            context = Policy.build_context(state.strength),
            armor = snapshot,
            breeds = count,
            started = false,
            mechanism = mechanism,
        }
        state.activations = state.activations + 1
        state.last = { reason = reason, list = #list, strength = state.level.context.wind_strength }
        bounded_log("[ct:253:metal] armed strength=%d list=%d breeds=%d mechanism=%s",
            state.level.context.wind_strength, #list, count, tostring(mechanism))
        return list, reason
    end

    -- hook-test: issue253_metal_wind_adapter
    -- _ct_consolidated_mutator_handler_init_hook (singleton for this (Class, method)).
    -- Every vanilla parameter is named and passed back [src: mutator_handler.lua:27].
    mod:hook("MutatorHandler", "init", function(func, self, mutators, server, network_handler,
            has_local_client, world, network_event_delegate, network_transmit)
        local ok, list = pcall(prepare_level, mutators, server)
        if not ok then
            record_error("prepare_error", list)
            state.level = nil
        elseif list then
            mutators = list
        end
        return func(self, mutators, server, network_handler, has_local_client, world,
            network_event_delegate, network_transmit)
    end)

    -- hook-test: issue253_metal_wind_adapter
    -- _ct_consolidated_mutator_handler_destroy_hook (singleton for this (Class, method)).
    mod:hook_safe("MutatorHandler", "destroy", function(self)
        local level = state.level
        if not level then return end
        state.level = nil
        local ok, bad, total = pcall(Policy.armor_mismatches, breeds(), level.armor)
        if not ok then
            record_error("teardown_error", bad)
            return
        end
        state.teardowns = state.teardowns + 1
        if bad == 0 then
            state.restored_ok = state.restored_ok + 1
        else
            state.restored_bad = state.restored_bad + 1
        end
        bounded_log("[ct:253:metal] teardown started=%s restored=%d/%d",
            tostring(level.started), total - bad, total)
    end)

    local function view()
        return {
            enabled = state.enabled,
            strength = state.strength,
            is_server = is_server(),
            mechanism = mechanism_name(),
            bridged = state.bridged,
            level_active = state.level ~= nil,
            activations = state.activations,
            teardowns = state.teardowns,
            restored_bad = state.restored_bad,
        }
    end
    state.view = view

    -- All multi-return work lives here so the command callback stays a straight
    -- line: one helper call, one literal printf receipt, one chat reply.
    local function handle_command(...)
        local parsed, why = Policy.parse_command(...)
        local report = { action = parsed and parsed.action or "invalid", result = "rejected" }
        if parsed then
            local enabled, strength, changed = Policy.transition(parsed, state.enabled, state.strength)
            state.enabled = enabled
            if strength ~= state.strength then
                state.strength = strength
                set_setting(Policy.STRENGTH_SETTING, strength)
            end
            report.result = changed and "changed" or "unchanged"
            local text = Policy.status_text(view())
            if parsed.action == "on" and not is_server() then
                text = text .. " Host-owned: takes effect only on missions you host."
            end
            if changed and state.level then
                text = text .. " A change applies from the next mission; the current level keeps its armed context."
            end
            report.text = text
        else
            report.text = why .. ". Usage: " .. Policy.USAGE
        end
        report.enabled = tostring(state.enabled)
        report.strength = state.strength
        report.server = tostring(is_server())
        report.mechanism = tostring(mechanism_name() or "none")
        report.bridged = tostring(ensure_bridge())
        report.level = state.level and "armed" or "idle"
        return report
    end
    state.handle_command = handle_command

    mod:command("ct_weave_metal", "Metal wind curse adapter (#253, host-owned, hidden from the curse menu): on | off | status | strength <1-5>", function(...)
        local report = handle_command(...)
        pcall(printf, "[ct:253:diag] action=%s result=%s enabled=%s strength=%d server=%s mechanism=%s bridged=%s level=%s", report.action, report.result, report.enabled, report.strength, report.server, report.mechanism, report.bridged, report.level)
        mod:echo(report.text)
    end)

    local function regression()
        if mod._ct_weave_metal_state ~= state then
            return "adapter state is not the registered owner"
        end
        if state.enabled_at_boot ~= false or Policy.DEFAULT_ENABLED ~= false then
            return "adapter is not off by default"
        end
        if state.exposed_in_menu ~= false or Policy.EXPOSED_IN_MENU ~= false then
            return "adapter claims curse-menu exposure"
        end
        if state.command ~= "ct_weave_metal" then
            return "command drift: " .. tostring(state.command)
        end
        local ok, why = Policy.context_matches(Policy.build_context(state.strength))
        if not ok then return why end
        if state.level and state.level.context then
            ok, why = Policy.context_matches(state.level.context)
            if not ok then return "live " .. why end
        end
        local template = metal_template()
        if not template then return "MutatorTemplates.metal missing" end
        if type(template.server) ~= "table" or type(template.client) ~= "table" then
            return "metal template is not handler-wrapped"
        end
        if template.packages ~= nil then
            return "metal template now declares packages; re-audit the preload plan"
        end
        if template.remove_pickups ~= nil then
            return "metal template now declares remove_pickups; the bridged start skips that default"
        end
        if template.primary_armor_category ~= Policy.EXPECTED_ARMOR_CATEGORY then
            return "metal primary_armor_category drift: " .. tostring(template.primary_armor_category)
        end
        if #Policy.armor_breeds(template) ~= Policy.EXPECTED_ARMOR_BREEDS then
            return "metal armor breed list drift: " .. tostring(#Policy.armor_breeds(template))
        end
        local wire = lookup()
        if type(wire) ~= "table" or wire[Policy.MUTATOR] == nil then
            return "NetworkLookup.mutator_templates.metal missing"
        end
        if not ensure_bridge() then
            return "server.start_function bridge could not install"
        end
        local list = Policy.compose_mutators({ "deus_more_hordes" },
            { enabled = true, is_server = true, mechanism = "deus" })
        if not list or #list ~= 2 or list[2] ~= Policy.MUTATOR then
            return "composition drift"
        end
        if Policy.compose_mutators({ "x" }, { enabled = false, is_server = true, mechanism = "deus" }) then
            return "composition ignores the default-off gate"
        end
        if Policy.compose_mutators({ "x" }, { enabled = true, is_server = false, mechanism = "deus" }) then
            return "composition ignores the client gate"
        end
        if Policy.compose_mutators({ "x" }, { enabled = true, is_server = true, mechanism = "adventure" }) then
            return "composition ignores the mechanism gate"
        end
        if Policy.compose_mutators({ Policy.MUTATOR }, { enabled = true, is_server = true, mechanism = "deus" }) then
            return "composition duplicates metal"
        end
        if state.errors > 0 then
            return "runtime errors this session: " .. tostring(state.last_error)
        end
        if state.restored_bad > 0 then
            return string.format("armor restoration faults this session: %d", state.restored_bad)
        end
        return nil
    end
    state.regression = regression
    if type(mod._ct_rt_register) == "function" then
        mod._ct_rt_register("issue253_metal_wind_adapter", regression)
    end

    ensure_bridge()
    log("[ct:253:metal] runtime installed enabled=%s strength=%d command=/%s bridged=%s hooks=%s",
        tostring(state.enabled), state.strength, state.command, tostring(state.bridged),
        table.concat(state.hook_pairs, ","))
    return state
end
