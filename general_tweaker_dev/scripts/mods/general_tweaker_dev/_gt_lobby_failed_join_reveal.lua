local mod = get_mod("gt_dev")
local M = {}

-- ============================================================================
-- Failed-Join Manifest Reveal (client side, migrated from lobby_tweaker
-- 2026-05-25; lt v0.1.7-dev "Phase 2 consumer").
-- ============================================================================
-- On `failure_start_join_server_incorrect_hash` (state_loading.lua:1084),
-- pull the host's mod manifest from Steam lobby_data and replace the vanilla
-- popup with one listing the missing mods + an Open-Workshop button. Hook
-- target: `StateLoading.create_popup` keyed on the error string (cleaner than
-- rewriting 115-line `_verify_joined_lobby`). Re-fetches lobby_id via
-- `Managers.lobby:get_lobby("matchmaking_session_lobby")` (live in same call
-- frame). Any failure -> fall back to vanilla popup; never degrade UX for
-- non-broadcasting hosts.
--
-- Lobby-data key prefix `ltw_` retained (NOT renamed to `gtw_`) for cross-
-- mod compat -- see _gt_lobby_modded_manifest.lua for rationale.

-- Forward declarations (Lua 5.1)
local _fetch_manifest_for_lobby
local _parse_manifest
local _build_local_index
local _diff_mods
local _build_popup_text
local _queue_enriched_popup
local _open_workshop_url

local TARGET_ERROR = "failure_start_join_server_incorrect_hash"
local PROTOCOL_VERSION = "1"
local FALLBACK_WORKSHOP_URL = "https://steamcommunity.com/app/552500/workshop/"
local MAX_CHUNKS = 64

-- Debug alert helper -- defers to gt's shared `_gt_dbg_alert` (general_tweaker_dev.lua:47).
-- Routes through mod:warning (VMF output_mode_warning gate). Used by the
-- create_popup soft guard (audit 2026-06-07, F17).
local function _dbg_alert(fmt, ...)
    if type(mod._gt_dbg_alert) == "function" then
        mod._gt_dbg_alert(fmt, ...)
    end
end

-- Helpers
local function _lz(key, fallback)
    -- mod:localize returns "<key>" if unregistered; fall back so missing
    -- localization doesn't print bracket noise to the popup.
    local s = mod and mod.localize and mod:localize(key)
    if not s or s == "" or s:sub(1, 1) == "<" then return fallback end
    return s
end

local function _safe_get_lobby_id()
    local lobby_mgr = Managers and Managers.lobby
    if not lobby_mgr or not lobby_mgr.get_lobby then return nil end
    local ok, lobby = pcall(function() return lobby_mgr:get_lobby("matchmaking_session_lobby") end)
    if not ok or not lobby then return nil end
    if lobby.get_stored_lobby_data then
        local ok2, d = pcall(function() return lobby:get_stored_lobby_data() end)
        if ok2 and d and d.id then return d.id end
    end
    if lobby.id then
        local ok3, id = pcall(function() return lobby:id() end)
        if ok3 then return id end
    end
    return nil
end

local function _lobby_data_get(lobby_id, key)
    if not (lobby_id and key and LobbyInternal and LobbyInternal.get_lobby_data_from_id_by_key) then return nil end
    local ok, val = pcall(LobbyInternal.get_lobby_data_from_id_by_key, lobby_id, key)
    if not ok then return nil end
    return val
end

-- Manifest fetch
_fetch_manifest_for_lobby = function(lobby_id)
    if not lobby_id then return nil, "no_lobby_id" end
    -- Nudge Steam to repopulate the data cache (idempotent).
    if LobbyInternal and LobbyInternal.get_lobby_data_from_id then
        pcall(LobbyInternal.get_lobby_data_from_id, lobby_id)
    end
    local proto = _lobby_data_get(lobby_id, "ltw_p")
    if proto ~= PROTOCOL_VERSION then return nil, "no_manifest" end
    local n = tonumber(_lobby_data_get(lobby_id, "ltw_n"))
    if not n or n < 1 then return nil, "no_chunks" end
    if n > MAX_CHUNKS then n = MAX_CHUNKS end
    local pieces = {}
    for i = 0, n - 1 do
        local chunk = _lobby_data_get(lobby_id, "ltw_m" .. tostring(i))
        if not chunk then return nil, "missing_chunk_" .. tostring(i) end
        pieces[#pieces + 1] = chunk
    end
    return table.concat(pieces), nil
end

-- Parse: TAB-separated lines per protocol. Unknown trailing fields ignored.
_parse_manifest = function(text)
    local out = {}
    if not text or text == "" then return out end
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then
            local fields = {}
            for f in (line .. "\t"):gmatch("([^\t]*)\t") do
                fields[#fields + 1] = f
            end
            if #fields >= 5 then
                local id, version, mode, wsid, name = fields[1], fields[2], fields[3], fields[4], fields[5]
                if id ~= "" and (mode == "R" or mode == "C" or mode == "H") then
                    out[#out + 1] = {
                        id = id,
                        version = version or "",
                        mode = mode,
                        workshop_id = wsid or "0",
                        display_name = (name and name ~= "") and name or id,
                    }
                end
            end
        end
    end
    return out
end

-- Local mod index: id -> { enabled, version, name }
_build_local_index = function()
    local idx = {}
    if not (Managers and Managers.mod and Managers.mod._mods) then return idx end
    for _, m in ipairs(Managers.mod._mods) do
        if type(m) == "table" and m.id then
            local id_str = tostring(m.id)
            local version = ""
            if _G.get_mod then
                local ok, mt = pcall(_G.get_mod, id_str)
                if ok and type(mt) == "table" and mt.MOD_VERSION then
                    version = tostring(mt.MOD_VERSION)
                end
            end
            idx[id_str] = {
                enabled = m.enabled and true or false,
                version = version,
                name = tostring(m.name or id_str),
            }
        end
    end
    return idx
end

-- Diff
_diff_mods = function(host_entries, local_idx)
    local missing_required, missing_cosmetic, version_mismatch = {}, {}, {}
    local host_only_count = 0
    for _, e in ipairs(host_entries) do
        if e.mode == "H" then
            host_only_count = host_only_count + 1
        else
            local local_e = local_idx[e.id]
            local active = local_e and local_e.enabled
            if not active then
                if e.mode == "R" then
                    missing_required[#missing_required + 1] = e
                elseif e.mode == "C" then
                    missing_cosmetic[#missing_cosmetic + 1] = e
                end
            elseif e.version ~= "" and local_e.version ~= "" and e.version ~= local_e.version then
                version_mismatch[#version_mismatch + 1] = {
                    id = e.id,
                    display_name = e.display_name,
                    host_version = e.version,
                    local_version = local_e.version,
                    workshop_id = e.workshop_id,
                    mode = e.mode,
                }
            end
        end
    end
    return {
        missing_required = missing_required,
        missing_cosmetic = missing_cosmetic,
        version_mismatch = version_mismatch,
        host_only_count = host_only_count,
    }
end

-- Popup body text
_build_popup_text = function(diff)
    local lines = {}
    local nR, nC, nV = #diff.missing_required, #diff.missing_cosmetic, #diff.version_mismatch
    if nR > 0 then
        lines[#lines + 1] = string.format(
            _lz("gt_lobby_failnotify_required_header", "You are missing %d mods required by the host:"), nR)
        for _, e in ipairs(diff.missing_required) do
            local v = (e.version ~= "" and (" (v" .. e.version .. ")")) or ""
            lines[#lines + 1] = "  - " .. e.display_name .. v
        end
    end
    if nV > 0 then
        if #lines > 0 then lines[#lines + 1] = "" end
        lines[#lines + 1] = string.format(
            _lz("gt_lobby_failnotify_version_header", "%d mods have a version mismatch:"), nV)
        for _, e in ipairs(diff.version_mismatch) do
            lines[#lines + 1] = string.format("  - %s (host v%s, you v%s)",
                e.display_name, e.host_version, e.local_version)
        end
    end
    if nC > 0 then
        if #lines > 0 then lines[#lines + 1] = "" end
        lines[#lines + 1] = string.format(
            _lz("gt_lobby_failnotify_cosmetic_footer", "Host also has %d cosmetic mods you don't (gameplay unaffected)."), nC)
    end
    if #lines == 0 then return nil end
    return table.concat(lines, "\n")
end

-- URL open. `Steam.open_url` is the working API (ingame_player_list_ui_v2:1803);
-- `Application.open_url_in_browser` is NOP'd at foundation/.../patches.lua:61.
_open_workshop_url = function(diff)
    local target_wsid
    for _, e in ipairs(diff.missing_required) do
        if e.workshop_id and e.workshop_id ~= "" and e.workshop_id ~= "0" then
            target_wsid = e.workshop_id; break
        end
    end
    if not target_wsid then
        for _, e in ipairs(diff.version_mismatch) do
            if e.workshop_id and e.workshop_id ~= "" and e.workshop_id ~= "0" then
                target_wsid = e.workshop_id; break
            end
        end
    end
    local url = target_wsid and ("steam://url/CommunityFilePage/" .. target_wsid) or FALLBACK_WORKSHOP_URL
    if _G.Steam and _G.Steam.open_url then
        pcall(_G.Steam.open_url, url)
    elseif _G.Application and _G.Application.open_url_in_browser then
        pcall(_G.Application.open_url_in_browser, url)
    end
end

-- Queue our enriched popup. Stash diff + the StateLoading instance for the
-- result-poller.
--
-- audit 2026-06-07 (F4, v0.2.80-dev): we deliberately DO NOT assign
-- state_loading_self._popup_id here. Vanilla StateLoading._try_next_state
-- (state_loading.lua:1308-1310) polls self._popup_id via _handle_popup, which
-- consume-once-reads Managers.popup:query_result. If both vanilla AND our
-- _update_consumer poller hold the same popup id, whichever reads first gets
-- the result and the other sees nil -- if the mod wins the read, vanilla's
-- _handle_popup never runs its restart_as_server teardown and the loading
-- screen hangs. So the enriched popup lives ONLY in _pending_popups and our
-- poller is the SOLE owner of both result actions (it drives the teardown
-- itself for restart_as_server -- see _update_consumer).
local _pending_popups = {}  -- popup_id -> { diff = ..., sl = state_loading_self }

_queue_enriched_popup = function(state_loading_self, body_text, diff)
    if not (Managers.popup and Managers.popup.queue_popup) then return false end
    local title = _lz("gt_lobby_failnotify_title", "Cannot join -- modded host")
    local btn_workshop = _lz("gt_lobby_failnotify_button_workshop", "Open Workshop")
    local btn_cancel = _lz("gt_lobby_failnotify_button_cancel", "Close")
    -- Right button uses vanilla "restart_as_server" action string, but OUR
    -- poller (not vanilla _handle_popup) consumes it and drives the teardown.
    -- The left action key `gt_lobby_open_workshop` is custom -- our poller
    -- below drives it too.
    local popup_id = Managers.popup:queue_popup(
        body_text, title,
        "gt_lobby_open_workshop", btn_workshop,
        "restart_as_server", btn_cancel
    )
    if not popup_id then return false end
    _pending_popups[popup_id] = { diff = diff, sl = state_loading_self }
    return true
end

-- Drive vanilla StateLoading's restart_as_server teardown by hand. Mirrors
-- StateLoading._handle_popup's "restart_as_server" branch (vanilla
-- state_loading.lua:1570-1577) exactly: tear down the network, grant
-- permission to advance, and force-complete the first-time view if present.
-- audit 2026-06-07 (F4): because we no longer hand the popup id to vanilla,
-- vanilla never runs this branch for our popup -- so we replicate it here.
local function _drive_restart_as_server_teardown(sl)
    if not sl then return end
    sl._teardown_network = true
    sl._permission_to_go_to_next_state = true
    if sl._first_time_view and sl._first_time_view.force_done then
        pcall(function() sl._first_time_view:force_done() end)
    end
end

-- v0.2.81 (Issue #72, F17): the popup-already-up soft-guard decision, exported so
-- /gt_regression_test can pin its truth table (a revert toward vanilla-style hard
-- assert semantics would raise inside the test instead of soft-deferring).
function M._should_defer_for_existing_popup(state_loading_self)
    return state_loading_self ~= nil and state_loading_self._popup_id ~= nil
end

-- Result poller via gt's central update registry. We are the SOLE poller of
-- the enriched popup id (vanilla never sees it -- see _queue_enriched_popup),
-- so this callback owns BOTH actions:
--   * gt_lobby_open_workshop -> open the URL + cancel the popup
--   * restart_as_server      -> drive the vanilla teardown ourselves
-- audit 2026-06-07 (F4): previously vanilla StateLoading was expected to
-- handle restart_as_server, but it polled the same consume-once popup id we
-- did -> double-consume race -> loading-screen hang. Now there is exactly one
-- poller.
-- v0.2.81 (Issue #72): result consumption factored out of the registry callback
-- and parameterized on popup_mgr so /gt_regression_test can drive it with a stub
-- (the callback shell below still reads the live Managers.popup).
local function _consume_results(popup_mgr)
    for popup_id, entry in pairs(_pending_popups) do
        local result = popup_mgr:query_result(popup_id)
        if result then
            _pending_popups[popup_id] = nil
            if result == "gt_lobby_open_workshop" then
                _open_workshop_url(entry.diff)
                if popup_mgr.cancel_popup then
                    pcall(popup_mgr.cancel_popup, popup_mgr, popup_id)
                end
                -- After opening the workshop URL the user still needs to leave
                -- the failed-join loading screen, so drive teardown too.
                _drive_restart_as_server_teardown(entry.sl)
            elseif result == "restart_as_server" then
                _drive_restart_as_server_teardown(entry.sl)
            else
                -- v0.2.81 (Issue #72): unknown result — unreachable today (only the
                -- two button actions above exist), but vanilla logs the analogous
                -- case (state_loading.lua:1588) and silently dropping the entry
                -- would strand the user on the loading screen. Log UNGATED and
                -- still drive teardown.
                mod:warning("[gt:lobby:failnotify] unknown popup result %s -- driving teardown anyway",
                    tostring(result))
                _drive_restart_as_server_teardown(entry.sl)
            end
        end
    end
end

local function _update_consumer(_dt)
    if not next(_pending_popups) then return end
    local popup_mgr = Managers.popup
    if not popup_mgr or not popup_mgr.query_result then return end
    _consume_results(popup_mgr)
end

-- v0.2.234-dev (Issue #72, F4-half): one explicit takeover boundary owns the
-- enriched popup without ever handing its consume-once id to StateLoading.
-- Keeping the live hook on this injectable helper lets /gt_regression_test
-- execute the shipped decision against a write-trapping synthetic state. The
-- complementary tier-a absence invariant rejects any direct _popup_id write in
-- this module, including one added outside this helper later.
local function _take_over_enriched_popup(state_loading_self, body, diff, queue_fn)
    return queue_fn(state_loading_self, body, diff) == true
end

if type(mod._gt_register_update) == "function" then
    mod._gt_register_update("gt_lobby_failed_join_reveal_poller", _update_consumer)
end

-- The intercept. Original: scripts/game_state/state_loading.lua:2447
mod:hook("StateLoading", "create_popup", function(func, self, error_key, header, action, right_button, ...)
    -- Fallback helper: tail-call vanilla with all original args.
    -- audit 2026-06-07 (unpack-safety, VMF_RECIPES § 2a): header/action/
    -- right_button are frequently nil while trailing varargs (the string.format
    -- args vanilla applies to the localized error at state_loading.lua:2467) are
    -- present. A bare unpack(args) does a #args boundary search over an array
    -- with leading nils and truncates non-deterministically, dropping the format
    -- args. Capture the real arity explicitly: 3 fixed leading slots + the
    -- variadic count, and pass an explicit upper bound to unpack.
    local n = 3 + select("#", ...)
    local args = { header, action, right_button, ... }
    local function vanilla() return func(self, error_key, unpack(args, 1, n)) end

    -- v0.2.81 (Issue #72): vanilla create_popup is a no-op while leaving the game
    -- (state_loading.lua:2448-2450). Never enrich in that window either — a popup
    -- queued against a dying state object lingers with teardown writes going to a
    -- dead object. vanilla() preserves the exact no-op (it early-returns inside).
    if Managers.account and Managers.account.leaving_game and Managers.account:leaving_game() then
        return vanilla()
    end

    if not mod:get("gt_lobby_manifest_failnotify_enabled") then return vanilla() end
    if error_key ~= TARGET_ERROR then return vanilla() end
    local lobby_id = _safe_get_lobby_id()
    if not lobby_id then return vanilla() end
    local text, err = _fetch_manifest_for_lobby(lobby_id)
    if not text then
        mod:info("[gt:lobby:failnotify] no manifest (%s) -- fallback to vanilla", tostring(err))
        return vanilla()
    end
    local host_entries = _parse_manifest(text)
    if #host_entries == 0 then return vanilla() end
    local diff = _diff_mods(host_entries, _build_local_index())
    local body = _build_popup_text(diff)
    if not body then
        -- No actionable mod diff (mismatch is from something other than the
        -- mod set, e.g. raw NetworkLookup desync). Vanilla popup is right.
        return vanilla()
    end
    -- Mirror vanilla's pre-popup _join_popup_id cleanup; vanilla's
    -- _destroy_lobby_client ran already in _verify_joined_lobby:1083.
    if self._join_popup_id and Managers.popup and Managers.popup.cancel_popup then
        pcall(Managers.popup.cancel_popup, Managers.popup, self._join_popup_id)
        self._join_popup_id = nil
    end
    -- audit 2026-06-07 (F17, v0.2.80-dev): a hard assert here would crash the
    -- game if a popup were somehow already up at intercept time (vanilla's own
    -- create_popup asserts the same at state_loading.lua:2469, but we should
    -- never be the one to hard crash from a hook). Soft-guard instead and fall
    -- through to vanilla, which owns the crash semantics for this state.
    if M._should_defer_for_existing_popup(self) then
        -- v0.2.81 (Issue #72): ungated (was _dbg_alert) — an unexpected-state
        -- deferral the user should see without Debug Logging enabled.
        mod:warning("[gt:lobby] enriched popup intercept while popup already up -- skipping enrichment, deferring to vanilla")
        return vanilla()
    end
    if not _take_over_enriched_popup(self, body, diff, _queue_enriched_popup) then
        return vanilla()
    end
    -- Suppress vanilla popup; we've taken over.
end)

-- ============================================================================
-- Join watchdog (client side, Issue #378, v0.2.213-dev).
-- ============================================================================
-- The failed-join reveal above only fires when the join actually RESOLVES to
-- `failure_start_join_server_incorrect_hash`. A mod mismatch frequently does
-- NOT resolve there: the network_hash covers only the compiled network config,
-- engine/content revision, the DLC set and the level-key count (`num_levels`),
-- NOT the VMF mod set (`scripts/network/lobby_aux.lua:16-48`). So a host mod
-- that changes breeds / items / buffs / adds a VMF RPC WITHOUT adding a
-- level_key or a DLCSetting leaves the hash equal, the client sails past the
-- hash gate (`state_loading.lua:1068`), and then stalls with NO timeout:
--   * pre-hash: `_verify_joined_lobby`'s `ready_to_compare_data` gate
--     (`state_loading.lua:1004`) never turns true if the host's Steam
--     lobby_data (network_hash / matchmaking_type / difficulty) or `host`
--     (`lobby:lobby_host()`) never populate client-side -> loops forever, no
--     popup, `_lobby_verified` never set.
--   * post-hash: the NetworkClient state machine has a timeout ONLY on
--     `connecting` (`network_client.lua:372-382`, CONNECTION_TIMEOUT=15);
--     `loading` / `loaded` / `waiting_enter_game` wait on host RPCs
--     (`rpc_loading_synced`, `rpc_game_started`) with no bound.
-- Result: indefinite loading screen, alt-F4 the only exit.
--
-- This watchdog times the pre-game-start join phase as a non-host client; on
-- timeout it force-surfaces the manifest diff (or, for a non-broadcasting /
-- vanilla host, a plain "join stalled" notice) and reroutes StateLoading back
-- to the main menu so alt-F4 is never needed. Everything is LOCAL: it only
-- READS Steam lobby_data and queues a LOCAL popup -- NO new networked sends.
-- Inert unless we are the joining client (host path early-outs on
-- `lobby.is_host`).

local _wd_armed_sl   = nil    -- StateLoading instance currently being timed
local _wd_elapsed    = 0      -- seconds accumulated in the pre-game-start phase
local _wd_fired_for  = nil    -- StateLoading instance already surfaced (no re-fire)
local _wd_last_err   = nil    -- de-dupe the per-frame tick-error printf
local _queue_stall_popup      -- forward decl (Lua 5.1)
local WD_TIMEOUT_FLOOR = 15    -- never trip faster than this, whatever the setting says

-- True (returns the session lobby) when we are a NON-host client whose session
-- lobby exists and whose join has not yet reached game-start. Level loading (the
-- legitimately slow part) happens AFTER `game_started` in StateLoading
-- (`state_loading.lua:1396-1452`), so gating on pre-game-start means a slow disk
-- can't false-trip the watchdog.
local function _wd_is_stalled_joining_client(sl)
    local lm = Managers and Managers.lobby
    if not (lm and lm.query_lobby) then return nil end
    local lobby = lm:query_lobby("matchmaking_session_lobby")
    if not lobby or lobby.is_host then return nil end
    local nc = sl and sl._network_client
    local states = rawget(_G, "NetworkClientStates")
    if nc and states and (nc.state == states.game_started or nc.state == states.is_ingame) then
        return nil
    end
    return lobby
end

local function _wd_timeout_seconds()
    local v = tonumber(mod:get("gt_lobby_join_watchdog_timeout_seconds")) or 60
    if v < WD_TIMEOUT_FLOOR then v = WD_TIMEOUT_FLOOR end
    return v
end

-- Reroute the loading state to the main menu. Mirrors the vanilla failure path:
-- `_verify_joined_lobby` calls `_destroy_lobby_client` right before the
-- incorrect_hash popup (`state_loading.lua:1083`), and `_destroy_lobby_client`
-- BOTH destroys the session lobby AND sets `self._wanted_state = StateTitleScreen`
-- (`state_loading.lua:1128-1145`). Without this, a pure hang leaves
-- `_wanted_state` at StateIngame (set in `_setup_init_network_view`,
-- `state_loading.lua:246`), so the popup teardown (`_teardown_network` +
-- `_permission_to_go_to_next_state`) would transition the user INTO a broken
-- session (`state_loading.lua:1497` `_new_state = _wanted_state`) instead of the
-- menu. `_teardown_network` is then set by the shared poller when the popup is
-- dismissed, exactly as the failed-join reveal already does.
local function _wd_reroute_to_menu(sl)
    if sl and type(sl._destroy_lobby_client) == "function" then
        pcall(function() sl:_destroy_lobby_client() end)
    end
end

-- The no-manifest branch: a vanilla / non-broadcasting host, or a diff with
-- nothing actionable. State plainly that the join stalled and offer the abort;
-- never claim to know the cause. Reuses `_pending_popups` + the shared poller so
-- the single "Leave" button drives the same restart_as_server teardown as the
-- reveal popup.
_queue_stall_popup = function(state_loading_self)
    if not (Managers.popup and Managers.popup.queue_popup) then return false end
    local title = _lz("gt_lobby_watchdog_stall_title", "Join timed out")
    local body  = _lz("gt_lobby_watchdog_stall_body",
        "The join to this lobby did not finish. The host may require mods you do not have, or may not be sharing its mod list. Leave to return to the main menu.")
    local btn   = _lz("gt_lobby_failnotify_button_cancel", "Close")
    local popup_id = Managers.popup:queue_popup(body, title, "restart_as_server", btn)
    if not popup_id then return false end
    _pending_popups[popup_id] = { diff = nil, sl = state_loading_self }
    return true
end

local function _wd_fire(sl)
    _wd_fired_for = sl
    -- Never stack on a popup already up (vanilla error, or our own reveal that
    -- DID resolve): if one exists, this isn't the silent-hang case we cover.
    if Managers.popup and Managers.popup.has_popup and Managers.popup:has_popup() then return end
    if next(_pending_popups) ~= nil then return end

    -- Read the host manifest while the session lobby wrapper is still alive
    -- (before the reroute destroys it).
    local diff, body
    local lobby_id = _safe_get_lobby_id()
    if lobby_id then
        local text = _fetch_manifest_for_lobby(lobby_id)
        if text then
            local host_entries = _parse_manifest(text)
            if #host_entries > 0 then
                diff = _diff_mods(host_entries, _build_local_index())
                body = _build_popup_text(diff)
            end
        end
    end

    _wd_reroute_to_menu(sl)

    if body and diff then
        local intro = _lz("gt_lobby_watchdog_intro",
            "The join to this host timed out. You appear to be missing mods it requires:")
        if not _queue_enriched_popup(sl, intro .. "\n\n" .. body, diff) then
            _queue_stall_popup(sl)
        end
    else
        _queue_stall_popup(sl)
    end
    printf("[gt:378] join watchdog surfaced popup after %.0fs (manifest=%s)",
        _wd_elapsed, tostring(body ~= nil))
end

local function _wd_tick(sl, dt)
    if not mod:get("gt_lobby_join_watchdog_enabled") then
        _wd_armed_sl, _wd_elapsed = nil, 0
        return
    end
    local lobby = _wd_is_stalled_joining_client(sl)
    if not lobby then
        -- host, no session lobby, or already past game-start: disarm
        _wd_armed_sl, _wd_elapsed = nil, 0
        return
    end
    if _wd_fired_for == sl then return end   -- already surfaced for this join
    if _wd_armed_sl ~= sl then                -- fresh StateLoading instance: (re)arm
        _wd_armed_sl, _wd_elapsed = sl, 0
    end
    _wd_elapsed = _wd_elapsed + (dt or 0)
    if _wd_elapsed >= _wd_timeout_seconds() then
        _wd_fire(sl)
    end
end

-- Capture the live StateLoading instance + dt each frame it updates (self-gating:
-- fires ONLY during a loading screen). hook_safe = observation; we mutate only
-- our own timer + (on fire) the state's documented teardown fields. Grep-verified
-- singleton: the only other StateLoading hook in gt is create_popup above.
mod:hook_safe("StateLoading", "update", function(self, dt, t)
    local ok, err = pcall(_wd_tick, self, dt)
    if not ok then
        local msg = tostring(err)
        if _wd_last_err ~= msg then
            _wd_last_err = msg
            printf("[gt:378] join watchdog tick error (repeats suppressed): %s", msg)
        end
    end
end)

-- Diagnostic chat command. Usage: /lobby_manifest_probe <lobby_id>
mod:command("lobby_manifest_probe", "Fetch+dump a remote lobby's modded manifest (no join)",
function(lobby_id_arg)
    if not lobby_id_arg or lobby_id_arg == "" then
        mod:echo("[gt_lobby_manifest_probe] usage: /lobby_manifest_probe <lobby_id>")
        return
    end
    local text, err = _fetch_manifest_for_lobby(lobby_id_arg)
    if not text then
        mod:echo(string.format("[gt_lobby_manifest_probe] no manifest for %s (%s)",
            tostring(lobby_id_arg), tostring(err)))
        return
    end
    local entries = _parse_manifest(text)
    mod:echo(string.format("[gt_lobby_manifest_probe] %d entries from lobby %s:",
        #entries, tostring(lobby_id_arg)))
    for _, e in ipairs(entries) do
        mod:echo(string.format("  [%s] %s v%s (ws=%s) %s",
            e.mode, e.id, e.version, e.workshop_id, e.display_name))
    end
    local diff = _diff_mods(entries, _build_local_index())
    mod:echo(string.format("  -> %d required missing, %d cosmetic missing, %d version-mismatch, %d host-only",
        #diff.missing_required, #diff.missing_cosmetic, #diff.version_mismatch, diff.host_only_count))
end)

-- Exports for tests / sibling modules.
M.fetch_manifest_for_lobby = _fetch_manifest_for_lobby
M.parse_manifest = _parse_manifest
M.build_local_index = _build_local_index
M.diff_mods = _diff_mods
M.build_popup_text = _build_popup_text

-- Engine helpers reused by the in-lobby appearance-parity banner
-- (_gt_lobby_appearance_parity.lua) so there is ONE manifest fetch and ONE local
-- mod index shared between the failed-join reveal and the successful-join banner.
mod._gt_lobby_fetch_manifest    = _fetch_manifest_for_lobby
mod._gt_lobby_safe_lobby_id     = _safe_get_lobby_id
mod._gt_lobby_build_local_index = _build_local_index

-- audit 2026-06-07 (F4): exposed on `mod` so /gt_regression_test can assert the
-- restart_as_server teardown driver sets the exact vanilla fields without
-- reloading this module (which would re-attempt the create_popup hook).
mod._gt_failnotify_drive_teardown = _drive_restart_as_server_teardown

-- v0.2.81 (Issue #72): test exports — the result consumer (parameterized on
-- popup_mgr) and the live pending-popups table (shared identity, so a test can
-- inject a synthetic entry, drive _consume_results with a stub manager, and
-- assert the entry is consumed + teardown driven).
mod._gt_failnotify_consume_results = _consume_results
mod._gt_failnotify_pending_popups = _pending_popups
mod._gt_failnotify_should_defer = M._should_defer_for_existing_popup
mod._gt_failnotify_take_over = _take_over_enriched_popup

-- Issue #378 join-watchdog exports (see /gt_regression_test). `_wd_reroute_to_menu`
-- is the load-bearing invariant this fix adds over the reveal: a hung join must be
-- rerouted to the menu (delegates to vanilla `_destroy_lobby_client`), else the
-- teardown would dump the user into a broken StateIngame.
mod._gt_join_watchdog_tick    = _wd_tick
mod._gt_join_watchdog_reroute = _wd_reroute_to_menu
mod._gt_join_watchdog_timeout = _wd_timeout_seconds

return M
