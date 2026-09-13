-- Issue #1575: Mod Tweaker transactions must not let the derived #445 family
-- masters or #936 Tourney career presets clear leaves by iteration order. Uses
-- the installed CRT callback/owner slices and the installed GUT view, state,
-- profile and transaction code through the #221 runtime fixture. Every
-- transaction case runs under forced `pairs` orders, because PUC Lua and
-- LuaJIT iterate these tables differently.
return function(H, repo_root)
    local runtime = assert(loadfile(repo_root .. "/qa/lua/tests/_crt_armor_runtime_fixture.lua"))()
    local catalog = assert(loadfile(repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_crt_tourney_catalog.lua"))()
    local A, B = "rework_dr_slayer_no_escape_15s", "rework_dr_slayer_dawi_drop_buffed"
    local T, T2 = "trn_dr_slayer_dodge_damage_reduction", "trn_dr_ranger_attack_speed"
    local ENSRICK, TOURNEY, ALL = "rework_master_ensrick", "rework_master_tourney", "rework_master_all"
    local HUNTSMAN = "trn_es_huntsman"
    local huntsman = catalog.LEAVES_BY_MASTER[HUNTSMAN]

    local flag = { [ENSRICK] = true, [TOURNEY] = true, [ALL] = true }
    for _, id in ipairs(catalog.MASTER_IDS) do flag[id] = true end

    -- Iterate every table in a forced key order while `fn` runs. Keys removed
    -- during iteration are skipped, exactly like `next`.
    local ORDERS = {
        ascending = function(k) return k end,
        descending = function(k) return k end,
        flags_first = function(k) return (flag[k] and "0" or "1") .. k end,
        leaves_first = function(k) return (flag[k] and "1" or "0") .. k end,
    }
    local function with_order(name, fn)
        local rank, real_pairs = ORDERS[name], pairs
        _G.pairs = function(t)
            local entries, key = {}, next(t)
            while key ~= nil do
                entries[#entries + 1] = { key = key, rank = type(key) == "string" and rank(key) or nil,
                    index = #entries + 1 }
                key = next(t, key)
            end
            table.sort(entries, function(a, b)
                if a.rank and b.rank and a.rank ~= b.rank then
                    if name == "descending" then return a.rank > b.rank end
                    return a.rank < b.rank
                end
                if a.rank and not b.rank then return true end
                if b.rank and not a.rank then return false end
                return a.index < b.index
            end)
            local position = 0
            return function()
                while true do
                    position = position + 1
                    local entry = entries[position]
                    if not entry then return nil end
                    local value = rawget(t, entry.key)
                    if value ~= nil then return entry.key, value end
                end
            end, t, nil
        end
        local ok, err = pcall(fn)
        _G.pairs = real_pairs
        if not ok then error(err, 0) end
    end

    local function world_for(surface, tourney_ids, with_catalog)
        local world = runtime(repo_root, {}, nil, {
            surface = surface, ensrick = { [A] = {}, [B] = {} }, tourney = tourney_ids,
            tourney_engine = with_catalog and { CATALOG = catalog, apply = function() end,
                restore = function() end } or nil,
        })
        for _, node in ipairs(world.view._build_nodes) do
            if node.setting_id and world.state[node.setting_id] == nil then
                world.state[node.setting_id] = node.default_value
            end
        end
        world.profiles.migrate_all(world.store)
        return world
    end

    local function switch(world, slot)
        world.view:_switch_profile(slot)
        H.equal(world.profiles.get_active(world.store, "crt"), slot)
    end

    local function expect(world, values, label)
        for id, value in pairs(values) do
            H.equal(world.state[id], value, label .. ": " .. id)
        end
    end

    for _, surface in ipairs({ "standalone", "embedded" }) do
        for order in pairs(ORDERS) do
            local label = surface .. " " .. order

            H.test("CRT #1575 " .. label .. " round trip keeps leaves under a derived Tourney indicator", function()
                local world = world_for(surface, { T })
                world.mod:set(A, true, true)
                world.mod:set(T, true, true)
                H.equal(world.state[TOURNEY], true, "a complete Tourney family derives its indicator")
                with_order(order, function()
                    H.equal(world.view:_profile_ensure(world.category), true)
                    switch(world, 2)
                    switch(world, 1)
                end)
                expect(world, { [A] = true, [B] = false, [T] = true,
                    [ENSRICK] = false, [TOURNEY] = true, [ALL] = false }, label)
            end)

            H.test("CRT #1575 " .. label .. " switches between two custom profiles exactly", function()
                local world = world_for(surface, { T, T2 })
                world.mod:set(A, true, true)
                world.mod:set(T, true, true)
                with_order(order, function()
                    H.equal(world.view:_profile_ensure(world.category), true)
                    switch(world, 2)
                end)
                world.mod:set(ENSRICK, true, true)
                expect(world, { [A] = true, [B] = true, [T] = false, [ENSRICK] = true }, label .. " profile 2 preset")
                with_order(order, function()
                    world.view:_profile_capture(world.category)
                    switch(world, 1)
                end)
                expect(world, { [A] = true, [B] = false, [T] = true, [T2] = false,
                    [ENSRICK] = false, [TOURNEY] = false, [ALL] = false }, label .. " back to profile 1")
                with_order(order, function() switch(world, 2) end)
                expect(world, { [A] = true, [B] = true, [T] = false, [T2] = false,
                    [ENSRICK] = true, [TOURNEY] = false }, label .. " back to profile 2")
            end)

            H.test("CRT #1575 " .. label .. " Tourney career preset replay keeps a partial career", function()
                local world = world_for(surface, catalog.LEAF_IDS, true)
                world.mod:set(huntsman[1], true, true)
                H.equal(world.state[HUNTSMAN], false)
                with_order(order, function()
                    H.equal(world.view:_profile_ensure(world.category), true)
                    switch(world, 2)
                    switch(world, 1)
                end)
                expect(world, { [huntsman[1]] = true, [huntsman[2]] = false, [HUNTSMAN] = false }, label)
            end)

            H.test("CRT #1575 " .. label .. " automatic additions keep a partial career", function()
                local world = world_for(surface, catalog.LEAF_IDS, true)
                world.mod:set(huntsman[1], true, true)
                H.equal(world.view:_profile_ensure(world.category), true)
                local key = world.profiles.slot_key("crt", 1)
                local stored = world.profile_values[key]
                stored[world.profiles.member_key("crt", HUNTSMAN)] = nil
                stored[world.profiles.member_key("crt", ENSRICK)] = nil
                world.view._profile_ready["crt:1"] = nil
                with_order(order, function()
                    H.equal(world.view:_profile_ensure(world.category), true)
                end)
                expect(world, { [huntsman[1]] = true, [HUNTSMAN] = false, [ENSRICK] = false }, label)
            end)

            H.test("CRT #1575 " .. label .. " staged family choice applies once", function()
                local world = world_for(surface, { T })
                world.mod:set(ALL, true, true)
                expect(world, { [A] = true, [T] = true, [ALL] = true }, label .. " all preset")
                world.view:stage_set(world.category, ENSRICK, true)
                world.view:stage_set(world.category, ALL, false)
                with_order(order, function() world.view:apply_pending(world.category) end)
                expect(world, { [A] = true, [B] = true, [T] = false,
                    [ENSRICK] = true, [TOURNEY] = false, [ALL] = false }, label)
            end)

            H.test("CRT #1575 " .. label .. " Apply runs family presets before careers and staged leaves win", function()
                local world = world_for(surface, catalog.LEAF_IDS, true)
                local other = catalog.LEAVES_BY_MASTER.trn_dr_slayer[1]
                -- Ensrick ON clears the rival Tourney family, then Huntsman ON.
                world.view:stage_set(world.category, ENSRICK, true)
                world.view:stage_set(world.category, HUNTSMAN, true)
                with_order(order, function() world.view:apply_pending(world.category) end)
                expect(world, { [A] = true, [B] = true, [huntsman[1]] = true, [huntsman[2]] = true,
                    [other] = false, [ENSRICK] = true, [HUNTSMAN] = true }, label .. " family then career")
                -- Huntsman OFF plus an explicit Huntsman port: the staged port wins.
                world.view:stage_set(world.category, HUNTSMAN, false)
                world.view:stage_set(world.category, huntsman[2], true)
                with_order(order, function() world.view:apply_pending(world.category) end)
                expect(world, { [huntsman[1]] = false, [huntsman[2]] = true, [HUNTSMAN] = false },
                    label .. " career off, staged port on")
            end)
        end
    end

    H.test("CRT #1575 stock single clicks keep their preset commands", function()
        local world = world_for("standalone", catalog.LEAF_IDS, true)
        world.mod:set(ENSRICK, true, true)
        expect(world, { [A] = true, [B] = true, [ENSRICK] = true }, "Ensrick ON")
        world.mod:set(HUNTSMAN, true, true)
        expect(world, { [huntsman[1]] = true, [huntsman[2]] = true, [HUNTSMAN] = true }, "career ON")
        world.mod:set(HUNTSMAN, false, true)
        expect(world, { [huntsman[1]] = false, [huntsman[2]] = false }, "career OFF")
        world.mod:set(ENSRICK, false, true)
        expect(world, { [A] = false, [B] = false, [ENSRICK] = false }, "Ensrick OFF")
    end)

    H.test("CRT #1575 provider classifies before writes and rejects malformed input", function()
        local world = world_for("standalone", catalog.LEAF_IDS, true)
        local api = world.mod.mod_tweaker_settings_owner
        H.equal(api.version, 1)
        world.mod:set(TOURNEY, true, true)
        local pending = { [ENSRICK] = true, [TOURNEY] = true, [ALL] = false, [HUNTSMAN] = false }
        for _, kind in ipairs({ "profile", "reconcile" }) do
            local writes = world.calls.writes
            local plan = api.prepare(pending, { owner_id = "crt", kind = kind })
            for id in pairs(pending) do H.equal(plan.handled[id], true, kind .. " owns " .. id) end
            H.equal(plan.commit(), true)
            expect(world, { [TOURNEY] = true, [ENSRICK] = false, [huntsman[1]] = true },
                kind .. " replay never runs presets")
            H.equal(world.calls.writes, writes, "replay writes nothing when indicators are derived")
        end
        -- Edit: Ensrick ON is a command, Tourney ON and All OFF are no-ops, and
        -- Huntsman OFF is a command that runs after the family preset.
        local plan = api.prepare(pending, { owner_id = "crt", kind = "edit" })
        H.equal(plan.commit(), true)
        expect(world, { [A] = true, [B] = true, [huntsman[1]] = false, [huntsman[2]] = false,
            [ENSRICK] = true, [TOURNEY] = false, [HUNTSMAN] = false }, "edit commands")
        H.equal(pcall(api.prepare, { [ENSRICK] = "false" }, { owner_id = "crt", kind = "profile" }), false)
        H.equal(pcall(api.prepare, pending, { owner_id = "other", kind = "profile" }), false,
            "a foreign transaction is still rejected")
        H.equal(api.prepare({ [A] = true }, { owner_id = "crt", kind = "edit" }), nil,
            "leaf-only Applies keep the ordinary notification path")
    end)

    H.test("CRT #1575 named runtime check covers every indicator without player writes", function()
        local world = world_for("standalone", catalog.LEAF_IDS, true)
        H.equal(#world.mod._crt.profile_family_ids, 3)
        H.equal(#world.mod._crt.profile_career_ids, #catalog.MASTER_IDS)
        local source = assert(io.open(repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/_crt_regression.lua", "rb"))
        local text = source:read("*a")
        source:close()
        local first = assert(text:find('_rt_register("issue1575_profile_indicator_owner", function()', 1, true))
        local finish = assert(text:find("-- #1575 profile-indicator check end", first, true))
        local check
        local chunk = assert(loadstring(text:sub(first, finish - 1), "@issue1575-runtime-check"))
        setfenv(chunk, setmetatable({ mod = world.mod,
            _rt_register = function(_, callback) check = callback end }, { __index = _G }))
        chunk()
        local writes = world.calls.writes
        H.equal(check(), nil)
        H.equal(world.calls.writes, writes, "the runtime check never writes player settings")
    end)
end
