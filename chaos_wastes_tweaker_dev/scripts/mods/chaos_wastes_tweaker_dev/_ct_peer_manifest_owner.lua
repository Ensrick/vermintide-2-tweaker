--[[
_ct_peer_manifest_owner - peer/version/settings diagnostics owner (#1159 / #2).

Owns the complete peer-manifest lifecycle: deterministic local manifest
construction, bounded chunked broadcast through the shared paced-send queue,
schema-gated reassembly, host-vs-peer diff logging, and the `/peers` command.

The entry installs this owner exactly where the former inline block executed,
so the `ct_peer_manifest_chunk` RPC and `/peers` command keep their original
registration order. The settings-sync receiver is defined earlier and calls the
returned `broadcast_local_manifest` through its existing late-bound entry slot.
The run-creation owner consumes the returned build/log helpers for its unchanged
run-start host baseline.

Cross-file dependencies are explicit in ctx. `synced_setting_names` is the
realized ordered registry, `enqueue_chunk` is the shared #97 paced transport,
and `chunk_size`/`rpc_schema` are the existing wire constants. No protocol,
payload, target, timing, or engine table is changed by this extraction.
]]

local function install(mod, ctx)
    assert(type(ctx) == "table", "_ct_peer_manifest_owner requires a context table")
    assert(type(ctx.dbg) == "function", "_ct_peer_manifest_owner requires ctx.dbg")
    assert(type(ctx.dbg_alert) == "function", "_ct_peer_manifest_owner requires ctx.dbg_alert")
    assert(type(ctx.cjson) == "table", "_ct_peer_manifest_owner requires ctx.cjson")
    assert(type(ctx.cjson.encode) == "function", "_ct_peer_manifest_owner requires ctx.cjson.encode")
    assert(type(ctx.cjson.decode) == "function", "_ct_peer_manifest_owner requires ctx.cjson.decode")
    assert(type(ctx.enqueue_chunk) == "function", "_ct_peer_manifest_owner requires ctx.enqueue_chunk")
    assert(type(ctx.mod_version) == "string", "_ct_peer_manifest_owner requires ctx.mod_version")
    assert(type(ctx.rpc_schema) == "number", "_ct_peer_manifest_owner requires ctx.rpc_schema")
    assert(type(ctx.synced_setting_names) == "table",
        "_ct_peer_manifest_owner requires ctx.synced_setting_names")
    assert(type(ctx.chunk_size) == "number" and ctx.chunk_size > 0,
        "_ct_peer_manifest_owner requires a positive ctx.chunk_size")

    local _dbg = ctx.dbg
    local _dbg_alert = ctx.dbg_alert
    local cjson = ctx.cjson
    local _ct_enqueue_chunk = ctx.enqueue_chunk
    local MOD_VERSION = ctx.mod_version
    local CT_RPC_SCHEMA = ctx.rpc_schema
    local SYNCED_SETTING_NAMES = ctx.synced_setting_names
    local SYNC_CHUNK_SIZE = ctx.chunk_size

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
        _dbg("[ct_peers] %s peer=%s ct=%s settings_hash=%08x vmf_ts=%s num_levels=%s enabled_mods=%d",
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
            _dbg("[ct_peers]   DIFF peer=%s: %s", tostring(peer_id), table.concat(diffs, "; "))
        else
            _dbg("[ct_peers]   peer=%s matches host", tostring(peer_id))
        end
    end

    local function _broadcast_local_manifest(target)
        local manifest = _build_local_manifest()
        local ok, json = pcall(cjson.encode, manifest)
        if not ok or type(json) ~= "string" then
            pcall(printf, "[ct_peers] manifest encode failed; not broadcasting")
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
            -- `target` is the function arg ("server" reply / "all" /peers dump).
            _ct_enqueue_chunk("ct_peer_manifest_chunk", target, CT_RPC_SCHEMA, session, seq, total, chunk_str)
        end
        return manifest, json_len, total
    end

    mod:network_register("ct_peer_manifest_chunk", function(sender_peer_id, schema_version, session, seq, total, chunk_str)
        -- Issue #27: schema-version gate. See CT_RPC_SCHEMA block near MOD_VERSION
        -- and VMF_RECIPES.md § 10. Mismatch = drop + _dbg_alert; no state mutation.
        if schema_version ~= CT_RPC_SCHEMA then
            _dbg_alert("[rpc:schema] %s mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
                "ct_peer_manifest_chunk", tostring(sender_peer_id), tostring(schema_version), CT_RPC_SCHEMA)
            return
        end
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
            pcall(printf, "[ct_peers] manifest decode failed from %s", tostring(sender_peer_id))
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

    return {
        broadcast_local_manifest = _broadcast_local_manifest,
        build_local_manifest = _build_local_manifest,
        log_peer_manifest = _log_peer_manifest,
    }
end

return install
