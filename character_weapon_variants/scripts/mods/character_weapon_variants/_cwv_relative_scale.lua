-- Engine-free baseline-relative scale owner.
--
-- Some weapon attachment paths author a non-unit root scale before CWV sees the
-- spawned unit.  Treating a user tune such as "half its current size" as an
-- absolute {0.5, 0.5, 0.5} overwrites that authored baseline and can enlarge
-- the model.  This owner captures the first settled scale per spawned unit and
-- returns an absolute target, keeping durable replays idempotent.
local M = {}

local function triplet(value)
	return type(value) == "table"
		and type(value[1]) == "number"
		and type(value[2]) == "number"
		and type(value[3]) == "number"
end

function M.new(deps)
	deps = deps or {}
	local baselines = setmetatable({}, { __mode = "k" })
	local owner = {}

	function owner:resolve(unit, multiplier, identity_token)
		if unit == nil or not triplet(multiplier) then return nil, nil end
		local record = baselines[unit]
		if record and record.identity_token ~= identity_token then
			record = nil
			baselines[unit] = nil
		end
		if not record then
			if type(deps.read_scale) ~= "function" then return nil, nil end
			local read = deps.read_scale(unit)
			if not triplet(read) then return nil, nil end
			record = {
				baseline = { read[1], read[2], read[3] },
				identity_token = identity_token,
			}
			baselines[unit] = record
		end
		local baseline = record.baseline
		return {
			baseline[1] * multiplier[1],
			baseline[2] * multiplier[2],
			baseline[3] * multiplier[3],
		}, baseline
	end

	function owner:baseline(unit)
		local record = baselines[unit]
		return record and record.baseline or nil
	end

	function owner:forget(unit)
		baselines[unit] = nil
	end

	return owner
end

return M
