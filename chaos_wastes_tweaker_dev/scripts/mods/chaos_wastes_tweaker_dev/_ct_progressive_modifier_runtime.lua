-- _ct_progressive_modifier_runtime.lua -- host-authoritative progressive modifier
-- stacking owner (#289). Default-off.
--
-- Owns the single CT hook on (GameModeDeus, mutators). Vanilla composes one
-- mission list there: the game-mode settings list (the node's singular `curse`,
-- its `minor_modifier_group`, theme and node mutators
-- [src: deus_mechanism.lua:781-808]), live-event mutators, and the run's
-- event-mutator list with name dedup [src: game_mode_deus.lua:667-686].
-- GameModeManager calls it once per mission when it creates the MutatorHandler
-- [src: game_mode_manager.lua:85-99]. The hook runs vanilla FIRST and, host-only,
-- appends at most ONE curated extra to the returned list: the same channel the
-- weekly event mutators ride, so the singular graph `node.curse` and the map,
-- curse-panel and reward contracts that read it are untouched.
--
-- Transport is vanilla end to end. The host handler initializes and activates
-- every list entry [src: mutator_handler.lua:45-48,85-111]; activation sends
-- rpc_activate_mutator_client keyed by NetworkLookup.mutator_templates
-- [src: mutator_handler.lua:697-702; network_lookup.lua:266]; the initialized map
-- is shared state [src: mutator_handler.lua:95-99,795-797]; hot join replays every
-- active mutator [src: mutator_handler.lua:148-170; game_mode_manager.lua:920].
-- Clients never consult their own composed list [src: mutator_handler.lua:49-55],
-- so the hook is inert on clients and no mod RPC, lookup entry, package load or
-- setting transport is added. Mission teardown deactivates every active entry
-- [src: mutator_handler.lua:60-83]; nothing is written to the run state or graph,
-- so a node transition or run end leaves no residue.
--
-- Package ownership: the allowlist holds only templates that declare no
-- `packages`, and the selector re-checks the live template, so no peer needs a
-- package Deus did not already load (Deus preloads only declared packages
-- [src: deus_run_state.lua:438-453]). Selection is a pure hash of run seed, node
-- key and completed level count, so it consumes no gameplay RNG and repeats
-- identically on every call for the same mission.
--
-- Owned by: chaos_wastes_tweaker_dev.lua entry point (installed before
-- _ct_modifier_stack_audit, which reads the published state and hooks nothing).
-- Guarded by qa/lua/tests/test_ct_progressive_modifier_runtime_owner.lua and the
-- /ct_regression_test check `issue289_progressive_modifier_stack`.
return function(ctx)
    assert(type(ctx) == "table", "CT progressive modifier runtime requires context")
    local mod = assert(ctx.mod, "CT progressive modifier runtime requires mod")
    local effective_setting = assert(ctx.effective_setting,
        "CT progressive modifier runtime requires effective_setting")
    local is_curse_disabled = assert(ctx.is_curse_disabled,
        "CT progressive modifier runtime requires is_curse_disabled")
    -- Engine seams default to the live game; tests inject doubles. The entry
    -- passes only mod + effective_setting + is_curse_disabled (it sits at the
    -- 200-local ceiling).
    local Policy = ctx.policy or (type(mod.dofile) == "function"
        and mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_modifier_stack_policy"))
    assert(type(Policy) == "table", "CT progressive modifier runtime requires policy")
    local function managers()
        return rawget(_G, "Managers")
    end
    local is_server = ctx.is_server or function()
        local live = managers()
        return (live and live.player and live.player.is_server) == true
    end
    local templates = ctx.templates or function()
        return rawget(_G, "MutatorTemplates")
    end
    local lookup = ctx.lookup or function()
        local network_lookup = rawget(_G, "NetworkLookup")
        return type(network_lookup) == "table" and network_lookup.mutator_templates or nil
    end
    local log = ctx.log or function(fmt, ...)
        pcall(printf, fmt, ...)
    end

    -- Idempotent: a second install never registers a second hook.
    if mod._ct_progressive_modifier_runtime_state then
        return mod._ct_progressive_modifier_runtime_state
    end

    local state = {
        installed = true,
        hook_pair = "GameModeDeus.mutators",
        setting_id = "progressive_modifier_stack",
        selections = 0,
        appended = 0,
        skipped = {},
        errors = 0,
        log_rows = 0,
        LOG_CAP = 12,
        ERROR_CAP = 4,
        observers = {},
        last = nil,
        last_error = nil,
    }
    mod._ct_progressive_modifier_runtime_state = state

    local function enabled()
        return effective_setting(state.setting_id) == true
    end

    state.enabled = enabled
    state.activation = function()
        return enabled() and "enabled" or "disabled"
    end
    state.ladder_label = function()
        return Policy.ladder_label()
    end
    state.extra_label = function()
        return Policy.extra_label()
    end
    state.allowlist = function()
        return table.concat(Policy.ALLOWLIST, ",")
    end
    state.add_observer = function(fn)
        if type(fn) == "function" then
            state.observers[#state.observers + 1] = fn
        end
    end

    local function record_error(kind, err)
        state.errors = state.errors + 1
        state.last_error = tostring(err)
        if state.errors <= state.ERROR_CAP then
            log("[ct:289] %s %d/%d err=%s", kind, state.errors, state.ERROR_CAP, tostring(err))
        end
    end

    -- A candidate is rejected when the host disabled that curse (CT's own
    -- _activate_mutator gate would silently leave it unactivated), when the live
    -- template is missing, or when it declares packages no peer preloaded.
    local function excluded(name, catalog)
        if is_curse_disabled(name) then return true end
        local template = type(catalog) == "table" and catalog[name] or nil
        return type(template) ~= "table" or template.packages ~= nil
    end

    -- Decision only; it reads the composed list and the run controller, never
    -- writes either.
    local function select_for(game_mode, list)
        if not is_server() then return nil, "client" end
        if not enabled() then return nil, "disabled" end
        local controller = game_mode and game_mode._deus_run_controller
        if type(controller) ~= "table" then return nil, "no_run_controller" end
        local node = controller.get_current_node and controller:get_current_node()
        local node_curse = type(node) == "table" and node.curse or nil
        local depth = controller.get_completed_level_count
            and controller:get_completed_level_count() or nil
        local seed = controller.get_run_seed and controller:get_run_seed() or nil
        local node_key = controller.get_current_node_key
            and controller:get_current_node_key() or nil
        local catalog = templates()
        local extra, reason = Policy.select_extra({
            node_curse = node_curse,
            vanilla = list,
            completed = depth,
            run_seed = seed,
            node_key = node_key,
        }, function(name)
            return excluded(name, catalog)
        end)
        return extra, reason, depth, node_curse, node_key
    end

    local function pack(...)
        return select("#", ...), { ... }
    end

    -- hook-test: issue289_progressive_modifier_stack
    -- _ct_consolidated_game_mode_deus_mutators_hook (singleton for this (Class, method)).
    mod:hook("GameModeDeus", "mutators", function(func, self, ...)
        -- Vanilla always runs first, with every argument and return value preserved.
        local count, results = pack(func(self, ...))
        local list = results[1]
        if type(list) == "table" then
            local ok, extra, reason, depth, node_curse, node_key = pcall(select_for, self, list)
            if ok then
                state.selections = state.selections + 1
                state.last = {
                    extra = extra,
                    reason = reason,
                    completed = depth,
                    node_curse = node_curse,
                    node_key = node_key,
                    vanilla_count = #list,
                }
                if extra then
                    list[#list + 1] = extra
                    state.appended = state.appended + 1
                    if state.log_rows < state.LOG_CAP then
                        state.log_rows = state.log_rows + 1
                        log("[ct:289] stack %d/%d node=%s curse=%s extra=%s completed=%s ladder=%s extras=%s list=%d",
                            state.log_rows, state.LOG_CAP, tostring(node_key), tostring(node_curse),
                            tostring(extra), tostring(depth), Policy.ladder_label(),
                            Policy.extra_label(), #list)
                    end
                else
                    state.skipped[reason] = (state.skipped[reason] or 0) + 1
                end
            else
                record_error("select_error", extra)
                reason = "error"
                extra = nil
            end
            local observers = state.observers
            for i = 1, #observers do
                pcall(observers[i], list, extra, reason)
            end
        end
        return unpack(results, 1, count)
    end)

    if type(mod._ct_rt_register) == "function" then
        mod._ct_rt_register("issue289_progressive_modifier_stack", function()
            local game_mode = rawget(_G, "GameModeDeus")
            if type(game_mode) ~= "table" or type(game_mode.mutators) ~= "function" then
                return "GameModeDeus.mutators seam missing"
            end
            local catalog = templates()
            if type(catalog) ~= "table" then
                return "MutatorTemplates catalog missing"
            end
            local wire = lookup()
            if type(wire) ~= "table" then
                return "NetworkLookup.mutator_templates missing"
            end
            if #Policy.ALLOWLIST ~= 2 then
                return "curated pair drift: " .. tostring(#Policy.ALLOWLIST)
            end
            for _, name in ipairs(Policy.ALLOWLIST) do
                local template = catalog[name]
                if type(template) ~= "table" then
                    return "allowlist template missing: " .. name
                end
                if template.packages ~= nil then
                    return "allowlist template declares packages: " .. name
                end
                if type(template.server) ~= "table" or type(template.client) ~= "table" then
                    return "allowlist template is not handler-wrapped: " .. name
                end
                if wire[name] == nil then
                    return "allowlist wire entry missing: " .. name
                end
            end
            if Policy.ladder_label() ~= "1/1/2/2/3" then
                return "documented ladder drift: " .. Policy.ladder_label()
            end
            if Policy.extra_label() ~= "0/0/1/1/1" then
                return "proof extra ladder drift: " .. Policy.extra_label()
            end
            if Policy.PROOF_MAX_TARGET ~= 2 then
                return "proof cap drift: " .. tostring(Policy.PROOF_MAX_TARGET)
            end
            local node_curses = { false, "curse_skulls_of_fury" }
            for _, name in ipairs(Policy.ALLOWLIST) do node_curses[#node_curses + 1] = name end
            local never = function() return false end
            for _, node_curse in ipairs(node_curses) do
                local curse = node_curse or nil
                for depth = 0, Policy.LADDER_DEPTHS + 2 do
                    for seed = 1, 6 do
                        local input = {
                            node_curse = curse,
                            vanilla = curse and { "deus_more_hordes", curse } or { "deus_more_hordes" },
                            completed = depth,
                            run_seed = "seed_" .. seed,
                            node_key = "node_" .. (seed % 3),
                        }
                        local extra, reason = Policy.select_extra(input, never)
                        local again = Policy.select_extra(input, never)
                        if extra ~= again then
                            return "selection is not deterministic"
                        end
                        if extra then
                            if not curse then return "extra selected without a node curse" end
                            if depth < 2 then return "extra selected below the ladder" end
                            if not Policy.is_allowlisted(extra) then
                                return "non-allowlisted extra selected: " .. tostring(extra)
                            end
                            if extra == curse then return "extra duplicates the node curse" end
                            if reason ~= "selected" then return "selected without the selected reason" end
                        elseif curse and depth >= 2 then
                            return "extra missing at depth " .. depth .. " reason=" .. tostring(reason)
                        end
                        local none = Policy.select_extra(input, function() return true end)
                        if none then return "exclusion callback ignored" end
                    end
                end
            end
            if state.hook_pair ~= "GameModeDeus.mutators" then
                return "hook pair drift: " .. tostring(state.hook_pair)
            end
            if state.errors > 0 then
                return "runtime selection errors this session: " .. tostring(state.last_error)
            end
        end)
    end

    log("[ct:289] runtime installed activation=%s ladder=%s extras=%s pair=%s hook=%s",
        state.activation(), state.ladder_label(), state.extra_label(), state.allowlist(),
        state.hook_pair)

    return state
end
