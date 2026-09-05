-- Pure ownership helpers for CWV's bounded Blacksmith-instance contract.
-- Kept engine-free so acquisition and migration predicates are host-testable
-- under Lua 5.1.
local M = {}

M.SEED_IDENTITY_SCHEMA = 2
M.SEED_IDENTITY_OWNER = "character_weapon_variants"
M.SEED_IDENTITY_CAPABILITY = "cwv.blacksmith-seed.identity.v2"

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
	return function(backend_id)
		local indeterminate = false
		for _, owner in ipairs(owners) do
			if owner and type(owner._cim_get_craft) == "function" then
				local ok, craft = pcall(owner._cim_get_craft, backend_id)
				if ok and craft ~= nil then return true end
				if not ok then indeterminate = true end
			end
		end
		if indeterminate then return nil end
		return false
	end
end

-- Issue #1141: a CWV Blacksmith seed is a provider-owned selector, not an
-- arbitrary member of the broad `cwv_<key>_NNN` instance namespace.  Temper
-- Craft may consume only the exact seed selected by the successful registration
-- transaction below (`_000` or `_001`), backed by a currently registered CWV
-- definition row.  Keeping this resolver in the acquisition owner prevents CIM
-- from independently guessing CWV identity from inherited vanilla donor keys.
-- PlayFab's live wrapper and MIL's retained definition expose overlapping
-- identity in several containers.  Visit every PRESENT representation: using
-- `top.CustomData or data.CustomData` lets a benign top row hide contradictory
-- nested evidence and turns the provider into an order-dependent parser.
local function _visit_item_rows(item, visit)
	if type(item) ~= "table" or type(visit) ~= "function" then return end
	local data = type(item.data) == "table" and item.data or nil
	local top_custom = type(item.CustomData) == "table" and item.CustomData or nil
	local data_custom = data and type(data.CustomData) == "table"
		and data.CustomData or nil
	local top_mod = type(item.mod_data) == "table" and item.mod_data or nil
	local data_mod = data and type(data.mod_data) == "table" and data.mod_data or nil
	visit(item, "item")
	if data then visit(data, "data") end
	if top_custom then visit(top_custom, "CustomData") end
	if data_custom then visit(data_custom, "data.CustomData") end
	if top_mod then visit(top_mod, "mod_data") end
	if data_mod then visit(data_mod, "data.mod_data") end
	if top_mod and type(top_mod.CustomData) == "table" then
		visit(top_mod.CustomData, "mod_data.CustomData")
	end
	if data_mod and type(data_mod.CustomData) == "table" then
		visit(data_mod.CustomData, "data.mod_data.CustomData")
	end
end

local function _empty_seed_value(value, field)
	if type(value) == "table" then return next(value) == nil end
	if type(value) ~= "string" then return false end
	local compact = value:gsub("%s", "")
	return field == "traits" and compact == "[]"
		or field == "properties" and compact == "{}"
end

local function _exact_seed_shape(row, custom)
	return type(row) == "table" and type(custom) == "table"
		and row.rarity == "default" and tonumber(row.power_level) == 5
		and _empty_seed_value(row.traits, "traits")
		and _empty_seed_value(row.properties, "properties")
		and custom.rarity == "default" and tonumber(custom.power_level) == 5
		and _empty_seed_value(custom.traits, "traits")
		and _empty_seed_value(custom.properties, "properties")
end

-- Seal only immutable scalar identity plus the exact definition object CWV
-- installed.  BackendInterfaceItemPlayfab deep-clones inventory rows while a
-- game-mode overlay is active, so live `item.data` table identity is not a
-- stable authority boundary.  ItemMasterList itself is not cloned; retaining
-- that private pointer rejects a later structurally similar replacement while
-- the scalar snapshot lets a legitimate deep-cloned seed be revalidated.
function M.protect_seed_identity(backend_id, item_key, seed_entry, master)
	if type(backend_id) ~= "string" or type(item_key) ~= "string"
			or type(seed_entry) ~= "table" or type(master) ~= "table" then
		return nil, "seed_identity_shape"
	end
	local seed_mod = type(seed_entry.mod_data) == "table"
		and seed_entry.mod_data or nil
	local seed_custom = seed_mod and type(seed_mod.CustomData) == "table"
		and seed_mod.CustomData or nil
	local donor_key = seed_entry.key
	local donor_name = seed_entry.name
	if type(donor_key) ~= "string" or donor_key == ""
			or donor_name ~= donor_key
			or seed_entry.cwv_variant ~= true
			or seed_entry.cwv_definition ~= false
			or seed_entry.cwv_key ~= item_key
			or not _exact_seed_shape(seed_mod, seed_custom)
			or seed_mod.backend_id ~= backend_id
			or seed_mod.ItemInstanceId ~= backend_id then
		return nil, "seed_identity_mismatch"
	end
	if master.cwv_variant ~= true or master.cwv_definition ~= true
			or master.cwv_key ~= item_key or master.mod_data ~= nil
			or master.key ~= donor_key or master.name ~= donor_name then
		return nil, "provider_row_mismatch"
	end
	return {
		backend_id = backend_id,
		item_key = item_key,
		donor_key = donor_key,
		donor_name = donor_name,
		registered_master = master,
		seed_ref = seed_entry,
	}, nil
end

function M.resolve_protected_seed(backend_id, item, registered_keys,
		protected_seed_ids, item_master_list)
	if type(backend_id) ~= "string" or backend_id == "" then
		return nil, "backend_id"
	end
	if type(item) ~= "table" then return nil, "item" end
	local item_key, suffix = backend_id:match("^(cwv_.-)_(%d%d%d)$")
	if not item_key or (suffix ~= "000" and suffix ~= "001") then
		return nil, "seed_band"
	end
	local protected = type(protected_seed_ids) == "table"
		and protected_seed_ids[backend_id] or nil
	if type(protected) ~= "table" or protected.item_key ~= item_key
			or protected.backend_id ~= backend_id
			or type(protected.registered_master) ~= "table"
			or type(protected.seed_ref) ~= "table" then
		return nil, "seed_not_protected"
	end
	local registered_master = type(registered_keys) == "table"
		and registered_keys[item_key] or nil
	if type(registered_master) ~= "table"
			or registered_master ~= protected.registered_master then
		return nil, "definition_not_registered"
	end
	local master = type(item_master_list) == "table"
		and rawget(item_master_list, item_key) or nil
	if master ~= registered_master then return nil, "provider_row_replaced" end
	if master.cwv_variant ~= true
			or master.cwv_definition ~= true or master.cwv_key ~= item_key
			or master.mod_data ~= nil
			or master.key ~= protected.donor_key
			or master.name ~= protected.donor_name then
		return nil, "provider_row_mismatch"
	end
	local seed_entry = type(item.data) == "table" and item.data or nil
	local seed_mod = seed_entry and type(seed_entry.mod_data) == "table"
		and seed_entry.mod_data or nil
	local seed_custom = seed_mod and type(seed_mod.CustomData) == "table"
		and seed_mod.CustomData or nil
	local live_custom = type(item.CustomData) == "table"
		and item.CustomData or nil
	if item.IsModItem ~= true
			or item.CreatedBy ~= M.SEED_IDENTITY_OWNER
			or item.data ~= protected.seed_ref
			or seed_entry.cwv_variant ~= true
			or seed_entry.cwv_definition ~= false
			or seed_entry.cwv_key ~= item_key
			or seed_entry.key ~= protected.donor_key
			or seed_entry.name ~= protected.donor_name
			or type(seed_mod) ~= "table"
			or seed_mod.backend_id ~= backend_id
			or seed_mod.ItemInstanceId ~= backend_id then
		return nil, "seed_provenance_mismatch"
	end
	if not _exact_seed_shape(item, live_custom)
			or not _exact_seed_shape(seed_mod, seed_custom) then
		return nil, "seed_required_shape_mismatch"
	end
	local donor_key = protected.donor_key
	if type(donor_key) ~= "string" or donor_key == ""
			or item.ItemId ~= donor_key or item.key ~= donor_key
			or item.name ~= nil and item.name ~= protected.donor_name then
		return nil, "seed_donor_mismatch"
	end

	-- When a live wrapper carries its own backend identity, it must agree with
	-- the selected row. Missing wrapper IDs are allowed: the UI supplies the
	-- authoritative selected backend id separately.
	local backend_seen, backend_conflict = false, false
	local stamp_seen, stamp_conflict = false, false
	local semantic_key_conflict = false
	local rarity_seen, rarity_conflict = false, false
	local power_seen, power_conflict = false, false
	local traits_seen, traits_conflict = false, false
	local properties_seen, properties_conflict = false, false
	local skin_conflict = false
	_visit_item_rows(item, function(row)
		for _, field in ipairs({ "backend_id", "ItemInstanceId" }) do
			local value = row[field]
			if value ~= nil then
				backend_seen = true
				if type(value) ~= "string" or value ~= backend_id then
					backend_conflict = true
				end
			end
		end
		for _, field in ipairs({ "ItemId", "key", "name" }) do
			local value = row[field]
			if value ~= nil and (type(value) ~= "string"
					or value ~= donor_key) then
				semantic_key_conflict = true
			end
		end
		for _, field in ipairs({
			"item_key", "cim_acquisition_key", "cwv_key",
		}) do
			local value = row[field]
			if value ~= nil then
				stamp_seen = true
				if type(value) ~= "string" or value ~= item_key then
					stamp_conflict = true
				end
			end
		end
		if row.rarity ~= nil then
			rarity_seen = true
			if row.rarity ~= "default" then rarity_conflict = true end
		end
		if row.power_level ~= nil then
			power_seen = true
			if tonumber(row.power_level) ~= 5 then power_conflict = true end
		end
		if row.traits ~= nil then
			traits_seen = true
			if not _empty_seed_value(row.traits, "traits") then
				traits_conflict = true
			end
		end
		if row.properties ~= nil then
			properties_seen = true
			if not _empty_seed_value(row.properties, "properties") then
				properties_conflict = true
			end
		end
		if row.skin ~= nil then skin_conflict = true end
	end)
	if backend_conflict then return nil, "backend_id_conflict" end
	if not backend_seen then return nil, "backend_id_missing" end
	if semantic_key_conflict then return nil, "semantic_key_conflict" end
	if stamp_conflict then return nil, "stamp_conflict" end
	if not stamp_seen then return nil, "provider_stamp_missing" end

	if not rarity_seen or rarity_conflict or not power_seen or power_conflict
			or not traits_seen or traits_conflict
			or not properties_seen or properties_conflict then
		return nil, "seed_shape_mismatch"
	end
	if skin_conflict then return nil, "seed_skin_mismatch" end
	local fingerprint = table.concat({
		"cwv-blacksmith-seed-v2", backend_id, item_key, donor_key,
	}, "|")
	return {
		schema = M.SEED_IDENTITY_SCHEMA,
		owner = M.SEED_IDENTITY_OWNER,
		capability = M.SEED_IDENTITY_CAPABILITY,
		backend_id = backend_id,
		item_key = item_key,
		donor_key = donor_key,
		fingerprint = fingerprint,
	}, nil
end

function M.new_seed_identity_provider(deps)
	assert(type(deps) == "table", "seed identity provider requires dependencies")
	local registered_keys = assert(deps.registered_keys,
		"seed identity provider requires registered keys")
	local get_protected_seed_ids = assert(deps.get_protected_seed_ids,
		"seed identity provider requires protected-seed accessor")
	local get_item_master_list = assert(deps.get_item_master_list,
		"seed identity provider requires ItemMasterList accessor")
	local get_backend_item = assert(deps.get_backend_item,
		"seed identity provider requires backend-item accessor")
	local provider = {
		schema = M.SEED_IDENTITY_SCHEMA,
		owner = M.SEED_IDENTITY_OWNER,
		capability = M.SEED_IDENTITY_CAPABILITY,
	}
	local function resolve_live(backend_id)
		local ids_ok, protected_seed_ids = pcall(get_protected_seed_ids)
		if not ids_ok or type(protected_seed_ids) ~= "table" then
			return nil, "protected_seed_ledger_unavailable", nil
		end
		local master_ok, item_master_list = pcall(get_item_master_list)
		if not master_ok or type(item_master_list) ~= "table" then
			return nil, "item_master_list_unavailable", nil
		end
		-- The provider proves its own live backend row.  Caller-supplied UI data
		-- is independently reconciled by CIM but can never manufacture authority.
		local fetched, item = pcall(get_backend_item, backend_id)
		if not fetched or type(item) ~= "table" then
			return nil, "protected_seed_backend_item_unavailable", nil
		end
		local proof, reason = M.resolve_protected_seed(
			backend_id, item, registered_keys,
			protected_seed_ids, item_master_list)
		return proof, reason
	end
	provider.resolve = function(_, backend_id)
		local proof, reason = resolve_live(backend_id)
		return proof, reason
	end
	provider.sample = function(_, required_item_key)
		local ids = {}
		local ok, protected_seed_ids = pcall(get_protected_seed_ids)
		if not ok or type(protected_seed_ids) ~= "table" then
			return nil, "protected_seed_ledger_unavailable"
		end
		for backend_id, protected in pairs(protected_seed_ids) do
			if type(protected) == "table"
					and type(protected.item_key) == "string"
					and protected.item_key ~= ""
					and (required_item_key == nil
						or protected.item_key == required_item_key) then
				ids[#ids + 1] = backend_id
			end
		end
		table.sort(ids)
		local backend_id = ids[1]
		if not backend_id then
			return nil, required_item_key and "protected_seed_key_unavailable"
				or "protected_seed_ledger_empty"
		end
		local item_key = protected_seed_ids[backend_id].item_key
		local proof, reason = resolve_live(backend_id)
		if type(proof) ~= "table" or proof.item_key ~= item_key then
			return nil,
				"protected_seed_sample_rejected:" .. tostring(reason)
		end
		return {
			backend_id = backend_id,
			item_key = item_key,
			proof = proof,
		}, nil
	end
	return provider
end

-- Publication is all-or-nothing: every staged identity must resolve through
-- the same private provider that will serve consumers.  A successful MIL add
-- or canonicalization alone is not proof that the live raw row still belongs
-- to the registered definition transaction.
function M.validate_seed_transaction(provider, protected_seed_ids)
	if type(provider) ~= "table" or type(provider.resolve) ~= "function"
			or type(protected_seed_ids) ~= "table" then
		return false, "provider_contract", 0
	end
	local ids = {}
	for backend_id in pairs(protected_seed_ids) do ids[#ids + 1] = backend_id end
	table.sort(ids)
	if #ids == 0 then return false, "protected_seed_ledger_empty", 0 end
	for index = 1, #ids do
		local backend_id = ids[index]
		local called, proof, reason = pcall(
			provider.resolve, provider, backend_id)
		local expected = protected_seed_ids[backend_id]
		if not called or type(proof) ~= "table"
				or proof.backend_id ~= backend_id
				or proof.item_key ~= expected.item_key
				or proof.donor_key ~= expected.donor_key then
			return false, tostring(called and reason or proof), index - 1
		end
	end
	return true, nil, #ids
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
	if type(is_cim_owned) == "function" and is_cim_owned(backend_id) == true then
		return false
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

function M.register_seed_interfaces(seed_entries, expected_count, mil,
		backend_items, backend_mirror, owner_name)
	local report = M.register_seeds(seed_entries, expected_count,
		mil and type(mil.add_mod_items_to_local_backend) == "function"
			and function(rows) return mil:add_mod_items_to_local_backend(rows, owner_name) end
			or nil,
		backend_mirror and type(backend_mirror.get_all_inventory_items) == "function"
			and function(seed_id)
				local items = backend_mirror:get_all_inventory_items()
				return type(items) == "table" and rawget(items, seed_id) or nil
			end
			or nil)
	if report.ok and backend_items and type(backend_items.make_dirty) == "function" then
		local dirtied = pcall(backend_items.make_dirty, backend_items)
		if not dirtied then
			report.ok, report.failed = false, report.attempted
			report.error = "backend presentation refresh unavailable"
		end
	end
	return report
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
