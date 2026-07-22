return function(H, repo_root)
    local path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()

    local function occurrences(needle)
        local count, at = 0, 1
        while true do
            local found = source:find(needle, at, true)
            if not found then return count end
            count = count + 1
            at = found + #needle
        end
    end

    local function load_runtime_predicate()
        local body = assert(source:match(
            "mod%._ct_backfill_rank8_max_health%s*=%s*(function%(mh%).-\nend)"),
            "could not extract the exact #470 runtime predicate")
        return assert(loadstring("return " .. body))()
    end

    H.test("CT #470 exact runtime predicate repairs only a missing rank 8", function()
        local backfill = load_runtime_predicate()
        local sparse = { [2] = 30, [3] = 40, [4] = 50, [5] = 70, [6] = 120, [7] = 150 }

        H.truthy(backfill(sparse))
        H.equal(sparse[8], 150)
        H.equal(sparse[6], 120)
        H.equal(sparse[7], 150)
        H.equal(backfill(sparse), false, "a second pass must not mutate again")
    end)

    H.test("CT #470 exact runtime predicate preserves complete and unknown shapes", function()
        local backfill = load_runtime_predicate()
        local complete = { [7] = 150, [8] = 175 }
        local no_rank7 = { [6] = 120 }
        local zero_rank8 = { [7] = 150, [8] = 0 }

        H.equal(backfill(complete), false)
        H.equal(complete[8], 175)
        H.equal(backfill(no_rank7), false)
        H.equal(no_rank7[8], nil)
        H.equal(backfill(zero_rank8), false)
        H.equal(zero_rank8[8], 0)
        H.equal(backfill(nil), false)
        H.equal(backfill("not-a-table"), false)
    end)

    H.test("CT #470 repair remains a singleton unconditional post-initialize hook", function()
        local predicate_at = assert(source:find(
            "mod._ct_backfill_rank8_max_health = function(mh)", 1, true))
        local hook_needle = 'mod:hook_safe("MutatorHandler", "initialize_mutators"'
        local hook_at = assert(source:find(hook_needle, 1, true))
        local hook_end = assert(source:find("\nend)", hook_at, true))
        local hook_body = source:sub(hook_at, hook_end)

        H.equal(occurrences(hook_needle), 1)
        H.truthy(hook_at > predicate_at, "hook must consume the already-defined predicate")
        H.truthy(hook_body:find("Breeds and Breeds.curse_mutator_sorcerer", 1, true))
        H.truthy(hook_body:find("mod._ct_backfill_rank8_max_health(mh)", 1, true))
        H.truthy(hook_body:find("[ct:470] backfilled curse_mutator_sorcerer.max_health[8]=150", 1, true))
        H.equal(hook_body:find("mod:get(", 1, true), nil,
            "never-crash repair must not depend on a feature toggle")
    end)

    H.test("CT #470 targeted loader vocabulary stays reachable", function()
        local loader_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_dev_mission.lua"
        local catalog_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_dev_mission_catalog.lua"
        local loader_file = assert(io.open(loader_path, "rb"))
        local loader = loader_file:read("*a")
        loader_file:close()
        local catalog_file = assert(io.open(catalog_path, "rb"))
        local catalog = catalog_file:read("*a")
        catalog_file:close()

        H.truthy(catalog:find('"curse_skulking_sorcerer"', 1, true))
        H.truthy(catalog:find('"cataclysm_3"', 1, true))
        H.truthy(loader:find('mod:command("ct_load_mission"', 1, true))
        H.truthy(loader:find("Cat.compose_level_key(base, selected_curse", 1, true))
        H.truthy(loader:find("difficulty = (difficulty ~= \"\" and difficulty) or nil", 1, true))
    end)
end
