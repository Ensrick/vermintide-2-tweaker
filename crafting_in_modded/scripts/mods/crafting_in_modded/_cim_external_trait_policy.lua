-- Pure policy for traits whose implementation is owned by another mod.
--
-- A CIM save may outlive its provider mod. Keep the selected trait parked in
-- persistence while the provider is absent, but never put the unresolved key
-- on the live backend item. The provider can reactivate it after all mods load.

local M = {}

M.RESERVED_PROVIDER_BY_TRAIT = {
	woc_poisoned_edge = "WOC",
}
M.REQUIRED_CAPABILITY_BY_PROVIDER = {
	WOC = "woc.poison_trait.v1",
}

local function append_unique(out, seen, value)
	if type(value) == "string" and value ~= "" and not seen[value] then
		seen[value] = true
		out[#out + 1] = value
	end
end

function M.merge_traits(active, parked)
	local out, seen = {}, {}
	for _, value in ipairs(type(active) == "table" and active or {}) do
		append_unique(out, seen, value)
	end
	for _, value in ipairs(type(parked) == "table" and parked or {}) do
		append_unique(out, seen, value)
	end
	return out
end

function M.partition(traits, available_providers)
	local active, parked = {}, {}
	local seen_active, seen_parked = {}, {}
	for _, trait_key in ipairs(type(traits) == "table" and traits or {}) do
		local provider = M.RESERVED_PROVIDER_BY_TRAIT[trait_key]
		if provider and not (available_providers and available_providers[provider] == true) then
			append_unique(parked, seen_parked, trait_key)
		else
			append_unique(active, seen_active, trait_key)
		end
	end
	return active, parked
end

function M.add_combination(combinations, category, trait_key)
	local pool = type(combinations) == "table" and combinations[category]
	if type(pool) ~= "table" or type(trait_key) ~= "string" then
		return false, "pool_unavailable"
	end
	for _, combination in ipairs(pool) do
		if type(combination) == "table" then
			for _, existing in ipairs(combination) do
				if existing == trait_key then return true, "existing" end
			end
		end
	end
	pool[#pool + 1] = { trait_key }
	return true, "installed"
end

return M
