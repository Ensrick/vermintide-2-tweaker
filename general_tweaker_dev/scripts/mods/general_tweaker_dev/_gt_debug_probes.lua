local mod = get_mod("gt_dev")

-- _gt_debug_probes.lua — Debug Mode (auto-dump on key events) + observation
-- probes + the burning-enemy fire VFX probe.
--
-- Extracted from the main file in Phase 4. PURE reorganization, no behavior
-- change. All emission routes through the file-local _dbg / _dbg_alert helpers
-- (mod:debug); gate is VMF output_mode_debug. Output lands in the console_logs
-- for crash triage.
--
-- Exposes (resolved at call time by cross-file consumers):
--   mod._dbg_on / mod._dbg_log      — the gate predicate + info-channel logger,
--     called by the mission-UI _customize_item hook and the AI Takeover module's
--     debug-toggle dump wrap.
--   mod._dbg_alert                  — the echo+info logger; read by the
--     dbg_helpers_two_channel regression check (which stays in main).
--   mod._gt_dump_ai_now             — the AI/bot state dump; called by the AI
--     Takeover module's debug-toggle wrap.
--
-- Consumes (mod._gt_ai_* fields seeded in main / assigned by _gt_ai_takeover.lua,
-- resolved at call time): mod._gt_ai_saved_state, mod._gt_ai_pending_host_toggle,
-- mod._gt_ai_pending_client_send — surfaced by the AI dump.
--
-- All observation hooks are SINGLETONS — whole-mod (Class,method) grep verified
-- disjoint from the rest of gt during the Phase-4 extraction (none of the
-- HeroView / HeroWindowItemCustomization / IngameUI / LevelTransitionHandler /
-- BackendInterfaceItemPlayfab / PlayerManager(.add_remote_player/.remove_player/
-- .relinquish_unit_ownership) / CharacterStateHelper / HeroViewStateOverview
-- targets is hooked by any other gt feature; the mission-UI module hooks
-- HeroWindowLoadoutConsole / HeroWindowPanelConsole, NOT these). The two
-- mod.on_game_state_changed wraps + the mod.update wrap are observational chains
-- (they call prev() first, then add logging / a deferred dump), so they remain
-- behavior-neutral wherever in the load order they re-wrap.
--
-- mod:hook (not hook_safe) is used for the observation hooks so they chain
-- cleanly with other mods' wrappers and preserve all returns (VMF_RECIPES § 2).

-- ============================================================
-- Debug Mode (auto-dump on key events)
-- ============================================================
-- Surfaces context that's hard to reconstruct from a crash log alone:
-- mechanism, level_key, in_keep, current_view, profile/career, item
-- being customized, cim presence. Off by default. Turn on before
-- reproducing a crash (or before any session you want richly-logged),
-- then off to silence the stream.
--
-- Output goes through mod:info — lands in
-- `%APPDATA%\fatshark\Vermintide 2\console_logs\` for post-mortem
-- triage. To surface in chat too, raise gt's Logging Level in VMF's
-- per-mod settings.
--
-- The toggle gates emission only — hooks register once at mod load
-- and early-return on every call when the toggle is off, so the
-- runtime cost in the off state is one mod:get() per event.
--
-- Why mod:hook (not hook_safe) for the observation hooks: hook_safe
-- registrations on the same Class.method silently overwrite each
-- other (VMF_RECIPES § 1). mod:hook with `return func(self, ...)`
-- preserves all returns intact (VMF_RECIPES § 2) and chains cleanly
-- with other mods' wrappers on the same method.

-- v0.2.54-dev: renamed from `gt_debug_mode` to the universal
-- `enable_debug_logging` key per PROJECT_STANDARDS.md § 3.6.
-- v0.2.55-dev: shadows the top-of-file `_dbg`/`_dbg_alert` pair.
-- v0.2.142-dev: gate removed; routes through VMF logging (mod:debug).
local function _dbg(fmt, ...)
    mod:debug(fmt, ...)
end

local function _dbg_alert(fmt, ...)
    mod:debug(fmt, ...)
end

-- Exposed on `mod` so cross-file consumers resolve them at call time:
--   * _customize_item / mission-UI hooks call mod._dbg_log,
--   * the AI Takeover module's debug wrap calls mod._dbg_log,
--   * the dbg_helpers_two_channel /gt_regression_test check (which stays in the
--     main file) calls mod._dbg_log / mod._dbg_alert.
mod._dbg_log   = _dbg
mod._dbg_alert = _dbg_alert

-- v0.2.144-dev FIX: the v0.2.142-dev "gate removed" refactor (above) dropped the
-- `_dbg_on` predicate from the logger but left 5 call sites still gating the
-- heavy AI/menu DUMP triggers on `_dbg_on()` (lines ~724/744/857/863/893) -> a
-- nil-global error fired every StateIngame enter / unit relinquish (caught by
-- VMF's event pcall, but spammed errors + silently killed the dump probes).
-- The logger `_dbg`/`_dbg_log` correctly stays ungated (routes through VMF
-- mod:debug); only the expensive dump triggers need this gate. Restore it as a
-- file-local + expose on `mod` (the AI Takeover module reads mod._dbg_on).
local function _dbg_on()
    return mod:get("enable_debug_logging") == true
end
mod._dbg_on = _dbg_on

local function _ctx_str()
    -- Single-line context summary, all fields nil-safe so calls from
    -- any state (boot, title screen, loading, ingame) don't fault.
    local mech, lvl, in_keep, view, profile, career = "?", "?", false, "?", "?", "?"
    if Managers and Managers.mechanism and Managers.mechanism.current_mechanism_name then
        mech = Managers.mechanism:current_mechanism_name() or "?"
    end
    local gm = Managers and Managers.state and Managers.state.game_mode
    if gm and gm.level_key then lvl = gm:level_key() or "?" end
    if rawget(_G, "DamageUtils") and DamageUtils.is_in_inn then in_keep = true end
    if Managers and Managers.ui and Managers.ui._ingame_ui then
        view = Managers.ui._ingame_ui.current_view or "?"
    end
    -- local_player() reads self.network_manager.peer_id() and asserts
    -- "Network backend has not been set" during boot/title-screen state
    -- transitions when Managers.player exists but its network_manager
    -- upvalue is still nil (set in PlayerManager.set_is_server). Guard
    -- on the actual field, not just method presence, so on_game_state_changed
    -- doesn't ERROR ~4x per session.
    if Managers and Managers.player and Managers.player.local_player
       and Managers.player.network_manager then
        local pl = Managers.player:local_player()
        if pl then
            -- profile_index/career_index return 0 (or nil) before the
            -- profile is bound — typical for StateIngame enter on the
            -- host's own peer until the profile_synchronizer publishes.
            -- Report "?" in that case so the dump distinguishes "unbound"
            -- from a legitimate profile/career index of 0 (which doesn't
            -- exist — SPProfiles is 1-indexed).
            local pi = (pl.profile_index and pl:profile_index()) or 0
            local ci = (pl.career_index  and pl:career_index())  or 0
            local sp_profile = (pi > 0) and rawget(_G, "SPProfiles") and SPProfiles[pi]
            profile = (sp_profile and sp_profile.display_name) or (pi > 0 and tostring(pi)) or "?"
            local sp_career  = sp_profile and sp_profile.careers and sp_profile.careers[ci]
            career  = (sp_career and sp_career.name) or (ci > 0 and tostring(ci)) or "?"
        end
    else
        profile = "<pre-backend>"
        career  = "<pre-backend>"
    end
    return string.format("mech=%s level=%s in_keep=%s view=%s profile=%s career=%s",
        mech, lvl, tostring(in_keep), view, profile, career)
end

local function _cim_str()
    -- cim doesn't expose MOD_VERSION on its mod table (file-scope local),
    -- so we can only assert present/absent here. If a future cim release
    -- exposes `mod.MOD_VERSION`, switch this to read it.
    return get_mod("cim") and "present" or "absent"
end

-- Wrap the existing mod.on_game_state_changed (defined above) so we
-- don't clobber the third-person camera / noclip / time-scale / AI
-- takeover reset logic that already lives there.
do
    local prev = mod.on_game_state_changed
    mod.on_game_state_changed = function(status, state_name)
        if prev then prev(status, state_name) end
        _dbg("[state] %s %s | %s | cim=%s", status, tostring(state_name), _ctx_str(), _cim_str())
    end
end

-- HeroView open/close: every entry to the keep / mission inventory
-- menu. Useful for confirming gt_open_mission_inventory actually
-- dispatched and which substate the view landed in.
mod:hook("HeroView", "on_enter", function(func, self, params, ...)
    _dbg("[hero_view] on_enter | %s | cim=%s", _ctx_str(), _cim_str())
    return func(self, params, ...)
end)

mod:hook("HeroView", "on_exit", function(func, self, ...)
    _dbg("[hero_view] on_exit | %s", _ctx_str())
    return func(self, ...)
end)

-- Item Customization screen: dump item context on enter so a future
-- crash log carries backend_id, slot, item key, plus mechanism + cim
-- presence. This is the screen the gear icon opens — the same path
-- that crashed in fa1ec6f8 (CW) and ef637399 (dlc_dwarf_interior).
mod:hook("HeroWindowItemCustomization", "on_enter", function(func, self, params, ...)
    local slot, key, bid = "?", "?", "?"
    if params and params.item_to_customize then
        local item = params.item_to_customize
        local d = item.data
        slot = (d and d.slot_type) or "?"
        key  = item.key or (d and d.key) or "?"
        bid  = item.backend_id or "?"
    end
    _dbg("[item_customize] on_enter item.key=%s slot=%s backend_id=%s | %s | cim=%s",
        tostring(key), tostring(slot), tostring(bid), _ctx_str(), _cim_str())
    return func(self, params, ...)
end)

mod:hook("HeroWindowItemCustomization", "on_exit", function(func, self, params, ...)
    local sd = self and self._skin_dirty and "true" or "false"
    local id = self and self._item_dirty and "true" or "false"
    local cd = self and self._character_dirty and "true" or "false"
    _dbg("[item_customize] on_exit skin_dirty=%s item_dirty=%s character_dirty=%s", sd, id, cd)
    return func(self, params, ...)
end)

-- Every menu transition — log the requested transition name. Often
-- the difference between "click did nothing" and "transition was
-- requested but blocked by IngameUI gates" is invisible without this.
mod:hook("IngameUI", "handle_transition", function(func, self, new_transition, transition_params, ...)
    _dbg("[transition] %s | %s", tostring(new_transition), _ctx_str())
    return func(self, new_transition, transition_params, ...)
end)

-- Level loading: log when a new level resource is requested. Pairs
-- well with the [state] enter StateLoading line — that line fires
-- first with the previous level still resolved; this one fires next
-- with the level being loaded. Hooks load_current_level directly
-- with full mod:hook because other mods (BossTimer, keyPickupMessage,
-- Loremasters-Armoury) all hook_safe this method — adding a fourth
-- hook_safe would silently shadow theirs.
mod:hook("LevelTransitionHandler", "load_current_level", function(func, self, ...)
    local lvl = "?"
    if self and self.level_key then
        lvl = (type(self.level_key) == "function" and self:level_key()) or tostring(self.level_key) or "?"
    end
    _dbg("[level_load] requested level_key=%s | %s | cim=%s", lvl, _ctx_str(), _cim_str())
    return func(self, ...)
end)

-- ------------------------------------------------------------
-- AI takeover / bot dump
-- ------------------------------------------------------------
-- Players table, bots table, party slot assignments, game-mode bot
-- capability flags, profile_synchronizer reservations, host peer_id,
-- and mod._gt_ai_saved_state contents. Used to triage why AI takeover still
-- doesn't reliably swap — the swap path depends on a long chain of
-- preconditions (server-only mutation, party slot present, game_mode
-- exposes _add_bot_to_party, profile_synchronizer not still busy with
-- a transfer) and a failure at any link returns one short reason
-- string. The dump surfaces the whole chain.
--
-- Auto-fires on: StateIngame enter, AI toggle changes (both host &
-- client), and a peer joining/leaving. Manual: /dump_ai.

local function _safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

local function _player_brief(p)
    if not p then return "nil" end
    local peer = (p.peer_id and (type(p.peer_id) == "function" and p:peer_id()) or p.peer_id) or "?"
    local lpid = p.local_player_id and (type(p.local_player_id) == "function" and p:local_player_id() or p.local_player_id) or "?"
    -- Same 0-vs-nil distinction as _ctx_str: SPProfiles is 1-indexed so
    -- pi=0 is "unbound", not a valid profile. Surface as "?".
    local pi = (p.profile_index and p:profile_index()) or 0
    local ci = (p.career_index  and p:career_index())  or 0
    local sp = (pi > 0) and rawget(_G, "SPProfiles") and SPProfiles[pi]
    local profile = (sp and sp.display_name) or (pi > 0 and tostring(pi)) or "?"
    local sp_career = sp and sp.careers and sp.careers[ci]
    local career = (sp_career and sp_career.name) or (ci > 0 and tostring(ci)) or "?"
    local unit_alive = (p.player_unit and Unit and Unit.alive(p.player_unit)) and "true" or "false"
    return string.format("{peer=%s lpid=%s profile=%s career=%s bot=%s remote=%s unit_alive=%s}",
        tostring(peer), tostring(lpid), profile, career,
        tostring(p.bot_player and true or false),
        tostring(p.remote and true or false),
        unit_alive)
end

local function _gt_dump_ai_now(why)
    local pm = Managers and Managers.player
    if not pm then
        _dbg("[ai_dump:%s] Managers.player absent", why or "manual")
        return
    end
    _dbg("[ai_dump:%s] === BEGIN ===", why or "manual")
    _dbg("[ai_dump:%s] context: %s", why or "manual", _ctx_str())
    _dbg("[ai_dump:%s] is_server=%s peer=%s",
        why or "manual",
        tostring(pm.is_server and true or false),
        tostring(Network and Network.peer_id and Network.peer_id() or "?"))

    -- Mechanism / host
    local host = nil
    if Managers.mechanism and Managers.mechanism.server_peer_id then
        host = _safe_call(function() return Managers.mechanism:server_peer_id() end)
    end
    _dbg("[ai_dump:%s] mechanism=%s host_peer=%s",
        why or "manual",
        Managers.mechanism and _safe_call(function() return Managers.mechanism:current_mechanism_name() end) or "?",
        tostring(host or "?"))

    -- Players & bots
    local players = (pm.players and _safe_call(function() return pm:players() end)) or {}
    local nh, nb = 0, 0
    for _, p in pairs(players) do
        if p.bot_player then nb = nb + 1 else nh = nh + 1 end
        _dbg("[ai_dump:%s] player %s", why or "manual", _player_brief(p))
    end
    _dbg("[ai_dump:%s] counts: humans=%d bots=%d total=%d", why or "manual", nh, nb, nh + nb)

    -- Party slots
    local parties = Managers.party and Managers.party._parties
    if parties then
        for pid, party in pairs(parties) do
            local slots = party and (party.slots or party.occupied_slots) or {}
            local slot_lines = {}
            for sid, slot in pairs(slots) do
                local peer = slot and (slot.peer_id or (slot.player and slot.player.peer_id)) or "-"
                slot_lines[#slot_lines + 1] = string.format("[%s]=%s", tostring(sid), tostring(peer))
            end
            _dbg("[ai_dump:%s] party %s slots {%s}", why or "manual", tostring(pid), table.concat(slot_lines, ","))
        end
    else
        _dbg("[ai_dump:%s] Managers.party absent or no _parties", why or "manual")
    end

    -- Game mode bot capability
    local gm = Managers.state and Managers.state.game_mode and _safe_call(function() return Managers.state.game_mode:game_mode() end)
    if gm then
        _dbg("[ai_dump:%s] game_mode supports: _add_bot_to_party=%s _remove_bot_instant=%s",
            why or "manual",
            tostring(gm._add_bot_to_party and true or false),
            tostring(gm._remove_bot_instant and true or false))
    else
        _dbg("[ai_dump:%s] game_mode unavailable", why or "manual")
    end

    -- Profile sync state. ProfileSynchronizer stores reservations inside
    -- its private `self._state` (a SharedState), not on the synchronizer
    -- itself — there is no `_owned_profiles` field. The canonical public
    -- enumerator is `:get_peers_with_full_profiles()` which returns an
    -- array of `{peer_id, local_player_id, profile_index, career_index}`
    -- entries. Use it to surface who's bound to which profile/career.
    local ps = pm.network_manager and pm.network_manager.profile_synchronizer
    if ps and ps.get_peers_with_full_profiles then
        local entries = _safe_call(function() return ps:get_peers_with_full_profiles() end) or {}
        if #entries > 0 then
            local lines = {}
            for _, e in ipairs(entries) do
                lines[#lines + 1] = string.format("{peer=%s lpid=%s pi=%s ci=%s}",
                    tostring(e.peer_id), tostring(e.local_player_id),
                    tostring(e.profile_index), tostring(e.career_index))
            end
            _dbg("[ai_dump:%s] profile_sync full_profiles: %s",
                why or "manual", table.concat(lines, " | "))
        else
            _dbg("[ai_dump:%s] profile_sync full_profiles: <empty>", why or "manual")
        end
    else
        _dbg("[ai_dump:%s] profile_synchronizer not available", why or "manual")
    end

    -- gt's own saved state
    local saved_lines = {}
    for k, v in pairs(mod._gt_ai_saved_state) do
        saved_lines[#saved_lines + 1] = string.format("%s={pi=%s,ci=%s,party=%s,slot=%s,remote=%s}",
            tostring(k), tostring(v.profile_index), tostring(v.career_index),
            tostring(v.party_id), tostring(v.slot_id), tostring(v.is_remote))
    end
    _dbg("[ai_dump:%s] mod._gt_ai_saved_state: {%s}", why or "manual", table.concat(saved_lines, " | "))
    _dbg("[ai_dump:%s] mod._gt_ai_pending_host_toggle=%s mod._gt_ai_pending_client_send=%s",
        why or "manual",
        mod._gt_ai_pending_host_toggle and "queued" or "nil",
        mod._gt_ai_pending_client_send and "queued" or "nil")

    -- VMF handshake state. The `_vmf_users` ping/pong table is a
    -- file-scope local inside `scripts/mods/vmf/modules/core/network.lua`
    -- (confirmed in cosmetics_tweaker/RPC_NOT_ROUTING.md). It is not
    -- exposed on the VMF mod table, so no introspection from outside
    -- VMF. If a client AI toggle fails, the relevant signals are the
    -- `[ai_toggle queue]` / `[ai_toggle emit]` mod:info lines (each
    -- retry logs a "CLIENT->req" attempt and ping_vmf_users is re-
    -- called before each fire to refresh the handshake).
    _dbg("[ai_dump:%s] vmf user table: private to VMF.network (not introspectable)", why or "manual")

    _dbg("[ai_dump:%s] === END ===", why or "manual")
end
-- Exposed so the AI Takeover module's debug-toggle dump wrap (in
-- _gt_ai_takeover.lua) can call this at call time. Travels with the rest of the
-- debug probes into _gt_debug_probes.lua in module 1 of this phase.
mod._gt_dump_ai_now = _gt_dump_ai_now

mod:command("dump_ai", "Dump the AI/bot takeover state (players, bots, party slots, profile sync, host peer, saved state)", function()
    -- Run the dump unconditionally on command (don't gate on debug_mode
    -- since the user explicitly asked for it). Force mod:info emission.
    local was = mod:get("gt_debug_mode")
    if not was then mod:set("gt_debug_mode", true) end
    _gt_dump_ai_now("manual")
    if not was then mod:set("gt_debug_mode", false) end
end)

-- ------------------------------------------------------------
-- AI takeover redesign probe: per-slot + camera-state dump
-- ------------------------------------------------------------
-- v0.2.116-dev (research wkcu0v4as): instrument the vanilla dead/respawn/slot
-- machinery the keep-slot rewrite will reuse. For each party slot, dump the raw
-- spawning status (game_mode_data.spawn_state / health_state) plus whether the
-- slot's player_unit exists and is alive, and the local player's live camera
-- state-machine state (so the user can SEE the engine drive observer entry/exit
-- on death/respawn before we replicate it). Every lookup is nil-guarded -- this
-- runs with units mid-teardown.
--
-- spawn_state / health_state live on the slot's player_status.game_mode_data,
-- written by AdventureSpawning._update_player_status (adventure_spawning.lua:
-- 263-266, 307-309). num_used_slots / num_slots are counters on the party
-- object (party_manager.lua:660-661). The camera state-machine state lives on
-- the player's separate camera_follow_unit (NOT player_unit) under the
-- "camera_state_machine_system" extension; the current state name is
-- state_machine.state_current.name (generic_state_machine.lua:90,
-- camera_system.lua:85). That unit survives player_unit despawn, which is
-- exactly why the observer cam keeps working with no controlled unit.

-- Read the live camera state-machine state name for a player, or a reason
-- string. The camera unit is per-player and persists across unit despawn.
local function _gt_player_camera_state(player)
    if not player then return "no-player" end
    local cam_unit = player.camera_follow_unit
    if not (cam_unit and rawget(_G, "Unit") and Unit.alive(cam_unit)) then return "no-camera-unit" end
    if not (rawget(_G, "ScriptUnit") and ScriptUnit.has_extension) then return "no-scriptunit" end
    local ext = ScriptUnit.has_extension(cam_unit, "camera_state_machine_system")
    if not ext then return "no-camera-ext" end
    -- Prefer the public getter; fall back to the raw field if the shape differs.
    if ext.state_machine and ext.state_machine.current_state then
        local ok, name = pcall(function() return ext.state_machine:current_state() end)
        if ok and name then return tostring(name) end
    end
    local sc = ext.state_machine and ext.state_machine.state_current
    return (sc and sc.name and tostring(sc.name)) or "unknown"
end

local function _gt_ai_slotdump(why)
    local why_s = why or "manual"
    local pm = Managers and Managers.player
    if not pm then
        _dbg("[ai_slotdump:%s] Managers.player absent", why_s)
        return
    end
    _dbg("[ai_slotdump:%s] === BEGIN === %s", why_s, _ctx_str())

    -- Local player's live camera state (observer/follow/idle/...). This is the
    -- make-or-break signal for the redesign -- it confirms the engine drives the
    -- client into observer cam on death and back to follow on respawn.
    local lp = (pm.local_player and _safe_call(function() return pm:local_player() end)) or nil
    _dbg("[ai_slotdump:%s] local_player camera_state=%s player=%s",
        why_s, _gt_player_camera_state(lp), _player_brief(lp))

    local parties = Managers.party and Managers.party._parties
    if not parties then
        _dbg("[ai_slotdump:%s] Managers.party absent or no _parties", why_s)
        _dbg("[ai_slotdump:%s] === END ===", why_s)
        return
    end

    for pid, party in pairs(parties) do
        local num_used = party and party.num_used_slots
        local num_slots = party and party.num_slots
        _dbg("[ai_slotdump:%s] party=%s num_used_slots=%s num_slots=%s",
            why_s, tostring(pid), tostring(num_used), tostring(num_slots))

        local slots = party and (party.slots or party.occupied_slots) or {}
        for sid, slot in pairs(slots) do
            -- slot fields are written by PartyManager._clear_slot_in_party /
            -- assign; peer_id == nil means a free slot.
            local peer_id = slot and slot.peer_id
            local lpid = slot and slot.local_player_id
            -- Resolve the slot's player object (may be a bot, a human, or gone).
            local player = nil
            if peer_id ~= nil and lpid ~= nil and pm.player then
                player = _safe_call(function() return pm:player(peer_id, lpid) end)
            end
            local is_bot = player and player.bot_player and true or false
            local punit = player and player.player_unit
            local has_unit = punit ~= nil
            local unit_alive = (has_unit and rawget(_G, "Unit") and Unit.alive(punit)) and true or false

            -- Spawning status lives on the host-side player_status for this slot.
            local pstatus = nil
            if peer_id ~= nil and lpid ~= nil and Managers.party.get_player_status then
                pstatus = _safe_call(function() return Managers.party:get_player_status(peer_id, lpid) end)
            end
            local gmd = pstatus and pstatus.game_mode_data
            local spawn_state  = gmd and gmd.spawn_state
            local health_state = gmd and gmd.health_state

            _dbg("[ai_slotdump:%s] slot_id=%s peer_id=%s local_player_id=%s is_bot=%s has_unit=%s unit_alive=%s spawn_state=%s health_state=%s",
                why_s,
                tostring(sid),
                tostring(peer_id),
                tostring(lpid),
                tostring(is_bot),
                tostring(has_unit),
                tostring(unit_alive),
                tostring(spawn_state),
                tostring(health_state))
        end
    end

    _dbg("[ai_slotdump:%s] === END ===", why_s)
end

-- Forced auto-dump (v0.2.121-dev): fire _gt_ai_slotdump even with Debug Logging OFF,
-- so the AI-takeover redesign data is captured during a NORMAL Chaos Wastes session
-- with ZERO commands. Temporarily flips the live debug gate (callback suppressed via
-- the 3rd arg to mod:set so it doesn't churn on_setting_changed) so the _dbg lines in
-- the slotdump emit, then restores it. The re-entrancy guard + pcall keep the restore
-- bulletproof even if the dump throws. Wired to the camera + relinquish hooks below.
local _gt_ai_autodumping = false
local function _gt_ai_autodump(why)
    if _gt_ai_autodumping then return end
    _gt_ai_autodumping = true
    pcall(_gt_ai_slotdump, why)
    _gt_ai_autodumping = false
end

mod:command("ai_slotdump", "Dump per-slot spawn/health state + the local player's camera state (AI-takeover redesign probe)", function()
    _gt_ai_slotdump("manual")
end)

-- ============================================================
-- Bot-loadout resolution probe (v0.2.123-dev)
-- ============================================================
-- REPORT: a host's AI bots spawn using the host's LAST-EQUIPPED loadout instead
-- of the loadout the host DESIGNATED as the bot loadout (via the loadout-slot UI /
-- "Modern UI"). Vanilla BackendInterfaceItemPlayfab.refresh_bot_loadouts
-- (backend_interface_item_playfab.lua:128-160) sets bot_loadouts = clone(the host's
-- current _loadouts) FIRST (line 129), then per career OVERRIDES from the
-- designated slot ONLY IF both:
--   (a) PlayerData.loadout_selection.bot_equipment[career] is set (the assignment), AND
--   (b) backend_mirror:has_loadout(career, idx) is true (the slot exists in the mirror).
-- If (a) is nil -> NO_ASSIGNMENT; if (b) is false -> the assignment is CLEARED
-- (line 144) -> ASSIGNED_BUT_MISSING. Either way the career keeps the host clone =
-- the reported bug. This probe re-derives that resolution READ-ONLY at every
-- refresh and logs, per career, which branch fired + whether the resulting bot
-- loadout is identical to the host's current loadout (the bug signature). That
-- tells us whether the UI mod's assignment never reached bot_equipment, or the
-- designated slot isn't recognized by the (possibly modded) backend mirror.
local _gt_item_interface = nil

local function _gt_bot_loadout_dump(itf, why)
    why = why or "manual"
    -- Resolve the LIVE item interface (the LA clone under Loremaster's Armoury),
    -- not the cold class -- get_interface("items") is the accessor cim/CWV use.
    itf = itf or _gt_item_interface
        or (Managers and Managers.backend and Managers.backend.get_interface
            and Managers.backend:get_interface("items"))
    if not itf then
        _dbg("[bot_loadout:%s] no item backend interface available (run /bot_loadout_dump in the keep)", why)
        return
    end
    local bot_loadouts = itf._bot_loadouts
    local host_loadouts = itf._loadouts
    local backend_mirror = itf._backend_mirror
    if not (bot_loadouts and host_loadouts) then
        _dbg("[bot_loadout:%s] interface has no _bot_loadouts/_loadouts yet", why)
        return
    end
    local pd = rawget(_G, "PlayerData")
    local loadout_selection = (pd and pd.loadout_selection) or {}
    local bot_equipment = loadout_selection.bot_equipment or {}
    local mech = Managers.mechanism and Managers.mechanism:current_mechanism_name()
    local inv = rawget(_G, "InventorySettings")
    local allowed = inv and inv.bot_loadout_allowed_mechanisms and inv.bot_loadout_allowed_mechanisms[mech]
    local be_count = 0
    for _ in pairs(bot_equipment) do be_count = be_count + 1 end
    _dbg("[bot_loadout:%s] === BEGIN === mech=%s bot_loadout_allowed=%s loadout_selection_present=%s bot_equipment_entries=%d",
        why, tostring(mech), tostring(allowed),
        tostring((pd and pd.loadout_selection) ~= nil), be_count)

    local careers = rawget(_G, "CareerSettings") or {}
    local n_ok, n_noassign, n_missing, n_clone = 0, 0, 0, 0
    for career, settings in pairs(careers) do
        if settings.playfab_name then
            local idx = allowed and bot_equipment[career]
            local has = nil
            if idx and backend_mirror and backend_mirror.has_loadout then
                local ok, r = pcall(function() return backend_mirror:has_loadout(career, idx) end)
                has = ok and (r and true or false) or nil
            end
            local bot_lo = bot_loadouts[career]
            local host_lo = host_loadouts[career]
            local clones_host = bot_lo and host_lo
                and bot_lo.slot_melee == host_lo.slot_melee
                and bot_lo.slot_ranged == host_lo.slot_ranged or false
            local status
            if not idx then status = "NO_ASSIGNMENT"; n_noassign = n_noassign + 1
            elseif has == false then status = "ASSIGNED_BUT_MISSING_IN_MIRROR"; n_missing = n_missing + 1
            else status = "OK_DESIGNATED"; n_ok = n_ok + 1 end
            if clones_host then n_clone = n_clone + 1 end
            -- Only log careers that are problematic OR clone the host (keeps a
            -- healthy setup quiet; a broken one surfaces the offending careers).
            if status ~= "OK_DESIGNATED" or clones_host then
                _dbg("[bot_loadout:%s] career=%s status=%s bot_idx=%s has_loadout=%s clones_host_current=%s bot{m=%s r=%s} host{m=%s r=%s}",
                    why, career, status, tostring(idx), tostring(has), tostring(clones_host),
                    tostring(bot_lo and bot_lo.slot_melee), tostring(bot_lo and bot_lo.slot_ranged),
                    tostring(host_lo and host_lo.slot_melee), tostring(host_lo and host_lo.slot_ranged))
            end
        end
    end
    _dbg("[bot_loadout:%s] === END === summary: OK_designated=%d no_assignment=%d missing_in_mirror=%d clones_host_current=%d",
        why, n_ok, n_noassign, n_missing, n_clone)
end

-- Forced auto-dump on every bot-loadout refresh (no command, no Debug Logging
-- needed) -- same forced-output pattern as the AI slotdump probe. Pre-flight:
-- grep "BackendInterfaceItemPlayfab" / "refresh_bot_loadouts" (quoted) -> ZERO
-- existing hooks in gt_dev. Safe to register.
local _gt_bl_dumping = false
local function _gt_bot_loadout_autodump(itf, why)
    if _gt_bl_dumping then return end
    _gt_bl_dumping = true
    pcall(_gt_bot_loadout_dump, itf, why)
    _gt_bl_dumping = false
end

-- Non-LA path: this class hook fires only when NO clone-backend mod intercepts.
mod:hook_safe("BackendInterfaceItemPlayfab", "refresh_bot_loadouts", function(self)
    _gt_item_interface = self
    _gt_bot_loadout_autodump(self, "refresh")
end)

-- LA path (v0.2.125-dev): Loremaster's Armoury replaces the live item interface
-- with a clone whose methods are COPIED, so the class hook above silently misses
-- every call -- CONFIRMED 2026-06-20: 14 vanilla `refresh_bot_loadouts` runs,
-- ZERO hook fires, with LA active. Table-hook the LIVE instance from
-- get_interface("items") instead (LA-safe: patches the actual object's own method
-- copy). Installed once, on demand -- the command triggers it -- so subsequent
-- refreshes auto-dump too. Different hook target than the class hook above, so no
-- VMF duplicate-hook collision.
local _gt_bl_live_hooked = false
local function _gt_try_hook_live_item_interface()
    if _gt_bl_live_hooked then return end
    local backend = Managers and Managers.backend
    local itf = backend and backend.get_interface and backend:get_interface("items")
    if not (itf and type(itf.refresh_bot_loadouts) == "function") then return end
    _gt_item_interface = itf
    local ok = pcall(function()
        mod:hook_safe(itf, "refresh_bot_loadouts", function(self)
            _gt_item_interface = self
            _gt_bot_loadout_autodump(self, "refresh")
        end)
    end)
    if ok then
        _gt_bl_live_hooked = true
        mod:info("[bot_loadout] live item-interface auto-dump hook installed (LA-safe path)")
    end
end

mod:command("bot_loadout_dump", "Dump bot-loadout resolution (designated bot loadout vs host's current) -- run in the keep after setting bots", function()
    _gt_try_hook_live_item_interface()   -- also wires auto-dump for future refreshes
    _gt_bot_loadout_dump(nil, "manual")   -- nil -> resolve the LIVE interface
end)

-- ============================================================
-- Patrol-formation crash probe (v0.2.124-dev)
-- ============================================================
-- The reported "necromancer-ult crash" logs as a VANILLA patrol crash:
-- ai_group_templates_patrol.lua update_units -> Vector3_distance_squared,
-- "Vector3 expected, got userdata" on arg #1 = POSITION_LOOKUP[member]. The error
-- aborts the frame, so we must NAME the offending member BEFORE vanilla runs.
-- This table-hooks the spline_patrol template's update, scans the group's
-- indexed_members each tick, and logs (unconditional mod:info, so it lands with
-- Debug Logging OFF) any member whose POSITION_LOOKUP is missing or not a real
-- Vector3 -- i.e. exactly the unit update_units is about to crash on -- with its
-- breed. If that breed is pet_skeleton_* the necro pets ARE entering patrols
-- (which would refute the mechanism analysis); if skaven_*/chaos_* it's the
-- oversized-patrol path that enemy_tweaker 0.7.13's row cap addresses. LOG ONLY
-- (no guard) so the crash still produces its backtrace for correlation. The scan
-- only emits on a bad member (rare), so no per-frame spam. Pre-flight: zero prior
-- gt_dev hooks on AIGroupTemplates / spline_patrol / update_units (verified).
do
    local AGT = rawget(_G, "AIGroupTemplates")
    local tmpl = AGT and AGT.spline_patrol
    if tmpl and type(tmpl.update) == "function" then
        mod:hook(tmpl, "update", function(func, world, nav_world, group, ...)
            local PL = rawget(_G, "POSITION_LOOKUP")
            local V3 = rawget(_G, "Vector3")
            local members = group and group.indexed_members
            local n = (group and group.num_indexed_members) or 0
            if PL and V3 and members and n > 0 then
                for i = 1, n do
                    local unit = members[i]
                    local pos = unit and PL[unit]
                    -- valid Vector3 -> Vector3.length succeeds; nil or wrong-type
                    -- userdata -> fails. This is the exact arg update_units passes
                    -- to Vector3_distance_squared.
                    local good = pos ~= nil and pcall(V3.length, pos)
                    if not good then
                        local bb = rawget(_G, "BLACKBOARDS")
                        bb = bb and bb[unit]
                        local breed = bb and bb.breed and bb.breed.name or "?"
                        local U = rawget(_G, "Unit")
                        mod:info("[patrol_probe] BAD MEMBER (update_units will crash here): i=%d/%d breed=%s unit=%s alive=%s pos=%s type=%s group_type=%s",
                            i, n, tostring(breed), tostring(unit),
                            tostring(U and unit and U.alive(unit)),
                            tostring(pos), type(pos), tostring(group.group_type))
                    end
                end
            end
            return func(world, nav_world, group, ...)
        end)
        mod:info("[patrol_probe] installed on AIGroupTemplates.spline_patrol.update")
    else
        mod:info("[patrol_probe] AIGroupTemplates.spline_patrol.update not present at hook time -- probe NOT installed")
    end
end

-- Auto-fire on player join/leave so we see who's where. hook_safe is
-- safe here: gt is the only mod hooking add_remote_player /
-- remove_player in this repo (verified). If another mod ships a
-- hook_safe on these, switch to full mod:hook.
mod:hook_safe("PlayerManager", "add_remote_player", function(self, peer_id, ...)
    _dbg("[ai_event] add_remote_player peer=%s", tostring(peer_id))
    _gt_dump_ai_now("peer_join")
end)

mod:hook_safe("PlayerManager", "remove_player", function(self, peer_id, local_player_id, ...)
    _dbg("[ai_event] remove_player peer=%s lpid=%s", tostring(peer_id), tostring(local_player_id))
    _gt_dump_ai_now("peer_leave")
end)

-- v0.2.116-dev (research wkcu0v4as): probes for the keep-slot AI-takeover
-- redesign. Both are debug-gated (fire through _dbg) and silent in normal play.
-- They capture the vanilla observer-entry/exit + clean unit relinquish the
-- rewrite will reuse, WITHOUT touching any behavior.
--
-- Pre-flight (VMF duplicate-hook rule, repo CLAUDE.md): grepped the file for
-- "change_camera_state" and "relinquish_unit_ownership" (quoted) -> ZERO
-- existing hooks on either. The only prior reference to change_camera_state is
-- a direct pcall(CharacterStateHelper.change_camera_state, ...) call (~line 625),
-- which is NOT a hook -- no collision. Safe to register.

-- Observer entry/exit: change_camera_state is the single funnel the dead/respawn
-- flow uses to push a player into "observer" and back to "follow"
-- (player_character_state_helper.lua:1822; bot_player calls early-return at
-- :1823, so bots never log a real transition). Signature is the static
-- (player, state, params); hook_safe fires after the camera actually switched.
mod:hook_safe("CharacterStateHelper", "change_camera_state", function(player, state, params)
    -- AUTO-CAPTURE (forced; no command + no Debug Logging needed): the dead<->respawn
    -- cycle funnels through here -- death -> "observer", respawn -> "follow". Auto-dump
    -- the slot+camera state on those two transitions so a normal CW death/respawn
    -- captures the redesign data hands-free. (bots early-return upstream; guard anyway.)
    if (state == "observer" or state == "follow") and not (player and player.bot_player) then
        _gt_ai_autodump("cam_" .. tostring(state))
    end
    if not _dbg_on() then return end
    local name = "?"
    if player then
        if player.name then
            name = (type(player.name) == "function" and _safe_call(function() return player:name() end)) or player.name or "?"
        end
    end
    _dbg("[ai_cam] change_camera_state player=%s -> state=%s bot=%s",
        tostring(name), tostring(state), tostring(player and player.bot_player and true or false))
end)

-- Clean relinquish on death: relinquish_unit_ownership nulls owner.player_unit
-- and fires "player_unit_relinquished" (player_manager.lua:236-252). This is the
-- exact clean teardown the rewrite needs the CLIENT to perform on its OWN unit
-- (instead of the host orphaning it). Signature is the method (self, unit).
mod:hook_safe("PlayerManager", "relinquish_unit_ownership", function(self, unit)
    -- AUTO-CAPTURE (forced): a player's unit being relinquished IS the clean death/
    -- despawn the redesign hinges on -- auto-dump hands-free so a normal CW death
    -- captures it without any command.
    _gt_ai_autodump("relinquish")
    if not _dbg_on() then return end
    local owner = (self and self._player_units_owners and self._player_units_owners[unit]) or nil
    local name = "?"
    if owner then
        if owner.name then
            name = (type(owner.name) == "function" and _safe_call(function() return owner:name() end)) or owner.name or "?"
        end
    end
    _dbg("[ai_relinquish] relinquish_unit_ownership owner=%s player_unit nulled (unit=%s)",
        tostring(name), tostring(unit))
end)

-- ------------------------------------------------------------
-- Menu / inventory dump
-- ------------------------------------------------------------
-- HeroView substate hierarchy + active windows + which game modes
-- the inventory considers itself allowed in. Useful for diagnosing
-- why a menu doesn't show up mid-mission, and which windows mounted
-- so we can target the right Class.method for any further hardening.
--
-- Auto-fires on: HeroView open, HeroViewStateOverview.set_layout_by_name,
-- and each HeroWindow* substate enter. Manual: /dump_menu.

local function _gt_dump_menu_now(why)
    _dbg("[menu_dump:%s] === BEGIN ===", why or "manual")
    _dbg("[menu_dump:%s] context: %s", why or "manual", _ctx_str())

    -- InventorySettings flags — the patch that allows the inventory
    -- panel to consider itself valid mid-mission.
    local inv = rawget(_G, "InventorySettings")
    local modes = inv and inv.inventory_loadout_access_supported_game_modes
    if modes then
        local mlines = {}
        for k, v in pairs(modes) do
            mlines[#mlines + 1] = string.format("%s=%s", tostring(k), tostring(v))
        end
        _dbg("[menu_dump:%s] inv.supported_game_modes: {%s}", why or "manual", table.concat(mlines, ","))
    else
        _dbg("[menu_dump:%s] InventorySettings.inventory_loadout_access_supported_game_modes absent", why or "manual")
    end

    local ingame_ui = Managers and Managers.ui and Managers.ui._ingame_ui
    if not ingame_ui then
        _dbg("[menu_dump:%s] no ingame_ui (not in StateIngame?)", why or "manual")
        _dbg("[menu_dump:%s] === END ===", why or "manual")
        return
    end

    local hero_view = ingame_ui.views and ingame_ui.views.hero_view
    if not hero_view then
        _dbg("[menu_dump:%s] hero_view view not registered", why or "manual")
        _dbg("[menu_dump:%s] === END ===", why or "manual")
        return
    end

    -- Current state name. VT2's class() helper (foundation/scripts/util/
    -- class.lua) sets `class_table.NAME` directly when the state file
    -- declares `Cls.NAME = "..."` after `class(Cls)`. Since
    -- `class_table.__index = class_table`, instances inherit NAME via
    -- the metatable — so `state.NAME` resolves correctly. Vanilla
    -- hero_view.lua:442 reads it the same way (`current_state.NAME`).
    local state = hero_view.current_state and _safe_call(function() return hero_view:current_state() end)
                  or (hero_view._machine and _safe_call(function() return hero_view._machine:state() end))
    local state_name = (state and state.NAME) or "?"
    _dbg("[menu_dump:%s] hero_view.state=%s current_transition=%s",
        why or "manual", state_name, tostring(ingame_ui._previous_transition or "?"))

    -- Active windows. HeroViewStateOverview stores them on `_active_windows`
    -- (underscore-prefixed — `hero_view_state_overview.lua:253`). Each
    -- entry is a window-class instance with a `.NAME` field set the same
    -- way as the state class (e.g. "HeroWindowLoadoutConsole").
    local active = state and state._active_windows
    if active then
        for idx, win in pairs(active) do
            local cls = (win and win.NAME) or "?"
            _dbg("[menu_dump:%s] window[%s]=%s", why or "manual", tostring(idx), cls)
        end
    else
        _dbg("[menu_dump:%s] no _active_windows on state", why or "manual")
    end

    -- Available layout names. `_window_layouts` is an ipairs array of
    -- `{name = "...", windows = {...}, ...}` tables — keys are integer
    -- indices, names live in the `.name` field of each entry. Iterating
    -- pairs() over the array and stringifying the integer keys produced
    -- "1,2,3,..." in the old code; surface the actual layout names
    -- (e.g. "equipment", "equipment_selection", "item_customization",
    -- "system") so they're useful targets for set_layout_by_name.
    if state and state._window_layouts then
        local layout_names = {}
        for _, entry in ipairs(state._window_layouts) do
            if entry and entry.name then
                layout_names[#layout_names + 1] = tostring(entry.name)
            end
        end
        _dbg("[menu_dump:%s] available layouts: %s", why or "manual", table.concat(layout_names, ","))
    end

    _dbg("[menu_dump:%s] === END ===", why or "manual")
end

mod:command("dump_menu", "Dump the active HeroView substate + windows + InventorySettings flags", function()
    local was = mod:get("gt_debug_mode")
    if not was then mod:set("gt_debug_mode", true) end
    _gt_dump_menu_now("manual")
    if not was then mod:set("gt_debug_mode", false) end
end)

-- Auto-fire on each layout change inside HeroViewStateOverview. This
-- catches the inventory → customize → upgrade → equipment_selection
-- traversal that the gear icon and tab buttons drive.
mod:hook("HeroViewStateOverview", "set_layout_by_name", function(func, self, name, ...)
    _dbg("[menu_event] set_layout_by_name name=%s", tostring(name))
    if _dbg_on() then _gt_dump_menu_now("layout_" .. tostring(name)) end
    return func(self, name, ...)
end)

mod:hook("HeroViewStateOverview", "on_enter", function(func, self, params, ...)
    _dbg("[menu_event] HeroViewStateOverview.on_enter")
    if _dbg_on() then _gt_dump_menu_now("state_overview_enter") end
    return func(self, params, ...)
end)

-- Each substate-window enter/exit is already vanilla-printed (see the
-- log: "[HeroViewWindow] Enter Substate HeroWindowLoadoutConsole").
-- Extend with our context so the same line carries mechanism +
-- in_keep + level info. _change_window is the single chokepoint
-- vanilla routes every window swap through.
mod:hook("HeroViewStateOverview", "_change_window", function(func, self, window_index, window_name, ...)
    _dbg("[menu_event] _change_window index=%s name=%s | %s",
        tostring(window_index), tostring(window_name), _ctx_str())
    return func(self, window_index, window_name, ...)
end)

-- AI-toggle pre/post dump wrap lives further down — see the comment
-- block after mod._gt_ai_handle_toggle_change's assignment (~line 2535).
-- It can't live here because mod._gt_ai_handle_toggle_change is forward-
-- declared at the top of the file and not assigned until line 2463;
-- capturing it here would bind to nil.

-- Auto-fire one AI dump shortly after StateIngame enter (deferred so
-- the player manager has finished publishing the local player /
-- mechanism has its server_peer_id). Wired by extending the
-- on_game_state_changed handler.
do
    local prev = mod.on_game_state_changed
    local _pending_after_ingame = false
    mod.on_game_state_changed = function(status, state_name)
        if prev then prev(status, state_name) end
        if status == "enter" and state_name == "StateIngame" and _dbg_on() then
            _pending_after_ingame = true
        end
    end
    -- Drain the pending dump on the first update tick after StateIngame
    -- enter — Managers.player and Managers.mechanism are guaranteed
    -- ready by then.
    local prev_update = mod.update
    mod.update = function(self, dt)
        if prev_update then prev_update(self, dt) end
        if _pending_after_ingame then
            _pending_after_ingame = false
            _gt_dump_ai_now("state_ingame_enter")
            _gt_dump_menu_now("state_ingame_enter")
        end
    end
end

-- ============================================================
-- Burning-enemy fire VFX opacity — PROBE phase (v0.2.93-dev)
-- ============================================================
-- The fire on a burning enemy is the `burning` StatusEffect particle
-- (fx/chr_impact_fire_{large,medium,small}_remap, linked to the enemy at j_hips;
-- status_effect_templates.lua:44/200). Its on_applied returns apply_data with
-- .particle_id (+ .attach_unit). The decompiled source names a COLOR-tint
-- material variable for that fire (cloud "fire", var "remap_index") but NOT an
-- alpha/opacity one -- so we don't yet know which material variable controls
-- opacity. This captures live burning particles and exposes /fire_probe to
-- discover the alpha variable in-game. Once known, the real gt_enemy_fire_opacity
-- slider applies it right here in the wrapper. Client-side / visual only.
do
    local BURNING_STATUSES = {
        "burning", "burning_balefire", "burning_elven_magic", "burning_warpfire",
        "burning_death_critical", "burning_balefire_death_critical",
        "burning_elven_magic_death_critical", "burning_warpfire_death_critical",
    }
    local _live = {}          -- { {id=particle_id, world=world, unit=enemy_unit}, ... }
    local _MAX = 64

    -- StatusEffectTemplates is plain global data (not a class) -> wrap the
    -- function with a sentinel, not a VMF mod:hook. Applied once at load.
    local STAT = rawget(_G, "StatusEffectTemplates")
    if STAT then
        for _, name in ipairs(BURNING_STATUSES) do
            local tmpl = STAT[name]
            if tmpl and tmpl.on_applied and not tmpl._gt_fire_wrapped then
                local orig = tmpl.on_applied
                tmpl.on_applied = function(unit, reason, status_template, world)
                    local apply_data = orig(unit, reason, status_template, world)
                    local id = apply_data and apply_data.particle_id
                    if id and world then
                        _live[#_live + 1] = { id = id, world = world, unit = apply_data.attach_unit or unit }
                        while #_live > _MAX do table.remove(_live, 1) end
                    end
                    return apply_data
                end
                tmpl._gt_fire_wrapped = true
            end
        end
    end

    -- /fire_probe <cloud> <variable> <value>
    -- Pushes World.set_particles_material_scalar to every live burning-enemy fire
    -- particle so we can find which (cloud, variable) controls opacity. Light an
    -- enemy on fire, then try combos and watch which dims/fades the flames.
    -- Known tint lever: cloud="fire" variable="remap_index". Candidate opacity
    -- variables to try: intensity / alpha / opacity / emissive_intensity / fade.
    mod:command("fire_probe", "Probe burning-enemy fire material vars: /fire_probe <cloud> <variable> <value>", function(cloud, variable, value)
        cloud = (cloud and cloud ~= "" and cloud) or "fire"
        variable = (variable and variable ~= "" and variable) or "intensity"
        local v = tonumber(value)
        if v == nil then v = 0.3 end
        local applied, failed, survivors = 0, 0, {}
        for _, e in ipairs(_live) do
            if e.unit and Unit.alive(e.unit) then
                survivors[#survivors + 1] = e
                local ok = pcall(World.set_particles_material_scalar, e.world, e.id, cloud, variable, v)
                if ok then applied = applied + 1 else failed = failed + 1 end
            end
        end
        _live = survivors  -- prune dead enemies
        mod:echo("[gt_fire_probe] cloud='%s' var='%s' val=%s -> applied=%d failed=%d (live burning=%d). Watch the flames; if they changed, that's the opacity lever.",
            cloud, variable, tostring(v), applied, failed, #_live)
        mod:info("[gt_fire_probe] cloud=%s var=%s val=%s applied=%d failed=%d", cloud, variable, tostring(v), applied, failed)
    end)
end
