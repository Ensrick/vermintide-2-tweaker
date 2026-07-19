return function(H, repo_root)
    local path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
        .. "_ct_chest_count_audit_core.lua"
    local Core = assert(loadfile(path))()

    H.test("CT settled chest audit distinguishes both over-cap paths", function()
        H.equal(Core.classify(5, 3, 3), "over_cap_raw_level_units")
        H.equal(Core.classify(5, 3, 5), "over_cap_pickup_path")
        H.equal(Core.classify(5, 3, 6), "over_cap_count_order_mismatch")
    end)

    H.test("CT settled chest audit reports healthy and malformed counts", function()
        H.equal(Core.classify(3, 3, 3), "within_cap_pickup_path")
        H.equal(Core.classify(0, 0, 0), "within_cap_pickup_path")
        H.equal(Core.classify(3, 3, 2), "within_cap_raw_level_units")
        H.equal(Core.classify(2, 3, 3), "within_cap_count_order_mismatch")
        H.equal(Core.classify(nil, 3, 3), "invalid")
    end)

    H.test("CT issue 349 audit is wired after delayed census", function()
        local main_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
            .. "chaos_wastes_tweaker_dev.lua"
        local file = assert(io.open(main_path, "rb"))
        local source = file:read("*a")
        file:close()
        local tally = assert(string.find(source, "[ct-spawn-tally]", 1, true))
        local finalize = assert(string.find(source, "mod._ct_chest132.finalize(_level", 1, true))
        H.truthy(finalize > tally)
    end)

    H.test("CT chest audit finalizes once and includes zero-chest missions", function()
        local state = {}
        Core.begin(state, "dlc_dwarf_interior_khorne_path1")
        local class, actual = Core.finalize(state,
            "dlc_dwarf_interior_khorne_path1", 0, 0)
        H.equal(class, "within_cap_pickup_path")
        H.equal(actual, 0)
        H.equal(Core.finalize(state, "dlc_dwarf_interior_khorne_path1", 0, 0), nil)

        Core.begin(state, "dlc_dwarf_interior_khorne_path1")
        H.equal(Core.appeared(state, "dlc_dwarf_interior_khorne_path1"), 1)
        H.equal(Core.appeared(state, "dlc_dwarf_interior_khorne_path1"), 2)
        H.equal(Core.finalize(state, "other_level", 2, 2), nil)
    end)

    -- ------------------------------------------------------------------
    -- Cluster D (issues 60 / 132 / 349 / 251): settled cross-path reconcile.
    -- ------------------------------------------------------------------
    local alive_all = function() return true end
    local waiting_all = function() return true end

    H.test("CT chest reconcile prunes from the end, only pickup-path, only over cap", function()
        local u = { "c1", "c2", "c3", "c4", "c5" }
        local pickup = { [u[3]] = true, [u[4]] = true, [u[5]] = true }
        local plan = Core.reconcile_plan(u, pickup, 3, alive_all, waiting_all)
        H.equal(plan.alive_n, 5)
        H.equal(plan.over_n, 2)
        H.equal(#plan.prune, 2)
        H.equal(plan.prune[1], u[5])
        H.equal(plan.prune[2], u[4])
        H.equal(plan.unprunable_n, 0)
    end)

    H.test("CT chest reconcile never deletes baked or activated chests", function()
        local u = { "b1", "b2", "b3" }
        -- Nothing came through the pickup path: over-cap is reported, not pruned.
        local baked = Core.reconcile_plan(u, {}, 1, alive_all, waiting_all)
        H.equal(#baked.prune, 0)
        H.equal(baked.over_n, 2)
        H.equal(baked.unprunable_n, 2)
        -- Activated (non-WAITING) chests are skipped even when pickup-path.
        local pickup = { [u[2]] = true, [u[3]] = true }
        local active = Core.reconcile_plan(u, pickup, 1,
            alive_all, function(x) return x ~= u[3] end)
        H.equal(#active.prune, 1)
        H.equal(active.prune[1], u[2])
        H.equal(active.unprunable_n, 1)
    end)

    H.test("CT chest reconcile handles dead units, under-cap, and bad input", function()
        local u = { "d1", "d2", "d3" }
        local pickup = { [u[1]] = true, [u[2]] = true, [u[3]] = true }
        -- Dead units drop out of the live census before the cap comparison.
        local half_dead = Core.reconcile_plan(u, pickup, 2,
            function(x) return x ~= u[2] end, waiting_all)
        H.equal(half_dead.alive_n, 2)
        H.equal(half_dead.over_n, 0)
        H.equal(#half_dead.prune, 0)
        -- Under cap: full no-op.
        local under = Core.reconcile_plan({ u[1] }, pickup, 3, alive_all, waiting_all)
        H.equal(under.over_n, 0)
        H.equal(#under.prune, 0)
        -- cap = 0 with an explicit setting prunes everything prunable.
        local zero = Core.reconcile_plan(u, pickup, 0, alive_all, waiting_all)
        H.equal(#zero.prune, 3)
        -- Invalid input shapes return an inert plan.
        H.equal(#Core.reconcile_plan(nil, pickup, 3).prune, 0)
        H.equal(#Core.reconcile_plan(u, nil, 3).prune, 0)
        H.equal(#Core.reconcile_plan(u, pickup, -1).prune, 0)
    end)

    H.test("CT chest reconcile is wired host-side behind the settled audit", function()
        local diag_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
            .. "_ct_diag_cursed_chest132.lua"
        local f = assert(io.open(diag_path, "rb"))
        local diag = f:read("*a")
        f:close()
        H.truthy(string.find(diag,
            'M.RECONCILE_MARKER = "CT_CHEST132_RECONCILE_PRUNE_v0.7.298"', 1, true))
        H.truthy(string.find(diag, "Managers.state.unit_spawner:mark_for_deletion(u)", 1, true),
            "prune must use the engine's own pickup delete path (pickup_system.lua:1451-1455)")
        H.truthy(string.find(diag, "pcall(_reconcile, level_id, cap, is_server)", 1, true),
            "reconcile must fire from the settled finalize, after the [ct:349] audit line")
        local audit = assert(string.find(diag, "[ct:349] chest_count_audit", 1, true))
        local reconcile_call = assert(string.find(diag, "pcall(_reconcile, level_id, cap, is_server)", 1, true))
        H.truthy(reconcile_call > audit)
        -- Explicit-cap gate: Default (-1) must leave vanilla counts alone.
        H.truthy(string.find(diag, 'if raw == nil or raw == -1 then return end', 1, true))

        local main_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
            .. "chaos_wastes_tweaker_dev.lua"
        local mf = assert(io.open(main_path, "rb"))
        local main_src = mf:read("*a")
        mf:close()
        H.truthy(string.find(main_src, "mod._ct_chest132.pickup_chest", 1, true),
            "pickup-path ledger feed missing from the _spawn_pickup census")
    end)

    H.test("CT injected pickup_settings cover every reachable difficulty key", function()
        -- issue 251: the injected table shipped only default+normal, so a
        -- Cataclysm run logged "NO MATCH for current difficulty='cataclysm'"
        -- and rode the engine fallback (pickup_system.lua:409-419). Canonical
        -- key list: difficulty_settings.lua:402-411 (minus versus_base).
        local pool_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
            .. "_adventure_pool.lua"
        local pf = assert(io.open(pool_path, "rb"))
        local pool = pf:read("*a")
        pf:close()
        H.truthy(string.find(pool,
            '{ "normal", "hard", "harder", "hardest", "cataclysm", "cataclysm_2", "cataclysm_3" }',
            1, true), "difficulty key coverage list missing from make_cw_pickup_settings")
        H.truthy(string.find(pool, "out[dk] = { primary = primary(), secondary = secondary() }", 1, true),
            "per-key entries must be FRESH tables (populate hook mutates them in place)")
    end)
end
