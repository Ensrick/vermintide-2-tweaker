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

    H.test("CWV Combat Style clones share donor remap and wield contracts", function()
        local streams = {
            "/weapon_tweaker/scripts/mods/weapon_tweaker/",
            "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/",
        }
        local aliases = {
            { "imperial_longsword_template", "two_handed_swords_template_1" },
            { "cwv_infantry_spear_template", "two_handed_spears_elf_template_1" },
            { "cwv_combat_style_kerillian_greatsword", "two_handed_swords_wood_elf_template" },
            { "cwv_combat_style_bretonnian_greatsword", "two_handed_swords_template_1" },
            { "cwv_combat_style_saltz_bretonnian_greatsword", "bastard_sword_template" },
            { "cwv_combat_style_empire_spear_shield", "es_deus_01_template" },
            { "cwv_combat_style_elven_spear_shield", "one_handed_spears_shield_template" },
        }
        for _, stream in ipairs(streams) do
            local wield_module = dofile(repo_root .. stream .. "wt_wield_patches.lua")
            local wield = wield_module.patches
            local bulk_wield = wield_module.bulk
            local build = dofile(repo_root .. stream .. "_wt_anim_remap_data.lua")
            local remaps = build({}, {}, {})
            for _, alias in ipairs(aliases) do
                local clone_name, donor_name = alias[1], alias[2]
                H.equal(wield_module.cwv_style_donors[clone_name], donor_name)
                local donor_remap = remaps[donor_name]
                H.equal(remaps[clone_name], donor_remap)
                local donor_wield = wield[donor_name] or bulk_wield[donor_name]
                local clone_wield = wield[clone_name] or bulk_wield[clone_name]
                H.truthy(type(donor_wield) == "table")
                H.equal(clone_wield, donor_wield)
                H.equal(type(wield[clone_name]) == "table",
                    type(wield[donor_name]) == "table")
                H.equal(type(bulk_wield[clone_name]) == "table",
                    type(bulk_wield[donor_name]) == "table")
            end

            local clone = remaps.cwv_infantry_spear_template
            H.equal(clone.wh_.attack_swing_down_left_axe, "attack_swing_stab")
            H.equal(clone.we_, false)

            local clone_wield = wield.cwv_infantry_spear_template
            for _, career in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
                H.equal(clone_wield[career], "to_2h_billhook")
            end

            local longsword_wield = bulk_wield.imperial_longsword_template
            for _, career in ipairs({
                "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister",
            }) do
                H.equal(longsword_wield[career], "to_2h_sword_we")
            end
        end
    end)
end
