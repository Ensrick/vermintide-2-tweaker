return function(H, repo_root)
    local path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_dev_mission_catalog.lua"

    local adventure = {
        MISSION_GROUPS = {},
        EVENT_MISSIONS = {},
        CW_SCENARIOS = {},
    }
    local mod = {
        dofile = function(_, dependency)
            if dependency:find("_adventure_pool", 1, true) then return adventure end
            error("unexpected dependency " .. tostring(dependency))
        end,
    }
    local old_get_mod = get_mod
    get_mod = function() return mod end
    local catalog = assert(loadfile(path))()
    get_mod = old_get_mod

    H.test("CT #505 run progress follows vanilla's strict sub-one boundary", function()
        H.equal(catalog.MAX_RUN_PROGRESS, 0.999)
        H.equal(catalog.PROGRESS[#catalog.PROGRESS], 0.999)
        H.equal(catalog.sanitize_progress(0), 0)
        H.equal(catalog.sanitize_progress(0.75), 0.75)
        H.equal(catalog.sanitize_progress(0.999), 0.999)
        H.equal(catalog.sanitize_progress(1), 0.999)
        H.equal(catalog.sanitize_progress(900), 0.999)
        H.equal(catalog.sanitize_progress(-1), 0)
        H.equal(catalog.sanitize_progress(0 / 0), 0)
        H.equal(catalog.sanitize_progress(nil), 0)
    end)

    H.test("CT #505 progress labels disclose the engine-safe deepest value", function()
        local loc = catalog.build_loc_entries()
        H.equal(loc.ctdm_p_5.en, "Deepest (99.9%%)")
    end)
end
