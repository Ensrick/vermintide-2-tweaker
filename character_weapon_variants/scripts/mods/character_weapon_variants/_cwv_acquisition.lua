-- Pure ownership helpers for CWV's bounded Blacksmith-instance contract.
-- Kept engine-free so acquisition and migration predicates are host-testable
-- under Lua 5.1.
local M = {}

function M.is_seed_eligible(definition)
	return type(definition) == "table"
		and not definition.skin_only
		and not definition.cwv_retired
		and type(definition.item_key) == "string"
		and definition.item_key ~= ""
end

-- Prefer the historical _001 identity so every existing _NNN resolver keeps
-- working. If an old CIM craft legitimately owns that exact id, preserve it
-- and use _000 for the one provider-owned Blacksmith seed instead.
function M.blacksmith_seed_id(definition, is_cim_owned)
	if not M.is_seed_eligible(definition) then return nil end
	local primary = definition.item_key .. "_001"
	local fallback = definition.item_key .. "_000"
	local function owned(backend_id)
		if type(is_cim_owned) ~= "function" then return false end
		local ok, result = pcall(is_cim_owned, backend_id)
		if not ok or result == nil then return nil end
		return result == true
	end
	local primary_owned = owned(primary)
	-- An unreadable ownership ledger is not evidence that an identity is free.
	-- Fail closed rather than risking replacement of a persisted CIM craft.
	if primary_owned == nil then return nil end
	if primary_owned then
		-- Missing one provider seed is recoverable; replacing player state is not.
		local fallback_owned = owned(fallback)
		if fallback_owned == nil or fallback_owned then return nil end
		return fallback
	end
	return primary
end

function M.owner_probe(...)
	local owners = { ... }
	local owner_count = select("#", ...)
	return function(backend_id)
		local indeterminate = false
		-- #592: stable CIM occupies slot two when CIM Dev is absent. This is
		-- a nullable argument tuple, not a dense array; every supplied slot counts.
		for index = 1, owner_count do
			local owner = owners[index]
			if owner ~= nil then
				-- A loaded owner without its reader is not an absent consumer.
				-- Protect lookup too: mod proxies can throw through __index.
				local readable, getter = pcall(function() return owner._cim_get_craft end)
				if not readable or type(getter) ~= "function" then
					indeterminate = true
				else
					local ok, craft = pcall(getter, backend_id)
					if ok and craft ~= nil then return true end
					if not ok then indeterminate = true end
				end
			end
		end
		if indeterminate then return nil end
		return false
	end
end

function M.legacy_auto_grant_ids(definitions)
	local ids = {}
	for _, def in ipairs(definitions or {}) do
		if type(def) == "table" and not def.skin_only and type(def.item_key) == "string" then
			-- The collision fallback is part of the finite migration ledger so a
			-- later return to `_001` cannot leave two provider seeds behind.
			ids[def.item_key .. "_000"] = true
			for i = 1, (tonumber(def.instances) or 1) do
				ids[string.format("%s_%03d", def.item_key, i)] = true
			end
		end
	end
	return ids
end

function M.should_remove(backend_id, legacy_ids, is_cim_owned, protected_ids)
	if type(backend_id) ~= "string" or not (legacy_ids and legacy_ids[backend_id]) then
		return false
	end
	if protected_ids and protected_ids[backend_id] then
		return false
	end
	-- Exact CIM persistence always wins, even if an old/manual craft happened to
	-- reuse a historical CWV id. Never infer ownership from a cwv_ prefix.
	if type(is_cim_owned) == "function" then
		local ok, owned = pcall(is_cim_owned, backend_id)
		-- Registration proof can become stale before cleanup. Only explicit
		-- unowned evidence authorizes deletion; nil/error is not permission.
		if not ok or owned ~= false then return false end
	end
	return true
end

function M.build_seed(definition, build_entry, clone_definition, is_cim_owned)
	if type(build_entry) ~= "function" or type(clone_definition) ~= "function" then
		return nil, nil, "builder unavailable"
	end
	local seed_id = M.blacksmith_seed_id(definition, is_cim_owned)
	if not seed_id then return nil, nil, "no collision-safe identity" end
	local seed_definition = clone_definition(definition)
	if type(seed_definition) ~= "table" then
		return nil, seed_id, "clone failed"
	end
	seed_definition.power_level = 5
	seed_definition.rarity = "default"
	seed_definition.traits = {}
	seed_definition.properties = {}
	seed_definition.no_skin = true
	local entry = build_entry(seed_definition, seed_id)
	if not entry then return nil, seed_id, "entry build failed" end
	return entry, seed_id
end

local function canonicalize_seed(item)
	if type(item) ~= "table" then return false end
	if item.CustomData ~= nil and type(item.CustomData) ~= "table" then
		return false
	end
	item.rarity = "default"
	item.power_level = 5
	item.traits = {}
	item.properties = {}
	item.skin = nil
	item.CustomData = item.CustomData or {}
	item.CustomData.rarity = "default"
	item.CustomData.power_level = "5"
	item.CustomData.traits = "[]"
	item.CustomData.properties = "{}"
	item.CustomData.skin = nil
	return true
end

-- Register one bounded seed per provider definition, then canonicalize the live
-- backend objects because MIL deliberately stamps its own Modded rarity. The
-- injected functions keep this policy engine-free and directly testable.
function M.register_seeds(seed_entries, expected_count, add_items, get_item)
	local report = {
		ok = false,
		attempted = #(seed_entries or {}),
		canonicalized = 0,
		failed = 0,
	}
	if report.attempted ~= (tonumber(expected_count) or -1) then
		report.failed = math.abs(report.attempted - (tonumber(expected_count) or 0))
		report.error = "seed/definition count mismatch"
		return report
	end
	if report.attempted == 0 then
		report.ok = expected_count == 0
		return report
	end
	if type(add_items) ~= "function" or type(get_item) ~= "function" then
		report.failed = report.attempted
		report.error = "backend acquisition interface unavailable"
		return report
	end
	local added, add_error = pcall(add_items, seed_entries)
	if not added then
		report.failed = report.attempted
		report.error = tostring(add_error)
		return report
	end
	for _, seed_entry in ipairs(seed_entries) do
		local seed_id = seed_entry.mod_data and seed_entry.mod_data.backend_id
		local fetched, item = pcall(get_item, seed_id)
		local canonicalized = false
		if fetched and seed_id and type(item) == "table" then
			local ok, result = pcall(canonicalize_seed, item)
			canonicalized = ok and result == true
		end
		if canonicalized then
			report.canonicalized = report.canonicalized + 1
		else
			report.failed = report.failed + 1
		end
	end
	report.ok = report.failed == 0 and report.canonicalized == report.attempted
	if not report.ok and not report.error then
		report.error = "one or more live seeds were unavailable"
	end
	return report
end

function M.register_seed_interfaces(seed_entries, expected_count, mil, backend_items, owner_name)
	return M.register_seeds(seed_entries, expected_count,
		mil and type(mil.add_mod_items_to_local_backend) == "function"
			and function(rows) return mil:add_mod_items_to_local_backend(rows, owner_name) end
			or nil,
		backend_items and type(backend_items.get_item_from_id) == "function"
			and function(seed_id) return backend_items:get_item_from_id(seed_id) end
			or nil)
end

function M.plan_removals(definitions, extra_legacy_ids, is_cim_owned, protected_ids)
	local legacy_ids = M.legacy_auto_grant_ids(definitions)
	for backend_id in pairs(extra_legacy_ids or {}) do legacy_ids[backend_id] = true end
	local removals = {}
	for backend_id in pairs(legacy_ids) do
		if M.should_remove(backend_id, legacy_ids, is_cim_owned, protected_ids) then
			removals[#removals + 1] = backend_id
		end
	end
	table.sort(removals)
	return removals
end

return M
