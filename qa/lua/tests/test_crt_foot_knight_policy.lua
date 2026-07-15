return function(H, repo_root)
    local path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_crt_foot_knight_policy.lua"
    local Policy = assert(loadfile(path))()

    H.test("CRT #619 shield capability includes cloned shield templates", function()
        H.equal(Policy.is_shield_type("AXE_1H_SHIELD"), true)
        H.equal(Policy.is_shield_type("MACE_1H_SHIELD"), true)
        H.equal(Policy.is_shield_type("SPEAR_1H_SHIELD"), true)
        H.equal(Policy.is_shield_type("FLAIL_1H", "one_handed_flail_shield_template"), true)
        H.equal(Policy.is_shield_type("MACE_1H", "cwv_dawi_mace_shield_template"), true)
        H.equal(Policy.is_shield_type("AXE_1H"), false)
    end)

    H.test("CRT #619 great capability excludes polearms", function()
        H.equal(Policy.is_non_polearm_great_type("AXE_2H"), true)
        H.equal(Policy.is_non_polearm_great_type("MACE_2H"), true)
        H.equal(Policy.is_non_polearm_great_type("SWORD_2H"), true)
        H.equal(Policy.is_non_polearm_great_type("PICK_2H"), true)
        H.equal(Policy.is_non_polearm_great_type("MACE_2H", "staff_scythe"), false)
        H.equal(Policy.is_non_polearm_great_type("AXE_2H", "two_handed_glaive_template"), false)
        H.equal(Policy.is_non_polearm_great_type("SPEAR_2H"), false)
        H.equal(Policy.is_non_polearm_great_type("HALBERD_2H"), false)
    end)

    H.test("CRT #619 category damage composes and caps allies", function()
        H.equal(Policy.enemy_multiplier(true, false, 0, { boss = true, armor_category = 3 }), 1.3)
        H.equal(Policy.enemy_multiplier(true, false, 0, { armor_category = 5 }), 1.3)
        H.equal(Policy.enemy_multiplier(false, true, 2, { armor_category = 2 }), 1.2)
        H.equal(Policy.enemy_multiplier(false, true, 8, { armor_category = 6 }), 1.3)
        H.equal(Policy.enemy_multiplier(false, true, 3, { armor_category = 5 }), 1)
        H.truthy(math.abs(Policy.enemy_multiplier(true, true, 3,
            { boss = true, armor_category = 3 }) - 1.69) < 0.000001)
    end)

    H.test("CRT #619 secondary melee owns only its inserted slot member", function()
        local enabled, owns = Policy.plan_secondary_slot({ "ranged" }, true, false)
        H.deep_equal(enabled, { "melee", "ranged" })
        H.equal(owns, true)

        local repeated
        repeated, owns = Policy.plan_secondary_slot(enabled, true, owns)
        H.deep_equal(repeated, { "melee", "ranged" })
        H.equal(owns, true)

        local disabled
        disabled, owns = Policy.plan_secondary_slot(repeated, false, owns)
        H.deep_equal(disabled, { "ranged" })
        H.equal(owns, false)

        local shared
        shared, owns = Policy.plan_secondary_slot({ "ranged", "melee" }, false, false)
        H.deep_equal(shared, { "ranged", "melee" })
        H.equal(owns, false)
    end)

    H.test("CRT #619 Final March distinguishes dead from disabled allies", function()
        H.equal(Policy.all_other_allies_dead({}), false)
        H.equal(Policy.all_other_allies_dead({ true, true, true }), true)
        H.equal(Policy.all_other_allies_dead({ true, false, true }), false)
    end)

    H.test("CRT #619 production composes the singleton damage hook", function()
        local path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_armor_overcharge.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local count = 0
        for _ in source:gmatch('mod:hook%(DamageUtils, "apply_buffs_to_damage"') do
            count = count + 1
        end
        H.equal(count, 1)
        H.truthy(source:find("fk.outgoing_damage_multiplier", 1, true))

        local foot_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/_crt_foot_knight.lua"
        local foot_file = assert(io.open(foot_path, "rb"))
        local foot_source = foot_file:read("*a")
        foot_file:close()
        H.truthy(foot_source:find('BUFF_ROCK_DODGE', 1, true))
        H.truthy(foot_source:find('multiplier = 0.90', 1, true))
        H.truthy(foot_source:find('BUFF_TEAMWORK_DR_CANCEL', 1, true))
        H.truthy(foot_source:find('multiplier = 0.10', 1, true))
        H.truthy(foot_source:find('markus_knight_passive_damage_reduction', 1, true))

        local balance_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua"
        local balance_file = assert(io.open(balance_path, "rb"))
        local balance_source = balance_file:read("*a")
        balance_file:close()
        H.truthy(balance_source:find('{ buff = "markus_knight_passive",                 field = "range", value = 10 }', 1, true))
        H.truthy(balance_source:find('{ buff = "markus_knight_passive_block_cost_aura", field = "range", value = 20 }', 1, true))
        H.truthy(balance_source:find('{ buff = "markus_knight_passive_range",           field = "range", value = 20 }', 1, true))
    end)
end
