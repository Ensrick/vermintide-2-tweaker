local mod = get_mod("gut_dev")

-- _gut_career_swap.lua -- EXPERIMENTAL diagnostic: real mid-mission CAREER SWAP test.
--
-- FEASIBILITY STEP for #173 (real mid-mission career swap), NOT the final UI. Adds a
-- single chat command `/gut_swap_career <n>` that asks the game to swap the LOCAL
-- player's CURRENT hero to career index n (1-4) while in a live mission, via the
-- vanilla ProfileRequester with force_respawn = true. Heavily logged with engine
-- `printf` (tag [gut:career]) because the user runs mod-logging OFF -- the whole point
-- is to farm ground truth on WHERE this succeeds or fails mid-mission.
--
-- ============================================================================
-- WHY THIS IS SAFE TO CALL DIRECTLY (no CharacterSelectionView)
-- ============================================================================
-- The mid-mission CRASH the sibling _gut_mission_hero_select.lua avoids is
-- CharacterSelectionView's keep-only preview WORLD + level-world/UI mount, NOT the
-- profile-request call itself. Vanilla changes career through
-- ProfileRequester:request_profile(peer_id, local_player_id, profile_name,
-- career_name, force_respawn) -- fully HOST-MEDIATED:
--   * server -> ProfileRequester:_request_profile(...) directly.
--   * client -> network_transmit:send_rpc_server("rpc_request_profile", ...).
-- (profile_requester.lua:46-58). The host can DECLINE or lock (matchmaking checks
-- hero_is_locked / profile_available_for_peer), so a swap may simply be refused --
-- that's expected, not an error.
--
-- CAVEAT the user is testing FOR: force_respawn = true despawns + respawns the live
-- unit at the LEVEL START spawn (GameModeAdventure.force_respawn), with fresh
-- health/ammo. That teleport is exactly why gut normally keeps career-PICK to the
-- keep. This command exists to observe whether the swap+respawn actually lands
-- mid-mission and how bad the teleport/desync is.
--
-- ============================================================================
-- HOW WE REACH THE PROFILE REQUESTER MID-MISSION (source-verified)
-- ============================================================================
-- The vanilla VIEWS get it via `network_handler:profile_requester()` where
-- network_handler is the ingame network context. The engine-agnostic accessor that
-- works from anywhere in a live mission is ImguiCareerDebug._get_profile_requester
-- (imgui_career_debug.lua:28-42), which we mirror exactly:
--     local nm = Managers.state.network
--     local network = nm.network_server or nm.network_client   -- host vs client
--     local requester = network:profile_requester()
-- (NetworkServer/NetworkClient.profile_requester both just return
-- self._profile_requester -- network_server.lua:323, network_client.lua:296.)
--
-- peer_id: the local player's own peer. player:network_id() returns self.peer_id
-- (BulldozerPlayer.network_id, bulldozer_player.lua:451). Vanilla _change_profile
-- uses local_player_id = 1 (character_selection_state_character.lua:1604), so we do
-- the same. imgui uses player.peer_id + player:local_player_id() -- identical for the
-- single local human. We fall back to Network.peer_id() if network_id() is nil.
--
-- HOOK PRE-FLIGHT: this module registers NO hooks (command only). Nothing to collide
-- with. Everything is pcall-guarded; a failure logs via printf + a plain mod:echo and
-- never hard-crashes.
--
-- Module dofile's from gui_tweaker_dev.lua next to the other feature dofiles.

-- ------------------------------------------------------------------
-- printf helper (survives mod-logging-off; tag [gut:career])
-- ------------------------------------------------------------------
local function _pf(fmt, ...)
    local p = rawget(_G, "printf")
    if not p then
        return
    end
    local n = select("#", ...)
    if n > 0 then
        local ok, s = pcall(string.format, fmt, ...)
        p("[gut:career] " .. (ok and s or tostring(fmt)))
    else
        p("[gut:career] " .. tostring(fmt))
    end
end

-- ------------------------------------------------------------------
-- Resolve the ProfileRequester the same way vanilla reaches it mid-mission
-- (ImguiCareerDebug._get_profile_requester). Returns requester, path_string.
-- ------------------------------------------------------------------
local function _get_profile_requester()
    local nm = Managers.state and Managers.state.network
    if not nm then
        _pf("no Managers.state.network (not in a live mission?)")
        return nil, "no_network_manager"
    end
    local is_server = nm.network_server ~= nil
    local network = nm.network_server or nm.network_client
    if not network then
        _pf("Managers.state.network has neither network_server nor network_client")
        return nil, "no_network"
    end
    local ok, requester = pcall(function()
        return network:profile_requester()
    end)
    if not ok then
        _pf("network:profile_requester() threw: %s", tostring(requester))
        return nil, "requester_threw"
    end
    if not requester then
        _pf("network:profile_requester() returned nil (path=%s)", is_server and "server" or "client")
        return nil, "requester_nil"
    end
    _pf("got requester=%s (path=%s)", tostring(requester), is_server and "server" or "client")
    return requester, (is_server and "server" or "client")
end

-- ------------------------------------------------------------------
-- /gut_swap_career <n>
-- ------------------------------------------------------------------
mod:command(
    "gut_swap_career",
    "EXPERIMENTAL/diagnostic: swap your current hero to career index N (1-4) mid-mission via ProfileRequester (force_respawn). Heavy [gut:career] logging; may refuse or respawn you at level start.",
    function(arg)
        local ok, err = pcall(function()
            _pf("=== /gut_swap_career %s START ===", tostring(arg))

            -- Validate arg
            local n = tonumber(arg)
            if not n or n < 1 or n > 4 or n ~= math.floor(n) then
                _pf("bad arg %s (need integer 1-4)", tostring(arg))
                mod:echo("Usage: /gut_swap_career <n>  (career index 1 to 4)")
                return
            end

            -- Step 1: local player + current profile / hero
            local player = Managers.player and Managers.player:local_player()
            if not player then
                _pf("no local player (Managers.player:local_player() nil -- not in game?)")
                mod:echo("No local player found. Are you in a mission?")
                return
            end
            local profile_index = player:profile_index()
            if not profile_index then
                _pf("player:profile_index() nil")
                mod:echo("Could not read your hero profile.")
                return
            end
            local profile = SPProfiles and SPProfiles[profile_index]
            if not profile then
                _pf("SPProfiles[%s] nil", tostring(profile_index))
                mod:echo("Could not resolve your hero profile.")
                return
            end
            local hero_name = profile.display_name
            local careers = profile.careers
            if not hero_name or not careers then
                _pf("profile missing display_name (%s) or careers (%s)", tostring(hero_name), tostring(careers))
                mod:echo("Your hero profile is incomplete; cannot swap.")
                return
            end
            local current_career_index = player:career_index()
            _pf("local player: hero=%s profile_index=%s current_career_index=%s num_careers=%d",
                tostring(hero_name), tostring(profile_index), tostring(current_career_index), #careers)

            -- Step 2: validate n against this hero's careers + resolve target career name
            if n > #careers then
                _pf("career index %d out of range (hero %s has %d careers)", n, tostring(hero_name), #careers)
                mod:echo(string.format("Career %d is out of range. %s has %d careers.", n, tostring(hero_name), #careers))
                return
            end
            local target_career = careers[n]
            local career_name = target_career and target_career.display_name
            if not career_name then
                _pf("careers[%d].display_name nil", n)
                mod:echo("Could not resolve the target career name.")
                return
            end
            _pf("target: career_index=%d career_name=%s (current career_index=%s)",
                n, tostring(career_name), tostring(current_career_index))
            if current_career_index == n then
                _pf("target career == current career; sending request anyway (diagnostic)")
            end

            -- Step 3: profile requester (mid-mission accessor)
            local requester, path = _get_profile_requester()
            if not requester then
                mod:echo("Could not reach the profile requester; swap not attempted. Check the log.")
                return
            end

            -- Step 4: peer + local_player_id (vanilla _change_profile uses local_player_id = 1)
            local peer_id = player:network_id()
            if not peer_id and Network and Network.peer_id then
                peer_id = Network.peer_id()
            end
            local local_player_id = 1
            _pf("peer_id=%s local_player_id=%d (player:local_player_id()=%s) path=%s",
                tostring(peer_id), local_player_id, tostring(player.local_player_id and player:local_player_id()), tostring(path))

            -- Step 5: fire request_profile (same hero, new career, force_respawn = true)
            _pf("CALLING requester:request_profile(peer=%s, lpid=%d, hero=%s, career=%s, force_respawn=true)",
                tostring(peer_id), local_player_id, tostring(hero_name), tostring(career_name))
            local rok, rerr = pcall(function()
                requester:request_profile(peer_id, local_player_id, hero_name, career_name, true)
            end)
            if not rok then
                _pf("request_profile THREW: %s", tostring(rerr))
                mod:echo("Career swap request errored. Check the log.")
                return
            end
            _pf("request_profile returned OK (host mediates; may decline; watch for respawn)")

            -- Step 6: user status
            mod:echo(string.format("Requested career swap to %s; if it works you should respawn as that career.", tostring(career_name)))
            _pf("=== /gut_swap_career %d DONE ===", n)
        end)

        if not ok then
            _pf("command handler crashed: %s", tostring(err))
            mod:echo("Career swap command failed. Check the log.")
        end
    end
)

return true
