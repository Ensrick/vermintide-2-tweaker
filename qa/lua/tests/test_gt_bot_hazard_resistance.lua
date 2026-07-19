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

    -- #469 bot AOE immunity: BINARY negation for a CURATED hazard list (distinct
    -- from #488's stacking gas/warpfire resistance above). Boss slams, warpfire,
    -- gas, and thrown bombs are DELIBERATELY excluded - gas wants a reduced-not-
    -- zero scalar (separate refinement). The checks execute the shipped tables so
    -- any silent broadening or shrinking of the curation fails here.
    H.test("GT #469 curated AOE immunity tables are exact", function()
        local src = read("general_tweaker_dev.lua")
        local prof_src = src:match("mod%._gt_bot_aoe_immune_profiles%s*=%s*(%b{})")
        local sources_src = src:match("mod%._gt_bot_aoe_immune_sources%s*=%s*(%b{})")
        H.truthy(prof_src, "_gt_bot_aoe_immune_profiles table extraction failed")
        H.truthy(sources_src, "_gt_bot_aoe_immune_sources table extraction failed")
        local profiles = assert(loadstring("return " .. prof_src))()
        local sources = assert(loadstring("return " .. sources_src))()
        -- Exact curation lock: each entry individually cited in source
        -- (explosion_templates.lua:1406/1417, morris_buff_settings.lua:5165-5174
        -- and :5040-5050, liquid_area_damage_templates.lua:768-770).
        H.deep_equal(profiles, {
            heavens_lightning_strike       = "Lightning Strike mutator",
            curse_skulls_of_fury_explosion = "Khorne Skulls of Fury curse",
            bolt_of_change                 = "Bolt of Change curse",
        })
        H.deep_equal(sources, { lamp_oil_fire = "oil-barrel ground fire" })
    end)

    H.test("GT #469 immunity rides the two singleton DamageUtils funnels, fully gated", function()
        local src = read("general_tweaker_dev.lua")
        -- Merged into the existing godmode hooks: exactly ONE hook per pair
        -- (VMF silently drops a second - repo CLAUDE.md NON-NEGOTIABLE 8).
        H.equal(select(2, src:gsub('mod:hook%("DamageUtils", "add_damage_network",', "")), 1,
            "add_damage_network must have exactly one gt hook")
        H.equal(select(2, src:gsub('mod:hook%("DamageUtils", "add_damage_network_player",', "")), 1,
            "add_damage_network_player must have exactly one gt hook")
        H.equal(src:find('mod:hook_safe("DamageUtils"', 1, true), nil,
            "no hook_safe registrations may target DamageUtils")
        -- Identity split: liquid/DoT funnel keys on damage_source; the explosion
        -- funnel keys on damage_profile.name because timed explosions pass the
        -- shared "undefined" damage_source (timed_explosion_extension.lua:125).
        H.truthy(src:find("mod._gt_bot_aoe_immune_sources[damage_source]", 1, true))
        H.truthy(src:find("mod._gt_bot_aoe_immune_profiles[pname]", 1, true))
        H.truthy(src:find("local pname = damage_profile.name", 1, true))
        -- Both funnels demand host authority + bot-owned unit + master AND sub
        -- toggle, so no human, client, or default-config path is ever negated.
        H.equal(select(2, src:gsub(
            '%(Managers%.player and Managers%.player%.is_server%) and mod%._gt_unit_is_bot%(attacked_unit%)', "")), 2,
            "host+bot conjunction must appear in both funnels")
        H.equal(select(2, src:gsub(
            'mod:get%("gt_bot_behavior_improvements"%) and mod:get%("gt_bot_aoe_immunity"%)', "")), 2,
            "master+sub toggle conjunction must appear in both funnels")
        -- The default-OFF sub-toggle stays registered in the options tree.
        local data = read("general_tweaker_dev_data.lua")
        H.truthy(data:find('"gt_bot_aoe_immunity"', 1, true),
            "gt_bot_aoe_immunity checkbox missing from the data tree")
    end)
end
