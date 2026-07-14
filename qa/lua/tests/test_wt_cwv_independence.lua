return function(H, repo_root)
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local unlocks = dofile(root .. "wt_unlock_data.lua")
    local catalog = dofile(root .. "wt_cwv_variant_catalog.lua")
    local policy = dofile(root .. "_wt_cwv_availability_policy.lua")
    local data = read(root .. "weapon_tweaker_data.lua")
    local availability = read(root .. "_wt_availability.lua")
    local localization = read(root .. "weapon_tweaker_localization.lua")
    local entry = read(root .. "weapon_tweaker.lua")
    local backend = read(root .. "weapon_tweaker_backend.lua")
    local careers = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }

    local function contains(values, wanted)
        for _, value in ipairs(values or {}) do
            if value == wanted then return true end
        end
        return false
    end

    H.test("issue368 removes legacy cwv cede ownership", function()
        H.equal(unlocks.cwv_managed, nil)
        H.equal(availability:find("local _cwv_managed", 1, true), nil)
        H.equal(availability:find("legacy_skip", 1, true), nil)
        H.equal(entry:find("mod._wt.cwv_managed", 1, true), nil)
    end)

    H.test("issue368 exposes all three Saltzpyre overlaps on Kruber", function()
        for _, career in ipairs(careers) do
            for _, key in ipairs({ "wh_1h_axe", "wh_1h_falchion", "wh_dual_wield_axe_falchion" }) do
                H.equal(contains(unlocks.weapon_unlock_map[career], key), true, career .. "/" .. key)
                H.truthy(data:find("unlock_" .. career .. "_" .. key, 1, true))
            end
        end
        H.truthy(data:find("local _cwv_overlap_default = _cwv_present", 1, true))
    end)

    H.test("issue368 CWV clone catalog is bounded and marker-gated", function()
        H.equal(#catalog, 33)
        local seen = {}
        for _, row in ipairs(catalog) do
            H.equal(seen[row.key], nil, row.key)
            seen[row.key] = true
            H.truthy(type(row.careers) == "table" and #row.careers > 0, row.key)
        end
        H.truthy(data:find('default_value = true', 1, true))
        H.truthy(availability:find("item.cwv_variant == true", 1, true))
        H.truthy(availability:find("_cwv_availability_policy.is_enabled", 1, true))
    end)

    H.test("issue391 builds one compatible master and exact career toggles per CWV item", function()
        local rows = policy.build_widgets(catalog)
        H.equal(#rows, #catalog)
        local seen = {}
        local child_count = 0
        for index, row in ipairs(rows) do
            local variant = catalog[index]
            H.equal(row.setting_id, "unlock_cwv_variant_" .. variant.key)
            H.equal(row.type, "checkbox")
            H.equal(row.default_value, true)
            H.equal(#row.sub_widgets, #variant.careers)
            for child_index, child in ipairs(row.sub_widgets) do
                local career = variant.careers[child_index]
                local expected = "unlock_cwv_variant_" .. career .. "_" .. variant.key
                H.equal(child.setting_id, expected)
                H.equal(child.type, "checkbox")
                local expected_default = true
                if variant.default_careers then
                    expected_default = contains(variant.default_careers, career)
                end
                H.equal(child.default_value, expected_default)
                H.equal(seen[expected], nil, expected)
                seen[expected] = true
                child_count = child_count + 1
            end
        end
        local expected_children = 0
        for _, variant in ipairs(catalog) do
            expected_children = expected_children + #variant.careers
        end
        H.equal(child_count, expected_children)
    end)

    H.test("CWV #596 Infantry Spear controls default to three Kruber careers", function()
        local by_key = {}
        for _, row in ipairs(catalog) do by_key[row.key] = row end
        local row = by_key.cwv_es_infantry_spear
        H.truthy(row)
        H.equal(#row.careers, 20)
        H.equal(#row.default_careers, 3)
        H.equal(#row.authored_careers, 3)
        H.equal(#row.conditional_careers, 17)
        H.equal(contains(row.default_careers, "es_questingknight"), false)
        H.equal(contains(row.conditional_careers, "es_questingknight"), true)
        H.equal(contains(row.careers, "bw_necromancer"), true)
        H.truthy(availability:find("variant.authored_careers or {}", 1, true))
    end)

    H.test("issue593 Empire Axe Shield replaces Saltz native fallback only while CWV is active", function()
        local by_key = {}
        for _, row in ipairs(catalog) do by_key[row.key] = row end
        for _, key in ipairs({ "cwv_es_axe_shield", "cwv_es_axe_shield_veteran" }) do
            local row = by_key[key]
            H.truthy(row, key)
            H.equal(#row.careers, 7)
            H.equal(#row.conditional_careers, 3)
            for _, career in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
                H.equal(contains(row.careers, career), true, key .. "/" .. career)
                H.equal(contains(row.conditional_careers, career), true, key .. "/conditional/" .. career)
                H.equal(unlocks.cwv_conditional_managed[career].dr_shield_axe, true)
            end
            H.equal(contains(row.careers, "wh_priest"), false)
        end
        H.truthy(availability:find("variant.conditional_careers or {}", 1, true))
        H.truthy(availability:find("_career_action_injections[item.template]", 1, true))
    end)

    H.test("issue391 policy composes legacy item master with exact career choice", function()
        local values = {
            unlock_cwv_variant_cwv_es_dual_axes = true,
            unlock_cwv_variant_es_knight_cwv_es_dual_axes = true,
            unlock_cwv_variant_es_questingknight_cwv_es_dual_axes = false,
        }
        local function get(setting_id) return values[setting_id] end
        H.equal(policy.is_enabled(get, "cwv_es_dual_axes", "es_knight"), true)
        H.equal(policy.is_enabled(get, "cwv_es_dual_axes", "es_questingknight"), false)
        values.unlock_cwv_variant_cwv_es_dual_axes = false
        H.equal(policy.is_enabled(get, "cwv_es_dual_axes", "es_knight"), false)
        H.equal(policy.is_enabled(nil, "cwv_es_dual_axes", "es_knight"), false)
    end)

    H.test("issue391 production consumes shared schema in data runtime and localization", function()
        H.truthy(data:find("policy.build_widgets(catalog)", 1, true))
        H.truthy(availability:find("_cwv_availability_policy.is_enabled", 1, true))
        H.truthy(localization:find("_cwv_availability_policy.career_setting_id", 1, true))
        H.truthy(localization:find('es_knight = "Foot Knight"', 1, true))
        H.truthy(localization:find('wh_priest = "Warrior Priest"', 1, true))
    end)

    H.test("issue368 WT performs a deferred final write", function()
        H.truthy(entry:find("mod._wt368_deferred_availability = true", 1, true))
        H.truthy(backend:find("if mod._wt368_deferred_availability then", 1, true))
        H.truthy(backend:find("apply_weapon_unlocks()", 1, true))
    end)
end
