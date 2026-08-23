-- Canonical bidirectional NetworkLookup registration primitive (issue #428).
--
-- Stingray lookup tables are dense arrays in the numeric direction and strict
-- maps in the string direction. Every registration must preserve both halves
-- of that relation. Use rawget/rawset because the engine installs throwing
-- __index behavior on several lookup tables.
local M = {}

local function valid_name(name)
	return type(name) == "string" and name ~= ""
end

-- Returns index, inserted, reason.
-- Existing symmetric entries are idempotent. Any half-pair or occupied append
-- slot fails closed instead of guessing or silently changing a network index.
function M.register(lookup, name)
	if type(lookup) ~= "table" then
		return nil, false, "lookup_missing"
	end
	if not valid_name(name) then
		return nil, false, "name_invalid"
	end

	local existing = rawget(lookup, name)
	if existing ~= nil then
		if type(existing) ~= "number" then
			return nil, false, "reverse_not_numeric"
		end
		if rawget(lookup, existing) ~= name then
			return nil, false, "pair_asymmetric"
		end
		return existing, false, "already_registered"
	end

	local index = #lookup + 1
	if rawget(lookup, index) ~= nil then
		return nil, false, "append_slot_occupied"
	end

	rawset(lookup, index, name)
	rawset(lookup, name, index)
	return index, true, "registered"
end

function M.register_named(network_lookup, table_name, name)
	if type(network_lookup) ~= "table" or not valid_name(table_name) then
		return nil, false, "network_lookup_missing"
	end
	return M.register(rawget(network_lookup, table_name), name)
end

return M
