return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_property_value_policy.lua")
    local function near(actual, expected, epsilon, message)
        H.truthy(type(actual) == "number"
            and math.abs(actual - expected) <= epsilon,
            (message or "numbers differ") .. ": expected " .. tostring(expected)
                .. ", got " .. tostring(actual))
    end

    H.test("CIM Athanor attack speed stores the literal forged percentage", function()
        local range = { 0.03, 0.05 }
        near(policy.storage_for_bubbles(range, 0.05, 3, 5), 0, 0.000001)
        near(policy.storage_for_bubbles(range, 0.05, 4, 5), 0.5, 0.000001)
        near(policy.storage_for_bubbles(range, 0.05, 5, 5), 1, 0.000001)

        local stored = policy.storage_for_bubbles(range, 0.05, 3, 5)
        local actual = range[1] + (range[2] - range[1]) * stored
        near(actual, 0.03, 0.000001)
    end)

    H.test("CIM Athanor normalized zero seeds as the valid low endpoint", function()
        local range = { 0.03, 0.05 }
        H.equal(policy.bubbles_for_storage(range, 0.05, 0, 5), 3)
        H.equal(policy.bubbles_for_storage(range, 0.05, 0.5, 5), 4)
        H.equal(policy.bubbles_for_storage(range, 0.05, 1, 5), 5)
    end)

    H.test("CIM Athanor conversion handles descending signed property ranges", function()
        local range = { -0.20, -0.30 }
        local stored = policy.storage_for_bubbles(range, -0.30, 4, 5)
        near(stored, 0.4, 0.000001)
        H.equal(policy.bubbles_for_storage(range, -0.30, stored, 5), 4)
    end)

    H.test("CIM Athanor policy declines scalar and discrete property shapes", function()
        H.equal(policy.storage_for_bubbles(0.05, 0.05, 3, 5), nil)
        H.equal(policy.storage_for_bubbles({ 1, 1, 1, 2, 2 }, 2, 1, 5), nil)
        H.equal(policy.bubbles_for_storage(0.05, 0.05, 0.6, 5), nil)
    end)

    H.test("CIM production wires symmetric issue 244 conversion", function()
        local path = repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua"
        -- The entry still publishes the policy singleton and its marker; the two
        -- CALL sites are the bubble-cap math, which moved into
        -- `_cim_weave_loadout_owner` at v0.8.120-dev (#1159) byte-identical. The
        -- needles follow the code, with entry-side absence pinning the split.
        local weave_path = repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_weave_loadout_owner.lua"
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a")
        f:close()
        f = assert(io.open(weave_path, "rb"))
        local weave_source = f:read("*a")
        f:close()
        H.truthy(source:find("CIM244_PROPERTY_VALUE_POLICY_MARKER_v0_8_74", 1, true))
        H.truthy(source:find("mod._cim244_property_value_policy = mod:dofile(", 1, true))
        H.truthy(weave_source:find("policy.storage_for_bubbles", 1, true))
        H.truthy(weave_source:find("policy.bubbles_for_storage", 1, true))
        H.equal(source:find("policy.storage_for_bubbles", 1, true), nil)
        H.equal(source:find("policy.bubbles_for_storage", 1, true), nil)
    end)
end
