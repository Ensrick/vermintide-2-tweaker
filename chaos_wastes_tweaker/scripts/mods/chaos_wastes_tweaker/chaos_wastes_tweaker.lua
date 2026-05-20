--[[
chaos_wastes_tweaker — Chaos Wastes ("deus" mode) run modifiers.

Major sections (search by name to jump):
  * Coin economy           — coin_multiplier hook on DeusRunController.on_soft_currency_picked_up,
                             starting_coins via setup_run.
  * Boon counts            — generate_random_power_ups hook intercepts shrine (4) and chest (3) defaults.
  * Disabled boons         — save-and-restore mutation of DeusPowerUpsArray / *ByRarity around the roll.
  * Curses                 — disable_curse_* setting reads, gating MutatorHandler._activate_mutator,
                             DeusMechanism.get_current_node_curse, and node theme/curse fields.
  * Run config overrides   — deus_journey_with_belakor hook (force_belakor) +
                             game_round_ended pre-mutation of vote_data.dominant_god
                             (finale_dominant_god). Both host-only.
  * Pickups & altars       — populate_pickups hook patches deus_weapon_chest / deus_cursed_chest /
                             ammo counts AND injects campaign potions into Pickups.deus_potions
                             with full-group renormalization (see also: DEVELOPMENT.md).
  * Chest-type distribution — get_deus_weapon_chest_type override; "Default" sentinel = 0.
  * Starting boons         — _add_initial_power_ups hook (host-only) grants toggled boons.
  * Banned weapon traits   — apply_weapon_trait_filter / restore_weapon_trait_filter wraps
                             DeusWeaponGeneration calls.
  * Khaine's Fury tweak    — apply_reckless_swings_tweak / revert_reckless_swings_tweak +
                             sync_reckless_swings (forward-declared; called from boon roll).
  * Bomb boon balance      — bomb_boon_cooldown override on drop_item_on_ability_use, mutual
                             exclusivity in generate_random_power_ups via BOMB_BOON_NAMES,
                             Endless-Bombs-consumes-Morgrim hook on apply_pockets_full_of_bombs_buff,
                             RV-no-save-Morgrim hook on ActionChargedProjectileUtility.fire_charged_projectile.
  * Lifecycle              — on_setting_changed re-syncs Khaine's Fury and bomb cooldown;
                             on_disabled reverts both persistent DeusPowerUpTemplates mutations.
]]

local mod = get_mod("ct")

local MOD_VERSION = "0.7.77-alpha"
mod:info("Chaos Wastes Tweaker v%s loaded", MOD_VERSION)
mod:echo("Chaos Wastes Tweaker v" .. MOD_VERSION)

local AdventurePool = mod:dofile("scripts/mods/chaos_wastes_tweaker/_adventure_pool")
-- Call unconditionally so the LEVEL_AVAILABILITY snapshot is captured at mod load,
-- even if the master toggle is off. inject_pool() short-circuits internally when the
-- master is off (only resets to snapshot). Snapshot-at-load means subsequent toggles
-- always reset to clean vanilla state — no race where snapshot is taken after our
-- own previous mutations.

-- Capture vanilla NetworkLookup.level_keys count BEFORE inject_pool can mutate it.
-- The lobby-hash-pretend hook below uses this to hide our injected entries from
-- LobbyAux.create_network_hash so the combined_hash always reports vanilla num_levels,
-- letting peers with this mod join vanilla / non-matching lobbies. See v0.7.4-alpha
-- CHANGELOG for the full root-cause and reference_vt2_lobby_combined_hash.md.
local _vanilla_level_keys_count
if rawget(_G, "NetworkLookup") and NetworkLookup.level_keys then
    _vanilla_level_keys_count = #NetworkLookup.level_keys
end

AdventurePool.inject_pool()

-- Lobby-hash-pretend shim. VT2's LobbyAux.create_network_hash (lobby_aux.lua:26) reads
-- `num_levels = #NetworkLookup.level_keys` and folds it into the lobby `combined_hash`
-- that all peers compare for join compatibility. Our _adventure_pool.lua registers a new
-- level_keys entry for every injected adventure permutation (and must — the multiplayer
-- level-load RPC serializes by index into this table). That bumped num_levels from
-- vanilla 582 to ~774 and gave players `Join failed - Game version mismatch` against any
-- peer with a different injection configuration (including vanilla).
--
-- Fix: temporarily nil out the injected entries (indices > _vanilla_level_keys_count)
-- during create_network_hash, then restore. `#` operates on the contiguous-prefix length,
-- so vanilla code computes num_levels as if we never injected. Entries are restored
-- before the function returns, so the in-game level-load RPC still resolves correctly.
--
-- Effect:
--   • A peer with injection on can JOIN any vanilla or mismatched lobby (hash matches).
--   • A peer hosting CW with injection on creates a lobby whose hash also reports vanilla,
--     so vanilla peers can join too.
--   • Cross-config play is now possible for VANILLA CW scenarios. Picking an INJECTED
--     adventure mission while a vanilla peer is in the lobby still crashes that peer
--     (their level_keys lacks the entry) — host has to pick a vanilla CW node, or all
--     peers must run matching injection. See "Caveats" in v0.7.4-alpha CHANGELOG.
local _LobbyAux = rawget(_G, "LobbyAux")
if _LobbyAux and _LobbyAux.create_network_hash and _vanilla_level_keys_count then
    mod:hook(_LobbyAux, "create_network_hash", function(func, ...)
        local lookup = rawget(_G, "NetworkLookup") and NetworkLookup.level_keys
        if not lookup then return func(...) end
        local current = #lookup
        if current <= _vanilla_level_keys_count then return func(...) end

        local saved = {}
        for i = current, _vanilla_level_keys_count + 1, -1 do
            saved[i] = lookup[i]
            lookup[i] = nil
        end

        local hash_result = func(...)

        for i, k in pairs(saved) do
            lookup[i] = k
        end

        return hash_result
    end)
    mod:info("Lobby hash shim installed (vanilla level_keys count = %d).", _vanilla_level_keys_count)
else
    mod:warning("Lobby hash shim NOT installed; LobbyAux=%s vanilla_count=%s. Injected adventure missions may cause 'Game version mismatch' on join.",
        tostring(_LobbyAux ~= nil), tostring(_vanilla_level_keys_count))
end

local SHRINE_DEFAULT = 4
local CHEST_DEFAULT = 3
local FINALE_GODS = { "nurgle", "tzeentch", "khorne", "slaanesh" }

-- Boons that grant or amplify free bombs/grenades. Used by the bomb-boon mutual-exclusion
-- toggle (one bomb boon per run) and listed in the localization tooltip.
local BOMB_BOON_NAMES = {
    drop_item_on_ability_use = true,
    deus_grenade_multi_throw = true,
}

local granting_starting_coins = false
local all_trait_combos_cache = nil
-- CLARIFY: Forward-declared so the `generate_random_power_ups` hook (call site line 150) and
-- `on_setting_changed` (line 740) can reference sync_reckless_swings before its assignment at line
-- 724. Lua 5.1 locals are not hoisted; without this stub the references would either resolve to a
-- global lookup (and silently no-op until the assignment runs) or crash. See
-- feedback_lua_forward_reference.md (5 prior crashes from this exact bug pattern).
local sync_reckless_swings
local sync_bomb_cooldown
local sync_ulric_pack_unlimited_range
local sync_boon_movespeed
-- v0.7.39: defeat-recovery state. Referenced in `_transition_next_node` hook (line ~402)
-- which is defined BEFORE the feature block that owns this flag (line ~2706+). Forward-
-- declaring here keeps the hook valid pre-feature-block execution.
local _defeat_recovery_triggered_this_round = false

-- Forward-declared so hooks/UI text generators can resolve it lexically; body assigned
-- after `effective_setting` is defined (Lua local hoisting rules require the slot to
-- exist before any closure captures it).
local is_curse_disabled

-- v0.7.55: forward-declared so hooks above its assignment (most notably the
-- on_soft_currency_picked_up hook at line ~140 reading coin_multiplier) can capture
-- the local slot at closure creation time. Body assigned in the multiplayer-sync
-- block below.
local effective_setting

-- Forward declaration: assigned in the peer-manifest block. The ct_sync_host_settings_chunk
-- handler calls this on receive so each client replies to the host's broadcast with its
-- own manifest. Defined later in the file, but the handler closure is built before then,
-- so it needs the forward-declared local slot to bind a closure-over.
local _broadcast_local_manifest

-- CLARIFY: Vanilla signature is `on_soft_currency_picked_up(self, amount, type)`. The `amount` is
-- args[1] (NOT args[2] — that mistake was the cause of an early-version coin multiplier bug; see
-- "Coin multiplier not working (wrong argument index)" in DEVELOPMENT.md).
mod:hook("DeusRunController", "on_soft_currency_picked_up", function(func, self, ...)
    local args = { ... }
    local raw_amount = args[1]

    if type(raw_amount) == "number" and not granting_starting_coins then
        -- v0.7.55: route through effective_setting so a client picking up coins applies
        -- the host's coin_multiplier (matches what the host's own pickups grant).
        local multiplier = effective_setting("coin_multiplier") or 1
        args[1] = math.max(1, math.floor(raw_amount * multiplier))
    end

    return func(self, unpack(args))
end)

-- CLARIFY: Granting starting coins by re-entering on_soft_currency_picked_up. The
-- `granting_starting_coins` flag suppresses the multiplier hook above so 500 starting coins doesn't
-- get doubled by a 2x multiplier setting. Without the flag, a multiplier > 1 would inflate the gift.
-- POTENTIAL BUG (LOW): the second arg to on_soft_currency_picked_up is `type` (a
-- DeusSoftCurrencySettings.types.{GROUND,MONSTER,...} value). Passing nil means the server-only
-- branch in vanilla treats this as neither GROUND nor MONSTER, so the per-pickup counters are NOT
-- incremented — fine for starting coins, but worth knowing.

-- ============================================================
-- Multiplayer settings sync (v0.7.21)
-- ============================================================
-- CW's graph generation is deterministic from seed and runs on BOTH host and
-- client (rpc_deus_setup_run triggers it on clients). Without sync, peers run
-- our graph-mutating overrides against THEIR OWN settings, producing divergent
-- local graphs. v0.7.20 gated the hook on `is_server` to stop crashes (clients
-- pass through to vanilla) but the client's local view still differs from the
-- host's mutated graph — so the map shows the wrong curse, the wrong theme on
-- a mission, etc.
--
-- This sync: when host's setup_run fires, broadcast effective host settings to
-- clients via VMF's mod:network_send. Clients stash the values in
-- `_ct_host_settings`. The deus_populate_graph hook then reads from there on
-- client (instead of mod:get which would give the CLIENT's own settings).
--
-- Settings synced: every mod-defined setting except those in PER_PEER_SETTING_NAMES.
--
-- v0.7.55: previously this was a hand-maintained list of ~50 names that grew every
-- release. After repeated bugs from missing entries (most recently: disable_curse_*
-- helper bypassed sync, finale_dominant_god / force_belakor weren't reaching clients,
-- coin/boon/trait toggles silently diverged) we switched to "sync everything by
-- default" — walk the data file's widget tree at module load and emit every
-- leaf-widget's setting_id, minus an explicit per-peer exclusion list.
--
-- This means: any setting that's host-authoritative (clients should see whatever host
-- has) gets synced automatically just by living in chaos_wastes_tweaker_data.lua.
-- Adding a new mod setting requires NO bookkeeping here.
--
-- PER_PEER excludes: settings that are intentionally each-peer-local. These are rare
-- and require a deliberate justification (see comments per entry).
local PER_PEER_SETTING_NAMES = {
    -- v0.7.64: `tweak_defeat_recovery` and `enable_campaign_potions` were per-peer for
    -- historical reasons (the comments below) but the user's design intent is "all
    -- settings sync to host." Both are now host-synced; the original comments are
    -- kept as a record of why they used to be per-peer.
    --
    --   tweak_defeat_recovery: was "each peer needs the toggle on for their own
    --   coins/boons to be penalized." Now: the host's value decides for the lobby.
    --   The wipe-prevention itself was always host-only (GameModeDeus is
    --   server-authoritative); only the local penalty arm was per-peer.
    --
    --   enable_campaign_potions: was "server-driven spawn, no graph effect; client
    --   mutation irrelevant." Same — the host's value decides; client-side table
    --   mutation never had any effect anyway.
    --
    -- inject_adventure_maps STAYS per-peer because it mutates NetworkLookup.level_keys
    -- count and folds into lobby `combined_hash` (see reference_vt2_lobby_combined_hash).
    -- The LobbyAux hash shim above hides the count diff so peers with different values
    -- can still join, but each peer's resolved graph diverges as a result. Switching it
    -- to host-sync would require also re-running AdventurePool.inject_pool() on clients,
    -- which can't happen post-boot (level_keys are sealed before lobby handshake).
    -- Curse/mission visual desync from this is tracked as a separate follow-up — likely
    -- needs a host→client graph snapshot RPC instead of toggle sync.
    inject_adventure_maps   = true,
}

local function _collect_setting_ids()
    -- mod:dofile re-executes the data file. Idempotent: tree-building has no side
    -- effects beyond an in-place recursive_sort (which is stable on already-sorted
    -- tables). Returns the same `data` table that VMF loaded at mod registration.
    local data = mod:dofile("scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker_data")
    local ids = {}
    local seen = {}
    local function visit(node)
        if type(node) ~= "table" then return end
        if type(node.setting_id) == "string" and node.type and node.type ~= "group"
            and not seen[node.setting_id]
        then
            seen[node.setting_id] = true
            ids[#ids + 1] = node.setting_id
        end
        if node.sub_widgets then
            for _, w in ipairs(node.sub_widgets) do visit(w) end
        end
        if node.widgets then
            for _, w in ipairs(node.widgets) do visit(w) end
        end
    end
    visit(data.options)
    return ids
end

local SYNCED_SETTING_NAMES = {}
for _, id in ipairs(_collect_setting_ids()) do
    if not PER_PEER_SETTING_NAMES[id] then
        SYNCED_SETTING_NAMES[#SYNCED_SETTING_NAMES + 1] = id
    end
end
mod:info("[ct_sync] synced setting registry built: %d keys (%d excluded as per-peer)",
    #SYNCED_SETTING_NAMES, (function() local n = 0; for _ in pairs(PER_PEER_SETTING_NAMES) do n = n + 1 end; return n end)())

local _ct_host_settings = {}
local _ct_host_sync_received = false

-- Forward-declared so the network_register callback below can call it before
-- its assignment further down the file (after all sync_* functions exist).
local sync_host_dependent_state

-- Chunked-string sync protocol (mirrors vanilla shared_state.lua:288-330).
-- Stingray caps each RPC string parameter at 500 chars (network_utils.lua:93
-- STRING_MAX). VMF's mod:network_send packs all user args into ONE JSON-encoded
-- string parameter on rpc_mod_user_data, so a 105-setting table (~4-5KB JSON)
-- crashes the host with "Failed to pack parameter 3, too many characters in
-- string with max length 500" before the packet ever leaves. Cost: clients
-- received zero host settings between v0.7.55 and v0.7.58.
--
-- Fix: encode the payload to JSON ourselves, split into <=CHUNK_SIZE pieces,
-- send each as (session, seq, total, chunk_str). Receiver buffers per sender
-- and decodes when all chunks for the current session arrive. Session id
-- changes on every broadcast so a partial buffer from a stale broadcast is
-- discarded the moment the next one starts.
--
-- CHUNK_SIZE budget: the wire-side JSON envelope is roughly
--   [<session>,<seq>,<total>,"<chunk>"]  ~= 20 chars of overhead + chunk_str.
-- VMF adds its own [mod_id,rpc_id] envelope as a separate string parameter,
-- so only this user-payload string needs to fit under 500. 400 leaves
-- headroom for the largest plausible envelope growth.
local SYNC_CHUNK_SIZE = 400
local _sync_inbound = {}

mod:network_register("ct_sync_host_settings_chunk", function(sender_peer_id, session, seq, total, chunk_str)
    if type(session) ~= "number" or type(seq) ~= "number" or type(total) ~= "number" or type(chunk_str) ~= "string" then
        mod:info("[ct_sync] malformed chunk from %s; ignoring", tostring(sender_peer_id))
        return
    end
    local key = tostring(sender_peer_id)
    local entry = _sync_inbound[key]
    if not entry or entry.session ~= session then
        entry = { session = session, total = total, received = 0, chunks = {} }
        _sync_inbound[key] = entry
    end
    if entry.chunks[seq] == nil then
        entry.chunks[seq] = chunk_str
        entry.received = entry.received + 1
    end
    if entry.received < entry.total then
        return
    end
    local pieces = {}
    for i = 1, entry.total do
        pieces[i] = entry.chunks[i] or ""
    end
    _sync_inbound[key] = nil
    local json = table.concat(pieces)
    local ok, payload = pcall(cjson.decode, json)
    if not ok or type(payload) ~= "table" then
        mod:info("[ct_sync] decode failed from %s (session %s, %d bytes)",
            tostring(sender_peer_id), tostring(session), #json)
        return
    end
    for _, name in ipairs(SYNCED_SETTING_NAMES) do
        _ct_host_settings[name] = payload[name]
    end
    _ct_host_sync_received = true
    mod:info("[ct_sync] received host settings from %s (session %s, %d chunks, %d bytes, %d keys)",
        tostring(sender_peer_id), tostring(session), entry.total, #json, #SYNCED_SETTING_NAMES)
    -- v0.7.67 ordering fix: the manifest broadcast MUST fire BEFORE
    -- sync_host_dependent_state() because any of the 11 sync_* re-registration
    -- helpers it invokes (trait boons, dormants, miracles, etc.) can throw, and
    -- VMF's network_register safe-wrapper swallows the error — aborting the
    -- receiver body silently. Pre-0.7.67 the manifest line was last; if anything
    -- in sync_host_dependent_state threw, the host never saw the client's RECV
    -- and we couldn't tell version drift from "feature didn't fire" in logs.
    mod:info("[ct_peers] client received host ct_sync — broadcasting own manifest back to host")
    if _broadcast_local_manifest then
        _broadcast_local_manifest("server")
    end
    if sync_host_dependent_state then
        sync_host_dependent_state()
    end
end)

-- ============================================================
-- Graph snapshot sync (v0.7.64)
-- ============================================================
-- ct_sync_host_settings_chunk above broadcasts the host's TOGGLES. That's enough
-- for graph determinism only when every peer's LEVEL_AVAILABILITY pool is identical.
-- But `inject_adventure_maps` mutates LEVEL_AVAILABILITY arrays at module-load and
-- can't be runtime-resynced (the count folds into lobby `combined_hash`, sealed at
-- the lobby handshake — see reference_vt2_lobby_combined_hash.md). When a peer has
-- the toggle in a different state than the host, their local `deus_populate_graph`
-- indexes into a different-sized pool and produces a different graph from the same
-- seed — observed 2026-05-19 in a 3-player run: same seed, three different node
-- assignments (host: 8 adventure-rewritten nodes; one client: 9; another: 0).
--
-- Fix: the host broadcasts its RESOLVED graph after `deus_populate_graph` returns.
-- Clients overwrite the picker-output fields of their own graph in place. Only the
-- fields the visual layer reads are shipped (level, base_level, theme, curse, god,
-- node_type, type, terror_event_power_up + rarity, mutators, minor_modifier_group);
-- topological fields (next, layout_x/y, run_progress, label) are deterministic
-- from base_graph + seed and don't need sync.

-- Short<->long field map. Short keys keep the per-node JSON tight to fit chunk
-- budget — ~22-28 CW nodes × ~110 bytes ~= 3.6 KB worst case, ~9-10 chunks.
local GRAPH_FIELD_MAP = {
    l  = "level",
    b  = "base_level",
    t  = "theme",
    c  = "curse",
    g  = "god",
    nt = "node_type",
    ty = "type",
    te = "terror_event_power_up",
    tr = "terror_event_power_up_rarity",
    m  = "mutators",
    mm = "minor_modifier_group",
}

local _ct_host_graph_snapshot = nil  -- { session = N, nodes = { [node_key] = { l=..., ... } } }
local _ct_graph_inbound = {}

-- Walk the snapshot and copy synced fields onto each node in `graph_data` in place.
-- In-place mutation preserves the table identity that `_path_graph` holds onto and
-- the `next` pointers that link nodes — neither is shipped, so neither is clobbered.
local function apply_graph_snapshot(graph_data)
    if not (_ct_host_graph_snapshot and _ct_host_graph_snapshot.nodes and graph_data) then
        return 0
    end
    local applied = 0
    for node_key, short_record in pairs(_ct_host_graph_snapshot.nodes) do
        local node = graph_data[node_key]
        if type(node) == "table" and type(short_record) == "table" then
            for short, long in pairs(GRAPH_FIELD_MAP) do
                local value = short_record[short]
                -- cjson encodes Lua nil as missing key; we treat missing as "no change"
                -- and explicit cjson.null (decoded to a sentinel) as "set to nil".
                if value ~= nil then
                    if value == cjson.null then
                        node[long] = nil
                    else
                        node[long] = value
                    end
                end
            end
            applied = applied + 1
        end
    end
    return applied
end

mod:network_register("ct_graph_snapshot_chunk", function(sender_peer_id, session, seq, total, chunk_str)
    if type(session) ~= "number" or type(seq) ~= "number" or type(total) ~= "number" or type(chunk_str) ~= "string" then
        mod:info("[ct_graph] malformed chunk from %s; ignoring", tostring(sender_peer_id))
        return
    end
    local key = tostring(sender_peer_id)
    local entry = _ct_graph_inbound[key]
    if not entry or entry.session ~= session then
        entry = { session = session, total = total, received = 0, chunks = {} }
        _ct_graph_inbound[key] = entry
    end
    if entry.chunks[seq] == nil then
        entry.chunks[seq] = chunk_str
        entry.received = entry.received + 1
    end
    if entry.received < entry.total then
        return
    end
    local pieces = {}
    for i = 1, entry.total do
        pieces[i] = entry.chunks[i] or ""
    end
    _ct_graph_inbound[key] = nil
    local json = table.concat(pieces)
    local ok, payload = pcall(cjson.decode, json)
    if not ok or type(payload) ~= "table" then
        mod:info("[ct_graph] decode failed from %s (session %s, %d bytes)",
            tostring(sender_peer_id), tostring(session), #json)
        return
    end
    _ct_host_graph_snapshot = { session = session, nodes = payload }
    local node_count = 0
    for _ in pairs(payload) do node_count = node_count + 1 end
    mod:info("[ct_graph] received host graph snapshot from %s (session %s, %d chunks, %d bytes, %d nodes)",
        tostring(sender_peer_id), tostring(session), entry.total, #json, node_count)
end)

-- Encode the host's resolved graph_data into the short-key wire shape and
-- chunk-broadcast it to all clients. Called from the deus_populate_graph hook on
-- the host's return path. Same envelope as ct_sync_host_settings_chunk.
local function broadcast_graph_snapshot(graph_data)
    if type(graph_data) ~= "table" then return end
    local payload = {}
    local node_count = 0
    for node_key, node in pairs(graph_data) do
        if type(node) == "table" then
            local short = {}
            for s, long in pairs(GRAPH_FIELD_MAP) do
                local v = node[long]
                if v ~= nil then short[s] = v end
            end
            payload[node_key] = short
            node_count = node_count + 1
        end
    end
    local ok, json = pcall(cjson.encode, payload)
    if not ok or type(json) ~= "string" then
        mod:info("[ct_graph] payload encode failed; not broadcasting")
        return
    end
    local json_len = #json
    local total = math.max(1, math.ceil(json_len / SYNC_CHUNK_SIZE))
    local session = math.floor(((Application and Application.time_since_launch and Application.time_since_launch()) or os.time()) * 1000) % 2147483647
    if session == 0 then session = 1 end
    for seq = 1, total do
        local start_i = (seq - 1) * SYNC_CHUNK_SIZE + 1
        local stop_i = math.min(start_i + SYNC_CHUNK_SIZE - 1, json_len)
        local chunk_str = string.sub(json, start_i, stop_i)
        mod:network_send("ct_graph_snapshot_chunk", "others", session, seq, total, chunk_str)
    end
    mod:info("[ct_graph] broadcast host graph snapshot (session %d, %d chunks, %d bytes, %d nodes)",
        session, total, json_len, node_count)
end

-- ============================================================
-- Peer manifest logging (v0.7.64)
-- ============================================================
-- Diagnostic: at lobby join / mission start, each client replies to the host's
-- ct_sync_host_settings_chunk broadcast with a ct_peer_manifest packet so the host's
-- log captures what every peer is actually running. Lets us tell version drift from
-- "real bug" in post-session log triage — the 2026-05-19 desync run had three peers
-- on potentially different ct builds and we couldn't confirm that from the logs.
--
-- Manifest fields (per peer):
--   v   ct version string (MOD_VERSION)
--   h   FNV-1a hash of the host-synced settings (so we can spot setting drift cheaply)
--   m   list of enabled Workshop mods (id, name, last_updated) — THE diagnostic for
--       "your friend's halo is different" caused by mismatched mod loadouts
--   vt  VMF workshop_timestamp (mismatched VMF builds cause weird bugs)
--   nl  #NetworkLookup.level_keys (confirms adventure-injection state per peer)
--
-- VMF network_register is string-keyed, NOT index-sequential, so this RPC does
-- NOT trip feedback_vt2_gated_registration_diverges.md. Old-ct peers without the
-- handler silently drop the packet — no crash.

local _ct_peer_manifests = {}      -- peer_id (string) -> decoded manifest table
local _ct_manifest_inbound = {}    -- chunked-receive buffer

-- FNV-1a 32-bit over a deterministic string. Used to fingerprint the synced settings
-- payload so a 1-byte log line shows whether two peers have identical CT config.
-- Stingray runs LuaJIT — `bit.bxor` and `bit.band` are available; native `~` and `&`
-- operators are not (LuaJIT defaults to Lua 5.1 syntax, no Lua-5.3 bitwise ops).
local _fnv_bxor = bit and bit.bxor
local _fnv_band = bit and bit.band
local function _fnv1a(s)
    if not (_fnv_bxor and _fnv_band) then
        -- Defensive fallback: bit library missing on some platform. Use a simple
        -- modular accumulator. Worse distribution but still good enough to flag
        -- "definitely different" without an exception.
        local h = 0
        for i = 1, #s do
            h = (h * 31 + string.byte(s, i)) % 4294967296
        end
        return h
    end
    local h = 2166136261
    for i = 1, #s do
        h = _fnv_band(_fnv_bxor(h, string.byte(s, i)), 0xFFFFFFFF)
        h = _fnv_band(h * 16777619, 0xFFFFFFFF)
    end
    return h
end

local function _build_local_manifest()
    local manifest = { v = MOD_VERSION }
    -- Settings hash: serialize SYNCED_SETTING_NAMES values in traversal-order (the
    -- order `_collect_setting_ids` walks the data tree, deterministic across all
    -- peers running the same ct version). Two peers with the same config produce
    -- the same fingerprint. mod:get reads the LOCAL value — we want each peer's
    -- local setting fingerprint, not the host's.
    local pieces = {}
    for _, name in ipairs(SYNCED_SETTING_NAMES) do
        pieces[#pieces + 1] = name .. "=" .. tostring(mod:get(name))
    end
    manifest.h = _fnv1a(table.concat(pieces, "|"))
    -- Enabled mods: Managers.mod._mods is the canonical local view (mod_manager.lua:326).
    local enabled = {}
    if Managers and Managers.mod and Managers.mod._mods then
        for _, m_entry in ipairs(Managers.mod._mods) do
            if type(m_entry) == "table" and m_entry.enabled then
                enabled[#enabled + 1] = {
                    i = tostring(m_entry.id or ""),
                    n = tostring(m_entry.name or ""),
                    u = m_entry.last_updated or m_entry.timestamp or 0,
                }
                if tostring(m_entry.id) == "1369573612" then
                    manifest.vt = m_entry.last_updated or m_entry.timestamp or 0
                end
            end
        end
    end
    manifest.m = enabled
    manifest.nl = (NetworkLookup and NetworkLookup.level_keys and #NetworkLookup.level_keys) or 0
    return manifest
end

local function _log_peer_manifest(peer_id, manifest, label)
    if type(manifest) ~= "table" then return end
    local mods_count = (type(manifest.m) == "table") and #manifest.m or 0
    mod:info("[ct_peers] %s peer=%s ct=%s settings_hash=%08x vmf_ts=%s num_levels=%s enabled_mods=%d",
        label or "PEER",
        tostring(peer_id),
        tostring(manifest.v),
        manifest.h or 0,
        tostring(manifest.vt or "?"),
        tostring(manifest.nl or "?"),
        mods_count)
end

local function _log_peer_diff_against_host(peer_id, peer_manifest, host_manifest)
    if type(peer_manifest) ~= "table" or type(host_manifest) ~= "table" then return end
    local diffs = {}
    if peer_manifest.v ~= host_manifest.v then
        diffs[#diffs + 1] = "ct_version(" .. tostring(peer_manifest.v) .. " vs host " .. tostring(host_manifest.v) .. ")"
    end
    if peer_manifest.h ~= host_manifest.h then
        diffs[#diffs + 1] = "settings_hash"
    end
    if peer_manifest.nl ~= host_manifest.nl then
        diffs[#diffs + 1] = "num_levels(" .. tostring(peer_manifest.nl) .. " vs host " .. tostring(host_manifest.nl) .. ")"
    end
    if peer_manifest.vt ~= host_manifest.vt then
        diffs[#diffs + 1] = "vmf_timestamp(" .. tostring(peer_manifest.vt) .. " vs host " .. tostring(host_manifest.vt) .. ")"
    end
    -- Mod-set diff (by id).
    local host_ids, peer_ids = {}, {}
    if type(host_manifest.m) == "table" then
        for _, m in ipairs(host_manifest.m) do host_ids[m.i or ""] = m.n or "?" end
    end
    if type(peer_manifest.m) == "table" then
        for _, m in ipairs(peer_manifest.m) do peer_ids[m.i or ""] = m.n or "?" end
    end
    local missing, extra = {}, {}
    for id, name in pairs(host_ids) do
        if not peer_ids[id] then missing[#missing + 1] = name end
    end
    for id, name in pairs(peer_ids) do
        if not host_ids[id] then extra[#extra + 1] = name end
    end
    if #missing > 0 then diffs[#diffs + 1] = "missing_vs_host=[" .. table.concat(missing, ",") .. "]" end
    if #extra > 0 then diffs[#diffs + 1] = "extra_vs_host=[" .. table.concat(extra, ",") .. "]" end

    if #diffs > 0 then
        mod:info("[ct_peers]   DIFF peer=%s: %s", tostring(peer_id), table.concat(diffs, "; "))
    else
        mod:info("[ct_peers]   peer=%s matches host", tostring(peer_id))
    end
end

-- Assigned to the forward-declared local at top of file so the ct_sync handler
-- closure (which fires before this block executes) can call us.
_broadcast_local_manifest = function(target)
    local manifest = _build_local_manifest()
    local ok, json = pcall(cjson.encode, manifest)
    if not ok or type(json) ~= "string" then
        mod:info("[ct_peers] manifest encode failed; not broadcasting")
        return
    end
    local json_len = #json
    local total = math.max(1, math.ceil(json_len / SYNC_CHUNK_SIZE))
    local session = math.floor(((Application and Application.time_since_launch and Application.time_since_launch()) or os.time()) * 1000) % 2147483647
    if session == 0 then session = 1 end
    for seq = 1, total do
        local start_i = (seq - 1) * SYNC_CHUNK_SIZE + 1
        local stop_i = math.min(start_i + SYNC_CHUNK_SIZE - 1, json_len)
        local chunk_str = string.sub(json, start_i, stop_i)
        mod:network_send("ct_peer_manifest_chunk", target, session, seq, total, chunk_str)
    end
    return manifest, json_len, total
end

mod:network_register("ct_peer_manifest_chunk", function(sender_peer_id, session, seq, total, chunk_str)
    if type(session) ~= "number" or type(seq) ~= "number" or type(total) ~= "number" or type(chunk_str) ~= "string" then
        return
    end
    local key = tostring(sender_peer_id)
    local entry = _ct_manifest_inbound[key]
    if not entry or entry.session ~= session then
        entry = { session = session, total = total, received = 0, chunks = {} }
        _ct_manifest_inbound[key] = entry
    end
    if entry.chunks[seq] == nil then
        entry.chunks[seq] = chunk_str
        entry.received = entry.received + 1
    end
    if entry.received < entry.total then return end
    local pieces = {}
    for i = 1, entry.total do pieces[i] = entry.chunks[i] or "" end
    _ct_manifest_inbound[key] = nil
    local json = table.concat(pieces)
    local ok, payload = pcall(cjson.decode, json)
    if not ok or type(payload) ~= "table" then
        mod:info("[ct_peers] manifest decode failed from %s", tostring(sender_peer_id))
        return
    end
    _ct_peer_manifests[key] = payload
    _log_peer_manifest(sender_peer_id, payload, "RECV")
    -- If we're host, also print a diff against our own manifest right away.
    local is_server = Managers and Managers.player and Managers.player.is_server
    if is_server then
        local host_manifest = _build_local_manifest()
        _log_peer_diff_against_host(sender_peer_id, payload, host_manifest)
    end
end)

-- /peers — on-demand dump. Anyone can run it; everyone re-shares their
-- manifest so the requester's log is freshly populated.
mod:command("peers", "Dump per-peer ct/mod manifest diff vs host (for lobby desync triage)", function()
    local host_manifest = _build_local_manifest()
    _log_peer_manifest("self", host_manifest, "SELF")
    -- Broadcast to everyone so each peer re-shares its manifest with us.
    _broadcast_local_manifest("all")
    -- Print whatever we already have stored.
    local n = 0
    for peer_id, manifest in pairs(_ct_peer_manifests) do
        n = n + 1
        _log_peer_manifest(peer_id, manifest, "CACHED")
        _log_peer_diff_against_host(peer_id, manifest, host_manifest)
    end
    mod:echo(string.format("[ct_peers] dumped %d cached peer manifest(s); refreshed broadcast — re-run /peers in ~2s for new replies", n))
end)

-- Read effective setting: on host, use the user's actual configured value.
-- On client, use whatever the host most recently broadcast. If the client
-- hasn't received the broadcast yet (solo, RPC ordering before host setup_run),
-- fall back to the client's own mod:get so the mod still works locally before
-- any sync arrives.
-- v0.7.55: assigned to the forward-declared `effective_setting` slot so callers
-- above this point (on_soft_currency_picked_up coin multiplier, etc.) bind to the
-- same local instead of a nil global.
effective_setting = function(name)
    local is_server = Managers and Managers.player and Managers.player.is_server
    if is_server then
        return mod:get(name)
    end
    local v = _ct_host_settings[name]
    if v ~= nil then
        return v
    end
    return mod:get(name)
end

-- v0.7.53: routed through `effective_setting` so client peers gate on the host's synced
-- toggle, not their own. Previously used `mod:get` directly, which made client-side curse
-- name display (`get_current_node_curse` hook + `_transition_next_node` save-restore)
-- diverge from the host's: gameplay ran the host's mutator either way, but the curse
-- name shown on Holseher's map / mission tooltips read each peer's local toggle.
is_curse_disabled = function(curse_name)
    if type(curse_name) ~= "string" or not curse_name:find("^curse_") then
        return false
    end
    local key = "disable_curse_" .. curse_name:gsub("^curse_", "")
    return effective_setting(key) == true
end

mod:hook_safe("DeusRunController", "setup_run", function(self)
    local starting = mod:get("starting_coins")
    if starting and starting > 0 and self.on_soft_currency_picked_up then
        granting_starting_coins = true
        self:on_soft_currency_picked_up(starting)
        granting_starting_coins = false
    end

    -- On host only: broadcast our settings to all clients so their
    -- deus_populate_graph hook (about to fire on their machines) mutates the
    -- same way. VMF's network_send is FIFO over the same Steam channel as the
    -- engine's rpc_deus_setup_run, so as long as we send BEFORE the engine
    -- sends its setup_run RPC (we hook_safe AT the end of host's setup_run,
    -- which is right before full_sync() ships the engine RPC to clients), our
    -- packet arrives first and the client processes it before their setup_run
    -- fires. Verified safe to spam — receiving the same values twice is a
    -- no-op assignment.
    local is_server = Managers and Managers.player and Managers.player.is_server
    if is_server then
        local payload = {}
        for _, name in ipairs(SYNCED_SETTING_NAMES) do
            payload[name] = mod:get(name)
        end
        local ok, json = pcall(cjson.encode, payload)
        if not ok or type(json) ~= "string" then
            mod:info("[ct_sync] payload encode failed; not broadcasting")
            return
        end
        local json_len = #json
        local total = math.max(1, math.ceil(json_len / SYNC_CHUNK_SIZE))
        local session = math.floor(((Application and Application.time_since_launch and Application.time_since_launch()) or os.time()) * 1000) % 2147483647
        if session == 0 then session = 1 end
        for seq = 1, total do
            local start_i = (seq - 1) * SYNC_CHUNK_SIZE + 1
            local stop_i = math.min(start_i + SYNC_CHUNK_SIZE - 1, json_len)
            local chunk_str = string.sub(json, start_i, stop_i)
            mod:network_send("ct_sync_host_settings_chunk", "others", session, seq, total, chunk_str)
        end
        mod:info("[ct_sync] broadcast host settings to clients (session %d, %d chunks, %d bytes, %d keys)",
            session, total, json_len, #SYNCED_SETTING_NAMES)
        -- v0.7.64: also log the host's own manifest as a baseline so clients'
        -- replies can be diff'd against it in post-session log triage.
        local host_manifest = _build_local_manifest()
        _log_peer_manifest("self (host)", host_manifest, "HOST")
    end
end)

-- CLARIFY: Vanilla signature is `(seed, count, existing_power_ups, difficulty, run_progress, ...)`.
-- Rather than hard-coding count = args[2] (which would be brittle to future signature drift), the
-- code scans args for the first integer in [1,10] and assumes that's the count. `seed` is normally a
-- 32-bit hash > 10 so it won't collide.
-- QUESTION: Why detect by value range instead of just args[2]? If FatShark ever wraps this, the
-- scan also finds the count, but a non-default count outside [1,10] would silently be missed.
mod:hook("DeusPowerUpUtils", "generate_random_power_ups", function(func, ...)
    local args = { ... }

    local count_index
    for index, value in ipairs(args) do
        if type(value) == "number" and value >= 1 and value <= 10 then
            count_index = index
            break
        end
    end

    if count_index then
        local original = args[count_index]
        local custom_count

        -- CLARIFY: Only override when the original count matches a known default (4 = shrine, 3 =
        -- chest). This avoids hijacking other call sites that pass arbitrary counts (e.g., quest
        -- rewards, Belakor temple). If FatShark changes the defaults this silently no-ops.
        if original == SHRINE_DEFAULT then
            custom_count = effective_setting("shrine_boon_count")
        elseif original == CHEST_DEFAULT then
            custom_count = effective_setting("chest_boon_count")
        end

        if custom_count and custom_count ~= original then
            args[count_index] = custom_count
        end
    end

    -- v0.7.77: Belakor temple force-rarity — was a separate `mod:hook("DeusPowerUpUtils",
    -- "generate_random_power_ups", ...)` block at the old line 1387, which triggered the
    -- "Attempting to rehook active hook" VMF warning (same mod hooking the same Class+method
    -- twice). Consolidated into this single hook. Same logic: at the Belakor arena node, when
    -- a cursed_chest roll fires and the toggle is on, force `forced_rarity = "unique"` so the
    -- temple chest rewards uniques instead of the default `weight_by_rarity` mix.
    --
    -- Positional indices per vanilla signature
    -- `(seed, count, existing_power_ups, difficulty, run_progress, availability_type,
    --   career_name, forced_rarity)`:
    --   args[6] = availability_type
    --   args[8] = forced_rarity
    do
        local availability_type = args[6]
        local already_forced    = args[8]
        if not already_forced
            and availability_type == DeusPowerUpAvailabilityTypes.cursed_chest
            and effective_setting("tweak_belakor_temple_unique_boons")
        then
            local mechanism = Managers and Managers.mechanism and Managers.mechanism:game_mechanism()
            local run_controller = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
            local run_state = run_controller and run_controller._run_state
            if run_state and run_state.get_arena_belakor_node and run_state.get_current_node_key then
                local arena_node = run_state:get_arena_belakor_node()
                local current_node = run_state:get_current_node_key()
                if arena_node and current_node and arena_node == current_node then
                    args[8] = "unique"
                end
            end
        end
    end

    -- CLARIFY: Disabled-boon enforcement uses the "remove-then-restore" pattern: temporarily mutate
    -- the global pool, run the original sampler, then restore. This is safer than wrapping the
    -- sampler because vanilla's `generate_random_power_up` directly reads DeusPowerUpsArray /
    -- DeusPowerUpsArrayByRarity for both random and rarity-filtered selection.
    -- POTENTIAL BUG (LOW): If `func()` raises an error, restore code below never runs and disabled
    -- boons stay removed for the rest of the session. Consider wrapping in pcall for safety.
    local removed_main = {}
    local removed_rarity = {}

    -- Bomb-boon exclusivity: if the toggle is on AND the player already owns any bomb boon, also
    -- strip the rest from the pool for this roll. existing_power_ups is positionally args[3] in the
    -- vanilla signature (seed, count, existing_power_ups, ...).
    local exclude_bomb_boons = false
    if effective_setting("bomb_boon_exclusive") then
        local existing = args[3]
        if type(existing) == "table" then
            for _, pu in ipairs(existing) do
                if pu and pu.name and BOMB_BOON_NAMES[pu.name] then
                    exclude_bomb_boons = true
                    break
                end
            end
        end
    end

    if DeusPowerUpsArray then
        -- CLARIFY: Iterate backwards so table.remove indices stay stable. The saved `index` is the
        -- pre-removal slot, which is the correct insertion point for restoration in reverse order.
        for i = #DeusPowerUpsArray, 1, -1 do
            local boon = DeusPowerUpsArray[i]
            local name = boon and boon.name
            local key = name and ("disable_boon_" .. name)
            if (key and effective_setting(key)) or (exclude_bomb_boons and name and BOMB_BOON_NAMES[name]) then
                table.remove(DeusPowerUpsArray, i)
                removed_main[#removed_main + 1] = { index = i, boon = boon }
            end
        end
        if DeusPowerUpsArrayByRarity then
            for rarity, arr in pairs(DeusPowerUpsArrayByRarity) do
                removed_rarity[rarity] = {}
                for i = #arr, 1, -1 do
                    local boon = arr[i]
                    local name = boon and boon.name
                    local key = name and ("disable_boon_" .. name)
                    if (key and effective_setting(key)) or (exclude_bomb_boons and name and BOMB_BOON_NAMES[name]) then
                        table.remove(arr, i)
                        removed_rarity[rarity][#removed_rarity[rarity] + 1] = { index = i, boon = boon }
                    end
                end
            end
        end
    end

    local new_seed, new_power_ups = func(unpack(args))

    -- CLARIFY: Restore in reverse order of removal so that re-inserting at the saved indices
    -- reconstructs the original array exactly. `removed_main` was appended in descending-i order,
    -- so iterating it in reverse means we reinsert from the lowest index first.
    for i = #removed_main, 1, -1 do
        local e = removed_main[i]
        table.insert(DeusPowerUpsArray, e.index, e.boon)
    end
    for rarity, removed in pairs(removed_rarity) do
        local arr = DeusPowerUpsArrayByRarity[rarity]
        for i = #removed, 1, -1 do
            local e = removed[i]
            table.insert(arr, e.index, e.boon)
        end
    end

    -- CLARIFY: Re-applies the Khaine's Fury (deus_reckless_swings) tweak after every boon-roll. The
    -- engine may rebuild boon templates between rolls; this defensive call ensures the modified
    -- description and damage values stay in effect. on_setting_changed also calls this when the
    -- toggle flips.
    sync_reckless_swings()
    sync_bomb_cooldown()
    sync_boon_movespeed()

    return new_seed, new_power_ups
end)

-- CLARIFY: Workaround for a vanilla VT2 layout bug. When a shrine/cursed-chest only spawns ONE
-- widget on the arc, vanilla code computes the offset via `cos(angle) * radius` where `angle = 0/0`
-- (NaN from division-by-zero in degenerate single-element arc). The widget then renders at NaN
-- screen position and is invisible. Replacing NaN with 0 centers the single widget. NaN is detected
-- via `x ~= x` (the only value that isn't equal to itself in IEEE 754).
-- QUESTION: Why only fix the 1-widget case? If the issue can also occur for 0 or N>1 widgets, this
-- silently fails to repair them. May be intentional — maybe FatShark's layout only divides by zero
-- when count == 1.
local function fix_arc_nan(widgets)
    if not widgets or #widgets ~= 1 then
        return
    end

    local widget = widgets[1]
    if widget and widget.offset then
        if widget.offset[1] ~= widget.offset[1] then
            widget.offset[1] = 0
        end
        if widget.offset[2] ~= widget.offset[2] then
            widget.offset[2] = 0
        end
    end
end

mod:hook_safe("DeusShopView", "_create_ui_elements", function(self, shop_settings, power_ups, blessings)
    fix_arc_nan(self._shop_item_widgets)
    -- v0.7.67 diagnostic: log the blessings the shop is offering this visit. The
    -- 2026-05-20 session had blessing_of_power available at shop_strife but the
    -- user reported it "wasn't purchaseable" with zero buy attempts in logs. This
    -- captures whether the blessing was even in the offering pool, plus the buyer
    -- state at shop-open so we can tell from logs alone whether the button was
    -- already greyed out when the shop opened.
    if type(blessings) == "table" then
        local names = {}
        for i = 1, #blessings do names[i] = tostring(blessings[i]) end
        local with_buyer = self._deus_run_controller and self._deus_run_controller:get_blessings_with_buyer() or {}
        local buyer_dump = {}
        for k, v in pairs(with_buyer) do buyer_dump[#buyer_dump + 1] = tostring(k) .. "=" .. tostring(v) end
        mod:info("[miracle] DeusShopView opened type=%s blessings=[%s] already_bought={%s}",
            tostring(self._shop_type), table.concat(names, ","), table.concat(buyer_dump, ","))
    end
end)

mod:hook_safe("DeusCursedChestView", "create_ui_elements", function(self)
    fix_arc_nan(self._power_up_widgets)
end)

mod:hook("MutatorHandler", "_activate_mutator", function(func, self, name, ...)
    if is_curse_disabled(name) then
        return
    end
    return func(self, name, ...)
end)

mod:hook("DeusMechanism", "get_current_node_curse", function(func, self, ...)
    local curse = func(self, ...)
    if is_curse_disabled(curse) then
        return nil
    end
    return curse
end)

-- CLARIFY: Save-and-restore pattern for disabled curses. When transitioning into a node, vanilla
-- reads node.curse to spawn the curse mutator. We blank node.curse for the duration of the
-- transition so the mutator doesn't activate, then restore the original value so other code paths
-- (UI tooltips, save state, network sync) still see the canonical curse.
-- POTENTIAL BUG (LOW): If the wrapped `func` errors, restoration is skipped and node.curse stays
-- nil for the rest of the run. Same pattern repeats in start_next_round and _enable_hover.
mod:hook("DeusMechanism", "_transition_next_node", function(func, self, next_node_key, ...)
    -- v0.7.39: reset defeat-recovery flag on every level/node transition so each new
    -- mission gets its own one-shot rescue. Forward-declared variable lives near the
    -- defeat-recovery feature block.
    _defeat_recovery_triggered_this_round = false

    local run_controller = self._deus_run_controller
    local graph_data = run_controller and run_controller:get_graph_data()
    local node = graph_data and graph_data[next_node_key]
    local saved_curse = node and node.curse

    if saved_curse and is_curse_disabled(saved_curse) then
        node.curse = nil
    end

    local results = { func(self, next_node_key, ...) }

    if saved_curse and is_curse_disabled(saved_curse) then
        node.curse = saved_curse
    end

    return unpack(results)
end)

mod:hook("DeusMechanism", "start_next_round", function(func, self, ...)
    local run_controller = self._deus_run_controller
    local current_node = run_controller and run_controller:get_current_node()
    local saved_curse = current_node and current_node.curse
    local saved_theme = current_node and current_node.theme

    -- CLARIFY: Forcing theme="wastes" prevents the curse-themed visuals/lighting from loading even
    -- though node.curse is suppressed. Without this, the engine could still load curse aesthetic
    -- assets keyed off node.theme (e.g., "tzeentch", "khorne") and produce mismatched visuals.
    if saved_curse and is_curse_disabled(saved_curse) then
        current_node.curse = nil
        current_node.theme = "wastes"
    end

    local results = { func(self, ...) }

    if saved_curse and is_curse_disabled(saved_curse) then
        current_node.curse = saved_curse
        current_node.theme = saved_theme
    end

    return unpack(results)
end)

-- CLARIFY: Suppresses the curse-themed hover preview on the map for nodes whose curse is disabled.
-- Sets theme=nil so the hover view shows the default "wastes" preview instead of (e.g.) the
-- Tzeentch-themed curse preview, accurately reflecting that the player won't experience the curse.
-- POTENTIAL BUG (LOW): Inconsistent return semantics — the disabled-curse path returns nothing
-- (implicit nil), the normal path returns whatever func returns. If a future caller relies on the
-- return value, the disabled path silently differs.
mod:hook("DeusMapDecisionView", "_enable_hover", function(func, self, node_key, ...)
    local graph_data = self._deus_run_controller and self._deus_run_controller:get_graph_data()
    local node = graph_data and graph_data[node_key]

    if node and is_curse_disabled(node.curse) then
        local saved_theme = node.theme
        node.theme = nil
        func(self, node_key, ...)
        node.theme = saved_theme
        return
    end

    return func(self, node_key, ...)
end)

-- CLARIFY: Custom altar distribution for chests. Vanilla `get_deus_weapon_chest_type` lazily builds
-- self._deus_weapon_chest_distribution from the level's deus_weapon_chest_distribution table on
-- first call per node, then pops one entry per call. We intercept the FIRST call (when distribution
-- is empty), build our own custom distribution if any altar setting is non-zero, write it to
-- self._deus_weapon_chest_distribution, pop one entry, and return it. Subsequent calls find a
-- non-empty distribution and we fall through to vanilla which pops the rest.
-- The custom distribution overrides the entire chest contents — types left at 0 simply don't appear.
-- Filter unknown rarities out of get_own_weapon_pool_excludes. Vanilla
-- `DeusRunController.get_weapon_pool` (line 2130-2134) iterates pool_excludes
-- as the source of truth and does `weapon_pool[pool_rarity][...] = nil`, but
-- weapon_pool only contains the vanilla rarities (plentiful/common/exotic/unique).
-- If a sibling mod (e.g. Peregrinaje) wrote a custom rarity like "modded" to
-- pool_excludes and is no longer active, the `weapon_pool["modded"]` lookup is
-- nil and the indexing crashes with "attempt to index a nil value" inside chest
-- generation (deus_chest_extension.lua:_generate_stored_weapon).
-- We strip non-standard rarities from the returned table so vanilla doesn't trip.
local _VANILLA_RARITIES = { plentiful = true, common = true, exotic = true, unique = true }
mod:hook("DeusRunController", "get_own_weapon_pool_excludes", function(func, self, ...)
    local excludes = func(self, ...)
    if type(excludes) ~= "table" then return excludes end
    for rarity in pairs(excludes) do
        if not _VANILLA_RARITIES[rarity] then
            mod:info("[weapon-pool] stripped unknown rarity '%s' from pool_excludes", tostring(rarity))
            excludes[rarity] = nil
        end
    end
    return excludes
end)

mod:hook("DeusRunController", "get_deus_weapon_chest_type", function(func, self)
    local distribution = self._deus_weapon_chest_distribution

    if (not distribution or #distribution == 0) and DEUS_CHEST_TYPES then
        -- v0.7.42: effective_setting so client's chest opens see host's distribution.
        -- v0.7.65: sentinel -1 = "Default" (use vanilla random distribution). 0 = literal
        -- zero altars of this type. is_custom is true if ANY altar setting is not the
        -- sentinel (the user has expressed an override). For altars set to Default in a
        -- mixed config (one type explicit, others "Default"), the Default ones contribute
        -- ZERO to the override distribution — explicit per-type control. If users want
        -- vanilla random behavior, ALL four must be "Default".
        local upgrade = effective_setting("chest_upgrade_count") or -1
        local swap_melee = effective_setting("chest_swap_melee_count") or -1
        local swap_ranged = effective_setting("chest_swap_ranged_count") or -1
        local power_up = effective_setting("chest_power_up_count") or -1

        local is_custom = upgrade ~= -1 or swap_melee ~= -1 or swap_ranged ~= -1 or power_up ~= -1
        if is_custom then
            local function as_count(v) return (v == -1) and 0 or v end
            local new_distribution = {}
            for _ = 1, as_count(upgrade)    do new_distribution[#new_distribution + 1] = DEUS_CHEST_TYPES.upgrade    end
            for _ = 1, as_count(swap_melee) do new_distribution[#new_distribution + 1] = DEUS_CHEST_TYPES.swap_melee end
            for _ = 1, as_count(swap_ranged)do new_distribution[#new_distribution + 1] = DEUS_CHEST_TYPES.swap_ranged end
            for _ = 1, as_count(power_up)   do new_distribution[#new_distribution + 1] = DEUS_CHEST_TYPES.power_up   end

            if #new_distribution > 0 then
                -- CLARIFY: Seeding the shuffle with the node's level_seed ensures deterministic
                -- altar order across host/clients on the same node. Falls back to seed=0 if any
                -- intermediate is nil (defensive — shouldn't normally happen since this hook only
                -- fires inside an active run).
                local run_state = self._run_state
                local node_key = run_state and run_state:get_current_node_key()
                local graph = self:_get_graph_data()
                local node = graph and node_key and graph[node_key]
                local seed = node and HashUtils and HashUtils.fnv32_hash(node.level_seed) or 0
                table.shuffle(new_distribution, seed)

                self._deus_weapon_chest_distribution = new_distribution
                local chest_type = new_distribution[#new_distribution]
                new_distribution[#new_distribution] = nil
                return chest_type
            end
        end
    end

    return func(self)
end)

-- CLARIFY: Builds the union of all trait-combinations across all CW weapons, deduplicated. Used
-- when "Any Trait on Any Weapon" is enabled — every weapon gets the FULL pool of trait combos
-- instead of its baked subset. The dedupe key uses "\0" as separator since trait names can't
-- contain null bytes; this avoids ambiguity (e.g. `{"a","bc"}` vs `{"ab","c"}`).
-- POTENTIAL BUG (LOW): The cache is never invalidated. If DeusWeapons is mutated after first call
-- (e.g. by another mod), stale combos persist. Acceptable since DeusWeapons is normally static.
local function get_all_trait_combos()
    if all_trait_combos_cache then
        return all_trait_combos_cache
    end
    if not DeusWeapons then
        return nil
    end

    local combos = {}
    local seen = {}
    for _, data in pairs(DeusWeapons) do
        local baked = data.baked_trait_combinations
        if baked then
            for _, combo in ipairs(baked) do
                local key = table.concat(combo, "\0")
                if not seen[key] then
                    seen[key] = true
                    combos[#combos + 1] = combo
                end
            end
        end
    end

    all_trait_combos_cache = combos
    return combos
end

-- CLARIFY: Trait filter has three behaviors based on the `any_trait_any_weapon` toggle and the
-- ban list. The base pool is either the weapon's vanilla trait combos or the global expanded pool.
-- Then any combo containing a banned trait is removed from `filtered`.
-- The new_value selection logic:
--   - filtered partially shrunk (some bans hit, some left): use filtered
--   - filtered emptied (every combo had a ban): keep `base` so the weapon isn't unrollable —
--     a fully-banned weapon would crash the upgrade UI when no traits can be picked
--   - filtered unchanged but `expanded_pool` differs from original: use base (= expanded_pool)
--   - filtered unchanged and base==original: skip (no patch needed)
-- POTENTIAL BUG (LOW): When `filtered` is empty, falling back to `base` means banned traits CAN
-- still appear on that weapon. This is a reasonable graceful-degradation choice but the UI tooltip
-- doesn't tell the user.
local function apply_weapon_trait_filter()
    if not DeusWeapons then
        return {}
    end

    local any_trait = effective_setting("any_trait_any_weapon")
    local expanded_pool = any_trait and get_all_trait_combos()
    local saved = {}

    for item_key, data in pairs(DeusWeapons) do
        local original = data.baked_trait_combinations
        local base = expanded_pool or original
        if base then
            local filtered = {}
            for _, combo in ipairs(base) do
                local keep = true
                for _, trait in ipairs(combo) do
                    if effective_setting("ban_trait_" .. trait) then
                        keep = false
                        break
                    end
                end
                if keep then
                    filtered[#filtered + 1] = combo
                end
            end

            local new_value
            if #filtered < #base and #filtered > 0 then
                new_value = filtered
            elseif #filtered == 0 then
                new_value = base
            elseif base ~= original then
                new_value = base
            end

            if new_value and new_value ~= original then
                saved[item_key] = original
                data.baked_trait_combinations = new_value
            end
        end
    end

    return saved
end

local function restore_weapon_trait_filter(saved)
    if not DeusWeapons then
        return
    end

    for item_key, original in pairs(saved) do
        DeusWeapons[item_key].baked_trait_combinations = original
    end
end

-- ============================================================
-- Trait Tier by Rarity (v0.7.28a-alpha)
-- ============================================================
-- TRAIT_RARITY_POOL: maps every weapon trait → set of rarities at which it can roll.
-- Walked all 34 traits with the user 2026-05-15; basis lives in TRAITS_REFERENCE.md.
-- T1=common (green), T2=rare (blue), T3=exotic (orange), T4=unique (red).
-- Multi-tier means the trait is eligible in multiple rarity pools.
--
-- When `tweak_trait_tier_by_rarity` is on, every weapon roll/upgrade picks a trait
-- combo whose ALL traits are eligible for the rolled rarity. Implementation: hook the
-- public DeusWeaponGeneration methods, call vanilla, then overwrite result.traits with
-- a tier-filtered random pick. This ALSO enables traits at common/rare rarities (which
-- vanilla skips per `deus_weapon_generation.lua:166-169`) because we don't rely on the
-- vanilla rarity gate — we pick from the original baked_trait_combinations and filter.
local TRAIT_RARITY_POOL = {
    -- T1 only (common / green)
    melee_increase_damage_on_block                = { common = true },
    melee_reduce_cooldown_on_crit                 = { common = true },
    melee_shield_on_assist                        = { common = true },
    melee_timed_block_cost                        = { common = true },
    ranged_reduce_cooldown_on_crit                = { common = true },
    ranged_restore_stamina_headshot               = { common = true },
    shield_splinters                              = { common = true },
    deus_ammo_pickup_reload_speed                 = { common = true },
    deus_big_swing_stagger                        = { common = true },
    -- T2 only (rare / blue)
    melee_heal_on_crit                            = { rare = true },
    ranged_consecutive_hits_increase_power        = { rare = true },
    ranged_increase_power_level_vs_armour_crit    = { rare = true },
    ranged_reduced_overcharge                     = { rare = true },
    ranged_remove_overcharge_on_crit              = { rare = true },
    melee_counter_push_power                      = { rare = true },
    bloodthirst                                   = { rare = true },
    headhunter                                    = { rare = true },
    follow_up                                     = { rare = true },
    -- T3 only (exotic / orange)
    shield_of_isha                                = { exotic = true },
    stagger_aoe_on_crit                           = { exotic = true },
    serrated_blade                                = { exotic = true },
    melee_attack_speed_on_crit                    = { exotic = true },
    -- T4 only (unique / red)
    armor_breaker                                 = { unique = true },
    refilling_shot                                = { unique = true },
    home_run                                      = { unique = true },
    deus_crit_chain_lightning                     = { unique = true },
    deus_extra_shot                               = { unique = true },
    always_blocking                               = { unique = true },
    -- T2 + T3
    ranged_replenish_ammo_on_crit                 = { rare = true,   exotic = true },
    ranged_replenish_ammo_headshot                = { rare = true,   exotic = true },
    -- T3 + T4
    piercing_projectiles                          = { exotic = true, unique = true },
    crescendo_strike                              = { exotic = true, unique = true },
    deus_collateral_damage_on_melee_killing_blow  = { exotic = true, unique = true },
    deus_ranged_crit_explosion                    = { exotic = true, unique = true },
}

local function get_tier_filtered_combos(item_key, rarity)
    if not DeusWeapons or not DeusWeapons[item_key] then return {} end
    local original = DeusWeapons[item_key].baked_trait_combinations
    if not original then return {} end
    local filtered = {}
    for _, combo in ipairs(original) do
        local all_eligible = true
        for _, trait in ipairs(combo) do
            local pool = TRAIT_RARITY_POOL[trait]
            if not pool or not pool[rarity] then
                all_eligible = false
                break
            end
        end
        if all_eligible then
            filtered[#filtered + 1] = combo
        end
    end
    return filtered
end

-- Post-process the result of a vanilla weapon generation/upgrade: overwrite result.traits
-- with a tier-eligible combo for the rolled rarity. No-op if:
--   - the toggle is off
--   - result is nil or has no deus_item_key
--   - no tier-eligible combos exist for this weapon at this rarity
-- The no-tier-combos guard means weapons with no T1 traits available won't suddenly get
-- assigned an out-of-tier trait at common rarity — they keep vanilla behavior (no traits).
local function override_traits_in_result(result, rarity)
    if not effective_setting("tweak_trait_tier_by_rarity") then return result end
    if not result or not result.deus_item_key then return result end
    local combos = get_tier_filtered_combos(result.deus_item_key, rarity)
    if #combos == 0 then return result end
    local picked = combos[math.random(#combos)]
    local new_traits = {}
    for _, trait in ipairs(picked) do
        new_traits[#new_traits + 1] = trait
    end
    result.traits = new_traits
    return result
end

-- CLARIFY: Three trait-filter wrap points cover the three vanilla call sites that read
-- baked_trait_combinations: initial weapon roll, slot-specific roll (Belakor temple?), and altar
-- upgrade. Same save/restore pattern as the boon hooks above.
-- POTENTIAL BUG (LOW): Same as boon-removal — if `func()` errors, restore is skipped and DeusWeapons
-- stays mutated. pcall would harden this.
-- v0.7.28a: each hook now ALSO post-processes with `override_traits_in_result` to apply tier-by-rarity.
mod:hook("DeusWeaponGeneration", "generate_weapon", function(func, difficulty, run_progress, rarity, ...)
    local saved = apply_weapon_trait_filter()
    local result = func(difficulty, run_progress, rarity, ...)
    restore_weapon_trait_filter(saved)
    return override_traits_in_result(result, rarity)
end)

mod:hook("DeusWeaponGeneration", "generate_weapon_for_slot", function(func, difficulty, run_progress, rarity, ...)
    local saved = apply_weapon_trait_filter()
    local result = func(difficulty, run_progress, rarity, ...)
    restore_weapon_trait_filter(saved)
    return override_traits_in_result(result, rarity)
end)

mod:hook("DeusWeaponGeneration", "generate_item_from_item_key", function(func, item_key, difficulty, run_progress, rarity, ...)
    local saved = apply_weapon_trait_filter()
    local result = func(item_key, difficulty, run_progress, rarity, ...)
    restore_weapon_trait_filter(saved)
    return override_traits_in_result(result, rarity)
end)

mod:hook("DeusWeaponGeneration", "upgrade_item", function(func, item, difficulty, run_progress, target_rarity, ...)
    local saved = apply_weapon_trait_filter()
    local result = func(item, difficulty, run_progress, target_rarity, ...)
    restore_weapon_trait_filter(saved)
    return override_traits_in_result(result, target_rarity)
end)

-- Upstream override for `force_belakor` (v0.7.49). Vanilla `game_round_ended` calls
-- `deus_backend:deus_journey_with_belakor(journey_name)` to compute the `with_belakor`
-- flag, then uses that single value for BOTH `_setup_run` (host local state) AND
-- `send_rpc_clients("rpc_deus_setup_run", ..., with_belakor, ...)` (client state). Hooking
-- the source makes the override propagate to both paths, so clients see the Belakor curse
-- on Holseher's map when the host has the toggle on. Host-only — `deus_journey_with_belakor`
-- is only invoked on the run host (in `game_round_ended`) and from UI views which are
-- read by the local player only; mutating it for a client would silently desync.
mod:hook("BackendInterfaceDeusPlayFab", "deus_journey_with_belakor", function(func, self, journey_name)
    local is_server = Managers and Managers.player and Managers.player.is_server
    if is_server and mod:get("force_belakor") then
        return true
    end
    return func(self, journey_name)
end)

-- v0.7.75: Belakor's Temple → unique-tier boon rewards.
-- The temple is the `arena_belakor` node on the Wastes graph. Completing it triggers a
-- cursed_chest reward roll via the standard cursed-chest UI; vanilla `weight_by_rarity`
-- is `{ event=6, exotic=3, rare=6, unique=1 }` for cursed chests, so the temple often
-- rewards rare/exotic boons even though uniques are in the pool. Lore-wise, Belakor's
-- temple is meant to be the prestige reward — uniques should be the default.
--
-- Hook target: `DeusPowerUpUtils.generate_random_power_ups` (the util, not the
-- DeusRunController wrapper). The util takes a `forced_rarity` parameter which already
-- implements the "fall back to adjacent tiers if pool is empty" semantics we want
-- (deus_power_up_utils.lua:192-215 walks event→rare→exotic→unique and then back up
-- only when no entries are available). We pass `"unique"` when the conditions match.
--
-- Conditions:
--   - Toggle on (`tweak_belakor_temple_unique_boons`, default ON).
--   - Availability type is `cursed_chest` (the temple chest is a cursed chest).
--   - The current node is the run's Belakor arena node, queried via
--     `_run_state:get_arena_belakor_node()` + `:get_current_node_key()`.
--
-- We do NOT mutate `DeusPowerUpSettings.weight_by_rarity` — that's the boot-time table
-- and any mutation would affect every other cursed/weapon chest in the run. Forcing
-- the rarity through the function parameter is local to this single call. Per
-- `feedback_vt2_gated_registration_diverges.md`, this is gate-at-roll-time, not
-- gate-at-registration-time — no peer-index divergence.
--
-- Per-peer note: each peer rolls its own seed when opening the cursed chest
-- (`deus_cursed_chest_view.lua:58` uses position-derived hash), so the hook runs on
-- each player's machine independently. No host-authority concern — the boon CHOICE
-- isn't sync'd, only the resulting `add_power_up` RPC is.
-- v0.7.77: Belakor-temple force-rarity logic was previously a SECOND mod:hook on
-- DeusPowerUpUtils.generate_random_power_ups, which triggered the
-- "Attempting to rehook active hook" VMF warning (same mod hooking the same
-- Class+method twice). Consolidated into the single hook at line ~783 above —
-- see the "v0.7.77: Belakor temple force-rarity" comment block inside that
-- function body. The semantics are identical: at the Belakor arena node, when
-- a cursed_chest roll fires and the toggle is on, force unique rarity.

-- v0.7.53: Upstream override for `finale_dominant_god`. Same bug shape as the old
-- `force_belakor` issue (fixed in v0.7.49): `game_round_ended` reads
-- `self._vote_data.dominant_god` into a local at the top, then uses it for BOTH
-- `_setup_run` AND `send_rpc_clients(..., dominant_god_id, ...)`. The previous
-- `_setup_run` hook only changed the value INSIDE `_setup_run` — host's local run state
-- saw the override but the RPC payload kept the original god, so clients populated their
-- graph with vanilla god distribution. Fix: pre-mutate `self._vote_data.dominant_god`
-- before vanilla `game_round_ended` runs, restore after. Both paths then see the override.
--
-- Restore-on-return is critical: vote_data persists on `self` and is consumed once per
-- mission-start; leaving it mutated would survive across rounds.
mod:hook("DeusMechanism", "game_round_ended", function(func, self, t, dt, reason, reason_data)
    local is_server = Managers and Managers.player and Managers.player.is_server
    local restored = false
    local original_god
    local vote_data = self._vote_data
    if reason == "start_game" and is_server and vote_data then
        local god_index = mod:get("finale_dominant_god")
        if god_index and god_index > 0 then
            local god = FINALE_GODS[god_index]
            if god then
                original_god = vote_data.dominant_god
                vote_data.dominant_god = god
                restored = true
            end
        end
    end

    local ok, err = pcall(func, self, t, dt, reason, reason_data)

    if restored then
        vote_data.dominant_god = original_god
    end

    if not ok then
        error(err, 0)
    end
end)

-- CLARIFY: Patches LevelSettings[level].pickup_settings to control the COUNT of altars/cursed
-- chests/arena ammo crates spawned per mission. This works alongside `get_deus_weapon_chest_type`
-- which controls the TYPE distribution within each chest. Net effect:
--   - altar_total > 0: spawn this many altars total (types determined by chest_*_count proportions)
--   - cursed_count != 1: override cursed-chest count (vanilla = 1)
--   - arena_ammo != 2: override arena ammo box count (vanilla = 2)
--   - potions_on: inject campaign damage/speed/CDR potions into Pickups.deus_potions for this mission
-- All settings save/restore around `func()` so vanilla values are preserved between runs.
-- POTENTIAL BUG (LOW): Same `func` error → state leak issue as boon/trait hooks. If `func()` raises,
-- pickup_settings stays mutated AND added_potions clones leak in Pickups.deus_potions.
--
-- Per-level counter for tome/grim → Chest of Trials conversions. Declared here (not
-- where the conversion hook below uses it) because Lua 5.1 closures bind locals
-- lexically AT CREATION TIME — placing the `local` after the hook would make the
-- earlier reference resolve to a global (per feedback_lua_forward_reference.md).
-- Reset is performed at the top of THIS hook (consolidated to avoid the VMF
-- "Attempting to rehook active hook" warning for populate_pickups).
local _CAMPAIGN_POTION_NAMES = { "damage_boost_potion", "speed_boost_potion", "cooldown_reduction_potion" }
local _chest_conversions_this_level = 0
-- v0.7.55: per-level Belakor altar tracker. Lua 5.1 closure binding rules require this
-- be declared BEFORE the _spawn_guaranteed_pickup hook reads it. Reset at the top of
-- the consolidated populate_pickups hook (alongside _chest_conversions_this_level).
local _belakor_altar_spawned_this_level = false
mod:hook("PickupSystem", "populate_pickups", function(func, self, ...)
    _chest_conversions_this_level = 0
    if not LevelHelper then
        return func(self, ...)
    end

    -- v0.7.42: effective_setting so each peer's populate_pickups mutation uses host's values.
    -- v0.7.65: sentinel -1 = "Default" (use vanilla random/count) — distinct from 0 which means
    -- "literally zero." `as_count(-1) = 0` for the altar TOTAL sum (a Default altar contributes
    -- 0 to the override total) but `altar_custom` triggers on ANY non-sentinel value.
    local function _as_count(v) return (v == -1) and 0 or v end
    local upgrade_c    = effective_setting("chest_upgrade_count")    or -1
    local swap_melee_c = effective_setting("chest_swap_melee_count") or -1
    local swap_ranged_c= effective_setting("chest_swap_ranged_count")or -1
    local power_up_c   = effective_setting("chest_power_up_count")   or -1
    local altar_total = _as_count(upgrade_c) + _as_count(swap_melee_c) + _as_count(swap_ranged_c) + _as_count(power_up_c)
    local altar_any_explicit = upgrade_c ~= -1 or swap_melee_c ~= -1 or swap_ranged_c ~= -1 or power_up_c ~= -1
    local cursed_count_raw = effective_setting("cursed_chest_count") or -1
    local cursed_count = _as_count(cursed_count_raw)
    local arena_ammo_raw = effective_setting("arena_ammo_count") or -1
    local arena_ammo = _as_count(arena_ammo_raw)
    local potions_on = effective_setting("enable_campaign_potions")  -- v0.7.64: now host-synced

    -- Defensive cleanup: if a previous populate_pickups call errored mid-flight
    -- with potions_on=true, the campaign-potion clones could remain in
    -- Pickups.deus_potions for the rest of the session. Scrub them every call
    -- when the toggle is off so subsequent missions don't see ghost potions.
    if not potions_on and Pickups and Pickups.deus_potions then
        for _, name in ipairs(_CAMPAIGN_POTION_NAMES) do
            Pickups.deus_potions[name] = nil
        end
    end

    -- v0.7.65: "custom" gates determine which fields to mutate. Sentinel -1 = "Default" =
    -- skip override. Explicit values (including 0 = literally zero) trigger override.
    -- Pre-0.7.65 the gates compared to vanilla defaults (1, 2) — that's gone because the
    -- new sentinel makes "use vanilla" the explicit choice, not "happens to match vanilla."
    local altar_custom = altar_any_explicit
    local cursed_custom = cursed_count_raw ~= -1
    local ammo_custom = arena_ammo_raw ~= -1

    -- v0.7.55: reset per-level Belakor altar tracker. Used by the tome/grim hook so
    -- only the first book spot after all Chests of Trials are placed gets the altar
    -- (one altar per mission, like vanilla belakor-themed CW levels which request
    -- `deus_02 = 1`). The altar is no longer requested via populate_pickups primary
    -- (which placed it in a random ammo/healing spot); routing through book spots
    -- means it shares the same pedestal a chest would have used, per user spec.
    _belakor_altar_spawned_this_level = false

    if not altar_custom and not cursed_custom and not ammo_custom and not potions_on then
        return func(self, ...)
    end

    -- CLARIFY: Detect arena (finale) vs normal levels. Arena levels have no `deus_weapon_chest` key
    -- but DO have `ammo`; normal levels have `deus_weapon_chest` and `deus_cursed_chest`. The
    -- detection lets one hook handle both level types correctly.
    local saved = {}
    local current = LevelHelper:current_level_settings()
    local pickup_settings = current and current.pickup_settings
    if pickup_settings then
        for _, difficulty_data in pairs(pickup_settings) do
            if type(difficulty_data) == "table" and difficulty_data.primary then
                local primary = difficulty_data.primary
                local is_arena = primary.deus_weapon_chest == nil
                local entry = { tbl = primary }

                if not is_arena then
                    if altar_custom and primary.deus_weapon_chest ~= nil then
                        entry.deus_weapon_chest = primary.deus_weapon_chest
                        primary.deus_weapon_chest = altar_total
                    end
                    if cursed_custom and primary.deus_cursed_chest ~= nil then
                        entry.deus_cursed_chest = primary.deus_cursed_chest
                        primary.deus_cursed_chest = cursed_count
                    end
                elseif ammo_custom and primary.ammo ~= nil then
                    entry.ammo = primary.ammo
                    primary.ammo = arena_ammo
                end

                -- CLARIFY: Only push to `saved` if at least one field was mutated, so the restore
                -- loop below is a no-op for unchanged entries.
                if entry.deus_weapon_chest ~= nil or entry.deus_cursed_chest ~= nil or entry.ammo ~= nil then
                    saved[#saved + 1] = entry
                end
            end
        end
    end

    local added_potions = {}
    -- Saved spawn_weightings keyed by pickup_name. We renormalize the entire deus_potions
    -- group below so the inserted campaign potions are actually reachable by the sampler;
    -- both the inserts AND the originals get restored after vanilla populate_pickups runs.
    local saved_weights = {}
    if potions_on and Pickups and Pickups.deus_potions and Pickups.potions then
        -- Step 1: insert campaign potion clones using their NATIVE Pickups.potions weight
        -- (so each entry contributes ~0.33 to the running total). We'll renormalize after.
        for _, name in ipairs({ "damage_boost_potion", "speed_boost_potion", "cooldown_reduction_potion" }) do
            if Pickups.potions[name] and not Pickups.deus_potions[name] then
                local clone = table.clone(Pickups.potions[name])
                Pickups.deus_potions[name] = clone
                added_potions[#added_potions + 1] = name
            end
        end

        -- Step 2: renormalize ALL entries in Pickups.deus_potions so they sum to 1.0.
        -- Without this, the sampler in pickup_system.lua _spawn_spread_pickups picks
        -- random[0,1) and breaks on first cumulative >= random — entries past
        -- cumulative 1.0 are unreachable. CW potions were already normalized to sum
        -- ~1.0 at engine startup; adding 3 campaign entries pushed the total to ~1.375
        -- and made some entries (depending on `pairs` iteration order, which is
        -- unspecified in Lua 5.1) silently never spawn.
        local total = 0
        for name, settings in pairs(Pickups.deus_potions) do
            if settings and settings.spawn_weighting then
                saved_weights[name] = settings.spawn_weighting
                total = total + settings.spawn_weighting
            end
        end
        if total > 0 then
            for name, settings in pairs(Pickups.deus_potions) do
                if saved_weights[name] then
                    settings.spawn_weighting = saved_weights[name] / total
                end
            end
        end
    end

    local results = { func(self, ...) }

    for _, entry in ipairs(saved) do
        local primary = entry.tbl
        if entry.deus_weapon_chest ~= nil then primary.deus_weapon_chest = entry.deus_weapon_chest end
        if entry.deus_cursed_chest ~= nil then primary.deus_cursed_chest = entry.deus_cursed_chest end
        if entry.ammo ~= nil then primary.ammo = entry.ammo end
    end

    -- Restore CW potion weights to their pre-renormalization values, then drop the
    -- inserted campaign clones. Order matters: restore first so we don't briefly leave
    -- weights in an inconsistent state if anything else reads Pickups.deus_potions.
    for name, original in pairs(saved_weights) do
        local entry = Pickups.deus_potions[name]
        if entry then entry.spawn_weighting = original end
    end
    for _, name in ipairs(added_potions) do
        Pickups.deus_potions[name] = nil
    end

    return unpack(results)
end)

-- ============================================================
-- Tome / Grimoire → Chest of Trials substitution
-- ============================================================

-- CLARIFY: Adventure levels injected into the CW map pool (see _adventure_pool.lua) have
-- tome/grimoire pickup_spawner units baked into the level bundle. On an injected adventure
-- level we want those positions to spawn a Chest of Trials (deus_cursed_chest) instead.
--
-- Vanilla PickupSystem._spawn_guaranteed_pickup (pickup_system.lua:821-844) iterates AllPickups
-- and filters via _can_spawn, which reads Unit.get_data(spawner, pickup_name). Tome spawners
-- have only `tome = true` set; grimoire spawners only `grimoire = true`. We detect those flags
-- and short-circuit to spawn deus_cursed_chest directly.
--
-- Gated on IS_INJECTED_ADVENTURE_LEVEL[base_level_name] so vanilla CW levels (no tomes/grims)
-- and stock adventure runs (when CW pool injection is off) are completely unaffected.

-- Reverse-match a permutation or duplicate-alias key back to its injected adventure base.
-- Returns the base key (e.g. "bell") if level_key matches an injected adventure, else nil.
-- Handles three formats:
--   "bell"                       (raw base)
--   "bell_khorne_path1"          (per-theme permutation)
--   "bell_dup1_khorne_path1"     (duplicate-alias permutation)
local function adventure_base_from_level_key(level_key)
    if type(level_key) ~= "string" or not AdventurePool then return nil end
    for base in pairs(AdventurePool.IS_INJECTED_ADVENTURE_LEVEL) do
        if level_key == base or level_key:find("^" .. base .. "_") then
            return base
        end
    end
    return nil
end

local function on_injected_adventure_level()
    if not LevelHelper then return false end
    local current = LevelHelper:current_level_settings()
    return current and adventure_base_from_level_key(current.level_id) ~= nil
end

-- Lookup table: <adv_base_key>_title → display name. Used to satisfy the CW map UI
-- which constructs the title localization key ad-hoc at deus_map_ui_v2.lua:593 as
-- `Localize(level .. "_title")`, ignoring LevelSettings[<perm>].display_name entirely.
-- Without this hook the map shows "<elven_ruins_title>" / "<bell_title>" etc.
-- We also intercept `_desc` for the same reason (line 594).
local ADV_TITLE_OVERRIDES = {}
local ADV_DESC_OVERRIDES = {}
do
    local function add(key, title, desc)
        ADV_TITLE_OVERRIDES[key .. "_title"] = title
        ADV_DESC_OVERRIDES[key .. "_desc"] = desc
    end
    for _, m in ipairs(AdventurePool.ADVENTURE_MISSIONS) do
        -- title shown on the node icon hover; desc shown below it.
        add(m.key, m.name, m.name)
    end
end

-- Mod Boon localization overrides (v0.7.30). The 4 ct-injected meta boons reference
-- `display_name_ct_meta_*` and `description_ct_meta_*` localization keys in their
-- DeusPowerUpTemplates entries. Vanilla Localize() returns `<key>` for keys it doesn't
-- know — so the in-game boon UI would show "<display_name_ct_meta_stagger>" unless we
-- intercept and provide the strings. Each `%` is escaped as `%%` because vanilla's
-- UIUtils.format_localized_description re-feeds via string.format (see
-- feedback_vt2_localize_string_format_pipeline.md).
local MOD_BOON_LOC = {
    display_name_ct_meta_stagger = "(Mod Boon) Reactive Bulwark",
    description_ct_meta_stagger  = "+1%% stagger power and +1%% melee cleave per active boon.",
    display_name_ct_meta_crit    = "(Mod Boon) Crit Cascade",
    description_ct_meta_crit     = "+1%% critical strike chance and +5%% critical strike effectiveness per active boon.",
    display_name_ct_meta_health  = "(Mod Boon) Vitality Cascade",
    description_ct_meta_health   = "+1%% max health and +1%% healing received per active boon.",
    display_name_ct_meta_cooldown = "(Mod Boon) Ability Cascade",
    description_ct_meta_cooldown = "+2%% cooldown regen per active boon.",
    display_name_ct_meta_movespeed = "(Mod Boon) Wind Cascade",
    description_ct_meta_movespeed  = "+1%% movement speed per active boon.",
    display_name_ct_meta_ammo      = "(Mod Boon) Quiver Cascade",
    description_ct_meta_ammo       = "+5%% total ammo, +5%% max overheat (Sienna staves, Bardin drakefire), and +5%% Moonfire Bow energy capacity per active boon. May Khaine's quivers and Vaul's forges fill in equal measure.",
    display_name_ct_kill_heal    = "(Mod Boon) Khaine's Communion",
    description_ct_kill_heal     = "Killing an enemy heals you for 1 health.",

    -- v0.7.34 Trait-as-Boon
    display_name_ct_boon_vauls_anvil         = "(Mod Boon) Vaul's Anvil",
    description_ct_boon_vauls_anvil          = "All attacks against you count as blocked while your melee weapon is wielded. Block break disables this for 10 seconds.",
    display_name_ct_boon_manann_tempest      = "(Mod Boon) Manann's Tempest",
    description_ct_boon_manann_tempest       = "Critical strikes trigger a chain lightning that jumps to up to 5 nearby enemies, ignoring armour. Stacks with the trait.",
    display_name_ct_boon_taal_twinned_arrow  = "(Mod Boon) Taal's Twinned Arrow",
    description_ct_boon_taal_twinned_arrow   = "Ranged attacks fire one additional projectile. Stacks with the trait. Has no effect without a ranged weapon.",
    display_name_ct_boon_asuryan_wrath       = "(Mod Boon) Asuryan's Wrath",
    description_ct_boon_asuryan_wrath        = "Melee kills have a 50%% chance to deal the killing blow's damage to a nearby enemy. Stacks with the trait.",

    -- v0.7.33 typo fix: vanilla description for Addaioth's Splendour (deus_ranged_crit_explosion
    -- trait) claims "Every 30 seconds" but the actual cooldown_duration in buff_tweak_data.lua:344
    -- is 10. Vanilla's loc string swapped the cooldown (10) and damage percent (30) when filling
    -- description_values positionally. Override returns a static, correct string.
    description_deus_ranged_crit_explosion_trait = "Every 10 seconds, ranged Critical Hits explode in an area for 30%% of their Damage. Deals damage scaled by Hero Power. Staggers nearby enemies.",
}

-- Consolidated _G.Localize hook. VMF warns "Attempting to rehook active hook" if the
-- same target is hooked twice — only the second binding survives and shadows the first.
-- Two purposes live here:
--   1. Adventure-mission titles/descriptions used by deus_map_ui_v2.lua:593's
--      ad-hoc `Localize(level .. "_title")` lookup. Without this, injected
--      adventure nodes render as "<elven_ruins_title>" on Olesya's map.
--   2. Khaine's Fury (deus_reckless_swings) description override when the user has
--      `tweak_reckless_swings` enabled. Vanilla format string is "While above 50% …";
--      we substitute "25% / 1 damage" verbatim. Percent signs MUST be `%%` because
--      UIUtils.format_localized_description (ui_utils.lua:69) re-feeds the result
--      through string.format with description_values — a bare `%` becomes
--      "[Invalid String Format]". See feedback_vt2_localize_string_format_pipeline.md.
local RECKLESS_SWINGS_DESC_OVERRIDE = "While above 25%% Health, gain 25%% Power but take 1 damage on each melee hit."

-- v0.7.65: Miracle of Ulric / Miracle of Isha localization overrides — only
-- applied when the matching tweak toggle is on, so vanilla text stays put when
-- the alternative behaviors are off. Vanilla loc keys live in compiled
-- .strings bundles (deus_blessing_settings.lua:19-26, 47-56); we intercept the
-- Localize hook to substitute when the toggle is host-active.
-- `%%` is required because UIUtils.format_localized_description re-feeds the
-- result through string.format (feedback_vt2_localize_string_format_pipeline.md).
-- v0.7.67: name override removed — vanilla already returns "Miracle of Ulric"
-- for `blessing_of_power_name` (user-confirmed 2026-05-20). Only the
-- description differs, so only the description is overridden.
local MIRACLE_LOC_OVERRIDES = {
    blessing_of_power_desc      = "Grants every hero +50 Power for the rest of the run. The bonus persists through weapon swaps and upgrades at altars.",
    blessing_of_isha_desc_aegis = "Grants every hero -25%% damage taken for the rest of the run.",
    blessing_of_isha_desc_wounds= "Grants every hero unlimited wounds for the rest of the run — every knockdown is revivable instead of resulting in instant death after the first down.",
}

mod:hook(_G, "Localize", function(func, key, ...)
    if type(key) == "string" then
        local t = ADV_TITLE_OVERRIDES[key]
        if t then return t end
        local d = ADV_DESC_OVERRIDES[key]
        if d then return d end
        local m = MOD_BOON_LOC[key]
        if m then return m end
        if key == "description_deus_reckless_swings" and reckless_swings_originals then
            return RECKLESS_SWINGS_DESC_OVERRIDE
        end
        if key == "blessing_of_power_desc"
            and effective_setting("tweak_miracle_of_ulric_persistent") then
            return MIRACLE_LOC_OVERRIDES[key]
        end
        if key == "blessing_of_isha_desc" then
            -- Inline mode read because _get_isha_mode is defined later in the file
            -- and this closure is built before its declaration. v0.7.65 stored a
            -- boolean from the prior checkbox; migrate true→"aegis" here too.
            local isha_mode = effective_setting("tweak_miracle_of_isha_alternative")
            if isha_mode == true then isha_mode = "aegis" end
            if isha_mode == "aegis" then return MIRACLE_LOC_OVERRIDES.blessing_of_isha_desc_aegis end
            if isha_mode == "wounds" then return MIRACLE_LOC_OVERRIDES.blessing_of_isha_desc_wounds end
        end
    end
    return func(key, ...)
end)

-- DeusMechanism.uses_random_directors returns false (deus_mechanism.lua:909) so
-- EnemyPackageLoader._random_director_list stays nil for the entire CW run. Vanilla
-- CW levels' baked spawn_zone data have explicit `roaming_set` directors (no "random"
-- choice), so they never hit the nil dereference at
-- main_path_spawning_generator.lua:314 (`random_director_list[index].name`). Adventure
-- level spawn zones, however, were authored for AdventureMechanism (which returns
-- true) and DO have zone strings with "random" as one of the slash-separated
-- choices. When `process_conflict_directors_zones` picks "random" for any zone, the
-- subsequent generate_great_cycles crash fires.
--
-- Fix: force `use_random_directors = true` on the EnemyPackageLoader.setup_startup_enemies
-- call for any injected adventure level (matching by permutation base). This causes
-- _resolve_breed_packages (line 750) to populate _random_director_list, which the
-- spawn_zone generator then reads safely.
mod:hook("EnemyPackageLoader", "setup_startup_enemies", function(func, self, level_key, level_seed, failed_locked_functions, use_random_directors, conflict_director_name, difficulty, difficulty_tweak)
    if adventure_base_from_level_key(level_key) then
        use_random_directors = true
    end
    return func(self, level_key, level_seed, failed_locked_functions, use_random_directors, conflict_director_name, difficulty, difficulty_tweak)
end)

-- v0.7.41: Adventure-injected levels use vanilla conflict directors (e.g., chaos_light)
-- whose `PackSpawningSettings` entries lack `difficulty_overrides`. CW's SIGNATURE-zone
-- pacing applies the `no_roamers` mutator (mutator_deus_pacing_tweak.lua:38) which does
-- `pairs(pack_spawning_settings.difficulty_overrides)` → "bad argument #1 to 'pairs'
-- (table expected, got nil)" on first mission entry. Vanilla CW levels all have the
-- field populated; adventure ones don't (Crashify guid 004768e7).
--
-- Vanilla intends no_roamers as a CW-only pacing tool; it's mechanically too aggressive
-- for adventure levels anyway (area_density_coefficient = 0 wipes roaming spawns). Per
-- user: replace with the gentler `deus_less_roamers` semantics OR just exempt adventure
-- levels. Simplest exemption: filter the mutator name out of the zone/mutator lists
-- before vanilla `tweak_pack_spawning_settings` processes them.
local ADVENTURE_INCOMPATIBLE_PACK_MUTATORS = {
    no_roamers = true,
}

mod:hook("MutatorHandler", "tweak_pack_spawning_settings", function(func, self, zone_mutator_list, mutator_list, conflict_director_name, pack_spawning_settings)
    if not on_injected_adventure_level() then
        return func(self, zone_mutator_list, mutator_list, conflict_director_name, pack_spawning_settings)
    end
    local function filter(list)
        if type(list) ~= "table" then return list end
        local kept = {}
        for _, name in ipairs(list) do
            if not ADVENTURE_INCOMPATIBLE_PACK_MUTATORS[name] then
                kept[#kept + 1] = name
            end
        end
        return kept
    end
    return func(self, filter(zone_mutator_list), filter(mutator_list), conflict_director_name, pack_spawning_settings)
end)

-- ============================================================
-- Curse light tinting on injected adventure levels
-- ============================================================
-- Vanilla GameModeDeus.local_player_game_starts (game_mode_deus.lua:358-378)
-- iterates `Level.units(current_level)` and applies `DeusThemeSettings[theme].light_probe_tint`
-- to lights inside reflection_probe units. For vanilla CW that's enough — the level
-- bundle's sky shader and atmosphere are theme-specific too, so the tint reinforces
-- the existing visual.
--
-- Adventure level bundles have only the native atmosphere baked in (no per-god sky).
-- So when our injected `<adv>_<theme>_path1` permutation loads under a curse, the
-- engine applies the reflection-probe tint but the sky/atmosphere remains adventure-
-- vanilla. Result: cursed adventure missions look too "normal".
--
-- Partial mitigation: hook_safe the same function and apply the theme color to
-- EVERY light in the level (not just reflection probes), plus the camera backlight.
-- This makes the curse colour shift more pronounced even on adventure geometry.
-- It can't bring back the baked sky/particles, but it makes "this node is cursed"
-- visually obvious.
-- Per-curse PALETTES instead of a single tint, so individual level lights
-- pick up complementary / accent colors and the scene reads as themed
-- atmosphere rather than a uniform color filter.
--
-- Each palette has:
--   dominant: the headline color (most lights). Hits ~50% of lights.
--   accent:   a related-but-distinct shade. ~25% of lights.
--   complement: a deliberately contrasting hue. ~15% of lights.
--   warm/cool counterpoint: ~10% of lights — adds visual depth.
--
-- Distribution uses a deterministic hash on each light's index so the look
-- is repeatable per level / per run, not random per frame. The hash is
-- coarse on purpose (a handful of buckets) so nearby lights tend to
-- group rather than producing rainbow noise.
-- Each palette balances 4-5 slots:
--   - Dominant: god's headline hue (most lights).
--   - Accent:   nearby hue, reinforces theme (some lights).
--   - Complement: TRUE opposite on the color wheel — provides contrast pop.
--                 Red↔Cyan, Green↔Magenta, Blue↔Orange, Purple↔Yellow-Green.
--   - Neutral white-ish: keeps some lights "normal-looking" so the
--     colored lights register as accents instead of saturating the scene.
--     User feedback 2026-05-14: "purple looks good with white light sources" —
--     applies broadly; neutral slot makes other palettes pop too.
local _CURSE_LIGHT_PALETTES = {
    khorne = {
        { 1.00, 0.30, 0.25, w = 40 },   -- blood red (dominant)
        { 1.30, 0.55, 0.20, w = 20 },   -- ember orange (accent — same warm family)
        { 1.10, 1.05, 0.90, w = 15 },   -- warm white candle (neutral)
        { 0.95, 0.95, 0.35, w = 10 },   -- gold flame (warm secondary pop)
        { 0.20, 0.90, 1.00, w = 15 },   -- cold cyan complement (true ↔ red)
    },
    nurgle = {
        { 0.45, 1.00, 0.40, w = 40 },   -- sickly bog green (dominant)
        { 0.95, 1.05, 0.35, w = 20 },   -- jaundiced yellow (accent)
        { 1.00, 1.00, 0.95, w = 15 },   -- pale moldy white (neutral)
        { 0.30, 0.85, 0.95, w = 10 },   -- swamp teal (cool secondary)
        -- v0.7.46: was { 1.10, 0.30, 0.95 } — bright magenta. User wanted deep
        -- dark purple instead. Reduced red and blue and dropped overall intensity
        -- so the complement slot reads as ominous violet rather than hot pink.
        { 0.45, 0.15, 0.65, w = 15 },   -- deep dark purple complement (true ↔ green)
    },
    tzeentch = {
        -- Per user feedback v0.7.16: "make all the lights and most of the
        -- natural lights a magic blue, but then have just the overarching
        -- outdoor light be a deep orange." Dropped the cool-white slot
        -- entirely so 100% of Light components are some shade of deep
        -- magic blue. The contrast is now strictly: indoor / point lights
        -- (= blue) vs. outdoor sun + ambient (= warm orange via the shading
        -- env profile below).
        --
        -- NOTE: vanilla torches that get their orange glow from PARTICLE FX
        -- and self-illumination materials (not Light components) will still
        -- look warm — Light.set_color on the unit's Light handle doesn't
        -- override particle / material colors. If the user wants those
        -- pulled cool too we need a separate hook on the particle effect
        -- registry. Not done yet — wait for user feedback to see if it
        -- matters in practice.
        { 0.15, 0.30, 1.50, w = 75 },   -- deep magic cobalt (saturated, dominant)
        { 0.25, 0.50, 1.40, w = 25 },   -- mid cobalt variant (subtle variation, still deep blue)
    },
    slaanesh = {
        { 1.20, 0.45, 1.15, w = 35 },   -- hot pink (dominant)
        { 0.65, 0.40, 1.10, w = 20 },   -- deep purple (accent)
        { 1.10, 1.05, 1.10, w = 20 },   -- pale white (USER: "purple looks good with white")
        { 1.20, 0.75, 0.50, w = 10 },   -- peach warm pop
        { 0.55, 1.10, 0.45, w = 15 },   -- yellow-green complement (true ↔ pink)
    },
    belakor = {
        { 0.40, 0.30, 0.75, w = 40 },   -- twilight purple (dominant)
        { 0.30, 0.45, 0.95, w = 20 },   -- moonlight blue (accent)
        { 0.95, 0.95, 1.05, w = 15 },   -- pale silver-white (ghostly neutral)
        { 0.55, 0.30, 0.55, w = 10 },   -- shadow violet (cool secondary)
        { 1.05, 1.00, 0.50, w = 15 },   -- pale gold complement (true ↔ violet)
    },
}

-- Pick a palette slot for light index `i`. Stable across reloads — same
-- light index always gets the same slot for a given palette. Multiplier 7
-- and offset are arbitrary; chosen so groups of adjacent indices don't all
-- fall into the same bucket (avoid "all lights in this room are blood red").
local function _palette_slot(palette, idx)
    local total_w = 0
    for s = 1, #palette do total_w = total_w + (palette[s].w or 1) end
    -- Hash idx into [0, total_w)
    local h = ((idx * 7919) + 11) % total_w
    local cum = 0
    for s = 1, #palette do
        cum = cum + (palette[s].w or 1)
        if h < cum then return palette[s] end
    end
    return palette[1]
end

mod:hook_safe("GameModeDeus", "local_player_game_starts", function(self, player, loading_context)
    if not on_injected_adventure_level() then return end
    local run_controller = self._deus_run_controller
    if not run_controller then return end
    local current_node = run_controller:get_current_node()
    if not current_node then return end
    local theme = current_node.theme
    if not theme or theme == "wastes" then
        mod:info("[curse-tint] theme=%s (no curse); skipping", tostring(theme))
        return
    end
    local palette = _CURSE_LIGHT_PALETTES[theme]
    if not palette then
        mod:warning("[curse-tint] no palette mapping for theme=%s", tostring(theme))
        return
    end

    local world = self._world
    local level = LevelHelper:current_level(world)
    if not level then return end

    -- DELIBERATE: don't tint the camera backlight (that was glowing the
    -- first-person hands which the user didn't want). Tint only world lights.
    local units = Level.units(level)
    local lights_tinted = 0
    local global_idx = 0
    for j = 1, #units do
        local level_unit = units[j]
        if Unit.alive(level_unit) then
            local num_lights = Unit.num_lights(level_unit)
            if num_lights and num_lights > 0 then
                for i = 1, num_lights do
                    local light = Unit.light(level_unit, i - 1)  -- 0-indexed per vanilla
                    if light then
                        global_idx = global_idx + 1
                        local slot = _palette_slot(palette, global_idx)
                        Light.set_color(light, Vector3(slot[1], slot[2], slot[3]))
                        lights_tinted = lights_tinted + 1
                    end
                end
            end
        end
    end
    mod:info("[curse-tint] level=%s theme=%s palette_size=%d lights=%d",
        tostring(current_node.level), tostring(theme), #palette, lights_tinted)
end)

-- ============================================================
-- Vanilla bug fix: NetworkedFlowStateManager._num_states leak
-- ============================================================
-- Fatshark vanilla bug. `NetworkedFlowStateManager.clear_object_state`
-- (networked_flow_state_manager.lua:493) nils `_object_states[unit]` when a
-- unit is destroyed (entity_manager2.lua:390) BUT NEVER DECREMENTS
-- `_num_states`. The counter is monotonic and the run fatals at
-- `_num_states == _max_states (512)` with:
--   "[NetworkedFlowStateManager] Too many object states(512)."
-- Every destroyed unit that ever held a networked flow state permanently
-- leaks its slot.
--
-- Hits hardest in CW runs with our adventure-mission injection + curses:
-- the `cursed_chest_objective_unit` buff is applied to every cursed-chest
-- enemy spawn (deus_generic_terror_events.lua:26 →
-- morris_buff_settings.lua:614 apply_objective_unit) which spawns a
-- `units/hub_elements/objective_unit` carrying a `chest_open_state`
-- networked flow state. Each enemy = 1 permanently-leaked slot. Crash
-- reproduced ~40 min into a Verminious Dreams khorne node with 2 Chests
-- of Trials triggered (crash dump
-- console-2026-05-14-03.23.33-d86fd894-...).
--
-- Fix: count the states being released, subtract from `_num_states` BEFORE
-- delegating to vanilla. Defensive about table shape since this is a
-- private engine field that could change shape in future patches.
mod:hook("NetworkedFlowStateManager", "clear_object_state", function(func, self, unit)
    local unit_states = self._object_states and self._object_states[unit]
    if unit_states and type(unit_states.states) == "table" and type(self._num_states) == "number" then
        local count = 0
        for _ in pairs(unit_states.states) do count = count + 1 end
        if count > 0 then
            self._num_states = math.max(0, self._num_states - count)
        end
    end
    return func(self, unit)
end)

-- ============================================================
-- Curse SKY / atmosphere tinting (CameraManager.shading_callback)
-- ============================================================
-- Light.set_color only tints individual lights — adventure-level skies, sun,
-- and atmospheric fog stay vanilla. Peregrinaje (bundle-unpacked, file
-- 92BC0C4E7BFF8C3A.lua) drives sky/sun/fog via ShadingEnvironment.set_vector3
-- on keys like `skydome_tint_color`, `sun_color`, `secondary_sun_color`,
-- `ambient_tint`, `fog_color`. Vanilla CameraManager.shading_callback
-- (camera_manager.lua:283-368) runs per frame with a live shading_env handle;
-- vanilla `MoodHandler.apply_environment_variables` is called at line 346 to
-- overlay any active moods. We hook_safe AFTER vanilla so the curse tint
-- multiplies the post-mood sky color.
--
-- Stingray re-seeds the shading_environment from the level's baked template
-- every frame, so no save/restore — when the player leaves the cursed node
-- and we stop applying, the level's vanilla atmosphere returns automatically.
-- Per-curse lighting PROFILES instead of a single flat tint. Each profile
-- specifies a different multiplicative tint per shading-environment variable so
-- the scene reads as "themed atmosphere" rather than "uniform color filter":
--   - sky (skydome_tint_color):    the headline color — strongest hue
--   - sun (sun_color):             warmer / cooler accent, not pure-color
--   - secondary_sun (fill):        subtler, often neutral-toward-tint
--   - ambient_tint (mid):          moody, shifts whole scene tone
--   - ambient_tint_top (zenith):   slight contrast cue at the top of ambient
--   - fog_color (haze):            second strongest accent, ties scene together
--   - exposure (scalar):           tiny dim/bright tweak for mood
-- All values are multiplicative on top of the level's baked atmosphere, so the
-- result blends with the underlying environment instead of replacing it.
local _CURSE_SKY_PROFILES = {
    -- KHORNE — blood-red dominant. v0.7.18: toned ~30% toward neutral
    -- so the exterior color isn't oppressive (user feedback).
    khorne = {
        skydome_tint_color   = { 1.32, 0.51, 0.44 },
        sun_color            = { 1.21, 0.76, 0.62 },
        secondary_sun_color  = { 1.14, 0.65, 0.58 },
        ambient_tint         = { 1.04, 0.69, 0.62 },
        ambient_tint_top     = { 1.14, 0.58, 0.51 },
        fog_color            = { 1.39, 0.48, 0.44 },
        exposure_mul         = 0.95,
    },
    -- NURGLE — sickly bog green. v0.7.18 toned ~30% toward neutral. v0.7.46
    -- further tones the green channel ~10–15% on every slot and shifts toward
    -- yellow so it reads as jaundiced/sickly without overwhelming. Per user:
    -- "outdoor greens a bit less intense, but still visibly a sickly greenish-yellow."
    nurgle = {
        skydome_tint_color   = { 0.78, 1.05, 0.55 },   -- was {0.62, 1.21, 0.58} — softer sky, more yellow tint
        sun_color            = { 1.05, 1.02, 0.65 },   -- was {0.97, 1.11, 0.69} — pull green down, lean yellow
        secondary_sun_color  = { 0.92, 0.98, 0.66 },   -- was {0.79, 1.04, 0.69}
        ambient_tint         = { 0.88, 0.95, 0.68 },   -- was {0.76, 1.00, 0.72} — softer bounce
        ambient_tint_top     = { 0.82, 1.00, 0.60 },   -- was {0.69, 1.07, 0.62}
        fog_color            = { 0.80, 1.05, 0.55 },   -- was {0.65, 1.14, 0.58} — fog less aggressively green
        exposure_mul         = 1.00,
    },
    -- TZEENTCH — cobalt sky lit by orange daylight, deep-blue point lights.
    -- v0.7.18: toned ~30% toward neutral on sun/ambient (user feedback —
    -- the deep-orange exterior in v0.7.17 was too oppressive). Cobalt sky
    -- and cool blue fog are also pulled slightly to neutral.
    tzeentch = {
        skydome_tint_color   = { 0.62, 0.76, 1.35 },   -- cobalt sky (softer)
        sun_color            = { 1.39, 0.72, 0.44 },   -- orange direct sun (softer than v0.7.17)
        secondary_sun_color  = { 1.28, 0.79, 0.55 },
        ambient_tint         = { 1.25, 0.86, 0.58 },
        ambient_tint_top     = { 1.32, 0.76, 0.48 },
        fog_color            = { 0.76, 0.83, 1.21 },   -- cool blue fog (softer)
        exposure_mul         = 1.04,
    },
    -- SLAANESH — pink + lilac, with hot magenta highlights. Sun is a peach
    -- counterpoint to the pink sky for visual depth. Ambient drinks the pink.
    slaanesh = {
        skydome_tint_color   = { 1.35, 0.50, 1.15 },
        sun_color            = { 1.30, 0.85, 0.95 },
        secondary_sun_color  = { 1.20, 0.65, 1.05 },
        ambient_tint         = { 1.15, 0.65, 1.05 },
        ambient_tint_top     = { 1.30, 0.55, 1.20 },
        fog_color            = { 1.25, 0.40, 1.10 },
        exposure_mul         = 0.97,
    },
    -- BELAKOR — twilight purple. v0.7.21: brightened ambient (interior
    -- bounce) so rooms aren't pitch-black, slightly dimmed exterior
    -- (sky + sun) so the outdoor mood stays oppressive. Per user feedback.
    belakor = {
        skydome_tint_color   = { 0.40, 0.25, 0.65 },   -- slightly darker sky
        sun_color            = { 0.50, 0.50, 0.85 },   -- slightly dimmer direct sun
        secondary_sun_color  = { 0.55, 0.50, 0.90 },   -- brighter fill (helps interiors)
        ambient_tint         = { 0.75, 0.65, 1.00 },   -- BRIGHTER interior bounce (was 0.45/0.40/0.75)
        ambient_tint_top     = { 0.60, 0.55, 1.00 },   -- brighter top ambient
        fog_color            = { 0.40, 0.30, 0.75 },   -- keep fog
        exposure_mul         = 0.92,                    -- less darkening (was 0.85)
    },
}

local function _current_node_theme()
    if not (Managers.mechanism and Managers.mechanism.game_mechanism) then return nil end
    local mechanism = Managers.mechanism:game_mechanism()
    if not mechanism or not mechanism.get_deus_run_controller then return nil end
    local run = mechanism:get_deus_run_controller()
    if not run or not run.get_current_node then return nil end
    local node = run:get_current_node()
    return node and node.theme or nil
end

local function _current_node_curse()
    if not (Managers.mechanism and Managers.mechanism.game_mechanism) then return nil end
    local mechanism = Managers.mechanism:game_mechanism()
    if not mechanism or not mechanism.get_deus_run_controller then return nil end
    local run = mechanism:get_deus_run_controller()
    if not run or not run.get_current_node then return nil end
    local node = run:get_current_node()
    return node and node.curse or nil
end

-- v0.7.64: locus only spawns on the actual Belakor-cursed mission.
local function _current_node_is_belakor()
    return _current_node_curse() == "curse_belakor_totems"
end

mod:hook_safe("CameraManager", "shading_callback", function(self, world, shading_env, viewport)
    if not on_injected_adventure_level() then return end
    local theme = _current_node_theme()
    if not theme or theme == "wastes" then return end
    local profile = _CURSE_SKY_PROFILES[theme]
    if not profile then return end

    -- Multiply each existing color by the curse profile's per-var tint.
    -- ShadingEnvironment.vector3 returns a fresh Vector3 each call (valid
    -- within this frame) — safe to read, multiply, and write back.
    local function mul_set(var_name)
        local t = profile[var_name]
        if not t then return end
        local v = ShadingEnvironment.vector3(shading_env, var_name)
        if v then
            ShadingEnvironment.set_vector3(shading_env, var_name,
                Vector3(v.x * t[1], v.y * t[2], v.z * t[3]))
        end
    end
    mul_set("skydome_tint_color")
    mul_set("sun_color")
    mul_set("secondary_sun_color")
    mul_set("ambient_tint")
    mul_set("ambient_tint_top")
    mul_set("fog_color")

    if profile.exposure_mul and profile.exposure_mul ~= 1.0 then
        local cur = ShadingEnvironment.scalar(shading_env, "exposure")
        if cur then
            ShadingEnvironment.set_scalar(shading_env, "exposure", cur * profile.exposure_mul)
        end
    end
end)

-- ============================================================
-- Replace shrines with missions (SHOP -> TRAVEL conversion)
-- ============================================================
-- When `replace_shrines_with_missions` is enabled, every SHOP node in the base
-- journey graph is converted to a TRAVEL node BEFORE deus_populate_graph picks
-- levels for it. Effect: the boon-picker shrines on Olesya's map become regular
-- mission slots that roll from the TRAVEL pool (vanilla CW missions plus any
-- enabled adventure missions). Players play more missions and lose the free
-- between-mission boon picks.
--
-- Implementation: hook deus_populate_graph and clone-then-mutate the base_graph
-- before passing to the original. We shallow-clone individual SHOP nodes (not
-- the whole graph) so we don't waste memory copying TRAVEL/SIGNATURE/ARENA nodes
-- — and crucially DON'T mutate the source baked-graph table, which is shared
-- across calls. Setting `label = 0` on the converted node skips the
-- shuffled_levels_for_labels deterministic lookup and forces a random pick from
-- LEVEL_AVAILABILITY.TRAVEL (which is what we want — random TRAVEL roll).
-- Map node icon swap for adventure levels. Vanilla `spawn_graph_units` in
-- deus_map_scene.lua:182-192 picks the node's 3D model by string-prefix on
-- `node.level`:  "sig_*" → SIG, "pat_*" → TRAVEL, "arena_*" → ARENA, else SHRINE.
-- Adventure mission keys (e.g. `bell_khorne_path1`, `farmlands_khorne_path1`)
-- don't match any prefix, so they fall to SHRINE. Hook DeusMapScene.on_enter
-- (the public method that calls spawn_graph_units at line 466): walk the
-- graph_data, prefix each adventure node's `level` with the CW-icon basename
-- that matches the mission's `icon` field, call vanilla, then restore.
-- This routes adventure nodes to TRAVEL_NODE_UNIT and feeds the flow event's
-- `data.level` lookup a CW basename it recognizes (pat_tower for towers,
-- pat_mountain for mountain missions, etc.) so the per-mission icon variant
-- on the 3D node mesh matches our `icon` field. Adventure base_level is also
-- rewritten so the flow event's `data.level` (set from node.base_level on the
-- spawned unit) sees the icon-matching base too.
mod:hook("DeusMapScene", "on_enter", function(func, self, graph_data, ...)
    if not graph_data then
        mod:info("[DeusMapScene.on_enter] no graph_data; passing through")
        return func(self, graph_data, ...)
    end
    -- v0.7.64 late-arrival apply: if the host's graph snapshot arrived AFTER the
    -- client's `deus_populate_graph` ran (RPC ordering race during setup_run),
    -- this is the natural re-apply site — the map UI is the only visible consumer
    -- the user complained about. Phase-A's in-place mutation makes downstream
    -- `_path_graph` reads see the synced values too, so we don't need a third
    -- application site for in-mission tooltip / curse-name reads.
    if _ct_host_graph_snapshot then
        local applied = apply_graph_snapshot(graph_data)
        if applied > 0 then
            mod:info("[ct_graph] applied host snapshot to %d nodes (DeusMapScene.on_enter)", applied)
        end
    end
    local saved = {}
    local seen, rewritten, skipped = 0, 0, 0
    for key, node in pairs(graph_data) do
        if type(node) == "table" and type(node.level) == "string" then
            seen = seen + 1
            local base_key = adventure_base_from_level_key(node.level)
            if base_key then
                local mission = AdventurePool and AdventurePool.MISSION_BY_KEY and AdventurePool.MISSION_BY_KEY[base_key]
                local icon = mission and mission.icon or "mountain"  -- fallback
                local cw_base = "pat_" .. icon
                saved[key] = { level = node.level, base_level = node.base_level }
                local suffix = node.level:match("(_[a-z]+_path%d+)$") or "_wastes_path1"
                local new_level = cw_base .. suffix
                mod:info("[DeusMapScene.on_enter]   rewrite %s: %s -> %s (theme=%s curse=%s)",
                    tostring(key), node.level, new_level, tostring(node.theme), tostring(node.curse))
                node.level = new_level
                node.base_level = cw_base
                rewritten = rewritten + 1
            else
                if node.level:match("^pat_") or node.level:match("^sig_") or node.level:match("^arena_") or node.level:match("^shop_") then
                    -- vanilla CW level, no rewrite needed
                else
                    skipped = skipped + 1
                    mod:info("[DeusMapScene.on_enter]   SKIP %s level=%s (no adventure base match — UI will use SHRINE_NODE_UNIT and curse halo won't show)",
                        tostring(key), node.level)
                end
            end
        end
    end
    mod:info("[DeusMapScene.on_enter] seen=%d rewritten=%d skipped_non_vanilla_non_adventure=%d",
        seen, rewritten, skipped)

    local result = { func(self, graph_data, ...) }

    for key, original in pairs(saved) do
        if graph_data[key] then
            graph_data[key].level = original.level
            graph_data[key].base_level = original.base_level
        end
    end
    return unpack(result)
end)

-- Filter curse pool by user's disable_curse_* settings BEFORE the graph generator
-- runs spread_curse → assign_random_curse. The vanilla picker reads
-- `config.AVAILABLE_CURSES[node_type][god]` and picks at random. If we strip
-- disabled curses from that array, a node hot-spotted to god X will roll a
-- DIFFERENT enabled curse of X instead of being nil-curse'd by our downstream
-- _transition_next_node hook.
-- Edge case: if user disabled ALL curses of god X, leaving the array empty would
-- crash assign_random_curse (`curses[random(1, 0)]` → nil indexing). We keep the
-- original list in that case so the picker has something to pick; the existing
-- runtime curse-disable hooks (_activate_mutator, get_current_node_curse,
-- _transition_next_node, start_next_round, _enable_hover) then null out the
-- still-disabled curse — net effect: theme stays as the god, curse vanishes.
-- Returns the save-list so the caller can restore originals after func() runs.
local function filter_available_curses(config)
    local saved = {}
    if not config or not config.AVAILABLE_CURSES then return saved end
    for node_type, god_table in pairs(config.AVAILABLE_CURSES) do
        if type(god_table) == "table" then
            for god, curse_list in pairs(god_table) do
                if type(curse_list) == "table" and #curse_list > 0 then
                    local filtered = {}
                    for _, curse in ipairs(curse_list) do
                        local key = "disable_curse_" .. curse:gsub("^curse_", "")
                        -- v0.7.42: use effective_setting so client mirrors host's disable
                        -- choices. Otherwise the deus_populate_graph filtering diverges
                        -- across peers → wrong-curse-on-node visible to one player only.
                        if not effective_setting(key) then
                            filtered[#filtered + 1] = curse
                        end
                    end
                    if #filtered > 0 and #filtered < #curse_list then
                        saved[#saved + 1] = { tbl = god_table, key = god, original = curse_list }
                        god_table[god] = filtered
                    end
                    -- If #filtered == 0 (all disabled), leave original in place; the
                    -- runtime is_curse_disabled hooks will null the picked curse anyway.
                end
            end
        end
    end
    return saved
end

local function restore_available_curses(saved)
    for i = #saved, 1, -1 do
        local entry = saved[i]
        entry.tbl[entry.key] = entry.original
    end
end

mod:hook(_G, "deus_populate_graph", function(func, base_graph, seed, config, dominant_god, with_belakor)
    -- CW graph generation runs on BOTH host and client (deterministic from
    -- seed). Use effective_setting(name) — returns mod:get() on host, the
    -- most-recently-synced host value on clients. v0.7.20 gated this hook
    -- on `is_server` to stop the deus_shop_view_v2 nil crash; v0.7.21
    -- replaces that gate with proper host→client setting sync (broadcast in
    -- the setup_run hook above) so peers produce IDENTICAL graphs from the
    -- same seed instead of merely-vanilla-on-client graphs.
    --
    -- If the broadcast hasn't arrived yet on the client (first run, RPC
    -- ordering), effective_setting falls back to defaults that match
    -- vanilla behavior (no mutation) — same safety as the v0.7.20 gate.

    -- Override the curse hotspot count if the user has set `cursed_mission_count`.
    -- Vanilla `spread_curse` (deus_populate_graph.lua:681) does:
    --   hot_spot_count = random(CURSES_HOT_SPOTS_MIN_COUNT, CURSES_HOT_SPOTS_MAX_COUNT)
    --   for each cluster: pick a center node, curse it, AND spread curse to nodes
    --   within `CURSES_HOT_SPOT_MAX_RANGE` (so each cluster typically curses 1-3 nodes).
    -- For the user's setting to give an EXACT count of cursed missions, we both:
    --   1. Force MIN = MAX = N (deterministic cluster count)
    --   2. Set MIN_RANGE = MAX_RANGE = 0 (each cluster curses only its center, no spread)
    -- Net: exactly N cursed nodes (or fewer if the map has < N curseable nodes; the
    -- spreader stops early when it runs out of candidates).
    local saved_min, saved_max, saved_range_min, saved_range_max, saved_min_progress, saved_no_dominant
    local override_curse_count = effective_setting("cursed_mission_count")
    mod:info("[deus_populate_graph] override_curse_count=%s, config?=%s, vanilla_min=%s vanilla_max=%s vanilla_range_min=%s vanilla_range_max=%s vanilla_min_progress=%s",
        tostring(override_curse_count), tostring(config ~= nil),
        config and tostring(config.CURSES_HOT_SPOTS_MIN_COUNT) or "?",
        config and tostring(config.CURSES_HOT_SPOTS_MAX_COUNT) or "?",
        config and tostring(config.CURSES_HOT_SPOT_MIN_RANGE) or "?",
        config and tostring(config.CURSES_HOT_SPOT_MAX_RANGE) or "?",
        config and tostring(config.CURSES_MIN_PROGRESS) or "?")
    if config and override_curse_count and override_curse_count > 0 then
        saved_min = config.CURSES_HOT_SPOTS_MIN_COUNT
        saved_max = config.CURSES_HOT_SPOTS_MAX_COUNT
        saved_range_min = config.CURSES_HOT_SPOT_MIN_RANGE
        saved_range_max = config.CURSES_HOT_SPOT_MAX_RANGE
        saved_min_progress = config.CURSES_MIN_PROGRESS
        config.CURSES_HOT_SPOTS_MIN_COUNT = override_curse_count
        config.CURSES_HOT_SPOTS_MAX_COUNT = override_curse_count
        config.CURSES_HOT_SPOT_MIN_RANGE = 0
        config.CURSES_HOT_SPOT_MAX_RANGE = 0
        -- Vanilla CURSES_MIN_PROGRESS (typically 0.2) excludes the first 1-2
        -- nodes of every journey from being curseable. With range=0 (exact
        -- count) the user's early nodes are guaranteed-uncursed even when
        -- they pick count=30. Drop the floor below zero so cluster centers
        -- can land anywhere.
        --
        -- NOTE: must be NEGATIVE, not 0. Vanilla `get_nodes_above_progress`
        -- (deus_populate_graph.lua:45-55) uses strict `progress < node.run_progress`,
        -- so 0 < 0 is false — first-mission nodes (run_progress=0) get excluded
        -- even with min_progress=0. Use -1 so 1+1=2 nodes at run_progress=0 are
        -- in the pool.
        config.CURSES_MIN_PROGRESS = -1
        mod:info("[deus_populate_graph] applied override: count=%d range=0/0 min_progress=-1", override_curse_count)
    end

    -- Vanilla's spread_curse reserves the dominant_god for the "final"
    -- node only (deus_populate_graph.lua:686-690), then EXCLUDES it from
    -- the non-final rotation (line 698) — so a journey with
    -- dominant_god=khorne will never have Khorne curses on regular missions,
    -- only on the final arena. NO_DOMINANT_GOD=true puts all 4 gods into
    -- the uniform rotation (final loses its "must match dominant" guarantee).
    -- v0.7.18: user-toggleable as `disable_dominant_god` (default on).
    -- Applies INDEPENDENTLY of the count override so the user can re-enable
    -- normal curse counts with all gods in rotation, or vice versa.
    if config and effective_setting("disable_dominant_god") then
        saved_no_dominant = config.NO_DOMINANT_GOD
        config.NO_DOMINANT_GOD = true
        mod:info("[deus_populate_graph] disable_dominant_god=true (all 4 gods in rotation)")
    end

    -- Filter the curse pool so disabled curses get re-rolled within their god
    -- rather than just removed (per user spec).
    local saved_curses = filter_available_curses(config)

    local function restore_curse_count()
        if saved_min then config.CURSES_HOT_SPOTS_MIN_COUNT = saved_min end
        if saved_max then config.CURSES_HOT_SPOTS_MAX_COUNT = saved_max end
        if saved_range_min then config.CURSES_HOT_SPOT_MIN_RANGE = saved_range_min end
        if saved_range_max then config.CURSES_HOT_SPOT_MAX_RANGE = saved_range_max end
        if saved_min_progress then config.CURSES_MIN_PROGRESS = saved_min_progress end
        -- restore even when saved_no_dominant was nil (default vanilla state)
        config.NO_DOMINANT_GOD = saved_no_dominant
        restore_available_curses(saved_curses)
    end

    -- Count cursed nodes in the completed graph for diagnostic.
    -- IMPORTANT: completed graph uses `node_type` ("ingame"/"shop"/"start") —
    -- the `type` field is only on the BASE graph. Burned in v0.7.6's first
    -- pass which counted 0/0 because it checked the wrong field.
    local function count_cursed(graph)
        if type(graph) ~= "table" then return 0, 0 end
        local cursed, total = 0, 0
        for _, n in pairs(graph) do
            if type(n) == "table" and n.node_type == "ingame" then
                total = total + 1
                if n.curse then cursed = cursed + 1 end
            end
        end
        return cursed, total
    end

    -- Dump every node so we can see the FULL graph state regardless of type.
    local function dump_graph(graph, tag)
        if type(graph) ~= "table" then
            mod:info("[deus_populate_graph %s] graph is %s (not a table)", tag, type(graph))
            return
        end
        local n_count = 0
        for k, n in pairs(graph) do
            n_count = n_count + 1
            if type(n) == "table" then
                mod:info("[deus_populate_graph %s]   %s node_type=%s curse=%s god=%s level=%s progress=%s",
                    tag, tostring(k),
                    tostring(n.node_type), tostring(n.curse), tostring(n.god),
                    tostring(n.level), tostring(n.run_progress or n.progress or "?"))
            else
                mod:info("[deus_populate_graph %s]   %s = %s (not a table)", tag, tostring(k), tostring(n))
            end
        end
        mod:info("[deus_populate_graph %s] total entries: %d", tag, n_count)
    end

    if not effective_setting("replace_shrines_with_missions") then
        local result = { func(base_graph, seed, config, dominant_god, with_belakor) }
        local cursed, total = count_cursed(result[1])
        mod:info("[deus_populate_graph] post-run cursed=%d / total_curseable=%d", cursed, total)
        dump_graph(result[1], "post-run")
        restore_curse_count()
        -- v0.7.64 graph sync — see ct_graph_snapshot_chunk block above.
        local is_server = Managers and Managers.player and Managers.player.is_server
        if is_server then
            broadcast_graph_snapshot(result[1])
        else
            local applied = apply_graph_snapshot(result[1])
            if applied > 0 then
                mod:info("[ct_graph] applied host snapshot to %d nodes (post-run)", applied)
            end
        end
        return unpack(result)
    end

    local mutated = {}
    local converted = 0
    for node_key, node in pairs(base_graph) do
        if type(node) == "table" and node.type == "SHOP" then
            local copy = table.clone(node)
            copy.type = "TRAVEL"
            copy.label = 0
            mutated[node_key] = copy
            converted = converted + 1
        else
            mutated[node_key] = node
        end
    end

    if converted > 0 then
        mod:info("deus_populate_graph: converted %d SHOP node(s) to TRAVEL", converted)
    end

    local result = { func(mutated, seed, config, dominant_god, with_belakor) }
    local cursed, total = count_cursed(result[1])
    mod:info("[deus_populate_graph] post-run (shop-converted) cursed=%d / total_curseable=%d", cursed, total)
    dump_graph(result[1], "post-run-shop-converted")
    restore_curse_count()
    -- v0.7.64 graph sync — see ct_graph_snapshot_chunk block above.
    local is_server = Managers and Managers.player and Managers.player.is_server
    if is_server then
        broadcast_graph_snapshot(result[1])
    else
        local applied = apply_graph_snapshot(result[1])
        if applied > 0 then
            mod:info("[ct_graph] applied host snapshot to %d nodes (post-run-shop-converted)", applied)
        end
    end
    return unpack(result)
end)

-- ============================================================
-- Per-career weapon override recovery (fixes CW bot ghost-scythe crash)
-- ============================================================
--
-- Crash: `Unit not found wpn_bw_ghost_scythe_01_3p` (Necromancer base mesh) when a
-- Sienna Unchained bot spawns with the ghost scythe (the scythe can_wield all four
-- Sienna careers; non-Necromancer careers use `_fire` mesh variants via
-- `ItemMasterList.bw_ghost_scythe.right_hand_unit_override`).
--
-- Vanilla flow:
--   simple_inventory_extension.add_equipment passes `self._career_name` to
--   gear_utils.create_equipment, which calls
--   `BackendUtils.get_item_units(item_data, nil, nil, career_name)`. The override
--   block at `backend_utils.lua:159-162` is gated on `career_name`, so when it
--   arrives nil, the BASE `right_hand_unit` survives — and `gear_utils.lua:189`
--   derives the 3P path as `weapon_unit_name .. "_3p"` (base 3P), which isn't
--   in the bot's preloaded packages → `world.spawn_unit` fatal.
--
-- Why career_name arrives nil: observed in weapon_tweaker v0.12.23/v0.12.24 — the
-- hook chain between simple_inventory and the unwrapped gear_utils drops the arg
-- (multiple modded create_equipment hooks chain via varargs, and one of them
-- occasionally loses the trailing args). weapon_tweaker fixed this for users with
-- that mod loaded; users who only have chaos_wastes_tweaker need the same fix here.
--
-- Fix (two layers):
--   1. If career_name is nil at hook entry, recover it from the 3P unit's
--      `inventory_system._career_name` (set in `SimpleInventoryExtension.init`
--      before extensions_ready fires).
--   2. If item_data has a per-career override AND we have career_name, pre-resolve
--      `item_units` ourselves and pass via override_item_units. Vanilla
--      gear_utils uses `override_item_units or get_item_units(...)`, so our
--      pre-resolved table is used verbatim and the broken chain pass-through is
--      sidestepped entirely.
--
-- Originally landed in weapon_tweaker v0.12.23-25; cross-ported here so the fix
-- works for users running ct without wt. Both mods can host the hook safely
-- (VMF chains them and the operation is idempotent — if the upstream hook
-- already pre-resolved override_item_units, our `override_item_units == nil`
-- guard skips the re-resolve).
mod:hook("GearUtils", "create_equipment", function(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    if career_name == nil and unit_3p and ScriptUnit and ScriptUnit.has_extension
            and ScriptUnit.has_extension(unit_3p, "inventory_system") then
        local inv = ScriptUnit.extension(unit_3p, "inventory_system")
        career_name = inv and inv._career_name or nil
    end

    if override_item_units == nil and item_data and career_name and BackendUtils
            and BackendUtils.get_item_units
            and ((item_data.right_hand_unit_override and item_data.right_hand_unit_override[career_name])
              or (item_data.left_hand_unit_override and item_data.left_hand_unit_override[career_name])) then
        local ok_resolve, resolved = pcall(BackendUtils.get_item_units, item_data, item_data.backend_id, nil, career_name)
        if ok_resolve and type(resolved) == "table" then
            override_item_units = resolved
        end
    end

    return func(world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
end)

-- `_chest_conversions_this_level` is declared earlier in this file (search for
-- the populate_pickups hook) and reset there at the top of every populate.
-- That placement is required because Lua 5.1 binds closure locals at creation
-- time, and consolidating populate_pickups hooks into one avoids the VMF
-- "Attempting to rehook active hook" warning.

-- Hook on PickupSystem._spawn_pickup — the lowest-level spawn function that ALL
-- paths route through (public spawn_pickup, spawn_pickup_async, buff_spawn_pickup,
-- _spawn_guaranteed_pickup, _spawn_spread_pickups). Used for two purposes:
--
-- 1. Substitute loot_die → deus_soft_currency on injected adventure levels.
--    The Bogenhafen loot-die system has no CW analogue. Catches:
--      a. Guaranteed spawners with loot_die data (also covered by our explicit
--         hook on _spawn_guaranteed_pickup above, but doesn't hurt to double-up).
--      b. Flow-event spawned loot dice (level-script-driven bonus dice drops).
--      c. Boss kill loot if the game_mode somehow returned "loot_die" (vanilla
--         GameModeDeus.get_boss_loot_pickup returns "deus_soft_currency" already
--         for our deus-mode adventure levels, but defensive).
--
-- 2. Disable physics collision on CW altars/chests so they don't block player
--    pathing at adventure spawner positions (designed for ammo/healing, not for
--    a multi-meter-wide blocking prop). `Actor.set_collision_enabled(false)`
--    removes the character-controller block; interaction raycasts still hit the
--    visible mesh, so E-to-open still works.
local _CW_BLOCKING_PICKUP_NAMES = {
    deus_weapon_chest = true,
    deus_cursed_chest = true,
    deus_02 = true,  -- alternate chest variant some CW level pickup_settings reference
}

mod:hook("PickupSystem", "_spawn_pickup", function(func, self, settings, pickup_name, position, rotation, flag, spawn_type, ...)
    if on_injected_adventure_level() and pickup_name == "loot_die" then
        pickup_name = "deus_soft_currency"
        settings = (AllPickups and AllPickups.deus_soft_currency) or settings
    end

    return func(self, settings, pickup_name, position, rotation, flag, spawn_type, ...)
end)
-- Note: previous versions attempted to make altars/chests walk-through by mutating
-- their actor collision filter / scene_query / collision_enabled flags. This
-- ALWAYS regressed interaction (v0.6.28 scene_query disable broke chest open;
-- v0.6.32 filter_trigger broke it again). The Peregrinaje mod ships chests without
-- a physics blocker by some other mechanism — investigate that pattern before
-- re-attempting any collision-disable here.

mod:hook("PickupSystem", "_spawn_guaranteed_pickup", function(func, self, spawner_unit, spawn_type)
    if not on_injected_adventure_level() then
        return func(self, spawner_unit, spawn_type)
    end

    -- loot_die spawners on Bogenhafen (Brugrodder '68 bottle, etc.) are guaranteed
    -- side-objective collectibles. We have no CW equivalent system — convert these
    -- positions to deus_soft_currency (Pilgrim's Coin) so the spawner still gives
    -- something useful instead of dropping a collectible the run can't interact with.
    if Unit.get_data(spawner_unit, "loot_die") then
        local settings = AllPickups and AllPickups.deus_soft_currency
        if settings then
            local position = Unit.local_position(spawner_unit, 0)
            local rotation = Unit.local_rotation(spawner_unit, 0)
            return self:_spawn_pickup(settings, "deus_soft_currency", position, rotation, false, spawn_type)
        end
        return func(self, spawner_unit, spawn_type)
    end

    local is_tome = Unit.get_data(spawner_unit, "tome")
    local is_grim = Unit.get_data(spawner_unit, "grimoire")
    if not is_tome and not is_grim then
        return func(self, spawner_unit, spawn_type)
    end

    -- Respect the user's `cursed_chest_count` setting. The first N book spots become
    -- Chests of Trials. Default ("Default" sentinel = -1) treats this as the vanilla
    -- value of 1 chest per mission; explicit 0 leaves all book spots empty. Vanilla
    -- adventure maps ship 5 book pedestals (3 tomes + 2 grimoires), so up to 4 spots
    -- remain afterwards.
    -- v0.7.65: sentinel -1 → 1 (vanilla default); 0+ → use as-is.
    local cap_raw = effective_setting("cursed_chest_count") or -1  -- v0.7.42: sync with host
    local cap = (cap_raw == -1) and 1 or cap_raw
    if _chest_conversions_this_level < cap then
        local pickup_name = "deus_cursed_chest"
        local settings = AllPickups and AllPickups[pickup_name]
        if not settings then
            -- AllPickups not yet built (extremely unlikely at populate time, but defensive).
            return func(self, spawner_unit, spawn_type)
        end

        local position = Unit.local_position(spawner_unit, 0)
        local rotation = Unit.local_rotation(spawner_unit, 0)
        local spawned_unit = self:_spawn_pickup(settings, pickup_name, position, rotation, false, spawn_type)
        _chest_conversions_this_level = _chest_conversions_this_level + 1
        return spawned_unit
    end

    -- v0.7.55: after Chests of Trials are placed, the NEXT remaining book spot becomes
    -- the Belakor altar (`deus_02` / `deus_belakor_locus`) when the host has "Always
    -- Include Belakor's Temple" on. One altar per mission, matching vanilla
    -- belakor-themed CW levels which all request `deus_02 = 1`. The `_spawn_pickup`
    -- call below also re-checks `can_spawn_belakor_locus` (vanilla pickup-settings
    -- `can_spawn_func` gate), which our DeusRunController.can_spawn_belakor_locus hook
    -- below permits on adventure-injected levels — both paths must agree, or the call
    -- silently no-ops.
    -- v0.7.64: locus only spawns on the actual Belakor cursed mission. Previously
    -- `force_belakor` alone caused the locus to land on the FIRST adventure-injected
    -- book pedestal regardless of which node held curse_belakor_totems — so in last
    -- night's run the locus landed on nurgle_slaanesh_path1 while the actual Belakor
    -- mission (magnus_belakor_path1) got nothing. `_current_node_is_belakor()` reads
    -- the current node's curse field, which is the only data that identifies "this
    -- mission has the Belakor totems curse." `force_belakor` itself only guarantees a
    -- Belakor curse appears SOMEWHERE in the run — it doesn't say where.
    if not _belakor_altar_spawned_this_level
        and effective_setting("force_belakor")
        and _current_node_is_belakor()
        and AllPickups and AllPickups.deus_02 then
        local position = Unit.local_position(spawner_unit, 0)
        local rotation = Unit.local_rotation(spawner_unit, 0)
        local spawned_unit = self:_spawn_pickup(AllPickups.deus_02, "deus_02", position, rotation, false, spawn_type)
        if spawned_unit then
            _belakor_altar_spawned_this_level = true
            return spawned_unit
        end
        -- _spawn_pickup returns nil if can_spawn_func vetoed; fall through to "skip
        -- this spawner" so the empty pedestal stays hidden, same as the no-cap case.
    end

    -- All conversions used up — leave the spawner alone (empty pedestal stays hidden
    -- because adventure flow units only materialize after spawn).
    return
end)

-- Grant CW-pickup eligibility on adventure-level spawners that have analogous
-- adventure tags. Vanilla `PickupSystem._can_spawn` returns
-- `Unit.get_data(spawner, pickup_name) or Managers.mechanism:can_spawn_pickup(spawner, pickup_name)`.
-- For adventure spawners, neither path matches CW pickup types — they're tagged
-- `potions`/`painting_scrap`/`ammo`/etc., not `deus_potion`/`deus_cursed_chest`. So
-- our deus pickup counts in pickup_settings.primary result in "spawn debt" warnings
-- (engine wanted N, found 0 eligible spawners).
--
-- Mapping (only fires on injected adventure levels):
--   * potion spawners       → deus_potions   (any pickup in Pickups.deus_potions)
--   * painting_scrap spots  → deus_soft_currency (Pilgrim's Coin)
--   * non-claimed primaries → deus_weapon_chest (altars compete with ammo/healing
--                              for remaining primary spawn slots)
mod:hook("PickupSystem", "_can_spawn", function(func, self, spawner_unit, pickup_name)
    local ok = func(self, spawner_unit, pickup_name)
    if ok then return ok end

    if not on_injected_adventure_level() then return ok end

    -- Reserved for the tome/grim → Chest of Trials conversion (see
    -- _spawn_guaranteed_pickup hook below). Never let any CW pickup hijack
    -- these book spots.
    if Unit.get_data(spawner_unit, "tome") or Unit.get_data(spawner_unit, "grimoire") then
        return false
    end

    -- Triggered event spawners (lamp_oil barrels for wagon-escape, explosive_barrel
    -- for body-burn objectives, training_dummy_bob spawners, etc.) MUST stay
    -- exclusive to their tagged pickup type. The vanilla `_can_spawn` checks
    -- `Unit.get_data(spawner, pickup_name)` — only e.g. `lamp_oil = true` returns
    -- true. But `_spawn_guaranteed_pickup` iterates ALL pickup names, and our
    -- CW-type fallback below would otherwise add `healing_draught`, `strength_potion`,
    -- etc. to the candidate list, so a triggered barrel-spawner could roll a potion
    -- and break the scripted event. v0.6.32 burned this: barrels for "burn the bodies"
    -- type events sometimes appeared as potions.
    -- Same risk for guaranteed_spawn spawners (already filtered for tome/grim
    -- above) and specified spawners.
    if Unit.get_data(spawner_unit, "guaranteed_spawn") then
        return false
    end
    local triggered_spawn_id = Unit.get_data(spawner_unit, "triggered_spawn_id")
    if triggered_spawn_id and triggered_spawn_id ~= "" then
        return false
    end

    -- CW pickups accept any non-tome/grim, non-event primary spawner. They
    -- compete with vanilla ammo/healing/grenades for unclaimed slots.
    if Pickups and Pickups.deus_potions and Pickups.deus_potions[pickup_name] then
        return true
    end
    if pickup_name == "deus_soft_currency" then
        return true
    end
    if pickup_name == "deus_weapon_chest" then
        return true
    end

    -- v0.7.64: on injected adventure levels, ALSO allow vanilla campaign pickup
    -- categories (ammo, healing, grenades, potions, painting_scrap, level_events).
    -- Pre-v0.7.64 the comment block above incorrectly assumed vanilla `_can_spawn`
    -- already returned true on these — but for adventure levels running under the
    -- deus mechanism, `Managers.mechanism:can_spawn_pickup` routes to the deus
    -- mechanism's pickup whitelist which doesn't recognize campaign pickup names,
    -- and the per-spawner `Unit.get_data(spawner, pickup_name)` check often fails
    -- for category vs specific-name mismatches (spawner tagged "ammo=true" while
    -- pickup_name is "ammo_specific_X"). Result on Holly DLC adventure-injected
    -- levels (Magnus / Cemetery / Forest Ambush): ALL pickups silently vetoed —
    -- not just deus types — leaving the map with literally nothing on the ground.
    -- Burned in the 2026-05-19 3-player run: 13 spawn-debt warnings on magnus
    -- including ammo, healing, grenades — the vanilla pickup-types ct's earlier
    -- code path mistakenly assumed were handled before our hook.
    --
    -- Explicit allowlist (not `string.sub(cat, 1, 5) ~= "deus_"`) to keep
    -- `versus_objective`, `weave`, and other non-campaign categories out of the
    -- candidate set even if Fatshark adds them to the global Pickups table in a
    -- future patch. Tome/grim/guaranteed/triggered spawners are already filtered
    -- above; this fallback only fires on plain primary/secondary spawners.
    if Pickups then
        local ADVENTURE_CATS = { "ammo", "healing", "grenades", "potions",
            "painting_scrap", "level_events" }
        for _, category in ipairs(ADVENTURE_CATS) do
            local bucket = Pickups[category]
            if type(bucket) == "table" and bucket[pickup_name] then
                return true
            end
        end
    end

    return false
end)

-- v0.7.51: Belakor altar gate. Vanilla `can_spawn_belakor_locus` only returns true on
-- belakor-themed CW nodes (or arena_belakor). Adventure-injected campaign levels have
-- their own non-belakor themes, so the gate would reject every altar spawn even after
-- populate_pickups has requested one. Override: also return true on injected adventure
-- levels when host has force_belakor — gating mirrors the populate_pickups inject so
-- the two stay in sync.
mod:hook("DeusRunController", "can_spawn_belakor_locus", function(func, self)
    if func(self) then return true end
    if on_injected_adventure_level() and effective_setting("force_belakor") then
        return true
    end
    return false
end)

-- ============================================================
-- Respawn / Revive on Chest of Trials Completion
-- ============================================================

-- CLARIFY: STATES.OPEN = 3 in deus_cursed_chest_extension.lua. State transitions to OPEN at line
-- 174 of that file ONLY on the server, and ONLY when the curse encounter's terror event has ended
-- successfully. Hot-join clients enter HOTJOIN_OPEN (= 4) instead, so they do not trigger here.
local CURSED_CHEST_STATE_OPEN = 3
-- CLARIFY: DifficultyMapping["normal"] = "recruit" (difficulty_settings.lua:424). The string the
-- engine uses internally is "normal"; "recruit" is only the display name.
local DIFFICULTY_RECRUIT = "normal"
-- CLARIFY: peer_id -> true marker, set by the chest hook for any player whose health_state was
-- "dead" at the moment the chest opened. Consumed by the sync_health_state hook (THP override)
-- and the _respawn_player hook (wounded). Cleared in _respawn_player so a future Chest of Trials
-- in the same run can re-mark the same peer.
local pending_chest_respawn = {}

mod:hook_safe("DeusCursedChestExtension", "_set_state", function(self, state)
    -- v0.7.23: verbose diagnostic on every _set_state call so we can see in
    -- the log whether the hook is firing, what state it saw, and what player
    -- states were present at chest-open time. Strip once revive-on-open is
    -- confirmed working.
    mod:info("[chest-revive] _set_state fired, state=%s open_const=%s setting=%s is_server=%s",
        tostring(state), tostring(CURSED_CHEST_STATE_OPEN),
        tostring(effective_setting("respawn_on_chest_complete")),
        tostring(Managers and Managers.player and Managers.player.is_server))

    if state ~= CURSED_CHEST_STATE_OPEN then
        return
    end
    if not effective_setting("respawn_on_chest_complete") then
        mod:info("[chest-revive] setting OFF; bailing")
        return
    end
    if not Managers.player or not Managers.player.is_server then
        mod:info("[chest-revive] not server; bailing (this hook is host-authoritative)")
        return
    end

    local game_mode = Managers.state and Managers.state.game_mode
    if not game_mode then
        mod:info("[chest-revive] game_mode nil; bailing")
        return
    end

    local side = Managers.state.side and Managers.state.side:get_side_from_name("heroes")
    local party = side and side.party
    local occupied_slots = party and party.occupied_slots

    if occupied_slots then
        mod:info("[chest-revive] inspecting %d player slot(s)", #occupied_slots)
        for i = 1, #occupied_slots do
            local status = occupied_slots[i]
            local data = status.game_mode_data
            local peer_id = status.peer_id
            local local_player_id = status.local_player_id

            if peer_id and local_player_id then
                local player = Managers.player:player(peer_id, local_player_id)
                local unit = player and player.player_unit

                local health_state = data and data.health_state or "?"
                local is_knocked = false
                local is_disabled_pact = false
                if unit and Unit.alive(unit) then
                    local status_ext = ScriptUnit.has_extension(unit, "status_system")
                    if status_ext then
                        is_knocked = status_ext.is_knocked_down and status_ext:is_knocked_down() or false
                        is_disabled_pact = status_ext.is_disabled_by_pact_sworn and status_ext:is_disabled_by_pact_sworn() or false
                    end
                end
                mod:info("[chest-revive] slot[%d] peer=%s health_state=%s unit_alive=%s knocked=%s disabled_pact=%s",
                    i, tostring(peer_id), tostring(health_state),
                    tostring(unit and Unit.alive(unit) or false),
                    tostring(is_knocked), tostring(is_disabled_pact))

                -- Revive knocked-down players (immediate, skipping disabler-held ones).
                if unit and Unit.alive(unit) and is_knocked and not is_disabled_pact then
                    StatusUtils.set_revived_network(unit, true, nil)
                    mod:info("[chest-revive]   -> called set_revived_network on peer=%s", tostring(peer_id))
                end

                -- Mark dead-state players for the post-respawn THP/wounded overrides.
                if data and data.health_state == "dead" then
                    pending_chest_respawn[peer_id] = true
                    mod:info("[chest-revive]   -> marked peer=%s for pending_chest_respawn (dead-state)", tostring(peer_id))
                end
            end
        end
    else
        mod:info("[chest-revive] no occupied_slots; nothing to revive")
    end

    if game_mode.force_respawn_dead_players then
        game_mode:force_respawn_dead_players()
        mod:info("[chest-revive] called game_mode:force_respawn_dead_players()")
    else
        mod:info("[chest-revive] game_mode has no force_respawn_dead_players method")
    end
end)

-- CLARIFY: THP override on the dead-respawn path. sync_health_state reads
-- status.game_mode_data.temporary_health_percentage (player_unit_health_extension.lua:111), which
-- the engine sets from difficulty.respawn.temporary_health_percentage at respawn_handler.lua:358
-- (0 on Recruit/Veteran/Champion, 0.25 on Legend). Mutating to 0.5 just before sync reads it
-- means the spawn applies 50% of max-health THP without us touching the network game object
-- ourselves. The is_dead-at-chest-open guard means this only fires for our feature's respawns.
mod:hook("PlayerUnitHealthExtension", "sync_health_state", function(func, self)
    local player = self.player
    local peer_id = player and player.network_id and player:network_id()

    if peer_id and pending_chest_respawn[peer_id] then
        local status = Managers.party:get_player_status(peer_id, player:local_player_id())
        if status and status.game_mode_data and status.game_mode_data.health_state == "respawning" then
            status.game_mode_data.temporary_health_percentage = 0.5
        end
    end

    func(self)
end)

-- CLARIFY: Apply wounded (1 wound) on dead-respawn above Recruit. Mirrors the engine's own
-- post-revive wound at player_unit_health_extension.lua:277 — same reason string ("revived"),
-- which is one of the four valid entries in NetworkLookup.set_wounded_reasons. Recruit is skipped
-- because it has 5 max wounds and no real wounded mechanic in player perception. The flag is
-- cleared here so a subsequent dead-respawn (different chest, same run) re-arms via the chest
-- hook above instead of double-applying.
mod:hook_safe("RespawnHandler", "_respawn_player", function(self, player, profile_index, career_index, respawn_unit, ...)
    local peer_id = player and player.network_id and player:network_id()
    if not peer_id or not pending_chest_respawn[peer_id] then
        return
    end
    pending_chest_respawn[peer_id] = nil

    if Managers.state.difficulty:get_difficulty() == DIFFICULTY_RECRUIT then
        return
    end

    local unit = player.player_unit
    if not unit or not Unit.alive(unit) then
        return
    end

    local t = Managers.time:time("game")
    StatusUtils.set_wounded_network(unit, true, "revived", t)
end)

-- ============================================================
-- Starting Boons
-- ============================================================

-- Starting-boons hook. Vanilla `_add_initial_power_ups` adds talent power-ups + event
-- boons after run setup; we append toggled starting boons after that (hook_safe = post-call).
--
-- HOST-ONLY: the server processes the hook for every peer in the lobby and uses the
-- HOST's `start_boon_*` settings — so every player gets the same starting boons,
-- whatever the host picked. Clients early-out unconditionally and never apply their
-- own start_boon settings (and never duplicate the host's grant either, which was
-- the old bug). The server's `run_state:set_player_power_ups(peer_id, ...)` call
-- syncs the granted boons to the target peer via the shared-state networking layer.
-- QUESTION: The hook signature drops the 5th arg `initial_talents_for_career` (vanilla has 5
-- positional args). hook_safe ignores extra args so this is fine, but a future maintainer adding a
-- new arg might be confused.
-- POTENTIAL BUG (LOW): `mod:echo` fires on every player-add (incl. bots/late-join), spamming chat
-- with "Granted N starting boon(s)." Once per run would be cleaner.
mod:hook_safe("DeusRunController", "_add_initial_power_ups", function(self, peer_id, local_player_id, profile_index, career_index)
    local run_state = self._run_state
    if not run_state or not run_state:is_server() then return end  -- host-only
    if not DeusPowerUpsArray or not DeusPowerUpUtils then return end

    local extra = {}
    for _, entry in ipairs(DeusPowerUpsArray) do
        local name = entry.name
        if name and mod:get("start_boon_" .. name) then
            extra[#extra + 1] = DeusPowerUpUtils.generate_specific_power_up(name, entry.rarity)
        end
    end

    if #extra == 0 then return end

    -- CLARIFY: Re-fetching existing power-ups inside the hook (rather than capturing pre-call) is
    -- correct: the original func has already added talent + event boons by the time this fires
    -- (hook_safe = post-call). table.clone with skip_metatable keeps the array shape without
    -- copying any inherited methods.
    local skip_metatable = true
    local existing = run_state:get_player_power_ups(peer_id, local_player_id, profile_index, career_index)
    local new_power_ups = table.clone(existing, skip_metatable)
    table.append(new_power_ups, extra)
    run_state:set_player_power_ups(peer_id, local_player_id, profile_index, career_index, new_power_ups)

    -- Resolve the player's character + career for the chat message. SPProfiles maps
    -- profile_index → profile (Kruber/Bardin/Kerillian/Sienna/Saltzpyre) and
    -- profile.careers maps career_index → career (es_mercenary, dr_slayer, etc.).
    -- Both use localization keys for display; Localize() resolves them to the
    -- player-facing names.
    local profile = rawget(_G, "SPProfiles") and SPProfiles[profile_index]
    local character = profile and profile.display_name and Localize(profile.display_name) or "?"
    local career = profile and profile.careers and profile.careers[career_index]
    local career_name = career and career.display_name and Localize(career.display_name) or "?"
    -- Player slot in the party: peer_id + local_player_id. Use party-slot index if
    -- available so users can quickly identify which on-screen panel got the boons.
    local slot_label = ""
    local party_manager = Managers.party
    if party_manager and party_manager.get_status_from_unique_id then
        local status = party_manager:get_status_from_unique_id(peer_id, local_player_id)
        if status and status.party_id and status.slot_id then
            slot_label = string.format(" [P%d:S%d]", status.party_id, status.slot_id)
        end
    end

    mod:echo(string.format("Granted %d starting boon(s) to %s (%s)%s",
        #extra, character, career_name, slot_label))
end)

-- ============================================================
-- Bot Boon Mirror (v0.7.76)
-- ============================================================
-- When `bots_mirror_host_boons` is on, every boon a HUMAN host gains in Chaos
-- Wastes (shrine pick, altar reward, dormant reveal, Belakor temple, blessing
-- of the gods, set reward, end-of-level grant, etc.) is also granted to every
-- bot in the lobby.
--
-- The single canonical entry point for boon application is
-- `DeusRunController.add_power_ups(new_power_ups, local_player_id, present)`
-- (deus_run_controller.lua:1126). Every code path that grants a boon — chest
-- pickup, cursed chest, shop blessing, set completion, end-of-level node
-- (`try_grant_end_of_level_deus_power_ups` falls through to this), debug — funnels
-- through here. Hooking it once covers all sources.
--
-- HOST-ONLY: Bots are entirely client-side on the host (they don't exist as
-- bots on remote peers; remote peers see them as husk units with normal buff
-- replication via the server-authoritative buff_system). So mirroring only
-- runs on `_run_state:is_server()`.
--
-- Reentry guard: re-calling `add_power_ups` for each bot would re-enter this
-- hook → infinite recursion. `_ct_bot_mirror_active` short-circuits the nested
-- calls.
--
-- Talent vs buff boons: `DeusPowerUpUtils.activate_deus_power_up` (called from
-- `add_power_ups`) branches on `power_up.talent`. Buff boons land via
-- `buff_system:add_buff(player_unit, buff_name, ...)` which works identically
-- on bot units. Talent boons mutate the backend talent ids for the receiving
-- career — that's fine when the bot has the same career as the host, but if
-- the bot is on a different career the talent slot still gets written into
-- the bot's own backend so the per-bot talent set is independent. The buff
-- the talent grants is the same one the host got.
--
-- Set completion: `_check_set_completed` runs inside `add_power_ups` post-add
-- and may recursively call `add_power_ups` for set rewards. We let those run
-- normally; the guard wraps only our bot-iteration loop so any set rewards a
-- bot triggers also mirror correctly.
local _ct_bot_mirror_active = false

mod:hook_safe("DeusRunController", "add_power_ups", function(self, new_power_ups, local_player_id, present)
    if _ct_bot_mirror_active then return end
    if not effective_setting("bots_mirror_host_boons") then return end
    if not new_power_ups or #new_power_ups == 0 then return end

    local run_state = self._run_state
    if not run_state or not run_state:is_server() then return end

    -- Resolve who just got the boon. add_power_ups uses
    -- `run_state:get_own_peer_id()` for the recipient peer; the recipient
    -- local_player_id is the second arg. We want to mirror onto bots only when
    -- the recipient is a HUMAN (otherwise a bot's own grant would re-trigger
    -- the bot loop).
    local own_peer_id = run_state:get_own_peer_id()
    local recipient = Managers.player and Managers.player:player(own_peer_id, local_player_id)
    if recipient and recipient.bot_player then return end

    local player_manager = Managers.player
    if not player_manager or not player_manager.human_and_bot_players then return end
    local all_players = player_manager:human_and_bot_players()
    if not all_players then return end

    -- Filter bots and skip the recipient (defensive — recipient should be human
    -- per the check above, but harmless to double-check).
    local bots = {}
    for _, p in pairs(all_players) do
        if p ~= recipient and p.bot_player and p.player_unit and Unit.alive(p.player_unit) then
            bots[#bots + 1] = p
        end
    end
    if #bots == 0 then return end

    -- Clone the power-up list per-bot. Each call needs fresh client_ids so the
    -- run_state stores distinct entries (otherwise the same client_id appears
    -- across multiple players and `remove_power_ups` matching could mis-target).
    -- generate_specific_power_up assigns a new random id; we mirror by name+rarity.
    _ct_bot_mirror_active = true
    local ok, err = pcall(function()
        for _, bot in ipairs(bots) do
            local cloned = {}
            for i = 1, #new_power_ups do
                local pu = new_power_ups[i]
                cloned[i] = DeusPowerUpUtils.generate_specific_power_up(pu.name, pu.rarity)
            end
            -- present=false: don't trigger the reward-popup UI for bot grants.
            self:add_power_ups(cloned, bot:local_player_id(), false)
        end
    end)
    _ct_bot_mirror_active = false

    if not ok then
        mod:info("[bot-mirror] error mirroring boons to bots: %s", tostring(err))
        return
    end

    mod:info("[bot-mirror] mirrored %d boon(s) onto %d bot(s)", #new_power_ups, #bots)
end)

-- Per-bot late-respawn re-apply. CW's `_add_initial_power_ups` (host-side per
-- peer at run start) already grants bots the talent-boon defaults; the host's
-- early-run mirror calls during initial setup then propagate via the hook
-- above. The only respawn case that bypasses both is a mid-run bot career
-- swap (rare) — vanilla doesn't re-run _add_initial_power_ups in that case
-- and there is no general "bot career swap" event in CW. We accept this as a
-- known limit; users can disable + re-enable the bot to re-grant.

-- ============================================================
-- Grudge Mark Ban Menu (v0.7.76)
-- ============================================================
-- Per-mark checkboxes that exclude individual BreedEnhancements from the
-- monster-boss enhancement roll. Vanilla picks 1-3 enhancements per boss from
-- `BossGrudgeMarks` (grudge_mark_settings.lua) via
-- `TerrorEventUtils.generate_enhanced_breed` (terror_event_utils.lua:107).
--
-- Filter strategy: hook `add_enhancements_for_difficulty` (line 191) and pass
-- a filtered `enhancement_set` to `generate_enhanced_breed`. The function
-- iterates the set into a candidate list and randomly picks; an empty set
-- yields an empty list of enhancements, which is safe (the base entry is
-- still appended).
--
-- HOST-ONLY because enhancement assignment happens server-authoritatively
-- during boss spawn. Clients see the chosen enhancements via the spawn data
-- propagated by `add_enhancements_to_spawn_data`.
local BOSS_GRUDGE_MARK_NAMES = {
    "commander", "crippling", "crushing", "frenzy", "intangible",
    "periodic_curse", "periodic_shield", "raging", "ranged_immune",
    "regenerating", "unstaggerable", "vampiric", "warping",
}

local function _build_filtered_boss_grudge_marks(base_set)
    -- Build a filtered copy of `base_set` (defaults to vanilla
    -- BossGrudgeMarks). Drop any mark whose ban toggle is on. Returns the
    -- filtered set OR nil if nothing was banned (so vanilla path runs).
    base_set = base_set or rawget(_G, "BossGrudgeMarks")
    if not base_set then return nil end
    local filtered = {}
    local any_banned = false
    for name, _ in pairs(base_set) do
        local sid = "ban_grudge_mark_" .. name
        if effective_setting(sid) then
            any_banned = true
        else
            filtered[name] = true
        end
    end
    if not any_banned then return nil end
    return filtered
end

mod:hook("TerrorEventUtils", "add_enhancements_for_difficulty", function(func, optional_data, difficulty, breed_name, event, difficulty_tweak, enhancement_set)
    local is_server = Managers and Managers.player and Managers.player.is_server
    if not is_server then
        return func(optional_data, difficulty, breed_name, event, difficulty_tweak, enhancement_set)
    end

    -- Only override when caller passed BossGrudgeMarks (or nil, which defaults
    -- to BossGrudgeMarks inside vanilla on line 197). Other callers may pass
    -- custom sets (e.g. termite/dwarf-fest event variants) — leave those alone.
    local effective_set = enhancement_set
    if effective_set == nil or effective_set == rawget(_G, "BossGrudgeMarks") then
        local filtered = _build_filtered_boss_grudge_marks(rawget(_G, "BossGrudgeMarks"))
        if filtered then
            effective_set = filtered
        end
    end

    return func(optional_data, difficulty, breed_name, event, difficulty_tweak, effective_set)
end)

-- Resolve display strings for the 13 BreedEnhancements at boot. Internal
-- names map to localization keys via the `display_name` field on each
-- BreedEnhancements entry (grudge_mark_settings.lua). The strings live in
-- compiled localization data — Localize() resolves at runtime. We cache once
-- at module load so the data file's tooltips can include them; if Localize
-- isn't ready, fall back to title-cased internal names.
local function _resolve_grudge_mark_display_name(name)
    local be = rawget(_G, "BreedEnhancements")
    local entry = be and be[name]
    local dn_key = entry and entry.display_name or ("display_name_" .. name)
    if rawget(_G, "Localize") then
        local raw = Localize(dn_key)
        if raw and raw ~= "<" .. dn_key .. ">" then
            return raw
        end
    end
    -- Title-case fallback: "periodic_curse" -> "Periodic Curse"
    return (name:gsub("_", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

mod._ct_grudge_mark_display = mod._ct_grudge_mark_display or {}
for _, n in ipairs(BOSS_GRUDGE_MARK_NAMES) do
    mod._ct_grudge_mark_display[n] = _resolve_grudge_mark_display_name(n)
end

mod:command("dump_grudge_marks", "Dump the 13 BreedEnhancement names with resolved display strings", function()
    mod:info("[DUMP:grudge_marks] === %d Boss Grudge Marks ===", #BOSS_GRUDGE_MARK_NAMES)
    mod:info("[DUMP:grudge_marks] internal_name\tdisplay_name_key\tresolved_display")
    for _, name in ipairs(BOSS_GRUDGE_MARK_NAMES) do
        local be = rawget(_G, "BreedEnhancements")
        local entry = be and be[name]
        local dn_key = entry and entry.display_name or ("display_name_" .. name)
        local resolved = _resolve_grudge_mark_display_name(name)
        mod:info("[DUMP:grudge_marks] %s\t%s\t%s", name, dn_key, resolved)
    end
    mod:echo(string.format("dump_grudge_marks: %d entries dumped to log.", #BOSS_GRUDGE_MARK_NAMES))
end)

-- ============================================================
-- Modified Boons
-- ============================================================

-- CLARIFY: `reckless_swings_originals` doubles as a "tweak active" flag. Non-nil = tweak applied.
-- This avoids double-apply (which would save the already-modified values as "originals" and lose
-- the real originals).
local reckless_swings_originals = nil

-- CLARIFY: Khaine's Fury (internal name `deus_reckless_swings`) softening:
--   vanilla:  health threshold 0.50, self-damage 3 per melee hit
--   tweaked:  health threshold 0.25, self-damage 1 per melee hit
-- Patches THREE places: the on-buff template (governs gameplay), description_values[1] (the % shown
-- in tooltip's "above X% Health"), and description_values[3] (the damage shown). The `Localize`
-- hook below also overrides the description text since its formatting may not refer to
-- description_values directly.
local function apply_reckless_swings_tweak()
    if reckless_swings_originals then
        return
    end

    local power_up = rawget(_G, "DeusPowerUpTemplates")
    -- v0.7.24 bugfix: previous versions mutated DeusPowerUpBuffTemplates, but
    -- the runtime buff system reads from the GLOBAL `BuffTemplates` table which
    -- received COPIED values via DLCUtils.merge() at game boot
    -- (buff_templates.lua:9532). Mutating the source DeusPowerUpBuffTemplates
    -- has no effect on what the proc function reads — `template.damage_to_deal`
    -- inside `deus_reckless_swings_buff_on_hit` reads from BuffTemplates.
    -- Mutate BuffTemplates directly. Outer-buff health_threshold via
    -- DeusPowerUpTemplates still works because the apply path reads that
    -- table directly (deus_power_up_utils.lua:250).
    local runtime_buffs = rawget(_G, "BuffTemplates")
    if not power_up or not power_up.deus_reckless_swings then
        return
    end

    local tpl = power_up.deus_reckless_swings
    local runtime_buff_entry = runtime_buffs and runtime_buffs.deus_reckless_swings_buff

    -- POTENTIAL BUG (LOW): Hard-codes index [1] for buffs and [1]/[3] for description_values. If
    -- FatShark reorders these arrays in a patch, we silently mutate the wrong fields. A more
    -- defensive version would search by buff_to_add or description key.
    reckless_swings_originals = {
        health_threshold = tpl.buff_template.buffs[1].health_threshold,
        desc_1_value = tpl.description_values[1].value,
        desc_3_value = tpl.description_values[3].value,
        buff_damage = runtime_buff_entry and runtime_buff_entry.buffs[1].damage_to_deal,
    }

    tpl.buff_template.buffs[1].health_threshold = 0.25
    tpl.description_values[1].value = 0.25
    tpl.description_values[3].value = 1

    if runtime_buff_entry and runtime_buff_entry.buffs and runtime_buff_entry.buffs[1] then
        runtime_buff_entry.buffs[1].damage_to_deal = 1
    end

    mod:info("[khaines-fury] apply: threshold 0.50->0.25, damage_to_deal 3->1 (BuffTemplates entry=%s)",
        tostring(runtime_buff_entry ~= nil))
end

-- CLARIFY: Mirrors apply_reckless_swings_tweak. Note the early-out when DeusPowerUpTemplates is
-- gone (e.g. user left Chaos Wastes) — we still clear the originals flag so the next entry can
-- re-apply cleanly. This is the only path that nils the flag without doing the actual restore.
local function revert_reckless_swings_tweak()
    if not reckless_swings_originals then
        return
    end

    local power_up = rawget(_G, "DeusPowerUpTemplates")
    -- v0.7.24: revert from runtime BuffTemplates (same fix as apply).
    local runtime_buffs = rawget(_G, "BuffTemplates")
    if not power_up or not power_up.deus_reckless_swings then
        reckless_swings_originals = nil
        return
    end

    local tpl = power_up.deus_reckless_swings
    local runtime_buff_entry = runtime_buffs and runtime_buffs.deus_reckless_swings_buff

    tpl.buff_template.buffs[1].health_threshold = reckless_swings_originals.health_threshold
    tpl.description_values[1].value = reckless_swings_originals.desc_1_value
    tpl.description_values[3].value = reckless_swings_originals.desc_3_value

    if runtime_buff_entry and runtime_buff_entry.buffs and runtime_buff_entry.buffs[1] and reckless_swings_originals.buff_damage then
        runtime_buff_entry.buffs[1].damage_to_deal = reckless_swings_originals.buff_damage
    end

    reckless_swings_originals = nil
end

-- CLARIFY: Description override for Khaine's Fury lives in the consolidated _G.Localize
-- hook above (search for ADV_TITLE_OVERRIDES). Centralized to avoid the VMF
-- "Attempting to rehook active hook [Localize]" warning when two hooks compete for the
-- same target. The `reckless_swings_originals` gate ensures the override only fires
-- while the tweak is active.

-- CLARIFY: Assignment to the forward-declared `sync_reckless_swings`. From here on, references at
-- the top of the file (in generate_random_power_ups hook) and the on_setting_changed callback
-- below resolve to this function.
sync_reckless_swings = function()
    if effective_setting("tweak_reckless_swings") then
        apply_reckless_swings_tweak()
    else
        revert_reckless_swings_tweak()
    end
end

-- CLARIFY: Apply once at mod load. If the user has the toggle on AND DeusPowerUpTemplates is
-- already loaded (e.g. they enter the Keep, hot-reload doesn't apply since chaos_wastes_tweaker is
-- restart-only per CLAUDE.md), this immediately patches. Outside CW, DeusPowerUpTemplates is nil
-- and the apply silently no-ops; the generate_random_power_ups hook re-runs sync on first roll.
sync_reckless_swings()

-- ============================================================
-- Bomb Boon Cooldown Tweak
-- ============================================================
-- The `drop_item_on_ability_use` boon (rally flag / Morgrim's / Endless Bombs) reads its per-item
-- cooldowns from `buff_template.buffs[1].cooldown_durations` at proc time
-- (morris_buff_settings.lua:2830). Mutating that table in place lets us uniformly override the
-- vanilla 180/180/120 with a single configurable value. Mirrors the reckless_swings save-and-
-- restore pattern: the mutation persists across hook calls within a session, so on_disabled has
-- to revert it.

local bomb_cooldown_originals = nil

local function apply_bomb_cooldown_tweak()
    if bomb_cooldown_originals then
        return
    end
    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local tpl = power_up and power_up.drop_item_on_ability_use
    local buff_entry = tpl and tpl.buff_template and tpl.buff_template.buffs and tpl.buff_template.buffs[1]
    local durations = buff_entry and buff_entry.cooldown_durations
    if not durations then
        mod:info("[bomb-cooldown] DeusPowerUpTemplates.drop_item_on_ability_use not loaded yet; will retry on next boon roll")
        return
    end

    local override = effective_setting("bomb_boon_cooldown")
    if not override or override <= 0 then
        mod:info("[bomb-cooldown] override=%s (no change)", tostring(override))
        return
    end

    bomb_cooldown_originals = {}
    local before = {}
    for k, v in pairs(durations) do
        before[#before + 1] = string.format("%s=%d", k, v)
        bomb_cooldown_originals[k] = v
        durations[k] = override
    end
    mod:info("[bomb-cooldown] override=%d applied. Was: %s", override, table.concat(before, ", "))
end

local function revert_bomb_cooldown_tweak()
    if not bomb_cooldown_originals then
        return
    end
    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local tpl = power_up and power_up.drop_item_on_ability_use
    local buff_entry = tpl and tpl.buff_template and tpl.buff_template.buffs and tpl.buff_template.buffs[1]
    local durations = buff_entry and buff_entry.cooldown_durations
    if durations then
        for k, v in pairs(bomb_cooldown_originals) do
            durations[k] = v
        end
    end
    bomb_cooldown_originals = nil
end

sync_bomb_cooldown = function()
    -- Always revert first so a setting change from one positive value to another re-applies the
    -- new value (rather than silently no-op'ing because originals are already saved).
    revert_bomb_cooldown_tweak()
    local override = effective_setting("bomb_boon_cooldown")
    if override and override > 0 then
        apply_bomb_cooldown_tweak()
    end
end

sync_bomb_cooldown()

-- ============================================================
-- Ulric's Pack (wolfpack) Unlimited Aura Range
-- ============================================================
-- Vanilla `wolfpack` boon's proximity buff has `range_check = { radius = 20, ... }`
-- (deus_power_up_settings.lua:3829-3835). BuffAreaHelper.update_range_check reads
-- `range_check_template.radius` fresh on every tick (buff_area_helper.lua:26), so a
-- one-time mutation of that field is sufficient — no per-frame hook needed. Mirror
-- the bomb_cooldown save-and-restore pattern: on_setting_changed re-syncs without
-- restart, and revert lets toggling off restore vanilla 20m radius.
--
-- Per `feedback_vt2_gated_registration_diverges.md`: this only mutates an existing
-- vanilla template field; it never registers/unregisters the boon, never touches
-- BuffTemplates, NetworkLookup, or any sequential-index table. Safe to gate on the
-- per-user toggle. Host-authoritative: each peer mutates locally for their own
-- buff-extension proximity ticks, and the buff itself is applied via standard
-- buff-system propagation so client peers without the toggle still see the buff's
-- effect — they just compute their own proximity passes at vanilla 20m. Toggle the
-- host's setting and the host's proximity passes (which drive who gets the buff
-- via wolfpack_entered_range/wolfpack_left_range RPCs) ignore distance.

local wolfpack_radius_original = nil

local function apply_wolfpack_unlimited_range()
    if wolfpack_radius_original ~= nil then
        return
    end
    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local tpl = power_up and power_up.wolfpack
    local buff_entry = tpl and tpl.buff_template and tpl.buff_template.buffs and tpl.buff_template.buffs[1]
    local rc = buff_entry and buff_entry.range_check
    if not rc or type(rc.radius) ~= "number" then
        mod:info("[ulric-pack-range] DeusPowerUpTemplates.wolfpack not loaded yet; will retry on next sync")
        return
    end
    wolfpack_radius_original = rc.radius
    rc.radius = math.huge
    mod:info("[ulric-pack-range] radius %s -> math.huge", tostring(wolfpack_radius_original))
end

local function revert_wolfpack_unlimited_range()
    if wolfpack_radius_original == nil then
        return
    end
    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local tpl = power_up and power_up.wolfpack
    local buff_entry = tpl and tpl.buff_template and tpl.buff_template.buffs and tpl.buff_template.buffs[1]
    local rc = buff_entry and buff_entry.range_check
    if rc then
        rc.radius = wolfpack_radius_original
    end
    wolfpack_radius_original = nil
end

sync_ulric_pack_unlimited_range = function()
    revert_wolfpack_unlimited_range()
    if effective_setting("ulric_pack_unlimited_range") then
        apply_wolfpack_unlimited_range()
    end
end

sync_ulric_pack_unlimited_range()

-- ============================================================
-- Movement Speed Boon Tweak (5% -> 10%)
-- ============================================================
-- The vanilla `movespeed` boon (a one-of-a-kind CW mission-completion reward, boon-treated)
-- adds `apply_movement_buff` with multiplier 1.05 (sourced from
-- `MorrisBuffTweakData.movespeed.multiplier`) and shows "5%" in the tooltip (sourced from
-- `MorrisBuffTweakData.movespeed.description_value`). The values are baked at game load by
-- `deus_power_up_settings.lua` into two places:
--   * Gameplay: `DeusPowerUpBuffTemplates.power_up_movespeed_<rarity>.buffs[1].multiplier` (1.05),
--     one entry per rarity (common/rare/legendary).
--   * Tooltip:  `DeusPowerUpTemplates.movespeed.description_values[1].value` (0.05), shared by
--     all rarities via reference — a single mutation propagates to every rarity tooltip.
-- We mirror the reckless_swings save-and-restore: snapshot originals on apply, restore them on
-- revert, and call sync from the boon-roll hook + on_setting_changed.

local MOVESPEED_RARITIES = { "common", "rare", "legendary" }
local boon_movespeed_originals = nil

local function apply_boon_movespeed_tweak()
    if boon_movespeed_originals then
        return
    end

    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local buff_tpls = rawget(_G, "DeusPowerUpBuffTemplates")
    local tpl = power_up and power_up.movespeed
    if not tpl or not buff_tpls then
        return
    end

    local desc_value_entry = tpl.description_values and tpl.description_values[1]
    if not desc_value_entry then
        return
    end

    local per_rarity = {}
    for i = 1, #MOVESPEED_RARITIES do
        local rarity = MOVESPEED_RARITIES[i]
        local buff_entry = buff_tpls["power_up_movespeed_" .. rarity]
        local sub = buff_entry and buff_entry.buffs and buff_entry.buffs[1]
        if sub and sub.multiplier then
            per_rarity[rarity] = sub.multiplier
            sub.multiplier = 1.10
        end
    end

    boon_movespeed_originals = {
        desc_value = desc_value_entry.value,
        per_rarity = per_rarity,
    }

    desc_value_entry.value = 0.10
end

local function revert_boon_movespeed_tweak()
    if not boon_movespeed_originals then
        return
    end

    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local buff_tpls = rawget(_G, "DeusPowerUpBuffTemplates")
    local tpl = power_up and power_up.movespeed
    local desc_value_entry = tpl and tpl.description_values and tpl.description_values[1]

    if desc_value_entry then
        desc_value_entry.value = boon_movespeed_originals.desc_value
    end

    if buff_tpls then
        for rarity, original_mult in pairs(boon_movespeed_originals.per_rarity) do
            local buff_entry = buff_tpls["power_up_movespeed_" .. rarity]
            local sub = buff_entry and buff_entry.buffs and buff_entry.buffs[1]
            if sub then
                sub.multiplier = original_mult
            end
        end
    end

    boon_movespeed_originals = nil
end

sync_boon_movespeed = function()
    if effective_setting("tweak_boon_movespeed") then
        apply_boon_movespeed_tweak()
    else
        revert_boon_movespeed_tweak()
    end
end

sync_boon_movespeed()

-- ============================================================
-- Potion Reworks (v0.7.26-alpha)
-- ============================================================
-- BuffTemplates is the runtime merged table built by DLCUtils.merge at boot
-- (`buff_templates.lua:5568`-ish). Source `DLCSettings.morris.buff_templates` is the
-- per-DLC definition; mutating it after merge has no effect on what the runtime reads
-- (same gotcha as Khaine's Fury v0.7.24). All mutations target `BuffTemplates.<name>`
-- directly.
--
-- Pattern matches reckless_swings: snapshot originals once on apply, restore on revert,
-- re-run sync on settings change. The action's vanilla `_increased` resolution (in
-- `action_potion.lua:68`, gated on `potion_duration` perk) automatically picks up the
-- modified `_increased` variant when Decanter is held — no extra plumbing needed for
-- Decanter composition.
--
-- TODO v0.7.27: Home Brewer composition (+50% potency when home_brewer is held). Needs
-- a buff-apply hook + `_brewed` / `_brewed_increased` variant registration in
-- NetworkLookup.buff_templates.

-- --- Poison Proof duration tweak (vanilla 120s/240s -> 240s/360s) ---
local poison_proof_originals = nil

local function apply_poison_proof_tweak()
    if poison_proof_originals then
        return
    end
    local bt = rawget(_G, "BuffTemplates")
    local base = bt and bt.poison_proof_potion
    local inc = bt and bt.poison_proof_potion_increased
    local base_buff = base and base.buffs and base.buffs[1]
    local inc_buff = inc and inc.buffs and inc.buffs[1]
    if not base_buff or not inc_buff then
        mod:info("[poison-proof] BuffTemplates not loaded yet; will retry on settings sync")
        return
    end
    poison_proof_originals = {
        base = base_buff.duration,
        inc = inc_buff.duration,
    }
    base_buff.duration = 240
    inc_buff.duration = 360
    mod:info(string.format("[poison-proof] applied: base=%s -> 240, increased=%s -> 360",
        tostring(poison_proof_originals.base), tostring(poison_proof_originals.inc)))
end

local function revert_poison_proof_tweak()
    if not poison_proof_originals then
        return
    end
    local bt = rawget(_G, "BuffTemplates")
    local base_buff = bt and bt.poison_proof_potion and bt.poison_proof_potion.buffs and bt.poison_proof_potion.buffs[1]
    local inc_buff = bt and bt.poison_proof_potion_increased and bt.poison_proof_potion_increased.buffs and bt.poison_proof_potion_increased.buffs[1]
    if base_buff then base_buff.duration = poison_proof_originals.base end
    if inc_buff then inc_buff.duration = poison_proof_originals.inc end
    poison_proof_originals = nil
end

local function sync_poison_proof_tweak()
    if effective_setting("tweak_poison_proof_duration") then
        apply_poison_proof_tweak()
    else
        revert_poison_proof_tweak()
    end
end

sync_poison_proof_tweak()

-- --- Killer in the Shadows (invisibility potion) 2x duration ---
-- Vanilla: base 5s / increased 15s (MorrisBuffTweakData.killer_in_the_shadows_potion.duration).
-- BuffTemplates copies duration by value at template generation, so we mutate the
-- BuffTemplates entry directly (the MorrisBuffTweakData mutation is a no-op post-boot).
local invis_potion_originals = nil

local function apply_invis_potion_tweak()
    if invis_potion_originals then
        return
    end
    local bt = rawget(_G, "BuffTemplates")
    local base = bt and bt.killer_in_the_shadows_potion
    local inc = bt and bt.killer_in_the_shadows_potion_increased
    local base_buff = base and base.buffs and base.buffs[1]
    local inc_buff = inc and inc.buffs and inc.buffs[1]
    if not base_buff or not inc_buff then
        mod:info("[invis-potion] BuffTemplates not loaded yet; will retry on settings sync")
        return
    end
    invis_potion_originals = {
        base = base_buff.duration,
        inc = inc_buff.duration,
    }
    base_buff.duration = (invis_potion_originals.base or 5) * 2
    inc_buff.duration = (invis_potion_originals.inc or 15) * 2
    mod:info(string.format("[invis-potion] applied: base=%s -> %s, increased=%s -> %s",
        tostring(invis_potion_originals.base), tostring(base_buff.duration),
        tostring(invis_potion_originals.inc), tostring(inc_buff.duration)))
end

local function revert_invis_potion_tweak()
    if not invis_potion_originals then
        return
    end
    local bt = rawget(_G, "BuffTemplates")
    local base_buff = bt and bt.killer_in_the_shadows_potion and bt.killer_in_the_shadows_potion.buffs and bt.killer_in_the_shadows_potion.buffs[1]
    local inc_buff = bt and bt.killer_in_the_shadows_potion_increased and bt.killer_in_the_shadows_potion_increased.buffs and bt.killer_in_the_shadows_potion_increased.buffs[1]
    if base_buff then base_buff.duration = invis_potion_originals.base end
    if inc_buff then inc_buff.duration = invis_potion_originals.inc end
    invis_potion_originals = nil
end

local function sync_invis_potion_tweak()
    if effective_setting("tweak_invis_potion_2x") then
        apply_invis_potion_tweak()
    else
        revert_invis_potion_tweak()
    end
end

sync_invis_potion_tweak()

-- --- Hangover Brew (moot_milk) alternative effect ---
-- Vanilla buff structure (morris_buff_settings.lua:5804): 3 buffs
--   1. screenspace FX (`fx/screenspace_hungover_01`)
--   2. movespeed (apply_movement_buff, +50% MS for 1.5s)
--   3. damage (stat_buff increased_weapon_damage, multiplier 1)
-- Alt structure: 3 buffs for 60s
--   1. screenspace FX (keep hungover for visual feedback)
--   2. movement speed +25% for full duration
--   3. infinite_dodge perk
--   4. stamina regen (fatigue_regen stat_buff) +40%
-- Decanter automatically picks `_increased` (90s) via vanilla action_potion.lua resolution.

local moot_milk_originals = nil

local function build_moot_milk_alt_buffs(duration)
    return {
        {
            activation_effect = "fx/screenspace_drink_01",
            continuous_effect = "fx/screenspace_drink_looping",
            icon = "potion_hold_my_beer",
            max_stacks = 1,
            name = "moot_milk_potion",
            refresh_durations = true,
            remove_buff_func = "remove_deus_potion_buff",
            duration = duration,
        },
        {
            -- v0.7.50: WAS 0.25 (which is a literal multiplier on move_speed, so the player
            -- moved at 25% of base speed — a -75% slow). `apply_movement_buff` does
            -- `move_speed *= multiplier`; vanilla speed_boost_potion uses 1.5 for +50%.
            -- 1.25 = +25% as the surrounding comment / changelog have always claimed.
            apply_buff_func = "apply_movement_buff",
            max_stacks = 1,
            name = "moot_milk_potion_movement_speed_alt",
            refresh_durations = true,
            remove_buff_func = "remove_movement_buff",
            duration = duration,
            multiplier = 1.25,
            path_to_movement_setting_to_modify = {
                "move_speed",
            },
        },
        {
            max_stacks = 1,
            name = "moot_milk_potion_infinite_dodge_alt",
            refresh_durations = true,
            duration = duration,
            perks = {
                -- v0.7.44: was `buff_perks.infinite_dodge`. The `buff_perks` global is
                -- a `table.enum` map of name → name string. At mod-load timing it isn't
                -- always populated in `_G` (the buff system's perk_names file is
                -- required AFTER mods init in some load orders), so the lookup returned
                -- nil and the apply silently bailed at the `rawget(_G, "buff_perks")`
                -- gate below — meaning Moot Milk stayed vanilla for the whole session.
                -- Using the literal string is functionally identical (the buff system
                -- looks up perks by string key, which IS what `table.enum` stores).
                "infinite_dodge",
            },
        },
        {
            max_stacks = 1,
            name = "moot_milk_potion_stamina_regen_alt",
            refresh_durations = true,
            stat_buff = "fatigue_regen",
            duration = duration,
            multiplier = 0.40,
        },
    }
end

local function apply_moot_milk_alt_tweak()
    if moot_milk_originals then
        return
    end
    local bt = rawget(_G, "BuffTemplates")
    local base = bt and bt.moot_milk_potion
    local inc = bt and bt.moot_milk_potion_increased
    if not base or not inc then
        mod:info("[moot-milk-alt] BuffTemplates not loaded yet; will retry on settings sync")
        return
    end
    -- v0.7.44: removed `buff_perks` gate. The previous gate bailed when the global
    -- wasn't populated yet (logged in 2026-05-15 session); the replacement uses the
    -- literal string "infinite_dodge" in build_moot_milk_alt_buffs above, which is
    -- functionally equivalent and doesn't require the global.
    moot_milk_originals = {
        base_buffs = base.buffs,
        inc_buffs = inc.buffs,
    }
    base.buffs = build_moot_milk_alt_buffs(60)
    inc.buffs = build_moot_milk_alt_buffs(90)
    mod:info("[moot-milk-alt] applied: base=60s, increased=90s (+25%% MS, infinite dodge, +40%% stamina regen)")
end

local function revert_moot_milk_alt_tweak()
    if not moot_milk_originals then
        return
    end
    local bt = rawget(_G, "BuffTemplates")
    if bt and bt.moot_milk_potion then bt.moot_milk_potion.buffs = moot_milk_originals.base_buffs end
    if bt and bt.moot_milk_potion_increased then bt.moot_milk_potion_increased.buffs = moot_milk_originals.inc_buffs end
    moot_milk_originals = nil
end

local function sync_moot_milk_alt_tweak()
    if effective_setting("tweak_moot_milk_alt") then
        apply_moot_milk_alt_tweak()
    else
        revert_moot_milk_alt_tweak()
    end
end

sync_moot_milk_alt_tweak()

-- ============================================================
-- Shard Strike duration nerf (v0.7.28b-alpha)
-- ============================================================
-- Shard Strike (`armor_breaker` weapon trait) spawns a 16-second damaging stagger aura
-- around the player on killing an armoured enemy. Vanilla 16s is widely considered
-- overtuned (top-tier offensive AND defensive). This nerf lets the user shorten the
-- duration to any value 1-16s. At 16 = vanilla (no-op).
--
-- Mutates `WeaponTraits.buff_templates.armor_breaker.buffs[1].duration` directly. The
-- buff template is merged from `weapon_traits_morris.lua:980` (BuffUtils.apply_buff_tweak_data)
-- and registered at game boot, so the runtime value is whatever lives in WeaponTraits at
-- the moment add_buff is called. Mod load happens after merge, so our mutation takes
-- effect for all subsequent procs. ALSO mutates `BuffTemplates.armor_breaker` if present
-- (defensive — some merge paths copy into the global BuffTemplates).
local shard_strike_originals = nil

local function _shard_strike_buff_entries()
    local out = {}
    local wt = rawget(_G, "WeaponTraits")
    local wt_buff = wt and wt.buff_templates and wt.buff_templates.armor_breaker and wt.buff_templates.armor_breaker.buffs and wt.buff_templates.armor_breaker.buffs[1]
    if wt_buff then out[#out+1] = wt_buff end
    local bt = rawget(_G, "BuffTemplates")
    local bt_buff = bt and bt.armor_breaker and bt.armor_breaker.buffs and bt.armor_breaker.buffs[1]
    if bt_buff then out[#out+1] = bt_buff end
    return out
end

local function revert_shard_strike_tweak()
    if not shard_strike_originals then return end
    for _, b in ipairs(_shard_strike_buff_entries()) do
        b.duration = shard_strike_originals.duration
    end
    shard_strike_originals = nil
end

local function apply_shard_strike_tweak()
    local user_value = effective_setting("tweak_shard_strike_duration") or 16
    local target = math.max(1, math.min(16, user_value))
    if target == 16 then
        revert_shard_strike_tweak()
        return
    end
    local entries = _shard_strike_buff_entries()
    if #entries == 0 then
        mod:info("[shard-strike] WeaponTraits.buff_templates.armor_breaker not loaded yet; will retry on settings sync")
        return
    end
    if not shard_strike_originals then
        shard_strike_originals = { duration = entries[1].duration }
    end
    for _, b in ipairs(entries) do
        b.duration = target
    end
end

local function sync_shard_strike()
    apply_shard_strike_tweak()
end

sync_shard_strike()

-- ============================================================
-- Anath Raema's Swiftness — permanent reload speed (v0.7.36-alpha)
-- ============================================================
-- Vanilla: the trait `deus_ammo_pickup_reload_speed` watches `on_consumable_picked_up`
-- and adds a 10-second `deus_ammo_pickup_reload_speed_buff` (+50% reload speed) on
-- ammo pickup. This rework swaps the parent trait template for a passive permanent
-- +50% `reload_speed` stat_buff that's active whenever the weapon (with the trait) is
-- wielded.
--
-- Mutates BOTH `WeaponTraits.buff_templates.deus_ammo_pickup_reload_speed` (the trait
-- registry the trait system reads at apply time) AND `BuffTemplates.deus_ammo_pickup_reload_speed`
-- (the global runtime buff lookup). Save-and-restore so the toggle is reversible.
local anath_raema_originals = nil

local function _anath_raema_buff_entries()
    local out = {}
    local wt = rawget(_G, "WeaponTraits")
    if wt and wt.buff_templates and wt.buff_templates.deus_ammo_pickup_reload_speed then
        out[#out + 1] = { tbl = wt.buff_templates, key = "deus_ammo_pickup_reload_speed" }
    end
    local bt = rawget(_G, "BuffTemplates")
    if bt and bt.deus_ammo_pickup_reload_speed then
        out[#out + 1] = { tbl = bt, key = "deus_ammo_pickup_reload_speed" }
    end
    return out
end

local function revert_anath_raema_permanent_tweak()
    if not anath_raema_originals then return end
    for _, e in ipairs(_anath_raema_buff_entries()) do
        e.tbl[e.key] = anath_raema_originals.templates[e.key] or e.tbl[e.key]
    end
    anath_raema_originals = nil
end

local function apply_anath_raema_permanent_tweak()
    local entries = _anath_raema_buff_entries()
    if #entries == 0 then
        mod:info("[anath-raema] templates not loaded yet; will retry on settings sync")
        return
    end
    if anath_raema_originals then return end
    local saved = {}
    for _, e in ipairs(entries) do
        saved[e.key] = e.tbl[e.key]
    end
    anath_raema_originals = { templates = saved }

    -- Replacement template: single permanent stat_buff. multiplier = 0.5 matches the
    -- vanilla on-pickup multiplier from MorrisBuffTweakData.deus_ammo_pickup_reload_speed_buff.
    local replacement = {
        buffs = {
            {
                name        = "deus_ammo_pickup_reload_speed_permanent",
                stat_buff   = "reload_speed",
                multiplier  = 0.5,
                max_stacks  = 1,
            },
        },
    }
    for _, e in ipairs(entries) do
        e.tbl[e.key] = replacement
    end
end

local function sync_anath_raema_permanent()
    if effective_setting("tweak_anath_raema_permanent") then
        apply_anath_raema_permanent_tweak()
    else
        revert_anath_raema_permanent_tweak()
    end
end

sync_anath_raema_permanent()

-- ============================================================
-- Defeat Recovery: soft wipe recovery with penalty (v0.7.39-alpha)
-- ============================================================
-- When `tweak_defeat_recovery` is on and the team would wipe, instead force-respawn
-- everyone in place and apply a penalty: zero own coins + remove 5 random own boons.
-- The mission continues from the wipe point — this is NOT a full level reload (the
-- engine doesn't expose a safe mid-run "reload current level" path; that'd require a
-- full level transition with all the run-state replication that entails).
--
-- LIMITATIONS:
-- * Per-peer locality: each peer applies the penalty to their OWN coins and boons.
--   In MP, every peer needs ct with the toggle on for the team to share the rescue.
--   If only the host has ct, the host doesn't lose / the run continues, but other
--   peers' coins/boons are not modified.
-- * Recovery fires once per round (per level). Subsequent wipes on the same level end
--   the run normally. This prevents infinite loops and keeps recovery a finite resource.
-- * Reset on level transition via the existing `_transition_next_node` hook.
-- (Flag itself is forward-declared near the top of the file; just used here.)

local function _apply_local_defeat_penalty()
    local mechanism = Managers.mechanism and Managers.mechanism:game_mechanism()
    local deus_run_controller = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
    if not deus_run_controller then
        mod:info("[defeat-recovery] no deus_run_controller; skipping penalty")
        return
    end
    local run_state = deus_run_controller._run_state
    if not run_state then return end

    local local_peer_id = run_state:get_own_peer_id()
    local local_player_id = 1  -- REAL_PLAYER_LOCAL_ID per deus_run_controller.lua:29

    -- Zero own coins.
    run_state:set_player_soft_currency(local_peer_id, local_player_id, 0)
    mod:info("[defeat-recovery] zeroed own coins")

    -- Pick 5 random boons (or fewer if you have less than 5) and remove them.
    local profile_index, career_index = run_state:get_player_profile(local_peer_id, local_player_id)
    local power_ups = run_state:get_player_power_ups(local_peer_id, local_player_id, profile_index, career_index)
    if power_ups and #power_ups > 0 then
        local indices = {}
        for i = 1, #power_ups do indices[i] = i end
        local to_remove = math.min(5, #indices)
        local removed_names = {}
        for _ = 1, to_remove do
            local pick = math.random(#indices)
            local boon_idx = indices[pick]
            table.remove(indices, pick)
            local boon = power_ups[boon_idx]
            if boon and boon.name then
                removed_names[#removed_names + 1] = boon.name
                deus_run_controller:remove_power_ups(boon.name, local_player_id)
            end
        end
        mod:info(string.format("[defeat-recovery] removed %d boons: %s", #removed_names, table.concat(removed_names, ", ")))
    else
        mod:info("[defeat-recovery] no boons to remove")
    end
end

local function _force_respawn_team()
    if not Managers.state.game_mode then return end
    local game_mode = Managers.state.game_mode:game_mode()
    if game_mode and game_mode.force_respawn_dead_players then
        game_mode:force_respawn_dead_players()
        mod:info("[defeat-recovery] force-respawned dead players")
    end
end

mod:hook("GameModeDeus", "evaluate_end_conditions", function(func, self, ...)
    -- v0.7.64: host-synced. The hook itself only runs on the host (GameModeDeus is
    -- server-authoritative), so this read effectively gets the host's value either
    -- way — but using effective_setting keeps the lookup pattern uniform with the
    -- rest of the codebase and survives any future re-entry from a client context.
    if not effective_setting("tweak_defeat_recovery") then
        return func(self, ...)
    end
    if _defeat_recovery_triggered_this_round then
        -- Already burned the recovery for this round; normal end-condition resolution.
        return func(self, ...)
    end
    local ended, reason = func(self, ...)
    if ended and reason == "lost" then
        _defeat_recovery_triggered_this_round = true
        _apply_local_defeat_penalty()
        _force_respawn_team()
        mod:info("[defeat-recovery] intercepted wipe — penalty applied, players respawned, round continues")
        return false  -- Don't propagate the "lost" outcome.
    end
    return ended, reason
end)

-- ============================================================
-- Activate Dormant Boons (v0.7.29-alpha)
-- ============================================================
-- 9 boons defined in vanilla `DeusPowerUpTemplates` but NOT registered in
-- `DeusPowerUpRarityPool` — they can never roll in the active CW loot pool. Each has an
-- `activate_dormant_<boon>` toggle. When on, the boon is injected into the rarity pool
-- (and all derived tables: DeusPowerUps, DeusPowerUpsArray, DeusPowerUpsArrayByRarity,
-- DeusPowerUpsLookup, DeusPowerUpBuffTemplates) using the same construction pattern as
-- vanilla's registration loop at `deus_power_up_settings.lua:7121-7176`.
--
-- LIMITATIONS:
-- * Additive only — toggling OFF doesn't remove the boon from the active run; would
--   require a game restart to fully clear. The injection takes effect on the next CW
--   run setup (since the engine reads the pool at run start).
-- * Per-boon rarity is fixed; user can't currently choose a different rarity for a
--   given dormant boon. Defaults are sensible (powerful boons → exotic, weaker → rare).
-- IMPORTANT: vanilla boon rarities are { event, rare, exotic, unique } ONLY (see
-- deus_power_up_settings.lua:7032 `DeusPowerUpRarities`). "common" / "plentiful" are
-- weapon-drop rarities and do NOT exist for boons. `existing_power_ups_lut` is keyed
-- off DeusPowerUpRarities — injecting at a non-listed rarity crashes
-- `deus_power_up_utils.lua:189` when the boon ends up in `existing_power_ups`.
-- v0.7.37 fix: squats and deus_larger_clip moved from "common" → "rare".
local DORMANT_BOON_RARITY = {
    deus_ammo_pickup_give_allies_ammo    = "rare",
    deus_coin_pickup_regen               = "rare",
    deus_large_ammo_pickup_infinite_ammo = "exotic",
    deus_larger_clip                     = "rare",   -- v0.7.37 was "common", crashed
    deus_throw_speed_increase            = "rare",
    deus_timed_block_free_shot           = "exotic",
    deus_transmute_into_coins            = "rare",
    explosive_pushes_on_damage_taken     = "exotic",
    squats                               = "rare",   -- v0.7.37 was "common", crashed
}

local _injected_dormants = {}

-- v0.7.38/v0.7.40: Register a name in a NetworkLookup table. Vanilla builds these
-- lookups at boot from their backing global tables (BuffTemplates,
-- DeusPowerUpTemplates, etc.). Entries we add post-boot are NOT in the lookups, and
-- the lookup's __index metatable errors on unknown keys (network_lookup.lua:2354).
-- Append index→name and set the reverse name→index. rawget bypasses the
-- error-on-unknown-key metatable when checking for existing registration.
local function _register_in_network_lookup(lookup_key, name)
    if type(name) ~= "string" then return end
    local nl = rawget(_G, "NetworkLookup")
    local t = nl and nl[lookup_key]
    if not t then return end
    if rawget(t, name) then return end
    local idx = #t + 1
    t[idx] = name
    t[name] = idx
end

local function register_buff_in_network_lookup(buff_name)
    _register_in_network_lookup("buff_templates", buff_name)
end

local function register_power_up_in_network_lookup(power_up_name)
    _register_in_network_lookup("deus_power_up_templates", power_up_name)
end

local function inject_dormant_boon(power_up_name, rarity)
    if _injected_dormants[power_up_name] then return end

    -- v0.7.40: Register in NetworkLookup.deus_power_up_templates immediately. Vanilla
    -- code at deus_run_state_spec.lua:60, deus_run_controller.lua:1198 (and similar)
    -- looks up the power-up by name. Without registration the lookup errors when the
    -- player selects this boon at a chest (Crashify guid 9f697495 — burned in v0.7.39).
    register_power_up_in_network_lookup(power_up_name)

    -- v0.7.67: `DeusPowerUpRarityPool` (the pool table) is no longer read here —
    -- pool insertion moved to `_add_dormant_to_pool` below. Other globals stay.
    local templates        = rawget(_G, "DeusPowerUpTemplates")
    local power_ups        = rawget(_G, "DeusPowerUps")
    local array            = rawget(_G, "DeusPowerUpsArray")
    local array_by_rarity  = rawget(_G, "DeusPowerUpsArrayByRarity")
    local lookup           = rawget(_G, "DeusPowerUpsLookup")
    local buff_templates   = rawget(_G, "DeusPowerUpBuffTemplates")
    local settings         = rawget(_G, "DeusPowerUpSettings")
    local availability_t   = rawget(_G, "DeusPowerUpAvailabilityTypes")
    local tweak_data_glob  = rawget(_G, "MorrisBuffTweakData")

    if not (templates and power_ups and array and array_by_rarity and lookup and buff_templates) then
        mod:info("[dormant] DeusPowerUp* tables not loaded yet; skipping injection of " .. tostring(power_up_name))
        return
    end

    local template = templates[power_up_name]
    if not template then
        mod:info("[dormant] template not found for " .. tostring(power_up_name))
        return
    end

    local availability = (availability_t and {
        availability_t.cursed_chest,
        availability_t.weapon_chest,
        availability_t.shrine,
    }) or {}

    -- v0.7.67 split: the rarity-pool insert is no longer done here. It moved into
    -- `_add_dormant_to_pool` below, called separately and gated by the user's
    -- toggle. This function (`inject_dormant_boon`) now does all the network-
    -- relevant registration UNCONDITIONALLY at mod-load — `DeusPowerUpsLookup`,
    -- `DeusPowerUpsArray`, `DeusPowerUpsArrayByRarity`, `DeusPowerUps`,
    -- `NetworkLookup.deus_power_up_templates`, `NetworkLookup.buff_templates`,
    -- `BuffTemplates`, `DeusPowerUpBuffTemplates`. Same set of indices across
    -- every peer regardless of which `activate_dormant_*` or `enable_boon_*`
    -- toggles each has on. Only `DeusPowerUpRarityPool` (which determines what
    -- a peer actually has the *option* to roll) stays toggle-gated.
    --
    -- Why this matters: `DeusPowerUpsLookup[boon_id]` is indexed by an integer
    -- RPC parameter (deus_mechanism.lua:1256). If host's lookup table is
    -- ordered differently from client's, host's rpc_add_buff(id=N) resolves to
    -- a DIFFERENT boon on the client. Pre-0.7.67 the gate at the pool-insert
    -- was applied to the entire `inject_dormant_boon` call, so `deus_larger_clip`
    -- (and the other 8 dormants + 11 trait boons + ct_meta_movespeed +
    -- ct_kill_heal) appeared in the lookup table only on peers with their toggle
    -- on, drifting every subsequent boon's id by +1 per absent dormant.
    -- Burned ct v0.7.66 (same class as v0.7.59 / v0.7.60).

    -- Build the new_power_up record (mirrors vanilla deus_power_up_settings.lua:7121-7176).
    local new_power_up = {}
    new_power_up.name           = power_up_name
    new_power_up.rarity         = rarity
    new_power_up.mutators       = {}
    new_power_up.availability   = availability
    new_power_up.max_amount     = template.max_amount or 1
    new_power_up.incompatibility = template.incompatibility
    new_power_up.weight         = template.weight or (settings and settings.weight_by_rarity and settings.weight_by_rarity[rarity]) or 1

    if template.talent then
        new_power_up.talent       = true
        new_power_up.talent_tier  = template.talent_tier
        new_power_up.talent_index = template.talent_index
    else
        new_power_up.display_name        = template.display_name
        new_power_up.plain_display_name  = template.plain_display_name
        new_power_up.buff_name           = "power_up_" .. power_up_name .. "_" .. rarity
        new_power_up.advanced_description = template.advanced_description
        new_power_up.description_values  = template.description_values
        new_power_up.icon                = template.icon

        local buff_template = table.clone(template.buff_template)
        local tweak_data = tweak_data_glob and tweak_data_glob[power_up_name]
        if tweak_data then
            for k, v in pairs(tweak_data) do
                buff_template.buffs[1][k] = v
            end
        end
        buff_template.buffs[1].name = new_power_up.buff_name
        buff_templates[new_power_up.buff_name] = buff_template
        -- Also register in the global BuffTemplates table. Vanilla CW boons get here via a
        -- boot-time `table.merge_recursive(dlc_settings.buff_templates, DeusPowerUpBuffTemplates)`
        -- in morris_buff_settings.lua:7310 — but that merge happens BEFORE mods load. Runtime
        -- writes to DeusPowerUpBuffTemplates don't propagate, so BuffUtils.get_buff_template
        -- (buff_utils.lua:256, reads `BuffTemplates[name]`) returns nil → crash in
        -- buff_extension.lua:177 when the buff is applied. Mirror the write here.
        local global_bt = rawget(_G, "BuffTemplates")
        if global_bt then
            global_bt[new_power_up.buff_name] = buff_template
        end
        -- v0.7.38: Network sync of boon application reads NetworkLookup.buff_templates
        -- to translate buff_name → int ID. Vanilla builds the lookup at boot from
        -- BuffTemplates; our runtime additions aren't in it, and the table's
        -- __index metatable errors on unknown keys (network_lookup.lua:2354-2358).
        -- Crash: "Table buff_templates does not contain key: power_up_<name>_<rarity>"
        -- on the second peer / first network sync. Burned in ct v0.7.34 → v0.7.37.
        register_buff_in_network_lookup(new_power_up.buff_name)
    end

    -- 3. Register in all derived tables.
    power_ups[rarity] = power_ups[rarity] or {}
    power_ups[rarity][power_up_name] = new_power_up

    table.insert(array, new_power_up)
    new_power_up.id = #array

    array_by_rarity[rarity] = array_by_rarity[rarity] or {}
    table.insert(array_by_rarity[rarity], new_power_up)

    new_power_up.lookup_id = #lookup + 1
    lookup[#lookup + 1]    = new_power_up
    lookup[power_up_name]  = new_power_up

    _injected_dormants[power_up_name] = new_power_up
    mod:info(string.format("[dormant] injected %s at rarity %s (lookup_id=%d)", power_up_name, rarity, new_power_up.lookup_id))
end

-- v0.7.67: pool insertion is now its own gated step. See the long comment inside
-- `inject_dormant_boon` for why this split is necessary. Idempotent via
-- `_added_to_pool` table — safe to call repeatedly (e.g. from both pre-register
-- and the toggled sync_dormant_boons / register_trait_boon paths).
local _added_to_pool = {}
local function _add_dormant_to_pool(power_up_name, rarity)
    if _added_to_pool[power_up_name] then return end
    local record = _injected_dormants[power_up_name]
    if not record then
        mod:info("[dormant] _add_dormant_to_pool: " .. tostring(power_up_name) .. " not yet registered; skipping pool insert")
        return
    end
    local pool = rawget(_G, "DeusPowerUpRarityPool")
    if not pool then return end
    pool[rarity] = pool[rarity] or {}
    table.insert(pool[rarity], { power_up_name, record.availability, {} })
    _added_to_pool[power_up_name] = true
    mod:info(string.format("[dormant] added %s to %s rarity pool (now %d entries in that rarity)", power_up_name, rarity, #pool[rarity]))
end

-- v0.7.60: pre-register every dormant boon's buff template + NetworkLookup entries
-- at mod-load, regardless of activate_dormant_* toggle. This guarantees every
-- ct-running peer has identical `_G.BuffTemplates` / `DeusPowerUpBuffTemplates` /
-- `NetworkLookup.{buff_templates, deus_power_up_templates}` contents in the same
-- order. A host who has dormants active can RPC the resulting buff IDs to clients
-- who have those toggles OFF and the lookups resolve cleanly instead of crashing on
-- "Table buff_templates does not contain key: N" in network_lookup.lua:2514.
-- Pool injection (DeusPowerUpRarityPool / DeusPowerUps* / DeusPowerUpsLookup)
-- remains toggle-gated below so each user's offering pool still reflects their
-- preferences. Sorted iteration eliminates the latent pairs()-order risk where
-- two peers could otherwise register the same set in different sequences and
-- assign different network indices.
--
-- This is purely additive registration; `register_buff_in_network_lookup` /
-- `register_power_up_in_network_lookup` early-out if the name is already present,
-- and `BuffTemplates[name] = buff_template` is an idempotent overwrite with the
-- same value, so the subsequent toggle-gated `inject_dormant_boon` calls remain
-- safe and unchanged in behavior on the pool side.
local function pre_register_dormant_lookups()
    -- v0.7.67: fully register every dormant boon (NetworkLookup, buff templates,
    -- DeusPowerUps / Array / ArrayByRarity / Lookup) unconditionally in sorted
    -- order. Pool insertion stays toggle-gated in sync_dormant_boons. Replaces
    -- the v0.7.60 partial pre-register that only covered NetworkLookup names +
    -- buff templates — that left `DeusPowerUpsLookup` (which IS network-indexed
    -- per deus_mechanism.lua:1256) toggle-gated, causing lookup-id drift across
    -- peers with divergent activate_dormant_* toggles (burned 2026-05-19 in the
    -- multiplayer log scan: deus_larger_clip was inserted at lookup_id=165 on
    -- the client but absent on the host, shifting every later id by 1).
    local templates = rawget(_G, "DeusPowerUpTemplates")
    if not templates then
        mod:info("[dormant] pre-register skipped: DeusPowerUpTemplates not yet loaded")
        return
    end
    local keys = {}
    for k in pairs(DORMANT_BOON_RARITY) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, power_up_name in ipairs(keys) do
        local rarity = DORMANT_BOON_RARITY[power_up_name]
        inject_dormant_boon(power_up_name, rarity)
    end
    mod:info("[dormant] pre-registered %d dormants unconditionally for client compat", #keys)
end

local function sync_dormant_boons()
    -- v0.7.67: registration is now unconditional in pre_register_dormant_lookups.
    -- This pass only handles the pool insertion, which IS legitimately per-peer
    -- (each peer can choose which dormants they want to roll). _add_dormant_to_pool
    -- is idempotent so safe to call repeatedly.
    local keys = {}
    for k in pairs(DORMANT_BOON_RARITY) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, name in ipairs(keys) do
        local default_rarity = DORMANT_BOON_RARITY[name]
        if effective_setting("activate_dormant_" .. name) then
            _add_dormant_to_pool(name, default_rarity)
        end
    end
end

pre_register_dormant_lookups()
sync_dormant_boons()

-- ============================================================
-- Miracle of Ulric / Miracle of Isha (alternative blessing behaviors, v0.7.65)
-- ============================================================
-- Two host-synced toggles that REPLACE vanilla blessing behavior:
--   - tweak_miracle_of_ulric_persistent: vanilla blessing_of_power adds +50 to
--     each weapon's `power_level` field (deus_run_controller.lua:1671-1703).
--     That value EVAPORATES on weapon swap at an altar — the new weapon doesn't
--     have it. When the toggle is on, skip the vanilla weapon-mutation and
--     instead apply a persistent +50 power_level buff on every hero. Survives
--     swaps because it's on the player buff_extension, not the weapon entry.
--   - tweak_miracle_of_isha_alternative: vanilla blessing_of_isha runs a
--     mutator (mutator_blessing_of_isha.lua) that grants one team revive from
--     death. When the toggle is on, skip the mutator registration and instead
--     apply -25% damage_taken to every hero (persistent for the run).
--
-- Mirror writes to BuffTemplates (the global table) because the engine reads
-- via BuffUtils.get_buff_template which only consults that global; vanilla
-- merges DeusPowerUpBuffTemplates into it at boot, BEFORE mods load, so any
-- runtime writes to DeusPowerUpBuffTemplates alone are lost (per
-- feedback_vt2_dormant_buff_template_dual_register.md). Also register in
-- NetworkLookup.buff_templates via register_buff_in_network_lookup so the
-- rpc_add_buff sync path doesn't crash on unknown name.
local CT_BUFF_MIRACLE_OF_ULRIC = "ct_miracle_of_ulric"
local CT_BUFF_MIRACLE_OF_ISHA_AEGIS = "ct_miracle_of_isha_aegis"
local CT_BUFF_MIRACLE_OF_ISHA_WOUNDS = "ct_miracle_of_isha_wounds"

-- v0.7.66: Isha behavior is now a 3-way dropdown. Read it through this helper
-- because the v0.7.65 checkbox values (true/false) can persist in saved settings;
-- map true→"aegis" so users who enabled the old checkbox stay on Aegis after the
-- migration, false/nil→"vanilla". Reads via effective_setting → host-authoritative.
local function _get_isha_mode()
    local v = effective_setting("tweak_miracle_of_isha_alternative")
    if v == true then return "aegis" end
    if v == false or v == nil then return "vanilla" end
    return v
end

local function _register_miracle_buff_templates()
    local global_bt = rawget(_G, "BuffTemplates")
    local deus_bt = rawget(_G, "DeusPowerUpBuffTemplates")
    if not global_bt then
        mod:info("[miracle] BuffTemplates not loaded; cannot register")
        return
    end

    -- +50 power_level. Shape mirrors liquid_bravado_potion
    -- (morris_buff_settings.lua:5534-5546) for the stat_buff="power_level" + bonus
    -- plumbing; is_persistent flag matches deus_special_farm_max_health_buff
    -- (deus_power_up_settings.lua:231-242) so DeusSpawning saves+reapplies it
    -- across missions until the blessing is consumed at end of run.
    local ulric_tpl = {
        buffs = {
            {
                icon = "blessing_power_01",
                name = CT_BUFF_MIRACLE_OF_ULRIC,
                stat_buff = "power_level",
                bonus = 50,
                max_stacks = 1,
                is_persistent = true,
            },
        },
    }
    global_bt[CT_BUFF_MIRACLE_OF_ULRIC] = ulric_tpl
    if deus_bt then deus_bt[CT_BUFF_MIRACLE_OF_ULRIC] = ulric_tpl end
    register_buff_in_network_lookup(CT_BUFF_MIRACLE_OF_ULRIC)

    -- -25% damage_taken (NEGATIVE multiplier — vanilla pattern: ale_defence
    -- uses multiplier=-0.04 for 4% reduction at buff_templates.lua:5325-5333).
    local isha_tpl = {
        buffs = {
            {
                icon = "blessing_isha_01",
                name = CT_BUFF_MIRACLE_OF_ISHA_AEGIS,
                stat_buff = "damage_taken",
                multiplier = -0.25,
                max_stacks = 1,
                is_persistent = true,
            },
        },
    }
    global_bt[CT_BUFF_MIRACLE_OF_ISHA_AEGIS] = isha_tpl
    if deus_bt then deus_bt[CT_BUFF_MIRACLE_OF_ISHA_AEGIS] = isha_tpl end
    register_buff_in_network_lookup(CT_BUFF_MIRACLE_OF_ISHA_AEGIS)

    -- v0.7.66: Infinite-wounds variant (recruit-style: every down is revivable
    -- instead of the 2nd down being instant death). Mirrors vanilla CW boon
    -- `indomitable` (deus_power_up_settings.lua:5056-5073) — perks-only template
    -- with no stat_buff. The `infinite_wounds` perk makes GenericStatusExtension
    -- :set_wounded skip the wounds-counter decrement (generic_status_extension
    -- .lua:1443-1450), so `has_wounds_remaining` always returns true and the
    -- death-on-down branch at player_unit_health_extension.lua:812 is never taken.
    local isha_wounds_tpl = {
        buffs = {
            {
                icon = "blessing_isha_01",
                name = CT_BUFF_MIRACLE_OF_ISHA_WOUNDS,
                perks = { "infinite_wounds" },
                max_stacks = 1,
                is_persistent = true,
            },
        },
    }
    global_bt[CT_BUFF_MIRACLE_OF_ISHA_WOUNDS] = isha_wounds_tpl
    if deus_bt then deus_bt[CT_BUFF_MIRACLE_OF_ISHA_WOUNDS] = isha_wounds_tpl end
    register_buff_in_network_lookup(CT_BUFF_MIRACLE_OF_ISHA_WOUNDS)

    mod:info("[miracle] registered Ulric (+50 power), Isha-aegis (-25%% dmg taken), Isha-wounds (infinite wounds) buff templates")
end

_register_miracle_buff_templates()

-- Apply a persistent buff to every connected hero (host-only — the host-side
-- BuffSystem broadcasts add_buff via rpc_add_buff_synced so clients receive it
-- via the existing engine path). Both new buff templates are pre-registered in
-- NetworkLookup.buff_templates above, so the RPC dispatch is safe.
local function _apply_persistent_buff_to_all_heroes(buff_name)
    local is_server = Managers and Managers.player and Managers.player.is_server
    if not is_server then return end
    local side = Managers.state and Managers.state.side and Managers.state.side:get_side_from_name("heroes")
    local units = side and side.PLAYER_AND_BOT_UNITS
    if not units then return end
    local buff_system = Managers.state.entity and Managers.state.entity:system("buff_system")
    if not buff_system then return end
    for i = 1, #units do
        local u = units[i]
        if u and Unit.alive(u) then
            local be = ScriptUnit.has_extension(u, "buff_system")
            if be and not be:has_buff_type(buff_name) then
                buff_system:add_buff(u, buff_name, u)
            end
        end
    end
end

-- Single consolidated hook for both blessing overrides — VMF silently shadows
-- duplicate mod:hook on the same Class+method (feedback_vmf_hook_safe_no_chain.md).
mod:hook("DeusRunController", "_try_buy_blessing", function(func, self, buyer, blessing_name)
    -- v0.7.67 diagnostic: log every blessing_of_power entry regardless of toggle.
    -- The 2026-05-20 session showed zero entries despite the user reporting
    -- "Ulric wasn't purchaseable" — meaning the click was rejected at the UI
    -- layer (button greyed out) before reaching us. Next session will capture
    -- whether the click ever reaches _try_buy_blessing.
    if blessing_name == "blessing_of_power" then
        local toggle_on = effective_setting("tweak_miracle_of_ulric_persistent")
        local is_server = Managers and Managers.player and Managers.player.is_server
        local already = self:has_blessing(blessing_name)
        local coins = self._run_state:get_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID) or -1
        local cost = (DeusCostSettings and DeusCostSettings.shop and DeusCostSettings.shop.blessings
            and DeusCostSettings.shop.blessings[blessing_name]) or -1
        mod:info("[miracle] _try_buy_blessing entry: blessing=%s buyer=%s is_server=%s toggle=%s already=%s coins=%s cost=%s",
            tostring(blessing_name), tostring(buyer), tostring(is_server), tostring(toggle_on),
            tostring(already), tostring(coins), tostring(cost))
    end
    if blessing_name == "blessing_of_power" and effective_setting("tweak_miracle_of_ulric_persistent") then
        -- Replicate vanilla affordability / dedup guards from
        -- deus_run_controller.lua:1590-1599.
        if self:has_blessing(blessing_name) then
            mod:info("[miracle] Ulric rejected: has_blessing=true (already bought)")
            return false
        end
        local current_coins = self._run_state:get_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID)
        local blessing_cost = DeusCostSettings.shop.blessings[blessing_name]
        if current_coins < blessing_cost then
            mod:info("[miracle] Ulric rejected: coins=%d < cost=%d", current_coins, blessing_cost)
            return false
        end

        _apply_persistent_buff_to_all_heroes(CT_BUFF_MIRACLE_OF_ULRIC)

        -- Replicate vanilla accounting from deus_run_controller.lua:1705-1722 so
        -- the blessing appears in run-stats UI and the lifetime decrement runs.
        local skip_metatable = true
        local blessings_with_buyer = table.clone(self._run_state:get_blessings_with_buyer(), skip_metatable)
        blessings_with_buyer[blessing_name] = buyer
        self._run_state:set_blessings_with_buyer(blessings_with_buyer)
        self._run_state:set_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID, current_coins - blessing_cost)
        local bought_blessings = table.clone(self._run_state:get_bought_blessings(), skip_metatable)
        bought_blessings[#bought_blessings + 1] = blessing_name
        self._run_state:set_bought_blessings(bought_blessings)
        self:_add_coin_tracking_entry(buyer, REAL_PLAYER_LOCAL_ID, -blessing_cost, "blessing")

        mod:info("[miracle] Ulric (persistent +50 power) applied; vanilla weapon-power bump skipped")
        return true

    elseif blessing_name == "blessing_of_isha" then
        local isha_mode = _get_isha_mode()
        if isha_mode == "vanilla" then
            return func(self, buyer, blessing_name)
        end

        -- v0.7.66 fix (was v0.7.65 dedup bug): the prior implementation SKIPPED
        -- writing blessing_of_isha to blessings_with_buyer in an attempt to also
        -- suppress the auto-mutator activation. But `has_blessing` reads from
        -- blessings_with_buyer, so the shop let users re-buy the alternative on
        -- every visit and drain coins (deus_shop_view_v2.lua:854-867 also keys
        -- the "is_bought" indicator off that table). Now we DO write it (fixes
        -- the shop UX) and instead suppress the vanilla mutator behavior via
        -- the MutatorTemplates.blessing_of_isha.server_start_function hook below.
        if self:has_blessing(blessing_name) then return false end
        local current_coins = self._run_state:get_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID)
        local blessing_cost = DeusCostSettings.shop.blessings[blessing_name]
        if current_coins < blessing_cost then return false end

        if isha_mode == "wounds" then
            _apply_persistent_buff_to_all_heroes(CT_BUFF_MIRACLE_OF_ISHA_WOUNDS)
        else
            _apply_persistent_buff_to_all_heroes(CT_BUFF_MIRACLE_OF_ISHA_AEGIS)
        end

        local skip_metatable = true
        local blessings_with_buyer = table.clone(self._run_state:get_blessings_with_buyer(), skip_metatable)
        blessings_with_buyer[blessing_name] = buyer
        self._run_state:set_blessings_with_buyer(blessings_with_buyer)
        self._run_state:set_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID, current_coins - blessing_cost)
        local bought_blessings = table.clone(self._run_state:get_bought_blessings(), skip_metatable)
        bought_blessings[#bought_blessings + 1] = blessing_name
        self._run_state:set_bought_blessings(bought_blessings)
        self:_add_coin_tracking_entry(buyer, REAL_PLAYER_LOCAL_ID, -blessing_cost, "blessing")

        mod:info("[miracle] Isha alternative mode=%s applied; vanilla revive mutator suppressed", isha_mode)
        return true
    end

    return func(self, buyer, blessing_name)
end)

-- v0.7.66: Suppress vanilla Isha mutator when alternative mode is active.
-- Every entry point in mutator_blessing_of_isha.lua early-returns on
-- `not data.hero_side`:
--   - server_update_function:           line 168 — `if not data.hero_side then return end`
--   - server_player_disabled_function:  line 138 — same
--   - server_player_hit_function:       line 156 — same
--   - try_activate_blessing:            only called from the two above, so dead
-- Setting data.hero_side = nil in the post-start callback neutralizes the entire mutator.
--
-- IMPORTANT (v0.7.66 QA-found): the live dispatch target is
-- `template.server.start_function`, NOT `template.server_start_function`. The
-- engine wraps every mutator at `mutator_templates.lua:236-269` (runs at engine
-- boot, before mods) — `template.server_start_function` is left as a dead
-- field, the wrapper at template.server.start_function captures the original
-- via upvalue. Hooking the dead field compiled cleanly but suppressed nothing.
do
    local mut_templates = rawget(_G, "MutatorTemplates")
    local isha_template = mut_templates and mut_templates.blessing_of_isha
    local server_tbl = isha_template and isha_template.server
    if server_tbl and type(server_tbl.start_function) == "function" then
        mod:hook(server_tbl, "start_function", function(func, context, data, unit)
            func(context, data, unit)
            if _get_isha_mode() ~= "vanilla" then
                data.hero_side = nil
                mod:info("[miracle] Isha mutator neutralized at server.start_function (alternative mode active)")
            end
        end)
    else
        mod:info("[miracle] MutatorTemplates.blessing_of_isha.server.start_function not loaded at hook time; alternative-mode suppression skipped")
    end
end

-- ============================================================
-- Mod Boons: per-boon scaling (v0.7.30-alpha)
-- ============================================================
-- 4 new ct-injected boons modeled on vanilla `boon_meta_01` (Lileath's Favour: +1%
-- damage and +1% AS per active boon). Each scales different stats per total boon count.
-- Stat_buff names verified against `buff_templates.lua` (power_level_impact,
-- power_level_melee_cleave, critical_strike_chance, critical_strike_effectiveness,
-- max_health, healing_received, cooldown_regen — all are valid stacking_multiplier
-- entries except critical_strike_chance which is stacking_bonus).
--
-- IMPLEMENTATION (per boon):
--   1. Stack buff template added to BuffTemplates (the stat container)
--   2. Apply func added to BuffFunctionTemplates.functions (read by buff_extension
--      at line 397). on_boon_granted func added to the flat global `ProcFunctions`
--      table (read by buff_extension at line 1350). Both written via a factory that
--      shares the same proc body. v0.7.64 fix — pre-0.7.64 the granted func was
--      written only to BuffFunctionTemplates.functions and silently never fired.
--   3. Power-up template added to DeusPowerUpTemplates
--   4. Pool registration via `inject_dormant_boon` (the function is generic — it just
--      registers a power-up name + rarity into all the runtime tables)
--
-- LIMITATION: same as dormants — requires a new CW run to take effect (the engine
-- snapshots DeusPowerUpsArray at run setup). Toggle off doesn't remove the boon.
local CT_META_BOONS = {
    {
        name = "ct_meta_stagger",
        rarity = "exotic",
        icon = "deus_icon_meta_01",
        stat_buffs = {
            { stat_buff = "power_level_impact",         multiplier = 0.01 },
            { stat_buff = "power_level_melee_cleave",   multiplier = 0.01 },
        },
    },
    {
        name = "ct_meta_crit",
        rarity = "exotic",
        icon = "deus_icon_meta_01",
        stat_buffs = {
            { stat_buff = "critical_strike_chance",        bonus      = 0.01 },
            { stat_buff = "critical_strike_effectiveness", multiplier = 0.05 },
        },
    },
    {
        name = "ct_meta_health",
        rarity = "exotic",
        icon = "deus_icon_meta_01",
        stat_buffs = {
            { stat_buff = "max_health",        multiplier = 0.01 },
            { stat_buff = "healing_received",  multiplier = 0.01 },
        },
    },
    {
        name = "ct_meta_cooldown",
        rarity = "exotic",
        icon = "deus_icon_meta_01",
        stat_buffs = {
            { stat_buff = "cooldown_regen", multiplier = 0.02 },
        },
    },
    {
        name = "ct_meta_ammo",  -- v0.7.43: +5% total ammo per active boon
        rarity = "exotic",
        icon = "deus_icon_meta_01",
        stat_buffs = {
            -- v0.7.52: `apply_buff_func = "refresh_ranged_slot_buffs"` fires
            -- `ammo_extension:refresh_buffs()` on the player's ranged weapon every time the
            -- stack is added, which re-runs `_apply_buffs` and recomputes `_max_ammo`.
            -- v0.7.72: replaced with `ct_meta_ammo_refresh_capacity` which ALSO refreshes
            -- overcharge_extension (Sienna staves, Bardin drakefire) and energy_extension
            -- (Moonfire Bow). See registration block above CT_META_BOONS.
            { stat_buff = "total_ammo",     multiplier = 0.05, apply_buff_func = "ct_meta_ammo_refresh_capacity" },
            -- v0.7.72: max_overcharge scales the overcharge bar capacity for Sienna staves
            -- and Bardin drakefire/drake-pistols (both use PlayerUnitOverchargeExtension
            -- which reads this key at `_calculate_and_set_buffed_max_overcharge_values`).
            -- Vanilla recalcs only at extensions_ready (wield) and on_overcharge_lost; the
            -- custom apply func above forces an immediate recalc so the stack lands live.
            { stat_buff = "max_overcharge", multiplier = 0.05 },
        },
        -- v0.7.72: Coverage is now ammo + overcharge + Moonfire energy. Inert only on the
        -- (unlikely) loadout with no ranged weapon at all.
    },
}

-- Shared body for apply + granted. Brings the stack count up to the current boon count
-- by adding the delta only. Both procs use the same body so the result is idempotent
-- regardless of which fires first (vanilla CW fires `on_boon_granted` BEFORE
-- `activate_deus_power_up` for newly-granted boons, so when Quiver Cascade is the first
-- ct_meta_* boon a player has the apply func is what does the initial stack — for
-- subsequent boon grants only `granted` fires).
--
-- v0.7.53 fixes two bugs in the prior implementation:
--   1. `num_buff_stacks(stack_name)` returned 0 always — the actual stored key is the
--      SUB-buff's `.name`, which we set to `stack_name .. "_" .. i` in the factory. So the
--      granted func couldn't see existing stacks and re-added the full boon count on every
--      subsequent grant, producing quadratic stack growth (triangular sum across boons).
--   2. The apply path used `for 1, num_boons` with no existing-stacks check. Same fix.
--
-- The query uses the `_1` suffix (the first sub-buff's name). All meta specs have at least
-- one sub-buff, and add_buff(stack_name) increments every sub-buff's stack in lockstep, so
-- counting one of them is enough.
local function _make_meta_proc(stack_name)
    local stack_key = stack_name .. "_1"
    return function(unit, buff, params)
        local player = Managers.player and Managers.player:owner(unit)
        if not player then return end
        local buff_extension = ScriptUnit.extension(unit, "buff_system")
        if not buff_extension then return end
        local deus_run_controller = Managers.mechanism:game_mechanism():get_deus_run_controller()
        if not deus_run_controller then return end
        local num_boons = #deus_run_controller:get_player_power_ups(player:network_id(), player:local_player_id())
        local num_existing = buff_extension:num_buff_stacks(stack_key)
        for _ = num_existing + 1, num_boons do
            buff_extension:add_buff(stack_name)
        end
    end
end

local function register_meta_boon(spec)
    local power_ups      = rawget(_G, "DeusPowerUpTemplates")
    local buff_templates = rawget(_G, "BuffTemplates")
    local buff_funcs     = rawget(_G, "BuffFunctionTemplates")
    local proc_functions = rawget(_G, "ProcFunctions")
    if not (power_ups and buff_templates and buff_funcs and buff_funcs.functions and proc_functions) then
        mod:info("[mod-boon] global tables not ready for " .. spec.name)
        return
    end
    local stack_name   = spec.name .. "_stack"
    local apply_name   = spec.name .. "_apply"
    local granted_name = spec.name .. "_granted"

    -- 1. Proc functions. Same body for both — apply fires when this meta boon itself is
    -- granted; granted fires on every subsequent boon. Both should bring stack count to
    -- the current boon count, idempotently.
    -- v0.7.64: on_boon_granted handlers are resolved via the flat `ProcFunctions` global
    -- (buff_extension.lua:1350), NOT `BuffFunctionTemplates.functions`. Apply funcs read
    -- from the latter (buff_extension.lua:397). Writing to only one table = granted proc
    -- silently never fires; the per-boon stack only refreshes on next mission load when
    -- apply runs fresh. Same root-cause shape as v0.7.57 chain_lightning fix.
    local proc = _make_meta_proc(stack_name)
    buff_funcs.functions[apply_name]   = proc
    buff_funcs.functions[granted_name] = proc
    proc_functions[granted_name]       = proc

    -- 2. Stack buff template
    local stack_buffs = {}
    for i, sb in ipairs(spec.stat_buffs) do
        local entry = {
            name = stack_name .. "_" .. i,
            stat_buff = sb.stat_buff,
            max_stacks = math.huge,
        }
        if sb.multiplier      then entry.multiplier      = sb.multiplier      end
        if sb.bonus           then entry.bonus           = sb.bonus           end
        if sb.apply_buff_func then entry.apply_buff_func = sb.apply_buff_func end
        stack_buffs[i] = entry
    end
    buff_templates[stack_name] = { buffs = stack_buffs }
    register_buff_in_network_lookup(stack_name)

    -- 3. Power-up template
    power_ups[spec.name] = {
        advanced_description = "description_" .. spec.name,
        display_name         = "display_name_" .. spec.name,
        icon                 = spec.icon,
        max_amount           = 1,
        rectangular_icon     = true,
        buff_template = {
            buffs = {
                {
                    apply_buff_func = apply_name,
                    buff_func       = granted_name,
                    event           = "on_boon_granted",
                    name            = spec.name,
                },
            },
        },
        description_values = {},
    }

    -- 4. Register network-relevant tables + add to rarity pool. v0.7.67 split:
    -- inject_dormant_boon does the registration; _add_dormant_to_pool does the
    -- pool insert. Meta boons are unconditional (not toggle-gated), so always
    -- both — same peer-side behavior as pre-0.7.67.
    inject_dormant_boon(spec.name, spec.rarity)
    _add_dormant_to_pool(spec.name, spec.rarity)
    mod:info("[mod-boon] registered " .. spec.name .. " at rarity " .. spec.rarity)
end

-- v0.7.72: Custom apply_buff_func for ct_meta_ammo. Vanilla `refresh_ranged_slot_buffs`
-- only touches AmmoExtension; we extend it to also force-refresh the player's
-- OverchargeExtension (Sienna staves, Bardin drakefire) and EnergyExtension (Moonfire
-- Bow) so the new `max_overcharge` stack lands without requiring a weapon swap.
--
-- - OverchargeExtension calls `_calculate_and_set_buffed_max_overcharge_values` at
--   extensions_ready and `on_overcharge_lost` (`player_unit_overcharge_extension.lua:103,206`).
--   Calling it explicitly here picks up the new buff stack immediately.
--
-- - EnergyExtension reads `_max_energy = energy_data.max_value` at init and never
--   recalculates — there is NO stat_buff path in vanilla. We scale `_max_energy` and
--   `_energy` proportionally so the bar resizes mid-mission. The boon count is queried
--   from the deus_run_controller so the value is correct regardless of when this fires.
do
    local buff_funcs = rawget(_G, "BuffFunctionTemplates")
    if buff_funcs and buff_funcs.functions then
        buff_funcs.functions.ct_meta_ammo_refresh_capacity = function (unit, buff, params)
            -- 1. Vanilla ammo refresh (preserved from old `refresh_ranged_slot_buffs`).
            local inventory_extension = ScriptUnit.has_extension(unit, "inventory_system")
            if inventory_extension then
                local ranged_slot_data = inventory_extension:get_slot_data("slot_ranged")
                if ranged_slot_data then
                    local left_hand_unit  = ranged_slot_data.left_unit_1p
                    local right_hand_unit = ranged_slot_data.right_unit_1p
                    local left_ammo  = left_hand_unit  and ScriptUnit.has_extension(left_hand_unit,  "ammo_system")
                    local right_ammo = right_hand_unit and ScriptUnit.has_extension(right_hand_unit, "ammo_system")
                    if left_ammo  then left_ammo:refresh_buffs()  end
                    if right_ammo then right_ammo:refresh_buffs() end
                end
            end

            -- 2. Overcharge refresh — Sienna staves, Bardin drakegun/drake-pistols. The
            -- extension lives on the player_unit (not the weapon unit), so the call site
            -- target is `unit` itself.
            local overcharge_ext = ScriptUnit.has_extension(unit, "overcharge_system")
            if overcharge_ext and overcharge_ext._calculate_and_set_buffed_max_overcharge_values then
                -- pcall guard: if `original_max_value` happens to be nil (e.g. extension
                -- not yet through extensions_ready), the recalc fasserts on the network
                -- bounds check. Silent-skip in that case; next wield will pick it up.
                pcall(overcharge_ext._calculate_and_set_buffed_max_overcharge_values, overcharge_ext)
            end

            -- 3. Energy refresh — Moonfire Bow (we_deus_01). Vanilla has no buff hook, so
            -- we mutate `_max_energy` ourselves. We compute the desired multiplier from
            -- the live boon count (each stack = +5%) and scale relative to the recorded
            -- base. First entry stashes the base on the extension; later entries scale
            -- from that base.
            local energy_ext = ScriptUnit.has_extension(unit, "energy_system")
            if energy_ext then
                local player = Managers.player and Managers.player:owner(unit)
                local deus_run_controller = Managers.mechanism
                    and Managers.mechanism:game_mechanism()
                    and Managers.mechanism:game_mechanism().get_deus_run_controller
                    and Managers.mechanism:game_mechanism():get_deus_run_controller()
                if player and deus_run_controller then
                    local num_boons = #deus_run_controller:get_player_power_ups(player:network_id(), player:local_player_id())
                    -- Stash the unbuffed base the first time we touch this extension.
                    if energy_ext._ct_meta_ammo_base_max == nil then
                        energy_ext._ct_meta_ammo_base_max = energy_ext._max_energy
                    end
                    local base    = energy_ext._ct_meta_ammo_base_max
                    local new_max = base * (1.0 + 0.05 * num_boons)
                    -- Network field max_energy is a clamped int — round + clamp to int32
                    -- range to avoid future fassert if anyone bolts a similar network
                    -- field onto energy like the overcharge path does.
                    new_max = math.max(1, math.floor(new_max + 0.5))
                    local prev_max = energy_ext._max_energy
                    if prev_max ~= new_max then
                        local fraction = (prev_max > 0) and (energy_ext._energy / prev_max) or 1.0
                        energy_ext._max_energy = new_max
                        energy_ext._energy     = math.min(new_max, math.max(0, fraction * new_max))
                    end
                end
            end
        end
    else
        mod:info("[mod-boon] BuffFunctionTemplates not ready — ct_meta_ammo_refresh_capacity deferred (boon load order)")
    end
end

for _, spec in ipairs(CT_META_BOONS) do
    register_meta_boon(spec)
end

-- Movement Speed meta boon (v0.7.35): +1% MS per active boon, exotic. Diverges from the
-- stat_buff pattern used by CT_META_BOONS because plain `stat_buff = "movement_speed"`
-- isn't read by any vanilla code — movement speed must be modified via the
-- `apply_movement_buff` / `remove_movement_buff` function pair (which directly mutates
-- the move_speed value via path_to_movement_setting_to_modify).
--
-- Compounding caveat: each stack calls apply_movement_buff with multiplier 1.01, so N
-- stacks = move_speed * 1.01^N. At +1% per stack the compounding is tiny (10 stacks =
-- ~+10.5% vs +10% additive). Acceptable — tooltip says additive for player comprehension.
do
    local power_ups      = rawget(_G, "DeusPowerUpTemplates")
    local buff_templates = rawget(_G, "BuffTemplates")
    local buff_funcs     = rawget(_G, "BuffFunctionTemplates")
    local proc_functions = rawget(_G, "ProcFunctions")
    if power_ups and buff_templates and buff_funcs and buff_funcs.functions and proc_functions then
        local stack_name   = "ct_meta_movespeed_stack"
        local apply_name   = "ct_meta_movespeed_apply"
        local granted_name = "ct_meta_movespeed_granted"
        -- v0.7.56: was `_make_meta_apply` / `_make_meta_granted`. Those were consolidated
        -- into `_make_meta_proc` in v0.7.53 but this special-cased movespeed block was
        -- missed in the rename — module-load crashed with "attempt to call global
        -- '_make_meta_apply' (a nil value)". `_make_meta_proc` looks up existing stack
        -- count via `num_buff_stacks(stack_name .. "_1")`, so the sub-buff's `name`
        -- field has to use that exact key (was bare "ct_meta_movespeed_stack" prior).
        -- v0.7.64: also write granted proc to ProcFunctions (see register_meta_boon comment).
        local proc = _make_meta_proc(stack_name)
        buff_funcs.functions[apply_name]   = proc
        buff_funcs.functions[granted_name] = proc
        proc_functions[granted_name]       = proc
        buff_templates[stack_name] = {
            buffs = {
                {
                    apply_buff_func = "apply_movement_buff",
                    remove_buff_func = "remove_movement_buff",
                    name             = "ct_meta_movespeed_stack_1",
                    max_stacks       = math.huge,
                    multiplier       = 1.01,
                    path_to_movement_setting_to_modify = { "move_speed" },
                },
            },
        }
        register_buff_in_network_lookup(stack_name)
        power_ups.ct_meta_movespeed = {
            advanced_description = "description_ct_meta_movespeed",
            display_name         = "display_name_ct_meta_movespeed",
            icon                 = "deus_icon_meta_01",
            max_amount           = 1,
            rectangular_icon     = true,
            buff_template = {
                buffs = {
                    {
                        apply_buff_func = apply_name,
                        buff_func       = granted_name,
                        event           = "on_boon_granted",
                        name            = "ct_meta_movespeed",
                    },
                },
            },
            description_values = {},
        }
        inject_dormant_boon("ct_meta_movespeed", "exotic")
        _add_dormant_to_pool("ct_meta_movespeed", "exotic")
        mod:info("[mod-boon] registered ct_meta_movespeed at rarity exotic")
    end
end

-- ============================================================
-- Mod Boon: Khaine's Communion — 1 green HP per kill (v0.7.32-alpha)
-- ============================================================
-- Heal 1 permanent (green) health every time the player kills an enemy. Exotic rarity.
-- Catalogued under Defensive > Health in the boon tree (per user verdict — health-themed
-- effect groups by effect, not by mod-added origin), but display name carries the
-- "(Mod Boon)" prefix so it's flagged.
--
-- Implementation: proc function with `authority = "server"` so the heal fires once
-- per kill on the server, then `DamageUtils.heal_network` networks the heal to the
-- killer's owning peer. Heal type `heal_from_proc` restores permanent HP (green),
-- not THP.
-- ============================================================
-- Mod Boons: Trait-as-Boon (v0.7.34-alpha)
-- ============================================================
-- 4 weapon traits re-introduced as opt-in exotic boons. Each is gated behind its own
-- toggle in Reworks > Reworks: Boons (default off). When enabled, the trait's buff
-- template is cloned into a new power-up at exotic rarity.
--
-- STACKING WITH TRAIT:
-- * Vaul's Anvil — naturally non-stacks (always_blocking is a binary perk; having two
--   sources of the same perk = same effect as one source).
-- * Manann's Tempest — stacks (each buff fires its own chain_lightning proc on crit,
--   so 2 buffs = 2 independent chains per crit).
-- * Taal's Twinned Arrow — stacks (extra_shot stat_buff bonus is additive: 2 buffs =
--   +2 projectiles).
-- * Asuryan's Wrath — stacks (each fires its own proc roll on melee kill, so 2 buffs
--   = roughly +75% effective proc chance vs +50% baseline).
--
-- TAAL'S TWINNED ARROW RESTRICTION: user asked for "only granted if ranged weapon in
-- slot 2." Vanilla VT2 careers all have a ranged slot, so the case is rare. If the
-- player ends up with this boon but no ranged weapon, the stat_buff is just inert
-- (no shots fire = no extra projectiles). Skipping the gate for v0.7.34; can add an
-- offer-time filter if it becomes a real issue.
local CT_TRAIT_BOONS = {
    { name = "ct_boon_vauls_anvil",         toggle = "enable_boon_vauls_anvil",         rarity = "unique", icon = "deus_icon_meta_01", source_buff = "always_blocking" },
    { name = "ct_boon_manann_tempest",      toggle = "enable_boon_manann_tempest",      rarity = "unique", icon = "deus_icon_meta_01", source_buff = "deus_crit_chain_lightning" },
    { name = "ct_boon_taal_twinned_arrow",  toggle = "enable_boon_taal_twinned_arrow",  rarity = "unique", icon = "deus_icon_meta_01", source_buff = "deus_extra_shot" },
    { name = "ct_boon_asuryan_wrath",       toggle = "enable_boon_asuryan_wrath",       rarity = "unique", icon = "deus_icon_meta_01", source_buff = "deus_collateral_damage_on_melee_killing_blow" },
}

local function register_trait_boon(spec)
    -- v0.7.67: registration (NetworkLookup, buff template, DeusPowerUps* sides)
    -- now happens unconditionally in pre_register_trait_boon_lookups. This
    -- function is only responsible for the toggle-gated pool insert, which
    -- determines whether the user actually rolls the boon.
    if not effective_setting(spec.toggle) then return end
    _add_dormant_to_pool(spec.name, spec.rarity)
    mod:info("[trait-boon] enabled " .. spec.name .. " at rarity " .. spec.rarity)
end

-- v0.7.61: same shape as pre_register_dormant_lookups (v0.7.60). The gated
-- register_trait_boon below skips registration entirely when the peer's
-- enable_boon_<name> toggle is off, so without this pre-registration step two
-- peers with different toggle states (host enables Vaul's Anvil + Manann's
-- Tempest, client only enables Manann's Tempest) appended a different ordered
-- subset of `power_up_ct_boon_*_unique` entries to NetworkLookup.buff_templates
-- and matching deus_power_up_templates entries -- so the host's rpc_add_buff
-- for a trait-boon index resolved to either the wrong buff or a missing key on
-- the client. Pre-register every trait boon's DeusPowerUpTemplate, buff
-- template, and NetworkLookup entries unconditionally at mod-load in sorted
-- order; the gated register_trait_boon below only does pool injection now (its
-- own writes to buff_templates / NetworkLookup are idempotent early-outs).
local function pre_register_trait_boon_lookups()
    local templates       = rawget(_G, "DeusPowerUpTemplates")
    local buff_templates  = rawget(_G, "BuffTemplates")
    local dpubt           = rawget(_G, "DeusPowerUpBuffTemplates")
    if not (templates and buff_templates and dpubt) then
        mod:info("[trait-boon] pre-register skipped: globals not yet loaded")
        return
    end
    local sorted = {}
    for _, spec in ipairs(CT_TRAIT_BOONS) do sorted[#sorted + 1] = spec end
    table.sort(sorted, function(a, b) return a.name < b.name end)
    -- v0.7.63-alpha: register the NetworkLookup NAMES unconditionally (sorted
    -- order, every peer assigns identical indices regardless of which source
    -- buffs are loaded in their BuffTemplates). The buff-template clone +
    -- DeusPowerUpBuffTemplates write still requires source_template, but those
    -- side tables don't determine the sequential NetworkLookup id — only the
    -- name registration does. Splitting them prevents the receiver-side crash
    -- pattern where peer A skipped Vaul's Anvil (source 'always_blocking'
    -- missing for some reason) but peer B registered it → all subsequent
    -- power_up names land on different ids → `Table deus_power_up_templates
    -- does not contain key: N` fatal in network_lookup.lua's strict __index
    -- when peer B's rpc_add_buff reaches peer A. Crash dumps 2026-05-19
    -- 02:59:56 + 03:08:36 (key 177 on the client side).
    --
    -- Same shape as the v0.8.66-dev LA fix: deterministic name registration
    -- decouples NetworkLookup indices from runtime-dependent state, and the
    -- gated content writes (templates / dpubt / buff_templates) remain
    -- idempotent early-outs in the gated register_trait_boon below.
    for _, spec in ipairs(sorted) do
        register_power_up_in_network_lookup(spec.name)
        local buff_name = "power_up_" .. spec.name .. "_" .. spec.rarity
        register_buff_in_network_lookup(buff_name)
    end
    local count, placeholder_count = 0, 0
    for _, spec in ipairs(sorted) do
        local source_template = buff_templates[spec.source_buff]
        -- v0.7.67 hardening (QA-found): write a `templates[spec.name]` entry
        -- UNCONDITIONALLY in sorted order so `inject_dormant_boon` below doesn't
        -- early-out on missing template — if it did, `DeusPowerUpsLookup` would
        -- drift across peers (the exact bug class this refactor targets). When
        -- the source buff is missing on a peer, we ship a placeholder template
        -- with an empty buff array. The boon won't FUNCTION gameplay-wise on
        -- that peer, but its lookup_id will align with peers that do have it —
        -- so rpc_add_buff dispatches still resolve to the correct boon name and
        -- the run doesn't crash. Today all four source buffs (always_blocking,
        -- deus_crit_chain_lightning, deus_extra_shot,
        -- deus_collateral_damage_on_melee_killing_blow) are vanilla and always
        -- present, but this hardening guards against future DLC-gated source
        -- buffs that could differ across peers.
        if not templates[spec.name] then
            local cloned_buffs = {}
            if source_template and source_template.buffs then
                for i, sub in ipairs(source_template.buffs) do
                    cloned_buffs[i] = table.clone(sub)
                end
            else
                placeholder_count = placeholder_count + 1
                mod:info("[trait-boon] %s: source buff '%s' missing — using empty placeholder buffs (boon non-functional on this peer but lookup_id stays aligned)",
                    spec.name, tostring(spec.source_buff))
                -- Single placeholder buff with the correct name field so
                -- inject_dormant_boon's `buff_template.buffs[1].name = buff_name`
                -- assignment doesn't nil-crash.
                cloned_buffs[1] = { name = "placeholder" }
            end
            templates[spec.name] = {
                advanced_description = "description_" .. spec.name,
                display_name         = "display_name_" .. spec.name,
                icon                 = spec.icon,
                max_amount           = 1,
                rectangular_icon     = true,
                buff_template        = { buffs = cloned_buffs },
                description_values   = {},
            }
        end
        local buff_name = "power_up_" .. spec.name .. "_" .. spec.rarity
        local buff_template = table.clone(templates[spec.name].buff_template)
        buff_template.buffs[1].name = buff_name
        dpubt[buff_name] = buff_template
        buff_templates[buff_name] = buff_template
        -- Full registration (NetworkLookup IDs, DeusPowerUps / Array / Lookup,
        -- buff template tables) — UNCONDITIONAL so every peer's
        -- DeusPowerUpsLookup ordering matches regardless of source-buff
        -- availability. Pool insert is gated separately in register_trait_boon.
        inject_dormant_boon(spec.name, spec.rarity)
        count = count + 1
    end
    mod:info("[trait-boon] pre-registered %d trait boons for client compat (%d using placeholder buffs)",
        count, placeholder_count)
end

pre_register_trait_boon_lookups()

for _, spec in ipairs(CT_TRAIT_BOONS) do
    register_trait_boon(spec)
end

-- Assignment to the forward-declared `sync_host_dependent_state` (see top of file).
-- Called by the ct_sync_host_settings RPC handler immediately after a client
-- receives the host's settings payload, so any template/pool mutations gated on
-- a synced setting are reapplied with the host's values. Apply order mirrors the
-- one-shot calls each sync_* function does at module load.
sync_host_dependent_state = function()
    sync_reckless_swings()
    sync_bomb_cooldown()
    sync_boon_movespeed()
    sync_poison_proof_tweak()
    sync_invis_potion_tweak()
    sync_moot_milk_alt_tweak()
    sync_shard_strike()
    sync_anath_raema_permanent()
    sync_dormant_boons()
    for _, spec in ipairs(CT_TRAIT_BOONS) do
        register_trait_boon(spec)
    end
end

do
    -- v0.7.63-alpha: register NetworkLookup names FIRST, unconditionally, BEFORE
    -- the globals-ready gate. Two peers running the same ct version must always
    -- assign the same sequential index to "ct_kill_heal" regardless of whether
    -- their `DeusPowerUpTemplates` / `BuffFunctionTemplates` globals happened to
    -- be loaded at module-init time on each peer. Same fix pattern as
    -- pre_register_trait_boon_lookups: name registration decoupled from
    -- template construction so the lookup ids stay deterministic across peers.
    register_power_up_in_network_lookup("ct_kill_heal")
    register_buff_in_network_lookup("power_up_ct_kill_heal_exotic")

    local power_ups  = rawget(_G, "DeusPowerUpTemplates")
    local buff_funcs = rawget(_G, "BuffFunctionTemplates")

    if power_ups and buff_funcs and buff_funcs.functions then
        buff_funcs.functions.ct_kill_heal_on_kill = function(unit, buff, params)
            if ALIVE[unit] then
                DamageUtils.heal_network(unit, unit, 1, "heal_from_proc")
            end
        end

        power_ups.ct_kill_heal = {
            advanced_description = "description_ct_kill_heal",
            display_name         = "display_name_ct_kill_heal",
            icon                 = "deus_icon_meta_01",  -- placeholder; future: dedicated heal-on-kill icon
            max_amount           = 1,
            rectangular_icon     = true,
            buff_template = {
                buffs = {
                    {
                        authority = "server",
                        buff_func = "ct_kill_heal_on_kill",
                        event     = "on_kill",
                        name      = "ct_kill_heal",
                    },
                },
            },
            description_values = {},
        }

        inject_dormant_boon("ct_kill_heal", "exotic")
        _add_dormant_to_pool("ct_kill_heal", "exotic")
        mod:info("[mod-boon] registered ct_kill_heal at rarity exotic")
    else
        mod:info("[mod-boon] DeusPowerUpTemplates / BuffFunctionTemplates not ready for ct_kill_heal — NetworkLookup name reserved, template construction deferred")
    end
end

-- ============================================================
-- Home Brewer +50% potency for reworked potions (v0.7.31-alpha)
-- ============================================================
-- When the toggle is on AND the player has Home Brewer (the boon that grants the
-- `not_consume_potion` perk), the reworked Moot Milk potion's numerical multipliers are
-- scaled by 1.5x for that specific drink. Implementation: hook BuffExtension.add_buff,
-- save the template's multiplier/bonus fields, scale, call vanilla add, restore.
--
-- Only scales `moot_milk_potion` and `moot_milk_potion_increased` (the reworked variants)
-- — `poison_proof_potion` has binary immunity with no multiplier field, so potency is
-- moot for it. Duration is intentionally NOT scaled (Decanter is the duration lever;
-- Home Brewer is the potency lever — they remain orthogonal).
--
-- LIMITATIONS:
-- * RACE: BuffTemplates is shared global; two players drinking simultaneously could see
--   one peer's scaled values briefly. Rare in practice (potion drinks are individual)
--   and the effect is just stat values, not safety-critical.
-- * No NetworkLookup variant registration — multiplayer-safe because every peer
--   applies its own buff (with its own perk check) via this hook.
local HOME_BREWER_BREWED_TEMPLATES = {
    moot_milk_potion           = true,
    moot_milk_potion_increased = true,
}

mod:hook("BuffExtension", "add_buff", function(func, self, template_name, params)
    if not effective_setting("tweak_home_brewer_potency") then
        return func(self, template_name, params)
    end
    if not (type(template_name) == "string" and HOME_BREWER_BREWED_TEMPLATES[template_name]) then
        return func(self, template_name, params)
    end
    if not self.has_buff_perk or not self:has_buff_perk("not_consume_potion") then
        return func(self, template_name, params)
    end
    local bt = rawget(_G, "BuffTemplates")
    local sub_buffs = bt and bt[template_name] and bt[template_name].buffs
    if not sub_buffs then
        return func(self, template_name, params)
    end
    local saved = {}
    for i, sb in ipairs(sub_buffs) do
        if sb.multiplier or sb.bonus then
            saved[i] = { multiplier = sb.multiplier, bonus = sb.bonus }
            if sb.multiplier then sb.multiplier = sb.multiplier * 1.5 end
            if sb.bonus      then sb.bonus      = sb.bonus      * 1.5 end
        end
    end
    local result = func(self, template_name, params)
    for i, s in pairs(saved) do
        sub_buffs[i].multiplier = s.multiplier
        sub_buffs[i].bonus      = s.bonus
    end
    return result
end)

-- ============================================================
-- Endless Bombs Consumes Morgrim's
-- ============================================================
-- Vanilla `apply_pockets_full_of_bombs_buff` calls `inventory_extension:drop_level_event_item`
-- when the player is wielding slot_level_event, which spawns the held item back as a pickup on the
-- ground. With this toggle the saved Morgrim's Bomb is destroyed instead of dropped — same end
-- state as if the potion had eaten it.
-- CLARIFY: hook target is `BuffFunctionTemplates.functions` (the merged table built by
-- buff_function_templates.lua:5568 via DLCUtils.merge), NOT `BuffFunctionTemplates` directly. The
-- table-form mod:hook resolves the function value at registration time, so the guard prevents
-- a nil-table crash if the buff system somehow isn't loaded yet.
if BuffFunctionTemplates and BuffFunctionTemplates.functions then
    mod:hook(BuffFunctionTemplates.functions, "apply_pockets_full_of_bombs_buff", function(func, unit, buff, params)
        if not effective_setting("endless_bombs_consumes_morgrim") then
            return func(unit, buff, params)
        end

        local inventory_extension = ScriptUnit.has_extension(unit, "inventory_system")
        if inventory_extension then
            local slot_data = inventory_extension:get_slot_data("slot_level_event")
            local item_data = slot_data and slot_data.item_data
            if item_data and item_data.name == "holy_hand_grenade" then
                -- destroy_slot is what drop_level_event_item calls at its end; we skip the in-between
                -- pickup-spawn so the bomb isn't recoverable.
                inventory_extension:destroy_slot("slot_level_event")
            end
        end

        return func(unit, buff, params)
    end)

end

-- ============================================================
-- Manann's Tempest — single-toggle 8s cooldown for boon + trait
-- ============================================================
-- Vanilla `chain_lightning` has no cooldown: every crit triggers a chain, so high-crit
-- builds turn every fight into a strobe-light spam.
--
-- v0.7.64: ONE toggle (`tweak_manann_tempest_cooldown`, default OFF) gates BOTH the
-- boon and the trait. Previously the boon was hard-capped unconditionally — but the
-- gate at line 4024 only checked `is_trait`, so the boon's 8s window was applied
-- silently even when users wanted vanilla behavior, and "the toggle isn't doing
-- anything" was correct from the user perspective for the boon side. Now: off =
-- vanilla on both sources, on = 8s cooldown on both.
--
-- Cooldowns are tracked per `owner_unit` with separate buckets for boon vs trait, so
-- the two sources don't share a window — a player running both gets one chain per 8s
-- from each side (matches the existing "boon stacks with trait" design described above
-- at the CT_TRAIT_BOONS table). Weak-keyed so entries die with the unit.
--
-- Gate mirrors `chain_lightning`'s own ALIVE / first_hit / is_critical_strike check so
-- the cooldown only consumes when the proc would actually have fired.
--
-- v0.7.57: hook target is the GLOBAL `ProcFunctions` table, NOT
-- `BuffFunctionTemplates.functions`. `chain_lightning` lives in
-- `dlc_settings.morris.proc_functions` (morris_buff_settings.lua:2145+, separate from
-- buff_function_templates which ends at line 2144) and gets merged via
-- `DLCUtils.merge("proc_functions", ProcFunctions)` in buff_templates.lua:9533. At
-- runtime BuffExtension looks it up via `ProcFunctions[buff_func_name]`
-- (buff_extension.lua:1350) — `BuffFunctionTemplates.functions.chain_lightning` is nil
-- and was the source of the load-time "trying to hook function or method that doesn't
-- exist" error in v0.7.48 → v0.7.56. `apply_pockets_full_of_bombs_buff` happens to live
-- in `buff_function_templates` (the apply-callback category) which is why THAT hook
-- worked at the same call site.
if ProcFunctions and ProcFunctions.chain_lightning then
    local MANANN_TEMPEST_COOLDOWN_S = 8.0
    local _manann_tempest_t = setmetatable({}, { __mode = "k" })

    mod:hook(ProcFunctions, "chain_lightning", function(func, owner_unit, buff, params, world, param_order)
        local template = buff and buff.template
        local template_name = template and template.name
        local is_boon  = type(template_name) == "string"
            and string.find(template_name, "^power_up_ct_boon_manann_tempest_") ~= nil
        local is_trait = template_name == "deus_crit_chain_lightning"

        if not (is_boon or is_trait) then
            return func(owner_unit, buff, params, world, param_order)
        end
        if not effective_setting("tweak_manann_tempest_cooldown") then
            return func(owner_unit, buff, params, world, param_order)
        end

        local hit_unit = params[param_order.attacked_unit]
        local first_hit = params[param_order.first_hit]
        local is_critical_strike = params[param_order.is_critical_strike]
        if not (ALIVE[owner_unit] and ALIVE[hit_unit] and first_hit and is_critical_strike) then
            return func(owner_unit, buff, params, world, param_order)
        end

        local t = (Managers and Managers.time and Managers.time:time("game")) or 0
        local bucket = _manann_tempest_t[owner_unit]
        if not bucket then
            bucket = { boon_next_t = 0, trait_next_t = 0 }
            _manann_tempest_t[owner_unit] = bucket
        end
        local key = is_boon and "boon_next_t" or "trait_next_t"
        if t < bucket[key] then
            return
        end
        bucket[key] = t + MANANN_TEMPEST_COOLDOWN_S
        return func(owner_unit, buff, params, world, param_order)
    end)
end

-- ============================================================
-- Myrmidia's Wildfire — spread DoT color matches the source burn (v0.7.73)
-- ============================================================
-- Boon `boon_dot_burning_01` (Myrmidia's Wildfire). When a burning enemy dies, vanilla's
-- `boon_dot_burning_01_spread` (morris_buff_settings.lua:3714) applies the HARDCODED
-- template `boon_career_ability_burning_aoe` (vanilla orange) to nearby enemies — even
-- if the dying enemy was burning from Moonfire Bow (blue) or Necromancer balefire (purple).
--
-- We hook the proc and pick the spread template based on what burn status effect the
-- killed unit was carrying:
--
--   StatusEffectNames.burning_elven_magic  → Moonfire Bow blue flame
--                                            spread template: `we_deus_01_dot_fast`
--   StatusEffectNames.burning_balefire     → Necromancer purple
--                                            spread template: vanilla's auto-generated
--                                            `boon_career_ability_burning_aoe_balefire`
--                                            via `BalefireBurnDotLookup`
--                                            (buff_utils.lua:267 generator)
--   StatusEffectNames.burning_warpfire     → Chaos sorcerer warp-flame: keep vanilla
--                                            orange so the boon's own spread reads as
--                                            Myrmidia's fire rather than warp-corruption
--   default (StatusEffectNames.burning)    → vanilla orange (unchanged behavior)
--
-- We hook `ProcFunctions.boon_dot_burning_01_spread` (same table as `chain_lightning`
-- above — buff_func entries live in `dlc_settings.morris.proc_functions`, merged into
-- the global `ProcFunctions` at boot — see the Manann's Tempest block above for the
-- full lookup-vs-buff_function_templates split documented at v0.7.57).
--
-- Caveat: vanilla's spread uses `buff.cached_custom_dot` (one allocation reused across
-- kills). Our hook writes a fresh `dot_template_name` into the cached table per call so
-- each kill picks the right color. The other cached field (`cached_broadphase`) is
-- still reused safely.
--
-- v0.7.73: initial color-match. The hook is also the future host for the v0.7.74
-- generations cap (Phase 2C); that change will tag each spread DoT with a `generation`
-- field and bail when the source generation exceeds the slider cap, but the color-match
-- path lives here and is the contract surface.
--
-- Replicates vanilla's `is_burning` early-out via the same `unit_is_burning` query
-- (no need to call the original at all).
if ProcFunctions and ProcFunctions.boon_dot_burning_01_spread then
    -- Map status-effect name → dot_template_name we spread with. We resolve the
    -- balefire variant lazily (after boot) because vanilla generates it after
    -- buff_settings load. The `_resolved` flag flips on first hit.
    local _ct_spread_dot_by_status = {
        burning_elven_magic = "we_deus_01_dot_fast",
        burning_balefire    = nil, -- resolved lazily from BalefireBurnDotLookup
        burning_warpfire    = "boon_career_ability_burning_aoe",
        burning             = "boon_career_ability_burning_aoe",
    }
    local _ct_spread_resolved = false

    -- v0.7.74: per-unit Wildfire-spread generation tracker. Weak-keyed so entries
    -- die with the unit. Generation 0 = the player's own initial burn (NOT in this
    -- table). Generation N = applied by a spread sourced from a unit at generation
    -- (N-1). Cap reads from `tweak_wildfire_generations_cap` (1-10, default 3).
    --
    -- Why weak-keyed: unit handles are reused by the spawner, but stale entries
    -- on dead units shouldn't pin them or leak indefinitely. We don't use
    -- generation as an authoritative buff field — it's a side-band tag that
    -- accompanies the cached_custom_dot. The DoT applied by `DamageUtils.apply_dot`
    -- doesn't propagate generation natively, so we must hop via this side table.
    local _ct_wildfire_generation = setmetatable({}, { __mode = "k" })

    local function _ct_resolve_balefire_spread()
        if _ct_spread_resolved then return end
        local lookup = rawget(_G, "BalefireBurnDotLookup")
        if lookup then
            local v = lookup["boon_career_ability_burning_aoe"]
            if v then
                _ct_spread_dot_by_status.burning_balefire = v
            end
        end
        _ct_spread_resolved = true
    end

    local function _ct_pick_spread_template(killed_unit)
        local sem = Managers.state and Managers.state.status_effect
        if not sem then
            return "boon_career_ability_burning_aoe"
        end
        local StatusNames = rawget(_G, "StatusEffectNames")
        if not StatusNames then
            return "boon_career_ability_burning_aoe"
        end
        _ct_resolve_balefire_spread()

        -- Priority: elven_magic > balefire > warpfire > vanilla. Moonfire and
        -- Necromancer are player-induced and worth surfacing; warpfire is enemy
        -- ambient so it loses the priority race if any other burn is present.
        if StatusNames.burning_elven_magic and sem:has_status(killed_unit, StatusNames.burning_elven_magic) then
            return _ct_spread_dot_by_status.burning_elven_magic
        end
        if StatusNames.burning_balefire and sem:has_status(killed_unit, StatusNames.burning_balefire) then
            return _ct_spread_dot_by_status.burning_balefire
                or "boon_career_ability_burning_aoe"
        end
        if StatusNames.burning_warpfire and sem:has_status(killed_unit, StatusNames.burning_warpfire) then
            return _ct_spread_dot_by_status.burning_warpfire
        end
        return "boon_career_ability_burning_aoe"
    end

    mod:hook(ProcFunctions, "boon_dot_burning_01_spread", function(func, owner_unit, buff, params)
        local killed_unit = params[3]
        if not (killed_unit and Managers.state and Managers.state.status_effect) then
            return func(owner_unit, buff, params)
        end
        if not Managers.state.status_effect:unit_is_burning(killed_unit) then
            return
        end

        -- v0.7.74: generations cap. Generation of THIS death = whatever was
        -- recorded for killed_unit (or 0 if it wasn't a spread DoT — e.g. burnt
        -- by the player's own shot). The new spread DoT will be tagged with
        -- src_gen + 1; if that would meet or exceed the cap, we don't spread.
        local cap = effective_setting("tweak_wildfire_generations_cap") or 3
        if type(cap) ~= "number" then cap = 3 end
        local src_gen = _ct_wildfire_generation[killed_unit] or 0
        if src_gen + 1 > cap then
            return -- chain depth exceeded; stop spreading
        end
        local new_gen = src_gen + 1

        local chosen = _ct_pick_spread_template(killed_unit)

        -- Re-implement vanilla spread with our chosen template and generation
        -- tracking. Mirrors morris_buff_settings.lua:3714-3743. We always handle
        -- spread ourselves (rather than falling through to vanilla for the
        -- orange case) so generation tagging is consistent across colors.
        local template = buff.template
        buff.cached_broadphase = buff.cached_broadphase or {}
        buff.cached_custom_dot = buff.cached_custom_dot or { dot_template_name = chosen }
        buff.cached_custom_dot.dot_template_name = chosen

        local side = Managers.state.side.side_by_unit[owner_unit]
        local num_nearby_enemies = AiUtils.broadphase_query(
            POSITION_LOOKUP[killed_unit],
            template.area_radius,
            buff.cached_broadphase,
            side.enemy_broadphase_categories
        )
        local hit_zone_name = "full"
        local damage_source = "buff"
        local damage_profile, target_index, power_level, boost_curve_multiplier, is_critical_strike, aoe_data

        for i = 1, num_nearby_enemies do
            local target_unit = buff.cached_broadphase[i]
            if target_unit ~= killed_unit then
                DamageUtils.apply_dot(
                    damage_profile, target_index, power_level, target_unit,
                    owner_unit, hit_zone_name, damage_source, boost_curve_multiplier,
                    is_critical_strike, aoe_data, owner_unit, buff.cached_custom_dot
                )
                -- Tag the neighbor with the new generation. If it already has a
                -- LOWER generation tag (e.g. spread from a closer earlier source
                -- this same frame), we keep the lower one — the chain is bounded
                -- by the SHORTEST path, which is the more conservative choice
                -- for cap interpretation.
                local prev = _ct_wildfire_generation[target_unit]
                if not prev or new_gen < prev then
                    _ct_wildfire_generation[target_unit] = new_gen
                end
            end
        end
    end)
end

-- ============================================================
-- Larger Clip — scale ammo_per_reload alongside clip_size (v0.7.68 → v0.7.69 unconditional)
-- ============================================================
-- Vanilla `deus_larger_clip` (deus_power_up_settings.lua:2647-2673) uses
-- `stat_buff = "clip_size"` with multiplier 1 (+100%). On shotguns
-- (Grudge-Raker etc.) that doubles the clip from 2→4. BUT vanilla
-- `GenericAmmoUserExtension._ammo_per_reload` is set ONCE at init from the
-- weapon template (`grudge_raker.lua:155: ammo_per_reload = 2`) and is NEVER
-- passed through `apply_buffs_to_value`. So each shotgun pump still loads
-- only 2 shells, requiring 2 pumps to refill the doubled clip.
--
-- This is treated as an unintended vanilla bug (the boon is cut content
-- re-enabled by ct via activate_dormant_deus_larger_clip), not a rebalance —
-- fix applies unconditionally with no toggle. Hook fires on every weapon's
-- `_apply_buffs`; if no clip_size buff is active the scale factor is 1 and
-- nothing changes.
--
-- Captures `_ct_original_ammo_per_reload` once per extension instance to avoid
-- compounding across repeated `_apply_buffs` calls (which fire on every buff
-- add/remove). Reads the scaling factor from the ratio `_ammo_per_clip /
-- _original_ammo_per_clip` so ANY clip_size source (boon, talent, future
-- modded buff) drives the reload-tick scale too. On weapons without an
-- ammo_per_reload entry (everything that already reload-fills in one action)
-- this hook is a no-op — the `orig_reload <= 0` guard short-circuits.
mod:hook_safe("GenericAmmoUserExtension", "_apply_buffs", function(self)
    if not (self._original_ammo_per_clip and self._original_ammo_per_clip > 0) then return end
    if not self._ammo_per_clip then return end
    if self._ct_original_ammo_per_reload == nil then
        self._ct_original_ammo_per_reload = self._ammo_per_reload
    end
    local orig_reload = self._ct_original_ammo_per_reload
    if not orig_reload or orig_reload <= 0 then return end
    local scale = self._ammo_per_clip / self._original_ammo_per_clip
    self._ammo_per_reload = math.max(orig_reload, math.ceil(orig_reload * scale))
end)

-- ============================================================
-- Block Ranger Veteran from Saving Morgrim's
-- ============================================================
-- The `bardin_ranger_passive_consumeable_dupe_grenade` passive applies `not_consume_grenade` as a
-- proc stat_buff with proc_chance=0.1. When ActionChargedProjectileUtility.fire_charged_projectile
-- throws a grenade, it queries `apply_buffs_to_value(0, "not_consume_grenade")` to roll the proc
-- (action_charged_projectile.lua:83). We monkey-patch the buff_extension instance for the duration
-- of the call so the proc returns false specifically when the grenade is a Morgrim's Bomb. Other
-- grenades (frag, fire, conflagration) continue to roll normally.
mod:hook("ActionChargedProjectileUtility", "fire_charged_projectile", function(func, projectile_context, ...)
    if not effective_setting("rv_no_save_morgrim")
        or not projectile_context
        or projectile_context.item_name ~= "holy_hand_grenade"
        or not projectile_context.is_grenade
        or projectile_context.grenade_thrown
    then
        return func(projectile_context, ...)
    end

    local buff_ext = projectile_context.buff_extension
    if not buff_ext then
        return func(projectile_context, ...)
    end

    -- rawget so we know whether the instance had a pre-existing override (vs. inheriting via
    -- __index from the class). On restore we either reinstate the override or clear our shim.
    local had_instance_override = rawget(buff_ext, "apply_buffs_to_value") ~= nil
    local original = buff_ext.apply_buffs_to_value
    buff_ext.apply_buffs_to_value = function(self, value, stat_buff_name, ...)
        if stat_buff_name == "not_consume_grenade" then
            return value, false
        end
        return original(self, value, stat_buff_name, ...)
    end

    local ok, a, b = pcall(func, projectile_context, ...)

    if had_instance_override then
        buff_ext.apply_buffs_to_value = original
    else
        buff_ext.apply_buffs_to_value = nil
    end

    if not ok then
        error(a, 0)
    end
    return a, b
end)

-- Pool-affecting settings: master toggle, per-CW-scenario toggles, and per-adventure
-- toggles. Re-run inject_pool() on any of these so changes take effect without a
-- restart. The engine reads LEVEL_AVAILABILITY at run setup (DeusMechanism._setup_run)
-- — changes only affect the NEXT expedition, not a CW run already underway.
local function is_pool_setting(setting_id)
    if setting_id == "inject_adventure_maps" then return true end
    if type(setting_id) ~= "string" then return false end
    return setting_id:find("^enable_adventure_") ~= nil
        or setting_id:find("^enable_cw_") ~= nil
end

mod.on_setting_changed = function(setting_id)
    if setting_id == "tweak_reckless_swings" then
        sync_reckless_swings()
    elseif setting_id == "bomb_boon_cooldown" then
        sync_bomb_cooldown()
    elseif setting_id == "ulric_pack_unlimited_range" then
        sync_ulric_pack_unlimited_range()
    elseif setting_id == "tweak_boon_movespeed" then
        sync_boon_movespeed()
    elseif setting_id == "tweak_poison_proof_duration" then
        sync_poison_proof_tweak()
    elseif setting_id == "tweak_invis_potion_2x" then
        sync_invis_potion_tweak()
    elseif setting_id == "tweak_moot_milk_alt" then
        sync_moot_milk_alt_tweak()
    elseif setting_id == "tweak_shard_strike_duration" then
        sync_shard_strike()
    elseif setting_id == "tweak_anath_raema_permanent" then
        sync_anath_raema_permanent()
    elseif type(setting_id) == "string" and setting_id:find("^activate_dormant_") == 1 then
        sync_dormant_boons()
    elseif type(setting_id) == "string" and setting_id:find("^enable_boon_") == 1 then
        for _, spec in ipairs(CT_TRAIT_BOONS) do
            register_trait_boon(spec)  -- idempotent; injects only if toggle on and not yet injected
        end
    elseif is_pool_setting(setting_id) then
        -- inject_pool() is idempotent: takes a one-time snapshot, resets to it on
        -- every call, then applies current toggle state. Master-off branch inside
        -- skips inject and leaves the pool at vanilla.
        AdventurePool.inject_pool()
    end
end

-- Clean disable: revert the persistent DeusPowerUpTemplates mutations (Khaine's Fury and bomb-boon
-- cooldowns) so toggling the mod off via VMF doesn't leave them in a tweaked state until restart.
-- All other mutations in this mod are scoped (save-and-restore inside hooks).
mod.on_disabled = function()
    revert_reckless_swings_tweak()
    revert_bomb_cooldown_tweak()
    revert_boon_movespeed_tweak()
    revert_poison_proof_tweak()
    revert_invis_potion_tweak()
    revert_moot_milk_alt_tweak()
    revert_shard_strike_tweak()
    revert_anath_raema_permanent_tweak()
end

-- ============================================================
-- Debug commands
-- ============================================================

mod:command("dump_spawners", "Dump pickup spawner counts and pickup_settings for the current level", function()
    if not LevelHelper then
        mod:echo("LevelHelper not available.")
        return
    end

    local current = LevelHelper:current_level_settings()
    if not current then
        mod:echo("No level settings found.")
        return
    end

    mod:echo("=== Level: " .. tostring(current.display_name or current.level_id or "?") .. " ===")

    local pickup_settings = current.pickup_settings
    if pickup_settings then
        for diff_key, diff_data in pairs(pickup_settings) do
            if type(diff_data) == "table" and diff_data.primary then
                local p = diff_data.primary
                local line = string.format("  [%s] weapon_chest=%s cursed_chest=%s ammo=%s",
                    tostring(diff_key),
                    tostring(p.deus_weapon_chest or "nil"),
                    tostring(p.deus_cursed_chest or "nil"),
                    tostring(p.ammo or "nil"))
                mod:echo(line)
                mod:info(line)

                for k, v in pairs(p) do
                    if k ~= "deus_weapon_chest" and k ~= "deus_cursed_chest" and k ~= "ammo" then
                        local detail = string.format("    %s = %s", tostring(k), tostring(v))
                        mod:info(detail)
                    end
                end
            end
        end
    else
        mod:echo("  No pickup_settings found.")
    end

    if Managers.state and Managers.state.entity then
        local spawner_count = 0
        local entity_manager = Managers.state.entity
        local system = entity_manager:system("pickup_system")
        if system and system._pickup_spawners then
            for _ in pairs(system._pickup_spawners) do
                spawner_count = spawner_count + 1
            end
            mod:echo("  Physical pickup spawners: " .. spawner_count)
        elseif system and system._spawner_units then
            for _ in pairs(system._spawner_units) do
                spawner_count = spawner_count + 1
            end
            mod:echo("  Physical spawner units: " .. spawner_count)
        else
            mod:echo("  Could not count spawners (unknown fields). Check log.")
            if system then
                for k, v in pairs(system) do
                    mod:info("  pickup_system.%s = %s (%s)", tostring(k), tostring(v), type(v))
                end
            end
        end
    end

    mod:echo("Done. Full details in log.")
end)

mod:command("dump_potions", "Dump resolved in-game names for every CW potion (potion_*_01 in ItemMasterList)", function()
    local iml = rawget(_G, "ItemMasterList")
    if not iml then
        mod:echo("ItemMasterList not loaded.")
        return
    end
    local sorted = {}
    for key, entry in pairs(iml) do
        if type(entry) == "table" and entry.slot_type == "potion" then
            sorted[#sorted + 1] = key
        end
    end
    table.sort(sorted)
    local count = 0
    for _, key in ipairs(sorted) do
        local entry = iml[key]
        local display_raw = Localize(key)
        local display = (display_raw ~= "<" .. key .. ">") and display_raw or "(no display loc)"
        local desc_key = entry.description
        local desc_raw = desc_key and Localize(desc_key) or ""
        local desc = (desc_key and desc_raw ~= "<" .. desc_key .. ">") and desc_raw or "(no description loc)"
        local tmpl = entry.temporary_template or "(none)"
        mod:info("[DUMP:potions] %s\tdisplay='%s'\ttemplate=%s\tdesc='%s'", key, display, tmpl, desc)
        count = count + 1
    end
    mod:echo(string.format("dump_potions: %d potions dumped to log.", count))
end)

mod:command("dump_boon_loc", "Dump resolved display names and descriptions for all boons", function()
    if not DeusPowerUpTemplates or not DeusPowerUpsArray then
        mod:echo("DeusPowerUpTemplates not loaded (must be in Chaos Wastes).")
        return
    end

    local sorted_keys = {}
    for key in pairs(DeusPowerUpTemplates) do
        sorted_keys[#sorted_keys + 1] = key
    end
    table.sort(sorted_keys)

    local count = 0
    for _, key in ipairs(sorted_keys) do
        local tpl = DeusPowerUpTemplates[key]
        local display_key = tpl.display_name
        local desc_key = tpl.advanced_description

        local display_text = ""
        if display_key then
            local raw = Localize(display_key)
            if raw ~= "<" .. display_key .. ">" then
                display_text = raw
            end
        end

        local desc_text = ""
        if desc_key then
            local raw = Localize(desc_key)
            if raw ~= "<" .. desc_key .. ">" then
                desc_text = raw
            end
        end

        mod:info("[DUMP:boon_loc] %s\t%s\t%s", key, display_text, desc_text)
        count = count + 1
    end

    mod:echo(string.format("dump_boon_loc: %d boons dumped to log. Check console log for tab-separated output.", count))
end)

mod:command("dump_boons", "Deep dump of all DeusPowerUpTemplates + buff data to log", function(filter)
    if not DeusPowerUpTemplates then
        mod:echo("DeusPowerUpTemplates not loaded (must be in Chaos Wastes).")
        return
    end

    local function dump_table(tbl, prefix, lines, depth)
        if depth > 6 then
            lines[#lines + 1] = prefix .. "... (max depth)"
            return
        end
        local keys = {}
        for k in pairs(tbl) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local v = tbl[k]
            local key_str = prefix .. tostring(k)
            if type(v) == "table" then
                lines[#lines + 1] = key_str .. " = {"
                dump_table(v, prefix .. "  ", lines, depth + 1)
                lines[#lines + 1] = prefix .. "}"
            elseif type(v) == "function" then
                lines[#lines + 1] = key_str .. " = [function]"
            else
                lines[#lines + 1] = key_str .. " = " .. tostring(v) .. "  (" .. type(v) .. ")"
            end
        end
    end

    local function lookup_buff(name)
        if not name then return nil end
        local sources = {
            { rawget(_G, "DeusPowerUpBuffTemplates"), "DeusPowerUpBuffTemplates" },
            { rawget(_G, "BuffTemplates"), "BuffTemplates" },
            { rawget(_G, "NetworkedBuffTemplates"), "NetworkedBuffTemplates" },
        }
        for _, src in ipairs(sources) do
            if src[1] and src[1][name] then
                return src[1][name], src[2]
            end
        end
        return nil, nil
    end

    local sorted_keys = {}
    for key in pairs(DeusPowerUpTemplates) do
        if not filter or key:find(filter, 1, true) then
            sorted_keys[#sorted_keys + 1] = key
        end
    end
    table.sort(sorted_keys)

    local count = 0
    for _, key in ipairs(sorted_keys) do
        local tpl = DeusPowerUpTemplates[key]
        local lines = {}
        lines[#lines + 1] = "========== " .. key .. " =========="

        lines[#lines + 1] = "--- PowerUp Template ---"
        dump_table(tpl, "  ", lines, 0)

        local buff_name = tpl.buff_template_name or tpl.buff_name
        if buff_name then
            local buff_tpl, source = lookup_buff(buff_name)
            if buff_tpl then
                lines[#lines + 1] = "--- Buff Template: " .. buff_name .. " (from " .. source .. ") ---"
                dump_table(buff_tpl, "  ", lines, 0)
            else
                lines[#lines + 1] = "--- Buff Template: " .. buff_name .. " NOT FOUND in any buff table ---"
            end
        end

        for _, line in ipairs(lines) do
            mod:info("[DUMP:boon_deep] %s", line)
        end
        count = count + 1
    end

    mod:echo(string.format("dump_boons: %d boons dumped to log%s", count,
        filter and (" matching '" .. filter .. "'") or ""))
end)

mod:command("dump_buffs", "Deep dump of all buff templates referenced by boons", function(filter)
    if not DeusPowerUpTemplates then
        mod:echo("DeusPowerUpTemplates not loaded (must be in Chaos Wastes).")
        return
    end

    local function dump_table(tbl, prefix, lines, depth)
        if depth > 6 then
            lines[#lines + 1] = prefix .. "... (max depth)"
            return
        end
        local keys = {}
        for k in pairs(tbl) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local v = tbl[k]
            local key_str = prefix .. tostring(k)
            if type(v) == "table" then
                lines[#lines + 1] = key_str .. " = {"
                dump_table(v, prefix .. "  ", lines, depth + 1)
                lines[#lines + 1] = prefix .. "}"
            elseif type(v) == "function" then
                lines[#lines + 1] = key_str .. " = [function]"
            else
                lines[#lines + 1] = key_str .. " = " .. tostring(v) .. "  (" .. type(v) .. ")"
            end
        end
    end

    local buff_sources = {}
    local src_names = { "BuffTemplates", "NetworkedBuffTemplates", "DeusPowerUpBuffTemplates", "DeusBuffTemplates" }
    for _, name in ipairs(src_names) do
        local tbl = rawget(_G, name)
        if tbl then buff_sources[name] = tbl end
    end

    local function lookup_buff(name)
        for src_name, src_tbl in pairs(buff_sources) do
            if src_tbl[name] then return src_tbl[name], src_name end
        end
        return nil, nil
    end

    local refs = {}
    local function collect_refs(tbl, depth)
        if depth > 6 or type(tbl) ~= "table" then return end
        for k, v in pairs(tbl) do
            if type(v) == "string" and (k == "buff_to_add" or k == "buff_to_add_revived"
                or k == "cooldown_buff" or k == "full_heal_buff" or k == "removal_buff") then
                refs[v] = true
            elseif type(v) == "table" then
                if k == "buff_to_add" or k == "buff_to_add_revived" then
                    for _, name in pairs(v) do
                        if type(name) == "string" then refs[name] = true end
                    end
                else
                    collect_refs(v, depth + 1)
                end
            end
        end
    end

    for _, tpl in pairs(DeusPowerUpTemplates) do
        collect_refs(tpl, 0)
    end

    local sorted = {}
    for name in pairs(refs) do
        if not filter or name:find(filter, 1, true) then
            sorted[#sorted + 1] = name
        end
    end
    table.sort(sorted)

    local count = 0
    for _, name in ipairs(sorted) do
        local lines = {}
        local buff_tpl, source = lookup_buff(name)
        if buff_tpl then
            lines[#lines + 1] = "========== " .. name .. " (from " .. source .. ") =========="
            dump_table(buff_tpl, "  ", lines, 0)
            count = count + 1
        else
            lines[#lines + 1] = "========== " .. name .. " NOT FOUND =========="
        end
        for _, line in ipairs(lines) do
            mod:info("[DUMP:buff_deep] %s", line)
        end
    end

    mod:echo(string.format("dump_buffs: %d/%d referenced buffs found%s", count, #sorted,
        filter and (" matching '" .. filter .. "'") or ""))
end)

mod:command("dump_mutators", "Dump all mutator templates to log", function(filter)
    local src = rawget(_G, "MutatorTemplates")
    if not src then
        mod:echo("MutatorTemplates not loaded.")
        return
    end

    local entries = {}
    for key, tpl in pairs(src) do
        if not filter or key:find(filter, 1, true) then
            entries[#entries + 1] = key
        end
    end
    table.sort(entries)

    for _, key in ipairs(entries) do
        local tpl = src[key]
        local line = string.format("%-40s display=%s",
            key, tostring(tpl.display_name or tpl.name or "?"))
        mod:echo(line)
        mod:info("[DUMP:mutators] %s", line)
    end

    mod:echo(string.format("dump_mutators: %d templates", #entries))
end)

mod:command("dump_traits", "Dump every CW weapon trait that can roll, with localized display name and description", function(filter)
    if not DeusWeapons then
        mod:echo("DeusWeapons not loaded.")
        return
    end
    local WT = rawget(_G, "WeaponTraits")
    if not WT or not WT.traits then
        mod:echo("WeaponTraits.traits not loaded.")
        return
    end

    local rollable = {}
    for _, data in pairs(DeusWeapons) do
        local baked = data.baked_trait_combinations
        if baked then
            for _, combo in ipairs(baked) do
                for _, trait_name in ipairs(combo) do
                    rollable[trait_name] = true
                end
            end
        end
    end

    local sorted = {}
    for name in pairs(rollable) do
        if not filter or name:find(filter, 1, true) then
            sorted[#sorted + 1] = name
        end
    end
    table.sort(sorted)

    local function resolve(key)
        if not key then return "" end
        local raw = Localize(key)
        if raw and raw ~= "<" .. key .. ">" then
            return raw
        end
        return ""
    end

    mod:info("[DUMP:traits] === %d rollable CW traits ===", #sorted)
    mod:info("[DUMP:traits] trait_name\tdisplay_name_key\tdisplay_text\tdesc_key\tdesc_text")
    for _, name in ipairs(sorted) do
        local td = WT.traits[name]
        local dn_key = td and td.display_name or ""
        local desc_key = td and td.advanced_description or ""
        mod:info("[DUMP:traits] %s\t%s\t%s\t%s\t%s",
            name, dn_key, resolve(dn_key), desc_key, resolve(desc_key))
    end
    mod:echo(string.format("dump_traits: %d traits dumped to log.", #sorted))
end)

-- Resolves the canonical in-game display name for every adventure level AND every
-- vanilla CW scenario in the catalog. Emits tab-separated rows to the log
-- (`[DUMP:adv_names]`) for paste-back into _adventure_pool.lua. The level's
-- `display_name` is a loc key that Localize() resolves to the English string. Works
-- in the keep or the CW hub — no need to be in a mission.
mod:command("dump_adventure_names", "Resolve in-game names for every adventure level + CW scenario", function()
    if not LevelSettings then
        mod:echo("LevelSettings not loaded.")
        return
    end

    local function resolve(key)
        if not key or key == "" then return "" end
        local raw = Localize(key)
        if raw and raw ~= "<" .. key .. ">" then return raw end
        return ""
    end

    mod:info("[DUMP:adv_names] === ADVENTURE MISSIONS ===")
    mod:info("[DUMP:adv_names] level_key\tdisplay_text\tdlc_name\tact\tlevel_bundle_path")
    for _, entry in ipairs(AdventurePool.ADVENTURE_MISSIONS) do
        local lvl = entry.key
        local v = rawget(LevelSettings, lvl)
        local dn_key = v and v.display_name or ""
        local level_name = v and v.level_name or ""
        local dlc_name = v and v.dlc_name or "(base)"
        local act = v and v.act or ""
        mod:info("[DUMP:adv_names] %s\t%s\t%s\t%s\t%s", lvl, resolve(dn_key), dlc_name, act, level_name)
    end

    mod:info("[DUMP:adv_names] === CW SCENARIOS ===")
    mod:info("[DUMP:adv_names] cw_key\ttitle_key\tdisplay_text\tbase_level_name")
    for _, scen in ipairs(AdventurePool.CW_SCENARIOS) do
        local dls = rawget(DEUS_LEVEL_SETTINGS or {}, scen.key)
        -- CW levels' user-facing title is `<level_key>_title` per level_settings_morris.lua:112
        local title_key = scen.key .. "_title"
        local base = dls and dls.base_level_name or scen.key
        mod:info("[DUMP:adv_names] %s\t%s\t%s\t%s", scen.key, title_key, resolve(title_key), base)
    end

    local total = #AdventurePool.ADVENTURE_MISSIONS + #AdventurePool.CW_SCENARIOS
    mod:echo(string.format("dump_adventure_names: %d entries dumped to log (%d adventures + %d CW).",
        total, #AdventurePool.ADVENTURE_MISSIONS, #AdventurePool.CW_SCENARIOS))
end)

mod:command("pool_status", "Dump current CW map-pool state (TRAVEL/SIGNATURE keys per journey)", function()
    AdventurePool.dump_pool_state()
end)

-- Manual re-run of pool injection. Useful for debugging: if you toggle settings in VMF
-- and want to see them take effect without restarting the game, run this from the keep
-- BEFORE entering a CW run. The engine reads LEVEL_AVAILABILITY at run setup
-- (DeusMechanism._setup_run); changes only take effect for the NEXT run, not the current one.
mod:command("force_inject_pool", "Re-run adventure pool injection now", function()
    if not mod:get("inject_adventure_maps") then
        mod:echo("inject_adventure_maps is OFF — enable it first.")
        return
    end
    local n = AdventurePool.inject_pool()
    mod:echo("inject_pool ran: " .. tostring(n) .. " adventures injected (check log for details).")
end)

mod:command("cw_status", "Show Chaos Wastes Tweaker state", function()
    mod:echo("Chaos Wastes Tweaker v" .. MOD_VERSION)
    mod:echo("  Altars: upgrade=" .. tostring(mod:get("chest_upgrade_count") or -1)
        .. " melee_swap=" .. tostring(mod:get("chest_swap_melee_count") or -1)
        .. " ranged_swap=" .. tostring(mod:get("chest_swap_ranged_count") or -1)
        .. " boon=" .. tostring(mod:get("chest_power_up_count") or -1)
        .. " (-1=Default, 0=zero)")
    mod:echo("  Chests of Trials: " .. tostring(mod:get("cursed_chest_count") or -1) .. " (-1=Default, 0=zero)")
    mod:echo("  Arena ammo: " .. tostring(mod:get("arena_ammo_count") or -1) .. " (-1=Default, 0=zero)")
    mod:echo("  Campaign potions: " .. tostring(mod:get("enable_campaign_potions") or false))
end)
