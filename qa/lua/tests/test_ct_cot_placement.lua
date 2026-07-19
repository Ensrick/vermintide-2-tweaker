-- Issue #471: Chest of Trials enemy under-placement. The engine finder gives
-- each requested slot one separation-filter attempt (conflict_utils.lua:1678-1693)
-- and the fixed cursed-chest annulus saturates, so waves BUILD the full request
-- (event.spawn_table) but PLACE fewer positions (event.spawn_positions) and the
-- runtime spawner drops the tail (terror_event_mixer.lua:1043). Logged evidence
-- 2026-07-18: built_req=54 placed=23 (mult=3 cataclysm), built_req=8 placed=7
-- (mult=1). These suites pin the pure top-up policy (pass planning + shortfall
-- draining) and the runtime wiring contract in _ct_combat_hooks.lua.
return function(H, repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local Policy = assert(loadfile(root .. "_ct_cot_placement_policy.lua"))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        return content
    end

    H.test("CT #471 needs_topup pins the logged drop cases and rejects junk", function()
        H.equal(Policy.needs_topup(54, 23), true)  -- mult=3 cataclysm evidence
        H.equal(Policy.needs_topup(8, 7), true)    -- mult=1 evidence: vanilla-sized loss
        H.equal(Policy.needs_topup(24, 10), true)  -- 24->10/12 evidence
        H.equal(Policy.needs_topup(8, 8), false)
        H.equal(Policy.needs_topup(0, 0), false)
        H.equal(Policy.needs_topup(nil, 3), false)
        H.equal(Policy.needs_topup(3, nil), false)
        H.equal(Policy.needs_topup("54", 23), false)
        H.equal(Policy.needs_topup(0 / 0, 1), false)
        H.equal(Policy.needs_topup(5, 0 / 0), false)
    end)

    H.test("CT #471 pass plan keeps min_distance and widens only max_distance", function()
        -- Tight cursed-chest wave geometry: radius 8, spread 5
        -- (deus_generic_terror_events.lua:95-100) -> annulus 5.5..10.5.
        local passes = Policy.plan_passes(5.5, 10.5)
        H.equal(#passes, Policy.MAX_PASSES)
        H.equal(passes[1].min_distance, 5.5)
        H.equal(passes[1].max_distance, 10.5)  -- pass 1 = the element's own annulus
        for i = 1, #passes do
            H.equal(passes[i].min_distance, 5.5)          -- never closer to the chest
            H.equal(passes[i].max_distance, 10.5 + (i - 1) * Policy.WIDEN_STEP)
            H.equal(passes[i].tries, Policy.BASE_TRIES)   -- engine default retained
            H.equal(passes[i].circle_subdivision, Policy.SUBDIVISION)
        end
        -- Defensive inputs: nil/swapped never produce max < min.
        local degenerate = Policy.plan_passes(nil, nil)
        H.equal(degenerate[1].min_distance, 0)
        H.truthy(degenerate[1].max_distance >= degenerate[1].min_distance)
        local swapped = Policy.plan_passes(10, 4)
        H.equal(swapped[1].max_distance, 10)
    end)

    H.test("CT #471 drain fills the mult=3 evidence case and stops when met", function()
        local calls = {}
        local yields = { 12, 10, 9, 99, 99 }  -- later passes must never run
        local function finder(pass, want)
            calls[#calls + 1] = want
            return yields[#calls]
        end
        local final, topup, passes_used, residual =
            Policy.drain(54, 23, Policy.plan_passes(5.5, 10.5), finder)
        H.equal(final, 54)
        H.equal(topup, 31)
        H.equal(passes_used, 3)
        H.equal(residual, 0)
        H.deep_equal(calls, { 31, 19, 9 })  -- want shrinks by prior recoveries
    end)

    H.test("CT #471 drain recovers the vanilla-sized single-slot loss in one pass", function()
        local calls = 0
        local final, topup, passes_used, residual =
            Policy.drain(8, 7, Policy.plan_passes(5.5, 10.5), function()
                calls = calls + 1
                return 1
            end)
        H.equal(final, 8)
        H.equal(topup, 1)
        H.equal(passes_used, 1)
        H.equal(residual, 0)
        H.equal(calls, 1)
    end)

    H.test("CT #471 drain names the residual when every pass exhausts", function()
        local final, topup, passes_used, residual =
            Policy.drain(54, 23, Policy.plan_passes(5.5, 10.5), function()
                return 0
            end)
        H.equal(final, 23)
        H.equal(topup, 0)
        H.equal(passes_used, Policy.MAX_PASSES)
        H.equal(residual, 31)
    end)

    H.test("CT #471 drain clamps over-yield and tolerates junk finder returns", function()
        local final, topup, _, residual =
            Policy.drain(10, 6, Policy.plan_passes(5.5, 10.5), function()
                return 999  -- engine finder cannot structurally over-place; clamp anyway
            end)
        H.equal(final, 10)
        H.equal(topup, 4)
        H.equal(residual, 0)
        local nil_final = Policy.drain(10, 6, Policy.plan_passes(5.5, 10.5), function()
            return nil
        end)
        H.equal(nil_final, 6)
        local neg_final = Policy.drain(10, 6, Policy.plan_passes(5.5, 10.5), function()
            return -3
        end)
        H.equal(neg_final, 6)
    end)

    H.test("CT #471 drain is a no-op when the request was fully placed", function()
        local final, topup, passes_used, residual =
            Policy.drain(8, 8, Policy.plan_passes(5.5, 10.5), function()
                error("finder must not run when nothing is missing")
            end)
        H.equal(final, 8)
        H.equal(topup, 0)
        H.equal(passes_used, 0)
        H.equal(residual, 0)
    end)

    H.test("CT #471 widening defeats annulus saturation in a capacity model", function()
        -- Deterministic stand-in for the 2 m separation ceiling: an annulus of
        -- area pi*(max^2-min^2) holds capacity ~ density*(max^2-min^2) positions.
        -- density calibrated so the base 5.5..10.5 annulus caps at the OBSERVED
        -- 23 placements (23/80 = 0.2875) - pass 1 (same annulus) recovers zero,
        -- and only the widened passes unlock the remaining request.
        local density = 23 / 80
        local occupied = 23
        local function capacity(max_d)
            return math.floor((max_d * max_d - 5.5 * 5.5) * density)
        end
        local function finder(pass, want)
            local free = capacity(pass.max_distance) - occupied
            if free < 0 then free = 0 end
            local got = want < free and want or free
            occupied = occupied + got
            return got
        end
        local final, topup, passes_used, residual =
            Policy.drain(54, 23, Policy.plan_passes(5.5, 10.5), finder)
        H.equal(final, 54)
        H.equal(topup, 31)
        H.equal(residual, 0)
        H.truthy(passes_used > 1)                  -- the base annulus alone cannot fill it
        H.truthy(passes_used <= Policy.MAX_PASSES) -- bounded work
    end)

    H.test("CT #471 policy module stays engine-free", function()
        local policy_src = read(root .. "_ct_cot_placement_policy.lua")
        H.equal(policy_src:find("Managers", 1, true), nil)
        H.equal(policy_src:find("Vector3", 1, true), nil)
        H.equal(policy_src:find("Unit%."), nil)
        H.equal(policy_src:find("mod:", 1, true), nil)
        H.equal(policy_src:find("printf", 1, true), nil)
    end)

    H.test("CT #471 runtime wiring keeps one hook and drives the policy", function()
        local hooks_src = read(root .. "_ct_combat_hooks.lua")
        -- Singleton hook invariant on the shared (Class, method).
        local _, hook_count = hooks_src:gsub(
            'mod:hook%(TerrorEventMixer%.init_functions, "spawn_around_origin_unit"', "")
        H.equal(hook_count, 1)
        -- Policy is dofile'd (package wildcard covers it) and both entry points run.
        H.truthy(hooks_src:find("_ct_cot_placement_policy", 1, true))
        H.truthy(hooks_src:find("COT_PLACEMENT.needs_topup", 1, true))
        H.truthy(hooks_src:find("COT_PLACEMENT.plan_passes", 1, true))
        H.truthy(hooks_src:find("COT_PLACEMENT.drain", 1, true))
        -- The top-up re-drives the ENGINE finder and mirrors the mixer post-pass
        -- (boxing + telegraph decal) for every appended position.
        H.truthy(hooks_src:find("CU.find_positions_around_position", 1, true))
        H.truthy(hooks_src:find("Vector3Box(accepted[i])", 1, true))
        H.truthy(hooks_src:find("pcall(element.pre_spawn_unit_func, event, element, boxed, spawn_table[idx])", 1, true))
        -- Marker + regression check pair.
        H.truthy(hooks_src:find(
            'CT_COT_471_TOPUP_MARKER = "cot471:placement_topup_drain_v0.7.304"', 1, true))
        local regression_src = read(root .. "_ct_regression.lua")
        H.truthy(regression_src:find('_rt_register("cot471_placement_topup"', 1, true))
        H.truthy(regression_src:find("cot471:placement_topup_drain_v0.7.304", 1, true))
        -- The [ct:471] line proves delivery: final placed vs built_req plus the
        -- residual naming any engine-limit shortfall.
        H.truthy(hooks_src:find(
            "built_req=%s placed=%s vanilla_placed=%s topup=%s passes=%s residual=%s", 1, true))
    end)
end
