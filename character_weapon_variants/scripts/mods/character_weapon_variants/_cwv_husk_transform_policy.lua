-- Pure selection/application policy for production remote-husk transforms.
-- Engine-facing code supplies the live registries; keeping the decision here
-- makes model-aware reconstruction independently testable without duplicating
-- the render boundary.
local M = {}

function M.bind(deps)
	assert(type(deps) == "table", "husk transform dependencies are required")
	assert(type(deps.find_def) == "function", "find_def dependency is required")
	assert(type(deps.resolve_def) == "function", "resolve_def dependency is required")
	assert(type(deps.plan_transform) == "function", "plan_transform dependency is required")
	assert(type(deps.model_by_unit) == "table", "model_by_unit dependency is required")

	local function select(hand, exact, item_data, skin, resolved_unit_name, style_decision)
		if style_decision then return style_decision, "style" end
		local field = hand == "left" and "left_hand_unit" or "right_hand_unit"
		local exact_unit = exact and exact[field]
		if exact_unit then
			if resolved_unit_name ~= exact_unit then return nil, "exact_unit_mismatch" end
			local model_def = deps.model_by_unit[exact_unit]
			if model_def then return model_def, "exact_model" end
		end
		if exact then return deps.find_def(exact.variant_key), "exact_variant" end
		local resolved = deps.resolve_def(item_data, skin, resolved_unit_name)
		return resolved, resolved and "resolved" or "miss"
	end

	local function plan(hand, def, source)
		if not def then return nil end
		local resolved = deps.plan_transform(def, hand, "3p")
		return {
			def = def,
			source = source,
			scale = resolved.scale,
			scale_multiplier = resolved.scale_multiplier,
			offset = resolved.offset,
			rotation = resolved.rotation,
			should_apply = resolved.should_apply,
			durable = resolved.should_apply and def.crowbill_model_key ~= nil or false,
		}
	end

	return { select = select, plan = plan }
end

return M
