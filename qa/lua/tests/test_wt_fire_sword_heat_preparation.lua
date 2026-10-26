-- External bounded #942 candidate. Tests real policy/runtime owners; injected
-- proof callbacks do NOT establish an actual peer-settings protocol.
return function(H, root)
    local external = root .. "/weapon_tweaker/scripts/mods/weapon_tweaker"
    local P = dofile(external .. "/_wt_fire_sword_heat.lua")
    local R = dofile(external .. "/_wt_fire_sword_heat_runtime.lua")
    local function clone(value)
        if type(value) ~= "table" then return value end
        local out = {}; for k, v in pairs(value) do out[k] = clone(v) end; return out
    end
    local function pack(...) return { n = select("#", ...), ... } end
    local function almost(a, b) H.truthy(math.abs(a - b) < 1e-9, tostring(a) .. " != " .. tostring(b)) end
    local function fixture()
        local profiles = {}
        local function profile(name, charge, armored, dot, no_damage)
            profiles[name] = { charge_value = charge, armor_modifier = {
                attack = { 1, armored and .2 or 0, 2, 1, 1 },
                impact = { 1, .3, .5, 1, 1 },
            }, cleave_distribution = { attack = .35, impact = .2 },
                default_target = { power_distribution = { attack = .075, impact = .05 } },
                targets = {}, is_dot = dot, no_damage = no_damage }
        end
        profile("light_slashing_linesman", "light_attack")
        profile("light_slashing_smiter_stab", "light_attack", true)
        profile("light_slashing_linesman_burn", "light_attack")
        profile("medium_burning_tank", "heavy_attack", true)
        profile("dagger_burning_slam", "heavy_attack", true)
        profile("dagger_burning_slam_target", "heavy_attack", true)
        profile("dagger_burning_slam_aoe", "heavy_attack", true, nil, true)
        profile("burninating", "light_attack", nil, true)
        local actions = {
            light_attack_left = { kind = "sweep", damage_profile = "light_slashing_linesman" },
            light_attack_stab = { kind = "sweep", damage_profile = "light_slashing_smiter_stab" },
            light_attack_last = { kind = "sweep", damage_profile = "light_slashing_linesman_burn" },
            heavy_attack_left = { kind = "sweep", damage_profile = "medium_burning_tank" },
            heavy_attack_spell = { kind = "shield_slam", damage_profile = "dagger_burning_slam",
                damage_profile_target = "dagger_burning_slam_target",
                damage_profile_aoe = "dagger_burning_slam_aoe", push_radius = 2.5 },
            burn = { kind = "sweep", damage_profile = "burninating" },
            push = { kind = "push_stagger", damage_profile = "light_slashing_linesman" },
        }
        local settings = { [P.ENABLED] = true, [P.ARMOR] = true }
        local unit = { heat = 30, maximum = 40 }
        local controls = { catalog = true, agreement = true, registered = {}, extension_calls = 0 }
        local mod = { get = function(_, id) return settings[id] end }
        local deps = { policy = P, profiles = profiles,
            weapons = { [P.TEMPLATE] = { actions = { action_one = actions } },
                other = { actions = { action_one = { light = clone(actions.light_attack_left) } } } },
            clone = clone, register = function(key) controls.registered[#controls.registered + 1] = key end,
            fallbacks = {}, armor_reference = { attack = { 1, .3, 2, 1, 1 }, impact = { 1, .5, .5, 1, 1 } },
            catalog_allows = function() return controls.catalog end,
            configuration_agrees = function() return controls.agreement end,
            alive = function(u) return u.dead ~= true end,
            extension = function(u, name)
                H.equal(name, "overcharge_system"); controls.extension_calls = controls.extension_calls + 1
                return { current_overcharge_status = function() return u.heat, 25, u.maximum end }
            end,
        }
        local baseline = clone(profiles)
        local runtime = R.new(mod, deps)
        return { runtime = runtime, state = runtime.state, deps = deps, settings = settings,
            unit = unit, actions = actions, profiles = profiles, controls = controls, baseline = baseline }
    end
    local function hit(f, profile, native, ...)
        return f.runtime:calculate_damage(native or function() return 10 end,
            {}, {}, f.unit, "torso", 600, "curve", 1, false, profile, ...)
    end

    H.test("#942 defaults, finite settings and exact absolute heat caps", function()
        local c = assert(P.config(function() end))
        H.equal(c.enabled, false); H.equal(c.armor, false)
        H.equal(c.cleave, .02); H.equal(c.damage, .01); H.equal(c.threshold, 25)
        local f = fixture()
        for _, row in ipairs({ { -2, 40, 0 }, { 0, 40, 0 }, { 30, 40, 30 },
                { 99, 60, 60 }, { 20, 0, 0 }, { math.huge, 40, 0 }, { 20, 0/0, 0 } }) do
            f.unit.heat, f.unit.maximum = row[1], row[2]
            H.equal(P.heat(f.unit, f.deps.extension, f.deps.alive), row[3])
        end
        H.equal(P.heat(f.unit, function() error("reader") end, f.deps.alive), 0)
        H.equal(P.heat(nil, f.deps.extension, f.deps.alive), 0)
        f.unit.dead = true; H.equal(P.heat(f.unit, f.deps.extension, f.deps.alive), 0)
        for _, bad in ipairs({ math.huge, -1, 11, "2", false }) do
            H.equal(P.config(function(id) if id == P.CLEAVE then return bad end end), nil)
        end
        H.equal(P.config(function() error("settings") end), nil)
    end)

    H.test("#942 registration is sorted and isolates all native donors", function()
        local f = fixture(); local sorted = clone(f.controls.registered); table.sort(sorted)
        H.deep_equal(sorted, f.controls.registered); H.equal(#sorted, 8)
        for name, original in pairs(f.baseline) do H.deep_equal(f.profiles[name], original) end
        H.equal(f.state.clones.dagger_burning_slam_aoe, nil)
        H.equal(f.state.clones.burninating, nil)
        H.truthy(f.state.clones.light_slashing_linesman_burn)
        f.runtime:apply(false)
        H.equal(f.actions.push.damage_profile, "light_slashing_linesman")
        H.equal(f.actions.burn.damage_profile, "burninating")
        H.equal(f.deps.weapons.other.actions.action_one.light.damage_profile, "light_slashing_linesman")
        H.equal(f.actions.heavy_attack_spell.damage_profile_aoe, "dagger_burning_slam_aoe")
        H.equal(f.actions.heavy_attack_spell.push_radius, 2.5)
        f.runtime:apply(true); f.runtime:apply(true)
        H.equal(f.actions.light_attack_left.damage_profile, "light_slashing_linesman")
        H.equal(f.actions.heavy_attack_spell.damage_profile_target, "dagger_burning_slam_target")
    end)

    H.test("#942 resolved armor affects only zero armor attack entries", function()
        local f = fixture()
        local armor = f.profiles.wt942_armored_light_slashing_linesman
        H.equal(type(armor.armor_modifier), "table")
        H.equal(armor.armor_modifier.attack[2], .3)
        H.deep_equal(armor.armor_modifier.impact, f.baseline.light_slashing_linesman.armor_modifier.impact)
        H.equal(armor.armor_modifier.attack[1], 1); H.equal(armor.armor_modifier.attack[3], 2)
        H.equal(f.state.clones.light_slashing_smiter_stab.armored, nil)
        H.equal(f.state.clones.medium_burning_tank.armored, nil)
        local donor = { charge_value = "light_attack", armor_modifier = clone(armor.armor_modifier),
            default_target = { armor_modifier = { attack = {1,0,2}, impact = {1,.2,.5} } },
            targets = { { armor_modifier = { attack = {1,.7,2}, impact = {1,.9,.5} } } } }
        local p = { exact = donor }
        local s = P.new({ [P.TEMPLATE] = { actions = { a = { b = { kind = "sweep", damage_profile = "exact" } } } } },
            p, clone, function() end, {}, f.deps.armor_reference)
        local changed = p[s.clones.exact.armored]
        H.equal(changed.armor_modifier.attack[2], .3)
        H.equal(changed.default_target.armor_modifier.attack[2], .3)
        H.equal(changed.targets[1].armor_modifier.attack[2], .7)
        H.equal(donor.default_target.armor_modifier.attack[2], 0)
    end)

    H.test("#942 strict armor threshold and native direct/burn isolation", function()
        local f = fixture(); f.runtime:apply(false)
        local key = f.actions.light_attack_left.damage_profile
        for _, row in ipairs({ {25, false}, {25.001, true}, {40, true}, {0, false} }) do
            f.unit.heat = row[1]
            local selected
            local damage = hit(f, f.profiles[key], function(_, _, _, _, _, _, _, _, profile)
                selected = profile; return 10, nil, "tail", nil
            end)
            almost(damage, 10 * (1 + .01 * row[1]))
            H.equal(selected._wt942_armor == true, row[2])
        end
        for _, name in ipairs({ "burninating", "dagger_burning_slam_aoe", "light_slashing_linesman" }) do
            local calls = f.controls.extension_calls
            H.equal(hit(f, f.profiles[name]), 10)
            H.equal(f.controls.extension_calls, calls)
        end
        local forged = clone(f.profiles[key])
        H.equal(hit(f, forged), 10, "marker alone must not establish ownership")
    end)

    H.test("#942 Sweep synchronous cleave and full native result tuple", function()
        local f = fixture(); f.runtime:apply(false)
        local a = f.actions.light_attack_left
        local values = pack(f.runtime:start_action(function(self, current, ...)
            H.equal(select("#", ...), 6); H.equal(select(6, ...), "tail")
            local targets = pack(f.runtime:max_targets(function(profile, power, ...)
                H.equal(profile, f.profiles[current.damage_profile]); H.equal(select("#", ...), 3)
                almost(power, 960); return 7, nil, false, nil
            end, f.profiles[current.damage_profile], 600, nil, "sentinel", nil))
            H.deep_equal(targets, { n = 4, [1] = 7, [3] = false })
            return false, nil, "result", nil
        end, { owner_unit = f.unit }, a, 1, nil, 600, nil, nil, "tail"))
        H.deep_equal(values, { n = 4, [1] = false, [3] = "result" })
        H.equal(f.runtime.context, nil)
        H.equal(f.runtime:max_targets(function(_, power) return power end, f.profiles[a.damage_profile], 600), 600)
    end)

    H.test("#942 ShieldSlam ordinary/target are scaled; no AoE or radius rewrite", function()
        local f = fixture(); f.runtime:apply(false)
        f.runtime:start_action(function(_, action)
            H.equal(action.damage_profile_aoe, "dagger_burning_slam_aoe")
            H.equal(action.push_radius, 2.5)
            almost(hit(f, f.profiles[action.damage_profile]), 13)
            almost(hit(f, f.profiles[action.damage_profile_target]), 13)
            H.equal(hit(f, f.profiles[action.damage_profile_aoe]), 10)
        end, { owner_unit = f.unit }, f.actions.heavy_attack_spell, 1, nil, 600, nil)
    end)

    H.test("#942 offhand start uses native donors and receives no bonus", function()
        local f = fixture(); f.runtime:apply(false)
        f.runtime:start_action(function(_, action)
            H.equal(action.damage_profile, "light_slashing_linesman")
            H.equal(hit(f, f.profiles[action.damage_profile]), 10)
            H.equal(f.runtime:max_targets(function(_, power) return power end,
                f.profiles[action.damage_profile], 600), 600)
        end, { owner_unit = f.unit }, f.actions.light_attack_left, 1, nil, 600, { action_hand = "left" })
    end)

    H.test("#942 nested unrelated starts and exceptions restore exact context", function()
        local f = fixture(); f.runtime:apply(false)
        local error_object = {}
        f.runtime:start_action(function()
            local outer = f.runtime.context; H.truthy(outer)
            local ok, failure = pcall(function()
                f.runtime:start_action(function() H.equal(f.runtime.context, nil); error(error_object) end,
                    { owner_unit = f.unit }, { kind = "sweep", damage_profile = "light_slashing_linesman" })
            end)
            H.equal(ok, false); H.equal(failure, error_object); H.equal(f.runtime.context, outer)
        end, { owner_unit = f.unit }, f.actions.light_attack_left)
        H.equal(f.runtime.context, nil)
        local ok, failure = pcall(function()
            hit(f, f.profiles.wt942_direct_light_slashing_linesman, function() error(error_object) end)
        end)
        H.equal(ok, false); H.equal(failure, error_object)
    end)

    H.test("#942 native damage tuple and nil arguments survive scaling", function()
        local f = fixture(); f.runtime:apply(false)
        local output = pack(hit(f, f.profiles.wt942_direct_light_slashing_linesman,
            function(_, _, _, _, _, _, _, _, _, ...)
                H.deep_equal(pack(...), { n = 5, [2] = "tail", [4] = false })
                return 10, nil, false, "tail", nil
            end, nil, "tail", nil, false, nil))
        H.deep_equal(output, { n = 5, [1] = 13, [3] = false, [4] = "tail" })
    end)

    H.test("#942 proof failures restore native data even for latched armor", function()
        local f = fixture(); f.runtime:apply(false)
        local armor = f.profiles.wt942_armored_light_slashing_linesman
        for _, kind in ipairs({ "catalog", "agreement", "settings" }) do
            f.controls.catalog, f.controls.agreement = true, true
            f.settings[P.ENABLED] = true
            if kind == "settings" then f.settings[P.CLEAVE] = math.huge else f.controls[kind] = false end
            local selected; local out = hit(f, armor, function(_, _, _, _, _, _, _, _, p) selected = p; return 10 end)
            H.equal(out, 10); H.equal(selected, f.profiles.light_slashing_linesman)
            f.runtime:apply(false)
            H.equal(f.actions.light_attack_left.damage_profile, "light_slashing_linesman")
            f.settings[P.CLEAVE] = nil
            f.runtime:apply(false)
        end
        f.controls.agreement = true
        f.deps.configuration_agrees = nil
        H.equal(pcall(R.new, { get = function() end }, f.deps), false)
    end)

    H.test("#942 throwing proofs/readers are inert; disable and reapply are bounded", function()
        local f = fixture()
        f.controls.agreement = false
        local _, enabled = f.runtime:apply(false); H.equal(enabled, false)
        f.controls.agreement = true
        for _ = 1, 4 do
            H.equal(select(2, f.runtime:apply(false)), true)
            local profile = f.profiles[f.actions.light_attack_left.damage_profile]
            almost(hit(f, profile), 13)
            f.runtime:apply(true); H.equal(hit(f, profile), 10)
        end
        f.runtime:apply(false)
        local original = f.deps.extension
        -- Dependency closures retain their original function; a throwing
        -- extension is checked directly, not mislabeled as runtime injection.
        H.equal(P.heat(f.unit, function() error("reader") end, f.deps.alive), 0)
        f.deps.configuration_agrees = function() error("agreement") end
        local second = R.new({ get = function(_, id) return f.settings[id] end }, {
            policy = P, catalog_allows = function() return true end,
            configuration_agrees = f.deps.configuration_agrees,
            extension = original, alive = f.deps.alive,
            weapons = {}, profiles = {}, clone = clone, register = function() end,
            fallbacks = {}, armor_reference = f.deps.armor_reference,
        })
        H.equal(select(2, second:apply(false)), false)
    end)
end
