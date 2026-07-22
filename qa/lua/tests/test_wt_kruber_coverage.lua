return function(H, repo_root)
    local root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local unlocks = dofile(root .. "wt_unlock_data.lua").weapon_unlock_map
    local status = dofile(repo_root
        .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/wt_port_status.lua")
    local careers = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }

    H.test("WT #109 historical Kruber ledger proves routing only", function()
        local baseline
        for _, career in ipairs(careers) do
            local rows, counts = status.audit_cross_character(career, unlocks[career])
            local keys = {}
            for i, row in ipairs(rows) do
                keys[i] = row.weapon_key
                H.equal(row.state, "untested")
                H.equal(row.verification_state, "untested")
            end
            local signature = table.concat(keys, "\0")
            baseline = baseline or signature
            H.equal(signature, baseline, career .. " cross-character routing drift")
            H.equal(counts.total, 52)
            H.equal(counts.untested, 52)
            H.equal(counts.routing_wired, 37)
            H.equal(counts.routing_needs_animations, 13)
            H.equal(counts.routing_unknown, 2)
            H.equal(counts.routing_needs_offsets, 0)
        end
    end)

    H.test("WT #109 route labels do not imply verification", function()
        local rows = status.audit_cross_character("es_mercenary", unlocks.es_mercenary)
        local by_key = {}
        for _, row in ipairs(rows) do by_key[row.weapon_key] = row end
        H.equal(by_key.we_deus_01.state, "untested")
        H.equal(by_key.we_deus_01.routing_state, "needs_animations")
        H.equal(by_key.we_deus_01.redirect, "Empire Longbow")
        H.equal(by_key.we_javelin.routing_state, "unknown")
        H.equal(by_key.we_life_staff.routing_state, "unknown")
        H.equal(status.state("es_mercenary", "we_deus_01"), "untested")
    end)
end
