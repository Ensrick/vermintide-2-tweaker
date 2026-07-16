-- Renderer capability contract for WOC-owned inventory icons.
--
-- VMF injects a custom GUI material into named renderers; packaging the
-- material alone does not make it safe in every Gui. Consumers must retain a
-- resident vanilla fallback for any renderer outside this allow-list.
local M = {}

M.SCHEMA = 1
M.ICON = "icon_wpn_blightreaper"
M.MATERIAL = "materials/ui/icon_wpn_blightreaper"
M.TEXTURE = "gui/1080p/single_textures/weapons_of_chaos/icon_wpn_blightreaper"
M.SAFE_RENDERERS = {
	ingame_ui = true,
	hero_view = true,
	loading_view = true,
	popup_manager = true,
}

function M.describe(icon_id, renderer_name, fallback)
	if icon_id ~= M.ICON then return nil end
	return {
		schema = M.SCHEMA,
		material = M.MATERIAL,
		custom = true,
		safe = M.SAFE_RENDERERS[renderer_name] == true,
		fallback = fallback,
	}
end

function M.resolve(icon_id, renderer_name, fallback)
	local row = M.describe(icon_id, renderer_name, fallback)
	if not row then return icon_id, false end
	return row.safe and icon_id or fallback, true
end

return M
