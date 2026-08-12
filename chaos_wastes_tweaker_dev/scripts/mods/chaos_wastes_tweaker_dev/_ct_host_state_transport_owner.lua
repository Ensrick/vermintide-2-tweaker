-- Behavior-neutral owner for host-authoritative settings and graph transport.
-- Installed at the former inline position so RPC, hook, and check order is retained.
return function(mod, ctx)
    local AdventurePool = ctx.adventure_pool
    local CT_RPC_SCHEMA = ctx.rpc_schema
    local _broadcast_local_manifest = ctx.broadcast_local_manifest
    local _dbg = ctx.dbg
    local _dbg_alert = ctx.dbg_alert
    local _rt_register = ctx.rt_register
    local cjson = ctx.cjson
    local _collect_setting_ids

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

_collect_setting_ids = function()
    -- mod:dofile re-executes the data file. Idempotent: tree-building has no side
    -- effects beyond an in-place recursive_sort (which is stable on already-sorted
    -- tables). Returns the same `data` table that VMF loaded at mod registration.
    local data = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_data")
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
pcall(printf, "[ct_sync] synced setting registry built: %d keys (%d excluded as per-peer)",
    #SYNCED_SETTING_NAMES, (function() local n = 0; for _ in pairs(PER_PEER_SETTING_NAMES) do n = n + 1 end; return n end)())

-- O(1) membership for the mid-run re-broadcast gate in on_setting_changed (see
-- MIDRUN_SETTING_REBROADCAST_MARKER). Lives on `mod` rather than a new file-scope
-- local because this chunk is near Lua 5.1's 200-locals cap. Mirrors SYNCED_SETTING_NAMES.
mod._ct_synced_set = {}
for _, id in ipairs(SYNCED_SETTING_NAMES) do
    mod._ct_synced_set[id] = true
end

local _ct_host_settings = {}
local _ct_host_sync_received = false

-- Forward-declared so the network_register callback below can call it before
-- its assignment further down the file (after all sync_* functions exist).
local sync_host_dependent_state = ctx.sync_host_dependent_state

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

-- ============================================================
-- Issue #97: paced chunk send-queue (anti-flood)
-- ============================================================
-- The three chunked broadcasters below (host settings / graph snapshot / peer
-- manifest) each used to emit their ENTIRE chunk train inline in one frame:
--   for seq = 1, total do mod:network_send(<event>, <target>, ...) end
-- On a large-graph hot-join the three fire in the same frame window and dump
-- ~200 reliable RPCs (~94 KB) onto Stingray's reliable send queue at once. That
-- queue has a hard byte budget (~97822 B); overflowing it tears down the host
-- connection -> HOST CRASH (the reported #97 symptom).
--
-- Fix: don't send inline. ENQUEUE each chunk as a self-contained network_send
-- arg set into one FIFO queue, and drain a small budget per frame from
-- mod.update (below). The chunks then arrive paced across many frames; the
-- receivers already tolerate that (purely accumulative — they buffer by seq per
-- (sender,session) and only act once all `total` distinct chunks arrive; no
-- single-frame/burst assumption anywhere). NONE of the wire protocol changes:
-- same event names, same CT_RPC_SCHEMA gate, same session/seq/total semantics,
-- same SYNC_CHUNK_SIZE, same reassembly. Only the SEND TIMING is paced.
--
-- FIFO order is preserved (append at tail in enqueue order, pop from head).
-- Re-entrancy is safe: a new broadcast just appends more entries; the drainer
-- never clears the queue mid-drain and each entry already carries its own
-- session id, so concurrent/overlapping broadcasts never corrupt each other.
--
-- (Globals, not main-chunk locals: the file is at the Lua 5.1 200-locals cap —
-- see the note on CT_ALTAR_VISUAL_PROBE_MARKER near line 572. These three names
-- are referenced only from the mod.update drainer closure and the three chunk
-- broadcaster call sites below; nothing else shadows them, so file-scope globals
-- are safe and keep the main chunk under the 200-local ceiling.)
_ct_chunk_send_queue = {}
-- /ct_regression_test marker for `chunk_sends_paced_not_bursted` (Issue #97,
-- ct_dev 0.7.163-dev). All three chunked broadcasts (ct_graph_snapshot_chunk /
-- ct_sync_host_settings_chunk / ct_peer_manifest_chunk) route their per-seq
-- emission through `_ct_enqueue_chunk` and are drained by the single
-- `mod.update` owner below at _CT_CHUNK_DRAIN_BUDGET per frame -- NEVER an
-- inline `mod:network_send("<chunk-event>", ...)` inside the `for seq` loops
-- (that single-frame burst overran the reliable-channel queue cap and dropped
-- chunks). If a future edit re-inlines a burst send, update the wiring but NOT
-- this marker, and the regression check fails loudly. (Global, not a main-chunk
-- local: see the 200-locals-cap note above.)
_CT_CHUNK_PACED_SEND_MARKER = "chunk_sends:enqueue_drain_paced_v0.7.163"
-- Per-frame drain budget. Worst single chunk_str is SYNC_CHUNK_SIZE (400) chars
-- + the small fixed envelope; 8 chunks/frame keeps per-frame reliable bytes
-- (~8 * ~450 = ~3.6 KB) FAR under the ~97822 B queue limit, and the reliable
-- channel acks far faster than we enqueue at this cadence so the queue drains
-- steadily without ever stacking near the cap. Tunable.
-- (Global, not a main-chunk local: see the 200-locals-cap note just above.)
_CT_CHUNK_DRAIN_BUDGET = 8

-- Append one chunk send to the FIFO queue. `record_send` (optional) is invoked
-- with no args at SEND time (not enqueue time) so bt's net_replay ring records
-- the actual emission; it mirrors the inline _nr:record_send call the host
-- settings broadcaster used to make. Args mirror mod:network_send exactly:
-- (event, target, CT_RPC_SCHEMA, session, seq, total, chunk_str).
-- (Global, not a main-chunk local: see the 200-locals-cap note above.)
function _ct_enqueue_chunk(event, target, schema, session, seq, total, chunk_str, record_send)
    _ct_chunk_send_queue[#_ct_chunk_send_queue + 1] = {
        event = event, target = target, schema = schema,
        session = session, seq = seq, total = total, chunk_str = chunk_str,
        record_send = record_send,
    }
end

-- Per-frame drainer. VMF calls a registered mod.update(dt) every frame at the
-- keep AND in mission (the only mod-wide per-frame entry point in ct_dev — the
-- existing DeusChestExtension.update hook is mission/per-chest-only and read-
-- only, so it can't host this). Pops up to _CT_CHUNK_DRAIN_BUDGET entries from
-- the head of the FIFO each tick and sends them, pcall-wrapping each so one bad
-- send can't abort the rest of the drain or stall the queue. Cheap no-op when
-- the queue is empty (the common case), so it's safe to run unconditionally.
mod.update = function(dt)
    -- #58/#156: drive the deferred spawn-census emit (armed in populate_pickups,
    -- fires ~8s later once the guaranteed-spawn pass is done). Cheap no-op when
    -- disarmed. Resolved via mod._ since the census `do` block is defined LATER in
    -- this file; the field is assigned at load, before any update tick fires.
    if mod._ct_tally_tick then mod._ct_tally_tick(dt) end
    -- #487 freeze watchdog: reports any single frame whose dt exceeds the stall
    -- threshold (a recoverable game-loop stall), naming the last-open diagnostic
    -- region. Cheap field read + numeric compare; no-op on the common path.
    if mod._ct_freeze487 then mod._ct_freeze487.tick(dt) end
    -- #299: deferred host-side pass that teleports a chest-revived player back to a
    -- teammate once they become controllable (they otherwise stand up alone at a
    -- distant respawn beacon). Cheap no-op when nothing is armed. Resolved via mod._
    -- since the tick + its pending table are defined later in this file (assigned at
    -- load, before any update tick fires).
    if mod._ct_chest_teleport_tick then mod._ct_chest_teleport_tick(dt) end
    -- #205: debounced host-settings re-sync. on_setting_changed marks the registry
    -- dirty + (re)arms this short countdown instead of broadcasting inline, so an
    -- Apply-button burst (the gut Mod Tweaker commits its whole staged batch at once ->
    -- hundreds of on_setting_changed in one frame) or a slider drag coalesces into ONE
    -- encode + ONE 46-chunk sync once edits SETTLE, instead of hundreds of redundant
    -- full-registry encodes in a single frame. setup_run still broadcasts immediately
    -- (single call at run start, not a burst). The supersede guard in
    -- _ct_broadcast_host_settings remains as belt-and-suspenders.
    if mod._ct_settings_sync_pending then
        mod._ct_settings_sync_countdown = (mod._ct_settings_sync_countdown or 0) - dt
        if mod._ct_settings_sync_countdown <= 0 then
            mod._ct_settings_sync_pending = false
            if mod._ct_broadcast_host_settings then
                mod._ct_broadcast_host_settings("debounced_setting_edits")
            end
        end
    end
    if mod._ct919_profile_tick then mod._ct919_profile_tick(dt) end
    local q = _ct_chunk_send_queue
    if q[1] == nil then return end
    local budget = _CT_CHUNK_DRAIN_BUDGET
    local sent = 0
    while sent < budget do
        local entry = q[1]
        if entry == nil then break end
        table.remove(q, 1)  -- pop head (FIFO)
        local ok, err = pcall(function()
            mod:network_send(entry.event, entry.target, entry.schema,
                entry.session, entry.seq, entry.total, entry.chunk_str)
            if entry.record_send then entry.record_send() end
        end)
        if not ok then
            pcall(printf, "[ct_sync] paced send failed for %s (session %s seq %s/%s): %s",
                tostring(entry.event), tostring(entry.session), tostring(entry.seq),
                tostring(entry.total), tostring(err))
        end
        sent = sent + 1
    end
end

mod:network_register("ct_sync_host_settings_chunk", function(sender_peer_id, schema_version, session, seq, total, chunk_str)
    -- Issue #27: schema-version gate. See CT_RPC_SCHEMA block near MOD_VERSION
    -- and VMF_RECIPES.md § 10. Mismatch = drop + _dbg_alert; no state mutation.
    if schema_version ~= CT_RPC_SCHEMA then
        _dbg_alert("[rpc:schema] %s mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
            "ct_sync_host_settings_chunk", tostring(sender_peer_id), tostring(schema_version), CT_RPC_SCHEMA)
        return
    end
    -- Issue #28 demo integration: record receive on bt's shared net-replay
    -- ring. Silent no-op if buff_tweaker isn't installed. The payload snippet
    -- captures the leading 200 chars of chunk_str so post-session log diff
    -- can reconstruct what arrived. Header tag prefixes session/seq/total so
    -- the tail of the snippet is the actual JSON fragment.
    do
        local bt = get_mod("bt")
        local nr = bt and bt.net_replay and bt:net_replay()
        if nr then
            local tag = string.format("session=%s seq=%s total=%s chunk=%s",
                tostring(session), tostring(seq), tostring(total), tostring(chunk_str))
            nr:record_recv("ct", "ct_sync_host_settings_chunk", tag, sender_peer_id)
        end
    end
    if type(session) ~= "number" or type(seq) ~= "number" or type(total) ~= "number" or type(chunk_str) ~= "string" then
        pcall(printf, "[ct_sync] malformed chunk from %s; ignoring", tostring(sender_peer_id))
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
        pcall(printf, "[ct_sync] decode failed from %s (session %s, %d bytes)",
            tostring(sender_peer_id), tostring(session), #json)
        return
    end
    for _, name in ipairs(SYNCED_SETTING_NAMES) do
        _ct_host_settings[name] = payload[name]
    end
    _ct_host_sync_received = true
    _dbg("[ct_sync] received host settings from %s (session %s, %d chunks, %d bytes, %d keys)",
        tostring(sender_peer_id), tostring(session), entry.total, #json, #SYNCED_SETTING_NAMES)
    -- Client-side host-authoritative settings dump: now that _ct_host_settings is
    -- populated, effective_setting(id) resolves to the HOST's broadcast value, so this
    -- prints the config the client is actually running under (vs its own local get=).
    -- The helper is defined later in the file but populated by load time; this callback
    -- only fires at runtime, long after load, so the forward reference is safe.
    if mod._ct_dump_settings then mod._ct_dump_settings("host_sync") end
    if mod._ct919_log_profile_snapshot then mod._ct919_log_profile_snapshot("host_sync") end
    -- Issue #6 auto-probe: log the four chest_*_count keys the host pushed so a
    -- client-side log diff can spot setting drift without /verify_altars. Only
    -- the altar-determinism-relevant keys are dumped (full payload is verbose).
    _dbg("[altar:host_sync_arrived] from=%s session=%s host_settings: upgrade=%s melee=%s ranged=%s power_up=%s",
        tostring(sender_peer_id), tostring(session),
        tostring(payload.chest_upgrade_count), tostring(payload.chest_swap_melee_count),
        tostring(payload.chest_swap_ranged_count), tostring(payload.chest_power_up_count))
    -- v0.7.67 ordering fix: the manifest broadcast MUST fire BEFORE
    -- sync_host_dependent_state() because any of the 11 sync_* re-registration
    -- helpers it invokes (trait boons, dormants, miracles, etc.) can throw, and
    -- VMF's network_register safe-wrapper swallows the error — aborting the
    -- receiver body silently. Pre-0.7.67 the manifest line was last; if anything
    -- in sync_host_dependent_state threw, the host never saw the client's RECV
    -- and we couldn't tell version drift from "feature didn't fire" in logs.
    _dbg("[ct_peers] client received host ct_sync — broadcasting own manifest back to host")
    if _broadcast_local_manifest then
        _broadcast_local_manifest("server")
    end
    if sync_host_dependent_state then
        sync_host_dependent_state()
    end
end)

-- MIDRUN_SETTING_REBROADCAST_MARKER
-- Re-usable host->clients broadcast of the synced settings registry over the EXISTING
-- ct_sync_host_settings_chunk RPC (same schema/channel — no new registration). Called
-- from two places: DeusRunController.setup_run (run start) AND mod.on_setting_changed
-- (host edits a synced setting mid-run). Before this existed the broadcast lived only
-- inline in setup_run, so a host changing e.g. boons-per-chest/shrine mid-run never
-- reached clients — they stayed frozen at the run-start snapshot for the rest of the
-- run (reported 2026-06-17). Attached to `mod` (not a file-scope local) deliberately:
-- this chunk is near Lua 5.1's 200-locals-per-function cap, so new shared helpers go on
-- the mod table. Server-gated; no-op on clients / at menu (no peers). A fresh session id
-- per call means a client discards any partial stale buffer. `reason` is log-only.
function mod._ct_broadcast_host_settings(reason)
    local is_server = Managers and Managers.player and Managers.player.is_server
    if not is_server then return end
    local payload = {}
    for _, name in ipairs(SYNCED_SETTING_NAMES) do
        payload[name] = mod:get(name)
    end
    local ok, json = pcall(cjson.encode, payload)
    if not ok or type(json) ~= "string" then
        pcall(printf, "[ct_sync] payload encode failed; not broadcasting (%s)", tostring(reason))
        return
    end
    local json_len = #json
    local total = math.max(1, math.ceil(json_len / SYNC_CHUNK_SIZE))
    local session = math.floor(((Application and Application.time_since_launch and Application.time_since_launch()) or os.time()) * 1000) % 2147483647
    if session == 0 then session = 1 end
    local _bt = get_mod("bt")
    local _nr = _bt and _bt.net_replay and _bt:net_replay()
    -- Issue #205: SUPERSEDE pending host-settings chunks before enqueuing this
    -- snapshot. This broadcast is a COMPLETE snapshot of every SYNCED_SETTING_NAMES
    -- key, so any ct_sync_host_settings_chunk entries from a PRIOR broadcast still
    -- sitting un-drained in the paced FIFO are now redundant. Without this, a rapid
    -- burst of on_setting_changed edits (e.g. dragging a slider / toggling several
    -- settings in the gut Mod Tweaker) STACKS N full 46-chunk trains into the queue;
    -- the paced drainer then feeds all ~200 into Stingray's reliable send queue until
    -- it overflows its ~97 KB cap -> HOST CRASH. Dual-log confirmed 2026-06-30: host
    -- reliable-send-queue overflow at 204 msgs / 94 KB to the client, client received
    -- "46 chunks, 489 keys" at the SAME instant, then timed out 11 s later
    -- ("Rx age server 11.1s"). The #97 pacing throttles send RATE but does nothing
    -- about stacked redundant snapshots; this caps the host-settings portion of the
    -- FIFO at exactly one sync (~46 chunks) no matter how fast the host edits.
    -- Dropping un-sent OLD-session chunks is safe: the receiver keys by (sender,
    -- session) and only applies once ALL `total` chunks of a session arrive, so a
    -- never-completed old session is discarded when this fresh session's chunks land
    -- (see the fresh-session-id note at the top of this function). Only host-settings
    -- chunks are purged; graph-snapshot / peer-manifest chunks (separate syncs) stay.
    do
        local q = _ct_chunk_send_queue
        local w = 1
        for r = 1, #q do
            local e = q[r]
            if e and e.event ~= "ct_sync_host_settings_chunk" then
                q[w] = e
                w = w + 1
            end
        end
        for r = #q, w, -1 do q[r] = nil end
    end
    for seq = 1, total do
        local start_i = (seq - 1) * SYNC_CHUNK_SIZE + 1
        local stop_i = math.min(start_i + SYNC_CHUNK_SIZE - 1, json_len)
        local chunk_str = string.sub(json, start_i, stop_i)
        -- Issue #97: enqueue (paced by mod.update) instead of inline-bursting.
        -- record_send is deferred to actual emit time so the net_replay ring
        -- still records what left the wire (closure captures this chunk's args).
        local _rec
        if _nr then
            local _seq, _total, _cs = seq, total, chunk_str
            _rec = function()
                _nr:record_send("ct", "ct_sync_host_settings_chunk",
                    string.format("session=%d seq=%d total=%d chunk=%s", session, _seq, _total, _cs), "others")
            end
        end
        _ct_enqueue_chunk("ct_sync_host_settings_chunk", "others", CT_RPC_SCHEMA, session, seq, total, chunk_str, _rec)
    end
    _dbg("[ct_sync] broadcast host settings to clients (%s; session %d, %d chunks, %d bytes, %d keys)",
        tostring(reason), session, total, json_len, #SYNCED_SETTING_NAMES)
end

-- Regression guard for MIDRUN_SETTING_REBROADCAST_MARKER: the mid-run re-sync wiring must
-- be present and the two boon-count keys (the reported mid-run desync) must be in the
-- synced registry, else a host edit won't reach clients until the next run.
_rt_register("midrun_setting_rebroadcast_wired", function()
    if type(mod._ct_broadcast_host_settings) ~= "function" then
        return "MIDRUN-SYNC REGRESSION: mod._ct_broadcast_host_settings missing (mid-run host settings won't re-sync to clients)"
    end
    if type(mod._ct_synced_set) ~= "table" then
        return "MIDRUN-SYNC REGRESSION: mod._ct_synced_set membership table missing"
    end
    for _, k in ipairs({ "shrine_boon_count", "chest_boon_count" }) do
        if not mod._ct_synced_set[k] then
            return string.format("MIDRUN-SYNC REGRESSION: '%s' absent from synced set -- mid-run host edit won't reach clients", k)
        end
    end
end)

-- Boon-altar no-repeat bookkeeping: the taken-boon table must exist so the
-- no-repeat strip can read it (v0.7.152-dev: the mislabeled "Chest of Trials"
-- pay-with-coin schedule was removed -- it was wrongly re-pricing every boon
-- ALTAR via DeusChestExtension.power_up, shadowing the altar-reuse multiplier;
-- a real Chest of Trials is DeusCursedChestExtension with no coin cost).
_rt_register("boon_altar_no_repeat", function()
    if type(mod._ct_boon_altar_taken_boons) ~= "table" then
        return "mod._ct_boon_altar_taken_boons missing (boon-altar no-repeat table)"
    end
end)

-- Adventure-collectible -> coin coverage + leftover-book-spot big casket payout.
_rt_register("cw_collectible_and_big_casket", function()
    local set = mod._ct_collectible_to_coin
    if type(set) ~= "table" then return "mod._ct_collectible_to_coin missing" end
    -- Every dead Adventure collectible must share the same exact identity policy.
    if not set.loot_die then return "loot_die not in collectible->coin set" end
    if not set.lorebook_page then return "lorebook_page not in collectible->coin set" end
    if not set.painting_scrap then return "painting_scrap not in collectible->coin set" end
    if type(mod._ct351_rewrite_network_spawn) ~= "function" then
        return "#351 direct network-spawn rewrite missing (chest loot dice bypass PickupSystem)"
    end
    -- The big-casket 3x payout rides GameModeDeus._get_coins_amount_and_type; the
    -- class must exist and expose that method for our hook to have bound.
    if rawget(_G, "GameModeDeus") and type(GameModeDeus._get_coins_amount_and_type) ~= "function" then
        return "GameModeDeus._get_coins_amount_and_type missing (big-casket 3x hook can't bind)"
    end
end)

-- v0.7.165-dev: coin-reservation partition (Abundance-of-Life curse robust fix).
-- The _can_spawn hook reserves a deterministic slice of primary spawners as
-- coin-only so the ×3 potion curse can't drain coins out of the shared pool. This
-- marker asserts the partition is (a) wired, (b) deterministic, and (c) a PROPER
-- subset (neither empty nor total) -- an empty reservation = no guarantee, a total
-- reservation = potions/altars can never spawn.
_rt_register("coin_reservation_partition", function()
    local t = mod._ct_coin_reservation_test
    if type(t) ~= "table" or type(t.reserved) ~= "function" then
        return "mod._ct_coin_reservation_test missing (coin reservation not wired)"
    end
    if type(mod._ct_rebuild_coin_reserved_set) ~= "function" then
        return "mod._ct_rebuild_coin_reserved_set missing (rank-based reserve set not wired)"
    end
    if type(mod._ct_clear_coin_reserved_set) ~= "function" then
        return "mod._ct_clear_coin_reserved_set missing (reserve-set reset not wired)"
    end
    if not (type(t.fraction) == "number" and t.fraction > 0 and t.fraction < 1) then
        return "coin reserved fraction must be in (0,1), got " .. tostring(t.fraction)
    end
    -- Determinism: same input -> same output across calls.
    if t.reserved(0.5) ~= t.reserved(0.5) then
        return "reservation is non-deterministic for a fixed percentage_through_level"
    end
    -- Proper subset over a representative spread of percentage_through_level values.
    local reserved_n, total_n = 0, 0
    for i = 0, 100 do
        total_n = total_n + 1
        if t.reserved(i / 100) then reserved_n = reserved_n + 1 end
    end
    if reserved_n == 0 then
        return "coin reservation reserved ZERO spawners over [0,1] -- coins not guaranteed"
    end
    if reserved_n == total_n then
        return "coin reservation reserved ALL spawners over [0,1] -- potions/altars starved"
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
-- v0.7.124-dev: added `ls = level_seed` after host+client log diff (2026-05-26
-- session) showed host and client's local populate_graph produce DIFFERENT
-- level_seed values for the same node keys despite identical run_seed. Without
-- syncing level_seed, downstream per-mission generation paths that hash off
-- `node.level_seed` (curse-halo iconography, per-mission mutator config,
-- terror_event scheduling) can diverge between peers even when display fields
-- match. Issue: user reported "citadel of eternity mission curse doesn't match
-- what host set it to" — display curse matched on both peers, so the gap is
-- likely in a downstream consumer reading level_seed.
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
    ls = "level_seed",
}

local _ct_host_graph_snapshot = nil  -- { session = N, nodes = { [node_key] = { l=..., ... } } }
local _ct_graph_inbound = {}
local CT_GRAPH_SNAPSHOT_LIVE_APPLY_MARKER = "graph_snapshot_live_apply_before_mission_select_v0.7.299"
local _ct_graph_live_apply_log_count = 0

-- Walk the snapshot and copy synced fields onto each node in `graph_data` in place.
-- In-place mutation preserves `_path_graph` identity and `next` links. #53: skip
-- `_run_state:get_arena_belakor_node()` so vanilla's Belakor-temple swap from
-- DeusRunController._get_graph_data() is not reverted by the host snapshot.
local function apply_graph_snapshot(graph_data)
    if not (_ct_host_graph_snapshot and _ct_host_graph_snapshot.nodes and graph_data) then
        return 0
    end
    -- Resolve current arena_belakor_node (if any). nil = no temple yet; full apply.
    local arena_node_key
    do
        local mechanism = Managers and Managers.mechanism and Managers.mechanism:game_mechanism()
        local rc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
        local rs = rc and rc._run_state
        if rs and rs.get_arena_belakor_node then
            arena_node_key = rs:get_arena_belakor_node()
            if arena_node_key == "" then arena_node_key = nil end
        end
    end
    local applied, skipped = 0, 0
    for node_key, short_record in pairs(_ct_host_graph_snapshot.nodes) do
        if node_key == arena_node_key then
            skipped = skipped + 1
        else
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
                -- #68: make the client recognize host-injected adventure maps for UI
                -- icon/tint gates even when its own per-map toggle list differs.
                local bl = node.base_level
                if type(bl) ~= "string" and type(node.level) == "string" then
                    -- Fallback when the host didn't ship base_level: derive the base
                    -- from the permutation key, same intent as adventure_base_from_level_key
                    -- ("dlc_castle_slaanesh_path1" -> "dlc_castle"; "bell_dup1_khorne_path1"
                    -- -> "bell"). Strip the _dup<N> alias then the trailing _<theme>_path<N>.
                    bl = node.level:gsub("_dup%d+", ""):gsub("_%a+_path%d+$", "")
                end
                if type(bl) == "string"
                   and AdventurePool and AdventurePool.MISSION_BY_KEY and AdventurePool.MISSION_BY_KEY[bl]
                   and AdventurePool.IS_INJECTED_ADVENTURE_LEVEL
                   and not AdventurePool.IS_INJECTED_ADVENTURE_LEVEL[bl] then
                    AdventurePool.IS_INJECTED_ADVENTURE_LEVEL[bl] = true
                    _dbg("[#68] client now recognizes host-injected adventure base '%s' (from graph snapshot)", bl)
                end
                applied = applied + 1
            end
        end
    end
    if skipped > 0 then
        _dbg("[ct_graph] apply skipped %d node(s) for arena_belakor swap preservation (key=%s)",
            skipped, tostring(arena_node_key))
    end
    return applied
end

-- #136: mission/loadout code also reads DeusRunController directly, so clients
-- apply the host graph snapshot to the live run graph as soon as chunks assemble.
local function apply_host_graph_snapshot_to_live_run(reason)
    if not _ct_host_graph_snapshot then
        return 0, "no_snapshot"
    end
    local mechanism = Managers and Managers.mechanism and Managers.mechanism.game_mechanism
        and Managers.mechanism:game_mechanism()
    local rc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
    if not (rc and rc.get_graph_data) then
        if _ct_graph_live_apply_log_count < 8 then
            _ct_graph_live_apply_log_count = _ct_graph_live_apply_log_count + 1
            _dbg("[ct:136] live snapshot apply deferred reason=%s status=no_run_controller marker=%s",
                tostring(reason), CT_GRAPH_SNAPSHOT_LIVE_APPLY_MARKER)
        end
        return 0, "no_run_controller"
    end
    local ok, graph_data = pcall(function() return rc:get_graph_data() end)
    if not ok or type(graph_data) ~= "table" then
        if _ct_graph_live_apply_log_count < 8 then
            _ct_graph_live_apply_log_count = _ct_graph_live_apply_log_count + 1
            _dbg("[ct:136] live snapshot apply deferred reason=%s status=%s marker=%s",
                tostring(reason), tostring(graph_data), CT_GRAPH_SNAPSHOT_LIVE_APPLY_MARKER)
        end
        return 0, "no_graph_data"
    end
    local applied = apply_graph_snapshot(graph_data)
    if applied > 0 or _ct_graph_live_apply_log_count < 8 then
        _ct_graph_live_apply_log_count = _ct_graph_live_apply_log_count + 1
        _dbg("[ct:136] live snapshot apply reason=%s applied=%d session=%s marker=%s",
            tostring(reason), applied, tostring(_ct_host_graph_snapshot.session),
            CT_GRAPH_SNAPSHOT_LIVE_APPLY_MARKER)
    end
    return applied, "applied"
end

mod:network_register("ct_graph_snapshot_chunk", function(sender_peer_id, schema_version, session, seq, total, chunk_str)
    -- Issue #27: schema-version gate. See CT_RPC_SCHEMA block near MOD_VERSION
    -- and VMF_RECIPES.md § 10. Mismatch = drop + _dbg_alert; no state mutation.
    if schema_version ~= CT_RPC_SCHEMA then
        _dbg_alert("[rpc:schema] %s mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
            "ct_graph_snapshot_chunk", tostring(sender_peer_id), tostring(schema_version), CT_RPC_SCHEMA)
        return
    end
    if type(session) ~= "number" or type(seq) ~= "number" or type(total) ~= "number" or type(chunk_str) ~= "string" then
        pcall(printf, "[ct_graph] malformed chunk from %s; ignoring", tostring(sender_peer_id))
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
        pcall(printf, "[ct_graph] decode failed from %s (session %s, %d bytes)",
            tostring(sender_peer_id), tostring(session), #json)
        return
    end
    _ct_host_graph_snapshot = { session = session, nodes = payload }
    local node_count = 0
    for _ in pairs(payload) do node_count = node_count + 1 end
    _dbg("[ct_graph] received host graph snapshot from %s (session %s, %d chunks, %d bytes, %d nodes)",
        tostring(sender_peer_id), tostring(session), entry.total, #json, node_count)
    apply_host_graph_snapshot_to_live_run("ct_graph_snapshot_chunk")
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
        pcall(printf, "[ct_graph] payload encode failed; not broadcasting")
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
        -- Issue #27: CT_RPC_SCHEMA prepended as first arg. Receiver gates on it.
        -- Issue #97: enqueue (paced by mod.update) instead of inline-bursting.
        _ct_enqueue_chunk("ct_graph_snapshot_chunk", "others", CT_RPC_SCHEMA, session, seq, total, chunk_str)
    end
    _dbg("[ct_graph] broadcast host graph snapshot (session %d, %d chunks, %d bytes, %d nodes)",
        session, total, json_len, node_count)
end

    return {
        apply_graph_snapshot = apply_graph_snapshot,
        apply_host_graph_snapshot_to_live_run = apply_host_graph_snapshot_to_live_run,
        broadcast_graph_snapshot = broadcast_graph_snapshot,
        chunk_size = SYNC_CHUNK_SIZE,
        collect_setting_ids = _collect_setting_ids,
        enqueue_chunk = _ct_enqueue_chunk,
        host_graph_snapshot = function() return _ct_host_graph_snapshot end,
        host_settings = _ct_host_settings,
        host_sync_received = function() return _ct_host_sync_received end,
        synced_setting_names = SYNCED_SETTING_NAMES,
    }
end
