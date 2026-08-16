-- _gt_dupc_policy.lua - pure host-authority decision core for Allow Duplicate
-- Careers (issue #1150). Engine-free so the host-ON/client-OFF and
-- host-OFF/client-ON directions can be pinned offline under the vendored
-- Lua 5.1 test host.
--
-- Owned by: _gt_duplicate_careers_parity.lua. Consumed via: mod:dofile there
-- and dofile from qa/lua/tests/test_gt_dupc_policy.lua.
--
-- The mechanics being modeled (all verified against decompiled source):
--   * try_reserve_profile_for_peer / ProfileRequester._request_profile run on
--     the HOST only (profile_synchronizer.lua:457 fasserts is_server;
--     profile_requester.lua:53-57 routes clients through rpc_request_profile),
--     so the host's OWN setting is the authoritative reservation gate.
--   * get_profile_index_reservation (via GameMechanismManager.
--     profile_available_for_peer, character_selection_state_character.lua:350)
--     and the static is_free_in_lobby (popup_profile_picker.lua:430,
--     matchmaking_manager.lua:1561, lobby browser) also run on CLIENT
--     machines, where the LOCAL setting is the wrong authority - that is the
--     #1150 bug. A client must follow the HOST's advertised state instead.
--   * When the host's state is unknown (vanilla host, no gt, flag not yet
--     published), FAIL CLOSED to vanilla: the gate is not relaxed.

local Policy = {}

-- Steam lobby-data key the host publishes its setting under. gtw_ prefix keeps
-- it out of the legacy ltw_ manifest namespace read by other mods.
Policy.LOBBY_KEY = "gtw_dupc"

function Policy.serialize(enabled)
    return enabled and "1" or "0"
end

-- Parse an advertised lobby-data value: true (host allows duplicates), false
-- (host explicitly disallows), nil (unknown - absent key or garbage).
function Policy.parse(value)
    if value == "1" then return true end
    if value == "0" then return false end
    return nil
end

-- Session-scoped gate for call sites with no lobby_data argument
-- (get_profile_index_reservation, try_reserve_profile_for_peer).
--   is_server        - this machine hosts the session
--   local_setting_on - this machine's allow_duplicate_careers value
--   host_advertised  - raw gtw_dupc value read from the session lobby (client)
-- Returns true when the duplicate-careers relaxation should apply.
function Policy.effective_session(is_server, local_setting_on, host_advertised)
    if is_server then
        return local_setting_on == true
    end
    -- Client: ONLY the host's advertised state may relax the gate; the local
    -- toggle is irrelevant, and unknown fails closed to vanilla.
    return Policy.parse(host_advertised) == true
end

-- Lobby-scoped gate for is_free_in_lobby: the evaluated lobby's own advertised
-- flag wins when known (the lobby browser and join-time checks evaluate OTHER
-- hosts' lobbies); otherwise fall back to session semantics - the id-less
-- makeshift table popup_profile_picker builds belongs to the joining session.
function Policy.effective_for_lobby(lobby_advertised, is_server, local_setting_on, session_host_advertised)
    local per_lobby = Policy.parse(lobby_advertised)
    if per_lobby ~= nil then
        return per_lobby
    end
    return Policy.effective_session(is_server, local_setting_on, session_host_advertised)
end

return Policy
