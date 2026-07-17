-- _woc_wire_policy.lua — sender-side item identity substitution for WOC items.
--
-- WOC backend items may inherit a vanilla base key locally, but their Cursed
-- rarity and display-only properties are also mod-owned values. This policy
-- preserves ordinary vanilla items by identity and emits a vanilla key + promo
-- rarity shadow with no WOC-only properties/traits for every marked WOC relic.
--
-- Owned by: weapons_of_chaos.lua. Consumed via: mod:dofile and offline QA.

local M = {}

function M.is_woc_key(key)
	return type(key) == "string" and key:sub(1, 4) == "woc_"
end

function M.is_woc_item(item)
	if type(item) ~= "table" then return false end
	if M.is_woc_key(item.key) or item.woc_unique_relic == true then return true end
	if type(item.data) == "table" and item.data.woc_unique_relic == true then return true end
	local custom = item.CustomData
	return type(custom) == "table"
		and (custom.woc_unique_relic == true or custom.woc_unique_relic == "true")
end

function M.safe_item(item, base_key, base_resolvable, wire_rarity)
	if not M.is_woc_item(item) then
		return item
	end
	if not base_resolvable or type(base_key) ~= "string" or base_key == "" then
		return nil
	end

	local shadow = {}
	for key, value in pairs(item) do shadow[key] = value end
	shadow.key = base_key
	shadow.ItemId = base_key
	shadow.rarity = wire_rarity or "promo"
	-- LoadoutUtils.properties_to_rpc_params indexes every entry through the
	-- receiver-local NetworkLookup.properties/traits tables. WOC relic bonuses
	-- are baked into the private combat template; their item rows are display
	-- only and have no safe vanilla wire identity. Strip them from this transient
	-- shadow rather than registering or transmitting mod-only lookup keys.
	shadow.properties = nil
	shadow.traits = nil
	return shadow
end

return M
