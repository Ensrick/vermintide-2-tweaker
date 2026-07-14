return function(H, repo_root)
    local path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_crt_damage_classification.lua"
    local Policy = assert(loadfile(path))()

    H.test("CRT Focused Spirit ignores the shared DoT and AOE classes", function()
        local unit = {}
        H.equal(Policy.focused_spirit_ignores(unit, unit, nil, "wounded_dot"), true)
        H.equal(Policy.focused_spirit_ignores({}, unit, "dot_debuff", "burninating"), true)
        H.equal(Policy.focused_spirit_ignores({}, unit, "skaven_poison_wind_globadier", "poison"), true)
        H.equal(Policy.focused_spirit_ignores({}, unit, "skaven_warpfire_thrower", "warpfire_ground"), true)
    end)

    H.test("CRT Focused Spirit identifies Ratling sources without hiding ordinary hits", function()
        local unit = {}
        H.equal(Policy.focused_spirit_ignores({}, unit, "skaven_ratling_gunner", "shot_machinegun"), true)
        H.equal(Policy.focused_spirit_ignores({}, unit, "vs_ratling_gunner", "shot_machinegun"), true)
        H.equal(Policy.focused_spirit_ignores({}, unit, "skaven_storm_vermin", "light_attack"), false)
        H.equal(Policy.focused_spirit_ignores({}, unit, "we_shortbow", "shot_machinegun"), false)
    end)

    H.test("CRT #334 predicates retain their original boundary", function()
        local unit = {}
        H.equal(Policy.is_chip_or_aoe("dot_debuff", "burninating"), true)
        H.equal(Policy.is_self_dot(unit, unit, "wounded_dot"), true)
        H.equal(Policy.is_self_dot({}, unit, "wounded_dot"), false)
        H.equal(Policy.is_chip_or_aoe("skaven_slave", "light_attack"), false)
    end)
end
