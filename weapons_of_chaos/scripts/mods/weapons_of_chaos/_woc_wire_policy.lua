-- _woc_wire_policy.lua — sender-side item identity substitution for WOC items.
--
-- WOC backend items currently inherit a vanilla base key, while future items
-- may carry an explicit woc_ key. This pure policy preserves vanilla items by
-- identity, substitutes explicit WOC keys with a shallow vanilla-keyed shadow,
-- and fails closed when that base cannot be encoded.
--
-- Owned by: weapons_of_chaos.lua. Consumed via: mod:dofile and offline QA.

local M = {}

function M.is_woc_key(key)
	return type(key) == "string" and key:sub(1, 4) == "woc_"
end

function M.safe_item(item, base_key, base_resolvable)
	if not M.is_woc_key(item and item.key) then
		return item
	end
	if not base_resolvable or type(base_key) ~= "string" or base_key == "" then
		return nil
	end

	local shadow = {}
	for key, value in pairs(item) do shadow[key] = value end
	shadow.key = base_key
	shadow.ItemId = base_key
	return shadow
end

return M
