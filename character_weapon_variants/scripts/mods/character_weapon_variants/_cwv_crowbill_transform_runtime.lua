-- Engine-facing lifecycle owner for exact Crowbill transforms.
--
-- The entry module resolves authored fields and schedules units here. This
-- owner waits until the next update to sample the attachment-owned baseline,
-- repairs the canonical pose, lets Crowbill presentation write last, and then
-- records the final renderer-facing state. Networking and item identity remain
-- outside this module.
--
-- #747 durable-transform pattern (canonical: weapons_of_chaos/
-- _woc_durable_transform.lua): the per-tick apply is a retained-pose check
-- first, an ATOMIC pose write (WA.apply -> Unit.set_local_pose) only on
-- measured drift, and a post-write readback whose comparison - never the
-- setter result - is what the bounded [cwv:747] retained-proof receipts
-- report. The OR-of-three-setters shape (class 58) is deliberately gone:
-- a setter returning true while the engine keeps the native pose was the
-- documented false positive. Replay uses the ABSOLUTE captured position,
-- never the authored offset, so repair stays idempotent.
local M = {}

local EPSILON = 0.0001

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

	-- Numeric channel snapshot for drift measurement; nil when the unit or its
	-- root node is not readable this tick.
	local function read_numeric(unit)
		if not (unit and Unit.alive(unit)) then return nil end
		local has0 = false
		pcall(function() has0 = Unit.has_node(unit, 0) and true or false end)
		if not has0 then return nil end
		local snapshot = {}
		local ok = pcall(function()
			local scale = Unit.local_scale(unit, 0)
			if scale then snapshot.scale = { Vector3.to_elements(scale) } end
			local position = Unit.local_position(unit, 0)
			if position then snapshot.position = { Vector3.to_elements(position) } end
			local rotation = Unit.local_rotation(unit, 0)
			if rotation then snapshot.rotation = { Quaternion.to_elements(rotation) } end
		end)
		if not ok then return nil end
		return snapshot
	end

	local function close(a, b)
		return type(a) == "number" and type(b) == "number"
			and math.abs(a - b) <= EPSILON
	end

	local function triplet_close(a, b)
		return type(a) == "table" and type(b) == "table"
			and close(a[1], b[1]) and close(a[2], b[2]) and close(a[3], b[3])
	end

	-- Unit quaternions may compare as q or -q for one orientation; compare the
	-- absolute normalized dot product (canonical _woc_durable_transform shape).
	local function rotation_close(a, b)
		if type(a) ~= "table" or type(b) ~= "table" then return false end
		local dot, aa, bb = 0, 0, 0
		for i = 1, 4 do
			if type(a[i]) ~= "number" or type(b[i]) ~= "number" then return false end
			dot = dot + a[i] * b[i]
			aa = aa + a[i] * a[i]
			bb = bb + b[i] * b[i]
		end
		if aa <= 0 or bb <= 0 then return false end
		return math.abs(dot / math.sqrt(aa * bb)) >= 1 - EPSILON
	end

	-- True only when every AUTHORED channel is retained; an empty target never
	-- matches so an unresolved schedule keeps retrying.
	local function matches(snapshot, target)
		if type(snapshot) ~= "table" then return false end
		local authored = false
		if target.scale then
			authored = true
			if not triplet_close(snapshot.scale, target.scale) then return false end
		end
		if target.position then
			authored = true
			if not triplet_close(snapshot.position, target.position) then return false end
		end
		if target.rotation then
			authored = true
			if not rotation_close(snapshot.rotation, target.rotation) then return false end
		end
		return authored
	end

	-- Resolve the absolute target once per tick from retained state: relative
	-- scale settles against the first sampled baseline, position replays the
	-- captured ABSOLUTE Vector3Box (never the authored offset - a durable
	-- offset replay would compound), rotation converts the authored Euler
	-- triplet through the shared appearance seam.
	local function resolve_target(unit, spec)
		if spec.scale_multiplier then
			local resolved, baseline = relative:resolve(
				unit, spec.scale_multiplier, spec.identity_token)
			if resolved then spec.scale, spec.scale_baseline = resolved, baseline end
		end
		local target = {}
		if spec.scale then
			target.scale = { spec.scale[1], spec.scale[2], spec.scale[3] }
		end
		if spec.position then
			pcall(function()
				local position = spec.position:unbox()
				if position then target.position = { Vector3.to_elements(position) } end
			end)
		end
		if spec.rotation then
			target.rotation_euler = { spec.rotation[1], spec.rotation[2], spec.rotation[3] }
			local quaternion = appearance.to_quaternion(spec.rotation)
			if quaternion then
				pcall(function()
					target.rotation = { Quaternion.to_elements(quaternion) }
				end)
			end
		end
		return target
	end

	local proof_total, PROOF_LIMIT = 0, 96
	local function proof(phase, spec, target, snapshot, mode)
		if proof_total >= PROOF_LIMIT then return end
		proof_total = proof_total + 1
		emit("[cwv:747] retained-proof phase=%s surface=%s perspective=%s hand=%s model=%s unit_name=%s generation=%s mode=%s target scale=(%s) pos=(%s) rot=(%s) readback scale=(%s) pos=(%s) rot=(%s) count=%d/%d",
			tostring(phase), tostring(spec.surface), tostring(spec.perspective),
			tostring(spec.hand), tostring(spec.model_key), tostring(spec.unit_name),
			tostring(spec.generation), tostring(mode),
			triplet_text(target.scale), triplet_text(target.position),
			triplet_text(target.rotation_euler),
			triplet_text(snapshot and snapshot.scale),
			triplet_text(snapshot and snapshot.position),
			snapshot and snapshot.rotation and string.format("%.3f,%.3f,%.3f,%.3f",
				snapshot.rotation[1] or 0, snapshot.rotation[2] or 0,
				snapshot.rotation[3] or 0, snapshot.rotation[4] or 0) or "nil",
			proof_total, PROOF_LIMIT)
	end

	local durable = durable_library.new({
		alive = function(unit) return unit and Unit.alive(unit) end,
		before_apply = function(unit, spec)
			observe("pre_repair", unit, spec)
		end,
		-- #747 schedule/apply/readback: check retained state, write atomically
		-- only on drift, then prove the readback. Never a bare setter verdict.
		apply = function(unit, spec)
			local target = resolve_target(unit, spec)
			if not (target.scale or target.position or target.rotation_euler) then
				return false
			end
			local before = read_numeric(unit)
			if matches(before, target) then
				if not spec.retention_proof_logged then
					spec.retention_proof_logged = true
					proof("next-frame-retained", spec, target, before, "no-write")
				end
				first_tick[unit] = true
				return false
			end
			local apply_spec = { node = 0, scale = target.scale,
				position = target.position, rotation = spec.rotation }
			local wrote, report = appearance.apply(unit, apply_spec)
			wrote = wrote == true
			local after = read_numeric(unit)
			local retained = wrote and matches(after, target)
			local mode = type(report) == "table" and report.transform_mode or "unknown"
			if not first_tick[unit] then
				first_tick[unit] = true
				proof(retained and "initial-retained" or "initial-miss",
					spec, target, after, mode)
			elseif not spec.drift_proof_logged then
				spec.drift_proof_logged = true
				proof(retained and "drift-repaired" or "drift-unrepaired",
					spec, target, after, mode)
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
