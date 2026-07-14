local mod = get_mod("enemy_tweaker")

-- Issue #61: per-human personal combat handicap. Damage remains fully
-- host-authoritative. A client sends only its own requested preset; the host
-- keys it by VMF's authenticated sender_peer_id and applies it at the vanilla
-- server damage chokepoint. No buff/network lookup is registered.

local ET = mod._et
local Policy = ET.PersonalHandicapPolicy
local HostilePolicy = ET.HealthMultiplierCore
local RPC = "et_personal_handicap"
local SETTING = "personal_difficulty"
local SEND_RETRIES = 3
local SEND_INTERVAL = 0.75

local requested_by_peer = {}
local pending_send
local last_context

local function _is_server()
    return Managers.player and Managers.player.is_server
end

local function _host_peer_id()
    local mechanism = Managers.mechanism
    if mechanism and mechanism.server_peer_id then
        local ok, peer_id = pcall(mechanism.server_peer_id, mechanism)
        if ok and peer_id then return peer_id end
    end
    local network = Managers.state and Managers.state.network
    return network and ((network.network_client and network.network_client.server_peer_id)
        or (network.network_server and network.network_server.server_peer_id))
end

local function _local_peer_id()
    local ok, peer_id = pcall(function() return Network.peer_id() end)
    return ok and peer_id or nil
end

local function _queue_local_request(force)
    local preset = Policy.sanitize_preset(mod:get(SETTING))
    local host = _host_peer_id()
    local local_peer = _local_peer_id()
    local context = tostring(host) .. ":" .. tostring(local_peer) .. ":" .. preset
    if not force and context == last_context then return end
    last_context = context

    if _is_server() then
        if local_peer then requested_by_peer[local_peer] = preset end
        pending_send = nil
        mod:info("[et:61] local preset=%s host=%s", preset, tostring(host))
    elseif host and local_peer then
        pending_send = {
            host = host,
            preset = preset,
            attempts_left = SEND_RETRIES,
            next_at = os.clock(),
        }
        mod:info("[et:61] queued preset=%s host=%s retries=%d",
            preset, tostring(host), SEND_RETRIES)
    end
end

mod:network_register(RPC, function(sender_peer_id, schema, requested_preset)
    if not _is_server() or sender_peer_id == nil or schema ~= ET.rpc_schema then return end
    requested_by_peer[sender_peer_id] = Policy.sanitize_preset(requested_preset)
    mod:info("[et:61] request peer=%s preset=%s", tostring(sender_peer_id),
        tostring(requested_by_peer[sender_peer_id]))
end)

local function _update()
    _queue_local_request(false)
    local queued = pending_send
    if not queued or os.clock() < queued.next_at then return end

    local vmf = get_mod("VMF")
    if vmf and vmf.ping_vmf_users then pcall(vmf.ping_vmf_users) end
    mod:info("[et:61] emit preset=%s host=%s attempts_left=%d",
        queued.preset, tostring(queued.host), queued.attempts_left)
    mod:network_send(RPC, queued.host, ET.rpc_schema, queued.preset)
    queued.attempts_left = queued.attempts_left - 1
    if queued.attempts_left <= 0 then
        pending_send = nil
    else
        queued.next_at = os.clock() + SEND_INTERVAL
    end
end

local function _preset_for_player(player)
    if not player or player.bot_player or not player.peer_id then return "off" end
    if player.peer_id == _local_peer_id() and _is_server() then
        return Policy.sanitize_preset(mod:get(SETTING))
    end
    return requested_by_peer[player.peer_id] or "off"
end

local function _host_difficulty()
    local manager = Managers.state and Managers.state.difficulty
    return manager and manager:get_difficulty() or nil
end

local function _is_hostile_ai(unit)
    if unit == nil then return false end
    local ok, breed = pcall(Unit.get_data, unit, "breed")
    return ok and HostilePolicy.is_hostile_breed(breed)
end

local function _owner(unit)
    return unit and Managers.player:owner(unit) or nil
end

mod:hook(DamageUtils, "apply_buffs_to_damage", function(func, current_damage,
        attacked_unit, attacker_unit, damage_source, victim_units, damage_type,
        buff_attack_type, first_hit, source_attacker_unit)
    if _is_server() and type(current_damage) == "number" and current_damage > 0 then
        local attacked_player = _owner(attacked_unit)
        -- Explosions/projectiles may carry the hero or enemy on
        -- source_attacker_unit while attacker_unit is the transient damage unit.
        local attacker_player = _owner(attacker_unit) or _owner(source_attacker_unit)
        local hostile_attacker = _is_hostile_ai(attacker_unit) or _is_hostile_ai(source_attacker_unit)
        -- Personal difficulty is enemy combat only. Player-v-player friendly fire,
        -- self/environmental damage, bots, and pet damage remain vanilla.
        if attacked_player and not attacker_player and hostile_attacker then
            local incoming = Policy.factors(_host_difficulty(), _preset_for_player(attacked_player))
            current_damage = Policy.scale_damage(current_damage, incoming)
        elseif attacker_player and not attacked_player and _is_hostile_ai(attacked_unit) then
            local _, outgoing = Policy.factors(_host_difficulty(), _preset_for_player(attacker_player))
            current_damage = Policy.scale_damage(current_damage, outgoing)
        end
    end
    -- Feed the adjusted base through vanilla exactly once so damage-taken/dealt
    -- buffs, overcharge conversion, game-mode callbacks, and procs all observe
    -- the same authoritative value before network quantization.
    return func(current_damage, attacked_unit, attacker_unit, damage_source,
        victim_units, damage_type, buff_attack_type, first_hit, source_attacker_unit)
end)

ET.personal_handicap_update = _update
ET.personal_handicap_setting_changed = function() _queue_local_request(true) end
ET.personal_handicap_clear = function()
    pending_send = nil
    last_context = nil
    for peer_id in pairs(requested_by_peer) do requested_by_peer[peer_id] = nil end
end

ET.rt_register("issue61_personal_handicap_authoritative", function()
    local incoming, outgoing, delta = Policy.factors("harder", "cataclysm")
    if incoming ~= 1.25 or outgoing ~= 0.85 or delta ~= 2 then
        return "Champion-to-Cataclysm policy drift"
    end
    if type(ET.personal_handicap_update) ~= "function" then return "update driver missing" end
end)

_queue_local_request(true)
