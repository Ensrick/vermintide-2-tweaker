return function(H, repo_root)
    local root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local unlocks = dofile(root .. "wt_unlock_data.lua").weapon_unlock_map
    local status = dofile(repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/wt_port_status.lua")
    local careers = { "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer" }

    H.test("WT #110 Bardin has five working cross-character ports on every career", function()
        local baseline
        for _, career in ipairs(careers) do
            local rows, counts = status.audit_cross_character(career, unlocks[career])
            local keys = {}
            for i, row in ipairs(rows) do keys[i] = row.weapon_key end
            local signature = table.concat(keys, "\0")
            baseline = baseline or signature
            H.equal(signature, baseline, career .. " cross-character coverage drift")
            H.equal(#rows, 5)
            H.equal(counts.total, 5)
            H.equal(counts.working, 5)
            H.equal(counts.needs_animations, 0)
            H.equal(counts.untested, 0)
            H.equal(counts.needs_offsets, 0)
            H.equal(counts.picker_visible, 0)
            H.equal(counts.hidden_needs_animations, 0)
        end
    end)

    H.test("WT #110 Bardin display distinguishes event maps from native handgun", function()
        for _, key in ipairs({
            "we_1h_sword", "es_1h_sword", "wh_1h_falchion", "bw_1h_crowbill",
        }) do
            H.equal(status.decorate_tag("dr_ranger", key, true),
                "[working → Bardin 1H event map]")
            H.equal(status.decorate_tag("dr_ranger", key, false), "[working]")
            H.equal(status.model_substitute("dr_ranger", key), nil)
        end
        H.equal(status.tag("dr_ranger", "es_handgun"), "[working]")
        H.equal(status.redirect_target("dr_ranger", "es_handgun"), nil)
        H.equal(status.decorate_tag("dr_ranger", "es_handgun", true), "[working]")
    end)

    H.test("WT #110 Bardin diagnostics are automatic and bounded", function()
        local file = assert(io.open(repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_diagnostics.lua", "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("_audit_bardin_3p(false)", 1, true))
        H.truthy(source:find('mod:command("wt_audit_bardin_3p"', 1, true))
        H.truthy(source:find("[wt:110] Bardin 3P ports=%d", 1, true))
    end)
end
