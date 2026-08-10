return function(H, repo_root)
    local path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_replay_policy.lua"
    local chunk, err = loadfile(path)
    if not chunk then error(err) end
    local Policy = chunk()

    H.test("LA replay resolves the wielded slot identically for local and husk inventory", function()
        H.equal("slot_melee", Policy.wielded_slot({
            _equipment = { wielded_slot = "slot_melee" },
        }), "local SimpleInventoryExtension shape")
        H.equal("slot_ranged", Policy.wielded_slot({
            wielded_slot = "slot_ranged",
        }), "legacy/husk direct-field fallback")
        H.equal("slot_melee", Policy.wielded_slot({
            wielded_slot = "slot_ranged",
            _equipment = { wielded_slot = "slot_melee" },
        }), "common equipment field must win over a stale direct mirror")
        H.equal("slot_melee", Policy.wielded_slot({}, {
            wielded_slot = "slot_melee",
        }), "explicit equipment supplied by an existing caller")
        H.equal(nil, Policy.wielded_slot(nil))
    end)

    H.test("Cosmetics persisted LA replay waits for realized inventory", function()
        H.equal(false, Policy.inventory_ready(nil))
        H.equal(false, Policy.inventory_ready({}))
        H.equal(false, Policy.inventory_ready({ _equipment = { slots = {} } }))
        H.equal(false, Policy.inventory_ready({
            _equipment = { slots = { slot_hat = { item_data = {} } } },
        }))
    end)

    H.test("Cosmetics persisted LA replay waits for both staggered weapon slots", function()
        H.equal(false, Policy.inventory_ready({
            _equipment = { slots = {
                slot_melee = { item_data = { backend_id = "m" } },
                slot_ranged = {},
            } },
        }))
        H.equal(true, Policy.inventory_ready({
            equipment = { slots = {
                slot_melee = { item_data = { backend_id = "m" } },
                slot_ranged = { item_data = { backend_id = "r" } },
            } },
        }))
    end)

    H.test("Peer-ready local publication excludes self aliases", function()
        H.equal(false, Policy.should_publish_local_on_peer_ready(nil, "B"))
        H.equal(false, Policy.should_publish_local_on_peer_ready("A", nil))
        H.equal(false, Policy.should_publish_local_on_peer_ready("A", "A"))
        H.equal(true, Policy.should_publish_local_on_peer_ready("A", "B"))
    end)

    H.test("Complete local appearance snapshot waits for every durable owner", function()
        local inventory = {
            _equipment = {
                slots = {
                    slot_melee = { item_data = { backend_id = "weapon-A" } },
                    slot_ranged = { item_data = { backend_id = "weapon-B" } },
                },
            },
        }
        local ready, reason = Policy.local_snapshot_ready(
            inventory, false, true, true, "es_questingknight")
        H.equal(false, ready)
        H.equal("bridge", reason)
        ready, reason = Policy.local_snapshot_ready(
            inventory, true, false, true, "es_questingknight")
        H.equal(false, ready)
        H.equal("loadout", reason)
        ready, reason = Policy.local_snapshot_ready(
            inventory, true, true, false, "es_questingknight")
        H.equal(false, ready)
        H.equal("offhand", reason)
        ready, reason = Policy.local_snapshot_ready(
            inventory, true, true, true, nil)
        H.equal(false, ready)
        H.equal("career", reason)
        ready, reason = Policy.local_snapshot_ready(
            {}, true, true, true, "es_questingknight")
        H.equal(false, ready)
        H.equal("inventory", reason)
        ready, reason = Policy.local_snapshot_ready(
            inventory, true, true, true, "es_questingknight")
        H.equal(true, ready)
        H.equal("ready", reason)
    end)

    H.test("Durable career loadout rebuilds exact hat and outfit records", function()
        local records = Policy.cached_cosmetic_records({
            es_questingknight = {
                slot_hat = "cos_gk_purpure_azure_hat",
                slot_skin = "cos_gk_purpure_azure_skin",
                slot_pose = "ignored",
            },
            es_knight = {
                slot_skin = "wrong-career",
            },
        }, "es_questingknight", {
            cos_gk_purpure_azure_hat = "cos_gk_purpure_azure_hat_variant",
            cos_gk_purpure_azure_skin = "cos_gk_purpure_azure_skin_variant",
        })
        H.equal(2, #records)
        H.equal("slot_hat", records[1].slot)
        H.equal("hat", records[1].kind)
        H.equal("cos_gk_purpure_azure_hat", records[1].item_name)
        H.equal("slot_skin", records[2].slot)
        H.equal("armor", records[2].kind)
        H.equal("cos_gk_purpure_azure_skin_variant", records[2].armoury_key)

        H.equal(0, #Policy.cached_cosmetic_records(
            {}, "es_questingknight", {}))
        H.equal(0, #Policy.cached_cosmetic_records({
            es_questingknight = { slot_skin = "unknown-custom-item" },
        }, "es_questingknight", {}))

        local by_unit = {}
        H.equal(2, Policy.rehydrate_cosmetic_equips(
            by_unit, "unit-A", {
                es_questingknight = {
                    slot_hat = "cos_gk_purpure_azure_hat",
                    slot_skin = "cos_gk_purpure_azure_skin",
                },
            }, "es_questingknight", {
                cos_gk_purpure_azure_hat = "hat-variant",
                cos_gk_purpure_azure_skin = "skin-variant",
            }))
        H.equal("cos_gk_purpure_azure_hat", by_unit["unit-A"].slot_hat)
        H.equal("cos_gk_purpure_azure_skin", by_unit["unit-A"].slot_skin)
    end)

    H.test("Managed hat and outfit replacement clears stale career state atomically", function()
        local by_unit = {
            ["unit-A"] = {
                slot_hat = "stale-wrong-career-hat",
                slot_skin = "stale-wrong-career-outfit",
                slot_melee = "durable-weapon-illusion",
            },
        }
        H.equal(0, Policy.replace_cosmetic_equips(
            by_unit, "unit-A", {
                es_questingknight = {},
                es_knight = {
                    slot_hat = "stale-wrong-career-hat",
                    slot_skin = "stale-wrong-career-outfit",
                },
            }, "es_questingknight", {
                ["stale-wrong-career-hat"] = "hat-variant",
                ["stale-wrong-career-outfit"] = "skin-variant",
            }))
        H.equal(nil, by_unit["unit-A"].slot_hat)
        H.equal(nil, by_unit["unit-A"].slot_skin)
        H.equal("durable-weapon-illusion", by_unit["unit-A"].slot_melee)
    end)

    local function complete_set_fixture()
        return {
            unit = "unit-A",
            inventory = {
                _equipment = {
                    slots = {
                        slot_melee = {
                            item_data = {
                                backend_id = "melee-A",
                                template = "sword-template",
                            },
                        },
                        slot_ranged = {
                            item_data = {
                                backend_id = "ranged-A",
                                template = "shield-template",
                            },
                        },
                    },
                },
            },
            career_name = "es_questingknight",
            bridge_ready = true,
            loadout_ready = true,
            offhand_restore_ready = true,
            loadout_cache = {
                es_questingknight = {
                    slot_hat = "hat-A",
                    slot_skin = "outfit-A",
                },
            },
            backend_to_armoury = {
                ["hat-A"] = "hat-variant",
                ["outfit-A"] = "outfit-variant",
            },
            saved_offhands = {
                ["ranged-A"] = {
                    left_hand_unit = {
                        armoury_key = "shield-variant",
                    },
                },
            },
            offhand_selection = {
                ["ranged-A"] = {
                    left_hand_unit = {
                        la_armoury_key = "shield-variant",
                        vanilla_skin = "shield-vanilla",
                    },
                },
            },
        }
    end

    H.test("Staggered hat outfit and shield compose only after full convergence", function()
        local args = complete_set_fixture()
        args.inventory._equipment.slots.slot_ranged.item_data = nil
        local snapshot, reason = Policy.compose_local_snapshot(args)
        H.equal(nil, snapshot)
        H.equal("inventory", reason)

        args = complete_set_fixture()
        args.offhand_selection["ranged-A"] = nil
        snapshot, reason = Policy.compose_local_snapshot(args)
        H.equal(nil, snapshot)
        H.equal("offhand-convergence", reason)

        args = complete_set_fixture()
        snapshot, reason = Policy.compose_local_snapshot(args)
        H.equal("ready", reason)
        H.equal(2, #snapshot.cosmetics)
        H.equal("hat", snapshot.cosmetics[1].kind)
        H.equal("armor", snapshot.cosmetics[2].kind)
        H.equal(1, #snapshot.offhands)
        H.equal("shield-variant", snapshot.offhands[1].armoury_key)

        local sent = {}
        local result = Policy.publish_local_snapshot(snapshot, {
            vanilla_fallback = function(item) return item .. "-vanilla" end,
            send_la = function(_, slot, kind, key)
                sent[#sent + 1] = slot .. "|" .. kind .. "|" .. key
                return true
            end,
            send_mesh = function() return true end,
            send_custom = function() return true end,
        })
        H.equal(true, result.complete)
        H.equal(5, result.expected)
        H.equal(5, result.accepted)
        H.equal("slot_hat|hat|hat-variant", sent[1])
        H.equal("slot_skin|armor|outfit-variant", sent[2])
        H.equal("shield-template|offhand|shield-variant", sent[3])
    end)

    H.test("Unproven career and send failure retain pending replay for retry", function()
        local runtime = assert(loadfile(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_complete_set_rebroadcast.lua"))()
        local args = complete_set_fixture()
        local pending, career, allow_send = true, nil, false
        local now = 0
        local tick = runtime.new({
            policy = Policy,
            pending = function() return pending end,
            clear_pending = function() pending = false end,
            local_player = function()
                return { player_unit = "unit-A" }
            end,
            unit_alive = function() return true end,
            inventory_for = function() return args.inventory end,
            career_for = function() return career end,
            bridge_ready = function() return true end,
            loadout_ready = function() return true end,
            offhand_restore_ready = function() return true end,
            loadout_cache = function() return args.loadout_cache end,
            backend_to_armoury = function() return args.backend_to_armoury end,
            saved_offhands = function() return args.saved_offhands end,
            offhand_selection = function() return args.offhand_selection end,
            migrate_selection = function() end,
            equips_by_unit = function() return {} end,
            send_la = function() return allow_send end,
            send_mesh = function() return allow_send end,
            send_custom = function() return allow_send end,
            vanilla_fallback = function() return "vanilla" end,
            now = function() return now end,
            retry_delay = 0.25,
            log = function() end,
        })

        local ok, reason = tick()
        H.equal(false, ok)
        H.equal("career", reason)
        H.equal(true, pending)

        career = "es_questingknight"
        ok, reason = tick()
        H.equal(false, ok)
        H.equal("backoff", reason)
        H.equal(true, pending)
        now = 0.25
        ok, reason = tick()
        H.equal(false, ok)
        H.equal("publish", reason)
        H.equal(true, pending)

        allow_send = true
        now = 0.5
        ok, reason = tick()
        H.equal(true, ok)
        H.equal("complete", reason)
        H.equal(false, pending)
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

    H.test("Issue 149 mesh repair uses common slot resolution and retained apply", function()
        -- #1159: both pulse helpers (_ensure_offhand_mesh and the revert-side
        -- mod._la_native_pulse) moved verbatim into _cos_la_apply_runtime, along
        -- with the apply core these three needles pin. The census is retargeted
        -- to the owner and the entry is asserted CLEAN, so re-inlining either
        -- helper - which is how the two would drift apart again - still fails.
        local owner_path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_apply_runtime.lua"
        local f = assert(io.open(owner_path, "rb"))
        local source = f:read("*a")
        f:close()
        local entry_f = assert(io.open(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua", "rb"))
        local entry_source = entry_f:read("*a")
        entry_f:close()
        local _, resolver_calls = source:gsub(
            "local orig_slot = LA_REPLAY_POLICY%.wielded_slot%(inv, equipment%)", "")
        H.equal(resolver_calls, 2,
            "both authored and native pulse helpers must use the shared slot resolver")
        local _, entry_calls = entry_source:gsub(
            "local orig_slot = LA_REPLAY_POLICY%.wielded_slot%(inv, equipment%)", "")
        H.equal(entry_calls, 0,
            "the pulse helpers belong to _cos_la_apply_runtime, not the entry")
        H.truthy(source:find("if not applied and repaired then", 1, true),
            "replay can coalesce before repaired mesh paint succeeds")
        H.truthy(source:find("return painted", 1, true),
            "offhand paint still reports success after a mesh-mismatch skip")
    end)

    H.test("Issue 629 peer-ready edge republishes the complete local snapshot", function()
        local source_path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua"
        local f = assert(io.open(source_path, "rb"))
        local source = f:read("*a")
        f:close()
        local lifecycle_path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_mod_lifecycle.lua"
        f = assert(io.open(lifecycle_path, "rb"))
        local lifecycle = f:read("*a")
        f:close()
        local runtime_path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_complete_set_rebroadcast.lua"
        f = assert(io.open(runtime_path, "rb"))
        local runtime = f:read("*a")
        f:close()
        -- #1159: the add_remote_player hook that consults the policy moved
        -- verbatim into the cos_la_* transport owner with the rest of the peer
        -- lifecycle. The edge is pinned where it now lives.
        local transport_path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_sync_transport.lua"
        f = assert(io.open(transport_path, "rb"))
        local transport = f:read("*a")
        f:close()
        H.truthy(transport:find(
            "LA_REPLAY_POLICY.should_publish_local_on_peer_ready", 1, true))
        H.equal(source:find(
            "LA_REPLAY_POLICY.should_publish_local_on_peer_ready", 1, true), nil)
        H.truthy(lifecycle:find(
            "mod._la_self_rebroadcast_pending = true", 1, true))
        H.truthy(source:find(
            "mod._cos_complete_set_rebroadcast_tick()", 1, true))
        H.truthy(runtime:find(
            "deps.policy.compose_local_snapshot", 1, true))
        H.truthy(source:find(
            "send_la = _send_la_apply", 1, true))
        H.truthy(source:find(
            "mod._la_skin_safety_installed == true", 1, true))
        H.truthy(source:find(
            "mod._la_offhand_restore_done == true", 1, true))
        H.truthy(runtime:find(
            "if not result.complete then", 1, true))
        H.truthy(source:find(
            "if LA_BRIDGE.registered then _install_skin_loadout_safety() end",
            1, true), "Cosmetics-authored set must not require LA itself")
    end)
end
