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
    local data = read(root .. "weapon_tweaker_data.lua")
    local availability = read(root .. "_wt_availability.lua")
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
        H.equal(#catalog, 29)
        local seen = {}
        for _, row in ipairs(catalog) do
            H.equal(seen[row.key], nil, row.key)
            seen[row.key] = true
            H.truthy(type(row.careers) == "table" and #row.careers > 0, row.key)
        end
        H.truthy(data:find('default_value = true', 1, true))
        H.truthy(availability:find("item.cwv_variant == true", 1, true))
        H.truthy(availability:find('mod:get("unlock_cwv_variant_" .. variant.key)', 1, true))
    end)

    H.test("issue368 WT performs a deferred final write", function()
        H.truthy(entry:find("mod._wt368_deferred_availability = true", 1, true))
        H.truthy(backend:find("if mod._wt368_deferred_availability then", 1, true))
        H.truthy(backend:find("apply_weapon_unlocks()", 1, true))
    end)
end
