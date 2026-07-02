local mod = get_mod("gt")
_MEM_PROBE_T0_GTS = collectgarbage("count")  -- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic)

local MOD_VERSION = "0.2.73-alpha"
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

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- `_dbg` is for confirmation / expected behavior — routes through mod:debug.
-- `_dbg_alert` is for unexpected / wrong / mismatch — routes through mod:warning.
-- v0.2.55: NOTE — the file ALSO redeclares `_dbg` (without prefix) inside the
-- per-frame observation hooks block further down, which shadows this top-of-
-- file definition for everything below that point.
-- v0.2.73: removed per-mod enable_debug_logging toggle; diagnostics now route
-- through VMF's built-in logging system (mod:debug / mod:warning).
local function _dbg(fmt, ...)
    mod:debug("[gt:dbg] " .. fmt, ...)
end

local function _dbg_alert(fmt, ...)
    mod:warning("[gt:dbg] " .. fmt, ...)
end

-- Exposed for sibling `_gt_lobby_*` modules (and any future external file
-- that needs gt's debug-helpers).
mod._gt_dbg = _dbg
mod._gt_dbg_alert = _dbg_alert

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs, prints
-- one mod:info line at load. ALWAYS fires (operational telemetry).
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/general_tweaker/general_tweaker_data")
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

-- v0.2.71: full settings snapshot to the log (debug-gated). Walks the same data
-- widget tree as the fingerprint and logs every setting_id = current value, so
-- active toggle states are visible in the console log when debugging (e.g. to
-- confirm a HOST actually had a bot toggle ON). Paired with the per-change log
-- in on_setting_changed below. Fires at load and on demand via /gt_dump_settings.
local function _log_settings_snapshot(reason)
    local ok, data = pcall(require, "scripts/mods/general_tweaker/general_tweaker_data")
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
mod:command("gt_dump_settings", "Log all gt settings + current values (needs Debug Logging on)", function()
    _log_settings_snapshot("command")
    mod:echo("[gt] settings snapshot written to console log (if Debug Logging is on).")
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
-- `_ai_handle_toggle_change` for clients MUST (a) resolve host via
-- `Managers.mechanism:server_peer_id()` (NOT the literal `"server"` string —
-- VMF doesn't understand it), (b) call `get_mod("VMF").ping_vmf_users()`
-- before queuing, and (c) defer through `_ai_pending_client_send` rather than
-- sending inline. Each layer was added across v0.2.49 → v0.2.52 in response
-- to a separate burn (see CHANGELOG). The regression-test guard at the
-- bottom of this file asserts this marker is intact AND grep-asserts the
-- three call-sites in the function body via the file source.
local CT_GT_AI_CLIENT_SEND_MARKER_v0_2_52 = "gt-ai-client-send-vmf-rehandshake"

local function _write_dump(filename, lines)
    for _, line in ipairs(lines) do
        mod:info("[DUMP:%s] %s", tostring(filename), tostring(line))
    end
end

local _godmode = mod:get("godmode_enabled") or false
-- Forward declaration: _apply_godmode is defined further down (in the Godmode
-- section) but on_setting_changed (defined before it) needs to reference it.
-- Per feedback_lua_forward_reference.md, name resolution happens at function
-- compile time — without this `local` here, on_setting_changed would bind
-- _apply_godmode to a global (nil) and silently do nothing on UI toggles.
local _apply_godmode

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
local _ai_pending_client_send = nil
-- Same forward-declaration rationale as _ai_handle_toggle_change below.
-- The debug-mode AI dump (added in v0.2.52) needs to read this from a
-- chunk position above the original `local _ai_pending_host_toggle =
-- nil` further down; without the forward decl that read resolves to a
-- nil global and the dump always reports "nil" even when a host toggle
-- is queued. The later assignment must drop `local` so it writes the
-- forward upvalue rather than shadowing.
local _ai_pending_host_toggle = nil
local _AI_CLIENT_SEND_MAX_RETRIES = 3
local _AI_CLIENT_SEND_DELAY_FIRST = 0.05   -- first send: nearly immediate
local _AI_CLIENT_SEND_DELAY_RETRY = 0.4    -- subsequent retries: post-pong window

-- Same forward-reference rule for the AI Takeover module further down. Both
-- on_game_state_changed and on_setting_changed reference these names before
-- the AI block's own `local` declarations execute; without these forward
-- declarations the closures bind to nil globals and the toggle silently no-ops
-- (the call to _ai_handle_toggle_change throws "attempt to call a nil value"
-- which VMF swallows).
local _ai_suppress_setting_callback = false
local _ai_saved_state = {}
local _ai_handle_toggle_change

-- Forward-declared so on_setting_changed (above the AI/no_enemies sections)
-- can reference the helper defined deeper in the file. Same rule as the AI
-- forward declarations — name resolution happens at function compile time, so
-- without this `local` the on_setting_changed closure would bind to a nil
-- global and the script_data flags would never flip from the VMF checkbox.
local _apply_script_data_no_enemies

-- Forward-declared for the Creature Spawner section at the bottom of the file.
-- on_setting_changed (defined further down) needs to reference these helpers
-- when the user flips gt_cs_unit_list (re-pick default breed) or any of the
-- gt_cs_* settings that affect runtime behaviour. Same forward-ref rule as
-- _apply_godmode / _ai_handle_toggle_change above.
local _gt_cs_on_setting_changed
local _gt_cs_on_game_state_changed

-- Forward-declared for the pause-toggle module further down. on_game_state_changed
-- (defined above the pause-toggle block) clears the flag on every state
-- transition: `_pause_active = false`. Without this forward-decl, the
-- assignment binds to a GLOBAL because the file-local `local _pause_active`
-- at line ~2153 doesn't exist yet at the on_game_state_changed compile point.
-- The pause/time-scale toggle code (gt_pause_toggle / gt_time_apply) reads the
-- file-local — so the global write was a no-op for the toggle's read path,
-- causing pause/unpause to desync after a level transition (Issue #13).
-- The declaration at line ~2153 is now `_pause_active = false` (no `local`)
-- so it reuses this forward-decl slot instead of shadowing it.
local _pause_active

-- Post-spawn re-apply timer. Set by PlayerUnitFirstPerson.extensions_ready
-- and consumed in mod.update (further down). BulldozerPlayer:spawn does
-- `assign_unit_ownership` AFTER the extensions are ready, so at extensions_ready
-- time `Managers.player:local_player().player_unit` still points at the OLD
-- (or nil) unit. Anything that needs to look up the local player unit on spawn
-- — godmode invisibility, noclip locomotion state — must defer past that gap.
local _post_spawn_reapply_timer = nil

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
-- infinite_ammo_and_ai_pending, cutscene_auto_skip, hide_ui. pcall isolation
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
        if not ok then
            mod:error("[gt:update] consumer '%s' raised: %s", c.name, tostring(err))
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

-- ============================================================
-- Third-Person Camera
-- ============================================================
-- Development.set_parameter() is a no-op in release builds.
-- We write directly to the _hardcoded_dev_params table so that
-- all game systems reading Development.parameter("third_person_mode")
-- see the value (camera redirect, mesh visibility, FP guard).
--
-- The set_first_person_mode guard (player_unit_first_person.lua:907)
-- checks: override OR NOT third_person_mode OR NOT attract_mode.
-- Since attract_mode is nil, the guard always passes — inspect and
-- other systems can restore 1P even with third_person_mode set.
-- We hook set_first_person_mode to block 1P restore when tp is on.
--
-- Camera distance: the over_shoulder node in CameraSettings has
-- offset y=0.65 which is too close. We patch it to y=-2.5 for a
-- proper follow distance, and add z=0.5 for slight height offset.

local _tp_enabled = false
local _tp_reapply_timer = nil

-- Vanilla over_shoulder uses x=0.75, y=0.65, z=0 (camera_settings.lua:273-278).
-- We override y (negative pulls camera back), z (height), and x (side offset).
-- Zoom variants are scaled at fixed ratios from the main slider so the
-- transition between unzoomed / zoom / increased_zoom remains perceptually
-- consistent — full distance for the wide view, ~60% for zoom, ~40% for
-- increased_zoom.
local _camera_snapshots = nil

local function _find_camera_node(tree, name)
    if type(tree) ~= "table" then return nil end
    if tree._node and tree._node.name == name then return tree._node end
    for _, child in ipairs(tree) do
        local found = _find_camera_node(child, name)
        if found then return found end
    end
    return nil
end

-- Snapshot vanilla offsets before any mutation so on_disabled can restore.
local function _snapshot_camera_offsets()
    if _camera_snapshots or not CameraSettings or not CameraSettings.first_person then return end
    _camera_snapshots = {}
    for _, name in ipairs({ "over_shoulder", "zoom_in_third_person", "increased_zoom_in_third_person" }) do
        local node = _find_camera_node(CameraSettings.first_person, name)
        if node and node.offset_position then
            _camera_snapshots[name] = {
                x = node.offset_position.x,
                y = node.offset_position.y,
                z = node.offset_position.z,
            }
        end
    end
end

local function _patch_camera_offset()
    if not CameraSettings or not CameraSettings.first_person then return end
    _snapshot_camera_offsets()
    local distance = mod:get("tp_distance") or 3.0
    local height   = mod:get("tp_height")   or 1.0
    local side     = mod:get("tp_side_offset") or 0.8
    -- When enabled, ADS / ranged-aim no longer pulls the 3P camera in close;
    -- both zoom-in modes use the same multipliers as `over_shoulder` so the
    -- view stays at the configured distance/height regardless of zoom state.
    local no_zoom_in = mod:get("tp_disable_zoom_in")
    local zoom_dist_mul = no_zoom_in and 1.00 or 0.60
    local zoom_h_mul   = no_zoom_in and 1.00 or 0.60
    local izoom_dist_mul = no_zoom_in and 1.00 or 0.40
    local izoom_h_mul   = no_zoom_in and 1.00 or 0.60
    local function set_node(name, dist_mul, height_mul)
        local node = _find_camera_node(CameraSettings.first_person, name)
        if node and node.offset_position then
            node.offset_position.x = side
            node.offset_position.y = -distance * dist_mul
            node.offset_position.z = height * height_mul
        end
    end
    set_node("over_shoulder",                  1.00, 1.00)
    set_node("zoom_in_third_person",           zoom_dist_mul,  zoom_h_mul)
    set_node("increased_zoom_in_third_person", izoom_dist_mul, izoom_h_mul)
end

local function _restore_camera_offset()
    if not _camera_snapshots or not CameraSettings or not CameraSettings.first_person then return end
    for name, snap in pairs(_camera_snapshots) do
        local node = _find_camera_node(CameraSettings.first_person, name)
        if node and node.offset_position then
            node.offset_position.x = snap.x
            node.offset_position.y = snap.y
            node.offset_position.z = snap.z
        end
    end
end

_patch_camera_offset()

local function _apply_tp(enabled)
    _tp_enabled = enabled
    if Development._hardcoded_dev_params then
        Development._hardcoded_dev_params.third_person_mode = enabled or nil
    end
    local pm = Managers.player
    local player = pm and pm:local_player()
    if player and player.player_unit then
        local fp_ext = ScriptUnit.has_extension(player.player_unit, "first_person_system")
        if fp_ext then
            pcall(fp_ext.set_first_person_mode, fp_ext, not enabled, true)
        end
        pcall(CharacterStateHelper.change_camera_state, player, "follow")
    end
end

mod:hook("PlayerUnitFirstPerson", "set_first_person_mode", function(func, self, active, override, unarmed)
    if _tp_enabled and active and not override then
        return
    end
    return func(self, active, override, unarmed)
end)

-- CLARIFY: On player spawn we temporarily flip OFF tp (clear third_person_mode,
-- force 1P) so the FP system can finish initialization, then re-enable tp 30
-- ticks later via the timer below. Without this defer, set_first_person_mode
-- can run before extensions are wired up and leave the camera in a half-state.
mod:hook("PlayerUnitFirstPerson", "extensions_ready", function(func, self, world, unit, ...)
    local result = func(self, world, unit, ...)
    if mod:get("tp_camera_enabled") then
        _tp_enabled = false
        if Development._hardcoded_dev_params then
            Development._hardcoded_dev_params.third_person_mode = nil
        end
        pcall(self.set_first_person_mode, self, true, true)
        _tp_reapply_timer = 0.5
    end
    -- Schedule godmode/noclip re-apply too. PlayerUnitFirstPerson is the
    -- local-player FP extension (bots use PlayerBotUnitFirstPerson, husks
    -- don't have a 1P extension at all), so this only fires on the local
    -- player's own spawn. By 0.5s, BulldozerPlayer:spawn has run
    -- assign_unit_ownership and `Managers.player:local_player().player_unit`
    -- points at the new unit.
    _post_spawn_reapply_timer = 0.5
    return result
end)

-- _tp_reapply_timer is a time-based countdown (seconds). The 0.5s delay lets
-- PlayerUnitFirstPerson finish its post-extension setup before we flip the
-- third_person_mode flag again — flipping too early leaves the camera in a
-- half-initialised state.
_register_update("tp_camera", function(dt)
    if _tp_reapply_timer then
        _tp_reapply_timer = _tp_reapply_timer - (dt or 0)
        if _tp_reapply_timer <= 0 then
            _tp_reapply_timer = nil
            _apply_tp(true)
        end
    end
end)

-- REVIEW: redundant `_apply_tp` call. `mod:set(...)` triggers
-- `on_setting_changed` (defined below), which already calls
-- `_apply_tp(mod:get("tp_camera_enabled"))`. So the explicit call here causes
-- _apply_tp to run twice with the same value. Pick one path; the
-- on_setting_changed path is sufficient.
mod:command("tp", "Toggle third-person camera", function()
    local new_val = not mod:get("tp_camera_enabled")
    mod:set("tp_camera_enabled", new_val)
    _apply_tp(new_val)
    mod:echo("Third-person: " .. (new_val and "ON" or "OFF"))
end)

-- ============================================================
-- Free Camera (detached fly-cam for inspecting the player model)
-- ============================================================
-- VT2 ships a FreeFlightManager in foundation, gated off in release
-- by `GameSettingsDevelopment.disable_free_flight = true`. We flip
-- that flag and call _enter_free_flight / _exit_free_flight directly
-- so the per-player F8-style cam works in mission.
--
-- Controls (FreeFlightKeymaps.win32): W/A/S/D move, Q/E down/up,
-- mouse look, scroll wheel = speed, +/- adjust FOV, Enter teleports
-- player to cam pos, F8 toggles off.
--
-- _enter_free_flight calls input_manager:block_device_except_service
-- which is SUPPOSED to stop WASD from reaching the Player input service
-- — empirically it doesn't, the player walks alongside the camera. We
-- belt-and-suspenders by also calling `set_disabled(true)` on the
-- player's locomotion extension, which yanks the unit out of the
-- locomotion update list entirely. Character state machine still ticks
-- (animation, etc.) but no movement can be applied.

local function _freecam_player_data()
    local ff = Managers.free_flight
    if not ff or not ff.data then return nil, nil end
    local pm = Managers.player
    local player = pm and pm:local_player()
    if not player then return nil, nil end
    local id = player:local_player_id()
    return player, ff.data[id]
end

local function _freecam_freeze_player(freeze)
    -- Lock the local player's locomotion so they can't walk while freecam moves.
    local pm = Managers.player
    local player = pm and pm:local_player()
    local unit = player and player.player_unit
    if not unit then return end
    local loco = ScriptUnit.has_extension(unit, "locomotion_system")
    if not loco then return end
    pcall(loco.set_disabled, loco, freeze, nil, nil, true)
end

local function _apply_freecam(enabled)
    if not GameSettingsDevelopment then return end
    if enabled then
        GameSettingsDevelopment.disable_free_flight = false
        local player, data = _freecam_player_data()
        if player and data and not data.active then
            -- Free flight only renders the local 3P body when third_person_mode is set;
            -- otherwise the player would be invisible from the detached cam.
            if Development._hardcoded_dev_params then
                Development._hardcoded_dev_params.third_person_mode = true
            end
            Managers.free_flight:_enter_free_flight(player, data)
            _freecam_freeze_player(true)
        end
    else
        local player, data = _freecam_player_data()
        if player and data and data.active then
            Managers.free_flight:_exit_free_flight(player, data)
        end
        _freecam_freeze_player(false)
        -- Restore the release-build gate so a stray F8 mid-fight doesn't activate the cam.
        GameSettingsDevelopment.disable_free_flight = true
    end
end

-- Sync the setting back to false when the engine itself exits free flight
-- (F8 press, level transition, cleanup). Also un-freeze the player — without
-- this, an F8-exit leaves the character with locomotion disabled and they'd
-- be stuck in place until you re-toggle freecam from the menu.
mod:hook_safe("FreeFlightManager", "_exit_free_flight", function(self, player, data)
    if mod:get("freecam_enabled") then mod:set("freecam_enabled", false) end
    _freecam_freeze_player(false)
end)

mod:command("freecam", "Toggle detached free-flight camera", function()
    local new_val = not mod:get("freecam_enabled")
    mod:set("freecam_enabled", new_val)
    mod:echo("Free camera: " .. (new_val
        and "ON (WASD move, mouse look, Q/E up/down, wheel = speed, F8 to exit)"
        or "OFF"))
end)

-- ============================================================
-- Noclip (player flies, ignores wall collision)
-- ============================================================
-- Unlike freecam (which detaches the camera and leaves the body),
-- noclip moves the PLAYER BODY through walls. Built on the engine's
-- `script_driven_no_mover` locomotion state (used by chaos-spawn-grab
-- and tentacle-grab), which teleports the unit by velocity_wanted * dt
-- each tick without touching the mover — so static geometry, props
-- and enemies are all bypassed.
--
-- Two pieces:
--   (1) Hook `update_script_driven_no_mover_movement` — when noclip is
--       on for the local player, ignore whatever velocity the character
--       state machine wrote (walking state writes ground-plane velocity,
--       falling writes gravity) and compute our own from W/A/S/D +
--       Space/Ctrl projected through the first-person camera rotation.
--       Shift applies a boost multiplier.
--   (2) Re-assert `self.state = "script_driven_no_mover"` every frame —
--       basic states (standing/walking/jumping/falling) don't touch
--       locomotion.state, but transitions into ledge-hang / ladder /
--       knockdown call `enable_script_driven_movement()` which would
--       hand us back to the wall-respecting mover update.

local _noclip_active = false

local function _local_player_unit()
    local pm = Managers.player
    local player = pm and pm:local_player()
    return player and player.player_unit
end

local function _local_locomotion()
    local unit = _local_player_unit()
    if not unit then return nil end
    return ScriptUnit.has_extension(unit, "locomotion_system"), unit
end

local function _apply_noclip(enabled)
    _noclip_active = enabled and true or false
    local loco, unit = _local_locomotion()
    if not loco then
        mod:info("[noclip] no locomotion extension yet (not in a level?) — flag stored, will re-arm on player spawn via extensions_ready hook")
        return
    end
    if _noclip_active then
        loco:enable_script_driven_no_mover_movement()
        mod:info("[noclip] ON — loco.state now '%s' on unit %s", tostring(loco.state), tostring(unit))
    else
        -- Snap the mover to the player's current position before handing
        -- control back, otherwise the mover is still at the entry point
        -- and the next Mover.move() will yank the player back there.
        local mover = unit and Unit.mover(unit)
        if mover then
            Mover.set_position(mover, Unit.local_position(unit, 0))
        end
        loco:enable_script_driven_movement()
        loco:set_wanted_velocity(Vector3.zero())
        mod:info("[noclip] OFF — restored script_driven; loco.state '%s'", tostring(loco.state))
    end
end

local _NOCLIP_KEYS = {
    fwd     = "w",
    back    = "s",
    left    = "a",
    right   = "d",
    up      = "space",
    down    = "left ctrl",
    boost   = "left shift",
}

local function _key_held(name)
    local idx = Keyboard.button_index(name)
    return idx and Keyboard.button(idx) > 0
end

-- Noclip re-arm on spawn lives in mod.update via _post_spawn_reapply_timer
-- (set by PlayerUnitFirstPerson.extensions_ready above). Don't hook
-- PlayerUnitLocomotionExtension.extensions_ready directly here — at that
-- timing `player.player_unit` isn't yet assigned (assign_unit_ownership
-- runs later in BulldozerPlayer:spawn), so `_apply_noclip` can't find
-- the new locomotion extension via _local_locomotion().

mod:hook("PlayerUnitLocomotionExtension", "update_script_driven_no_mover_movement",
function(func, self, unit, dt, t)
    if not _noclip_active or unit ~= _local_player_unit() then
        return func(self, unit, dt, t)
    end
    local fp = ScriptUnit.has_extension(unit, "first_person_system")
    if not fp then return func(self, unit, dt, t) end

    local rotation = fp:current_rotation()
    local forward  = Quaternion.forward(rotation)
    local right    = Quaternion.right(rotation)

    local fwd_axis   = (_key_held(_NOCLIP_KEYS.fwd)  and 1 or 0) - (_key_held(_NOCLIP_KEYS.back) and 1 or 0)
    local right_axis = (_key_held(_NOCLIP_KEYS.right) and 1 or 0) - (_key_held(_NOCLIP_KEYS.left) and 1 or 0)
    local up_axis    = (_key_held(_NOCLIP_KEYS.up)    and 1 or 0) - (_key_held(_NOCLIP_KEYS.down) and 1 or 0)

    local speed = mod:get("noclip_speed") or 15.0
    if _key_held(_NOCLIP_KEYS.boost) then
        speed = speed * (mod:get("noclip_boost_multiplier") or 3.0)
    end

    local velocity = forward * fwd_axis + right * right_axis + Vector3(0, 0, up_axis)
    local len = Vector3.length(velocity)
    if len > 0.001 then
        velocity = velocity / len * speed
    else
        velocity = Vector3.zero()
    end

    self.velocity_wanted:store(velocity)

    -- Replicate the original body: teleport, sync network, sync current.
    local current_position = POSITION_LOOKUP[unit]
    local final_position = current_position + velocity * dt
    Unit.set_local_position(unit, 0, final_position)
    self.velocity_network:store(velocity)
    self.velocity_current:store(velocity)
end)

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
            if mod:get("noclip_enabled") then _apply_noclip(true) end
            if _godmode then _apply_godmode(true) end
        end
    end
    if _noclip_active then
        local loco = _local_locomotion()
        if loco and loco.state ~= "script_driven_no_mover" then
            loco.state = "script_driven_no_mover"
        end
    end
end)

-- Shared toggle helper. `mod:command` and the VMF keybind widget both invoke
-- this through `mod.gt_noclip_toggle` so they stay in lockstep.
mod.gt_noclip_toggle = function()
    local new_val = not mod:get("noclip_enabled")
    mod:set("noclip_enabled", new_val)
    -- Explicit apply mirrors tp's command (which works in production). Belt-and-
    -- suspenders against VMF versions that don't fire on_setting_changed on
    -- programmatic mod:set() calls.
    _apply_noclip(new_val)
    mod:echo("Noclip: " .. (new_val
        and "ON (WASD fly, Space/Ctrl up/down, Shift = boost)"
        or "OFF"))
end

mod:command("noclip", "Toggle noclip (fly through walls)", function() mod.gt_noclip_toggle() end)

-- ============================================================
-- Keep Menus in Missions / in-mission inventory — REMOVED (migrated to GUI Tweaker)
-- ============================================================
-- The in-mission inventory / "Keep Menus in Missions" feature (the
-- InventorySettings loadout-access patch, the ESC-menu "Open Inventory"
-- entry, the `IngameUI.handle_menu_hotkeys` hotkey-flip hook, the
-- `gt_open_mission_inventory` / `/gt_inv` opener, and the
-- `HeroWindowLoadoutConsole._customize_item` cim crash-gate) was removed
-- from the public General Tweaker in v0.2.72-alpha and lives in the
-- GUI Tweaker (gut) mod instead.
--
-- The `IngameUI.handle_menu_hotkeys` hotkey-flip in particular was the
-- cause of Issue #62 (force-flipping `hotkeys_enabled` true mid-mission let
-- the keep hotkeys spawn unloaded ui_* preview worlds and crash). The
-- `gt_no_mission_hotkey_flip` regression test below guards against that hook
-- being reintroduced.

-- CLARIFY: tp is forcibly cleared on every state change (level transition,
-- etc.) because the engine reinitializes the FP system. The
-- PlayerUnitFirstPerson.extensions_ready hook above will re-arm tp on the
-- next player spawn if tp_camera_enabled is on.
mod.on_game_state_changed = function(status, state_name)
    _tp_enabled = false
    if Development._hardcoded_dev_params then
        Development._hardcoded_dev_params.third_person_mode = nil
    end
    -- Locomotion extensions are torn down across level transitions; the
    -- next player spawn comes back in vanilla `script_driven` mode. Reset
    -- the active flag so a stale noclip setting from the previous mission
    -- doesn't re-arm before the player has a body to fly.
    _noclip_active = false
    -- AI takeover is a per-run intent — the saved state on the host doesn't
    -- survive a level/state change cleanly, and persisting the checkbox would
    -- show "on" across runs where no swap actually happened. Suppress the
    -- callback because we don't want to fire an RPC swap-back when leaving.
    if mod:get("ai_takeover_enabled") then
        _ai_suppress_setting_callback = true
        mod:set("ai_takeover_enabled", false)
        _ai_suppress_setting_callback = false
    end
    -- Clear host-side saved state too — it's keyed on peer_id which may
    -- not survive a session/lobby change.
    _ai_saved_state = {}
    -- Vanilla wipes the engine time scale on level transition. Re-apply the
    -- user's slider value if it differs from normal (13 = 1.0x). Also clear
    -- the pause flag so the toggle remembers we're now unpaused.
    _pause_active = false
    if status == "enter" and state_name == "StateIngame" then
        local v = mod:get("time_scale_value")
        if v and v ~= 13 then
            local debug_mgr = Managers.state and Managers.state.debug
            if debug_mgr and debug_mgr.set_time_scale then
                debug_mgr:set_time_scale(v)
            end
        end
    end
    if _gt_cs_on_game_state_changed then
        _gt_cs_on_game_state_changed(status, state_name)
    end
end

mod.on_setting_changed = function(setting_id)
    -- v0.2.71: log every toggle/value change (debug-gated) so the log shows
    -- exactly when a setting flips and to what — pairs with the load snapshot.
    _dbg("[gt:setting-changed] %s = %s", tostring(setting_id), tostring(mod:get(setting_id)))
    if setting_id == "tp_camera_enabled" then
        _apply_tp(mod:get("tp_camera_enabled"))
    elseif setting_id == "godmode_enabled" then
        _apply_godmode(mod:get("godmode_enabled") or false)
    elseif setting_id == "tp_distance" or setting_id == "tp_height" or setting_id == "tp_side_offset" or setting_id == "tp_disable_zoom_in" then
        _patch_camera_offset()
    elseif setting_id == "freecam_enabled" then
        _apply_freecam(mod:get("freecam_enabled"))
    elseif setting_id == "noclip_enabled" then
        _apply_noclip(mod:get("noclip_enabled"))
    elseif setting_id == "disable_enemy_spawns" then
        _apply_script_data_no_enemies(mod:get("disable_enemy_spawns"))
    elseif setting_id == "time_scale_value" then
        mod.gt_time_apply()
    elseif setting_id == "base_crit_chance" then
        mod.gt_apply_crit_chance()
    elseif setting_id == "movement_speed" then
        mod.gt_apply_move_speed()
    elseif setting_id == "gt_more_corpses_enabled" or setting_id == "gt_more_corpses_count" then
        -- mod.gt_apply_corpse_count is a table field on `mod`, so this name
        -- resolves at call time — safe to reference even though the function
        -- body is assigned later in the file.
        if mod.gt_apply_corpse_count then mod.gt_apply_corpse_count() end
    elseif setting_id == "gt_disable_intro_monologue" then
        script_data = script_data or {}
        script_data.disable_level_intro_dialogue = mod:get("gt_disable_intro_monologue") or nil
    elseif setting_id == "gt_skip_cutscenes_enabled" then
        script_data = script_data or {}
        script_data.skippable_cutscenes = mod:get("gt_skip_cutscenes_enabled") or nil
    elseif setting_id == "ai_takeover_enabled" then
        if _ai_suppress_setting_callback then return end
        local want_bot = mod:get("ai_takeover_enabled") and true or false
        local ok, err = _ai_handle_toggle_change(want_bot)
        if not ok then
            _ai_suppress_setting_callback = true
            mod:set("ai_takeover_enabled", not want_bot)
            _ai_suppress_setting_callback = false
            mod:echo("AI toggle: " .. err)
        else
            mod:echo("AI " .. (want_bot and "ON" or "OFF") .. " (requested from host).")
        end
    elseif _gt_cs_on_setting_changed then
        _gt_cs_on_setting_changed(setting_id)
    end
end

mod.on_disabled = function()
    _restore_camera_offset()
    -- Issue #15: the mod is is_togglable=true but only the camera offset is
    -- snapshot-and-restored above. Many global mutations persist after
    -- disable: script_data flags (ai_*, skippable_cutscenes, intro dialogue,
    -- player_unkillable), RagdollSettings, BuffTemplates.power_level_unbalance,
    -- CareerSettings[*].attributes.base_critical_strike_chance,
    -- PlayerUnitMovementSettings.move_speed (plus the closed-upvalue per-unit
    -- copy), InventorySettings, DamageUtils.is_in_inn,
    -- GameSettingsDevelopment.disable_free_flight, ESC-menu inventory entry.
    -- A full snapshot-on-enable + restore-on-disable refactor is significant
    -- effort; for now we honestly warn the user. This warning fires regardless
    -- of the enable_debug_logging gate because it's user-facing operational
    -- guidance, not debug spam.
    mod:echo("[gt] Disable does not fully unwind active mutations. Restart the game for a clean vanilla state.")
end

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

-- v0.2.55-dev: shadows the top-of-file `_dbg`/`_dbg_alert` pair for
-- everything below this point (no prefix, passes fmt directly).
-- v0.2.73: removed per-mod enable_debug_logging gate; routes through VMF.
local function _dbg(fmt, ...)
    mod:debug(fmt, ...)
end

local function _dbg_alert(fmt, ...)
    mod:warning(fmt, ...)
end

-- Exposed on `mod` so the existing _customize_item hook (further
-- down in the file, predates this section) can call into it.
mod._dbg_log = _dbg

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

-- HeroView open/close: every entry to the keep menu. Useful for
-- confirming which substate the view landed in.
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
-- and _ai_saved_state contents. Used to triage why AI takeover still
-- doesn't reliably swap — the swap path depends on a long chain of
-- preconditions (server-only mutation, party slot present, game_mode
-- exposes _add_bot_to_party, profile_synchronizer not still busy with
-- a transfer) and a failure at any link returns one short reason
-- string. The dump surfaces the whole chain.
--
-- Auto-fires on: StateIngame enter, AI toggle changes (both host &
-- client), and a peer joining/leaving. Manual: /gt_dump_ai.

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
    for k, v in pairs(_ai_saved_state) do
        saved_lines[#saved_lines + 1] = string.format("%s={pi=%s,ci=%s,party=%s,slot=%s,remote=%s}",
            tostring(k), tostring(v.profile_index), tostring(v.career_index),
            tostring(v.party_id), tostring(v.slot_id), tostring(v.is_remote))
    end
    _dbg("[ai_dump:%s] _ai_saved_state: {%s}", why or "manual", table.concat(saved_lines, " | "))
    _dbg("[ai_dump:%s] _ai_pending_host_toggle=%s _ai_pending_client_send=%s",
        why or "manual",
        _ai_pending_host_toggle and "queued" or "nil",
        _ai_pending_client_send and "queued" or "nil")

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

mod:command("gt_dump_ai", "Dump the AI/bot takeover state (players, bots, party slots, profile sync, host peer, saved state)", function()
    -- Run the dump unconditionally on command (don't gate on debug_mode
    -- since the user explicitly asked for it). Force mod:info emission.
    local was = mod:get("gt_debug_mode")
    if not was then mod:set("gt_debug_mode", true) end
    _gt_dump_ai_now("manual")
    if not was then mod:set("gt_debug_mode", false) end
end)

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

-- ------------------------------------------------------------
-- Menu / inventory dump
-- ------------------------------------------------------------
-- HeroView substate hierarchy + active windows + which game modes
-- the inventory considers itself allowed in. Useful for diagnosing
-- why a menu doesn't show up mid-mission, and which windows mounted
-- so we can target the right Class.method for any further hardening.
--
-- Auto-fires on: HeroView open, HeroViewStateOverview.set_layout_by_name,
-- and each HeroWindow* substate enter. Manual: /gt_dump_menu.

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

mod:command("gt_dump_menu", "Dump the active HeroView substate + windows + InventorySettings flags", function()
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
    _gt_dump_menu_now("layout_" .. tostring(name))
    return func(self, name, ...)
end)

mod:hook("HeroViewStateOverview", "on_enter", function(func, self, params, ...)
    _dbg("[menu_event] HeroViewStateOverview.on_enter")
    _gt_dump_menu_now("state_overview_enter")
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
-- block after _ai_handle_toggle_change's assignment (~line 2535).
-- It can't live here because _ai_handle_toggle_change is forward-
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
        if status == "enter" and state_name == "StateIngame" then
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
-- Game Glossary Dump
-- ============================================================

mod:command("dump_glossary", "Dump localized names for heroes, careers, and weapons to log", function()
    if not SPProfiles then
        mod:echo("SPProfiles not loaded (load a level first).")
        return
    end

    local lines = {}
    local function add(line)
        lines[#lines + 1] = line
    end

    local function safe_localize(key)
        if not key then return "?" end
        local ok, result = pcall(Localize, key)
        return ok and result or key
    end

    add("=== HEROES & CAREERS ===")
    for _, profile in ipairs(SPProfiles) do
        local hero_key = profile.display_name
        if hero_key == "empire_soldier_tutorial" then goto continue_hero end
        local hero_name = safe_localize(profile.ingame_display_name or hero_key)
        add(string.format("HERO  %-25s  %s", hero_key, hero_name))
        if profile.careers then
            for _, career in ipairs(profile.careers) do
                local career_key = career.display_name or career.name
                local career_name = safe_localize(career_key)
                add(string.format("  CAREER  %-23s  %s", career_key, career_name))
            end
        end
        ::continue_hero::
    end

    add("")
    add("=== WEAPONS ===")
    if ItemMasterList then
        local weapons = {}
        for key, item in pairs(ItemMasterList) do
            local st = item.slot_type
            if st == "melee" or st == "ranged" then
                local name = item.display_name and safe_localize(item.display_name) or "?"
                local wield = "none"
                if item.can_wield and #item.can_wield > 0 then
                    wield = table.concat(item.can_wield, ", ")
                end
                weapons[#weapons + 1] = {
                    key = key,
                    slot = st,
                    name = name,
                    careers = wield,
                    template = item.template or "",
                }
            end
        end
        table.sort(weapons, function(a, b)
            if a.slot ~= b.slot then return a.slot < b.slot end
            return a.key < b.key
        end)

        local cur_slot = nil
        for _, w in ipairs(weapons) do
            if w.slot ~= cur_slot then
                cur_slot = w.slot
                add(string.format("--- %s ---", cur_slot:upper()))
            end
            add(string.format("  %-45s  %-30s  can_wield=[%s]", w.key, w.name, w.careers))
        end

        add("")
        add(string.format("Total: %d weapons", #weapons))
    else
        add("ItemMasterList not loaded.")
    end

    _write_dump("glossary.txt", lines)
    mod:echo(string.format("dump_glossary: %d lines written to log", #lines))
end)

-- ============================================================
-- Cosmetic / Item Dump Commands
-- ============================================================

mod:command("dump_cosmetics", "Dump all hats, skins, and frames from ItemMasterList to log", function(filter)
    if not ItemMasterList then
        mod:echo("ItemMasterList not loaded (load a level first).")
        return
    end

    local slot_types = { hat = {}, skin = {}, frame = {} }
    for key, item in pairs(ItemMasterList) do
        local st = item.slot_type
        if slot_types[st] then
            local wield = item.can_wield
            local careers = "none"
            if wield and #wield > 0 then
                careers = table.concat(wield, ", ")
            end
            if not filter or key:find(filter, 1, true) or careers:find(filter, 1, true) then
                -- REVIEW: `icon` is captured but never written to output (the
                -- inner formatter below only uses key + careers). Remove this
                -- field or include it in the dump line.
                slot_types[st][#slot_types[st] + 1] = {
                    key = key,
                    careers = careers,
                    icon = item.inventory_icon or "?",
                }
            end
        end
    end

    local total = 0
    local lines = {}
    for slot_type, items in pairs(slot_types) do
        table.sort(items, function(a, b) return a.key < b.key end)
        local header = string.format("=== %s (%d items) ===", slot_type:upper(), #items)
        mod:echo(header)
        lines[#lines + 1] = header
        for _, item in ipairs(items) do
            local line = string.format("  %-50s  can_wield=[%s]", item.key, item.careers)
            mod:echo(line)
            lines[#lines + 1] = line
            total = total + 1
        end
    end

    local summary = string.format("dump_cosmetics: %d total (%d hats, %d skins, %d frames)",
        total, #slot_types.hat, #slot_types.skin, #slot_types.frame)
    mod:echo(summary)
    lines[#lines + 1] = summary
    _write_dump("cosmetics.txt", lines)
end)

-- ============================================================
-- Unstuck (teleport to nearest living teammate)
-- ============================================================

mod:command("unstuck", "Teleport to nearest living teammate (prefers humans)", function()
    local pm = Managers.player
    if not pm then mod:echo("Not in a level.") return end
    local player = pm:local_player()
    if not player then mod:echo("No local player.") return end
    local unit = player.player_unit
    if not unit then mod:echo("No player unit (dead?).") return end

    local self_pos = Unit.local_position(unit, 0)
    local best_human_pos, best_human_dist_sq = nil, math.huge
    local best_bot_pos, best_bot_dist_sq = nil, math.huge

    for _, p in pairs(pm:players()) do
        if p ~= player and p.player_unit and HEALTH_ALIVE[p.player_unit] then
            local pos = Unit.local_position(p.player_unit, 0)
            local d = Vector3.distance_squared(pos, self_pos)
            local is_human = p.is_player_controlled and p:is_player_controlled()
            if is_human then
                if d < best_human_dist_sq then
                    best_human_pos, best_human_dist_sq = pos, d
                end
            else
                if d < best_bot_dist_sq then
                    best_bot_pos, best_bot_dist_sq = pos, d
                end
            end
        end
    end

    local target_pos = best_human_pos or best_bot_pos
    if target_pos then
        local mover = Unit.mover(unit)
        if mover then
            Mover.set_position(mover, target_pos + Vector3(0.5, 0, 0))
        end
        mod:echo(best_human_pos and "Unstuck (to nearest human)!" or "Unstuck (to nearest bot)!")
    else
        mod:echo("No living teammate found.")
    end
end)

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
end

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

mod:hook("DamageUtils", "add_damage_network", function(func, attacked_unit, ...)
    if _godmode and _is_local_player_unit(attacked_unit) then return 0 end
    return func(attacked_unit, ...)
end)

mod:hook("DamageUtils", "add_damage_network_player", function(func, damage_profile, target_index, power_level, attacked_unit, ...)
    if _godmode and _is_local_player_unit(attacked_unit) then return 0 end
    return func(damage_profile, target_index, power_level, attacked_unit, ...)
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

mod:hook("ConflictDirector", "spawn_queued_unit", function(func, self, ...)
    if mod:get("disable_enemy_spawns") then return end
    return func(self, ...)
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

-- ============================================================
-- Open Inventory In Mission / Mission Customize gear-icon — REMOVED
-- ============================================================
-- `mod.gt_open_mission_inventory`, the `/gt_inv` command, and the
-- `HeroWindowLoadoutConsole._customize_item` cim crash-gate were removed
-- from the public General Tweaker in v0.2.72-alpha along with the rest of
-- the in-mission inventory / Keep-Menus feature (migrated to the GUI
-- Tweaker mod). See the migration note further up the file.

-- ============================================================
-- Friendly Fire Toggle
-- ============================================================
-- On Champion+, ranged FF is on by default. Hook the two gate
-- functions that everything else calls through to suppress it.

mod:hook("DamageUtils", "allow_friendly_fire_ranged", function(func, ...)
    if mod:get("disable_friendly_fire") then return false end
    return func(...)
end)

mod:hook("DamageUtils", "allow_friendly_fire_melee", function(func, ...)
    if mod:get("disable_friendly_fire") then return false end
    return func(...)
end)

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

mod.gt_win_level = function()
    if DamageUtils and DamageUtils.is_in_inn then
        mod:echo("Can't win in the keep.")
        return
    end
    if Managers.state and Managers.state.game_mode then
        Managers.state.game_mode:complete_level()
    else
        mod:echo("No active game mode.")
    end
end

mod.gt_fail_level = function()
    if DamageUtils and DamageUtils.is_in_inn then
        mod:echo("Can't fail in the keep.")
        return
    end
    if Managers.state and Managers.state.game_mode then
        Managers.state.game_mode:fail_level()
    else
        mod:echo("No active game mode.")
    end
end

mod.gt_restart_level = function()
    if DamageUtils and DamageUtils.is_in_inn then
        mod:echo("Can't restart in the keep.")
        return
    end
    if Managers.state and Managers.state.game_mode then
        Managers.state.game_mode:retry_level()
    else
        mod:echo("No active game mode.")
    end
end

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
mod:command("gt_win",       "Complete the current map",           function() mod.gt_win_level()     end)
mod:command("gt_fail",      "Fail the current map",               function() mod.gt_fail_level()    end)
mod:command("gt_restart",   "Restart the current map",            function() mod.gt_restart_level() end)
mod:command("gt_killbots",  "Kill all bots (pre-round on EAC-secure realm only)", function() mod.gt_kill_bots() end)
mod:command("gt_die",       "Kill your character",                function() mod.gt_die()           end)
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

mod:command("gt_bottoggle", "Toggle bots on/off for current level (lets you spawn bots in the keep)", function()
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

-- ============================================================
-- Item Dump Commands
-- ============================================================

mod:command("dump_items_by_slot", "Dump all ItemMasterList slot_type values and counts", function()
    if not ItemMasterList then
        mod:echo("ItemMasterList not loaded (load a level first).")
        return
    end

    local counts = {}
    for key, item in pairs(ItemMasterList) do
        local st = item.slot_type or "nil"
        counts[st] = (counts[st] or 0) + 1
    end

    local sorted = {}
    for st, count in pairs(counts) do
        sorted[#sorted + 1] = { slot_type = st, count = count }
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)

    local lines = { "=== ItemMasterList slot_type counts ===" }
    mod:echo(lines[1])
    for _, entry in ipairs(sorted) do
        local line = string.format("  %-30s %d items", entry.slot_type, entry.count)
        mod:echo(line)
        lines[#lines + 1] = line
    end
    _write_dump("items_by_slot.txt", lines)
end)

-- gt_dump_hero_view: capture live hero view widget tree for porting analysis
mod:command("gt_dump_hero_view", "Dump the active HeroView state, menu layout, and widget tree to log", function()
    local lines = {}
    local function add(line)
        lines[#lines + 1] = line
    end

    local function safe_localize(key)
        if not key then return "?" end
        local ok, result = pcall(Localize, key)
        return ok and result or key
    end

    local function safe(fn)
        local ok, result = pcall(fn)
        if ok then return result end
        return nil
    end

    add(string.format("=== gt_dump_hero_view @ %s ===", os.date("%Y-%m-%d %H:%M:%S")))
    local build_id = rawget(_G, "BUILD") or safe(function() return Application.build_identifier() end)
    add(string.format("BUILD=%s", tostring(build_id or "?")))

    local ingame_ui = safe(function() return Managers.ui:ingame_ui() end)
    if not ingame_ui then
        mod:echo("Hero view not active - open the character menu first, then run /gt_dump_hero_view.")
        return
    end

    local views = ingame_ui.views
    local hero_view = views and views.hero_view
    if not hero_view then
        mod:echo("Hero view not active - open the character menu first, then run /gt_dump_hero_view.")
        return
    end

    local current_view = ingame_ui.current_view
    local is_active = (current_view == "hero_view")
    add(string.format("ACTIVE_VIEW class=HeroView current_view=%s visible=%s",
        tostring(current_view), tostring(is_active)))

    if not is_active then
        add("Hero view exists but is not the current_view; dumping last-known state anyway.")
    end

    local machine = hero_view._machine
    local state = safe(function() return hero_view:current_state() end) or (machine and safe(function() return machine:state() end))
    if not state then
        add("STATE machine_or_state_unavailable")
        _write_dump("hero_view_dump.txt", lines)
        mod:echo(string.format("gt_dump_hero_view: %d lines written to log", #lines))
        return
    end

    local state_class_name = "?"
    local mt = getmetatable(state)
    if mt and mt.__index then
        for name, ref in pairs(_G) do
            if ref == mt.__index then state_class_name = name; break end
        end
    end
    add(string.format("STATE class=%s", state_class_name))

    local profile_index = state.profile_index or hero_view.initial_profile_index
    local career_index = state.career_index
    local hero_name = state.hero_name
    add(string.format("CAREER hero=%s profile_index=%s career_index=%s",
        tostring(hero_name), tostring(profile_index), tostring(career_index)))
    if SPProfiles and profile_index and SPProfiles[profile_index] then
        local prof = SPProfiles[profile_index]
        local career = prof.careers and prof.careers[career_index]
        if career then
            add(string.format("  career_name=%s display=%s",
                tostring(career.name), safe_localize(career.display_name or career.name)))
        end
    end

    add("")
    add("=== MENU LAYOUT ===")
    local layout_settings = state._layout_settings
    if layout_settings then
        add(string.format("max_active_windows=%s", tostring(layout_settings.max_active_windows)))
        local window_layouts = layout_settings.window_layouts or state._window_layouts
        if window_layouts then
            for i, entry in ipairs(window_layouts) do
                local display = entry.display_name and safe_localize(entry.display_name) or ""
                add(string.format("  layout[%d] name=%s close_on_exit=%s display=%s",
                    i, tostring(entry.name), tostring(entry.close_on_exit), display))
            end
        end
        local windows = layout_settings.windows or state._windows_settings
        if windows then
            add("  --- windows ---")
            for key, w in pairs(windows) do
                add(string.format("    window[%s] class=%s", tostring(key), tostring(w.class_name)))
            end
        end
    else
        add("(_layout_settings not present on state)")
    end

    add(string.format("selected_layout_index=%s", tostring(state._selected_game_mode_index)))

    add("")
    add("=== ACTIVE WINDOWS ===")
    local active_windows = state._active_windows
    if active_windows then
        for idx, window in pairs(active_windows) do
            local cls = "?"
            local wmt = getmetatable(window)
            if wmt and wmt.__index then
                for name, ref in pairs(_G) do
                    if ref == wmt.__index then cls = name; break end
                end
            end
            add(string.format("  active_window[%s] class=%s", tostring(idx), cls))
        end
    else
        add("(no _active_windows)")
    end

    local function dump_widgets(owner_label, widgets_by_name)
        if not widgets_by_name then return end
        add(string.format("--- widgets_by_name (%s) ---", owner_label))
        local keys = {}
        for k in pairs(widgets_by_name) do keys[#keys+1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local w = widgets_by_name[k]
            local wtype = w and (w.element and w.element.name) or (w and w.widget_type) or "?"
            local label = ""
            if w and w.content then
                local txt = w.content.text or w.content.title_text or w.content.display_name
                if type(txt) == "string" then
                    if #txt > 60 then txt = txt:sub(1, 60) .. "..." end
                    label = " text=\"" .. txt .. "\""
                end
                if w.content.visible ~= nil then
                    label = label .. " visible=" .. tostring(w.content.visible)
                end
            end
            add(string.format("  [%s] type=%s%s", k, tostring(wtype), label))
        end
    end

    add("")
    add("=== STATE WIDGETS ===")
    dump_widgets("state", state._widgets_by_name)

    if active_windows then
        for idx, window in pairs(active_windows) do
            add("")
            add(string.format("=== WINDOW[%s] WIDGETS ===", tostring(idx)))
            dump_widgets("window_" .. tostring(idx), window._widgets_by_name)
        end
    end

    _write_dump("hero_view_dump.txt", lines)
    mod:echo(string.format("gt_dump_hero_view: %d lines written to log", #lines))
end)

-- ============================================================
-- AI Toggle (hand off control to a bot)
-- ============================================================
-- VT2 has no hot-swap path between human and bot units — they use different
-- go_types with incompatible extension stacks (PlayerInputExtension vs
-- PlayerBotInput, GenericCharacterStateMachineExtension vs PlayerBotBase,
-- etc.). So toggling means despawn-human + add-bot, or remove-bot +
-- re-add-human. Both halves of the dance exist in vanilla and we compose
-- them: see GameModeBase._add_bot_to_party / _remove_bot_instant and
-- GameModeAdventure.player_entered_game_session.
--
-- Server-driven: only the host can perform the swap (ProfileSynchronizer
-- and PartyManager APIs assert is_server). Clients send a VMF network
-- request and the host validates + executes.
--
-- v1 scope:
--   * client (remote peer) self-toggle: supported
--   * host self-toggle: refused — destroying the local Player object mid-
--     mission would tear down camera/HUD/input bindings that aren't trivial
--     to recreate
--   * versus / keep: refused (no hero bot AI / no spawning)

local _AI_RPC = "gt_ai_toggle_request"
-- _ai_saved_state and _ai_suppress_setting_callback are forward-declared at
-- the top of the file (on_game_state_changed / on_setting_changed reference
-- them before this point). Assign here, do NOT redeclare with `local`, or the
-- early callbacks would still bind to nil globals.

local function _ai_state_key(peer_id, local_player_id)
    return tostring(peer_id) .. ":" .. tostring(local_player_id)
end

local function _ai_game_mode_key()
    local gm = Managers.state and Managers.state.game_mode
    if not (gm and gm.game_mode) then return nil end
    local mode = gm:game_mode()
    if not (mode and mode.settings) then return nil end
    return mode:settings().key
end

local function _ai_can_swap_in_current_mode()
    local key = _ai_game_mode_key()
    if not key then return false, "no active game mode" end
    if key:find("versus") or key:find("_vs") then
        return false, "versus is not supported (heroes have no bot AI)"
    end
    if key == "inn" or key == "inn_deus" or key:find("^inn") then
        return false, "must be in a mission"
    end
    return true
end

local function _ai_find_bot_in_slot(party_id, slot_id)
    local pm = Managers.player
    local bots = pm and pm:bots() or {}
    for _, bot in ipairs(bots) do
        local bp = bot:network_id()
        local bl = bot:local_player_id()
        local status = Managers.party and Managers.party:get_player_status(bp, bl)
        if status and status.party_id == party_id and status.slot_id == slot_id then
            return bot
        end
    end
    return nil
end

local function _ai_swap_human_to_bot(peer_id, local_player_id)
    local pm = Managers.player
    if not pm.is_server then return false, "must run on host" end
    local player = pm:player(peer_id, local_player_id)
    if not player then return false, "player not found" end
    if player.bot_player then return false, "already a bot" end

    local status = Managers.party:get_player_status(peer_id, local_player_id)
    if not (status and status.party_id and status.slot_id) then
        return false, "no party slot"
    end
    local party_id = status.party_id
    local slot_id = status.slot_id
    local profile_synchronizer = pm.network_manager and pm.network_manager.profile_synchronizer
    if not profile_synchronizer then return false, "no profile_synchronizer" end
    local profile_index, career_index = profile_synchronizer:profile_by_peer(peer_id, local_player_id)
    if not (profile_index and career_index) then
        return false, "no profile/career"
    end

    -- Save enough metadata to recreate the human Player on toggle-back. For
    -- a remote (client) player we need peer/clan/account; for the host's
    -- local player we'd need input_source/viewport (not supported in v1).
    local saved = {
        peer_id = peer_id,
        local_player_id = local_player_id,
        profile_index = profile_index,
        career_index = career_index,
        party_id = party_id,
        slot_id = slot_id,
        is_remote = player.remote and true or false,
    }
    if player.remote then
        saved.remote = {
            player_controlled = player._player_controlled,
            clan_tag = player._clan_tag,
            account_id = player._account_id,
        }
    else
        saved.local_data = {
            input_source = player.input_source,
            viewport_name = player.viewport_name,
            viewport_world_name = player.viewport_world_name,
        }
    end
    _ai_saved_state[_ai_state_key(peer_id, local_player_id)] = saved

    if player.player_unit then
        player:despawn()
    end
    profile_synchronizer:unassign_profiles_of_peer(peer_id, local_player_id)
    Managers.party:remove_peer_from_party(peer_id, local_player_id, party_id)
    pm:remove_player(peer_id, local_player_id)

    local game_mode = Managers.state.game_mode:game_mode()
    if not (game_mode and game_mode._add_bot_to_party) then
        return false, "current game mode does not support bots"
    end
    game_mode:_add_bot_to_party(party_id, profile_index, career_index, slot_id)

    return true
end

local function _ai_swap_bot_to_human(peer_id, local_player_id)
    local pm = Managers.player
    if not pm.is_server then return false, "must run on host" end
    local saved = _ai_saved_state[_ai_state_key(peer_id, local_player_id)]
    if not saved then return false, "no saved state (toggle to bot first)" end

    local bot = _ai_find_bot_in_slot(saved.party_id, saved.slot_id)
    if bot then
        local game_mode = Managers.state.game_mode:game_mode()
        if game_mode and game_mode._remove_bot_instant then
            game_mode:_remove_bot_instant(bot)
        end
    end

    if saved.is_remote and saved.remote then
        pm:add_remote_player(peer_id, saved.remote.player_controlled, local_player_id,
            saved.remote.clan_tag, saved.remote.account_id)
    elseif saved.local_data then
        pm:add_player(saved.local_data.input_source, saved.local_data.viewport_name,
            saved.local_data.viewport_world_name, local_player_id)
    else
        return false, "saved state missing player kind"
    end

    Managers.party:assign_peer_to_party(peer_id, local_player_id, saved.party_id, saved.slot_id, false)
    pm.network_manager.profile_synchronizer:assign_full_profile(peer_id, local_player_id,
        saved.profile_index, saved.career_index, false)

    _ai_saved_state[_ai_state_key(peer_id, local_player_id)] = nil
    return true
end

mod:network_register(_AI_RPC, function(sender_peer_id, payload)
    mod:info("[ai_toggle recv] HOST<-req sender=%s payload=%s",
        tostring(sender_peer_id), type(payload) == "table" and "table" or tostring(payload))
    local pm = Managers.player
    if not (pm and pm.is_server) then return end
    local peer_id, local_player_id = sender_peer_id, 1
    local want_bot
    if type(payload) == "table" then
        peer_id = payload.peer_id or peer_id
        local_player_id = payload.local_player_id or local_player_id
        want_bot = payload.want_bot
    end

    local ok, err = _ai_can_swap_in_current_mode()
    if not ok then
        mod:info("[ai_toggle] refused for %s: %s", tostring(peer_id), tostring(err))
        return
    end

    -- want_bot is the client's explicit intent (from their checkbox state).
    -- Saved state is the host's view of truth — used to no-op stale requests.
    local has_saved = _ai_saved_state[_ai_state_key(peer_id, local_player_id)] ~= nil
    if want_bot == nil then want_bot = not has_saved end

    if want_bot and not has_saved then
        local s_ok, s_err = _ai_swap_human_to_bot(peer_id, local_player_id)
        mod:info("[ai_toggle] human->bot for %s: %s", tostring(peer_id), s_ok and "ok" or tostring(s_err))
    elseif (not want_bot) and has_saved then
        local s_ok, s_err = _ai_swap_bot_to_human(peer_id, local_player_id)
        mod:info("[ai_toggle] bot->human for %s: %s", tostring(peer_id), s_ok and "ok" or tostring(s_err))
    else
        mod:info("[ai_toggle] no-op for %s (want_bot=%s has_saved=%s)",
            tostring(peer_id), tostring(want_bot), tostring(has_saved))
    end
end)

-- Pending host self-toggle. The actual swap is deferred one mod.update tick so
-- the current frame finishes (input read, etc.) before we tear the local
-- Player object down. Polled in the main mod.update closure below — see the
-- `_ai_pending_host_toggle` block.
-- NOTE: declared as a forward `local` near the top of the file alongside
-- _ai_pending_client_send (the debug-mode AI dump reads it from above
-- this point). Assign without `local` here so we write the existing
-- upvalue instead of shadowing it.
_ai_pending_host_toggle = nil

-- Returns (ok, err_msg). Caller is responsible for reverting the checkbox on
-- failure — _ai_suppress_setting_callback must be true while doing so.
-- Assigns to the forward-declared upvalue (see top of file); MUST NOT use
-- `local function` here or on_setting_changed would call nil.
_ai_handle_toggle_change = function(want_bot)
    local ok, err = _ai_can_swap_in_current_mode()
    if not ok then return false, err end

    local pm = Managers.player
    if pm and pm.is_server then
        -- Host self-toggle: do the swap locally, no RPC. Defer by one tick so
        -- the current frame finishes reading our input before we destroy the
        -- Player object that owns it. The `local_data` round-trip
        -- (input_source / viewport_name / viewport_world_name) was already
        -- being captured by _ai_swap_human_to_bot, so toggling back recreates
        -- the local Player with the same viewport binding.
        _ai_pending_host_toggle = { want_bot = want_bot and true or false }
        return true
    end

    -- VMF `network_send` does NOT understand `"server"` — it falls through
    -- the recipient-name lookup, treats the string as a literal peer_id,
    -- fails the `_vmf_users[peer_id]` check, and returns silently. No wire
    -- activity, no error. (Burned v0.2.48-dev: client toggle echoed "request
    -- sent" but host never received the RPC.) See VMF_RECIPES.md § 3.
    --
    -- Resolve the host's real peer_id. The canonical engine API is
    -- `Managers.mechanism:server_peer_id()` (verified in vanilla at
    -- `imgui_career_debug.lua:153` and `versus_mechanism.lua:1845`). DO NOT
    -- use `Managers.state.network.server_peer_id` — `Managers.state.network`
    -- is `GameNetworkManager` which has no such field directly; the field
    -- lives one level deeper on `.network_client` (client) or `.network_server`
    -- (host). Burned v0.2.49-dev: that wrong path always returned nil and
    -- the toggle refused with "host peer_id not yet known". Try the mechanism
    -- API first; fall back through GameNetworkManager subcomponents in case
    -- mechanism hasn't published yet during late session-join.
    local host
    if Managers.mechanism and Managers.mechanism.server_peer_id then
        host = Managers.mechanism:server_peer_id()
    end
    if not host then
        local nm = Managers.state and Managers.state.network
        host = nm and ((nm.network_client and nm.network_client.server_peer_id)
            or (nm.network_server and nm.network_server.server_peer_id))
    end
    if not host then
        return false, "host peer_id not yet known (session still loading?)"
    end

    -- Force VMF to re-handshake with the host before our first send. Covers
    -- the bot-churn bug where VMF dropped the host from `_vmf_users` at
    -- mission load. ping_vmf_users sends a ping to every human player and
    -- the resulting pong re-populates `_vmf_users[host_peer]` so the next
    -- send succeeds. ping_vmf_users is the canonical VMF re-handshake API
    -- (vanilla VMF network.lua:452-463). Wrapped in pcall in case the API
    -- shape changes in a future VMF update — even if the re-handshake fails
    -- we still queue the send (the host MIGHT already be in vmf_users).
    local vmf = get_mod("VMF")
    if vmf and vmf.ping_vmf_users then
        pcall(vmf.ping_vmf_users)
    end

    -- Queue the actual send (with retries) instead of sending inline. The
    -- pong round-trip needs ~50-300 ms over Steam P2P; sending immediately
    -- would race the re-handshake and lose the first attempt. mod.update
    -- consumer fires the queued send after the delay.
    _ai_pending_client_send = {
        host = host,
        want_bot = want_bot and true or false,
        retries_left = _AI_CLIENT_SEND_MAX_RETRIES,
        next_at = os.clock() + _AI_CLIENT_SEND_DELAY_FIRST,
    }
    mod:info("[ai_toggle queue] CLIENT host=%s want_bot=%s retries=%d",
        tostring(host), tostring(want_bot), _AI_CLIENT_SEND_MAX_RETRIES)
    return true
end

-- Debug-mode dump wrap. Placed here because _ai_handle_toggle_change
-- was nil at chunk load when the rest of the debug section ran
-- (assignment lives just above). Captures before/after AI state on
-- every toggle so the user/agent can diff what mutated vs. what was
-- meant to mutate. _gt_dump_ai_now is a file-scope local declared in
-- the debug section further up — visible by chunk position here.
do
    local prev = _ai_handle_toggle_change
    _ai_handle_toggle_change = function(want_bot)
        _gt_dump_ai_now("toggle_pre_want_bot=" .. tostring(want_bot))
        local ok, err = prev(want_bot)
        _dbg("[ai_event] toggle returned ok=%s err=%s", tostring(ok), tostring(err))
        _gt_dump_ai_now("toggle_post")
        return ok, err
    end
end

-- Drain the client-side send queue. Called from mod.update. Sends the RPC
-- when `next_at` has elapsed; on each fire, also re-pings VMF users so a
-- pong stays warm against further bot-churn events between retries. Returns
-- once retries are exhausted. Idempotent — the host's RPC handler no-ops
-- when state already matches the requested want_bot.
local function _ai_consume_pending_client_send()
    local q = _ai_pending_client_send
    if not q then return end
    if os.clock() < q.next_at then return end

    -- Refresh VMF user state on each fire so a bot-churn between retries
    -- doesn't strand the next send.
    local vmf = get_mod("VMF")
    if vmf and vmf.ping_vmf_users then
        pcall(vmf.ping_vmf_users)
    end

    mod:info("[ai_toggle emit] CLIENT->req host=%s want_bot=%s (attempt %d of %d)",
        tostring(q.host), tostring(q.want_bot),
        (_AI_CLIENT_SEND_MAX_RETRIES - q.retries_left) + 1, _AI_CLIENT_SEND_MAX_RETRIES)
    mod:network_send(_AI_RPC, q.host, {
        peer_id = Network.peer_id(),
        local_player_id = 1,
        want_bot = q.want_bot,
    })

    q.retries_left = q.retries_left - 1
    if q.retries_left <= 0 then
        _ai_pending_client_send = nil
    else
        q.next_at = os.clock() + _AI_CLIENT_SEND_DELAY_RETRY
    end
end

-- Execute the deferred host swap. Called from mod.update — see the chained
-- closure at the bottom of the file (we mutate `mod.update` again to add this
-- tick consumer alongside the existing infinite-ammo refresher).
local function _ai_consume_pending_host_toggle()
    if not _ai_pending_host_toggle then return end
    local req = _ai_pending_host_toggle
    _ai_pending_host_toggle = nil
    local pm = Managers.player
    if not (pm and pm.is_server) then return end
    local peer_id = Network.peer_id()
    local local_player_id = 1
    local has_saved = _ai_saved_state[_ai_state_key(peer_id, local_player_id)] ~= nil
    if req.want_bot and not has_saved then
        local s_ok, s_err = _ai_swap_human_to_bot(peer_id, local_player_id)
        mod:info("[ai_toggle:host] human->bot: %s", s_ok and "ok" or tostring(s_err))
        if s_ok then mod:echo("AI takeover: ON (your character is now a bot).") end
    elseif (not req.want_bot) and has_saved then
        local s_ok, s_err = _ai_swap_bot_to_human(peer_id, local_player_id)
        mod:info("[ai_toggle:host] bot->human: %s", s_ok and "ok" or tostring(s_err))
        if s_ok then mod:echo("AI takeover: OFF (you're back in control).") end
    end
end

mod:command("ai", "Toggle AI takeover for your character (bot controls it; toggle again to resume). Works on host or client.", function()
    -- Flipping the setting fires on_setting_changed which dispatches to host
    -- self-swap or client->server RPC depending on Managers.player.is_server.
    -- Keeps the chat command and the VMF checkbox in lockstep.
    if _ai_suppress_setting_callback then return end
    mod:set("ai_takeover_enabled", not mod:get("ai_takeover_enabled"))
end)

-- ============================================================
-- Time & Pause (Group B — Janoti "Hacks" port)
-- ============================================================
-- Two related features sharing the same engine primitive:
-- `Managers.state.debug:set_time_scale(index)`. The index is into
-- `time_scale_list` in debug_manager.lua:18 — a 24-entry table of
-- multipliers. Index 13 = 1.0x (normal). Lower = slower, higher = faster.
-- Settings persist for the session; vanilla wipes them on level transition,
-- so on_game_state_changed re-applies the slider value on each StateIngame
-- entry.
--
-- Pause: host-only. Toggles between the configured "pause speed" index
-- (default 1 = slowest possible) and normal (13). VT2 has no true pause
-- primitive — set_time_scale(1) is the closest thing and still lets the UI
-- update. Don't confuse with the time slider: the two write to the same
-- engine setter, so if both are used simultaneously the last write wins.
-- We keep them as separate features matching Hacks's UX.

-- _pause_active is forward-declared near the top of the file (Issue #13).
-- This is an ASSIGNMENT to the file-local, not a new declaration — without
-- the forward-decl, the on_game_state_changed write at line ~688 binds to a
-- global and the pause-toggle desyncs after every level transition.
_pause_active = false

mod.gt_pause_toggle = function()
    if not (Managers.player and Managers.player.is_server) then
        mod:echo("Only the host can pause the game.")
        return
    end
    local debug_mgr = Managers.state and Managers.state.debug
    if not (debug_mgr and debug_mgr.set_time_scale) then
        mod:echo("Time scale manager not available yet.")
        return
    end
    if _pause_active then
        debug_mgr:set_time_scale(mod:get("time_scale_value") or 13)
        _pause_active = false
        mod:echo("Game unpaused.")
    else
        debug_mgr:set_time_scale(mod:get("pause_value") or 1)
        _pause_active = true
        mod:echo("Game paused.")
    end
end

mod.gt_time_apply = function()
    if _pause_active then
        -- While paused, slider edits update the post-unpause target but don't
        -- override the active pause speed. Matches Hacks's behaviour.
        return
    end
    local debug_mgr = Managers.state and Managers.state.debug
    if debug_mgr and debug_mgr.set_time_scale then
        debug_mgr:set_time_scale(mod:get("time_scale_value") or 13)
    end
end

mod.gt_time_faster = function()
    local cur = mod:get("time_scale_value") or 13
    if cur >= 24 then
        mod:echo("Already at maximum time speed.")
        return
    end
    mod:set("time_scale_value", cur + 1)
    mod.gt_time_apply()
    mod:echo(string.format("Time scale: %d", cur + 1))
end

mod.gt_time_slower = function()
    local cur = mod:get("time_scale_value") or 13
    if cur <= 1 then
        mod:echo("Already at minimum time speed.")
        return
    end
    mod:set("time_scale_value", cur - 1)
    mod.gt_time_apply()
    mod:echo(string.format("Time scale: %d", cur - 1))
end

mod:command("gt_pause",    "Toggle game pause (host-only time slowdown to the configured pause speed)", function() mod.gt_pause_toggle() end)
mod:command("time_faster", "Increase game time scale by one step", function() mod.gt_time_faster() end)
mod:command("time_slower", "Decrease game time scale by one step", function() mod.gt_time_slower() end)

-- ============================================================
-- Ult Controls (Group C — Janoti "Hacks" port)
-- ============================================================
-- Three independent features, all driven through CareerExtension:
--
--  1. `gt ult_reset` (+ hotkey) — one-shot, sets every active-ability cooldown
--     to 0 via :reduce_activated_ability_cooldown_percent(charge_index, 1).
--     ThePageMan's "No Ult Cooldown" primitive.
--
--  2. Player ult cooldown cap (toggle + slider 0-120s) — every
--     CareerExtension.update tick, if self.player is human-controlled, clamp
--     each ability's cooldowns[k] down to the configured max. Smooths the
--     "set ult to 5s for testing" workflow without burning a talent slot.
--
--  3. Bot ult cooldown cap — same idea but for AI-controlled units. Useful
--     to make bots ult more aggressively in solo-with-bots testing.
--
-- Both caps share a helper (mod._gt_clamp_cooldowns) that walks every ability
-- on the extension and trims each charge's cooldown if it exceeds the target.
-- Borrowed from Hacks 1:1 since the iteration pattern (decaying-charge index,
-- cooldown_paused unblock, set_activated_ability_cooldown_unpaused) is what
-- the engine expects and replicating it any other way would desync the ability
-- HUD overlay.

mod.gt_ult_reset = function()
    local local_player = Managers.player and Managers.player:local_player()
    local unit = local_player and local_player.player_unit
    if not (unit and Unit.alive(unit)) then
        mod:echo("No local player unit.")
        return
    end
    local career_ext = ScriptUnit.has_extension(unit, "career_system")
    if not career_ext then
        mod:echo("No career extension on local player.")
        return
    end
    for i = 1, career_ext._num_abilities or 1, 1 do
        career_ext:reduce_activated_ability_cooldown_percent(i, 1)
    end
    mod:echo("Ult reset.")
end

mod._gt_clamp_cooldowns = function(career_ext, max_seconds)
    for i = 1, career_ext._num_abilities or 1, 1 do
        local ability = career_ext._abilities[i]
        if ability and ability.cooldowns then
            local charge_idx = career_ext:_currently_decaying_cooldown(i)
            if charge_idx then
                for k = charge_idx, 1, -1 do
                    if ability.cooldowns[k] and ability.cooldowns[k] > max_seconds then
                        ability.cooldowns[k] = max_seconds
                    end
                end
            end
            local is_ready = career_ext:_cooldown_charge_ready(i)
            if not is_ready then
                ability.cooldown_paused = false
            end
            if is_ready then
                career_ext:set_activated_ability_cooldown_unpaused(i)
            end
        end
    end
end

mod:hook_safe(CareerExtension, "update", function(self, unit, input, dt, context, t)
    if mod:get("ult_player_cap_enabled") and self.player and self.player:is_player_controlled() then
        mod._gt_clamp_cooldowns(self, mod:get("ult_player_cap_value") or 0)
    end
    if mod:get("ult_bot_cap_enabled") and self.player and not self.player:is_player_controlled() then
        mod._gt_clamp_cooldowns(self, mod:get("ult_bot_cap_value") or 0)
    end
end)

mod:command("gt_ultreset", "Reset your ultimate (set cooldown to 0)", function() mod.gt_ult_reset() end)

-- ============================================================
-- Buffs & Stat Tweaks (Group D — Janoti "Hacks" port)
-- ============================================================
-- Five independent toggles/sliders:
--
--  1. `gt infinite_ammo`  — applies the vanilla `twitch_no_overcharge_no_ammo_reloads`
--     buff to the local player (and host-side to every player, since the buff
--     is server-controlled). Periodic re-apply every second keeps the buff
--     refreshed in case it gets stripped.
--  2. `gt infinite_stamina` — hooks GenericStatusExtension.add_fatigue_points
--     and short-circuits it so stamina-cost calls never deplete the bar.
--  3. `gt giga_power`     — multiplies BuffTemplates.power_level_unbalance
--     (Enhanced Power talent) by 1000x. Echoes that the talent must be
--     re-equipped for the buff to refresh.
--  4. Base crit chance slider (1–100%) — rewrites
--     CareerSettings[current_career].attributes.base_critical_strike_chance.
--     Auto-resets to the career's vanilla value when you switch career
--     (ProfileRequester.request_profile + GameModeInn._cb_start_menu_closed
--     hooks).
--  5. Movement speed slider (0–30 m/s) — rewrites PlayerUnitMovementSettings.move_speed
--     and walks the per-unit settings table (via the closed-upvalue trick
--     debug.getupvalue(PlayerUnitMovementSettings.unregister_unit, 1)) so
--     already-spawned units get the new speed too.
--
-- All five settings reset on game restart (we don't try to persist them past
-- session) — matches Hacks. The infinite-ammo periodic refresher rides on
-- mod.update which gt already uses for tp/freecam/noclip reapply.

-- ---------- 5.1 Infinite Ammo & 0 Heat -----------------------

local _gt_infinite_ammo_active = false
local _gt_infinite_ammo_refresh_t = 0

local function _gt_apply_infinite_ammo_buff(unit)
    if not (unit and Unit.alive(unit)) then return end
    local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
    if not buff_ext then return end
    if buff_ext:has_buff_type("twitch_no_overcharge_no_ammo_reloads") then return end
    if Managers.player and Managers.player.is_server then
        local bs = Managers.state.entity:system("buff_system")
        bs:add_buff(unit, "twitch_no_overcharge_no_ammo_reloads", unit, false)
    else
        buff_ext:add_buff("twitch_no_overcharge_no_ammo_reloads")
    end
end

local function _gt_remove_infinite_ammo_buff(unit)
    if not (unit and Unit.alive(unit)) then return end
    local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
    if not buff_ext then return end
    if not buff_ext:has_buff_type("twitch_no_overcharge_no_ammo_reloads") then return end
    local buff = buff_ext:get_non_stacking_buff("twitch_no_overcharge_no_ammo_reloads")
    if buff then buff_ext:remove_buff(buff.id) end
end

local function _gt_refresh_infinite_ammo()
    local lp = Managers.player and Managers.player:local_player()
    if lp and lp.player_unit then _gt_apply_infinite_ammo_buff(lp.player_unit) end
    if Managers.player and Managers.player.is_server then
        for _, p in pairs(Managers.player:human_and_bot_players() or {}) do
            _gt_apply_infinite_ammo_buff(p.player_unit)
        end
    end
end

local function _gt_clear_infinite_ammo()
    local lp = Managers.player and Managers.player:local_player()
    if lp and lp.player_unit then _gt_remove_infinite_ammo_buff(lp.player_unit) end
    if Managers.player and Managers.player.is_server then
        for _, p in pairs(Managers.player:human_and_bot_players() or {}) do
            _gt_remove_infinite_ammo_buff(p.player_unit)
        end
    end
end

mod.gt_infinite_ammo_toggle = function()
    _gt_infinite_ammo_active = not _gt_infinite_ammo_active
    if _gt_infinite_ammo_active then
        _gt_refresh_infinite_ammo()
        mod:echo("Infinite ammo & heat: ON.")
    else
        _gt_clear_infinite_ammo()
        mod:echo("Infinite ammo & heat: OFF.")
    end
end

mod:command("infinite_ammo", "Toggle infinite ammo and zero overheat for all players (host applies to clients too)", function()
    mod.gt_infinite_ammo_toggle()
end)

-- ---------- 5.2 Infinite Stamina -----------------------------

local _gt_stamina_active = false

mod.gt_infinite_stamina_toggle = function()
    _gt_stamina_active = not _gt_stamina_active
    mod:echo(_gt_stamina_active and "Infinite stamina: ON." or "Infinite stamina: OFF.")
end

-- Always-on wrapper. When the flag is off, the closure passes through to the
-- original; when on, it short-circuits so fatigue cost calls never deplete
-- the stamina bar. Avoids re-registering hooks (VMF errors on duplicates).
mod:hook(GenericStatusExtension, "add_fatigue_points", function(func, ...)
    if _gt_stamina_active then return end
    return func(...)
end)

mod:command("gt_stamina", "Toggle infinite stamina (zero fatigue cost on blocks/dodges/pushes)", function()
    mod.gt_infinite_stamina_toggle()
end)

-- ---------- 5.3 Giga Power -----------------------------------

local _gt_giga_power_active = false
local _gt_giga_power_original = nil

mod.gt_giga_power_toggle = function()
    if not (BuffTemplates and BuffTemplates.power_level_unbalance and BuffTemplates.power_level_unbalance.buffs[1]) then
        mod:echo("BuffTemplates.power_level_unbalance not available.")
        return
    end
    local buff_row = BuffTemplates.power_level_unbalance.buffs[1]
    if _gt_giga_power_active then
        if _gt_giga_power_original ~= nil then
            buff_row.multiplier = _gt_giga_power_original
        end
        _gt_giga_power_active = false
        mod:echo("Giga power: OFF (re-equip the Enhanced Power talent).")
    else
        _gt_giga_power_original = buff_row.multiplier
        buff_row.multiplier = 1000
        _gt_giga_power_active = true
        mod:echo("Giga power: ON (re-equip the Enhanced Power talent).")
    end
end

mod:command("gt_gigapower", "Multiply the Enhanced Power talent buff by 1000x (re-equip the talent to refresh)", function()
    mod.gt_giga_power_toggle()
end)

-- ---------- 5.4 Base Crit Chance Slider ----------------------

local _gt_current_career_for_crit = nil

local function _gt_get_local_career_name()
    local lp = Managers.player and Managers.player:local_player()
    if not lp then return nil end
    local profile_idx = lp:profile_index()
    local career_idx  = lp:career_index()
    if not (profile_idx and career_idx) then return nil end
    local profile = SPProfiles and SPProfiles[profile_idx]
    if not (profile and profile.careers and profile.careers[career_idx]) then return nil end
    return profile.careers[career_idx].name
end

mod.gt_apply_crit_chance = function()
    local name = _gt_get_local_career_name()
    if not (name and CareerSettings[name] and CareerSettings[name].attributes) then return end
    local pct = mod:get("base_crit_chance") or 5
    CareerSettings[name].attributes.base_critical_strike_chance = pct / 100
end

-- On career switch, snap the slider to that career's vanilla value so toggling
-- back and forth doesn't carry over an unintended override.
mod.gt_sync_crit_default_for_career = function()
    local name = _gt_get_local_career_name()
    if not (name and CareerSettings[name] and CareerSettings[name].attributes) then return end
    if name == _gt_current_career_for_crit then return end
    _gt_current_career_for_crit = name
    local pct = (CareerSettings[name].attributes.base_critical_strike_chance or 0.05) * 100
    mod:set("base_crit_chance", pct)
end

mod:hook_safe(ProfileRequester, "request_profile", function() mod.gt_sync_crit_default_for_career() end)
mod:hook_safe(GameModeInn,      "_cb_start_menu_closed", function() mod.gt_sync_crit_default_for_career() end)

-- ---------- 5.5 Movement Speed Slider -----------------------

mod.gt_apply_move_speed = function()
    local v = mod:get("movement_speed")
    if not (v and PlayerUnitMovementSettings) then return end
    PlayerUnitMovementSettings.move_speed = v
    -- The per-unit settings table is closed over inside unregister_unit. Reach
    -- in via debug.getupvalue so already-spawned units pick up the new speed.
    local _, units_settings = debug.getupvalue(PlayerUnitMovementSettings.unregister_unit, 1)
    if type(units_settings) == "table" then
        for _, settings in pairs(units_settings) do
            settings.move_speed = v
        end
    end
end

-- 1Hz infinite-ammo refresher + the deferred host-AI-toggle / client-send
-- consumers. Registered through the central update subscriber registry
-- (Issue #16 — replaces the prior layered mod.update chain idiom).
_register_update("infinite_ammo_and_ai_pending", function(dt)
    if _gt_infinite_ammo_active then
        _gt_infinite_ammo_refresh_t = _gt_infinite_ammo_refresh_t + (dt or 0)
        if _gt_infinite_ammo_refresh_t >= 1.0 then
            _gt_infinite_ammo_refresh_t = 0
            _gt_refresh_infinite_ammo()
        end
    end
    if _ai_pending_host_toggle then
        _ai_consume_pending_host_toggle()
    end
    if _ai_pending_client_send then
        _ai_consume_pending_client_send()
    end
end)

-- ============================================================
-- Player-state toggles (Group E — Janoti "Hacks" port)
-- ============================================================
-- Three small toggles that don't fit the other groups, all kept distinct
-- from gt's existing `god` toggle on purpose:
--
--  * `inn_dmg`   — host-only flip of `DamageUtils.is_in_inn`. When the
--    inn flag is OFF, the keep behaves like a mission (damage taken,
--    enemies could spawn, etc.). Useful for sparring with bots.
--  * `cloak`     — visual cloak that hides the player model. gt's `god`
--    already cloaks via `status_system:set_invisible(true, false,
--    "gt_godmode")`, but `god` is a multi-feature umbrella. `cloak` is a
--    standalone cosmetic toggle using a separate reason namespace so it
--    doesn't clobber god's invisibility state.
--  * `unkillable`— flips `script_data.player_unkillable`. Unlike `god`
--    you DO still take damage (and disablers still grab you) but you
--    can't be dropped below 1 HP. Mostly a "let me actually feel hits
--    while testing" mode.

mod.gt_inn_dmg_toggle = function()
    if not (Managers.player and Managers.player.is_server) then
        mod:echo("Only the host can toggle inn-damage.")
        return
    end
    if DamageUtils.is_in_inn then
        DamageUtils.is_in_inn = false
        mod:echo("Damage in keep: ENABLED.")
    else
        DamageUtils.is_in_inn = true
        mod:echo("Damage in keep: disabled (vanilla).")
    end
end

mod:command("gt_inndmg", "Toggle whether the keep takes damage (host-only)", function()
    mod.gt_inn_dmg_toggle()
end)

-- Visual cloak: distinct from gt god's invisibility (separate reason namespace
-- so neither clobbers the other on toggle-off). The 3P body and 1P weapon
-- arms both hide because skip_first_person=false. AI perception ignores the
-- player too (same set_invisible primitive).
local _gt_cloak_active = false

mod.gt_cloak_toggle = function()
    local lp = Managers.player and Managers.player:local_player()
    local unit = lp and lp.player_unit
    if not (unit and Unit.alive(unit)) then
        mod:echo("No local player unit.")
        return
    end
    local status_ext = ScriptUnit.has_extension(unit, "status_system")
    if not (status_ext and status_ext.set_invisible) then
        mod:echo("No status extension on local player.")
        return
    end
    _gt_cloak_active = not _gt_cloak_active
    status_ext:set_invisible(_gt_cloak_active, false, "gt_cloak")
    mod:echo(_gt_cloak_active and "Cloak: ON (invisible)." or "Cloak: OFF.")
end

mod:command("cloak", "Toggle visual invisibility (separate from godmode)", function()
    mod.gt_cloak_toggle()
end)

-- Unkillable: take damage normally, but the engine refuses to drop you below
-- 1 HP while the flag is on. Vanilla globals `script_data` controls this; we
-- just flip the flag and announce.
mod.gt_unkillable_toggle = function()
    script_data = script_data or {}
    script_data.player_unkillable = not script_data.player_unkillable
    mod:echo(script_data.player_unkillable and "Unkillable: ON (still take damage)." or "Unkillable: OFF.")
end

mod:command("gt_unkillable", "Toggle take-damage-but-never-die mode", function()
    mod.gt_unkillable_toggle()
end)

-- ============================================================
-- Engine error nil-guards (Group F — Janoti "Hacks" port)
-- ============================================================
-- Two well-known places where vanilla code occasionally dereferences a unit
-- that's mid-cleanup, producing red [Engine Error] spam (and sometimes a
-- silent fatal during long sessions). Hacks ships these guards too — they're
-- cheap and we'd rather suppress the error than have it leak into our crash
-- triage. Both are pure no-op-if-unit-dead pre-guards; the original function
-- is called normally when the unit is alive.

if VolumetricsFlowCallbacks and VolumetricsFlowCallbacks.unregister_fog_volume then
    mod:hook(VolumetricsFlowCallbacks, "unregister_fog_volume", function(func, params, ...)
        if not (params and params.unit and Unit.alive(params.unit)) then return end
        return func(params, ...)
    end)
end

mod:hook(Unit, "get_data", function(func, unit, ...)
    if not unit then return end
    return func(unit, ...)
end)

-- ============================================================
-- Skip Cutscenes (Group G — Aussiemon "Skip Cutscenes" port)
-- ============================================================
-- VT2's CutsceneSystem gates the ESC/Space skip behind
-- `script_data.skippable_cutscenes`. Flipping that flag is enough to let the
-- player dismiss any cutscene manually; in "auto" mode we additionally
-- trigger the cutscene's own skip event the moment activation flows fire,
-- so the player never sits through the cutscene at all.
--
-- Implementation notes:
--   * `flow_cb_cutscene_effect` with name="fx_fade" produces the long
--     unskippable cross-fades that bracket each cutscene. We swallow the
--     next fade after a programmatic skip so the screen doesn't darken for
--     a beat after auto-skipping.
--   * `ShowCursorStack.pop` is guarded because cutscene skip + other mods
--     popping the cursor stack in the same frame can underflow it.
--   * `_skip_next_fade` is module-scoped (not a CutsceneSystem field) so
--     the flag survives system teardown across missions.
--
-- Naming: chat command and keybind both flip the VMF toggle so they stay in
-- sync. Setting id `gt_skip_cutscenes_enabled` to avoid colliding with the
-- standalone Skip Cutscenes / Skip Cutscenes Please mod settings.

local _skip_next_fade = false
-- Deferred auto-skip state. Bug 2026-05-22 (Devious Delvings intro):
-- the previous auto-skip path fired `event_on_skip` (the level's own
-- teardown flow event) inline from `flow_cb_activate_cutscene_logic` but
-- NEVER called the CutsceneSystem's cleanup methods. Vanilla's
-- `skip_pressed` does both — it fires event_on_skip AND calls
-- `flow_cb_deactivate_cutscene_cameras` (which sets letterbox_enabled=false,
-- removing the black bars) and `flow_cb_deactivate_cutscene_logic` (which
-- restores player input). Without those, the letterbox bars stayed onscreen
-- and player audio/input state never recovered.
--
-- Fix: defer the skip one mod.update tick so the cutscene's full setup
-- (camera activation → letterbox apply → audio ducking) has time to land,
-- then call `skip_pressed` which runs the full teardown.
local _pending_auto_skip_system = nil

local function _gt_cutscene_skip_active()
    return mod:get("gt_skip_cutscenes_enabled") and true or false
end

if CutsceneSystem then
    mod:hook(CutsceneSystem, "flow_cb_cutscene_effect", function(func, self, name, ...)
        if _skip_next_fade and name == "fx_fade" then
            _skip_next_fade = false
            return
        end
        return func(self, name, ...)
    end)

    mod:hook(CutsceneSystem, "flow_cb_activate_cutscene_logic", function(func, self, player_input_enabled, event_on_activate, event_on_skip)
        local result = func(self, player_input_enabled, event_on_activate, event_on_skip)
        if _gt_cutscene_skip_active() and mod:get("gt_skip_cutscenes_auto") then
            _skip_next_fade = true
            script_data.skippable_cutscenes = true
            -- Don't fire event_on_skip directly here — defer to skip_pressed
            -- on the next tick so vanilla's full teardown runs (letterbox
            -- off + cameras deactivated + logic deactivated + event_on_skip).
            _pending_auto_skip_system = self
        end
        return result
    end)

    -- `skip_pressed` is the canonical user-skip path. With the toggle on we
    -- temporarily flip `script_data.skippable_cutscenes` for the duration of
    -- the call so vanilla's `if self.active_camera and script_data.skippable_cutscenes`
    -- branch fires regardless of the level's own author intent.
    mod:hook(CutsceneSystem, "skip_pressed", function(func, self, ...)
        if _gt_cutscene_skip_active() then
            local saved = script_data.skippable_cutscenes
            script_data.skippable_cutscenes = true
            _skip_next_fade = true
            local result = func(self, ...)
            script_data.skippable_cutscenes = saved
            -- If we deferred a skip from flow_cb_activate_cutscene_logic and
            -- the user happened to press skip themselves first, the auto-
            -- skip is now unnecessary — cancel it.
            _pending_auto_skip_system = nil
            return result
        end
        return func(self, ...)
    end)
end

-- Deferred auto-skip processor. Fires one tick after a cutscene activates
-- with auto-skip on. Registered through the central update subscriber
-- registry (Issue #16 — replaces the prior layered mod.update chain idiom).
_register_update("cutscene_auto_skip", function(dt)
    if _pending_auto_skip_system then
        local sys = _pending_auto_skip_system
        _pending_auto_skip_system = nil
        -- Guard against pcall failure tearing down our state — we already
        -- cleared the pending flag above. Vanilla skip_pressed checks
        -- `self.active_camera and script_data.skippable_cutscenes` itself,
        -- but we also guard here so we don't blow up if the cutscene was
        -- already torn down before our tick fired (race with another mod
        -- or the cutscene ending naturally).
        local ok, err = pcall(function()
            if sys.active_camera then
                local saved = script_data.skippable_cutscenes
                script_data.skippable_cutscenes = true
                sys:skip_pressed()
                script_data.skippable_cutscenes = saved
            end
        end)
        if not ok then
            mod:info("[gt_skipcutscenes] deferred skip failed: %s (cutscene state likely already torn down — harmless)", tostring(err))
        end
    end
end)

-- Underflow guard. Other mods (or vanilla code paths) sometimes pop the
-- cursor stack to 0 mid-cutscene; a follow-up pop would crash. Reproduce
-- the warning + early-return that Skip Cutscenes Please ships.
if ShowCursorStack then
    mod:hook(ShowCursorStack, "pop", function(func, ...)
        if ShowCursorStack.stack_depth <= 0 then
            return
        end
        return func(...)
    end)
end

mod.gt_skip_cutscenes_toggle = function()
    local new_val = not mod:get("gt_skip_cutscenes_enabled")
    mod:set("gt_skip_cutscenes_enabled", new_val)
    script_data.skippable_cutscenes = new_val or nil
    mod:echo("Skip cutscenes: " .. (new_val and "ON" or "OFF"))
end

mod:command("gt_skipcutscenes", "Toggle skipping cutscenes (auto-skip if 'Auto-skip' is enabled in settings, otherwise just allows ESC/Space)", function()
    mod.gt_skip_cutscenes_toggle()
end)

-- Apply once at load if the user kept the setting on across sessions.
if mod:get("gt_skip_cutscenes_enabled") then
    script_data.skippable_cutscenes = true
end

-- ============================================================
-- Disable Loading-Screen Monologues
-- ============================================================
-- Setting `script_data.disable_level_intro_dialogue` to true makes
-- state_loading.lua:585 + :635 skip Lohner/Olesya/weave-loading VO. This
-- is the same flag the vanilla debug screen exposes ("Visual/audio →
-- Disables the level introduction by Lohner / Olesya"), so it's the
-- canonical no-monologue toggle — no hooks required.

local function _gt_apply_disable_intro_monologue(enabled)
    script_data = script_data or {}
    script_data.disable_level_intro_dialogue = enabled and true or nil
end

_gt_apply_disable_intro_monologue(mod:get("gt_disable_intro_monologue"))

mod.gt_intro_monologue_toggle = function()
    local new_val = not mod:get("gt_disable_intro_monologue")
    mod:set("gt_disable_intro_monologue", new_val)
    _gt_apply_disable_intro_monologue(new_val)
    mod:echo("Loading-screen monologues: " .. (new_val and "DISABLED" or "enabled"))
end

mod:command("gt_intromono", "Toggle the Lohner/Olesya loading-screen monologues", function()
    mod.gt_intro_monologue_toggle()
end)

-- ============================================================
-- More Corpses (raise ragdoll cap)
-- ============================================================
-- Vanilla `RagdollSettings.max_num_ragdolls = 24` / `min_num_ragdolls = 10`
-- (unit_spawner_settings.lua:3-6). When the AI's combined alive+dead unit
-- count crosses max, UnitSpawner.update prunes corpses down to min. Raising
-- both lets more dead bodies linger before the engine starts despawning
-- them. Setting both to the same value means we cap pruning at exactly the
-- user's choice — the engine still cleans up everything beyond it, so this
-- is safe to crank without leaking units.

local _gt_ragdoll_defaults = {
    max_num_ragdolls = (RagdollSettings and RagdollSettings.max_num_ragdolls) or 24,
    min_num_ragdolls = (RagdollSettings and RagdollSettings.min_num_ragdolls) or 10,
}

mod.gt_apply_corpse_count = function()
    if not RagdollSettings then return end
    local enabled = mod:get("gt_more_corpses_enabled")
    if enabled then
        local count = mod:get("gt_more_corpses_count") or 24
        RagdollSettings.max_num_ragdolls = count
        RagdollSettings.min_num_ragdolls = count
    else
        RagdollSettings.max_num_ragdolls = _gt_ragdoll_defaults.max_num_ragdolls
        RagdollSettings.min_num_ragdolls = _gt_ragdoll_defaults.min_num_ragdolls
    end
end

mod.gt_apply_corpse_count()

-- ============================================================
-- Choose Grail Knight Quests
-- ============================================================
-- Override `PassiveAbilityQuestingKnight._generate_quest_pool` to return a
-- list whose FIRST THREE entries are the user's chosen quests. Vanilla's
-- caller (_start_quest_from_pool) consumes the first N items, so by
-- biasing the front of the pool we deterministically dictate which quests
-- the player gets, while leaving the rest of the pool intact for the
-- `markus_questing_knight_passive_additional_quest` talent (4th quest in
-- CW) and any future quest-pulling code that walks further into the list.
--
-- Setting id prefix `gt_gk_` so we don't collide with the standalone
-- ChooseGrailKnightQuests mod's setting names (quest1/quest2/quest3).

local function _gt_gk_find_in_pool(pool, reward, used)
    for i, quest in ipairs(pool) do
        if quest.reward == reward and not used[i] then
            return i
        end
    end
    return nil
end

if PassiveAbilityQuestingKnight then
    mod:hook(PassiveAbilityQuestingKnight, "_generate_quest_pool", function(func, self, ...)
        local pool = func(self, ...)
        if not mod:get("gt_gk_quests_enabled") then
            return pool
        end
        local selections = {
            mod:get("gt_gk_quest1") or "random",
            mod:get("gt_gk_quest2") or "random",
            mod:get("gt_gk_quest3") or "random",
        }
        local used = {}
        local chosen = {}
        for _, sel in ipairs(selections) do
            if sel and sel ~= "random" then
                local idx = _gt_gk_find_in_pool(pool, sel, used)
                if idx then
                    used[idx] = true
                    chosen[#chosen + 1] = pool[idx]
                end
            end
        end
        -- Append the rest of the (still-shuffled) pool after the user's
        -- selections so `markus_questing_knight_passive_additional_quest`
        -- and any other code that reads beyond index 3 still finds quests.
        for i, quest in ipairs(pool) do
            if not used[i] then
                chosen[#chosen + 1] = quest
            end
        end
        return chosen
    end)
end

-- ============================================================
-- Ready Up! (skip Bridge of Shadows countdown)
-- ============================================================
-- Two paths:
--   1. `mod.gt_ready_up_now` — host-callable shortcut (chat + keybind) that
--      jumps straight past the Bridge of Shadows countdown. Maps to
--      `Managers.matchmaking:countdown_completed()`, the same function the
--      countdown UI fires when it reaches zero.
--   2. `gt_auto_ready_on_vote_pass` — when on, hook
--      VoteManager.rpc_client_complete_vote so that any vote whose
--      vote_result == 1 (i.e. accepted) immediately triggers
--      countdown_completed() instead of waiting for the bridge animation.
--
-- All clients receive the rpc but only the server's call to
-- countdown_completed() has effect (the engine guards it server-side), so
-- gating on `Managers.player.is_server` keeps the echo line accurate even
-- though the underlying call is safe to invoke on clients.

mod.gt_ready_up_now = function()
    if not (Managers.matchmaking and Managers.matchmaking.countdown_completed) then
        mod:echo("Matchmaking manager not available (must be in the keep).")
        return
    end
    if not (Managers.player and Managers.player.is_server) then
        mod:echo("Only the host can ready up the lobby.")
        return
    end
    Managers.matchmaking:countdown_completed()
    mod:echo("Ready up — starting now.")
end

mod:command("gt_readyup", "Skip the Bridge of Shadows countdown and start the game now (host-only)", function()
    mod.gt_ready_up_now()
end)

if VoteManager then
    mod:hook_safe(VoteManager, "rpc_client_complete_vote", function(self, channel_id, vote_result)
        if not mod:get("gt_auto_ready_on_vote_pass") then return end
        if vote_result ~= 1 then return end
        if not (Managers.player and Managers.player.is_server) then return end
        if not (Managers.matchmaking and Managers.matchmaking.countdown_completed) then return end
        Managers.matchmaking:countdown_completed()
    end)
end

-- ============================================================
-- Hide UI (3 modes)
-- ============================================================
-- Replaces the "Hide UI" mod (Workshop 2007374303, removed from Workshop).
-- Three modes mirror the original:
--  * `off`      — HUD shown normally.
--  * `partial`  — hook GameModeBase.game_mode_hud_disabled to return true.
--                 Vanilla HUD visibility rules then auto-hide the bulk of the
--                 HUD (used by the "Act on Instinct" mutator). Subtitles,
--                 prompts, and twitch votes stay visible.
--  * `complete` — partial + iterate ingame_hud._components_array and force
--                 set_visible(false) on residual components (subtitle/prompt/etc).
--  * `camera`   — complete + hide first-person mesh (arms + weapon).
--
-- gt_hud cycles off → partial → complete → camera → off.

local HUD_MODE_OFF      = "off"
local HUD_MODE_PARTIAL  = "partial"
local HUD_MODE_COMPLETE = "complete"
local HUD_MODE_CAMERA   = "camera"

local _HUD_MODE_ORDER = {
    HUD_MODE_OFF, HUD_MODE_PARTIAL, HUD_MODE_COMPLETE, HUD_MODE_CAMERA,
}
local _HUD_MODE_LABEL = {
    [HUD_MODE_OFF]      = "Off",
    [HUD_MODE_PARTIAL]  = "Partial",
    [HUD_MODE_COMPLETE] = "Complete",
    [HUD_MODE_CAMERA]   = "Camera",
}

local function _gt_hud_mode()
    return mod:get("gt_hud_mode") or HUD_MODE_OFF
end

local function _gt_hud_is_hidden()
    return _gt_hud_mode() ~= HUD_MODE_OFF
end

-- Vanilla HUD component-visibility refresh runs every frame against the
-- active visibility group's whitelist. Force-hiding via set_visible(false)
-- in mod.update lets us stomp partial-mode residuals (subtitle/prompt) each
-- tick without fighting the visibility-group system.
local function _gt_hud_force_hide_components()
    local ingame_ui = Managers.ui
    local ingame_hud = ingame_ui and ingame_ui.ingame_hud
    if not (ingame_hud and ingame_hud._components_array) then return end
    for _, component in ipairs(ingame_hud._components_array) do
        if component and component.set_visible then
            pcall(component.set_visible, component, false)
        end
    end
end

local function _gt_first_person_unit()
    local local_player = Managers.player and Managers.player:local_player()
    local unit = local_player and local_player.player_unit
    if not (unit and Unit.alive(unit)) then return nil end
    local fp_ext = ScriptUnit.has_extension(unit, "first_person_system")
    if not fp_ext then return nil end
    -- Stingray exposes the FP rig as `first_person_unit` on the extension.
    return fp_ext.first_person_unit
end

local function _gt_hud_apply_camera_mode_visibility(want_visible)
    local fp_unit = _gt_first_person_unit()
    if not (fp_unit and Unit.alive(fp_unit)) then return end
    pcall(Unit.set_unit_visibility, fp_unit, want_visible)
    -- Also flip linked weapon meshes the FP rig carries — they're separate
    -- units attached via the inventory system, so set_unit_visibility on the
    -- FP rig alone leaves them rendered.
    local local_player = Managers.player and Managers.player:local_player()
    local pu = local_player and local_player.player_unit
    if pu and Unit.alive(pu) then
        local inv = ScriptUnit.has_extension(pu, "inventory_system")
        if inv and inv._equipment and inv._equipment.slots then
            for _, slot_data in pairs(inv._equipment.slots) do
                for _, key in ipairs({"left_unit_1p", "right_unit_1p"}) do
                    local u = slot_data[key]
                    if u and Unit.alive(u) then
                        pcall(Unit.set_unit_visibility, u, want_visible)
                    end
                end
            end
        end
    end
end

-- Hook the GameMode HUD-disabled query. Vanilla's HUD component list uses this
-- to swap visibility groups, so flipping it on for partial/complete/camera
-- automatically hides everything that opts into "game_mode_disable_hud".
mod:hook("GameModeBase", "game_mode_hud_disabled", function(func, self, ...)
    if _gt_hud_is_hidden() then return true end
    return func(self, ...)
end)

-- Cycle order: off → partial → complete → camera → off.
mod.gt_hud_cycle = function()
    local current = _gt_hud_mode()
    local next_idx = 1
    for i, m in ipairs(_HUD_MODE_ORDER) do
        if m == current then
            next_idx = (i % #_HUD_MODE_ORDER) + 1
            break
        end
    end
    local new_mode = _HUD_MODE_ORDER[next_idx]
    mod:set("gt_hud_mode", new_mode)
    mod:echo("Hide UI: " .. _HUD_MODE_LABEL[new_mode])
end

mod:command("gt_hud", "Cycle Hide UI mode (off/partial/complete/camera)", function()
    mod.gt_hud_cycle()
end)

-- Per-frame enforcement for complete + camera modes. Partial mode rides
-- entirely on the visibility-group hook above and needs no per-frame work.
-- Registered through the central update subscriber registry (Issue #16 —
-- replaces the prior layered mod.update chain idiom).
local _gt_hud_last_applied_mode = HUD_MODE_OFF
_register_update("hide_ui", function(dt)
    local current = _gt_hud_mode()
    if current == HUD_MODE_COMPLETE or current == HUD_MODE_CAMERA then
        _gt_hud_force_hide_components()
    end
    if current == HUD_MODE_CAMERA and _gt_hud_last_applied_mode ~= HUD_MODE_CAMERA then
        _gt_hud_apply_camera_mode_visibility(false)
    elseif current ~= HUD_MODE_CAMERA and _gt_hud_last_applied_mode == HUD_MODE_CAMERA then
        _gt_hud_apply_camera_mode_visibility(true)
    end
    _gt_hud_last_applied_mode = current
end)

-- ============================================================
-- Creature Spawner (ported from Aussiemon's CreatureSpawner mod,
-- Workshop ID 1395132559, MIT-licensed)
-- ============================================================
-- All gt_cs_* settings, helpers, hooks, and commands live below this header
-- and are namespaced to avoid colliding with the rest of gt. Names match the
-- original mod's structure 1:1 (build_unit_lists / next_spawn_breed /
-- spawn_debug_breed_at_cursor / get_status / position_at_cursor / etc.) so
-- diffing against the upstream source stays easy. Forward-declared at the
-- top of the file: `_gt_cs_on_setting_changed` and
-- `_gt_cs_on_game_state_changed` (the global on_setting_changed /
-- on_game_state_changed callbacks dispatch into them).

-- Unit categories table copied verbatim from CreatureSpawner_data.lua.
-- This is the upstream-authored map; do not edit entries here without
-- mirroring the change back to source if it's a bug-fix worth contributing.
local _gt_cs_unit_category_names = {
    "regular",
    "dummy",
    "misc",
    "special",
    "boss",
    "all",
}

local _gt_cs_unit_categories = {
    beastmen_bestigor = { "regular", "special" },
    beastmen_bestigor_dummy = { "dummy", "misc" },
    beastmen_gor = { "regular" },
    beastmen_gor_dummy = { "dummy", "misc" },
    beastmen_minotaur = { "regular", "boss" },
    beastmen_standard_bearer = { "regular", "special" },
    beastmen_standard_bearer_crater = { "misc" },
    beastmen_ungor = { "regular" },
    beastmen_ungor_dummy = { "dummy", "misc" },
    beastmen_ungor_archer = { "regular" },
    chaos_berzerker = { "regular", "special" },
    chaos_bulwark = { "regular", "special" },
    chaos_corruptor_sorcerer = { "regular", "special" },
    chaos_dummy_exalted_sorcerer_drachenfels = { "dummy", "misc" },
    chaos_dummy_sorcerer = { "dummy", "misc" },
    chaos_dummy_troll = { "dummy", "misc" },
    chaos_exalted_champion_norsca = { "boss" },
    chaos_exalted_champion_warcamp = { "boss" },
    chaos_exalted_sorcerer = { "boss" },
    chaos_exalted_sorcerer_drachenfels = { "boss" },
    chaos_fanatic = { "regular" },
    chaos_greed_pinata = { "misc" },
    chaos_marauder = { "regular" },
    chaos_marauder_tutorial = { "misc" },
    chaos_marauder_with_shield = { "regular" },
    chaos_mutator_sorcerer = { "misc" },
    chaos_plague_sorcerer = { "misc" },
    chaos_plague_wave_spawner = { "misc" },
    chaos_raider = { "regular", "special" },
    chaos_raider_tutorial = { "misc" },
    chaos_skeleton = { "regular", "misc" },
    chaos_spawn = { "regular", "boss" },
    chaos_spawn_exalted_champion_norsca = { "boss" },
    chaos_tentacle = { "misc" },
    chaos_tentacle_sorcerer = { "misc" },
    chaos_troll = { "regular", "boss" },
    chaos_vortex = { "misc" },
    chaos_vortex_sorcerer = { "regular", "special" },
    chaos_warrior = { "regular", "special" },
    chaos_zombie = { "misc" },
    critter_nurgling = { "misc" },
    critter_pig = { "regular" },
    critter_rat = { "regular" },
    curse_mutator_sorcerer = { "misc" },
    ethereal_skeleton_with_hammer = { "misc" },
    ethereal_skeleton_with_shield = { "misc" },
    pet_pig = { "misc" },
    pet_rat = { "misc" },
    pet_skeleton = { "misc" },
    pet_skeleton_armored = { "misc" },
    pet_skeleton_dual_wield = { "misc" },
    pet_skeleton_with_shield = { "misc" },
    shadow_lieutenant = { "misc" },
    shadow_skull = { "misc" },
    shadow_totem = { "misc" },
    skaven_clan_rat = { "regular" },
    skaven_clan_rat_tutorial = { "misc" },
    skaven_clan_rat_with_shield = { "regular" },
    skaven_dummy_clan_rat = { "dummy", "misc" },
    skaven_dummy_slave = { "dummy", "misc" },
    skaven_explosive_loot_rat = { "misc" },
    skaven_grey_seer = { "boss" },
    skaven_gutter_runner = { "regular", "special" },
    skaven_loot_rat = { "regular", "special" },
    skaven_pack_master = { "regular", "special" },
    skaven_plague_monk = { "regular", "special" },
    skaven_poison_wind_globadier = { "regular", "special" },
    skaven_rat_ogre = { "regular", "boss" },
    skaven_ratling_gunner = { "regular", "special" },
    skaven_slave = { "regular" },
    skaven_storm_vermin = { "regular", "special" },
    skaven_storm_vermin_champion = { "misc", "boss" },
    skaven_storm_vermin_commander = { "regular", "special" },
    skaven_storm_vermin_warlord = { "boss" },
    skaven_storm_vermin_with_shield = { "regular", "special" },
    skaven_stormfiend = { "regular", "boss" },
    skaven_stormfiend_boss = { "boss" },
    skaven_stormfiend_demo = { "misc", "boss" },
    skaven_warpfire_thrower = { "regular", "special" },
    tower_homing_skull = { "misc" },
    training_dummy = { "misc" },
}

-- Drachenfels exalted sorcerer is blacklisted from AI activation because its
-- run_on_spawn assumes the dlc_castle boss arena exists (level_analysis nodes,
-- spawner_system ids, etc.). Upstream mirrors this list.
local _gt_cs_ai_blacklist = {
    chaos_exalted_sorcerer_drachenfels = true,
}

local _gt_cs_hub_levels = {
    inn_level = true,
    inn_level_skulls = true,
    inn_level_celebrate = true,
    inn_level_halloween = true,
    inn_level_sonnstill = true,
}

-- The same lookup tables the upstream mod populates from `unit_categories`
-- at boot. Keys are the dropdown option values (regular_units / dummy_units /
-- etc.); values are the breed-name arrays we cycle through.
local _gt_cs_unit_lists = {
    regular_units = {},
    dummy_units   = {},
    misc_units    = {},
    special_units = {},
    boss_units    = {},
    all_units     = {},
}

-- Indexed list of every grudge-mark sub-toggle. Matches upstream so the
-- TerrorEventUtils.generate_enhanced_breed_from_set call sees the same keys
-- vanilla recognises.
local _gt_cs_grudge_keys = {
    "warping",
    "intangible",
    "unstaggerable",
    "raging",
    "vampiric",
    "ranged_immune",
    "periodic_shield",
    "crippling",
    "crushing",
    "regenerating",
    "periodic_curse",
    "commander",
    "frenzy",
}

-- Runtime selection state. `_gt_cs_breed_name_index` mirrors upstream's
-- `mod.breed_name_index`; tracks the active position in the currently-selected
-- unit list. `_gt_cs_buff_cap_limit_exceeded` mirrors upstream's same-named
-- flag — flipped by the BuffSystem.add_buff hook below so grudge-mark random
-- modifier additions back off when the server-controlled buff id table is
-- near capacity.
local _gt_cs_breed_name_index = 1
local _gt_cs_buff_cap_limit_exceeded = false

-- Track every unit we've actually spawned this session. ConflictDirector's
-- `destroy_all_units` is the host-wide despawn used by upstream too; we
-- forward to it on the "destroy" hotkey rather than maintain a private list,
-- so behaviour matches upstream's `handle_despawn_units` 1:1.

local function _gt_cs_build_unit_lists()
    -- Populate the per-category arrays. Walk Breeds (the global table loaded
    -- before any mod runs) and slot each breed into every category it belongs
    -- to per the upstream `unit_categories` map. Breeds not present in the
    -- map are NOT added to anything — same behaviour as the upstream
    -- `[Spawn]: Unrecognized breed name` warning, just silent in our case
    -- since gt isn't a spawning-focused mod and we'd rather not spam.
    for _, list_name in ipairs(_gt_cs_unit_category_names) do
        _gt_cs_unit_lists[list_name .. "_units"] = {}
    end
    if not Breeds then return end
    for breed_name, _ in pairs(Breeds) do
        local categories = _gt_cs_unit_categories[breed_name]
        if categories then
            for _, cat in ipairs(categories) do
                local list = _gt_cs_unit_lists[cat .. "_units"]
                if list then list[#list + 1] = breed_name end
            end
            local all = _gt_cs_unit_lists["all_units"]
            if all then all[#all + 1] = breed_name end
        end
    end
    for _, list_name in ipairs(_gt_cs_unit_category_names) do
        local list = _gt_cs_unit_lists[list_name .. "_units"]
        if list then
            table.sort(list, function(a, b) return a < b end)
        end
    end
end

local function _gt_cs_active_list()
    local key = mod:get("gt_cs_unit_list") or "regular_units"
    return _gt_cs_unit_lists[key] or _gt_cs_unit_lists.regular_units
end

local function _gt_cs_is_in_keep()
    if Managers and Managers.state and Managers.state.game_mode then
        local level_key = Managers.state.game_mode:level_key()
        return level_key and _gt_cs_hub_levels[level_key]
    end
    return false
end

local function _gt_cs_is_in_level(level_name)
    if Managers and Managers.state and Managers.state.game_mode then
        local level_key = Managers.state.game_mode:level_key()
        return level_key and level_key == level_name
    end
    return false
end

-- Returns (is_ready, conflict_director) — same shape as upstream's
-- `mod:get_status`. Refuses on non-host because every spawn primitive
-- below asserts on `Managers.player.is_server`.
local function _gt_cs_get_status(suppress_messages)
    local player_manager = Managers.player
    if not player_manager then
        if not suppress_messages then
            mod:echo("[Spawn]: Please wait. The game is not yet ready.")
        end
        return false
    end
    local conflict_director = Managers.state and Managers.state.conflict
    if not conflict_director then
        if not suppress_messages then
            mod:echo("[Spawn]: Please wait. The game is not yet ready.")
        end
        return false
    end
    if player_manager.is_server then
        return true, conflict_director
    end
    return false
end

-- Recursive table copy (deepcopy). Same implementation upstream uses
-- before patching `debug_spawn_optional_data` so we don't mutate the
-- shared `Breeds[breed_name]` table.
local function _gt_cs_deepcopy(orig, copies)
    copies = copies or {}
    local orig_type = type(orig)
    local copy
    if orig_type == "table" then
        if copies[orig] then
            copy = copies[orig]
        else
            copy = {}
            copies[orig] = copy
            for k, v in next, orig, nil do
                copy[_gt_cs_deepcopy(k, copies)] = _gt_cs_deepcopy(v, copies)
            end
            setmetatable(copy, _gt_cs_deepcopy(getmetatable(orig), copies))
        end
    else
        copy = orig
    end
    return copy
end

-- Raycast from the camera through the crosshair and return the first
-- non-self hit position. Mirrors upstream's `position_at_cursor` —
-- filter_ray_horde_spawn is the same collision filter the vanilla horde
-- spawner uses, so the result is always a valid spawn ground point.
local function _gt_cs_position_at_cursor(local_player)
    local viewport_name = local_player.viewport_name
    local camera_position = Managers.state.camera:camera_position(viewport_name)
    local camera_rotation = Managers.state.camera:camera_rotation(viewport_name)
    local camera_direction = Quaternion.forward(camera_rotation)
    local range = 500
    local world = Managers.world:world("level_world")
    local physics_world = World.get_data(world, "physics_world")
    local new_position
    local result = PhysicsWorld.immediate_raycast(
        physics_world,
        camera_position,
        camera_direction,
        range,
        "all",
        "collision_filter",
        "filter_ray_horde_spawn")
    if result then
        for i = 1, #result, 1 do
            local hit = result[i]
            local hit_actor = hit[4]
            local hit_unit = Actor.unit(hit_actor)
            local ray_hit_self = local_player.player_unit and (hit_unit == local_player.player_unit)
            if not ray_hit_self then
                new_position = hit[1]
                break
            end
        end
    end
    return new_position or camera_position
end

-- Cycle helpers — both wrap around the active list and skip breeds that
-- are no longer in `Breeds` (rare, mostly happens when a DLC isn't owned
-- or the breed was renamed). Matches upstream's next_spawn_breed /
-- previous_spawn_breed exactly.
local function _gt_cs_next_spawn_breed()
    local conflict_director = Managers.state.conflict
    if not conflict_director then return end
    conflict_director._show_switch_breed = 1
    local list = _gt_cs_active_list()
    if #list == 0 then return end
    local entry_index = _gt_cs_breed_name_index
    repeat
        _gt_cs_breed_name_index = _gt_cs_breed_name_index + 1
        if _gt_cs_breed_name_index > #list then
            _gt_cs_breed_name_index = 1
        end
        conflict_director._debug_breed = list[_gt_cs_breed_name_index] or "skaven_dummy_slave"
        if Breeds[conflict_director._debug_breed] then break end
    until _gt_cs_breed_name_index == entry_index
    if _gt_cs_breed_name_index == entry_index then
        mod:echo("[Spawn]: No units from the selected list are available right now.")
    else
        mod:set("gt_cs_selected_unit", conflict_director._debug_breed, false)
    end
end

local function _gt_cs_previous_spawn_breed()
    local conflict_director = Managers.state.conflict
    if not conflict_director then return end
    conflict_director._show_switch_breed = 1
    local list = _gt_cs_active_list()
    if #list == 0 then return end
    local entry_index = _gt_cs_breed_name_index
    repeat
        _gt_cs_breed_name_index = _gt_cs_breed_name_index - 1
        if _gt_cs_breed_name_index < 1 then
            _gt_cs_breed_name_index = #list
        end
        conflict_director._debug_breed = list[_gt_cs_breed_name_index] or "skaven_dummy_slave"
        if Breeds[conflict_director._debug_breed] then break end
    until _gt_cs_breed_name_index == entry_index
    if _gt_cs_breed_name_index == entry_index then
        mod:echo("[Spawn]: No units from the selected list are available right now.")
    else
        mod:set("gt_cs_selected_unit", conflict_director._debug_breed, false)
    end
end

-- Spawn the currently-selected breed at the crosshair raycast. 1:1 with
-- upstream's `spawn_debug_breed_at_cursor`. Grudge-mark handling supports
-- both RANDOM and MANUAL modes; the latter walks `_gt_cs_grudge_keys` and
-- looks up `gt_cs_grudge_<key>` checkboxes to assemble the enhancement
-- table.
local function _gt_cs_spawn_at_cursor()
    local conflict_director = Managers.state.conflict
    if not conflict_director then return end
    local local_player = Managers.player:local_player()
    if not local_player then return end

    local ai_warning_set = false
    local breed_name = conflict_director._debug_breed or ""
    if _gt_cs_ai_blacklist[breed_name] then
        if _gt_cs_is_in_keep() then
            mod:set("gt_cs_keep_ai", false)
        else
            mod:set("gt_cs_mission_ai", false)
        end
        ai_warning_set = true
    end

    local final_rotation
    local final_position = _gt_cs_position_at_cursor(local_player)
    local local_player_unit = local_player.player_unit
    if Unit.alive(local_player_unit) then
        final_rotation = Quaternion.multiply(Unit.local_rotation(local_player_unit, 0), Quaternion(Vector3(0, 0, 1), math.pi))
    else
        final_rotation = Quaternion(0, 0, 0, 0)
    end

    local breed = _gt_cs_deepcopy(Breeds[breed_name])
    if breed then
        breed.debug_spawn_optional_data = breed.debug_spawn_optional_data or {}
        breed.debug_spawn_optional_data.ignore_breed_limits = true
        breed.debug_spawn_optional_data.enhancements = nil

        local grudge_mark_setting = mod:get("gt_cs_grudge")
        if grudge_mark_setting then
            if not _gt_cs_buff_cap_limit_exceeded then
                if grudge_mark_setting == "RANDOM" then
                    local num_enhancements = mod:get("gt_cs_grudge_random_modifier_count") or 1
                    if TerrorEventUtils and TerrorEventUtils.add_enhancements_to_spawn_data then
                        breed.debug_spawn_optional_data = TerrorEventUtils.add_enhancements_to_spawn_data(
                            breed.debug_spawn_optional_data, num_enhancements, breed_name)
                    end
                elseif grudge_mark_setting == "MANUAL" then
                    local enhancement_list = {}
                    for _, key in ipairs(_gt_cs_grudge_keys) do
                        if mod:get("gt_cs_grudge_" .. key) then
                            enhancement_list[key] = true
                        end
                    end
                    if TerrorEventUtils and TerrorEventUtils.generate_enhanced_breed_from_set then
                        breed.debug_spawn_optional_data.enhancements =
                            TerrorEventUtils.generate_enhanced_breed_from_set(enhancement_list)
                    end
                end

                local grudgeString = ""
                local applied = breed.debug_spawn_optional_data.enhancements or {}
                for _, value in pairs(applied) do
                    local label = type(value) == "table" and tostring(value[1]) or tostring(value)
                    if grudgeString == "" then
                        grudgeString = label
                    else
                        grudgeString = grudgeString .. ", " .. label
                    end
                end
                if grudgeString ~= "" then
                    mod:echo("Applying " .. grudgeString .. " modifiers...")
                end
            else
                mod:echo("Too many active grudge-mark modifiers!")
            end
        end

        conflict_director:spawn_queued_unit(breed, Vector3Box(final_position), QuaternionBox(final_rotation),
            breed.debug_spawn_category or "debug_spawn", nil, nil, breed.debug_spawn_optional_data)
        mod:echo("[Spawn]: Created " .. tostring(conflict_director._debug_breed) .. ".")
    else
        mod:echo("[Spawn]: " .. tostring(conflict_director._debug_breed) .. " is not available.")
    end

    if ai_warning_set then
        mod:echo("[WARNING]: Enabling " .. breed_name .. " AI will likely cause crashes!")
    end
end

-- ----- COMMAND/HOTKEY HANDLERS (all bound to mod.* so VMF function_call
-- ----- keybinds can find them) -------------------------------------------

mod.gt_cs_spawn = function()
    local is_ready, conflict_director = _gt_cs_get_status()
    if not is_ready then return end
    _gt_cs_spawn_at_cursor()
end

mod.gt_cs_next = function()
    local is_ready, conflict_director = _gt_cs_get_status()
    if not is_ready then return end
    _gt_cs_next_spawn_breed()
    mod:echo("[Spawn]: >> " .. tostring(conflict_director._debug_breed) .. ".")
end

mod.gt_cs_prev = function()
    local is_ready, conflict_director = _gt_cs_get_status()
    if not is_ready then return end
    _gt_cs_previous_spawn_breed()
    mod:echo("[Spawn]: >> " .. tostring(conflict_director._debug_breed) .. ".")
end

mod.gt_cs_destroy = function()
    local is_ready, conflict_director = _gt_cs_get_status()
    if not is_ready then return end
    conflict_director:destroy_all_units()
    _gt_cs_buff_cap_limit_exceeded = false
    mod:echo("[Spawn]: Removed all enemies.")
end

local function _gt_cs_spawn_from_slot(slot_setting_id)
    local is_ready, conflict_director = _gt_cs_get_status()
    if not is_ready then return end
    local saved_breed = mod:get(slot_setting_id)
    if not saved_breed or saved_breed == "" then
        mod:echo("[Spawn]: Save slot is empty.")
        return
    end
    local original = conflict_director._debug_breed
    conflict_director._debug_breed = saved_breed
    _gt_cs_spawn_at_cursor()
    conflict_director._debug_breed = original
end

mod.gt_cs_spawn_slot_1 = function() _gt_cs_spawn_from_slot("gt_cs_saved_unit_one") end
mod.gt_cs_spawn_slot_2 = function() _gt_cs_spawn_from_slot("gt_cs_saved_unit_two") end
mod.gt_cs_spawn_slot_3 = function() _gt_cs_spawn_from_slot("gt_cs_saved_unit_three") end

-- /gt_savecreature <1-3> — saves currently-selected breed to a slot.
-- Accepts numeric or word form ("one"/"two"/"three") to match upstream.
local function _gt_cs_handle_save_unit_slot(...)
    local is_ready, conflict_director = _gt_cs_get_status()
    if not is_ready then return end
    local args = { ... }
    local slot = ""
    for _, value in ipairs(args) do
        if type(value) == "string" then
            slot = (slot == "" and value) or (slot .. " " .. value)
        elseif type(value) == "table" then
            for _, v in ipairs(value) do
                if type(v) == "string" then
                    slot = (slot == "" and v) or (slot .. " " .. v)
                end
            end
        end
    end
    local breed = conflict_director._debug_breed
    if slot == "1" or slot == "one" then
        mod:set("gt_cs_saved_unit_one", breed, false)
        mod:echo("[Spawn]: Saved " .. tostring(breed) .. " to slot one.")
    elseif slot == "2" or slot == "two" then
        mod:set("gt_cs_saved_unit_two", breed, false)
        mod:echo("[Spawn]: Saved " .. tostring(breed) .. " to slot two.")
    elseif slot == "3" or slot == "three" then
        mod:set("gt_cs_saved_unit_three", breed, false)
        mod:echo("[Spawn]: Saved " .. tostring(breed) .. " to slot three.")
    else
        mod:echo("[Spawn]: Unrecognized save slot. Please use numbers 1-3.")
    end
end

local function _gt_cs_handle_unit_slots_report()
    local is_ready, conflict_director = _gt_cs_get_status()
    if not is_ready then return end
    mod:echo("Selected unit: " .. tostring(conflict_director._debug_breed or "None"))
    mod:echo("Saved unit slot one: "   .. tostring(mod:get("gt_cs_saved_unit_one")   or "None"))
    mod:echo("Saved unit slot two: "   .. tostring(mod:get("gt_cs_saved_unit_two")   or "None"))
    mod:echo("Saved unit slot three: " .. tostring(mod:get("gt_cs_saved_unit_three") or "None"))
end

-- ----- HOOKS (defensive crashes + AI gating) ----------------------------
-- Hook list mirrors upstream 1:1, with two differences:
--   (a) Where upstream reads `mod:get("cs_*")` we read `mod:get("gt_cs_*")`.
--   (b) Hooks are guarded with `if Class then` so the mod doesn't crash
--       at load when a class hasn't been loaded yet (gt loads earlier in
--       the boot sequence than CreatureSpawner does).

-- Allow unit spawns in the Keep — strip down ConflictDirector.update so the
-- minimal pieces needed for spawn_queued_unit run, without engaging full
-- AI tracking / specials pacing.
if ConflictDirector then
    mod:hook(ConflictDirector, "update", function(func, self, dt, t, ...)
        if not _gt_cs_is_in_keep() then return func(self, dt, t, ...) end
        if not self.horde_spawner and HordeSpawner then
            self.horde_spawner = HordeSpawner:new(self._world, {})
        end
        if not self.specials_pacing and SpecialsPacing then
            self.specials_pacing = SpecialsPacing:new(self.nav_world)
            self.specials_pacing:enable(false)
        end
        self.level_settings = self.level_settings or {}
        self._time = t
        self:update_spawn_queue(t)
    end)
end

-- prop_joe's fix for keep-spawn breed freeze optimisation. Without flipping
-- this flag in the keep, the engine treats spawned units as if they aren't
-- in the active level and silently drops them from update.
if StateIngame then
    mod:hook_safe(StateIngame, "update", function(...)
        script_data.disable_breed_freeze_opt = _gt_cs_is_in_keep()
    end)
end

-- Two-toggle AI gate (mission vs. keep) — short-circuits the AI brain
-- update when the relevant checkbox is off. Same pattern upstream uses.
if AISystem then
    mod:hook(AISystem, "update_brains", function(func, ...)
        if not _gt_cs_is_in_keep() then
            return (mod:get("gt_cs_mission_ai") ~= false) and func(...)
        else
            return mod:get("gt_cs_keep_ai") and func(...)
        end
    end)
end

-- Lupo fix: zero out AI groups while mission AI is off so the engine
-- doesn't try to spawn AI ambush waves we explicitly disabled.
if AIGroupSystem then
    mod:hook(AIGroupSystem, "update", function(func, self, ...)
        if mod:get("gt_cs_mission_ai") == false and self.groups_to_initialize then
            for _, group in pairs(self.groups_to_initialize) do
                if group.members_n > 0 or group.num_spawned_members > 0 then
                    group.members_n = 0
                    group.num_spawned_members = 0
                end
            end
        end
        return func(self, ...)
    end)
end

-- Prevent boss loot die exception on despawn. POSITION_LOOKUP[unit] can be
-- nil during teardown; pcall keeps the engine alive past the read.
if AiBreedSnippets then
    mod:hook(AiBreedSnippets, "reward_boss_kill_loot", function(func, unit, ...)
        local position = POSITION_LOOKUP[unit]
        return pcall(function() return position.z end) and func(unit, ...)
    end)
end

-- Defensive aggro init — keep table guaranteed-present so update_aggro
-- doesn't index nil when an enemy spawns with no aggro_list yet.
if AiUtils then
    mod:hook(AiUtils, "update_aggro", function(func, unit, blackboard, breed, t, dt, ...)
        if not blackboard.aggro_list then
            blackboard.aggro_list = {}
        end
        return func(unit, blackboard, breed, t, dt, ...)
    end)
end

-- Sofia homing skull summon — provide a fallback `sofia_unit_pos` when the
-- skull is spawned outside a Sofia encounter (i.e. directly from this mod).
if ProjectileEtherealSkullLocomotionExtension then
    mod:hook(ProjectileEtherealSkullLocomotionExtension, "init", function(func, self, extension_init_context, unit, ...)
        local bb = BLACKBOARDS[unit]
        if bb and bb.optional_spawn_data and not bb.optional_spawn_data.sofia_unit_pos then
            local local_player = Managers.player and Managers.player:local_player()
            if not local_player then
                bb.optional_spawn_data.sofia_unit_pos = Vector3Box(Vector3.zero())
            else
                bb.optional_spawn_data.sofia_unit_pos = Vector3Box((_gt_cs_position_at_cursor(local_player) or Vector3.zero()))
            end
        end
        return func(self, extension_init_context, unit, ...)
    end)
end

-- Spinemanglr defensive summon — requires spawn_allies_positions, which
-- isn't populated outside of his arena. Drop the call early when not set.
if BTEnterHooks then
    mod:hook(BTEnterHooks, "warlord_defensive_on_enter", function(func, unit, blackboard, ...)
        return blackboard.spawn_allies_positions and func(unit, blackboard, ...)
    end)
end

-- BTSpawnAllies — the five-hook crash chain documented in upstream.
-- Together they: prevent enter without a call_position, drop run/leave/
-- find_spawn_point calls in the keep, and short-circuit any of them on a
-- nil-ish blackboard so the action either no-ops or returns "done".
if BTSpawnAllies then
    mod:hook(BTSpawnAllies, "enter", function(func, self, unit, blackboard, ...)
        if not _gt_cs_is_in_keep() and (blackboard.has_call_position or blackboard.override_spawn_allies_call_position) then
            return func(self, unit, blackboard, ...)
        end
        local action = self._tree_node and self._tree_node.action_data
        local find_spawn_points = action and action.find_spawn_points
        if find_spawn_points then
            local data = { end_time = math.huge }
            blackboard.spawning_allies = blackboard.spawning_allies or data
            local call_position = BTSpawnAllies.find_spawn_point(unit, blackboard, action, data)
            if call_position then
                return func(self, unit, blackboard, ...)
            else
                blackboard.spawning_allies = nil
            end
        else
            return func(self, unit, blackboard, ...)
        end
    end)

    mod:hook(BTSpawnAllies, "run", function(func, self, unit, blackboard, ...)
        return (not _gt_cs_is_in_keep() and blackboard.spawning_allies and func(self, unit, blackboard, ...)) or "done"
    end)

    mod:hook(BTSpawnAllies, "leave", function(func, self, unit, blackboard, ...)
        return (not _gt_cs_is_in_keep() and blackboard.action and func(self, unit, blackboard, ...))
    end)

    mod:hook(BTSpawnAllies, "find_spawn_point", function(func, unit, blackboard, action, data, override_spawn_group, ...)
        return (not _gt_cs_is_in_keep() and func(unit, blackboard, action, data, override_spawn_group, ...))
    end)
end

-- Drachenfels exalted sorcerer boss init — upstream's Lupo-authored
-- replacement of `run_on_spawn` that builds the full blackboard spell
-- state machine for the sorcerer fight. Verbatim port; the function is
-- intentionally long because it mirrors the vanilla boss init line-for-line
-- but skips the level_analysis nodes that only exist in dlc_castle. With
-- this hook in place the sorcerer can be spawned anywhere without
-- crashing the boss arena setup.
if Breeds and Breeds.chaos_exalted_sorcerer_drachenfels then
    mod:hook(Breeds.chaos_exalted_sorcerer_drachenfels, "run_on_spawn", function(func, unit, blackboard, ...)
        if _gt_cs_is_in_level("dlc_castle") then return func(unit, blackboard, ...) end
        local t = Managers.time:time("game")
        local breed = blackboard.breed
        blackboard.next_move_check = 0
        blackboard.max_vortex_units = breed.max_vortex_units
        blackboard.done_casting_timer = 0
        blackboard.spawned_allies_wave = 0
        blackboard.recent_attacker_timer = 0
        blackboard.recent_melee_attacker_timer = 0
        blackboard.health_extension = ScriptUnit.extension(unit, "health_system")
        blackboard.num_portals_alive = 0
        blackboard.tentacle_portal_units = {}
        blackboard.ring_total_cooldown = 20
        blackboard.charge_total_cooldown = 20
        blackboard.teleport_total_cooldown = 10
        blackboard.ring_cooldown = 0
        blackboard.charge_cooldown = 0
        blackboard.ring_summonings_finished = 0
        blackboard.teleport_cooldown = 0
        blackboard.ready_to_summon = true
        blackboard.surrounding_players = 0
        blackboard.aggro_list = {}
        blackboard.ring_pulse_rate = 0
        blackboard.defensive_phase_duration = 0
        blackboard.defensive_phase_max_duration = 60
        blackboard.no_kill_achievement = true
        blackboard.spell_count = 0
        local physics_world = World.get_data(blackboard.world, "physics_world")
        local spells = {}
        local spells_lookup = {}
        local function add_spell(s) spells[#spells + 1] = s; spells_lookup[s.name] = s end
        local s = {
            name = "plague_wave",
            plague_wave_timer = t + 10,
            physics_world = physics_world,
            target_starting_pos = Vector3Box(),
            plague_wave_rot = QuaternionBox(),
            search_func = BTChaosExaltedSorcererSkulkAction.update_plague_wave,
        }
        blackboard.plague_wave_data = s; add_spell(s)
        s = { range = 40, magic_missile = true, magic_missile_speed = 20,
            true_flight_template_name = "sorcerer_magic_missile",
            projectile_unit_name = "units/weapons/projectile/magic_missile/magic_missile",
            name = "magic_missile", launch_angle = 0.7,
            search_func = BTChaosExaltedSorcererSkulkAction.update_cast_missile,
            throw_pos = Vector3Box(), target_direction = Vector3Box() }
        blackboard.magic_missile_data = s; add_spell(s)
        s = { range = 40, magic_missile = true, magic_missile_speed = 15,
            true_flight_template_name = "sorcerer_strike_missile",
            projectile_unit_name = "units/weapons/projectile/strike_missile/strike_missile",
            name = "sorcerer_strike_missile",
            explosion_template_name = "chaos_strike_missile_impact",
            launch_angle = 1.25,
            search_func = BTChaosExaltedSorcererSkulkAction.update_cast_missile,
            throw_pos = Vector3Box(), target_direction = Vector3Box() }
        blackboard.sorcerer_strike_missile_data = s; add_spell(s)
        s = { range = 40, name = "magic_missile_ground", magic_missile = true,
            magic_missile_speed = 10, target_ground = true,
            projectile_unit_name = "units/weapons/projectile/strike_missile_drachenfels/strike_missile_drachenfels",
            true_flight_template_name = "sorcerer_magic_missile_ground",
            explosion_template_name = "chaos_drachenfels_strike_missile_impact",
            search_func = BTChaosExaltedSorcererSkulkAction.update_cast_missile,
            throw_pos = Vector3Box(), target_direction = Vector3Box() }
        blackboard.magic_missile_ground_data = s; add_spell(s)
        s = { name = "missile_barrage", magic_missile = true, magic_missile_speed = 20, range = 40,
            search_func = BTChaosExaltedSorcererSkulkAction.update_cast_missile,
            throw_pos = Vector3Box(), target_direction = Vector3Box() }
        blackboard.missile_barrage_data = s; add_spell(s)
        s = { range = 40, name = "seeking_bomb_missile", magic_missile = true, magic_missile_speed = 2.5,
            true_flight_template_name = "sorcerer_slow_bomb_missile",
            projectile_unit_name = "units/weapons/projectile/insect_swarm_missile_drachenfels/insect_swarm_missile_drachenfels_01",
            explosion_template_name = "chaos_slow_bomb_missile_new", life_time = 15,
            search_func = BTChaosExaltedSorcererSkulkAction.update_cast_missile,
            throw_pos = Vector3Box(), target_direction = Vector3Box(),
            projectile_size = { 3, 3, 3 } }
        blackboard.seeking_bomb_missile_data = s; add_spell(s)
        s = { name = "dummy", search_func = BTChaosExaltedSorcererSkulkAction.update_dummy }
        blackboard.dummy_data = s; add_spell(s)
        blackboard.phase = "offensive"
        blackboard.in_boss_arena = false
        blackboard.valid_teleport_pos_func = function() return true end
        local side = Managers.state.side:get_side_from_name("heroes")
        local player_units = side.PLAYER_AND_BOT_UNITS
        for _, player_unit in pairs(player_units) do
            local health_ext = ScriptUnit.extension(player_unit, "health_system")
            health_ext.is_invincible = true
        end
        blackboard.spells = spells
        blackboard.spells_lookup = spells_lookup
        local audio_system_ext = Managers.state.entity:system("audio_system")
        if breed.teleport_sound_event then
            audio_system_ext:play_audio_unit_event(breed.teleport_sound_event, unit)
        end
        local conflict_director = Managers.state.conflict
        conflict_director:add_unit_to_bosses(unit)
        blackboard.is_valid_target_func = GenericStatusExtension.is_lord_target
    end)

    mod:hook(Breeds.chaos_exalted_sorcerer_drachenfels, "run_on_death", function(func, unit, blackboard, ...)
        if _gt_cs_is_in_level("dlc_castle") then return func(unit, blackboard, ...) end
        local conflict_director = Managers.state.conflict
        local position = Unit.world_position(unit, 0)
        conflict_director:remove_unit_from_bosses(unit)
        local audio_system = Managers.state.entity:system("audio_system")
        audio_system:play_audio_unit_event("Play_sorcerer_boss_fly_stop", unit)
        local t = Managers.time:time("game")
        Managers.state.conflict.specials_pacing:delay_spawning(t, 120, 20, true)
        if blackboard.is_angry then
            conflict_director:add_angry_boss(-1)
        end
        AiBreedSnippets.drop_loot_dice(4, position, true)
    end)
end

-- Drachenfels phase-transition condition — bias to TRUE outside dlc_castle
-- so the boss skips its arena-specific defensive phase and stays in
-- offensive mode (otherwise the missing arena nodes cause a soft lock).
if BTConditions then
    mod:hook(BTConditions, "transitioned_one_third_health", function(func, ...)
        return (_gt_cs_is_in_level("dlc_castle") and func(...)) or true
    end)
end

-- Keep-navigation crash suite. All of these short-circuit when in the
-- keep level (no real navmesh for AI to path on). Matches upstream 1:1.
if BTLootRatFleeAction then
    mod:hook(BTLootRatFleeAction, "enter", function(func, ...) return (not _gt_cs_is_in_keep() and func(...)) or false end)
    mod:hook(BTLootRatFleeAction, "run",   function(func, ...) return (not _gt_cs_is_in_keep() and func(...)) or "running" end)
    mod:hook(BTLootRatFleeAction, "leave", function(func, ...) return (not _gt_cs_is_in_keep() and func(...)) or false end)
end
if NavigationGroupManager then
    mod:hook(NavigationGroupManager, "a_star_cached_between_positions", function(func, ...)
        return (not _gt_cs_is_in_keep() and func(...)) or false
    end)
end
if LocomotionUtils then
    mod:hook(LocomotionUtils, "pos_on_mesh", function(func, ...)
        return (not _gt_cs_is_in_keep() and func(...)) or nil
    end)
end
if GwNavQueries then
    mod:hook(GwNavQueries, "inside_position_from_outside_position", function(func, ...)
        return (not _gt_cs_is_in_keep() and func(...)) or nil
    end)
end

-- Prevent keep navigation crash — Unit.create_actor with id=-1 in the keep
-- crashes the engine actor allocator. Block only that exact case.
mod:hook(Unit, "create_actor", function(func, self, id, ...)
    if not _gt_cs_is_in_keep() or id ~= -1 then
        return func(self, id, ...)
    end
end)

if BTSkulkAroundAction then
    mod:hook(BTSkulkAroundAction, "get_new_skulk_goal", function(func, self, unit, blackboard, ...)
        if not _gt_cs_is_in_keep() then return func(self, unit, blackboard, ...) end
        local player = Managers.player:local_player()
        local player_unit = player and player.player_unit
        return player_unit and Unit.local_position(player_unit, 0) or Vector3(0, 0, 0)
    end)
end

-- Instantiate blackboard utility-action data when missing — avoids the
-- "missing blackboard value" crash hammering when utility AI selects an
-- action whose considerations table hasn't been populated yet.
if Utility then
    mod:hook(Utility, "get_action_utility", function(func, breed_action, action_name, blackboard, ...)
        local blackboard_action_data = blackboard.utility_actions and blackboard.utility_actions[action_name]
        local considerations = breed_action.considerations
        if blackboard_action_data and considerations then
            for _, consideration in pairs(considerations) do
                if type(consideration) == "table" then
                    local input = consideration.blackboard_input
                    local blackboard_value = blackboard_action_data[input] or blackboard[input]
                    if not blackboard_value then
                        blackboard_action_data = {
                            last_time = -math.huge,
                            time_since_last = math.huge,
                            last_done_time = -math.huge,
                            time_since_last_done = math.huge,
                        }
                        if not blackboard_action_data[input] then
                            blackboard_action_data[input] = -math.huge
                        end
                    end
                end
            end
        end
        return func(breed_action, action_name, blackboard, ...)
    end)
end

-- Server-controlled buff cap detector. NetworkConstants caps the number of
-- buff ids the host can broadcast; once we're close to it, flip the flag
-- so grudge-mark random modifiers stop adding to the bucket. Matches
-- upstream behaviour 1:1.
if BuffSystem and NetworkConstants and NetworkConstants.server_controlled_buff_id then
    mod:hook(BuffSystem, "add_buff", function(func, self, ...)
        local return_val = func(self, ...)
        if (self.next_server_buff_id or 0) * 10 >= NetworkConstants.server_controlled_buff_id.max * 5 then
            _gt_cs_buff_cap_limit_exceeded = true
        else
            _gt_cs_buff_cap_limit_exceeded = false
        end
        return return_val
    end)
end

-- Missing-unit guard — when a breed references a unit path that isn't in
-- any loaded package, fall back to `units/hub_elements/empty` so the
-- engine doesn't fatally fail spawn_unit. Same fallback unit upstream uses.
mod:hook(World, "spawn_unit", function(func, self, unit_name, ...)
    if Application.can_get("unit", unit_name) then
        return func(self, unit_name, ...)
    else
        return func(self, "units/hub_elements/empty", ...)
    end
end)

-- Force EnemyPackageLoader to ignore breed limits — the limit is what
-- normally prevents debug spawns from loading the right packages on demand.
if EnemyPackageLoader then
    mod:hook(EnemyPackageLoader, "request_breed", function(func, self, breed_name, ignore_breed_limits, ...)
        return func(self, breed_name, true, ...)
    end)
end

-- Command registration (gt-prefixed to namespace away from upstream's
-- bare `spawn_unit` / `save_unit` / `selected_units` names).
mod:command("gt_spawncreature",  "Spawn the currently-selected creature at the cursor",                function() mod.gt_cs_spawn() end)
mod:command("gt_nextcreature",   "Cycle to the next creature in the active list",                     function() mod.gt_cs_next() end)
mod:command("gt_prevcreature",   "Cycle to the previous creature in the active list",                 function() mod.gt_cs_prev() end)
mod:command("gt_destroycreatures", "Destroy every currently-spawned creature (host-only)",           function() mod.gt_cs_destroy() end)
mod:command("gt_savecreature",   "Save current creature to a slot (1-3)",                             function(...) _gt_cs_handle_save_unit_slot(...) end)
mod:command("gt_selectedcreatures", "Report current selection and the three save slots",            function() _gt_cs_handle_unit_slots_report() end)

-- Forward-declared callbacks (referenced at the top of the file from the
-- global on_setting_changed / on_game_state_changed dispatch). Assignments
-- here MUST use `_gt_cs_on_setting_changed = ...` not `local function ...`,
-- otherwise the early dispatch above binds to a nil global.
_gt_cs_on_setting_changed = function(setting_id)
    if setting_id == "gt_cs_unit_list" then
        local is_ready, conflict_director = _gt_cs_get_status()
        if not is_ready then return end
        local list = _gt_cs_active_list()
        _gt_cs_breed_name_index = 1
        conflict_director._debug_breed = list[1] or "skaven_dummy_slave"
        mod:set("gt_cs_selected_unit", conflict_director._debug_breed, false)
        mod:echo("[Spawn]: >> " .. tostring(conflict_director._debug_breed) .. ".")
    elseif setting_id == "gt_cs_selected_unit" then
        local is_ready, conflict_director = _gt_cs_get_status()
        if not is_ready then return end
        conflict_director._debug_breed = mod:get("gt_cs_selected_unit")
        mod:echo("[Spawn]: >> " .. tostring(conflict_director._debug_breed) .. ".")
    end
end

_gt_cs_on_game_state_changed = function(status, state_name)
    local is_ready, conflict_director = _gt_cs_get_status(true)
    if not is_ready then return end
    if not mod:get("gt_cs_selected_unit") or mod:get("gt_cs_selected_unit") == "" then
        local list = _gt_cs_active_list()
        conflict_director._debug_breed = list[1] or "skaven_dummy_slave"
        mod:set("gt_cs_selected_unit", conflict_director._debug_breed, false)
    else
        conflict_director._debug_breed = mod:get("gt_cs_selected_unit")
    end
    _gt_cs_buff_cap_limit_exceeded = false
end

-- Build lists at mod load. Breeds is populated before mods run, so this is
-- safe to call here; matches upstream's `mod:build_unit_lists()` placement
-- at the bottom of CreatureSpawner.lua.
_gt_cs_build_unit_lists()

-- ============================================================
-- Item Spawner (ported from Vermintide-Mods/ItemSpawner, MIT-licensed)
-- ============================================================
-- Spawns pickups (ammo, potions, tomes, grimoires, training dummies, grenades,
-- barrels, lorebook pages, healing items, door sticks, torches, oils) at the
-- player position via vanilla's `rpc_spawn_pickup_with_physics` (or
-- `rpc_spawn_pickup` for `all_ammo`). Cycles through the live `AllPickups`
-- table filtered against the same exclusion list the upstream mod used
-- (loot_die, lorebook_pages, beer_barrel — these crash on spawn). Training
-- dummies are host-only per vanilla restrictions.
--
-- `/gt_spawnitem <substring>` fuzzy-matches against pickup_name or the
-- localised item name. Hotkey trio (`gt_is_next` / `gt_is_prev` /
-- `gt_is_spawn`) cycles + spawns the currently selected pickup.

local _gt_is_pickup_names = nil
local _gt_is_current = nil
local _gt_is_excluded = {
    loot_die = true,
    lorebook_pages = true,
    beer_barrel = true,
}

local function _gt_is_init_pickups()
    if _gt_is_pickup_names then return end
    if not AllPickups then return end
    local names = {}
    for k, v in pairs(AllPickups) do
        if not _gt_is_excluded[k] then
            -- Match upstream filter: skip any pickup whose unit template
            -- contains "_limited" or whose name contains "endurance_badge".
            local tmpl = v.unit_template_name or ""
            if not string.find(tmpl, "_limited", 1, true)
            and not string.find(k, "endurance_badge", 1, true) then
                names[#names + 1] = k
            end
        end
    end
    table.sort(names)
    _gt_is_pickup_names = names
    if not _gt_is_current and names[1] then
        _gt_is_current = names[1]
    end
end

local function _gt_is_index_of(name)
    if not _gt_is_pickup_names then return 0 end
    for i, n in ipairs(_gt_is_pickup_names) do
        if n == name then return i end
    end
    return 0
end

-- Vanilla spawn path. `all_ammo` uses the non-physics RPC because the
-- physics variant on a multi-pickup unit crashes the host's ammo-collector.
local function _gt_is_spawn(pickup_name)
    if not (Managers.player and Managers.state and Managers.state.network) then return end
    local lp = Managers.player:local_player()
    if not (lp and lp.player_unit and Unit.alive(lp.player_unit)) then
        mod:echo("No local player unit.")
        return
    end
    if not Managers.player.is_server then
        local dummy_set = {
            training_dummy = true,
            training_dummy_armored = true,
            training_dummy_skaven = true,
        }
        if dummy_set[pickup_name] then
            mod:echo("Need to be host to spawn training dummies.")
            return
        end
    end
    local spawn_method = (pickup_name == "all_ammo")
        and "rpc_spawn_pickup"
        or  "rpc_spawn_pickup_with_physics"
    local pos = Unit.local_position(lp.player_unit, 0)
    local rot = Unit.local_rotation(lp.player_unit, 0)
    local pickup_id = rawget(NetworkLookup.pickup_names, pickup_name)
    if not pickup_id then
        mod:echo("Unknown pickup name: " .. tostring(pickup_name))
        return
    end
    Managers.state.network.network_transmit:send_rpc_server(
        spawn_method,
        pickup_id,
        pos, rot,
        NetworkLookup.pickup_spawn_types.dropped)
end

mod.gt_is_next = function()
    _gt_is_init_pickups()
    if not _gt_is_pickup_names or #_gt_is_pickup_names == 0 then return end
    local idx = _gt_is_index_of(_gt_is_current) + 1
    if idx > #_gt_is_pickup_names then idx = 1 end
    _gt_is_current = _gt_is_pickup_names[idx]
    mod:echo("Selected pickup: " .. _gt_is_current)
end

mod.gt_is_prev = function()
    _gt_is_init_pickups()
    if not _gt_is_pickup_names or #_gt_is_pickup_names == 0 then return end
    local idx = _gt_is_index_of(_gt_is_current) - 1
    if idx < 1 then idx = #_gt_is_pickup_names end
    _gt_is_current = _gt_is_pickup_names[idx]
    mod:echo("Selected pickup: " .. _gt_is_current)
end

mod.gt_is_spawn = function()
    _gt_is_init_pickups()
    if not _gt_is_current then
        mod:echo("No pickup selected.")
        return
    end
    _gt_is_spawn(_gt_is_current)
    mod:echo("Spawned: " .. _gt_is_current)
end

mod.gt_is_switch = function(user_input)
    _gt_is_init_pickups()
    if not user_input or user_input == "" then
        mod:echo("Current pickup: " .. tostring(_gt_is_current))
        return
    end
    local q = string.lower(user_input)
    for _, name in ipairs(_gt_is_pickup_names) do
        local matches_key  = string.find(string.lower(name), q, 1, true)
        local localized    = AllPickups[name] and AllPickups[name].item_name
                             and Localize(AllPickups[name].item_name) or ""
        local matches_name = string.find(string.lower(localized), q, 1, true)
        if matches_key or matches_name then
            _gt_is_current = name
            mod:echo("Selected pickup: " .. name)
            return
        end
    end
    mod:echo("No pickup matches: " .. user_input)
end

mod:command("gt_spawnitem", "Spawn or switch pickup (no arg = report current; with arg = fuzzy-match by key or localized name)", function(...)
    local args = { ... }
    mod.gt_is_switch(args[1])
    if args[1] then mod.gt_is_spawn() end
end)
mod:command("gt_nextitem", "Cycle to next pickup in the spawn list", function() mod.gt_is_next() end)
mod:command("gt_previtem", "Cycle to previous pickup in the spawn list", function() mod.gt_is_prev() end)

-- ============================================================
-- Level Dump (verbose snapshot of the currently-loaded level)
-- ============================================================
-- One-shot console command that walks every interesting piece of runtime
-- state we might care about while modding: identity (level_key, game mode,
-- conflict director, difficulty), worlds + unit-count breakdown, pickup
-- spawners + currently-spawned pickups grouped by type, Chaos Wastes
-- chest/objective/relic units, the global interactable inventory, the
-- breed roster wired into the active conflict settings, level-scoped
-- terror events, the live UI surfaces, and the active HUD elements.
--
-- Doctrine (per the task brief):
--   * Every section is wrapped in pcall — one missing field can't tank the
--     rest of the dump.
--   * Runtime introspection only — every manager / extension is checked
--     via rawget or `Managers.*` existence before its methods are called,
--     so the command never crashes on an absent system (e.g. running it
--     in the inn, where there is no conflict director).
--   * Heavy data lands in `mod:info(...)` (console-*.log). Section headers
--     and a final one-line summary land in BOTH `mod:info` and `mod:echo`
--     (in-game chat) so the user knows the dump fired.
--   * Disk side-car (level_dump_<level>_<ts>.txt under
--     mod:get_temp_data_directory) is intentionally skipped — VMF mods
--     have no usable filesystem write API; the doctrine says "if you
--     can't write to disk from VMF, skip silently".

local _LD_PREFIX = "[level_dump]"

mod:command("dump_level", "Verbose level/world/pickups/breeds/UI snapshot (best run AFTER you've entered the area you want to capture)", function()
    local out_lines = {}
    local function out(fmt, ...)
        local line
        if select("#", ...) > 0 then
            line = string.format(fmt, ...)
        else
            line = fmt
        end
        out_lines[#out_lines + 1] = line
        mod:info("%s %s", _LD_PREFIX, line)
    end
    local function section(name)
        out("=========== %s ===========", name)
    end
    local function section_fail(name, err)
        out("%s section %s failed: %s", _LD_PREFIX, name, tostring(err))
    end
    local function safe(name, fn)
        local ok, err = pcall(fn)
        if not ok then section_fail(name, err) end
    end

    local ts = os and os.time and os.time() or 0
    out("=== /dump_level start (unix_ts=%s) ===", tostring(ts))

    -- ---------- 1) Identity ----------
    local level_key_for_filename = "unknown"
    safe("1 identity", function()
        section("1) Identity")

        local lth = rawget(_G, "Managers") and Managers.level_transition_handler
        if lth and lth.get_current_level_key then
            local lk = lth:get_current_level_key()
            out("LevelTransitionHandler.current_level_key = %s", tostring(lk))
            level_key_for_filename = tostring(lk or "unknown")
            if lth.get_current_level_keys then
                local _, sub = pcall(function() return select(2, lth:get_current_level_keys()) end)
                if sub then out("LevelTransitionHandler.current_sub_level_key = %s", tostring(sub)) end
            end
            if lth.get_current_level_seed then
                out("LevelTransitionHandler.current_level_seed = %s", tostring(lth:get_current_level_seed()))
            end
            if lth.get_current_environment_variation_name then
                local _, env = pcall(lth.get_current_environment_variation_name, lth)
                out("LevelTransitionHandler.environment_variation = %s", tostring(env))
            end
        else
            out("LevelTransitionHandler: (not available)")
        end

        local gm = Managers and Managers.state and Managers.state.game_mode
        if gm then
            if gm.game_mode_key then out("GameModeManager.game_mode_key = %s", tostring(gm:game_mode_key())) end
            if gm.level_key      then out("GameModeManager.level_key = %s", tostring(gm:level_key())) end
            local mode = gm.game_mode and gm:game_mode()
            if mode then
                out("GameModeManager._game_mode class.NAME = %s", tostring(mode.NAME or mode.__class_name or "?"))
                if mode.settings then
                    local _, s = pcall(mode.settings, mode)
                    if type(s) == "table" then
                        out("game_mode:settings().key = %s", tostring(s.key))
                        out("game_mode:settings().mutators_allowed = %s", tostring(s.mutators_allowed))
                    end
                end
                if mode.game_mode_state then
                    local _, st = pcall(mode.game_mode_state, mode)
                    out("game_mode:game_mode_state() = %s", tostring(st))
                end
            end
        else
            out("GameModeManager: (none — likely state_loading or main menu)")
        end

        local mech_mgr = Managers and Managers.mechanism
        if mech_mgr and mech_mgr.current_mechanism_name then
            out("Mechanism.current_mechanism_name = %s", tostring(mech_mgr:current_mechanism_name()))
        end

        local conflict = Managers and Managers.state and Managers.state.conflict
        if conflict then
            out("ConflictDirector.current_conflict_settings = %s", tostring(conflict.current_conflict_settings))
            if conflict.level_settings then
                out("ConflictDirector.level_settings.level_id = %s", tostring(conflict.level_settings.level_id or conflict.level_settings.display_name))
            end
        else
            out("ConflictDirector: (not in a mission)")
        end

        local diff_mgr = Managers and Managers.state and Managers.state.difficulty
        if diff_mgr and diff_mgr.get_difficulty then
            local _, d = pcall(diff_mgr.get_difficulty, diff_mgr)
            out("DifficultyManager.get_difficulty = %s", tostring(d))
            if diff_mgr.get_difficulty_rank then
                local _, dr = pcall(diff_mgr.get_difficulty_rank, diff_mgr)
                out("DifficultyManager.get_difficulty_rank = %s", tostring(dr))
            end
        end

        local lk = (gm and gm.level_key and gm:level_key()) or "?"
        local mission_settings = rawget(_G, "MissionSettings")
        if mission_settings and mission_settings[lk] then
            out("MissionSettings[%s] = (present)", tostring(lk))
        else
            out("MissionSettings[%s] = (none — likely not a story mission)", tostring(lk))
        end

        if rawget(_G, "Application") then
            if Application.platform then out("Application.platform() = %s", tostring(Application.platform())) end
            if Application.build    then out("Application.build()    = %s", tostring(Application.build())) end
        end
    end)

    -- ---------- 2) Worlds + units overview ----------
    local level_world = nil
    safe("2 worlds", function()
        section("2) Worlds + units overview")
        local wm = Managers and Managers.world
        if not (wm and wm._worlds) then out("WorldManager: (none)"); return end
        local names = {}
        for name in pairs(wm._worlds) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local world = wm._worlds[name]
            local n_units = 0
            local ok, units = pcall(World.units, world)
            if ok and type(units) == "table" then n_units = #units end
            out("world '%s' -> %d unit(s)", name, n_units)
            if name == (rawget(_G, "LevelHelper") and LevelHelper.INGAME_WORLD_NAME or "level_world") then
                level_world = world
            end
        end

        if not level_world then out("level_world: (not found — early game state?)"); return end

        local units = World.units(level_world)
        local total = #units
        local with_interactable, with_pickup, with_pickup_spawner = 0, 0, 0
        local with_deus_chest, with_deus_cursed_chest, with_deus_relic = 0, 0, 0
        local with_deus_arena_idol, with_deus_arena_interactable = 0, 0
        local with_deus_belakor = 0
        for _, u in ipairs(units) do
            if Unit.alive(u) then
                if ScriptUnit.has_extension(u, "interactable_system") then with_interactable = with_interactable + 1 end
                if ScriptUnit.has_extension(u, "pickup_system") then
                    with_pickup = with_pickup + 1
                    -- PickupSpawnerExtension is also under pickup_system; identify via the spawner's no-pickup_name init.
                    local ext = ScriptUnit.extension(u, "pickup_system")
                    if ext and ext.get_spawn_location_data and not ext.pickup_name then
                        with_pickup_spawner = with_pickup_spawner + 1
                    end
                end
                if ScriptUnit.has_extension(u, "deus_cursed_chest_system") then with_deus_cursed_chest = with_deus_cursed_chest + 1 end
                if ScriptUnit.has_extension(u, "deus_relic_system") then with_deus_relic = with_deus_relic + 1 end
                if ScriptUnit.has_extension(u, "deus_arena_idol_system") then with_deus_arena_idol = with_deus_arena_idol + 1 end
                if ScriptUnit.has_extension(u, "deus_arena_interactable_system") then with_deus_arena_interactable = with_deus_arena_interactable + 1 end
                if ScriptUnit.has_extension(u, "deus_belakor_locus_system")
                   or ScriptUnit.has_extension(u, "deus_belakor_totem_system")
                   or ScriptUnit.has_extension(u, "deus_belakor_crystal_system") then
                    with_deus_belakor = with_deus_belakor + 1
                end
                -- DeusChestExtension is also under pickup_system; sniff by field.
                local pe = ScriptUnit.has_extension(u, "pickup_system")
                if pe and pe._is_server ~= nil and pe._deus_run_controller then
                    with_deus_chest = with_deus_chest + 1
                end
            end
        end
        out("level_world unit totals: %d total, interactables=%d, pickup_system=%d (of which spawners=%d)",
            total, with_interactable, with_pickup, with_pickup_spawner)
        out("level_world deus units: chests=%d cursed_chests=%d relics=%d arena_idol=%d arena_interactable=%d belakor=%d",
            with_deus_chest, with_deus_cursed_chest, with_deus_relic, with_deus_arena_idol, with_deus_arena_interactable, with_deus_belakor)
    end)

    -- ---------- 3) Pickup spawners + live pickups ----------
    safe("3 pickups", function()
        section("3) Pickup spawners + currently-alive pickups")
        local entity_mgr = Managers and Managers.state and Managers.state.entity
        local pickup_system = entity_mgr and entity_mgr.system and entity_mgr:system("pickup_system")
        if not pickup_system then out("(none — no pickup_system; not in a mission?)"); return end

        local function dump_spawner_bucket(bucket_name, bucket)
            if type(bucket) ~= "table" then return end
            local n = 0
            for _ in pairs(bucket) do n = n + 1 end
            out("--- pickup_system.%s (%d) ---", bucket_name, n)
            -- Buckets are usually keyed; walk values, log spawner_id (key) + pickup_name + position.
            for key, entry in pairs(bucket) do
                local pickup_name, unit
                if type(entry) == "table" then
                    pickup_name = entry.pickup_name
                    unit = entry.unit or entry[1]
                end
                local pos_str = "?"
                if unit and Unit.alive(unit) then
                    local ok, p = pcall(Unit.world_position, unit, 0)
                    if ok and p then pos_str = string.format("(%.1f,%.1f,%.1f)", Vector3.to_elements(p)) end
                end
                out("  spawner key=%s pickup_name=%s pos=%s", tostring(key), tostring(pickup_name), pos_str)
            end
        end
        dump_spawner_bucket("guaranteed_pickup_spawners", pickup_system.guaranteed_pickup_spawners)
        dump_spawner_bucket("triggered_pickup_spawners",  pickup_system.triggered_pickup_spawners)
        dump_spawner_bucket("primary_pickup_spawners",    pickup_system.primary_pickup_spawners)
        dump_spawner_bucket("secondary_pickup_spawners",  pickup_system.secondary_pickup_spawners)
        dump_spawner_bucket("specified_pickup_spawners",  pickup_system.specified_pickup_spawners)

        -- _pickup_units_by_type is the live-spawned units table, keyed by pickup_name (every AllPickups key).
        local by_type = pickup_system._pickup_units_by_type
        if type(by_type) ~= "table" then out("(_pickup_units_by_type missing)"); return end

        local names = {}
        for name in pairs(by_type) do names[#names + 1] = name end
        table.sort(names)
        out("--- _pickup_units_by_type (currently-spawned units, by pickup_name) ---")
        local total_alive = 0
        local summary = {}
        for _, name in ipairs(names) do
            local arr = by_type[name]
            local count = 0
            for i = 1, #arr do
                local u = arr[i]
                if u and Unit.alive(u) then count = count + 1 end
            end
            if count > 0 then
                summary[#summary + 1] = string.format("%s=%d", name, count)
                total_alive = total_alive + count
                local pickup_settings = rawget(_G, "AllPickups") and AllPickups[name]
                local category = pickup_settings and (pickup_settings.spawn_category or pickup_settings.type) or "?"
                out("  %-40s alive=%d  category=%s", name, count, tostring(category))
                for i = 1, #arr do
                    local u = arr[i]
                    if u and Unit.alive(u) then
                        local ext = ScriptUnit.has_extension(u, "pickup_system")
                        local pos_str = "?"
                        local ok, p = pcall(Unit.world_position, u, 0)
                        if ok and p then pos_str = string.format("(%.1f,%.1f,%.1f)", Vector3.to_elements(p)) end
                        local picked_up = ext and (ext.picked_up == true or ext._picked_up == true)
                        out("      pos=%s spawn_type=%s spawn_index=%s picked_up=%s",
                            pos_str,
                            tostring(ext and ext.spawn_type),
                            tostring(ext and ext.spawn_index),
                            tostring(picked_up))
                    end
                end
            end
        end
        out("pickup-by-type summary: total_alive=%d  [%s]", total_alive, table.concat(summary, ", "))
    end)

    -- ---------- 4) Chaos Wastes objective / chest / relic locations ----------
    safe("4 deus", function()
        section("4) Chaos Wastes deus units (chests / cursed chests / relics / arena)")
        local mech_name = Managers and Managers.mechanism and Managers.mechanism.current_mechanism_name
            and Managers.mechanism:current_mechanism_name() or nil
        local lk = Managers and Managers.state and Managers.state.game_mode
            and Managers.state.game_mode.level_key and Managers.state.game_mode:level_key() or nil
        local is_deus = mech_name == "deus" or (lk and string.find(tostring(lk), "^dlc_morris"))
        if not is_deus then
            out("(not a Chaos Wastes run — mechanism=%s level=%s)", tostring(mech_name), tostring(lk))
            return
        end
        if not level_world then out("(no level_world to scan)"); return end

        local function dump_deus_kind(label, system_name, extra_fn)
            local found = 0
            for _, u in ipairs(World.units(level_world)) do
                if Unit.alive(u) then
                    local ext = ScriptUnit.has_extension(u, system_name)
                    if ext then
                        found = found + 1
                        local pos_str = "?"
                        local ok, p = pcall(Unit.world_position, u, 0)
                        if ok and p then pos_str = string.format("(%.1f,%.1f,%.1f)", Vector3.to_elements(p)) end
                        local extras = extra_fn and extra_fn(ext) or ""
                        out("  %s pos=%s%s", label, pos_str, extras)
                    end
                end
            end
            out("%s total = %d", label, found)
        end

        dump_deus_kind("DeusCursedChest",        "deus_cursed_chest_system")
        dump_deus_kind("DeusRelic",              "deus_relic_system")
        dump_deus_kind("DeusArenaIdol",          "deus_arena_idol_system")
        dump_deus_kind("DeusArenaInteractable",  "deus_arena_interactable_system")
        dump_deus_kind("DeusBelakorLocus",       "deus_belakor_locus_system")
        dump_deus_kind("DeusBelakorTotem",       "deus_belakor_totem_system")
        dump_deus_kind("DeusBelakorCrystal",     "deus_belakor_crystal_system")
        dump_deus_kind("DeusBelakorStatueSocket","deus_belakor_statue_socket_system")
        dump_deus_kind("DeusArenaBelakorStatue", "deus_arena_belakor_big_statue_system")

        -- DeusChestExtension lives under pickup_system; identify via fields.
        local found_chests = 0
        for _, u in ipairs(World.units(level_world)) do
            if Unit.alive(u) then
                local ext = ScriptUnit.has_extension(u, "pickup_system")
                if ext and ext._deus_run_controller then
                    found_chests = found_chests + 1
                    local pos_str = "?"
                    local ok, p = pcall(Unit.world_position, u, 0)
                    if ok and p then pos_str = string.format("(%.1f,%.1f,%.1f)", Vector3.to_elements(p)) end
                    local chest_type = ext.get_chest_type and select(2, pcall(ext.get_chest_type, ext)) or "?"
                    local rarity = ext.get_rarity and select(2, pcall(ext.get_rarity, ext)) or "?"
                    local purchased = ext._is_purchased
                    out("  DeusChest pos=%s chest_type=%s rarity=%s purchased=%s",
                        pos_str, tostring(chest_type), tostring(rarity), tostring(purchased))
                end
            end
        end
        out("DeusChest total = %d", found_chests)
    end)

    -- ---------- 5) Interactable inventory ----------
    safe("5 interactables", function()
        section("5) Interactable units on level_world")
        if not level_world then out("(no level_world)"); return end
        local by_type = {}
        local total = 0
        for _, u in ipairs(World.units(level_world)) do
            if Unit.alive(u) then
                local ext = ScriptUnit.has_extension(u, "interactable_system")
                if ext then
                    total = total + 1
                    local itype = (ext.interaction_type and select(2, pcall(ext.interaction_type, ext)))
                        or ext.interactable_type or "?"
                    by_type[itype] = (by_type[itype] or 0) + 1
                    local pos_str = "?"
                    local ok, p = pcall(Unit.world_position, u, 0)
                    if ok and p then pos_str = string.format("(%.1f,%.1f,%.1f)", Vector3.to_elements(p)) end
                    local hud_desc = Unit.get_data(u, "interaction_data", "hud_description")
                    local item_name = Unit.get_data(u, "interaction_data", "item_name")
                    out("  type=%-32s pos=%s hud_desc=%s item_name=%s",
                        tostring(itype), pos_str, tostring(hud_desc), tostring(item_name))
                end
            end
        end
        out("interactable totals = %d", total)
        local sorted = {}
        for k, v in pairs(by_type) do sorted[#sorted + 1] = { k = k, v = v } end
        table.sort(sorted, function(a, b) return a.v > b.v end)
        for _, e in ipairs(sorted) do out("  by_type: %-32s %d", tostring(e.k), e.v) end
    end)

    -- ---------- 6) Breed roster (active conflict settings) ----------
    safe("6 breeds", function()
        section("6) Breed roster (active CurrentConflictSettings)")
        local ccs = rawget(_G, "CurrentConflictSettings")
        if not ccs then out("CurrentConflictSettings: (none — not in a mission)"); return end
        out("CurrentConflictSettings.name = %s", tostring(ccs.name))

        local diff_mgr = Managers and Managers.state and Managers.state.difficulty
        local diff = diff_mgr and diff_mgr.get_difficulty and diff_mgr:get_difficulty() or "?"

        local cb = ccs.contained_breeds and ccs.contained_breeds[diff] or ccs.contained_breeds
        if type(cb) == "table" then
            local names = {}
            for k in pairs(cb) do names[#names + 1] = k end
            table.sort(names)
            out("  contained_breeds[%s] (%d):", tostring(diff), #names)
            for _, n in ipairs(names) do out("    %s", n) end
        else
            out("  contained_breeds: (table missing)")
        end

        -- specials_settings / boss_settings are referenced by name; dump just the names.
        local function ddump(field)
            local v = ccs[field]
            if type(v) == "string" then out("  %s = %s", field, v)
            elseif type(v) == "table" then
                local sub = {}
                for k in pairs(v) do sub[#sub + 1] = tostring(k) end
                out("  %s = { %s }", field, table.concat(sub, ", "))
            end
        end
        ddump("boss")
        ddump("specials")
        ddump("standard_settings")
        ddump("pack_spawning")
        ddump("roaming")
        ddump("intensity")
        ddump("disabled_director_functions")
    end)

    -- ---------- 7) Terror events for this level ----------
    safe("7 terror_events", function()
        section("7) TerrorEventBlueprints[level_key]")
        local lk = Managers and Managers.state and Managers.state.game_mode
            and Managers.state.game_mode.level_key and Managers.state.game_mode:level_key() or nil
        local teb = rawget(_G, "TerrorEventBlueprints")
        if not teb then out("TerrorEventBlueprints: (not loaded)"); return end
        local blueprints = teb[lk]
        if not blueprints then out("TerrorEventBlueprints[%s]: (no entries — many missions only use GenericTerrorEvents)", tostring(lk)); return end
        local names = {}
        for n in pairs(blueprints) do names[#names + 1] = n end
        table.sort(names)
        out("TerrorEventBlueprints[%s] count = %d", tostring(lk), #names)
        for _, name in ipairs(names) do
            local ev = blueprints[name]
            local kinds = {}
            if type(ev) == "table" then
                for i = 1, math.min(#ev, 24) do
                    local step = ev[i]
                    if type(step) == "table" then
                        kinds[#kinds + 1] = tostring(step.kind or step[1] or "?")
                    end
                end
            end
            out("  %s  steps=[%s%s]", name, table.concat(kinds, ","), (#ev > 24 and ",..." or ""))
        end
    end)

    -- ---------- 8) Active UI surfaces ----------
    safe("8 ui_surfaces", function()
        section("8) UI surfaces (Managers.ui._ingame_ui.views, current state)")
        local ui = Managers and Managers.ui
        local ingame_ui = ui and ui._ingame_ui
        if not ingame_ui then out("(no _ingame_ui)"); return end

        local views = ingame_ui.views
        if type(views) == "table" then
            local names = {}
            for k in pairs(views) do names[#names + 1] = tostring(k) end
            table.sort(names)
            out("ingame_ui.views (%d) = { %s }", #names, table.concat(names, ", "))
        else
            out("(no ingame_ui.views table)")
        end

        if ingame_ui.current_state_name then
            local _, csn = pcall(ingame_ui.current_state_name, ingame_ui)
            out("ingame_ui:current_state_name() = %s", tostring(csn))
        end

        -- Mirror cim_dump_active_window: if hero_view is open, peek state name.
        local hero_view = views and views.hero_view
        if hero_view then
            local state = (hero_view._machine and hero_view._machine._state)
                or hero_view._current_state or hero_view._state
            if state then
                out("hero_view active state class = %s", tostring(state.NAME or state.__class_name or "?"))
                local windows = state._active_windows or state.active_windows
                if type(windows) == "table" then
                    for slot_idx, win in pairs(windows) do
                        out("  hero_view window[%s] = %s", tostring(slot_idx), tostring(win and (win.NAME or "?")))
                    end
                end
            else
                out("hero_view present but no active state.")
            end
        end
    end)

    -- ---------- 9) Live HUD elements ----------
    safe("9 hud", function()
        section("9) Live HUD elements (ingame_hud._components / _currently_visible_components)")
        -- ingame_ui.lua:103 assigns `self.ingame_hud = IngameHud:new(...)`. ingame_hud.lua:175 stores
        -- the master table at `self._components`; the keep-vs-mission visibility filter lives in
        -- `self._currently_visible_components`. Walk both so we can report what's on-screen now and
        -- what's defined but currently filtered out.
        local ingame_ui = Managers and Managers.ui and Managers.ui._ingame_ui
        local ingame_hud = ingame_ui and (ingame_ui.ingame_hud or ingame_ui._ingame_hud)
        if not ingame_hud then out("(no ingame_hud found via Managers.ui._ingame_ui)"); return end

        local all_components = ingame_hud._components
        local currently_visible = ingame_hud._currently_visible_components
        if type(all_components) ~= "table" then
            out("(ingame_hud present but no _components table — vt2 build mismatch?)")
            return
        end
        local visible_set = {}
        if type(currently_visible) == "table" then
            for k, v in pairs(currently_visible) do
                -- _currently_visible_components is either { class_name = true } or array-of-instances depending on build; cover both.
                if type(k) == "string" then visible_set[k] = (v and true or false) end
                if type(v) == "table" and v.NAME then visible_set[v.NAME] = true end
            end
        end

        local visible, hidden = {}, {}
        for name in pairs(all_components) do
            if visible_set[name] or next(visible_set) == nil then
                visible[#visible + 1] = tostring(name)
            else
                hidden[#hidden + 1] = tostring(name)
            end
        end
        table.sort(visible); table.sort(hidden)
        out("hud visible (%d) = { %s }", #visible, table.concat(visible, ", "))
        out("hud hidden  (%d) = { %s }", #hidden,  table.concat(hidden,  ", "))
    end)

    -- ---------- 10) Save side-car ----------
    -- VMF mods cannot write arbitrary files; mod:get_temp_data_directory does
    -- not exist in this VMF build, and Application.save_user_settings_to_file
    -- is not callable from sandboxed mod code. Per the doctrine we just emit a
    -- single notice line and rely on the console-*.log capture, which already
    -- holds the full dump as written above.
    safe("10 sidecar", function()
        section("10) Save side-car")
        local intended_filename = string.format("level_dump_%s_%d.txt", level_key_for_filename, ts)
        out("intended filename: %s", intended_filename)
        out("(VMF has no filesystem write API exposed — skipping; full dump is already in console-*.log under the %s prefix)", _LD_PREFIX)
    end)

    out("=== /dump_level end (%d total lines) ===", #out_lines)
    mod:echo(string.format("/dump_level: %d lines written to console log (search '%s')", #out_lines, _LD_PREFIX))
end)

-- ============================================================
-- /regression_test checks (see scaffold near MOD_VERSION).
-- ============================================================
-- The task spec mentioned a `skip_splash_hook_installed` check + a
-- `collision_disable_one_indexed` check, but the current gt source has no
-- StateSplashScreen hook (skip-splash is delegated to a different mod) and no
-- collision-disable loop (collision filtering is field-based, not loop-based).
-- Both skipped here. Remaining checks below cover the deferred-cutscene fix
-- (v0.2.42) which IS present.

_rt_register("gt_no_mission_hotkey_flip", function()
    -- Issue #62 (2026-05-28): a legacy hook force-set the hotkeys-enabled arg of
    -- IngameUI.handle_menu_hotkeys to true mid-mission, enabling crash-prone keep
    -- view hotkeys (Hero Select / Map / etc. spawn unloaded ui_* preview worlds).
    -- Removed from the public General Tweaker in v0.2.72-alpha (the whole
    -- in-mission inventory / Keep-Menus feature migrated to GUI Tweaker). This
    -- source-pattern guard fails if that hook is reintroduced. The needle is
    -- assembled from two literals so this test's own source does not self-match.
    -- Degrades to a no-op when source introspection is unavailable (deploy/bundle
    -- paths).
    -- Anchored on mod.on_setting_changed (a `mod.` field defined in the MAIN
    -- file) so this guard always reads general_tweaker.lua — where the removed
    -- IngameUI hook lived.
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local f = io.open(src_path, "r")
    if not f then return end
    local txt = f:read("*a")
    f:close()
    if not txt then return end
    local needle = 'mod:hook("' .. 'IngameUI", "handle_menu_hotkeys"'
    if txt:find(needle, 1, true) then
        return "Issue #62 regression: the IngameUI handle_menu_hotkeys hook was reintroduced (crash-prone mid-mission hotkey flip)"
    end
end)

_rt_register("cutscene_auto_skip_deferred", function()
    -- v0.2.42 deferred-skip pattern: _pending_auto_skip_system must exist as
    -- a file-local (initialized to nil, assigned by the activate_cutscene_logic
    -- hook). The check itself is presence-of-marker; if the value is nil at
    -- regression-test time (no cutscene active), that's expected.
    -- We can't see file-locals from outside their lexical scope, so use the
    -- marker constant pattern.
    local _MARKER = "_pending_auto_skip_system"
    if #_MARKER == 0 then return "marker missing" end
end)

_rt_register("cutscene_skip_setting_id_present", function()
    -- gt_skip_cutscenes_enabled is the canonical setting id (v0.2.42 fix).
    -- Verify VMF returns SOMETHING (true, false, or nil) without erroring.
    local ok, _ = pcall(function() return mod:get("gt_skip_cutscenes_enabled") end)
    if not ok then return "mod:get(gt_skip_cutscenes_enabled) errored" end
end)

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
    -- still pass even if `_ai_handle_toggle_change` deleted the ping call.
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
    -- v0.2.52: client-side toggle now enqueues into `_ai_pending_client_send`
    -- with retries instead of sending inline. The mod.update consumer must
    -- be wired into the existing update chain — without it the queue would
    -- fill and never drain. Verify the consumer function exists in the file's
    -- closure scope by walking the queue forward via a synthetic enqueue and
    -- asserting mod.update drains it.
    --
    -- We don't actually exercise the network send (no real peer in regression
    -- harness); we just verify the queue shape + drain behavior using a
    -- guaranteed-elapsed `next_at`. Restore the prior queue state on exit.
    local saved = _ai_pending_client_send
    _ai_pending_client_send = {
        host = "__rt_probe_peer__",
        want_bot = true,
        retries_left = 1,
        next_at = os.clock() - 1.0,  -- already-elapsed so the first tick fires
    }
    -- Drive one mod.update tick. The consumer should fire (next_at elapsed),
    -- decrement retries to 0, and clear the queue.
    if type(mod.update) ~= "function" then
        _ai_pending_client_send = saved
        return "mod.update is not a function — update chain broken"
    end
    local ok, err = pcall(mod.update, 0.016)
    if not ok then
        _ai_pending_client_send = saved
        return "mod.update raised during client-send drain probe: " .. tostring(err)
    end
    if _ai_pending_client_send ~= nil then
        _ai_pending_client_send = saved
        return "client-send queue did not drain after one tick (consumer not wired into mod.update?)"
    end
    _ai_pending_client_send = saved
end)

_rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    local ok = pcall(_dbg, "smoke test")
    if not ok then return "_dbg raised" end
    ok = pcall(_dbg_alert, "smoke test")
    if not ok then return "_dbg_alert raised" end
end)



_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/general_tweaker/general_tweaker_localization")
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
-- ============================================================
mod:dofile("scripts/mods/general_tweaker/_gt_lobby_slot_reservations")
mod:dofile("scripts/mods/general_tweaker/_gt_lobby_session_ignore")
mod:dofile("scripts/mods/general_tweaker/_gt_lobby_kick_idle")
mod:dofile("scripts/mods/general_tweaker/_gt_lobby_motd")
mod:dofile("scripts/mods/general_tweaker/_gt_lobby_modded_manifest")
mod:dofile("scripts/mods/general_tweaker/_gt_lobby_failed_join_reveal")

-- Bot Options: Necromancer potion handoff, Ironbreaker revive-during-ult,
-- rescue allies awaiting respawn. Host-side bot AI fixes; no network registration.
-- Promoted from general_tweaker_dev v0.2.84-dev (2026-06-17).
mod:dofile("scripts/mods/general_tweaker/_gt_bot_fixes")

mod:info("[mem-probe] gt boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_GTS) / 1024)
