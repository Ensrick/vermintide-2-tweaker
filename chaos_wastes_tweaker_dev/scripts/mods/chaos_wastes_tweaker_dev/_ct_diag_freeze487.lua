--[[
_ct_diag_freeze487 - Chaos Wastes load-freeze instrumentation (issue #487).

WHY THIS EXISTS
    Issue #487: the game freezes ("stuck on loading initializing the Chaos
    Wastes"; menus respond, game input does not) after queuing a run. The user's
    own hypothesis: it happens after disabling all-but-one available mission, and
    the intended behaviour is to REPEAT a mission to fill the map when fewer are
    enabled than the graph has nodes. No crash dump exists (a freeze, not a
    crash), and the two attached console logs are clean sessions that never hit
    the freeze - so the root cause is NOT provable from evidence yet. Per the
    diagnose-before-mitigating doctrine this module ships INSTRUMENTATION ONLY.

WHAT IT INSTRUMENTS
    The suspect region is the deus map-graph build. `DeusRunController.setup_run`
    (deus_run_controller.lua:284) calls `deus_generate_graph` ->
    `deus_populate_graph`, a backtracking constraint solver capped at 100000
    iterations (deus_populate_graph.lua:1006-1020). Two of its per-node validators
    - `prevent_same_level_on_same_path` / `prevent_same_level_choice`
    (deus_populate_graph.lua:165-197) - reject a level KEY already used on the
    path, so a TRAVEL/SIGNATURE pool with fewer DISTINCT keys than the longest
    same-type path has nodes cannot be solved; the solver then burns its whole
    iteration budget (a multi-second stall = perceived freeze) and returns nil.
    PROVEN cause (#487, 2026-07-13 host log): the failure is not budget exhaustion
    but a THROW. The baked journeys (citadel/cave/ice/ruin) assign labeled nodes a
    level by indexing `shuffled_levels_for_labels[type][node_label]`
    (deus_populate_graph.lua:460); that list is the pool's distinct keys, so a pool
    with fewer distinct keys than the node's label leaves node.level nil and :462
    `levels_available[nil].paths` throws -> graph nil -> freeze. Max TRAVEL label is
    6 (citadel), so a floored pool needs 6 distinct keys, not 4.

    ct's own `_adventure_pool.inject_duplicate_aliases` is the safety net for
    this (mints `<key>_dupN` distinct keys up to POOL_SAFETY_THRESHOLD=6 by cloning
    the user's ENABLED missions, so an underflowed run REPEATS them). A pool the
    user empties of ALL enabled missions has nothing to clone; `_adventure_pool`'s
    zero-enabled fallback (fall_back_zero_enabled_pools) restores that pool's vanilla
    contents so the solver still has assignable keys. So an EMPTY line below should no
    longer occur in normal use - if it does, BOTH the duplication and the fallback
    failed (snapshot missing), which is a real bug to chase.

OUTPUT
    engine `printf` only (visible with mod logging OFF, and flushed to the console
    log synchronously - so if the game hard-freezes inside the solve, the BEGIN
    breadcrumb is the last log line and pinpoints it with the pool state). Prefix
    `[ct:487]`. Always-on in this dev build; no menu toggle (diagnostics doctrine).

PUBLIC SURFACE (mod._ct_freeze487)
    .begin_generate(journey_name, is_server) - breadcrumb + pool snapshot, arms timer
    .finish_generate(journey_name, path_graph) - elapsed + solve outcome, disarms
    .tick(dt)                                 - per-frame stall watchdog
    .pool_snapshot(journey_name)              - returns the snapshot string (reusable)
    .MARKER                                   - source-pattern regression anchor

MANIFEST POSITION: dofile'd right after `_adventure_pool` (both are CW-map
    concerns); must precede the `mod.update` definition and the
    `DeusRunController.setup_run` hook, which are its only call sites.
]]

local mod = get_mod("ct_dev")

local M = {}

-- Regression / ship-scan source anchor. Bump the version tail when the diagnostic
-- shape changes so a stale reference is visible in review.
M.MARKER = "CT_FREEZE487_DIAG_v0.7.242"

-- A graph solve slower than this is reported as a WARN even if it eventually
-- succeeds (the near-budget backtrack stall is the freeze symptom).
local SLOW_GENERATE_MS = 250
-- A single frame delta longer than this is a game-loop stall worth a line. The
-- deus solve is synchronous within one setup_run call, so a solve that recovers
-- surfaces here as one oversized dt on the recovery frame.
local FRAME_STALL_S = 3.0

-- The two graph node types whose per-path uniqueness constraint the pool must
-- satisfy (deus_populate_graph.lua LEVEL_VALIDATIONS). SHOP is reported for
-- context only (its sole validator is prevent_same_level_choice, siblings only).
local WATCHED_POOLS = { "TRAVEL", "SIGNATURE", "SHOP" }

-- { label = <string>, t0 = <os.clock seconds> } while a bracketed region is open.
local _active = nil
local _active_warned = false

local function _safe_printf(fmt, ...)
    if rawget(_G, "printf") then
        pcall(printf, fmt, ...)
    end
end

local function _clock()
    local ok, v = pcall(os.clock)
    if ok and type(v) == "number" then return v end
    return 0
end

-- Count entries in one LEVEL_AVAILABILITY pool, splitting real keys from the
-- `_dupN` aliases ct's safety net minted, so the log shows whether duplication
-- actually fired. Returns total, dup_count.
local function _count_pool(pool)
    if type(pool) ~= "table" then return nil, 0 end
    local total, dups = 0, 0
    for key in pairs(pool) do
        total = total + 1
        if type(key) == "string" and key:find("_dup%d+$") then
            dups = dups + 1
        end
    end
    return total, dups
end

-- Build the human-readable pool snapshot for a journey. Reads the LIVE
-- DEUS_MAP_POPULATE_SETTINGS the solver is about to consume (post filter +
-- post duplicate-injection), NOT the toggle state - what the generator actually
-- sees is the ground truth. Flags EMPTY pools (n==0, the un-duplicated deadlock
-- case) and UNDERFLOW pools (0 < n < POOL_SAFETY_THRESHOLD, the marginal case).
function M.pool_snapshot(journey_name)
    local settings = rawget(_G, "DEUS_MAP_POPULATE_SETTINGS")
    if type(settings) ~= "table" then
        return "pools=<DEUS_MAP_POPULATE_SETTINGS not loaded>"
    end
    local config = (journey_name and settings[journey_name]) or settings.default
    local la = config and config.LEVEL_AVAILABILITY
    if type(la) ~= "table" then
        return string.format("pools=<no LEVEL_AVAILABILITY for journey=%s>", tostring(journey_name))
    end

    local parts, empty, underflow = {}, {}, {}
    for _, pool_type in ipairs(WATCHED_POOLS) do
        local total, dups = _count_pool(la[pool_type])
        if total == nil then
            parts[#parts + 1] = string.format("%s=<none>", pool_type)
        else
            parts[#parts + 1] = string.format("%s=%d(dup=%d)", pool_type, total, dups)
            -- SHOP is not path-uniqueness-constrained, so only flag TRAVEL/SIGNATURE.
            -- UNDERFLOW threshold is 6 = POOL_SAFETY_THRESHOLD (the max labeled node
            -- index the baked journeys use for TRAVEL; deus_populate_graph.lua:460).
            -- A pool with < 6 distinct keys can leave a high-labeled node unassigned
            -- (nil level -> :462 index-nil throw), which is the #487 freeze.
            if pool_type ~= "SHOP" then
                if total == 0 then
                    empty[#empty + 1] = pool_type
                elseif total < 6 then
                    underflow[#underflow + 1] = pool_type
                end
            end
        end
    end

    local s = table.concat(parts, " ")
    if #empty > 0 then
        s = s .. " | EMPTY=" .. table.concat(empty, ",")
    end
    if #underflow > 0 then
        s = s .. " | UNDERFLOW=" .. table.concat(underflow, ",")
    end
    return s
end

-- Count the solved graph's playable nodes by type so the finish line shows how
-- many same-type nodes the pool actually had to cover.
local function _count_graph(path_graph)
    if type(path_graph) ~= "table" then return nil end
    local total, travel, sig = 0, 0, 0
    for _, node in pairs(path_graph) do
        total = total + 1
        if type(node) == "table" then
            local lt = node.level_type
            if lt == "TRAVEL" then travel = travel + 1
            elseif lt == "SIGNATURE" then sig = sig + 1 end
        end
    end
    return total, travel, sig
end

-- Breadcrumb printed SYNCHRONOUSLY right before the solve. If the solve hangs,
-- this is the last line in the console log and it carries the pool state that
-- explains why.
function M.begin_generate(journey_name, is_server)
    _active = { label = "graph-solve journey=" .. tostring(journey_name), t0 = _clock() }
    _active_warned = false
    _safe_printf("[ct:487] GRAPH-SOLVE begin journey=%s is_server=%s | %s",
        tostring(journey_name), tostring(is_server), M.pool_snapshot(journey_name))
end

-- Printed right after the solve returns. Reports elapsed time and whether the
-- graph came back nil (unsolvable pool) - the two signatures that confirm the
-- underflow hypothesis.
function M.finish_generate(journey_name, path_graph)
    local elapsed_ms = (_clock() - ((_active and _active.t0) or _clock())) * 1000
    local total, travel, sig = _count_graph(path_graph)
    if total == nil then
        _safe_printf("[ct:487] GRAPH-SOLVE end journey=%s elapsed=%.0fms graph=NIL (solver failed - pool too small to satisfy path uniqueness) | %s",
            tostring(journey_name), elapsed_ms, M.pool_snapshot(journey_name))
    else
        _safe_printf("[ct:487] GRAPH-SOLVE end journey=%s elapsed=%.0fms graph=%d nodes (travel=%d sig=%d)",
            tostring(journey_name), elapsed_ms, total, travel, sig)
        if elapsed_ms >= SLOW_GENERATE_MS then
            _safe_printf("[ct:487] WARN slow solve (%.0fms >= %dms) - near-budget backtrack, pool may be marginal | %s",
                elapsed_ms, SLOW_GENERATE_MS, M.pool_snapshot(journey_name))
        end
    end
    _active = nil
    _active_warned = false
end

-- Per-frame stall watchdog. Driven from the single ct mod.update owner. Two jobs:
--   1. If a solve breadcrumb is still open across frames (defensive - the solve is
--      normally synchronous), warn ONCE that we are still inside it.
--   2. Report any single frame whose dt exceeds FRAME_STALL_S as a game-loop stall,
--      naming the last-open region so a recoverable hang is attributed.
-- Field reads only; no allocations on the common (no-stall) path.
function M.tick(dt)
    if _active and not _active_warned then
        if (_clock() - _active.t0) > FRAME_STALL_S then
            _safe_printf("[ct:487] STALL still inside %s for >%.0fs (game loop advanced a frame mid-region)",
                _active.label, FRAME_STALL_S)
            _active_warned = true
        end
    end
    if dt and dt > FRAME_STALL_S then
        _safe_printf("[ct:487] frame-stall dt=%.1fs (last region: %s)",
            dt, (_active and _active.label) or "none")
    end
end

return M
