--[[
_ct_official_chest_cap - selective settled #60 cap reconciliation.
Derived from the behavior-bearing reconcile in _ct_diag_cursed_chest132.
Owns no hooks/census. Main feeds population begin, extension appearance,
confirmed pickup origin, and the existing delayed (eight-second) finalizer.
Only live pickup-origin WAITING units can use vanilla mark_for_deletion
(pickup_system.lua:1345,1451-1455); baked/activated chests remain untouched.
Owned by: chaos_wastes_tweaker.lua. Consumed via: mod:dofile installer.
]]
return function(mod, ctx)
    assert(type(ctx) == "table" and type(ctx.effective_setting) == "function",
        "_ct_official_chest_cap requires effective_setting")
    local Core = mod:dofile("scripts/mods/chaos_wastes_tweaker/_ct_chest_count_audit_core")
    local M = { MARKER = "CT_CHEST132_RECONCILE_PRUNE_v0.7.298" }
    local tracker, units, pickup_units, seen = {}, {}, {}, {}
    local settled, begin_controller
    local function controller()
        local mechanism = Managers and Managers.mechanism and Managers.mechanism:game_mechanism()
        return mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
    end

    function M.begin(level_id)
        Core.begin(tracker, level_id)
        units, pickup_units, seen = {}, {}, {}
        local ok, current = pcall(controller)
        settled, begin_controller = nil, ok and tostring(current) or "unavailable"
    end

    function M.appeared(level_id, unit)
        if tracker.level_id ~= level_id then M.begin(level_id) end
        if unit == nil or seen[unit] then return end
        seen[unit] = true
        Core.appeared(tracker, level_id)
        units[#units + 1] = unit
    end

    function M.pickup_chest(unit)
        if unit ~= nil then pickup_units[unit] = true end
    end

    local function chest_state(unit)
        local ok, result = pcall(function()
            local state = Managers.state
            local game = state.network:game()
            local go_id = state.unit_storage:go_id(unit)
            if not game or not go_id then return nil end
            return GameSession.game_object_field(game, go_id,
                "deus_cursed_chest_state")
        end)
        if ok then return result end
    end
    local function waiting(unit) return chest_state(unit) == 1 end
    local function census()
        local row = { appeared = #units, live = 0, pickup_origin = 0, non_pickup_origin = 0,
            waiting = 0, activated = 0, unknown = 0, marked = 0, eligible = 0 }
        local spawner = Managers and Managers.state and Managers.state.unit_spawner
        for i = 1, #units do
            local unit = units[i]
            local ok, alive = pcall(Unit.alive, unit)
            if ok and alive == true then
                row.live = row.live + 1
                local origin = pickup_units[unit] == true
                if origin then row.pickup_origin = row.pickup_origin + 1 else row.non_pickup_origin = row.non_pickup_origin + 1 end
                local state = chest_state(unit)
                if state == 1 then
                    row.waiting = row.waiting + 1
                    if origin then row.eligible = row.eligible + 1 end
                elseif state == 2 or state == 3 or state == 4 then row.activated = row.activated + 1
                else row.unknown = row.unknown + 1 end
                if spawner and spawner.is_marked_for_deletion then
                    local marked_ok, marked = pcall(spawner.is_marked_for_deletion, spawner, unit)
                    if marked_ok and marked == true then row.marked = row.marked + 1 end
                end
            end
        end
        return row
    end
    function M.inspect()
        local current = LevelHelper and LevelHelper:current_level_settings()
        if not (controller() and current and current.level_id == tracker.level_id
            and begin_controller == tostring(controller()) and tracker.finalized and settled) then
            return { status = "SKIP", reason = "no settled current-controller/current-level chest census" }
        end
        local row = census()
        local cap = ctx.effective_setting("cursed_chest_count")
        row.cap, row.queued, row.confirmed_marked, row.queue_failures = cap, settled.queued, settled.confirmed_marked, settled.failed
        if type(cap) ~= "number" or cap < 0 or cap ~= math.floor(cap) or cap == math.huge then
            return { status = "SKIP", reason = "explicit finite chest cap disabled", fields = row }
        end
        local entity = Managers.state and Managers.state.entity
        local pickup = entity and entity:system("pickup_system")
        local loci = pickup and pickup.get_pickups_by_type and pickup:get_pickups_by_type("deus_02")
        if type(loci) == "table" then
            row.locus = 0
            for i = 1, math.min(#loci, 128) do if Unit.alive(loci[i]) then row.locus = row.locus + 1 end end
            if #loci > 128 then return { status = "SKIP", reason = "locus census truncated", fields = row } end
        end
        if row.locus and row.locus > 1 then return { status = "FAIL", reason = "multiple current pickup-system loci", fields = row } end
        local over = math.max(0, row.live - cap)
        if over > 0 and row.marked > 0 then return { status = "SKIP", reason = "PENDING queued/marked is not drained deletion", fields = row } end
        if over > 0 and row.eligible > 0 then return { status = "FAIL", reason = "eligible excess remains unmarked", fields = row } end
        if over > 0 then return { status = "SKIP", reason = "unprunable non-pickup/activated/unknown excess; not automatically baked", fields = row } end
        if row.locus == nil then return { status = "SKIP", reason = "chest cap readable; current locus census unavailable", fields = row } end
        return { status = "PASS", reason = "fresh settled census within cap; locus at most one; not gameplay acceptance", fields = row }
    end

    function M.finalize(level_id, cap, is_server)
        if tracker.level_id ~= level_id or tracker.finalized then return nil end
        tracker.finalized = true
        -- Require the current explicit authoritative value, not a stale supplied
        -- cap. Default (-1), malformed values and every client are pass-throughs.
        local effective = ctx.effective_setting("cursed_chest_count")
        if is_server ~= true or not (Managers.player and Managers.player.is_server)
            or type(cap) ~= "number" or cap ~= cap or cap == math.huge
            or cap < 0 or cap ~= math.floor(cap) or effective ~= cap then
            return nil
        end
        local in_deus, controller = pcall(function()
            local mechanism = Managers.mechanism:game_mechanism()
            return mechanism and mechanism.get_deus_run_controller
                and mechanism:get_deus_run_controller()
        end)
        if not in_deus or not controller then return nil end
        local plan = Core.reconcile_plan(units, pickup_units, cap, function(unit)
            local ok, alive = pcall(Unit.alive, unit)
            return ok and alive == true
        end, waiting)
        local pruned, failed, confirmed = 0, 0, 0
        for i = 1, #plan.prune do
            -- Re-prove WAITING immediately before each mutation. A broken/missing
            -- replicated field never authorizes deletion.
            local unit = plan.prune[i]
            if waiting(unit) then
                local ok = pcall(function()
                    Managers.state.unit_spawner:mark_for_deletion(unit)
                end)
                if ok then
                    pruned = pruned + 1
                    local spawner = Managers.state.unit_spawner
                    local marked_ok, marked = pcall(function() return spawner:is_marked_for_deletion(unit) end)
                    if marked_ok and marked == true then confirmed = confirmed + 1 end
                else failed = failed + 1 end
            else
                failed = failed + 1
            end
        end
        plan.pruned_n, plan.failed_n = pruned, failed
        settled = { queued = pruned, confirmed_marked = confirmed, failed = failed }
        if mod._ct_apply_evidence then
            local ok, row = pcall(census)
            if ok then
                row.cap, row.over, row.planned = cap, plan.over_n, #plan.prune
                row.queued, row.confirmed_marked, row.failed, row.unprunable = pruned, confirmed, failed, plan.unprunable_n
                mod._ct_apply_evidence.call("record", "60", "settled census; queued/marked != removed", row)
            end
        end
        if rawget(_G, "printf") then
            pcall(printf, "[ct:132] reconcile level=%s alive=%d cap=%d over=%d queued=%d unprunable=%d failed=%d",
                tostring(level_id), plan.alive_n, cap, plan.over_n, pruned,
                plan.unprunable_n, failed)
        end
        return plan
    end

    if ctx.rt_register then
        ctx.rt_register("cursed_chest_reconcile_132", function()
            local baked, early, late, active = {}, {}, {}, {}
            local plan = Core.reconcile_plan({baked, early, late, active},
                {[early]=true,[late]=true,[active]=true}, 2,
                function() return true end, function(unit) return unit ~= active end)
            if plan.alive_n ~= 4 or #plan.prune ~= 2
                or plan.prune[1] ~= late or plan.prune[2] ~= early then
                return "#60 safe pickup-only reverse-order reconciliation missing"
            end
        end)
    end
    return M
end
