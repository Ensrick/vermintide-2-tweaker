local mod = get_mod("lobby_tweaker")
local M = {}

-- Failed-Join Manifest Reveal (client side, Phase 2).
-- On `failure_start_join_server_incorrect_hash` (state_loading.lua:1084), pull
-- the host's mod manifest from Steam lobby_data and replace the vanilla popup
-- with one listing the missing mods + an Open-Workshop button. Hook target:
-- `StateLoading.create_popup` keyed on the error string (cleaner than
-- rewriting 115-line `_verify_joined_lobby`). Re-fetches lobby_id via
-- `Managers.lobby:get_lobby("matchmaking_session_lobby")` (live in same call
-- frame). Any failure -> fall back to vanilla popup; never degrade UX for
-- non-lobby_tweaker hosts.

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
            _lz("failnotify_required_header", "You are missing %d mods required by the host:"), nR)
        for _, e in ipairs(diff.missing_required) do
            local v = (e.version ~= "" and (" (v" .. e.version .. ")")) or ""
            lines[#lines + 1] = "  - " .. e.display_name .. v
        end
    end
    if nV > 0 then
        if #lines > 0 then lines[#lines + 1] = "" end
        lines[#lines + 1] = string.format(
            _lz("failnotify_version_header", "%d mods have a version mismatch:"), nV)
        for _, e in ipairs(diff.version_mismatch) do
            lines[#lines + 1] = string.format("  - %s (host v%s, you v%s)",
                e.display_name, e.host_version, e.local_version)
        end
    end
    if nC > 0 then
        if #lines > 0 then lines[#lines + 1] = "" end
        lines[#lines + 1] = string.format(
            _lz("failnotify_cosmetic_footer", "Host also has %d cosmetic mods you don't (gameplay unaffected)."), nC)
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

-- Queue our enriched popup. Stash diff for the result-poller. We set
-- state_loading_self._popup_id so the state machine's bookkeeping stays
-- consistent with vanilla (which asserts no double-popups).
local _pending_popups = {}  -- popup_id -> { diff = ... }

_queue_enriched_popup = function(state_loading_self, body_text, diff)
    if not (Managers.popup and Managers.popup.queue_popup) then return false end
    local title = _lz("failnotify_title", "Cannot join — modded host")
    local btn_workshop = _lz("failnotify_button_workshop", "Open Workshop")
    local btn_cancel = _lz("failnotify_button_cancel", "Close")
    -- Right button uses vanilla "restart_as_server" action so the loading
    -- state's standard dismissal path runs on close.
    local popup_id = Managers.popup:queue_popup(
        body_text, title,
        "lt_open_workshop", btn_workshop,
        "restart_as_server", btn_cancel
    )
    if not popup_id then return false end
    _pending_popups[popup_id] = { diff = diff }
    state_loading_self._popup_id = popup_id
    return true
end

-- Result poller. StateLoading polls vanilla actions itself; "lt_open_workshop"
-- isn't a known action string so we drive it. After the URL fires we cancel
-- the popup so the state machine moves on as if the user closed it.
local _prev_update = mod.update
mod.update = function(dt)
    if _prev_update then _prev_update(dt) end
    if not next(_pending_popups) then return end
    local popup_mgr = Managers.popup
    if not popup_mgr or not popup_mgr.query_result then return end
    for popup_id, entry in pairs(_pending_popups) do
        local result = popup_mgr:query_result(popup_id)
        if result then
            _pending_popups[popup_id] = nil
            if result == "lt_open_workshop" then
                _open_workshop_url(entry.diff)
                if popup_mgr.cancel_popup then
                    pcall(popup_mgr.cancel_popup, popup_mgr, popup_id)
                end
            end
            -- "restart_as_server" path: vanilla StateLoading handles it.
        end
    end
end

-- The intercept. Original: scripts/game_state/state_loading.lua:2447
mod:hook("StateLoading", "create_popup", function(func, self, error_key, header, action, right_button, ...)
    -- Fallback helper: tail-call vanilla with all original args.
    local args = { header, action, right_button, ... }
    local function vanilla() return func(self, error_key, unpack(args)) end

    if not mod:get("manifest_failnotify_enabled") then return vanilla() end
    if error_key ~= TARGET_ERROR then return vanilla() end
    local lobby_id = _safe_get_lobby_id()
    if not lobby_id then return vanilla() end
    local text, err = _fetch_manifest_for_lobby(lobby_id)
    if not text then
        mod:info("[failnotify] no manifest (%s) — fallback to vanilla", tostring(err))
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
    assert(self._popup_id == nil, "[lobby_tweaker] enriched popup intercept while popup already up")
    if not _queue_enriched_popup(self, body, diff) then return vanilla() end
    -- Suppress vanilla popup; we've taken over.
end)

-- Diagnostic chat command. Usage: /lt_manifest_probe <lobby_id>
mod:command("lt_manifest_probe", "Fetch+dump a remote lobby's modded manifest (no join)",
function(lobby_id_arg)
    if not lobby_id_arg or lobby_id_arg == "" then
        mod:echo("[lt_manifest_probe] usage: /lt_manifest_probe <lobby_id>")
        return
    end
    local text, err = _fetch_manifest_for_lobby(lobby_id_arg)
    if not text then
        mod:echo(string.format("[lt_manifest_probe] no manifest for %s (%s)",
            tostring(lobby_id_arg), tostring(err)))
        return
    end
    local entries = _parse_manifest(text)
    mod:echo(string.format("[lt_manifest_probe] %d entries from lobby %s:",
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

return M
