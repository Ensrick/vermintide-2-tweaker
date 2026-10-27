-- Shared fallback ownership: real producers and real nonzero history records.
return function(H, root)
    local F = dofile(root .. "/qa/lua/fixtures/cwv_shortsword_history_owner.lua")
    H.test("#428 real AuthenticPistol append preserves history-owned Shortsword admission", function()
        local c = F.new(H, root); local row = c.install_history("wt")
        F.admitted(H, c); H.equal(row.verify(), nil)
        local fallback = row.mod._wt431_custom_profile_fallback
        local Producer = assert(loadfile(root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_authentic_pistol_owner.lua"))()
        local owner, reason = Producer.install(row.mod, { globals = c.env, lookup = c.helper,
            clone = function(value) return c.env.table.clone(value, true) end })
        H.truthy(owner, reason); H.equal(owner.validate(), true); H.equal(row.verify(), nil)
        H.truthy(rawequal(row.mod._wt431_custom_profile_fallback, fallback))
        H.equal(fallback.wt_authentic_pistol, "shot_sniper"); F.admitted(H, c)
    end)
    local function prepare_native(context)
        local fixture = dofile(root .. "/qa/lua/fixtures/cwv_javelin_construction_source.lua")
        local env = setmetatable({ DamageProfileTemplates = {}, PowerLevelTemplates = {} }, { __index = context.env })
        context.T.run("DamageProfileTemplates={\n" .. fixture.donor_rows .. "\n}\n", env, "actual-four-native-Javelin-donors")
        context.T.run(fixture.resolve, env, "complete-actual-native-profile-resolution")
        for _, name in ipairs({ "heavy_javelin_smiter_stab_bleed", "medium_javelin_smiter_stab", "medium_javelin_smiter_stab_bleed", "thrown_javelin" }) do
            H.equal(rawget(context.env.DamageProfileTemplates, name), nil)
            context.env.DamageProfileTemplates[name] = assert(env.DamageProfileTemplates[name])
            local id, inserted = context.helper.register(context.lookup, name)
            H.truthy(id); H.equal(inserted, true)
        end
    end
    local function projected(context, Catalog, dagger, mod, module_root)
        local original = mod:dofile(module_root .. "_wt_history_5_2_catalog")
        local family
        for _, row in ipairs(original.families) do if row.id == "javelin" then family = row end end
        H.truthy(family)
        local javelin = {}; for key, value in next, original do javelin[key] = value end
        javelin.families, javelin.states = { family }, { ["5_1_1"] = original.states["5_1_1"] }
        javelin.profile_specs, javelin.derived_profiles = { ["5_1_1"] = {} }, {}
        for _, name in ipairs(family.states["5_1_1"].profile_names) do
            javelin.profile_specs["5_1_1"][name] = original.profile_specs["5_1_1"][name]
        end
        return Catalog.merge({ dagger, javelin })
    end
    local function nonzero()
        return F.new(H, root, { expected_registration_count = 4, project_catalog = projected,
            before = function(context, install) prepare_native(context); install("wt") end })
    end
    for _, defect in ipairs({ "replace-owned-row", "remove-owned-row", "map-object", "map-metatable", "registration-names" }) do
        H.test("#428 real nonzero history registration rejects " .. defect .. " after restore", function()
            local c = nonzero(); F.admitted(H, c)
            local row = c.histories.wt
            H.equal(row.runtime.registration.count, 4)
            H.equal(row.owner:restore(), true); H.truthy(row.verify()); F.admitted(H, c)
            local fallback, registration = row.mod._wt431_custom_profile_fallback, row.runtime.registration
            local name = registration.names[1]
            H.truthy(type(rawget(fallback, name)) == "string")
            if defect == "replace-owned-row" then fallback[name] = "foreign"
            elseif defect == "remove-owned-row" then fallback[name] = nil
            elseif defect == "map-object" then row.mod._wt431_custom_profile_fallback = {}
            elseif defect == "map-metatable" then setmetatable(fallback, {})
            else registration.names[1] = "foreign" end
            F.denied(H, c)
        end)
    end
end
