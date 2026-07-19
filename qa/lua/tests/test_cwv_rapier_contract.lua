return function(H, repo_root)
    local contract = dofile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_rapier_contract.lua")

    H.test("CWV pistol-less Rapier removes the inherited ammo contract", function()
        local never = function() return false end
        local base = {
            ammo_data = { ammo_hand = "left", max_ammo = 8 },
            actions = {
                action_one = { light = { kind = "sweep" } },
                action_three = { shoot = { kind = "handgun" } },
            },
        }
        local clone = {
            ammo_data = { ammo_hand = base.ammo_data.ammo_hand, max_ammo = base.ammo_data.max_ammo },
            actions = {
                action_one = { light = { kind = base.actions.action_one.light.kind } },
                action_three = { shoot = { kind = base.actions.action_three.shoot.kind } },
            },
        }

        H.truthy(contract.disable_pistol(clone, never))
        H.equal(clone.ammo_data, nil)
        H.equal(clone.actions.action_three.shoot.condition_func, never)
        H.equal(clone.actions.action_three.shoot.chain_condition_func, never)
        H.equal(clone.actions.action_one.light.kind, "sweep")

        -- The native Saltzpyre Rapier is the donor, not the mutation target.
        H.equal(base.ammo_data.ammo_hand, "left")
        H.equal(base.actions.action_three.shoot.condition_func, nil)
    end)

    H.test("CWV Rapier pistol disable is nil-safe", function()
        H.equal(contract.disable_pistol(nil, function() return false end), false)
        H.truthy(contract.disable_pistol({}, function() return false end))
    end)

    H.test("CWV Rapier definition declares no ammo item-entry contract", function()
        local source = assert(io.open(repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_variant_catalog.lua", "rb"))
        local text = source:read("*a")
        source:close()

        local rapier_at = assert(text:find('item_key        = "cwv_es_rapier"', 1, true))
        local next_def = text:find('item_key        = "cwv_es_dual_swords"', rapier_at, true) or #text
        local rapier_block = text:sub(rapier_at, next_def)

        H.truthy(rapier_block:find('template        = "rapier_template"', 1, true))
        H.truthy(rapier_block:find("no_left_hand    = true", 1, true))
        H.truthy(rapier_block:find("no_ammo_unit    = true", 1, true))
    end)

    H.test("CWV Rapier production constructor applies the pistol-less contract", function()
        local source = assert(io.open(repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua", "rb"))
        local text = source:read("*a")
        source:close()

        local constructor_at = assert(text:find("local function _create_rapier_template()", 1, true))
        local next_section = text:find("-- ============================================================", constructor_at + 1, true) or #text
        local constructor = text:sub(constructor_at, next_section)

        H.truthy(constructor:find("local template = table.clone(Weapons.fencing_sword_template_1, true)", 1, true))
        H.truthy(constructor:find("_om.rapier_contract.disable_pistol(template, _always_false)", 1, true))
        H.truthy(constructor:find("Weapons.rapier_template = template", 1, true))
    end)
end
