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

return M
