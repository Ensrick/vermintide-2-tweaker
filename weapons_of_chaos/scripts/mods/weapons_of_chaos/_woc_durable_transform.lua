-- Durable presentation owner for the authored Blightreaper transform.
--
-- GearUtils owns the linked attachment root before WOC receives the spawned
-- unit. The authored import exposes a separate named render node, so this owner
-- captures that node's position once, resolves the canonical WA
-- descriptor once, and re-applies only after a retained-pose comparison fails.
-- Preview worlds are event-driven and remain one-shot; gameplay 1P/3P units
-- are weak-tracked and never create network traffic.
local M = {}

M.CONTRACT = {
	attachment_node = 0,
	target_node = "authored_render_node",
	target_node_name = "blightreaper",
	position = "render_baseline_plus_offset",
	scale = "absolute",
	rotation = "absolute_euler_xyz",
	write_mode = "atomic_local_pose",
	gameplay = "retained_check_then_reapply",
	preview = "one_shot",
	transport = "none",
}

local EPSILON = 0.0001

-- Vanilla GearUtils gameplay callers pass owner 1P+3P for the local inventory
-- and nil+3P for husks. A nil+nil pair is not source-backed, so fail it closed
-- to an untracked one-shot surface instead of guessing husk ownership.
function M.classify_surface(owner_unit_1p, owner_unit_3p)
	if owner_unit_1p ~= nil then return "owner-spawn" end
	if owner_unit_3p ~= nil then return "husk-spawn" end
	return "preview-spawn"
end

-- Vanilla returns only `weapon_unit_3p, ammo_unit_3p` when owner_unit_1p is
-- nil (gear_utils.lua:276); the husk path always passes a nil 1P rig
-- (simple_husk_inventory_extension.lua:319 -> :666). A nil returned 1P unit on
-- husk/preview spawns is therefore the source contract, not a defect; only an
-- owner spawn (owner_unit_1p ~= nil, gear_utils.lua:201/:273) owes a 1P unit.
function M.expects_first_person_unit(owner_unit_1p)
	return owner_unit_1p ~= nil
end

-- A non-identity hold-pose value is authored tuner ownership whether it was
-- applied continuously or through /wt_dev_hp_apply. Live-apply controls when
-- WT writes; it does not revoke a one-shot pose that is already on the unit.
function M.dev_tuner_claims(record, setting)
	if type(record) ~= "table" or record.surface ~= "owner-spawn"
			or type(setting) ~= "function"
			or setting("wt_dev_hp_enabled", false) ~= true then return false end
	local target_slot = setting("wt_dev_hp_target_slot", "auto")
	if target_slot ~= "auto" and target_slot ~= "slot_melee" then return false end
	local prefix
	if record.perspective == "1p" then
		if setting("wt_dev_hp_enable_1p", false) ~= true then return false end
		prefix = "wt_dev_hp_fp_rh_"
	else
		if setting("wt_dev_hp_enable_3p", true) == false then return false end
		prefix = "wt_dev_hp_rh_"
	end
	for _, suffix in ipairs({ "offset_x", "offset_y", "offset_z",
			"rot_pitch", "rot_yaw", "rot_roll" }) do
		if setting(prefix .. suffix, 0) ~= 0 then return true end
	end
	for _, suffix in ipairs({ "scale_x", "scale_y", "scale_z" }) do
		if setting(prefix .. suffix, 1) ~= 1 then return true end
	end
	return false
end

local function triplet(value)
	return type(value) == "table"
		and type(value[1]) == "number"
		and type(value[2]) == "number"
		and type(value[3]) == "number"
end

local function copy_triplet(value)
	return { value[1], value[2], value[3] }
end

local function close(a, b)
	return type(a) == "number" and type(b) == "number"
		and math.abs(a - b) <= EPSILON
end

local function triplet_close(a, b)
	return triplet(a) and triplet(b)
		and close(a[1], b[1]) and close(a[2], b[2]) and close(a[3], b[3])
end

-- Unit quaternions may compare as q or -q while representing the same
-- orientation. Compare the absolute normalized dot product.
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

function M.resolve(base, spec, rotation_components)
	if type(base) ~= "table" or not triplet(base.position)
			or type(spec) ~= "table" or not triplet(spec.scale)
			or not triplet(spec.offset) or not triplet(spec.rotation)
			or type(spec.node) ~= "number"
			or type(rotation_components) ~= "table" then return nil end
	return {
		apply_spec = {
			node = spec.node,
			scale = copy_triplet(spec.scale),
			position = {
				base.position[1] + spec.offset[1],
				base.position[2] + spec.offset[2],
				base.position[3] + spec.offset[3],
			},
			rotation = copy_triplet(spec.rotation),
		},
		position = {
			base.position[1] + spec.offset[1],
			base.position[2] + spec.offset[2],
			base.position[3] + spec.offset[3],
		},
		scale = copy_triplet(spec.scale),
		rotation = { rotation_components[1], rotation_components[2],
			rotation_components[3], rotation_components[4] },
		node = spec.node,
	}
end

function M.matches(snapshot, target)
	return type(snapshot) == "table" and type(target) == "table"
		and triplet_close(snapshot.position, target.position)
		and triplet_close(snapshot.scale, target.scale)
		and rotation_close(snapshot.rotation, target.rotation)
end

function M.new(api)
	api = api or {}
	local records = setmetatable({}, { __mode = "k" })
	local owner = {}

	local function alive(unit)
		return unit ~= nil and type(api.alive) == "function" and api.alive(unit) == true
	end

	local function read(unit, node)
		if not alive(unit) or type(api.read) ~= "function" then return nil end
		return api.read(unit, node)
	end

	local function emit(kind, record, before, after)
		if type(api.diagnostic) == "function" then
			api.diagnostic(kind, record, before, after)
		end
	end

	function owner:apply(unit, spec, perspective, surface)
		local node = type(spec) == "table" and spec.node or nil
		if type(node) ~= "number" then return false end
		local base = read(unit, node)
		if not base or type(api.rotation_components) ~= "function"
				or type(api.apply) ~= "function" then return false end
		local expected_rotation = api.rotation_components(spec and spec.rotation)
		local target = M.resolve(base, spec, expected_rotation)
		if not target then return false end
		local record = {
			node = node,
			perspective = perspective,
			surface = surface,
			base = base,
			target = target,
		}
		local wrote, write_report = api.apply(unit, target.apply_spec)
		wrote = wrote == true
		record.write_report = write_report
		local after = read(unit, node)
		local retained = wrote and M.matches(after, target)
		emit(retained and "initial-retained" or "initial-miss", record, base, after)
		if type(api.should_track) == "function" and api.should_track(surface) then
			records[unit] = record
		end
		return retained
	end

	function owner:step()
		local applied, tracked = 0, 0
		for unit, record in pairs(records) do
			if not alive(unit) then
				records[unit] = nil
			else
				tracked = tracked + 1
				local yielded = type(api.should_yield) == "function"
					and api.should_yield(record) == true
				if not yielded then
					local before = read(unit, record.node)
					local retained = M.matches(before, record.target)
					if not retained then
						local wrote, write_report = api.apply(unit, record.target.apply_spec)
						wrote = wrote == true
						record.write_report = write_report
						local after = read(unit, record.node)
						if wrote then applied = applied + 1 end
						if not record.drift_proof_logged then
							record.drift_proof_logged = true
							emit(M.matches(after, record.target)
								and "drift-repaired" or "drift-unrepaired",
								record, before, after)
						end
					elseif not record.retention_proof_logged then
						record.retention_proof_logged = true
						emit("next-frame-retained", record, before, before)
					end
				end
			end
		end
		return applied, tracked
	end

	function owner:clear()
		for unit in pairs(records) do records[unit] = nil end
	end

	-- Live pose retune (issue 712 tuner): rebuild every tracked record's target
	-- from its STORED baseline - never a fresh read, which would compound the
	-- offset - then apply immediately and re-arm the proof lines so the next
	-- log documents the new pose. `values` carries scale/offset/rotation.
	function owner:retarget(values)
		if type(values) ~= "table"
				or type(api.rotation_components) ~= "function"
				or type(api.apply) ~= "function" then return 0, 0 end
		local expected_rotation = api.rotation_components(values.rotation)
		if not expected_rotation then return 0, 0 end
		local retargeted, live = 0, 0
		for unit, record in pairs(records) do
			if not alive(unit) then
				records[unit] = nil
			else
				live = live + 1
				local spec = {
					node = record.node,
					scale = (record.perspective == "1p" and values.scale_1p)
						or values.scale,
					offset = values.offset,
					rotation = values.rotation,
				}
				local target = M.resolve(record.base, spec, expected_rotation)
				if target then
					record.target = target
					record.drift_proof_logged = nil
					record.retention_proof_logged = nil
					local wrote, write_report = api.apply(unit, target.apply_spec)
					record.write_report = write_report
					local after = read(unit, record.node)
					if wrote == true and M.matches(after, target) then
						retargeted = retargeted + 1
					end
					emit("retargeted", record, record.base, after)
				end
			end
		end
		return retargeted, live
	end

	function owner:count()
		local count = 0
		for _ in pairs(records) do count = count + 1 end
		return count
	end

	return owner
end

return M
