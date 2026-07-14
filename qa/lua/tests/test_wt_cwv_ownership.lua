return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_cwv_ownership.lua")
    local managed = {
        es_mercenary = { dr_shield_axe = true },
        es_knight = { dr_shield_axe = true },
    }

    H.test("WT detects absent disabled and active CWV", function()
        H.equal(policy.cwv_is_active(nil), false)
        H.equal(policy.cwv_is_active({ is_enabled = function() return false end }), false)
        H.equal(policy.cwv_is_active({ is_enabled = function() return true end }), true)
        H.equal(policy.cwv_is_active({}), true)
        H.equal(policy.cwv_is_active({ is_enabled = function() error("failed mod") end }), false)
    end)

    H.test("WT yields native Axe Shield only to active CWV", function()
        H.equal(policy.should_yield_native("es_mercenary", "dr_shield_axe", false, managed), false)
        H.equal(policy.should_yield_native("es_mercenary", "dr_shield_axe", true, managed), true)
        H.equal(policy.should_yield_native("es_mercenary", "dr_2h_axe", true, managed), false)
        H.equal(policy.should_yield_native("dr_ranger", "dr_shield_axe", true, managed), false)
    end)

    H.test("WT ownership transition reconciles unlocks and cache", function()
        local path = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_backend.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("owns_axe_shield ~= M._last_cwv_active", 1, true))
        H.truthy(source:find("apply_weapon_unlocks()", 1, true))
        H.truthy(source:find("M.refresh_on_setting_change(mod)", 1, true))
    end)
end
