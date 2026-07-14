-- Pure ownership helpers for CWV's registration-only inventory contract.
-- Kept engine-free so the migration predicate is host-testable under Lua 5.1.
local M = {}

function M.legacy_auto_grant_ids(definitions)
	local ids = {}
	for _, def in ipairs(definitions or {}) do
		if type(def) == "table" and not def.skin_only and type(def.item_key) == "string" then
			for i = 1, (tonumber(def.instances) or 1) do
				ids[string.format("%s_%03d", def.item_key, i)] = true
			end
		end
	end
	return ids
end

function M.should_remove(backend_id, legacy_ids, is_cim_owned)
	if type(backend_id) ~= "string" or not (legacy_ids and legacy_ids[backend_id]) then
		return false
	end
	-- Exact CIM persistence always wins, even if an old/manual craft happened to
	-- reuse a historical CWV id. Never infer ownership from a cwv_ prefix.
	if type(is_cim_owned) == "function" and is_cim_owned(backend_id) == true then
		return false
	end
	return true
end

return M
