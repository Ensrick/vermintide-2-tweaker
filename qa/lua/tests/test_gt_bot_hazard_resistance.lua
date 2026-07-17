return function(H, repo_root)
    local root = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/"
    local policy = dofile(root .. "_gt_bot_hazard_resistance_policy.lua")

    local function read(name)
        local f = assert(io.open(root .. name, "rb"))
        local value = f:read("*a")
        f:close()
        return value
    end

    H.test("GT #488 hazard classifier is exact and type-specific", function()
        H.equal(policy.classify("skaven_poison_wind_globadier", "damage_over_time"), "gas")
        H.equal(policy.classify("anything", "gas"), "gas")
        H.equal(policy.classify("skaven_warpfire_thrower", "warpfire_ground"), "warpfire")
        H.equal(policy.classify("skaven_stormfiend", "warpfire_face"), "warpfire")
        H.equal(policy.classify("lamp_oil_fire", "burn"), nil)
    end)

    H.test("GT #488 stacks reduce only subsequent hits and cap at immunity", function()
        local state = {}
        local damage, before, after = policy.apply_hit(state, "gas", 10, 0)
        H.equal(damage, 10)
        H.equal(before, 0)
        H.equal(after, 1)
        for expected = 1, 4 do
            damage, before, after = policy.apply_hit(state, "gas", 10, expected * 0.1)
            H.equal(before, expected)
            H.equal(damage, 10 * (1 - expected * 0.2))
        end
        damage, before, after = policy.apply_hit(state, "gas", 10, 0.6)
        H.equal(before, 5)
        H.equal(after, 5)
        H.equal(damage, 0)
    end)

    H.test("GT #488 gas and warpfire ledgers expire independently", function()
        local state = {}
        policy.apply_hit(state, "gas", 10, 0)
        policy.apply_hit(state, "warpfire", 10, 1)
        local gas, gas_before = policy.apply_hit(state, "gas", 10, 2)
        local fire, fire_before = policy.apply_hit(state, "warpfire", 10, 2)
        H.equal(gas_before, 0)
        H.equal(gas, 10)
        H.equal(fire_before, 1)
        H.equal(fire, 8)
    end)

    H.test("GT #488 production composes singleton damage and cover hooks", function()
        local main = read("general_tweaker_dev.lua") .. read("_gt_regression_checks.lua")
        local hazard = read("_gt_bot_hazard_resistance.lua")
        local combat = read("_gt_improved_bot_combat.lua")
        H.truthy(main:find("_gt488_scale_bot_hazard_damage", 1, true))
        H.truthy(main:find("issue488_bot_improvement_families", 1, true))
        H.equal(hazard:find("mod:hook", 1, true), nil)
        H.equal(hazard:find("network_send", 1, true), nil)
        H.truthy(combat:find("ratling-shield", 1, true))
        H.truthy(combat:find("SHIELD_PROBE_CAP = 12", 1, true))
        H.truthy(combat:find("mutation=0", 1, true))
    end)
end
