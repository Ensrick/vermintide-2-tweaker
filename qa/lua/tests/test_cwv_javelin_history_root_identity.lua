-- Raw dynamic-root identity, not Lua metamethod equivalence.
return function(H, root)
    local F = dofile(root .. "/qa/lua/fixtures/cwv_javelin_history_owner.lua")
    local function roots(c)
        return { profiles = c.env.DamageProfileTemplates, levels = c.env.PowerLevelTemplates,
            lookup = c.env.NetworkLookup.damage_profiles, weapons = c.env.Weapons }
    end
    local function replace(c, kind, value)
        if kind == "profiles" then c.env.DamageProfileTemplates = value
        elseif kind == "levels" then c.env.PowerLevelTemplates = value
        elseif kind == "lookup" then c.env.NetworkLookup.damage_profiles = value
        else c.env.Weapons = value end
    end
    local function copy(value, meta)
        local result = {}; for key, item in next, value do result[key] = item end
        return setmetatable(result, meta)
    end
    local function fixture(kind, extra)
        local meta = { __eq = function() return true end }
        local c = F.new(H, root, { before = function(context)
            setmetatable(roots(context)[kind], meta)
        end, construction_owner = extra and function(owner, context)
            local construct = owner.construct
            owner.construct = function(prepare, wields)
                return construct(function(...)
                    local ok = prepare(...); extra(context, meta); return ok
                end, wields)
            end
        end })
        return c, meta
    end
    for _, kind in ipairs({ "profiles", "levels", "lookup", "weapons" }) do
        H.test("#428 Javelin raw getter rejects equal-comparing foreign " .. kind, function()
            local c, meta = fixture(kind); c:install(); F.admitted(H, c)
            local original = roots(c)[kind]; local foreign = copy(original, meta)
            H.equal(rawequal(original, foreign), false); H.truthy(original == foreign)
            replace(c, kind, foreign); F.denied(H, c)
        end)
    end
    H.test("#428 Javelin precommit raw getter rejects equal-comparing foreign lookup", function()
        local prior
        local c = fixture("lookup", function(context, meta)
            prior = roots(context).lookup; local foreign = copy(prior, meta)
            H.equal(rawequal(prior, foreign), false); H.truthy(prior == foreign)
            replace(context, "lookup", foreign)
        end)
        c:install(); F.denied(H, c)
        H.truthy(c.owner.check():find("family_commit_rejected", 1, true))
        H.equal(c.env.Weapons.tuskgor_javelin_template, nil)
        for _, name in ipairs(c.names) do
            H.equal(rawget(c.env.DamageProfileTemplates, "cwv_tj_" .. name), nil)
            H.equal(rawget(prior, "cwv_tj_" .. name), nil)
        end
    end)
    H.test("#428 Javelin actual healthy shared metatable roots are not blanket rejected", function()
        local meta = { __eq = function() return true end }
        local c = F.new(H, root, { before = function(context)
            for _, value in pairs(roots(context)) do setmetatable(value, meta) end
        end }):install()
        F.admitted(H, c)
    end)
    local axes = { "source", "template", "native profile", "owned profile", "shared map", "preview", "native named power" }
    for _, axis in ipairs(axes) do
        H.test("#428 Javelin raw registry rejects equal-comparing foreign " .. axis, function()
            local meta, original = { __eq = function() return true end }
            local c = F.new(H, root, { before = function(context)
                local source = context.env.Weapons.javelin_template
                if axis == "source" then setmetatable(source, meta)
                elseif axis == "native profile" then setmetatable(context.env.DamageProfileTemplates[context.names[1]], meta)
                elseif axis == "shared map" then setmetatable(context.state._cwv_damage_profile_wire_source, meta)
                elseif axis == "preview" then source.wield_anim_career_3p = setmetatable({ we_waywatcher = "native" }, meta)
                elseif axis == "native named power" then
                    -- Exact existing named_default compatibility seam: this is
                    -- the actual resolved native default target, not new math.
                    local profile = context.env.DamageProfileTemplates[context.names[1]]
                    context.env.PowerLevelTemplates.review_legacy_default_target = setmetatable(profile.default_target, meta)
                    profile.default_target = "review_legacy_default_target"
                end
            end, construction_options = function(options, context)
                local clone = options.clone
                options.clone = function(value)
                    local result = clone(value)
                    if axis == "template" and rawequal(value, context.env.Weapons.javelin_template) then setmetatable(result, meta) end
                    if axis == "owned profile" and rawget(value, "charge_value") == "projectile"
                            and not rawequal(value, context.env.DamageProfileTemplates.thrown_javelin) then setmetatable(result, meta) end
                    return result
                end
            end }):install()
            F.admitted(H, c)
            local target, key
            if axis == "source" then target, key = c.env.Weapons, "javelin_template"
            elseif axis == "template" then target, key = c.env.Weapons, "tuskgor_javelin_template"
            elseif axis == "native profile" then target, key = c.env.DamageProfileTemplates, c.names[1]
            elseif axis == "owned profile" then target, key = c.env.DamageProfileTemplates, "cwv_tj_thrown_javelin"
            elseif axis == "shared map" then target, key = c.state, "_cwv_damage_profile_wire_source"
            elseif axis == "preview" then target, key = c.env.Weapons.javelin_template, "wield_anim_career_3p"
            else target, key = c.env.PowerLevelTemplates, "review_legacy_default_target" end
            original = rawget(target, key)
            H.truthy(rawequal(getmetatable(original), meta), "shared meta installed before owned snapshot")
            local foreign = copy(original, meta)
            H.equal(rawequal(original, foreign), false); H.truthy(original == foreign)
            rawset(target, key, foreign); F.denied(H, c)
        end)
    end
    H.test("#428 Javelin retained shared map metatable mutation denies without repair", function()
        local c = F.new(H, root):install(); F.admitted(H, c)
        local map, meta = c.state._cwv_damage_profile_wire_source, {}
        setmetatable(map, meta); F.denied(H, c)
        H.truthy(rawequal(c.state._cwv_damage_profile_wire_source, map)); H.truthy(rawequal(getmetatable(map), meta))
    end)
    for _, axis in ipairs({ "preview", "shared map" }) do
        H.test("#428 Javelin raw observable metatable rejects equal-comparing foreign " .. axis, function()
            local equality = { __eq = function() return true end }
            local original, foreign = setmetatable({}, equality), setmetatable({}, equality)
            local c = F.new(H, root, { before = function(context)
                if axis == "preview" then context.env.Weapons.javelin_template.wield_anim_career_3p = setmetatable({}, original)
                else setmetatable(context.state._cwv_damage_profile_wire_source, original) end
            end }):install()
            F.admitted(H, c); H.truthy(original == foreign); H.equal(rawequal(original, foreign), false)
            local object = axis == "preview" and c.env.Weapons.javelin_template.wield_anim_career_3p or c.state._cwv_damage_profile_wire_source
            setmetatable(object, foreign); F.denied(H, c)
            H.truthy(rawequal(getmetatable(object), foreign), "never repair the foreign metatable")
        end)
    end
end
