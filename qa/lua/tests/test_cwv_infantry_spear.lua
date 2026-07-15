return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_infantry_spear.lua")

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("CWV #596 Infantry Spear balance contract is exact and orthogonal", function()
        H.equal(policy.SPEED_MULT, 0.85)
        H.equal(policy.DAMAGE_MULT, 1.075)
        H.equal(policy.STAGGER_MULT, 1.15)
        H.equal(policy.CLEAVE_MULT, 1.15)
        H.truthy(math.abs(policy.scaled_attack_time("sweep", 0.85) - 0.7225) < 0.000001)
        H.equal(policy.scaled_attack_time("melee_start", nil), 0.85)
        H.equal(policy.scaled_attack_time("push_stagger", nil), nil)
        H.equal(policy.scaled_attack_time("block", 1.2), 1.2)
    end)

    H.test("CWV #596 legacy template careers remain migration-compatible", function()
        H.equal(#policy.DEFAULT_CAREERS, 3)
        H.equal(#policy.ALL_CAREERS, 20)
        local defaults = policy.default_career_set()
        H.equal(defaults.es_mercenary, true)
        H.equal(defaults.es_huntsman, true)
        H.equal(defaults.es_knight, true)
        H.equal(defaults.es_questingknight, nil)
        local conditional = policy.conditional_careers()
        H.equal(#conditional, 17)
    end)

    H.test("CWV #596 Infantry Spear production wiring clones only direct hit profiles", function()
        local path = repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
        local source = read(path)
        H.truthy(source:find('Weapons.two_handed_spears_elf_template_1', 1, true))
        H.truthy(source:find('sub_action.damage_profile = _clone_damage_profile(', 1, true))
        H.truthy(source:find('"cwv_infantry_spear_"', 1, true))
        H.truthy(source:find('infantry.scaled_attack_time', 1, true))
        H.equal(source:find('damage_profile_inner = _clone_damage_profile', 1, true), nil)
        H.equal(source:find('damage_profile_outer = _clone_damage_profile', 1, true), nil)
    end)

    H.test("CWV #620 moves shield-free spear meshes onto native Tuskgor Spear", function()
        H.equal(#policy.SPEAR_SHIELD_SKINS, 7)
        local source = read(repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua")
        H.truthy(source:find('right_hand_unit = source.right_hand_unit', 1, true))
        H.truthy(source:find('local target_item = "es_2h_heavy_spear"', 1, true))
        H.truthy(source:find('local target_combo = "es_2h_heavy_spear_skins"', 1, true))
        H.truthy(source:find('local skin_key = "cwv_tuskgor_spear_"', 1, true))
        H.truthy(source:find('cwv_retired     = true', 1, true))
        H.truthy(source:find('tuskgor.can_wield[#tuskgor.can_wield + 1] = "es_knight"', 1, true))
    end)
end
