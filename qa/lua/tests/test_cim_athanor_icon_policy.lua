return function(H, repo_root)
    local cim_root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local Policy = assert(loadfile(cim_root .. "_cim_athanor_icon_policy.lua"))()
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
