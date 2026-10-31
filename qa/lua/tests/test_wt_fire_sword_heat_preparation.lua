-- Bounded #942 policy/runtime tests; isolated proof callbacks alone do not
-- establish a live peer-settings protocol or game acceptance.
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
        -- Actual native control key; this is still a minimal offline profile,
        -- not a fabricated claim that the retail damage function was executed.
        profile("burning_dot", "light_attack", nil, true)
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
        local controls = { catalog = true, agreement = true, registered = {}, extension_calls = 0,
            catalog_calls = 0, agreement_calls = 0 }
        local mod = { get = function(_, id) return settings[id] end }
        local deps = { policy = P, profiles = profiles,
            weapons = { [P.TEMPLATE] = { actions = { action_one = actions } },
                other = { actions = { action_one = { light = clone(actions.light_attack_left) } } } },
            clone = clone, register = function(key) controls.registered[#controls.registered + 1] = key end,
            fallbacks = {}, armor_reference = { attack = { 1, .3, 2, 1, 1 }, impact = { 1, .5, .5, 1, 1 } },
            catalog_allows = function() controls.catalog_calls = controls.catalog_calls + 1; return controls.catalog end,
            configuration_agrees = function() controls.agreement_calls = controls.agreement_calls + 1; return controls.agreement end,
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


    local function contains(row, field)
        H.truthy(type(row) == "string" and row:find(field, 1, true), "capture field absent: " .. field)
    end
    local function ascii_bytes(row)
        H.equal(type(row), "string", "actual capture row is required")
        H.truthy(#row <= 960, "actual capture row exceeds its byte cap")
        for index = 1, #row do
            local byte = row:byte(index)
            H.truthy(byte >= 32 and byte <= 126, "actual capture row contains a nonprintable byte")
        end
    end
    local function numeric_field(row, name)
        local value = assert(row:match(" " .. name .. "=([^ ]+)"), "numeric capture field absent: " .. name)
        return tonumber(value) -- assert also returns its message; tonumber accepts one scalar here.
    end
    H.test("#942 capture shares one exact scalar/sample getter contract", function()
        local f = fixture(); f.unit.heat, f.unit.maximum = 81.25, 80
        local calls = f.controls.extension_calls
        H.deep_equal(pack(P.heat(f.unit, f.deps.extension, f.deps.alive)), { n = 1, 80 })
        H.equal(f.controls.extension_calls, calls + 1)
        H.deep_equal(pack(P.sample_heat(f.unit, f.deps.extension, f.deps.alive)),
            { n = 4, 80, 81.25, 80, "ok" })
        H.equal(f.controls.extension_calls, calls + 2)
        local opaque = setmetatable({}, { __tostring = function() error("must not stringify") end })
        H.deep_equal(pack(P.sample_heat(f.unit, function() error(opaque, 0) end, f.deps.alive)),
            { n = 4, [1] = 0, [4] = "reader-error" })
        H.equal(select("#", P.heat(nil, f.deps.extension, f.deps.alive)), 1)
    end)

    H.test("#942 capture records actual power/native results and async calculated damage once", function()
        local f = fixture(); f.runtime:apply(false)
        f.unit.heat, f.unit.maximum = 12.5, 80
        H.equal(f.runtime:capture_arm(f.unit, {}), true)
        f.controls.catalog_calls, f.controls.agreement_calls, f.controls.extension_calls = 0, 0, 0
        local native_calls, token = 0, {}
        local out = pack(f.runtime:start_action(function(_, action)
            return f.runtime:max_targets(function(_, passed)
                native_calls = native_calls + 1; H.equal(passed, 1250)
                return 19, 23, nil, token, nil
            end, f.profiles[action.damage_profile], 1000)
        end, { owner_unit = f.unit }, f.actions.light_attack_left))
        H.deep_equal(out, { n = 5, 19, 23, nil, token, nil })
        H.deep_equal(pack(hit(f, f.profiles.wt942_direct_light_slashing_linesman,
            function() native_calls = native_calls + 1; return 40, nil, token, nil end)),
            { n = 4, 45, nil, token, nil })
        H.equal(native_calls, 2)
        H.equal(f.controls.catalog_calls, 3); H.equal(f.controls.agreement_calls, 3)
        H.equal(f.controls.extension_calls, 2, "capture must not re-read active heat")
        local data = assert(f.runtime:capture_dump()); H.equal(data.count, 3, "three actual observations must be retained")
        contains(data.rows[1], "heat_raw=12.5"); contains(data.rows[1], "heat_max=80")
        contains(data.rows[2], "input_power=1000"); contains(data.rows[2], "passed_power=1250")
        contains(data.rows[2], "native_attack_cleave=19"); contains(data.rows[2], "native_impact_cleave=23")
        contains(data.rows[3], "action_context=none"); contains(data.rows[3], "action=unknown")
        contains(data.rows[3], "pre_942_calculated_damage=40")
        contains(data.rows[3], "post_942_calculated_damage=45")
        contains(data.rows[3], "observed_damage_ratio=1.125")
        H.equal(f.runtime:capture_dump(), nil, "one dump cannot replay the arm")
    end)

    H.test("#942 common cap spans start cleave damage and the ninth eligible control", function()
        local f = fixture(); f.runtime:apply(false)
        H.equal(f.runtime:capture_arm(f.unit, {}), true)
        local function start()
            f.runtime:start_action(function(_, action)
                return f.runtime:max_targets(function() return 3, 4 end,
                    f.profiles[action.damage_profile], 100)
            end, { owner_unit = f.unit }, f.actions.light_attack_left)
        end
        for _ = 1, 2 do
            start()
            hit(f, f.profiles.wt942_direct_light_slashing_linesman)
        end
        start() -- start/cleave/damage, start/cleave/damage, start/cleave = eight
        local calls = f.controls.extension_calls
        local token = {}
        local burn = f.profiles.burning_dot
        H.deep_equal(pack(hit(f, burn, function(_, _, _, _, power, _, _, _, selected)
            H.equal(power, 600); H.equal(rawequal(selected, burn), true)
            return 7, nil, token, nil
        end)), { n = 4, 7, nil, token, nil }) -- ninth eligible local observation if the cap is relaxed
        local aoe = f.profiles.dagger_burning_slam_aoe
        H.deep_equal(pack(hit(f, aoe, function(_, _, _, _, power, _, _, _, selected)
            H.equal(power, 600); H.equal(rawequal(selected, aoe), true)
            return 7, nil, token, nil
        end)), { n = 4, 7, nil, token, nil })
        local data = assert(f.runtime:capture_dump())
        H.equal(data.count, 8, "ninth mixed observation cannot extend the common cap")
        H.equal(f.controls.extension_calls, calls, "capped capture releases its extra sampling path")
        contains(data.header, "reason=cap")
        for index, phase in ipairs({ "start", "cleave", "damage", "start", "cleave", "damage", "start", "cleave" }) do
            contains(data.rows[index], "phase=" .. phase); ascii_bytes(data.rows[index])
        end
        H.equal(f.runtime:capture_dump(), nil)
        f.runtime:capture_clear(); H.equal(f.runtime:capture_dump(), nil)
    end)

    H.test("#942 armed burn AoE donor and unowned-start controls retain native evidence", function()
        local f = fixture(); f.runtime:apply(false)
        H.equal(f.runtime:capture_arm(f.unit, {}), true)
        local token, calls = {}, 0
        for _, key in ipairs({ "burning_dot", "dagger_burning_slam_aoe", "light_slashing_linesman" }) do
            local original = f.profiles[key]
            H.deep_equal(pack(hit(f, original, function(_, _, _, _, power, _, _, _, selected)
                calls = calls + 1
                H.equal(power, 600); H.equal(rawequal(selected, original), true)
                return 7, nil, token, nil
            end)), { n = 4, 7, nil, token, nil })
        end
        f.runtime:start_action(function(_, action)
            H.equal(rawequal(action, f.actions.push), true)
            H.deep_equal(pack(f.runtime:max_targets(function(profile, power)
                calls = calls + 1
                H.equal(rawequal(profile, f.profiles.light_slashing_linesman), true)
                H.equal(power, 600); return 9, nil, token, nil
            end, f.profiles[action.damage_profile], 600)), { n = 4, 9, nil, token, nil })
        end, { owner_unit = f.unit }, f.actions.push)
        local data = assert(f.runtime:capture_dump())
        H.equal(data.count, 5, "exclusion evidence must be collected before the cap is spent")
        H.equal(calls, 4)
        for index = 1, 3 do
            contains(data.rows[index], "phase=damage"); contains(data.rows[index], "same_profile=1")
            contains(data.rows[index], "pre_942_calculated_damage=7")
            contains(data.rows[index], "post_942_calculated_damage=7")
            contains(data.rows[index], "heat_usage=diagnostic-only")
        end
        contains(data.rows[1], "profile=burning_dot"); contains(data.rows[1], "dot=1")
        contains(data.rows[2], "profile=dagger_burning_slam_aoe"); contains(data.rows[2], "no_damage=1")
        contains(data.rows[3], "class=native")
        contains(data.rows[5], "input_power=600"); contains(data.rows[5], "passed_power=600")
        for _, row in ipairs(data.rows) do ascii_bytes(row) end
    end)

    H.test("#942 nested unindexed capture scopes suppress and restore actual outer context", function()
        local f = fixture(); f.runtime:apply(false); f.unit.heat, f.unit.maximum = 12.5, 80
        H.equal(f.runtime:capture_arm(f.unit, {}), true)
        local token, calls = {}, 0
        local out = pack(f.runtime:start_action(function(_, outer_action)
            local outer = f.runtime.context; H.truthy(outer)
            H.deep_equal(pack(f.runtime:start_action(function()
                H.equal(f.runtime.context, nil)
                H.equal(f.runtime:max_targets(function(_, power)
                    calls = calls + 1; return power
                end, f.profiles.light_slashing_linesman, 1000), 1000)
                almost(hit(f, f.profiles.wt942_direct_light_slashing_linesman, function() return 40 end), 45)
                return nil, token, nil
            end, { owner_unit = f.unit }, { kind = "sweep", damage_profile = "light_slashing_linesman" })),
                { n = 3, [2] = token })
            H.equal(rawequal(f.runtime.context, outer), true)
            H.equal(f.runtime:max_targets(function(_, power)
                calls = calls + 1; return power
            end, f.profiles[outer_action.damage_profile], 1000), 1250)
            return false, nil, token, nil
        end, { owner_unit = f.unit }, f.actions.light_attack_left))
        H.deep_equal(out, { n = 4, [1] = false, [3] = token }); H.equal(calls, 2)
        H.equal(f.runtime.context, nil)
        local data = assert(f.runtime:capture_dump()); H.equal(data.count, 4)
        contains(data.rows[2], "phase=start action_context=sync action=unknown")
        contains(data.rows[3], "phase=damage action_context=none action=unknown")
        contains(data.rows[4], "phase=cleave action_context=sync action=action_one.light_attack_left scope=1")
        contains(data.rows[4], "passed_power=1250")
        H.equal(f.runtime:capture_arm(f.unit, {}), true)
        local opaque = setmetatable({}, { __tostring = function() error("nested error stringified") end })
        f.runtime:start_action(function()
            local outer = f.runtime.context
            local ok, failure = pcall(f.runtime.start_action, f.runtime, function() error(opaque, 0) end,
                { owner_unit = f.unit }, { kind = "sweep", damage_profile = "light_slashing_linesman" })
            H.equal(ok, false); H.equal(rawequal(failure, opaque), true)
            H.equal(rawequal(f.runtime.context, outer), true)
        end, { owner_unit = f.unit }, f.actions.light_attack_left)
        H.equal(f.runtime.context, nil)
        data = assert(f.runtime:capture_dump()); H.equal(data.count, 2)
        contains(data.header, "reason=native-error")
    end)

    H.test("#942 capture short circuit and unavailable samples cannot forge a proof", function()
        local f = fixture(); f.runtime:apply(false)
        f.controls.catalog = false
        H.equal(f.runtime:capture_arm(f.unit, {}), true)
        f.controls.catalog_calls, f.controls.agreement_calls = 0, 0
        H.equal(hit(f, f.profiles.wt942_direct_light_slashing_linesman), 10)
        H.equal(f.controls.catalog_calls, 1); H.equal(f.controls.agreement_calls, 0)
        local data = assert(f.runtime:capture_dump())
        contains(data.rows[1], "catalog=false"); contains(data.rows[1], "agreement=not-evaluated")
        contains(data.rows[1], "heat_usage=diagnostic-only")
        contains(data.rows[1], "pre_942_calculated_damage=10")
        contains(data.rows[1], "post_942_calculated_damage=10")
        f.controls.catalog = true; f.runtime:apply(false)
        H.equal(f.runtime:capture_arm(f.unit, {}), true)
        local marker = {}
        local ok, failure = pcall(f.runtime.start_action, f.runtime,
            function() error(marker, 0) end, { owner_unit = f.unit }, f.actions.light_attack_left)
        H.equal(ok, false); H.equal(rawequal(failure, marker), true)
        H.equal(f.runtime.context, nil)
        data = assert(f.runtime:capture_dump()); contains(data.header, "reason=native-error")
    end)

    -- Native excerpts are verbatim from93dea911: action_utils.lua15-33 and
    -- action_shield_slam.lua22-157. Only finite engine collaborators are supplied;
    -- no WT policy/runtime is replaced; the native bodies below are not a model.
    local function native_seams(f)
        local events = { helper = 0, super = 0, flow = 0, critical = 0, rig = 0 }
        local first_person = {
            disable_rig_movement = function() events.rig = events.rig + 1 end,
            current_position = function() return "position" end,
            current_rotation = function() return "rotation" end,
        }
        local extensions = { buff_system = {}, career_system = { has_melee_boost = function() return false, 1 end },
            first_person_system = first_person }
        local env = setmetatable({ MIN_POWER_LEVEL = 0, MAX_POWER_LEVEL = 1000,
            Cleave = { min = 0, max = 10 }, DefaultCleaveDistribution = { attack = .35, impact = .2 },
            DamageProfileTemplates = f.profiles, NetworkLookup = { damage_profiles = {} },
            ActionUtils = { is_critical_strike = function() return false end, get_action_time_scale = function() return 1 end },
            ScriptUnit = { extension = function(unit, name)
                H.equal(rawequal(unit, f.unit), true); return assert(extensions[name], name)
            end, has_extension = function() return nil end },
            Managers = { player = { owner = function() return { bot_player = true } end },
                state = { difficulty = { get_difficulty_settings = function() return {} end } } },
            Unit = { flow_event = function() events.flow = events.flow + 1 end },
            World = { get_data = function() return "physics" end }, Quaternion = { forward = function() return "forward" end },
            DamageUtils = { allow_friendly_fire_melee = function() return false end },
            PhysicsWorld = { immediate_raycast = function(_, _, _, range)
                H.equal(range, 3.5); return nil -- no physics or target/health behavior is emulated
            end }, table = setmetatable({ clear = function(row) for key in pairs(row) do row[key] = nil end end }, { __index = table }),
        }, { __index = _G })
        local id = 0; for key in pairs(f.profiles) do id = id + 1; env.NetworkLookup.damage_profiles[key] = id end
        local helper = assert(loadstring([=[
ActionUtils.get_power_level_percentage = function (power_level)
	local min_power_level, max_power_level = MIN_POWER_LEVEL, MAX_POWER_LEVEL
	local percentage = (power_level - min_power_level) / (max_power_level - min_power_level)

	return percentage
end

ActionUtils.get_max_targets = function (damage_profile, cleave_power_level)
	local cleave_distribution = damage_profile.cleave_distribution or DefaultCleaveDistribution
	local cleave_range = Cleave.max - Cleave.min
	local attack_cleave_power_level = cleave_power_level * cleave_distribution.attack
	local attack_percentage = ActionUtils.get_power_level_percentage(attack_cleave_power_level)
	local max_targets_attack = cleave_range * attack_percentage
	local impact_cleave_power_level = cleave_power_level * cleave_distribution.impact
	local impact_percentage = ActionUtils.get_power_level_percentage(impact_cleave_power_level)
	local max_targets_impact = cleave_range * impact_percentage

	return max_targets_attack, max_targets_impact
end
]=], "@native93dea911/action_utils.lua:15-33"))
        setfenv(helper, env); helper()
        local native_helper = env.ActionUtils.get_max_targets
        env.ActionUtils.get_max_targets = function(...)
            events.helper = events.helper + 1; return native_helper(...)
        end
        env.ActionShieldSlam = { super = { client_owner_start_action = function(...)
            events.super = events.super + 1; events.super_args = pack(...)
        end } }
        local slam = assert(loadstring([=[
ActionShieldSlam.client_owner_start_action = function (self, new_action, t, chain_action_data, power_level, action_init_data)
	ActionShieldSlam.super.client_owner_start_action(self, new_action, t, chain_action_data, power_level, action_init_data)

	self.current_action = new_action
	self.target_breed_unit = nil

	local owner_unit = self.owner_unit
	local first_person_unit = self.first_person_unit
	local buff_extension = ScriptUnit.extension(owner_unit, "buff_system")
	local career_extension = ScriptUnit.extension(owner_unit, "career_system")

	self.owner_career_extension = career_extension
	self.owner_buff_extension = buff_extension

	local _, melee_boost_curve_multiplier = career_extension:has_melee_boost()
	local is_critical_strike = ActionUtils.is_critical_strike(owner_unit, new_action, t)

	self.melee_boost_curve_multiplier = melee_boost_curve_multiplier
	self.power_level = power_level

	if not Managers.player:owner(owner_unit).bot_player then
		Managers.state.controller_features:add_effect("rumble", {
			rumble_effect = "light_swing",
		})
	end

	local action_hand = action_init_data and action_init_data.action_hand
	local damage_profile_name = action_hand and new_action["damage_profile_" .. action_hand] or new_action.damage_profile or "default"

	self.damage_profile_id = NetworkLookup.damage_profiles[damage_profile_name]
	self.damage_profile = DamageProfileTemplates[damage_profile_name]

	local damage_profile_name_aoe = action_hand and new_action["damage_profile_aoe_" .. action_hand] or new_action.damage_profile_aoe or "default"

	self.damage_profile_aoe_id = NetworkLookup.damage_profiles[damage_profile_name_aoe]
	self.damage_profile_aoe = DamageProfileTemplates[damage_profile_name_aoe]

	local damage_profile_target_name = action_hand and new_action["damage_profile_target" .. action_hand] or new_action.damage_profile_target or "default"

	self.damage_profile_target_id = NetworkLookup.damage_profiles[damage_profile_target_name]
	self.damage_profile_target = DamageProfileTemplates[damage_profile_target_name]

	local ammo_extension = self.ammo_extension

	if ammo_extension and ammo_extension:is_reloading() then
		ammo_extension:abort_reload()
	end

	local hud_extension = ScriptUnit.has_extension(owner_unit, "hud_system")
	local first_person_extension = ScriptUnit.extension(owner_unit, "first_person_system")

	self:_handle_critical_strike(is_critical_strike, buff_extension, hud_extension, first_person_extension, "on_critical_sweep", "Play_player_combat_crit_swing_2D")

	self._is_critical_strike = is_critical_strike

	Unit.flow_event(first_person_unit, "sfx_swing_started")
	first_person_extension:disable_rig_movement()

	local physics_world = World.get_data(self.world, "physics_world")
	local pos = first_person_extension:current_position()
	local rot = first_person_extension:current_rotation()
	local direction = Quaternion.forward(rot)
	local difficulty_settings = Managers.state.difficulty:get_difficulty_settings()
	local owner_player = Managers.player:owner(owner_unit)
	local melee_friendly_fire = DamageUtils.allow_friendly_fire_melee(difficulty_settings, owner_player)
	local collision_filter = melee_friendly_fire and "filter_melee_sweep" or "filter_melee_sweep_no_player"
	local results = PhysicsWorld.immediate_raycast(physics_world, pos, direction, new_action.dedicated_target_range, "all", "collision_filter", collision_filter)

	if results then
		local side_manager = Managers.state.side
		local num_results = #results

		for i = 1, num_results do
			local result = results[i]
			local actor = result[4]
			local hit_unit = Actor.unit(actor)

			if not melee_friendly_fire and side_manager:is_ally(owner_unit, hit_unit) then
				-- Nothing
			else
				local breed = Unit.get_data(hit_unit, "breed")

				if breed then
					local node = Actor.node(actor)
					local hit_zone = breed.hit_zones_lookup[node]
					local hit_zone_name = hit_zone.name

					if hit_zone_name ~= "afro" and HEALTH_ALIVE[hit_unit] then
						self.target_breed_unit = hit_unit

						break
					end
				end
			end
		end
	end

	if not self.target_breed_unit and ScriptUnit.has_extension(owner_unit, "smart_targeting_system") then
		local targeting_extension = ScriptUnit.extension(owner_unit, "smart_targeting_system")
		local targeting_data = targeting_extension:get_targeting_data()
		local smart_targeting_unit = targeting_data.unit

		if HEALTH_ALIVE[smart_targeting_unit] then
			local smart_targeting_position = Unit.has_node(smart_targeting_unit, "j_spine") and Unit.world_position(smart_targeting_unit, Unit.node(smart_targeting_unit, "j_spine"))
			local target_world_position = POSITION_LOOKUP[smart_targeting_unit] or Unit.world_position(smart_targeting_unit, 0)
			local target_position = smart_targeting_position or target_world_position
			local distance = Vector3.length(pos - target_position)

			if HEALTH_ALIVE[smart_targeting_unit] and distance < new_action.dedicated_target_range then
				self.target_breed_unit = smart_targeting_unit
			end
		end
	end

	self.state = "waiting_to_hit"

	local anim_time_scale = ActionUtils.get_action_time_scale(owner_unit, new_action)

	self.time_to_hit = t + (new_action.hit_time or 0) / anim_time_scale

	table.clear(self.hit_units)
	table.clear(self.inner_hit_units)
	table.clear(self.target_hit_zones_names)
	table.clear(self.target_hit_unit_positions)

	local current_action = self.current_action
	local overcharge_type = current_action.overcharge_type

	if overcharge_type then
		local overcharge_amount = PlayerUnitStatusSettings.overcharge_values[overcharge_type]

		self.overcharge_extension:add_charge(overcharge_amount)
	end

	self._num_targets_hit = 0
end
]=], "@native93dea911/action_shield_slam.lua:22-157"))
        setfenv(slam, env); slam()
        f.actions.heavy_attack_spell.dedicated_target_range = 3.5
        f.actions.heavy_attack_spell.hit_time = .35
        local actor = { owner_unit = f.unit, first_person_unit = {}, world = {},
            hit_units = {}, inner_hit_units = {}, target_hit_zones_names = {}, target_hit_unit_positions = {},
            _handle_critical_strike = function() events.critical = events.critical + 1 end,
            overcharge_extension = { add_charge = function() error("unexpected native heat write") end } }
        return env.ActionShieldSlam.client_owner_start_action, env.ActionUtils.get_max_targets, actor, events
    end

    H.test("#942 captured cleave delegates to the verbatim native target helper", function()
        local f = fixture(); f.runtime:apply(false); f.unit.heat, f.unit.maximum = 12.5, 80
        local _, helper, _, events = native_seams(f)
        H.equal(f.runtime:capture_arm(f.unit, {}), true)
        local out = pack(f.runtime:start_action(function(_, action)
            return f.runtime:max_targets(helper, f.profiles[action.damage_profile], 1000)
        end, { owner_unit = f.unit }, f.actions.light_attack_left))
        H.equal(out.n, 2); almost(out[1], 4.375); almost(out[2], 2.5)
        H.equal(events.helper, 1)
        local data = assert(f.runtime:capture_dump()); H.equal(data.count, 2)
        almost(numeric_field(data.rows[2], "input_power"), 1000)
        almost(numeric_field(data.rows[2], "passed_power"), 1250)
        almost(numeric_field(data.rows[2], "native_attack_cleave"), 4.375)
        almost(numeric_field(data.rows[2], "native_impact_cleave"), 2.5)
    end)

    H.test("#942 actual native ShieldSlam captures selected direct target AoE and no invented damage", function()
        for _, hand in ipairs({ "unspecified", "right", "left" }) do
            local f = fixture(); f.runtime:apply(false)
            local slam, _, actor, events = native_seams(f)
            local init = hand ~= "unspecified" and { action_hand = hand } or nil
            H.equal(f.runtime:capture_arm(f.unit, {}), true)
            H.equal(pack(f.runtime:start_action(slam, actor, f.actions.heavy_attack_spell, 7, nil, 600, init)).n, 0)
            local direct_key = hand == "left" and "dagger_burning_slam" or "wt942_direct_dagger_burning_slam"
            local target_key = hand == "left" and "dagger_burning_slam_target" or "wt942_direct_dagger_burning_slam_target"
            H.equal(rawequal(actor.damage_profile, f.profiles[direct_key]), true)
            H.equal(rawequal(actor.damage_profile_target, f.profiles[target_key]), true)
            H.equal(rawequal(actor.damage_profile_aoe, f.profiles.dagger_burning_slam_aoe), true)
            H.equal(events.super, 1); H.equal(events.super_args.n, 6)
            H.equal(rawequal(events.super_args[2], actor.current_action), true)
            H.equal(events.super_args[3], 7); H.equal(events.super_args[4], nil)
            H.equal(events.super_args[5], 600); H.equal(rawequal(events.super_args[6], init), true)
            H.equal(events.flow, 1); H.equal(events.critical, 1); H.equal(events.rig, 1)
            H.equal(events.helper, 0, "ShieldSlam start does not own the separate Sweep target-helper seam")
            H.equal(f.unit.heat, 30); H.equal(f.runtime.context, nil)
            local data = assert(f.runtime:capture_dump())
            H.equal(data.count, 1, "native start must not manufacture AoE/damage calculation evidence")
            contains(data.rows[1], "init_hand=" .. hand)
            contains(data.rows[1], "prepared_profile_field=" .. direct_key)
            contains(data.rows[1], "prepared_target_field=" .. target_key)
            contains(data.rows[1], "prepared_aoe_field=dagger_burning_slam_aoe aoe_no_damage=1")
            ascii_bytes(data.rows[1])
        end
        local f = fixture(); f.runtime:apply(false)
        local slam, _, actor = native_seams(f)
        local opaque = setmetatable({}, { __tostring = function() error("native error stringified") end })
        actor._handle_critical_strike = function() error(opaque, 0) end
        H.equal(f.runtime:capture_arm(f.unit, {}), true)
        local ok, failure = pcall(f.runtime.start_action, f.runtime, slam, actor, f.actions.heavy_attack_spell, 7, nil, 600, nil)
        H.equal(ok, false); H.equal(rawequal(failure, opaque), true); H.equal(f.runtime.context, nil)
        local data = assert(f.runtime:capture_dump()); contains(data.header, "reason=native-error")
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
