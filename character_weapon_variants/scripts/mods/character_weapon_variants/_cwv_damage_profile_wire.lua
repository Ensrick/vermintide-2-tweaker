-- Issue #423 / #371: pure sender-side policy for damage-profile wire safety.
--
-- `rpc_attack_hit` carries a numeric NetworkLookup.damage_profiles id from a
-- client to the host.  A `cwv_*` id is meaningful only to a compatible CWV
-- host.  Mixed or unknown parity must therefore substitute a boot-stable
-- vanilla id, or suppress the hit if no such id can be proven.  This module is
-- engine-free so the fail-closed contract can run in the offline Lua suite.

local M = {}

M.VANILLA_FALLBACK_NAME = "default"

local function _is_cwv_name(name)
	return type(name) == "string" and name:sub(1, 4) == "cwv_"
end

local function _verified_vanilla_id(lookup, name)
	if type(lookup) ~= "table" or type(name) ~= "string" or _is_cwv_name(name) then
		return nil
	end
	local id = rawget(lookup, name)
	if type(id) ~= "number" then return nil end
	local reverse = rawget(lookup, id)
	if reverse ~= name or _is_cwv_name(reverse) then return nil end
	return id
end

-- Returns `(wire_id, disposition)`.
--
-- disposition is one of:
--   vanilla   - input was not a CWV profile and passes through unchanged
--   source    - CWV profile substituted with its recorded vanilla donor
--   fallback  - untracked/broken donor substituted with vanilla `default`
--   drop      - input was CWV, but no vanilla id could be proven
function M.resolve_unconfirmed(lookup, source_by_name, id)
	if type(lookup) ~= "table" then return nil, "drop" end
	local name = rawget(lookup, id)
	if not _is_cwv_name(name) then return id, "vanilla" end

	local source_name = type(source_by_name) == "table" and source_by_name[name] or nil
	local source_id = _verified_vanilla_id(lookup, source_name)
	if source_id then return source_id, "source" end

	local fallback_id = _verified_vanilla_id(lookup, M.VANILLA_FALLBACK_NAME)
	if fallback_id then return fallback_id, "fallback" end

	-- Never return the original custom id here.  Suppressing one hit is a safe
	-- degraded behavior; transmitting an unresolvable id can terminate the host.
	return nil, "drop"
end

-- Returns `(wire_id, disposition)`.  The server path is in-process and positive
-- parity preserves the authored CWV balance.  Only a client with unknown or
-- negative parity enters the substitution policy above.
function M.for_send(is_server, parity_confirmed, lookup, source_by_name, id)
	if is_server then return id, "server" end
	if parity_confirmed then return id, "parity" end
	return M.resolve_unconfirmed(lookup, source_by_name, id)
end

-- ---------------------------------------------------------------------------
-- Exact catalog (#423 / BUG_CLASSES 64)
-- ---------------------------------------------------------------------------
-- Same-mod presence is not proof of identical numeric ids: a second
-- profile-appending mod, or a different CWV build, shifts our indices while the
-- beacon still reports a full lobby.  The snapshot below pins both directions
-- of every cwv_* row AND its vanilla donor, and `generation` catches a producer
-- that records a new mapping after finalization.

local function _positive_integer(value)
	return type(value) == "number" and value > 0 and math.floor(value) == value
end

function M.capture(Catalog, lookup, source_by_name, generation)
	if type(Catalog) ~= "table" or type(Catalog.build_identity) ~= "function" then
		return nil, "wire-catalog-library-missing"
	end
	if type(lookup) ~= "table" or type(source_by_name) ~= "table" then
		return nil, "lookup-or-source-map-missing"
	end
	local entries, names = { [M.VANILLA_FALLBACK_NAME] = true }, {}
	for id, name in pairs(lookup) do
		if _positive_integer(id) and _is_cwv_name(name) then
			local donor = rawget(source_by_name, name)
			if type(donor) ~= "string" or _is_cwv_name(donor) then
				return nil, "unmapped-custom-profile:" .. tostring(name)
			end
			entries[name], names[#names + 1] = donor, name
		end
	end
	table.sort(names)
	local identity, err = Catalog.build_identity(
		"cwv.damage_profiles", entries, lookup)
	if not identity then return nil, err end
	local snapshot = {
		identity = identity,
		lookup = lookup,
		generation = generation,
		default_id = rawget(lookup, M.VANILLA_FALLBACK_NAME),
		rows = {},
		owned_by_id = {},
	}
	for i = 1, #names do
		local name, donor = names[i], entries[names[i]]
		local row = {
			name = name, id = rawget(lookup, name),
			donor = donor, donor_id = rawget(lookup, donor),
		}
		snapshot.rows[i] = row
		snapshot.owned_by_id[row.id] = row
	end
	return snapshot
end

function M.catalog_intact(snapshot, generation)
	if type(snapshot) ~= "table" or type(snapshot.lookup) ~= "table"
			or type(snapshot.rows) ~= "table" or snapshot.generation ~= generation then
		return false
	end
	local lookup = snapshot.lookup
	if not _positive_integer(snapshot.default_id)
			or rawget(lookup, M.VANILLA_FALLBACK_NAME) ~= snapshot.default_id
			or rawget(lookup, snapshot.default_id) ~= M.VANILLA_FALLBACK_NAME then
		return false
	end
	for i = 1, #snapshot.rows do
		local row = snapshot.rows[i]
		if rawget(lookup, row.name) ~= row.id or rawget(lookup, row.id) ~= row.name
				or rawget(lookup, row.donor) ~= row.donor_id
				or rawget(lookup, row.donor_id) ~= row.donor then
			return false
		end
	end
	return true
end

-- Exact sender state machine.  Lookup corruption and predicate errors arrive
-- here as exact_safe=false; this function never emits an unproven custom id.
function M.profile_id_for_send(is_server, id, exact_safe, snapshot, generation)
	if is_server then return id, "server" end
	if type(snapshot) ~= "table" or type(snapshot.lookup) ~= "table"
			or not _positive_integer(id) then return nil, "drop" end
	local lookup, name = snapshot.lookup, rawget(snapshot.lookup, id)
	if type(name) ~= "string" or rawget(lookup, name) ~= id then return nil, "drop" end
	if not _is_cwv_name(name) then return id, "vanilla" end
	local row = snapshot.owned_by_id and rawget(snapshot.owned_by_id, id)
	if exact_safe == true and row and M.catalog_intact(snapshot, generation) then
		return id, "exact"
	end
	if row and _verified_vanilla_id(lookup, row.donor) == row.donor_id then
		return row.donor_id, "source"
	end
	if _verified_vanilla_id(lookup, M.VANILLA_FALLBACK_NAME) == snapshot.default_id then
		return snapshot.default_id, "fallback"
	end
	return nil, "drop"
end

return M
