return function(H, repo_root)
    local core_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_exit_snapshot_core.lua"
    local Core = assert(loadfile(core_path))()
    local policy_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadout_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    local SLOTS = {
        "slot_ranged", "slot_melee", "slot_skin", "slot_hat",
        "slot_necklace", "slot_ring", "slot_trinket_1", "slot_frame", "slot_pose",
    }

    H.test("exit-snapshot diff detects a diverged slot and overwrites only it", function()
        local stored = { slot_melee = "old_melee", slot_ranged = "keep_r", talents = "1,2,3" }
        local live = { slot_melee = "new_melee" }
        local merged, diverged, changes = Core.diff_row(live, stored, SLOTS)
        H.equal(diverged, 1)
        H.equal(merged.slot_melee, "new_melee", "diverged slot must take the live value")
        H.equal(merged.slot_ranged, "keep_r", "unrelated stored slot preserved")
        H.equal(merged.talents, "1,2,3", "non-slot row keys (talents) preserved")
        H.equal(#changes, 1)
        H.equal(changes[1].slot, "slot_melee")
        H.equal(changes[1].from, "old_melee")
        H.equal(changes[1].to, "new_melee")
    end)

    H.test("exit-snapshot diff is idempotent + a no-op when clean", function()
        local stored = { slot_melee = "m", slot_ranged = "r" }
        -- live equals stored -> no divergence, no merged row (caller writes nothing).
        local merged, diverged = Core.diff_row({ slot_melee = "m", slot_ranged = "r" }, stored, SLOTS)
        H.equal(diverged, 0)
        H.equal(merged, nil, "clean state must return nil merged (no write)")
        -- re-diffing a produced merged row against the same live diverges 0.
        local first = Core.diff_row({ slot_melee = "z" }, stored, SLOTS)
        local m2, d2 = Core.diff_row({ slot_melee = "z" }, first, SLOTS)
        H.equal(d2, 0, "second pass over merged row must be idempotent")
        H.equal(m2, nil)
    end)

    H.test("exit-snapshot diff is non-destructive: a nil live value never clears a stored slot", function()
        local stored = { slot_melee = "m", slot_hat = "hat_a", slot_frame = "frame_a" }
        -- live has NO value for slot_hat/slot_frame (unresolved id -> skip): they must survive.
        local merged, diverged = Core.diff_row({ slot_melee = "m2" }, stored, SLOTS)
        H.equal(diverged, 1)
        H.equal(merged.slot_hat, "hat_a", "unresolved live slot must not blank the stored value")
        H.equal(merged.slot_frame, "frame_a")
        H.equal(merged.slot_melee, "m2")
        -- an entirely empty live row diverges 0 and touches nothing.
        local m2, d2 = Core.diff_row({}, stored, SLOTS)
        H.equal(d2, 0)
        H.equal(m2, nil)
    end)

    H.test("exit-snapshot stores the equip-path serialized identity byte-for-byte", function()
        -- The backstop must persist the SAME value the equip capture would (Policy is the shared
        -- serializer): gear = raw backend id; cosmetics = override_id or ItemId.
        local gear_val = Policy.canonical_equip_value("slot_melee", "backend_uuid_123", nil)
        H.equal(gear_val, "backend_uuid_123")
        local hat_val = Policy.canonical_equip_value("slot_hat", "transient_bid", { ItemId = "hat_masterlist" })
        H.equal(hat_val, "hat_masterlist")
        local skin_val = Policy.canonical_equip_value("slot_skin", "transient_bid",
            { override_id = "skin_override", ItemId = "skin_masterlist" })
        H.equal(skin_val, "skin_override")
        -- feeding those canonical values through the diff yields a store row holding them exactly.
        local merged = Core.diff_row(
            { slot_melee = gear_val, slot_hat = hat_val, slot_skin = skin_val }, {}, SLOTS)
        H.equal(merged.slot_melee, "backend_uuid_123")
        H.equal(merged.slot_hat, "hat_masterlist")
        H.equal(merged.slot_skin, "skin_override")
    end)

    H.test("exit-snapshot reconcile aggregates only diverged, owned, selected careers", function()
        local store = {
            es_mercenary = {
                selected_index = 2,
                loadouts = {
                    { slot_melee = "row1_m" },
                    { slot_melee = "sel_m_old", slot_ranged = "sel_r" },
                },
            },
            -- kerillian is owned but its selected row already matches live -> no divergence.
            we_shade = {
                selected_index = 1,
                loadouts = { { slot_melee = "shade_m" } },
            },
        }
        local live_by_career = {
            es_mercenary = { slot_melee = "sel_m_new" },        -- diverges on the SELECTED row (idx 2)
            we_shade     = { slot_melee = "shade_m" },          -- identical -> skip
            wh_zealot    = { slot_melee = "ghost" },            -- no store entry -> skip
        }
        local total, merged_rows, per_career = Core.reconcile_selected(live_by_career, store, SLOTS)
        H.equal(total, 1)
        H.equal(per_career.es_mercenary, 1)
        H.truthy(merged_rows.es_mercenary, "diverged career must produce a merged row")
        H.equal(merged_rows.es_mercenary.slot_melee, "sel_m_new")
        H.equal(merged_rows.es_mercenary.slot_ranged, "sel_r", "other selected-row slots preserved")
        H.equal(merged_rows.we_shade, nil, "clean career must not produce a merged row")
        H.equal(merged_rows.wh_zealot, nil, "career with no store entry must be skipped")
    end)

    H.test("exit-snapshot reconcile only touches the SELECTED row and never mutates inputs", function()
        local store = {
            es_mercenary = {
                selected_index = 2,
                loadouts = {
                    { slot_melee = "row1_untouched" },
                    { slot_melee = "sel_old" },
                },
            },
        }
        local live = { es_mercenary = { slot_melee = "sel_new" } }
        local total, merged_rows = Core.reconcile_selected(live, store, SLOTS)
        H.equal(total, 1)
        -- pure: the store and live inputs are unchanged (caller applies merged_rows).
        H.equal(store.es_mercenary.loadouts[1].slot_melee, "row1_untouched", "non-selected row untouched")
        H.equal(store.es_mercenary.loadouts[2].slot_melee, "sel_old", "reconcile must not mutate the store")
        H.equal(live.es_mercenary.slot_melee, "sel_new", "reconcile must not mutate the live input")
        H.equal(merged_rows.es_mercenary.slot_melee, "sel_new")
    end)

    H.test("exit-snapshot reconcile handles a career whose selected row is absent", function()
        local store = { es_mercenary = { selected_index = 5, loadouts = { { slot_melee = "m" } } } }
        local live = { es_mercenary = { slot_melee = "x" } }
        local total, merged_rows = Core.reconcile_selected(live, store, SLOTS)
        H.equal(total, 0, "no selected row (index out of range) -> skip, never invent a row")
        H.equal(merged_rows.es_mercenary, nil)
    end)

    H.test("exit-snapshot is wired into the native-loadout store + the entry-point exit edges", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua"
        local f = assert(io.open(runtime_path, "rb"))
        local src = f:read("*a")
        f:close()
        H.truthy(src:find("function M.exit_snapshot(edge_name)", 1, true),
            "exit_snapshot entry not defined on the store module")
        H.truthy(src:find("ExitSnapshotCore.reconcile_selected(live_by_career, store, LOADOUT_SLOT_NAMES)", 1, true),
            "STORE reconcile does not go through the pure core")
        H.truthy(src:find("_persist()", 1, true), "reconcile does not persist through the single store writer")
        H.truthy(src:find("[gut:persist] edge=%s diverged=%d written=%s", 1, true),
            "bounded persist diagnostic missing")

        local entry_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev.lua"
        local ef = assert(io.open(entry_path, "rb"))
        local esrc = ef:read("*a")
        ef:close()
        H.truthy(esrc:find('_snap("ingame_exit")', 1, true), "StateIngame-exit edge not wired")
        H.truthy(esrc:find('_snap("title_enter")', 1, true), "StateTitleScreen-enter edge not wired")
        H.truthy(esrc:find('_snap("unload")', 1, true), "on_unload edge not wired")
    end)
end
