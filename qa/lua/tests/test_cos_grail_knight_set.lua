return function(H, repo_root)
    local function read(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local module = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_grail_knight_set.lua")
    local entry = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
    local package_file = read("cosmetics_tweaker/resource_packages/cosmetics_tweaker/cosmetics_tweaker.package")

    H.test("Grail Knight set reuses exact vanilla geometry", function()
        H.truthy(module:find('M.HAT_BASE_UNIT = "units/beings/player/empire_soldier_breton/headpiece/es_gk_hat_02"', 1, true))
        H.truthy(module:find('M.SKIN_FP_UNIT = "units/beings/player/empire_soldier_breton/first_person_base/chr_first_person_mesh"', 1, true))
        H.truthy(module:find('M.SKIN_TP_UNIT = "units/beings/player/empire_soldier_breton/third_person_base/chr_third_person_mesh"', 1, true))
        H.truthy(module:find('M.SHIELD_BASE_UNIT = "units/weapons/player/wpn_emp_gk_shield_05/wpn_emp_gk_shield_05"', 1, true))
        H.equal(module:find("World.spawn_unit", 1, true), nil)
        H.equal(module:find("CUSTOM_UNIT", 1, true), nil)
    end)

    H.test("Grail Knight set uses per-unit texture bindings and wire fallbacks", function()
        H.truthy(module:find("pcall(Unit.set_texture_for_materials", 1, true))
        H.truthy(module:find("bridge.backend_to_vanilla[row[1]] = row[3]", 1, true))
        H.truthy(module:find("bridge.custom_variants[row[2]] = true", 1, true))
        H.truthy(module:find("mod._cos.custom_skin_keys[M.SHIELD_SKIN_KEY] = true", 1, true))
        H.truthy(entry:find("GK_SET.apply_armor_to_owner", 1, true))
        H.truthy(entry:find("GK_SET.apply_variant_to_unit", 1, true))
        H.truthy(entry:find('mod:hook_safe("PlayerUnitCosmeticExtension", "extensions_ready"', 1, true))
        H.truthy(entry:find('mod:hook_safe("HeroPreviewer", "post_update"', 1, true))
        H.truthy(entry:find('GK_SET.apply_variant_to_unit(cached.armoury_key, spawned_hat, "remote_husk")', 1, true))
    end)

    H.test("Grail Knight shield is a reusable independent Kruber offhand", function()
        H.truthy(module:find("function M.offhand_option()", 1, true))
        H.truthy(module:find("la_armoury_key = M.SHIELD_VARIANT_KEY", 1, true))
        H.truthy(module:find("intended_unit = M.SHIELD_BASE_UNIT", 1, true))
        H.truthy(module:find("inventory_icon = M.ICONS.shield", 1, true))
        H.truthy(module:find("new_units = { M.SHIELD_BASE_UNIT, M.SHIELD_BASE_UNIT }", 1, true))
        H.equal(module:find("add_skin_to_combination(M.SHIELD_SKIN_KEY", 1, true), nil)
        H.truthy(entry:find("for _, item_type in ipairs(LA_BRIDGE.kruber_shield_item_types or {})", 1, true))
        H.truthy(entry:find("hands.left_hand_unit[#hands.left_hand_unit + 1] = GK_SET.offhand_option()", 1, true))
        for _, family in ipairs({
            "es_1h_sword_shield", "es_1h_mace_shield",
            "es_1h_sword_shield_breton", "es_deus_01",
            "cwv_es_axe_shield", "cwv_es_longsword_shield",
            "cwv_es_warpriest_hammer_shield",
        }) do
            H.truthy(entry:find(family, 1, true), "missing Kruber shield family " .. family)
        end
    end)

    H.test("authored offhand resolver composes canonical model before material", function()
        H.truthy(entry:find("local function _resolve_authored_offhand_variant", 1, true))
        H.truthy(entry:find("local function _resolve_authored_offhand_mesh", 1, true))
        H.truthy(entry:find("local function _apply_authored_offhand_to_unit", 1, true))
        H.truthy(entry:find("variant.new_units and variant.new_units[1]", 1, true))
        H.truthy(entry:find("_resolve_authored_offhand_mesh(entry.armoury_key)", 1, true))
        H.truthy(entry:find("_resolve_authored_offhand_mesh(opt.la_armoury_key)", 1, true))
        H.truthy(entry:find("_apply_authored_offhand_to_unit(", 1, true))
        -- Local preview/body and remote husk must consume the same descriptor.
        H.truthy(entry:find('"loot_previewer"', 1, true))
        H.truthy(entry:find('"hero_previewer"', 1, true))
        H.truthy(entry:find('"ingame"', 1, true))
        H.truthy(entry:find('"network_husk"', 1, true))
    end)

    H.test("Grail Knight authored resources are packaged", function()
        H.truthy(package_file:find('"textures/cosmetics_tweaker/grail_knight_set/*"', 1, true))
        for _, name in ipairs({
            "gk_hat_diffuse", "gk_hat_combined", "gk_hat_normal",
            "gk_outfit_1p_diffuse", "gk_outfit_1p_combined", "gk_outfit_1p_normal",
            "gk_outfit_3p_diffuse", "gk_outfit_3p_combined", "gk_outfit_3p_normal",
            "gk_shield_diffuse", "gk_shield_combined", "gk_shield_normal",
        }) do
            local png = io.open(repo_root .. "/cosmetics_tweaker/textures/cosmetics_tweaker/grail_knight_set/" .. name .. ".png", "rb")
            H.truthy(png, "missing " .. name .. ".png")
            if png then png:close() end
            read("cosmetics_tweaker/textures/cosmetics_tweaker/grail_knight_set/" .. name .. ".texture")
        end
        for _, icon in ipairs({ "hat", "skin", "shield" }) do
            local key = "icon_cos_gk_purpure_azure_" .. icon
            read("cosmetics_tweaker/gui/1080p/single_textures/cosmetics_tweaker/" .. key .. ".texture")
            read("cosmetics_tweaker/materials/ui/" .. key .. ".material")
            H.truthy(package_file:find('"materials/ui/' .. key .. '"', 1, true))
        end
    end)
end
