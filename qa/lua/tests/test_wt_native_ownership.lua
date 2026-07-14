return function(H, repo_root)
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local unlocks = dofile(root .. "wt_unlock_data.lua")
    local data = read(root .. "weapon_tweaker_data.lua")
    local loc = read(root .. "weapon_tweaker_localization.lua")
    local availability = read(root .. "_wt_availability.lua")
    local entry = read(root .. "weapon_tweaker.lua")
    local careers = { "wh_captain", "wh_bountyhunter", "wh_zealot" }

    local function contains(values, wanted)
        for _, value in ipairs(values or {}) do
            if value == wanted then return true end
        end
        return false
    end

    H.test("Saltzpyre uses Empire Mace Shield instead of Bardin Hammer Shield", function()
        for _, career in ipairs(careers) do
            local weapons = unlocks.weapon_unlock_map[career]
            H.equal(contains(weapons, "es_mace_shield"), true, career .. " lost Empire pair")
            H.equal(contains(weapons, "dr_shield_hammer"), false, career .. " retained Bardin pair")
        end
    end)

    H.test("removed Bardin ownership has no menu or localization row", function()
        for _, career in ipairs(careers) do
            local setting = "unlock_" .. career .. "_dr_shield_hammer"
            H.equal(data:find(setting, 1, true), nil)
            H.equal(loc:find(setting, 1, true), nil)
        end
    end)

    H.test("stale Saltzpyre Hammer Shield ownership is scrubbed", function()
        local _, tombstones = availability:gsub('"dr_dual_wield_axes", "dr_shield_hammer"', "")
        H.equal(tombstones, 3)
        H.truthy(entry:find('issue594_saltzpyre_hammer_shield_ownership', 1, true))
        H.truthy(entry:find('is_mod_unlocked_weapon(career, "dr_shield_hammer")', 1, true))
    end)

    H.test("CWV changes only Saltzpyre Axe Shield ownership", function()
        for _, career in ipairs(careers) do
            H.equal(unlocks.cwv_managed, nil)
            local managed = unlocks.cwv_conditional_managed[career]
            H.truthy(managed)
            H.equal(managed.dr_shield_axe, true)
            H.equal(managed.dr_shield_hammer, nil)
            H.equal(managed.dr_dual_wield_axes, nil)
        end
    end)
end
