-- Engine-free transform-definition contract shared by every CWV render surface.
-- A crafted UUID is allowed to reach a transform only through the canonical
-- item resolver; no consumer may infer a variant from its inherited vanilla
-- name.  The bound functions are deliberately small so the live hooks and the
-- #482 runtime regression can execute the exact same decisions.
local M = {}

function M.bind(deps)
	assert(type(deps) == "table", "transform consumer dependencies are required")
	assert(type(deps.resolve_def) == "function", "resolve_def dependency is required")
	assert(type(deps.resolve_key) == "function", "resolve_key dependency is required")
	assert(type(deps.transform_map) == "table", "transform_map dependency is required")
	assert(type(deps.skin_transform_map) == "table", "skin_transform_map dependency is required")
	assert(type(deps.style_decision) == "function", "style_decision dependency is required")

	local function world(item_data, skin, resolved_unit_name)
		return deps.resolve_def(item_data, skin, resolved_unit_name)
	end

	local function preview(item_name, info, model_def)
		local handled, decision = deps.style_decision({ name = item_name },
			info and info.backend_id)
		if handled then return decision end
		local skin = info and info.skin_name
		if skin and deps.skin_transform_map[skin] then
			return deps.skin_transform_map[skin]
		end
		if model_def then return model_def end
		if info and info.backend_id then
			local key = deps.resolve_key(info.backend_id, nil)
			if key and deps.transform_map[key] then return deps.transform_map[key] end
		end
		return deps.transform_map[item_name]
	end

	local function browser(item, weapon_key, model_def, explicit_skin_def)
		local item_data = item and item.data
		local def = model_def or explicit_skin_def or deps.transform_map[weapon_key]
		local key = deps.resolve_key(item and item.backend_id, item_data)
		if key and not model_def and not explicit_skin_def then
			def = deps.transform_map[key] or deps.skin_transform_map[key] or def
		end
		local handled, decision = deps.style_decision(item_data, item and item.backend_id)
		if handled then def = decision end
		return def, key
	end

	return {
		world = world,
		preview = preview,
		browser = browser,
	}
end

return M
