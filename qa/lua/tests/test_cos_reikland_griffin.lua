return function(H, repo_root)
    local function read(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local provider = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_reikland_griffin.lua")
    local painter = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_grail_knight_set.lua")
    local entry = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
    local data = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker_data.lua")
    local localization = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker_localization.lua")
    local package_file = read("cosmetics_tweaker/resource_packages/cosmetics_tweaker/cosmetics_tweaker.package")
    local runtime = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_runtime_checks.lua")

    H.test("Reikland cape clones the exact vanilla Foot Knight red outfit", function()
        H.truthy(provider:find('M.BASE_KEY = "skin_es_knight_red"', 1, true))
        H.truthy(provider:find('M.VANILLA_FALLBACK = "skin_es_knight_red"', 1, true))
        H.truthy(provider:find('M.FP_UNIT = "units/beings/player/empire_soldier_knight/first_person_base/chr_first_person_mesh"', 1, true))
        H.truthy(provider:find('M.TP_UNIT = "units/beings/player/empire_soldier_knight/third_person_base/chr_third_person_mesh"', 1, true))
        H.equal(provider:find("World.spawn_unit", 1, true), nil)
        H.equal(provider:find("Unit.set_local_scale", 1, true), nil)
    end)

    H.test("Reikland cape uses one authored-outfit provider across surfaces", function()
        H.truthy(provider:find('M.PROVIDER_ID = "issue656_reikland_griffin"', 1, true))
        H.truthy(entry:find('mod._cos_reikland_provider_registered = GK_SET.add_outfit_provider(mod:dofile("scripts/mods/cosmetics_tweaker/_cos_reikland_griffin"))', 1, true))
        H.truthy(painter:find("function M.add_outfit_provider(provider)", 1, true))
        H.truthy(painter:find("function M.has_outfit_provider(provider_id)", 1, true))
        H.truthy(painter:find("function M.resolve_skin_variant(skin_data)", 1, true))
        H.truthy(painter:find('cache_identity = "mesh_unit+variant_key"', 1, true))
        H.truthy(painter:find("previewer[variant_cache_field] == variant_key", 1, true))
        H.truthy(painter:find("function M.apply_armor_to_score_preview(previewer, variant_key)", 1, true))
        H.truthy(entry:find('mod:hook_safe("PlayerUnitCosmeticExtension", "extensions_ready"', 1, true))
        H.truthy(entry:find('mod:hook_safe("HeroPreviewer", "post_update"', 1, true))
        H.truthy(entry:find("hero_previewer._cos_score_armor_variant = entry.armoury_key", 1, true))
        H.truthy(entry:find("GK_SET.apply_armor_to_score_preview(self, self._cos_score_armor_variant)", 1, true))
        H.truthy(entry:find("hero_previewer._cos_score_armor_variant = nil", 1, true))
        H.truthy(entry:find('GK_SET.apply_armor_to_owner(owner_unit, "appearance_replay", armoury_key)', 1, true))
        H.truthy(runtime:find('GK_SET.has_outfit_provider("issue656_reikland_griffin")', 1, true))
    end)

    H.test("Reikland provider registers one exact item and vanilla-safe replay mapping", function()
        local saved = {
            get_mod = _G.get_mod,
            ItemMasterList = _G.ItemMasterList,
            Cosmetics = _G.Cosmetics,
            clone = table.clone,
        }
        local added_master, added_backend
        local fake_mod = {
            get = function() return true end,
            add_mod_items_to_masterlist = function(_, items)
                added_master = items
                for _, item in ipairs(items) do _G.ItemMasterList[item.key] = item end
            end,
            add_mod_items_to_local_backend = function(_, items) added_backend = items end,
        }
        _G.get_mod = function() return fake_mod end
        _G.ItemMasterList = { skin_es_knight_red = { key = "skin_es_knight_red", rarity = "promo" } }
        _G.Cosmetics = {
            skin_es_knight_red = {
                name = "skin_es_knight_red",
                first_person_attachment = { unit = "units/beings/player/empire_soldier_knight/first_person_base/chr_first_person_mesh" },
                third_person_attachment = { unit = "units/beings/player/empire_soldier_knight/third_person_base/chr_third_person_mesh" },
            },
        }
        table.clone = function(source)
            local result = {}
            for key, value in pairs(source) do result[key] = value end
            return result
        end
        local module_path = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_reikland_griffin.lua"
        local reikland = assert(loadfile(module_path))()
        local bridge = {
            backend_to_armoury = {}, backend_to_vanilla = {}, armoury_to_backend = {},
            custom_variants = {},
        }
        local ok, err = pcall(function()
            H.truthy(reikland.register_all(bridge))
            H.equal(#added_master, 1)
            H.equal(#added_backend, 1)
            local item = added_master[1]
            H.equal(item.key, reikland.ITEM_KEY)
            H.equal(item.cos_vanilla_fallback, reikland.VANILLA_FALLBACK)
            H.equal(item.can_wield[1], "es_knight")
            H.equal(_G.Cosmetics[reikland.ITEM_KEY].name, reikland.ITEM_KEY)
            H.equal(bridge.backend_to_armoury[reikland.ITEM_KEY], reikland.VARIANT_KEY)
            H.equal(bridge.backend_to_vanilla[reikland.ITEM_KEY], reikland.VANILLA_FALLBACK)
            H.equal(bridge.armoury_to_backend[reikland.VARIANT_KEY], reikland.ITEM_KEY)
            H.truthy(bridge.custom_variants[reikland.VARIANT_KEY])
            local variant = reikland.resolve_variant(reikland.VARIANT_KEY)
            H.equal(variant.issue, 656)
            H.equal(variant.variant_key, reikland.VARIANT_KEY)
        end)
        _G.get_mod = saved.get_mod
        _G.ItemMasterList = saved.ItemMasterList
        _G.Cosmetics = saved.Cosmetics
        table.clone = saved.clone
        if not ok then error(err, 0) end
    end)

    H.test("Foot Knight packed-map and material contracts travel with the variant", function()
        H.truthy(provider:find('"texture_map_b788717c", -- combined / packed', 1, true))
        H.truthy(provider:find('armor_materials_3p = { "mtr_outfit", "mtr_outfit_ds" }', 1, true))
        H.truthy(provider:find('armor_materials_1p = { "mtr_outfit" }', 1, true))
        H.truthy(painter:find("variant.armor_slots_3p or ARMOR_3P_SLOTS", 1, true))
        H.truthy(painter:find("variant.armor_materials_1p or ARMOR_MATERIAL_NAMES", 1, true))
    end)

    H.test("Reikland cape feature is localized and default enabled", function()
        H.truthy(data:find('setting_id    = "cos_fk_reikland_griffin_enabled"', 1, true))
        H.truthy(data:find('default_value = true', 1, true))
        H.truthy(localization:find('en = "Foot Knight: Reikland Griffin Cape"', 1, true))
        H.truthy(localization:find('en = "Knights Encarmine — Reikland Griffin"', 1, true))
    end)

    H.test("Reikland authored texture set is complete and packaged", function()
        H.truthy(package_file:find('"textures/cosmetics_tweaker/reikland_griffin/*"', 1, true))
        for _, surface in ipairs({ "1p", "3p" }) do
            for _, map in ipairs({ "diffuse", "combined", "normal" }) do
                local stem = "fk_reikland_" .. surface .. "_" .. map
                local png = io.open(repo_root .. "/cosmetics_tweaker/textures/cosmetics_tweaker/reikland_griffin/" .. stem .. ".png", "rb")
                H.truthy(png, "missing " .. stem .. ".png")
                if png then
                    H.equal(png:read(8), "\137PNG\r\n\26\n", stem .. " must remain a PNG")
                    png:close()
                end
                local descriptor = read("cosmetics_tweaker/textures/cosmetics_tweaker/reikland_griffin/" .. stem .. ".texture")
                H.truthy(descriptor:find('filename = "textures/cosmetics_tweaker/reikland_griffin/' .. stem .. '"', 1, true))
            end
        end
        read("cosmetics_tweaker/tools/reikland_griffin_cape/README.md")
        read("cosmetics_tweaker/tools/reikland_griffin_cape/reikland_griffin_source_cutout.png")
        read("cosmetics_tweaker/tools/reikland_griffin_cape/reikland_griffin_source_mask.png")
    end)
end
