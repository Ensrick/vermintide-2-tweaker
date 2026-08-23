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
      * settled ground-truth N > census C -> some chests bypassed
                                             _spawn_pickup (raw baked units)
      * ground-truth N  > cap M     -> the cap is not enforced on this level
    The per-chest census= field is PROVISIONAL: extensions_ready runs inside
    the synchronous spawn before _spawn_pickup returns and increments census.
    Issue #349 therefore adds finalize(), called by the existing delayed spawn
    census after eight seconds. Its one [ct:349] line compares settled counts.

OUTPUT
    engine `printf` only (visible with mod logging OFF). Prefixes `[ct:132]`
    per chest and one settled `[ct:349]` audit per mission.
    Always-on in this dev build; no menu toggle (diagnostics doctrine). One line
    per cursed chest (bounded by the handful of chests a mission spawns - never
    per-frame). Read-only: touches no cap / spawn logic.

PUBLIC SURFACE (mod._ct_chest132)
    .chest_appeared(level_id, cap, census, is_server) - per-chest ground-truth
        line; resets the per-mission counter when level_id changes so it works
        on a client too (where populate_pickups never runs).
    .MARKER - source-pattern regression anchor.
    .begin(level_id) - reset at the host's per-mission populate boundary, which
        also makes a healthy zero-chest mission auditable.
    .finalize(level_id, cap, census, is_server) - settled one-shot audit.

MANIFEST POSITION: dofile'd after the adventure-pool owner with the other
    CW-run diagnostics; callers are the existing populate/census lifecycle and
    the DeusCursedChestExtension.extensions_ready hook in the entry file.
]]

local mod = get_mod("ct_dev")
local Core = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_chest_count_audit_core")

local M = {}

M.MARKER = "CT_CHEST132_349_SETTLED_AUDIT_v0.7.271"
-- issue 132 / issue 60 (v0.7.298-dev): the module now also OWNS the settled
-- post-populate reconciliation pass (prune side). Census stays read-only; the
-- reconcile fires from finalize() under four gates (host + deus run + explicit
-- cap + over-cap) and deletes only pickup-path units via the engine's own
-- pickup delete path [src: pickup_system.lua:1451-1455 -> unit_spawner
-- mark_for_deletion; same call vanilla uses at :1345]. Raw baked level units
-- and non-WAITING chests are never touched - they are reported as unprunable.
M.RECONCILE_MARKER = "CT_CHEST132_RECONCILE_PRUNE_v0.7.298"

-- Per-mission ground-truth counter. Reset on level change (not via a hook) so
-- the count is correct on both host and client without depending on the host-
-- only populate_pickups reset.
local _tracker = {}
-- issue 132: per-mission unit ledgers backing the reconcile plan. `_units` is
-- appearance order (every spawn path, from extensions_ready); `_pickup_units`
-- is the subset that routed through PickupSystem._spawn_pickup (the engine-
-- deletable class). Both reset with the tracker.
local _units = {}
local _pickup_units = {}

local function _safe_printf(fmt, ...)
    if rawget(_G, "printf") then pcall(printf, fmt, ...) end
end

function M.begin(level_id)
    Core.begin(_tracker, level_id)
    _units = {}
    _pickup_units = {}
end

-- Called once per cursed chest from the extensions_ready hook. cap/census are
-- resolved by the caller (entry-file scope) and passed in so this module stays
-- free of file-local dependencies. `unit` (v0.7.298-dev) feeds the reconcile
-- ledger; older call shapes without it stay valid (census-only).
function M.chest_appeared(level_id, cap, census, is_server, unit)
    if _tracker.level_id ~= level_id then
        _units = {}
        _pickup_units = {}
    end
    local actual = Core.appeared(_tracker, level_id)
    if unit ~= nil then _units[#_units + 1] = unit end
    local over = (type(cap) == "number" and actual > cap) and " OVER_CAP" or ""
    _safe_printf("[ct:132] chest_of_trials #%d level=%s cap=%s census=%s is_server=%s%s",
        actual, tostring(level_id), tostring(cap), tostring(census), tostring(is_server), over)
end

-- Called from the entry file's _spawn_pickup census for every CONFIRMED
-- deus_cursed_chest spawn. Marks the unit engine-deletable for the reconcile.
function M.pickup_chest(unit)
    if unit ~= nil then _pickup_units[unit] = true end
end

-- Prune predicate: a chest may only be deleted while its replicated state is
-- still WAITING (= 1) [src: deus_cursed_chest_extension.lua:13 STATES,
-- :367-373 _set_state writes game-object field "deus_cursed_chest_state"].
-- Any read failure = NOT prunable (fail-safe: never delete a chest a player
-- may already be running).
local function _chest_is_waiting(unit)
    local ok, waiting = pcall(function()
        local game = Managers.state.network:game()
        local go_id = Managers.state.unit_storage:go_id(unit)
        if not game or not go_id then return false end
        return GameSession.game_object_field(game, go_id, "deus_cursed_chest_state") == 1
    end)
    return ok and waiting == true
end

-- The settled reconciliation pass (issue 132 / issue 60 prune side). Runs at
-- most once per mission from finalize(). Gates: host only (deletion authority),
-- deus run only (never vanilla Adventure), explicit host cap only
-- (cursed_chest_count ~= -1; under Default the vanilla per-level counts stand),
-- and only when the settled live count exceeds the cap. The under-spawn
-- direction is NOT handled here - issue 251's root (missing difficulty keys in
-- injected pickup_settings) is fixed at the source in _adventure_pool.lua, and
-- spawning extra chests post-hoc would duplicate the conversion path's
-- placement logic unsafely.
local function _reconcile(level_id, cap, is_server)
    if not is_server then return end
    local raw = mod._ct_effective_setting and mod._ct_effective_setting("cursed_chest_count")
    if raw == nil or raw == -1 then return end
    local in_deus = pcall(function()
        local mech = Managers.mechanism and Managers.mechanism:game_mechanism()
        local drc = mech and mech.get_deus_run_controller and mech:get_deus_run_controller()
        assert(drc ~= nil)
    end)
    if not in_deus then return end
    local alive_fn = function(u)
        local ok, alive = pcall(Unit.alive, u)
        return ok and alive == true
    end
    local plan = Core.reconcile_plan(_units, _pickup_units, cap, alive_fn, _chest_is_waiting)
    if plan.over_n <= 0 then return end
    local pruned = 0
    for i = 1, #plan.prune do
        local u = plan.prune[i]
        local ok = pcall(function()
            Managers.state.unit_spawner:mark_for_deletion(u)
        end)
        if ok then pruned = pruned + 1 end
    end
    _safe_printf("[ct:132] reconcile level=%s alive=%d cap=%d over=%d pruned=%d unprunable=%d (issue 132 / issue 60 cross-path cap)",
        tostring(level_id), plan.alive_n, cap, plan.over_n, pruned, plan.unprunable_n)
end

-- Called once the existing pickup census has settled. This is deliberately not
-- emitted from extensions_ready: vanilla network-unit construction is synchronous,
-- so that seam observes the pickup census one return too early.
function M.finalize(level_id, cap, census, is_server)
    local classification, actual = Core.finalize(_tracker, level_id, cap, census)
    if not classification then return nil end
    local mission_of_mercy = string.find(tostring(level_id), "dlc_dwarf_interior", 1, true) ~= nil
    _safe_printf("[ct:349] chest_count_audit level=%s mission_of_mercy=%s actual=%d cap=%s pickup_census=%s class=%s is_server=%s",
        tostring(level_id), tostring(mission_of_mercy), actual, tostring(cap),
        tostring(census), tostring(classification), tostring(is_server))
    -- issue 132 / issue 60: run the prune-side reconcile AFTER the audit line so
    -- the [ct:349] classification always reports the pre-reconcile reality.
    pcall(_reconcile, level_id, cap, is_server)
    return classification
end

return M
