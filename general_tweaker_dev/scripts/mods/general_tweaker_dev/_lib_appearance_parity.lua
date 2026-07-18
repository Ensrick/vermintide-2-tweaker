-- ============================================================================
-- SHARED LIBRARY  --  appearance-mod parity comparison (issue 371 / issue 737)
-- ----------------------------------------------------------------------------
-- MASTER SOURCE: tools/shared_lib/_lib_appearance_parity.lua
-- DO NOT EDIT THE COPY. The runtime copy lives at
--     general_tweaker_dev/scripts/mods/general_tweaker_dev/_lib_appearance_parity.lua
-- and is loaded via
--     mod:dofile("scripts/mods/general_tweaker_dev/_lib_appearance_parity").
-- VMB bundles ONLY a mod's own scripts/, so a runtime dofile cannot reach
-- tools/shared_lib -- edit THIS master, then copy the whole file (verbatim) to
-- the consumer. qa/lua/tests/test_gt_appearance_parity.lua dofiles the master
-- and asserts the copy is byte-identical, so drift fails the suite.
-- ============================================================================
--
-- WHAT THIS IS
--   The PURE, engine-free comparison core behind the in-lobby appearance-parity
--   banner. No VT2 globals, no mod state, no side effects -- callers inject the
--   host's parsed lobby manifest and the local mod index; this returns the
--   asymmetries + a stable composition key so the runtime consumer fires ONE
--   chat line per lobby composition change.
--
-- WHY it exists (issue 737, 2026-07-18)
--   A mixed lobby -- host on wt 0.12.274-beta DISABLED, both clients on wt_dev
--   0.12.275-dev ENABLED -- desynced the NetworkLookup.weapon_skins index space
--   (host cwv injections at 913-946, clients shifted), producing a score-sync
--   CTD on index 924 plus every husk/preview surface resolving modded gear to
--   base for the whole session. The join SUCCEEDED (the network_hash ignores the
--   VMF mod set -- see _gt_lobby_failed_join_reveal.lua's watchdog note), so
--   neither the failed-join reveal nor the stalled-join watchdog fired. The one
--   thing that would have caught it in second one was a lobby line naming the
--   asymmetric appearance mod and both peers' states. That is what this powers.
--
-- APPEARANCE MODS (the desync-bearing subset of the manifest)
--   Only mods that put mod-only indices onto the shared NetworkLookup / item key
--   spaces desync appearance across peers. dev/stable variants (wt/wt_dev,
--   cim/cim_dev) share a FAMILY so a stream split reads as one mod at two
--   streams, not two unrelated warnings.

local M = {}

-- id (as it appears in the manifest / Managers.mod._mods) -> { family, label }.
M.APPEARANCE_MODS = {
    wt                        = { family = "weapon_tweaker",     label = "Weapon Tweaker" },
    wt_dev                    = { family = "weapon_tweaker",     label = "Weapon Tweaker" },
    character_weapon_variants = { family = "cwv",                label = "Character Weapon Variants" },
    cosmetics_tweaker         = { family = "cosmetics",          label = "Cosmetics Tweaker" },
    WOC                       = { family = "weapons_of_chaos",   label = "Weapons of Chaos" },
    cim                       = { family = "crafting_in_modded", label = "Crafting in Modded" },
    cim_dev                   = { family = "crafting_in_modded", label = "Crafting in Modded" },
}

-- family -> label, precomputed once so records carry the canonical mod name even
-- for a stream mismatch (host wt vs your wt_dev) where the two ids differ.
local FAMILY_LABEL = {}
for _, meta in pairs(M.APPEARANCE_MODS) do
    FAMILY_LABEL[meta.family] = meta.label
end
M.FAMILY_LABEL = FAMILY_LABEL

-- The manifest producer (_gt_lobby_modded_manifest.lua) writes
-- "version_unavailable" when a sister mod keeps its MOD_VERSION file-local
-- instead of exposing mod.MOD_VERSION. Treat that sentinel and empty as UNKNOWN
-- so we never compare against a placeholder and never emit a false version
-- warning. Presence asymmetry (the issue 737 root) needs no version at all.
local function _norm_version(v)
    if type(v) ~= "string" or v == "" or v == "version_unavailable" then return nil end
    return v
end
M._norm_version = _norm_version

-- Parse the host manifest wire format published under lobby_data key ltw_m*:
-- TAB-separated "id<TAB>version<TAB>mode<TAB>workshop_id<TAB>name" per line,
-- newline-joined. Mirrors _gt_lobby_failed_join_reveal.lua's parser (same
-- producer, same format); unknown trailing fields are ignored.
function M.parse_manifest(text)
    local out = {}
    if type(text) ~= "string" or text == "" then return out end
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then
            local fields = {}
            for f in (line .. "\t"):gmatch("([^\t]*)\t") do
                fields[#fields + 1] = f
            end
            if #fields >= 5 and fields[1] ~= "" then
                out[#out + 1] = {
                    id = fields[1],
                    version = fields[2] or "",
                    mode = fields[3],
                    workshop_id = fields[4] or "0",
                    display_name = (fields[5] ~= "" and fields[5]) or fields[1],
                }
            end
        end
    end
    return out
end

-- Reduce the HOST manifest (a list; presence in the manifest == enabled on the
-- host) to family -> { id, version }. First present id per family wins.
local function _reduce_host(host_entries)
    local by_family = {}
    for _, e in ipairs(host_entries or {}) do
        local meta = e and e.id and M.APPEARANCE_MODS[e.id]
        if meta and not by_family[meta.family] then
            by_family[meta.family] = { id = e.id, version = _norm_version(e.version) }
        end
    end
    return by_family
end

-- Reduce the LOCAL mod index (id -> { enabled, version, name }; the shape
-- _gt_lobby_failed_join_reveal.lua's _build_local_index returns) to
-- family -> { id, version }. A locally-DISABLED appearance mod injects nothing,
-- so it counts as absent.
local function _reduce_local(local_index)
    local by_family = {}
    for id, entry in pairs(local_index or {}) do
        local meta = M.APPEARANCE_MODS[id]
        if meta and entry and entry.enabled and not by_family[meta.family] then
            by_family[meta.family] = { id = id, version = _norm_version(entry.version) }
        end
    end
    return by_family
end

-- Deterministic sorted family list over the union of both sides.
local function _ordered_families(host, mine)
    local seen, out = {}, {}
    for f in pairs(host) do if not seen[f] then seen[f] = true; out[#out + 1] = f end end
    for f in pairs(mine) do if not seen[f] then seen[f] = true; out[#out + 1] = f end end
    table.sort(out)
    return out
end

-- Compare the appearance-mod subset of the host manifest against the local mod
-- index. Returns a sorted list of asymmetry records, each:
--   { family, label, kind, host = {id,version}|nil, mine = {id,version}|nil, show_ids }
-- kind is one of:
--   "presence_local_only" -- enabled for you, absent on the host (issue 737: you
--                            inject indices the host lacks -> the host can CTD
--                            receiving your modded skins).
--   "presence_host_only"  -- enabled on the host, absent for you (you can CTD
--                            receiving the host's modded content).
--   "version"             -- present both sides but a different stream (ids
--                            differ, show_ids=true) or a different version of the
--                            same id (show_ids=false). Only reported when it can
--                            be PROVEN: a version mismatch needs both versions
--                            known, so unknown-vs-unknown never false-alarms.
function M.diff(host_entries, local_index)
    local host = _reduce_host(host_entries)
    local mine = _reduce_local(local_index)
    local out = {}
    for _, f in ipairs(_ordered_families(host, mine)) do
        local h, l = host[f], mine[f]
        local label = FAMILY_LABEL[f] or f
        if h and not l then
            out[#out + 1] = { family = f, label = label, kind = "presence_host_only",
                host = h, mine = nil, show_ids = false }
        elseif l and not h then
            out[#out + 1] = { family = f, label = label, kind = "presence_local_only",
                host = nil, mine = l, show_ids = false }
        elseif h and l then
            local ids_differ = h.id ~= l.id
            local versions_differ = h.version ~= nil and l.version ~= nil and h.version ~= l.version
            if ids_differ or versions_differ then
                out[#out + 1] = { family = f, label = label, kind = "version",
                    host = h, mine = l, show_ids = ids_differ }
            end
        end
    end
    return out
end

-- Stable fingerprint of the appearance composition (host set + local set). The
-- runtime consumer fires the banner only when this changes, so it posts ONE line
-- per lobby composition change rather than every poll. Built from the SAME
-- reduced data as diff(), so it moves exactly when a warning could change.
function M.composition_key(host_entries, local_index)
    local function ser(by_family)
        local fs = {}
        for f in pairs(by_family) do fs[#fs + 1] = f end
        table.sort(fs)
        local parts = {}
        for _, f in ipairs(fs) do
            local e = by_family[f]
            parts[#parts + 1] = f .. "=" .. tostring(e.id) .. "@" .. tostring(e.version or "?")
        end
        return table.concat(parts, ",")
    end
    return "H[" .. ser(_reduce_host(host_entries)) .. "]L[" .. ser(_reduce_local(local_index)) .. "]"
end

-- Render one peer's state for the banner. show_ids surfaces the mod id (needed
-- to tell wt from wt_dev in a stream mismatch); otherwise the family label
-- already names the mod, so the id would be redundant noise.
local function _state_str(side, show_ids)
    if not side then return "not present" end
    local id_part = show_ids and side.id or nil
    if side.version then
        return id_part and (id_part .. " " .. side.version) or side.version
    end
    return id_part and (id_part .. " (enabled)") or "enabled"
end
M._state_str = _state_str

-- Build the single chat line. No em dashes (menu/chat string rule). Contains no
-- '%'; the consumer still escapes before mod:echo, which runs its arg through
-- string.format.
function M.format_banner(record)
    return string.format(
        "Parity warning: %s - host: %s, you: %s - modded appearance may desync",
        record.label,
        _state_str(record.host, record.show_ids),
        _state_str(record.mine, record.show_ids))
end

return M
