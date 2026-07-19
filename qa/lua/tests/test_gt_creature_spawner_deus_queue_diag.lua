return function(H, repo_root)
    local path = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_creature_spawner.lua"

    local function read_source()
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("issue 254 diagnostics retain the ConflictDirector queue id", function()
        local source = read_source()
        H.truthy(source:find("local queue_id = conflict_director:spawn_queued_unit", 1, true))
        H.truthy(source:find("_gt_cs_254_track_enqueue(conflict_director, queue_id, breed_name)", 1, true))
        H.truthy(source:find('"get_spawned_unit", nil, queue_id', 1, true))
        H.truthy(source:find("local queued_breed = entry and entry[1]", 1, true))
        H.truthy(source:find("requested_breed_name = breed_name", 1, true))
    end)

    H.test("issue 254 diagnostics classify the known Chaos Wastes queue blockers", function()
        local source = read_source()
        H.truthy(source:find('return "director_disabled"', 1, true))
        H.truthy(source:find('return "conflict_settings_disabled"', 1, true))
        H.truthy(source:find('return "breed_not_processed"', 1, true))
        H.truthy(source:find('return "breed_not_loaded_on_all_peers"', 1, true))
        H.truthy(source:find('return "queue_not_drained"', 1, true))
    end)

    H.test("issue 254 diagnostics are bounded and do not log on every frame", function()
        local source = read_source()
        H.truthy(source:find("local _GT_CS_254_MAX_PENDING = 8", 1, true))
        H.truthy(source:find("local _GT_CS_254_TIMEOUT = 8", 1, true))
        H.truthy(source:find("and not pending.blocker_logged", 1, true))
        H.truthy(source:find("_gt_cs_254_finish(queue_id)", 1, true))
        H.truthy(source:find('printf("[gt:254] phase=%s', 1, true))
        H.truthy(source:find('" result=evicted capacity=8"', 1, true))
        H.truthy(source:find("pending.conflict_director ~= conflict_director", 1, true))
        H.truthy(source:find('" result=director_replaced"', 1, true))
        H.truthy(source:find("local ok, value = pcall(method, target, ...)", 1, true))
        H.truthy(source:find('"is_breed_loaded_on_all_peers", false, breed_name', 1, true))
    end)

    H.test("issue 254 runtime readiness check is registered", function()
        local source = read_source()
        H.truthy(source:find('mod._gt_rt_register("issue254_deus_spawn_queue_diagnostics_armed"', 1, true))
        H.truthy(source:find("mod._gt254_cs_queue_diagnostics_armed = true", 1, true))
    end)
end
