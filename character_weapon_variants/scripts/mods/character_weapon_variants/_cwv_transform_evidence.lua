-- Engine-free bounded evidence owner for Crowbill transform lifecycle checks.
--
-- This intentionally accepts only exact Crowbill model identities. General CWV
-- husk diagnostics have their own budget, so unrelated weapons cannot silence
-- issue #604 evidence before a co-op reproduction reaches the custom model.
local M = {}

local function token(value)
	return tostring(value == nil and "nil" or value)
end

function M.new(deps)
	deps = deps or {}
	local total_limit = deps.total_limit or 96
	local per_model_limit = deps.per_model_limit or 16
	local total = 0
	local per_model = {}
	local seen = {}
	local owner = {}

	function owner:observe(row)
		if type(row) ~= "table" or type(row.model_key) ~= "string"
				or row.model_key == "" then return false, "not_crowbill" end
		local model_count = per_model[row.model_key] or 0
		if total >= total_limit then return false, "total_limit" end
		if model_count >= per_model_limit then return false, "model_limit" end
		local key = table.concat({
			token(row.phase), token(row.surface), token(row.unit_id),
			token(row.model_key), token(row.unit_name), token(row.generation),
			token(row.fingerprint),
		}, "|")
		if seen[key] then return false, "duplicate" end
		seen[key] = true
		total = total + 1
		model_count = model_count + 1
		per_model[row.model_key] = model_count
		row.index = total
		row.total_limit = total_limit
		row.model_index = model_count
		row.per_model_limit = per_model_limit
		if type(deps.emit) == "function" then pcall(deps.emit, row) end
		return true
	end

	function owner:stats()
		local counts = {}
		for key, value in pairs(per_model) do counts[key] = value end
		return {
			count = total,
			limit = total_limit,
			per_model_limit = per_model_limit,
			per_model = counts,
		}
	end

	return owner
end

return M
