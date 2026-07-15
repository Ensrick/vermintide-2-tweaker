-- Canonical inventory policy for every Weapons of Chaos trophy weapon.
--
-- A WOC weapon is a unique relic, not a crafting definition.  Provider rows,
-- live backend rows, and cross-mod consumers all classify the same marker.
-- This module is engine-free so registration and reconciliation are covered
-- without launching the game.

local M = {}

M.MARKER = "woc_unique_relic"
M.RARITY = "promo"

local function identity(item)
	if type(item) ~= "table" then return nil end
	return item.backend_id or item.ItemInstanceId
end

function M.mark_definition(definition, backend_id)
	if type(definition) ~= "table" then return nil end
	definition.woc_variant = true
	definition[M.MARKER] = true
	definition.rarity = M.RARITY
	definition.skin_combination_table = nil
	definition.mod_data = definition.mod_data or {}
	definition.mod_data.backend_id = backend_id or definition.mod_data.backend_id
	definition.mod_data.ItemInstanceId = backend_id or definition.mod_data.ItemInstanceId
	definition.mod_data[M.MARKER] = true
	definition.mod_data.rarity = M.RARITY
	definition.mod_data.skin = nil
	definition.mod_data.CustomData = definition.mod_data.CustomData or {}
	definition.mod_data.CustomData.rarity = M.RARITY
	definition.mod_data.CustomData.skin = nil
	definition.mod_data.CustomData[M.MARKER] = "true"
	return definition
end

function M.is_definition(definition)
	return type(definition) == "table" and definition[M.MARKER] == true
end

function M.is_instance(item)
	if type(item) ~= "table" then return false end
	if item[M.MARKER] == true then return true end
	if type(item.data) == "table" and item.data[M.MARKER] == true then return true end
	local custom = item.CustomData
	return type(custom) == "table"
		and (custom[M.MARKER] == true or custom[M.MARKER] == "true")
end

-- MoreItemsLibrary deliberately overwrites every live mod item's rarity with
-- `default` after copying mod_data.  Enforce the relic contract on the actual
-- stored backend row after MIL registration; definition-only rarity is not
-- sufficient.
function M.enforce_instance(item, definition, backend_id)
	if type(item) ~= "table" or not M.is_definition(definition) then return false end
	item[M.MARKER] = true
	item.rarity = M.RARITY
	item.skin = nil
	item.CustomData = item.CustomData or {}
	item.CustomData.rarity = M.RARITY
	item.CustomData.skin = nil
	item.CustomData[M.MARKER] = "true"
	item.data = definition
	if backend_id then
		item.backend_id = backend_id
		item.ItemInstanceId = backend_id
	end
	return true
end

function M.registry_by_item_key(definitions)
	local registry = {}
	for _, definition in ipairs(definitions or {}) do
		if type(definition) == "table"
				and type(definition.item_key) == "string"
				and type(definition.backend_id) == "string" then
			registry[definition.item_key] = definition
		end
	end
	return registry
end

local function item_key(item, registry)
	if type(item) ~= "table" then return nil end
	local data = item.data
	if type(data) == "table" then
		for key in pairs(registry) do
			if data == registry[key].master or data[M.MARKER] == true
					and (data.woc_item_key == key or item.ItemId == key or item.key == key) then
				return key
			end
		end
	end
	local key = item.woc_item_key or item.ItemId or item.key
	return registry[key] and key or nil
end

-- Returns exact ids only.  The canonical deterministic backend id is never a
-- deletion candidate. Equipped/unknown duplicates are deferred fail-closed;
-- the runtime retries on later state transitions after loadouts are safe.
function M.plan_reconciliation(items, definitions, equip_state, ownership_state)
	local registry = M.registry_by_item_key(definitions)
	local report = { canonical = {}, removable = {}, deferred = {}, missing = {} }
	local seen_canonical = {}

	for backend_id, item in pairs(items or {}) do
		local key = item_key(item, registry)
		local definition = key and registry[key]
		if definition then
			local id = identity(item) or backend_id
			if id == definition.backend_id then
				seen_canonical[key] = true
				report.canonical[#report.canonical + 1] = id
			else
				local state
				if type(equip_state) == "function" then state = equip_state(id, item) end
				local owned
				if type(ownership_state) == "function" then
					owned = ownership_state(id, item)
				end
				-- Deletion requires two independent positive facts: CIM owns this
				-- exact record and no current/saved loadout equips it. Unknown
				-- provenance stays fail-closed even when the equip query succeeds.
				if state == false and owned == true then
					report.removable[#report.removable + 1] = id
				else
					report.deferred[#report.deferred + 1] = id
				end
			end
		end
	end

	for key, definition in pairs(registry) do
		if not seen_canonical[key] then report.missing[#report.missing + 1] = definition.backend_id end
	end
	table.sort(report.canonical)
	table.sort(report.removable)
	table.sort(report.deferred)
	table.sort(report.missing)
	return report
end

return M
