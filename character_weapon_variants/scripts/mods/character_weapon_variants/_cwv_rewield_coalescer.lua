-- _cwv_rewield_coalescer.lua -- per-wearer re-wield coalescer + mid-destroy
-- guard (#1145, #660 Wave A).
--
-- WHY: CWV re-wields a remote wearer's husk from two independent arrival
-- edges -- exact-identity arrival on `cwv_item_identity`
-- (character_weapon_variants.lua, the "rebuild the currently wielded husk
-- once" branch) and generated-pair state arrival on
-- `cwv_exact_pair_state_v1` (_cwv_exact_pair_state.apply). Neither knows about
-- the other, nor about cosmetics_tweaker's la-state pulses. On 2026-08-03 a
-- single host illusion click fanned out over four sync channels and drove 8
-- full husk re-wield cycles in 220 ms on the client, collapsing the husk's
-- destroy+respawn into ONE frame (game object 48 destroyed and 52 created in
-- the same millisecond). The stranded old husk's locomotion extension then
-- polled the dead id for 33 frames to an engine fatal: `current_velocity`
-- reads `GameSession.game_object_field(self.game, self.id, "velocity")` with
-- no existence guard at all
-- [src: scripts/unit_extensions/default_player_unit/player_husk_locomotion_extension.lua:59-61].
--
-- FIX, two parts:
--   1. COALESCE. Both re-wield edges enqueue per wearer unit instead of
--      calling `inventory.wield` inline. `drain()` runs from mod.update and
--      executes AT MOST ONE re-wield per wearer per frame; same-frame
--      duplicates merge into the newest request. The queue is swapped out
--      before executors run, so a re-wield that re-enters `request()` lands in
--      the NEXT frame and cannot recurse within a frame.
--   2. MID-DESTROY GUARD. `go_alive()` re-checks the wearer's husk game object
--      immediately before executing. A husk mid-destroy has its pending
--      re-wield DROPPED, never carried across the respawn -- the fresh husk
--      re-derives appearance through the normal spawn path (identity arrival,
--      hot_join_sync, and the pair-state query all re-drive it).
--
-- This coalescer is cwv-local ON PURPOSE. cosmetics_tweaker owns an
-- identically shaped `_cos_rewield_coalescer`; there is deliberately no shared
-- global. Each mod collapsing its own fan-out is what removes the same-frame
-- pile-up, and a cross-mod singleton would couple two independently versioned
-- load orders.
--
-- NEVER destroys units: slot-level `inventory.wield` only, per the
-- POSITION_LOOKUP crash class prohibition on World.destroy_unit for husks.
--
-- Owned by: character_weapon_variants.lua (loads this as `mod._cwv_rewield`,
-- installs its own preserving mod.update wrap for the drain, and routes both
-- re-wield edges through `request`).

local M = {}

-- Source marker for the #1145 regression check. The marker constant AND the
-- check that reads it live in THIS file on purpose: #1148 documented how the
-- OOP decomposition stranded CWV marker constants as file-scope locals in
-- `character_weapon_variants.lua` while the relocated checks in
-- `_cwv_regression_identity.lua` read the bare names as globals (= nil),
-- producing three permanent false FAILs. Co-locating them makes that
-- impossible here.
M.MARKER = "cwv-rewield-coalescer-per-wearer-per-frame-v1"

-- Bounded diagnostics: #1145 is OPEN so the needles are always-on (never a
-- menu toggle, per probe doctrine), but hard-capped so a long session cannot
-- drown console_logs.
local DIAG_LINE_BUDGET = 200

local _queue = {}   -- array of pending records, one per wearer
local _index = {}   -- owner_unit -> record (same tables as _queue)
local _diag_lines = 0
local _diag_capped = false

M.stats = {
    queued = 0,
    merged = 0,
    executed = 0,
    dropped_dead_go = 0,
}

local function _printf(deps, fmt, ...)
    -- `silent` is the regression self-test: it drives the real queue, so it
    -- must neither emit needles nor consume the live diagnostic budget.
    if _diag_capped or (deps and deps.silent) then return end
    local printf_fn = deps and deps.printf or rawget(_G, "printf")
    if type(printf_fn) ~= "function" then return end
    _diag_lines = _diag_lines + 1
    if _diag_lines > DIAG_LINE_BUDGET then
        _diag_capped = true
        pcall(printf_fn, "[cwv:1145] diagnostic budget reached (%d lines); further coalescer lines suppressed",
            DIAG_LINE_BUDGET)
        return
    end
    pcall(printf_fn, fmt, ...)
end

-- Mid-destroy guard. Returns (alive, reason).
--
-- A remote peer's body carries SimpleHuskInventoryExtension, whose `_game` and
-- `_game_object_id` are handed in at init
-- [src: scripts/unit_extensions/default_player_unit/inventory/simple_husk_inventory_extension.lua:6-9].
-- Vanilla refuses to read game-object fields without exactly this check
-- [src: same file:59 and :67], and the husk locomotion extension uses the
-- session-manager form
-- [src: scripts/unit_extensions/default_player_unit/player_husk_locomotion_extension.lua:132-134].
-- The local player's SimpleInventoryExtension has no `_game_object_id`; it is
-- not the crash class, so it reports alive on the Unit.alive check alone.
function M.go_alive(unit, deps)
    deps = deps or {}
    local Unit_ = deps.unit_api or rawget(_G, "Unit")
    if not (unit and Unit_ and Unit_.alive) then return false, "no-unit-api" end
    local ok_alive, alive = pcall(Unit_.alive, unit)
    if not (ok_alive and alive) then return false, "unit-dead" end
    local ScriptUnit_ = deps.script_unit or rawget(_G, "ScriptUnit")
    if not (ScriptUnit_ and ScriptUnit_.has_extension) then return true, "no-extension-api" end
    local ok_ext, inv = pcall(ScriptUnit_.has_extension, unit, "inventory_system")
    if not (ok_ext and inv) then return false, "no-inventory-extension" end
    local go_id = inv._game_object_id
    if not go_id then return true, "not-a-husk" end
    local GameSession_ = deps.game_session or rawget(_G, "GameSession")
    if not (GameSession_ and GameSession_.game_object_exists) then
        return true, "no-session-api"
    end
    local game = inv._game
    if not game then
        local managers = deps.managers or rawget(_G, "Managers")
        local network = managers and managers.state and managers.state.network
        if network and network.game then
            local ok_game, g = pcall(network.game, network)
            game = ok_game and g or nil
        end
    end
    if not game then return false, "no-game-session" end
    local ok_exists, exists = pcall(GameSession_.game_object_exists, game, go_id)
    if not ok_exists then return false, "exists-query-failed" end
    if not exists then return false, "go-destroyed" end
    return true, "alive"
end

-- Enqueue a re-wield for `owner_unit`. `run` is a zero-arg closure performing
-- the wield; it is invoked at most once, from the next `drain`. Same-frame
-- duplicates merge and the NEWEST closure wins, because it reflects the newest
-- arrived identity. Returns (false, "queued"|"merged"|"bad-request").
function M.request(owner_unit, tag, run)
    if not owner_unit or type(run) ~= "function" then return false, "bad-request" end
    local rec = _index[owner_unit]
    if rec then
        rec.run = run
        rec.tag = tag
        rec.merged = rec.merged + 1
        M.stats.merged = M.stats.merged + 1
        return false, "merged"
    end
    rec = { unit = owner_unit, run = run, tag = tag, merged = 0 }
    _index[owner_unit] = rec
    _queue[#_queue + 1] = rec
    M.stats.queued = M.stats.queued + 1
    return false, "queued"
end

-- Identity-arrival adapter. Resolves the sender peer's husk and enqueues ONE
-- re-wield of `slot`, so the arriving exact identity is what the rebuild
-- resolves. Vanilla equipment may arrive before or after the identity; whichever
-- lands second is the rebuild, so the two orderings converge with no polling.
-- The wielded-slot check is repeated at drain time because the wearer may have
-- switched weapons during the deferral. Returns (false, reason).
--
-- #786: `deps.on_verify(unit, inventory, slot, wield_error)` is the POST-DRAIN
-- verification seam. Because the wield is deferred to `drain`, a caller that
-- must prove the re-wield landed cannot read a verdict from this call; it
-- passes `on_verify` and is called back from inside the drain, immediately
-- after the wield. The callback never gates, repairs, or repeats the wield, and
-- a DROPPED request (mid-destroy husk) never calls back at all -- the caller's
-- bounded ledger owns that timeout. `deps.tag` names the requesting edge.
function M.request_peer_rewield(peer_id, slot, deps)
    if not (peer_id and slot) then return false, "bad-peer-slot" end
    deps = deps or {}
    local managers = deps.managers or rawget(_G, "Managers")
    local pm = managers and managers.player
    if not (pm and pm.player_from_peer_id) then return false, "no-player-manager" end
    local ok_p, player = pcall(pm.player_from_peer_id, pm, peer_id)
    local unit = ok_p and player and player.player_unit
    local Unit_ = deps.unit_api or rawget(_G, "Unit")
    if not (unit and Unit_ and Unit_.alive and Unit_.alive(unit)) then
        return false, "wearer-not-spawned"
    end
    local ScriptUnit_ = deps.script_unit or rawget(_G, "ScriptUnit")
    if not (ScriptUnit_ and ScriptUnit_.extension) then return false, "no-extension-api" end
    local ok_i, inventory = pcall(ScriptUnit_.extension, unit, "inventory_system")
    if not (ok_i and inventory and type(inventory.wield) == "function") then
        return false, "no-inventory"
    end
    if inventory.wielded_slot ~= slot then return false, "slot-not-wielded" end
    local on_verify = deps.on_verify
    local tag = deps.tag or ("identity-arrival:" .. tostring(slot))
    return M.request(unit, tag, function()
        local wield_error
        if inventory.wielded_slot == slot then
            local ok, err = pcall(inventory.wield, inventory, slot)
            if not ok then wield_error = err end
        else
            wield_error = "slot-not-wielded"
        end
        if type(on_verify) == "function" then
            pcall(on_verify, unit, inventory, slot, wield_error)
        end
    end)
end

-- Execute the frame's pending re-wields: at most one per wearer, each gated on
-- a live game object. Returns (executed, dropped).
function M.drain(deps)
    local pending = _queue
    local n = #pending
    if n == 0 then return 0, 0 end
    -- Swap FIRST: an executor that re-enters request() must land in the next
    -- frame's queue, never in the one we are walking.
    _queue, _index = {}, {}
    local executed, dropped, merged_total = 0, 0, 0
    for i = 1, n do
        local rec = pending[i]
        merged_total = merged_total + rec.merged
        local alive, reason = M.go_alive(rec.unit, deps)
        if not alive then
            dropped = dropped + 1
            M.stats.dropped_dead_go = M.stats.dropped_dead_go + 1
            _printf(deps, "[cwv:1145] DROP wearer=%s tag=%s merged=%d reason=%s",
                tostring(rec.unit), tostring(rec.tag), rec.merged, tostring(reason))
        else
            executed = executed + 1
            M.stats.executed = M.stats.executed + 1
            pcall(rec.run)
        end
    end
    if merged_total > 0 or dropped > 0 then
        _printf(deps, "[cwv:1145] DRAIN depth=%d executed=%d merged=%d dropped_dead_go=%d totals(q=%d m=%d x=%d d=%d)",
            n, executed, merged_total, dropped,
            M.stats.queued, M.stats.merged, M.stats.executed, M.stats.dropped_dead_go)
    end
    return executed, dropped
end

-- Test/inspection seam: current queue depth without draining.
function M.depth()
    return #_queue
end

-- Install the per-frame drain as a PRESERVING mod.update wrap, the same shape
-- `_lib_peer_parity` uses. Returns true when the wrap was installed.
function M.install(mod, deps)
    if type(mod) ~= "table" and type(mod) ~= "userdata" then return false end
    if mod._cwv_rewield_update_installed then return false end
    local previous_update = mod.update
    mod.update = function(dt)
        if previous_update then pcall(previous_update, dt) end
        M.drain(deps)
    end
    mod._cwv_rewield_update_installed = true
    return true
end

-- Self-test scaffolding. The regression checks drive the REAL queue (that is
-- the point -- a presence-only check is what let the 0.9.65-dev self-heal ship
-- inert for 3+ versions), so they must leave no trace in the live evidence:
-- silent, and the needle totals are restored afterwards.
local function _selftest_deps(force_alive)
    local deps = { silent = true }
    if force_alive then
        deps.unit_api = { alive = function() return true end }
        -- An inventory extension with no `_game_object_id` is the local-player
        -- shape, which go_alive reports alive without touching GameSession.
        deps.script_unit = { has_extension = function() return {} end }
    end
    return deps
end

local function _stats_snapshot()
    local s = M.stats
    return { s.queued, s.merged, s.executed, s.dropped_dead_go }
end

local function _stats_restore(snap)
    local s = M.stats
    s.queued, s.merged, s.executed, s.dropped_dead_go = snap[1], snap[2], snap[3], snap[4]
end

-- Register the #1145 regression checks.
--
-- The contract rule from #660: disconnecting the live hook MUST fail the
-- check. These therefore assert the choke point is routed through this module
-- and that the queue actually coalesces and actually drops a dead wearer --
-- not merely that the functions exist.
function M.install_checks(mod, rt_register)
    if type(rt_register) ~= "function" then return false end

    rt_register("cwv_issue1145_coalescer_marker", function()
        if M.MARKER ~= "cwv-rewield-coalescer-per-wearer-per-frame-v1" then
            return "re-wield coalescer source marker missing/changed (#1145 fix reverted?)"
        end
        if mod._cwv_rewield ~= M then
            return "mod._cwv_rewield is not this module (#1145 coalescer unwired)"
        end
        if not mod._cwv_rewield_update_installed then
            return "coalescer drain not wired into mod.update (#1145 queue would never flush)"
        end
        if type(M.request) ~= "function" or type(M.drain) ~= "function"
                or type(M.go_alive) ~= "function" then
            return "coalescer API incomplete (request/drain/go_alive)"
        end
        return nil
    end)

    rt_register("cwv_issue1145_coalescer_live", function()
        local snap = _stats_snapshot()
        local before = M.depth()
        local fired = 0
        local sentinel = {}
        local _, why = M.request(sentinel, "rt-selftest", function() fired = fired + 1 end)
        if why ~= "queued" then
            _stats_restore(snap)
            return "coalescer did not queue a fresh request (got " .. tostring(why) .. ")"
        end
        local _, why2 = M.request(sentinel, "rt-selftest-dup", function() fired = fired + 1 end)
        if why2 ~= "merged" then
            _stats_restore(snap)
            return "same-frame duplicate did not merge (got " .. tostring(why2) .. ")"
        end
        if M.depth() ~= before + 1 then
            _stats_restore(snap)
            return "duplicate request grew the queue (coalescing broken)"
        end
        M.drain(_selftest_deps(true))
        _stats_restore(snap)
        if fired ~= 1 then
            return "drain ran the wearer's re-wield " .. tostring(fired) .. " times, expected exactly 1"
        end
        if M.depth() ~= 0 then
            return "drain left " .. tostring(M.depth()) .. " entries queued"
        end
        return nil
    end)

    rt_register("cwv_issue1145_mid_destroy_guard", function()
        if M.go_alive(nil) then
            return "go_alive(nil) reported alive (mid-destroy guard inert)"
        end
        local snap = _stats_snapshot()
        local ran = false
        M.request({}, "rt-dead", function() ran = true end)
        -- Real liveness deps against a non-unit sentinel: the probe must fail.
        local executed, dropped = M.drain(_selftest_deps(false))
        _stats_restore(snap)
        if ran or executed ~= 0 or dropped ~= 1 then
            return string.format("dead-wearer re-wield was not dropped (ran=%s executed=%d dropped=%d)",
                tostring(ran), executed, dropped)
        end
        return nil
    end)

    return true
end

return M
