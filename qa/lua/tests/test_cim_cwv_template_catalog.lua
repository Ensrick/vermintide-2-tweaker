return function(H, repo_root)
    local root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local Catalog = assert(loadfile(root .. "_cim_template_catalog.lua"))()

    local families = {
        cwv_es_dual_axes = "icon_wpn_axe_hatchet_t1_dual_cwv",
        cwv_es_infantry_spear = "icon_wpn_emp_gk_spear_01_t1",
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
        end
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
