return function(H, repo_root)
    local path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_replay_policy.lua"
    local chunk, err = loadfile(path)
    if not chunk then error(err) end
    local Policy = chunk()

    H.test("Cosmetics persisted LA replay waits for realized inventory", function()
        H.equal(false, Policy.inventory_ready(nil))
        H.equal(false, Policy.inventory_ready({}))
        H.equal(false, Policy.inventory_ready({ _equipment = { slots = {} } }))
        H.equal(false, Policy.inventory_ready({
            _equipment = { slots = { slot_hat = { item_data = {} } } },
        }))
    end)

    H.test("Cosmetics persisted LA replay accepts either realized weapon slot", function()
        H.equal(true, Policy.inventory_ready({
            _equipment = { slots = { slot_melee = { item_data = { backend_id = "m" } } } },
        }))
        H.equal(true, Policy.inventory_ready({
            equipment = { slots = { slot_ranged = { item_data = { backend_id = "r" } } } },
        }))
    end)

    -- ------------------------------------------------------------------
    -- Bounded-edge replay reconciler (#660 S3 cold-join slice)
    -- ------------------------------------------------------------------

    local function la_records()
        return {
            { peer = "A", slot = "slot_ranged",
              record = { kind = "offhand", armoury_key = "reiland",
                         vanilla_key = "es_shield", hand_field = "left_hand_unit" } },
        }
    end

    H.test("Replay edge coalesces a repeated generation (never per-frame)", function()
        local state = Policy.new_replay_state()
        local calls = 0
        local apply = function() calls = calls + 1; return "applied" end

        local r1 = Policy.reconcile_edge(state, "session-ready", la_records(), apply)
        H.equal(r1.applied, 1)
        H.equal(r1.per_peer["A"], 1)

        -- Same edge fires again with the same persisted record: no re-apply.
        local r2 = Policy.reconcile_edge(state, "session-ready", la_records(), apply)
        H.equal(r2.applied, 0)
        H.equal(r2.coalesced, 1)
        H.equal(calls, 1)
    end)

    H.test("Replay edge re-applies when the generation changes", function()
        local state = Policy.new_replay_state()
        local calls = 0
        local apply = function() calls = calls + 1; return "applied" end

        Policy.reconcile_edge(state, "session-ready", la_records(), apply)

        -- A live customization change alters the persisted record -> new gen.
        local changed = la_records()
        changed[1].record.armoury_key = "bastonne"
        local r = Policy.reconcile_edge(state, "session-ready", changed, apply)
        H.equal(r.applied, 1)
        H.equal(calls, 2)
    end)

    H.test("Replay defers an unready wearer and drains on the next edge", function()
        local state = Policy.new_replay_state()
        local ready = false
        local apply = function() return ready and "applied" or "defer" end

        local r1 = Policy.reconcile_edge(state, "peer-ready", la_records(), apply)
        H.equal(r1.applied, 0)
        H.equal(r1.deferred, 1)

        -- Husk becomes available; the NEXT edge retries the same record.
        ready = true
        local r2 = Policy.reconcile_edge(state, "peer-ready", la_records(), apply)
        H.equal(r2.applied, 1)
        H.equal(r2.deferred, 0)

        -- And now coalesces (drained, not re-applied per frame).
        local r3 = Policy.reconcile_edge(state, "peer-ready", la_records(), apply)
        H.equal(r3.applied, 0)
        H.equal(r3.coalesced, 1)
    end)

    H.test("Replay treats a terminal skip as non-retryable", function()
        local state = Policy.new_replay_state()
        local calls = 0
        local apply = function() calls = calls + 1; return "skip" end

        local r1 = Policy.reconcile_edge(state, "session-ready", la_records(), apply)
        H.equal(r1.skipped, 1)
        H.equal(r1.applied, 0)
        -- A skipped generation is marked, so it does not retry next edge.
        local r2 = Policy.reconcile_edge(state, "session-ready", la_records(), apply)
        H.equal(r2.coalesced, 1)
        H.equal(calls, 1)
    end)

    H.test("A husk-recreating transition invalidates and re-applies", function()
        local state = Policy.new_replay_state()
        local calls = 0
        local apply = function() calls = calls + 1; return "applied" end

        Policy.reconcile_edge(state, "session-ready", la_records(), apply)
        H.equal(calls, 1)

        -- Same generation, but the transition destroyed the husk: invalidate
        -- forces the freshly spawned husk to re-apply.
        Policy.invalidate_all(state)
        local r = Policy.reconcile_edge(state, "session-ready", la_records(), apply)
        H.equal(r.applied, 1)
        H.equal(calls, 2)

        -- Per-peer invalidation is scoped to that peer only.
        local two = {
            { peer = "A", slot = "slot_ranged",
              record = { kind = "offhand", armoury_key = "reiland",
                         hand_field = "left_hand_unit" } },
            { peer = "B", slot = "slot_ranged",
              record = { kind = "offhand", armoury_key = "kotbs",
                         hand_field = "left_hand_unit" } },
        }
        Policy.reconcile_edge(state, "peer-ready", two, apply) -- A already applied; B new
        Policy.invalidate(state, "B")
        local r2 = Policy.reconcile_edge(state, "peer-ready", two, apply)
        H.equal(r2.applied, 1)        -- only B re-applies
        H.equal(r2.coalesced, 1)      -- A stays coalesced
    end)

    H.test("Replay records come from the persisted stores, not menu state", function()
        local equips_by_peer = {
            A = { slot_ranged = { kind = "offhand", armoury_key = "reiland",
                                  vanilla_key = "es_shield", hand_field = "left_hand_unit" } },
        }
        local offhand_by_peer = {
            A = { slot_melee = { right_hand_unit = "units/weapons/player/wpn_x/wpn_x" } },
            B = { slot_ranged = { left_hand_unit = "" } }, -- empty path filtered out
        }
        -- A live "menu selection" table that must NOT be consulted.
        local menu_selection = { A = { slot_ranged = { armoury_key = "SHOULD_NOT_APPEAR" } } }

        local records = Policy.build_records(equips_by_peer, offhand_by_peer)
        local seen = {}
        for _, rec in ipairs(records) do
            seen[Policy.record_generation(rec.record)] = rec
        end

        -- LA offhand + one vanilla mesh, and nothing from the menu table.
        H.equal(#records, 2)
        H.truthy(seen["la|offhand|reiland|es_shield|left_hand_unit"], "LA record built from store")
        H.truthy(seen["mesh|right_hand_unit|units/weapons/player/wpn_x/wpn_x"], "vanilla mesh from store")
        for gen in pairs(seen) do
            H.equal(gen:find("SHOULD_NOT_APPEAR", 1, true), nil, "menu state leaked into a record")
        end

        -- only_peer scopes the record set to a single joiner.
        local scoped = Policy.build_records(equips_by_peer, offhand_by_peer, { only_peer = "A" })
        H.equal(#scoped, 2)
        for _, rec in ipairs(scoped) do
            H.equal(rec.peer, "A")
        end
    end)
end
