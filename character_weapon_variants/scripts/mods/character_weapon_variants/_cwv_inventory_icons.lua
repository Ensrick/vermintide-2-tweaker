-- Cross-mod inventory-icon safety contract.
--
-- CWV's paired Dual Axe icons live in a private atlas. A material name being
-- packaged does not make it available to every UI renderer: VMF injects the
-- atlas into an explicit renderer allow-list. Consumers such as CIM must call
-- resolve() and use the vanilla fallback for any other renderer (notably the
-- Athanor top renderer), otherwise ui_passes.lua receives a nil texture.
local M = {}

M.SCHEMA = 1
M.ATLAS = "materials/character_weapon_variants/cwv_weapon_icons"
M.SAFE_RENDERERS = {
	ingame_ui = true,
	hero_view = true,
	loading_view = true,
	popup_manager = true,
}

M.FALLBACKS = {
	icon_axe_hatchet_t2_magic_01_dual_cwv = "icon_axe_hatchet_t2_magic_01",
	icon_wh_1h_axe_skin_06_magic_02_dual_cwv = "icon_wh_1h_axe_skin_06_magic_02",
	icon_wpn_axe_02_t1_dual_cwv = "icon_wpn_axe_02_t1",
	icon_wpn_axe_02_t2_dual_cwv = "icon_wpn_axe_02_t2",
	icon_wpn_axe_02_t2_runed_06_dual_cwv = "icon_wpn_axe_02_t2_runed_06",
	icon_wpn_axe_03_t1_dual_cwv = "icon_wpn_axe_03_t1",
	icon_wpn_axe_03_t2_dual_cwv = "icon_wpn_axe_03_t2",
	icon_wpn_axe_hatchet_t1_dual_cwv = "icon_wpn_axe_hatchet_t1",
	icon_wpn_axe_hatchet_t2_dual_cwv = "icon_wpn_axe_hatchet_t2",
}

function M.describe(icon_id, renderer_name)
	local fallback = M.FALLBACKS[icon_id]
	if not fallback then return nil end
	return {
		schema = M.SCHEMA,
		atlas = M.ATLAS,
		custom = true,
		safe = M.SAFE_RENDERERS[renderer_name] == true,
		fallback = fallback,
	}
end

function M.resolve(icon_id, renderer_name)
	local row = M.describe(icon_id, renderer_name)
	if not row then return icon_id, false end
	return row.safe and icon_id or row.fallback, true
end

-- VMF custom_atlas exposes base/masked/saturated fields but has no argument
-- for the masked+saturated field selected by the Athanor list
-- (UIRenderer.script_draw_bitmap, ui_renderer.lua:91-106). These are CWV-owned
-- atlas rows, so complete that missing variant with the existing masked
-- material before CIM performs its exact-Gui proof. No vanilla row is mutated.
function M.complete_masked_saturated(atlas_helper)
	if type(atlas_helper) ~= "table"
		or type(atlas_helper.get_atlas_settings_by_texture_name) ~= "function" then
		return 0
	end
	local completed = 0
	for icon_id in pairs(M.FALLBACKS) do
		local ok, settings = pcall(atlas_helper.get_atlas_settings_by_texture_name, icon_id)
		if ok and type(settings) == "table"
			and settings.material_name == "cwv_weapon_icons"
			and settings.masked_material_name == "cwv_weapon_icons_masked" then
			local current = settings.masked_saturated_material_name
			if current == nil or current == "" then
				settings.masked_saturated_material_name = settings.masked_material_name
				current = settings.masked_saturated_material_name
			end
			-- Count any authored non-empty variant as complete. Never replace a
			-- future dedicated material merely because this compatibility fill
			-- currently aliases the masked material.
			if type(current) == "string" and current ~= "" then
				completed = completed + 1
			end
		end
	end
	return completed
end

return M
