-- Fail-closed inventory-icon policy for CIM's Athanor weapon selector.
--
-- HeroWindowWeaveForgeWeapons draws list icons on its ui_top_renderer with
-- masked=true AND saturated=true. A texture id in UIAtlasHelper is not enough:
-- the atlas must name the masked+saturated material and that exact material
-- must exist in the renderer's live Gui. Passing an unproven id reaches
-- Gui.bitmap_uv with a nil material and crashes the game (issue #617).

local M = {}

-- The weapon list takes `self._ui_top_renderer` from ingame_ui_context; that
-- shared renderer is created by ingame_ui, not by the separate Weave Forge
-- preview renderer. The live Gui proof below remains authoritative if VMF's
-- creator inference or material residency ever drifts.
M.RENDERER_NAME = "ingame_ui"
M.PLACEHOLDERS = {
    melee = "icons_placeholder_melee_01",
    ranged = "icons_placeholder_ranged_01",
}

local function _copy(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

-- Mirrors UIRenderer.script_draw_bitmap's material selection without drawing.
-- A nil result is unsafe even when the atlas texture itself exists.
function M.material_name(texture_name, atlas_helper, flags)
    if type(texture_name) ~= "string" or texture_name == "" then return nil end
    if type(atlas_helper) ~= "table"
        or type(atlas_helper.has_atlas_settings_by_texture_name) ~= "function"
        or type(atlas_helper.get_atlas_settings_by_texture_name) ~= "function" then
        return texture_name
    end

    local ok_has, has = pcall(atlas_helper.has_atlas_settings_by_texture_name, texture_name)
    if not ok_has or not has then return texture_name end
    local ok_get, settings = pcall(atlas_helper.get_atlas_settings_by_texture_name, texture_name)
    if not ok_get or type(settings) ~= "table" then return nil end

    flags = flags or {}
    if flags.masked then
        if flags.saturated then return settings.masked_saturated_material_name end
        if flags.point_sample then return settings.masked_point_sample_material_name end
        return settings.masked_material_name
    end
    if flags.saturated then return settings.saturated_material_name end
    if flags.point_sample then return settings.point_sample_material_name end
    if flags.viewport_mask then return settings.viewport_mask_material_name end
    return settings.material_name
end

-- Proves resource closure against the exact Gui that will draw the icon.
-- Gui.material is a lookup only; no bitmap is submitted on this path.
function M.renderer_has_texture(renderer, texture_name, atlas_helper, gui_api, flags)
    local material_name = M.material_name(texture_name, atlas_helper, flags)
    if type(material_name) ~= "string" or material_name == "" then
        return false, material_name
    end
    if type(renderer) ~= "table" or renderer.gui == nil
        or type(gui_api) ~= "table" or type(gui_api.material) ~= "function" then
        return false, material_name
    end
    local ok, material = pcall(gui_api.material, renderer.gui, material_name)
    return ok and material ~= nil, material_name
end

local function _append_unique(values, seen, value)
    if type(value) == "string" and value ~= "" and not seen[value] then
        seen[value] = true
        values[#values + 1] = value
    end
end

local function _fallback_candidates(entry, item_master_list, provider_resolve)
    local data = entry.item_data or {}
    local icon = data.inventory_icon
    local values, seen = {}, {}
    if type(icon) == "string" then seen[icon] = true end

    if type(provider_resolve) == "function" then
        local ok, resolved, was_custom = pcall(provider_resolve, icon, M.RENDERER_NAME)
        if ok and was_custom then _append_unique(values, seen, resolved) end
    end
    _append_unique(values, seen, data.cim_athanor_inventory_icon)
    _append_unique(values, seen, data.cim_inventory_icon_fallback)

    -- CWV clones retain the base weapon's name/key specifically for vanilla
    -- fallback lookups. Prefer that authored vanilla family icon before the
    -- generic slot placeholder. This also works when CWV's optional descriptor
    -- is unavailable because of mod load order.
    local base_keys = { data.name, data.key, data.cim_base_weapon }
    for i = 1, 3 do
        local base_key = base_keys[i]
        local base = type(item_master_list) == "table" and type(base_key) == "string"
            and rawget(item_master_list, base_key)
        if type(base) == "table" and base ~= data and base.cwv_variant ~= true then
            _append_unique(values, seen, base.inventory_icon)
        end
    end
    _append_unique(values, seen, M.PLACEHOLDERS[data.slot_type] or "icons_placeholder")
    return values
end

-- Returns a new outer layout only when a row needs substitution or omission;
-- ItemMasterList/provider data is never mutated. Every returned row has an icon
-- that `has_texture` proved renderable for the exact Athanor top renderer.
function M.sanitize_layout(layout, args)
    args = args or {}
    local has_texture = args.has_texture
    local report = { total = 0, verified = 0, fallback = 0, omitted = 0, changes = {} }
    local safe_layout = {}
    if type(layout) ~= "table" or type(has_texture) ~= "function" then
        return safe_layout, report
    end

    for i = 1, #layout do
        local entry = layout[i]
        local data = type(entry) == "table" and entry.item_data
        local icon = type(data) == "table" and data.inventory_icon
        report.total = report.total + 1
        local ok, safe = pcall(has_texture, icon)
        if ok and safe then
            report.verified = report.verified + 1
            safe_layout[#safe_layout + 1] = entry
        else
            local replacement
            for _, candidate in ipairs(_fallback_candidates(
                entry or {}, args.item_master_list, args.provider_resolve)) do
                local probe_ok, candidate_safe = pcall(has_texture, candidate)
                if probe_ok and candidate_safe then
                    replacement = candidate
                    break
                end
            end
            if replacement then
                local safe_entry = _copy(entry)
                safe_entry.item_data = _copy(data)
                safe_entry.item_data.inventory_icon = replacement
                safe_entry.item_data.cim_athanor_original_icon = icon
                safe_layout[#safe_layout + 1] = safe_entry
                report.fallback = report.fallback + 1
                report.changes[#report.changes + 1] = {
                    key = entry.key, original = icon, replacement = replacement,
                }
            else
                report.omitted = report.omitted + 1
                report.changes[#report.changes + 1] = {
                    key = entry and entry.key, original = icon, replacement = nil,
                }
            end
        end
    end
    return safe_layout, report
end

return M
