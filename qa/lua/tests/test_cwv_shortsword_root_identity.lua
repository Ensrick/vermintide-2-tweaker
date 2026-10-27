-- Actual constructor/private builder/acquisition seam, not native engine ABI.
return function(H, root)
    local F = dofile(root .. "/qa/lua/fixtures/cwv_shortsword_history_owner.lua")
    local function roots(c)
        return { profiles = c.env.DamageProfileTemplates, levels = c.env.PowerLevelTemplates,
            lookup = c.env.NetworkLookup.damage_profiles, weapons = c.env.Weapons, map = c.state._cwv_damage_profile_wire_source }
    end
    local function set_root(c, kind, value)
        if kind == "profiles" then c.env.DamageProfileTemplates = value
        elseif kind == "levels" then c.env.PowerLevelTemplates = value
        elseif kind == "lookup" then c.env.NetworkLookup.damage_profiles = value
        elseif kind == "weapons" then c.env.Weapons = value
        else c.state._cwv_damage_profile_wire_source = value end
    end
    local function shallow(value, meta)
        local result = {}; for key, item in next, value do result[key] = item end
        return setmetatable(result, meta)
    end
    for _, kind in ipairs({ "profiles", "levels", "lookup", "weapons", "map" }) do
        H.test("#428 Shortsword raw identity rejects foreign equal-comparing " .. kind, function()
            local meta = { __eq = function() return true end }
            local c = F.new(H, root, { before = function(context) setmetatable(roots(context)[kind], meta) end })
            F.admitted(H, c)
            local original = roots(c)[kind]; local foreign = shallow(original, meta)
            H.equal(rawequal(original, foreign), false); H.truthy(original == foreign)
            set_root(c, kind, foreign); F.denied(H, c)
        end)
    end
    H.test("#428 Shortsword healthy same-object shared-meta roots stay admitted", function()
        local meta = { __eq = function() return true end }
        local c = F.new(H, root, { before = function(context)
            for _, value in pairs(roots(context)) do setmetatable(value, meta) end
        end }); F.admitted(H, c)
    end)
    for _, axis in ipairs({ "source", "template", "native profile", "owned profile", "native named power" }) do
        H.test("#428 Shortsword raw registry rejects foreign equal-comparing " .. axis, function()
            local meta = { __eq = function() return true end }
            local c = F.new(H, root, { before = function(context)
                if axis == "source" then setmetatable(context.env.Weapons.one_handed_daggers_template_1, meta)
                elseif axis == "native profile" then setmetatable(context.env.DamageProfileTemplates.light_fencer_stab, meta)
                elseif axis == "native named power" then
                    -- Exact existing legacy() seam and actual resolved row.
                    local profile = context.env.DamageProfileTemplates.light_fencer_stab
                    context.env.PowerLevelTemplates.review_legacy_default_target = setmetatable(profile.default_target, meta)
                    profile.default_target = "review_legacy_default_target"
                end
            end, construction_options = function(options, context)
                if axis == "template" then
                    local clone = options.clone
                    options.clone = function(value)
                        local result = clone(value)
                        if rawequal(value, context.env.Weapons.one_handed_daggers_template_1) then setmetatable(result, meta) end
                        return result
                    end
                elseif axis == "owned profile" then
                    -- Real scalar factory and real private publication callback;
                    -- meta is added before owner capture, not after snapshot.
                    local scalar = options.scalar_factory
                    options.scalar_factory = function(input)
                        local publish = input.register
                        input.register = function(name, profile)
                            if name == "cwv_shortsword_light_fencer_stab" then setmetatable(profile, meta) end
                            return publish(name, profile)
                        end
                        return scalar(input)
                    end
                end
            end })
            F.admitted(H, c)
            local target, key
            if axis == "source" then target, key = c.env.Weapons, "one_handed_daggers_template_1"
            elseif axis == "template" then target, key = c.env.Weapons, "shortsword_template"
            elseif axis == "native profile" then target, key = c.env.DamageProfileTemplates, "light_fencer_stab"
            elseif axis == "owned profile" then target, key = c.env.DamageProfileTemplates, "cwv_shortsword_light_fencer_stab"
            else target, key = c.env.PowerLevelTemplates, "review_legacy_default_target" end
            local original = rawget(target, key)
            H.truthy(rawequal(getmetatable(original), meta), "installed meta before owned capture")
            local foreign = shallow(original, meta)
            H.equal(rawequal(original, foreign), false); H.truthy(original == foreign)
            rawset(target, key, foreign); F.denied(H, c)
        end)
    end
    for _, kind in ipairs({ "profiles", "levels", "lookup", "weapons", "map" }) do
        H.test("#428 Shortsword raw observable meta rejects foreign equal-comparing " .. kind, function()
            local equality = { __eq = function() return true end }
            local original, foreign = setmetatable({}, equality), setmetatable({}, equality)
            local c = F.new(H, root, { before = function(context) setmetatable(roots(context)[kind], original) end })
            F.admitted(H, c); H.truthy(original == foreign); H.equal(rawequal(original, foreign), false)
            local object = roots(c)[kind]; setmetatable(object, foreign); F.denied(H, c)
            H.truthy(rawequal(getmetatable(object), foreign), "never repair foreign observable meta")
        end)
    end
    H.test("#428 Shortsword raw lookup precommit abort publishes no Short family", function()
        local meta, foreign = { __eq = function() return true end }
        local c = F.new(H, root, { before = function(context) setmetatable(context.lookup, meta) end,
            construction_options = function(options, context)
                local clone = options.clone
                options.clone = function(value)
                    local result = clone(value)
                    if rawequal(value, context.env.Weapons.one_handed_daggers_template_1) then
                        local original = context.env.NetworkLookup.damage_profiles
                        foreign = shallow(original, meta); H.truthy(original == foreign); H.equal(rawequal(original, foreign), false)
                        context.env.NetworkLookup.damage_profiles = foreign
                    end
                    return result
                end
            end })
        F.denied(H, c); H.truthy(c.owner.check():find("family_commit_rejected", 1, true))
        H.equal(c.env.Weapons.shortsword_template, nil)
        for _, name in ipairs({ "medium_slashing_linesman", "medium_slashing_smiter_stab", "light_fencer_stab", "dagger_1h_light_linesman", "dagger_1h_light_smiter_stab" }) do
            H.equal(c.env.DamageProfileTemplates["cwv_shortsword_" .. name], nil)
            H.equal(rawget(foreign, "cwv_shortsword_" .. name), nil)
        end
        H.truthy(rawequal(c.env.NetworkLookup.damage_profiles, foreign), "foreign root preserved")
    end)
end
