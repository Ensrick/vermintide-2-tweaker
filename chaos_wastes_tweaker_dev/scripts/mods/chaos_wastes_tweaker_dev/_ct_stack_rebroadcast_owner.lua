-- _ct_stack_rebroadcast_owner.lua — issue 249: re-broadcast meta-boon stack buffs after a parity restore.
--
-- The [ct:426] parity-loss strip removes every live server-controlled ct buff
-- with a replicated removal [src: buff_system.lua:340], and any meta-stack
-- grant made while the gate was degraded used the LOCAL host-only fail-safe
-- path, so a client exits a degrade/restore cycle holding its boons with ZERO
-- ct_meta_*_stack stacks (issue 249 client log 2026-08-04:
-- boon_effective_count=17, stacks=0; same signature as issue 289) while the
-- host's buff extension sits at target - which zeroes every later grant_plan
-- delta, so the client can NEVER converge organically. The restore callback in
-- _ct_meta_trait_boons.lua only re-injects pools. This owner registers a
-- SECOND gated feature on the same peer-parity beacon: on every enable
-- transition the HOST reconciles each player unit via the pure
-- _ct_ammo_guard_core.restore_plan kernel - remove the host-only stacks, then
-- re-add the full target through BuffSystem.add_buff(unit, name, unit, true),
-- the replicated server-controlled path [src: buff_system.lua:277-311] that is
-- also re-sent to hot-joining peers [src: buff_system.lua:66-97]. Wire safety
-- is structural, never toggle-gated (docs/BUG_CLASSES.md 31): the networked
-- adds run only inside the enabled parity gate plus a fresh mod._ct_wire_safe()
-- check, and a beacon-less session leaves the reconcile inert (fail-safe).
--
-- Owned by: chaos_wastes_tweaker_dev.lua entry point. Consumed via: one
-- mod:dofile from _ct_settings_lifecycle_owner.lua, directly after
-- _ct_meta_trait_boons.lua installs the beacon (load order is load-bearing:
-- mod._ct_peer_parity and mod._ct_ammo_guard_core must already exist).
return function(mod, ctx)
    local _rt_register = ctx.rt_register

    local Core = mod._ct_ammo_guard_core

    -- Bounded [ct:249] receipts. Restores are transition events (one per level
    -- load in practice), so 60 rows covers a full expedition many times over.
    local RECEIPT_BUDGET = 60
    local budget = RECEIPT_BUDGET
    local function _receipt(fmt, ...)
        if budget <= 0 then return end
        budget = budget - 1
        pcall(printf, fmt, ...)
        if budget == 0 then
            pcall(printf, "[ct:249] receipt cap reached (%d rows); further parity-restore rows suppressed this session", RECEIPT_BUDGET)
        end
    end

    -- Reconcile ONE (unit, stack template) pair on the host. Stack identity:
    -- BuffExtension stores one sub-buff instance per add under the sub-buff
    -- name, each carrying the add-call id [src: buff_extension.lua:300-345],
    -- and BuffSystem tracks server-controlled adds as
    -- server_controlled_buffs[unit][server_buff_id] = { local_buff_id,
    -- template_name, ... } [src: buff_system.lua:262-271] - so a stack whose id
    -- is not tracked there is exactly a host-only fail-safe grant.
    -- Returns (removed_local, added_networked, server_count, local_total).
    local function _reconcile_stack(buff_system, unit, ext, stack_name, stack_key, target)
        local server_ids, server_count = {}, 0
        local scb = buff_system.server_controlled_buffs
        local unit_buffs = scb and scb[unit]
        if type(unit_buffs) == "table" then
            for _, entry in pairs(unit_buffs) do
                if entry and entry.template_name == stack_name and entry.local_buff_id then
                    server_ids[entry.local_buff_id] = true
                    server_count = server_count + 1
                end
            end
        end
        local local_total = ext:num_buff_stacks(stack_key)
        local remove_n, add_n = Core.restore_plan(server_count, local_total, target)
        local removed = 0
        if remove_n > 0 then
            -- Collect ids first (removal mutates the stack array), then remove
            -- every host-local stack. remove_buff is extension-local here: the
            -- sync path no-ops without a server sync id for the add
            -- [src: buff_extension.lua:889-928 -> _remove_buff_synced].
            local stacks = ext:get_stacking_buff(stack_key)
            local ids = {}
            for i = 1, (stacks and #stacks or 0) do
                local b = stacks[i]
                if b and b.id and not server_ids[b.id] then
                    ids[#ids + 1] = b.id
                end
            end
            for i = 1, #ids do
                local n = ext:remove_buff(ids[i])
                if type(n) == "number" and n > 0 then removed = removed + 1 end
            end
        end
        local added = 0
        for _ = 1, add_n do
            -- Replicated add: host extension + rpc_add_buff to every client,
            -- re-sent on hot-join. Returns nil for a dead unit - those stacks
            -- re-grant through the ordinary proc on the next apply, which is
            -- now parity-confirmed and therefore networked.
            if buff_system:add_buff(unit, stack_name, unit, true) then
                added = added + 1
            end
        end
        return removed, added, server_count, local_total
    end

    -- Full-roster reconcile, invoked from the beacon's enable transition.
    -- Host-only; no-op outside a Deus (Chaos Wastes) run.
    local function _restore_rebroadcast()
        local pm = Managers and Managers.player
        if not (pm and pm.is_server) then return end
        local mechanism = Managers.mechanism and Managers.mechanism:game_mechanism()
        local rc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
        if not rc then return end
        local entity = Managers.state and Managers.state.entity
        local buff_system = entity and entity:system("buff_system")
        local buff_templates = rawget(_G, "BuffTemplates")
        if not (buff_system and buff_templates) then return end
        if not (mod._ct_wire_safe and mod._ct_wire_safe() == true) then
            -- Defense-in-depth: the enable callback implies wire safety; if the
            -- gate disagrees, a networked add would put a modded NetworkLookup
            -- id on a vanilla RPC (the non-ct-peer CTD class), so refuse
            -- sender-side - a receiver guard cannot protect that peer.
            _receipt("[ct:249] parity-restore reconcile SKIPPED: wire safety not confirmed at enable transition")
            return
        end
        local players_touched, total_removed, total_added = 0, 0, 0
        local ok, err = pcall(function()
            for _, player in pairs(pm:human_and_bot_players()) do
                local unit = player.player_unit
                if unit and ScriptUnit.has_extension(unit, "buff_system") then
                    local ext = ScriptUnit.extension(unit, "buff_system")
                    local ok_pu, power_ups = pcall(rc.get_player_power_ups, rc,
                        player:network_id(), player:local_player_id())
                    power_ups = (ok_pu and type(power_ups) == "table") and power_ups or nil
                    local num_boons = power_ups and #power_ups or 0
                    local p_removed, p_added = 0, 0
                    for i = 1, num_boons do
                        local name = power_ups[i] and power_ups[i].name
                        if type(name) == "string" and name:find("^ct_meta_") then
                            local stack_name = name .. "_stack"
                            local tmpl = buff_templates[stack_name]
                            local sub = tmpl and tmpl.buffs and tmpl.buffs[1]
                            if sub and sub.name then
                                -- Same target arithmetic as _make_meta_proc: boon
                                -- count capped by the template's own max_stacks.
                                local target = math.min(num_boons, sub.max_stacks or num_boons)
                                local removed, added, server_had = _reconcile_stack(
                                    buff_system, unit, ext, stack_name, sub.name, target)
                                if removed > 0 or added > 0 then
                                    _receipt("[ct:249] parity-restore re-broadcast peer=%s boon=%s localized_removed=%d networked_added=%d server_had=%d target=%d",
                                        tostring(player:network_id()), tostring(name),
                                        removed, added, server_had, target)
                                end
                                p_removed = p_removed + removed
                                p_added = p_added + added
                            end
                        end
                    end
                    if p_removed > 0 or p_added > 0 then
                        players_touched = players_touched + 1
                    end
                    total_removed = total_removed + p_removed
                    total_added = total_added + p_added
                end
            end
        end)
        if not ok then
            _receipt("[ct:249] parity-restore reconcile errored: %s", tostring(err))
            return
        end
        _receipt("[ct:249] parity-restore stack reconcile ran: players_reconciled=%d local_only_removed=%d networked_rebroadcast=%d",
            players_touched, total_removed, total_added)
    end
    mod._ct249_restore_rebroadcast = _restore_rebroadcast

    -- Register as a gated feature on the SAME beacon the strip lives on, so the
    -- reconcile runs on exactly the transitions whose strip created the deficit
    -- (feature order: pools restore first, then this). A beacon-less session
    -- (install failed) keeps modded content inert anyway, so staying unwired
    -- there is the correct fail-safe.
    local pp = mod._ct_peer_parity
    if type(pp) == "table" and type(pp.register_gated_feature) == "function" then
        pp:register_gated_feature("ct249_stack_rebroadcast", {
            label = "ct_gated_boon_stack_resync",
            on_enable = _restore_rebroadcast,
        })
        mod._ct249_rebroadcast_wired = true
    else
        mod._ct249_rebroadcast_wired = false
        pcall(printf, "[ct:249] peer-parity beacon unavailable; parity-restore stack re-broadcast inert this session (fail-safe)")
    end

    _rt_register("issue249_stack_rebroadcast_on_restore", function()
        if type(mod._ct249_restore_rebroadcast) ~= "function" then
            return "#249 REGRESSION: mod._ct249_restore_rebroadcast missing (parity-restore stack re-broadcast)"
        end
        if type(Core) ~= "table" or type(Core.restore_plan) ~= "function" then
            return "#249 REGRESSION: AmmoGuardCore.restore_plan missing (pure reconcile kernel)"
        end
        if Core.RESTORE_MARKER ~= "ct249:parity_restore_stack_rebroadcast_v1" then
            return "#249 REGRESSION: restore kernel marker missing/mismatch; got: " .. tostring(Core.RESTORE_MARKER)
        end
        local cases = {
            { 0, 5, 5, 5, 5 },   -- post-strip local grants: replace all
            { 5, 5, 5, 0, 0 },   -- healthy networked state: no-op
            { 0, 0, 5, 0, 5 },   -- nothing anywhere: full networked grant
            { 3, 5, 5, 2, 2 },   -- mixed: strip extras, top up networked
            { 5, 7, 5, 2, 0 },   -- server already at target: drop local strays
            { 0, 0, 0, 0, 0 },   -- no boons: no-op
        }
        for i = 1, #cases do
            local c = cases[i]
            local rm, add = Core.restore_plan(c[1], c[2], c[3])
            if rm ~= c[4] or add ~= c[5] then
                return string.format(
                    "#249 REGRESSION: restore_plan case %d gave (%s,%s), expected (%d,%d)",
                    i, tostring(rm), tostring(add), c[4], c[5])
            end
        end
        if mod._ct249_rebroadcast_wired ~= true then
            return "#249 REGRESSION: reconcile not registered on the peer-parity beacon (beacon missing at module load)"
        end
    end)

    return true
end
