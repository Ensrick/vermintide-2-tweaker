return function(H, repo_root)
    local function read(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local module = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_grail_knight_set.lua")
    local entry_only = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
    -- #1159: the four attachment-slot LA spawn/sync seams (husk hat create, local
    -- go-init, resync, hot join) moved verbatim out of the entry, taking the
    -- career-exact name substitution and the Grail Knight husk variant paint with
    -- them, so the owner joins the source this test reads.
    local attachment_spawn_sync =
        read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_attachment_spawn_sync.lua")
    -- #1159: the live equipment-assembly seam (GearUtils.create_equipment and the
    -- BackendUtils.get_item_units resolution it brackets) moved verbatim out of
    -- the entry, taking the create_equipment shield-variant paint and the husk
    -- authored-mesh resolve with it, so that owner joins the source too.
    local equipment_assembly =
        read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_equipment_assembly.lua")
    -- #1159: the unified LA apply core moved verbatim out of the entry, taking
    -- the appearance-replay armor and hat-variant paints (apply_armor_to_owner /
    -- apply_variant_to_unit) with it, so that owner joins the source too.
    local la_apply_runtime =
        read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_apply_runtime.lua")
    -- #1159: the LA loadout-state hooks and the two vanilla-RPC net-safe senders
    -- moved verbatim out of the entry, taking `_la_vanilla_fallback` (the sole
    -- caller of GK_SET.wire_fallback) and every one of its call sites with them,
    -- so that owner joins the source too.
    local la_loadout_safety =
        read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_loadout_safety.lua")
    local local_wield_runtime =
        read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_local_wield_runtime.lua")
    local husk_wield_runtime =
        read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_husk_wield_runtime.lua")
    local entry = entry_only
        .. read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_preview_runtime.lua")
        .. read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_offhand_catalog.lua")
        .. read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_offhand_state_runtime.lua")
        .. read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_offhand_apply_runtime.lua")
        .. read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_runtime_checks.lua")
        .. attachment_spawn_sync
        .. equipment_assembly
        .. la_apply_runtime
        .. la_loadout_safety
        .. local_wield_runtime
        .. husk_wield_runtime
    local localization = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker_localization.lua")
    local package_file = read("cosmetics_tweaker/resource_packages/cosmetics_tweaker/cosmetics_tweaker.package")

    local function with_loaded_module(callback, setting_values)
        local saved = {
            get_mod = _G.get_mod,
            Cosmetics = _G.Cosmetics,
            Application = _G.Application,
            Unit = _G.Unit,
            Mesh = _G.Mesh,
            Material = _G.Material,
            printf = _G.printf,
            ItemMasterList = _G.ItemMasterList,
        }
        _G.get_mod = function()
            return {
            get = function(_, setting_id)
                if setting_values then return setting_values[setting_id] end
                return true
            end,
            dofile = function(_, path)
                H.equal(path, "scripts/mods/cosmetics_tweaker/_lib_resource_residency")
                return assert(loadfile(repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_lib_resource_residency.lua"))()
            end,
            }
        end
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
        _G.printf = saved.printf
        _G.ItemMasterList = saved.ItemMasterList
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

    H.test("Grail Knight set career sharing is independent and fail-closed", function()
        local settings = {
            cos_gk_purpure_azure_enabled = true,
            cos_gk_purpure_azure_share_mercenary = true,
            cos_gk_purpure_azure_share_huntsman = false,
            cos_gk_purpure_azure_share_foot_knight = true,
        }
        with_loaded_module(function(set)
            H.equal(#set.SHARED_CAREERS, 3)
            H.equal(set.SHARED_CAREERS[1].career, "es_mercenary")
            H.equal(set.SHARED_CAREERS[2].career, "es_huntsman")
            H.equal(set.SHARED_CAREERS[3].career, "es_knight")
            H.equal(table.concat(set.can_wield_careers(), ","),
                "es_questingknight,es_mercenary,es_knight")
            H.equal(set.vanilla_fallback_for_career(set.HAT_ITEM_KEY, "es_mercenary"),
                "mercenary_hat_0000")
            H.equal(set.vanilla_fallback_for_career(set.SKIN_ITEM_KEY, "es_huntsman"),
                "skin_es_huntsman")
            H.equal(set.vanilla_fallback_for_career(set.HAT_ITEM_KEY, "es_knight"),
                "knight_hat_0000")
            H.equal(set.vanilla_fallback_for_career(set.SKIN_ITEM_KEY, "es_questingknight"),
                set.SKIN_VANILLA_FALLBACK)
            H.equal(set.vanilla_fallback_for_career(set.HAT_ITEM_KEY, nil), nil)
            H.equal(set.vanilla_fallback_for_career(set.SKIN_ITEM_KEY, "future_career"), nil)
            H.equal(set.vanilla_fallback_for_career("unrelated", "es_knight"), nil)
            local bridge = {
                registered = true,
                backend_to_armoury = { [set.SKIN_ITEM_KEY] = set.SKIN_VARIANT_KEY },
                backend_to_vanilla = { [set.SKIN_ITEM_KEY] = set.SKIN_VANILLA_FALLBACK },
            }
            H.equal(set.wire_fallback(bridge, set.SKIN_ITEM_KEY, "es_huntsman"), "skin_es_huntsman")
            H.equal(set.wire_fallback(bridge, set.SKIN_ITEM_KEY, nil), set.SKIN_VANILLA_FALLBACK)
            H.equal(set.wire_fallback(bridge, "foreign", "es_huntsman"), nil)
            H.equal(set.career_for_player({ career_name = function() return "es_knight" end }), "es_knight")

            local items = {
                [set.HAT_ITEM_KEY] = {},
                [set.SKIN_ITEM_KEY] = {},
                [set.SHIELD_SKIN_KEY] = {},
            }
            _G.ItemMasterList = items
            set.sync_toggle()
            for _, item in pairs(items) do
                H.equal(table.concat(item.can_wield, ","),
                    "es_questingknight,es_mercenary,es_knight")
            end
            H.truthy(items[set.HAT_ITEM_KEY].can_wield ~= items[set.SKIN_ITEM_KEY].can_wield,
                "set items must not alias a mutable can_wield table")

            settings.cos_gk_purpure_azure_share_mercenary = false
            settings.cos_gk_purpure_azure_share_huntsman = true
            set.sync_toggle()
            H.equal(table.concat(items[set.HAT_ITEM_KEY].can_wield, ","),
                "es_questingknight,es_huntsman,es_knight")
            H.truthy(set.is_availability_setting("cos_gk_purpure_azure_share_huntsman"))
            H.equal(set.is_availability_setting("unrelated_setting"), false)

            settings.cos_gk_purpure_azure_enabled = false
            set.sync_toggle()
            for _, item in pairs(items) do H.equal(#item.can_wield, 0) end
        end, settings)
    end)

    H.test("Grail Knight set sharing widgets are explicit and default off", function()
        local data = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker_data.lua")
        H.truthy(data:find('setting_id  = "cos_gk_purpure_azure_career_sharing_group"', 1, true))
        for _, setting_id in ipairs({
            "cos_gk_purpure_azure_share_mercenary",
            "cos_gk_purpure_azure_share_huntsman",
            "cos_gk_purpure_azure_share_foot_knight",
        }) do
            local start_at = assert(data:find('setting_id    = "' .. setting_id .. '"', 1, true))
            local row = data:sub(start_at, start_at + 220)
            H.truthy(row:find("default_value = false", 1, true), setting_id .. " must default off")
            H.truthy(localization:find(setting_id .. " = {", 1, true), setting_id .. " localization missing")
        end
        H.truthy(entry:find("GK_SET.wire_fallback(LA_BRIDGE, name, career)", 1, true))
        H.truthy(module:find("function M.wire_fallback(bridge, original_name, career_name)", 1, true))
        H.truthy(module:find("or vanilla", 1, true),
            "unknown career must not leave a custom key on the wire")
        H.truthy(entry:find("_la_vanilla_fallback(item_name, _wire_career_for_player(player))", 1, true))
        H.truthy(entry:find("_la_vanilla_fallback(item.key, _wire_career_for_player(player))", 1, true))
        H.truthy(attachment_spawn_sync:find("_la_substitute_name(orig, career)", 1, true))
        H.equal(entry_only:find("_la_substitute_name(orig, career)", 1, true), nil)
        H.truthy(entry:find("_la_vanilla_fallback(bid, career_name)", 1, true),
            "persisted loadout clones must use the exact career fallback")
        H.truthy(entry:find("_la_vanilla_fallback(raw, career_name)", 1, true),
            "loadout item lookup must use the exact career fallback")
        H.truthy(attachment_spawn_sync:find("_la_vanilla_fallback(la_id, career)", 1, true),
            "hot-join replay must use the exact wearer career fallback")
        H.equal(entry_only:find("_la_vanilla_fallback(la_id, career)", 1, true), nil)
        H.truthy(entry:find("career_for = _wire_career_for_player", 1, true),
            "self-rebroadcast must use the exact local player career fallback")
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
        H.truthy(module:find("scripts/mods/cosmetics_tweaker/_lib_resource_residency", 1, true))
        H.truthy(module:find("texture_set_resident", 1, true))
        H.truthy(module:find("unit_materials_resident", 1, true))
        H.truthy(module:find("textures_ready(slots, textures", 1, true))
        H.truthy(module:find("pcall(Unit.set_texture_for_materials", 1, true))
        H.truthy(module:find("bridge.backend_to_vanilla[row[1]] = row[3]", 1, true))
        H.truthy(module:find("bridge.custom_variants[row[2]] = true", 1, true))
        H.truthy(module:find("mod._cos.custom_skin_keys[M.SHIELD_SKIN_KEY] = true", 1, true))
        H.truthy(entry:find("GK_SET.apply_armor_to_owner", 1, true))
        H.truthy(entry:find("GK_SET.apply_variant_to_unit", 1, true))
        H.truthy(entry:find('mod:hook_safe("PlayerUnitCosmeticExtension", "extensions_ready"', 1, true))
        H.truthy(entry:find('mod:hook_safe("HeroPreviewer", "post_update"', 1, true))
        H.truthy(attachment_spawn_sync:find(
            'GK_SET.apply_variant_to_unit(cached.armoury_key, spawned_hat, "remote_husk")', 1, true))
        H.equal(entry_only:find(
            'GK_SET.apply_variant_to_unit(cached.armoury_key, spawned_hat, "remote_husk")', 1, true), nil)
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
        H.truthy(module:find("function M.apply_armor_to_score_preview(previewer, variant_key)", 1, true))
        H.truthy(module:find("previewer.character_unit_skin_data or (loading and loading.skin_data)", 1, true))
        H.truthy(module:find("previewer.character_unit_hidden_after_spawn", 1, true))
        H.truthy(module:find("previewer.character_unit_visible ~= true", 1, true))
        H.truthy(module:find("previewer[mesh_cache_field] == mesh", 1, true))
        H.truthy(module:find("previewer[mesh_cache_field] = mesh", 1, true))
        H.truthy(entry:find("state.gk_set.apply_armor_to_hero_preview(self)", 1, true))
        H.truthy(entry:find("state.gk_set.apply_armor_to_score_preview(self, self._cos_score_armor_variant)", 1, true))
        H.truthy(entry:find("hero_previewer._cos_score_armor_variant = nil", 1, true))
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
            H.equal(set.PREVIEW_REPLAY_CONTRACT.cache_identity, "mesh_unit+variant_key")
            H.equal(set.PREVIEW_REPLAY_CONTRACT.score_uses_same_visibility_boundary, true)
        end)
    end)

    H.test("authored outfit score preview waits for visibility and clears by mesh and variant", function()
        with_loaded_module(function(set)
            local mesh_a, mesh_b = {}, {}
            local writes = 0
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
                mesh_unit = mesh_a,
                character_unit_hidden_after_spawn = true,
                character_unit_visible = false,
            }
            H.equal(set.apply_armor_to_score_preview(previewer, set.SKIN_VARIANT_KEY), false)
            H.equal(writes, 0)
            previewer.character_unit_hidden_after_spawn = false
            previewer.character_unit_visible = true
            H.truthy(set.apply_armor_to_score_preview(previewer, set.SKIN_VARIANT_KEY))
            H.equal(writes, 6)
            H.truthy(set.apply_armor_to_score_preview(previewer, set.SKIN_VARIANT_KEY))
            H.equal(writes, 6, "same score mesh and authored identity must remain bounded")
            previewer.character_unit_visible = false
            H.equal(set.apply_armor_to_score_preview(previewer, set.SKIN_VARIANT_KEY), false)
            previewer.character_unit_visible = true
            H.truthy(set.apply_armor_to_score_preview(previewer, set.SKIN_VARIANT_KEY))
            H.equal(writes, 12, "hide/show must replay after donor material work")
            previewer.mesh_unit = mesh_b
            H.truthy(set.apply_armor_to_score_preview(previewer, set.SKIN_VARIANT_KEY))
            H.equal(writes, 18, "replacement score mesh must paint once")
            H.equal(set.apply_armor_to_score_preview(previewer, "not_an_authored_skin"), false)
            H.equal(writes, 18, "unknown score identity must fail closed")
        end)
    end)

    H.test("authored outfit preview cache repaints a new variant on the same mesh", function()
        with_loaded_module(function(set)
            local first_skin, second_skin, mesh = {}, {}, {}
            local writes = 0
            _G.Cosmetics = { [set.SKIN_ITEM_KEY] = first_skin, second_skin = second_skin }
            _G.Application = { can_get = function(kind) return kind == "texture" end }
            _G.Unit = {
                alive = function(unit) return unit == mesh end,
                has_data = function() return false end,
                num_meshes = function() return 1 end,
                mesh = function(unit) return unit end,
            }
            _G.Mesh = {
                has_material = function(_, name)
                    return name == "mtr_outfit" or name == "mtr_outfit_ds"
                end,
                material = function(unit, name) return { unit = unit, name = name } end,
            }
            _G.Material = { set_texture = function() writes = writes + 1 end }
            set.add_outfit_provider({
                PROVIDER_ID = "test_second_variant",
                ITEM_LOCALIZATION = {},
                resolve_skin_variant = function(skin)
                    return skin == second_skin and "second_variant" or nil
                end,
                resolve_variant = function(key)
                    if key ~= "second_variant" then return nil end
                    return {
                        swap_hand = "armor",
                        textures = { "second_d", "second_c", "second_n" },
                        textures_fps = { "second_1d", "second_1c", "second_1n" },
                    }
                end,
                register_all = function() return true end,
                sync_toggle = function() return true end,
            })
            local previewer = {
                character_unit_skin_data = first_skin,
                mesh_unit = mesh,
                character_unit_hidden_after_spawn = false,
                character_unit_visible = true,
            }
            H.truthy(set.apply_armor_to_hero_preview(previewer))
            H.equal(writes, 6)
            previewer.character_unit_skin_data = second_skin
            H.truthy(set.apply_armor_to_hero_preview(previewer))
            H.equal(writes, 12, "same mesh must repaint when authored skin identity changes")
            H.truthy(set.apply_armor_to_hero_preview(previewer))
            H.equal(writes, 12, "same mesh and variant must remain bounded")
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

    H.test("authored outfit providers reject malformed, duplicate, and excess registrations", function()
        with_loaded_module(function(set)
            local function provider(id)
                return {
                    PROVIDER_ID = id,
                    ITEM_LOCALIZATION = {},
                    resolve_variant = function() return nil end,
                    resolve_skin_variant = function() return nil end,
                    register_all = function() return true end,
                    sync_toggle = function() return true end,
                }
            end
            H.equal(set.add_outfit_provider({}), false)
            local first = provider("test_provider_1")
            H.truthy(set.add_outfit_provider(first))
            H.truthy(set.has_outfit_provider("test_provider_1"))
            H.equal(set.add_outfit_provider(first), false, "duplicate identity must not grow the registry")
            H.equal(set.add_outfit_provider(provider("test_provider_1")), false)
            for i = 2, 16 do H.truthy(set.add_outfit_provider(provider("test_provider_" .. i))) end
            H.equal(#set._outfit_providers, 16)
            H.equal(set.add_outfit_provider(provider("test_provider_17")), false)
            H.equal(#set._outfit_providers, 16)
        end)
    end)

    H.test("Grail Knight texture residency drift fails closed before any unit write", function()
        with_loaded_module(function(set)
            local unit, writes = {}, 0
            _G.Application = {
                can_get = function(_, path) return path ~= set.TEXTURES.shield[2] end,
            }
            _G.Unit = {
                alive = function(candidate) return candidate == unit end,
                set_texture_for_materials = function() writes = writes + 1 end,
            }
            H.equal(set.apply_variant_to_unit(set.SHIELD_VARIANT_KEY, unit, "network_husk"), false)
            H.equal(writes, 0)
        end)
    end)

    H.test("Grail Knight armor texture residency drift fails closed before any material write", function()
        with_loaded_module(function(set)
            local unit, writes = {}, 0
            _G.Application = {
                can_get = function(_, path) return path ~= set.TEXTURES.skin_3p[3] end,
            }
            _G.Unit = {
                alive = function(candidate) return candidate == unit end,
                has_data = function() return false end,
                num_meshes = function() return 1 end,
                mesh = function() return { materials = { mtr_outfit = true, mtr_outfit_ds = true } } end,
            }
            _G.Mesh = {
                has_material = function(mesh, name) return mesh.materials[name] == true end,
                material = function(_, name) return { name = name } end,
            }
            _G.Material = { set_texture = function() writes = writes + 1 end }
            H.equal(set.apply_variant_to_unit(set.SKIN_VARIANT_KEY, unit, "third_person"), false)
            H.equal(writes, 0)
        end)
    end)

    H.test("Grail Knight missing residency helper fails closed before native texture writes", function()
        local saved = {
            get_mod = _G.get_mod,
            Application = _G.Application,
            Unit = _G.Unit,
        }
        _G.get_mod = function() return { get = function() return true end } end
        local path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_grail_knight_set.lua"
        local set = assert(loadfile(path))()
        local unit, writes = {}, 0
        _G.Application = { can_get = function() return true end }
        _G.Unit = {
            alive = function(candidate) return candidate == unit end,
            set_texture_for_materials = function() writes = writes + 1 end,
        }
        local ok, err = pcall(function()
            H.equal(set.apply_variant_to_unit(set.SHIELD_VARIANT_KEY, unit, "network_husk"), false)
            H.equal(writes, 0)
        end)
        _G.get_mod = saved.get_mod
        _G.Application = saved.Application
        _G.Unit = saved.Unit
        if not ok then error(err, 0) end
    end)

    H.test("authored outfit residency diagnostics are explicitly bounded", function()
        with_loaded_module(function(set)
            local unit, reports = {}, 0
            _G.printf = function() reports = reports + 1 end
            _G.Application = { can_get = function() return false end }
            _G.Unit = {
                alive = function(candidate) return candidate == unit end,
                set_texture_for_materials = function() error("must not write") end,
            }
            for i = 1, 80 do
                H.equal(set.apply_variant_to_unit(set.SHIELD_VARIANT_KEY, unit,
                    "adversarial_surface_" .. i .. string.rep("x", 512)), false)
            end
            H.equal(set._residency_diag_count, 24)
            H.equal(reports, 24)
        end)
    end)

    H.test("provider-specific surface evidence is exact and deduplicated", function()
        with_loaded_module(function(set)
            local unit, reports = {}, {}
            _G.printf = function(format, ...)
                reports[#reports + 1] = string.format(format, ...)
            end
            _G.Application = { can_get = function() return true end }
            _G.Unit = {
                alive = function(candidate) return candidate == unit end,
                num_meshes = function() return 1 end,
                mesh = function() return "shield_mesh" end,
                set_texture_for_materials = function() end,
            }
            _G.Mesh = {
                num_materials = function() return 1 end,
                material = function() return "#ID[12345678]" end,
            }
            local variant = {
                swap_hand = "left_hand_unit",
                textures = { "diffuse", "combined", "normal" },
                issue = 656,
                variant_key = "cos_fk_reikland_griffin_skin_variant",
            }
            H.truthy(set.apply_variant_to_unit(variant, unit, "remote_husk"))
            H.truthy(set.apply_variant_to_unit(variant, unit, "remote_husk"))
            H.equal(#reports, 1)
            H.truthy(reports[1]:find("[cos:656] applied", 1, true))
            H.truthy(reports[1]:find("variant=cos_fk_reikland_griffin_skin_variant", 1, true))
            H.truthy(reports[1]:find("surface=remote_husk", 1, true))
        end)
    end)

    H.test("Grail Knight shield rejects null spawned materials before texture writes", function()
        with_loaded_module(function(set)
            local unit, writes = {}, 0
            _G.Application = { can_get = function() return true end }
            _G.Unit = {
                alive = function(candidate) return candidate == unit end,
                num_meshes = function() return 1 end,
                mesh = function() return "shield_mesh" end,
                set_texture_for_materials = function() writes = writes + 1 end,
            }
            _G.Mesh = {
                num_materials = function() return 1 end,
                material = function() return "#ID[00000000]" end,
            }
            H.equal(set.apply_variant_to_unit(
                set.SHIELD_VARIANT_KEY, unit, "network_husk"), false)
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
        -- #1159: the create_equipment paint now lives in the equipment-assembly
        -- owner. Pin it THERE and require the entry to have let go of it, so a
        -- re-inlined copy (which VMF would silently shadow) fails here.
        H.truthy(equipment_assembly:find('GK_SET.apply_variant_to_unit(GK_SET.SHIELD_VARIANT_KEY, target, "create_equipment")', 1, true))
        H.equal(entry_only:find('GK_SET.apply_variant_to_unit(GK_SET.SHIELD_VARIANT_KEY, target, "create_equipment")', 1, true), nil)
        H.truthy(local_wield_runtime:find(
            'mod:hook_safe("SimpleInventoryExtension", "_wield_slot"', 1, true))
        H.equal(entry_only:find(
            'mod:hook_safe("SimpleInventoryExtension", "_wield_slot"', 1, true), nil)
        H.truthy(husk_wield_runtime:find(
            'mod:hook("SimpleHuskInventoryExtension", "_wield_slot"', 1, true))
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
