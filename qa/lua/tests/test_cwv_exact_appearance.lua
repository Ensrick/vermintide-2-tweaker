return function(H, repo_root)
    local module_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_exact_appearance.lua"
    local main_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
    local Policy = assert(loadfile(module_path))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("CWV #579 resolves the exact saved dual-axes skin from backend identity", function()
        local appearance = Policy.resolve({
            backend_id = "cwv_es_dual_axes_001",
            skin_from_backend = function() return "dual_red" end,
            weapon_skins = { dual_red = {
                right_hand_unit = "axe_red_right",
                left_hand_unit = "axe_blue_left",
            } },
        })
        H.equal(appearance.skin, "dual_red")
        H.equal(appearance.right_hand_unit, "axe_red_right")
        H.equal(appearance.left_hand_unit, "axe_blue_left")
    end)

    H.test("CWV #579 all render surfaces preserve both exact hands", function()
        local appearance = {
            skin = "dual_exact", right_hand_unit = "axe_right", left_hand_unit = "axe_left",
        }
        for surface, adapter in pairs(Policy.SURFACES) do
            if adapter == "item_units" then
                local result = { right_hand_unit = "base_r", left_hand_unit = "base_l" }
                H.equal(Policy.apply_item_units(appearance, result), 2, surface)
                H.equal(result.right_hand_unit, "axe_right", surface)
                H.equal(result.left_hand_unit, "axe_left", surface)
            else
                local recipe = {
                    { right_hand = true, unit_name = "base_r_3p" },
                    { left_hand = true, unit_name = "base_l_3p" },
                }
                H.equal(Policy.apply_spawn_data(appearance, recipe), 2, surface)
                H.equal(recipe[1].unit_name, "axe_right_3p", surface)
                H.equal(recipe[2].unit_name, "axe_left_3p", surface)
            end
        end
    end)

    H.test("CWV #579 adapters route unit and preview recipes through canonical policy", function()
        local source = read(main_path)
        for _, marker in ipairs({
            "_om.exact_appearance.resolve({",
            "_om.exact_appearance.apply_item_units(exact, result, true)",
            "_om.exact_appearance.apply_spawn_data(",
            'mod:hook("HeroPreviewer", "_spawn_item"',
            'mod:hook("MenuWorldPreviewer", "_spawn_item"',
            'mod:hook("LootItemUnitPreviewer", "spawn_units"',
            '_om._husk_preselect_units(result, item_data, backend_id, skin, career_name)',
        }) do
            H.truthy(source:find(marker, 1, true), "missing canonical surface route: " .. marker)
        end
    end)

    H.test("CWV #579 explicit render identity wins over stale stores", function()
        local appearance = Policy.resolve({
            explicit_skin = "selected", stored_skin = "stale", backend_id = "bid",
            skin_from_backend = function() return "backend" end,
            weapon_skins = { selected = { right_hand_unit = "chosen" } },
        })
        H.equal(appearance.skin, "selected")
    end)

    H.test("CWV #579 composes Cosmetics independent offhand without clobbering", function()
        local appearance = { right_hand_unit = "runed", left_hand_unit = "runed" }
        local fallback = { right_hand_unit = "base", left_hand_unit = "base" }
        local recipe = {
            { right_hand = true, unit_name = "base_3p" },
            { left_hand = true, unit_name = "independent_offhand_3p" },
        }
        H.equal(Policy.apply_spawn_data(appearance, recipe, nil, fallback), 1)
        H.equal(recipe[1].unit_name, "runed_3p")
        H.equal(recipe[2].unit_name, "independent_offhand_3p")

        local units = { right_hand_unit = nil, left_hand_unit = "independent_offhand" }
        H.equal(Policy.apply_item_units(appearance, units, true), 1)
        H.equal(units.right_hand_unit, "runed")
        H.equal(units.left_hand_unit, "independent_offhand")
    end)
end
