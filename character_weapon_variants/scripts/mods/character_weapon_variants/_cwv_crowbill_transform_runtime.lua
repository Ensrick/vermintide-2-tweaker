-- Engine-facing lifecycle owner for exact Crowbill transforms.
--
-- The entry module resolves authored fields and schedules units here. This
-- owner waits until the next update to sample the attachment-owned baseline,
-- repairs the canonical pose, lets Crowbill presentation write last, and then
-- records the final renderer-facing state. Networking and item identity remain
-- outside this module.
local M = {}

local function triplet_text(value)
	if type(value) ~= "table" then return "nil" end
	return string.format("%.3f,%.3f,%.3f", value[1] or 0, value[2] or 0, value[3] or 0)
end

function M.new(deps)
	deps = deps or {}
	local om = assert(deps.om, "om dependency is required")
	local appearance = assert(deps.appearance, "appearance dependency is required")
	local durable_library = assert(deps.durable_library, "durable library is required")
	local relative_library = assert(deps.relative_library, "relative-scale library is required")
	local evidence_library = assert(deps.evidence_library, "evidence library is required")
	local emit = deps.emit or function() end
	local first_tick = setmetatable({}, { __mode = "k" })

	local relative = relative_library.new({
		read_scale = function(unit)
			if not (unit and Unit.alive(unit)) then return nil end
			local ok, current = pcall(Unit.local_scale, unit, 0)
			if not ok or not current then return nil end
			local elements_ok, x, y, z = pcall(Vector3.to_elements, current)
			if not elements_ok then return nil end
			return { x, y, z }
		end,
	})

	local evidence = evidence_library.new({
		total_limit = 96,
		per_model_limit = 16,
		emit = function(row)
			emit(
				"[cwv:604] retained phase=%s surface=%s perspective=%s hand=%s model=%s unit_name=%s unit_id=%s generation=%s owner=%s slot=%s source=%s scale=(%s) pos=(%s) rot=(%s) model_index=%d/%d total_index=%d/%d",
				tostring(row.phase), tostring(row.surface), tostring(row.perspective),
				tostring(row.hand), tostring(row.model_key), tostring(row.unit_name),
				tostring(row.unit_id), tostring(row.generation), tostring(row.owner_id),
				tostring(row.slot_name), tostring(row.def_source), tostring(row.scale),
				tostring(row.position), tostring(row.rotation), row.model_index,
				row.per_model_limit, row.index, row.total_limit)
		end,
	})

	local function read_state(unit)
		if not (unit and Unit.alive(unit)) then return nil end
		local has0 = false
		pcall(function() has0 = Unit.has_node(unit, 0) and true or false end)
		if not has0 then return nil end
		local scale, position, rotation = "nil", "nil", "nil"
		pcall(function()
			local value = Unit.local_scale(unit, 0)
			if value then scale = triplet_text({ Vector3.to_elements(value) }) end
		end)
		pcall(function()
			local value = Unit.local_position(unit, 0)
			if value then position = triplet_text({ Vector3.to_elements(value) }) end
		end)
		pcall(function()
			local value = Unit.local_rotation(unit, 0)
			if value then
				local x, y, z, w = Quaternion.to_elements(value)
				rotation = string.format("%.3f,%.3f,%.3f,%.3f", x or 0, y or 0, z or 0, w or 0)
			end
		end)
		return { scale = scale, position = position, rotation = rotation,
			fingerprint = scale .. "|" .. position .. "|" .. rotation }
	end

	local function observe(phase, unit, spec)
		if not (spec and spec.model_key) then return false end
		local state = read_state(unit)
		if not state then return false end
		return evidence:observe({
			phase = phase, surface = spec.surface, perspective = spec.perspective,
			hand = spec.hand, model_key = spec.model_key, unit_name = spec.unit_name,
			unit_id = tostring(unit), generation = spec.generation,
			owner_id = spec.owner_id, slot_name = spec.slot_name,
			def_source = spec.def_source, scale = state.scale,
			position = state.position, rotation = state.rotation,
			fingerprint = state.fingerprint,
		})
	end

	local durable = durable_library.new({
		alive = function(unit) return unit and Unit.alive(unit) end,
		before_apply = function(unit, spec)
			observe("pre_repair", unit, spec)
		end,
		apply = function(unit, spec)
			local wrote = false
			if spec.scale_multiplier then
				local resolved, baseline = relative:resolve(
					unit, spec.scale_multiplier, spec.identity_token)
				if resolved then spec.scale, spec.scale_baseline = resolved, baseline end
			end
			if spec.scale then wrote = appearance.apply_scale(unit, spec.scale) or wrote end
			if spec.position then
				wrote = appearance.apply_position(unit, spec.position:unbox()) or wrote
			end
			if spec.rotation then wrote = appearance.apply_rotation(unit, spec.rotation) or wrote end
			if wrote and not first_tick[unit] then
				first_tick[unit] = true
				emit("[cwv:604] durable transform active surface=%s perspective=%s hand=%s model=%s unit=%s generation=%s",
					tostring(spec.surface), tostring(spec.perspective), tostring(spec.hand),
					tostring(spec.model_key), tostring(spec.unit_name), tostring(spec.generation))
			end
			return wrote
		end,
		after_all = function()
			if om.crowbill_presentation_owner
					and type(om.crowbill_presentation_owner.reapply_all) == "function" then
				om.crowbill_presentation_owner:reapply_all()
			end
		end,
		after_final = function(unit, spec)
			observe("post_final", unit, spec)
		end,
		on_forget = function(unit)
			relative:forget(unit)
			first_tick[unit] = nil
			if om.crowbill_presentation_owner
					and type(om.crowbill_presentation_owner.forget) == "function" then
				om.crowbill_presentation_owner:forget(unit)
			end
		end,
	})

	return { durable = durable, evidence = evidence, relative = relative }
end

return M
