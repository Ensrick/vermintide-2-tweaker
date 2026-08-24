return function(H, repo_root)
    local mod_root = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants"
    local path = mod_root .. "/_cwv_diag_smoke_bomb.lua"
    local old_path = mod_root .. "/_cwv_smoke_bomb_probe.lua"
    local entry_path = mod_root .. "/character_weapon_variants.lua"
    local lifecycle_path = mod_root .. "/_cwv_commands_lifecycle.lua"
    local regression_path = mod_root .. "/_cwv_regression_render.lua"
    local Probe = assert(loadfile(path))()

    local function read(source_path)
        local file = assert(io.open(source_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_literal(source, needle)
        local count = 0
        local cursor = 1
        while true do
            local found = source:find(needle, cursor, true)
            if not found then return count end
            count = count + 1
            cursor = found + #needle
        end
    end

    H.test("CWV smoke bomb probe classifies complete runtime prerequisites", function()
        local result = Probe.classify({
            grenade_template = true,
            grenade_projectile = true,
            ranger_template = true,
            ranger_item = true,
            smoke_explosion = true,
            ranger_area_buff = true,
            buff_area_position_contract = true,
            pool_count = 4,
            pool_sum = 1,
        })
        H.truthy(result.base_ready)
        H.truthy(result.area_ready)
        H.truthy(result.pool_healthy)
        H.equal(result.exact_z_scale_ready, false)
        H.truthy(result.registration_quarantined)
        H.equal(result.status, "runtime_prereqs_ready_exact_fx_and_registration_blocked")
    end)

    H.test("CWV smoke bomb probe rejects malformed pickup pool", function()
        local result = Probe.classify({ pool_count = 2, pool_sum = 0.5 })
        H.equal(result.base_ready, false)
        H.equal(result.area_ready, false)
        H.equal(result.pool_healthy, false)
        H.equal(result.status, "runtime_prereq_missing")
    end)

    H.test("CWV smoke bomb probe is observation-only and bounded", function()
        local source = read(path)
        H.equal(Probe.MAX_RUNS, 3)
        H.equal(type(Probe.auto_run), "function")
        H.equal(source:find("rawset", 1, true), nil)
        H.equal(source:find("spawn_network_unit", 1, true), nil)
        H.equal(source:find(":add_buff(", 1, true), nil)
        H.equal(source:find("NetworkLookup.", 1, true), nil)
    end)

    H.test("CWV smoke bomb diagnostic has one role-owned runtime consumer", function()
        local old = io.open(old_path, "rb")
        if old then old:close() end
        H.equal(old, nil, "legacy probe path must stay absent")

        local entry = read(entry_path)
        H.equal(count_literal(entry,
            'mod:dofile("scripts/mods/character_weapon_variants/_cwv_diag_smoke_bomb")'), 1)
        H.equal(count_literal(entry, "mod._cwv_smoke_bomb_probe.install(mod)"), 1)

        local lifecycle = read(lifecycle_path)
        H.equal(count_literal(lifecycle, "mod._cwv_smoke_bomb_probe.auto_run(mod)"), 1)

        local regression = read(regression_path)
        H.equal(count_literal(regression,
            '_rt_register("issue343_smoke_bomb_diagnostics"'), 1)

        local diagnostic = read(path)
        H.equal(count_literal(diagnostic, "[cwv:343] status=%s"), 1)
        H.equal(count_literal(diagnostic, 'mod:command("cwv_smoke_bomb_probe"'), 1)
    end)
end
