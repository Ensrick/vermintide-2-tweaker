--[[
_ct_chest_revive_owner - Chest of Trials completion recovery (#1159 / #2 file-size refactor).

RESPONSIBILITY
Owns everything ct does to the PARTY at the moment a Chest of Trials completes.
A "Chest of Trials" here is the engine class DeusCursedChestExtension - the
curse encounter that runs a terror event and only reaches STATES.OPEN (3) on the
server once that event ends successfully. It is NOT a DeusChestExtension altar
(boon shrine / weapon shrines), whose reuse economy belongs to
_ct_altar_reuse_owner.

One user-facing decision drives this whole file - the `respawn_on_chest_complete`
toggle, "surviving the trial brings the whole team back" - and everything that
decision implies lives here:
  * the completion detector: the single hook_safe on
    DeusCursedChestExtension._set_state, host-gated, filtered to state OPEN
  * the per-slot triage of all three downed states, ported from
    general_tweaker's proven host-respawn primitive (#116): awaiting-rescue
    hangs are armed for the ordered rescue, bleeding-out players are revived in
    place (skipping disabler-held ones), and dead / queued players get their
    respawn timer zeroed so RespawnHandler spawns them at the active beacon
  * the #299 ordered rescue transaction in full - arm, per-frame process, and
    the deferred tick the entry's mod.update drives - which MOVES a still-
    disabled player next to a living teammate and only THEN frees them, because
    the assisted-respawn beacon sits ~70m ahead and bots will follow it the
    instant the player goes controllable
  * the two post-respawn compensations keyed off the same per-run
    `pending_chest_respawn` marker: the 50% temporary-health override on
    sync_health_state, and the single "revived" wound applied above Recruit

Extracted from chaos_wastes_tweaker_dev.lua entry lines 5781-5803 and 5814-6222
with no behaviour change. Both moved chunks are byte-identical to the
pre-extraction entry region (MD5-proven, zero edits inside either chunk); the
only additions are this header, the ctx binding block below, and the closing
`end` / `return install`. mod:dofile is not a singleton, so the entry calls this
installer EXACTLY once.

DELIBERATE GAP BETWEEN THE TWO CHUNKS, AND THE ONE ORDERING DEVIATION
Entry lines 5805-5812 - the six-line `do` block that dofiles _ct_cot_cost and
_ct_cot_early_reward and forwards their rt_checks - sat BETWEEN the two moved
chunks and deliberately STAYS in the entry: those are the Chest of Trials
activation COST and the early-reward PRESENTATION, a different responsibility
from completion recovery, and folding their installation in here would make this
file the loader for two modules it has nothing to say about.

That leaves exactly one load-order deviation, documented because it is the only
one: the first chunk (three constants plus
`mod._ct_pending_team_teleport = ... or {}` and the `_ct_chest_revive_policy`
dofile) used to run BEFORE that block and now runs after it. It is inert in both
directions and each half is asserted offline:
  * neither _ct_cot_cost, _ct_cot_early_reward, nor their two policy cores
    mentions pending_chest_respawn, CURSED_CHEST_STATE_OPEN, DIFFICULTY_RECRUIT,
    mod._ct_pending_team_teleport, mod._ct_chest_revive_policy or mod._ct299_*,
    so nothing they do at load can read state the move now publishes later
  * _ct_chest_revive_policy.lua is a pure engine-free table (no hook, no
    mod:set, no global write - its own offline test already pins that), so
    loading it after the two CoT modules cannot perturb them either
Hook-registration order is NOT affected: the CoT interaction hooks still
register before the completion-only OPEN hook, which is what the entry comment
above the `do` block asks for.

HOOKS OWNED (each hooked EXACTLY ONCE in the whole mod - VMF silently drops a
second registration on the same (Class, method) pair)
  DeusCursedChestExtension._set_state           [hook_safe]
  PlayerUnitHealthExtension.sync_health_state   [hook]
  RespawnHandler._respawn_player                [hook_safe]
No RPC, no command, no _rt_register moved with this slice. The mod-wide census
is unchanged by the move (97 hook / 29 hook_safe / 7 network_register /
44 command sites, 175 distinct keys), verified before and after by two
independent methods.

COMPOSES WITH, DOES NOT OVERLAP, THE OTHER ct OWNERS
  * _ct_cot_cost owns DeusCursedChestExtension.on_server_interact - the
    WAITING -> RUNNING activation debit. It charges to START a trial; this file
    reacts to one FINISHING. No shared state.
  * _ct_cot_early_reward owns update / can_interact / get_interaction_length /
    get_interaction_action / on_client_interact - reward presentation while
    vanilla state is still RUNNING. It must never write OPEN early, precisely
    because that would falsely trigger the completion recovery this file owns.
  * _ct_chest_revive_policy is the pure lifecycle policy this file drives. The
    split is engine-free decision (there) vs unit/network execution (here): the
    policy names the next action, this file performs it and reports the result.
  * _ct_pickup_spawn_owner and _ct_diag_cursed_chest132 decide where Chests of
    Trials are placed and audit how many exist. Neither touches what happens
    when one completes.
  * _ct_altar_reuse_owner owns DeusChestExtension - a different engine class
    with a purchase step and no terror event. Nothing here may grow an altar
    behaviour, and nothing there may grow a revive.

CROSS-FILE CONTRACT
Entry file-locals the moved chunks closed over, and how each crosses:
  ctx.effective_setting entry :785 forward slot, body assigned at entry :2054.
                        That IS above this install site, so a by-value bind
                        would work today; it crosses as a late-binding wrapper
                        anyway so the binding survives the install site moving,
                        matching _ct_altar_reuse_owner (#1236) where the earlier
                        install position made late binding mandatory. The assert
                        below turns a dropped key into a load-time failure
                        instead of a nil read the first time a trial completes.
`mod` is the installer's first parameter, exactly as the other ct owners take it.
The three constants the chunks declare - CURSED_CHEST_STATE_OPEN,
DIFFICULTY_RECRUIT, pending_chest_respawn - were main-chunk locals with ZERO
references anywhere outside the moved lines (real-parser proven), so they become
install-scope locals with identical closure semantics and cross nothing.

EXPORTS: none. Every seam stays a `mod._ct*` field assigned by the moved code,
because two entry-side readers resolve them off `mod` at CALL time rather than
through an install-time return value:
  mod._ct_chest_teleport_tick     driven each frame by the entry's mod.update
  mod._ct_chest_revive_policy     )
  mod._ct299_arm / _ct299_process ) read by the entry's
  mod._ct_pending_team_teleport   ) issue299_chest_revive_team_teleport_ordered
                                  ) regression check
The moved comment at the head of chunk one still explains those fields as a
dodge around the entry's Lua 5.1 200-locals chunk cap. That was the original
reason and the line is preserved verbatim; the binding reason NOW is the chunk
boundary itself - a separate chunk cannot bind the entry's locals, so `mod` is
the only channel those two readers have.

Owned by: chaos_wastes_tweaker_dev.lua entry point.
Guarded by: qa/lua/tests/test_ct_chest_revive_owner.lua,
qa/lua/tests/test_ct_chest_revive_teleport.lua,
qa/lua/tests/test_ct_entry_decomposition.lua, the #299 rows in
qa/rt_textual_invariants.psd1, and the DeusCursedChestExtension._set_state +
PlayerUnitHealthExtension.sync_health_state / RespawnHandler._respawn_player
rows in chaos_wastes_tweaker_dev/ENGINE_SURFACE.md.
]]

local function install(mod, ctx)

assert(type(ctx) == "table", "_ct_chest_revive_owner requires a context table")
assert(type(ctx.effective_setting) == "function",
    "_ct_chest_revive_owner requires ctx.effective_setting (late-binding wrapper, not the forward slot by value)")

-- The moved chunks below call `effective_setting(...)` unqualified, exactly as
-- they did in the entry. Binding the ctx wrapper to that same name is what lets
-- both chunks stay byte-identical across the move.
local effective_setting = ctx.effective_setting

-- ============================================================
-- Respawn / Revive on Chest of Trials Completion
-- ============================================================

-- CLARIFY: STATES.OPEN = 3 in deus_cursed_chest_extension.lua. State transitions to OPEN at line
-- 174 of that file ONLY on the server, and ONLY when the curse encounter's terror event has ended
-- successfully. Hot-join clients enter HOTJOIN_OPEN (= 4) instead, so they do not trigger here.
local CURSED_CHEST_STATE_OPEN = 3
-- CLARIFY: DifficultyMapping["normal"] = "recruit" (difficulty_settings.lua:424). The string the
-- engine uses internally is "normal"; "recruit" is only the display name.
local DIFFICULTY_RECRUIT = "normal"
-- CLARIFY: peer_id -> true marker, set by the chest hook for any player whose health_state was
-- "dead" at the moment the chest opened. Consumed by the sync_health_state hook (THP override)
-- and the _respawn_player hook (wounded). Cleared in _respawn_player so a future Chest of Trials
-- in the same run can re-mark the same peer.
local pending_chest_respawn = {}

-- #299: peer/local-player keyed rescue jobs. Anchors are plain xyz numbers, never
-- frame-pool vectors. The policy is engine-free and pins move-before-free ordering.
-- These are mod fields because this file sits at Lua 5.1's 200-locals chunk cap.
mod._ct_pending_team_teleport = mod._ct_pending_team_teleport or {}
mod._ct_chest_revive_policy = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_chest_revive_policy")

mod:hook_safe("DeusCursedChestExtension", "_set_state", function(self, state)
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
                    pending_chest_respawn[peer_id] = true   -- arm THP/wounded post-respawn overrides
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
end)

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
        return true, retained and "retained" or "readback-drift"
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

-- CLARIFY: THP override on the dead-respawn path. sync_health_state reads
-- status.game_mode_data.temporary_health_percentage (player_unit_health_extension.lua:111), which
-- the engine sets from difficulty.respawn.temporary_health_percentage at respawn_handler.lua:358
-- (0 on Recruit/Veteran/Champion, 0.25 on Legend). Mutating to 0.5 just before sync reads it
-- means the spawn applies 50% of max-health THP without us touching the network game object
-- ourselves. The is_dead-at-chest-open guard means this only fires for our feature's respawns.
mod:hook("PlayerUnitHealthExtension", "sync_health_state", function(func, self)
    local player = self.player
    local peer_id = player and player.network_id and player:network_id()

    if peer_id and pending_chest_respawn[peer_id] then
        local status = Managers.party:get_player_status(peer_id, player:local_player_id())
        if status and status.game_mode_data and status.game_mode_data.health_state == "respawning" then
            status.game_mode_data.temporary_health_percentage = 0.5
        end
    end

    func(self)
end)

-- CLARIFY: Apply wounded (1 wound) on dead-respawn above Recruit. Mirrors the engine's own
-- post-revive wound at player_unit_health_extension.lua:277 — same reason string ("revived"),
-- which is one of the four valid entries in NetworkLookup.set_wounded_reasons. Recruit is skipped
-- because it has 5 max wounds and no real wounded mechanic in player perception. The flag is
-- cleared here so a subsequent dead-respawn (different chest, same run) re-arms via the chest
-- hook above instead of double-applying.
mod:hook_safe("RespawnHandler", "_respawn_player", function(self, player, profile_index, career_index, respawn_unit, ...)
    local peer_id = player and player.network_id and player:network_id()
    if not peer_id or not pending_chest_respawn[peer_id] then
        return
    end
    pending_chest_respawn[peer_id] = nil

    if Managers.state.difficulty:get_difficulty() == DIFFICULTY_RECRUIT then
        return
    end

    local unit = player.player_unit
    if not unit or not Unit.alive(unit) then
        return
    end

    local t = Managers.time:time("game")
    StatusUtils.set_wounded_network(unit, true, "revived", t)
end)

-- No return value on purpose. Every seam this owner publishes is a `mod._ct*`
-- field assigned by the moved code above, because the entry's mod.update tick
-- and its #299 regression check both resolve them off `mod` at call time. An
-- install-time return would be a second, divergent channel for state that is
-- already reachable, so the shape stays exactly as it was pre-extraction.

end

return install
