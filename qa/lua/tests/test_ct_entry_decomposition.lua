return function(H, repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")

    local function read(name)
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    local entry = CTSource.entry(repo_root)
    local expanded = CTSource.expanded(repo_root)
    local regression = read("_ct_regression.lua")
    local owners = {
        host = read("_ct_host_state_transport_owner.lua"),
        run = read("_ct_run_runtime_owner.lua"),
        adventure = read("_ct_adventure_runtime_owner.lua"),
        boon = read("_ct_boon_runtime_owner.lua"),
        lifecycle = read("_ct_settings_lifecycle_owner.lua"),
    }

    H.test("CT completion owners parse as Lua 5.1 installers", function()
        for _, name in ipairs({
            "_ct_host_state_transport_owner.lua",
            "_ct_run_runtime_owner.lua",
            "_ct_adventure_runtime_owner.lua",
            "_ct_boon_runtime_owner.lua",
            "_ct_settings_lifecycle_owner.lua",
        }) do
            local installer = assert(loadfile(root .. name))()
            H.equal(type(installer), "function", name .. " must return an installer")
        end
    end)

    H.test("CT Dev entry reaches and retains the structural completion ceiling", function()
        local lines = 0
        for line in entry:gmatch("[^\r\n]+") do
            if line:match("%S") then lines = lines + 1 end
        end
        H.truthy(lines <= 1498,
            "CT Dev entry exceeded the frozen 1498-line completion ceiling")

        for name, source in pairs(owners) do
            local owner_lines = 0
            for line in source:gmatch("[^\r\n]+") do
                if line:match("%S") then owner_lines = owner_lines + 1 end
            end
            H.truthy(owner_lines < 1500,
                name .. " owner exceeded the 1500-line owner ceiling")
        end
    end)

    H.test("CT completion owners install exactly once in preserved runtime order", function()
        local ordered = {
            "_ct_host_state_transport_owner",
            "_ct_peer_manifest_owner",
            "_ct_run_runtime_owner",
            "_ct_adventure_runtime_owner",
            "_ct_boon_runtime_owner",
            "_ct_settings_lifecycle_owner",
            "_ct_regression",
            "_ct_mechanic_tweaks",
        }
        local previous = 0
        for _, name in ipairs(ordered) do
            H.equal(count_plain(entry,
                "scripts/mods/chaos_wastes_tweaker_dev/" .. name), 1,
                name .. " must have one entry install")
            local at = assert(entry:find(name, previous + 1, true),
                name .. " is missing from the entry")
            H.truthy(previous < at, name .. " moved across a runtime boundary")
            previous = at
        end
    end)

    H.test("CT virtual source conserves registration cardinality", function()
        -- These are the exact pre-extraction entry counts. The expanded view
        -- inserts each completion owner at its real installer position.
        H.equal(count_plain(expanded, "mod:hook("), 17)
        H.equal(count_plain(expanded, "mod:hook_safe("), 5)
        H.equal(count_plain(expanded, "mod:network_register("), 2)
        H.equal(count_plain(expanded, "_rt_register("), 24)
        H.equal(count_plain(regression, "_rt_register("), 71)

        H.equal(count_plain(owners.host, "_rt_register("), 4)
        H.equal(count_plain(owners.run, "_rt_register("), 0)
        H.equal(count_plain(owners.adventure, "_rt_register("), 1)
        H.equal(count_plain(owners.boon, "_rt_register("), 10)
        H.equal(count_plain(owners.lifecycle, "_rt_register("), 1)
        H.equal(count_plain(entry, "_rt_register("), 8)
    end)

    H.test("CT completion boundaries preserve live mutable slots", function()
        H.truthy(entry:find("local sync_host_dependent_state", 1, true))
        H.truthy(entry:find(
            "if sync_host_dependent_state then return sync_host_dependent_state(...) end",
            1, true))
        H.truthy(owners.host:find(
            "local sync_host_dependent_state = ctx.sync_host_dependent_state",
            1, true))

        H.equal(count_plain(entry,
            "local _defeat_recovery_triggered_this_round = false"), 1)
        H.equal(count_plain(entry,
            "if value ~= nil then _defeat_recovery_triggered_this_round = value end"), 2)
        H.equal(count_plain(owners.run,
            "defeat_recovery_triggered = ctx.defeat_recovery_triggered,"), 1)
        H.equal(count_plain(owners.boon,
            "defeat_recovery_triggered = ctx.defeat_recovery_triggered,"), 1)
        H.equal(count_plain(owners.run,
            "local _defeat_recovery_triggered_this_round"), 0)
        H.equal(count_plain(owners.boon,
            "local _defeat_recovery_triggered_this_round"), 0)

        H.equal(count_plain(entry,
            "local _starting_coins_applied_for_run"), 1)
        H.equal(count_plain(owners.run,
            "local _starting_coins_applied_for_run"), 0)
        H.truthy(owners.run:find(
            "starting_coins_applied_for_run = ctx.starting_coins_applied_for_run",
            1, true))
    end)

    H.test("CT completion owners expose every entry continuation explicitly", function()
        for _, marker in ipairs({
            "host_sync_received = function() return _ct_host_sync_received end",
            "host_graph_snapshot = function() return _ct_host_graph_snapshot end",
            "collect_setting_ids = _collect_setting_ids",
            "enqueue_chunk = _ct_enqueue_chunk",
        }) do
            H.truthy(owners.host:find(marker, 1, true), marker)
        end
        H.truthy(entry:find(
            "return _ct_host_transport.host_sync_received() and", 1, true))

        H.truthy(owners.run:find(
            "is_curse_disabled = is_curse_disabled", 1, true))
        H.truthy(entry:find(
            "is_curse_disabled = _ct_run_runtime.is_curse_disabled", 1, true))

        for _, marker in ipairs({
            "adventure_incompatible_pack_mutators = ADVENTURE_INCOMPATIBLE_PACK_MUTATORS",
            "dump_pickup_spawners_verbose = _dump_pickup_spawners_verbose",
            "dump_pickup_system_state = _dump_pickup_system_state",
            "on_injected_adventure_level = on_injected_adventure_level",
        }) do
            H.truthy(owners.adventure:find(marker, 1, true), marker)
        end
        H.truthy(entry:find(
            "_ct_adventure_runtime.adventure_incompatible_pack_mutators", 1, true))

        H.truthy(owners.boon:find(
            "sync_grudge_marks = sync_grudge_marks", 1, true))
        H.truthy(entry:find(
            "local sync_grudge_marks = _ct_boon_runtime.sync_grudge_marks", 1, true))

        for _, marker in ipairs({
            "sync_bomb_cooldown = sync_bomb_cooldown",
            "sync_boon_movespeed = sync_boon_movespeed",
            "sync_host_dependent_state = sync_host_dependent_state",
            "sync_reckless_swings = sync_reckless_swings",
            "sync_ulric_pack_unlimited_range = sync_ulric_pack_unlimited_range",
        }) do
            H.truthy(owners.lifecycle:find(marker, 1, true), marker)
        end
    end)

    H.test("CT lifecycle callbacks have one explicit owner", function()
        for _, callback in ipairs({
            "mod.on_setting_changed = function",
            "mod.on_disabled = function",
        }) do
            H.equal(count_plain(entry, callback), 0)
            H.equal(count_plain(owners.lifecycle, callback), 1)
            H.equal(count_plain(regression, callback), 0)
        end
        H.equal(count_plain(owners.lifecycle,
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_combat_hooks"), 1)
        local lifecycle_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_settings_lifecycle_owner",
            1, true))
        local regression_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_regression", 1, true))
        H.truthy(lifecycle_at < regression_at)
    end)

    H.test("CT regression registry and representative checks remain single-owner", function()
        H.truthy(entry:find("mod._ct_rt_register = _rt_register", 1, true))
        H.truthy(regression:find(
            "local _rt_register = mod._ct_rt_register", 1, true))

        for _, check in ipairs({
            "midrun_setting_rebroadcast_wired",
            "boon_altar_no_repeat",
            "cw_collectible_and_big_casket",
            "coin_reservation_partition",
        }) do
            H.equal(count_plain(owners.host,
                '_rt_register("' .. check .. '"'), 1)
            H.equal(count_plain(entry,
                '_rt_register("' .. check .. '"'), 0)
        end

        H.equal(count_plain(entry,
            '_rt_register("starting_coins_value_matches_setting"'), 1)
        H.equal(count_plain(regression,
            '_rt_register("starting_coins_value_matches_setting"'), 0)
        H.truthy(owners.boon:find(
            'if type(mod._ct_boon_disabled) ~= "function" then', 1, true))
    end)
end
