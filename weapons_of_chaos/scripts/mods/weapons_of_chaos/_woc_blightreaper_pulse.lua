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

function M.new(policy, transform_appearance, injected)
	local api = injected or defaults()
	local unit_api = api.unit
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
		local can_get = application and application.can_get
		if type(can_get) ~= "function" then return false end
		local ok, ready = pcall(can_get, kind, name)
		return ok and ready == true
	end

	function runtime.apply(unit, transform, perspective, surface)
		if not alive(unit) then return false, "unit-unavailable" end
		if applied[unit] then return true, "already-applied" end
		local descriptor = policy and policy.pulse_descriptor
			and policy.pulse_descriptor(perspective)
		if type(descriptor) ~= "table" then return false, "descriptor-unavailable" end

		if not resource_ready("material", descriptor.material) then
			diagnostic_once("material:" .. tostring(descriptor.material),
				"[WOC:613] pulse SKIP reason=material-not-resident resource=%s chat=false",
				tostring(descriptor.material))
			return false, "material-not-resident"
		end
		for _, binding in ipairs(descriptor.textures or {}) do
			if not resource_ready("texture", binding.texture) then
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

		local material_ok = pcall(unit_api.set_all_materials, unit, descriptor.material)
		if not material_ok then return false, "material-bind-rejected" end
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
			and transform_appearance.apply(unit, transform)
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
