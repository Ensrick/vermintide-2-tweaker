return function(H, repo_root)
    local function isolated(callback)
        local saved = {
            get_mod = _G.get_mod,
            ItemMasterList = _G.ItemMasterList,
            NetworkLookup = _G.NetworkLookup,
            Application = _G.Application,
            Unit = _G.Unit,
            Mesh = _G.Mesh,
            Material = _G.Material,
            clone = table.clone,
        }
        local setting = true
        local backend_entries
        local mod = {
            get = function(_, id)
                if id == "cos_encarmine_hat_enabled" then return setting end
            end,
            add_mod_items_to_masterlist = function(_, entries)
                for _, entry in ipairs(entries) do
                    ItemMasterList[entry.name] = entry
                    local index = #NetworkLookup.item_names + 1
                    NetworkLookup.item_names[index] = entry.name
                    NetworkLookup.item_names[entry.name] = index
                end
            end,
            add_mod_items_to_local_backend = function(_, entries)
                backend_entries = entries
            end,
            info = function() end,
        }
        _G.get_mod = function(name)
            if name == "cosmetics_tweaker" then return mod end
        end
        _G.ItemMasterList = {
            knight_hat_0006 = {
                key = "knight_hat_0006",
                name = "knight_hat_0006",
                template = "es_hats_no_ear_moustache",
                slot_type = "hat",
                item_type = "hat",
                unit = "units/beings/player/empire_soldier_knight/headpiece/es_k_hat_07",
                rarity = "exotic",
                can_wield = { "es_knight" },
            },
        }
        _G.NetworkLookup = { item_names = {} }
        _G.Application = nil
        table.clone = function(source)
            local out = {}
            for key, value in pairs(source) do out[key] = value end
            return out
        end

        local path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_custom_hats.lua"
        local hats = assert(loadfile(path))()
        local bridge = {
            registered = false,
            la_registered = false,
            backend_to_armoury = {},
            backend_to_vanilla = {},
            armoury_to_backend = {},
            unit_path_to_clones = {},
        }
        local ok, err = pcall(callback, hats, bridge,
            function(value) setting = value end,
            function() return backend_entries end)
        _G.get_mod = saved.get_mod
        _G.ItemMasterList = saved.ItemMasterList
        _G.NetworkLookup = saved.NetworkLookup
        _G.Application = saved.Application
        _G.Unit = saved.Unit
        _G.Mesh = saved.Mesh
        _G.Material = saved.Material
        table.clone = saved.clone
        if not ok then error(err, 0) end
    end

    H.test("Encarmine registers a stable exact-Laurel item", function()
        isolated(function(hats, bridge, _, get_backend_entries)
            H.truthy(hats.register_all(bridge))
            local entry = ItemMasterList.cos_encarmine_hat
            H.equal(entry.unit, hats.BASE_UNIT)
            H.equal(hats.CUSTOM_UNIT, hats.BASE_UNIT)
            H.equal(entry.template, "es_hats_no_ear_moustache")
            H.equal(entry.inventory_icon, "icon_knight_hat_0006_encarmine")
            H.equal(entry.required_dlc, nil)
            H.equal(entry.can_wield[1], "es_knight")
            H.equal(bridge.backend_to_vanilla.cos_encarmine_hat, "knight_hat_0006")
            H.equal(bridge.backend_to_armoury.cos_encarmine_hat, hats.VARIANT_KEY)
            H.equal(bridge.unit_path_to_clones[hats.BASE_UNIT], nil)
            H.equal(get_backend_entries()[1].mod_data.backend_id, "cos_encarmine_hat")
        end)
    end)

    H.test("Encarmine never substitutes a custom geometry unit", function()
        isolated(function(hats, bridge)
            H.truthy(hats.register_all(bridge))
            local spawn_path, custom = hats.spawn_unit(Application, "test")
            H.equal(spawn_path, hats.BASE_UNIT)
            H.equal(custom, false)
            local variant = hats.resolve_variant(hats.VARIANT_KEY)
            H.equal(variant.kind, "vanilla_donor_texture_override")
            H.equal(variant.new_units[1], hats.BASE_UNIT)
            H.truthy(variant.is_vanilla_unit)
            H.equal(hats.RENDER_MODE, "vanilla_laurel_material_instance_override")
        end)
    end)

    H.test("Encarmine paints only Laurel armor and plume material instances", function()
        isolated(function(hats)
            local unit = {}
            local calls = {}
            _G.Application = { can_get = function(kind) return kind == "texture" end }
            _G.Unit = {
                alive = function(candidate) return candidate == unit end,
                num_meshes = function() return 8 end,
                mesh = function(_, index) return { index = index } end,
            }
            _G.Mesh = {
                num_materials = function() return 1 end,
                material = function(mesh) return { mesh_index = mesh.index } end,
            }
            _G.Material = {
                set_texture = function(material, slot, texture)
                    calls[#calls + 1] = {
                        mesh_index = material.mesh_index,
                        slot = slot,
                        texture = texture,
                    }
                end,
            }

            local ok, reason = hats.apply_surface(unit, "unit-test")
            H.truthy(ok)
            H.equal(reason, "applied")
            H.equal(#calls, 18)
            local mesh_counts = {}
            for _, call in ipairs(calls) do
                mesh_counts[call.mesh_index] = (mesh_counts[call.mesh_index] or 0) + 1
                H.truthy(call.slot == hats.TEXTURE_SLOTS.diffuse
                    or call.slot == hats.TEXTURE_SLOTS.normal
                    or call.slot == hats.TEXTURE_SLOTS.combined)
            end
            H.equal(mesh_counts[0], nil)
            H.equal(mesh_counts[7], nil)
            for index = 1, 6 do H.equal(mesh_counts[index], 3) end
            for _, call in ipairs(calls) do
                if call.mesh_index >= 1 and call.mesh_index <= 3 then
                    H.truthy(call.texture:find("encarmine_armored_", 1, true),
                        "Laurel armor mesh received a plume texture")
                elseif call.mesh_index >= 4 and call.mesh_index <= 6 then
                    H.truthy(call.texture:find("encarmine_cloth_", 1, true),
                        "Laurel plume mesh received an armor texture")
                end
            end

            local again_ok, again_reason = hats.apply_surface(unit, "unit-test")
            H.truthy(again_ok)
            H.equal(again_reason, "already_applied")
            H.equal(#calls, 18)
        end)
    end)

    H.test("Encarmine rejects scene drift before writing materials", function()
        isolated(function(hats)
            local writes = 0
            _G.Application = { can_get = function() return true end }
            _G.Unit = {
                alive = function() return true end,
                num_meshes = function() return 2 end,
            }
            _G.Mesh = {}
            _G.Material = { set_texture = function() writes = writes + 1 end }
            local ok, reason = hats.apply_surface({}, "unit-test")
            H.equal(ok, false)
            H.equal(reason, "donor_mesh_count_2")
            H.equal(writes, 0)
        end)
    end)

    H.test("Encarmine toggle changes availability without changing lookup identity", function()
        isolated(function(hats, bridge, set_setting)
            H.truthy(hats.register_all(bridge))
            set_setting(false)
            H.truthy(hats.sync_toggle())
            H.equal(ItemMasterList.cos_encarmine_hat.unit, hats.BASE_UNIT)
            H.equal(#ItemMasterList.cos_encarmine_hat.can_wield, 0)
            H.equal(hats.resolve_variant(hats.VARIANT_KEY).enabled, false)
            H.truthy(NetworkLookup.item_names.cos_encarmine_hat)
        end)
    end)

    H.test("Encarmine Laurel contract pins the complete donor scene", function()
        isolated(function(hats)
            local contract = hats.LAUREL_SCENE_CONTRACT
            H.equal(contract.mesh_count, 8)
            H.equal(#contract.armor_mesh_indices, 3)
            H.equal(#contract.plume_mesh_indices, 3)
            H.equal(contract.armor_mesh_indices[1], 1)
            H.equal(contract.armor_mesh_indices[3], 3)
            H.equal(contract.plume_mesh_indices[1], 4)
            H.equal(contract.plume_mesh_indices[3], 6)
            H.equal(#contract.shadow_mesh_indices, 2)
            H.equal(contract.shadow_mesh_indices[1], 0)
            H.equal(contract.shadow_mesh_indices[2], 7)
            H.equal(contract.lod_steps, 3)
            H.equal(contract.rig_bones, 13)
            H.equal(contract.dynamic_plume_bones, 6)
            H.equal(hats.MATERIAL_RESPONSE_REVISION, 6)
            H.truthy(hats.DONOR_ALPHA_CONTRACT)
            H.truthy(hats.DONOR_NORMAL_TANGENT_CONTRACT)
            H.truthy(hats.DONOR_CONTROLLER_CONTRACT)
            H.truthy(hats.DONOR_FADE_CONTRACT)
        end)
    end)

    H.test("Encarmine resolves runtime mesh roles from donor material identity", function()
        isolated(function(hats)
            local expected = {
                [0] = { 8, "shadow", "5ED8F236" },
                [1] = { 7, "armor",  "1903313B" },
                [2] = { 6, "armor",  "1903313B" },
                [3] = { 5, "armor",  "1903313B" },
                [4] = { 4, "plume",  "BD15BFF9" },
                [5] = { 3, "plume",  "BD15BFF9" },
                [6] = { 2, "plume",  "BD15BFF9" },
                [7] = { 1, "shadow", "5ED8F236" },
            }
            H.equal(hats.DONOR_MATERIALS.armor.slot, "1903313B")
            H.equal(hats.DONOR_MATERIALS.armor.resource,
                "units/beings/player/empire_soldier_knight/headpiece/es_k_hat_base")
            H.equal(hats.DONOR_MATERIALS.plume.slot, "BD15BFF9")
            H.equal(hats.DONOR_MATERIALS.plume.resource,
                "units/beings/player/empire_soldier_knight/headpiece/es_k_hat_feather")
            for mesh_index = 0, 7 do
                local binding = hats.DONOR_MESH_BINDINGS[mesh_index]
                local want = expected[mesh_index]
                H.truthy(binding, "missing semantic donor binding")
                H.equal(binding.geometry_index, want[1])
                H.equal(binding.role, want[2])
                H.equal(binding.material_slot, want[3])
                H.equal(binding.material_slot, hats.DONOR_MATERIALS[binding.role].slot)
                if binding.role == "armor" then
                    H.truthy(hats.ARMOR_TEXTURES.diffuse:find("encarmine_armored_", 1, true))
                elseif binding.role == "plume" then
                    H.truthy(hats.PLUME_TEXTURES.diffuse:find("encarmine_cloth_", 1, true))
                end
            end
        end)
    end)

    H.test("Encarmine integration paints all render surfaces", function()
        local file = assert(io.open(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua", "rb"))
        local source = file:read("*a")
        file:close()
        for _, surface in ipairs({
            "appearance-replay", "remote-husk", "local-attachment",
            "live-attachment", "hero-preview",
        }) do
            H.truthy(source:find('"' .. surface .. '"', 1, true))
        end
        H.truthy(source:find("CUSTOM_HATS.apply_surface", 1, true))
        H.equal(source:find('CANDIDATE_CUSTOM_UNIT', 1, true), nil)
    end)

    H.test("Encarmine texture declarations preserve native material inputs", function()
        local texture_file = assert(io.open(repo_root
            .. "/cosmetics_tweaker/textures/cosmetics_tweaker/encarmine_hat/encarmine_cloth_diffuse.texture", "rb"))
        local texture_source = texture_file:read("*a")
        texture_file:close()
        H.truthy(texture_source:find("enable_cut_alpha_threshold = false", 1, true))

        isolated(function(hats)
            H.equal(hats.TEXTURE_SLOTS.diffuse, "texture_map_c0ba2942")
            H.equal(hats.TEXTURE_SLOTS.normal, "texture_map_59cd86b9")
            H.equal(hats.TEXTURE_SLOTS.combined, "texture_map_b788717c")
            H.truthy(hats.ARMOR_TEXTURES.combined:find("encarmine_armored_combined", 1, true))
            H.truthy(hats.PLUME_TEXTURES.combined:find("encarmine_cloth_combined", 1, true))
        end)
    end)

    H.test("Encarmine compiled-scene gate parses donor structure", function()
        local validator = assert(io.open(repo_root
            .. "/cosmetics_tweaker/tools/encarmine_asset_pipeline/validate_laurel_resource.py", "rb"))
        local source = validator:read("*a")
        validator:close()
        H.truthy(source:find("UnitImporterVT2", 1, true))
        H.truthy(source:find("unit.meshes", 1, true))
        H.truthy(source:find("unit.lod_objects", 1, true))
        H.truthy(source:find("geometry.materials", 1, true))
        H.truthy(source:find("geometry_index - 1", 1, true))
        H.truthy(source:find("role_by_slot", 1, true))
        H.truthy(source:find("runtime_mesh_materials", 1, true))
        H.truthy(source:find("ENCARMINE_LAUREL_COMPILED_CONTRACT=OK", 1, true))

        local contract = assert(io.open(repo_root
            .. "/cosmetics_tweaker/tools/encarmine_asset_pipeline/laurel_scene_contract.json", "rb"))
        local contract_source = contract:read("*a")
        contract:close()
        H.truthy(contract_source:find('"mesh_objects"', 1, true))
        H.truthy(contract_source:find('"geometry_material_slots"', 1, true))
        H.truthy(contract_source:find('"runtime_mesh_materials"', 1, true))
        H.truthy(contract_source:find('[1, 7, "1903313B", "armor"]', 1, true))
        H.truthy(contract_source:find('[4, 4, "BD15BFF9", "plume"]', 1, true))
        H.truthy(contract_source:find('"lod_objects"', 1, true))
        H.truthy(contract_source:find('"dynamic_plume_bones": 6', 1, true))
    end)
end
