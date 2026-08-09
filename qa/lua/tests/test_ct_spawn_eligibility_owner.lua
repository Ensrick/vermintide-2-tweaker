-- Boundary test for the #1159 ct_dev spawn-eligibility owner extraction.
-- Engine-free: asserts the structural contract of the split (ownership, wiring
-- position, and the getter seam that preserves per-run telemetry resets).
return function(H, repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"

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

    local entry = read("chaos_wastes_tweaker_dev.lua")
    local owner = read("_ct_spawn_eligibility_owner.lua")

    H.test("spawn-eligibility owner is dofile'd exactly once by the entry", function()
        H.equal(count_plain(entry,
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_spawn_eligibility_owner"), 1)
    end)

    H.test("the _can_spawn hook lives only in the owner", function()
        -- Exactly one PickupSystem._can_spawn hook in the mod, and it is the
        -- owner's. A second hook anywhere would violate the VMF duplicate-hook
        -- rule and silently shadow this one.
        H.equal(count_plain(owner, 'mod:hook("PickupSystem", "_can_spawn"'), 1)
        H.equal(count_plain(entry, 'mod:hook("PickupSystem", "_can_spawn"'), 0)
    end)

    H.test("coin-reservation helpers moved wholesale, none left behind", function()
        for _, sym in ipairs({
            "_COIN_RESERVED_FRACTION",
            "_coin_reservation_hash_reserved",
            "_coin_reserved_units",
            "_rebuild_coin_reserved_set",
            "_spawner_reserved_for_coins",
            "_pickup_unit_loadable",
        }) do
            H.equal(count_plain(entry, "local " .. sym), 0,
                sym .. " must no longer be an entry local")
            H.truthy(owner:find(sym, 1, true), sym .. " must live in the owner")
        end
    end)

    H.test("the mod._ct_ public surface is preserved by the owner", function()
        -- These four fields are read by the populate_pickups hook (defined EARLIER
        -- in the entry) and by the coin_reservation_partition regression marker.
        -- The owner must keep assigning all four under their original names.
        for _, field in ipairs({
            "mod._ct_coin_reservation_test",
            "mod._ct_rebuild_coin_reserved_set",
            "mod._ct_clear_coin_reserved_set",
            "mod._ct_spawner_reserved_for_coins",
        }) do
            H.equal(count_plain(owner, field .. " ="), 1, field .. " assigned by owner")
        end
        -- The consumers stayed in the entry and still reference them.
        H.truthy(entry:find("mod._ct_rebuild_coin_reserved_set", 1, true))
        H.truthy(entry:find("mod._ct_coin_reservation_test", 1, true))
    end)

    H.test("install runs AFTER the populate_pickups hook that calls into it", function()
        -- mod._ct_rebuild_coin_reserved_set is resolved at CALL time, so the owner
        -- may install later in the script body -- but it must still install during
        -- the body, i.e. after the populate hook's definition and before any hook
        -- can fire. Locking the relative order keeps a future reorder honest.
        local populate_at = assert(entry:find("mod._ct_rebuild_coin_reserved_set({", 1, true))
        local install_at = assert(entry:find(
            "mods/chaos_wastes_tweaker_dev/_ct_spawn_eligibility_owner", 1, true))
        H.truthy(populate_at < install_at,
            "populate_pickups consumer must be defined before the owner installs")
    end)

    H.test("per-run telemetry is passed as getters, never as captured tables", function()
        -- The entry REASSIGNS these two tables to fresh {} at every populate_pickups
        -- entry (run boot). If ctx handed the owner the table VALUES, the owner would
        -- pin the load-time tables: denial counts would accumulate across runs and the
        -- once-per-run log gate would never reset. Assert the getter seam on both ends.
        H.truthy(entry:find(
            "get_denial_counts           = function() return _career_exclusive_denial_counts end",
            1, true), "entry must wire denial counts as a getter")
        H.truthy(entry:find(
            "get_logged_this_run         = function() return _career_exclusive_logged_this_run end",
            1, true), "entry must wire the log gate as a getter")
        -- The owner must CALL them per hook invocation, not hoist them at install.
        H.equal(count_plain(owner, "local denial_counts = get_denial_counts()"), 1)
        H.equal(count_plain(owner, "local logged_this_run = get_logged_this_run()"), 1)
        -- And it must never bind them to install-scope locals.
        H.equal(count_plain(owner, "local get_denial_counts           = ctx.get_denial_counts"), 1)
        H.equal(count_plain(owner, "= ctx.get_denial_counts()"), 0)
        H.equal(count_plain(owner, "= ctx.get_logged_this_run()"), 0)
    end)

    H.test("owner is a pure ctx-keyed installer with no command surface", function()
        H.truthy(owner:find("function M.install(ctx)", 1, true))
        H.truthy(owner:find("return M", 1, true))
        -- Commands and lifecycle callbacks stay in the entry.
        H.equal(count_plain(owner, "mod:command"), 0)
        H.equal(count_plain(owner, "mod.on_setting_changed"), 0)
        H.equal(count_plain(owner, "mod.on_disabled"), 0)
    end)
end
