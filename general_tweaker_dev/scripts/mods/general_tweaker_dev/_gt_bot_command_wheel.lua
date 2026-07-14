local mod = get_mod("gt_dev")
local policy = mod:dofile("scripts/mods/general_tweaker_dev/_gt_bot_command_policy")

-- Issue #359: reuse the four already-networked Versus social-wheel events as a
-- second Adventure/Deus page. No NetworkLookup mutation and no custom RPC: the
-- host decodes the existing event after vanilla handles its chat/VO surface.
-- Bot brains are server-owned, so clients neither see the page nor mutate AI.
mod._GT359_BOT_COMMAND_WHEEL_MARKER = "gt-359-existing-versus-events-host-bot-orders"

local PAGE_MARKER = "gt359_bot_command_page"
local _last_enemy_by_pinger = {}
local _holds = {}
local _cover
local _hold_token = 0

local function _enabled()
    return mod:get("gt_bot_command_wheel") == true
end

local function _is_host()
    return Managers.player and Managers.player.is_server == true
end

local function _game_time()
    local tm = Managers.time
    return tm and tm.time and tm:time("game") or nil
end

local function _event_name(event_id)
    local lookup = rawget(_G, "NetworkLookup")
    local events = lookup and lookup.social_wheel_events
    return events and rawget(events, event_id) or nil
end

local function _command_page()
    local ping_types = rawget(_G, "PingTypes") or {}
    return {
        [PAGE_MARKER] = true,
        {
            event_text = "vs_social_wheel_dark_pact_general_attack",
            icon = "radial_chat_icon_attack",
            name = "vs_social_wheel_dark_pact_general_attack",
            text = "vs_social_wheel_dark_pact_general_attack",
            data = {},
            ping_type = ping_types.VO_ONLY,
        },
        {
            event_text = "vs_social_wheel_dark_pact_general_group_up",
            icon = "radial_chat_icon_gather",
            name = "vs_social_wheel_dark_pact_general_group_up",
            text = "vs_social_wheel_dark_pact_general_group_up",
            data = {},
            ping_type = ping_types.VO_ONLY,
        },
        {
            event_text = "vs_social_wheel_dark_pact_general_cover_me",
            icon = "radial_chat_icon_cover",
            name = "vs_social_wheel_dark_pact_general_cover_me",
            text = "vs_social_wheel_dark_pact_general_cover_me",
            data = {},
            ping_type = ping_types.VO_ONLY,
        },
        {
            event_text = "vs_social_wheel_dark_pact_general_wait",
            icon = "radial_chat_icon_wait",
            name = "vs_social_wheel_dark_pact_general_wait",
            text = "vs_social_wheel_dark_pact_general_wait",
            data = {},
            -- This preserves the crosshair position in PingSystem._pinged_units;
            -- the host consumes it immediately and boxes it in the bot extension.
            ping_type = ping_types.MOVEMENT_WAIT,
        },
    }
end

local function _find_page(category)
    if type(category) ~= "table" then return nil end
    for i = 1, #category do
        if type(category[i]) == "table" and category[i][PAGE_MARKER] then
            return i
        end
    end
    return nil
end

local function _set_page(category, wanted)
    if type(category) ~= "table" then return false end
    local index = _find_page(category)
    if wanted and not index then
        -- Page one remains vanilla chat; command orders are the first page-cycle.
        table.insert(category, math.min(2, #category + 1), _command_page())
        return true
    elseif not wanted and index then
        table.remove(category, index)
        return true
    end
    return false
end

local function _bot_system()
    local entity = Managers.state and Managers.state.entity
    return entity and entity.system and entity:system("ai_bot_group_system") or nil
end

local function _side_bot_data(system, pinger_unit)
    local side_manager = Managers.state and Managers.state.side
    local side = side_manager and side_manager.side_by_unit and side_manager.side_by_unit[pinger_unit]
    return side and system and system._bot_ai_data and system._bot_ai_data[side.side_id] or nil
end

local function _clear_our_holds()
    for bot_unit, rec in pairs(_holds) do
        if Unit.alive(bot_unit) then
            local bb = rawget(_G, "BLACKBOARDS") and BLACKBOARDS[bot_unit]
            local ext = bb and bb.ai_bot_group_extension
            local data = ext and ext.data
            if data and data._gt359_hold_token == rec.token then
                ext:set_hold_position(nil)
                data._gt359_hold_token = nil
            end
        end
        _holds[bot_unit] = nil
    end
end

local function _arm_cover(pinger_unit, until_t)
    _clear_our_holds()
    _cover = { unit = pinger_unit, until_t = until_t }
end

function mod._gt359_clear_commands()
    _cover = nil
    _clear_our_holds()
    local settings = rawget(_G, "SocialWheelSettings")
    if settings then
        _set_page(settings.general, false)
        _set_page(settings.general_gamepad, false)
    end
end

local function _hold_nearest(system, pinger_unit, position, t)
    local bot_data = _side_bot_data(system, pinger_unit)
    if type(bot_data) ~= "table" or not position then return false end

    local candidates = {}
    for bot_unit in pairs(bot_data) do
        if Unit.alive(bot_unit) then
            local bot_position = POSITION_LOOKUP[bot_unit]
            if bot_position then
                candidates[#candidates + 1] = {
                    unit = bot_unit,
                    distance_sq = Vector3.distance_squared(bot_position, position),
                }
            end
        end
    end

    local bot_unit = policy.nearest(candidates)
    local data = bot_unit and bot_data[bot_unit]
    local ext = data and data.blackboard and data.blackboard.ai_bot_group_extension
    if not ext then return false end

    _hold_token = _hold_token + 1
    ext:set_hold_position(position, policy.HOLD_RADIUS_M)
    ext.data._gt359_hold_token = _hold_token
    _holds[bot_unit] = { token = _hold_token, until_t = t + policy.HOLD_DURATION_S }
    return true
end

local function _wait_position(ping_system, pinger_unit)
    local rec = ping_system and ping_system._pinged_units and ping_system._pinged_units[pinger_unit]
    local p = rec and rec.position
    if type(p) == "table" and p[1] and p[2] and p[3] then
        return Vector3(p[1], p[2], p[3])
    end
    return Unit.alive(pinger_unit) and Unit.world_position(pinger_unit, 0) or nil
end

local function _execute_command(ping_system, command, pinger_unit, t)
    local system = _bot_system()
    if not system then return false end

    if command == "attack_pinged" then
        local target = _last_enemy_by_pinger[pinger_unit]
        if target and HEALTH_ALIVE[target] and system._urgent_targets then
            system._urgent_targets[target] = t + policy.ATTACK_DURATION_S
            return true
        end
        return false
    elseif command == "hold_here" then
        return _hold_nearest(system, pinger_unit, _wait_position(ping_system, pinger_unit), t)
    elseif command == "group_up" then
        _arm_cover(pinger_unit, t + policy.GROUP_DURATION_S)
        return true
    elseif command == "cover_me" then
        _arm_cover(pinger_unit, t + policy.COVER_DURATION_S)
        return true
    end
    return false
end

-- Duplicate-hook preflight 2026-07-14: gt_dev had no SocialWheelUI hooks and no
-- PingSystem._handle_chat hook. Both pairs are owned only by this module.
mod:hook("SocialWheelUI", "_open_menu", function(func, self, ...)
    local settings = rawget(_G, "SocialWheelSettings")
    local wanted = _enabled() and _is_host()
    local changed = settings and (
        _set_page(settings.general, wanted)
        or _set_page(settings.general_gamepad, wanted)
    )
    -- Lua `or` short-circuits, so always reconcile the second category too.
    if settings then
        changed = _set_page(settings.general_gamepad, wanted) or changed
    end
    if changed and self._create_social_wheel then
        self:_create_social_wheel(settings)
    end
    return func(self, ...)
end)

mod:hook_safe("PingSystem", "_handle_chat", function(self, ping_type, event_id, sender_player, pinger_unit, pinged_unit)
    if not (_enabled() and _is_host() and sender_player and pinger_unit) then return end

    local local_player = Managers.player and Managers.player:local_player()
    local sender_peer = sender_player.peer_id
    local local_peer = local_player and local_player.peer_id
    if sender_player ~= local_player and not policy.is_host_sender(sender_peer, local_peer) then return end

    local side_manager = Managers.state and Managers.state.side
    if pinged_unit and Unit.alive(pinged_unit) and side_manager
            and side_manager.is_enemy and side_manager:is_enemy(pinger_unit, pinged_unit) then
        _last_enemy_by_pinger[pinger_unit] = pinged_unit
    end

    local command = policy.command_for_event(_event_name(event_id))
    local mechanism = Managers.mechanism and Managers.mechanism:current_mechanism_name()
    local t = command and mechanism ~= "versus" and _game_time() or nil
    if not t then return end

    local ok = _execute_command(self, command, pinger_unit, t)
    local engine_printf = rawget(_G, "printf")
    if engine_printf then
        engine_printf("[gt:359] command=%s applied=%s duration=bounded", command, tostring(ok))
    end
end)

-- Cover/group-up composes at the existing singleton destination-assignment
-- hook. Returning true tells its owner that this temporary order has final say.
function mod._gt359_apply_follow_override(system, bot_ai_data)
    local t = _game_time()
    if not (_enabled() and _cover and t and policy.is_active(t, _cover.until_t)
            and Unit.alive(_cover.unit) and type(bot_ai_data) == "table") then
        _cover = nil
        return false
    end

    local bots = {}
    for bot_unit, data in pairs(bot_ai_data) do
        if data and not data.hold_position and Unit.alive(bot_unit) then
            bots[#bots + 1] = bot_unit
        end
    end
    table.sort(bots, function(a, b) return tostring(a) < tostring(b) end)

    local points
    local entity = Managers.state and Managers.state.entity
    local ai_system = entity and entity.system and entity:system("ai_system")
    local nav_world = ai_system and ai_system.nav_world and ai_system:nav_world()
    if nav_world and mod._gt_fan_points_for_unit then
        points = mod._gt_fan_points_for_unit(system, nav_world, _cover.unit, #bots)
    end

    for i = 1, #bots do
        local data = bot_ai_data[bots[i]]
        data.follow_unit = _cover.unit
        if points and points[i] then data.follow_position = points[i] end
    end
    return true
end

if mod._gt_register_update then
    mod._gt_register_update("gt359_bot_command_expiry", function()
        local t = _game_time()
        if not t then return end
        if not _enabled() then
            mod._gt359_clear_commands()
            return
        end
        for bot_unit, rec in pairs(_holds) do
            if not Unit.alive(bot_unit) or not policy.is_active(t, rec.until_t) then
                if Unit.alive(bot_unit) then
                    local bb = rawget(_G, "BLACKBOARDS") and BLACKBOARDS[bot_unit]
                    local ext = bb and bb.ai_bot_group_extension
                    local data = ext and ext.data
                    if data and data._gt359_hold_token == rec.token then
                        ext:set_hold_position(nil)
                        data._gt359_hold_token = nil
                    end
                end
                _holds[bot_unit] = nil
            end
        end
    end)
end

mod._gt_rt_register("issue359_bot_command_wheel", function()
    if mod._GT359_BOT_COMMAND_WHEEL_MARKER ~= "gt-359-existing-versus-events-host-bot-orders" then
        return "issue 359 provenance marker missing"
    end
    if type(mod._gt359_apply_follow_override) ~= "function" then
        return "issue 359 follow-override dispatcher missing"
    end
    for event_name in pairs(policy.EVENTS) do
        local lookup = rawget(_G, "NetworkLookup")
        if not (lookup and lookup.social_wheel_events
                and rawget(lookup.social_wheel_events, event_name)) then
            return "vanilla social-wheel event unavailable: " .. event_name
        end
    end
end)
