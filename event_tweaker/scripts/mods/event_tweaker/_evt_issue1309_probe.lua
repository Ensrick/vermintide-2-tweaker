-- _evt_issue1309_probe.lua — pure session state for the Tzeentch Twins co-op diagnostic
--
-- Issue 1309 (owner report #1149): the Chaos Wastes curse curse_change_of_tzeentch
-- reportedly does nothing for client peers while the weekly-modifier version of the
-- same template works. The template is a table.clone of mutator_splitting_enemies
-- (mutator_curse_change_of_tzeentch.lua:3-4) whose entire split path is host-side
-- server_ai_killed_function, and it ships NO client functions, so what a client
-- observes failing cannot be known without instrumentation. This module owns the
-- bounded receipt vocabulary and the per-peer counters; the engine-facing hooks
-- live in _evt_diagnostics.lua. Kept engine-free so the offline Lua suite can
-- exercise the cap, the roll classifier, and the split-observation window without
-- loading a mission.
--
-- Two invariants the receipts must not break. The emit budget is hard-capped at
-- RECEIPT_CAP per-kill lines plus exactly one end-of-mission summary per peer, so
-- a 25%-roll-per-AI-death diagnostic cannot flood a Cataclysm log. And the host
-- receipt reproduces the roll from the PRE-call seed rather than rolling its own:
-- Math.next_random is a pure seeded step, so replaying seed_before yields the exact
-- value the curse compared against SPLIT_CHANCE without consuming the stream.
--
-- Owned by: event_tweaker.lua entry point. Consumed via:
-- require("scripts/mods/event_tweaker/_evt_issue1309_probe") from _evt_diagnostics.lua

local M = {}

-- Historical prefix from #1149 / #1309. Do NOT renumber it to 1309: the issue
-- names this string and the owner greps logs for it.
M.PREFIX = "[et:1149t]"
M.CURSE = "curse_change_of_tzeentch"

-- mutator_curse_change_of_tzeentch.lua:10 — the roll passes at `random <= 0.25`
-- because the template returns early on `random > SPLIT_CHANCE` (:23-25).
M.SPLIT_CHANCE = 0.25

M.RECEIPT_CAP = 10

-- Seconds a client will attribute a replicated husk spawn to a death it just
-- observed. The host queues splits at death time + data.spawn_delay = 0.25
-- (mutator_splitting_enemies.lua:85,175) and the conflict director drains one
-- queued unit per update once the breed package is loaded on all peers
-- (conflict_director.lua:1835-1891), so the arrival is late and variable.
M.OBSERVE_WINDOW = 3

function M.new_session()
    return {
        armed = false,
        role = nil,
        seed = nil,
        seed_reported = false,
        template_active = nil,
        kills_rolled = 0,
        splits_spawned = 0,
        deaths_seen = 0,
        spawns_in_window = 0,
        splits_matched = 0,
        receipts = 0,
        summary_emitted = false,
        pending = {},
        tier_map_state = "unread",
    }
end

function M.reset(state)
    if type(state) ~= "table" then return end
    local fresh = M.new_session()
    for key in pairs(state) do state[key] = nil end
    for key, value in pairs(fresh) do state[key] = value end
end

-- "host" and "client" are the two receipt roles. A listen host runs both the
-- server and the local-client halves of MutatorHandler (game_mode_manager.lua:97
-- sets has_local_client = not DEDICATED_SERVER), so role is decided by
-- self._is_server and a listen host reports as the host.
function M.role_name(is_server)
    return is_server and "host" or "client"
end

-- Arm the session on curse activation. Returns the activation receipt exactly
-- once per mission so a re-activation or a hot-join resync cannot double-log.
function M.arm(state, role, seed, template_active)
    if type(state) ~= "table" then return nil end
    state.armed = true
    state.role = role
    state.seed = seed
    state.template_active = template_active
    if state.seed_reported then return nil end
    state.seed_reported = true
    return string.format(
        "%s activated role=%s seed=%s template_active=%s cap=%d",
        M.PREFIX, tostring(role), tostring(seed), tostring(template_active), M.RECEIPT_CAP)
end

-- The template compares `random > SPLIT_CHANCE` and returns, so a roll at or
-- below the chance is the one that reaches the split path.
function M.classify_roll(roll)
    if type(roll) ~= "number" then return "unknown" end
    if roll <= M.SPLIT_CHANCE then return "pass" end
    return "fail"
end

-- Bounded emit budget shared by every per-kill receipt on this peer.
function M.take_receipt(state)
    if type(state) ~= "table" then return false end
    if (state.receipts or 0) >= M.RECEIPT_CAP then return false end
    state.receipts = (state.receipts or 0) + 1
    return true
end

-- Record a host kill and return its receipt line when the budget allows one.
-- `enqueued` is the growth of the curse's own spawn_queue across the vanilla
-- call: that is the split path's only observable output at kill time, because
-- the units themselves are spawned later by server_update_function
-- (mutator_splitting_enemies.lua:87-114).
function M.host_kill(state, peer_id, breed, roll, enqueued, seed_before, seed_after)
    if type(state) ~= "table" then return nil end
    state.kills_rolled = (state.kills_rolled or 0) + 1
    state.splits_spawned = (state.splits_spawned or 0) + (type(enqueued) == "number" and enqueued or 0)
    if not M.take_receipt(state) then return nil end
    return string.format(
        "%s kill role=host killer_peer=%s breed=%s roll=%s verdict=%s enqueued=%s seed_advanced=%s",
        M.PREFIX, tostring(peer_id), tostring(breed), tostring(roll),
        M.classify_roll(roll), tostring(enqueued),
        tostring(seed_before ~= nil and seed_after ~= nil and seed_before ~= seed_after))
end

-- Client side. A client never runs the split logic, so all it can prove is that
-- it saw the death and whether a replicated husk of the expected lower-tier
-- breed showed up afterwards.
function M.client_death(state, breed, expected_breed, t)
    if type(state) ~= "table" then return nil end
    state.deaths_seen = (state.deaths_seen or 0) + 1
    if expected_breed and type(t) == "number" then
        local pending = state.pending
        pending[#pending + 1] = { breed = expected_breed, expires_at = t + M.OBSERVE_WINDOW }
    end
    if not M.take_receipt(state) then return nil end
    return string.format(
        "%s kill role=client breed=%s expected_split=%s pending=%d",
        M.PREFIX, tostring(breed), tostring(expected_breed), #state.pending)
end

-- Drop expired expectations so a long mission cannot grow the pending list
-- without bound, then try to consume one matching entry.
function M.observe_spawn(state, breed, t)
    if type(state) ~= "table" or type(t) ~= "number" then return false end
    local pending = state.pending
    if type(pending) ~= "table" then return false end

    local kept, matched, live = {}, false, 0
    for i = 1, #pending do
        local entry = pending[i]
        if entry.expires_at >= t then
            live = live + 1
            if not matched and entry.breed == breed then
                matched = true
            else
                kept[#kept + 1] = entry
            end
        end
    end
    state.pending = kept

    -- Only a spawn that lands while a real expectation is open counts toward the
    -- superset. An expired backlog must not inflate it.
    if live > 0 then
        state.spawns_in_window = (state.spawns_in_window or 0) + 1
    end
    if matched then
        state.splits_matched = (state.splits_matched or 0) + 1
    end
    return matched
end

-- One summary per peer per mission. Host and client report the counters their
-- role can actually observe; naming the unobservable ones keeps a reader from
-- reading a structural zero as evidence of failure.
function M.summary(state)
    if type(state) ~= "table" or not state.armed then return nil end
    if state.summary_emitted then return nil end
    state.summary_emitted = true

    if state.role == "host" then
        return string.format(
            "%s summary role=host seed=%s kills_rolled=%d splits_spawned=%d receipts=%d",
            M.PREFIX, tostring(state.seed), state.kills_rolled or 0,
            state.splits_spawned or 0, state.receipts or 0)
    end
    return string.format(
        "%s summary role=client template_active=%s deaths_seen=%d spawns_in_window=%d splits_matched=%d tier_map=%s receipts=%d",
        M.PREFIX, tostring(state.template_active), state.deaths_seen or 0,
        state.spawns_in_window or 0, state.splits_matched or 0,
        tostring(state.tier_map_state), state.receipts or 0)
end

return M
