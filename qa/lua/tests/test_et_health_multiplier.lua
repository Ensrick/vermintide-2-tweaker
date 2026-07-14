return function(H, repo_root)
    local core_path = repo_root
        .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_health_multiplier_core.lua"
    local Core = assert(loadfile(core_path))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        return content
    end

    H.test("Enemy Tweaker health multiplier has bounded numeric settings", function()
        local data = read(repo_root .. "/enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker_data.lua")
        H.truthy(data:find('setting_key%(diff.key, "health_multiplier"%)'))
        H.truthy(data:find('range%s*=%s*{%s*0%.1,%s*5%.0%s*}'))
        H.truthy(data:find('default_value%s*=%s*1%.0'))
        H.truthy(data:find('decimals_number%s*=%s*1'))
    end)

    H.test("Enemy Tweaker health multiplier clamps invalid values", function()
        H.equal(Core.sanitize_multiplier(nil), 1)
        H.equal(Core.sanitize_multiplier("2.5"), 2.5)
        H.equal(Core.sanitize_multiplier(-4), 0.1)
        H.equal(Core.sanitize_multiplier(99), 5.0)
        H.equal(Core.sanitize_multiplier(0 / 0), 1)
    end)

    H.test("Enemy Tweaker health multiplier targets hostile AI but not pets", function()
        H.truthy(Core.is_hostile_breed({ race = "skaven", boss = true }))
        H.truthy(Core.is_hostile_breed({ race = "undead", unit_template = "ai_unit" }))
        H.equal(Core.is_hostile_breed({ race = "undead", pet_skeleton_type = "tank" }), false)
        H.equal(Core.is_hostile_breed({ race = "undead", unit_template = "ai_unit_pet_skeleton" }), false)
        H.equal(Core.is_hostile_breed({ race = "critter" }), false)
        H.equal(Core.is_hostile_breed({ race = "hero" }), false)
    end)

    H.test("Enemy Tweaker live rescale preserves damage percentage", function()
        H.equal(Core.scaled_max_health(100, 2), 200)
        H.equal(Core.rescaled_damage(100, 25, 200), 50)
        H.equal(Core.rescaled_damage(90, 30, 100), 33.25)
        H.equal(Core.rescaled_damage(100, 120, 50), 50)
    end)

    H.test("Enemy Tweaker health scaling uses one host-authoritative extension hook", function()
        local runtime = read(repo_root .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_health_multiplier.lua")
        local _, hooks = runtime:gsub('mod:hook%("GenericHealthExtension", "init"', "")
        H.equal(hooks, 1)
        H.truthy(runtime:find("Managers.player.is_server", 1, true))
        H.truthy(runtime:find("set_server_damage_taken", 1, true))
        H.equal(runtime:find("Breeds[", 1, true), nil)
    end)
end
