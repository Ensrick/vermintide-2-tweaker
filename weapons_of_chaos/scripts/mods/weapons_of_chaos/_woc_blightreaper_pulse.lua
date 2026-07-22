-- Event-driven, unit-local Blightreaper material application.
--
-- The native trophy pulse is a shader/material effect, not a particle or flow.
-- WOC borrows the universally available runed Empire sword shader graph, then
-- replaces every texture and the native pulse variables on the spawned unit.
-- There is no update loop and no network traffic.
local M = {}

local function defaults()
	return {
		unit = rawget(_G, "Unit"),
		application = rawget(_G, "Application"),
		script_unit = rawget(_G, "ScriptUnit"),
		printf = rawget(_G, "printf"),
	}
end

function M.new(policy, transform_appearance, injected, residency_contract)
	local api = injected or defaults()
	local unit_api = api.unit
	local mesh_api = api.mesh or rawget(_G, "Mesh")
	local application = api.application
	local script_unit = api.script_unit
	local print_fn = api.printf
	local applied = setmetatable({}, { __mode = "k" })
	local diagnostics = {}
	local runtime = {}

	local function diagnostic_once(key, format, ...)
		if diagnostics[key] then return end
		diagnostics[key] = true
		if type(print_fn) == "function" then pcall(print_fn, format, ...) end
	end

	local function alive(unit)
		if unit == nil or type(unit_api) ~= "table"
				or type(unit_api.alive) ~= "function" then return false end
		local ok, value = pcall(unit_api.alive, unit)
		return ok and value == true
	end

	local function resource_ready(kind, name)
		if residency_contract and type(residency_contract.resource_resident) == "function" then
			return residency_contract.resource_resident(
				kind, name, application, nil, "woc_blightreaper_pulse") == true
		end
		-- Unit-test compatibility. Production always receives the synchronized V2
		-- contract from weapons_of_chaos.lua.
		local can_get = application and application.can_get
		if type(can_get) ~= "function" then return false end
		local ok, ready = pcall(can_get, kind, name)
		return ok and ready == true
	end

	local function resolved_transform(unit, transform)
		if type(transform) ~= "table" then return nil, "transform-unavailable" end
		local node_name = policy and policy.TRANSFORM_NODE_NAME
		if type(node_name) ~= "string" or type(unit_api.has_node) ~= "function"
				or type(unit_api.node) ~= "function" then
			return nil, "transform-node-api-unavailable"
		end
		local has_ok, has_node = pcall(unit_api.has_node, unit, node_name)
		if not has_ok or has_node ~= true then
			return nil, "transform-node-missing"
		end
		local node_ok, node = pcall(unit_api.node, unit, node_name)
		if not node_ok or type(node) ~= "number" then
			return nil, "transform-node-unresolved"
		end
		return {
			node = node,
			scale = transform.scale,
			offset = transform.offset,
			position = transform.position,
			rotation = transform.rotation,
		}
	end

	function runtime.apply(unit, transform, perspective, surface)
		if not alive(unit) then return false, "unit-unavailable" end
		if applied[unit] then return true, "already-applied" end
		local descriptor = policy and policy.pulse_descriptor
			and policy.pulse_descriptor(perspective)
		if type(descriptor) ~= "table" then return false, "descriptor-unavailable" end
		local transform_spec, transform_reason = resolved_transform(unit, transform)
		if not transform_spec then
			diagnostic_once("transform-node:" .. tostring(transform_reason),
				"[WOC:712] transform SKIP reason=%s node_name=%s chat=false",
				tostring(transform_reason), tostring(policy and policy.TRANSFORM_NODE_NAME))
			return false, transform_reason
		end

		if not resource_ready("material", descriptor.material) then
			diagnostic_once("material:" .. tostring(descriptor.material),
				"[WOC:613] pulse SKIP reason=material-not-resident resource=%s chat=false",
				tostring(descriptor.material))
			return false, "material-not-resident"
		end
		local texture_ready = residency_contract
			and type(residency_contract.texture_set_resident) == "function"
			and residency_contract.texture_set_resident(
				descriptor.textures, application, nil, "woc_blightreaper_pulse")
		if residency_contract and texture_ready ~= true then
			diagnostic_once("texture-set",
				"[WOC:613] pulse SKIP reason=texture-set-not-resident chat=false")
			return false, "texture-not-resident"
		end
		for _, binding in ipairs(descriptor.textures or {}) do
			if not residency_contract and not resource_ready("texture", binding.texture) then
				diagnostic_once("texture:" .. tostring(binding.texture),
					"[WOC:613] pulse SKIP reason=texture-not-resident resource=%s chat=false",
					tostring(binding.texture))
				return false, "texture-not-resident"
			end
		end

		if type(unit_api.set_all_materials) ~= "function"
				or type(unit_api.set_texture_for_materials) ~= "function"
				or type(script_unit) ~= "table"
				or type(script_unit.set_material_variable) ~= "function" then
			return false, "material-api-unavailable"
		end
		if residency_contract and type(residency_contract.unit_materials_resident) ~= "function" then
			return false, "residency-contract-incomplete"
		end

		local material_ok = pcall(unit_api.set_all_materials, unit, descriptor.material)
		if not material_ok then return false, "material-bind-rejected" end
		if residency_contract then
			local closure_ok, closure_reason = residency_contract.unit_materials_resident(
				unit, unit_api, mesh_api, nil, "woc_blightreaper_pulse")
			if closure_ok ~= true then
				diagnostic_once("unit-material:" .. tostring(closure_reason),
					"[WOC:613] pulse SKIP reason=unit-material-unready detail=%s chat=false",
					tostring(closure_reason))
				return false, "unit-material-unready"
			end
		end
		for _, binding in ipairs(descriptor.textures or {}) do
			local ok = pcall(unit_api.set_texture_for_materials,
				unit, binding.slot, binding.texture)
			if not ok then return false, "texture-bind-rejected" end
		end
		for _, variable in ipairs(descriptor.variables or {}) do
			local ok = pcall(script_unit.set_material_variable,
				unit, variable.name, variable.value, true)
			if not ok then return false, "variable-bind-rejected" end
		end

		local transformed = transform_appearance
			and transform_appearance.apply
			and transform_appearance:apply(unit, transform_spec, perspective, surface)
		if transformed ~= true then return false, "transform-rejected" end

		applied[unit] = true
		diagnostic_once("applied:" .. tostring(surface) .. ":" .. tostring(perspective),
			"[WOC:613] pulse applied surface=%s perspective=%s textures=%d variables=%d chat=false",
			tostring(surface), tostring(perspective), #(descriptor.textures or {}),
			#(descriptor.variables or {}))
		return true, "applied"
	end

	return runtime
end

return M
