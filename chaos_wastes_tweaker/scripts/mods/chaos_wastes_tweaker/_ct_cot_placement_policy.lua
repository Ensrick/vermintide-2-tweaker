-- Engine-free placement top-up policy for Issue #471: Chest of Trials waves
-- BUILD the full request (event.spawn_table) but PLACE fewer nav positions
-- (event.spawn_positions), and the runtime spawner only spawns one enemy per
-- PLACED position (terror_event_mixer.lua:1043) - the spawn_table tail is
-- silently dropped. Logged evidence: built_req=54 placed=23 (mult=3,
-- cataclysm) and built_req=8 placed=7 (mult=1).
--
-- Root cause (decompile): ConflictUtils.find_positions_around_position gives
-- each requested slot up to `tries` attempts, BUT the inner `break` sits inside
-- `if spawn_pos then` (conflict_utils.lua:1678-1693), so any ON-NAV candidate
-- that fails filter_func - closer than distance_to_enemies (default 2, mixer
-- terror_event_mixer.lua:136) to an already-accepted position
-- (conflict_utils.lua:1616-1622) - still breaks: ONE separation attempt per
-- slot. Compounding it, cursed-chest waves sample a fixed annulus of radius
-- 8 +/- spread/2 (deus_generic_terror_events.lua:95-100), whose discrete
-- 4-angle spiral saturates around ~23 accepted positions at 2 m spacing -
-- exactly the observed mult=3 ceiling.
--
-- Fix shape (pure here, engine adapter in _ct_combat_hooks.lua): re-drive the
-- SAME engine finder over a bounded pass plan. Each call re-randomizes its
-- sampling phase (conflict_utils.lua:1644-1647), so pass 1 on the original
-- annulus already recovers single-attempt drops; later passes widen
-- max_distance so the annulus area outgrows the separation saturation.
-- min_distance never shrinks - spawns never get closer than the trial intends.

local M = {
    MAX_PASSES = 5,
    WIDEN_STEP = 2.0,  -- metres added to max_distance per pass after the first
    BASE_TRIES = 30,   -- engine default (conflict_utils.lua:1650)
    SUBDIVISION = 8,   -- denser angular sampling than the engine default 4
                       -- (conflict_utils.lua:1639); sampling density only,
                       -- no gameplay semantics
}

-- True when a numeric request was under-placed. Non-numbers / NaN -> false.
function M.needs_topup(built_req, placed)
    if type(built_req) ~= "number" or type(placed) ~= "number" then return false end
    if built_req ~= built_req or placed ~= placed then return false end
    return built_req > 0 and placed < built_req
end

-- Pass schedule for one under-placed element. Returns MAX_PASSES descriptors:
-- pass 1 = the element's own annulus, pass i widens max_distance by
-- (i-1)*WIDEN_STEP. All passes keep the element's min_distance.
function M.plan_passes(min_distance, max_distance)
    min_distance = tonumber(min_distance) or 0
    max_distance = tonumber(max_distance) or min_distance
    if max_distance < min_distance then max_distance = min_distance end
    local passes = {}
    for i = 1, M.MAX_PASSES do
        passes[i] = {
            min_distance = min_distance,
            max_distance = max_distance + (i - 1) * M.WIDEN_STEP,
            tries = M.BASE_TRIES,
            circle_subdivision = M.SUBDIVISION,
        }
    end
    return passes
end

-- Drain the shortfall across the pass plan. `finder(pass, want)` must return
-- how many NEW positions it placed for that pass (the engine adapter appends
-- into one shared accepted list and reports the delta). Stops as soon as the
-- request is met. Returns: final_placed, topup, passes_used, residual.
function M.drain(built_req, placed, passes, finder)
    if not M.needs_topup(built_req, placed) then
        local p = type(placed) == "number" and placed or 0
        local b = type(built_req) == "number" and built_req or p
        return p, 0, 0, (b > p) and (b - p) or 0
    end
    local topup = 0
    local passes_used = 0
    for i = 1, #passes do
        local missing = built_req - placed - topup
        if missing <= 0 then break end
        passes_used = i
        local got = tonumber(finder(passes[i], missing)) or 0
        if got < 0 then got = 0 end
        if got > missing then got = missing end
        topup = topup + got
    end
    local final = placed + topup
    return final, topup, passes_used, built_req - final
end

return M
