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
        return levels, areas, acts
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

    H.test("Event mission contract ignores NetworkLookup and accepts the menu-read shape", function()
        local levels, areas, acts = fixtures()
        local ok, problems = Missions.validate_contract(levels, areas, acts)
        H.equal(ok, true)
        H.equal(#problems, 0)
    end)

    H.test("Event mission contract fails closed on missing menu-read tables", function()
        local levels, areas, acts = fixtures()
        levels.dlc_dwarf_fest = nil
        local ok, problems = Missions.validate_contract(levels, areas, acts)
        H.equal(ok, false)
        H.truthy(table.concat(problems, ";"):find("LevelSettings.dlc_dwarf_fest missing", 1, true))

        local levels2, areas2, acts2 = fixtures()
        areas2.celebrate.acts = {}
        local ok2, problems2 = Missions.validate_contract(levels2, areas2, acts2)
        H.equal(ok2, false)
        H.truthy(table.concat(problems2, ";"):find("AreaSettings.celebrate lacks act_celebrate", 1, true))

        local levels3, areas3, acts3 = fixtures()
        acts3.act_celebrate.sorting = nil
        local ok3, problems3 = Missions.validate_contract(levels3, areas3, acts3)
        H.equal(ok3, false)
        H.truthy(table.concat(problems3, ";"):find("ActSettings.act_celebrate.sorting not a number", 1, true))
    end)

    H.test("Campaign registration fallback is a no-op on a vanilla-complete install", function()
        local levels = fixtures()
        local unlockable = { "control_level", "dlc_dwarf_fest", "dlc_celebrate_crawl" }
        local game_acts = { act_celebrate = { "dlc_dwarf_fest", "dlc_celebrate_crawl" }, act_1 = { "control_level" } }
        local map_acts = { "act_1", "act_celebrate" }
        local appended = Missions.ensure_campaign_registration(levels, unlockable, game_acts, map_acts)
        H.equal(#appended, 0)
        H.equal(#unlockable, 3)
        H.equal(#game_acts.act_celebrate, 2)
        H.equal(#map_acts, 2)
    end)

    H.test("Campaign registration fallback appends missing entries idempotently", function()
        local levels = fixtures()
        local unlockable = { "control_level" }
        local game_acts = { act_1 = { "control_level" } }
        local map_acts = { "act_1" }
        local appended = Missions.ensure_campaign_registration(levels, unlockable, game_acts, map_acts)
        H.equal(#appended, 5)
        H.truthy(table.concat(appended, ";"):find("UnlockableLevels+dlc_dwarf_fest", 1, true))
        H.truthy(table.concat(appended, ";"):find("GameActs.act_celebrate+dlc_celebrate_crawl", 1, true))
        H.truthy(table.concat(appended, ";"):find("MapPresentationActs+act_celebrate", 1, true))
        H.equal(#unlockable, 3)
        H.equal(#game_acts.act_celebrate, 2)
        H.equal(#map_acts, 2)
        H.equal(game_acts.act_1[1], "control_level")

        local appended2 = Missions.ensure_campaign_registration(levels, unlockable, game_acts, map_acts)
        H.equal(#appended2, 0)
        H.equal(#unlockable, 3)
        H.equal(#game_acts.act_celebrate, 2)
        H.equal(#map_acts, 2)
    end)

    H.test("Campaign registration fallback never registers a malformed level", function()
        local levels = fixtures()
        levels.dlc_dwarf_fest.packages = {}
        levels.dlc_celebrate_crawl = nil
        local unlockable = {}
        local game_acts = {}
        local map_acts = {}
        local appended = Missions.ensure_campaign_registration(levels, unlockable, game_acts, map_acts)
        H.equal(#appended, 0)
        H.equal(#unlockable, 0)
        H.equal(#map_acts, 0)
    end)
end
