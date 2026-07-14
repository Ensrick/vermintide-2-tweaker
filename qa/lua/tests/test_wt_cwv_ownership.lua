return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_cwv_ownership.lua")
    local managed = {
        es_mercenary = { dr_shield_axe = true, dr_2h_axe = true },
        es_knight = { dr_shield_axe = true },
        wh_captain = { dr_shield_axe = true, dr_2h_axe = true },
    }

    H.test("WT detects absent disabled and active CWV", function()
        H.equal(policy.cwv_is_active(nil), false)
        H.equal(policy.cwv_is_active({ is_enabled = function() return false end }), false)
        H.equal(policy.cwv_is_active({ is_enabled = function() return true end }), true)
        H.equal(policy.cwv_is_active({}), true)
        H.equal(policy.cwv_is_active({ is_enabled = function() error("failed mod") end }), false)
    end)

    H.test("WT yields native Axe Shield only to active CWV", function()
        H.equal(policy.should_yield_native("es_mercenary", "dr_shield_axe", false, managed, true), false)
        H.equal(policy.should_yield_native("es_mercenary", "dr_shield_axe", true, managed, true), true)
        H.equal(policy.should_yield_native("es_mercenary", "dr_shield_axe", true, managed, false), false)
        H.equal(policy.should_yield_native("es_mercenary", "dr_2h_axe", true, managed, true), true)
        H.equal(policy.should_yield_native("es_mercenary", "dr_2h_axe", true, managed, false), false)
        H.equal(policy.should_yield_native("wh_captain", "dr_shield_axe", false, managed, true), false)
        H.equal(policy.should_yield_native("wh_captain", "dr_shield_axe", true, managed, true), true)
        H.equal(policy.should_yield_native("wh_priest", "dr_shield_axe", true, managed, true), false)
        H.equal(policy.should_yield_native("dr_ranger", "dr_shield_axe", true, managed, true), false)
    end)

    H.test("WT requires exact CWV replacement registration before yielding", function()
        local iml = {
            cwv_es_axe_shield = { cwv_variant = true },
            cwv_es_axe_shield_veteran = { cwv_variant = true },
            cwv_es_greataxe = { cwv_variant = true },
        }
        H.equal(policy.replacement_ready(iml, "dr_shield_axe"), true)
        H.equal(policy.replacement_ready(iml, "dr_2h_axe"), true)
        iml.cwv_es_greataxe.cwv_variant = nil
        H.equal(policy.replacement_ready(iml, "dr_2h_axe"), false)
        H.equal(policy.replacement_ready(iml, "dr_shield_axe"), true)
    end)

    H.test("WT ownership transition reconciles unlocks and cache", function()
        local path = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_backend.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("owns_axe_shield ~= M._last_cwv_active", 1, true))
        H.truthy(source:find("axe_shield_ready ~= M._last_cwv_axe_shield_ready", 1, true))
        H.truthy(source:find("greataxe_ready ~= M._last_cwv_greataxe_ready", 1, true))
        H.truthy(source:find('replacement_ready(ItemMasterList, "dr_2h_axe")', 1, true))
        H.truthy(source:find('replacement_ready(ItemMasterList, "dr_shield_axe")', 1, true))
        H.truthy(source:find("apply_weapon_unlocks()", 1, true))
        H.truthy(source:find("patch_career_actions_on_weapons()", 1, true))
        H.truthy(source:find("M.refresh_on_setting_change(mod)", 1, true))
    end)
end
