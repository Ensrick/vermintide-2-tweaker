return function(H, repo_root)
    local policy_path = repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_flamestorm_fx_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        return content
    end

    H.test("WT Flamestorm FX targets every non-Sienna receiver", function()
        for _, career in ipairs({
            "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
            "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer",
            "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister",
            "wh_captain", "wh_bountyhunter", "wh_zealot",
        }) do
            H.truthy(Policy.is_target("" .. career, "staff_flamethrower_template"))
        end
    end)

    H.test("WT Flamestorm FX preserves native and unrelated weapons", function()
        H.truthy(not Policy.is_target("bw_adept", "staff_flamethrower_template"))
        H.truthy(not Policy.is_target("bw_scholar", "staff_flamethrower_template"))
        H.truthy(not Policy.is_target("bw_unchained", "staff_flamethrower_template"))
        H.truthy(not Policy.is_target("es_mercenary", "drakegun_template_1"))
        H.truthy(not Policy.is_target(nil, "staff_flamethrower_template"))
    end)

    H.test("WT Flamestorm FX owns both creation and continuous observer seams", function()
        local runtime = read(repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_flamestorm_fx.lua")
        local _, start_hooks = runtime:gsub('safe_hook_safe%("WeaponSystem", "rpc_start_flamethrower"', "")
        local _, update_hooks = runtime:gsub('safe_hook_safe%("WeaponSystem", "update_synced_flamethrower_particle_effects"', "")
        H.equal(start_hooks, 1)
        H.equal(update_hooks, 1)
        H.truthy(runtime:find('game_object_field%(game, unit_id, "aim_direction"%)'))
        H.truthy(runtime:find("Unit.world_position", 1, true))
        H.truthy(runtime:find("Quaternion.look", 1, true))
        H.truthy(runtime:find("World.move_particles", 1, true))
    end)
end
