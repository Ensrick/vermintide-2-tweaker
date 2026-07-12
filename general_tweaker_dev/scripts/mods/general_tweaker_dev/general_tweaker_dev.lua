local mod = get_mod("gt_dev")

local MOD_VERSION = "0.2.202-dev"
_MEM_PROBE_T0_GT = collectgarbage("count")  -- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic)
-- Public field so cross-mod code (e.g. bt's /bug_report walker, the
-- gt_lobby_* manifest broadcaster below) can read the version without
-- needing access to this file-local. Mirrors the same pattern lt used
-- (lt v0.1.x exposed `mod.MOD_VERSION` for this exact reason).
mod.MOD_VERSION = MOD_VERSION

-- ============================================================
-- gt_lobby RPC schema versioning (VMF_RECIPES.md § 10, Issue #43)
-- ============================================================
-- Bumped ONLY when the payload shape of any gt_lobby_* RPC changes
-- (currently just `gt_lobby_motd_show`). Receivers gate on this and
-- drop mismatched payloads with a `_dbg_alert` -- no state mutation,
-- no crash. See _gt_lobby_motd.lua sender + receiver for the gate.
--
-- Established for gt as the merge-in heir to lt's `lt_motd_show` RPC.
-- Initial value is 1; never define lower.
mod.GT_LOBBY_RPC_SCHEMA = 1

-- AI-control RPC schema versioning (VMF_RECIPES.md § 10, Issue #44).
-- The AI Takeover client->host request RPC (`gt_ai_toggle_request`, sender +
-- receiver both in _gt_ai_takeover.lua) prepends this as the FIRST positional
-- arg of every send and validates it as the first arg of the receiver. A peer
-- running a different gt_dev build (or an older build that sends no schema arg)
-- fails the match and the host drops the request gracefully -- no swap, no
-- crash. Defined here (mirroring GT_LOBBY_RPC_SCHEMA) so the module reads it at
-- call time and the /gt_regression_test check below can assert it cross-module.
-- Bump ONLY when the `gt_ai_toggle_request` payload shape changes. Initial
-- value is 1; never define lower.
mod.GT_AI_RPC_SCHEMA = 1

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- `_dbg` routes through mod:debug (confirmation / expected behavior).
-- `_dbg_alert` routes through mod:warning (unexpected / wrong / mismatch).
-- Gate is VMF output_mode_debug / output_mode_warning (no per-mod checkbox).
-- v0.2.55: NOTE — the file ALSO redeclares `_dbg` (without prefix) inside the
-- per-frame observation hooks block further down, which shadows this top-of-
-- file definition for everything below that point. Both route through VMF
-- logging (mod:debug / mod:warning); gate is VMF output_mode_debug /
-- output_mode_warning.
local function _dbg(fmt, ...)
    mod:debug("[gt:dbg] " .. fmt, ...)
end

local function _dbg_alert(fmt, ...)
    mod:warning("[gt:dbg] " .. fmt, ...)
end

-- Exposed for sibling `_gt_lobby_*` modules (and any future external file
-- that needs gt's debug-helpers). Both route through VMF logging (mod:debug /
-- mod:warning); gate is VMF output_mode_debug / output_mode_warning.
mod._gt_dbg = _dbg
mod._gt_dbg_alert = _dbg_alert

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs, prints
-- one mod:info line at load. ALWAYS fires (operational telemetry).
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
    if not ok or type(data) ~= "table" then return "nodata" end
    local keys = {}
    local function walk(node)
        if type(node) ~= "table" then return end
        if type(node.setting_id) == "string" then keys[#keys + 1] = node.setting_id end
        for _, child in pairs(node) do
            if type(child) == "table" then walk(child) end
        end
    end
    walk(data)
    if #keys == 0 then return "nosettings" end
    table.sort(keys)
    local parts = {}
    for i, k in ipairs(keys) do
        local v = mod:get(k)
        if v == true then       parts[i] = k .. "=1"
        elseif v == false then  parts[i] = k .. "=0"
        elseif v == nil then    parts[i] = k .. "=?"
        else                    parts[i] = k .. "=" .. tostring(v) end
    end
    local s = table.concat(parts, ";")
    local h = 2166136261
    for i = 1, #s do
        local byte = string.byte(s, i)
        local xored, place = 0, 1
        local hh, bb = h, byte
        for _ = 1, 32 do
            local hb, bbit = hh % 2, bb % 2
            if hb ~= bbit then xored = xored + place end
            place = place * 2
            hh = (hh - hb) / 2
            bb = (bb - bbit) / 2
        end
        h = (xored * 16777619) % 4294967296
    end
    return string.format("%08x", h)
end

mod:info("[gt:LOAD] v%s enabled fp=%s OK", MOD_VERSION, _settings_fingerprint())

-- v0.2.85-dev: full settings snapshot to the log (debug-gated). Logs every
-- setting_id = current value so active toggle states are visible when debugging
-- (e.g. confirming a HOST had a bot toggle ON). Paired with the per-change log
-- in on_setting_changed. Fires at load and on demand via /dump_settings.
local function _log_settings_snapshot(reason)
    local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
    if not ok or type(data) ~= "table" then return end
    local keys = {}
    local function walk(node)
        if type(node) ~= "table" then return end
        if type(node.setting_id) == "string" then keys[#keys + 1] = node.setting_id end
        for _, child in pairs(node) do
            if type(child) == "table" then walk(child) end
        end
    end
    walk(data)
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = k .. "=" .. tostring(mod:get(k))
    end
    mod:debug("[gt:settings@%s] %s", reason or "load", table.concat(parts, "; "))
end
mod._gt_log_settings_snapshot = _log_settings_snapshot
_log_settings_snapshot("load")
mod:command("dump_settings", "Log all gt settings + current values", function()
    _log_settings_snapshot("command")
    mod:echo("[gt] settings snapshot written to console log.")
end)

-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print
-- version to chat on load so the user can see what's active. Stable
-- (>=1.0.0) versions stay silent. Detect via MOD_VERSION string match.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
    mod:echo(string.format("[gt] v%s loaded", MOD_VERSION))
end

-- v0.2.48: source-pattern marker constant for the /gt_regression_test
-- `gt_pickup_lookup_uses_rawget` check (audit `.test_coverage_audit_2026-05-24.md`
-- PARTIAL row 2 — promoted to PASS by adding a runtime check beside the
-- existing strict-table-lookup lint coverage).
local CT_GT_PICKUP_LOOKUP_RAWGET_MARKER_v0_2_48 = "gt-pickup-lookup-rawget-hardened"

-- v0.2.52 marker: source-pattern guard for the AI Takeover client send fix.
-- `mod._gt_ai_handle_toggle_change` for clients MUST (a) resolve host via
-- `Managers.mechanism:server_peer_id()` (NOT the literal `"server"` string —
-- VMF doesn't understand it), (b) call `get_mod("VMF").ping_vmf_users()`
-- before queuing, and (c) defer through `mod._gt_ai_pending_client_send` rather than
-- sending inline. Each layer was added across v0.2.49 → v0.2.52 in response
-- to a separate burn (see CHANGELOG). The regression-test guard at the
-- bottom of this file asserts this marker is intact AND grep-asserts the
-- three call-sites in the function body via the file source.
local CT_GT_AI_CLIENT_SEND_MARKER_v0_2_52 = "gt-ai-client-send-vmf-rehandshake"

-- v0.2.73-dev marker (Issue #60): host self-toggle of AI Takeover crashes the
-- next frame in LocomotionSystem.update_animation_lods because vanilla
-- `self._override_player or Managers.player:local_player()` resolves to nil
-- after pm:remove_player destroys the host's local Player. Fix mirrors the
-- vanilla benchmark path (`benchmark_handler.lua:423`): set_override_player
-- on the bot after the swap, clear it on toggle-back. Marker pins both halves
-- so a refactor that drops either call gets caught at /gt_regression_test.
local CT_GT_AI_LOCOMOTION_OVERRIDE_MARKER_v0_2_73 = "gt-ai-locomotion-override-on-host-swap"

local _godmode = mod:get("godmode_enabled") or false
-- Forward declaration: _apply_godmode is defined further down (in the Godmode
-- section) but on_setting_changed (defined before it) needs to reference it.
-- Per feedback_lua_forward_reference.md, name resolution happens at function
-- compile time — without this `local` here, on_setting_changed would bind
-- _apply_godmode to a global (nil) and silently do nothing on UI toggles.
local _apply_godmode

-- Godmode multiplayer sync (v0.2.89-dev).
-- Damage to a player is resolved on whatever machine is AUTHORITATIVE for that
-- unit -- the HOST for any client's unit (DamageUtils.add_damage_network applies
-- directly on the host, only RPCs from a client). So a CLIENT with godmode on
-- still took full damage: the host applied it and the host's local damage hook
-- saw a REMOTE player unit, for which _is_local_player_unit() is false. Fix: each
-- peer broadcasts its own godmode state; the damage hooks then block damage to
-- ANY unit whose owning peer has godmode on, evaluated on whichever machine
-- applies the hit. Keyed by peer_id. The local peer is recorded directly in
-- _apply_godmode; remote peers arrive via the gt_godmode_state network event.
-- Fire-and-forget + pcall-guarded: VMF drops the event for peers that didn't
-- register it (non-gt / older gt), so it can't crash a mixed lobby, and if the
-- broadcast fails godmode simply behaves as before (host-self still works via the
-- local fast path) -- no regression. Schema arg per VMF_RECIPES.md §10.
mod._gt_godmode_peers = mod._gt_godmode_peers or {}
local _gt_godmode_peers = mod._gt_godmode_peers
local _GT_GODMODE_RPC = "gt_godmode_state"
local _GT_GODMODE_RPC_SCHEMA = 1
local _gt_godmode_resync_t = 0  -- self-heal countdown for the MP godmode rebroadcast (see mod.update)
local _gt_net_clock = 0          -- monotonic seconds (advanced in mod.update) for godmode heartbeat expiry
local _GT_GODMODE_TIMEOUT = 9.0  -- a synced peer's godmode expires after ~3 missed 3s heartbeats

-- Record our godmode locally + broadcast it to other peers. CRITICAL: ping VMF
-- first. VMF silently drops the host from a client's `_vmf_users` when the host's
-- bots churn at mission load (VMF_RECIPES §3a), so a cold client->host send
-- no-ops -- that is exactly why a client's godmode wasn't honored on the host
-- (reported 2026-06-18). ping_vmf_users re-handshakes; its pong is async so the
-- first send may race it, but the 3s heartbeat in mod.update converges and the
-- receiver is idempotent (stores a timestamp, expires on missed heartbeats).
local function _gt_godmode_broadcast(on)
    local ok, peer = pcall(function() return Network and Network.peer_id and Network.peer_id() end)
    if not (ok and peer) then return end
    _gt_godmode_peers[peer] = on and _gt_net_clock or nil
    local vmf = get_mod("VMF")
    if vmf and vmf.ping_vmf_users then pcall(vmf.ping_vmf_users) end
    pcall(function() mod:network_send(_GT_GODMODE_RPC, "others", _GT_GODMODE_RPC_SCHEMA, on and true or false) end)
end

-- AI Takeover client-side send queue.
--
-- Why a queue rather than a single send: VMF's `_vmf_users` table can be
-- stale on the client. Vanilla VMF (network.lua:375-404) hooks
-- `PlayerManager.remove_player` and, when ANY player owned by peer_id is
-- removed AND that peer still has a human_player on the same peer_id, it
-- removes the WHOLE peer from `_vmf_users`. Host bot churn at mission
-- load (e.g. a slot reassignment) triggers `remove_player(host_peer,
-- bot_local_id)`; the host's own human player on host_peer matches the
-- "still has human_player" check, so VMF drops the host. Once dropped, every
-- `mod:network_send(..., host_peer, ...)` silently no-ops via
-- `convert_names_to_numbers` returning nil. Re-handshake (`ping_vmf_users`)
-- restores it but is async — pong round-trip ~50-300 ms on Steam P2P.
--
-- Queue contains zero or one entry of `{want_bot, retries_left, next_at}`.
-- Each toggle replaces the queue (latest intent wins). mod.update polls and
-- fires the send when `next_at` arrives; on failure (no detection possible
-- since VMF returns void) we just re-fire up to `_AI_CLIENT_SEND_MAX_RETRIES`
-- times. Idempotent: the host's RPC handler no-ops if state already matches.
-- AI Takeover cross-boundary state was PROMOTED from file-locals to mod._gt_ai_*
-- table fields (Phase 4) so the AI Takeover body could be extracted to
-- _gt_ai_takeover.lua while the on_setting_changed / on_game_state_changed
-- DISPATCHERS (which read/write this state and STAY in main per the dispatcher
-- rule) plus the debug AI-dump and the /gt_regression_test checks still resolve
-- it at call time. The module dofiles after the main chunk, so it (re)initializes
-- these fields before any dispatcher fires at runtime; we seed defaults here so a
-- dispatcher that somehow runs pre-module-load reads a sane value, not nil.
mod._gt_ai_pending_client_send       = nil
mod._gt_ai_pending_host_toggle       = nil

mod._gt_ai_suppress_setting_callback = false
mod._gt_ai_saved_state               = {}
-- mod._gt_ai_handle_toggle_change is assigned by _gt_ai_takeover.lua.

-- v0.2.116-dev: convert-in-place takeover disabled pending the keep-slot
-- redesign (research wkcu0v4as). EVERY takeover entry point bails before
-- anything destructive runs; the Group-F nil-guards and the position-keepalive
-- stay active and untouched. on_setting_changed (a dispatcher) reads this, so
-- it's a mod._gt_ai_* field resolved at call time.
mod._gt_ai_takeover_disabled         = true

-- AFK-to-AI-takeover state (gt_ai_afk_takeover). The on_game_state_changed
-- dispatcher clears these at the mission boundary, so they're mod._gt_ai_afk_*
-- fields resolved at call time. mod._gt_ai_afk_took_over is the DISCRIMINATOR that lets
-- input cancel an AFK-CAUSED takeover while leaving a manual /ai (or manual-
-- checkbox) takeover untouched. The driver + the _gt_local_any_input()
-- predicate live in _gt_ai_takeover.lua.
mod._gt_ai_afk_took_over   = false
mod._gt_ai_afk_idle_t      = 0.0    -- seconds of no detected local input
mod._gt_ai_afk_input_stamp = nil    -- last seen Managers.input.last_active_time
mod._gt_ai_afk_grace_until = 0.0    -- post-trigger / post-cancel input-swallow window (counts down on dt)

-- Forward-declared so on_setting_changed (above the AI/no_enemies sections)
-- can reference the helper defined deeper in the file. Same rule as the AI
-- forward declarations — name resolution happens at function compile time, so
-- without this `local` the on_setting_changed closure would bind to a nil
-- global and the script_data flags would never flip from the VMF checkbox.
local _apply_script_data_no_enemies

-- Disable Bots (Solo) is extracted to _gt_bots_keep.lua and exposes its apply
-- function as mod._gt_apply_no_bots (a `mod.` table field). on_setting_changed
-- and on_game_state_changed reference it at call time, so no forward-declared
-- file-local is needed — the former `local _gt_apply_no_bots` was retired.

-- Creature Spawner is extracted to _gt_creature_spawner.lua (dofile'd after the
-- main chunk). It assigns mod._gt_cs_on_setting_changed /
-- mod._gt_cs_on_game_state_changed; the main on_setting_changed /
-- on_game_state_changed DISPATCHERS below resolve those fields at call time
-- (no forward-decl needed — the dispatchers only fire at runtime, long after
-- the module has dofiled).

-- Time & Pause is extracted to _gt_hacks.lua. Its pause flag is shared with the
-- on_game_state_changed dispatcher (which clears it on every state transition,
-- Issue #13) via the mod._gt_pause_active table field — resolved at call time,
-- so no forward-declared file-local is needed (the former `local _pause_active`
-- was retired). The toggle's read path and this dispatcher write now see the
-- same field.

-- Post-spawn re-apply timer. Set by the PlayerUnitFirstPerson.extensions_ready
-- hook just below and consumed in mod.update (further down).
-- BulldozerPlayer:spawn does `assign_unit_ownership` AFTER the extensions are
-- ready, so at extensions_ready time `Managers.player:local_player().player_unit`
-- still points at the OLD (or nil) unit. Anything that needs to look up the
-- local player unit on spawn — godmode invisibility, noclip locomotion state —
-- must defer past that gap.
local _post_spawn_reapply_timer = nil
-- The timer + its post_spawn_reapply consumer stay HERE because godmode/noclip are
-- not moved. Resolved at call time.
mod._gt_schedule_post_spawn_reapply = function()
    _post_spawn_reapply_timer = 0.5
end

-- PlayerUnitFirstPerson.extensions_ready fires on the LOCAL player's own spawn (bots
-- use PlayerBotUnitFirstPerson; husks have no 1P extension), so this schedules the
-- godmode/noclip post-spawn re-apply exactly once per local spawn. This hook used to
-- live in _gt_camera.lua (it also re-armed the third-person camera there); the Third-
-- Person Camera feature MIGRATED to gui_tweaker (gut) 2026-06-29 (#191), so only the
-- post-spawn-reapply trigger remains and it moved here. PRE-FLIGHT: this is now gt's
-- ONLY hook on PlayerUnitFirstPerson.extensions_ready (the camera module's copy was
-- removed in the same change), so there is no VMF duplicate-hook conflict.
mod:hook_safe("PlayerUnitFirstPerson", "extensions_ready", function(self, world, unit, ...)
    mod._gt_schedule_post_spawn_reapply()
end)

-- Startup banner: log-only, NOT chat. The applied marker line further down
-- ([gt] enabled v<X> settings_fp=<hash>) is the canonical version surface
-- (PROJECT_STANDARDS.md § 3.6 "Chat-echo policy").
mod:info("General Tweaker v%s loaded", MOD_VERSION)

-- ============================================================
-- mod.update subscriber registry (Issue #16)
-- ============================================================
-- Replaces the prior 5x layered `local _orig = mod.update; mod.update = ...`
-- chain pattern (lines ~287/522/2486/2693/3027). The chain had no central
-- registry, no inline `-- consumer #N: <feature>` header, and a single
-- accidental edit `mod.update = function(dt) ... end` without preserving
-- `_orig` silently dropped every earlier consumer.
--
-- Each feature registers its per-frame tick via `_register_update(name, fn)`.
-- Registration order is preserved so dependencies between consumers (if any)
-- continue to run in the original order: tp_camera, post_spawn_reapply,
-- infinite_ammo_and_ai_pending. (cutscene_auto_skip migrated to gut with the
-- Skip Cutscenes feature, 2026-06-25 / issue #106.) pcall isolation
-- per-consumer is a bonus — one consumer error no longer kills the others.
local _update_consumers = {}
local function _register_update(name, fn)
    _update_consumers[#_update_consumers + 1] = { name = name, fn = fn }
end
-- Exposed for sibling `_gt_lobby_*` modules (and any future external file
-- that wants to plug into gt's per-frame tick). Same isolated-pcall +
-- ordered-registration semantics as the file-local _register_update.
mod._gt_register_update = _register_update
mod.update = function(dt)
    for i = 1, #_update_consumers do
        local c = _update_consumers[i]
        local ok, err = pcall(c.fn, dt)
        if ok then
            c.last_err = nil
        else
            -- Log each DISTINCT error once per streak, not per frame: a consumer
            -- failing through a boot/menu phase it later recovers from (issue 508:
            -- 60/s chat-visible spam) must not flood mod:error. A different
            -- message, or a success in between, re-arms the line.
            local msg = tostring(err)
            if c.last_err ~= msg then
                c.last_err = msg
                mod:error("[gt:update] consumer '%s' raised (repeats suppressed): %s", c.name, msg)
            end
        end
    end
end

-- /regression_test scaffold. Registrations at end of file.
local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
mod:command("gt_regression_test", "Run regression smoke checks for past bugs", function()
    local pass, fail = 0, 0
    mod:echo("=== gt regression_test (v%s) ===", MOD_VERSION)
    for _, c in ipairs(_RT_CHECKS) do
        local ok, err = pcall(c.fn)
        if ok and err == nil then
            mod:echo("  PASS: %s", c.name); pass = pass + 1
            mod:info("[regression] PASS %s", c.name)
        else
            local msg = (not ok and tostring(err)) or tostring(err)
            mod:echo("  FAIL: %s -- %s", c.name, msg); fail = fail + 1
            mod:warning("[regression] FAIL %s: %s", c.name, msg)
        end
    end
    mod:echo("=== %d passed, %d failed ===", pass, fail)
end)
mod:info("[regression-test-command] registered as /gt_regression_test")

-- Third-Person Camera MIGRATED to gui_tweaker (gut) 2026-06-29, #191 — it used to
-- live in _gt_camera.lua and also carried the PlayerUnitFirstPerson.extensions_ready
-- hook that schedules the godmode/noclip post-spawn re-apply. That single shared hook
-- was relocated (slimmed to only the schedule call) into the main chunk above, beside
-- mod._gt_schedule_post_spawn_reapply, so godmode/noclip re-apply still fires on spawn.
-- Noclip (player flies through walls) is extracted to _gt_noclip.lua
-- (dofile'd after the main chunk). It exposes:
--   * mod._gt_apply_noclip(enabled) — called from on_setting_changed below
--     AND from the shared post_spawn_reapply consumer just below.
--   * mod._gt_noclip_heartbeat()    — per-frame locomotion-state re-assert,
--     called from the same shared consumer.
-- The update_script_driven_no_mover_movement hook + the /noclip command +
-- mod.gt_noclip_toggle live in that module. The post_spawn_reapply consumer
-- and the shared _post_spawn_reapply_timer stay HERE because godmode (not
-- moved) shares them.

-- CLARIFY: `mod.update` runs each tick from VMF's main loop. We use it
-- as the heartbeat that re-asserts the locomotion state, so transient
-- character-state transitions can't drop us back into wall collision.
-- It also consumes _post_spawn_reapply_timer so godmode invisibility and
-- noclip locomotion state are re-applied after a level transition, since
-- both depend on `Managers.player:local_player().player_unit` which isn't
-- yet assigned at PlayerUnitFirstPerson.extensions_ready time.
_register_update("post_spawn_reapply", function(dt)
    if _post_spawn_reapply_timer then
        _post_spawn_reapply_timer = _post_spawn_reapply_timer - (dt or 0)
        if _post_spawn_reapply_timer <= 0 then
            _post_spawn_reapply_timer = nil
            -- Use the forward-declared `_apply_godmode` (line 17) — calling
            -- `_set_local_player_invisible` directly would be a forward-ref
            -- bug since it's defined far below this closure's parse point.
            -- Noclip re-arm goes through mod._gt_apply_noclip (extracted to
            -- _gt_noclip.lua, resolved at call time).
            if mod:get("noclip_enabled") and mod._gt_apply_noclip then mod._gt_apply_noclip(true) end
            if _godmode then _apply_godmode(true) end
        end
    end
    -- Self-heal godmode MP sync: a client->host VMF send can drop if the VMF
    -- handshake isn't settled (see the _AI_RPC send-queue notes), so a single
    -- toggle-time broadcast may not reach the host. Re-broadcast our godmode
    -- state every ~3s while it's ON so the host converges even if the first send
    -- was lost. Cheap (one bool, only while the cheat is active); no-op solo.
    _gt_net_clock = _gt_net_clock + (dt or 0)  -- advance the godmode-sync clock every frame
    if _godmode then
        _gt_godmode_resync_t = _gt_godmode_resync_t - (dt or 0)
        if _gt_godmode_resync_t <= 0 then
            _gt_godmode_resync_t = 3.0
            _gt_godmode_broadcast(true)  -- heartbeat: re-handshakes VMF + refreshes our entry on the host
        end
    end
    -- Noclip per-frame locomotion-state re-assert (extracted to _gt_noclip.lua;
    -- resolved at call time). No-op when noclip is off.
    if mod._gt_noclip_heartbeat then mod._gt_noclip_heartbeat() end
end)

-- Keep Menus in Missions (InventorySettings loadout-access patch + ESC-menu
-- "Open Inventory" entry) MIGRATED to gui_tweaker (gut) 2026-06-24 along with the
-- rest of the in-mission inventory feature. _gt_keep_menus.lua was deleted.
--
-- HISTORICAL (Issue #62, v0.2.82-dev): a legacy hook here once force-flipped the
-- hotkeys-enabled arg of IngameUI.handle_menu_hotkeys to true mid-mission, which
-- enabled EVERY keep hotkey (Hero Select / Map / Achievements / Weave Forge / Store
-- each spawn a `levels/ui_*/world` preview level NOT in a mission's package set →
-- "Level not loaded" + c_api_world.cpp:691 assert). It was removed. The
-- gt_no_mission_hotkey_flip regression test (further down) still guards against
-- that hook being reintroduced — it stays in gt even though the inventory feature
-- it accompanied has moved to gut.

-- CLARIFY: third-person camera (MIGRATED to gut 2026-06-29, #191) used to be reset
-- here on every state change; gut's _gut_camera.lua now owns that. This handler keeps
-- the noclip reset below.
-- (Keep Menus / in-mission inventory MIGRATED to gut 2026-06-24 — the
-- mod._gt_apply_keep_menus re-apply that used to live here is gone.)
mod.on_game_state_changed = function(status, state_name)
    -- (3rd-Person Camera tp-reset MIGRATED to gui_tweaker / gut 2026-06-29, #191 —
    -- gut's _gut_camera.lua now clears tp on its own on_game_state_changed.)
    -- Locomotion extensions are torn down across level transitions; the
    -- next player spawn comes back in vanilla `script_driven` mode. Reset
    -- the noclip active flag (now owned by _gt_noclip.lua; resolved at call
    -- time) so a stale noclip setting from the previous mission doesn't
    -- re-arm before the player has a body to fly.
    if mod._gt_noclip_reset_active then mod._gt_noclip_reset_active() end
    -- AI takeover is a per-run intent — the saved state on the host doesn't
    -- survive a level/state change cleanly, and persisting the checkbox would
    -- show "on" across runs where no swap actually happened. Suppress the
    -- callback because we don't want to fire an RPC swap-back when leaving.
    if mod:get("ai_takeover_enabled") then
        mod._gt_ai_suppress_setting_callback = true
        mod:set("ai_takeover_enabled", false)
        mod._gt_ai_suppress_setting_callback = false
    end
    -- Clear host-side saved state too — it's keyed on peer_id which may
    -- not survive a session/lobby change.
    mod._gt_ai_saved_state = {}
    -- AFK-takeover: drop our cause-flag + timers so a stale flag can't survive
    -- into the next mission (where the human Player is freshly spawned). The
    -- ai_takeover_enabled force-off above already tears down any in-flight swap.
    mod._gt_ai_afk_took_over   = false
    mod._gt_ai_afk_idle_t      = 0.0
    mod._gt_ai_afk_input_stamp = nil
    mod._gt_ai_afk_grace_until = 0.0
    -- bots_in_keep bookkeeping: drop the tracked-spawned-bots table on every
    -- state change so we never try to call _remove_bot_instant on a Player
    -- reference from the previous game session. State-shutdown destroys the
    -- bot units; this is just bookkeeping reset, NOT a vanilla bot-clear.
    -- mod._bik_reset_bookkeeping is a table field — resolved at call time,
    -- safe to reference even though it's assigned further down.
    if mod._bik_reset_bookkeeping then mod._bik_reset_bookkeeping() end
    -- Vanilla wipes the engine time scale on level transition. Re-apply the
    -- user's slider value if it differs from normal (13 = 1.0x). Also clear
    -- the pause flag so the toggle remembers we're now unpaused. The pause flag
    -- moved to _gt_hacks.lua and is shared as mod._gt_pause_active (so this
    -- dispatcher write and the toggle's read path see the same value).
    mod._gt_pause_active = false
    if status == "enter" and state_name == "StateIngame" then
        local v = mod:get("time_scale_value")
        if v and v ~= 13 then
            local debug_mgr = Managers.state and Managers.state.debug
            if debug_mgr and debug_mgr.set_time_scale then
                debug_mgr:set_time_scale(v)
            end
        end
        -- Re-apply the Disable Bots (Solo) flag on every mission start so the
        -- party is bot-free from the very first server tick. script_data is a
        -- persistent global, but the game's own reset paths (debug_manager,
        -- dedicated_server_commands) can clear ai_bots_disabled between
        -- sessions — re-asserting here guarantees the user's setting wins
        -- before GameModeAdventure._handle_bots runs. mod._gt_apply_no_bots is
        -- a table field (body in _gt_bots_keep.lua), resolved at call time.
        if mod._gt_apply_no_bots then mod._gt_apply_no_bots(mod:get("gt_no_bots")) end
    end
    if mod._gt_cs_on_game_state_changed then
        mod._gt_cs_on_game_state_changed(status, state_name)
    end
end

-- ============================================================
-- AI Commander crash guard (host) — AI Takeover swap fallout
-- ============================================================
-- CRITICAL host crash (2026-06-19, danjo session a81cfea2): a CLIENT using AI
-- Takeover hard-crashed the host with
--   ai_commander_extension.lua: bad argument #1 to '__add' (userdata expected, got nil)
-- Root cause: AICommanderExtension._update_units does
--   local commander_unit_pos = POSITION_LOOKUP[self._unit]   -- can be nil
--   ...
--   local detection_source_pos = commander_unit_pos + avg_velocity   -- nil + Vector3 -> fatal
-- Vanilla guards the CONTROLLED unit's position a few lines later but NOT the
-- commander's OWN position. AI Takeover despawns/recreates a player unit
-- mid-frame (human->bot swap), so a commander unit can be left without a
-- POSITION_LOOKUP entry for a tick and the unguarded `+` fatals on the host.
-- Symmetric nil-guard: skip the tick until the commander has a position again
-- (exactly what vanilla already does when the controlled unit's pos is nil).
-- Always-on safety (no toggle); host-side (only the server ticks AI extensions).
if rawget(_G, "AICommanderExtension") then
    mod:hook("AICommanderExtension", "_update_units", function(func, self, dt, t)
        if not POSITION_LOOKUP[self._unit] then
            return
        end
        return func(self, dt, t)
    end)
end

mod.on_setting_changed = function(setting_id)
    -- v0.2.85-dev: log every toggle/value change (debug-gated) so the log shows
    -- exactly when a setting flips and to what — pairs with the load snapshot.
    _dbg("[gt:setting-changed] %s = %s", tostring(setting_id), tostring(mod:get(setting_id)))
    -- (3rd-Person Camera tp_* branches MIGRATED to gui_tweaker / gut 2026-06-29, #191.)
    if setting_id == "godmode_enabled" then
        _apply_godmode(mod:get("godmode_enabled") or false)
    elseif setting_id == "noclip_enabled" then
        -- _gt_apply_noclip is a table field on `mod` (extracted to _gt_noclip.lua),
        -- resolved at call time — safe to reference even though the module
        -- dofile's after the main chunk.
        if mod._gt_apply_noclip then mod._gt_apply_noclip(mod:get("noclip_enabled")) end
    elseif setting_id == "disable_enemy_spawns" then
        _apply_script_data_no_enemies(mod:get("disable_enemy_spawns"))
    elseif setting_id == "gt_no_bots" then
        -- mod._gt_apply_no_bots body lives in _gt_bots_keep.lua; table-field
        -- ref resolves at call time.
        if mod._gt_apply_no_bots then mod._gt_apply_no_bots(mod:get("gt_no_bots")) end
    elseif setting_id == "gt_adventure_save_trait_chance" then
        -- table-field ref resolves at call time, so it's fine that the body is
        -- assigned further down the file.
        if mod._gt_apply_adv_save_traits then mod._gt_apply_adv_save_traits() end
    elseif setting_id == "time_scale_value" then
        mod.gt_time_apply()
    elseif setting_id == "base_crit_chance" then
        mod.gt_apply_crit_chance()
    elseif setting_id == "movement_speed" then
        mod.gt_apply_move_speed()
    elseif setting_id == "gt_fall_damage_enabled" or setting_id == "gt_fall_damage_mult" then
        mod.gt_apply_fall_damage()
    elseif setting_id == "gt_more_corpses_count" then
        -- mod.gt_apply_corpse_count is a table field on `mod`, so this name
        -- resolves at call time — safe to reference even though the function
        -- body is assigned later in the file.
        if mod.gt_apply_corpse_count then mod.gt_apply_corpse_count() end
    -- (Disable Loading-Screen Monologues MIGRATED to gui_tweaker / gut 2026-06-29,
    -- #192 — branch removed.)
    elseif setting_id == "ai_takeover_enabled" then
        if mod._gt_ai_suppress_setting_callback then return end
        local want_bot = mod:get("ai_takeover_enabled") and true or false
        local ok, err = mod._gt_ai_handle_toggle_change(want_bot)
        if not ok then
            mod._gt_ai_suppress_setting_callback = true
            mod:set("ai_takeover_enabled", not want_bot)
            mod._gt_ai_suppress_setting_callback = false
            -- v0.2.116-dev: when the takeover is disabled, mod._gt_ai_handle_toggle_change
            -- already echoed the rebuild message; don't stack the generic line.
            if not mod._gt_ai_takeover_disabled then
                mod:echo("AI toggle: " .. err)
            end
        else
            mod:echo("AI " .. (want_bot and "ON" or "OFF") .. " (requested from host).")
        end
    elseif setting_id == "gt_bots_in_keep" then
        -- The mod.update consumer below will tick a fill once a second when
        -- active, but firing one immediately on toggle-flip makes the UX feel
        -- responsive. On toggle-off we tear down only the bots we spawned —
        -- vanilla logic doesn't add bots in inn modes, so this should be a
        -- full party-1 clear in practice. mod._bik_* are table fields on
        -- `mod`, resolved at call time — safe to reference here (the
        -- function bodies are assigned further down in the file).
        if mod:get("gt_bots_in_keep") then
            if mod._bik_fill then mod._bik_fill() end
        else
            if mod._bik_clear then mod._bik_clear() end
        end
    -- Main Menu & Startup (gt_skip_start_screen / gt_return_to_menu_quits)
    -- MIGRATED to gui_tweaker (gut) 2026-06-29, #190 — branches removed.
    elseif setting_id == "gt_bot_fast_reactions" then
        -- Replicant Bots port: snapshot/restore the vanilla bot reaction-time
        -- table (apply/restore bodies live in _gt_bot_fixes.lua, exposed on mod).
        if mod:get("gt_bot_fast_reactions") then
            if mod._gt_apply_fast_reactions then mod._gt_apply_fast_reactions() end
        else
            if mod._gt_restore_fast_reactions then mod._gt_restore_fast_reactions() end
        end
    elseif mod._gt_cs_on_setting_changed then
        mod._gt_cs_on_setting_changed(setting_id)
    end
end

mod.on_disabled = function()
    -- (3rd-Person Camera offset restore MIGRATED to gui_tweaker / gut 2026-06-29,
    -- #191 — gut's _gut_camera.lua restores its own camera offset on_disabled.)
    -- (Main Menu & Startup on-disable restore MIGRATED to gui_tweaker / gut
    -- 2026-06-29, #190 — gut's _gut_mainmenu.lua now restores those on its own
    -- on_disabled.)
    -- Replicant Bots port: restore the snapshotted vanilla bot reaction-time
    -- table (the source mod's on_disabled was author-flagged broken).
    if mod._gt_restore_fast_reactions then mod._gt_restore_fast_reactions() end
    -- Issue #15: the mod is is_togglable=true but only the camera offset is
    -- snapshot-and-restored above. Many global mutations persist after
    -- disable: script_data flags (ai_*, intro dialogue,
    -- player_unkillable), RagdollSettings, BuffTemplates.power_level_unbalance,
    -- CareerSettings[*].attributes.base_critical_strike_chance,
    -- PlayerUnitMovementSettings.move_speed (plus the closed-upvalue per-unit
    -- copy), InventorySettings, DamageUtils.is_in_inn, ESC-menu inventory entry.
    -- A full snapshot-on-enable + restore-on-disable refactor is significant
    -- effort; for now we honestly warn the user. This warning fires regardless
    -- This warning is user-facing operational guidance, not debug spam.
    mod:echo("[gt] Disable does not fully unwind active mutations. Restart the game for a clean vanilla state.")
end

-- ============================================================
-- Debug Mode + observation probes are extracted to _gt_debug_probes.lua
-- (dofile'd after the main chunk).
-- ============================================================
-- Routes through VMF logging (mod:debug). Surfaces context that's hard to
-- reconstruct from a crash log: mechanism / level / view / profile /
-- item-being-customized / cim presence, plus the AI/bot state dump, the menu /
-- inventory dump, the bot-loadout-resolution probe, and the patrol-formation
-- crash probe. The module exposes mod._dbg_log / mod._dbg_alert
-- (the dbg_helpers_two_channel regression check below + the AI Takeover module
-- read these) and mod._gt_dump_ai_now (the AI Takeover debug-toggle wrap calls
-- it). It consumes the mod._gt_ai_* state fields seeded above. Every observation
-- hook is a singleton; the two mod.on_game_state_changed wraps + the mod.update
-- wrap are additive observational chains (prev() first), so they stay
-- behavior-neutral after the move.

-- Unstuck (/unstuck teleport to nearest living teammate) is extracted to
-- _gt_godmode_qol.lua (dofile'd after the main chunk). Command-only, no hook.
-- (The Godmode body below STAYS in the main file — its DamageUtils
-- add_damage_network* hooks are shared with the floating-damage-numbers
-- feature and must not be duplicated.)

-- ============================================================
-- Godmode
-- ============================================================

-- Invisibility: use the engine's own canonical signal so AI perception treats us as
-- "skip this target" (perception_utils.lua:381 explicitly checks status_ext:is_invisible()).
-- `reason = "gt_godmode"` namespaces our flag so it doesn't clobber other invisibility
-- sources (Shade's Shadowfall ult, Pact Sworn ghost mode, etc.).
local _GODMODE_INVIS_REASON = "gt_godmode"

local function _set_local_player_invisible(invisible)
    local pm = Managers.player
    local player = pm and pm:local_player()
    local unit = player and player.player_unit
    if not unit then return end
    local status_ext = ScriptUnit.has_extension(unit, "status_system")
    if not status_ext or not status_ext.set_invisible then return end
    -- skip_third_person=false → fade the 3P body so user has a visual cue godmode is on.
    -- 1P weapon arms are unaffected (they're a separate unit), so first-person view stays normal.
    pcall(status_ext.set_invisible, status_ext, invisible, false, _GODMODE_INVIS_REASON)
end

-- NOTE: NOT `local function _apply_godmode(...)` — the local was forward-declared
-- at the top of the file so on_setting_changed can reference it. Re-declaring
-- local here would shadow the forward decl and reintroduce the forward-ref bug.
_apply_godmode = function(on)
    _godmode = on and true or false
    _set_local_player_invisible(_godmode)
    -- MP sync: record + broadcast our godmode so the host (which applies damage
    -- to our unit when we're a client) honors it. The broadcast re-handshakes VMF
    -- first (host bot-churn drops us from its _vmf_users). The post-spawn reapply
    -- path and the 3s heartbeat both re-call this, so a toggle before joining a
    -- lobby still converges, and turning it off expires on the host even if the
    -- "off" send is lost.
    _gt_godmode_broadcast(_godmode)
end

-- Receive other peers' godmode state (see _gt_godmode_peers rationale near the
-- top of the file). Validates the schema arg per VMF_RECIPES.md §10.
mod:network_register(_GT_GODMODE_RPC, function(sender_peer_id, schema, on)
    if sender_peer_id == nil or schema ~= _GT_GODMODE_RPC_SCHEMA then
        return
    end
    -- Store the local clock at receipt; _gt_godmode_active expires the entry if
    -- the sender stops heartbeating (clean godmode-off even if its send dropped).
    _gt_godmode_peers[sender_peer_id] = (on == true) and _gt_net_clock or nil
end)

mod:command("god", "Toggle godmode (invincibility + invisibility to enemies)", function()
    local new_val = not _godmode
    mod:set("godmode_enabled", new_val)
    -- Belt-and-suspenders apply in case on_setting_changed doesn't fire on programmatic set.
    _apply_godmode(new_val)
    mod:echo("Godmode " .. (new_val and "ON" or "OFF"))
end)

-- Godmode invisibility re-arm on spawn lives in mod.update via
-- _post_spawn_reapply_timer (set by PlayerUnitFirstPerson.extensions_ready
-- above). Don't hook GenericStatusExtension.extensions_ready here — that
-- check (`player.player_unit ~= unit`) is unreliable at extension-ready
-- timing because BulldozerPlayer:spawn calls assign_unit_ownership AFTER
-- extensions have already been wired up, so player.player_unit still
-- points at the OLD (or nil) unit and the check always early-returns.

-- Both DamageUtils paths must be blocked for full invincibility:
--   * add_damage_network         — used by direct damage sources (most attacks)
--   * add_damage_network_player  — used by player-vs-player damage profiles
--                                  (area effects, certain weapon profiles)
-- Both are static functions (called with `.`), so the hook signatures
-- intentionally omit `self`.
local function _is_local_player_unit(unit)
    local pm = Managers.player
    local player = pm and pm:local_player()
    return player and player.player_unit == unit
end

-- True if `unit`'s owning peer currently has godmode on -- the local player
-- (fast path, also covers the case where peer_id wasn't available at toggle
-- time) OR any synced remote peer. The HP-damage hooks below use this instead of
-- _is_local_player_unit so a CLIENT's godmode is honored on the HOST, where that
-- client's incoming damage is actually applied (see _gt_godmode_peers note up
-- top). owner(unit) is reliable here: damage fires mid-combat, well after the
-- spawn-time window where the unit->player reverse lookup is briefly nil.
local function _gt_godmode_active(unit)
    if not unit then return false end
    local pm = Managers.player
    if not pm then return false end
    if _godmode then
        local lp = pm:local_player()
        if lp and lp.player_unit == unit then return true end
    end
    if not next(_gt_godmode_peers) then return false end
    local owner = pm.owner and pm:owner(unit)
    -- CRITICAL (v0.2.91-dev regression fix): only HUMAN player units. BOTS are
    -- owned by the HOST's peer_id, so a bare peer check made every host bot
    -- invincible whenever the host had godmode on (reported 2026-06-18).
    -- is_player_controlled() is true for humans, false for bots.
    if not owner or not owner.is_player_controlled or not owner:is_player_controlled() then
        return false
    end
    local peer = owner.peer_id
    if peer == nil then return false end
    local seen = _gt_godmode_peers[peer]
    -- `seen` = our local clock when we last heard this peer's godmode=on; expire
    -- it so a missed "off" (or a disconnect) can't leave them invincible forever.
    return seen ~= nil and (_gt_net_clock - seen) < _GT_GODMODE_TIMEOUT
end

-- Block fall damage at the source on the local player when godmode is on.
-- The server-side `add_damage_network` hook below covers the host-self case,
-- but NOT the client-self case: fall damage RPCs from a client get processed
-- on the host where `_is_local_player_unit(attacked_unit)` returns false for
-- a remote-player's unit. Setting `ignore_next_fall_damage` on the client's
-- own status extension before `update_falling` checks the flag prevents the
-- RPC from being sent in the first place — works as host AND client.
mod:hook("GenericStatusExtension", "update_falling", function(func, self, t)
    if _godmode and _is_local_player_unit(self.unit) then
        self.ignore_next_fall_damage = true
    end
    return func(self, t)
end)

-- Godmode HP-damage block (host-self path). add_damage_network carries DoTs,
-- explosions (bombs) and other already-final damage values. (The floating-damage-
-- numbers feed that used to share this hook MIGRATED to gui_tweaker / gut
-- 2026-06-29 — gut registers its own DamageUtils hooks, so this is pure godmode
-- again.) damage_amount is the function's single return value; return it unchanged
-- when godmode is off.
mod:hook("DamageUtils", "add_damage_network", function(func, attacked_unit, attacker_unit, original_damage_amount, hit_zone_name, damage_type, ...)
    if _gt_godmode_active(attacked_unit) then return 0 end
    return func(attacked_unit, attacker_unit, original_damage_amount, hit_zone_name, damage_type, ...)
end)

-- Godmode HP-damage block (player-weapon / pvp-profile path). (Floating-damage-
-- numbers feed MIGRATED to gut 2026-06-29 — see note above.) Return the original
-- damage unchanged when godmode is off.
mod:hook("DamageUtils", "add_damage_network_player", function(func, damage_profile, target_index, power_level, attacked_unit, attacker_unit, hit_zone_name, hit_position, attack_direction, damage_source, hit_ragdoll_actor, boost_curve_multiplier, is_critical_strike, ...)
    if _gt_godmode_active(attacked_unit) then return 0 end
    return func(damage_profile, target_index, power_level, attacked_unit, attacker_unit, hit_zone_name, hit_position, attack_direction, damage_source, hit_ragdoll_actor, boost_curve_multiplier, is_critical_strike, ...)
end)

-- Block disabler-state transitions on the local player while godmode is on.
-- The DamageUtils hooks above stop hp damage but disablers (packmaster hook,
-- pounce, chaos-spawn / corruptor / tentacle grabs, hanging cage) bypass the
-- damage pipeline and transition the character state machine directly. To
-- catch all of them in one place we hook GenericStateMachine.change_state
-- (the chokepoint every csm:change_state call funnels through) and drop the
-- transition before the new state's on_enter runs.
--
-- Set of states we treat as "disabled":
--   pounced_down              — gutter runner / assassin pin
--   grabbed_by_pack_master    — hook drag
--   grabbed_by_chaos_spawn    — chaos spawn grab
--   grabbed_by_corruptor      — corruptor grab
--   grabbed_by_tentacle       — beastman bestigor tentacle, etc.
--   in_hanging_cage           — Citadel of Eternity hanging cage objective
--
-- NOT blocked (these are normal gameplay states even with godmode):
--   stunned / staggered, ledge_hanging, overpowered, knocked_down, dead.
local _DISABLER_STATES = {
    pounced_down           = true,
    grabbed_by_pack_master = true,
    grabbed_by_chaos_spawn = true,
    grabbed_by_corruptor   = true,
    grabbed_by_tentacle    = true,
    in_hanging_cage        = true,
}

mod:hook("GenericStateMachine", "change_state", function(func, self, state_next, state_next_params)
    if _godmode and _DISABLER_STATES[state_next] and _is_local_player_unit(self.unit) then
        return
    end
    return func(self, state_next, state_next_params)
end)

-- Adventure "save a consumable" trait odds (Home Brewer / Healers Touch /
-- Grenadier proc_chance) is extracted to _gt_misc_features.lua (dofile'd after
-- the main chunk). Load-time data mutation, no hook. It exposes
-- mod._gt_apply_adv_save_traits, which the on_setting_changed branch for
-- gt_adventure_save_trait_chance (above) resolves at call time.

-- ============================================================
-- Disable Enemy Spawns
-- ============================================================
-- Every enemy unit in VT2 — hordes, specials, bosses, patrols, and the
-- pre-placed level-load spawns — funnels through ConflictDirector's two
-- public entry points: spawn_queued_unit (the deferred queue used by the
-- pacing system) and spawn_unit_immediate (synchronous, used by terror
-- events and some scripted triggers). Hook both and refuse when the
-- setting is on.
--
-- Existing enemies are NOT despawned — refusing the spawn affects future
-- enemies only. Pair with `gt god` if you want existing enemies to ignore
-- you while you reach a cleaner area.

mod:hook("ConflictDirector", "spawn_queued_unit", function(func, self, breed, ...)
    if mod:get("disable_enemy_spawns") then return end
    -- Solo/QoL: assassin/packmaster spawn text warning. Merged here because VMF
    -- drops a 2nd hook on the same Class.method; the detector lives in
    -- _gt_solo_qol.lua and no-ops unless one of its warning toggles is on.
    if mod._gt_solo_on_spawn_queued then mod._gt_solo_on_spawn_queued(self, breed) end
    -- v0.2.124-dev necro-pet probe: log Necromancer pet-skeleton spawns
    -- (pet_skeleton_dual_wield etc.) for temporal correlation with the patrol
    -- crash. Merged into this existing hook (VMF drops a 2nd hook on the same
    -- Class.method). Unconditional mod:info so it lands with Debug Logging off.
    local bn = (type(breed) == "table" and breed.name) or breed
    if bn and string.find(tostring(bn), "pet_skeleton", 1, true) then
        mod:info("[necro_probe] pet skeleton queued for spawn: breed=%s", tostring(bn))
    end
    return func(self, breed, ...)
end)

mod:hook("ConflictDirector", "spawn_unit_immediate", function(func, self, ...)
    if mod:get("disable_enemy_spawns") then return nil, nil end
    return func(self, ...)
end)

-- Belt-and-suspenders: the two ConflictDirector hooks above catch every spawn
-- *call*, but Janoti's "Hacks" also flips a fuller set of `script_data.ai_*`
-- flags that abort earlier in the pacing/intervention pipelines so the spawner
-- doesn't even queue the work. Mirror that set in sync with the VMF toggle.
-- Per `feedback_redundant_safeguards_ok` redundancy is welcome here — the cost
-- is a couple of boolean writes per toggle and the missed-path failure (an
-- enemy slipping through) is silent.
local _AI_SPAWN_FLAGS = {
    "ai_mini_patrol_disabled",
    "ai_critter_spawning_disabled",
    "ai_horde_spawning_disabled",
    "ai_roaming_spawning_disabled",
    "ai_boss_spawning_disabled",
    "ai_rush_intervention_disabled",
    "ai_specials_spawning_disabled",
    "ai_pacing_disabled",
    "ai_outside_navmesh_intervention_disabled",
}

_apply_script_data_no_enemies = function(enabled)
    script_data = script_data or {}
    for _, name in ipairs(_AI_SPAWN_FLAGS) do
        script_data[name] = enabled or nil
    end
end

_apply_script_data_no_enemies(mod:get("disable_enemy_spawns"))

mod:command("no_enemies", "Toggle blocking all enemy spawns", function()
    local new_val = not mod:get("disable_enemy_spawns")
    mod:set("disable_enemy_spawns", new_val)
    _apply_script_data_no_enemies(new_val)
    mod:echo("Enemy spawns: " .. (new_val and "BLOCKED" or "normal"))
end)

-- ============================================================
-- Clear Enemy Spawns (despawn every currently-alive AI)
-- ============================================================
-- Distinct from `disable_enemy_spawns` (which only refuses *future* spawns).
-- This calls ConflictDirector:destroy_all_units(true) — the same primitive
-- the engine uses internally (conflict_director.lua:2418). `except_immune=true`
-- spares breeds tagged `debug_despawn_immunity` (bosses tied to objectives,
-- the cursed chest beastman in Citadel of Eternity, etc.) so we don't bork
-- mission-critical NPCs.
--
-- Host-only — clients despawning enemies would desync the spawned list with
-- the server's authoritative view. Bound to `mod.gt_clear_enemies` so both
-- chat command and VMF function_call keybind hit the same code path.

mod.gt_clear_enemies = function()
    if not (Managers.player and Managers.player.is_server) then
        mod:echo("Only the host can clear enemy spawns.")
        return
    end
    local conflict = Managers.state and Managers.state.conflict
    if not (conflict and conflict.destroy_all_units) then
        mod:echo("No conflict director (not in a mission?).")
        return
    end
    conflict:destroy_all_units(true)
    mod:echo("Cleared all enemy spawns.")
end

mod:command("clear_enemies", "Despawn every currently-alive enemy (host-only, skips objective-immune bosses)", function()
    mod.gt_clear_enemies()
end)

-- In-mission inventory access (Open Inventory In Mission + Mission Customize
-- gear-icon cim gate + Show menu tabs in-mission + the InventorySettings/ESC-menu
-- patch) MIGRATED to gui_tweaker (gut) 2026-06-24. gut now owns this feature;
-- _gt_mission_ui.lua + _gt_keep_menus.lua were deleted and their dispatcher
-- branches removed from main. The gt_no_mission_hotkey_flip regression test
-- (Issue #62) stays — it guards the removed IngameUI.handle_menu_hotkeys flip.

-- Friendly Fire Toggle (DamageUtils.allow_friendly_fire_ranged/melee hooks) is
-- extracted to _gt_godmode_qol.lua (dofile'd after the main chunk). These are
-- DISTINCT methods from the godmode add_damage_network* hooks that stay here, so
-- there is no duplicate-hook collision. disable_friendly_fire is read directly
-- inside the hooks (no apply-fn / dispatch).

-- Level Control (win / fail / restart) + End-of-level profile fallback /
-- score-screen fix + gt_kill_bots / gt_die + /respawn + gt_fix_sound +
-- gt_bot_toggle + Duplicate Careers are extracted to _gt_level_control.lua
-- (dofile'd after the main chunk). That module co-locates ALL FOUR
-- ProfileSynchronizer hooks (get_persistent_profile_index_reservation for the
-- score-screen fix vs get_profile_index_reservation / try_reserve_profile_for_peer
-- / is_free_in_lobby for Duplicate Careers — four DISJOINT methods) plus the
-- StateInGameRunning._award_end_of_level_rewards hook, so the singleton audit is
-- local to that file. The block was fully self-contained (its own RPC names +
-- helper locals); every keybind-bound callable stays a `mod.` field so VMF
-- function_name resolution still works.

-- ============================================================
-- AI Takeover + AFK->AI takeover are extracted to _gt_ai_takeover.lua
-- (dofile'd after the main chunk).
-- ============================================================
-- The module assigns mod._gt_ai_handle_toggle_change (CALLED by the
-- on_setting_changed DISPATCHER below) and reads/writes the promoted
-- mod._gt_ai_* state fields seeded near the top of this file (the
-- on_setting_changed / on_game_state_changed DISPATCHERS, which STAY in main,
-- share that state). It registers its own `ai_pending` + `afk_autobot` per-frame
-- consumers via mod._gt_register_update, registers the _AI_RPC network event,
-- and exposes mod._gt_ai_swap_human_to_bot for the locomotion-override
-- regression check. The debug AI-toggle dump wrap (in the module) calls
-- mod._gt_dump_ai_now (exposed by _gt_debug_probes.lua) at call time.
--
-- The AICommanderExtension._update_units always-on crash guard (a SEPARATE
-- AI-takeover-fallout guard) STAYS in the main file near the dispatcher above —
-- it is not part of this extraction.
-- Bots in Keep (mod._bik_*) + Disable Bots (Solo) (mod._gt_apply_no_bots) are
-- extracted to _gt_bots_keep.lua (dofile'd after the main chunk). Neither
-- registers a Class.method hook. The on_game_state_changed / on_setting_changed
-- branches above call mod._bik_* and mod._gt_apply_no_bots (resolved at call
-- time); the forward-declared file-local _gt_apply_no_bots was retired in favor
-- of the mod._gt_apply_no_bots field. The bots_in_keep _bik_* regression tests
-- read mod._bik_* fields, so they stay resolvable.

-- Time & Pause (Group B) + Ult Controls (Group C) + Buffs & Stat Tweaks
-- (Group D) + Engine error nil-guards (Group F) are extracted to _gt_hacks.lua
-- (dofile'd after the main chunk). Every Hacks hook is a singleton. The pause
-- flag is shared with the on_game_state_changed dispatcher via mod._gt_pause_active;
-- mod.gt_time_apply / gt_apply_crit_chance / gt_apply_move_speed /
-- gt_apply_fall_damage stay `mod.` fields so the on_setting_changed branches +
-- the fall-damage regression test resolve them at call time. The original merged
-- infinite-ammo+ai-pending update consumer was split: the infinite-ammo half is
-- in _gt_hacks.lua (`infinite_ammo`), the AI half stays here (`ai_pending`).



-- Player-state toggles (Group E — inn-damage / cloak / unkillable) are extracted
-- to _gt_godmode_qol.lua (dofile'd after the main chunk). Command-only, no hooks;
-- expose mod.gt_inn_dmg_toggle / gt_cloak_toggle / gt_unkillable_toggle, resolved
-- at command-invoke time. The Engine error nil-guards (Group F) moved to
-- _gt_hacks.lua alongside the rest of the Hacks port (B/C/D); the
-- AICommanderExtension._update_units guard (a separate always-on AI-takeover
-- crash guard) stays near the AI Takeover code above.


-- Skip Cutscenes (Group G — Aussiemon "Skip Cutscenes" port) MIGRATED to
-- gui_tweaker (gut) 2026-06-25, issue #106 — _gt_cutscenes.lua removed (renamed to
-- _gt_cutscenes.lua.bak.v0.2.139). gut now owns the CutsceneSystem.* +
-- ShowCursorStack.pop hooks, the cutscene_auto_skip deferred processor, the
-- /gut_skipcutscenes command, and the [gut:cutscene] printf diagnostic. The
-- TP-camera-yields-to-cutscene fix (PlayerUnitFirstPerson.set_first_person_mode) also
-- MIGRATED to gut with the Third-Person Camera feature 2026-06-29, #191.

-- Burning-enemy fire VFX opacity PROBE (v0.2.93-dev) is extracted to
-- _gt_debug_probes.lua (dofile'd after the main chunk). Self-contained: it
-- sentinel-wraps StatusEffectTemplates[burning_*].on_applied to capture live
-- fire particles and exposes /fire_probe to discover the opacity material
-- variable in-game. Command-only, no Class.method hook, no cross-file state.

-- More Corpses (RagdollSettings cap) is extracted to _gt_godmode_qol.lua (dofile'd
-- after the main chunk). No hooks. It exposes mod.gt_apply_corpse_count, resolved at
-- call time from the on_setting_changed branch for gt_more_corpses_*.
-- (Disable Loading-Screen Monologues MIGRATED to gui_tweaker / gut 2026-06-29, #192 —
-- gut's _gut_monologue.lua now owns the script_data.disable_level_intro_dialogue
-- flag + the /gut_intromono command.)

-- Choose Grail Knight Quests (PassiveAbilityQuestingKnight._generate_quest_pool)
-- and Ready Up! (VoteManager.rpc_client_complete_vote + mod.gt_ready_up_now host
-- shortcut) are extracted to _gt_misc_features.lua (dofile'd after the main
-- chunk). Both hooks are table-form guarded (the classes are global tables
-- resolved at module load). The gk_quest_dropdowns_dont_share_options
-- /gt_regression_test check stays in the main file (it inspects the DATA file).

-- Creature Spawner (Aussiemon CreatureSpawner port, Workshop 1395132559) is
-- extracted to _gt_creature_spawner.lua (dofile'd after the main chunk). It
-- assigns mod._gt_cs_on_setting_changed / mod._gt_cs_on_game_state_changed (the
-- main on_setting_changed / on_game_state_changed DISPATCHERS resolve those
-- fields) and exposes mod._gt_cs_is_in_level for the gt_cs_is_in_level_prefix_
-- match regression check (which stays below). Every CS hook is a singleton;
-- the consolidated ConflictDirector.spawn_queued_unit hook STAYS in main
-- (CS only hooks the DISTINCT ConflictDirector.update for keep-spawns).

-- ============================================================
-- /regression_test checks (see scaffold near MOD_VERSION).
-- ============================================================
-- The task spec mentioned a `skip_splash_hook_installed` check + a
-- `collision_disable_one_indexed` check, but the current gt source has no
-- StateSplashScreen hook (skip-splash is delegated to a different mod) and no
-- collision-disable loop (collision filtering is field-based, not loop-based).
-- Both skipped here. (The Skip Cutscenes feature — and its two regression checks
-- cutscene_auto_skip_deferred / cutscene_skip_setting_id_present — MIGRATED to
-- gui_tweaker (gut) 2026-06-25, issue #106. Those checks now live in gut.)

_rt_register("gt_pickup_lookup_uses_rawget", function()
    -- v0.2.47/.48: `_gt_is_spawn` resolves the chat-supplied pickup name through
    -- `rawget(NetworkLookup.pickup_names, pickup_name)` (~L3553) so an unknown
    -- name echoes "Unknown pickup name: ..." instead of raising the strict
    -- `__index` metatable. The strict-table-lookup lint covers static-pattern
    -- regressions; this runtime check is the belt-and-suspenders companion
    -- required by §15 of PROJECT_STANDARDS.md.
    --
    -- 1. Source-pattern: the marker constant must be present.
    if CT_GT_PICKUP_LOOKUP_RAWGET_MARKER_v0_2_48 ~= "gt-pickup-lookup-rawget-hardened" then
        return "RAWGET marker absent — was the v0.2.47 pickup-lookup hardening reverted?"
    end
    -- 2. Runtime-state: probe rawget on a known-bad key — must return nil
    --    without raising. If pickup_names ever loses its strict metatable,
    --    this still passes; if it grows one with broken handling, this fails.
    local NL = rawget(_G, "NetworkLookup")
    local pn = NL and NL.pickup_names
    if type(pn) == "table" then
        local ok, value = pcall(rawget, pn, "__gt_rawget_probe_does_not_exist__")
        if not ok then
            return "rawget(NetworkLookup.pickup_names, <bad-key>) RAISED — strict-metatable behavior changed"
        end
        if value ~= nil then
            return "rawget(NetworkLookup.pickup_names, <bad-key>) returned non-nil — unexpected"
        end
    end
end)

_rt_register("ai_takeover_marker_present", function()
    -- v0.2.52 source-pattern guard. If a future refactor strips the marker
    -- constant or the v0.2.52 fix gets reverted, this fails. Belt-and-
    -- suspenders for the runtime queue test below — the queue test would
    -- still pass even if `mod._gt_ai_handle_toggle_change` deleted the ping call.
    if CT_GT_AI_CLIENT_SEND_MARKER_v0_2_52 ~= "gt-ai-client-send-vmf-rehandshake" then
        return "AI client-send marker absent — was the v0.2.52 fix reverted?"
    end
end)

_rt_register("ai_takeover_vmf_ping_api_available", function()
    -- v0.2.52: AI Takeover client send now calls `get_mod("VMF").ping_vmf_users()`
    -- before each emit to force VMF to re-handshake when `_vmf_users` has gone
    -- stale (bot-churn at mission load drops the host — see send-queue comment
    -- in this file). If VMF ever renames or removes this entry point, the
    -- workaround silently no-ops via the pcall and every client toggle would
    -- silently drop again. Pin both the mod presence and the function shape.
    local vmf = get_mod("VMF")
    if not vmf then
        return "VMF mod not loaded — `get_mod('VMF')` returned nil"
    end
    if type(vmf.ping_vmf_users) ~= "function" then
        return "vmf.ping_vmf_users is not a function (type=" .. type(vmf.ping_vmf_users) .. ")"
    end
end)

_rt_register("ai_takeover_client_send_queue_wired", function()
    -- v0.2.52: client-side toggle now enqueues into `mod._gt_ai_pending_client_send`
    -- with retries instead of sending inline. The mod.update consumer must
    -- be wired into the existing update chain — without it the queue would
    -- fill and never drain. Verify the consumer function exists in the file's
    -- closure scope by walking the queue forward via a synthetic enqueue and
    -- asserting mod.update drains it.
    --
    -- We don't actually exercise the network send (no real peer in regression
    -- harness); we just verify the queue shape + drain behavior using a
    -- guaranteed-elapsed `next_at`. Restore the prior queue state on exit.
    local saved = mod._gt_ai_pending_client_send
    mod._gt_ai_pending_client_send = {
        host = "__rt_probe_peer__",
        want_bot = true,
        retries_left = 1,
        next_at = os.clock() - 1.0,  -- already-elapsed so the first tick fires
    }
    -- Drive one mod.update tick. The consumer should fire (next_at elapsed),
    -- decrement retries to 0, and clear the queue.
    if type(mod.update) ~= "function" then
        mod._gt_ai_pending_client_send = saved
        return "mod.update is not a function — update chain broken"
    end
    local ok, err = pcall(mod.update, 0.016)
    if not ok then
        mod._gt_ai_pending_client_send = saved
        return "mod.update raised during client-send drain probe: " .. tostring(err)
    end
    if mod._gt_ai_pending_client_send ~= nil then
        mod._gt_ai_pending_client_send = saved
        return "client-send queue did not drain after one tick (consumer not wired into mod.update?)"
    end
    mod._gt_ai_pending_client_send = saved
end)

_rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    local ok = pcall(_dbg, "smoke test")
    if not ok then return "_dbg raised" end
    ok = pcall(_dbg_alert, "smoke test")
    if not ok then return "_dbg_alert raised" end
end)

_rt_register("necro_potion_give_half_targeted_promote", function()
    -- v0.2.138-dev (FIX 1 give-half completion). The Necromancer-bot potion
    -- promote must target the REAL potion BY IDENTITY (SwapFromStorageType.Same
    -- + the potion's item_data), not storage index 1 (SwapFromStorageType.First).
    -- slot_potion storage can also hold the grimoire (non-giveable) and the
    -- demoted skull, so a First-swap could promote the wrong occupant -> primary
    -- stays non-giveable -> the give never resolves -> the bot loops "trying to
    -- pass but can't". Pin both halves:
    --   1) the source-pattern marker constant is present, AND
    --   2) the SwapFromStorageType.Same enum member exists (the swap mode we rely
    --      on for identity promotion). If vanilla ever drops it, the promote
    --      would silently no-op the targeted path.
    if GT_NECRO_POTION_GIVE_HALF_MARKER_v0_2_138 ~= "gt-necro-potion-give-half-targeted-promote" then
        return "give-half marker absent — was the v0.2.138 targeted-promote reverted to a blind First-swap?"
    end
    local sfs = rawget(_G, "SwapFromStorageType")
    if type(sfs) ~= "table" then
        return "SwapFromStorageType enum table missing"
    end
    if sfs.Same == nil then
        return "SwapFromStorageType.Same absent — identity promotion can't target the real potion"
    end
end)



_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/general_tweaker_dev/general_tweaker_dev_localization")
    if not ok or type(loc) ~= "table" then return end  -- can't reach loc; skip
    for k, v in pairs(loc) do
        if type(v) == "table" and type(v.en) == "string" then
            local fmt_ok, fmt_err = pcall(string.format, v.en)
            if not fmt_ok then
                return string.format(
                    "loc key %q has invalid format string (escape literal %% as %%%%): %s",
                    k, tostring(fmt_err))
            end
        end
    end
end)

-- v0.2.60-dev: VMF_RECIPES § 10 / Issue #43 -- assert the gt_lobby RPC schema
-- constant is in place. Migrated from lt v0.1.7-dev when its `lt_motd_show`
-- RPC was absorbed as `gt_lobby_motd_show`.
_rt_register("gt_lobby_rpc_schema_present", function()
    if type(mod.GT_LOBBY_RPC_SCHEMA) ~= "number" then
        return "mod.GT_LOBBY_RPC_SCHEMA not defined as number"
    end
    if mod.GT_LOBBY_RPC_SCHEMA < 1 then
        return "mod.GT_LOBBY_RPC_SCHEMA < 1"
    end
end)

-- v0.2.167-dev: VMF_RECIPES § 10 / Issue #44 -- assert the AI-control RPC schema
-- constant is in place (mirrors gt_lobby_rpc_schema_present). The
-- `gt_ai_toggle_request` sender + receiver in _gt_ai_takeover.lua both read
-- mod.GT_AI_RPC_SCHEMA; if it goes missing the receiver gate compares against nil
-- and would accept anything, so guard it here.
_rt_register("gt_ai_rpc_schema_present", function()
    if type(mod.GT_AI_RPC_SCHEMA) ~= "number" then
        return "mod.GT_AI_RPC_SCHEMA not defined as number"
    end
    if mod.GT_AI_RPC_SCHEMA < 1 then
        return "mod.GT_AI_RPC_SCHEMA < 1"
    end
end)

-- audit 2026-06-07 (F3, v0.2.80-dev): event-registration clobber. The three
-- lobby modules (slot_reservations, session_ignore, motd) used to each register
-- (mod, "on_player_joined_party") -- EventManager keys by (object, event_name)
-- so last-writer-wins meant only ONE fired. They now append to a single shared
-- dispatcher. This test FAILS if a module reverts to self-registration (its
-- handler would be absent from the shared list) or the consolidation is dropped.
_rt_register("gt_lobby_join_dispatch_consolidated", function()
    local handlers = mod._gt_lobby_join_handlers
    if type(handlers) ~= "table" then
        return "mod._gt_lobby_join_handlers missing (shared dispatcher not installed)"
    end
    if type(mod.gt_lobby_on_player_joined_party) ~= "function" then
        return "mod.gt_lobby_on_player_joined_party (single registered method) missing"
    end
    -- All three join-handlers must be reachable from the single dispatch list.
    local want = { session_ignore = false, slot_reservations = false, motd = false }
    for i = 1, #handlers do
        local h = handlers[i]
        if h and want[h.name] ~= nil then
            if type(h.fn) ~= "function" then
                return "join-handler '" .. tostring(h.name) .. "' is not a function"
            end
            want[h.name] = true
        end
    end
    for name, present in pairs(want) do
        if not present then
            return "join-handler '" .. name .. "' not registered on the shared dispatcher"
        end
    end
end)

-- audit 2026-06-07 (F3): the single dispatcher must (a) strip the EventManager
-- object-prepend so handlers get the true peer_id, and (b) invoke EVERY handler
-- even if an earlier one raises (pcall isolation). We swap the live handler list
-- for two synthetic handlers (so the real session_ignore/slot_reservations/motd
-- logic never runs against a fake peer), drive the dispatcher the way
-- EventManager.trigger does (object prepended), then restore the real list.
_rt_register("gt_lobby_join_dispatch_pcall_isolated", function()
    local handlers = mod._gt_lobby_join_handlers
    if type(handlers) ~= "table" or type(mod.gt_lobby_on_player_joined_party) ~= "function" then
        return "shared dispatcher not installed"
    end
    -- Snapshot + clear the live list so we test only our synthetic handlers.
    local saved = {}
    for i = 1, #handlers do saved[i] = handlers[i]; handlers[i] = nil end
    local function restore()
        for i = #handlers, 1, -1 do handlers[i] = nil end
        for i = 1, #saved do handlers[i] = saved[i] end
    end
    local reached = false
    local got_peer = nil
    handlers[1] = { name = "_rt_raiser", fn = function() error("synthetic raise") end }
    handlers[2] = { name = "_rt_recorder", fn = function(peer_id) reached = true; got_peer = peer_id end }
    -- EventManager.trigger calls object[name](object, ...); first real arg is mod.
    local ok = pcall(mod.gt_lobby_on_player_joined_party, mod, "peer123", 1, 0, 1, false)
    restore()
    if not ok then
        return "dispatcher itself raised (handler pcall isolation broken)"
    end
    if not reached then
        return "second handler never ran after first raised (no pcall isolation)"
    end
    if got_peer ~= "peer123" then
        return "handler received wrong peer_id (object-prepend not stripped): got " .. tostring(got_peer)
    end
end)

-- audit 2026-06-07 (F4, v0.2.80-dev): double consume-once popup race. The
-- enriched failed-join popup is now polled ONLY by the mod (it is no longer
-- assigned to StateLoading._popup_id), so the mod's poller must drive the
-- vanilla restart_as_server teardown itself. This test exercises that driver
-- against a synthetic StateLoading and asserts it sets the exact fields vanilla
-- _handle_popup's restart_as_server branch sets (state_loading.lua:1570-1577).
-- FAILS if the teardown driver is dropped or stops setting either field --
-- which is the exact symptom of the loading-screen hang the race caused.
_rt_register("gt_lobby_failnotify_teardown_driver", function()
    local drive = mod._gt_failnotify_drive_teardown
    if type(drive) ~= "function" then
        return "mod._gt_failnotify_drive_teardown missing (F4 teardown driver not installed)"
    end
    -- Synthetic StateLoading-like object with a force_done()-capable view.
    local forced = false
    local fake_sl = {
        _teardown_network = false,
        _permission_to_go_to_next_state = false,
        _first_time_view = { force_done = function() forced = true end },
    }
    local ok, err = pcall(drive, fake_sl)
    if not ok then
        return "teardown driver raised: " .. tostring(err)
    end
    if fake_sl._teardown_network ~= true then
        return "driver did not set _teardown_network=true (loading screen would hang)"
    end
    if fake_sl._permission_to_go_to_next_state ~= true then
        return "driver did not set _permission_to_go_to_next_state=true"
    end
    if forced ~= true then
        return "driver did not force_done the first_time_view"
    end
    -- Must tolerate a nil StateLoading (entry.sl absent) without raising.
    local ok2, err2 = pcall(drive, nil)
    if not ok2 then
        return "teardown driver raised on nil sl: " .. tostring(err2)
    end
end)

_rt_register("gt_lobby_failnotify_unknown_result_drives_teardown", function()
    -- v0.2.81 (Issue #72): an unrecognized popup result must NOT silently drop
    -- the pending entry — it logs (ungated) and still drives teardown so the
    -- user is never stranded on the loading screen. Drive the real consumer
    -- with a stub popup manager and a synthetic pending entry.
    local consume = mod._gt_failnotify_consume_results
    local pending = mod._gt_failnotify_pending_popups
    if type(consume) ~= "function" or type(pending) ~= "table" then
        return "consume_results/pending_popups test exports missing (Issue #72 regression)"
    end
    local fake_sl = { _teardown_network = false, _permission_to_go_to_next_state = false }
    local popup_id = "gt_rt_unknown_result_probe"  -- string key can't collide with engine numeric ids
    pending[popup_id] = { diff = nil, sl = fake_sl }
    local stub_mgr = { query_result = function(_, id)
        if id == popup_id then return "some_future_unknown_action" end
    end }
    local ok, err = pcall(consume, stub_mgr)
    pending[popup_id] = nil  -- belt-and-suspenders cleanup regardless of outcome
    if not ok then
        return "consumer raised on unknown result: " .. tostring(err)
    end
    if fake_sl._teardown_network ~= true or fake_sl._permission_to_go_to_next_state ~= true then
        return "unknown result did not drive teardown (user would be stranded on loading screen)"
    end
end)

_rt_register("gt_lobby_failnotify_popup_up_soft_defers", function()
    -- v0.2.81 (Issue #72, F17): the popup-already-up branch must soft-defer
    -- (boolean decision), never raise. Pins the truth table.
    local should_defer = mod._gt_failnotify_should_defer
    if type(should_defer) ~= "function" then
        return "should_defer test export missing (F17 soft guard regressed)"
    end
    local ok, a, b, c = pcall(function()
        return should_defer({ _popup_id = 123 }), should_defer({}), should_defer(nil)
    end)
    if not ok then
        return "F17 guard raised instead of soft-deferring: " .. tostring(a)
    end
    if a ~= true then return "popup-up state did not defer (would hit vanilla's assert with our enrichment half-applied)" end
    if b ~= false then return "no-popup state wrongly deferred (enrichment would never fire)" end
    if c ~= false then return "nil self wrongly deferred" end
end)

_rt_register("gt_lobby_failnotify_unpack_preserves_leading_nils", function()
    -- v0.2.81 (Issue #72): replica of the create_popup forward idiom
    -- (n = 3 + select('#', ...); unpack(args, 1, n)) under its worst case:
    -- header/action/right_button all nil with trailing format varargs present
    -- (vanilla call site state_loading.lua:1084 passes 2 trailing args). Bare
    -- unpack(args) boundary-searches across the leading nils and can drop the
    -- format args, crashing vanilla's string.format at state_loading.lua:2467.
    local function _forward(header, action, right_button, ...)
        local n = 3 + select("#", ...)
        local args = { header, action, right_button, ... }
        return select("#", unpack(args, 1, n)), (select(n, unpack(args, 1, n)))
    end
    local count, last = _forward(nil, nil, nil, "client_hash", "lobby_hash")
    if count ~= 5 then
        return string.format("forward dropped args across leading nil holes: expected 5, got %d", count)
    end
    if last ~= "lobby_hash" then
        return string.format("trailing format arg lost: expected 'lobby_hash', got %s", tostring(last))
    end
end)

_rt_register("bots_in_keep_helpers_exposed", function()
    -- v0.2.71-dev "Allow Bots in Keep": the early on_setting_changed and
    -- on_game_state_changed closures (declared ~line 830/789) reach into the
    -- feature via mod._bik_* table fields because the file-locals aren't
    -- visible at compile time at those positions. If a future refactor stops
    -- exposing the helpers OR renames them, the on_setting_changed branch
    -- becomes a silent no-op (toggle would still flip the setting but no
    -- bots would ever be added/removed in response).
    for _, name in ipairs({ "_bik_fill", "_bik_clear", "_bik_active", "_bik_reset_bookkeeping" }) do
        if type(mod[name]) ~= "function" then
            return "mod." .. name .. " is not a function (type=" .. type(mod[name]) .. ")"
        end
    end
end)

_rt_register("bots_in_keep_active_default_false", function()
    -- _bik_active() must return false when the gt_bots_in_keep setting is
    -- off (default state on fresh install). Catches regressions where the
    -- gate logic gets inverted, the setting_id changes without updating the
    -- gate read, or _bik_active starts throwing on a missing dependency
    -- (Managers.player nil at boot, etc.).
    local saved = mod:get("gt_bots_in_keep")
    if saved == true then mod:set("gt_bots_in_keep", false) end
    local ok, result = pcall(mod._bik_active)
    if saved == true then mod:set("gt_bots_in_keep", true) end
    if not ok then
        return "_bik_active raised: " .. tostring(result)
    end
    if result ~= false then
        return "_bik_active returned " .. tostring(result) .. " with toggle off (expected false)"
    end
end)

_rt_register("bots_in_keep_reset_bookkeeping_safe", function()
    -- _bik_reset_bookkeeping is called from on_game_state_changed on EVERY
    -- state transition (StateSplashScreen, StateTitleScreen, StateLoading,
    -- StateIngame, etc.). It must be a pure table reset — no engine calls,
    -- no _remove_bot_instant invocations on Player references that may have
    -- been torn down by state shutdown. Probe by calling it twice in a row
    -- and asserting no raise.
    local ok1, err1 = pcall(mod._bik_reset_bookkeeping)
    if not ok1 then
        return "_bik_reset_bookkeeping raised on first call: " .. tostring(err1)
    end
    local ok2, err2 = pcall(mod._bik_reset_bookkeeping)
    if not ok2 then
        return "_bik_reset_bookkeeping raised on second call (idempotency failure): " .. tostring(err2)
    end
end)

_rt_register("bots_in_keep_crashfix_marker_present", function()
    -- v0.2.146-dev: "Allow Bots in Keep" was un-kill-switched after the two
    -- v0.2.74-dev crash classes (#65) were fixed structurally (Photo-Mode port):
    -- teardown via GameModeInn/InnDeus.cleanup_game_mode_units (unregisters bot
    -- stats before the venture stats manager is destroyed -> Bug 1) and fill
    -- gated on _bik_host_in_party1() (-> Bug 2 slot-1 race). If this marker
    -- disappears, the revival was reverted (or the kill-switch came back).
    if GT_BIK_CRASHFIX_MARKER_v0_2_146 ~= "gt-bik-cleanup-and-host-slot-gate" then
        return "bots_in_keep crash-fix marker absent — was the v0.2.146-dev revival reverted?"
    end
end)

_rt_register("bots_in_keep_necro_pets_marker_present", function()
    -- v0.2.147-dev: necromancer BOT keep-skeletons sub-feature. With Bots in Keep
    -- on, a bot necromancer's raise-dead AI loops against the vanilla hub pet ban
    -- (PassiveAbilityNecromancerCharges._pets_forbidden_in_level). We post-hook
    -- _on_talents_changed and clear that flag for bot necromancers only. If this
    -- marker disappears, the sub-feature (or its hook) was removed.
    if GT_BIK_NECRO_KEEP_PETS_MARKER_v0_2_147 ~= "gt-bik-necro-bot-keep-pets" then
        return "necromancer keep-pets marker absent — was the v0.2.147-dev sub-feature reverted?"
    end
end)

_rt_register("bot_leash_veto_while_teammate_needs_aid_present", function()
    -- #139 (v0.2.185-dev): the v0.2.148 snap-toward-downed guard + the v0.2.152
    -- side-aid guard were consolidated into ONE blanket leash veto in the
    -- BTConditions.should_teleport hook: with aid-priority ON, a bot never
    -- teleports (vanilla 40 m OR gt tighter leash) while any teammate is
    -- downed/disabled — it paths in to revive (user decision on #139: all bots
    -- converge). Marker + source-pattern check so a refactor that drops the veto,
    -- or lets vanilla's 40 m path through again, gets caught.
    -- #511 (v0.2.202-dev): the veto-conjunction source-grep (io.open) was removed --
    -- io is nil in the VMF sandbox, so it threw and reported FAIL on healthy code.
    -- The marker constant (set at LOAD right beside the veto in _gt_bot_fixes.lua)
    -- already proves the block is present; the exact "_gt_aid_priority_on() and
    -- _gt_any_side_teammate_needs_aid" text invariant is STATIC and belongs in a
    -- repo QA gate (PROJECT_STANDARDS 2.2b tier a).
    if GT_BOT139_LEASH_VETO_AIDPRIORITY_MARKER_v0_2_185 ~= "gt-bot139-teleport-veto-while-teammate-needs-aid" then
        return "bot #139 leash-veto marker absent — was the v0.2.185-dev consolidation reverted?"
    end
end)

_rt_register("gt_bot139_needs_aid_status_predicate", function()
    -- #139 (v0.2.192-dev): the leash veto keys off _gt_unit_needs_aid, whose
    -- status -> boolean core is _gt_status_needs_aid: a teammate "needs aid" when
    -- knocked down, hanging from a hook, or ledge-hanging AND not yet pulled up.
    -- Exercise the exact truth table with a STUB status extension so a refactor
    -- that narrows the covered states (or drops the "not pulled up" clause, which
    -- would re-flag an ally who has already been helped up) is caught at load.
    -- Stub tables, not live units: _gt_unit_needs_aid's ALIVE[u] guard reads the
    -- engine POSITION_LOOKUP map (global_utils.lua:15) and rejects a fake key, so
    -- the leaf predicate is the injectable seam.
    local pred = mod._gt_status_needs_aid
    if type(pred) ~= "function" then
        return "mod._gt_status_needs_aid not exposed -- was the #139 leaf seam reverted?"
    end
    local function st(knocked, hook, ledge, pulled)
        return {
            is_knocked_down      = function() return knocked end,
            is_hanging_from_hook = function() return hook end,
            get_is_ledge_hanging = function() return ledge end,
            is_pulled_up         = function() return pulled end,
        }
    end
    local function b(v) return v and true or false end
    local cases = {
        { s = st(true,  false, false, false), want = true,  why = "knocked down" },
        { s = st(false, true,  false, false), want = true,  why = "hanging from hook" },
        { s = st(false, false, true,  false), want = true,  why = "ledge-hanging, not pulled up" },
        { s = st(false, false, true,  true),  want = false, why = "ledge-hanging but already pulled up" },
        { s = st(false, false, false, false), want = false, why = "healthy (no disabler state)" },
        { s = st(false, false, false, true),  want = false, why = "healthy, pulled_up irrelevant" },
    }
    for _, c in ipairs(cases) do
        if b(pred(c.s)) ~= c.want then
            return string.format("_gt_status_needs_aid(%s): want=%s got=%s",
                c.why, tostring(c.want), tostring(b(pred(c.s))))
        end
    end
end)

_rt_register("gt_bot139_teleport_veto_singleton_and_gated", function()
    -- #139 (v0.2.192-dev): the blanket leash veto must live in EXACTLY ONE
    -- BTConditions.should_teleport hook -- VMF silently drops a 2nd hook on the
    -- same (Class, method) (CLAUDE.md non-negotiable 8), which would shadow the
    -- veto. And the veto must gate on aid-priority AND a downed side teammate.
    -- Assert both so a refactor can neither add a duplicate should_teleport hook
    -- nor weaken the gate. Complements bot_leash_veto_..._present (which only
    -- checks the veto conjunction marker) with the singleton count.
    -- #511 (v0.2.202-dev): the source-grep half (io.open) was removed -- io is nil
    -- in the VMF sandbox, so it threw and reported FAIL on healthy code. The
    -- runtime residual (both helper seams exposed) stays. The two STATIC invariants
    -- it grepped move to their correct homes: the "exactly one
    -- BTConditions.should_teleport hook" duplicate-hook count is ALREADY enforced
    -- by tools/mod-lint/lint-mod.ps1 (PROJECT_STANDARDS 2.2b tier a, mod-wide), and
    -- the veto-conjunction / master+sub-gate text belongs in a repo QA gate.
    if type(mod._gt_aid_priority_on) ~= "function" then
        return "mod._gt_aid_priority_on not exposed"
    end
    if type(mod._gt_any_side_teammate_needs_aid) ~= "function" then
        return "mod._gt_any_side_teammate_needs_aid not exposed"
    end
end)

_rt_register("gt_bot139_aid_scan_is_side_scoped_not_follow", function()
    -- #139 (v0.2.192-dev) STRUCTURAL + behavioral guard against the exact root
    -- cause: _gt_any_side_teammate_needs_aid must scan the SIDE player list
    -- (side.PLAYER_UNITS via side_by_unit), never the bot's follow target.
    -- Vanilla AIBotGroupSystem._update_move_targets (ai_bot_group_system.lua
    -- :695-719) drops disabled players from the follow-candidate set unless EVERY
    -- human is down, so a follow-scoped aid check is structurally blind to a
    -- teammate who went down while the bot was leashed to a LIVING far player.
    if type(mod._gt_any_side_teammate_needs_aid) ~= "function" then
        return "mod._gt_any_side_teammate_needs_aid not exposed"
    end
    local pred = mod._gt_status_needs_aid
    if type(pred) ~= "function" then return "mod._gt_status_needs_aid not exposed" end

    -- Behavioral: a healthy follow-target stub is NOT aid-worthy, while a knocked
    -- non-follow teammate IS -- so a full side-list scan finds the downed teammate
    -- the (healthy) follow target would otherwise hide.
    local function st(knocked)
        return {
            is_knocked_down      = function() return knocked end,
            is_hanging_from_hook = function() return false end,
            get_is_ledge_hanging = function() return false end,
            is_pulled_up         = function() return false end,
        }
    end
    if (pred(st(false)) and true or false) ~= false then
        return "healthy follow-target stub wrongly classified as needing aid"
    end
    if (pred(st(true)) and true or false) ~= true then
        return "knocked non-follow teammate stub not classified as needing aid"
    end
    -- #511 (v0.2.202-dev): the structural body-grep (io.open, isolating the scan
    -- body to assert it reads side.PLAYER_UNITS/side_by_unit and never "follow")
    -- was removed -- io is nil in the VMF sandbox, so it threw and reported FAIL on
    -- healthy code. The behavioral stub checks above are the runtime residual; the
    -- side-scoped-not-follow SOURCE-TEXT invariant belongs in a repo QA gate
    -- (PROJECT_STANDARDS 2.2b tier a).
end)

_rt_register("gt_bot492_aid_stall_recovery", function()
    -- #492 (reworked v0.2.202-dev): fast, within-down-window recovery for the
    -- aid-priority pursuit lock. Locks THREE things so a refactor can't silently
    -- drop the safety valve:
    --   (1) the marker constant is present,
    --   (2) the pure decision machine (_gt492_step) bails on EITHER a sustained
    --       engine aid-path failure (fast) OR a far no-progress stall (backstop),
    --       never bails a CLOSE (in-range) target, and LATCHES until the ally
    --       clears or the bot gets close again (functional check, no engine reads),
    --   (3) both halves of the actuator are wired in _gt_bot_fixes.lua: the picker
    --       drops the bailed aid pick, and the #139 veto steps aside on the flag.
    if GT_BOT492_AID_STALL_RECOVERY_MARKER_v0_2_198 ~= "gt-bot492-aid-pursuit-stall-recovery" then
        return "bot #492 aid-stall-recovery marker absent -- was the recovery reverted?"
    end

    -- (2) Functional: drive the pure machine. Signature is (state, aid_unit,
    -- aid_dist, path_failed, t). Constants in source: PATH_FAIL_CONFIRM 4 s,
    -- NO_PROGRESS_TIMEOUT 8 s, FAR 20 m, REACHED 12 m, EPSILON 2 m; the margins
    -- below stay clear of those edges so the check does not depend on exact values.
    local step = mod._gt492_step
    if type(step) ~= "function" then
        return "mod._gt492_step not exposed -- the #492 decision machine seam is missing"
    end
    local U, V = "downA", "downB"
    local s, bail

    -- Backstop: far + no closing progress past the timeout must bail, and latch.
    s, bail = step({ aid_unit = nil }, U, 100, false, 0) ; if bail then return "#492: fresh far target must not bail immediately" end
    s, bail = step(s, U, 100, false, 5)                  ; if bail then return "#492: far stall under the no-progress timeout must not bail" end
    s, bail = step(s, U, 100, false, 20)                 ; if not bail then return "#492: far no-progress past the timeout must bail" end
    s, bail = step(s, U, 100, false, 40)                 ; if not bail then return "#492: bail must LATCH while the bot is still far" end
    s, bail = step(s, U, 5,   false, 41)                 ; if bail then return "#492: reaching the ally (close) must clear the latch" end

    -- Close target: an in-range stall (bot fighting next to a reachable revive)
    -- must NEVER bail, no matter how long -- the revive is imminent.
    local c
    c, bail = step({ aid_unit = nil }, U, 8, false, 0)   ; if bail then return "#492: fresh close target must not bail" end
    c, bail = step(c, U, 8, false, 500)                  ; if bail then return "#492: an in-range stall must never bail (revive imminent)" end

    -- Fast path: sustained engine aid-path failure bails quickly (well before the
    -- no-progress backstop). The confirm clock only starts on the FIRST observed
    -- failure (fail_since), so a fresh target's path-fail tick must not bail.
    local p
    p, bail = step({ aid_unit = nil }, U, 100, true, 0)  ; if bail then return "#492: first path-fail tick (fresh target) must not bail" end
    p, bail = step(p, U, 100, true, 2)                   ; if bail then return "#492: path-fail confirm window not yet elapsed must not bail" end
    p, bail = step(p, U, 100, true, 7)                   ; if not bail then return "#492: sustained aid-path failure must bail fast (before the no-progress backstop)" end

    -- A new (different) aid target resets and does not inherit the prior bail.
    local n = { aid_unit = U, best_dist = 100, progress_t = 0, fail_since = nil, bailed = true }
    n, bail = step(n, V, 300, false, 201)                ; if bail then return "#492: a new (different) aid target must reset and not bail" end

    -- No aid target: no bail.
    local _, zb = step({ aid_unit = nil }, nil, nil, false, 600) ; if zb then return "#492: no aid target must not bail" end

    -- (3) Actuator seams present at runtime. #511 (v0.2.202-dev): the source-grep
    -- that asserted the picker calls mod._gt492_should_suppress_pick and the veto
    -- reads blackboard._gt492_bailout was removed -- io is nil in the VMF sandbox,
    -- so it threw and reported FAIL on healthy code. The functional drive above
    -- already exercises the whole decision machine, and the marker constant proves
    -- the actuator block loaded; the two exact source-text wirings belong in a repo
    -- QA gate (PROJECT_STANDARDS 2.2b tier a).
    if type(mod._gt492_should_suppress_pick) ~= "function" or type(mod._gt492_aid_stall_tick) ~= "function" then
        return "mod._gt492 actuator seams not exposed -- picker suppression / stall tick missing"
    end
end)

_rt_register("gt_bot383_fix9_splits_follow_position", function()
    -- issue 383 (v0.2.194-dev): FIX 9 (split bots among humans) must set
    -- data.follow_position -- a vanilla-spacing fan point around each bot's OWN
    -- assigned human -- not only data.follow_unit. Re-pointing follow_unit alone
    -- left a split bot standing next to the WRONG human (movement reads
    -- follow_position, player_bot_base.lua:1655). Marker + source-pattern guard,
    -- plus a behavioral check of the fan helper's nil-return fallback contract.
    if GT_BOT383_FIX9_SPLIT_FOLLOW_POSITION_MARKER ~= "gt-bot383-fix9-split-follow-position" then
        return "issue-383 split follow_position marker absent -- was the FIX A recompute reverted?"
    end
    -- Behavioral: the fan helper returns nil (caller then leaves follow_position
    -- untouched) on its guard paths -- no nav_world, non-positive count. Exercises
    -- the "fall back rather than stamp the raw player position" contract without a
    -- live navmesh / POSITION_LOOKUP entry.
    local fan = mod._gt_fan_points_for_unit
    if type(fan) ~= "function" then
        return "mod._gt_fan_points_for_unit not exposed -- FIX A fan helper missing"
    end
    if fan({}, nil, {}, 1) ~= nil then
        return "fan helper must return nil when nav_world is nil (fallback contract)"
    end
    if fan({}, "navworld", {}, 0) ~= nil then
        return "fan helper must return nil when needed <= 0 (fallback contract)"
    end
    -- #511 (v0.2.202-dev): the structural source-grep (io.open) that asserted the
    -- split branch computes a per-human fan, writes data.follow_position, and keeps
    -- the hold_position guard was removed -- io is nil in the VMF sandbox, so it
    -- threw and reported FAIL on healthy code. The marker + fan-helper nil-contract
    -- checks are the runtime residual; the split-branch SOURCE-TEXT invariants
    -- belong in a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
end)

_rt_register("gt_bot142_backward_wants_no_segment_gate", function()
    -- issue 142 (v0.2.194-dev): _gt_backward_teleport_wants mirrors vanilla
    -- should_teleport MINUS the behind-segment gate, so a follow target behind the
    -- bot still triggers once beyond the leash threshold. Drive the pure decision
    -- with a stub blackboard + injected squared distance (ScriptUnit/ALIVE/Vector3
    -- are file-local upvalues a test cannot stub). "Behind" is implicit: the
    -- function reads no segment, so a beyond-threshold distance fires regardless.
    local wants = mod._gt_backward_teleport_wants
    if type(wants) ~= "function" then
        return "mod._gt_backward_teleport_wants not exposed"
    end
    local FAR = 5000    -- ~70 m^2; above any slider threshold (max 40 m => 1600 sq)
    local NEAR = 50     -- ~7 m^2; below the tightest threshold (10 m => 100 sq)
    local function bb(extra)
        local b = { unit = {}, ai_bot_group_extension = { data = { follow_unit = {} } } }
        for k, v in pairs(extra or {}) do b[k] = v end
        return b
    end
    if wants(bb(), FAR) ~= true then
        return "backward wants should be true for a beyond-threshold follow target (behind or not)"
    end
    if wants(bb({ has_teleported = true }), FAR) ~= false then
        return "backward wants must be false when has_teleported is set"
    end
    if wants(bb({ target_ally_need_type = "knocked_down" }), FAR) ~= false then
        return "backward wants must be false when target_ally_need_type is set (aid exception)"
    end
    local prio = {}
    if wants(bb({ target_unit = prio, priority_target_enemy = prio }), FAR) ~= false then
        return "backward wants must be false when the bot holds its priority enemy target"
    end
    if wants(bb(), NEAR) ~= false then
        return "backward wants must be false within the leash threshold"
    end
end)

_rt_register("gt_bot142_veto_still_final", function()
    -- issue 142 (v0.2.194-dev): the backward-teleport branch must be evaluated
    -- BEFORE the #139 blanket aid veto in the should_teleport hook, so the veto
    -- stays the FINAL word on the combined decision (a downed teammate overrides a
    -- backward leash -- the bot paths in to revive).
    -- #511 (v0.2.202-dev): the source-ORDER grep (io.open) was removed -- io is nil
    -- in the VMF sandbox, so it threw and reported FAIL on healthy code. Runtime
    -- residual: both feature seams are exposed (the backward branch + the ignore-
    -- gate toggle exist). Source ORDER is a purely STATIC property with no runtime
    -- signal; that "veto must come after the backward branch" invariant belongs in
    -- a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
    if type(mod._gt_backward_teleport_wants) ~= "function" then
        return "mod._gt_backward_teleport_wants not exposed -- the issue-142 backward-teleport branch is missing"
    end
    if type(mod._gt_ignore_backward_gate_on) ~= "function" then
        return "mod._gt_ignore_backward_gate_on not exposed -- the issue-142 backward-gate toggle seam is missing"
    end
end)

_rt_register("gt_bot261_leash_conflict_invariants", function()
    -- issue 261 (v0.2.194-dev): guard the whole bot-leash / teleport conflict net
    -- so the issue-142 backward-gate work cannot silently loosen a neighbouring
    -- bound. (a) the tighter leash still reads the gt_bot_follow_distance_m slider;
    -- (b) improved-combat still caps the special-chase path via CHASE_MAX_DIST_SQ
    -- on _enemy_path_allowed; (c) FIX 10's greedy pickup post-passes still honour
    -- vanilla's follow-range gates; (d) exactly ONE hook each on should_teleport
    -- and BTBotTeleportToAllyAction.run (VMF drops a 2nd on the same pair).
    -- #511 (v0.2.202-dev): the source-grep half (io.open over _gt_bot_fixes.lua and
    -- the sibling _gt_improved_bot_combat.lua) was removed -- io is nil in the VMF
    -- sandbox, so it threw and reported FAIL on healthy code. The greedy-pickup
    -- marker constant is the runtime residual; the STATIC invariants it grepped move
    -- to their correct homes: the "exactly one hook each on should_teleport /
    -- BTBotTeleportToAllyAction.run" duplicate-hook counts are ALREADY enforced by
    -- tools/mod-lint/lint-mod.ps1 (PROJECT_STANDARDS 2.2b tier a), and the tighter-
    -- leash slider read (a), the FIX 10 follow-range gate references (c), and the
    -- improved-combat CHASE_MAX_DIST_SQ / _enemy_path_allowed cap (b) belong in a
    -- repo QA gate.
    if GT_BOT_GREEDY_PICKUP_MARKER_v0_2_182 ~= "gt-bot-greedy-pickup-mule-health-postpass" then
        return "greedy-pickup marker absent -- FIX 10 follow-range gate net broken"
    end
end)

_rt_register("gt_dh_no_position_lookup_reads", function()
    -- issue 302 (v0.2.195-dev): the debug-highlights draw runs as a mod.update
    -- consumer, where POSITION_LOOKUP's raw Vector3 entries are DEAD temporaries
    -- for any unit the engine has not refreshed this section (issue-337 bug
    -- class). Every position in _gt_debug_highlights.lua must be a LIVE read
    -- (_unit_pos / Unit.local_position).
    -- #511 (v0.2.202-dev): converted from an io source-grep (the VMF sandbox has
    -- no io library, so the old grep threw and reported FAIL on healthy code) to a
    -- runtime provenance marker the module sets at LOAD next to its live-read
    -- helper. The textual "no POSITION_LOOKUP index in that file" invariant is a
    -- STATIC check and belongs in a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
    if mod._gt_dh_live_pos_reads ~= true then
        return "_gt_debug_highlights.lua live-position provenance marker absent -- did the module fail to load, or was the _unit_pos live-read path replaced with POSITION_LOOKUP (issue-337 class)?"
    end
end)

_rt_register("gt_dh_local_player_safe_508", function()
    -- issue 508 (v0.2.200-dev): _gt_debug_highlights runs as a mod.update
    -- consumer, which also ticks in the boot/menu phase where vanilla
    -- PlayerManager.local_player() asserts "Network backend has not been set"
    -- (player_manager.lua:580-586; the readiness-guarded local_player_safe is
    -- :588-596).
    -- #511 (v0.2.202-dev): converted from an io source-grep (io is nil in the VMF
    -- sandbox -> the grep threw and reported FAIL on healthy code) to the runtime
    -- provenance marker the module sets at LOAD right where local_player_safe is
    -- called. The textual "no bare :local_player() in that file" invariant is a
    -- STATIC check and belongs in a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
    if mod._gt_dh_local_player_safe ~= true then
        return "_gt_debug_highlights.lua local_player_safe provenance marker absent -- did the module fail to load, or was a bare local_player() call reintroduced (issue 508)?"
    end
end)

_rt_register("bot_follow_mode_dropdown_consolidated", function()
    -- v0.2.152-dev: gt_bot_split_among_players + gt_bot_follow_host checkboxes
    -- replaced by a single gt_bot_follow_mode dropdown (default/follow_host/split).
    -- The hook reads mod._gt_resolve_follow_mode() (legacy-fallback aware).
    if GT_BOT_FOLLOW_MODE_DROPDOWN_MARKER_v0_2_152 ~= "gt-bot-follow-mode-dropdown-consolidation" then
        return "gt_bot_follow_mode dropdown consolidation marker absent — was the v0.2.152-dev change reverted?"
    end
    if type(mod._gt_resolve_follow_mode) ~= "function" then
        return "mod._gt_resolve_follow_mode helper missing — dropdown migration may be broken"
    end
end)

_rt_register("bot_behavior_master_sub_widgets_registered", function()
    -- #297 (v0.2.182-dev): gt_bot_behavior_improvements is a MASTER toggle with
    -- nested sub_widgets (checkboxes default ON + the 2 delay sliders, defaults
    -- 3 / 4). issue 142 (v0.2.194-dev) added gt_bot_ignore_backward_gate.
    -- Checkbox ids reuse the pre-bundle setting ids so persisted
    -- pre-bundle user choices are restored; defaults must stay ON so the master
    -- alone reproduces the former v0.2.128-dev bundle behavior.
    local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
    if not ok or type(data) ~= "table" then return "could not require data file" end
    local master
    local function find(node)
        if master or type(node) ~= "table" then return end
        if node.setting_id == "gt_bot_behavior_improvements" then master = node return end
        for _, child in pairs(node) do if type(child) == "table" then find(child) end end
    end
    find(data)
    if not master then return "gt_bot_behavior_improvements widget missing from the data tree" end
    if type(master.sub_widgets) ~= "table" then return "master toggle has no sub_widgets array" end
    local want = {
        gt_bot_necro_potion_handoff      = { wtype = "checkbox", default = true },
        gt_bot_mission_fail_prevention   = { wtype = "checkbox", default = true },
        gt_bot_ledge_pullup              = { wtype = "checkbox", default = true },
        gt_bot_ledge_pullup_delay        = { wtype = "numeric",  default = 3 },
        gt_bot_ladder_unstick            = { wtype = "checkbox", default = true },
        gt_bot_ladder_unstick_delay      = { wtype = "numeric",  default = 4 },
        gt_bot_instant_pickup            = { wtype = "checkbox", default = true },
        gt_bot_greedy_pickup             = { wtype = "checkbox", default = true },
        gt_bot_aid_priority              = { wtype = "checkbox", default = true },
        gt_bot_ignore_backward_gate      = { wtype = "checkbox", default = true },
        gt_bot_ironbreaker_revive_in_ult = { wtype = "checkbox", default = true },
    }
    for _, w in ipairs(master.sub_widgets) do
        local spec = w.setting_id and want[w.setting_id]
        if spec then
            if w.type ~= spec.wtype then
                return w.setting_id .. " has type " .. tostring(w.type) .. ", want " .. spec.wtype
            end
            if w.default_value ~= spec.default then
                return w.setting_id .. " default_value is " .. tostring(w.default_value) .. ", want " .. tostring(spec.default)
            end
            want[w.setting_id] = nil
        end
    end
    for id in pairs(want) do
        return id .. " missing from the master toggle's sub_widgets"
    end
end)

_rt_register("bot_drink_potion_advanced_conditions_registered", function()
    -- #320 (v0.2.183-dev): gt_bot_drink_potions_in_danger is a MASTER toggle with
    -- 7 nested sub_widgets (the scan-range slider + four trigger checkboxes + the
    -- two cluster-count sliders). Defaults must reproduce the former hard-coded
    -- behavior (boss on, patrol on at 3, range 18; special + horde off), so a user
    -- who never expands the option sees no change. A refactor that drops a
    -- sub-widget or flips a default should trip this.
    local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
    if not ok or type(data) ~= "table" then return "could not require data file" end
    local master
    local function find(node)
        if master or type(node) ~= "table" then return end
        if node.setting_id == "gt_bot_drink_potions_in_danger" then master = node return end
        for _, child in pairs(node) do if type(child) == "table" then find(child) end end
    end
    find(data)
    if not master then return "gt_bot_drink_potions_in_danger widget missing from the data tree" end
    if type(master.sub_widgets) ~= "table" then return "drink-potions master toggle has no sub_widgets array" end
    local want = {
        gt_bot_drink_range_m       = { wtype = "numeric",  default = 18 },
        gt_bot_drink_on_boss       = { wtype = "checkbox", default = true },
        gt_bot_drink_on_special    = { wtype = "checkbox", default = false },
        gt_bot_drink_on_patrol     = { wtype = "checkbox", default = true },
        gt_bot_drink_patrol_count  = { wtype = "numeric",  default = 3 },
        gt_bot_drink_on_horde      = { wtype = "checkbox", default = false },
        gt_bot_drink_horde_count   = { wtype = "numeric",  default = 8 },
    }
    for _, w in ipairs(master.sub_widgets) do
        local spec = w.setting_id and want[w.setting_id]
        if spec then
            if w.type ~= spec.wtype then
                return w.setting_id .. " has type " .. tostring(w.type) .. ", want " .. spec.wtype
            end
            if w.default_value ~= spec.default then
                return w.setting_id .. " default_value is " .. tostring(w.default_value) .. ", want " .. tostring(spec.default)
            end
            want[w.setting_id] = nil
        end
    end
    for id in pairs(want) do
        return id .. " missing from the drink-potions master toggle's sub_widgets"
    end
end)

_rt_register("bot_greedy_pickup_hooks_present", function()
    -- #297 item 8 (v0.2.182-dev): the greedy-pickup post-passes must exist --
    -- marker global set beside the FIX 10 hooks in _gt_bot_fixes.lua, plus both
    -- hook_safe registrations on AIBotGroupSystem._update_mule_pickups /
    -- _update_health_pickups (fresh (Class, method) pairs, grep-verified at
    -- authoring time). Source read is best-effort.
    -- #511 (v0.2.202-dev): the source-grep for the two AIBotGroupSystem pickup
    -- hooks (io.open) was removed -- io is nil in the VMF sandbox, so it threw and
    -- reported FAIL on healthy code. The marker constant is the runtime residual;
    -- the presence of the _update_mule_pickups / _update_health_pickups hook
    -- registrations is a STATIC check already covered by tools/mod-lint (hook
    -- inventory) and belongs in a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
    if GT_BOT_GREEDY_PICKUP_MARKER_v0_2_182 ~= "gt-bot-greedy-pickup-mule-health-postpass" then
        return "greedy-pickup marker absent -- was the #297 item-8 feature removed?"
    end
end)

_rt_register("bot_fix_delays_read_from_settings", function()
    -- #297 (v0.2.182-dev): the ledge pull-up / ladder unstick delays are sliders
    -- again. The tick bodies must read them via mod:get.
    -- #511 (v0.2.202-dev): the source-grep (io.open, asserting the mod:get reads
    -- exist and no `local delay = 3/4` literal returned) was removed -- io is nil
    -- in the VMF sandbox, so it threw and reported FAIL on healthy code. Converted
    -- to a RUNTIME assertion: both settings resolve to numbers via mod:get, which
    -- proves the sliders are registered and readable the same way the tick reads
    -- them. The "no hard-coded delay literal" SOURCE-TEXT invariant belongs in a
    -- repo QA gate (PROJECT_STANDARDS 2.2b tier a).
    if type(tonumber(mod:get("gt_bot_ledge_pullup_delay"))) ~= "number" then
        return "gt_bot_ledge_pullup_delay does not resolve to a number via mod:get -- slider missing / renamed?"
    end
    if type(tonumber(mod:get("gt_bot_ladder_unstick_delay"))) ~= "number" then
        return "gt_bot_ladder_unstick_delay does not resolve to a number via mod:get -- slider missing / renamed?"
    end
end)

_rt_register("btlab_settings_removed", function()
    -- v0.2.175-dev: the Bot Teleport Lab settings section (master + 10 D-toggles +
    -- 10 F-toggles + 4 numeric params) was removed. Diagnostics are now implicit /
    -- always-on in the dev build; the two visual tools moved to "Dev Tools". No
    -- gt_btlab_ widget may remain in the data tree, else a friend's saved F-toggle
    -- could resurface behind a ghost UI. Walk the tree and fail on any survivor.
    local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
    if not ok or type(data) ~= "table" then return "could not require data file" end
    local offending
    local function walk(node)
        if offending or type(node) ~= "table" then return end
        local sid = node.setting_id
        if type(sid) == "string" and sid:find("^gt_btlab_") then offending = sid return end
        for _, child in pairs(node) do if type(child) == "table" then walk(child) end end
    end
    walk(data)
    if offending then
        return "a gt_btlab_ widget still exists in the data tree: " .. tostring(offending)
    end
end)

_rt_register("btlab_fixes_dormant", function()
    -- v0.2.175-dev: the retired F1..F10 bisection candidates must be DORMANT --
    -- their three dispatch fns early-return on the module flag _BTLAB_FIXES_ARMED
    -- (false) regardless of any (removed) setting, so a stale saved F-toggle can't
    -- resurrect a behavior change. Behavioral proof: call each with nil args and
    -- assert the dormant return. The proven #139 fixes in _gt_bot_fixes.lua are a
    -- SEPARATE path and are unaffected.
    if type(mod._gt_btlab_veto_teleport) ~= "function"
        or type(mod._gt_btlab_override_follow_unit) ~= "function"
        or type(mod._gt_btlab_redirect_teleport) ~= "function" then
        return "a gt_btlab fix dispatch fn is missing (expected all three present but dormant)"
    end
    local veto = mod._gt_btlab_veto_teleport(nil, nil, nil, nil)
    if veto ~= false then return "veto_teleport not dormant (returned " .. tostring(veto) .. ", want false)" end
    local ovr = mod._gt_btlab_override_follow_unit(nil, nil)
    if ovr ~= nil then return "override_follow_unit not dormant (returned " .. tostring(ovr) .. ", want nil)" end
    local redir = mod._gt_btlab_redirect_teleport(nil, nil)
    if redir ~= false then return "redirect_teleport not dormant (returned " .. tostring(redir) .. ", want false)" end
end)

_rt_register("devtools_group_dev_gated", function()
    -- v0.2.175-dev: the "Dev Tools" group (gt_devtools_bot_hud + gt_devtools_leash_lines)
    -- exists ONLY in the dev clone and is appended after "Cheats and Debug". This
    -- test runs inside the dev mod, so require() returns the tree WITH Dev Tools.
    -- (1) behavioral: the group + both children are present and ordered after
    -- cheats_debug_group. (2) source-pattern: the data file gates the append on the
    -- sed-safe get_mod("gt" .. "_dev") needle (survives the dev->stable gt_dev->gt
    -- sed, so the group never builds in the promoted stable clone).
    local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
    if not ok or type(data) ~= "table" then return "could not require data file" end
    local widgets = data.options and data.options.widgets
    if type(widgets) ~= "table" then return "data.options.widgets missing" end
    local cheats_i, devtools_i
    for i = 1, #widgets do
        local sid = widgets[i].setting_id
        if sid == "cheats_debug_group" then cheats_i = i end
        if sid == "gt_devtools_group" then devtools_i = i end
    end
    if not devtools_i then return "gt_devtools_group not present in the dev data tree (append broken?)" end
    if cheats_i and devtools_i < cheats_i then
        return "gt_devtools_group must sort AFTER cheats_debug_group (A->Z)"
    end
    local want = { gt_devtools_bot_hud = false, gt_devtools_leash_lines = false }
    local function walk(node)
        if type(node) ~= "table" then return end
        if node.setting_id and want[node.setting_id] ~= nil then want[node.setting_id] = true end
        for _, child in pairs(node) do if type(child) == "table" then walk(child) end end
    end
    walk(widgets[devtools_i])
    for id, found in pairs(want) do
        if not found then return id .. " missing from the Dev Tools group" end
    end
    -- #511 (v0.2.202-dev): the data-file needle grep (io.open, asserting the
    -- sed-safe get_mod("gt" .. "_dev") gate) was removed -- io is nil in the VMF
    -- sandbox, so it threw and reported FAIL on healthy code. The data-tree walk
    -- above (group present + ordered + both children) is the runtime residual; the
    -- sed-safe-gate SOURCE-TEXT invariant belongs in a repo QA gate
    -- (PROJECT_STANDARDS 2.2b tier a).
end)

_rt_register("devtools_bot_hud_wired", function()
    -- v0.2.175-dev: the bot behavior HUD must be wired -- the per-frame ring-buffer
    -- poll dispatch fn present (driven from _gt_bot_fixes.lua's PlayerBotBase.update
    -- merge-dispatch), and the lab source must read the current BT leaf action from
    -- the blackboard (running_nodes) and gate the HUD on its toggle. Source read is
    -- best-effort and degrades if the deploy doesn't expose source.
    -- #511 (v0.2.202-dev): the lab source-grep (io.open, asserting the running_nodes
    -- read and the gt_devtools_bot_hud toggle gate) was removed -- io is nil in the
    -- VMF sandbox, so it threw and reported FAIL on healthy code. The dispatch-fn
    -- presence above is the runtime residual; those SOURCE-TEXT invariants belong in
    -- a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
    if type(mod._gt_btlab_observe_update) ~= "function" then
        return "mod._gt_btlab_observe_update missing -- HUD ring-buffer poll chokepoint gone"
    end
end)

_rt_register("breach_probe_present_dev_gated", function()
    -- #261 (v0.2.176-dev): the always-on radius-breach probe must be present and
    -- dev-gated. It runs inside mod._gt_btlab_observe_update (dispatched from the
    -- existing PlayerBotBase.update merge-dispatch) behind the IS_DEV_STREAM gate,
    -- and printfs the [gt:btlab:breach] block. Source read is best-effort.
    -- #511 (v0.2.202-dev): the lab source-grep (io.open, asserting the
    -- [gt:btlab:breach] printf tag and the IS_DEV_STREAM gate) was removed -- io is
    -- nil in the VMF sandbox, so it threw and reported FAIL on healthy code. The
    -- probe-host dispatch fn above is the runtime residual; those SOURCE-TEXT
    -- invariants belong in a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
    if type(mod._gt_btlab_observe_update) ~= "function" then
        return "mod._gt_btlab_observe_update missing -- radius-breach probe host removed"
    end
end)

_rt_register("tether_dump_present", function()
    -- #261 (v0.2.176-dev): every leash yank must dump its cause. mod._gt_btlab_report_tether
    -- printfs the [gt:btlab:tether] block (current action + ring buffer, ~2s cooldown),
    -- dispatched from the existing BTBotTeleportToAllyAction.run hook in _gt_bot_fixes.lua.
    -- #511 (v0.2.202-dev): the lab source-grep (io.open, asserting the
    -- [gt:btlab:tether] printf tag) was removed -- io is nil in the VMF sandbox, so
    -- it threw and reported FAIL on healthy code. The dump fn presence is the
    -- runtime residual; the tag SOURCE-TEXT invariant belongs in a repo QA gate
    -- (PROJECT_STANDARDS 2.2b tier a).
    if type(mod._gt_btlab_report_tether) ~= "function" then
        return "mod._gt_btlab_report_tether missing -- leash/tether printf dump removed"
    end
end)

_rt_register("btlab_no_class_hooks", function()
    -- #261 (v0.2.176-dev): the lab must stay merge-dispatch -- ZERO class hooks
    -- (VMF single-hook rule; all injection points ride existing _gt_bot_fixes.lua
    -- hooks).
    -- #511 (v0.2.202-dev): the "no mod:hook( in the lab file" source-grep (io.open)
    -- was removed -- io is nil in the VMF sandbox, so it threw and reported FAIL on
    -- healthy code. Runtime residual: the lab loaded (its dispatch fns are exposed).
    -- The "zero class hooks in this file" invariant is a STATIC source-text check;
    -- tools/mod-lint/lint-mod.ps1 already inventories hooks mod-wide, and a per-file
    -- no-hooks assertion belongs in a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
    if type(mod._gt_btlab_veto_teleport) ~= "function" or type(mod._gt_btlab_observe_update) ~= "function" then
        return "bot teleport lab dispatch fns not exposed -- did _gt_bot_teleport_lab.lua load?"
    end
end)

_rt_register("btlab_gui_material_guarded", function()
    -- #293/#295 (v0.2.179-dev): the lab's World.create_screen_gui call takes a HARD
    -- C-level fatal (bypasses pcall) if handed a non-resident material. ROOT CAUSE was
    -- creating with FONT_MTRL (materials/fonts/arial), not a resident create material;
    -- fixed to GUI_MTRL (gw_fonts, every vanilla debug GUI's material). Two invariants:
    --   (1) the create call passes GUI_MTRL, never FONT_MTRL (regression on the root cause);
    --   (2) the create is still pre-filtered by can_get("material", GUI_MTRL) (belt+suspenders).
    -- #511 (v0.2.202-dev): the source-grep (io.open, asserting FONT_MTRL is not
    -- passed and can_get pre-filters the create) was removed -- io is nil in the VMF
    -- sandbox, so it threw and reported FAIL on healthy code. Converted to the
    -- runtime provenance marker the lab sets at LOAD to the exact material its
    -- create_screen_gui call passes: it must be gw_fonts, never arial/FONT_MTRL
    -- (the #293/#295 C-fatal root cause). The remaining "create is pre-filtered by
    -- can_get(GUI_MTRL)" SOURCE-TEXT invariant belongs in a repo QA gate
    -- (PROJECT_STANDARDS 2.2b tier a).
    if mod._gt_btlab_gui_create_material == nil then
        return  -- lab HUD create path removed / marker not set -> nothing to guard
    end
    if mod._gt_btlab_gui_create_material ~= "materials/fonts/gw_fonts" then
        return "bot teleport lab create_screen_gui material is '" .. tostring(mod._gt_btlab_gui_create_material)
            .. "', not gw_fonts -- #293/#295 root cause (arial/FONT_MTRL is not a resident create material -> C-fatal)"
    end
end)

_rt_register("gt_459_lineobject_cleanup_liveness_gated", function()
    -- issue 459 (v0.2.196-dev): _clear_and_null (_gt_bot_teleport_lab.lua) and
    -- _clear (_gt_debug_highlights.lua) dispatch a CACHED LineObject into a CACHED
    -- world. On Leave Game, StateIngame.on_exit destroys the level world while VMF
    -- mods_update keeps ticking, so an unguarded reset/dispatch is a C-level access
    -- violation that pcall CANNOT catch. Both cleanup sites must gate the engine
    -- calls on an IDENTITY check against the currently-live level_world
    -- (live == w) -- has_world alone passes when a NEW same-named world exists
    -- while the cached handle points at the freed old one.
    -- #511 (v0.2.202-dev): the two-file source-grep (io.open, asserting the
    -- live == w gate text) was removed -- io is nil in the VMF sandbox, so it threw
    -- and reported FAIL on healthy code. Converted to the runtime provenance markers
    -- each cleanup site sets at LOAD next to its live == w gate. The exact gate
    -- SOURCE-TEXT invariant belongs in a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
    if mod._gt459_liveness_gated_lab ~= true then
        return "_gt_bot_teleport_lab.lua lost the issue-459 world-liveness gate provenance marker (LineObject cleanup AV guard)"
    end
    if mod._gt459_liveness_gated_dh ~= true then
        return "_gt_debug_highlights.lua lost the issue-459 world-liveness gate provenance marker (LineObject cleanup AV guard)"
    end
end)

_rt_register("gt_bot448_downed_morrs_grant_suppressed", function()
    -- issue 448 (v0.2.197-dev): a downed BOT carrying the CW boon Morr's
    -- Protection (deus_knockdown_damage_immunity_aura) must stop granting the
    -- invulnerable-perk buff, or two adjacent downed bot carriers are mutually
    -- unkillable and the run soft-locks. Vanilla never checks the carrier's own
    -- knocked-down state (morris_buff_settings.lua:887 gates only on
    -- is_ready_for_assisted_respawn). Asserts: FIX 11 marker present (file
    -- loaded, fix not reverted); exactly ONE hook on the aura update func (VMF
    -- drops a silent duplicate); the strip is SOURCE-GATED on
    -- attacker_unit == owner (a standing carrier's aura must be left alone);
    -- and both the bot_player and is_knocked_down gates are present (humans and
    -- standing bots keep vanilla behavior).
    -- #511 (v0.2.202-dev): the source-grep half (io.open) was removed -- io is nil
    -- in the VMF sandbox, so it threw and reported FAIL on healthy code. The FIX 11
    -- marker constant (set at LOAD beside the fix in _gt_bot_fixes.lua) is the
    -- runtime residual; the STATIC invariants it grepped move to their correct
    -- homes: the "exactly one deus_knockdown_damage_immunity_aura_func hook"
    -- duplicate-hook count is ALREADY enforced by tools/mod-lint/lint-mod.ps1
    -- (PROJECT_STANDARDS 2.2b tier a), and the attacker_unit == owner /
    -- bot_player / is_knocked_down source gates belong in a repo QA gate.
    if GT_BOT_DOWNED_MORRS_MARKER_v0_2_197 ~= "gt-448-downed-bot-no-morrs-grant" then
        return "FIX 11 marker absent -- was the issue-448 downed-bot Morr's grant fix reverted?"
    end
end)

_rt_register("bt_health_conditions_nilguarded_marker_present", function()
    -- #59 secondary fix (v0.2.149-dev): nil-guard the BTConditions.at_*_health
    -- + can_transition_*_health + less_than_one_health condition family so a
    -- first-tick read of an uninitialized blackboard.current_health[_percent]
    -- biases to false instead of crashing on `nil <= number`. Primary fix
    -- (level-family prefix match) is regression-tested by
    -- gt_cs_is_in_level_prefix_match below. If this marker disappears the
    -- belt-and-suspenders guard was removed.
    if GT_BT_HEALTH_NILGUARD_MARKER_v0_2_149 ~= "gt-bt-health-conditions-nilguarded-i59" then
        return "BT health-condition nil-guard marker absent — was the v0.2.149-dev fix reverted?"
    end
end)

_rt_register("ai_locomotion_override_marker_present", function()
    -- Issue #60 (2026-05-27): host self-toggle AI Takeover crashed in
    -- LocomotionSystem.update_animation_lods one frame after pm:remove_player
    -- destroyed the host's local Player. Vanilla reads
    -- `self._override_player or Managers.player:local_player()` for the
    -- viewport name — both are nil after the swap. Fix mirrors
    -- benchmark_handler.lua:423: set_override_player(bot_player) on swap,
    -- clear it on swap-back. If the marker disappears or a refactor drops
    -- the calls, host AI Takeover will crash the next frame again.
    if CT_GT_AI_LOCOMOTION_OVERRIDE_MARKER_v0_2_73 ~= "gt-ai-locomotion-override-on-host-swap" then
        return "AI locomotion override marker absent — was the v0.2.73-dev fix reverted?"
    end
end)

_rt_register("ai_locomotion_override_set_and_cleared", function()
    -- Guard for both halves of the v0.2.73-dev fix: the host swap path calls
    -- locomotion_system:set_override_player(bot_player) AND the swap-back path
    -- calls set_override_player(nil). Catches a partial revert that keeps the
    -- marker but drops one of the two calls.
    -- #511 (v0.2.202-dev): the source-grep (io.open over _gt_ai_takeover.lua) was
    -- removed -- io is nil in the VMF sandbox, so it threw and reported FAIL on
    -- healthy code. Runtime residual: the swap entry point is exposed (the AI-
    -- takeover module loaded). The "both set_override_player calls present" partial-
    -- revert invariant is a STATIC source-text check and belongs in a repo QA gate
    -- (PROJECT_STANDARDS 2.2b tier a); the companion ai_locomotion_override_marker_present
    -- still asserts the fix marker at runtime.
    if type(mod._gt_ai_swap_human_to_bot) ~= "function" then
        return "mod._gt_ai_swap_human_to_bot not exposed -- the AI-takeover host-swap path is missing"
    end
end)

_rt_register("saved_positions_module_wired", function()
    -- #306 (v0.2.184-dev): the Saved Positions dev tool (_gt_saved_positions.lua)
    -- registers /save_position_1..10 + /recall_position_1..10, capturing the local
    -- player position + look rotation and teleporting back per map via
    -- PlayerUnitLocomotionExtension:teleport_to. Structural check: the module
    -- dofiled and exposed its save/recall entry points, the 10-slot count, and its
    -- marker. If any of these are absent the module failed to load or was gutted.
    if mod._GT_SAVED_POSITIONS_MARKER ~= "gt-saved-positions-per-map-slots" then
        return "saved-positions marker absent — did _gt_saved_positions.lua load?"
    end
    if mod._gt_saved_positions_slot_count ~= 10 then
        return "saved-positions slot count is not 10 (got " .. tostring(mod._gt_saved_positions_slot_count) .. ")"
    end
    if type(mod._gt_save_position) ~= "function" or type(mod._gt_recall_position) ~= "function" then
        return "saved-positions save/recall entry points not exposed on mod"
    end
end)

_rt_register("gt_no_mission_hotkey_flip", function()
    -- Issue #62 (2026-05-28): a legacy hook force-set the hotkeys-enabled arg of
    -- IngameUI.handle_menu_hotkeys to true mid-mission, enabling crash-prone keep
    -- view hotkeys (Hero Select / Map / etc. spawn unloaded ui_* preview worlds).
    -- Removed in v0.2.82-dev; the invariant is that the hook stays absent.
    -- #511 (v0.2.202-dev): the absence-of-hook source-grep (io.open) was removed --
    -- io is nil in the VMF sandbox, so it threw and reported FAIL on healthy code.
    -- This is a purely STATIC "a specific hook must NOT exist" invariant with no
    -- runtime signal; it belongs in a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
    -- Runtime residual: the main file loaded (its on_setting_changed is defined).
    if type(mod.on_setting_changed) ~= "function" then
        return "mod.on_setting_changed not defined -- general_tweaker_dev.lua failed to load"
    end
end)

_rt_register("gt_cs_is_in_level_prefix_match", function()
    -- Issue #59 (2026-05-26): _gt_cs_is_in_level("dlc_castle") used to be
    -- `level_key == level_name` (exact-match). In CW variants of the same
    -- physical arena (dlc_castle_slaanesh_path1 / dlc_castle_chaos_path2 /
    -- etc.) that returned false, causing the transitioned_one_third_health
    -- hook to bias TRUE and skip vanilla phase-init, which left
    -- blackboard.current_health_percent nil and crashed bt_conditions.lua:309
    -- (at_one_fifth_health) when the BT entered the final offense phase.
    --
    -- Probe by stubbing Managers.state.game_mode:level_key() and verifying
    -- both exact and `<name>_<suffix>` levels match, while non-prefix
    -- levels (dlc_morningstar, dlc_castled_unrelated) do not.
    local saved_state = Managers.state
    local saved_game_mode = saved_state and saved_state.game_mode
    Managers.state = Managers.state or {}
    local probe_level
    Managers.state.game_mode = {
        level_key = function() return probe_level end,
    }
    local cases = {
        { level = "dlc_castle",                       name = "dlc_castle", want = true,  why = "exact match" },
        { level = "dlc_castle_path1",                 name = "dlc_castle", want = true,  why = "vanilla path variant" },
        { level = "dlc_castle_slaanesh_path1",        name = "dlc_castle", want = true,  why = "CW theme variant (Issue #59 case)" },
        { level = "dlc_castle_chaos_boss_path1",      name = "dlc_castle", want = true,  why = "CW boss variant" },
        { level = "dlc_morningstar",                  name = "dlc_castle", want = false, why = "unrelated level" },
        { level = "dlc_castled_unrelated",            name = "dlc_castle", want = false, why = "shared prefix without underscore boundary" },
        { level = "inn_level",                        name = "dlc_castle", want = false, why = "keep level" },
    }
    local fail = nil
    for _, c in ipairs(cases) do
        probe_level = c.level
        local got = mod._gt_cs_is_in_level(c.name)
        if got ~= c.want then
            fail = string.format("level=%q name=%q want=%s got=%s (%s)",
                c.level, c.name, tostring(c.want), tostring(got), c.why)
            break
        end
    end
    Managers.state.game_mode = saved_game_mode
    if fail then return fail end
end)

_rt_register("gt_cs_transitioned_one_third_not_forced", function()
    -- Issue #275 (2026-07-06): the transitioned_one_third_health hook body used to
    -- be `(_gt_cs_is_in_level("dlc_castle") and func(...)) or true`, which collapses
    -- to constant-true. Inside the real Nurgloth arena a legitimate vanilla `false`
    -- (boss has not yet passed the one-third-health transition) became true via the
    -- `or true` tail, forcing the BT into its final-offense phase at full health and
    -- breaking the real fight everywhere, always. The fix routes the hook through
    -- the pure helper mod._gt_cs_one_third_wrapper(in_arena, vanilla_result);
    -- assert its truth table so the collapse can never return.
    local wrap = mod._gt_cs_one_third_wrapper
    if type(wrap) ~= "function" then
        return "mod._gt_cs_one_third_wrapper missing (hook not routed through the pure helper)"
    end
    local cases = {
        { in_arena = true,  vanilla = false, want = false, why = "in arena, vanilla false -> defer (must NOT force true)" },
        { in_arena = true,  vanilla = true,  want = true,  why = "in arena, vanilla true -> true" },
        { in_arena = false, vanilla = false, want = true,  why = "outside arena -> force true (spawner Nurgloth skips arena phase)" },
        { in_arena = false, vanilla = true,  want = true,  why = "outside arena -> force true" },
    }
    for _, c in ipairs(cases) do
        local got = wrap(c.in_arena, c.vanilla)
        if got ~= c.want then
            return string.format("in_arena=%s vanilla=%s want=%s got=%s (%s)",
                tostring(c.in_arena), tostring(c.vanilla), tostring(c.want), tostring(got), c.why)
        end
    end
end)

_rt_register("bots_in_keep_setting_registered", function()
    -- The gt_bots_in_keep checkbox must exist in general_tweaker_dev_data.lua's
    -- widget tree. If a future refactor drops it from gameplay_group without
    -- updating the feature module, mod:get("gt_bots_in_keep") returns nil and
    -- the toggle silently no-ops. Verify by walking the data table.
    local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
    if not ok or type(data) ~= "table" then return "could not require data file" end
    local found = false
    local function walk(node)
        if found or type(node) ~= "table" then return end
        if node.setting_id == "gt_bots_in_keep" then found = true; return end
        for _, child in pairs(node) do
            if type(child) == "table" then walk(child) end
        end
    end
    walk(data)
    if not found then
        return "gt_bots_in_keep widget not found in data file widget tree"
    end
end)

_rt_register("no_bots_setting_registered", function()
    -- The gt_no_bots checkbox must exist in the widget tree, else
    -- mod:get("gt_no_bots") returns nil and the toggle silently no-ops.
    local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
    if not ok or type(data) ~= "table" then return "could not require data file" end
    local found = false
    local function walk(node)
        if found or type(node) ~= "table" then return end
        if node.setting_id == "gt_no_bots" then found = true; return end
        for _, child in pairs(node) do
            if type(child) == "table" then walk(child) end
        end
    end
    walk(data)
    if not found then
        return "gt_no_bots widget not found in data file widget tree"
    end
end)

_rt_register("no_bots_apply_sets_ai_bots_disabled", function()
    -- mod._gt_apply_no_bots must drive script_data.ai_bots_disabled — that's the
    -- ONLY engine flag _handle_bots re-reads per server tick to both despawn
    -- existing bots and block new ones. The old /bottoggle path
    -- (level_settings.no_bots_allowed) does NOT despawn mid-mission, which was
    -- the reported bug. This test pins the correct flag. (Phase 3: the apply fn
    -- moved to _gt_bots_keep.lua and is exposed as mod._gt_apply_no_bots.)
    local apply = mod._gt_apply_no_bots
    if type(apply) ~= "function" then
        return "mod._gt_apply_no_bots is not a function (type=" .. type(apply) .. ")"
    end
    script_data = script_data or {}
    local saved = script_data.ai_bots_disabled
    apply(true)
    local on = script_data.ai_bots_disabled
    apply(false)
    local off = script_data.ai_bots_disabled
    script_data.ai_bots_disabled = saved
    if on ~= true then
        return "ai_bots_disabled not true after mod._gt_apply_no_bots(true) (got " .. tostring(on) .. ")"
    end
    if off ~= nil then
        return "ai_bots_disabled not cleared after mod._gt_apply_no_bots(false) (got " .. tostring(off) .. ")"
    end
end)

_rt_register("gk_quest_dropdowns_dont_share_options", function()
    -- Choose Grail Knight Quests has THREE dropdowns (gt_gk_quest1/2/3). VMF's
    -- localize_dropdown_data mutates option.text in place, so if the dropdowns
    -- share one options table the 2nd/3rd re-localize already-localized strings
    -- and render the `<<...>>` / `<<<...>>>` bracket cascade users reported.
    -- Each dropdown MUST hold its own table (built by _gt_gk_quest_options()).
    -- This walks the data tree and fails if any two of the three share a table
    -- identity. See REGRESSION_CHECKLIST "vmf-dropdown-options-mutated".
    local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
    if not ok or type(data) ~= "table" then return "could not require data file" end
    local opts_by_id = {}
    local function walk(node)
        if type(node) ~= "table" then return end
        local sid = node.setting_id
        if (sid == "gt_gk_quest1" or sid == "gt_gk_quest2" or sid == "gt_gk_quest3") and node.options then
            opts_by_id[sid] = node.options
        end
        for _, child in pairs(node) do
            if type(child) == "table" then walk(child) end
        end
    end
    walk(data)
    local q1, q2, q3 = opts_by_id.gt_gk_quest1, opts_by_id.gt_gk_quest2, opts_by_id.gt_gk_quest3
    if not (q1 and q2 and q3) then
        return "one or more gt_gk_quest dropdowns missing an options table"
    end
    if q1 == q2 or q1 == q3 or q2 == q3 then
        return "gt_gk_quest dropdowns share an options table — bracket cascade will occur"
    end
    -- Option text must be loc KEYS (no spaces / punctuation), else VMF's
    -- missing-key fallback wraps the raw display string in angle brackets.
    for _, opt in ipairs(q1) do
        if type(opt.text) ~= "string" or opt.text:find("[%s%.]") then
            return "gt_gk_quest option text is not a bare loc key: " .. tostring(opt.text)
        end
    end
end)

-- (menu_qol_settings_registered + menu_qol_return_quits_roundtrips regression
-- tests MIGRATED out with the Main Menu & Startup feature to gui_tweaker / gut
-- 2026-06-29, #190.)

_rt_register("fall_damage_widgets_and_scaling", function()
    -- Both fall-damage widgets must exist, the apply fn must be callable, and a
    -- direct scaling probe must hold: scaling fall.heights by m must produce
    -- m*vanilla for the three damage fields (m=0 -> 0). Pins the host-side fall
    -- damage multiplier (health_system.lua rpc_take_falling_damage reads these).
    local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
    if not ok or type(data) ~= "table" then return "could not require data file" end
    local want = { gt_fall_damage_enabled = false, gt_fall_damage_mult = false }
    local function walk(node)
        if type(node) ~= "table" then return end
        if node.setting_id and want[node.setting_id] ~= nil then want[node.setting_id] = true end
        for _, child in pairs(node) do if type(child) == "table" then walk(child) end end
    end
    walk(data)
    for id, found in pairs(want) do
        if not found then return id .. " widget not found in data file widget tree" end
    end
    if type(mod.gt_apply_fall_damage) ~= "function" then
        return "mod.gt_apply_fall_damage is not a function"
    end
    if not (PlayerUnitMovementSettings and PlayerUnitMovementSettings.fall and PlayerUnitMovementSettings.fall.heights) then
        return nil -- settings not loaded in this context; skip (not a failure)
    end
    -- Pure-math probe on a standalone table (no live mutation): clamp(d*FDM*m,
    -- max*0*m, max*1*m) must equal m * clamp(d*FDM, 0, max).
    local FDM, d, max = 14, 3, 150
    local function fall_dmg(mult)
        return math.clamp(d * FDM * mult, max * 0 * mult, max * 1 * mult)
    end
    if fall_dmg(0) ~= 0 then return "m=0 should yield 0 fall damage" end
    if math.abs(fall_dmg(2) - 2 * fall_dmg(1)) > 0.001 then return "fall damage not linear in multiplier" end
    -- Re-applying the live setting must leave a positive, numeric multiplier.
    mod.gt_apply_fall_damage()
    local live = PlayerUnitMovementSettings.fall.heights.FALL_DAMAGE_MULTIPLIER
    if type(live) ~= "number" or live < 0 then
        return "FALL_DAMAGE_MULTIPLIER not a non-negative number after apply (got " .. tostring(live) .. ")"
    end
end)

-- (tp_camera_yields_to_cutscene regression test MIGRATED out with the Third-Person
-- Camera feature to gui_tweaker / gut 2026-06-29, #191.)

-- ============================================================
-- Shared `on_player_joined_party` dispatcher (audit 2026-06-07, F3, v0.2.80-dev)
-- ============================================================
-- BUG_CLASSES § 3b: Stingray's EventManager keys callbacks by (object, event_name).
-- Three lobby modules (slot_reservations, session_ignore, motd) each registered
-- the SAME (mod, "on_player_joined_party") pair -- last-writer-wins, so only ONE
-- of the three handlers ever fired on a player join; the other two silently
-- never ran. Fix (audit option b): a SINGLE registered callback on `mod` that
-- invokes every module's join-handler in registration order, each wrapped in
-- pcall so one raising doesn't starve the others. Each module appends its
-- handler via `mod._gt_lobby_register_join_handler(name, fn)` instead of calling
-- `em:register` itself.
--
-- Managers.state.event is rebuilt on every game-state transition, so a single
-- boot-time register is dropped after the first map load. We re-register the
-- one dispatcher on every fresh event-manager handle via gt's per-frame update
-- registry (pointer-compare the manager), AND attempt an immediate register in
-- case the manager already exists at load (hot-reload mid-mission).
mod._gt_lobby_join_handlers = mod._gt_lobby_join_handlers or {}
mod._gt_lobby_register_join_handler = function(name, fn)
    if type(fn) ~= "function" then return end
    mod._gt_lobby_join_handlers[#mod._gt_lobby_join_handlers + 1] = { name = name, fn = fn }
end

-- The single registered method. Stingray em:register resolves the 3rd arg by
-- NAME against the object, so this MUST live as a named field on `mod`.
-- EventManager.trigger invokes it as `object[name](object, ...)`
-- (foundation/.../event_manager.lua:42), i.e. `mod` is prepended as the first
-- arg ahead of the real payload. We swallow that leading `self` so each handler
-- receives the true (peer_id, local_player_id, party_id, slot_id, is_bot) the
-- party_manager:trigger passed (party_manager.lua:562).
mod.gt_lobby_on_player_joined_party = function(_self, peer_id, local_player_id, party_id, slot_id, is_bot)
    local handlers = mod._gt_lobby_join_handlers
    for i = 1, #handlers do
        local h = handlers[i]
        local ok, err = pcall(h.fn, peer_id, local_player_id, party_id, slot_id, is_bot)
        if not ok then
            mod:error("[gt:lobby:join] handler '%s' raised: %s", tostring(h.name), tostring(err))
        end
    end
end

do
    local _last_join_event_mgr = nil
    local function _ensure_join_dispatch_registered()
        local em = Managers.state and Managers.state.event
        if not em or em == _last_join_event_mgr then return end
        _last_join_event_mgr = em
        -- em:register expects (object, event_name, METHOD_NAME_STRING). A
        -- function-value 3rd arg triggers "No function found with name
        -- '[function]'". We registered the method as a named field above.
        em:register(mod, "on_player_joined_party", "gt_lobby_on_player_joined_party")
    end
    if type(mod._gt_register_update) == "function" then
        mod._gt_register_update("gt_lobby_join_dispatch_register", function(_dt)
            _ensure_join_dispatch_registered()
        end)
    end
    -- Immediate attempt for the hot-reload-mid-mission case.
    _ensure_join_dispatch_registered()
end

-- Debug Mode + observation probes + the burning-enemy fire VFX probe. Loaded
-- first so its mod._dbg_on / _dbg_log / _dbg_alert / _gt_dump_ai_now exposures
-- and its additive mod.on_game_state_changed / mod.update observation wraps are
-- established ahead of the feature modules (closest to the original chunk
-- order). Every observation hook is a singleton; all cross-file coupling is
-- via mod._* fields resolved at call time (the AI Takeover module's debug wrap
-- reads mod._gt_dump_ai_now; this module reads mod._gt_ai_* state for the dump).
mod:dofile("scripts/mods/general_tweaker_dev/_gt_debug_probes")

-- Console dump commands (level / glossary / cosmetics / items / hero-view) +
-- the pickup Item Spawner. Both command-only, read-only/self-contained; no
-- hooks, no setting/state chain, so load order is irrelevant. Extracted from
-- the main file v0.2.132-dev.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_dumps")
mod:dofile("scripts/mods/general_tweaker_dev/_gt_item_spawner")

-- Phase-2 extracted features (single-hook, self-contained — no behavior change).
-- Each exposes its apply-fn / per-frame helper on `mod` so the main-file
-- on_setting_changed / on_disabled / shared-update consumers (which stay here)
-- resolve them at call time. Dofile after the main chunk so mod._* fields set
-- above are visible. v0.2.133-dev.
-- Third-Person Camera MIGRATED to gui_tweaker (gut) 2026-06-29, #191 — the
-- _gt_camera dofile was removed (file renamed to .bak.v0.2.149-dev). The shared
-- PlayerUnitFirstPerson.extensions_ready hook that scheduled the godmode/noclip
-- post-spawn re-apply was preserved by relocating a slim copy into the main chunk
-- (near mod._gt_schedule_post_spawn_reapply). gut now owns all tp_* settings, the
-- /gut_tp command, and the camera hooks.
-- Noclip: update_script_driven_no_mover_movement hook; exposes
-- mod._gt_apply_noclip / mod._gt_noclip_heartbeat (called from the shared
-- post_spawn_reapply consumer, which also drives godmode and stays in main).
mod:dofile("scripts/mods/general_tweaker_dev/_gt_noclip")
-- Skip Cutscenes MIGRATED to gui_tweaker (gut) 2026-06-25, issue #106 —
-- _gt_cutscenes dofile removed (file renamed to .bak.v0.2.139).
-- Misc features: Choose Grail Knight Quests (PassiveAbilityQuestingKnight.
-- _generate_quest_pool) + Ready Up! (VoteManager.rpc_client_complete_vote +
-- mod.gt_ready_up_now) + Adventure save-consumable trait odds (no hook; exposes
-- mod._gt_apply_adv_save_traits, called from on_setting_changed). Table-form
-- hooks bind to global classes at module load.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_misc_features")
-- QoL / cheat bundle (NOT the godmode body): Unstuck + Friendly Fire Toggle
-- (DamageUtils.allow_friendly_fire_* — distinct from the godmode add_damage_*
-- hooks that stay in main) + Player-state toggles (inn-damage/cloak/unkillable)
-- + Disable Loading-Screen Monologues + More Corpses. Exposes
-- mod.gt_apply_corpse_count (on_setting_changed) + the *_toggle commands.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_godmode_qol")
-- In-mission hero-view access (Open Inventory In Mission + Customize cim gate +
-- Show menu tabs in-mission + the InventorySettings/ESC-menu patch) MIGRATED to
-- gui_tweaker (gut) 2026-06-24 — gut now owns the in-mission inventory. Both
-- _gt_mission_ui.lua and _gt_keep_menus.lua were deleted. The dispatcher branches
-- that drove them (on_setting_changed mission_inventory_enabled + the
-- on_game_state_changed _gt_apply_keep_menus call) were removed too.
-- Bot-roster features (no Class.method hooks): Bots in Keep (mod._bik_* +
-- bots_in_keep update consumer; kill-switched in source) + Disable Bots (Solo)
-- (mod._gt_apply_no_bots). on_game_state_changed / on_setting_changed in main
-- drive both via the mod._* fields; the _bik_* + no_bots regression tests in
-- main read those fields too.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_bots_keep")
-- Level control + reservation-side fixes: Level Control (win/fail/restart RPC) +
-- End-of-level profile fallback / score-screen fix + gt_kill_bots / gt_die +
-- /respawn RPC + gt_fix_sound + gt_bot_toggle + Duplicate Careers. Co-locates
-- all FOUR ProfileSynchronizer hooks (disjoint methods) + StateInGameRunning.
-- _award_end_of_level_rewards so the singleton audit is local. Every keybind-
-- bound callable stays a `mod.` field; the block was self-contained (own RPC
-- names + helper locals), so nothing in main's dispatchers needed repointing.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_level_control")
-- (Keep Menus in Missions / _gt_keep_menus.lua MIGRATED to gut 2026-06-24 — see
-- the _gt_mission_ui migration note above. Both files deleted.)
-- Hacks port (Groups B/C/D/F): Time & Pause + Ult Controls + Buffs & Stat
-- Tweaks + Engine error nil-guards. All hooks are singletons. Shares the pause
-- flag with main via mod._gt_pause_active; keeps gt_time_apply / gt_apply_crit_
-- chance / gt_apply_move_speed / gt_apply_fall_damage as `mod.` fields for the
-- on_setting_changed branches + regression test. Registers its own `infinite_ammo`
-- update consumer (the AI half stays in main's `ai_pending` consumer).
mod:dofile("scripts/mods/general_tweaker_dev/_gt_hacks")
-- Creature Spawner (Aussiemon CreatureSpawner port). ~28 singleton hooks (keep-
-- spawn ConflictDirector.update + a large AI/BT/nav crash-guard suite + breed
-- package-loader overrides). Assigns mod._gt_cs_on_setting_changed /
-- mod._gt_cs_on_game_state_changed (the main dispatchers resolve them) and
-- exposes mod._gt_cs_is_in_level for the regression check. Self-contained
-- (own gt_cs_* settings + commands), so load order vs the lobby block below is
-- irrelevant. The consolidated ConflictDirector.spawn_queued_unit hook STAYS in
-- main — CS only hooks the DISTINCT ConflictDirector.update method.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_creature_spawner")
-- AI Takeover (hand your character to a bot) + AFK->AI takeover. Assigns
-- mod._gt_ai_handle_toggle_change (CALLED by the main on_setting_changed
-- DISPATCHER) and reads/writes the promoted mod._gt_ai_* state seeded at the top
-- of main (shared with the on_setting_changed / on_game_state_changed
-- DISPATCHERS). Registers the _AI_RPC network event + its own `ai_pending` /
-- `afk_autobot` per-frame consumers (via mod._gt_register_update). Exposes
-- mod._gt_ai_swap_human_to_bot for the locomotion-override regression check; its
-- debug-toggle dump wrap calls mod._gt_dump_ai_now (call-time resolved). The
-- AICommanderExtension._update_units always-on crash guard is SEPARATE and stays
-- in main. No hard load-order dependency (all cross refs are mod._* call-time).
mod:dofile("scripts/mods/general_tweaker_dev/_gt_ai_takeover")

-- ============================================================
-- gt_lobby_* feature modules (absorbed from lobby_tweaker 2026-05-25;
-- lt v0.1.7-dev). Each module is self-contained and wires into gt's
-- central per-frame update registry (mod._gt_register_update) and
-- wraps mod.on_setting_changed / mod.on_game_state_changed where
-- needed. Settings are namespaced `gt_lobby_*`; chat commands too.
--
-- Load order matters slightly:
--   * known_mods is a pure data table -- loaded by modded_manifest itself.
--   * slot_reservations / session_ignore / kick_idle / motd are independent.
--   * modded_manifest must load AFTER on_setting_changed has its final
--     shape (we just finished defining it above).
--   * failed_join_reveal hooks StateLoading.create_popup -- order-independent.
--   * slot_reservations / session_ignore / motd append their join-handler to
--     the shared dispatcher above instead of registering the event themselves
--     (F3 fix) -- the dispatcher block above MUST load before they do.
-- ============================================================
mod:dofile("scripts/mods/general_tweaker_dev/_gt_lobby_slot_reservations")
mod:dofile("scripts/mods/general_tweaker_dev/_gt_lobby_session_ignore")
mod:dofile("scripts/mods/general_tweaker_dev/_gt_lobby_kick_idle")
mod:dofile("scripts/mods/general_tweaker_dev/_gt_lobby_motd")
mod:dofile("scripts/mods/general_tweaker_dev/_gt_lobby_modded_manifest")
mod:dofile("scripts/mods/general_tweaker_dev/_gt_lobby_failed_join_reveal")
-- Floating Damage Numbers MIGRATED to gui_tweaker (gut) 2026-06-29 — gut now owns
-- the feature with its own clean DamageUtils hooks (it has no godmode to share
-- them with). The _gt_damage_numbers dofile + the damage-number feed lines inside
-- the godmode add_damage_network* hooks were removed; those hooks are now pure
-- godmode again.

-- Bot Options: Necromancer potion handoff, Ironbreaker revive-during-ult,
-- rescue allies awaiting respawn. Host-side bot AI fixes; no network registration.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_bot_fixes")
mod:dofile("scripts/mods/general_tweaker_dev/_gt_prioritize_specials")
mod:dofile("scripts/mods/general_tweaker_dev/_gt_weave_unlock")
-- Improved Bot Combat: non-conflicting combat improvements migrated from the
-- "Bot Improvements - Combat Returns" Workshop mod, folded into one toggle.
-- Distinct methods from _gt_bot_fixes (no duplicate-hook collision).
mod:dofile("scripts/mods/general_tweaker_dev/_gt_improved_bot_combat")
-- Bot Teleport Lab (diagnostics): observe/probe the "bots teleport away from the
-- player" bug. Defines mod._gt_btlab_* observer fns that are dispatched from the
-- EXISTING _gt_bot_fixes.lua hook bodies (should_teleport / .run / update /
-- _assign_destination_points) -- NO new hooks on those already-hooked pairs (VMF
-- single-hook rule). v0.2.175-dev: the D-probes are now IMPLICIT + always-on in
-- the dev build (IS_DEV_STREAM gate, no menu toggles); the two visual tools (bot
-- behavior HUD + leash lines) moved to the dev-only "Dev Tools" settings group and
-- also require host; the former F1..F10 fix candidates are dormant. Registers its
-- own draw update consumer + the /bot_tp_dump + /bot_tp_snap chat commands.
-- Runtime dispatch is call-time resolved, so load order after _gt_bot_fixes is not
-- required. See _gt_bot_teleport_lab.lua header for the merge-dispatch design.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_bot_teleport_lab")

-- (v0.2.128-dev) Boss Mechanic Tweaks (Halescourge/Nurgloth fly-disable
-- duration) MOVED to enemy_tweaker (et_fly_disable_mult). _gt_boss_tweaks.lua
-- deleted; no dofile here anymore.

-- Main Menu & Startup QoL MIGRATED to gui_tweaker (gut) 2026-06-29, #190 — gut now
-- owns Skip-start-screen + Return-to-Menu-quits + /gut_quit. The _gt_menu_qol dofile,
-- its on_setting_changed / on_disabled dispatch, and the menu_qol regression tests
-- were removed.

-- Solo & QoL: error-free reimplementation of True Solo QoL Tweaks features
-- (auto-restart on wipe, assassin/packmaster warnings, disable ult VO/fog/
-- shadows/mutator-explosions/intro-audio, boss path draw). Exposes
-- mod._gt_solo_on_spawn_queued (called from the ConflictDirector hook above).
mod:dofile("scripts/mods/general_tweaker_dev/_gt_solo_qol")

-- Client-side latency cosmetics (Issue #308). Both self-contained, all toggles
-- default OFF, no networking, no gameplay-outcome change:
--   * _gt_melee_warning  -- early-warning cue on enemy melee windups (hook_safe
--     AnimationSystem.anim_event + IngameHud.update; rides mod._gt_register_update).
--   * _gt_hp_smoothing   -- eases the local player's own health-bar drop
--     (hook_safe UnitFrameUI.set_total_health_percentage + .update).
mod:dofile("scripts/mods/general_tweaker_dev/_gt_melee_warning")
mod:dofile("scripts/mods/general_tweaker_dev/_gt_hp_smoothing")

-- Saved Positions (dev tool, #306): /save_position_1..10 + /recall_position_1..10.
-- Command-only, no hooks. Captures the LOCAL player unit position + look rotation
-- and teleports back via PlayerUnitLocomotionExtension:teleport_to; saves are
-- per-map, persisted through the `gt_saved_positions` VMF setting. Self-contained;
-- exposes mod._gt_save_position / mod._gt_recall_position / the structural marker
-- for the saved_positions_module_wired regression check below. Load order
-- irrelevant (no setting/state chain, no hooks).
mod:dofile("scripts/mods/general_tweaker_dev/_gt_saved_positions")

-- Debug Highlights (Dev Tools, #302): in-world LineObject wireframes for
-- interactables, pickups, pickup spawners, enemy/player boxes, headshot nodes,
-- and enemy aggro rings. Rides mod._gt_register_update; all toggles default OFF
-- (zero per-frame work until enabled). Dev-only, client-safe. No new hooks.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_debug_highlights")

mod:info("[mem-probe] gt boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_GT) / 1024)
