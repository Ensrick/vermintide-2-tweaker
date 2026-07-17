return function(H, repo_root)
    local adapter = dofile(repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_cwv_effective_template.lua")

    local weapons = {
        one_handed_sword_shield_template_1 = {},
        one_handed_sword_shield_template_2 = {},
        one_handed_swords_template_1 = {},
    }

    H.test("WT consumes CWV effective Sword and Shield donors in both directions", function()
        local calls = {}
        local cwv = {
            is_enabled = function() return true end,
            get_effective_combat_style_template_name = function(item, backend_id,
                    owner_unit, slot_name)
                calls[#calls + 1] = { item = item.name, backend_id = backend_id,
                    owner_unit = owner_unit, slot_name = slot_name }
                if item.name == "es_sword_shield" then
                    return "one_handed_sword_shield_template_2"
                end
                if item.name == "es_sword_shield_breton" then
                    return "one_handed_sword_shield_template_1"
                end
            end,
        }
        local empire = { name = "es_sword_shield", backend_id = "empire_uuid",
            template = "one_handed_sword_shield_template_1" }
        local bretonnian = { name = "es_sword_shield_breton", backend_id = "bret_uuid",
            template = "one_handed_sword_shield_template_2" }

        H.equal(adapter.resolve(empire, cwv, weapons, "owner_a", "slot_melee"),
            "one_handed_sword_shield_template_2")
        H.equal(adapter.resolve(bretonnian, cwv, weapons, "owner_b", "slot_melee"),
            "one_handed_sword_shield_template_1")
        H.equal(calls[1].backend_id, "empire_uuid")
        H.equal(calls[1].owner_unit, "owner_a")
        H.equal(calls[2].slot_name, "slot_melee")
    end)

    H.test("WT effective-template consumer preserves native fallback fail closed", function()
        local native = { name = "es_1h_sword", backend_id = "native_uuid",
            template = "one_handed_swords_template_1" }
        H.equal(adapter.resolve(native, nil, weapons), native.template)
        H.equal(adapter.resolve(native, {}, weapons), native.template)
        H.equal(adapter.resolve(native, {
            is_enabled = function() return false end,
            get_effective_combat_style_template_name = function()
                return "one_handed_sword_shield_template_2"
            end,
        }, weapons), native.template)
        H.equal(adapter.resolve(native, {
            get_effective_combat_style_template_name = function() error("provider failure") end,
        }, weapons), native.template)
        H.equal(adapter.resolve(native, {
            get_effective_combat_style_template_name = function() return "unknown_template" end,
        }, weapons), native.template)
        H.equal(adapter.resolve(native, {
            get_effective_combat_style_template_name = function() return nil end,
        }, weapons), native.template)
    end)

    H.test("WT wield state uses only the shared CWV template-name contract", function()
        local function read(relative)
            local file = assert(io.open(repo_root .. relative, "rb"))
            local source = file:read("*a")
            file:close()
            return source
        end
        local public = read("/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_anim_remap.lua")
        local dev = read("/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_anim_remap.lua")
        for _, source in ipairs({ public, dev }) do
            H.truthy(source:find("_cwv_effective_template.resolve(item_data, cwv,", 1, true))
            H.equal(source:find('item_data.name == "es_sword_shield"', 1, true), nil)
            H.equal(source:find('item_data.name == "es_sword_shield_breton"', 1, true), nil)
        end
    end)
end
