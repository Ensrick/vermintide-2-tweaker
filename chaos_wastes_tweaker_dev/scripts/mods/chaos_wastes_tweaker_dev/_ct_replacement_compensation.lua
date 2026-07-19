-- Pure state-copy policy for issue #465. Runtime hooks supply the DeusRunState;
-- this module owns bounded cloning, wire-safe filtering, and the exact fields
-- transferred between a departing human, their replacement bot, and a joiner.
local M = {}

local MAX_DEPTH = 6
local MAX_ENTRIES = 256

local function clone(value, depth, budget)
    if type(value) ~= "table" then return value end
    depth = depth or 0
    if depth >= MAX_DEPTH or budget.left <= 0 then
        budget.overflow = true
        return nil
    end

    local out = {}
    for key, child in pairs(value) do
        if budget.left <= 0 then
            budget.overflow = true
            break
        end
        budget.left = budget.left - 1
        local copied_key = clone(key, depth + 1, budget)
        if copied_key ~= nil then
            out[copied_key] = clone(child, depth + 1, budget)
        end
    end
    return out
end

local function equal(a, b, depth, budget)
    if a == b then return true end
    if type(a) ~= type(b) or type(a) ~= "table" then return false end
    depth = depth or 0
    if depth >= MAX_DEPTH or budget.left <= 0 then return false end

    for key, value in pairs(a) do
        if budget.left <= 0 then return false end
        budget.left = budget.left - 1
        if not equal(value, b[key], depth + 1, budget) then return false end
    end
    for key, _ in pairs(b) do
        if budget.left <= 0 then return false end
        budget.left = budget.left - 1
        if a[key] == nil then return false end
    end
    return true
end

function M.profile_key(profile_index, career_index)
    if type(profile_index) ~= "number" or profile_index <= 0 then return nil end
    if type(career_index) ~= "number" or career_index <= 0 then return nil end
    return tostring(profile_index) .. ":" .. tostring(career_index)
end

function M.same_identity(a_profile, a_career, b_profile, b_career)
    return M.profile_key(a_profile, a_career) ~= nil
        and a_profile == b_profile and a_career == b_career
end

function M.capture(run_state, peer_id, local_player_id, profile_index, career_index)
    if not run_state or not peer_id or not local_player_id or not M.profile_key(profile_index, career_index) then
        return nil, "missing identity or run state"
    end

    local budget = { left = MAX_ENTRIES }
    local snapshot = {
        profile_index = profile_index,
        career_index = career_index,
        power_ups = clone(run_state:get_player_power_ups(peer_id, local_player_id, profile_index, career_index) or {}, 0, budget) or {},
        persistent_buffs = clone(run_state:get_player_persistent_buffs(peer_id, local_player_id, profile_index, career_index) or {}, 0, budget) or {},
        coins = run_state:get_player_soft_currency(peer_id, local_player_id) or 0,
        slot_melee = run_state:get_player_loadout(peer_id, local_player_id, profile_index, career_index, "slot_melee"),
        slot_ranged = run_state:get_player_loadout(peer_id, local_player_id, profile_index, career_index, "slot_ranged"),
    }
    if budget.overflow then return nil, "progression exceeds bounded snapshot" end
    return snapshot
end

-- A replacement is selected by profile first, but its career can differ from the
-- departing/joining human's career. Boons are generic Deus instances and may be
-- copied directly; serialized weapons are career-specific. The runtime supplies a
-- projector that reapplies only the source weapon tier to the target career's
-- already-initialized weapon. If projection fails, keep the target weapon rather
-- than placing an incompatible source item in its row.
function M.prepare_for_target(snapshot, target_snapshot, profile_index, career_index, project_weapon)
    if not snapshot or not target_snapshot or not M.profile_key(profile_index, career_index) then
        return nil, { "missing source or initialized target" }
    end

    local budget = { left = MAX_ENTRIES }
    local prepared = clone(snapshot, 0, budget) or {}
    if budget.overflow then return nil, { "source progression exceeds bounded snapshot" } end
    prepared.profile_index = profile_index
    prepared.career_index = career_index

    if M.same_identity(snapshot.profile_index, snapshot.career_index, profile_index, career_index) then
        return prepared, {}
    end

    local failures = {}
    for _, slot in ipairs({ "slot_melee", "slot_ranged" }) do
        local source_weapon = snapshot[slot]
        local target_weapon = target_snapshot[slot]
        local projected, reason
        if project_weapon then
            projected, reason = project_weapon(source_weapon, target_weapon, slot)
        end
        if projected then
            prepared[slot] = projected
        else
            prepared[slot] = target_weapon
            failures[#failures + 1] = slot .. ":" .. tostring(reason or "projection unavailable")
        end
    end
    return prepared, failures
end

function M.progression_equal(a, b)
    if not a or not b then return false end
    if a.coins ~= b.coins or a.slot_melee ~= b.slot_melee or a.slot_ranged ~= b.slot_ranged then
        return false
    end
    local budget = { left = MAX_ENTRIES }
    return equal(a.power_ups or {}, b.power_ups or {}, 0, budget)
        and equal(a.persistent_buffs or {}, b.persistent_buffs or {}, 0, budget)
end

function M.wire_safe_copy(snapshot, wire_safe, is_modded_power_up, is_ct_buff)
    if not snapshot then return nil, 0, 0 end
    local budget = { left = MAX_ENTRIES }
    local out = clone(snapshot, 0, budget) or {}
    if budget.overflow then return nil, 0, 0, "progression exceeds bounded wire copy" end
    if wire_safe then return out, 0, 0 end

    local power_ups, removed_power_ups = {}, 0
    for i = 1, #(out.power_ups or {}) do
        local power_up = out.power_ups[i]
        if power_up and is_modded_power_up and is_modded_power_up(power_up.name) then
            removed_power_ups = removed_power_ups + 1
        else
            power_ups[#power_ups + 1] = power_up
        end
    end
    out.power_ups = power_ups

    local persistent, removed_buffs = {}, 0
    for i = 1, #(out.persistent_buffs or {}) do
        local buff_name = out.persistent_buffs[i]
        if is_ct_buff and is_ct_buff(buff_name) then
            removed_buffs = removed_buffs + 1
        else
            persistent[#persistent + 1] = buff_name
        end
    end
    out.persistent_buffs = persistent
    return out, removed_power_ups, removed_buffs
end

function M.apply(run_state, peer_id, local_player_id, profile_index, career_index, snapshot, coin_override)
    if not run_state or not snapshot or not M.profile_key(profile_index, career_index) then
        return false, "missing target identity, snapshot, or run state"
    end

    local previous, capture_reason = M.capture(run_state, peer_id, local_player_id, profile_index, career_index)
    if not previous then return false, capture_reason end
    local previous_profile_initialized = run_state.get_profile_initialized
        and run_state:get_profile_initialized(peer_id, local_player_id, profile_index, career_index)
    local previous_peer_initialized = run_state.get_peer_initialized
        and run_state:get_peer_initialized(peer_id)
    local clone_budget = { left = MAX_ENTRIES }
    local expected = clone(snapshot, 0, clone_budget) or {}
    if clone_budget.overflow then return false, "progression exceeds bounded apply" end
    expected.coins = coin_override == nil and snapshot.coins or coin_override

    local function write(value, profile_initialized, peer_initialized)
        run_state:set_player_power_ups(peer_id, local_player_id, profile_index, career_index, value.power_ups or {})
        run_state:set_player_persistent_buffs(peer_id, local_player_id, profile_index, career_index, value.persistent_buffs or {})
        run_state:set_player_loadout(peer_id, local_player_id, profile_index, career_index, "slot_melee", value.slot_melee)
        run_state:set_player_loadout(peer_id, local_player_id, profile_index, career_index, "slot_ranged", value.slot_ranged)
        run_state:set_player_soft_currency(peer_id, local_player_id, value.coins or 0)
        run_state:set_profile_initialized(peer_id, local_player_id, profile_index, career_index, profile_initialized)
        run_state:set_peer_initialized(peer_id, peer_initialized)
    end

    local ok, err = pcall(write, expected, true, true)
    local actual = ok and M.capture(run_state, peer_id, local_player_id, profile_index, career_index) or nil
    if ok and M.progression_equal(actual, expected) then return true end

    -- SharedState writes are individually replicated, so a failed multi-field copy
    -- must restore the complete prior row. The rollback itself is best-effort and
    -- reported to the runtime wrapper; it is never retried as a second grant.
    local rollback_ok, rollback_err = pcall(write, previous,
        previous_profile_initialized == true, previous_peer_initialized == true)
    return false, string.format("apply/readback failed: %s; rollback=%s%s",
        tostring(err or "mismatch"), tostring(rollback_ok),
        rollback_ok and "" or (":" .. tostring(rollback_err)))
end

return M
