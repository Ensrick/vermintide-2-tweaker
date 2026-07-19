local mod = get_mod("enemy_tweaker")

-- Issue #61: per-human personal combat handicap. Damage remains fully
-- host-authoritative. A client sends only its own requested preset; the host
-- keys it by VMF's authenticated sender_peer_id and applies it at the vanilla
-- server damage chokepoint. No buff/network lookup is registered.

local ET = mod._et
local Policy = ET.PersonalHandicapPolicy
local HostilePolicy = ET.HealthMultiplierCore
local UnitPolicy = ET.PersonalHandicapUnits
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

local UnitAccess = UnitPolicy.new({
    -- Crash GUID 404228a8 (issue #640): a Globadier poison AreaDamageExtension
    -- retained source_attacker_unit after the Globadier despawned. Stingray's
    -- Unit.get_data asserted on that non-nil deleted reference and bypassed
    -- pcall. Vanilla itself uses Unit.alive before consuming buffered units
    -- (area_damage_extension.lua:368); use the same lifetime gate before every
    -- native Unit read and PlayerManager owner lookup here. Rejecting an invalid
    -- classifier preserves vanilla damage rather than suppressing func below.
    unit_alive = Unit.alive,
    breed = function(unit) return Unit.get_data(unit, "breed") end,
    owner = function(unit)
        local player_manager = Managers.player
        return player_manager and player_manager:owner(unit) or nil
    end,
    is_hostile_breed = HostilePolicy.is_hostile_breed,
})
local _printf = rawget(_G, "printf") or function() end
_printf("[et:640] applied: Unit.alive guards owner=true breed=true neutral_bypass=true")

mod:hook(DamageUtils, "apply_buffs_to_damage", function(func, current_damage,
        attacked_unit, attacker_unit, damage_source, victim_units, damage_type,
        buff_attack_type, first_hit, source_attacker_unit)
    if _is_server() and type(current_damage) == "number" and current_damage > 0 then
        -- #450 composes Skarrik's ranged resistance into this existing singleton
        -- damage owner. The provider is exact-breed/ranged gated and otherwise
        -- returns the original value, so Personal difficulty remains independent.
        if type(ET.boss_behavior_scale_incoming_damage) == "function" then
            current_damage = ET.boss_behavior_scale_incoming_damage(
                current_damage, attacked_unit, buff_attack_type)
        end
        local attacked_player = UnitAccess.owner(attacked_unit)
        if attacked_player then
            local incoming = Policy.factors(_host_difficulty(), _preset_for_player(attacked_player))
            -- Neutral presets must not inspect attacker units. Besides avoiding
            -- needless work, this closes #640 even when a lingering area effect
            -- retains a deleted source while Personal difficulty is Auto/off.
            if incoming ~= 1 then
                -- Explosions/projectiles may carry the hero or enemy on
                -- source_attacker_unit while attacker_unit is the transient unit.
                local attacker_player = UnitAccess.owner(attacker_unit)
                    or UnitAccess.owner(source_attacker_unit)
                -- Personal difficulty is enemy combat only. Player-v-player
                -- friendly fire, self/environmental damage, bots, and pets stay
                -- vanilla. An invalid/deleted source cannot establish hostility.
                if not attacker_player then
                    current_damage = UnitPolicy.scale_if_hostile(current_damage,
                        incoming, UnitAccess, attacker_unit, source_attacker_unit,
                        Policy.scale_damage)
                end
            end
        else
            local attacker_player = UnitAccess.owner(attacker_unit)
                or UnitAccess.owner(source_attacker_unit)
            if attacker_player then
                local _, outgoing = Policy.factors(_host_difficulty(),
                    _preset_for_player(attacker_player))
                current_damage = UnitPolicy.scale_if_hostile(current_damage,
                    outgoing, UnitAccess, attacked_unit, nil, Policy.scale_damage)
            end
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

ET.rt_register("issue640_personal_handicap_unit_lifetime", function()
    local live_player = { state = "live", breed = { race = "hero" } }
    local live_proxy = { state = "live", breed = nil }
    local live_enemy = { state = "live", breed = { race = "skaven" } }
    local deleted_globadier = { state = "deleted", breed = { race = "skaven" } }
    local owner_marker = {}
    local calls = { alive = 0, owner = 0, breed = 0 }
    local access = UnitPolicy.new({
        unit_alive = function(unit)
            calls.alive = calls.alive + 1
            return unit.state == "live"
        end,
        owner = function(unit)
            calls.owner = calls.owner + 1
            return unit == live_player and owner_marker or nil
        end,
        breed = function(unit)
            calls.breed = calls.breed + 1
            return unit.breed
        end,
        is_hostile_breed = HostilePolicy.is_hostile_breed,
    })

    if access.owner(nil) ~= nil or access.is_hostile_ai(nil) then
        return "nil unit reached classifier"
    end
    if access.owner(live_player) ~= owner_marker then return "live owner not resolved" end
    if not access.is_hostile_ai(live_enemy) then return "live hostile not resolved" end
    local native_before_deleted = calls.owner + calls.breed
    if access.owner(deleted_globadier) ~= nil
            or access.is_hostile_ai(deleted_globadier) then
        return "deleted Globadier classified"
    end
    if calls.owner + calls.breed ~= native_before_deleted then
        return "deleted Globadier reached native owner/breed access"
    end

    local alive_before_off = calls.alive
    local unchanged = UnitPolicy.scale_if_hostile(40, 1, access, live_proxy,
        deleted_globadier, Policy.scale_damage)
    if unchanged ~= 40 or calls.alive ~= alive_before_off then
        return "Auto/off path inspected attacker units"
    end

    local lingering = UnitPolicy.scale_if_hostile(40, 1.25, access, live_proxy,
        deleted_globadier, Policy.scale_damage)
    if lingering ~= 40 then return "deleted lingering source changed damage" end
    local hostile = UnitPolicy.scale_if_hostile(40, 1.25, access, live_enemy,
        deleted_globadier, Policy.scale_damage)
    if hostile ~= 50 then return "live hostile scaling failed" end
end)

_queue_local_request(true)
