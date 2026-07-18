-- _gut_exit_snapshot_core.lua -- pure, engine-free divergence diff for the exit-time
-- loadout/cosmetic persistence backstop (issues #354, #353, #287, #175).
--
-- WHY THIS EXISTS. The modded native-loadout store (_gut_native_loadouts.lua) is captured
-- on EQUIP EVENTS only -- the mirror write hooks plus the outer BackendUtils.set_loadout_item
-- capture -- and persisted immediately. Any loadout/cosmetic state that reaches the live
-- backend interface through a path that does NOT fire one of those capture hooks (an
-- LA-cloned cosmetic dispatch #353, a WT cross-character weapon whose enable/apply lands
-- outside a captured equip #354) is never written to the store, so it is lost on quit. The
-- exit snapshot is the BACKSTOP: at bounded exit edges it re-reads the live selected loadout
-- and reconciles any diverged slot into the store, reusing the SAME store format and the same
-- single writer -- it is a second capture TRIGGER, never a second format or a second store.
--
-- This module is the PURE arithmetic half so the reconcile can be exercised by the offline
-- Lua harness (qa/lua/tests/test_gut_exit_snapshot.lua). It touches no VMF/game global. The
-- engine-facing half (live reads, RESOLVE_YES gating, _persist) lives in _gut_native_loadouts.lua
-- as M.exit_snapshot, which calls into here.
--
-- NON-DESTRUCTIVE INVARIANT (inherited from the #375/#387 store doctrine). A `nil` live value
-- for a slot means "no resolvable live value right now" -- it NEVER clears a stored value. The
-- merged row is the stored row with ONLY the diverged (live, resolvable, different) slots
-- overwritten; every other stored slot, plus "talents" and any other row key, is preserved
-- verbatim. So a slot the live read could not resolve (a late-registering synthetic id) can
-- never blank out a legitimately stored id, and re-running the diff on a merged row diverges 0
-- (idempotent).

local Core = {}

-- diff_row(live, stored, slot_names) -> merged_or_nil, diverged, changes
--   live       : { [slot] = value }  values already canonicalized to the store's format;
--                a nil entry means "skip this slot" (unresolved / no live value).
--   stored     : the store's selected loadout row (may be nil or empty).
--   slot_names : ordered array of the slot keys to reconcile.
-- A slot diverges iff live[slot] ~= nil AND live[slot] ~= stored[slot]. Returns:
--   merged  = nil when nothing diverged (caller writes nothing); otherwise a shallow copy of
--             `stored` with each diverged slot overwritten by its live value (all other stored
--             keys preserved).
--   diverged = number of slots that changed.
--   changes  = array of { slot = <s>, from = <old>, to = <new> } for diagnostics/tests.
function Core.diff_row(live, stored, slot_names)
    if type(live) ~= "table" or type(slot_names) ~= "table" then
        return nil, 0, {}
    end
    stored = type(stored) == "table" and stored or {}
    local diverged, changes, merged = 0, {}, nil
    for i = 1, #slot_names do
        local slot = slot_names[i]
        local lv = live[slot]
        if lv ~= nil and lv ~= stored[slot] then
            if merged == nil then
                merged = {}
                for k, v in pairs(stored) do merged[k] = v end
            end
            changes[#changes + 1] = { slot = slot, from = stored[slot], to = lv }
            merged[slot] = lv
            diverged = diverged + 1
        end
    end
    return merged, diverged, changes
end

-- reconcile_selected(live_by_career, store, slot_names) -> total_diverged, merged_rows, per_career
--   live_by_career[career] = { [slot] = value }  the live SELECTED-row values for that career.
--   store[career]          = { selected_index = i, loadouts = { [i] = row, ... }, ... }.
-- PURE: mutates neither argument. Returns the merged selected row per diverged career so the
-- engine caller can apply them to the live in-memory store and persist once. A career with no
-- store entry, no selected row, or no live values is skipped (the backstop only reconciles
-- careers the store already owns -- it never invents a career or a loadout index, keeping clear
-- of the STORE-space vs official-space index hazard, #387/#372).
function Core.reconcile_selected(live_by_career, store, slot_names)
    local total, merged_rows, per_career = 0, {}, {}
    if type(live_by_career) ~= "table" or type(store) ~= "table" then
        return 0, merged_rows, per_career
    end
    for career, live in pairs(live_by_career) do
        local entry = store[career]
        local idx = type(entry) == "table" and entry.selected_index or nil
        local stored_row = idx and type(entry.loadouts) == "table" and entry.loadouts[idx] or nil
        if stored_row ~= nil then
            local merged, diverged = Core.diff_row(live, stored_row, slot_names)
            if diverged > 0 then
                merged_rows[career] = merged
                per_career[career] = diverged
                total = total + diverged
            end
        end
    end
    return total, merged_rows, per_career
end

return Core
