-- Characterization cases for the modded loadout writers (WP-GUT-02 / WP-GUT-03).
--
-- One case per production writer of the modded loadout store (plus the readonly overlay). Each
-- case names its starting state, the action through the REAL hooks of _gut_native_loadouts.lua
-- (`old`, driven by _gut_native_owner_fixture.lua), the equivalent action on the store module
-- (`new`), and the literal saved tables both must produce:
--   test_gut_native_loadout_writers.lua runs `old` (the writers as they are on master),
--   test_gut_loadout_store.lua runs `new` (the extracted store).
-- After WP-GUT-03 routes the hooks through the store, `old` keeps pinning the hooks.
--
-- Usage: local cases = assert(loadfile(<this>))()(Fixture, Policy)
return function(Fixture, Policy)
    local deepcopy = Fixture.deepcopy
    local GEAR = Fixture.GEAR
    local C, HUNTSMAN = "es_mercenary", "es_huntsman"
    local MIRROR = "PlayFabMirrorAdventure."
    local O = function(career, n) return Fixture.official_row(career, n) end
    local function official_rows(career, n)
        local rows = {}
        for i = 1, n do rows[i] = O(career, i) end
        return rows
    end
    local function seeded(career, n, selected)
        return { selected_index = selected or 1, loadouts = official_rows(career, n),
            _seeded = true, _slot_integrity_v2 = true }
    end
    local cases = {}
    local function case(t) cases[#cases + 1] = t end

    do
        local expected = { [C] = seeded(C, 2, 1) }
        expected[C].loadouts[2].slot_melee = "cim_x"
        expected[C].loadouts[1].talents = "2,2,2,2,2,2"
        case({ name = "set_character_data: seed, then the given row or the selected row",
            options = {}, expected = expected, saves = 3, vanilla_calls = 0,
            old = function(s)
                s:hook(MIRROR .. "set_character_data", C, "slot_melee", "cim_x", false, 2)
                s:hook(MIRROR .. "set_character_data", C, "talents", "2,2,2,2,2,2", false, nil)
            end,
            new = function(store)
                store:ensure_seeded(C, official_rows(C, 2), 1)
                store:set(C, "slot_melee", "cim_x", 2)
                store:set(C, "talents", "2,2,2,2,2,2", nil)
            end })
    end

    do
        local expected = { [C] = seeded(C, 2, 1) }
        expected[C].loadouts[1].slot_ring = "cim_ring"
        expected[C].loadouts[2].slot_hat = "cim_hat"
        case({ name = "set_career_read_only_data: same row rule, career is the fourth argument",
            options = {}, expected = expected, saves = 3, vanilla_calls = 0,
            old = function(s)
                s:hook(MIRROR .. "set_career_read_only_data", "mercenary", "slot_ring", "cim_ring", C, false, nil)
                s:hook(MIRROR .. "set_career_read_only_data", "mercenary", "slot_hat", "cim_hat", C, false, 2)
            end,
            new = function(store)
                store:ensure_seeded(C, official_rows(C, 2), 1)
                store:set(C, "slot_ring", "cim_ring", nil)
                store:set(C, "slot_hat", "cim_hat", 2)
            end })
    end

    case({ name = "set_loadout_index: an existing row is selected, a missing row refused",
        options = {}, expected = { [C] = seeded(C, 2, 2) }, saves = 2, vanilla_calls = 0,
        old = function(s)
            s:hook(MIRROR .. "set_loadout_index", C, 2)
            s:hook(MIRROR .. "set_loadout_index", C, 5)
        end,
        new = function(store)
            store:ensure_seeded(C, official_rows(C, 2), 1)
            store:select(C, 2)
            store:select(C, 5)
        end })

    do
        local expected = { [C] = seeded(C, 2, 2) }
        expected[C].loadouts[3] = O(C, 1)
        case({ name = "add_loadout: copy of the selected row, selection old + 1, stops at the cap",
            options = { max_loadouts = 3 }, expected = expected, saves = 2, vanilla_calls = 0,
            old = function(s)
                s:hook(MIRROR .. "add_loadout", C)
                s:hook(MIRROR .. "add_loadout", C)
            end,
            new = function(store)
                store:ensure_seeded(C, official_rows(C, 2), 1)
                store:add(C)
                store:add(C)
            end })
    end

    do
        local expected = { [C] = seeded(C, 3, 1) }
        table.remove(expected[C].loadouts, 1)
        table.remove(expected[C].loadouts, 2)
        case({ name = "delete_loadout: guards and selection fix-up",
            options = { store = { [C] = seeded(C, 3, 3) }, careers = { [C] = { rows = 3, selected = 1 } } },
            expected = expected, saves = 2, vanilla_calls = 0,
            old = function(s)
                s:hook(MIRROR .. "delete_loadout", C, 9)
                s:hook(MIRROR .. "delete_loadout", C, 1)
                s:hook(MIRROR .. "delete_loadout", C, 2)
                s:hook(MIRROR .. "delete_loadout", C, 1)
            end,
            new = function(store)
                store:delete(C, 9); store:delete(C, 1); store:delete(C, 2); store:delete(C, 1)
            end })
    end

    do
        local expected = { [C] = seeded(C, 2, 1) }
        expected[C].loadouts[1].slot_melee = "cim_new_melee"
        case({ name = "outer equip capture: always the selected row",
            options = {}, expected = expected, saves = 2,
            vanilla_calls = 1,   -- the outer BackendUtils entry still runs vanilla once
            old = function(s)
                s:hook(MIRROR .. "get_character_data", C, "slot_melee", 2)   -- installs the capture, seeds
                s:hook("BackendUtils.set_loadout_item", "cim_new_melee", C, "slot_melee")
            end,
            new = function(store)
                store:ensure_seeded(C, official_rows(C, 2), 1)
                store:set(C, "slot_melee", "cim_new_melee", nil)
            end })
    end

    do
        local o1 = O(C, 1)
        local expected = { [C] = { selected_index = 1, _seeded = true, _slot_integrity_v2 = true, loadouts = {
            { slot_melee = "keep_m", slot_ranged = o1.slot_ranged, slot_skin = o1.slot_skin,
              slot_hat = o1.slot_hat, slot_frame = o1.slot_frame, slot_pose = o1.slot_pose, talents = o1.talents },
            O(C, 2) } } }
        case({ name = "seed repair through the first mirror read",
            options = { store = { [C] = { selected_index = 1, loadouts = { { slot_melee = "keep_m" } } } } },
            expected = expected, saves = 1, vanilla_calls = 0,
            log = "repaired career=es_mercenary partial store (issues #375/#402): rows_added=1 rows_repaired=1 slots_repaired=0 loadouts=2 selected=1",
            old = function(s) s:hook(MIRROR .. "get_character_data", C, "slot_hat", nil) end,
            new = function(store) store:ensure_seeded(C, official_rows(C, 2), 1) end })
    end

    do
        local entry = seeded(C, 2, 2)
        entry.loadouts[1].slot_melee = "modded"
        entry.bot_index = 2; entry.bot_loadout = { slot_melee = "bot_m" }; entry._bot_designation_snapshot_v2 = true
        case({ name = "reset: clear, keep the bot designation, reseed in one transaction",
            options = { store = { [C] = entry }, overlay = { [C] = { [1] = { slot_hat = "ov" } } },
                careers = { [C] = { rows = 2, selected = 1 }, [HUNTSMAN] = { rows = 1, selected = 1 } } },
            expected = {
                [C] = { selected_index = 1, loadouts = official_rows(C, 2), bot_index = 2,
                    bot_loadout = { slot_melee = "bot_m" }, _bot_designation_snapshot_v2 = true,
                    _seeded = true, _slot_integrity_v2 = true },
                [HUNTSMAN] = seeded(HUNTSMAN, 1, 1),
            },
            expected_overlay = {}, saves = 1, overlay_saves = 1,
            old = function(s) s.native.reset_modded_loadouts(nil, "test", false) end,
            new = function(store, s)
                store:batch(function()
                    store:reset(nil)
                    local careers = Policy.official_seed_careers(s.mirror, nil)
                    for i = 1, #careers do
                        store:ensure_seeded(careers[i], s.mirror._career_data[careers[i]],
                            s.mirror._career_loadouts[careers[i]])
                    end
                end)
            end })
    end

    do
        local entry = seeded(C, 2, 1)
        entry.loadouts[1].slot_necklace = "unresolved_neck"
        local live = O(C, 1)
        live.talents = nil
        live.slot_hat = "live_hat"
        local expected = { [C] = deepcopy(entry) }
        expected[C].loadouts[1].slot_hat = "live_hat"
        case({ name = "exit snapshot: unresolved stored gear kept, resolvable divergence written",
            options = { store = { [C] = entry }, extra_items = { "live_hat" }, live = live },
            expected = expected, saves = 1,
            old = function(s)
                local total, wrote = s.native.exit_snapshot("test")
                assert(total == 1 and wrote == true, "exit snapshot totals")
            end,
            new = function(store, s)
                local _, _, total, _, skipped = store:reconcile_selected({ [C] = live }, function(_, slot, value)
                    local gear = false
                    for i = 1, #GEAR do if GEAR[i] == slot then gear = true end end
                    return gear and s.items[value] == nil
                end)
                assert(total == 1 and skipped == 1, "reconcile totals")
            end })
    end

    do
        local expected = { [C] = seeded(C, 2, 1) }
        local snapshot = O(C, 2); snapshot.talents = nil
        expected[C].bot_index = 2; expected[C].bot_loadout = snapshot
        expected[C]._bot_designation_snapshot_v2 = true
        case({ name = "bot designation: detached snapshot of the designated row",
            options = { store = { [C] = seeded(C, 2, 1) } }, expected = expected, saves = 1, vanilla_calls = 0,
            old = function(s)
                s:hook("HeroWindowLoadoutSelectionConsole._save_bot_equipment",
                    { _profile_index = 1, _career_index = 1, _context_menu_loadout_index = 2 })
            end,
            new = function(store) store:set_bot_designation(C, 2, nil) end })
    end

    case({ name = "readonly writes: overlay at the official index, store untouched",
        options = { readonly = true, careers = { [C] = { rows = 2, selected = 2 } } },
        expected = {}, saves = 0, overlay_saves = 2, vanilla_calls = 0,
        expected_overlay = { [C] = { [2] = { slot_hat = "ro_hat", slot_melee = "cwv_es_dual_axes_001" } } },
        old = function(s)
            s:hook(MIRROR .. "set_character_data", C, "slot_hat", "ro_hat", false, nil)
            s:hook(MIRROR .. "set_character_data", C, "slot_melee", "cwv_es_dual_axes_001", false, nil)
            s:hook(MIRROR .. "set_character_data", C, "slot_ranged", "plain_ranged", false, nil)
            s:hook(MIRROR .. "set_character_data", C, "slot_ring", "ring", false, nil)
            s:hook(MIRROR .. "set_career_read_only_data", "mercenary", "talents", "1,1,1,1,1,1", C, false, nil)
        end,
        new = function(store)
            store:overlay_set(C, "slot_hat", "ro_hat", 2)
            store:overlay_set(C, "slot_melee", "cwv_es_dual_axes_001", 2)
            store:overlay_clear(C, "slot_ranged", 2)
        end })

    -- Read decision: what the get_character_data hook serves for each input. `served` is the
    -- literal value; for an official fallback it is the official SELECTED row (nil index).
    local read_entry = seeded(C, 2, 1)
    read_entry.loadouts[1].slot_melee = nil
    read_entry.loadouts[1].slot_necklace = nil
    read_entry.loadouts[2].slot_ring = "gone_ring"
    local reads = {
        options = { store = { [C] = read_entry } },
        career = C,
        rows = {
            { key = "slot_melee", index = nil, served = O(C, 1).slot_melee, source = "need-official-fallback" },
            { key = "slot_necklace", index = nil, served = nil, source = "nil-jewelry" },
            { key = "slot_ring", index = 2, served = O(C, 1).slot_ring, source = "need-official-fallback" },
            { key = "slot_ranged", index = 2, served = O(C, 2).slot_ranged, source = "store" },
            { key = "slot_hat", index = 1, served = O(C, 1).slot_hat, source = "store" },
            { key = "talents", index = 2, served = O(C, 2).talents, source = "store" },
            { key = "slot_melee", index = 7, served = nil, source = "row-missing" },
        },
    }

    return cases, reads
end
