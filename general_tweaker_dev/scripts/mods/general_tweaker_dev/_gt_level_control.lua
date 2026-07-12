local mod = get_mod("gt_dev")

-- _gt_level_control.lua — host/level control + reservation-side fixes.
--
-- Co-locates every gt feature that lives between "Level Control" and "AI Toggle"
-- in the original main chunk, so the ProfileSynchronizer singleton audit is
-- LOCAL to this one file. All five hooks below are singletons AND target
-- distinct methods (whole-mod grep before extraction confirmed no collision
-- with each other, with main, or with _gt_lobby_slot_reservations.lua):
--
--   * ProfileSynchronizer.get_persistent_profile_index_reservation  (score-screen fix)
--   * StateInGameRunning._award_end_of_level_rewards                (score-screen fix)
--   * ProfileSynchronizer.get_profile_index_reservation            (Duplicate Careers)
--   * ProfileSynchronizer.try_reserve_profile_for_peer             (Duplicate Careers)
--   * ProfileSynchronizer.is_free_in_lobby                         (Duplicate Careers)
--
-- The four ProfileSynchronizer methods are DISJOINT (get_persistent_profile_
-- index_reservation vs get_profile_index_reservation / try_reserve_profile_
-- for_peer / is_free_in_lobby), so co-locating them here does not create a
-- (Class, method) duplicate. NOTE: the gt LOBBY slot-reservations feature does
-- NOT hook ProfileSynchronizer at all (verified), so there's no cross-module
-- collision with the score-screen fallback either.
--
-- Features bundled:
--   (1) Level Control (win / fail / restart) — host-exec + client->host RPC
--       gt_level_control. Exposes mod.gt_win_level / gt_fail_level /
--       gt_restart_level (VMF keybinds + chat commands resolve them).
--   (2) End-of-level profile fallback + score-screen fix — the two singleton
--       hooks listed above.
--   (3) gt_kill_bots / gt_die — host/self commands (mod. fields).
--   (4) /respawn — client->host RPC gt_respawn_request (mod.gt_respawn).
--   (5) gt_fix_sound — vortex-SFX clear (mod.gt_fix_sound).
--   (6) gt_bot_toggle — level no_bots_allowed flip (mod.gt_bot_toggle).
--   (7) Duplicate Careers — the three Duplicate-Careers ProfileSynchronizer hooks.
--
-- DISPATCH WIRING (no behavior change after extraction):
--   * Every callable a VMF keybind binds (gt_win_level / gt_fail_level /
--     gt_restart_level / gt_kill_bots / gt_die / gt_fix_sound / gt_bot_toggle)
--     stays a PUBLIC `mod.` field so function_name resolution works at invoke
--     time. allow_duplicate_careers is read directly inside the hooks (no
--     apply-fn / dispatch), so nothing in on_setting_changed needs to change.
--   * No file-locals are shared with the main chunk — the whole block was self-
--     contained (its own _GT_LEVEL_RPC / _GT_RESPAWN_RPC / helper locals).
--
-- Module dofile's AFTER the main chunk, so the ProfileSynchronizer /
-- StateInGameRunning global classes are resolvable at load time (the
-- get_persistent hook is already rawget-guarded as in the original).
--
-- Extracted from general_tweaker_dev.lua (Phase 3 refactor, no behavior change).

-- ============================================================
-- Level Control (win / fail / restart / kill_bots / die / fix_sound)
-- ============================================================
-- All five commands also have keybind widgets in the Level Control settings
-- group; VMF's `keybind_type = "function_call"` resolves the bound function via
-- the function_name string against the mod table, so every callable must live
-- on `mod.` (not just a local). The keep-guards mirror Janoti's Hacks mod:
-- complete/fail/restart all no-op in the inn with a friendly echo, so a
-- mis-press while sorting loadout doesn't accidentally yank you out of the
-- keep state machine.

-- HOST-ONLY GATE (v0.2.89-dev): complete_level / fail_level / retry_level are
-- server-authoritative. Only the host runs GameModeManager.server_update ->
-- evaluate_end_conditions, which is what actually consumes the level-end flag
-- (state_ingame.lua:982-983); a CLIENT calling these sets a flag nothing reads
-- AND fires trigger_end_level_area_events flow events out of band with the host,
-- driving a client-side level-flow desync that surfaces as a crash. The engine's
-- own flow_callback_complete_level guards identically (`if Managers.player
-- .is_server`). Mirrors the host idiom already used by mod.gt_kill_bots.
-- Level control is host-authoritative (GameModeManager:complete/fail/retry_level
-- assert is_server). v0.2.99-dev: make these CLIENT-USABLE — a client REQUESTS
-- the action and the host performs it, mirroring the gt_respawn client->host RPC
-- (handy for co-op testing where a non-host wants to force-win/fail/restart).
-- Any peer can trigger it (no extra permission gate) -- fine for a friends test;
-- a host opt-out toggle can be added later if grief is a concern.
local _GT_LEVEL_RPC = "gt_level_control"

local _GT_LEVEL_VERBS = {
    complete = { fn = "complete_level", label = "force-completing" },
    fail     = { fn = "fail_level",     label = "force-failing" },
    restart  = { fn = "retry_level",    label = "restarting" },
}

-- Host-side executor. Serves BOTH the host's own command and a client's RPC.
local function _gt_host_exec_level_control(verb)
    local pm = Managers.player
    if not (pm and pm.is_server) then return false, "must run on host" end
    local v = _GT_LEVEL_VERBS[verb]
    if not v then return false, "unknown level verb: " .. tostring(verb) end
    local gm = Managers.state and Managers.state.game_mode
    if not gm or type(gm[v.fn]) ~= "function" then return false, "no active game mode" end
    mod:info("[gt:level-control] %s -> GameModeManager:%s() (host)", tostring(verb), v.fn)
    gm[v.fn](gm)
    return true, v.label .. " the level"
end

-- Command body: host runs it directly; a client re-handshakes VMF (the host can
-- drop out of _vmf_users on mission-load bot churn, VMF_RECIPES 3a) then sends
-- the verb to the RESOLVED host peer -- the literal "server" recipient does NOT
-- work (VMF_RECIPES §10). Same shape as gt_respawn.
local function _gt_request_level_control(verb)
    if DamageUtils and DamageUtils.is_in_inn then
        mod:echo("Can't do that in the keep.")
        return
    end
    local pm = Managers.player
    if pm and pm.is_server then
        local _, msg = _gt_host_exec_level_control(verb)
        mod:echo("[gt] level: " .. tostring(msg) .. " (host).")
    else
        local vmf = get_mod("VMF")
        if vmf and vmf.ping_vmf_users then pcall(vmf.ping_vmf_users) end
        local host = Managers.mechanism and Managers.mechanism.server_peer_id and Managers.mechanism:server_peer_id()
        if host then
            pcall(function() mod:network_send(_GT_LEVEL_RPC, host, verb) end)
            mod:echo("[gt] " .. tostring(verb) .. " requested from host (run it again if nothing happens -- the host link may have just re-synced).")
        else
            mod:echo("[gt] couldn't resolve the host peer.")
        end
    end
end

mod.gt_win_level     = function() _gt_request_level_control("complete") end
mod.gt_fail_level    = function() _gt_request_level_control("fail")     end
mod.gt_restart_level = function() _gt_request_level_control("restart")  end

-- Host receives a client's level-control request and performs it for the lobby.
mod:network_register(_GT_LEVEL_RPC, function(sender_peer_id, verb)
    local pm = Managers.player
    if not (pm and pm.is_server) then return end
    local ok, msg = _gt_host_exec_level_control(tostring(verb))
    mod:info("[gt:level-control-rpc] from=%s verb=%s ok=%s (%s)", tostring(sender_peer_id), tostring(verb), tostring(ok), tostring(msg))
end)

-- ============================================================
-- End-of-level profile fallback + score-screen fix (v0.2.103-dev)
-- ============================================================
-- After a host force-wins via /win, a CLIENT's persistent profile reservation
-- races to nil/0 for its OWN peer (observed 2026-06-18, danjo as client on
-- ground_zero/cataclysm). Vanilla reads that reservation in MULTIPLE end-of-level
-- places, ALL of which break when it's nil:
--   * StateInGameRunning._award_end_of_level_rewards (state_ingame_running.lua:768)
--     -> profile = SPProfiles[nil] -> hero_name = profile.display_name CRASHES
--     (or, if skipped, starves the results-view gate so no score screen builds).
--   * StateInGameRunning._setup_end_of_level_UI (state_ingame_running.lua:266-280)
--     -> hero_name stays nil -> level_end_view_context.local_player_hero_name = nil
--     -> EndViewStateSummary._hero_name = nil -> ExperienceSettings.get_experience(nil)
--     -> BackendInterfaceHeroAttributes.get -> `nil .. "_experience"` CRASHES. This
--     is the f32490ac crash -- it fired INSIDE the score screen the earlier fix
--     enabled, because the temporary shim was already restored by the time
--     _setup_end_of_level_UI ran.
--
-- v0.2.89 skipped the reward (no crash, no score screen). v0.2.101 ran the reward
-- with a TEMPORARY reservation shim (score screen built, but the shim was gone
-- before _setup_end_of_level_UI's read -> f32490ac crash). v0.2.103 fixes it at the
-- SOURCE: a permanent fallback on get_persistent_profile_index_reservation that,
-- when the reservation is stale for OUR peer, returns the local player's REAL
-- profile (which survives the race). EVERY consumer (reward + score screen +
-- experience) then resolves a real hero. Healthy reservations pass through
-- untouched; the override only fires when the reservation is nil/0 AND we have a
-- valid local profile, so it's semantically correct and client-local (no host
-- desync). Pre-flight: no other gt hook targets
-- ProfileSynchronizer.get_persistent_profile_index_reservation (the lobby feature
-- hooks the DIFFERENT get_profile_index_reservation / try_reserve_profile_for_peer)
-- nor StateInGameRunning._award_end_of_level_rewards.
local function _gt_local_profile_index()
    local lp = Managers and Managers.player and Managers.player:local_player()
    if not lp then return nil end
    local ok, idx, career = pcall(function()
        local i = lp.profile_index and lp:profile_index()
        local c = lp.career_index and lp:career_index()
        return i, c
    end)
    if ok and idx and rawget(SPProfiles, idx) then return idx, career end
    return nil
end

if rawget(_G, "ProfileSynchronizer") then
    mod:hook("ProfileSynchronizer", "get_persistent_profile_index_reservation", function(func, self, peer_id)
        local idx, career = func(self, peer_id)
        if idx and idx ~= 0 and rawget(SPProfiles, idx) then
            return idx, career   -- healthy reservation: untouched
        end
        -- Stale ONLY for our own peer -> fall back to the local player's real
        -- profile so every end-of-level consumer resolves a real hero.
        local my_peer = Network and Network.peer_id and Network.peer_id()
        if peer_id == my_peer then
            local fb, fb_career = _gt_local_profile_index()
            if fb then return fb, fb_career or career end
        end
        return idx, career
    end)
end

-- Last-resort net: with the fallback above, vanilla resolves a real profile and
-- completes (no nil crash; the score screen + experience lookups build). This only
-- catches the genuinely-unresolvable case (no local player) -- skip rather than crash.
mod:hook("StateInGameRunning", "_award_end_of_level_rewards", function(func, self, ...)
    local ok, err = pcall(func, self, ...)
    if not ok then
        mod:warning("[gt] _award_end_of_level_rewards errored (profile unresolvable): %s", tostring(err))
    end
end)

-- Mirrors Hacks's EAC-secure guard: only allowed pre-round on official servers,
-- unrestricted on untrusted (modded) realm. Vanilla bot_status_extension.set_dead
-- handles the actual cleanup; we just iterate Managers.player:bots().
mod.gt_kill_bots = function()
    if EAC and EAC.state and EAC.state() ~= "untrusted" then
        local gm = Managers.state and Managers.state.game_mode
        if gm and gm.is_round_started and gm:is_round_started() then
            mod:echo("Bots may only be killed at the start of the map on official realm.")
            return
        end
    end
    local bots = Managers.player and Managers.player:bots() or {}
    local killed = 0
    for _, bot in ipairs(bots) do
        local unit = bot.player_unit
        if unit and Unit.alive(unit) then
            local status_ext = ScriptUnit.has_extension(unit, "status_system")
            if status_ext and not status_ext:is_ready_for_assisted_respawn() then
                status_ext:set_dead(true)
                killed = killed + 1
            end
        end
    end
    mod:echo(string.format("Killed %d bot(s).", killed))
end

-- Force every bot into the knocked-down (bleedout) state -- the in-game repro
-- harness for issue 448 (downed bots must not grant Morr's Protection). The user
-- asked for a way to "down all bots" so the soft-lock fix (_gt_bot_fixes.lua
-- FIX 11) can actually be verified: get two boon-carrying bots downed within 10m
-- and watch whether they bleed out (fix ON) or stay permanently invulnerable
-- (bug). knock_down is server-authoritative (player_unit_health_extension.lua:224
-- asserts is_server) and bots are host-only, so this is host-only.
--
-- We set the health extension's `set_knocked_down` FIELD (a plain boolean, not a
-- method -- the same field vanilla sets at spawn for health_state=="knocked_down",
-- player_unit_health_extension.lua:126-127) rather than dealing raw 10000 damage.
-- The extension's own server update consumes it next tick and calls
-- self:knock_down(unit) (player_unit_health_extension.lua:291-295) -- the exact
-- path lethal damage takes when it downs a live player (:298-301). Advantages over
-- raw damage: wounds-independent (a 10000-damage hit would OUTRIGHT KILL a bot on
-- its final wound, or vary by difficulty/wounds), yet still drives the full
-- network-synced knockdown AND the knockdown_bleed DoT (buff_function_templates
-- .lua:354) that Morr's invulnerable perk blocks -- so the 448 repro is faithful.
-- Skips bots already down / awaiting rescue / dead (idempotent).
mod.gt_down_bots = function()
    local pm = Managers.player
    if not (pm and pm.is_server) then
        mod:echo("Down bots must run on the host (bots are host-side).")
        return
    end
    if DamageUtils and DamageUtils.is_in_inn then
        mod:echo("Can't down bots in the keep.")
        return
    end
    local bots = pm:bots() or {}
    local downed = 0
    for _, bot in ipairs(bots) do
        local unit = bot.player_unit
        if unit and Unit.alive(unit) then
            local status_ext = ScriptUnit.has_extension(unit, "status_system")
            local health_ext = ScriptUnit.has_extension(unit, "health_system")
            if status_ext and health_ext
               and not status_ext:is_knocked_down()
               and not status_ext:is_ready_for_assisted_respawn()
               and not status_ext:is_dead() then
                health_ext.set_knocked_down = true
                downed = downed + 1
            end
        end
    end
    mod:echo(string.format("Downing %d bot(s) into bleedout.", downed))
end

mod.gt_die = function()
    if DamageUtils and DamageUtils.is_in_inn then
        mod:echo("Can't die in the keep.")
        return
    end
    local local_player = Managers.player and Managers.player:local_player()
    local unit = local_player and local_player.player_unit
    if not (unit and Unit.alive(unit)) then
        mod:echo("No local player unit.")
        return
    end
    local death_system = Managers.state.entity:system("death_system")
    death_system:kill_unit(unit, {})
end

-- ============================================================
-- /respawn — force yourself back in when dead or awaiting rescue (v0.2.94-dev)
-- ============================================================
-- Respawn is server-authoritative, so the HOST performs it (directly for its own
-- player; via RPC for a client's request). Two cases:
--   * Awaiting rescue (hanging at a beacon; is_ready_for_assisted_respawn) ->
--     StatusUtils.set_respawned_network(unit, true, helper) (status_utils.lua:58,
--     asserts is_server) -- the same call the assisted_respawn interaction makes.
--   * Dead / in the respawn queue (party game_mode_data.health_state == "dead")
--     -> zero this player's respawn_timer; the host's RespawnHandler.server_update
--     (respawn_handler.lua:333) then spawns them. Per-player (unlike
--     game_mode:force_respawn_dead_players(), which respawns the whole team).
local _GT_RESPAWN_RPC = "gt_respawn_request"

-- Host-side respawn primitive. peer_id + local_player_id identify the target, so
-- it serves both the local host player and a client's RPC. Returns ok, message.
local function _gt_host_respawn(peer_id, local_player_id)
    local pm = Managers.player
    if not (pm and pm.is_server) then return false, "must run on host" end
    local target
    for _, p in pairs(pm:players()) do
        -- Match BOTH peer_id AND local_player_id. On a host/solo game the host peer
        -- OWNS the human player (local_player_id 1) AND every bot (lpid 2-4) under the
        -- SAME peer_id, so a peer_id-only match grabbed whichever pairs() yielded first
        -- -- often a live bot. Case A then checked the bot's (alive) unit and reported
        -- "not dead or awaiting rescue" for a player who was genuinely awaiting rescue
        -- (health_state=respawn). Case B survived only because it keys party status by
        -- (peer_id, local_player_id). (#338)
        if p and p.peer_id == peer_id then
            local p_lpid = (p.local_player_id and p:local_player_id()) or 1
            if p_lpid == local_player_id then target = p; break end
        end
    end
    if not target then return false, "player not found on host" end
    local unit = target.player_unit
    local status = unit and ScriptUnit.has_extension(unit, "status_system")
    -- Case A: awaiting rescue -> free directly (helper = self; nil-tolerant).
    if status and status.is_ready_for_assisted_respawn and status:is_ready_for_assisted_respawn() then
        if rawget(_G, "StatusUtils") and StatusUtils.set_respawned_network then
            StatusUtils.set_respawned_network(unit, true, unit)
            return true, "freed from awaiting-rescue"
        end
        return false, "set_respawned_network unavailable"
    end
    -- Case B: dead / queued -> zero this player's respawn timer.
    local pstatus = Managers.party and Managers.party:get_player_status(peer_id, local_player_id)
    local data = pstatus and pstatus.game_mode_data
    if data and (data.health_state == "dead" or data.respawn_timer ~= nil) then
        data.respawn_timer = 0
        return true, "respawn timer cleared -- spawning shortly"
    end
    return false, "you're not dead or awaiting rescue"
end

mod.gt_respawn = function()
    if DamageUtils and DamageUtils.is_in_inn then
        mod:echo("Can't respawn in the keep.")
        return
    end
    local pm = Managers.player
    local player = pm and pm:local_player()
    if not player then mod:echo("No local player."); return end
    local peer_id = Network and Network.peer_id and Network.peer_id()
    local lpid = (player.local_player_id and player:local_player_id()) or 1
    if pm.is_server then
        local _, msg = _gt_host_respawn(peer_id, lpid)
        mod:echo("[gt] respawn: " .. tostring(msg))
    else
        -- client -> host: re-handshake first (VMF drops the host from _vmf_users
        -- on mission-load bot churn, VMF_RECIPES 3a), then send to the resolved
        -- host peer ("server" recipient string does not work -- use the literal).
        local vmf = get_mod("VMF")
        if vmf and vmf.ping_vmf_users then pcall(vmf.ping_vmf_users) end
        local host = Managers.mechanism and Managers.mechanism.server_peer_id and Managers.mechanism:server_peer_id()
        if host then
            pcall(function() mod:network_send(_GT_RESPAWN_RPC, host, lpid) end)
            mod:echo("[gt] respawn requested from host (run it again if nothing happens -- the host link may have just re-synced).")
        else
            mod:echo("[gt] couldn't resolve the host peer.")
        end
    end
end

-- Host receives a client's respawn request and performs it for that peer.
mod:network_register(_GT_RESPAWN_RPC, function(sender_peer_id, lpid)
    local pm = Managers.player
    if not (pm and pm.is_server) then return end
    local ok, msg = _gt_host_respawn(sender_peer_id, tonumber(lpid) or 1)
    mod:info("[gt:respawn-rpc] from=%s lpid=%s ok=%s (%s)", tostring(sender_peer_id), tostring(lpid), tostring(ok), tostring(msg))
end)

-- Restart-in-storm leaves a vortex SFX looping; canonical fix is to fire the
-- "false" event for the same sound which un-mutes/clears the wwise state.
mod.gt_fix_sound = function()
    local gm = Managers.state and Managers.state.game_mode
    local level_key = gm and gm._level_key
    if level_key and string.find(level_key, "inn_level") then
        mod:echo("Can't fix sound in the keep — must be in a mission.")
        return
    end
    local local_player = Managers.player and Managers.player:local_player()
    local unit = local_player and local_player.player_unit
    if not (unit and Unit.alive(unit)) then
        mod:echo("No local player unit.")
        return
    end
    local fp_ext = ScriptUnit.has_extension(unit, "first_person_system")
    if fp_ext and fp_ext.play_hud_sound_event then
        fp_ext:play_hud_sound_event("sfx_player_in_vortex_false")
        mod:echo("Vortex sound stopped.")
    end
end

-- Names are gt-prefixed to avoid colliding with Janoti's "Hacks" mod which
-- also registers `win` / `fail` / `restart` / `kill_bots` / `die` (and others
-- below). VMF only allows one registration per global slot; whichever mod
-- loads first wins it and the other's registration is silently dropped, so
-- coexistence requires unique names.
mod:command("win",       "Complete the current map",           function() mod.gt_win_level()     end)
mod:command("fail",      "Fail the current map",               function() mod.gt_fail_level()    end)
mod:command("restart",   "Restart the current map",            function() mod.gt_restart_level() end)
mod:command("killbots",  "Kill all bots (pre-round on EAC-secure realm only)", function() mod.gt_kill_bots() end)
mod:command("downbots",  "Force all bots into bleedout (issue 448 Morr's test)", function() mod.gt_down_bots() end)
mod:command("die",       "Kill your character",                function() mod.gt_die()           end)
mod:command("respawn",   "Force yourself back in when dead or awaiting rescue", function() mod.gt_respawn() end)
mod:command("fix_sound",    "Stop the looping vortex SFX bug (post-restart in a storm)", function() mod.gt_fix_sound() end)

-- Flip no_bots_allowed on the current level. Lets bots spawn in the keep
-- (or removes them mid-mission). Original Helpers documented "Inn bots can
-- lead to a rare nav crash" — flag preserved in the chat echo.
mod.gt_bot_toggle = function()
    if not LevelHelper then
        mod:echo("LevelHelper not available.")
        return
    end
    local level_settings = LevelHelper:current_level_settings()
    if not level_settings then
        mod:echo("No current level settings (load a map first).")
        return
    end
    level_settings.no_bots_allowed = not level_settings.no_bots_allowed
    mod:echo(level_settings.no_bots_allowed
        and "Bots disabled on this level."
        or  "Bots allowed on this level. NOTE: Inn bots can trigger a rare nav crash.")
end

mod:command("bottoggle", "Toggle bots on/off for current level (lets you spawn bots in the keep)", function()
    mod.gt_bot_toggle()
end)

-- ============================================================
-- Duplicate Careers
-- ============================================================

mod:hook("ProfileSynchronizer", "get_profile_index_reservation", function(func, self, party_id, profile_index)
    if mod:get("allow_duplicate_careers") then return nil, nil end
    return func(self, party_id, profile_index)
end)

mod:hook("ProfileSynchronizer", "try_reserve_profile_for_peer", function(func, self, party_id, peer_id, profile_index, career_index)
    local result = func(self, party_id, peer_id, profile_index, career_index)
    if result then return true end
    if mod:get("allow_duplicate_careers") then return true end
    return false
end)

-- CLARIFY: `is_free_in_lobby` is a STATIC function (no `self` arg — see
-- profile_synchronizer.lua:860). Hook signature intentionally omits self.
mod:hook("ProfileSynchronizer", "is_free_in_lobby", function(func, profile_index, lobby_data, optional_party_id)
    if mod:get("allow_duplicate_careers") then return true end
    return func(profile_index, lobby_data, optional_party_id)
end)
