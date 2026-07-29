local mod = get_mod("gt_dev")

local MOD_VERSION = "0.2.259-dev"
-- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic).
-- On the mod table, not a bare _G global (issue 510 class) and not a new
-- top-level local (this chunk lives near the 200-local ceiling).
mod._mem_probe_t0 = collectgarbage("count")
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
-- v2 adds the authenticated host result/acknowledgement message and makes the
-- request sender authoritative; old v1 peers fail closed instead of entering
-- a half-swapped state.
mod.GT_AI_RPC_SCHEMA = 2

-- Shared-debug-draw RPC schema versioning (VMF_RECIPES.md § 10, issue 534).
-- The `gt_draw_leash` broadcast (host -> gt peers; sender + receiver both in
-- _gt_bot_teleport_lab.lua) prepends this as the FIRST positional arg of every
-- send and validates it as the first arg of the receiver. VMF network messages
-- reach only peers running gt_dev, so the payload never touches a vanilla peer
-- (zero wire-safety exposure); a peer on a different gt_dev build fails the
-- match and the receiver drops the snapshot -- no draw, no crash. Defined here
-- (mirroring GT_LOBBY_RPC_SCHEMA / GT_AI_RPC_SCHEMA) so the module reads it at
-- call time and the /gt_regression_test check below can assert it cross-module.
-- Bump ONLY when the `gt_draw_leash` payload shape changes. Initial value is 1;
-- never define lower.
mod.GT_DRAW_RPC_SCHEMA = 1

-- Creature-spawner client-request RPC schema versioning (VMF_RECIPES.md § 10,
-- issue 693). The `gt_cs_request` client->host spawn/destroy request and the
-- `gt_cs_ack` host->client acknowledgement (sender + receiver both in
-- _gt_creature_spawner.lua) prepend this as the FIRST positional arg of every
-- send and validate it as the first arg of the receiver. VMF network messages
-- reach only peers running gt_dev, so the payload never touches a vanilla peer
-- (zero wire-safety exposure); a peer on a different gt_dev build fails the
-- match and the host drops the request gracefully -- no spawn, no crash. Bump
-- ONLY when the `gt_cs_request`/`gt_cs_ack` payload shape changes. Initial
-- value is 1; never define lower.
mod.GT_CS_RPC_SCHEMA = 1

-- Copied shared debug helper (master: tools/shared_lib/_lib_debug.lua). The
-- bundled copy keeps gt_dev standalone while exact-drift QA prevents a local
-- edit from returning issue 240's mod:warning chat spam.
-- v0.2.55: NOTE — the file ALSO redeclares `_dbg` (without prefix) inside the
-- per-frame observation hooks block further down, which shadows this top-of-
-- file definition for everything below that point.
local _dbg, _dbg_alert = mod:dofile("scripts/mods/general_tweaker_dev/_lib_debug")(mod, "[gt:dbg]")

-- Exposed for sibling `_gt_lobby_*` modules (and any future external file
-- that needs gt's debug-helpers). _dbg is VMF mod:debug; _dbg_alert is
-- log-only engine printf (#427).
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
mod._gt_godmode_damage_peers = mod._gt_godmode_damage_peers or {}
local _gt_godmode_damage_peers = mod._gt_godmode_damage_peers
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
    local strike_damage_on = on and mod:get("gt_godmode_strike_damage") == true
    _gt_godmode_damage_peers[peer] = strike_damage_on and _gt_net_clock or nil
    local vmf = get_mod("VMF")
    if vmf and vmf.ping_vmf_users then pcall(vmf.ping_vmf_users) end
    -- Optional trailing flag preserves the schema-1 base contract: older peers
    -- ignore it, while a new host can authoritatively apply #549 for its client.
    pcall(function()
        mod:network_send(_GT_GODMODE_RPC, "others", _GT_GODMODE_RPC_SCHEMA,
            on and true or false, strike_damage_on)
    end)
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

-- #247 v0.2.239-dev: the owner-destructive conversion is retired.  The active
-- implementation keeps the human Player and party slot, uses native observer /
-- force-respawn boundaries, and gives a temporary real bot the required free
-- slot.  This emergency field remains callable by dispatchers and can be set
-- true at runtime if in-game verification uncovers an engine regression.
mod._gt_ai_takeover_disabled         = false

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
mod._gt_rt_register = _rt_register
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
    if mod._gt_player_stat_hud_reset then mod._gt_player_stat_hud_reset() end
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
    -- #304: state transitions can flip DamageUtils.is_in_inn and rebuild every
    -- AI extension. Reconcile tracked dummies after either edge; the module's
    -- exact keep gate restores vanilla radius outside an inn level.
    if mod._gt_apply_keep_dummy_collision then
        mod._gt_apply_keep_dummy_collision(mod:get("gt_keep_dummy_no_collision"))
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
    if setting_id == "gt_devtools_player_stat_hud"
        or setting_id == "gt_player_stat_hud_mode"
        or setting_id == "gt_player_stat_hud_position"
        or setting_id == "gt_player_stat_hud_scale" then
        if mod._gt_player_stat_hud_reset then mod._gt_player_stat_hud_reset() end
    elseif setting_id == "godmode_enabled" then
        _apply_godmode(mod:get("godmode_enabled") or false)
    elseif setting_id == "gt_godmode_strike_damage" then
        -- The host needs the client's child-toggle state at the same damage
        -- authority seam as base godmode. Refresh immediately; heartbeat heals
        -- a cold VMF handshake exactly like the parent state.
        _gt_godmode_broadcast(_godmode)
    elseif setting_id == "gt_godmode_unlimited_ammo" then
        -- Ammo is consumed on the owning machine; no child-state RPC is needed.
        if mod._gt_reconcile_infinite_ammo then mod._gt_reconcile_infinite_ammo() end
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
    elseif setting_id == "gt_keep_dummy_no_collision" then
        if mod._gt_apply_keep_dummy_collision then
            mod._gt_apply_keep_dummy_collision(mod:get("gt_keep_dummy_no_collision"))
        end
    elseif setting_id == "gt_bot_command_wheel" and not mod:get("gt_bot_command_wheel") then
        if mod._gt359_clear_commands then mod._gt359_clear_commands() end
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
        if mod._gt332_reconcile_client_corpses then
            mod._gt332_reconcile_client_corpses()
        end
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
            -- The emergency gate already emits its specific refusal; do not
            -- stack the generic line in that case.
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
    -- Unlike the older broad global mutations documented below, #304 owns a
    -- bounded per-extension snapshot and can unwind immediately.
    if mod._gt_restore_keep_dummy_collision then mod._gt_restore_keep_dummy_collision() end
    if mod._gt359_clear_commands then mod._gt359_clear_commands() end
    if mod._gt_player_stat_hud_reset then mod._gt_player_stat_hud_reset() end
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
    if mod._gt_reconcile_infinite_ammo then mod._gt_reconcile_infinite_ammo() end
end

-- Receive other peers' godmode state (see _gt_godmode_peers rationale near the
-- top of the file). Validates the schema arg per VMF_RECIPES.md §10.
mod:network_register(_GT_GODMODE_RPC, function(sender_peer_id, schema, on, strike_damage_on)
    if sender_peer_id == nil or schema ~= _GT_GODMODE_RPC_SCHEMA then
        return
    end
    -- Store the local clock at receipt; _gt_godmode_active expires the entry if
    -- the sender stops heartbeating (clean godmode-off even if its send dropped).
    _gt_godmode_peers[sender_peer_id] = (on == true) and _gt_net_clock or nil
    _gt_godmode_damage_peers[sender_peer_id] =
        (on == true and strike_damage_on == true) and _gt_net_clock or nil
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

-- Issue #529: exported for the godmode stamina gate merged into the EXISTING
-- GenericStatusExtension.add_fatigue_points hook in _gt_hacks.lua (one hook per
-- (Class, method) — the infinite-stamina wrapper already owns that pair). The
-- closure reads the live _godmode / _gt_godmode_peers upvalues, so the export
-- stays current without re-assignment. Consumers must nil-check (dofile order).
mod._gt_godmode_active = _gt_godmode_active

-- Issue #549: outgoing damage is host-authoritative for a joining client's
-- weapon hit, so the child toggle rides the existing heartbeat and is resolved
-- against the attacking HUMAN's peer here. Bots are excluded for the same
-- host-peer ownership reason as base godmode.
local function _gt_godmode_strike_damage_active(unit)
    if not unit then return false end
    local pm = Managers.player
    if not pm then return false end
    if _godmode and mod:get("gt_godmode_strike_damage") == true then
        local lp = pm:local_player()
        if lp and lp.player_unit == unit then return true end
    end
    if not next(_gt_godmode_damage_peers) then return false end
    local owner = pm.owner and pm:owner(unit)
    if not owner or not owner.is_player_controlled or not owner:is_player_controlled() then
        return false
    end
    local seen = _gt_godmode_damage_peers[owner.peer_id]
    return seen ~= nil and (_gt_net_clock - seen) < _GT_GODMODE_TIMEOUT
end
mod._gt_godmode_strike_damage_active = _gt_godmode_strike_damage_active

-- Pure truth table shared by the live hook and /gt_regression_test. Requiring a
-- positive vanilla result preserves immune/invalid hits at zero; enemy scope
-- prevents the cheat from turning friendly fire or self damage into 9999.
mod._gt549_should_override_outgoing = function(damage, is_enemy, attacker_active, source_active)
    return type(damage) == "number" and damage > 0 and is_enemy == true
        and (attacker_active == true or source_active == true)
end
mod._GT_549_GODMODE_POWER_MARKER = "gt-549-godmode-power-and-ammo"

-- PRE-FLIGHT: this is gt's only DamageUtils.apply_buffs_to_damage hook. Vanilla
-- has already populated victim_units and applied target mitigation by the time
-- func returns [src: scripts/helpers/damage_utils.lua:2134-2450]. Both damage
-- funnels consume that return before the authoritative health write [src:
-- damage_utils.lua:1783-1831, 1916-1987], making this the narrow shared seam.
mod._gt_bot_hazard_policy = mod:dofile("scripts/mods/general_tweaker_dev/_gt_bot_hazard_resistance_policy")
mod:dofile("scripts/mods/general_tweaker_dev/_gt_bot_hazard_resistance")
mod:hook("DamageUtils", "apply_buffs_to_damage", function(func, current_damage,
        attacked_unit, attacker_unit, damage_source, victim_units, damage_type,
        buff_attack_type, first_hit, source_attacker_unit)
    local damage = func(current_damage, attacked_unit, attacker_unit, damage_source,
        victim_units, damage_type, buff_attack_type, first_hit, source_attacker_unit)
    -- #488: host-owned bots gain independent gas/warpfire resistance stacks.
    -- Consolidated here because this is GT's singleton final-damage hook.
    damage = mod._gt488_scale_bot_hazard_damage(
        damage, attacked_unit, damage_source, damage_type)
    local source_active = source_attacker_unit
        and _gt_godmode_strike_damage_active(source_attacker_unit) or false
    local attacker_active = _gt_godmode_strike_damage_active(attacker_unit)
    local actual_attacker = source_active and source_attacker_unit or attacker_unit
    local is_enemy = actual_attacker and attacked_unit
        and DamageUtils.is_enemy(actual_attacker, attacked_unit) or false
    if mod._gt549_should_override_outgoing(damage, is_enemy, attacker_active, source_active) then
        return 9999
    end
    return damage
end)

-- Issue #548: damage immunity alone does not suppress the separate player
-- stagger funnel. Boss hits calculate damage and then call stagger_player, so
-- returning zero from add_damage_network still allowed launches. Drop only the
-- stagger application for a godmode human; no persistent status flag is
-- written, so toggling godmode cannot clobber another immunity source.
mod:hook("DamageUtils", "stagger_player", function(func, unit, ...)
    if _gt_godmode_active(unit) then
        return
    end
    return func(unit, ...)
end)
mod._gt548_stagger_gate_wired = true

-- Debuffs use a separate buff funnel and the report does not identify their
-- authored template names. Capture each unique template automatically while
-- godmode is active so an ordinary reproduction supplies the exact deny-list
-- evidence. Observation-only and session-capped to prevent log spam.
local _gt548_seen_buffs = {}
local _gt548_seen_count = 0
local _GT548_MAX_BUFF_RECORDS = 24
mod:hook("BuffExtension", "add_buff", function(func, self, template_name, ...)
    local unit = self and self._unit
    if unit and _gt_godmode_active(unit) and _gt548_seen_count < _GT548_MAX_BUFF_RECORDS
       and not _gt548_seen_buffs[template_name] then
        _gt548_seen_buffs[template_name] = true
        _gt548_seen_count = _gt548_seen_count + 1
        pcall(printf, "[gt:548] godmode buff observed template=%s count=%d/%d",
            tostring(template_name), _gt548_seen_count, _GT548_MAX_BUFF_RECORDS)
    end
    return func(self, template_name, ...)
end)
mod._gt548_buff_probe_wired = true

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

-- ============================================================
-- Issue #469: bots immune to environment / mutator AOE damage
-- ============================================================
-- Bots cannot path around certain live-event / Chaos Wastes / hazard AOE fields
-- and die to them repeatedly. This makes BOTS (never humans) ignore a CURATED
-- set of such damage. It is HOST-AUTHORITATIVE and needs no wire work: bots are
-- owned by the host's peer, so the host is the machine that applies their damage
-- and its decision is final. We alter only the LOCAL damage event (return 0) --
-- sending nothing networked, touching no NetworkLookup key and no _max_ health
-- field (max-resource doctrine). A client never applies a host-bot's damage, so
-- gating on `Managers.player.is_server` keeps this a pure host decision; unlike
-- the client-godmode case there is no client-authoritative bot to broadcast for.
--
-- Two funnels carry these hits, BOTH already hooked for godmode below, so the
-- checks are MERGED into those hook bodies (VMF drops a 2nd hook on a pair --
-- repo CLAUDE.md NON-NEGOTIABLE 8):
--   * add_damage_network_player -- explosion / profile AOE. Identify by the
--     resolved `damage_profile.name` (a reliable key: every DamageProfileTemplates
--     entry gets `.name` set = its table key [src: scripts/settings/equipment/
--     damage_profile_templates.lua:5646-5650]). damage_source is NOT used here --
--     timed_explosion sources pass the shared "undefined" [src: scripts/
--     unit_extensions/weapons/area_damage/timed_explosion_extension.lua:125].
--   * add_damage_network        -- liquid / DoT AOE. Identify by `damage_source`.
--
-- CURATION over blanket: each entry is individually justified + cited. Boss slams,
-- warpfire, gas, and friendly-fire bombs are DELIBERATELY EXCLUDED so bots still
-- take them. Gas is out on purpose -- issue #469 asks for REDUCED (not zero) gas
-- damage, which needs a scalar multiplier and is a separate refinement.
mod._gt_bot_aoe_immune_profiles = {
    -- Weaves / Twitch "Lightning Strike" mutator -> timed_explosion using
    -- ExplosionTemplates.lightning_strike_twitch, damage_profile below.
    -- [src: scripts/settings/mutators/mutator_lightning_strike.lua:44,49;
    --  scripts/settings/explosion_templates.lua:1406,1417]
    heavens_lightning_strike       = "Lightning Strike mutator",
    -- Chaos Wastes Khorne "Skulls of Fury" curse -> exploding skulls.
    -- [src: scripts/settings/mutators/mutator_curse_skulls_of_fury.lua:44-48;
    --  scripts/settings/dlcs/morris/morris_buff_settings.lua:5165-5174]
    curse_skulls_of_fury_explosion = "Khorne Skulls of Fury curse",
    -- Chaos Wastes Tzeentch "Bolt of Change" curse -> the blue-fire bolt AOE
    -- (same bot-cannot-path-around class as the Khorne skull curse).
    -- [src: scripts/settings/mutators/mutator_curse_bolt_of_change.lua:141-147;
    --  scripts/settings/dlcs/morris/morris_buff_settings.lua:5040-5050]
    bolt_of_change                 = "Bolt of Change curse",
}
mod._gt_bot_aoe_immune_sources = {
    -- Oil / lamp-oil barrel ground fire pool (damage_type "burn").
    -- [src: scripts/unit_extensions/weapons/area_damage/liquid/liquid_area_damage_templates.lua:768-770;
    --  scripts/unit_extensions/weapons/area_damage/liquid/liquid_area_damage_extension.lua:29,793]
    lamp_oil_fire = "oil-barrel ground fire",
}

-- True only for a BOT-owned player unit: bots have a Player owner whose
-- is_player_controlled() is false (humans -> true, enemies -> no owner). Mirrors
-- the bot/human split the godmode predicate uses at _gt_godmode_active.
mod._gt_unit_is_bot = function(unit)
    if not unit then return false end
    local pm = Managers.player
    if not pm or not pm.owner then return false end
    local owner = pm:owner(unit)
    if not owner or not owner.is_player_controlled then return false end
    return not owner:is_player_controlled()
end

-- Godmode HP-damage block (host-self path). add_damage_network carries DoTs,
-- explosions (bombs) and other already-final damage values. (The floating-damage-
-- numbers feed that used to share this hook MIGRATED to gui_tweaker / gut
-- 2026-06-29 — gut registers its own DamageUtils hooks, so this is pure godmode
-- again.) damage_amount is the function's single return value; return it unchanged
-- when godmode is off.
-- Signature expanded through arg 8 (damage_source) for the #469 check below;
-- hit_position/damage_direction/damage_source are captured and forwarded verbatim.
mod:hook("DamageUtils", "add_damage_network", function(func, attacked_unit, attacker_unit, original_damage_amount, hit_zone_name, damage_type, hit_position, damage_direction, damage_source, ...)
    if _gt_godmode_active(attacked_unit) then return 0 end
    -- #469 bot AOE immunity (liquid / DoT funnel). Cheap table-miss on the hot
    -- path; the host/bot/setting checks only run when the source is curated.
    if attacked_unit then
        local why = damage_source and mod._gt_bot_aoe_immune_sources[damage_source]
        if why and (Managers.player and Managers.player.is_server) and mod._gt_unit_is_bot(attacked_unit)
           and mod:get("gt_bot_behavior_improvements") and mod:get("gt_bot_aoe_immunity") then
            printf("[gt:469] bot AOE-immune: negated %s (damage_source=%s type=%s)", why, tostring(damage_source), tostring(damage_type))
            return 0
        end
    end
    return func(attacked_unit, attacker_unit, original_damage_amount, hit_zone_name, damage_type, hit_position, damage_direction, damage_source, ...)
end)

-- Godmode HP-damage block (player-weapon / pvp-profile path). (Floating-damage-
-- numbers feed MIGRATED to gut 2026-06-29 — see note above.) Return the original
-- damage unchanged when godmode is off.
mod:hook("DamageUtils", "add_damage_network_player", function(func, damage_profile, target_index, power_level, attacked_unit, attacker_unit, hit_zone_name, hit_position, attack_direction, damage_source, hit_ragdoll_actor, boost_curve_multiplier, is_critical_strike, ...)
    if _gt_godmode_active(attacked_unit) then return 0 end
    -- #469 bot AOE immunity (explosion / profile funnel). Identify by
    -- damage_profile.name; damage_source is the shared "undefined" here.
    if attacked_unit and damage_profile then
        local pname = damage_profile.name
        local why = pname and mod._gt_bot_aoe_immune_profiles[pname]
        if why and (Managers.player and Managers.player.is_server) and mod._gt_unit_is_bot(attacked_unit)
           and mod:get("gt_bot_behavior_improvements") and mod:get("gt_bot_aoe_immunity") then
            printf("[gt:469] bot AOE-immune: negated %s (profile=%s damage_source=%s)", why, tostring(pname), tostring(damage_source))
            return 0
        end
    end
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
    -- Freeze AI (#303, dev-only) blocks new spawns too, via the same gate as the
    -- /no_enemies toggle. mod._gt_freeze_ai_active is only ever set on the dev
    -- stream host (nil elsewhere), so this OR is a no-op in stable.
    if mod:get("disable_enemy_spawns") or mod._gt_freeze_ai_active then return nil, nil end
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

-- Effective spawn-block = the /no_enemies toggle OR the dev-only Freeze AI state
-- (#303). ORing both sources here means neither one toggling off clobbers the
-- other's write, and Freeze AI reuses the identical vanilla-respected
-- script_data.ai_*_disabled flag set that /no_enemies already drives.
_apply_script_data_no_enemies = function(enabled)
    script_data = script_data or {}
    local block = enabled or mod._gt_freeze_ai_active
    for _, name in ipairs(_AI_SPAWN_FLAGS) do
        script_data[name] = block or nil
    end
end

-- Re-applies the combined block from current state. Freeze AI (_gt_freeze_ai.lua,
-- dofiled below) calls this after flipping mod._gt_freeze_ai_active so the two
-- sources stay composed. Resolved at call time; safe before the module loads.
mod._gt_apply_spawn_block = function()
    _apply_script_data_no_enemies(mod:get("disable_enemy_spawns"))
end

_apply_script_data_no_enemies(mod:get("disable_enemy_spawns"))

_rt_register("issue242_all_spawn_classes_blocked", function()
    local required = {
        ai_mini_patrol_disabled = true,
        ai_boss_spawning_disabled = true,
        ai_horde_spawning_disabled = true,
        ai_roaming_spawning_disabled = true,
        ai_specials_spawning_disabled = true,
        ai_critter_spawning_disabled = true,
    }
    for _, name in ipairs(_AI_SPAWN_FLAGS) do
        required[name] = nil
    end
    for name in pairs(required) do
        return "missing spawn-block flag: " .. name
    end
    if type(mod._gt_apply_spawn_block) ~= "function" then
        return "spawn-block reapply boundary missing"
    end
end)

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
-- after the main chunk). It exposes mod.gt_apply_corpse_count, resolved at call
-- time from the on_setting_changed branch for gt_more_corpses_*. Client-local
-- retention at the authoritative husk-destroy seam lives in
-- _gt_client_ragdolls.lua (#332).
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

-- Regression checks receive private helpers; live state resolves through `mod` at run time.
local _gt_regression_checks = mod:dofile("scripts/mods/general_tweaker_dev/_gt_regression_checks")
_gt_regression_checks.install(mod, _rt_register, {
    CT_GT_PICKUP_LOOKUP_RAWGET_MARKER_v0_2_48 = CT_GT_PICKUP_LOOKUP_RAWGET_MARKER_v0_2_48,
    CT_GT_AI_CLIENT_SEND_MARKER_v0_2_52 = CT_GT_AI_CLIENT_SEND_MARKER_v0_2_52, dbg = _dbg, dbg_alert = _dbg_alert,
})

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
-- Issue #309: observation-only host disconnect lifecycle trace. Loaded before
-- _gt_debug_probes so its existing add_remote_player singleton can dispatch
-- reconnect evidence into this module without registering a duplicate hook.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_disconnect_grace_diag")
-- Issue #753: transition-only service-loss diagnostics. Observes measured
-- Steam availability, PlayFab disconnect state, and NetworkClient failure;
-- dev-only and read-only, with no recovery or network mutation.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_diag_disconnect_failure")
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
mod:dofile("scripts/mods/general_tweaker_dev/_gt_client_ragdolls")
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
-- #659: observation-only trace across Raise Dead targeting, finish, passive,
-- and authoritative spawn boundaries. The prior lifecycle flag hypothesis was
-- falsified by log #940; this module identifies the first actual failing seam.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_necro_keep_trace")
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
-- Freeze AI (#303, dev-only). Registers /freezeai + exposes mod.gt_freeze_ai_toggle
-- (the Dev Tools keybind's function_call target) and drives mod._gt_freeze_ai_active,
-- read by the merged AISystem.update_brains gate in _gt_creature_spawner.lua and by
-- the spawn hook + _apply_script_data_no_enemies in main. Call-time cross refs, so
-- load order is irrelevant; the module early-outs (registers nothing) off the dev stream.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_freeze_ai")
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
mod:dofile("scripts/mods/general_tweaker_dev/_gt_lobby_appearance_parity")
mod:dofile("scripts/mods/general_tweaker_dev/_gt_network_transmit_guard")
-- Floating Damage Numbers migrated to gui_tweaker (gut) 2026-06-29; its old
-- dofile/feed lines are gone and gt's damage hooks are pure godmode again.

-- Host-side bot options and AI fixes; no network registration.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_bot_pickups")
mod:dofile("scripts/mods/general_tweaker_dev/_gt_bot_consumables")
mod._gt_teleport_loop_policy = mod:dofile("scripts/mods/general_tweaker_dev/_gt_teleport_loop_policy")
mod:dofile("scripts/mods/general_tweaker_dev/_gt_bot_fixes")
mod:dofile("scripts/mods/general_tweaker_dev/_gt_prioritize_specials")
mod:dofile("scripts/mods/general_tweaker_dev/_gt_weave_unlock")
-- Offline Twitch mode + native candidate allow-list controls (#333). Reuses
-- vanilla vote timing, random resolution, UI and RPCs; host authoritative.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_offline_twitch")
-- Improved Bot Combat: non-conflicting combat improvements migrated from the
-- "Bot Improvements - Combat Returns" Workshop mod, folded into one toggle.
-- Distinct methods from _gt_bot_fixes (no duplicate-hook collision).
mod:dofile("scripts/mods/general_tweaker_dev/_gt_improved_bot_combat")
-- Bot command wheel (#359): adds a host-only second page using vanilla's
-- already-networked Versus event IDs. Temporary hold/follow/urgent-target state
-- is bounded and composes through the existing destination-assignment hook.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_bot_command_wheel")
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
-- Godmode indicator (#381) owns no hook; it exports a bounded draw consumer to
-- the melee-warning module's existing singleton IngameHud.update dispatcher.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_godmode_indicator")
mod:dofile("scripts/mods/general_tweaker_dev/_gt_melee_warning")
mod:dofile("scripts/mods/general_tweaker_dev/_gt_hp_smoothing")

-- Keep dummy no-collision (#304): removes only the per-unit player locomotion
-- constrain radius while enabled in an inn level. The dummy's actors/hitzones
-- remain intact. Owns the distinct AISimpleExtension.init and
-- AiHuskBaseExtension.init post-hooks; no networking.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_dummy_collision")

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

-- Live player-stat HUD (#797). The default-off overlay preserves retained
-- BuffExtension stage/source identity, uses the engine's deterministic equation
-- for complete consumer paths and exact retained factors, reconciles
-- authoritative getters, and labels downstream/proc/dynamic paths unsupported.
-- Provenance rebuilds only on lifecycle edges; values sample at 4 Hz through
-- gt's singleton HUD-composite hook.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_diag_player_stats")

mod:info("[mem-probe] gt boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - mod._mem_probe_t0) / 1024)
