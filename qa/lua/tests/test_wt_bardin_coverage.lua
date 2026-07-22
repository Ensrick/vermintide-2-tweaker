return function(H, repo_root)
    local root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local unlocks = dofile(root .. "wt_unlock_data.lua").weapon_unlock_map
    local status = dofile(repo_root
        .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/wt_port_status.lua")
    local careers = { "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer" }

    H.test("WT #110 historical Bardin ledger proves routing only", function()
        local baseline
        for _, career in ipairs(careers) do
            local rows, counts = status.audit_cross_character(career, unlocks[career])
            local keys = {}
            for i, row in ipairs(rows) do
                keys[i] = row.weapon_key
                H.equal(row.state, "untested")
                H.equal(row.routing_state, "wired")
            end
            local signature = table.concat(keys, "\0")
            baseline = baseline or signature
            H.equal(signature, baseline, career .. " cross-character routing drift")
            H.equal(counts.total, 5)
            H.equal(counts.untested, 5)
            H.equal(counts.routing_wired, 5)
            H.equal(counts.routing_needs_animations, 0)
            H.equal(counts.routing_unknown, 0)
        end
    end)

    H.test("WT #110 event-map metadata remains non-verifying", function()
        for _, key in ipairs({
            "we_1h_sword", "es_1h_sword", "wh_1h_falchion", "bw_1h_crowbill",
        }) do
            H.equal(status.state("dr_ranger", key), "untested")
            H.equal(status.routing_state("dr_ranger", key), "wired")
            H.equal(status.redirect_target("dr_ranger", key), "Bardin 1H event map")
        end
        H.equal(status.routing_state("dr_ranger", "es_handgun"), "wired")
        H.equal(status.redirect_target("dr_ranger", "es_handgun"), nil)
    end)
end
