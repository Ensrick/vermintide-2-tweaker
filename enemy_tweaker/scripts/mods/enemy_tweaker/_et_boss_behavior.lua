local mod = get_mod("enemy_tweaker")

-- Issue #450: Halescourge's Cataclysm+ half-health monster add.
--
-- Ownership is deliberately split across existing singleton seams:
--   * `_et_boss_grudge.lua` already owns ConflictDirector._post_spawn_unit and
--     calls ET.observe_boss_behavior_spawn after vanilla has fully initialized
--     the boss.
--   * `_et_lifecycle.lua` already owns mod.update and calls
--     ET.boss_behavior_update.
-- This module adds no engine hook. It tracks only live Halescourge units in a
-- weak-key table, evaluates a pure one-shot policy, finds an arena-contained
-- navmesh point with the same ConflictUtils helper Halescourge's teleport uses,
-- and queues one vanilla Bile Troll or Chaos Spawn through ConflictDirector's
-- package-aware spawn queue.

local ET = mod._et
local Core = ET.BossBehaviorCore
local _et_probe = ET.et_probe
local rt_register = ET.rt_register

local _tracked = setmetatable({}, { __mode = "k" })
ET.boss_behavior_tracked = _tracked

-- Skarrik's 30% ranged reduction shares the already-owned
-- DamageUtils.apply_buffs_to_damage hook in _et_personal_handicap.lua. The
-- server applies it before vanilla victim buffs, and this exact-breed branch is
-- inert for melee, environmental damage, and every other unit.
ET.boss_behavior_scale_incoming_damage = function(damage, attacked_unit, buff_attack_type)
    local enabled = mod:get("boss_behavior_skarrik_ranged_dr") and true or false
    if not enabled or not Unit.alive(attacked_unit) then return damage end
    local breed = Unit.get_data(attacked_unit, "breed")
    local is_skarrik = type(breed) == "table" and breed.name == Core.SKARRIK_BREED
    local ranged_types = rawget(_G, "RangedAttackTypes")
    local is_ranged = type(ranged_types) == "table" and ranged_types[buff_attack_type] == true
    return Core.skarrik_ranged_damage(damage, enabled, is_skarrik, is_ranged)
end

-- Deathrattler's ordinary ratling action hardcodes a `dt * 6` aim lerp in
-- vanilla. Feeding half dt halves that tracking gain without copying the engine
-- method, and only for the exact boss breed while its ratling setup is active.
mod:hook("BTStormfiendShootAction", "_fire_from_position_direction",
    function(func, self, unit, blackboard, data, dt)
        local enabled = mod:get("boss_behavior_deathrattler_tracking") and true or false
        local breed = blackboard and blackboard.breed
        local is_deathrattler = type(breed) == "table"
            and breed.name == Core.DEATHRATTLER_BREED
        local is_ratling = blackboard and blackboard.weapon_setup == "ratling_gun"
        dt = Core.deathrattler_tracking_dt(dt, enabled, is_deathrattler, is_ratling)
        return func(self, unit, blackboard, data, dt)
    end)

local function _runtime_context(unit, state)
    if not state.blackboard then
        local blackboards = rawget(_G, "BLACKBOARDS")
        state.blackboard = blackboards and blackboards[unit]
    end
    local game_mode = Managers.state and Managers.state.game_mode
    local difficulty = Managers.state and Managers.state.difficulty
    local network = Managers.state and Managers.state.network
    local health = state.blackboard and state.blackboard.health_extension
    return {
        triggered = state.triggered,
        enabled = mod:get("boss_behavior_halescourge_monster") and true or false,
        is_server = network and network.is_server and true or false,
        game_mode = game_mode and game_mode:game_mode_key() or nil,
        level_key = game_mode and game_mode:level_key() or nil,
        difficulty_rank = difficulty and difficulty:get_difficulty_rank() or nil,
        in_boss_arena = state.blackboard and state.blackboard.in_boss_arena == true,
        health_percent = health and health:current_health_percent() or nil,
    }
end

local function _spawn_position(unit, blackboard)
    local lookup = rawget(_G, "POSITION_LOOKUP")
    local unit_pos = lookup and lookup[unit]
    local nav_world = blackboard and blackboard.nav_world
    local valid = blackboard and blackboard.valid_teleport_pos_func
    if not unit_pos or not nav_world or type(valid) ~= "function" then return nil end
    local utils = rawget(_G, "ConflictUtils")
    if not utils or type(utils.get_spawn_pos_on_circle_with_func) ~= "function" then
        return nil
    end
    -- Vanilla Halescourge teleports through this helper and the same
    -- valid_teleport_pos_func (bt_chaos_exalted_sorcerer_skulk_action.lua:
    -- 99-116). Reusing it keeps the add inside the arena OOB and on navmesh.
    return utils.get_spawn_pos_on_circle_with_func(
        nav_world, unit_pos, 6, 6, 12, valid, blackboard, 4, 4)
end

local function _queue_monster(unit, state, context)
    local blackboard = state.blackboard
    local spawn_pos = _spawn_position(unit, blackboard)
    if not spawn_pos then return false, "spawn_position_missing" end

    local roll = math.random(1, #Core.HALESCOURGE_MONSTERS)
    local breed_name = Core.monster_for_roll(roll)
    local breeds = rawget(_G, "Breeds")
    local breed = breeds and breeds[breed_name]
    if not breed then return false, "breed_missing:" .. tostring(breed_name) end

    local conflict = Managers.state and Managers.state.conflict
    if not conflict or type(conflict.spawn_queued_unit) ~= "function" then
        return false, "conflict_missing"
    end

    local rotation = Quaternion(Vector3.up(), math.degrees_to_radians(math.random(1, 360)))
    local optional_data = {
        ignore_breed_limits = true,
        far_off_despawn_immunity = true,
        -- The separate Warlord monster-pool toggle must not replace this
        -- explicitly curated Bile Troll / Chaos Spawn add.
        et_boss_balance_no_pool_swap = true,
    }
    local queue_id = conflict:spawn_queued_unit(
        breed, Vector3Box(spawn_pos), QuaternionBox(rotation),
        "boss_balance_halescourge", nil, "boss_balance", optional_data)
    if type(queue_id) ~= "number" then return false, "queue_id_missing" end

    state.triggered = true
    state.queued_breed = breed_name
    state.queue_id = queue_id
    state.last_reason = "queued"
    _et_probe("boss450_halescourge_queued",
        "[et:450] Halescourge threshold=%.2f current=%.3f queued=%s queue_id=%d rank=%d",
        Core.HALESCOURGE_THRESHOLD, context.health_percent, breed_name, queue_id,
        context.difficulty_rank)
    return true, "queued"
end

local function _tick_one(unit, state, t)
    if not Unit.alive(unit) then
        _tracked[unit] = nil
        return
    end
    if state.next_attempt_at and t < state.next_attempt_at then return end

    local context = _runtime_context(unit, state)
    state.last_health_percent = context.health_percent
    state.last_rank = context.difficulty_rank
    local ready, reason = Core.halescourge_gate(context)
    state.last_reason = reason
    if not ready then return end

    state.attempts = state.attempts + 1
    local ok, queued, queue_reason = pcall(_queue_monster, unit, state, context)
    if ok and queued then return end
    reason = ok and queue_reason or ("queue_error:" .. tostring(queued))
    state.last_reason = reason
    if state.last_logged_failure ~= reason then
        state.last_logged_failure = reason
        _et_probe("boss450_halescourge_failure_" .. tostring(reason),
            "[et:450] Halescourge threshold reached but add not queued reason=%s attempts=%d health=%.3f",
            tostring(reason), state.attempts, context.health_percent)
    end
    -- A transient navmesh/package/director boundary is retried, but never in a
    -- hot loop. The one-shot closes only after vanilla returns a queue id.
    state.next_attempt_at = t + 0.5
end

ET.observe_boss_behavior_spawn = function(ai_unit, breed)
    if type(breed) ~= "table" or breed.name ~= Core.HALESCOURGE_BREED then return end
    local blackboards = rawget(_G, "BLACKBOARDS")
    local blackboard = blackboards and blackboards[ai_unit]
    _tracked[ai_unit] = {
        blackboard = blackboard,
        triggered = false,
        attempts = 0,
        last_reason = "observed",
    }
    _et_probe("boss450_halescourge_observed",
        "[et:450] Halescourge observer armed level=%s arena=%s toggle=%s",
        tostring(Managers.state and Managers.state.game_mode
            and Managers.state.game_mode:level_key()),
        tostring(blackboard and blackboard.in_boss_arena == true),
        tostring(mod:get("boss_behavior_halescourge_monster") and true or false))
end

ET.boss_behavior_update = function()
    -- mod.update runs in every application state, while the "game" timer only
    -- exists in StateIngame. Use the always-resident main timer so title/loading
    -- transitions cannot turn this optional monitor into a startup error.
    local time_manager = Managers and Managers.time
    local ok, time = false, nil
    if time_manager and type(time_manager.time) == "function" then
        ok, time = pcall(time_manager.time, time_manager, "main")
    end
    if type(time) ~= "number" then return end
    for unit, state in pairs(_tracked) do
        local ok, err = pcall(_tick_one, unit, state, time)
        if not ok and state.last_tick_error ~= tostring(err) then
            state.last_tick_error = tostring(err)
            _et_probe("boss450_halescourge_tick_error",
                "[et:450] Halescourge monitor error=%s", tostring(err))
        end
    end
end

ET.boss_behavior_live_state = function()
    for unit, state in pairs(_tracked) do
        if Unit.alive(unit) then return state end
    end
    return nil
end

rt_register("boss450_halescourge_behavior_wired", function()
    if type(ET.observe_boss_behavior_spawn) ~= "function" then
        return "Halescourge post-spawn observer missing"
    end
    if type(ET.boss_behavior_update) ~= "function" then
        return "Halescourge lifecycle update missing"
    end
    local breeds = rawget(_G, "Breeds")
    for i = 1, #Core.HALESCOURGE_MONSTERS do
        local name = Core.HALESCOURGE_MONSTERS[i]
        if not (breeds and breeds[name]) then return "missing add breed: " .. name end
    end
end)

rt_register("boss450_halescourge_difficulty_rank_sane", function()
    local settings = rawget(_G, "DifficultySettings")
    local cata = settings and settings.cataclysm
    if not cata or cata.rank ~= Core.CATACLYSM_RANK then
        return "Cataclysm rank drifted from boss behavior policy"
    end
end)

rt_register("boss450_remaining_behavior_targets", function()
    local breeds = rawget(_G, "Breeds")
    local actions = rawget(_G, "BreedActions")
    local deathrattler = actions and actions[Core.DEATHRATTLER_BREED]
    if not (breeds and breeds[Core.SKARRIK_BREED]) then
        return "Skarrik ranged-resistance breed missing"
    end
    if not (breeds and breeds[Core.DEATHRATTLER_BREED]) then
        return "Deathrattler tracking breed missing"
    end
    if not (deathrattler and deathrattler.dual_shoot_intro
            and type(deathrattler.dual_shoot_intro.rotation_time) == "number") then
        return "Deathrattler dual-shoot rotation target missing"
    end
end)
