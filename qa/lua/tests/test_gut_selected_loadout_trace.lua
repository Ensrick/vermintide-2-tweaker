return function(Harness, repo_root)
    local core = dofile(repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_selected_loadout_trace_core.lua")

    local function snapshot(row, value)
        return {
            career = "es_mercenary",
            slot = "slot_melee",
            requested_index = row,
            resolved_index = row,
            selected_index = 2,
            row_melee = "melee-" .. tostring(row),
            row_ranged = "ranged-" .. tostring(row),
            selected_melee = "melee-2",
            selected_ranged = "ranged-2",
            served_value = value,
            source = "store",
            caller = "hero_view_state_overview.lua",
        }
    end

    Harness.test("selected loadout trace suppresses identical hot reads", function()
        local trace = core.new(4)
        Harness.truthy(trace:record(snapshot(2, "melee-2")))
        Harness.falsy(trace:record(snapshot(2, "melee-2")))
        Harness.equal(trace:size(), 1)
    end)

    Harness.test("selected loadout trace exposes a changed served row", function()
        local trace = core.new(4)
        Harness.truthy(trace:record(snapshot(2, "melee-2")))
        Harness.truthy(trace:record(snapshot(2, "melee-1")))
        Harness.equal(trace:size(), 1)
    end)

    Harness.test("selected loadout trace cache is hard bounded", function()
        local trace = core.new(2)
        Harness.truthy(trace:record(snapshot(1, "melee-1")))
        Harness.truthy(trace:record(snapshot(2, "melee-2")))
        Harness.truthy(trace:record(snapshot(3, "melee-3")))
        Harness.equal(trace:size(), 2)
        -- Row 1 was evicted, so seeing it again must emit once rather than growing.
        Harness.truthy(trace:record(snapshot(1, "melee-1")))
        Harness.equal(trace:size(), 2)
    end)
end
