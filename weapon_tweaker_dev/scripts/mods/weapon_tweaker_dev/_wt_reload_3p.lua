-- _wt_reload_3p.lua -- local-owner 3P reload replay + receiver-native reload
-- stance contracts for cross-character ranged weapons (issue #536).
--
-- Source boundary:
-- GenericAmmoUserExtension.start_reload_animation plays the event on the local
-- 1P rig, then sends rpc_anim_event to the other peers. It never plays the event
-- on the originating player's owner_unit (the 3P body). The server sends only to
-- clients; a client sends to the server, which forwards to every client except
-- the origin. That is correct for vanilla first-person play, but leaves a local
-- third-person camera with no reload animation. We replay only on the local 3P
-- body with Unit.animation_event, which is local-only and cannot rebroadcast.

local mod = get_mod("wt_dev")
local WT = mod._wt
local _safe_has_anim = WT.safe_has_anim
local _unit_state = WT.unit_state

local _RELOAD_CONTRACTS = {
    -- Kerillian Volley Crossbow on the Saltzpyre body. Both vanilla templates
    -- emit the generic `reload` event; the receiver's CURRENT wield state picks
    -- the actual clip/sequence. Re-arm Saltzpyre's native volley-crossbow state
    -- before the reload event so it cannot fall through to ordinary crossbow.
    repeating_crossbow_elf_template = {
        wh_ = {
            stance = "to_repeating_crossbow",
            events = { reload = "reload", reload_last = "reload_last" },
        },
    },
}

local function _contract_for(template_name, career)
    local by_career = _RELOAD_CONTRACTS[template_name]
    if not by_career or type(career) ~= "string" then return nil end
    for prefix, contract in pairs(by_career) do
        if career:sub(1, #prefix) == prefix then return contract end
    end
    return nil
end

-- Mirrors generic_ammo_user_extension.lua:298-312 before the vanilla call
-- consumes reloaded_from_zero_ammo / _override_reload_anim.
local function _selected_reload_event(ammo)
    local event = ammo and ammo._reload_event
    if not ammo then return event end
    local missing = (tonumber(ammo._ammo_per_clip) or 0) - (tonumber(ammo._current_ammo) or 0)
    if ammo.reloaded_from_zero_ammo then
        if ammo._no_ammo_reload_event then
            event = ammo._no_ammo_reload_event
        end
    elseif missing == 1 or ammo._available_ammo == 1 then
        event = ammo._last_reload_event
    end
    return ammo._override_reload_anim or event
end

local _diag_counts = {}
local function _diag_bounded(kind, fmt, ...)
    local count = (_diag_counts[kind] or 0) + 1
    _diag_counts[kind] = count
    -- First four transitions establish the path; thereafter one in 25 keeps a
    -- long session observable without turning a reload loop into log spam.
    if count <= 4 or count % 25 == 0 then
        local ok, message = pcall(string.format, fmt, ...)
        pcall(printf, "[wt:536:reload] %s count=%d",
            ok and message or ("diagnostic_format_error=" .. tostring(fmt)), count)
    end
end

local function _is_local_owner(unit)
    local players = Managers and Managers.player
    if not players or not unit then return false end
    local ok, player = pcall(players.local_player, players)
    return ok and player and player.player_unit == unit
end

-- Receiver-local correction helper. The existing singleton Unit.animation_event
-- hook calls this function; registering a second VMF hook would be silently
-- dropped. Returning a stance + target lets the central funnel perform both
-- engine calls without adding another registration at this hot seam.
local function _route_volley_reload(unit, event_name, state, career, is_local)
    if event_name ~= "reload" and event_name ~= "reload_last" then
        return nil
    end

    local contract = state and _contract_for(state.template, career)
    local target = contract and contract.events[event_name]
    if not target then return nil end

    local has_stance = _safe_has_anim(unit, contract.stance)
    local has_target = _safe_has_anim(unit, target)
    if not has_stance or not has_target then
        _diag_bounded("rejected",
            "rejected template=%s career=%s source=%s target=%s stance=%s has_target=%s has_stance=%s",
            tostring(state.template), tostring(career), tostring(event_name), tostring(target),
            tostring(contract.stance), tostring(has_target), tostring(has_stance))
        return nil
    end

    -- `has_animation_event` proves vocabulary only, not visible playback. Log
    -- this as a dispatched/unverified transition until an in-game observer sees
    -- the native volley reload sequence.
    _diag_bounded("dispatch",
        "dispatch_unverified template=%s career=%s source=%s stance=%s target=%s local=%s",
        tostring(state.template), tostring(career), tostring(event_name),
        tostring(contract.stance), tostring(target), tostring(is_local))
    return contract.stance, target
end

-- Restore the event vanilla deliberately omits on the originating 3P body.
-- ActiveReloadAmmoUserExtension is excluded: its source already calls
-- Unit.animation_event(owner_unit, reload_event) locally.
mod:hook("GenericAmmoUserExtension", "start_reload_animation", function(func, self, reload_time, ...)
    local event = _selected_reload_event(self)
    local owner = self and self.owner_unit
    local is_local = self and self.first_person_extension and _is_local_owner(owner)

    func(self, reload_time, ...)

    if is_local and event and Unit.alive(owner) then
        _diag_bounded("local_replay",
            "local_3p_replay_dispatched event=%s item=%s template=%s",
            tostring(event), tostring(self.item_name),
            tostring(_unit_state[owner] and _unit_state[owner].template))
        Unit.animation_event(owner, event)
    elseif is_local then
        _diag_bounded("missing",
            "local_3p_replay_missing event=%s owner_alive=%s item=%s",
            tostring(event), tostring(owner and Unit.alive(owner)), tostring(self and self.item_name))
    end
end)

local _rt_register = WT.rt_register
if _rt_register then
    _rt_register("reload_3p_volley_contract_is_receiver_native", function()
        local saltz = _contract_for("repeating_crossbow_elf_template", "wh_captain")
        if not saltz then return "Saltzpyre elf-volley reload contract missing" end
        if saltz.stance ~= "to_repeating_crossbow" then
            return "elf volley reload stance = " .. tostring(saltz.stance)
        end
        if saltz.events.reload ~= "reload" or saltz.events.reload_last ~= "reload_last" then
            return "volley reload event vocabulary drifted"
        end
        if _contract_for("repeating_crossbow_elf_template", "we_shade") then
            return "native Kerillian incorrectly receives Saltzpyre reload contract"
        end
        if _contract_for("repeating_crossbow_template_1", "wh_captain") then
            return "native Saltzpyre volley crossbow incorrectly receives port contract"
        end
    end)

    _rt_register("reload_3p_event_selection_matches_vanilla_precedence", function()
        local base = {
            _reload_event = "reload",
            _last_reload_event = "reload_last",
            _no_ammo_reload_event = "reload_zero",
            _ammo_per_clip = 15,
            _current_ammo = 10,
            _available_ammo = 20,
        }
        if _selected_reload_event(base) ~= "reload" then return "base reload event mismatch" end
        base._current_ammo = 14
        if _selected_reload_event(base) ~= "reload_last" then return "last-round event mismatch" end
        base.reloaded_from_zero_ammo = true
        if _selected_reload_event(base) ~= "reload_zero" then return "zero-ammo event precedence mismatch" end
        base._no_ammo_reload_event = nil
        if _selected_reload_event(base) ~= "reload" then
            return "zero-ammo without special event must skip last-round branch"
        end
        base._override_reload_anim = "reload_override"
        if _selected_reload_event(base) ~= "reload_override" then return "override event precedence mismatch" end
    end)
end

WT.reload_3p_contract_for = _contract_for
WT.reload_3p_selected_event = _selected_reload_event
WT.reload_3p_route = _route_volley_reload

return {
    contract_for = _contract_for,
    selected_reload_event = _selected_reload_event,
    route_volley_reload = _route_volley_reload,
}
