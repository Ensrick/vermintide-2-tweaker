local mod = get_mod("gt_dev")
local Policy = mod:dofile("scripts/mods/general_tweaker_dev/_gt_host_lag_comp_policy")

-- Issue #1034: host-authoritative melee latency compensation.
--
-- Vanilla resolves ordinary AI melee block state immediately before calling
-- AiUtils.damage_target (for example bt_melee_overlap_attack_action.lua:
-- 635-666). Remote dodge/block state reaches the host through StatusSystem RPCs
-- (status_system.lua:278-302,430-445), while the host's own RTT sample is
-- GameNetworkManager:ping_by_peer (game_network_manager.lua:82-85,176-192).
--
-- This module delays only blockable AI melee damage aimed at a REMOTE HUMAN.
-- The grace window is a capped EMA of host-measured RTT. At the deadline the
-- authoritative host re-checks dodge and block, plus any stagger delivered by
-- that same player during the window. Clients send no custom latency or combat
-- RPC. Host/bot/projectile/hazard/grab/unblockable paths remain vanilla.

local Unit = Unit
local ScriptUnit = ScriptUnit
local Network = Network
local DamageUtils = DamageUtils
local AiUtils = AiUtils
local BLACKBOARDS = BLACKBOARDS
local printf = printf

local _pending = {}
local _ping_ema_by_peer = {}
local _stagger_epoch_by_unit_source = setmetatable({}, { __mode = "k" })
local _resolving = false
local _trace_count = 0
local _TRACE_LIMIT = 64

local _metrics = {
    queued = 0,
    applied = 0,
    blocked = 0,
    dodged = 0,
    staggered = 0,
    attacker_dead = 0,
    target_invalid = 0,
    overflow = 0,
    unsafe = 0,
}

local function _trace(fmt, ...)
    if _trace_count >= _TRACE_LIMIT then return end
    _trace_count = _trace_count + 1
    printf("[gt_dev:LC] " .. fmt, ...)
end

local function _unit_alive(unit)
    return unit ~= nil and Unit and Unit.alive and Unit.alive(unit)
end

local function _status(unit)
    return _unit_alive(unit)
        and ScriptUnit.has_extension(unit, "status_system")
        or nil
end

local function _remote_human_owner(unit)
    local player_manager = Managers and Managers.player
    local player = player_manager and player_manager:owner(unit)
    local local_peer = Network and Network.peer_id and Network.peer_id()

    if not player or player.bot_player or not player.peer_id
        or player.peer_id == local_peer or not player.remote then
        return nil
    end

    return player
end

local function _server_network()
    local state = Managers and Managers.state
    local network = state and state.network

    if not network or not network.is_server or not network.ping_by_peer then
        return nil
    end

    return network
end

local function _ping_delay(peer_id)
    local network = _server_network()
    if not network then return nil end

    local ok, sample = pcall(network.ping_by_peer, network, peer_id)
    if not ok then return nil end

    local previous = _ping_ema_by_peer[peer_id]
    local delay, smoothed = Policy.smooth_ping_seconds(
        previous,
        sample,
        mod:get("gt_host_lag_comp_max_ms")
    )

    if delay then
        _ping_ema_by_peer[peer_id] = smoothed
    end

    return delay
end

local function _attack_direction(action, blackboard)
    local directions = action and action.attack_directions
    local attack_anim = blackboard and blackboard.attack_anim
    return directions and attack_anim and directions[attack_anim] or nil
end

local function _stagger_epoch(unit, source)
    local by_source = _stagger_epoch_by_unit_source[unit]
    return by_source and by_source[source] or 0
end

local function _eligible(
    target_unit, attacker_unit, action, damage, before_block_check
)
    local status = _status(target_unit)
    local owner = _remote_human_owner(target_unit)
    local attacker_blackboard = attacker_unit and BLACKBOARDS[attacker_unit]
    local blocked_damage = action and action.blocked_damage

    local context = {
        enabled = mod:get("gt_host_lag_comp") ~= false,
        is_server = _server_network() ~= nil,
        target_is_remote_human = owner ~= nil,
        attacker_is_ai = attacker_blackboard ~= nil
            and attacker_blackboard.breed ~= nil
            and not attacker_blackboard.is_player,
        action_has_fatigue = action ~= nil and action.fatigue_type ~= nil,
        action_unblockable = action ~= nil and action.unblockable == true
            or attacker_blackboard ~= nil
            and attacker_blackboard.hit_through_block == true,
        already_blocked_damage = not before_block_check
            and blocked_damage ~= nil and damage == blocked_damage,
        target_disabled = status ~= nil and status.is_disabled
            and status:is_disabled() or false,
    }

    if not Policy.is_eligible(context) then return nil end
    return owner, status, attacker_blackboard
end

local function _apply_record(record)
    _resolving = true
    local ok, result

    if record.invoke then
        ok, result = pcall(record.invoke)
    else
        ok, result = pcall(
            record.func,
            record.target_unit,
            record.attacker_unit,
            record.action,
            record.damage,
            record.damage_source
        )
    end
    _resolving = false

    if not ok then
        _metrics.unsafe = _metrics.unsafe + 1
        _trace("apply failed peer=%s err=%s", tostring(record.peer_id), tostring(result))
        return
    end

    _metrics.applied = _metrics.applied + 1
end

local function _pass_whole_hit(func, self, unit, blackboard, hit_unit, action, attack)
    -- A whole-hit path that fails open must also bypass the lower
    -- AiUtils.damage_target fallback. Otherwise a second ping sample could
    -- defer only the damage while vanilla applies the push/callback now.
    _resolving = true
    local ok, result = pcall(
        func, self, unit, blackboard, hit_unit, action, attack
    )
    _resolving = false

    if not ok then
        error(result)
    end
    return result
end

local function _resolve(record)
    local target_alive = _unit_alive(record.target_unit)
    local attacker_alive = _unit_alive(record.attacker_unit)
    local status = target_alive and _status(record.target_unit) or nil
    local current_epoch = _stagger_epoch(
        record.attacker_unit, record.target_unit
    )
    local staggered_by_target = current_epoch ~= record.stagger_epoch
    local target_dodging = status and status.get_is_dodging
        and status:get_is_dodging() or false
    local target_blocked = false

    if not record.whole_hit and target_alive and attacker_alive and not staggered_by_target
        and not target_dodging and status then
        target_blocked = DamageUtils.check_block(
            record.attacker_unit,
            record.target_unit,
            record.action.fatigue_type,
            record.attack_direction
        )
    end

    local reason = Policy.cancel_reason({
        target_alive = target_alive,
        attacker_alive = attacker_alive,
        attacker_staggered_by_target = staggered_by_target,
        target_dodging = target_dodging,
        target_blocked = target_blocked,
    })

    if reason then
        if reason == "block" then _metrics.blocked = _metrics.blocked + 1
        elseif reason == "dodge" then _metrics.dodged = _metrics.dodged + 1
        elseif reason == "stagger" then _metrics.staggered = _metrics.staggered + 1
        elseif reason == "attacker_dead" then _metrics.attacker_dead = _metrics.attacker_dead + 1
        else _metrics.target_invalid = _metrics.target_invalid + 1 end

        _trace(
            "cancel reason=%s peer=%s window_ms=%d pending=%d",
            reason,
            tostring(record.peer_id),
            math.floor(record.delay * 1000 + 0.5),
            #_pending
        )
        return
    end

    _apply_record(record)
end

local function _can_currently_block(record)
    local status = _status(record.target_unit)
    if not status or not status.is_blocking or not status:is_blocking()
        or not status.can_block then
        return false
    end

    local target_buff = ScriptUnit.has_extension(
        record.target_unit, "buff_system"
    )
    if target_buff and target_buff.has_buff_perk
        and target_buff:has_buff_perk("invulnerable") then
        return false
    end

    local attacker_buff = ScriptUnit.has_extension(
        record.attacker_unit, "buff_system"
    )
    if attacker_buff and attacker_buff.has_buff_perk
        and attacker_buff:has_buff_perk("ai_unblockable") then
        return false
    end

    local ok, can_block = pcall(
        status.can_block,
        status,
        record.attacker_unit,
        record.attack_direction
    )
    return ok and can_block == true
end

local function _resolve_target_defense(target_unit, defense)
    for i = #_pending, 1, -1 do
        local record = _pending[i]
        local matches = record.target_unit == target_unit

        if matches and (defense ~= "block" or _can_currently_block(record)) then
            table.remove(_pending, i)
            _resolve(record)
        end
    end
end

local function _resolve_stagger(attacker_unit, source_unit)
    for i = #_pending, 1, -1 do
        local record = _pending[i]

        if record.attacker_unit == attacker_unit
            and record.target_unit == source_unit then
            table.remove(_pending, i)
            _resolve(record)
        end
    end
end

local function _flush(apply)
    local records = _pending
    _pending = {}

    if apply then
        for i = 1, #records do
            if _unit_alive(records[i].target_unit)
                and _unit_alive(records[i].attacker_unit) then
                _apply_record(records[i])
            end
        end
    end
end

local function _reset()
    _flush(false)
    _ping_ema_by_peer = {}
    _stagger_epoch_by_unit_source = setmetatable({}, { __mode = "k" })
    _trace_count = 0
    for key in pairs(_metrics) do
        _metrics[key] = 0
    end
end

mod._gt_host_lag_comp_reset = _reset
mod._gt_host_lag_comp_disable = function()
    _flush(true)
end
mod._gt_host_lag_comp_setting_changed = function()
    if mod:get("gt_host_lag_comp") == false then
        _flush(true)
    end
end

-- Pre-flight: no other gt hook owns (AiUtils, damage_target) or
-- (AiUtils, stagger), and no gt hook owns
-- (BTMeleeOverlapAttackAction, hit_player), as of #1034. Different methods
-- elsewhere do not collide under VMF's per-(class,method) singleton rule.
mod:hook("BTMeleeOverlapAttackAction", "hit_player", function(
    func, self, unit, blackboard, hit_unit, action, attack
)
    if _resolving then
        return func(self, unit, blackboard, hit_unit, action, attack)
    end

    local owner = _eligible(
        hit_unit, unit, action, action and action.damage, true
    )
    if not owner then
        return _pass_whole_hit(
            func, self, unit, blackboard, hit_unit, action, attack
        )
    end

    local delay = _ping_delay(owner.peer_id)
    if delay == nil then
        _metrics.unsafe = _metrics.unsafe + 1
        return _pass_whole_hit(
            func, self, unit, blackboard, hit_unit, action, attack
        )
    end
    if delay <= 0 then
        return _pass_whole_hit(
            func, self, unit, blackboard, hit_unit, action, attack
        )
    end
    if #_pending >= Policy.MAX_PENDING then
        _metrics.overflow = _metrics.overflow + 1
        return _pass_whole_hit(
            func, self, unit, blackboard, hit_unit, action, attack
        )
    end

    _pending[#_pending + 1] = {
        invoke = function()
            return func(self, unit, blackboard, hit_unit, action, attack)
        end,
        whole_hit = true,
        target_unit = hit_unit,
        attacker_unit = unit,
        action = action,
        peer_id = owner.peer_id,
        remaining = delay,
        delay = delay,
        attack_direction = _attack_direction(action, blackboard),
        stagger_epoch = _stagger_epoch(unit, hit_unit),
    }
    _metrics.queued = _metrics.queued + 1
    return nil
end)

mod:hook("AiUtils", "damage_target", function(
    func, target_unit, attacker_unit, action, damage, damage_source
)
    if _resolving then
        return func(target_unit, attacker_unit, action, damage, damage_source)
    end

    local owner, _, blackboard = _eligible(
        target_unit, attacker_unit, action, damage
    )

    if not owner then
        return func(target_unit, attacker_unit, action, damage, damage_source)
    end

    local delay = _ping_delay(owner.peer_id)
    if delay == nil then
        _metrics.unsafe = _metrics.unsafe + 1
        return func(target_unit, attacker_unit, action, damage, damage_source)
    end
    if delay <= 0 then
        return func(target_unit, attacker_unit, action, damage, damage_source)
    end

    if #_pending >= Policy.MAX_PENDING then
        _metrics.overflow = _metrics.overflow + 1
        return func(target_unit, attacker_unit, action, damage, damage_source)
    end

    _pending[#_pending + 1] = {
        func = func,
        target_unit = target_unit,
        attacker_unit = attacker_unit,
        action = action,
        damage = damage,
        damage_source = damage_source,
        peer_id = owner.peer_id,
        remaining = delay,
        delay = delay,
        attack_direction = _attack_direction(action, blackboard),
        stagger_epoch = _stagger_epoch(attacker_unit, target_unit),
    }
    _metrics.queued = _metrics.queued + 1

    -- Eligible callers do not consume the return value; return zero rather than
    -- nil to preserve the numeric shape of AiUtils.damage_target.
    return 0
end)

mod:hook("AiUtils", "stagger", function(
    func, unit, blackboard, attacker_unit, ...
)
    local before = blackboard and blackboard.stagger

    func(unit, blackboard, attacker_unit, ...)

    -- AiUtils.stagger can reject the request before it mutates the
    -- blackboard (for example a boss_staggers gate). Count only a stagger
    -- that the host actually accepted, otherwise a rejected client hit could
    -- incorrectly cancel an enemy attack.
    if blackboard and blackboard.stagger ~= before then
        local by_source = _stagger_epoch_by_unit_source[unit]
        if not by_source then
            by_source = setmetatable({}, { __mode = "k" })
            _stagger_epoch_by_unit_source[unit] = by_source
        end
        by_source[attacker_unit] = (by_source[attacker_unit] or 0) + 1
        _resolve_stagger(unit, attacker_unit)
    end
end)

-- Observe the two vanilla client->host defense RPC receivers AFTER they update
-- the authoritative status extension. Resolving immediately on a valid rising
-- edge means a short block tap or dodge still counts even if it ends before the
-- original RTT deadline.
mod:hook_safe("StatusSystem", "rpc_set_blocking", function(
    self, channel_id, game_object_id, blocking
)
    if not blocking or not _server_network() then return end
    local unit = self.unit_storage and self.unit_storage:unit(game_object_id)
    if unit then _resolve_target_defense(unit, "block") end
end)

mod:hook_safe("StatusSystem", "rpc_status_change_bool", function(
    self, channel_id, status_id, status_bool, game_object_id
)
    if not status_bool or not _server_network() then return end
    local status_name = NetworkLookup
        and NetworkLookup.statuses
        and NetworkLookup.statuses[status_id]
    if status_name ~= "dodging" then return end

    local unit = self.unit_storage and self.unit_storage:unit(game_object_id)
    if unit then _resolve_target_defense(unit, "dodge") end
end)

mod._gt_register_update("host_lag_comp", function(dt)
    if #_pending == 0 then return end

    if mod:get("gt_host_lag_comp") == false or not _server_network() then
        _flush(true)
        return
    end

    local elapsed = type(dt) == "number" and math.max(dt, 0) or 0
    local due = {}

    for i = #_pending, 1, -1 do
        local record = _pending[i]
        record.remaining = record.remaining - elapsed

        if record.remaining <= 0 then
            table.remove(_pending, i)
            due[#due + 1] = record
        end
    end

    for i = #due, 1, -1 do
        _resolve(due[i])
    end
end)

mod:command(
    "gt_lag_comp_status",
    "Show host melee latency-compensation counters",
    function()
        mod:echo(
            "Lag compensation: pending=%d queued=%d applied=%d block=%d dodge=%d stagger=%d dead=%d invalid=%d overflow=%d unsafe=%d",
            #_pending,
            _metrics.queued,
            _metrics.applied,
            _metrics.blocked,
            _metrics.dodged,
            _metrics.staggered,
            _metrics.attacker_dead,
            _metrics.target_invalid,
            _metrics.overflow,
            _metrics.unsafe
        )
    end
)

mod._gt_rt_register("host_lag_comp_bounded", function()
    if Policy.MAX_PENDING ~= 256 then
        return "pending queue bound changed"
    end
    if Policy.configured_cap_seconds(9999) ~= 0.35 then
        return "hard grace-window cap changed"
    end
    return nil
end)
