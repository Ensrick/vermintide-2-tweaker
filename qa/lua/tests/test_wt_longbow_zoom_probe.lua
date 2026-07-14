return function(H, repo_root)
    local path = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_longbow_zoom_probe.lua"
    local Probe = assert(loadfile(path))()

    H.test("WT longbow zoom probe targets only non-Huntsman Kruber", function()
        for _, career in ipairs({ "es_mercenary", "es_knight", "es_questingknight" }) do
            H.truthy(Probe.is_target("longbow_empire_template", career))
        end
        H.truthy(not Probe.is_target("longbow_empire_template", "es_huntsman"))
        H.truthy(not Probe.is_target("longbow_empire_template", "wh_captain"))
        H.truthy(not Probe.is_target("longbow_template_1", "es_mercenary"))
    end)

    H.test("WT longbow zoom probe observes once at the authored due time", function()
        local probe = Probe.new()
        local rec = probe:arm("longbow_empire_template", "es_mercenary", "es_longbow", 10, 10.22)
        H.truthy(rec)
        H.equal(nil, probe:observe(rec, 10.21, false, nil))
        local result = probe:observe(rec, 10.22, true, "zoom_in")
        H.equal("zoomed", result.outcome)
        H.equal("zoom_in", result.zoom_mode)
        H.equal(nil, probe:observe(rec, 10.30, true, "zoom_in"))
    end)

    H.test("WT longbow zoom probe records early finish and caps attempts", function()
        local probe = Probe.new(2)
        local one = probe:arm("longbow_empire_template", "es_knight", "es_longbow", 1, 1.22)
        local result = probe:finish(one, 1.1, "action_complete")
        H.equal("finished_before_observation", result.outcome)
        H.equal(nil, probe:finish(one, 1.2, "duplicate"))
        H.truthy(probe:arm("longbow_empire_template", "es_knight", "es_longbow", 2, 2.22))
        H.equal(nil, probe:arm("longbow_empire_template", "es_knight", "es_longbow", 3, 3.22))
    end)
end
