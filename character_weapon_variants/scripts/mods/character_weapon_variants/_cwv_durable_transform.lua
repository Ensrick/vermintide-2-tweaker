-- Engine-free durable transform registry for weapon units whose attachment
-- owner rewrites the unit root after spawn. The registry owns no identity,
-- transform math, networking, or engine hooks; callers provide those seams.
local M = {}

function M.new(deps)
	deps = deps or {}
	local records = setmetatable({}, { __mode = "k" })
	local owner = {}

	local function alive(unit)
		return type(deps.alive) ~= "function" or deps.alive(unit) == true
	end

	function owner:track(unit, spec)
		if unit == nil or type(spec) ~= "table" or not alive(unit) then return false end
		records[unit] = spec
		return true
	end

	function owner:forget(unit)
		records[unit] = nil
	end

	function owner:step()
		local applied, tracked = 0, 0
		for unit, spec in pairs(records) do
			if alive(unit) then
				tracked = tracked + 1
				if type(deps.apply) == "function" and deps.apply(unit, spec) == true then
					applied = applied + 1
				end
			else
				records[unit] = nil
			end
		end
		if type(deps.after_all) == "function" then deps.after_all(applied, tracked) end
		return applied, tracked
	end

	function owner:count()
		local count = 0
		for unit in pairs(records) do
			if alive(unit) then count = count + 1 else records[unit] = nil end
		end
		return count
	end

	return owner
end

return M
