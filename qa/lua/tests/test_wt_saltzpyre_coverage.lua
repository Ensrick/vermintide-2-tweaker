return function(H, repo_root)
    local root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local unlocks = dofile(root .. "wt_unlock_data.lua").weapon_unlock_map
    local status = dofile(repo_root
        .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/wt_port_status.lua")
    local careers = { "wh_captain", "wh_bountyhunter", "wh_zealot" }

    H.test("WT #112 historical Saltzpyre ledger proves routing only", function()
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
            H.equal(counts.total, 54)
            H.equal(counts.untested, 54)
            H.equal(counts.routing_wired, 37)
            H.equal(counts.routing_needs_animations, 17)
            H.equal(counts.routing_unknown, 0)
            H.equal(counts.picker_visible, 2)
        end
    end)

    H.test("WT #112 pending routes and shipped transforms stay inspectable", function()
        local rows = status.audit_cross_character("wh_captain", unlocks.wh_captain)
        local by_key = {}
        for _, row in ipairs(rows) do by_key[row.weapon_key] = row end
        H.equal(by_key.bw_ghost_scythe.picker_visible, true)
        H.equal(by_key.we_spear.picker_visible, true)
        H.equal(by_key.we_1h_spears_shield.redirect, "Dual Axe & Falchion")
        H.equal(by_key.we_deus_01.redirect, "Saltzpyre Crossbow")
        H.equal(by_key.we_deus_01.model_substitute, "Crossbow")
        H.equal(by_key.we_shortbow.routing_state, "needs_animations")
        H.equal(by_key.we_shortbow.redirect, nil)
    end)

    H.test("WT #112 Saltzpyre transforms retain their source contracts", function()
        local file = assert(io.open(root .. "weapon_tweaker.lua", "rb"))
        local source = file:read("*a")
        file:close()
        local checks = assert(io.open(root .. "_wt_runtime_checks.lua", "rb"))
        source = source .. checks:read("*a")
        checks:close()
        H.truthy(source:find("es_handgun = { wh_ = {0, -0.17, -0.05} }", 1, true))
        H.truthy(source:find("issue112_saltzpyre_handgun_baked_offset", 1, true))
        H.truthy(source:find(
            'local _SALTZ_KRUBER_SHIELD_ROTATION = { 25, -17.5, -15, hand = "left" }',
            1, true))
        H.truthy(source:find("issue112_saltzpyre_kruber_shield_baked_rotation", 1, true))
    end)
end
