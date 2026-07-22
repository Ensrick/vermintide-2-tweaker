return function(H, repo_root)
    local root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local unlocks = dofile(root .. "wt_unlock_data.lua").weapon_unlock_map
    local status = dofile(repo_root
        .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/wt_port_status.lua")
    local careers = { "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister" }

    H.test("WT #111 historical Kerillian ledger proves routing only", function()
        local baseline
        for _, career in ipairs(careers) do
            local rows, counts = status.audit_cross_character(career, unlocks[career])
            local keys = {}
            for i, row in ipairs(rows) do
                keys[i] = row.weapon_key
                H.equal(row.state, "untested")
            end
            local signature = table.concat(keys, "\0")
            baseline = baseline or signature
            H.equal(signature, baseline, career .. " cross-character routing drift")
            H.equal(counts.total, 60)
            H.equal(counts.untested, 60)
            H.equal(counts.routing_wired, 44)
            H.equal(counts.routing_needs_animations, 14)
            H.equal(counts.routing_unknown, 2)
        end
    end)

    H.test("WT #111 target labels remain routing metadata", function()
        local rows = status.audit_cross_character("we_waywatcher", unlocks.we_waywatcher)
        local by_key = {}
        for _, row in ipairs(rows) do by_key[row.weapon_key] = row end
        for _, key in ipairs({
            "dr_crossbow", "dr_deus_01", "dr_drake_pistol", "dr_drakegun",
            "dr_rakegun", "dr_steam_pistol", "es_blunderbuss", "es_handgun",
            "es_repeating_handgun", "wh_brace_of_pistols", "wh_crossbow",
            "wh_crossbow_repeater", "wh_deus_01", "wh_repeating_pistols",
        }) do
            H.equal(by_key[key].state, "untested")
            H.equal(by_key[key].routing_state, "needs_animations")
            H.equal(by_key[key].redirect, "Elf Repeater Crossbow")
        end
        for _, key in ipairs({ "es_1h_mace", "es_longbow" }) do
            H.equal(by_key[key].routing_state, "unknown")
            H.equal(by_key[key].redirect, nil)
        end
    end)
end
