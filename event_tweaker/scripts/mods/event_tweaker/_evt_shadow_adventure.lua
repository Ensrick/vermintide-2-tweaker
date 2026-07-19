local mod = get_mod("event_tweaker")

-- _evt_shadow_adventure.lua -- issue 413 Adventure Shadow adapter
--
-- Vanilla Shadow cannot be activated outside a Weave: every local client
-- spawns wpn_shadow_gargoyle_head and immediately calls Unit.light on it, while
-- the server receives no wind-settings radius. Adventure does not keep the
-- gargoyle or vfx_static_shadow_01 resident. A host-only pcall cannot contain
-- either engine-resource failure.
--
-- The gameplay itself needs neither asset. Fatshark's server path gives enemies
-- outside six metres of every hero mutator_shadow_damage_reduction (-90% damage
-- taken); its client path fades enemies outside the same radius. This adapter
-- preserves those mechanics using only boot-registered code/buff identities and
-- deliberately omits the non-resident lantern and shadow VFX.
--
-- The stock mutator name is still broadcast, so every peer must run THIS
-- capability before the host may inject it. A dedicated parity channel proves
-- the adapter rather than merely proving some older event_tweaker version. The
-- common pre-session pending-peer fence and hot-join lock remain unconditional.

local ET = mod._evt
local rt_register = ET.rt_register
local Policy = require("scripts/mods/event_tweaker/event_tweaker_shadow_policy")

local SHADOW_CHANNEL = "et_shadow_adventure_v1"
local SHADOW_SCHEMA = 1
local shadow_template
local adapter_ready = false

local function _in_native_weave()
    return ET.weave_wind_active and ET.weave_wind_active() == true
end

local function _position(unit)
    local lookup = rawget(_G, "POSITION_LOOKUP")
    return unit and lookup and lookup[unit] or nil
end

local function _alive(unit)
    local health_alive = rawget(_G, "HEALTH_ALIVE")
    return unit and health_alive and health_alive[unit] == true
end

local function _server_start(context, data)
    if _in_native_weave() then
        return shadow_template._et413_original_server_start(context, data)
    end
    local managers = rawget(_G, "Managers")
    local state = managers and managers.state
    local entity = state and state.entity
    local side = state and state.side
    data.et413_adventure_shadow = true
    data.et413_light_radius = Policy.ADVENTURE_RADIUS
    data.et413_server_index = 0
    data.et413_buffs = {}
    data.buff_system = entity and entity:system("buff_system") or nil
    data.hero_side = side and side:get_side_from_name("heroes") or nil
end

local function _remove_server_buff(data, unit)
    local id = data.et413_buffs and data.et413_buffs[unit]
    if id and data.buff_system then
        pcall(data.buff_system.remove_server_controlled_buff, data.buff_system, unit, id)
    end
    if data.et413_buffs then data.et413_buffs[unit] = nil end
end

local function _server_update(context, data, dt, t)
    if not data.et413_adventure_shadow then
        return shadow_template._et413_original_server_update(context, data, dt, t)
    end
    local hero_side = data.hero_side
    local enemies = hero_side and hero_side:enemy_units()
    local players = hero_side and hero_side.PLAYER_UNITS
    local buff_system = data.buff_system
    if type(enemies) ~= "table" or type(players) ~= "table" or not buff_system then return end

    for _ = 1, 5 do
        data.et413_server_index = data.et413_server_index + 1
        local unit = enemies[data.et413_server_index]
        if not unit then
            data.et413_server_index = 0
            break
        end

        if _alive(unit) and ScriptUnit.has_extension(unit, "buff_system") then
            local unit_pos = _position(unit)
            local revealed = false
            if unit_pos then
                for _, player_unit in pairs(players) do
                    local player_pos = _position(player_unit)
                    if player_pos and Vector3.distance_squared(player_pos, unit_pos)
                        <= Policy.ADVENTURE_RADIUS * Policy.ADVENTURE_RADIUS then
                        revealed = true
                        break
                    end
                end
            end

            local buff_extension = ScriptUnit.has_extension(unit, "buff_system")
            local has_buff = buff_extension
                and buff_extension:has_buff_type("mutator_shadow_damage_reduction")
            if revealed then
                if has_buff and data.et413_buffs[unit] then
                    _remove_server_buff(data, unit)
                end
            else
                -- Match native Shadow: a concealed enemy cannot remain pinged.
                -- The ping system owns removal; this adapter only requests it.
                local ping_extension = ScriptUnit.has_extension(unit, "ping_system")
                if ping_extension and ping_extension:pinged() then
                    local managers = rawget(_G, "Managers")
                    local entity = managers and managers.state and managers.state.entity
                    local ping_system = entity and entity:system("ping_system")
                    if ping_system then ping_system:remove_ping_from_unit(unit) end
                end
                if not has_buff then
                    local id = buff_system:add_buff(
                        unit, "mutator_shadow_damage_reduction", unit, true)
                    if id then data.et413_buffs[unit] = id end
                end
            end
        end
    end

    for unit in pairs(data.et413_buffs) do
        if not _alive(unit) then data.et413_buffs[unit] = nil end
    end
end

local function _server_stop(context, data, is_destroy)
    if data.et413_adventure_shadow then
        for unit in pairs(data.et413_buffs or {}) do
            _remove_server_buff(data, unit)
        end
    end
    return shadow_template._et413_original_server_stop(context, data, is_destroy)
end

local function _client_start(context, data)
    if _in_native_weave() then
        return shadow_template._et413_original_client_start(context, data)
    end
    local managers = rawget(_G, "Managers")
    local side = managers and managers.state and managers.state.side
    data.et413_adventure_shadow = true
    data.et413_client_index = 0
    data.et413_faded_units = {}
    data.hero_side = side and side:get_side_from_name("heroes") or nil
end

local function _client_update(context, data, dt, t)
    if not data.et413_adventure_shadow then
        return shadow_template._et413_original_client_update(context, data, dt, t)
    end
    local managers = rawget(_G, "Managers")
    local state = managers and managers.state
    local player_manager = managers and managers.player
    local entity = state and state.entity
    local fade_system = entity and entity:system("fade_system")
    local hero_side = data.hero_side
    local enemies = hero_side and hero_side:enemy_units()
    local local_player = player_manager and player_manager:local_player()
    if type(enemies) ~= "table" or not fade_system or not local_player then return end

    local observed = local_player:observed_unit()
    local alive_lookup = rawget(_G, "ALIVE")
    if not (alive_lookup and alive_lookup[observed]) then observed = local_player.player_unit end
    local observer_pos = _position(observed)

    for _ = 1, 5 do
        data.et413_client_index = data.et413_client_index + 1
        local unit = enemies[data.et413_client_index]
        if not unit then
            data.et413_client_index = 0
            break
        end
        if _alive(unit) then
            local unit_pos = _position(unit)
            local outside = observer_pos and unit_pos
                and Vector3.distance_squared(observer_pos, unit_pos)
                    >= Policy.ADVENTURE_RADIUS * Policy.ADVENTURE_RADIUS
            local scalar = outside and 1 or 0
            if data.et413_faded_units[unit] ~= scalar then
                fade_system:set_min_fade(unit, scalar)
                data.et413_faded_units[unit] = scalar
            end
        end
    end

    for unit in pairs(data.et413_faded_units) do
        if not _alive(unit) then data.et413_faded_units[unit] = nil end
    end
end

local function _client_respawn(context, data, spawned_unit)
    if not data.et413_adventure_shadow then
        return shadow_template._et413_original_client_respawn(context, data, spawned_unit)
    end
    -- Adventure adapter has no linked lantern unit to respawn.
end

local function _client_stop(context, data, is_destroy)
    if data.et413_adventure_shadow then
        local managers = rawget(_G, "Managers")
        local entity = managers and managers.state and managers.state.entity
        local fade_system = entity and entity:system("fade_system")
        if fade_system then
            for unit in pairs(data.et413_faded_units or {}) do
                local ok_alive, alive = pcall(Unit.alive, unit)
                if ok_alive and alive then
                    pcall(fade_system.set_min_fade, fade_system, unit, 0)
                end
            end
        end
    end
    return shadow_template._et413_original_client_stop(context, data, is_destroy)
end

do
    local templates = rawget(_G, "MutatorTemplates")
    shadow_template = templates and rawget(templates, "shadow")
    local buffs = rawget(_G, "BuffTemplates")
    local shadow_buff = buffs and rawget(buffs, "mutator_shadow_damage_reduction")
    local sub_buff = shadow_buff and shadow_buff.buffs and shadow_buff.buffs[1]
    if shadow_template and shadow_template.server and shadow_template.client
        and type(shadow_template.server_start_function) == "function"
        and type(shadow_template.server_update_function) == "function"
        and type(shadow_template.client_start_function) == "function"
        and type(shadow_template.client_update_function) == "function"
        and type(shadow_template.client_player_respawned_function) == "function"
        and type(shadow_template.server.stop_function) == "function"
        and type(shadow_template.client.stop_function) == "function"
        and sub_buff then
        -- Preserve the native dispatch only once. VMF developer reloads can
        -- evaluate this module again in the same Lua state; capturing our prior
        -- wrapper as "original" would recurse on the next real Weave.
        shadow_template._et413_vanilla_server_start =
            shadow_template._et413_vanilla_server_start or shadow_template.server_start_function
        shadow_template._et413_vanilla_server_update =
            shadow_template._et413_vanilla_server_update or shadow_template.server_update_function
        shadow_template._et413_vanilla_server_stop =
            shadow_template._et413_vanilla_server_stop or shadow_template.server.stop_function
        shadow_template._et413_vanilla_client_start =
            shadow_template._et413_vanilla_client_start or shadow_template.client_start_function
        shadow_template._et413_vanilla_client_update =
            shadow_template._et413_vanilla_client_update or shadow_template.client_update_function
        shadow_template._et413_vanilla_client_respawn =
            shadow_template._et413_vanilla_client_respawn or shadow_template.client_player_respawned_function
        shadow_template._et413_vanilla_client_stop =
            shadow_template._et413_vanilla_client_stop or shadow_template.client.stop_function

        shadow_template._et413_original_server_start = shadow_template._et413_vanilla_server_start
        shadow_template._et413_original_server_update = shadow_template._et413_vanilla_server_update
        shadow_template._et413_original_server_stop = shadow_template._et413_vanilla_server_stop
        shadow_template._et413_original_client_start = shadow_template._et413_vanilla_client_start
        shadow_template._et413_original_client_update = shadow_template._et413_vanilla_client_update
        shadow_template._et413_original_client_respawn = shadow_template._et413_vanilla_client_respawn
        shadow_template._et413_original_client_stop = shadow_template._et413_vanilla_client_stop

        shadow_template.server_start_function = _server_start
        shadow_template.server_update_function = _server_update
        shadow_template.client_start_function = _client_start
        shadow_template.client_update_function = _client_update
        shadow_template.client_player_respawned_function = _client_respawn
        shadow_template.server.update = _server_update
        shadow_template.client.update = _client_update
        shadow_template.server.stop_function = _server_stop
        shadow_template.client.stop_function = _client_stop
        -- Outside a Weave BuffExtension otherwise leaves this wind-mutator buff
        -- at its nil/default multiplier (zero effect). Real Weaves override it
        -- from active wind settings at add/remove time.
        sub_buff.multiplier = -0.9
        adapter_ready = true
    else
        pcall(printf, "[et:413] Adventure Shadow adapter unavailable: vanilla template/buff contract changed")
    end
end

local shadow_parity
do
    local ok_lib, factory = pcall(function()
        return mod:dofile("scripts/mods/event_tweaker/_lib_peer_parity")
    end)
    if ok_lib and type(factory) == "function" then
        local ok_inst, instance = pcall(factory, mod, {
            channel = SHADOW_CHANNEL,
            schema = SHADOW_SCHEMA,
            mod_label = "Tweaker: Events with Adventure Shadow support",
            echo_prefix = "[Events]",
        })
        if ok_inst and type(instance) == "table" then
            shadow_parity = instance
            pcall(function() shadow_parity:install() end)
            pcall(function()
                shadow_parity:register_gated_feature("et_shadow_adventure", {
                    label = "peer_parity_shadow_feature_label",
                    on_enable = function()
                        pcall(printf, "[et:413] Adventure Shadow peer capability established")
                    end,
                    on_disable = function()
                        pcall(printf, "[et:413] Adventure Shadow disabled: a peer lacks capability v1")
                    end,
                })
            end)
        end
    end
end
mod._et_shadow_parity = shadow_parity

local function _wire_safe()
    if not adapter_ready or not shadow_parity or not ET.peer_feature_wire_safe then return false end
    return ET.peer_feature_wire_safe(shadow_parity) == true
end

local function _plan()
    return Policy.plan(true, _in_native_weave(), _wire_safe(), adapter_ready)
end

local notified = {}
local function _notify_drop(reason)
    reason = tostring(reason or "unsafe")
    if notified[reason] then return end
    notified[reason] = true
    pcall(function()
        mod:echo("[Events] Shadow skipped: every player needs the current Adventure Shadow-capable Tweaker: Events build.")
    end)
end

ET.shadow_adventure_wire_safe = _wire_safe
ET.shadow_adventure_plan = _plan
ET.notify_shadow_drop = _notify_drop
ET.shadow_adventure_adapter_ready = function() return adapter_ready end

rt_register("issue413_shadow_adventure_adapter", function()
    if not adapter_ready then return "Adventure Shadow template adapter was not installed" end
    if not shadow_parity or not shadow_parity:is_installed() then
        return "Adventure Shadow capability beacon was not installed"
    end
    if Policy.plan(true, false, true, true) ~= "adventure_adapter" then
        return "Shadow policy no longer allows a proven all-capability Adventure lobby"
    end
    if Policy.plan(true, false, false, true) ~= "drop_peer_capability" then
        return "Shadow policy no longer fails closed for an unproven peer"
    end
    if Policy.plan(true, true, false, true) ~= "native_weave" then
        return "Shadow policy interferes with native Weaves"
    end
end)
