-- Boundary test for the #1159 ct_dev pickup-spawn owner extraction.
-- Engine-free: asserts the structural contract of the split (hook ownership and
-- cardinality, wiring position, the mod-field seam for the two per-level counters
-- populate_pickups resets, and non-overlap with the sibling spawn-eligibility
-- owner).
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
    local owner = read("_ct_pickup_spawn_owner.lua")
    local eligibility = read("_ct_spawn_eligibility_owner.lua")
    -- #1159 wave 10: populate_pickups and the #58/#156 census moved out of the
    -- entry into their own owner. The gates below follow the code - same needles,
    -- new file - and keep the entry-side absence assertion.
    local population = read("_ct_pickup_population_owner.lua")

    -- The four vanilla seams that decide WHAT a spawn produces. Each is hooked
    -- exactly once in the whole mod; VMF silently drops a second hook on the same
    -- Class/method pair, so a duplicate would shadow the owner without an error.
    local HOOKS = {
        'mod:hook("PickupSystem", "_spawn_pickup"',
        'mod:hook("UnitSpawner", "spawn_network_unit"',
        'mod:hook("PickupSystem", "_spawn_guaranteed_pickup"',
        'mod:hook("GameModeDeus", "_get_coins_amount_and_type"',
    }

    H.test("pickup-spawn owner is dofile'd exactly once by the entry", function()
        H.equal(count_plain(entry,
            'mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_pickup_spawn_owner")'), 1)
        -- Bare dofile, not an installer call: the module body runs at file scope
        -- exactly where the block used to execute, which is what preserves hook
        -- registration order and the load-time marker timing.
        H.equal(count_plain(owner, "function M.install"), 0)
        H.equal(count_plain(owner, 'local mod = get_mod("ct_dev")'), 1)
    end)

    H.test("every moved hook lives only in the owner, exactly once", function()
        for _, head in ipairs(HOOKS) do
            H.equal(count_plain(owner, head), 1, head .. " must be owned once")
            H.equal(count_plain(entry, head), 0, head .. " must not remain in the entry")
            H.equal(count_plain(eligibility, head), 0,
                head .. " must not be duplicated by the eligibility owner")
        end
    end)

    H.test("owner and eligibility owner do not overlap", function()
        -- Eligibility answers "MAY this pickup claim this spawner"; this owner
        -- answers "what does the claimed spawner produce". Neither may hold the
        -- other's hook.
        H.equal(count_plain(owner, 'mod:hook("PickupSystem", "_can_spawn"'), 0)
        H.equal(count_plain(eligibility, 'mod:hook("PickupSystem", "_can_spawn"'), 1)
        -- No shared helper: the coin-reservation partition stays entirely on the
        -- eligibility side.
        for _, sym in ipairs({
            "_COIN_RESERVED_FRACTION",
            "_coin_reservation_hash_reserved",
            "_spawner_reserved_for_coins",
        }) do
            H.equal(count_plain(owner, sym), 0, sym .. " belongs to the eligibility owner")
        end
    end)

    H.test("owner installs BEFORE the spawn-eligibility owner", function()
        -- Registration order is byte-identical to the pre-extraction body only if
        -- the two dofiles keep their original relative position.
        local pickup_at = assert(entry:find(
            'mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_pickup_spawn_owner")', 1, true))
        local elig_at = assert(entry:find(
            "mods/chaos_wastes_tweaker_dev/_ct_spawn_eligibility_owner", 1, true))
        H.truthy(pickup_at < elig_at,
            "pickup-spawn owner must load at its original slot, ahead of eligibility")
    end)

    H.test("moved locals left no orphan behind in the entry", function()
        for _, sym in ipairs({
            "_CW_BLOCKING_PICKUP_NAMES",
            "_CW_COLLECTIBLE_TO_COIN",
        }) do
            H.equal(count_plain(entry, sym), 0, sym .. " must no longer appear in the entry")
            H.truthy(owner:find(sym, 1, true), sym .. " must live in the owner")
        end
        -- The collectible policy is dofile'd by the owner now, and only there.
        H.equal(count_plain(entry,
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_collectible_policy"), 0)
        H.equal(count_plain(owner,
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_collectible_policy"), 1)
    end)

    H.test("per-level counters cross the chunk boundary as mod fields", function()
        -- They were entry file-locals only so the lexically EARLIER
        -- populate_pickups hook could bind them at closure-creation time. With the
        -- reader in a separate chunk that binding cannot reach, so they move onto
        -- `mod`. A surviving `local` declaration would silently split the state:
        -- the entry would reset a local nobody reads while the owner incremented a
        -- nil field.
        for _, sym in ipairs({
            "_chest_conversions_this_level",
            "_belakor_altar_spawned_this_level",
        }) do
            H.equal(count_plain(entry, "local " .. sym), 0,
                sym .. " must not remain an entry local")
            H.equal(count_plain(owner, "local " .. sym), 0,
                sym .. " must not become an owner local either")
        end
        H.equal(count_plain(population, "local " .. "_chest_conversions_this_level"), 0,
            "nor an owner local in the population owner that now holds the reset")
        -- populate_pickups keeps sole ownership of the reset (load-time init +
        -- the per-populate reset); THIS owner never zeroes them. #1159 wave 10
        -- moved populate_pickups into _ct_pickup_population_owner.lua, so the two
        -- resets now live there and the entry must hold neither.
        H.equal(count_plain(population, "mod._ct_chest_conversions_this_level = 0"), 2)
        H.equal(count_plain(population, "mod._ct_belakor_altar_spawned_this_level = false"), 2)
        H.equal(count_plain(entry, "mod._ct_chest_conversions_this_level = 0"), 0)
        H.equal(count_plain(entry, "mod._ct_belakor_altar_spawned_this_level = false"), 0)
        H.equal(count_plain(owner, "mod._ct_chest_conversions_this_level = 0"), 0)
        H.equal(count_plain(owner, "mod._ct_belakor_altar_spawned_this_level = false"), 0)
        -- And the owner does read/advance them.
        H.truthy(owner:find(
            "mod._ct_chest_conversions_this_level = mod._ct_chest_conversions_this_level + 1",
            1, true))
        H.truthy(owner:find("mod._ct_belakor_altar_spawned_this_level = true", 1, true))
    end)

    H.test("load-time provenance markers moved with their hooks", function()
        -- _ct_regression.lua reads these bare as globals; the suite loads later in
        -- the entry, so setting them from this chunk keeps every check green.
        for _, marker in ipairs({
            'CT_MORGRIM143_MARKER = "morgrim143:appearance_by_spawn_type_census_v0.7.212"',
            'CT_MORGRIM143_RENORM_MARKER = "morgrim143:holy_hand_grenade_sum_preserving_renorm_v0.7.232"',
            'CT_PICKUP_RESIDENCY_GUARD_MARKER = "spawn_pickup_can_get_unit_guard_v0.7.222"',
            'CT_SPAWN_PICKUP322_MARKER = "spawn_pickup322:two_value_capture_and_return_v0.7.245"',
        }) do
            H.equal(count_plain(owner, marker), 1, marker .. " must be set by the owner")
            H.equal(count_plain(entry, marker), 0, marker .. " must not be set twice")
        end
    end)

    H.test("the mod._ct_ public surface is preserved by the owner", function()
        -- Read by the entry's regression checks, the #58/#156 census, and
        -- _ct_regression.lua. All must keep their original names.
        for _, field in ipairs({
            "mod._ct_collectible_policy",
            "mod._ct_collectible_to_coin",
            "mod._ct351_rewrite_network_spawn",
            "mod._ct351_log_conversion",
            "mod._ct134_log",
            "mod._ct_morgrim143_count",
            "mod._ct_morgrim143_grenade_tally",
            "mod._ct_pickup_unit_spawn_safe",
        }) do
            H.truthy(owner:find(field, 1, true), field .. " must be published by the owner")
        end
        -- The census tally is resolved at CALL time here, so it keeps working no
        -- matter which chunk defines it. #1159 wave 10 moved the definition out of
        -- the entry into _ct_pickup_population_owner.lua; the entry must not keep a
        -- second copy, and this owner must still reach it only through `mod`.
        H.truthy(population:find("mod._ct_tally_count = function", 1, true))
        H.equal(count_plain(entry, "mod._ct_tally_count = function"), 0)
        H.truthy(owner:find("mod._ct_tally_count(pickup_name, spawned)", 1, true))
    end)

    H.test("owner carries no command or lifecycle surface", function()
        H.equal(count_plain(owner, "mod:command"), 0)
        H.equal(count_plain(owner, "mod.on_setting_changed"), 0)
        H.equal(count_plain(owner, "mod.on_disabled"), 0)
        H.equal(count_plain(owner, "_rt_register("), 0)
    end)
end
