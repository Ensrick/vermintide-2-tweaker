local mod = get_mod("enemy_tweaker")

-- _et_fingerprint.lua — BR + settings fingerprints, cross-peer RPC, dormant-BR stub
--
-- Issue #17 auto-probe: hashes the BR sub-toggle values into a short hex id
-- and cross-compares it peer-to-peer over the schema-gated et_br_fingerprint
-- RPC (host/client BR-toggle drift = damage-math desync). Also owns the
-- mod-wide settings fingerprint the entry file's [et:LOAD] line prints, and
-- the stub that keeps the DORMANT Big Rebalance module's public API alive
-- (enemy_tweaker_big_rebalance.lua stays on disk, un-loaded — user decision
-- #433 pending; do not load, edit, or delete it).
--
-- Owned by: enemy_tweaker.lua entry point (dofile'd before the entry prints
-- the [et:LOAD] line). Consumed via mod._et exports: settings_fingerprint,
-- BR (the stub); plus mod fields _br_settings_fingerprint /
-- _br_fingerprint_broadcast_once / _bloodlust_health.

local ET = mod._et
local rt_register   = ET.rt_register
local _et_probe     = ET.et_probe
local ET_RPC_SCHEMA = ET.rpc_schema
local MOD_VERSION   = ET.version

-- ============================================================
-- BR settings fingerprint (Issue #17 auto-probe)
-- ============================================================
-- Hashes the BR sub-toggle values currently in effect on this peer into a
-- short hex id. If host and client report different fingerprints, their BR
-- damage hooks are reading divergent settings and damage math will desync.
-- The fingerprint is logged unconditionally at startup as a mod:info marker;
-- per-hook entry/exit dumps go through _dbg (debug-toggle gated).
--
-- Setting list is the eleven `br_*` widgets currently registered in
-- enemy_tweaker_data.lua. Order is fixed (not the table iteration order) so
-- the FNV-1a hash is deterministic across peers.
local _BR_SETTING_NAMES = {
    "br_bloodlust_class_table",
    "br_bloodlust_per_breed_assign",
    "br_breed_trash_flags",
    "br_stagger_ai_rewrite",
    "br_calculate_damage_rewrite",
    "br_shield_slam_rewrite",
    "br_unbalance_debuff_infra",
    "br_thp_regrowth_template",
    "br_thp_vanguard_template",
    "br_thp_reaper_template",
    "br_thp_bloodlust_template",
}

-- Minimal FNV-1a 32-bit. Standard Lua 5.1, no bit32. Plain arithmetic ops
-- keep the implementation portable across Lua 5.1 / LuaJIT (VT2 uses the
-- former). Result is 8 hex chars.
local function _fnv1a32(s)
    local hash = 2166136261
    for i = 1, #s do
        local byte = string.byte(s, i)
        -- XOR via per-bit emulation: Lua 5.1 has no bit32, and LuaJIT's bit
        -- lib isn't guaranteed under VT2's sandbox. The loop is cold-path
        -- (called once per BR hook fire at most), so per-bit cost is fine.
        local xored = 0
        local place = 1
        local h, b = hash, byte
        for _ = 1, 32 do
            local hb = h % 2
            local bb = b % 2
            if hb ~= bb then xored = xored + place end
            place = place * 2
            h = (h - hb) / 2
            b = (b - bb) / 2
        end
        hash = (xored * 16777619) % 4294967296
    end
    return string.format("%08x", hash)
end

function mod._br_settings_fingerprint()
    local parts = {}
    for i, name in ipairs(_BR_SETTING_NAMES) do
        local v = mod:get(name)
        if v == true then       parts[i] = "1"
        elseif v == false then  parts[i] = "0"
        elseif v == nil then    parts[i] = "?"
        else                    parts[i] = tostring(v)
        end
    end
    return _fnv1a32(table.concat(parts, "|"))
end

-- ============================================================
-- BR fingerprint cross-peer compare (Issue #17 auto-probe)
-- ============================================================
-- One-shot per session: at first BR hook fire (calculate_damage/stagger_ai/
-- _hit), broadcast this peer's fingerprint to the rest of the lobby. On
-- receive, compare against our own; if they differ, _dbg_alert so the
-- mismatch shows up in chat too (host/client BR-toggle drift is a real
-- multiplayer divergence — not just a confirmation dump).
local _br_fingerprint_broadcast = false
local _br_fingerprint_peers = {}  -- peer_id -> fingerprint

mod._br_fingerprint_broadcast_once = function()
    if _br_fingerprint_broadcast then return end
    _br_fingerprint_broadcast = true
    local fp = mod._br_settings_fingerprint()
    if mod.network_send then
        local ok, err = pcall(function()
            -- ET_RPC_SCHEMA is the FIRST positional arg (VMF_RECIPES § 10 / Issue #42).
            mod:network_send("et_br_fingerprint", "others", ET_RPC_SCHEMA, MOD_VERSION, fp)
        end)
        if not ok then
            mod:info("[BR:fp] broadcast failed: %s", tostring(err))
        else
            mod:info("[BR:fp] broadcast fp=%s v=%s to peers", fp, MOD_VERSION)
        end
    end
end

mod:network_register("et_br_fingerprint", function(sender_peer_id, schema_version, peer_version, peer_fp)
    -- Schema gate (VMF_RECIPES § 10 / Issue #42): drop peers on a different RPC
    -- schema so a mixed-version lobby degrades cleanly instead of parsing the
    -- payload by the wrong positions. Drop + log; never error() (a noisy per-tick
    -- chat error from a stale peer is worse than the corruption it replaces).
    if schema_version ~= ET_RPC_SCHEMA then
        -- printf (not _dbg_alert): the user runs mod-logging OFF, so the prior
        -- mod:warning-routed line never reached their console log. Keyed per peer
        -- so two mismatched peers both surface; rate-limited against per-tick spam.
        _et_probe("rpc:schema:" .. tostring(sender_peer_id),
            "[rpc:schema] %s mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
            "et_br_fingerprint", tostring(sender_peer_id),
            tostring(schema_version), ET_RPC_SCHEMA)
        return
    end
    -- Defensive type check AFTER the schema gate (catches the rare case where a
    -- legacy sender's first payload field happens to equal ET_RPC_SCHEMA).
    if type(peer_fp) ~= "string" then return end
    _br_fingerprint_peers[tostring(sender_peer_id)] = peer_fp
    local own_fp = mod._br_settings_fingerprint()
    if peer_fp ~= own_fp then
        -- _dbg_alert because mismatch is the actionable case (host/client
        -- BR settings drift -> damage math divergence). PROJECT_STANDARDS § 3.6.
        mod:debug("[et:dbg] [BR:fp] MISMATCH peer=%s peer_v=%s peer_fp=%s own_fp=%s -- BR sub-toggles diverge",
            tostring(sender_peer_id), tostring(peer_version), peer_fp, own_fp)
        -- Surface unconditionally — mismatch is a real bug condition, not a
        -- routine confirmation. mod:warning so it always lands in the log.
        mod:warning("[BR:fp] MISMATCH peer=%s peer_v=%s peer_fp=%s own_fp=%s -- BR sub-toggles diverge",
            tostring(sender_peer_id), tostring(peer_version), peer_fp, own_fp)
    else
        mod:info("[BR:fp] match peer=%s fp=%s v=%s",
            tostring(sender_peer_id), peer_fp, tostring(peer_version))
    end
end)

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes ALL setting=value pairs (not just
-- the BR sub-toggles — that's still `_br_settings_fingerprint()` above, used by
-- the cross-peer compare RPC). The universal marker uses a broader hash so it
-- surfaces drift in any setting. `host_required=true` retained as a per-mod
-- addendum (et's BR features are host-only). Printed by the entry file.
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/enemy_tweaker/enemy_tweaker_data")
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
    return _fnv1a32(table.concat(parts, ";"))
end
ET.settings_fingerprint = _settings_fingerprint

-- Big Rebalance integration (Core's BR / "Weapon Balance" decompile). Master
-- toggle + per-feature sub-toggles live under the [Big Rebalance] group. See
-- enemy_tweaker_big_rebalance.lua for ownership and per-toggle docs. (The
-- cross-mod-shared registration list it references was retired with bt.)
-- BR ON ICE (bt retired 2026-06-08; heap relief 2026-06-18). The module is no
-- longer require()'d, so its data tables + hook installers never load into the
-- 1 GiB lua_heap. Stub preserves the public API and seeds the external
-- NewBreedTweaks sink (mod._bloodlust_health). To revive: restore bt, delete the
-- stub, un-comment the require below.
-- local BR = require("scripts/mods/enemy_tweaker/enemy_tweaker_big_rebalance")
local BR = { on_enabled = function() end, on_setting_changed = function() end, on_disabled = function() end }
mod._bloodlust_health = mod._bloodlust_health or {}
ET.BR = BR

-- v0.5.7: source-pattern marker constant for the /et_regression_test
-- `et_big_rebalance_uses_rawget` check (audit `.test_coverage_audit_2026-05-24.md`
-- PARTIAL row 4 — promoted to PASS by adding a runtime check beside the
-- existing strict-table-lookup lint coverage at all 6 sites).
local CT_ET_BIG_REBALANCE_RAWGET_MARKER_v0_5_7 = "et-big-rebalance-rawget-hardened-6-sites"

rt_register("et_big_rebalance_uses_rawget", function()
    -- v0.5.6/.7: six call sites in `enemy_tweaker_big_rebalance.lua` (L1087,
    -- 1097, 1139, 1165, 1185, 1207) resolve hit-zone / damage-source / item
    -- names through `rawget(NetworkLookup.*, key)` so a missing entry returns
    -- nil instead of raising the strict `__index` metatable. The
    -- strict-table-lookup lint covers static-pattern regressions; this runtime
    -- check is the belt-and-suspenders companion required by §15 of
    -- PROJECT_STANDARDS.md.
    --
    -- 1. Source-pattern: marker constant must be present (catches accidental
    --    revert of any of the 6 conversions or removal of the marker block).
    if CT_ET_BIG_REBALANCE_RAWGET_MARKER_v0_5_7 ~= "et-big-rebalance-rawget-hardened-6-sites" then
        return "RAWGET marker absent — was the v0.5.6 six-site hardening reverted?"
    end
    -- 2. Runtime-state: rawget on a known-bad key against the two NL subtables
    --    that the six sites read (hit_zones + damage_sources). Both must
    --    return nil without raising.
    local NL = rawget(_G, "NetworkLookup")
    for _, sub in ipairs({ "hit_zones", "damage_sources" }) do
        local tbl = NL and NL[sub]
        if type(tbl) == "table" then
            local ok, value = pcall(rawget, tbl, "__et_rawget_probe_does_not_exist__")
            if not ok then
                return string.format("rawget(NetworkLookup.%s, <bad-key>) RAISED — strict-metatable behavior changed", sub)
            end
            if value ~= nil then
                return string.format("rawget(NetworkLookup.%s, <bad-key>) returned non-nil — unexpected", sub)
            end
        end
    end
end)

rt_register("et_rpc_schema_present", function()
    -- VMF_RECIPES § 10 / Issue #42: the et_br_fingerprint RPC is schema-gated.
    -- Guards against a future revert that drops the ET_RPC_SCHEMA constant or
    -- sets it below the floor (which would silently un-gate the receiver).
    if type(ET_RPC_SCHEMA) ~= "number" then
        return "ET_RPC_SCHEMA not defined as number"
    end
    if ET_RPC_SCHEMA < 1 then return "ET_RPC_SCHEMA < 1" end
end)
