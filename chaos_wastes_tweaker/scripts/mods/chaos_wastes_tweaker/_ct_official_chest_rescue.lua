--[[
_ct_official_chest_rescue - selective #299 move-before-free lifecycle.
Derived from _ct_chest_revive_owner.lua in Dev tree a179354e.
Owns no VMF hooks: the existing official _set_state hook calls on_state.
The official health/respawn hooks and their pending marker remain in main.
State carries scalar anchors only; native vectors are rebuilt within a frame.
Owned by: chaos_wastes_tweaker.lua. Consumed via: mod:dofile installer.
]]
return function(mod, ctx)
    assert(type(ctx) == "table" and type(ctx.effective_setting) == "function",
        "_ct_official_chest_rescue requires effective_setting")
    assert(type(ctx.mark_dead_respawn) == "function",
        "_ct_official_chest_rescue requires existing pending-respawn marker")
    local effective_setting = ctx.effective_setting
-- ============================================================
-- Respawn / Revive on Chest of Trials Completion
-- ============================================================

-- CLARIFY: STATES.OPEN = 3 in deus_cursed_chest_extension.lua. State transitions to OPEN at line
-- 174 of that file ONLY on the server, and ONLY when the curse encounter's terror event has ended
-- successfully. Hot-join clients enter HOTJOIN_OPEN (= 4) instead, so they do not trigger here.
local CURSED_CHEST_STATE_OPEN = 3
-- #299: peer/local-player keyed rescue jobs. Anchors are plain xyz numbers, never
-- frame-pool vectors. The policy is engine-free and pins move-before-free ordering.
-- These are mod fields because this file sits at Lua 5.1's 200-locals chunk cap.
mod._ct_pending_team_teleport = mod._ct_pending_team_teleport or {}
mod._ct_chest_revive_policy = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker/_ct_chest_revive_policy")

local function on_state(self, state)
    if state ~= CURSED_CHEST_STATE_OPEN then
        return
    end
    -- raw printf so it lands on a mod-logging-OFF host (the user's setup)
    pcall(printf, "[ct-chest-revive] chest OPEN: setting=%s is_server=%s",
        tostring(effective_setting("respawn_on_chest_complete")),
        tostring(Managers and Managers.player and Managers.player.is_server))

    if not effective_setting("respawn_on_chest_complete") then
        return
    end
    if not Managers.player or not Managers.player.is_server then
        return
    end

    local game_mode = Managers.state and Managers.state.game_mode
    if not game_mode then
        return
    end

    local side = Managers.state.side and Managers.state.side:get_side_from_name("heroes")
    local party = side and side.party
    local occupied_slots = party and party.occupied_slots

    -- #116 (v0.7.177-dev): the prior body relied solely on
    -- `game_mode:force_respawn_dead_players()` (which only zeroes respawn timers) and
    -- never handled AWAITING-RESCUE players (hanging at a beacon, ready for assisted
    -- respawn) — so a downed teammate just stayed down and the feature looked dead.
    -- Now we port general_tweaker's proven per-player respawn primitive
    -- (_gt_level_control.lua `_gt_host_respawn`) and apply it to every party slot,
    -- covering all three downed states:
    --   * awaiting-rescue (hanging)  -> move beside party, then assisted-respawn
    --   * knocked-down (bleeding out) -> StatusUtils.set_revived_network (revive in place)
    --   * dead / queued for respawn   -> zero respawn_timer so RespawnHandler.server_update
    --                                    spawns them at the active beacon shortly
    -- Host-authoritative (already gated on is_server above).
    --
    -- #299: capture the chest position ONCE as scalar data. It selects the living
    -- teammate who was nearest the completed trial, but the rescued unit is moved
    -- there while still disabled and is freed only after that move succeeds.
    local chest_anchor
    do
        local chest_unit = self._unit
        if chest_unit and Unit.alive(chest_unit) then
            local ok, p = pcall(Unit.world_position, chest_unit, 0)
            if ok and p then
                local copied, x, y, z = pcall(function() return p.x, p.y, p.z end)
                if copied then chest_anchor = { x = x, y = y, z = z } end
            end
        end
    end

    if occupied_slots then
        for i = 1, #occupied_slots do
            local status = occupied_slots[i]
            local data = status.game_mode_data
            local peer_id = status.peer_id
            local local_player_id = status.local_player_id

            if peer_id and local_player_id then
                local player = Managers.player:player(peer_id, local_player_id)
                local unit = player and player.player_unit
                local health_state = data and data.health_state or "?"

                local status_ext = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "status_system") or nil
                local is_knocked = status_ext and status_ext.is_knocked_down and status_ext:is_knocked_down() or false
                local is_disabled_pact = status_ext and status_ext.is_disabled_by_pact_sworn and status_ext:is_disabled_by_pact_sworn() or false
                local is_awaiting = status_ext and status_ext.is_ready_for_assisted_respawn and status_ext:is_ready_for_assisted_respawn() or false
                local action = "none"

                if is_awaiting and rawget(_G, "StatusUtils") and StatusUtils.set_respawned_network then
                    -- #299 regression: do NOT clear awaiting-rescue here. July 20 logs
                    -- prove bots can select the newly-alive player at the temporary beacon
                    -- before the old deferred teleport runs. Arm the job, then let its
                    -- synchronous first pass MOVE the still-disabled player before FREE.
                    action = "armed-move-before-free"
                    if chest_anchor and mod._ct299_arm then
                        mod._ct299_arm(peer_id, local_player_id, player, chest_anchor, true)
                    end
                elseif is_knocked and not is_disabled_pact and StatusUtils and StatusUtils.set_revived_network then
                    -- bleeding out -> revive in place (skip disabler-held players).
                    -- Already with the team where they fell -> NOT armed for teleport.
                    StatusUtils.set_revived_network(unit, true, nil)
                    action = "revived-knocked"
                elseif data and (health_state == "dead" or data.respawn_timer ~= nil) then
                    -- fully dead / in the respawn queue -> spawn at the active beacon.
                    -- #299: that beacon is ~70m ahead of the front player, so arm the
                    -- move-before-free transaction for when the hanging unit exists.
                    data.respawn_timer = 0
                    ctx.mark_dead_respawn(peer_id) -- preserve the existing official THP/wound owner
                    action = "respawn-timer-cleared"
                    if chest_anchor and mod._ct299_arm then
                        -- freed=nil: the unit spawns HANGING at the beacon a few frames later
                        -- (RespawnHandler sends ready_for_assisted_respawn=true). The tick
                        -- then performs the same MOVE-before-FREE transaction.
                        mod._ct299_arm(peer_id, local_player_id, player, chest_anchor, false)
                    end
                end

                pcall(printf, "[ct-chest-revive] slot=%d peer=%s health=%s knocked=%s awaiting=%s disabled=%s -> %s",
                    i, tostring(peer_id), tostring(health_state), tostring(is_knocked),
                    tostring(is_awaiting), tostring(is_disabled_pact), action)
            end
        end
    end

    -- Belt-and-suspenders: also fire the engine's team-wide dead-respawn so any dead
    -- player our per-slot health_state check didn't classify still respawns (idempotent
    -- — it only zeroes respawn timers). Per feedback_redundant_safeguards_ok.md.
    if game_mode.force_respawn_dead_players then
        game_mode:force_respawn_dead_players()
    end
end

-- ============================================================
-- #299: return chest-revived players to the team
-- ============================================================
-- July 20 host evidence disproved the previous diagnosis: the player DID become
-- controllable, but the branch stopped before both its success and no-anchor logs.
-- It read POSITION_LOOKUP from mod.update, where values can be dead frame-pool
-- vectors (BUG_CLASSES section 21), and its pcall discarded the exception. The
-- same trace showed a bot teleporting 62.7m toward the temporary rescue beacon
-- immediately before the player's health_state became alive.
--
-- Correct order: while still disabled, unlink and MOVE beside a living teammate,
-- broadcast the move, then FREE. Dead players wait only until RespawnHandler has
-- created their hanging unit. Once server health_state is alive, verify retention
-- and permit one corrective move. Errors are visible and bounded.
do
    local policy = mod._ct_chest_revive_policy

    local function _game_time()
        local tm = Managers.time
        if not (tm and tm.time) then return nil end
        local ok, t = pcall(tm.time, tm, "game")
        return ok and type(t) == "number" and t or nil
    end

    local function _world_xyz(unit)
        local ok, x, y, z = pcall(function()
            local p = Unit.world_position(unit, 0)
            return p.x, p.y, p.z
        end)
        if ok and type(x) == "number" and type(y) == "number" and type(z) == "number" then
            return x, y, z
        end
        return nil
    end

    local function _nearest_controllable_teammate(anchor, exclude_unit)
        local pm = Managers.player
        local players = pm and pm.human_and_bot_players and pm:human_and_bot_players()
        if not players then return nil end
        local best, best_d, best_x, best_y, best_z
        for _, player in pairs(players) do
            local unit = player and player.player_unit
            if unit and unit ~= exclude_unit and Unit.alive(unit) then
                local status = ScriptUnit.has_extension(unit, "status_system")
                local valid, disabled = pcall(function() return status and status:is_disabled() end)
                local x, y, z = _world_xyz(unit)
                if valid and status and not disabled and x then
                    local dx, dy, dz = x - anchor.x, y - anchor.y, z - anchor.z
                    local distance = dx * dx + dy * dy + dz * dz
                    if not best_d or distance < best_d then
                        best, best_d, best_x, best_y, best_z = unit, distance, x, y, z
                    end
                end
            end
        end
        return best, best_x, best_y, best_z
    end

    local function _retained_near_team(entry, unit)
        local _, tx, ty, tz = _nearest_controllable_teammate(entry.anchor, unit)
        local ux, uy, uz = _world_xyz(unit)
        if not (tx and ux) then return nil end
        local dx, dy, dz = ux - tx, uy - ty, uz - tz
        return dx * dx + dy * dy + dz * dz <= policy.RETAIN_DISTANCE_SQ
    end

    local function _move_to_team(entry, unit, unlink_first)
        local teammate, x, y, z = _nearest_controllable_teammate(entry.anchor, unit)
        if not teammate then return nil, "no-controllable-team-anchor" end
        local locomotion = ScriptUnit.has_extension(unit, "locomotion_system")
        if not (locomotion and locomotion.teleport_to) then
            return false, "locomotion-extension-missing"
        end

        if unlink_first then
            if not (rawget(_G, "LocomotionUtils") and LocomotionUtils.disable_linked_movement) then
                return false, "disable-linked-movement-missing"
            end
            local unlinked, unlink_err = pcall(LocomotionUtils.disable_linked_movement, unit)
            if not unlinked then return false, "unlink-failed: " .. tostring(unlink_err) end
        end

        local pos = Vector3(x, y, z)
        local rot = Unit.local_rotation(teammate, 0)
        -- #299: this write is KEPT, but as a guarded in-place REFRESH, never a seed.
        -- Flow analysis: nothing in this transaction reads the lookup back - the
        -- retention readback below and _retained_near_team both re-derive live
        -- positions via _world_xyz (Unit.world_position). The one consumer is the
        -- vanilla callee: teleport_to's last line calls set_falling_height
        -- (player_unit_locomotion_extension.lua:1022), which reads
        -- POSITION_LOOKUP[unit].z (generic_status_extension.lua:2590). This
        -- transaction runs in the mod.update phase, BEFORE StateIngame.pre_update's
        -- UPDATE_POSITION_LOOKUP (state_ingame.lua:808), so the stored entry is a
        -- dead frame-pool handle (BUG_CLASSES section 21); without the refresh the
        -- pcall'd teleport_to raises AFTER the player already moved and the whole
        -- move-then-free transaction aborts. The value must stay a raw Vector3
        -- (vanilla readers do .z and Vector3.distance on it, so Vector3Box cannot
        -- go here); per the BUG_CLASSES 21 fix template the residual lives one
        -- frame - the engine bulk refresh rewrites the maintained entry next
        -- frame, matching vanilla's own raw seeding (unit_spawner.lua:302).
        -- The lookup[unit] presence guard is the fix for the dangling-residual
        -- risk: set_falling_height no-ops when the entry is absent (its ALIVE
        -- guard; ALIVE = POSITION_LOOKUP, global_utils.lua:15), and CREATING an
        -- entry the engine is not maintaining would both flip ALIVE[unit] truthy
        -- for every consumer and leave expired frame-pool userdata behind.
        local lookup = rawget(_G, "POSITION_LOOKUP")
        if lookup and lookup[unit] then lookup[unit] = Vector3(x, y, z) end
        local moved, move_err = pcall(locomotion.teleport_to, locomotion, pos, rot)
        if not moved then return false, "teleport-failed: " .. tostring(move_err) end

        local network = Managers.state and Managers.state.network
        local go_id = network and network:unit_game_object_id(unit)
        if not (go_id and network.network_transmit) then
            return false, "network-game-object-missing"
        end
        local sent, send_err = pcall(network.network_transmit.send_rpc_clients,
            network.network_transmit, "rpc_teleport_unit_to", go_id, pos, rot)
        if not sent then return false, "teleport-rpc-failed: " .. tostring(send_err) end

        local ux, uy, uz = _world_xyz(unit)
        local retained = ux and ((ux - x) * (ux - x) + (uy - y) * (uy - y)
            + (uz - z) * (uz - z) <= policy.RETAIN_DISTANCE_SQ)
        if not retained then return false, "readback-drift" end
        return true, "retained"
    end

    local function _health_alive(entry)
        local party_manager = Managers.party
        local status = party_manager and party_manager.get_player_status
            and party_manager:get_player_status(entry.peer_id, entry.lpid)
        return status and status.game_mode_data
            and status.game_mode_data.health_state == "alive" or false
    end

    local function _process(key, entry, dt)
        entry.elapsed = (entry.elapsed or 0) + (dt or 0)
        local now = _game_time()
        local timed_out = (now and entry.deadline and now >= entry.deadline)
            or (not now and entry.elapsed >= policy.TIMEOUT_SECONDS)
        local player = entry.player
        if not (player and player.player_unit) then
            player = Managers.player:player(entry.peer_id, entry.lpid) or player
            entry.player = player or entry.player
        end
        local unit = player and player.player_unit
        local alive = unit and Unit.alive(unit) and true or false
        local status = alive and ScriptUnit.has_extension(unit, "status_system") or nil
        local awaiting = status and status.is_ready_for_assisted_respawn
            and status:is_ready_for_assisted_respawn() or false
        local health_alive = _health_alive(entry)
        local retained
        if entry.moved and entry.freed and health_alive then
            retained = _retained_near_team(entry, unit)
        end
        local action = policy.next_action(entry, {
            alive = alive,
            awaiting = awaiting,
            health_alive = health_alive,
            retained = retained,
            timed_out = timed_out,
        })
        local sig = table.concat({ tostring(alive), tostring(awaiting),
            tostring(health_alive), tostring(entry.moved), tostring(entry.freed),
            tostring(retained), tostring(action) }, "/")
        if entry._last_sig ~= sig then
            entry._last_sig = sig
            pcall(printf, "[ct:299] key=%s alive=%s awaiting=%s health_alive=%s moved=%s freed=%s retained=%s action=%s",
                tostring(key), tostring(alive), tostring(awaiting), tostring(health_alive),
                tostring(entry.moved), tostring(entry.freed), tostring(retained), action)
        end

        if action == "move_then_free" then
            local moved, detail = _move_to_team(entry, unit, true)
            if moved == nil then
                if entry._last_wait ~= detail then
                    entry._last_wait = detail
                    pcall(printf, "[ct:299] key=%s waiting: %s", tostring(key), detail)
                end
                return false
            end
            if not moved then error(detail) end
            entry.moved = true
            pcall(printf, "[ct:299] key=%s pre-move complete (%s); now freeing", tostring(key), detail)
            StatusUtils.set_respawned_network(unit, true, unit)
            entry.freed = true
            pcall(printf, "[ct:299] key=%s assisted-respawn recovery armed AFTER move", tostring(key))
            return false
        elseif action == "free" then
            StatusUtils.set_respawned_network(unit, true, unit)
            entry.freed = true
            return false
        elseif action == "correct_once" then
            local moved, detail = _move_to_team(entry, unit, false)
            if moved == nil then return false end
            entry.corrections = (entry.corrections or 0) + 1
            if not moved then error(detail) end
            pcall(printf, "[ct:299] key=%s recovery drift corrected once (%s)", tostring(key), detail)
            return false
        elseif action == "complete" then
            local result = retained == false and "DEGRADED" or "PASS"
            pcall(printf, "[ct:299] key=%s %s move-before-free retained=%s corrections=%d",
                tostring(key), result, tostring(retained), entry.corrections or 0)
            return true
        elseif action == "drop" then
            pcall(printf, "[ct:299] key=%s DROPPED timeout=%s errors=%d state=%s",
                tostring(key), tostring(timed_out), entry.errors or 0, tostring(sig))
            return true
        end
        return false
    end

    mod._ct299_process = function(key, entry, dt)
        local ok, drop_or_err = pcall(_process, key, entry, dt)
        if ok then return drop_or_err end
        entry.errors = (entry.errors or 0) + 1
        pcall(printf, "[ct:299] FAILED key=%s error=%s attempt=%d/%d",
            tostring(key), tostring(drop_or_err), entry.errors, policy.MAX_ERRORS)
        return entry.errors >= policy.MAX_ERRORS
    end

    mod._ct299_arm = function(peer_id, local_player_id, player, anchor, process_now)
        local entry = policy.new_entry(peer_id, local_player_id, player, anchor, _game_time())
        if not entry then
            pcall(printf, "[ct:299] arm rejected peer=%s lpid=%s (missing scalar chest anchor)",
                tostring(peer_id), tostring(local_player_id))
            return nil
        end
        mod._ct_pending_team_teleport[entry.key] = entry
        pcall(printf, "[ct:299] armed key=%s deadline=%s process_now=%s",
            entry.key, tostring(entry.deadline), tostring(process_now))
        if process_now and mod._ct299_process(entry.key, entry, 0) then
            mod._ct_pending_team_teleport[entry.key] = nil
        end
        return entry
    end

    mod._ct_pending_team_teleport = mod._ct_pending_team_teleport or {}
    mod._ct_chest_teleport_tick = function(dt)
        local pending = mod._ct_pending_team_teleport
        if not pending or next(pending) == nil then return end
        if not (Managers.player and Managers.player.is_server) then
            for key in pairs(pending) do pending[key] = nil end
            return
        end
        for key, entry in pairs(pending) do
            if mod._ct299_process(key, entry, dt) then pending[key] = nil end
        end
    end
end


    if ctx.rt_register then
        ctx.rt_register("issue299_chest_revive_move_before_free", function()
            local policy = mod._ct_chest_revive_policy
            local entry = policy.new_entry("peer", 2, {}, {x=1,y=2,z=3}, 10)
            if not entry or entry.key ~= "peer/2" or entry.deadline ~= 40
                or policy.next_action(entry, {alive=true,awaiting=true}) ~= "move_then_free"
                or type(mod._ct299_arm) ~= "function"
                or type(mod._ct299_process) ~= "function" then
                return "#299 ordered rescue policy/wiring missing"
            end
        end)
    end
    return { on_state = on_state, tick = mod._ct_chest_teleport_tick }
end
