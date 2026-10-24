-- #1676: execute the real core-template installer and its exported cloner.
-- The native 6.13 loader resolves these power references before mods run:
-- scripts/settings/equipment/damage_profile_templates.lua:5570-5616.
return function(H, root)
    local function clone(value)
        if type(value) ~= "table" then return value end
        local out = {}
        for key, child in pairs(value) do out[key] = clone(child) end
        return out
    end

    local function donor()
        return {
            charge_value = "light_attack",
            cleave_distribution = { attack = 2, impact = 4 },
            default_target = {
                attack_template = "slashing_smiter",
                power_distribution = { attack = 10, impact = 20 },
            },
            targets = {
                [2] = { power_distribution = { attack = 5, impact = 7 } },
                [5] = { power_distribution = { attack = 0, impact = 0 } },
            },
            critical_strike = { power_distribution = { attack = 3, impact = 4 } },
            armor_modifier = { attack = { 1, 0.5 }, impact = { 1, 1 } },
            custom = { keep = "unchanged" },
        }
    end

    local function fixture(profile, levels, weapons, policy)
        local profiles, lookup, sources = { source = profile or donor() }, {}, {}
        local chunk = assert(loadfile(root .. "/character_weapon_variants/scripts/mods/"
            .. "character_weapon_variants/_cwv_core_templates.lua"))
        -- Only the chunk's table helper is replaced; no global monkeypatch.
        setfenv(chunk, setmetatable({
            table = setmetatable({ clone = clone }, { __index = table }),
        }, { __index = _G }))
        local om = {
            combat_style_policy = policy or {},
            _record_cwv_dp_source = function(key, source) sources[key] = source end,
        }
        local owner = chunk()({ warning = function() end, info = function() end }, {
            om = om, Weapons = weapons or {}, ItemMasterList = {},
            DamageProfileTemplates = profiles, PowerLevelTemplates = levels or {},
            NetworkLookup = { damage_profiles = lookup }, printf = function() end,
        })
        return owner.clone_damage_profile, profiles, lookup, sources, om
    end

    H.test("#1676 real cloner scales resolved cleave, damage, stagger and sparse targets", function()
        local original = donor()
        local before = clone(original)
        local make, profiles, lookup, sources, om = fixture(original)
        local key = make("source", "cwv_probe_", { damage = 2, stagger = 3, cleave = 1.5 })
        local result = profiles[key]
        H.equal(result.cleave_distribution.attack, 3)
        H.equal(result.cleave_distribution.impact, 6)
        H.equal(result.default_target.power_distribution.attack, 20)
        H.equal(result.default_target.power_distribution.impact, 60)
        H.equal(result.targets[2].power_distribution.attack, 10)
        H.equal(result.targets[2].power_distribution.impact, 21)
        H.equal(result.targets[5].power_distribution.attack, 0)
        H.equal(result.critical_strike.power_distribution.attack, 6)
        H.equal(result.critical_strike.power_distribution.impact, 12)
        H.deep_equal(result.armor_modifier, before.armor_modifier)
        H.deep_equal(result.custom, before.custom)
        H.deep_equal(original, before, "the native donor must stay untouched")
        H.equal(sources[key], "source", "#423's wire donor must remain native")
        H.equal(lookup[lookup[key]], key)
        H.equal(om._cwv_profile_multiplier_check(), nil)
        result.targets[2].power_distribution.attack = 999
        H.equal(original.targets[2].power_distribution.attack, 5)
    end)

    H.test("#1676 unresolved power references keep cloned registry keys and scale once", function()
        local levels = {
            cleave = { attack = 2, impact = 4 },
            default = { power_distribution = { attack = 10, impact = 20 } },
            targets = { [2] = { power_distribution = { attack = 5, impact = 7 } } },
            crit = { power_distribution = { attack = 3, impact = 4 } },
        }
        local before = clone(levels)
        local make, profiles, lookup = fixture({
            cleave_distribution = "cleave", default_target = "default",
            targets = "targets", critical_strike = "crit",
        }, levels)
        local key = make("source", "cwv_legacy_", { damage = 2, stagger = 3, cleave = 1.5 })
        local result = profiles[key]
        H.equal(result.cleave_distribution, "cwv_legacy_cleave")
        H.equal(levels[result.cleave_distribution].attack, 3)
        H.equal(levels[result.default_target].power_distribution.impact, 60)
        H.equal(levels[result.targets][2].power_distribution.attack, 10)
        H.equal(levels[result.critical_strike].power_distribution.attack, 6)
        for name, row in pairs(before) do H.deep_equal(levels[name], row) end
        H.equal(make("source", "cwv_legacy_", { damage = 2, stagger = 3, cleave = 1.5 }), key)
        H.equal(levels[result.default_target].power_distribution.attack, 20)
        H.equal(#lookup, 1, "repeated use must not append a second wire identity")
    end)

    H.test("#1676 mixed resolved and legacy profile fields share one scaling contract", function()
        local profile = donor()
        profile.cleave_distribution = "cleave"
        local levels = { cleave = { attack = 2, impact = 4 } }
        local make, profiles = fixture(profile, levels)
        local key = make("source", "cwv_mixed_", { damage = 2, stagger = 3, cleave = 1.5 })
        H.equal(levels[profiles[key].cleave_distribution].attack, 3)
        H.equal(profiles[key].default_target.power_distribution.attack, 20)
        H.equal(profiles[key].targets[2].power_distribution.impact, 21)
    end)

    H.test("#1676 neutral multipliers and missing optional power rows preserve native data", function()
        local profile = donor()
        profile.critical_strike = { attack_armor_power_modifer = { 1, 1 } }
        profile.targets[7] = { attack_template = "no_power_here" }
        profile.default_target.power_distribution.impact = nil
        local before = clone(profile)
        local make, profiles = fixture(profile)
        local key = make("source", "cwv_neutral_", {})
        H.deep_equal(profiles[key], before)
        H.deep_equal(profile, before)
    end)

    H.test("#1676 missing donor does not create a profile, lookup or wire mapping", function()
        local make, profiles, lookup, sources, om = fixture()
        H.equal(make("absent", "cwv_missing_", { damage = 2 }), "absent")
        H.equal(profiles.cwv_missing_absent, nil)
        H.equal(next(lookup), nil)
        H.equal(next(sources), nil)
        H.truthy(om._cwv_profile_multiplier_check():find("skip:", 1, true) == 1)
    end)

    H.test("#1676 retained construction audit rejects an existing unscaled clone", function()
        local make, profiles, _, _, om = fixture()
        profiles.cwv_stale_source = clone(profiles.source)
        make("source", "cwv_stale_", { damage = 2, stagger = 3, cleave = 1.5 })
        H.truthy(om._cwv_profile_multiplier_check():find("constructor read-back", 1, true))
    end)

    H.test("#1676 retained construction proof is not invalidated by later WT tuning", function()
        local make, profiles, _, _, om = fixture()
        local key = make("source", "cwv_observed_", { damage = 2, stagger = 3, cleave = 1.5 })
        H.equal(om._cwv_profile_multiplier_check(), nil)
        profiles.source.default_target.power_distribution.attack = 123
        profiles[key].default_target.power_distribution.attack = 456
        H.equal(om._cwv_profile_multiplier_check(), nil,
            "this check proves construction, not subsequent optional modifiers")
    end)

    H.test("#1676 actual template constructor consumes the corrected shared cloner", function()
        local observed
        local weapons = { two_handed_swords_template_1 = {} }
        local policy = {
            IMPERIAL_DAMAGE_MULT = 2, IMPERIAL_SPEED_MULT = 1,
            IMPERIAL_CLEAVE_MULT = 1.5, IMPERIAL_STAGGER_MULT = 3,
            build_imperial_template = function(_, _, make)
                observed = make("source", "cwv_il_", { damage = 2, stagger = 3, cleave = 1.5 })
                return { actions = { action_one = { light = { damage_profile = observed } } } }
            end,
        }
        local _, profiles, _, sources = fixture(nil, nil, weapons, policy)
        H.equal(weapons.imperial_longsword_template.actions.action_one.light.damage_profile, observed)
        H.equal(profiles[observed].default_target.power_distribution.attack, 20)
        H.equal(sources[observed], "source")
    end)

    H.test("#1676 named installed callback distinguishes missing, unexercised and observed construction", function()
        local make, _, _, _, om = fixture()
        local checks = {}
        dofile(root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
            .. "_cwv_regression_husk_ammo.lua")({}, {
            om = om, rt_register = function(name, fn) checks[name] = fn end,
        })
        local check = assert(checks.issue1676_resolved_profile_multipliers)
        H.truthy(check():find("skip:", 1, true) == 1)
        make("source", "cwv_live_", { damage = 2, stagger = 3, cleave = 1.5 })
        H.equal(check(), nil)
        om._cwv_profile_multiplier_check = nil
        H.truthy(check():find("audit missing", 1, true))
    end)
end
