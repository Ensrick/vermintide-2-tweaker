return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_greataxe.lua")

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("CWV #597 Greataxe replaces Poleaxe with exact Bardin behavior", function()
        H.equal(policy.ITEM_KEY, "cwv_es_greataxe")
        H.equal(policy.BASE_WEAPON, "dr_2h_axe")
        H.equal(policy.TEMPLATE_KEY, "cwv_greataxe_template")
        local source = read(repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua")
        H.truthy(source:find("table.clone(Weapons.two_handed_axes_template_1, true)", 1, true))
        H.equal(source:find("_POLEAXE_SPEED_MULT", 1, true), nil)
        H.equal(source:find("_POLEAXE_POWER_MULT", 1, true), nil)
        H.equal(source:find('item_key        = "cwv_es_poleaxe"', 1, true), nil)
    end)

    H.test("CWV #597 Greataxe uses WT's exact Kruber 3P redirects", function()
        H.equal(policy.ANIM_REMAP_3P.attack_swing_up, "attack_swing_left")
        H.equal(policy.ANIM_REMAP_3P.attack_swing_heavy_left_diagonal, "attack_swing_heavy")
        H.equal(policy.ANIM_REMAP_3P.attack_swing_heavy_right_diagonal, "attack_swing_heavy_right")
        local source = read(repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_anim_remap_data.lua")
        H.truthy(source:find('attack_swing_up                   = "attack_swing_left"', 1, true))
        H.truthy(source:find('attack_swing_heavy_left_diagonal  = "attack_swing_heavy"', 1, true))
        H.truthy(source:find('attack_swing_heavy_right_diagonal = "attack_swing_heavy_right"', 1, true))
    end)

    H.test("CWV #597 Greataxe authors Kruber and WT controls all careers", function()
        H.equal(#policy.DEFAULT_CAREERS, 4)
        H.equal(#policy.ALL_CAREERS, 20)
        H.equal(#policy.conditional_careers(), 16)
        local catalog = dofile(repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/wt_cwv_variant_catalog.lua")
        local row
        for _, candidate in ipairs(catalog) do
            if candidate.key == policy.ITEM_KEY then row = candidate; break end
        end
        H.truthy(row)
        H.equal(#row.careers, 20)
        H.equal(#row.default_careers, 4)
        H.equal(#row.authored_careers, 4)
        H.equal(#row.conditional_careers, 16)
    end)

    H.test("CWV #597 packages five exact licensed model rows", function()
        H.equal(#policy.MODELS, 5)
        for index, model in ipairs(policy.MODELS) do
            local id = string.format("%02d", index)
            local unit_root = "units/cwv_es_greataxe/axe_" .. id .. "/axe_" .. id
            H.equal(model.key, "cwv_es_greataxe_skin_" .. id)
            H.equal(model.display_name, "Greataxe Model " .. id)
            H.equal(model.right_hand_unit, unit_root)
            for _, suffix in ipairs({ ".fbx", ".unit", "_3p.fbx", "_3p.unit", ".material", ".package", "_3p.package", "_assets.package" }) do
                local handle = io.open(repo_root .. "/character_weapon_variants/" .. unit_root .. suffix, "rb")
                H.truthy(handle, unit_root .. suffix .. " must be packaged")
                if handle then handle:close() end
            end
        end
    end)

    H.test("CWV #597 Greataxe model manifest rejects incomplete rows", function()
        local original = policy.MODELS
        policy.MODELS = {}
        for _, row in ipairs(original) do policy.MODELS[#policy.MODELS + 1] = row end
        policy.MODELS[#policy.MODELS + 1] = { key = "missing_name", right_hand_unit = "units/test" }
        policy.MODELS[#policy.MODELS + 1] = {
            key = "cwv_es_greataxe_skin_test",
            display_name = "Greataxe Test Model",
            right_hand_unit = "units/cwv_es_greataxe/axe_test/axe_test",
        }
        local usable = policy.usable_models()
        H.equal(#usable, #original + 1)
        H.equal(usable[#usable].key, "cwv_es_greataxe_skin_test")
        policy.MODELS = original
    end)
end
