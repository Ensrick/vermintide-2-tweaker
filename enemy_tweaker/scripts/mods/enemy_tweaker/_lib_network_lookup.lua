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

local function valid_index(index)
	return type(index) == "number"
		and index > 0
		and index == index
		and index ~= math.huge
		and index % 1 == 0
end

-- Validate the complete raw bidirectional table before trusting an existing
-- pair or choosing an append index. Lua's length operator is undefined for a
-- sparse array, so only a proven dense 1..N numeric side may be extended.
-- Returns the current maximum index, or nil plus a stable rejection reason.
local function validate_lookup(lookup)
	local numeric_count = 0
	local numeric_max = 0
	local numeric_key_invalid = false
	local lookup_key_invalid = false
	local pair_asymmetric = false

	for key, value in next, lookup do
		local key_type = type(key)
		if key_type == "number" then
			if not valid_index(key) then
				numeric_key_invalid = true
			else
				numeric_count = numeric_count + 1
				if key > numeric_max then
					numeric_max = key
				end
				if not valid_name(value) or rawget(lookup, value) ~= key then
					pair_asymmetric = true
				end
			end
		elseif key_type == "string" then
			if not valid_name(key)
				or not valid_index(value)
				or rawget(lookup, value) ~= key then
				pair_asymmetric = true
			end
		else
			lookup_key_invalid = true
		end
	end

	if numeric_key_invalid then
		return nil, "numeric_key_invalid"
	end
	if lookup_key_invalid then
		return nil, "lookup_key_invalid"
	end
	if numeric_count ~= numeric_max then
		return nil, "numeric_side_sparse"
	end
	if pair_asymmetric then
		return nil, "pair_asymmetric"
	end

	return numeric_max, nil
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
		if not valid_index(existing) then
			return nil, false, "reverse_index_invalid"
		end
		if rawget(lookup, existing) ~= name then
			return nil, false, "pair_asymmetric"
		end
	end

	local numeric_max, validation_reason = validate_lookup(lookup)
	if validation_reason then
		return nil, false, validation_reason
	end
	if existing ~= nil then
		return existing, false, "already_registered"
	end

	local index = numeric_max + 1
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
