-- Pure policy for issue #385: retain the first close-range no-path unstick,
-- but rate-limit repeated executions while the bot remains below its leash.

local M = {}

M.NO_PATH_RETRY_S = 5.0
M.AID_TRACE_WINDOW_S = 3.0

function M.should_suppress_no_path(distance_m, leash_m, now, last_no_path_t)
    if type(distance_m) ~= "number" or type(leash_m) ~= "number"
            or type(now) ~= "number" or type(last_no_path_t) ~= "number" then
        return false
    end
    if distance_m >= leash_m then return false end
    local age = now - last_no_path_t
    return age >= 0 and age < M.NO_PATH_RETRY_S
end

function M.is_no_path_reason(reason)
    return reason == "vanilla_no_path" or reason == "backward_no_path"
end

-- Issues #139/#384: retain the exact identity present at a veto long enough
-- for the execution-side teleport hook to correlate a later action. This is
-- ordinary Lua data only: engine unit handles are treated as opaque identity
-- tokens and no behavior decision reads this record.
function M.make_aid_veto_trace(now, aid_unit, follow_unit, reason)
    if type(now) ~= "number" or aid_unit == nil then return nil end
    return {
        t = now,
        aid_unit = aid_unit,
        follow_unit = follow_unit,
        reason = reason,
    }
end

function M.correlate_aid_veto(trace, now, current_aid_unit)
    if type(trace) ~= "table" or type(trace.t) ~= "number"
            or type(now) ~= "number" then
        return nil, nil
    end
    local age = now - trace.t
    if age < 0 or age > M.AID_TRACE_WINDOW_S then
        return nil, nil
    end
    return age, trace.aid_unit == current_aid_unit
end

-- ---------------------------------------------------------------------------
-- Issue #384: aid-errand PIN classification (pure, duck-typed status object).
-- ---------------------------------------------------------------------------
-- Vanilla clears blackboard.target_ally_need_type whenever _ally_path_allowed is
-- inside a failed-path cooldown (in_need_type nil'd / candidate skipped at
-- player_bot_base.lua:960-964, then _update_target_ally:721-723 clears the
-- flags), so the errand and every consumer of need_type -- vanilla's own
-- teleport aid exception (bt_bot_conditions.lua:1226-1228) AND gt's tighter
-- leash -- flicker off while the ally is still down. This classifier answers
-- "what need type can the picker legitimately PIN for this ally right now"
-- from the ally's LIVE status, independent of path cooldowns.
--
-- Only the interactable errand types the BT can act on are pinnable
-- (can_revive / can_rescue_* key on these: knocked_down / ledge / hook;
-- vanilla priority order player_bot_base.lua:909-917). An awaiting-assisted-
-- respawn ally maps to the FIX 3 relabel ("knocked_down") ONLY when the caller
-- says the rescue-awaiting feature is on -- the contextual interaction resolves
-- to assisted_respawn (interactions.lua:562). Disabler grabs (pounce /
-- pack-master / tentacle / chaos-spawn / vortex / corruptor) hold the teleport
-- VETO via _gt_status_needs_aid_or_rescue but have NO interactable errand, so
-- they are NOT pinnable. `st` is any object with the status-extension methods
-- (production passes the live extension; tests pass stubs).
function M.pin_need_type(st, allow_awaiting_relabel)
    if not st then
        return nil
    end
    if st:is_knocked_down() then
        return "knocked_down"
    end
    if st:get_is_ledge_hanging() and not st:is_pulled_up() then
        return "ledge"
    end
    if st:is_hanging_from_hook() then
        return "hook"
    end
    if allow_awaiting_relabel and st:is_ready_for_assisted_respawn() then
        return "knocked_down"
    end
    return nil
end

-- Pure release matrix for the pin. Returns (release, reason) -- release is true
-- when the pin must let go:
--   * pin_need nil        -> the ally genuinely no longer classifies (revived /
--                            rescued / dead with no awaiting relabel): release.
--   * #492 no-path bail   -> the engine's own aid pathing has confirmed the
--                            route is gone (sustained cb_ally_path_result
--                            failure); this is the authoritative give-up, so
--                            the pin steps aside and the bot may regroup.
--   * #492 no-progress bail -> HOLD. Log evidence (gt 0.2.248 session, 410x
--                            "[gt_bot:139] TELEPORT executed"; "[gt:139:chain]
--                            VETO ... reason=tighter_leash" followed 0.02 s
--                            later by "TELEPORT ... veto_age=0.02s
--                            same_aid=false"; "BAILED aid pursuit
--                            (reason=no-progress)" in the same chain) showed
--                            the straight-line no-progress signal firing while
--                            the ally was still down and releasing the veto
--                            into a teleport loop. A no-progress stall with an
--                            errand pinned is usually combat holding the bot,
--                            not unreachability; genuine unreachability keeps
--                            failing paths and surfaces as the no-path bail.
function M.pin_should_release(pin_need, bail_active, bail_reason, bail_is_pin_unit)
    if pin_need == nil then
        return true, "ally_recovered_or_gone"
    end
    if bail_active and bail_is_pin_unit and bail_reason == "no-path" then
        return true, "no_path_bail"
    end
    return false, nil
end

-- ---------------------------------------------------------------------------
-- Issue #385: below-leash teleport branch instrument (log-only, capped).
-- ---------------------------------------------------------------------------
-- The #385 log gap: 9 of 40 executed teleports fired with measured follow
-- distance BELOW the leash slider (down to 2.8 m) and no branch attribution
-- ("trigger=unknown"). A teleport below BOTH the configured leash and
-- vanilla's 40 m floor cannot have come from a distance trigger, so it is the
-- exact event to tag with its should_teleport / cant_reach_ally branch.
-- Pure decision: log while the pre-teleport follow distance is under
-- min(leash, 40) and the session cap is not exhausted. Instrument only --
-- suppression stays with should_suppress_no_path above.
M.BELOW_LEASH_LOG_CAP = 24

function M.should_log_below_leash(distance_m, leash_m, logged_count, cap)
    if type(distance_m) ~= "number" or type(leash_m) ~= "number" then
        return false
    end
    local limit = (type(cap) == "number") and cap or M.BELOW_LEASH_LOG_CAP
    if (tonumber(logged_count) or 0) >= limit then
        return false
    end
    local floor = leash_m < 40.0 and leash_m or 40.0
    return distance_m < floor
end

return M
