-- Issue #357: owner-only HUD timers for the four bomb-bubble boon cooldowns.
--
-- These templates are deliberately client-local. They are never appended to
-- NetworkLookup.buff_templates and never sent through vanilla rpc_add_buff; the
-- host targets only the boon owner through a schema-gated VMF event. The display
-- is presentation only -- gameplay timing remains owned by the existing
-- grenade_explode_buff_area gate in chaos_wastes_tweaker_dev.lua.
local mod = get_mod("ct_dev")
local M = {}

local CHANNEL = "ct_bomb_cooldown_display_v1"
local MAX_INTERVAL_SECONDS = 600 -- exact authored setting ceiling

local BOONS = {
    boon_supportbomb_concentration_01 = {
        template = "ct_bomb_cooldown_display_concentration",
        icon = "deus_icon_supportbomb_concentration_01",
    },
    boon_supportbomb_crit_01 = {
        template = "ct_bomb_cooldown_display_crit",
        icon = "deus_icon_supportbomb_crit_01",
    },
    boon_supportbomb_healing_01 = {
        template = "ct_bomb_cooldown_display_healing",
        icon = "deus_icon_supportbomb_healing_01",
    },
    boon_supportbomb_speed_01 = {
        template = "ct_bomb_cooldown_display_speed",
        icon = "deus_icon_supportbomb_speed_01",
    },
}

local function _valid_interval(value)
    return type(value) == "number"
        and value == value
        and value > 0
        and value <= MAX_INTERVAL_SECONDS
end

local function _expected_host_peer_id()
    local mechanism = Managers and Managers.mechanism
    if mechanism and type(mechanism.server_peer_id) == "function" then
        local ok, peer_id = pcall(mechanism.server_peer_id, mechanism)
        if ok and peer_id then return peer_id end
    end

    local network = Managers and Managers.state and Managers.state.network
    if not network then return nil end
    if network.network_client and network.network_client.server_peer_id then
        return network.network_client.server_peer_id
    end
    return network.network_server and network.network_server.server_peer_id or nil
end

local function _install_templates()
    local registry = rawget(_G, "BuffTemplates")
    if type(registry) ~= "table" then return false end

    for _, spec in pairs(BOONS) do
        registry[spec.template] = {
            buffs = {
                {
                    duration = 1,
                    icon = spec.icon,
                    is_cooldown = true,
                    max_stacks = 1,
                    name = spec.template,
                    refresh_durations = true,
                },
            },
        }
    end
    return true
end

local function _apply_local(owner_unit, boon_name, interval)
    local spec = BOONS[boon_name]
    if not spec or not _valid_interval(interval) or not owner_unit then return false end

    local buff_extension = ScriptUnit and ScriptUnit.has_extension
        and ScriptUnit.has_extension(owner_unit, "buff_system")
    if not buff_extension or type(buff_extension.add_buff) ~= "function" then return false end

    local ok = pcall(buff_extension.add_buff, buff_extension, spec.template, {
        external_optional_duration = interval,
    })
    if ok then
        pcall(printf, "[ct:357] owner cooldown display boon=%s duration=%.1fs",
            boon_name, interval)
    end
    return ok
end

function M.install(schema_version)
    if M._installed then return true end
    if type(schema_version) ~= "number" or not _install_templates() then return false end

    M._schema_version = schema_version
    mod:network_register(CHANNEL, function(sender_peer_id, received_schema, boon_name, interval)
        if received_schema ~= M._schema_version then
            pcall(printf, "[ct:357] dropped cooldown display: schema=%s expected=%s sender=%s",
                tostring(received_schema), tostring(M._schema_version), tostring(sender_peer_id))
            return
        end
        local host_peer_id = _expected_host_peer_id()
        if not host_peer_id or sender_peer_id ~= host_peer_id then
            pcall(printf, "[ct:357] dropped cooldown display: non-host sender=%s expected=%s",
                tostring(sender_peer_id), tostring(host_peer_id))
            return
        end
        if not BOONS[boon_name] or not _valid_interval(interval) then
            pcall(printf, "[ct:357] dropped cooldown display: invalid payload boon=%s interval=%s",
                tostring(boon_name), tostring(interval))
            return
        end

        local player_manager = Managers and Managers.player
        local player = player_manager and player_manager:local_player(1)
        _apply_local(player and player.player_unit, boon_name, interval)
    end)
    M._installed = true
    return true
end

-- Called only from the existing gate's allowed branch. This function repeats the
-- authority check so a client-side invocation can never forge a HUD cooldown.
function M.notify_allowed(owner_unit, boon_name, interval)
    if not (Managers and Managers.player and Managers.player.is_server) then return false end
    if not BOONS[boon_name] or not _valid_interval(interval) then return false end

    local owner = Managers.player:owner(owner_unit)
    if not owner or owner.bot_player then return false end
    if type(owner.is_player_controlled) == "function"
        and not owner:is_player_controlled() then return false end

    if owner.local_player then
        return _apply_local(owner_unit, boon_name, interval)
    end

    local peer_id = owner.network_id and owner:network_id()
    if not peer_id then return false end
    mod:network_send(CHANNEL, peer_id, M._schema_version, boon_name, interval)
    return true
end

function M.valid_payload(boon_name, interval)
    return BOONS[boon_name] ~= nil and _valid_interval(interval)
end

function M.regression_check(schema_version)
    if not M._installed or M._schema_version ~= schema_version then
        return "display module not installed with current schema"
    end
    local registry = rawget(_G, "BuffTemplates")
    for boon_name, spec in pairs(BOONS) do
        local buff = registry and registry[spec.template]
        local sub = buff and buff.buffs and buff.buffs[1]
        if not sub or sub.icon ~= spec.icon or sub.is_cooldown ~= true then
            return "invalid local template for " .. boon_name
        end
    end
    if _valid_interval(0) or _valid_interval(0 / 0) then
        return "interval validation accepts zero or NaN"
    end
    return nil
end

M.channel = CHANNEL
M.boons = BOONS

return M
