-- _cwv_thrown_wire_policy.lua -- issue #424 / #371 (BUG_CLASSES 31, 64):
-- pure exact-catalog and disposition policy for CWV's thrown-resource axes.
--
-- WHY EXACT, NOT PRESENCE. The peer-parity beacon proves "every peer runs CWV".
-- It does NOT prove that the numeric NetworkLookup indices those peers appended
-- mean the same thing: a second lookup-appending mod, a different CWV build, or
-- a different registration order all shift the integers while the beacon still
-- reports a full lobby. Every id CWV puts on a vanilla RPC is therefore proven
-- against an exact catalog identity (tools/shared_lib/_lib_wire_catalog.lua)
-- that fingerprints each owned name, its bidirectional numeric id, and the
-- vanilla donor id the unconditional sender floor substitutes.
--
-- THE FIVE THROWN RESOURCES (all appended post-boot by the Tuskgor Javelin):
--   projectile_units : the cwv ProjectileUnits template key
--   husks            : the in-flight boar-spear unit + the carrier pickup unit
--   pickup_names     : the impact pickup key + its link_ variant
--
-- This module owns NO engine globals and installs NO hooks, so the fail-closed
-- contract runs in the offline Lua suite (qa/lua/tests/test_cwv_thrown_wire_policy.lua).

local M = {}

-- Sender dispositions. Three-valued BY CONSTRUCTION: the predecessor helper
-- (_cwv_javelin_pickup.wire_fallback) returned nil for BOTH "parity confirmed,
-- keep the custom id" and "no fallback was ever declared for this key", so an
-- unmapped cwv pickup -- `cwv_tuskgor_javelin_bomb` was exactly that -- silently
-- resolved to sending the custom index. There is no nil verdict here.
M.RIDE_CUSTOM = "RIDE_CUSTOM"   -- send `name` unchanged (proven exact, or not ours)
M.SUBSTITUTE  = "SUBSTITUTE"    -- send the returned vanilla donor name instead
M.DROP        = "DROP"          -- send nothing; the spawn is suppressed
M.BLOCK       = "BLOCK"         -- feature-level: do not run the gated feature

M.OWNED_PREFIX = "cwv_"

local function _positive_integer(value)
	return type(value) == "number" and value > 0 and math.floor(value) == value
end

-- A lookup row is usable only if BOTH directions agree. NetworkLookup's strict
-- __index metamethod hard-errors on a missing key (network_lookup.lua), so a
-- half-registered row is a crash waiting for the first decode.
function M.lookup_row_intact(lookup, name)
	if type(lookup) ~= "table" then return false end
	local id = rawget(lookup, name)
	return _positive_integer(id) and rawget(lookup, id) == name
end

-- A configured vanilla donor is not safe merely because its key is a string.
-- Prove every table the native pickup sender dereferences immediately before
-- serialization (player_projectile_unit_extension.lua:1354, 1376-1383): the
-- pickup_names row, the AllPickups settings row, its husk unit, and its
-- go_types unit template.
function M.pickup_donor_intact(globals, name)
	globals = globals or {}
	local nl = globals.NetworkLookup
	local row = type(globals.AllPickups) == "table" and rawget(globals.AllPickups, name)
	if type(nl) ~= "table" or not M.lookup_row_intact(nl.pickup_names, name)
			or type(row) ~= "table" or type(row.unit_name) ~= "string"
			or type(row.unit_template_name) ~= "string" then
		return false
	end
	return M.lookup_row_intact(nl.husks, row.unit_name)
		and M.lookup_row_intact(nl.go_types, row.unit_template_name)
end

-- Prove the vanilla projectile template, both numeric lookup axes, and the
-- transient loader's unit->template inverse (projectile_units.lua:59-63,
-- consumed by transient_package_loader.lua:155 and
-- player_projectile_husk_extension.lua:60) before substituting it or shadowing
-- a transient hot-join ref with it.
function M.projectile_donor_intact(globals, template_key)
	globals = globals or {}
	local nl = globals.NetworkLookup
	local template = type(globals.ProjectileUnits) == "table"
		and rawget(globals.ProjectileUnits, template_key)
	local unit_name = type(template) == "table" and template.projectile_unit_name
	return type(nl) == "table" and type(unit_name) == "string"
		and M.lookup_row_intact(nl.projectile_units, template_key)
		and M.lookup_row_intact(nl.husks, unit_name)
		and type(globals.ProjectileUnitsFromUnitName) == "table"
		and rawget(globals.ProjectileUnitsFromUnitName, unit_name) == template_key
end

-- A pickup name is CWV-owned when it carries a declared donor OR the cwv_
-- prefix. The prefix arm is what makes an UNDECLARED cwv key (a newly
-- registered thrown pickup whose author forgot the donor map) fail closed
-- instead of riding the wire.
function M.is_owned_pickup(name, spec)
	if type(name) ~= "string" then return false end
	local fallbacks = spec and spec.pickup_fallbacks
	if type(fallbacks) == "table" and rawget(fallbacks, name) ~= nil then return true end
	local prefix = (spec and spec.owned_prefix) or M.OWNED_PREFIX
	return name:sub(1, #prefix) == prefix
end

function M.pickup_disposition(name, exact_safe, spec, globals)
	spec = spec or {}
	if type(name) ~= "string" or name == "" then return M.DROP end
	if not M.is_owned_pickup(name, spec) then return M.RIDE_CUSTOM, name end
	if exact_safe == true then return M.RIDE_CUSTOM, name end
	local fallbacks = spec.pickup_fallbacks
	local fallback = type(fallbacks) == "table" and rawget(fallbacks, name) or nil
	if type(fallback) == "string" and M.pickup_donor_intact(globals, fallback) then
		return M.SUBSTITUTE, fallback
	end
	return M.DROP
end

-- In-flight projectile axis. UNCONDITIONAL substitution (never gated on parity
-- or a toggle -- memory reference_vt2_wire_safety_never_toggle_gated, #278/#371):
-- the custom husk id must never reach a vanilla GameObject. The only decision
-- is whether the vanilla donor is currently PROVABLE; when it is not, the
-- caller gets DROP and the ProjectileSystem preflight refuses the spawn rather
-- than letting vanilla dereference a malformed resolution.
function M.projectile_disposition(projectile_units, spec, globals)
	spec = spec or {}
	if type(projectile_units) ~= "table" then return M.DROP end
	if projectile_units.projectile_unit_name ~= spec.inflight_unit then
		return M.RIDE_CUSTOM, projectile_units
	end
	if not M.projectile_donor_intact(globals, spec.safe_projectile_key) then
		return M.DROP
	end
	local units = type(globals) == "table" and globals.ProjectileUnits
	local donor = type(units) == "table" and rawget(units, spec.safe_projectile_key)
	if type(donor) ~= "table" or type(donor.projectile_unit_name) ~= "string" then
		return M.DROP
	end
	return M.SUBSTITUTE, donor
end

local function hash_identity(value)
	local h1, h2 = 104729, 130363
	for i = 1, #value do
		local byte = string.byte(value, i)
		h1 = (h1 * 131 + byte) % 2147483647
		h2 = (h2 * 257 + byte) % 2147483629
	end
	return string.format("cwv-thrown-v1:%08x:%08x", h1, h2)
end

-- Fingerprint the three lookup axes plus the projectile inverse into one
-- identity string. Returns nil + a reason when any row is missing or
-- half-registered, so the caller fails closed with a diagnosable cause.
function M.capture(Catalog, globals, spec)
	globals, spec = globals or {}, spec or {}
	local nl = globals.NetworkLookup
	if type(Catalog) ~= "table" or type(Catalog.build_identity) ~= "function"
			or type(nl) ~= "table" then return nil, "catalog-or-lookup-missing" end
	local axes = {
		{ "projectile_units", rawget(nl, "projectile_units"),
			{ [spec.projectile_key] = spec.safe_projectile_key } },
		{ "husks", rawget(nl, "husks"), {
			[spec.inflight_unit] = spec.safe_projectile_unit,
			[spec.carrier_unit] = true,
		} },
		{ "pickup_names", rawget(nl, "pickup_names"), {
			[spec.pickup_key] = spec.safe_pickup_key,
			[spec.link_pickup_key] = spec.safe_link_pickup_key,
		} },
	}
	local inverse = globals.ProjectileUnitsFromUnitName
	if type(inverse) ~= "table"
			or rawget(inverse, spec.inflight_unit) ~= spec.projectile_key then
		return nil, "projectile-inverse-mismatch:" .. tostring(spec.inflight_unit)
	end
	local snapshot = {
		globals = globals,
		spec = spec,
		axes = {},
		rows = {},
		projectile_inverse = inverse,
		projectile_inverse_key = spec.inflight_unit,
		projectile_inverse_value = spec.projectile_key,
	}
	local identities = {}
	for i = 1, #axes do
		local axis = axes[i]
		local identity, err, names = Catalog.build_identity(
			"cwv." .. axis[1], axis[3], axis[2])
		if not identity then return nil, err end
		identities[i] = identity
		snapshot.axes[i] = { name = axis[1], lookup = axis[2] }
		for n = 1, #names do
			local name, fallback = names[n], axis[3][names[n]]
			snapshot.rows[#snapshot.rows + 1] = {
				lookup = axis[2], name = name, id = rawget(axis[2], name),
				fallback = fallback,
				fallback_id = fallback == true and nil or rawget(axis[2], fallback),
			}
		end
	end
	identities[#identities + 1] = "projectile_inverse:"
		.. tostring(spec.inflight_unit) .. "=" .. tostring(spec.projectile_key)
	snapshot.identity = hash_identity(table.concat(identities, "|"))
	local intact, reason = M.integrity(snapshot)
	if not intact then return nil, reason end
	return snapshot
end

-- Re-prove the captured catalog at send time. A mod that appends to the same
-- lookups AFTER our capture shifts our ids without touching the beacon, so the
-- acknowledgement alone is never sufficient authority.
function M.integrity(snapshot)
	if type(snapshot) ~= "table" or type(snapshot.rows) ~= "table"
			or type(snapshot.globals) ~= "table" then return false, "snapshot-invalid" end
	for i = 1, #snapshot.rows do
		local row = snapshot.rows[i]
		if rawget(row.lookup, row.name) ~= row.id or rawget(row.lookup, row.id) ~= row.name then
			return false, "lookup-drift:" .. tostring(row.name)
		end
		if row.fallback ~= true and (rawget(row.lookup, row.fallback) ~= row.fallback_id
				or rawget(row.lookup, row.fallback_id) ~= row.fallback) then
			return false, "fallback-drift:" .. tostring(row.fallback)
		end
	end
	local g, s = snapshot.globals, snapshot.spec
	if type(snapshot.projectile_inverse) ~= "table"
			or snapshot.projectile_inverse ~= g.ProjectileUnitsFromUnitName
			or snapshot.projectile_inverse_key ~= s.inflight_unit
			or snapshot.projectile_inverse_value ~= s.projectile_key
			or rawget(snapshot.projectile_inverse, s.inflight_unit) ~= s.projectile_key then
		return false, "projectile-inverse-drift"
	end
	local pu = g.ProjectileUnits
	local custom = type(pu) == "table" and rawget(pu, s.projectile_key)
	local safe = type(pu) == "table" and rawget(pu, s.safe_projectile_key)
	if type(custom) ~= "table" or custom.projectile_unit_name ~= s.inflight_unit
			or type(safe) ~= "table" or safe.projectile_unit_name ~= s.safe_projectile_unit then
		return false, "projectile-contract-drift"
	end
	local ammo = type(g.Pickups) == "table" and g.Pickups.ammo
	local keys = { s.pickup_key, s.link_pickup_key }
	for i = 1, #keys do
		local key = keys[i]
		local row = type(ammo) == "table" and rawget(ammo, key)
		if type(row) ~= "table" or row.unit_name ~= s.carrier_unit
				or row.pickup_name ~= key or type(g.AllPickups) ~= "table"
				or rawget(g.AllPickups, key) ~= row then
			return false, "pickup-contract-drift:" .. tostring(key)
		end
	end
	return true
end

-- Exact safety = the beacon is installed, its committed feature state is
-- enabled (so every peer echoed OUR identity), and our own catalog has not
-- drifted since capture. Any error in any arm reads false.
function M.exact_safe(parity, snapshot)
	if type(parity) ~= "table" then return false end
	local ok_i, installed = pcall(parity.is_installed, parity)
	local ok_s, state = pcall(parity.applied_state, parity)
	local ok_c, intact = pcall(M.integrity, snapshot)
	return ok_i and installed == true and ok_s and state == "enabled"
		and ok_c and intact == true
end

function M.feature_disposition(exact_safe)
	return exact_safe == true and M.RIDE_CUSTOM or M.BLOCK
end

return M
