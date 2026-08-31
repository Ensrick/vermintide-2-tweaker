-- _ct_diag_gargoyle1124.lua -- Old Haunts objective observation (#1124).
--
-- The injected Adventure path reuses Old Haunts' authored limited-item units.
-- Do not add `gargoyle_head` to pickup_settings: those counts feed the spread-
-- pickup sampler, while the objective heads are created by the level's
-- LimitedItemTrackSpawner units. This owner records the native path without
-- changing a group, spawner, item, socket, mission, or caller-owned table.
--
-- Native boundaries (Vermintide-2-Source-Code):
--   * limited_item_track_system.lua:191-233 registers authored spawners.
--   * limited_item_track_spawner_templates.lua:472-522 resolves the configured
--     pickup (default `gargoyle_head`) and calls spawn_network_unit.
--   * limited_item_track_spawner.lua:42-67 records socket/spawn progress.
--   * objective_socket_system.lua:42-54 sockets the limited item.
--   * mission_system.lua:279-303,369-380 advances the collect objective.
--
-- All six hook pairs were grep-clean before this owner was added. Every wrapper
-- delegates once outside pcall and preserves trailing arguments plus all return
-- values. Exact-target pre-state snapshots and every post-read are pcall-
-- isolated. Output is bounded engine `printf` with the exact `[ct:1124]` prefix
-- so it remains visible when VMF logging is disabled.
return function(mod, ctx)
    assert(type(mod) == "table", "_ct_diag_gargoyle1124 requires mod")
    assert(type(ctx) == "table", "_ct_diag_gargoyle1124 requires ctx")
    assert(type(ctx.on_injected_adventure_level) == "function",
        "_ct_diag_gargoyle1124 requires injected-level predicate")
    assert(type(ctx.adventure_base_from_level_key) == "function",
        "_ct_diag_gargoyle1124 requires adventure-base resolver")
    assert(type(ctx.rt_register) == "function",
        "_ct_diag_gargoyle1124 requires runtime-check registrar")

    local TARGET_BASE = "dlc_portals"
    local TARGET_MISSION = "portals_survive"
    local MARKER = "CT_GARGOYLE1124_OBSERVATION_ONLY_V1"
    local RUN_RECORD_CAP = 96
    local TOTAL_RECORD_CAP = 512
    local OWNER_KEY = "_ct_gargoyle1124_owner_state"

    local owner = rawget(mod, OWNER_KEY)
    if type(owner) ~= "table" then
        owner = {
            hook_count = 0,
            hooks_installed = false,
            observation_only = true,
            records = 0,
            rt_registered = false,
        }
        rawset(mod, OWNER_KEY, owner)
    end
    owner.adventure_base_from_level_key = ctx.adventure_base_from_level_key
    owner.on_injected_adventure_level = ctx.on_injected_adventure_level

    local function pack_returns(...)
        return { n = select("#", ...), ... }
    end

    local function return_packed(values)
        return unpack(values, 1, values.n)
    end

    local function safe_call(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn, ...)
        if ok then return value end
        return nil
    end

    local function current_level_key()
        local helper = rawget(_G, "LevelHelper")
        local settings = helper and safe_call(helper.current_level_settings, helper)
        local key = type(settings) == "table" and settings.level_id or nil
        if type(key) == "string" then return key end

        local managers = rawget(_G, "Managers")
        local handler = managers and managers.level_transition_handler
        key = handler and safe_call(handler.get_current_level_keys, handler)
        if type(key) ~= "string" then
            key = handler and safe_call(handler.get_current_level_key, handler)
        end
        return type(key) == "string" and key or "unknown"
    end

    local function current_level_session_id()
        local managers = rawget(_G, "Managers")
        local handler = managers and managers.level_transition_handler
        local id = handler and safe_call(handler.get_current_level_session_id, handler)
        return id ~= nil and tostring(id) or "unknown"
    end

    local function target_context()
        local key = current_level_key()
        local injected = safe_call(owner.on_injected_adventure_level)
        local base = safe_call(owner.adventure_base_from_level_key, key)
        return injected == true and base == TARGET_BASE, key, base,
            current_level_session_id()
    end

    local function target_run()
        local target, key, base, session_id = target_context()
        if not target then
            owner.run = nil
            return nil
        end
        if type(owner.run) ~= "table"
            or owner.run.level_key ~= key
            or owner.run.level_session_id ~= session_id
        then
            owner.run = {
                emitted = 0,
                groups = {},
                level_base = base,
                level_key = key,
                level_session_id = session_id,
                objective_updates = 0,
                socketed = 0,
                spawn_attempts = 0,
                spawned = 0,
                spawner_count = 0,
                spawners = {},
                valid_pickups = 0,
            }
        end
        return owner.run
    end

    local function emit(run, fmt, ...)
        if type(run) ~= "table"
            or run.emitted >= RUN_RECORD_CAP
            or owner.records >= TOTAL_RECORD_CAP
        then
            return false
        end
        local ok, line = pcall(string.format, fmt, ...)
        if not ok then line = "format_error=true mutation=false" end
        -- Direct engine output keeps the literal issue marker provable by the
        -- deployed-tree lifecycle verifier.  `pcall` also makes a missing or
        -- throwing engine logger observation-only and fail-closed.
        pcall(printf, "[ct:1124] %s", line)
        run.emitted = run.emitted + 1
        owner.records = owner.records + 1
        return true
    end

    local function unit_data(unit, ...)
        local unit_api = rawget(_G, "Unit")
        return unit_api and safe_call(unit_api.get_data, unit, ...)
    end

    local function go_id(unit)
        local managers = rawget(_G, "Managers")
        local storage = managers and managers.state and managers.state.unit_storage
        local id = storage and safe_call(storage.go_id, storage, unit)
        return id ~= nil and tostring(id) or "none"
    end

    local function configured_pickup(unit)
        local configured = unit_data(unit, "pickup_name")
        return configured ~= nil and tostring(configured) or ""
    end

    local function final_pickup(template_name, configured)
        if configured ~= "" then return configured end
        if template_name == "gargoyle_head_spawner_vs" then return "gargoyle_head" end
        if template_name == "gargoyle_head_spawner" then return "gargoyle_head_vs" end
        return "unknown"
    end

    local function is_gargoyle_spawner(template_name)
        return template_name == "gargoyle_head_spawner_vs"
            or template_name == "gargoyle_head_spawner"
    end

    local function ensure_spawner(run, unit, extension, source)
        if unit == nil then return nil end
        local existing = run.spawners[unit]
        if existing then return existing end

        local template_name = extension and extension.template_name
            or unit_data(unit, "template_name")
        template_name = tostring(template_name or "")
        if not is_gargoyle_spawner(template_name) then return nil end

        local configured = configured_pickup(unit)
        local group_name = tostring(unit_data(unit, "group_name") or "")
        run.spawner_count = run.spawner_count + 1
        local record = {
            configured_pickup = configured,
            final_pickup = final_pickup(template_name, configured),
            group_name = group_name,
            ordinal = run.spawner_count,
            template_name = template_name,
        }
        run.spawners[unit] = record
        local group = run.groups[group_name] or { spawners = 0 }
        group.spawners = group.spawners + 1
        run.groups[group_name] = group

        emit(run,
            "phase=authored level=%s ordinal=%d template=%s group=%s configured_pickup=%s final_pickup=%s pool=%s go_id=%s source=%s extension_registered=%s mutation=false",
            tostring(run.level_key), record.ordinal, record.template_name,
            group_name ~= "" and group_name or "<none>",
            configured ~= "" and configured or "<default>", record.final_pickup,
            tostring(extension and extension.pool or "unknown"), go_id(unit),
            tostring(source), tostring(extension ~= nil))
        return record
    end

    local function group_is_active(system, group_name)
        local groups = system and system.active_groups
        local count = system and tonumber(system.active_groups_n) or 0
        if type(groups) ~= "table" then return false end
        for index = 1, count do
            if groups[index] == group_name then return true end
        end
        return false
    end

    local function observe_group(system, phase, group_name, requested_pool)
        local run = target_run()
        if not run then return end
        local native = system and type(system.groups) == "table"
            and system.groups[group_name] or nil
        local record = run.groups[group_name] or { spawners = 0 }
        record.pool_size = type(native) == "table" and native.pool_size or nil
        record.spawners_n = type(native) == "table" and native.spawners_n or nil
        record.active = group_is_active(system, group_name)
        run.groups[group_name] = record
        emit(run,
            "phase=group_%s level=%s group=%s requested_pool=%s final_pool=%s authored_spawners=%d registered_spawners=%s active=%s mutation=false",
            tostring(phase), tostring(run.level_key), tostring(group_name),
            tostring(requested_pool), tostring(record.pool_size),
            tonumber(record.spawners) or 0, tostring(record.spawners_n),
            tostring(record.active))
    end

    local function actual_pickup(unit)
        local script_unit = rawget(_G, "ScriptUnit")
        local extension = script_unit
            and safe_call(script_unit.has_extension, unit, "pickup_system")
        local name = type(extension) == "table" and extension.pickup_name or nil
        if name == nil then name = unit_data(unit, "pickup_name") end
        return tostring(name or "missing"), extension ~= nil
    end

    local function observe_spawn(spawner, before_items, before_num_items)
        local run = target_run()
        if not run then return end
        local record = ensure_spawner(run, spawner and spawner.unit, spawner, "spawn_fallback")
        if not record then return end

        local item_id, item
        if spawner and type(spawner.items) == "table" then
            for id, candidate in pairs(spawner.items) do
                if type(candidate) ~= "boolean" and before_items[id] ~= candidate
                    and (item_id == nil
                        or (tonumber(id) or math.huge) < (tonumber(item_id) or math.huge))
                then
                    item_id, item = id, candidate
                end
            end
        end
        local pickup_name, has_pickup_extension = actual_pickup(item)
        local item_go_id = go_id(item)
        local confirmed = item ~= nil
        local valid = confirmed
            and has_pickup_extension
            and pickup_name == record.final_pickup
            and item_go_id ~= "none"
        run.spawn_attempts = run.spawn_attempts + 1
        if confirmed then run.spawned = run.spawned + 1 end
        if valid then run.valid_pickups = run.valid_pickups + 1 end
        emit(run,
            "phase=spawn level=%s ordinal=%d attempt=%d item_id=%s expected_pickup=%s actual_pickup=%s pickup_extension=%s item_go_id=%s confirmed=%s valid=%s items_before=%s items_after=%s confirmed_total=%d valid_total=%d mutation=false",
            tostring(run.level_key), record.ordinal, run.spawn_attempts,
            tostring(item_id), record.final_pickup, pickup_name,
            tostring(has_pickup_extension), item_go_id, tostring(confirmed),
            tostring(valid), tostring(before_num_items),
            tostring(spawner and spawner.num_items), run.spawned,
            run.valid_pickups)
    end

    local function observe_socket(spawner, item, before_socketed, item_id)
        local run = target_run()
        if not run then return end
        local record = ensure_spawner(run, spawner and spawner.unit, spawner, "socket_fallback")
        if not record then return end
        local pickup_name, has_pickup_extension = actual_pickup(item)
        local after = spawner and tonumber(spawner.num_socketed_items) or nil
        local before = tonumber(before_socketed) or 0
        run.socketed = run.socketed + math.max(0, (after or before) - before)
        emit(run,
            "phase=socket level=%s ordinal=%d item_id=%s pickup=%s pickup_extension=%s socketed_before=%s socketed_after=%s pool=%s mutation=false",
            tostring(run.level_key), record.ordinal, tostring(item_id),
            pickup_name, tostring(has_pickup_extension), tostring(before_socketed),
            tostring(after), tostring(spawner and spawner.pool))
    end

    local function mission_snapshot(system, mission_name)
        local active = system and type(system.active_missions) == "table"
            and system.active_missions[mission_name] or nil
        local completed = system and type(system.completed_missions) == "table"
            and system.completed_missions[mission_name] or nil
        local data = active or completed
        local amount = data and safe_call(data.get_current_amount, data)
        if amount == nil and data then amount = data.current_amount end
        local required = data and data.collect_amount or nil
        return {
            active = active ~= nil,
            amount = amount,
            completed = completed ~= nil,
            required = required,
        }
    end

    local function observe_objective(system, before)
        local run = target_run()
        if not run then return end
        local after = mission_snapshot(system, TARGET_MISSION)
        run.objective_updates = run.objective_updates + 1
        run.objective_amount = after.amount or before.amount
        run.objective_required = after.required or before.required
        run.objective_completed = after.completed and true or false
        emit(run,
            "phase=objective level=%s ordinal=%d mission=%s progress_before=%s/%s progress_after=%s/%s active_after=%s completed=%s spawners=%d spawn_attempts=%d spawned=%d valid_pickups=%d socketed=%d mutation=false",
            tostring(run.level_key), run.objective_updates, TARGET_MISSION,
            tostring(before.amount), tostring(before.required), tostring(after.amount),
            tostring(after.required or before.required), tostring(after.active),
            tostring(after.completed), run.spawner_count, run.spawn_attempts,
            run.spawned, run.valid_pickups, run.socketed)
    end

    local api = owner.api
    if type(api) ~= "table" then
        api = { MARKER = MARKER }

        function api.snapshot()
            local run = owner.run
            if type(run) ~= "table" then return nil end
            local spawners = {}
            for _, record in pairs(run.spawners) do
                spawners[#spawners + 1] = {
                    configured_pickup = record.configured_pickup,
                    final_pickup = record.final_pickup,
                    group_name = record.group_name,
                    ordinal = record.ordinal,
                    template_name = record.template_name,
                }
            end
            table.sort(spawners, function(a, b) return a.ordinal < b.ordinal end)
            return {
                level_base = run.level_base,
                level_key = run.level_key,
                level_session_id = run.level_session_id,
                objective_amount = run.objective_amount,
                objective_completed = run.objective_completed,
                objective_required = run.objective_required,
                objective_updates = run.objective_updates,
                socketed = run.socketed,
                spawn_attempts = run.spawn_attempts,
                spawned = run.spawned,
                spawner_count = run.spawner_count,
                spawners = spawners,
                valid_pickups = run.valid_pickups,
            }
        end

        function api.regression()
            if owner.hooks_installed ~= true or owner.hook_count ~= 6 then
                return "issue1124 gargoyle diagnostic hook cardinality mismatch"
            end
            if owner.observation_only ~= true then
                return "issue1124 gargoyle diagnostic mutation contract drifted"
            end
            local run = owner.run
            if type(run) == "table" then
                for _, record in pairs(run.spawners) do
                    if record.template_name == "gargoyle_head_spawner_vs"
                        and record.final_pickup ~= "gargoyle_head"
                    then
                        return "issue1124 Adventure gargoyle pickup identity drifted"
                    end
                end
            end
            return nil
        end

        owner.api = api
    end
    rawset(mod, "_ct_gargoyle1124", api)

    if not owner.hooks_installed then
        mod:hook("LimitedItemTrackSystem", "on_add_extension",
            function(func, self, world, unit, extension_name, extension_init_data, ...)
                local results = pack_returns(func(self, world, unit, extension_name,
                    extension_init_data, ...))
                if extension_name == "LimitedItemTrackSpawner" then
                    pcall(function()
                        local run = target_run()
                        if run then ensure_spawner(run, unit, results[1], "on_add_extension") end
                    end)
                else
                    pcall(target_run)
                end
                return return_packed(results)
            end)

        mod:hook("LimitedItemTrackSystem", "register_group",
            function(func, self, group_name, pool_size, ...)
                local results = pack_returns(func(self, group_name, pool_size, ...))
                pcall(observe_group, self, "register", group_name, pool_size)
                return return_packed(results)
            end)

        mod:hook("LimitedItemTrackSystem", "activate_group",
            function(func, self, group_name, pool_size, ...)
                local results = pack_returns(func(self, group_name, pool_size, ...))
                pcall(observe_group, self, "activate", group_name, pool_size)
                return return_packed(results)
            end)

        mod:hook("LimitedItemTrackSpawner", "spawn_item", function(func, self, ...)
            local before
            pcall(function()
                if not target_run() then return end
                local items = {}
                if type(self.items) == "table" then
                    for id, item in pairs(self.items) do items[id] = item end
                end
                before = { items = items, num_items = self.num_items }
            end)
            local results = pack_returns(func(self, ...))
            if before then
                pcall(observe_spawn, self, before.items, before.num_items)
            else
                pcall(target_run)
            end
            return return_packed(results)
        end)

        mod:hook("LimitedItemTrackSpawner", "socket_item", function(func, self, unit, ...)
            local before
            pcall(function()
                if not target_run() then return end
                local item_id
                if type(self.items) == "table" then
                    for id, item in pairs(self.items) do
                        if item == unit then item_id = id; break end
                    end
                end
                before = {
                    item_id = item_id,
                    socketed = self.num_socketed_items,
                }
            end)
            local results = pack_returns(func(self, unit, ...))
            if before then
                pcall(observe_socket, self, unit, before.socketed, before.item_id)
            else
                pcall(target_run)
            end
            return return_packed(results)
        end)

        mod:hook("MissionSystem", "flow_callback_update_mission",
            function(func, self, mission_name, ...)
                local before
                pcall(function()
                    local target = target_context()
                    if target and mission_name == TARGET_MISSION then
                        before = mission_snapshot(self, mission_name)
                    end
                end)
                local results = pack_returns(func(self, mission_name, ...))
                if before then pcall(observe_objective, self, before) else pcall(target_run) end
                return return_packed(results)
            end)

        owner.hook_count = 6
        owner.hooks_installed = true
    end

    if not owner.rt_registered then
        ctx.rt_register("issue1124_gargoyle_objective_diagnostic", api.regression)
        owner.rt_registered = true
    end

    return api
end
