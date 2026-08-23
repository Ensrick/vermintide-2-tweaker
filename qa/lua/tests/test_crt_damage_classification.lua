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

    H.test("CRT #472 observes retained transitions and owns the full talent description", function()
        local base = repo_root .. "/career_tweaker/scripts/mods/career_tweaker/"
        local function read(name)
            local f = assert(io.open(base .. name, "rb"))
            local source = f:read("*a"); f:close()
            return source
        end
        local armor = read("career_tweaker_armor_overcharge.lua")
        local balance = require("crt_source").combined(repo_root)
        local loc = read("career_tweaker_localization.lua")

        H.truthy(armor:find("FOCUSED_DIAG_CAP = 48", 1, true))
        H.truthy(armor:find('"[crt:472] event=%s', 1, true))
        H.truthy(armor:find("FocusedSpirit.damage_action", 1, true))
        H.truthy(armor:find("FocusedSpirit.zero_stack_action", 1, true))
        H.truthy(armor:find('"zero_stack_restart_requested"', 1, true))
        H.truthy(armor:find("stacks_after = _focused_stack_count(be)", 1, true))
        H.truthy(balance:find('live_talent.description = policy.VANILLA_DESCRIPTION_KEY', 1, true))
        H.truthy(balance:find("saved.focused_talent_description_values_original", 1, true))
        H.equal(loc:find("crt_kerillian_maidenguard_focused_spirit_stacks_desc", 1, true), nil)
    end)
end
