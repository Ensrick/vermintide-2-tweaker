local mod = get_mod("gt_dev")
local M = {}

-- ============================================================================
-- In-lobby appearance-parity banner (client side, issue 371 / issue 737).
-- ============================================================================
-- Issue 737 shape: the host ran wt 0.12.274-beta DISABLED while both clients ran
-- wt_dev 0.12.275-dev ENABLED. The join SUCCEEDED -- the network_hash covers the
-- compiled network config / engine revision / DLC set / level-key count, NOT the
-- VMF mod set (see _gt_lobby_failed_join_reveal.lua's watchdog note) -- so
-- neither the failed-join reveal nor the stalled-join watchdog fired. The
-- divergent NetworkLookup.weapon_skins index spaces then desynced into a
-- score-screen CTD (index 924) and a session of husk/preview failures.
--
-- This module closes that gap. While a joined CLIENT it reads the host's already
-- published modded manifest (the SAME producer the failed-join reveal consumes,
-- _gt_lobby_modded_manifest.lua -- UNCHANGED, never a second writer) and compares
-- the APPEARANCE-mod subset against the local mod set. On any asymmetry -- an
-- appearance mod enabled on exactly one side, or a different stream/version -- it
-- posts ONE chat line per lobby composition change naming the mod and both
-- states. The comparison itself is the pure engine-free _lib_appearance_parity.
--
-- WIRE SAFETY: READ-ONLY. It only READS Steam lobby_data and posts a LOCAL chat
-- line. Zero new networked sends, zero NetworkLookup/RPC surface -- the producer
-- already broadcasts host-side and is hash-neutral, and lobby_data is Steam
-- metadata, not a game RPC (VMF_RECIPES section 10 wire-safety by construction).
--
-- CLIENT-ONLY, and why the host does not also warn: lobby_data is host->client
-- (only the host writes it), so a client can diff against the host but the host
-- has no channel to read a client's mod set. A peer-to-peer VMF beacon could add
-- host+client<->client coverage, but VMF network channels are mod-id-scoped, so
-- a gt vs gt_dev host/client split (exactly issue 737's wt vs wt_dev shape)
-- would not connect -- the mod-id-AGNOSTIC lobby_data manifest is the only
-- transport that spans it. See the ship report / issue 371 for the follow-up.
--
-- No new hooks: polls through gt's central update registry. Reuses the failed-
-- join reveal's engine helpers (manifest fetch + lobby id + local mod index) via
-- the mod._gt_lobby_* exports it publishes, so there is one fetch and one index.

local PARITY = mod:dofile("scripts/mods/general_tweaker_dev/_lib_appearance_parity")

local POLL_INTERVAL_S = 1.0
local _poll_accum = 0
local _last_key   = nil   -- appearance composition key we last evaluated (fire once per change)

-- The live session lobby when we are a NON-host client, else nil. The host
-- writes the manifest into lobby_data and clients read it, so only a client has
-- a host manifest to diff against. Mirrors the watchdog's client gate
-- (_gt_lobby_failed_join_reveal.lua _wd_is_stalled_joining_client).
local function _client_session_lobby()
    local lm = Managers and Managers.lobby
    if not (lm and lm.query_lobby) then return nil end
    local ok, lobby = pcall(function() return lm:query_lobby("matchmaking_session_lobby") end)
    if not ok or not lobby or lobby.is_host then return nil end
    return lobby
end

-- mod:echo runs its argument through string.format, so a literal '%' in a mod id
-- or version would misparse. Escape it (same guard as _lib_peer_parity's _echo).
local function _echo_safe(text)
    pcall(function() mod:echo((tostring(text):gsub("%%", "%%%%"))) end)
end

-- Fetch + parse the host manifest and build the local index using the failed-
-- join reveal's exported engine helpers. Returns host_entries, local_index or
-- nil when the host is not broadcasting (vanilla / non-gt host) or the helpers
-- are not yet available.
local function _gather()
    local fetch          = mod._gt_lobby_fetch_manifest
    local safe_lobby_id  = mod._gt_lobby_safe_lobby_id
    local build_index    = mod._gt_lobby_build_local_index
    if not (fetch and safe_lobby_id and build_index) then return nil end
    local lobby_id = safe_lobby_id()
    if not lobby_id then return nil end
    local text = fetch(lobby_id)
    if not text then return nil end
    return PARITY.parse_manifest(text), build_index()
end

local function _tick(dt)
    if not mod:get("gt_lobby_appearance_parity_enabled") then
        _last_key = nil
        return
    end
    _poll_accum = _poll_accum + (dt or 0)
    if _poll_accum < POLL_INTERVAL_S then return end
    _poll_accum = 0

    -- Not a joined client (solo / host / between lobbies): reset so a fresh join
    -- re-announces its composition.
    if not _client_session_lobby() then _last_key = nil; return end

    local host_entries, local_index = _gather()
    if not host_entries then _last_key = nil; return end

    local key = PARITY.composition_key(host_entries, local_index)
    if key == _last_key then return end   -- fire ONCE per composition change
    _last_key = key

    local records = PARITY.diff(host_entries, local_index)
    for i = 1, #records do
        _echo_safe(PARITY.format_banner(records[i]))
    end
end

if type(mod._gt_register_update) == "function" then
    mod._gt_register_update("gt_lobby_appearance_parity", _tick)
end

-- Diagnostic: dump the current appearance-parity evaluation on demand (no wait
-- for a composition change). Ignores the enable toggle so it always answers.
mod:command("lobby_appearance_parity", "Show how your appearance mods compare to the host", function()
    if not _client_session_lobby() then
        mod:echo("[gt] appearance parity: not a joined client (you are the host or solo).")
        return
    end
    local host_entries, local_index = _gather()
    if not host_entries then
        mod:echo("[gt] appearance parity: the host is not broadcasting a mod list.")
        return
    end
    local records = PARITY.diff(host_entries, local_index)
    if #records == 0 then
        mod:echo("[gt] appearance parity: OK, your appearance mods match the host.")
        return
    end
    for i = 1, #records do
        _echo_safe(PARITY.format_banner(records[i]))
    end
end)

-- Exports for the regression suite / manual drive.
M.tick = _tick
mod._gt_lobby_appearance_parity_tick = _tick
return M
