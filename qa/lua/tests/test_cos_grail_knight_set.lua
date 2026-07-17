return function(H, repo_root)
    local function read(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local module = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_grail_knight_set.lua")
    local entry = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
        .. read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_runtime_checks.lua")
    local localization = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker_localization.lua")
    local package_file = read("cosmetics_tweaker/resource_packages/cosmetics_tweaker/cosmetics_tweaker.package")

    local function with_loaded_module(callback)
        local saved = {
            get_mod = _G.get_mod,
            Cosmetics = _G.Cosmetics,
            Application = _G.Application,
            Unit = _G.Unit,
            Mesh = _G.Mesh,
            Material = _G.Material,
        }
        _G.get_mod = function() return { get = function() return true end } end
        local path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_grail_knight_set.lua"
        local set = assert(loadfile(path))()
        local ok, err = pcall(callback, set)
        _G.get_mod = saved.get_mod
        _G.Cosmetics = saved.Cosmetics
        _G.Application = saved.Application
        _G.Unit = saved.Unit
        _G.Mesh = saved.Mesh
        _G.Material = saved.Material
        if not ok then error(err, 0) end
    end

    H.test("Grail Knight set reuses exact vanilla geometry", function()
        H.truthy(module:find('M.HAT_BASE_UNIT = "units/beings/player/empire_soldier_breton/headpiece/es_gk_hat_02"', 1, true))
        H.truthy(module:find('M.SKIN_FP_UNIT = "units/beings/player/empire_soldier_breton/first_person_base/chr_first_person_mesh"', 1, true))
        H.truthy(module:find('M.SKIN_TP_UNIT = "units/beings/player/empire_soldier_breton/third_person_base/chr_third_person_mesh"', 1, true))
        H.truthy(module:find('M.SHIELD_BASE_UNIT = "units/weapons/player/wpn_emp_gk_shield_05/wpn_emp_gk_shield_05"', 1, true))
        H.equal(module:find("World.spawn_unit", 1, true), nil)
        H.equal(module:find("CUSTOM_UNIT", 1, true), nil)
    end)

    H.test("Grail Knight set keeps authored names and descriptions synchronized", function()
        local expected = {
            cos_gk_purpure_azure_hat_name = "Couronne de la Lune",
            cos_gk_purpure_azure_hat_description = "Its silvered crest recalls moonrise over Couronne, where Grail Knights keep vigil beneath the Lady's gaze and remember the vows that raised them above mortal knighthood.",
            cos_gk_purpure_azure_skin_name = "Midnight Purpure and Azure",
            cos_gk_purpure_azure_skin_description = "Once worn by a Bretonnian knight whose ardour burned brighter than good sense. Mortally wounded, he bequeathed his colours to Kruber, declaring the Grail Knight of Ubersreik worthy to bear them.",
            cos_gk_purpure_azure_shield_name = "The Blood-Bloomed Bouclier",
            cos_gk_purpure_azure_shield_description = "Kruber claims the blazon's four roses commemorate four maidens rescued, its gouttes de sang the blood spilled in their defence. The Ubersreik Five suspect the tale grows taller with every telling, but know better than to question his honesty within earshot.",
        }
        with_loaded_module(function(set)
            for key, value in pairs(expected) do
                H.equal(set.ITEM_LOCALIZATION[key], value, "runtime fallback drifted for " .. key)
                H.truthy(localization:find('en = "' .. value .. '"', 1, true),
                    "VMF localization drifted for " .. key)
            end
        end)
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
        H.truthy(module:find('M.SHIELD_BASE_UNIT_3P = M.SHIELD_BASE_UNIT .. "_3p"', 1, true))
        H.truthy(module:find("new_units = { M.SHIELD_BASE_UNIT, M.SHIELD_BASE_UNIT_3P }", 1, true))
        H.equal(module:find("add_skin_to_combination(M.SHIELD_SKIN_KEY", 1, true), nil)
        H.truthy(entry:find("for _, item_type in ipairs(LA_BRIDGE.kruber_shield_item_types or {})", 1, true))
        H.truthy(entry:find("_decorate_shield_option(GK_SET.offhand_option())", 1, true))
        for _, family in ipairs({
            "es_1h_sword_shield", "es_1h_mace_shield",
            "es_1h_sword_shield_breton", "es_deus_01",
            "cwv_es_axe_shield", "cwv_es_longsword_shield",
            "cwv_es_warpriest_hammer_shield",
        }) do
            H.truthy(entry:find(family, 1, true), "missing Kruber shield family " .. family)
        end
    end)

    H.test("Grail Knight outfit replays on each inventory hero mesh", function()
        H.truthy(module:find("function M.apply_armor_to_hero_preview(previewer)", 1, true))
        H.truthy(module:find("previewer.character_unit_skin_data or (loading and loading.skin_data)", 1, true))
        H.truthy(module:find("previewer.character_unit_hidden_after_spawn", 1, true))
        H.truthy(module:find("previewer.character_unit_visible ~= true", 1, true))
        H.truthy(module:find("previewer._cos_gk_armor_applied_mesh == mesh", 1, true))
        H.truthy(module:find("previewer._cos_gk_armor_applied_mesh = mesh", 1, true))
        H.truthy(entry:find("GK_SET.apply_armor_to_hero_preview(self)", 1, true))
    end)

    H.test("Grail Knight inventory hero replay is bounded and mesh-aware", function()
        with_loaded_module(function(set)
            local custom_skin = {}
            local mesh_a, mesh_b = {}, {}
            local writes = 0
            _G.Cosmetics = { [set.SKIN_ITEM_KEY] = custom_skin }
            _G.Application = { can_get = function(kind) return kind == "texture" end }
            _G.Unit = {
                alive = function(unit) return unit == mesh_a or unit == mesh_b end,
                has_data = function() return false end,
                num_meshes = function() return 1 end,
                mesh = function(unit) return unit end,
            }
            _G.Mesh = {
                has_material = function(_, name)
                    return name == "mtr_outfit" or name == "mtr_outfit_ds"
                end,
                material = function(mesh, name) return { mesh = mesh, name = name } end,
            }
            _G.Material = { set_texture = function() writes = writes + 1 end }
            local previewer = {
                character_unit_skin_data = custom_skin,
                mesh_unit = mesh_a,
                character_unit_hidden_after_spawn = true,
                character_unit_visible = false,
            }
            H.equal(set.apply_armor_to_hero_preview(previewer), false)
            H.equal(writes, 0, "spawn-hidden mesh must not be cached before vanilla visibility reset")
            previewer.character_unit_hidden_after_spawn = false
            previewer.character_unit_visible = true
            H.truthy(set.apply_armor_to_hero_preview(previewer))
            H.equal(writes, 6)
            H.truthy(set.apply_armor_to_hero_preview(previewer))
            H.equal(writes, 6, "same preview mesh should not repaint every frame")
            previewer.character_unit_visible = false
            H.equal(set.apply_armor_to_hero_preview(previewer), false)
            H.equal(writes, 6)
            previewer.character_unit_visible = true
            H.truthy(set.apply_armor_to_hero_preview(previewer))
            H.equal(writes, 12, "hide/show must repaint after vanilla restores donor materials")
            previewer.mesh_unit = mesh_b
            previewer.character_unit_hidden_after_spawn = true
            previewer.character_unit_visible = false
            H.equal(set.apply_armor_to_hero_preview(previewer), false)
            H.equal(writes, 12)
            previewer.character_unit_hidden_after_spawn = false
            previewer.character_unit_visible = true
            H.truthy(set.apply_armor_to_hero_preview(previewer))
            H.equal(writes, 18, "view/career respawn must repaint its new mesh once")
            H.equal(set.PREVIEW_REPLAY_CONTRACT.apply_after_visibility, true)
            H.equal(set.PREVIEW_REPLAY_CONTRACT.invalidate_while_hidden, true)
            H.equal(set.PREVIEW_REPLAY_CONTRACT.cache_identity, "mesh_unit")
        end)
    end)

    H.test("Grail Knight outfit paints armor materials without touching Markus face", function()
        with_loaded_module(function(set)
            local unit = {}
            local meshes = {
                { materials = { mtr_skin = true, mtr_eyes = true } },
                { materials = { mtr_outfit = true, mtr_outfit_ds = true } },
            }
            local writes = {}
            _G.Application = { can_get = function(kind) return kind == "texture" end }
            _G.Unit = {
                alive = function(candidate) return candidate == unit end,
                has_data = function() return false end,
                num_meshes = function() return #meshes end,
                mesh = function(_, index) return meshes[index + 1] end,
            }
            _G.Mesh = {
                has_material = function(mesh, name) return mesh.materials[name] == true end,
                material = function(mesh, name) return { mesh = mesh, name = name } end,
            }
            _G.Material = {
                set_texture = function(material, slot, texture)
                    writes[#writes + 1] = { material = material.name, slot = slot, texture = texture }
                end,
            }
            H.truthy(set.apply_variant_to_unit(set.SKIN_VARIANT_KEY, unit, "third_person"))
            H.equal(#writes, 6)
            for _, write in ipairs(writes) do
                H.truthy(write.material == "mtr_outfit" or write.material == "mtr_outfit_ds")
                H.equal(write.material == "mtr_skin" or write.material == "mtr_eyes", false)
            end
        end)
    end)

    H.test("Grail Knight outfit material drift fails closed before any write", function()
        with_loaded_module(function(set)
            local unit, writes = {}, 0
            _G.Application = { can_get = function() return true end }
            _G.Unit = {
                alive = function() return true end,
                has_data = function() return false end,
                num_meshes = function() return 1 end,
                mesh = function() return {} end,
            }
            _G.Mesh = {
                has_material = function(_, name) return name == "mtr_outfit" end,
                material = function(_, name) return { name = name } end,
            }
            _G.Material = { set_texture = function() writes = writes + 1 end }
            H.equal(set.apply_variant_to_unit(set.SKIN_VARIANT_KEY, unit, "third_person"), false)
            H.equal(writes, 0)
        end)
    end)

    H.test("Grail Knight shield descriptor distinguishes 1P and 3P receivers", function()
        with_loaded_module(function(set)
            local variant = set.resolve_variant(set.SHIELD_VARIANT_KEY)
            H.equal(variant.new_units[1], set.SHIELD_BASE_UNIT)
            H.equal(variant.new_units[2], set.SHIELD_BASE_UNIT .. "_3p")
        end)
    end)

    H.test("Grail Knight shield lifecycle covers preview, local body, swap, and husk", function()
        -- Spawn-time paint handles initial local 1P/3P equipment. The two wield
        -- hooks consume the same synced descriptor after local swaps and remote
        -- husk respawns; HeroPreviewer covers inventory reopen/equip.
        H.truthy(entry:find('GK_SET.apply_variant_to_unit(GK_SET.SHIELD_VARIANT_KEY, target, "create_equipment")', 1, true))
        H.truthy(entry:find('mod:hook_safe("SimpleInventoryExtension", "_wield_slot"', 1, true))
        H.truthy(entry:find('mod:hook("SimpleHuskInventoryExtension", "_wield_slot"', 1, true))
        H.truthy(entry:find('"hero_previewer"', 1, true))
        H.truthy(entry:find('"network_husk"', 1, true))
        H.truthy(entry:find("_resolve_authored_offhand_mesh(entry.armoury_key)", 1, true))
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
        local authored_icon_sizes = {
            hat = 12797,
            skin = 12711,
            shield = 11762,
        }
        for _, icon in ipairs({ "hat", "skin", "shield" }) do
            local key = "icon_cos_gk_purpure_azure_" .. icon
            local png_path = repo_root .. "/cosmetics_tweaker/gui/1080p/single_textures/cosmetics_tweaker/" .. key .. ".png"
            local png = io.open(png_path, "rb")
            H.truthy(png, "missing " .. key .. ".png")
            if png then
                H.equal(png:read(8), "\137PNG\r\n\26\n", key .. " must remain a PNG")
                H.equal(png:seek("end"), authored_icon_sizes[icon], key .. " reverted from the authored icon")
                png:close()
            end
            read("cosmetics_tweaker/gui/1080p/single_textures/cosmetics_tweaker/" .. key .. ".texture")
            read("cosmetics_tweaker/materials/ui/" .. key .. ".material")
            H.truthy(package_file:find('"materials/ui/' .. key .. '"', 1, true))
        end
    end)
end
