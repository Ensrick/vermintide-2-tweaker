-- Issue #440: automatic, observation-only disabler/dodge probe.
--
-- The decompiled Lua contains no Bardin-specific dodge branch. The remaining
-- uncertainty lives in compiled player-unit geometry, live dodge timing, and
-- the three disablers' distinct target-resolution paths. This module records
-- those boundaries without changing a return value, target, status, or setting.
local mod = get_mod("crt")
local M = {}

local MAX_ROWS_PER_KIND = 16
local rows = { profile = 0, dodge = 0, packmaster = 0, corruptor = 0, gutter = 0 }
local seen_profiles = {}
local dodge_state = setmetatable({}, { __mode = "k" })
local summary_accum = 0

M.source_contract = {
    shared_movement_table = true,
    first_person_height_is_presentation = true,
    packmaster_reads_dodge_status = true,
    corruptor_reads_dodge_status = true,
    gutter_target_height_offset = 0.2,
    gutter_overlap_radius = 1,
}

local function _game_time()
    local time = Managers and Managers.time
    if not time then return nil end
    local ok, value = pcall(time.time, time, "game")
    return ok and value or nil
end

local function _position(unit)
    if not unit then return nil end
    local cached = rawget(_G, "POSITION_LOOKUP")
    if cached and cached[unit] then return cached[unit] end
    if Unit and Unit.world_position then
        local ok, value = pcall(Unit.world_position, unit, 0)
        if ok then return value end
    end
    return nil
end

local function _flat_distance(a, b)
    if not a or not b or not Vector3 then return nil end
    local ok, value = pcall(function()
        return Vector3.length(Vector3.flat(a - b))
    end)
    return ok and value or nil
end

local function _profile(unit)
    local pm = Managers and Managers.player
    local owner
    if pm and pm.owner then
        local ok, value = pcall(pm.owner, pm, unit)
        if ok then owner = value end
    end
    local index
    if owner and type(owner.profile_index) == "function" then
        local ok, value = pcall(owner.profile_index, owner)
        if ok then index = value end
    end
    local profile = index and rawget(_G, "SPProfiles") and SPProfiles[index]
    return profile and profile.display_name or nil, profile, owner
end

local function _neck_height(unit, root)
    if not (unit and root and Unit and Unit.node and Unit.world_position and Vector3) then return nil end
    local ok, value = pcall(function()
        local node = Unit.node(unit, "j_neck")
        return Vector3.z(Unit.world_position(unit, node)) - Vector3.z(root)
    end)
    return ok and value or nil
end

local function _actor_count(unit)
    if not (unit and Unit and Unit.num_actors) then return nil end
    local ok, value = pcall(Unit.num_actors, unit)
    return ok and value or nil
end

local function _has_mover(unit)
    if not (unit and Unit and Unit.mover) then return false end
    local ok, mover = pcall(Unit.mover, unit)
    return ok and mover ~= nil
end

local DISABLER_BREEDS = {
    skaven_pack_master = true,
    skaven_gutter_runner = true,
    chaos_corruptor_sorcerer = true,
}

local function _nearest_disabler(unit)
    local side_manager = Managers and Managers.state and Managers.state.side
    local side = side_manager and side_manager.side_by_unit and side_manager.side_by_unit[unit]
    local enemies = side and side.ENEMY_UNITS
    local origin = _position(unit)
    if type(enemies) ~= "table" or not origin then return nil end

    local nearest, nearest_name, nearest_distance
    for i = 1, #enemies do
        local enemy = enemies[i]
        local breed
        if Unit and Unit.get_data then
            local ok, value = pcall(Unit.get_data, enemy, "breed")
            if ok then breed = value end
        end
        if breed and DISABLER_BREEDS[breed.name] then
            local distance = _flat_distance(origin, _position(enemy))
            if distance and distance <= 25
                and (not nearest_distance or distance < nearest_distance) then
                nearest, nearest_name, nearest_distance = enemy, breed.name, distance
            end
        end
    end
    return nearest, nearest_name, nearest_distance
end

local function _dodge_detail(unit, t)
    local record = dodge_state[unit]
    local status = ScriptUnit and ScriptUnit.has_extension
        and ScriptUnit.has_extension(unit, "status_system")
    local active = false
    if status and status.get_is_dodging then
        local ok, value = pcall(status.get_is_dodging, status)
        active = ok and value and true or false
    end
    local root = _position(unit)
    local moved = record and _flat_distance(record.start_pos, root) or nil
    local elapsed = record and t and record.start_t and t - record.start_t or nil
    local phase = active and "active" or (record and record.end_t and "ended" or "none")
    local state = record and record.state
    return phase, elapsed, moved, state and state.distance_left or nil, root
end

local function _emit(kind, target_unit, attacker_unit, outcome, extra)
    if not rows[kind] or rows[kind] >= MAX_ROWS_PER_KIND then return end
    local profile = _profile(target_unit)
    if not profile then return end
    rows[kind] = rows[kind] + 1

    local t = _game_time()
    local phase, elapsed, moved, left, target_pos = _dodge_detail(target_unit, t)
    local attacker_pos = _position(attacker_unit)
    local distance = _flat_distance(attacker_pos, target_pos)
    pcall(printf,
        "[crt:440] kind=%s row=%d/%d profile=%s outcome=%s dodge=%s elapsed=%s moved=%s left=%s attacker_dist=%s neck_h=%s actors=%s %s",
        kind, rows[kind], MAX_ROWS_PER_KIND, tostring(profile), tostring(outcome),
        tostring(phase), elapsed and string.format("%.3f", elapsed) or "na",
        moved and string.format("%.3f", moved) or "na",
        left and string.format("%.3f", left) or "na",
        distance and string.format("%.3f", distance) or "na",
        (_neck_height(target_unit, target_pos) and string.format("%.3f", _neck_height(target_unit, target_pos))) or "na",
        tostring(_actor_count(target_unit) or "na"), tostring(extra or ""))
end

-- Track actual dodge onset, duration and displacement; do not spend the bounded
-- log budget on ordinary dodges. Disabler resolution consumes this state.
mod:hook_safe("PlayerCharacterStateDodging", "on_enter", function(self, unit, input, dt, context, t)
    pcall(function()
        local nearby, nearby_name, nearby_distance = _nearest_disabler(unit)
        dodge_state[unit] = {
            start_t = t,
            start_pos = _position(unit),
            state = self,
            nearby = nearby,
            nearby_name = nearby_name,
            nearby_distance = nearby_distance,
        }
    end)
end)

mod:hook_safe("PlayerCharacterStateDodging", "on_exit", function(self, unit, input, dt, context, t)
    pcall(function()
        local record = dodge_state[unit]
        if record then
            record.end_t = t
            record.end_pos = _position(unit)
            if record.nearby then
                _emit("dodge", unit, record.nearby, "completed",
                    string.format("near=%s start_dist=%s", tostring(record.nearby_name),
                        record.nearby_distance and string.format("%.3f", record.nearby_distance)
                            or "na"))
            end
        end
    end)
end)

-- Packmaster success is decided at the animation callback from dodge status,
-- angle, distance and line of sight (bt_pack_master_attack_action.lua:108-139).
mod:hook_safe("BTPackMasterAttackAction", "attack_success", function(self, unit, blackboard)
    pcall(function()
        local action = blackboard and blackboard.action
        _emit("packmaster", blackboard and blackboard.target_unit, unit,
            blackboard and blackboard.attack_success and "grab" or "miss",
            string.format("gate_angle=%s gate_dist=%s", tostring(action and action.dodge_angle),
                tostring(action and action.dodge_distance)))
    end)
end)

-- Capture only the call that transitions to a resolved success/abort. The
-- optional grab delay may invoke this method earlier without resolving it.
mod:hook("BTCorruptorGrabAction", "grab_player", function(func, self, t, unit, blackboard)
    local had_result = blackboard.attack_success ~= nil or blackboard.attack_aborted ~= nil
    local result = func(self, t, unit, blackboard)
    local has_result = blackboard.attack_success ~= nil or blackboard.attack_aborted ~= nil
    if not had_result and has_result then
        pcall(_emit, "corruptor", blackboard.corruptor_target, unit,
            blackboard.attack_success and "grab" or "miss",
            string.format("tracked_dodge=%s projectile_target=%s",
                tostring(blackboard.target_dodged == true),
                tostring(blackboard.projectile_target_position ~= nil)))
    end
    return result
end)

-- Gutter Runner has no status-based dodge gate. It aims at root+0.2, then uses
-- a one-metre trigger overlap and neck-node snapping. Record the terminal state
-- before vanilla clears jump_data in leave().
mod:hook("BTCrazyJumpAction", "leave", function(func, self, unit, blackboard, t, reason, destroy)
    local data = blackboard and blackboard.jump_data
    local target = data and data.target_unit or blackboard and blackboard.target_unit
    pcall(_emit, "gutter", target, unit, reason == "done" and "pounce" or "miss",
        string.format("reason=%s state=%s snap_failed=%s", tostring(reason),
            tostring(data and data.state), tostring(data and data.snap_failed == true)))
    return func(self, unit, blackboard, t, reason, destroy)
end)

-- One automatic geometry/settings summary per profile encountered in a session.
-- This makes Bardin-vs-control comparison possible without a chat command.
function M.tick(dt)
    summary_accum = summary_accum + (dt or 0)
    if summary_accum < 1 then return end
    summary_accum = 0
    if rows.profile >= MAX_ROWS_PER_KIND then return end

    local pm = Managers and Managers.player
    if not pm or type(pm.human_players) ~= "function" then return end
    local ok, humans = pcall(pm.human_players, pm)
    if not ok or type(humans) ~= "table" then return end
    for _, player in pairs(humans) do
        local unit = player and player.player_unit
        local profile, profile_data = _profile(unit)
        if profile and not seen_profiles[profile] then
            seen_profiles[profile] = true
            rows.profile = rows.profile + 1
            local settings = PlayerUnitMovementSettings
                and PlayerUnitMovementSettings.get_movement_settings_table
                and PlayerUnitMovementSettings.get_movement_settings_table(unit)
            local dodge = settings and settings.dodging
            local root = _position(unit)
            pcall(printf,
                "[crt:440] kind=profile row=%d/%d profile=%s dodge_distance=%s distance_mod=%s speed_mod=%s dodge_cd=%s jump_override=%s fp_stand=%s neck_h=%s actors=%s mover=%s",
                rows.profile, MAX_ROWS_PER_KIND, tostring(profile),
                tostring(dodge and dodge.distance), tostring(dodge and dodge.distance_modifier),
                tostring(dodge and dodge.speed_modifier), tostring(dodge and dodge.dodge_cd),
                tostring(dodge and dodge.dodge_jump_override_timer),
                tostring(profile_data and profile_data.first_person_heights
                    and profile_data.first_person_heights.stand),
                tostring(_neck_height(unit, root) or "na"), tostring(_actor_count(unit) or "na"),
                tostring(_has_mover(unit)))
        end
    end
end

function M.regression_check()
    if M.source_contract.shared_movement_table ~= true
        or M.source_contract.gutter_overlap_radius ~= 1
        or M.source_contract.gutter_target_height_offset ~= 0.2 then
        return "source contract drifted"
    end
    if MAX_ROWS_PER_KIND ~= 16 then return "diagnostic row bound drifted" end
    return nil
end

M.max_rows_per_kind = MAX_ROWS_PER_KIND
M.hook_count = 5
mod._crt.bardin_disabler_probe = M
mod._crt_bardin_disabler_tick = M.tick

return M
