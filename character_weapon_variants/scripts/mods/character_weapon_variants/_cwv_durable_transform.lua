-- Engine-free durable transform registry for weapon units whose attachment
-- owner rewrites the unit root after spawn. The registry owns no identity,
-- transform math, networking, or engine hooks; callers provide those seams.
local M = {}

function M.new(deps)
	deps = deps or {}
	local records = setmetatable({}, { __mode = "k" })
	local owner = {}
	local next_generation = 0

	local function alive(unit)
		return type(deps.alive) ~= "function" or deps.alive(unit) == true
	end

	local function cleanup(unit, spec, reason)
		if type(deps.on_forget) == "function" then
			pcall(deps.on_forget, unit, spec, reason)
		end
	end

	local function identity_token(spec)
		if spec.identity_token ~= nil then return tostring(spec.identity_token) end
		return table.concat({
			tostring(spec.model_key), tostring(spec.unit_name), tostring(spec.surface),
			tostring(spec.perspective), tostring(spec.hand),
		}, "|")
	end

	function owner:track(unit, spec)
		if unit == nil or type(spec) ~= "table" or not alive(unit) then return false end
		local token = identity_token(spec)
		local previous = records[unit]
		if previous and previous.identity_token ~= token then
			cleanup(unit, previous, "identity_changed")
			previous = nil
		end
		if previous then
			spec.generation = previous.generation
			spec.steps = previous.steps or 0
		else
			next_generation = next_generation + 1
			spec.generation = next_generation
			spec.steps = 0
		end
		spec.identity_token = token
		records[unit] = spec
		return true, spec.generation, previous == nil
	end

	function owner:annotate(unit, fields)
		local spec = records[unit]
		if not spec or type(fields) ~= "table" then return false end
		for key, value in pairs(fields) do spec[key] = value end
		return true
	end

	function owner:record(unit)
		return records[unit]
	end

	function owner:forget(unit, reason)
		local spec = records[unit]
		if spec then cleanup(unit, spec, reason or "explicit") end
		records[unit] = nil
	end

	function owner:step()
		local applied, tracked = 0, 0
		for unit, spec in pairs(records) do
			if alive(unit) then
				tracked = tracked + 1
				spec.steps = (spec.steps or 0) + 1
				if spec.steps == 1 and type(deps.before_apply) == "function" then
					pcall(deps.before_apply, unit, spec)
				end
				if type(deps.apply) == "function" and deps.apply(unit, spec) == true then
					applied = applied + 1
				end
			else
				cleanup(unit, spec, "dead")
				records[unit] = nil
			end
		end
		if type(deps.after_all) == "function" then deps.after_all(applied, tracked) end
		if type(deps.after_final) == "function" then
			for unit, spec in pairs(records) do
				if alive(unit) and spec.steps == 1 then pcall(deps.after_final, unit, spec) end
			end
		end
		return applied, tracked
	end

	function owner:count()
		local count = 0
		for unit in pairs(records) do
			if alive(unit) then
				count = count + 1
			else
				cleanup(unit, records[unit], "dead")
				records[unit] = nil
			end
		end
		return count
	end

	return owner
end

return M
