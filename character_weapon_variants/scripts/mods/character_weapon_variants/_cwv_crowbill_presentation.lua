-- Engine-free presentation owner for Crowbill pick/hammer mode.
--
-- The hammer face is selected by composing one exact 180-degree turn around
-- the model's LOCAL haft axis with the authored/base rotation.  Callers must
-- never derive the next pose from the unit's already-flipped rotation.
local M = {}

M.MODE_PICK = "pick"
M.MODE_HAMMER = "hammer"
M.FLIP_AXIS = { 0, 0, 1 }
M.FLIP_DEGREES = 180

M.SURFACES = {
	owner_1p = true,
	owner_3p = true,
	bot = true,
	remote_husk = true,
	inventory_preview = true,
	lobby_preview = true,
	score_preview = true,
	item_browser = true,
	customization_preview = true,
}

local function valid_mode(mode)
	return mode == M.MODE_PICK or mode == M.MODE_HAMMER
end

-- `multiply(base, local_delta)` is deliberate: the delta remains in model
-- local space after any authored grip correction.  This preserves scale and
-- position because this owner writes rotation only.
function M.compose_rotation(base_rotation, mode, ops)
	if not valid_mode(mode) then return nil, "invalid mode" end
	if type(ops) ~= "table" or type(ops.identity) ~= "function"
			or type(ops.axis_angle) ~= "function" or type(ops.multiply) ~= "function" then
		return nil, "rotation operations missing"
	end
	local base = base_rotation or ops.identity()
	if mode == M.MODE_PICK then return base end
	local delta = ops.axis_angle(M.FLIP_AXIS, M.FLIP_DEGREES)
	return ops.multiply(base, delta)
end

-- TeamPreviewer score rows retain exact peer/local/profile/career identity in
-- the immutable context snapshot even though hero_data drops peer_id. Bots
-- share their owner's peer, so only a player-controlled exact row may bridge.
function M.resolve_score_peer(profile_index, career_index, scores)
	if profile_index == nil or career_index == nil or type(scores) ~= "table" then
		return nil, "score_miss"
	end
	for _, row in pairs(scores) do
		if type(row) == "table" and row.profile_index == profile_index
				and row.career_index == career_index then
			if row.is_player_controlled == true and row.peer_id
					and row.local_player_id ~= nil then
				return row.peer_id, "score_snapshot"
			end
			return nil, row.is_player_controlled == false and "score_bot" or "score_untrusted"
		end
	end
	return nil, "score_miss"
end

function M.new(deps)
	deps = deps or {}
	local records = setmetatable({}, { __mode = "k" })
	local units_by_identity = {}
	local owner = {}

	local function alive(unit)
		return type(deps.alive) ~= "function" or deps.alive(unit) == true
	end

	local function bucket(identity)
		local value = units_by_identity[identity]
		if not value then
			value = setmetatable({}, { __mode = "k" })
			units_by_identity[identity] = value
		end
		return value
	end

	function owner:apply(unit, identity, surface, base_rotation, explicit_mode)
		if unit == nil or not alive(unit) then return false, "unit unavailable" end
		if type(identity) ~= "string" or identity == "" then return false, "identity missing" end
		if not M.SURFACES[surface] then return false, "unsupported surface" end
		local previous = records[unit]
		-- A second preview hook or lifecycle replay must use the originally
		-- captured base, never the unit's current (possibly hammer-flipped) pose.
		local stored_base = previous and previous.base_rotation or base_rotation
		if not previous and type(deps.retain_rotation) == "function" then
			stored_base = deps.retain_rotation(stored_base)
		end
		local base = type(deps.resolve_rotation) == "function"
			and deps.resolve_rotation(stored_base) or stored_base
		local mode = explicit_mode
			or (type(deps.mode_for) == "function" and deps.mode_for(identity))
			or M.MODE_PICK
		local rotation, err = M.compose_rotation(base, mode, deps.rotation_ops)
		if rotation == nil then return false, err end
		if type(deps.write_rotation) ~= "function"
				or deps.write_rotation(unit, rotation) ~= true then
			return false, "rotation write failed"
		end
		if previous and previous.identity ~= identity then
			local old = units_by_identity[previous.identity]
			if old then old[unit] = nil end
		end
		records[unit] = {
			identity = identity,
			surface = surface,
			base_rotation = stored_base,
		}
		bucket(identity)[unit] = true
		return true
	end

	-- Bounded transition replay: one pass over units already registered for
	-- this identity.  Spawn/wield/reconstruction paths call `apply` themselves;
	-- there is no update callback and no per-frame pose/RPC traffic.
	function owner:reapply(identity, explicit_mode)
		local units = units_by_identity[identity]
		if not units then return 0 end
		local applied = 0
		for unit in pairs(units) do
			local record = records[unit]
			if record and alive(unit) then
				local ok = self:apply(unit, identity, record.surface,
						record.base_rotation, explicit_mode)
				if ok then applied = applied + 1 end
			else
				units[unit] = nil
			end
		end
		return applied
	end

	function owner:forget(unit)
		local record = records[unit]
		if not record then return end
		local units = units_by_identity[record.identity]
		if units then units[unit] = nil end
		records[unit] = nil
	end

	return owner
end

return M
