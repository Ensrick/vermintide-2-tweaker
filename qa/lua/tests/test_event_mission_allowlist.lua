return function(H, repo_root)
    local Missions = dofile(repo_root .. "/event_tweaker/scripts/mods/event_tweaker/event_tweaker_missions.lua")

    local function fixtures()
        local levels = {
            dlc_dwarf_fest = {
                level_id = "dlc_dwarf_fest", act = "act_celebrate",
                packages = { "resource_packages/levels/dlcs/dwarf_fest/dlc_dwarf_fest" },
            },
            dlc_celebrate_crawl = {
                level_id = "dlc_celebrate_crawl", act = "act_celebrate",
                packages = { "resource_packages/levels/dlcs/celebrate/crawl" },
            },
            control_level = {
                level_id = "control_level", act = "act_1", packages = { "control" },
            },
        }
        local areas = { celebrate = { acts = { "act_celebrate" }, exclude_from_area_selection = true } }
        local acts = { act_celebrate = { sorting = 2 } }
        local lookup = {
            level_keys = { dlc_dwarf_fest = 10, dlc_celebrate_crawl = 11 },
            mission_ids = { dlc_dwarf_fest = 20, dlc_celebrate_crawl = 21 },
            act_keys = { act_celebrate = 4 },
            unlockable_level_keys = { dlc_dwarf_fest = 30, dlc_celebrate_crawl = 31 },
        }
        return levels, areas, acts, lookup
    end

    H.test("Event mission allowlist is closed to the two audited levels", function()
        H.equal(#Missions.ALLOWLIST, 2)
        H.equal(Missions.ALLOWLIST[1].id, "dlc_dwarf_fest")
        H.equal(Missions.ALLOWLIST[2].id, "dlc_celebrate_crawl")
    end)

    H.test("Event mission filter enables both missions and preserves a control act", function()
        local levels = fixtures()
        local control = { levels.control_level }
        local original = { act_1 = control, act_celebrate = { { level_id = "future_event" } } }
        local enabled = {
            mission_dlc_dwarf_fest = true,
            mission_dlc_celebrate_crawl = true,
        }
        local out = Missions.filter_levels_by_act(original, levels, function(id) return enabled[id] end)
        H.equal(#out.act_celebrate, 2)
        H.equal(out.act_celebrate[1], levels.dlc_dwarf_fest)
        H.equal(out.act_celebrate[2], levels.dlc_celebrate_crawl)
        H.equal(out.act_1, control)
        H.equal(original.act_celebrate[1].level_id, "future_event")
    end)

    H.test("Event mission filter honors individual toggles and never admits a control", function()
        local levels = fixtures()
        local out = Missions.filter_levels_by_act({}, levels, function(id)
            return id == "mission_dlc_celebrate_crawl"
        end)
        H.equal(#out.act_celebrate, 1)
        H.equal(out.act_celebrate[1].level_id, "dlc_celebrate_crawl")
        H.equal(out.act_celebrate[1] == levels.control_level, false)
    end)

    H.test("Event mission contract fails closed on missing wire lookup", function()
        local levels, areas, acts, lookup = fixtures()
        lookup.mission_ids.dlc_dwarf_fest = nil
        local ok, problems = Missions.validate_contract(levels, areas, acts, lookup)
        H.equal(ok, false)
        H.truthy(table.concat(problems, ";"):find("NetworkLookup.mission_ids lacks dlc_dwarf_fest", 1, true))
    end)

    H.test("Event mission contract accepts the complete source-backed shape", function()
        local levels, areas, acts, lookup = fixtures()
        local ok, problems = Missions.validate_contract(levels, areas, acts, lookup)
        H.equal(ok, true)
        H.equal(#problems, 0)
    end)
end
