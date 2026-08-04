-- _cos_rewield_coalescer.lua -- per-wearer re-wield coalescer + mid-destroy
-- guard (#1145, #660 Wave A).
--
-- WHY: a single host illusion click fans out over four independent sync
-- channels (cwv exact identity, the vanilla equipment wire, two la-state
-- OFFHAND-MESH emits under two different slot keys, and a cos emit). Each one
-- lands in this mod's apply path and each one drives a wield PULSE -- the
-- melee<->ranged<->melee pair in `_ensure_offhand_mesh` / `mod._la_native_pulse`
-- -- so one click produced 8 full husk re-wield cycles in 220 ms on the client
-- (2026-08-03 session). That churn collapsed the husk's profile-reload
-- destroy+respawn into a single frame: game object 48 was destroyed and 52
-- created in the same millisecond, the old husk was never despawned, and its
-- locomotion extension kept polling the dead id for 33 frames until the engine
-- fatal `third_person_idle_fullbody_animation_control.lua:69` via
-- `PlayerHuskLocomotionExtension.current_velocity`
-- [src: scripts/unit_extensions/default_player_unit/player_husk_locomotion_extension.lua:59-61
--  -- an UNGUARDED GameSession.game_object_field read].
--
-- The channels are permanent by design: modded skin keys are unconditionally
-- nulled on the vanilla wire after the 2026-07-18 non-mod-peer CTD, so the
-- parallel transports are how appearance reaches a husk at all. The fix is
-- therefore to coalesce them, not to remove them.
--
-- FIX, two parts:
--   1. COALESCE. Every mod-initiated wield pulse is enqueued per wearer unit
--      instead of firing inline. `drain()` (called once from mod.update)
--      executes AT MOST ONE pulse per wearer per frame; same-frame duplicates
--      merge into the newest request. The queue is swapped out before the
--      executors run, so a pulse that re-enters `request()` lands in the NEXT
--      frame's queue and can never recurse within a frame.
--   2. MID-DESTROY GUARD. Immediately before executing, `go_alive()` re-checks
--      that the wearer's husk game object still exists. A husk whose game
--      object is gone or being torn down gets its pending pulse DROPPED, never
--      queued across the respawn -- the fresh husk re-derives its appearance
--      through the normal spawn path.
--
-- This coalescer is cos-local ON PURPOSE. character_weapon_variants owns an
-- identically shaped `_cwv_rewield_coalescer`; there is no shared global. Each
-- mod collapsing its own fan-out is what removes the same-frame pile-up, and a
-- cross-mod singleton would couple two independently versioned load orders.
--
-- NEVER destroys units. The pulse is slot-level `inventory.wield` only -- the
-- POSITION_LOOKUP crash class forbids `World.destroy_unit` on player husks.
--
-- Owned by: cosmetics_tweaker.lua (loads this as `mod._cos_rewield`, routes
-- `_ensure_offhand_mesh` + `mod._la_native_pulse` through `request`, and calls
-- `drain` from mod.update).

local M = {}

-- Source marker for the #1145 regression check. The marker constant AND the
-- check that reads it live in THIS file on purpose: issue #1148 documented how
-- the OOP decomposition stranded marker constants as file-scope locals in one
-- module while the relocated checks read them as globals (= nil), producing
-- permanent false FAILs. Keeping both here makes that failure mode impossible.
M.MARKER = "cos-rewield-coalescer-per-wearer-per-frame-v1"

-- Bounded diagnostics: the issue is OPEN so the needles are always-on (never
-- a menu toggle, per the probe doctrine), but a long session must not drown
-- console_logs. One summary line per non-trivial drain, hard-capped.
local DIAG_LINE_BUDGET = 200

local _queue = {}   -- array of pending records, one per wearer
local _index = {}   -- owner_unit -> record (same tables as _queue)
local _diag_lines = 0
local _diag_capped = false

M.stats = {
    queued = 0,          -- requests that opened a new per-wearer slot
    merged = 0,          -- requests folded into an already-pending slot
    executed = 0,        -- pulses that actually reached the engine
    dropped_dead_go = 0, -- pulses refused because the husk game object was gone
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
        pcall(printf_fn, "[cos:1145] diagnostic budget reached (%d lines); further coalescer lines suppressed",
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
-- Vanilla itself refuses to read game-object fields without this exact check
-- [src: same file:59 and :67 -- `if GameSession.game_object_exists(self._game,
-- self._game_object_id) then`], and the husk locomotion extension uses the
-- session-manager form
-- [src: scripts/unit_extensions/default_player_unit/player_husk_locomotion_extension.lua:132-134].
-- The local player's SimpleInventoryExtension has no `_game_object_id` at all;
-- it is not the crash class, so it reports alive on the Unit.alive check alone.
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

-- Enqueue a wield pulse for `owner_unit`. `run` is a zero-arg closure that
-- performs the pulse; it is invoked at most once, from the next `drain`.
-- Duplicate requests for the same wearer inside one frame merge -- the NEWEST
-- closure wins, because it reflects the newest desired appearance state.
-- Returns (false, "queued"|"merged") or (false, "bad-request"); the false is
-- the caller-visible "did not pulse synchronously" answer.
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

-- Execute the frame's pending pulses: at most one per wearer, each gated on a
-- live game object. Returns (executed, dropped).
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
            _printf(deps, "[cos:1145] DROP wearer=%s tag=%s merged=%d reason=%s",
                tostring(rec.unit), tostring(rec.tag), rec.merged, tostring(reason))
        else
            executed = executed + 1
            M.stats.executed = M.stats.executed + 1
            pcall(rec.run)
        end
    end
    if merged_total > 0 or dropped > 0 then
        _printf(deps, "[cos:1145] DRAIN depth=%d executed=%d merged=%d dropped_dead_go=%d totals(q=%d m=%d x=%d d=%d)",
            n, executed, merged_total, dropped,
            M.stats.queued, M.stats.merged, M.stats.executed, M.stats.dropped_dead_go)
    end
    return executed, dropped
end

-- Test/inspection seam: current queue depth without draining.
function M.depth()
    return #_queue
end

-- Pulse re-entrancy. A pulse's own `inventory.wield` re-enters the mod's apply
-- path, so both pulse sites bracket their wields with this flag and refuse to
-- start while it is set. The coalescer owns it because the coalescer is now the
-- only thing that runs a pulse.
local _pulsing = false

function M.pulsing() return _pulsing end

-- The pulse itself: wield the alternate slot, then return to the original.
-- Slot-level wield ONLY -- never World.destroy_unit on a player husk
-- (POSITION_LOOKUP crash class). Returns (ok_out, ok_back).
function M.pulse_now(inv, pulse_slot, orig_slot)
    _pulsing = true
    local ok1 = pcall(inv.wield, inv, pulse_slot)
    local ok2 = pcall(inv.wield, inv, orig_slot)
    _pulsing = false
    return ok1, ok2
end

-- Pick the slot to pulse THROUGH. A pulse wields an alternate weapon slot and
-- returns to the original, so nothing the player is holding visibly changes.
-- `_ensure_offhand_mesh` and `mod._la_native_pulse` resolved this identically
-- with two byte-identical inline blocks; both now call here, which is also what
-- keeps the #1145 wiring inside the entry file's decomposition ceiling.
-- Returns nil when the wearer has no second weapon slot to bounce off.
function M.alternate_slot(slots, orig_slot)
    if type(slots) ~= "table" or not orig_slot then return nil end
    if orig_slot == "slot_melee" and slots["slot_ranged"] then return "slot_ranged" end
    if orig_slot == "slot_ranged" and slots["slot_melee"] then return "slot_melee" end
    for sn, sd in pairs(slots) do
        if sn ~= orig_slot and sd and (sn == "slot_melee" or sn == "slot_ranged") then
            return sn
        end
    end
    return nil
end

-- Self-test scaffolding. The regression checks drive the REAL queue (that is
-- the point -- a presence-only check is what let the 0.9.65-dev self-heal ship
-- inert), so they must leave no trace in the live evidence: silent printf, and
-- the needle totals are restored afterwards.
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

-- Register the #1145 regression checks. Called from cosmetics_tweaker.lua once
-- `_rt_register` exists.
--
-- The contract rule from #660: disconnecting the live hook MUST fail the check.
-- `cos_issue1145_coalescer_live` therefore asserts the choke point is actually
-- routed through this module (mod._cos_rewield identity + a drained request),
-- not merely that the functions exist -- the 0.9.65-dev self-heal shipped inert
-- for 3+ versions precisely because its check only proved presence.
function M.install_checks(mod, rt_register)
    if type(rt_register) ~= "function" then return false end

    rt_register("cos_issue1145_coalescer_marker", function()
        if M.MARKER ~= "cos-rewield-coalescer-per-wearer-per-frame-v1" then
            return "re-wield coalescer source marker missing/changed (#1145 fix reverted?)"
        end
        if mod._cos_rewield ~= M then
            return "mod._cos_rewield is not this module (#1145 coalescer unwired)"
        end
        if type(M.request) ~= "function" or type(M.drain) ~= "function"
                or type(M.go_alive) ~= "function" then
            return "coalescer API incomplete (request/drain/go_alive)"
        end
        return nil
    end)

    -- Live-wiring assertion: push a sentinel request through the real queue and
    -- prove drain executes it exactly once and then empties. If someone routes
    -- the pulse sites back to an inline `inv.wield`, the pulse sites stop
    -- feeding this queue -- caught by the paired source check below.
    rt_register("cos_issue1145_coalescer_live", function()
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
            return "drain ran the wearer's pulse " .. tostring(fired) .. " times, expected exactly 1"
        end
        if M.depth() ~= 0 then
            return "drain left " .. tostring(M.depth()) .. " entries queued"
        end
        return nil
    end)

    -- Mid-destroy guard must actually refuse. A nil wearer can never be
    -- reported alive, and a wearer that fails the liveness probe must have its
    -- pending pulse DROPPED rather than executed. If either passes through,
    -- the guard is inert and #1145 is unprotected.
    rt_register("cos_issue1145_mid_destroy_guard", function()
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
            return string.format("dead-wearer pulse was not dropped (ran=%s executed=%d dropped=%d)",
                tostring(ran), executed, dropped)
        end
        return nil
    end)

    return true
end

return M
