--[[
_ct_diag_cursed_chest132 - Chest-of-Trials over-spawn instrumentation (issue #132).

WHY THIS EXISTS
    Issue #132: "Khazukan Kazakit-ha spawns 5 Chests of Trials despite
    cursed_chest_count" (same bug class as #60). A "Chest of Trials" is the
    deus_cursed_chest pickup - the extension class is DeusCursedChestExtension
    (deus_cursed_chest_extension.lua:39). The 2026-07-03 host log confirmed the
    per-mission cap held at 3 on every mission TESTED, but Khazukan Kazakit-ha
    was never visited, so the specific over-spawn is still unproven.

WHY A NEW SEAM (not the existing count probes)
    ct already logs the CONFIGURED cap ([ct-probe] populate cursed_chest_count)
    and the ACTUAL count via the unconditional spawn census ([ct-spawn-tally]
    chests(cursed=N)). Both count at PickupSystem._spawn_pickup - the pickup-
    system chokepoint. If Khazukan's extra chests are placed as raw baked LEVEL
    UNITS (a DeusCursedChestExtension attached at level compile, never routed
    through the pickup system / the #60 budget), the census MISSES them and the
    cap cannot touch them. This probe counts at DeusCursedChestExtension
    .extensions_ready instead - which fires once per cursed chest that actually
    EXISTS in the world, on every peer, regardless of spawn path - and CROSS-
    CHECKS the census. The disambiguation is the whole point (and answers the
    v0.7.175 revert reason "the chest probes already exist"):
      * ground-truth N  > census C  -> chests bypass _spawn_pickup entirely
                                        (raw baked level units, cap can't apply)
      * ground-truth N  > cap M     -> the cap is not enforced on this level
    The final (highest-N) line for a level is the ground-truth chest count;
    compare its census= and cap= fields to localise the leak.

OUTPUT
    engine `printf` only (visible with mod logging OFF). Prefix `[ct:132]`.
    Always-on in this dev build; no menu toggle (diagnostics doctrine). One line
    per cursed chest (bounded by the handful of chests a mission spawns - never
    per-frame). Read-only: touches no cap / spawn logic.

PUBLIC SURFACE (mod._ct_chest132)
    .chest_appeared(level_id, cap, census, is_server) - per-chest ground-truth
        line; resets the per-mission counter when level_id changes so it works
        on a client too (where populate_pickups never runs).
    .MARKER - source-pattern regression anchor.

MANIFEST POSITION: dofile'd alongside _ct_diag_freeze487 (both are CW-run
    diagnostics); its only caller is the DeusCursedChestExtension.extensions_ready
    hook in the entry file.
]]

local mod = get_mod("ct_dev")

local M = {}

M.MARKER = "CT_CHEST132_DIAG_v0.7.243"

-- Per-mission ground-truth counter. Reset on level change (not via a hook) so
-- the count is correct on both host and client without depending on the host-
-- only populate_pickups reset.
local _n = 0
local _level = nil

local function _safe_printf(fmt, ...)
    if rawget(_G, "printf") then pcall(printf, fmt, ...) end
end

-- Called once per cursed chest from the extensions_ready hook. cap/census are
-- resolved by the caller (entry-file scope) and passed in so this module stays
-- free of file-local dependencies.
function M.chest_appeared(level_id, cap, census, is_server)
    if level_id ~= _level then
        _level = level_id
        _n = 0
    end
    _n = _n + 1
    local over = (type(cap) == "number" and _n > cap) and " OVER_CAP" or ""
    _safe_printf("[ct:132] chest_of_trials #%d level=%s cap=%s census=%s is_server=%s%s",
        _n, tostring(level_id), tostring(cap), tostring(census), tostring(is_server), over)
end

return M
