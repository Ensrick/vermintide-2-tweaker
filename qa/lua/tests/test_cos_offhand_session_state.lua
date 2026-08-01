return function(H, repo_root)
    local module_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_offhand_session_state.lua"
    local owner = assert(dofile(module_path))

    H.test("offhand session state isolates exact item instances and hands", function()
        local state = owner.new()
        local first_right = { unit = "first_right" }
        local first_left = { unit = "first_left" }
        local second_left = { unit = "second_left" }

        state.selections.first = {
            right_hand_unit = first_right,
            left_hand_unit = first_left,
        }
        state.selections.second = { left_hand_unit = second_left }

        local snapshot = state.snapshot("first")
        state.selections.first.left_hand_unit = second_left
        state.restore("first", snapshot)

        H.equal(state.selections.first.right_hand_unit, first_right)
        H.equal(state.selections.first.left_hand_unit, first_left)
        H.equal(state.selections.second.left_hand_unit, second_left)
        H.truthy(state.selections.first ~= snapshot,
            "restore must clone the hand map instead of retaining caller state")
    end)

    H.test("empty offhand baseline remains distinguishable from no session", function()
        local state = owner.new()
        H.equal(state.snapshot(nil), nil)
        H.equal(state.snapshot("empty-item"), false)

        state.selections["empty-item"] = { left_hand_unit = { unit = "temporary" } }
        H.equal(state.restore("empty-item", false), true)
        H.equal(state.selections["empty-item"], nil)
        H.equal(state.restore(nil, false), false)
    end)

    H.test("legacy option records migrate once to the left hand", function()
        local legacy = { unit = "legacy_mesh", rarity = "exotic" }
        local state = owner.new({ selections = { old_item = legacy } })

        H.equal(state.migrate_legacy("old_item"), true)
        H.equal(state.selections.old_item.left_hand_unit, legacy)
        H.equal(state.migrate_legacy("old_item"), false)
        H.equal(state.migrate_legacy("missing"), false)
    end)

    H.test("offhand session owner adopts existing apply maps", function()
        local baselines = { retained = false }
        local committed = { retained = true }
        local state = owner.new({ baselines = baselines, committed = committed })

        H.equal(state.baselines, baselines)
        H.equal(state.committed, committed)
        H.equal(state.baselines.retained, false)
        H.equal(state.committed.retained, true)
    end)
end
