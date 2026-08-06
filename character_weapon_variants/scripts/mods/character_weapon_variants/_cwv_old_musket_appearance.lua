-- Phase-3 appearance pilot for the CWV Old Musket (#1155/#474/#660).
--
-- One immutable descriptor is resolved before an engine adapter runs.  Every
-- surface enters through `reconcile`; no surface owns a model/material/pose
-- recipe.  The shared reconciler applies at most twice per exact lifecycle
-- token and commits only after this module reads retained state back from the
-- live unit.  Unsupported renderers explicitly retain vanilla presentation.
local M = {}

local UNIT_SURFACES = {
	owner_1p = "1p", owner_3p = "3p", bot = "3p", husk = "3p",
	inventory_preview = "3p", illusion_browser = "3p", cim_preview = "3p",
	lobby = "3p", score_team = "3p",
}

local IMPLEMENTED_CELLS = {
	owner_1p = { equip = true, customize = true },
	owner_3p = { equip = true, customize = true },
	bot = { equip = true },
	husk = { equip = true, peer_ready = true },
	inventory_preview = { preview_open = true },
	illusion_browser = { preview_open = true },
	lobby = { preview_open = true },
	score_team = { preview_open = true },
}

local function item_backend_id(item)
	local data = type(item) == "table" and item.data or nil
	local mod_data = type(item) == "table" and (item.mod_data
		or (data and data.mod_data)) or nil
	return type(item) == "table" and (item.backend_id or item.ItemInstanceId
		or (data and (data.backend_id or data.ItemInstanceId))
		or (mod_data and mod_data.backend_id)) or nil
end

local function identity_evidence(item, surface, context)
	local bid = item_backend_id(item)
	if type(bid) == "string" and #bid > 0 then
		return { kind = "backend_id", value = bid }
	end
	if context and context.peer_id and context.slot_name then
		return { kind = "loadout_snapshot", value = tostring(context.peer_id)
			.. ":" .. tostring(context.slot_name) }
	end
	return { kind = "preview_slot", value = tostring(surface or "unknown") }
end

local function vector_elements(api, value)
	if type(value) == "table" and type(value[1]) == "number"
			and type(value[2]) == "number" and type(value[3]) == "number" then
		return { value[1], value[2], value[3] }
	end
	if not value or not api or type(api.to_elements) ~= "function" then return nil end
	local ok, x, y, z = pcall(api.to_elements, value)
	return ok and { x, y, z } or nil
end

local function quaternion_elements(api, value)
	if not value or not api or type(api.to_elements) ~= "function" then return nil end
	local ok, x, y, z, w = pcall(api.to_elements, value)
	return ok and { x, y, z, w } or nil
end

local function near3(actual, expected, epsilon)
	if type(actual) ~= "table" or type(expected) ~= "table" then return false end
	for i = 1, 3 do
		if type(actual[i]) ~= "number" or type(expected[i]) ~= "number"
				or math.abs(actual[i] - expected[i]) > epsilon then return false end
	end
	return true
end

local function quaternion_near(actual, expected, epsilon)
	if type(actual) ~= "table" or type(expected) ~= "table" then return false end
	local dot = 0
	for i = 1, 4 do
		if type(actual[i]) ~= "number" or type(expected[i]) ~= "number" then return false end
		dot = dot + actual[i] * expected[i]
	end
	-- q and -q encode the same rotation.
	return math.abs(math.abs(dot) - 1) <= epsilon
end

function M.new(args)
	args = args or {}
	local D, WA, policy = args.descriptor, args.weapon_appearance, args.policy
	local unit_api = args.unit
	local vector_api = args.vector
	local quaternion_api = args.quaternion
	local transform_source = args.transform_source
	local canonical_key = args.canonical_key
	local printf_fn = args.printf or function() end
	assert(type(D) == "table" and type(D.build) == "function", "descriptor contract required")
	assert(type(WA) == "table" and type(WA.apply_report) == "function", "appearance writer required")
	assert(type(policy) == "table", "Old Musket resource policy required")

	local tracked = setmetatable({}, { __mode = "k" })
	local generation = 0
	local C = {}

	local function mode_for(item, explicit)
		if explicit == "melee" then return "melee" end
		local data = type(item) == "table" and item.data or nil
		local md = type(item) == "table" and (item.mod_data
			or (data and data.mod_data)) or nil
		return md and md.cwv_musket_stance == "melee" and "melee" or "ranged"
	end

	local function recipe(perspective, mode)
		local position, rotation, scale = transform_source(perspective, mode)
		local unboxed = rotation
		if rotation ~= nil then
			local ok, value = pcall(function()
				return rotation.unbox and rotation:unbox() or rotation
			end)
			unboxed = ok and value or nil
		end
		return {
			position = vector_elements(vector_api, position),
			scale = vector_elements(vector_api, scale),
			rotation = quaternion_elements(quaternion_api, unboxed),
		}
	end

	function C.resolve(item, explicit_mode, surface, context)
		local key = canonical_key(item)
		if key ~= policy.ITEM_KEY and not policy.matches_item(item, key) then return nil end
		local mode = mode_for(item, explicit_mode)
		local one_p = recipe("1p", mode)
		local three_p = recipe("3p", mode)
		local descriptor, errors = D.build({
			item_key = policy.ITEM_KEY,
			skin_key = policy.SKIN_KEY,
			identity_evidence = identity_evidence(item, surface, context),
			mode = mode,
			requires_mod = "character_weapon_variants",
			right_hand_unit = { unit = policy.UNIT, unit_3p = policy.UNIT_3P,
				package = policy.PREVIEW_PACKAGE_ALIAS },
			textures = policy.TEXTURES,
			materials = { preview = policy.PREVIEW_MATERIAL },
			transform_1p = one_p,
			transform_3p = three_p,
			fallback = {
				right_hand_unit = { unit = policy.NETWORK_PACKAGE_ALIAS_1P,
					unit_3p = policy.NETWORK_PACKAGE_ALIAS_3P,
					package = policy.PREVIEW_PACKAGE_ALIAS },
				textures = {}, materials = {},
			},
			generation = generation,
		})
		if not descriptor then return nil, errors end
		return descriptor
	end

	local function target_is_custom(descriptor, surface, context)
		if context and context.unit_name then
			local expected = surface == "owner_1p" and descriptor.right_hand_unit.unit
				or descriptor.right_hand_unit.unit_3p
			return context.unit_name == expected
		end
		return not (context and context.custom_unit == false)
	end

	local function engine_rotation(value)
		if type(value) ~= "table" or #value ~= 4 then return nil end
		local ok, rotation = pcall(quaternion_api,
			value[1], value[2], value[3], value[4])
		return ok and rotation or nil
	end

	local function apply(descriptor, surface, edge, target, context)
		local perspective = UNIT_SURFACES[surface]
		if not perspective or not (IMPLEMENTED_CELLS[surface]
				and IMPLEMENTED_CELLS[surface][edge]) then
			return { fallback = true, reason = "surface-retains-vanilla-presentation" }
		end
		if not target_is_custom(descriptor, surface, context) then
			return { fallback = true, reason = "custom-unit-not-retained" }
		end
		local preview = surface == "inventory_preview" or surface == "illusion_browser"
			or surface == "cim_preview" or surface == "lobby" or surface == "score_team"
		local painted, texture_count = policy.apply_textures(target, preview)
		context = context or {}
		context._appearance_required_paint = painted == true
			and (texture_count or 0) >= #(descriptor.textures or {})
		local spec = perspective == "1p" and descriptor.transform_1p or descriptor.transform_3p
		local resolved_rotation = engine_rotation(spec.rotation)
		local report = WA.apply_report(target, {
			position = spec.position, scale = spec.scale,
			rotation = resolved_rotation,
		})
		context._appearance_required_apply = resolved_rotation ~= nil and report.ok == true
		report.painted = painted == true
		report.texture_writes = texture_count or 0
		tracked[target] = { item = context and context.item, mode = descriptor.mode,
			surface = surface, edge = edge, context = context }
		return report
	end

	local function observe(descriptor, surface, _, target, context)
		if not target_is_custom(descriptor, surface, context) then
			return { retained = false, reason = "unit-identity-mismatch" }
		end
		local alive_ok, alive = pcall(unit_api.alive, target)
		if not alive_ok or alive ~= true then return { retained = false, reason = "unit-dead" } end
		local perspective = UNIT_SURFACES[surface]
		if not perspective then return { retained = true, reason = "vanilla-fallback" } end
		local spec = perspective == "1p" and descriptor.transform_1p or descriptor.transform_3p
		local ok_p, position = pcall(unit_api.local_position, target, 0)
		local ok_s, scale = pcall(unit_api.local_scale, target, 0)
		local ok_r, rotation = pcall(unit_api.local_rotation, target, 0)
		local retained_position = ok_p and near3(vector_elements(vector_api, position), spec.position, 0.002)
		local retained_scale = ok_s and near3(vector_elements(vector_api, scale), spec.scale, 0.002)
		local retained_rotation = ok_r and quaternion_near(
			quaternion_elements(quaternion_api, rotation), spec.rotation, 0.003)
		local materials_ready = policy.unit_materials_ready(target)
		local retained = context and context._appearance_required_paint == true
			and context._appearance_required_apply == true
			and retained_position and retained_scale and retained_rotation
			and materials_ready == true
		return {
			retained = retained,
			reason = retained and "retained" or "retained-postcondition-failed",
			position = retained_position, scale = retained_scale,
			rotation = retained_rotation, materials = materials_ready == true,
			paint = context and context._appearance_required_paint == true,
			apply = context and context._appearance_required_apply == true,
		}
	end

	local reconciler = D.new_reconciler({ apply = apply, observe = observe, max_attempts = 2 })

	function C.reconcile(target, surface, edge, item, explicit_mode, context)
		context = context or {}; context.item = item
		local descriptor, errors = C.resolve(item, explicit_mode, surface, context)
		if not descriptor then return { ok = false, reason = "identity-unresolved", errors = errors } end
		local result = reconciler.reconcile(descriptor, surface, edge, target, context)
		pcall(printf_fn,
			"[cwv:1155] family=old_musket surface=%s edge=%s fingerprint=%s retained=%s fallback=%s reason=%s attempts=%s chat=false",
			tostring(surface), tostring(edge), D.fingerprint(descriptor),
			tostring(result.retained == true), tostring(result.fallback == true),
			tostring(result.reason), tostring(result.attempts or 0))
		return result, descriptor
	end

	function C.forget(target) return reconciler.forget(target) end
	function C.disconnect() tracked = setmetatable({}, { __mode = "k" }); return reconciler.disconnect() end

	-- Dev tuning is an explicit generation edge, never an update-loop owner.
	function C.reapply_tracked()
		generation = generation + 1
		local applied = 0
		for target, record in pairs(tracked) do
			local alive_ok, alive = pcall(unit_api.alive, target)
			if alive_ok and alive then
				local result = C.reconcile(target, record.surface, "customize",
					record.item, record.mode, record.context)
				if result and result.ok then applied = applied + 1 end
			else tracked[target] = nil end
		end
		return applied
	end

	function C.preview_targets(descriptor, units, spawn_data)
		local targets = {}
		if not descriptor or type(units) ~= "table" or type(spawn_data) ~= "table" then return targets end
		for index, unit in ipairs(units) do
			local path = spawn_data[index] and spawn_data[index].unit_name
			if path == descriptor.right_hand_unit.unit or path == descriptor.right_hand_unit.unit_3p then
				targets[#targets + 1] = unit
			end
		end
		return targets
	end

	C.reconciler = reconciler
	C.unit_surfaces = UNIT_SURFACES
	C.implemented_cells = IMPLEMENTED_CELLS
	return C
end

return M
