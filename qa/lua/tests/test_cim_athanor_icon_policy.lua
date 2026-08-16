return function(H, repo_root)
    local cim_root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local Policy = assert(loadfile(cim_root .. "_cim_athanor_icon_policy.lua"))()
    local Residency = assert(loadfile(cim_root .. "_lib_resource_residency.lua"))()
    Policy.set_resource_residency(Residency)
    local Provider = assert(loadfile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_inventory_icons.lua"))()
    local atlas_path = repo_root
        .. "/character_weapon_variants/materials/character_weapon_variants/cwv_weapon_icons.lua"
    local live_cwv_icons = assert(loadfile(atlas_path))()
    local CwvIcons = { FALLBACKS = {} }
    for icon in pairs(live_cwv_icons) do
        CwvIcons.FALLBACKS[icon] = icon:gsub("_dual_cwv$", "")
    end
    CwvIcons.resolve = function(icon, renderer_name)
        local fallback = CwvIcons.FALLBACKS[icon]
        if fallback and renderer_name == Policy.RENDERER_NAME then return fallback, true end
        return icon, fallback ~= nil
    end

    H.test("masked saturated atlas path requires its exact material", function()
        local settings = {
            material_name = "custom",
            masked_material_name = "custom_masked",
            saturated_material_name = "custom_saturated",
        }
        local atlas = {
            has_atlas_settings_by_texture_name = function(name) return name == "custom_icon" end,
            get_atlas_settings_by_texture_name = function() return settings end,
        }
        H.equal(Policy.material_name("custom_icon", atlas,
            { masked = true, saturated = true }), nil)

        settings.masked_saturated_material_name = "custom_masked_saturated"
        H.equal(Policy.material_name("custom_icon", atlas,
            { masked = true, saturated = true }), "custom_masked_saturated")

        local gui = {
            material = function(live, name) return live.materials[name] end,
        }
        local renderer = { gui = { materials = { custom_masked_saturated = {} } } }
        local safe, material = Policy.renderer_has_texture(renderer, "custom_icon", atlas, gui,
            { masked = true, saturated = true })
        H.truthy(safe)
        H.equal(material, "custom_masked_saturated")
        renderer.gui.materials.custom_masked_saturated = nil
        H.equal(Policy.renderer_has_texture(renderer, "custom_icon", atlas, gui,
            { masked = true, saturated = true }), false)
    end)

    H.test("every live CWV custom inventory icon closes to vanilla in Athanor", function()
        local layout = {}
        local safe = {}
        local originals = {}
        for icon, fallback in pairs(CwvIcons.FALLBACKS) do
            safe[fallback] = true
            local data = { inventory_icon = icon, slot_type = "melee", cwv_variant = true }
            originals[icon] = data
            layout[#layout + 1] = { key = "row_" .. icon, item_data = data }
        end
        local sanitized, report = Policy.sanitize_layout(layout, {
            item_master_list = {},
            provider_resolve = CwvIcons.resolve,
            has_texture = function(icon) return safe[icon] == true end,
        })
        H.equal(report.total, 9)
        H.equal(report.fallback, 9)
        H.equal(report.omitted, 0)
        H.equal(#sanitized, 9)
        for i = 1, #sanitized do
            local row = sanitized[i]
            local original = row.item_data.cim_athanor_original_icon
            H.equal(row.item_data.inventory_icon, CwvIcons.FALLBACKS[original])
            H.equal(originals[original].inventory_icon, original)
            H.equal(row.item_data == originals[original], false)
        end
    end)

    H.test("renderer-owned CWV Dual Axes icons remain authored in Athanor", function()
        local layout = {}
        local safe = {}
        for icon in pairs(Provider.FALLBACKS) do
            safe[icon] = true
            layout[#layout + 1] = {
                key = "row_" .. icon,
                item_data = { inventory_icon = icon, slot_type = "melee", cwv_variant = true },
            }
        end
        local sanitized, report = Policy.sanitize_layout(layout, {
            item_master_list = {},
            provider_resolve = Provider.resolve,
            has_texture = function(icon) return safe[icon] == true end,
        })
        H.equal(Policy.RENDERER_NAME, "ingame_ui")
        H.equal(report.total, 9)
        H.equal(report.verified, 9)
        H.equal(report.fallback, 0)
        H.equal(report.omitted, 0)
        for i = 1, #sanitized do
			H.equal(sanitized[i], layout[i])
			H.equal(sanitized[i].item_data, layout[i].item_data)
            H.equal(sanitized[i].item_data.inventory_icon,
                layout[i].item_data.inventory_icon)
        end
    end)

    H.test("base icon fallback works without optional provider registry", function()
        local custom = {
            inventory_icon = "unknown_provider_icon",
            slot_type = "melee",
            key = "vanilla_base",
            cwv_variant = true,
        }
        local base = { inventory_icon = "vanilla_base_icon", slot_type = "melee" }
        local result, report = Policy.sanitize_layout({
            { key = "custom", item_data = custom },
        }, {
            item_master_list = { vanilla_base = base },
            has_texture = function(icon) return icon == "vanilla_base_icon" end,
        })
        H.equal(report.fallback, 1)
        H.equal(result[1].item_data.inventory_icon, "vanilla_base_icon")
        H.equal(custom.inventory_icon, "unknown_provider_icon")
    end)

    H.test("row is omitted when neither icon nor fallback is renderer proven", function()
        local result, report = Policy.sanitize_layout({
            { key = "unsafe", item_data = { inventory_icon = "unsafe", slot_type = "melee" } },
        }, {
            item_master_list = {},
            has_texture = function() return false end,
        })
        H.equal(#result, 0)
        H.equal(report.omitted, 1)
    end)

    H.test("icon refusals name the refusing gate for the bounded log (#481)", function()
        -- Missing masked+saturated material: the resolution gate refuses
        -- before any residency probe.
        local atlas = {
            has_atlas_settings_by_texture_name = function() return true end,
            get_atlas_settings_by_texture_name = function()
                return { material_name = "raw", masked_material_name = "raw_masked" }
            end,
        }
        local safe, material, gate = Policy.renderer_has_texture(
            { gui = {} }, "raw_icon", atlas, { material = function() end },
            { masked = true, saturated = true })
        H.equal(safe, false)
        H.equal(material, nil)
        H.equal(gate, "no-material-name")

        -- Gui-local absence: the policy reports the residency contract's own
        -- refusal reason for the exact renderer (behavioral parity with the
        -- live contract, not a re-implementation).
        local gui_api = { material = function(gui, name) return gui.materials[name] end }
        local renderer = { gui = { materials = {} } }
        local flat_atlas = {
            has_atlas_settings_by_texture_name = function() return false end,
            get_atlas_settings_by_texture_name = function() return nil end,
        }
        safe, material, gate = Policy.renderer_has_texture(
            renderer, "plain_icon", flat_atlas, gui_api, {})
        H.equal(safe, false)
        H.equal(material, "plain_icon")
        local expected_ok, expected_reason = Residency.gui_material_resident(
            renderer, "plain_icon", gui_api, nil, "cim_athanor_icon")
        H.equal(expected_ok, false)
        H.equal(gate, expected_reason)
        H.truthy(type(gate) == "string" and gate ~= "")

        -- No residency contract installed: fresh module copy refuses closed
        -- and says so.
        local Bare = assert(loadfile(cim_root .. "_cim_athanor_icon_policy.lua"))()
        safe, material, gate = Bare.renderer_has_texture(
            renderer, "plain_icon", flat_atlas, gui_api, {})
        H.equal(safe, false)
        H.equal(gate, "no-residency-contract")
    end)

    H.test("sanitize_layout change rows carry gate attribution (#481)", function()
        local rows = {
            { key = "falls_back", item_data = {
                inventory_icon = "bad_icon", slot_type = "melee",
                cim_athanor_inventory_icon = "good_icon",
            } },
            { key = "omitted", item_data = {
                inventory_icon = "bad_icon2", slot_type = "ranged",
            } },
            { key = "throws", item_data = {
                inventory_icon = "boom_icon", slot_type = "melee",
            } },
        }
        local result, report = Policy.sanitize_layout(rows, {
            item_master_list = {},
            has_texture = function(icon)
                if icon == "boom_icon" then error("probe explosion") end
                if icon == "good_icon" then return true, icon, "resident" end
                return false, icon .. "_material", "gui_material_absent"
            end,
        })
        H.equal(report.fallback, 1)
        H.equal(report.omitted, 2)
        H.equal(#result, 1)
        local by_key = {}
        for _, change in ipairs(report.changes) do by_key[change.key] = change end
        H.equal(by_key.falls_back.gate, "gui_material_absent")
        H.equal(by_key.falls_back.material, "bad_icon_material")
        H.equal(by_key.falls_back.replacement, "good_icon")
        H.equal(by_key.omitted.gate, "gui_material_absent")
        H.equal(by_key.omitted.replacement, nil)
        H.equal(by_key.throws.gate, "probe-error",
            "a throwing probe is attributed, not silently omitted")
        H.equal(by_key.throws.material, nil)
    end)

    H.test("production probes exact Athanor top renderer before populate", function()
        local file = assert(io.open(cim_root .. "crafting_in_modded_dev.lua", "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("icon_policy.sanitize_layout", 1, true))
        H.truthy(source:find("self._ui_top_renderer", 1, true))
        H.truthy(source:find("{ masked = true, saturated = true }", 1, true))
        local sanitize = assert(source:find("local safe_layout, icon_report", 1, true))
        local populate = assert(source:find("self:_populate_list(safe_layout)", sanitize, true))
        H.truthy(sanitize < populate)
    end)
end
