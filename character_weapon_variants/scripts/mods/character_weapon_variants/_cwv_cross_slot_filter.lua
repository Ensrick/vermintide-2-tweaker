-- Pure policy for the CWV melee-grid post-filter.
--
-- Career Tweaker can intentionally expose a combined `(melee or ranged)`
-- category in one equipment slot. That is not a melee-only grid and must not
-- be narrowed to CWV cross-slot weapons.
local M = {}

function M.kind(filter)
	if type(filter) ~= "string" then
		return "unrelated"
	end

	local has_melee = string.find(filter, "slot_type == melee", 1, true) ~= nil
	local has_ranged = string.find(filter, "slot_type == ranged", 1, true) ~= nil

	if has_melee and has_ranged then
		return "combined"
	elseif has_melee then
		return "melee_only"
	elseif has_ranged then
		return "ranged_only"
	end

	return "unrelated"
end

function M.should_narrow(filter, slot_name)
	local kind = M.kind(filter)
	return kind == "melee_only"
		or (kind == "combined" and slot_name == "slot_melee")
end

function M.apply(items, filter, slot_name, is_cross_slot_item)
	if type(items) ~= "table" or not M.should_narrow(filter, slot_name) then
		return items, 0, 0, {}
	end

	local filtered, kept, dropped, dropped_examples = {}, 0, 0, {}
	for _, item in ipairs(items) do
		local data = item.data or {}
		if data.slot_type ~= "ranged" or is_cross_slot_item(item) then
			filtered[#filtered + 1] = item
			kept = kept + 1
		else
			dropped = dropped + 1
			if #dropped_examples < 3 then
				dropped_examples[#dropped_examples + 1] = string.format(
					"{key=%s name=%s ItemId=%s bid=%s mod_bid=%s}",
					tostring(data.key),
					tostring(data.name),
					tostring(item.ItemId),
					tostring(item.backend_id),
					tostring(data.mod_data and data.mod_data.backend_id))
			end
		end
	end

	return filtered, kept, dropped, dropped_examples
end

return M
