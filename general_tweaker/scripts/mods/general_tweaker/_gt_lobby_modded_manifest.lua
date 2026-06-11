local mod = get_mod("gt")
local M = {}

-- ============================================================================
-- Modded Manifest Broadcast (host-side, migrated from lobby_tweaker
-- 2026-05-25; lt v0.1.7-dev "Phase 2 producer").
-- ============================================================================
-- Enumerates loaded mods via Managers.mod._mods (mod_manager.lua:326-336),
-- serializes one line per mod ("<id>\t<ver>\t<mode>\t<workshop_id>\t<display_name>"),
-- chunks into <=CHUNK_SIZE pieces, and publishes via LobbyHost:set_lobby_data
-- (lobby_host.lua:139) under keys ltw_p / ltw_n / ltw_m0..N-1. Throttled to
-- <=1 republish per 500 ms; heals every 60 s; re-fires on VMF setting change.
-- Host-only, hash-neutral.
--
-- Lobby-data key prefix `ltw_` retained (NOT renamed to `gtw_`) so peers on
-- the legacy lobby_tweaker mod can still read manifests we publish, and so
-- our `_gt_lobby_failed_join_reveal` reader can still read manifests they
-- publish. This is intentional cross-mod compat -- bumping the key prefix
-- would split the install base in two.

-- Constants ------------------------------------------------------------------
local PROTOCOL_VERSION = "1"
local CHUNK_SIZE       = 200
local MAX_CHUNKS       = 40
local THROTTLE_MS      = 500
local POLL_INTERVAL_S  = 1.0
local HEAL_INTERVAL_S  = 60.0
local FIELD_VER_MAX    = 16
local FIELD_NAME_MAX   = 64
local FIELD_ID_MAX     = 32
local TAG              = "[gt:lobby]"

-- Forward declarations (Lua 5.1) ---------------------------------------------
local KNOWN_MODS
local _is_host, _get_lobby_host, _now_ms, _trim_field
local _resolve_mode, _resolve_version, _resolve_workshop_id, _resolve_display_name
local _enumerate_mods, _build_manifest_text, _chunk_text, _build_lobby_data
local _clear_lobby_data, _publish, _maybe_publish, _on_setting_changed

KNOWN_MODS = mod:dofile("scripts/mods/general_tweaker/_gt_lobby_known_mods") or {}

-- State ----------------------------------------------------------------------
local _last_publish_ms     = 0
local _last_heal_s         = 0
local _last_poll_s         = 0
local _last_text_published = nil
local _last_chunks         = {}
local _last_chunk_count    = 0
local _last_handle_found   = false
local _was_enabled         = nil

-- Helpers --------------------------------------------------------------------
_now_ms = function() return math.floor((os.clock() or 0) * 1000) end

_is_host = function()
    local sn = Managers.state and Managers.state.network
    if sn and sn.is_server == true then return true end
    local pm = Managers.player
    return pm and pm.is_server == true or false
end

-- LobbyHost candidates (verified vs Vermintide-2-Source-Code):
--   game_network_manager.lua:50  self._lobby_host = lobby:lobby_host()
--   network_server.lua:55        self.lobby_host = lobby_host
--   matchmaking_manager.lua:637  self.lobby (LobbyHost on host side only --
--                                 duck-type on set_lobby_data because the
--                                 same field is a LobbyClient when joining).
_get_lobby_host = function()
    local sn = Managers.state and Managers.state.network
    if sn then
        if sn._lobby_host then return sn._lobby_host end
        if sn.network_server and sn.network_server.lobby_host then
            return sn.network_server.lobby_host
        end
    end
    local mm = Managers.matchmaking
    if mm and mm.lobby and type(mm.lobby.set_lobby_data) == "function" then
        return mm.lobby
    end
    return nil
end

_trim_field = function(s, max_len)
    if s == nil then return "" end
    s = tostring(s):gsub("[\t\n\r]", " ")
    if max_len and #s > max_len then
        if max_len == FIELD_NAME_MAX then
            s = s:sub(1, max_len - 1) .. "\xE2\x80\xA6"
        else
            s = s:sub(1, max_len)
        end
    end
    return s
end

-- Field resolvers ------------------------------------------------------------
_resolve_mode = function(mod_id, mod_obj)
    -- Sister mods may still set `_lt_mode` (the lobby_tweaker-era field name).
    -- Future-proof by ALSO honoring `_gt_lobby_mode`.
    if mod_obj then
        for _, field in ipairs({ "_gt_lobby_mode", "_lt_mode" }) do
            local m = mod_obj[field]
            if type(m) == "string" then
                m = m:upper()
                if m == "R" or m == "C" or m == "H" then return m end
            end
        end
    end
    local k = KNOWN_MODS[mod_id]
    if k == "R" or k == "C" or k == "H" then return k end
    return "R"
end

-- Sibling mods scope their MOD_VERSION as `local MOD_VERSION = "..."`, which
-- means it's invisible cross-mod -- `mod_obj.MOD_VERSION` / `_G[mod_id].MOD_VERSION`
-- both fall through to nil for every sister mod. Until either (1) sister
-- mods publish their version as `mod.MOD_VERSION` (public table field) or
-- (2) we maintain a hardcoded id->version map here, the manifest's version
-- column can't be populated and clients will see "version_unavailable" in
-- the failed-join reveal popup. Functionally this only matters for the
-- "version mismatch" branch -- the missing-mod branch (more common failure
-- mode) doesn't depend on version strings.
_resolve_version = function(mod_id, mod_obj)
    if mod_obj then
        if type(mod_obj.MOD_VERSION) == "string" then return mod_obj.MOD_VERSION end
        if type(mod_obj.version) == "string" then return mod_obj.version end
    end
    return "version_unavailable"
end

_resolve_workshop_id = function(vanilla_entry)
    if vanilla_entry and vanilla_entry.id then
        local id = tostring(vanilla_entry.id)
        if id ~= "" and id ~= "-9999" then return id end
    end
    return "0"
end

_resolve_display_name = function(vanilla_entry, mod_id, mod_obj)
    if vanilla_entry and type(vanilla_entry.name) == "string" and vanilla_entry.name ~= "" then
        return vanilla_entry.name
    end
    if mod_obj and type(mod_obj.get_name) == "function" then
        local ok, n = pcall(function() return mod_obj:get_name() end)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    return mod_id or "?"
end

-- Enumeration ----------------------------------------------------------------
-- String-id probe order: get_mod(name), get_mod(name:lower()),
-- KNOWN_MODS key whose lowercase matches name, else fall back to name itself.
_enumerate_mods = function()
    local out = {}
    local mm = Managers.mod
    if not mm or type(mm._mods) ~= "table" then return out end

    local seen = {}
    for i = 1, #mm._mods do
        local entry = mm._mods[i]
        if entry and entry.enabled and entry.handle then
            local display = entry.name or ""
            local string_id, mod_obj = nil, nil

            if _G.get_mod and display ~= "" then
                local ok, m = pcall(_G.get_mod, display)
                if ok and type(m) == "table" then
                    string_id, mod_obj = display, m
                else
                    local lc = display:lower()
                    if lc ~= display then
                        local ok2, m2 = pcall(_G.get_mod, lc)
                        if ok2 and type(m2) == "table" then string_id, mod_obj = lc, m2 end
                    end
                end
            end

            if not mod_obj and _G.get_mod and display ~= "" then
                local dlc = display:lower()
                for known_id, _ in pairs(KNOWN_MODS) do
                    if known_id:lower() == dlc then
                        local ok, m = pcall(_G.get_mod, known_id)
                        if ok and type(m) == "table" then
                            string_id, mod_obj = known_id, m
                            break
                        end
                    end
                end
            end

            if not string_id then
                string_id = display ~= "" and display or ("mod_" .. tostring(entry.id or i))
            end

            if not seen[string_id] then
                seen[string_id] = true
                out[#out + 1] = { id = string_id, mod_obj = mod_obj, vanilla = entry }
            end
        end
    end
    return out
end

-- Manifest text + chunking ---------------------------------------------------
_build_manifest_text = function()
    local mods = _enumerate_mods()
    local lines = {}
    for i = 1, #mods do
        local rec = mods[i]
        local id_s   = _trim_field(rec.id, FIELD_ID_MAX)
        local ver_s  = _trim_field(_resolve_version(rec.id, rec.mod_obj), FIELD_VER_MAX)
        local mode   = _resolve_mode(rec.id, rec.mod_obj)
        local wsid   = _trim_field(_resolve_workshop_id(rec.vanilla), FIELD_VER_MAX)
        local name_s = _trim_field(_resolve_display_name(rec.vanilla, rec.id, rec.mod_obj), FIELD_NAME_MAX)
        if id_s ~= "" then
            lines[#lines + 1] = id_s .. "\t" .. ver_s .. "\t" .. mode .. "\t" .. wsid .. "\t" .. name_s
        end
    end

    -- Size enforcement: drop H, then C, then truncate tail.
    local budget = MAX_CHUNKS * CHUNK_SIZE
    local function total_size(t)
        local sz = 0
        for i = 1, #t do sz = sz + #t[i] + 1 end
        return sz
    end
    local function drop_mode(t, mode)
        local out2 = {}
        for i = 1, #t do
            local m = t[i]:match("[^\t]*\t[^\t]*\t([^\t]*)")
            if m ~= mode then out2[#out2 + 1] = t[i] end
        end
        return out2
    end
    if total_size(lines) > budget then lines = drop_mode(lines, "H") end
    if total_size(lines) > budget then lines = drop_mode(lines, "C") end
    while total_size(lines) > budget and #lines > 1 do
        table.remove(lines, #lines)
    end
    return table.concat(lines, "\n")
end

_chunk_text = function(s)
    local out = {}
    if not s or s == "" then return out end
    local total = #s
    local n = math.ceil(total / CHUNK_SIZE)
    if n > MAX_CHUNKS then n = MAX_CHUNKS end
    for i = 1, n do
        local lo = (i - 1) * CHUNK_SIZE + 1
        local hi = math.min(i * CHUNK_SIZE, total)
        out[i] = s:sub(lo, hi)
    end
    return out
end

_build_lobby_data = function(chunks)
    local t = { ltw_p = PROTOCOL_VERSION, ltw_n = tostring(#chunks) }
    for i = 1, #chunks do t["ltw_m" .. (i - 1)] = chunks[i] end
    return t
end

_clear_lobby_data = function(lobby_host)
    if not lobby_host or type(lobby_host.set_lobby_data) ~= "function" then return end
    local t = { ltw_p = "", ltw_n = "0" }
    for i = 0, MAX_CHUNKS - 1 do t["ltw_m" .. i] = "" end
    local ok, err = pcall(function() lobby_host:set_lobby_data(t) end)
    if not ok then mod:warning("%s clear publish failed: %s", TAG, tostring(err)) end
    _last_text_published = nil
    _last_chunks = {}
    _last_chunk_count = 0
end

-- Publish --------------------------------------------------------------------
_publish = function(force)
    if not _is_host() then return false end

    local enabled = mod:get("gt_lobby_manifest_broadcast_enabled") and true or false
    if _was_enabled == true and enabled == false then
        local lh = _get_lobby_host()
        if lh then
            _clear_lobby_data(lh)
            mod:info("%s manifest broadcast disabled -- cleared lobby keys.", TAG)
        end
    end
    _was_enabled = enabled
    if not enabled then return false end

    local now = _now_ms()
    if not force and (now - _last_publish_ms) < THROTTLE_MS then return false end

    local lobby_host = _get_lobby_host()
    _last_handle_found = lobby_host ~= nil
    if not lobby_host then return false end
    -- v0.2.65-dev: defensive check mirrors _clear_lobby_data below.
    -- _get_lobby_host() may return a LobbyClient when joining a remote lobby
    -- (only host-side has set_lobby_data). Without this guard, the publish
    -- loop fires `attempt to call method 'set_lobby_data' (a nil value)`
    -- every tick (~once/sec) flooding chat warnings for non-host peers.
    if type(lobby_host.set_lobby_data) ~= "function" then return false end

    local text = _build_manifest_text()
    if not force and text == _last_text_published then
        _last_publish_ms = now
        return false
    end

    local chunks = _chunk_text(text)
    local data = _build_lobby_data(chunks)
    local ok, err = pcall(function() lobby_host:set_lobby_data(data) end)
    if not ok then
        mod:warning("%s set_lobby_data failed: %s", TAG, tostring(err))
        return false
    end

    _last_publish_ms     = now
    _last_text_published = text
    _last_chunks         = chunks
    _last_chunk_count    = #chunks
    mod:info("%s manifest published (%d chunks, %d bytes).", TAG, #chunks, #text)
    return true
end

_maybe_publish = function() _publish(false) end

-- Lifecycle ------------------------------------------------------------------
_on_setting_changed = function(setting_id) _publish(true) end

-- gt already owns mod.on_setting_changed (defined in general_tweaker.lua).
-- Wrap it the same way we wrap on_game_state_changed in _gt_lobby_session_ignore.
do
    local prev = mod.on_setting_changed
    mod.on_setting_changed = function(setting_id)
        if prev then
            local ok, err = pcall(prev, setting_id)
            if not ok then mod:warning("%s prev on_setting_changed err: %s", TAG, tostring(err)) end
        end
        -- Only republish on gt_lobby_* settings -- other gt settings don't
        -- affect the manifest, no point in churning lobby_data on every camera
        -- slider tweak.
        if type(setting_id) == "string" and setting_id:sub(1, 9) == "gt_lobby_" then
            _on_setting_changed(setting_id)
        end
    end
end

-- Poll via gt's central update registry.
local function _update_consumer(dt)
    _last_poll_s = _last_poll_s + (dt or 0)
    if _last_poll_s < POLL_INTERVAL_S then return end
    _last_poll_s = 0

    if not _is_host() then _last_handle_found = false; return end

    _last_heal_s = _last_heal_s + POLL_INTERVAL_S
    local force = _last_heal_s >= HEAL_INTERVAL_S
    if force then _last_heal_s = 0 end
    if force then _publish(true) else _maybe_publish() end
end

if type(mod._gt_register_update) == "function" then
    mod._gt_register_update("gt_lobby_modded_manifest", _update_consumer)
end

-- Diagnostics (renamed lt_manifest_dump -> gt_lobby_manifest_dump per merge)
mod:command("gt_lobby_manifest_dump", "Print the locally-built modded manifest.", function()
    local function chat(msg)
        if Managers.chat and Managers.chat.add_local_system_message then
            Managers.chat:add_local_system_message(1, msg, true)
        else
            mod:echo(msg)
        end
    end
    local host = _is_host()
    local lh = _get_lobby_host()
    chat(string.format("%s host=%s lobby_host=%s last_chunk_count=%d",
        TAG, tostring(host), tostring(lh ~= nil), _last_chunk_count))
    local text = _build_manifest_text()
    if text == "" then
        chat(string.format("%s manifest empty (no enabled mods or not built yet).", TAG))
        return
    end
    local chunks = _chunk_text(text)
    chat(string.format("%s built: chunks=%d bytes=%d", TAG, #chunks, #text))
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then chat("  " .. line) end
    end
end)

-- Exports --------------------------------------------------------------------
M.publish             = function() return _publish(true) end
M.maybe_publish       = _maybe_publish
M.build_manifest_text = _build_manifest_text
M.chunk_text          = _chunk_text
M.get_lobby_host      = _get_lobby_host
M.is_host             = _is_host

return M
