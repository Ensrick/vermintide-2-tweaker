return function(H, repo_root)
    local root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local Catalog = assert(loadfile(root .. "_cim_template_catalog.lua"))()

    local families = {
        cwv_es_dual_axes = "icon_wpn_axe_hatchet_t1_dual_cwv",
        cwv_wh_dual_axes = "icon_wpn_axe_hatchet_t1_dual_cwv",
        cwv_es_imperial_crowbill = "icon_cwv_imperial_crowbill_01",
        cwv_dr_dawi_crowbill = "icon_cwv_dawi_crowbill_01",
        cwv_es_greataxe = "icon_cwv_es_greataxe_01",
    }

    H.test("every CWV family keeps exact definition and authored icon", function()
        local iml = {}
        for key, icon in pairs(families) do
            iml[key] = {
                cwv_definition = true,
                slot_type = "melee",
                item_type = key,
                rarity = "default",
                can_wield = { "es_knight" },
                inventory_icon = icon,
                right_hand_unit = "units/test/" .. key,
            }
        end
        local cache, report = Catalog.build({
            item_master_list = iml,
            career_name = "es_knight",
            craftable_slot_types = { melee = true },
            base_power = 300,
        })
        H.equal(report.cwv, 5)
        for key, icon in pairs(families) do
            local row = cache["cim_template_" .. key]
            H.truthy(row)
            H.equal(row.cim_acquisition_key, key)
            H.equal(row.data, iml[key])
            H.equal(row.data.inventory_icon, icon)
            H.equal(row.rarity, "default")
            H.equal(row.backend_id, "cim_template_" .. key)
            H.equal(row.power_level, 5)
            H.equal(row.CustomData.power_level, "5")
        end
    end)

    H.test("accessory icons remain separate five-power selectors", function()
        local iml = {
            necklace = {
                slot_type = "necklace", item_type = "necklace", rarity = "default",
                can_wield = { "es_knight" }, inventory_icon = "necklace_01",
            },
            necklace_02 = {
                slot_type = "necklace", item_type = "necklace", rarity = "default",
                can_wield = { "es_knight" }, inventory_icon = "necklace_02",
            },
        }
        local cache, report = Catalog.build({
            item_master_list = iml,
            career_name = "es_knight",
            craftable_slot_types = { necklace = true },
            base_power = 300,
        })
        H.equal(report.total, 2)
        H.equal(cache.cim_template_necklace.power_level, 5)
        H.equal(cache.cim_template_necklace_02.power_level, 5)
    end)

    H.test("catalog enforces career and DLC ownership without acquisition", function()
        local iml = {
            cwv_owned = {
                cwv_definition = true, slot_type = "melee", item_type = "cwv_owned",
                rarity = "default", can_wield = { "es_knight" },
            },
            cwv_other_career = {
                cwv_definition = true, slot_type = "melee", item_type = "cwv_other_career",
                rarity = "default", can_wield = { "dr_ranger" },
            },
            paid_weapon = {
                slot_type = "melee", item_type = "paid_weapon", rarity = "default",
                can_wield = { "es_knight" }, required_dlc = "test_dlc",
            },
        }
        local cache = Catalog.build({
            item_master_list = iml,
            career_name = "es_knight",
            craftable_slot_types = { melee = true },
            requires_unowned_dlc = function(key) return key == "paid_weapon" end,
        })
        H.truthy(cache.cim_template_cwv_owned)
        H.equal(cache.cim_template_cwv_other_career, nil)
        H.equal(cache.cim_template_paid_weapon, nil)
        H.equal(cache.cim_template_cwv_owned.mod_data, nil)
    end)

    H.test("native helper aliases collapse to one craft family", function()
        local iml = {
            es_bastard_sword_preview = {
                slot_type = "melee", item_type = "es_bastard_sword", rarity = "plentiful",
                can_wield = { "es_knight" }, is_local = true,
            },
            vs_es_bastard_sword = {
                slot_type = "melee", item_type = "es_bastard_sword", rarity = "plentiful",
                can_wield = { "es_knight" }, mechanisms = { "versus" },
            },
            es_bastard_sword = {
                slot_type = "melee", item_type = "es_bastard_sword", rarity = "plentiful",
                can_wield = { "es_knight" },
            },
        }
        local cache, report = Catalog.build({
            item_master_list = iml,
            career_name = "es_knight",
            craftable_slot_types = { melee = true },
        })
        H.equal(report.eligible, 3)
        H.equal(report.total, 1)
        H.equal(report.suppressed, 2)
        H.truthy(cache.cim_template_es_bastard_sword)
        H.equal(cache.cim_template_es_bastard_sword_preview, nil)
        H.equal(cache.cim_template_vs_es_bastard_sword, nil)
        H.equal(cache.cim_template_es_bastard_sword.cim_acquisition_family,
            "item_type:melee:es_bastard_sword")
    end)

    H.test("CWV authored stat variants remain distinct inside shared item type", function()
        local iml = {
            cwv_es_axe_shield = {
                cwv_definition = true, cwv_key = "cwv_es_axe_shield",
                slot_type = "melee", item_type = "cwv_es_axe_shield", rarity = "default",
                can_wield = { "es_knight" },
            },
            cwv_es_axe_shield_veteran = {
                cwv_definition = true, cwv_key = "cwv_es_axe_shield_veteran",
                slot_type = "melee", item_type = "cwv_es_axe_shield", rarity = "default",
                can_wield = { "es_knight" },
            },
        }
        local cache, report = Catalog.build({
            item_master_list = iml,
            career_name = "es_knight",
            craftable_slot_types = { melee = true },
        })
        H.equal(report.total, 2)
        H.equal(report.cwv, 2)
        H.truthy(cache.cim_template_cwv_es_axe_shield)
        H.truthy(cache.cim_template_cwv_es_axe_shield_veteran)
    end)

    H.test("localization collisions never merge distinct weapon families", function()
        local iml = {
            mod_sword = {
                display_name = "shared_loc", slot_type = "melee", item_type = "mod_sword",
                rarity = "default", can_wield = { "es_knight" },
            },
            mod_axe = {
                display_name = "shared_loc", slot_type = "melee", item_type = "mod_axe",
                rarity = "default", can_wield = { "es_knight" },
            },
        }
        local cache, report = Catalog.build({
            item_master_list = iml,
            career_name = "es_knight",
            craftable_slot_types = { melee = true },
        })
        H.equal(report.total, 2)
        H.truthy(cache.cim_template_mod_sword)
        H.truthy(cache.cim_template_mod_axe)
    end)

    H.test("live career availability is re-evaluated on every catalog rebuild", function()
        local item = {
            slot_type = "melee", item_type = "mod_weapon", rarity = "default",
            can_wield = { "es_knight" },
        }
        local args = {
            item_master_list = { mod_weapon = item },
            career_name = "es_knight",
            craftable_slot_types = { melee = true },
        }
        local enabled = Catalog.build(args)
        H.truthy(enabled.cim_template_mod_weapon)
        item.can_wield = { "dr_ranger" }
        local disabled = Catalog.build(args)
        H.equal(disabled.cim_template_mod_weapon, nil)
    end)

    H.test("forge activation and cache rebuild precede vanilla on_enter", function()
        local file = assert(io.open(root .. "standard_forge.lua", "rb"))
        local source = file:read("*a")
        file:close()
        local marker = assert(source:find("#524: this MUST be a wrapping pre-hook", 1, true))
        local block = source:sub(marker, marker + 1800)
        local hook = assert(block:find('mod:hook(klass, "on_enter"', 1, true))
        local active = assert(block:find("mod._cim_standard_forge_active = true", 1, true))
        local rebuild = assert(block:find("mod._cim_rebuild_template_cache()", 1, true))
        local original = assert(block:find("func(self, ...)", 1, true))
        H.truthy(hook < active and active < rebuild and rebuild < original)
        H.equal(block:find('mod:hook_safe(klass, "on_enter"', 1, true), nil)
    end)
end
