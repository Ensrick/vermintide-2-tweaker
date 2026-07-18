-- Canonical immutable appearance descriptor (#660 slice S1).
-- Engine-free: no VT2 globals, no mod state - callers inject identity
-- evidence and authored fields; adapters consume the frozen result.
--
-- One descriptor per exact item instance (or per strongest identity the
-- caller actually has - see WEAPON_APPEARANCE_STANDARD.md "Identity
-- available to presentation adapters"). Surfaces NEVER re-derive a field
-- the descriptor carries; the reconciler replays the same descriptor at
-- every lifecycle edge and correlates apply reports by fingerprint.
local M = {}

M.EVIDENCE_KINDS = { backend_id = true, loadout_snapshot = true, preview_slot = true }

-- The acceptance cells every registered family must declare (implemented or
-- unsupported-with-fallback). qa/check_appearance_census.ps1 enforces this
-- list; keep the two in sync via M.CELLS.
M.CELLS = {
	"owner_1p", "owner_3p", "bot", "husk",
	"inventory_preview", "illusion_browser", "cim_preview",
	"lobby", "score_team", "hold_tab",
}

M.EDGES = {
	"instance_load", "peer_ready", "equip", "customize",
	"preview_open", "mission_transition", "respawn", "mod_disable_restore",
}

local function is_triplet(v)
	return type(v) == "table" and #v == 3
		and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number"
end

local function validate_transform(t, path, errors)
	if t == nil then return end
	if type(t) ~= "table" then
		errors[#errors + 1] = path .. " must be a table"
		return
	end
	for _, field in ipairs({ "scale", "offset", "rotation" }) do
		local v = t[field]
		if v ~= nil and not is_triplet(v) then
			errors[#errors + 1] = path .. "." .. field .. " must be a numeric triplet"
		end
	end
end

local function validate_hand(h, path, errors)
	if h == nil then return end
	if type(h) ~= "table" or type(h.unit) ~= "string" or #h.unit == 0 then
		errors[#errors + 1] = path .. " must carry a non-empty unit string"
		return
	end
	if h.package ~= nil and type(h.package) ~= "string" then
		errors[#errors + 1] = path .. ".package must be a string when present"
	end
end

-- Every OPTIONAL visual field demands a vanilla-safe fallback twin so a
-- peer without the providing mod (or a failed residency proof) degrades to
-- a resident vanilla presentation instead of an invisible/base-mesh unit.
local FALLBACK_REQUIRED = {
	right_hand_unit = true, left_hand_unit = true,
	textures = true, materials = true, glow = true,
}

function M.validate(spec)
	local errors = {}
	if type(spec) ~= "table" then return false, { "spec must be a table" } end
	if type(spec.item_key) ~= "string" or #spec.item_key == 0 then
		errors[#errors + 1] = "item_key required"
	end
	local ev = spec.identity_evidence
	if type(ev) ~= "table" or not M.EVIDENCE_KINDS[ev.kind or ""] then
		errors[#errors + 1] = "identity_evidence.kind must be backend_id | loadout_snapshot | preview_slot"
	elseif ev.kind == "backend_id" and (type(ev.value) ~= "string" or #ev.value == 0) then
		errors[#errors + 1] = "backend_id evidence requires a non-empty value"
	end
	validate_hand(spec.right_hand_unit, "right_hand_unit", errors)
	validate_hand(spec.left_hand_unit, "left_hand_unit", errors)
	validate_transform(spec.transform_1p, "transform_1p", errors)
	validate_transform(spec.transform_3p, "transform_3p", errors)
	if spec.requires_mod ~= nil and type(spec.requires_mod) ~= "string" then
		errors[#errors + 1] = "requires_mod must be a string when present"
	end
	local has_optional_visual = false
	for field in pairs(FALLBACK_REQUIRED) do
		if spec[field] ~= nil then has_optional_visual = true break end
	end
	if has_optional_visual then
		local fb = spec.fallback
		if type(fb) ~= "table" then
			errors[#errors + 1] = "fallback table required whenever an optional visual field is set"
		else
			validate_hand(fb.right_hand_unit, "fallback.right_hand_unit", errors)
			validate_hand(fb.left_hand_unit, "fallback.left_hand_unit", errors)
		end
	end
	return #errors == 0, errors
end

-- Deterministic serialization: sorted keys, primitives only, cycles and
-- functions rejected - descriptors are DATA. Used by fingerprint().
local function serialize(value, out, seen)
	local t = type(value)
	if t == "nil" then out[#out + 1] = "~"
	elseif t == "boolean" or t == "number" then out[#out + 1] = tostring(value)
	elseif t == "string" then out[#out + 1] = string.format("%q", value)
	elseif t == "table" then
		if seen[value] then error("descriptor tables must not contain cycles", 0) end
		seen[value] = true
		local keys = {}
		for k in pairs(value) do
			if type(k) ~= "string" and type(k) ~= "number" then
				error("descriptor keys must be strings or numbers", 0)
			end
			keys[#keys + 1] = k
		end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		out[#out + 1] = "{"
		for _, k in ipairs(keys) do
			out[#out + 1] = tostring(k) .. "="
			serialize(value[k], out, seen)
			out[#out + 1] = ";"
		end
		out[#out + 1] = "}"
		seen[value] = nil
	else
		error("descriptor fields must be data, got " .. t, 0)
	end
end

-- djb2 over the canonical serialization, kept in 32-bit range (Lua 5.1
-- doubles are exact well past 2^32; the modulo keeps the value printable
-- as 8 hex digits so owner and observer logs can correlate cheaply).
function M.fingerprint(descriptor)
	local out = {}
	serialize(M.raw(descriptor) or descriptor, out, {})
	local s = table.concat(out)
	local hash = 5381
	for i = 1, #s do
		hash = (hash * 33 + string.byte(s, i)) % 4294967296
	end
	return string.format("%08x", hash)
end

local RAW = {}

-- Freeze: the built descriptor is a read-only proxy. Adapters cannot
-- mutate shared appearance state (the two-writers race #660 bans);
-- reconciler internals reach the plain table via M.raw().
function M.build(spec)
	local ok, errors = M.validate(spec)
	if not ok then return nil, errors end
	local data = {}
	for k, v in pairs(spec) do data[k] = v end
	data.generation = spec.generation or 0
	local proxy = setmetatable({ [RAW] = data }, {
		__index = data,
		__newindex = function()
			error("appearance descriptor is immutable - build a new one", 2)
		end,
		__metatable = "appearance_descriptor",
	})
	return proxy
end

function M.raw(descriptor)
	return type(descriptor) == "table" and rawget(descriptor, RAW) or nil
end

-- Lifecycle regeneration: a customization/style change produces a NEW
-- descriptor with generation+1; stale applies are detected by comparing
-- (fingerprint, generation) rather than re-reading menu state.
function M.next_generation(descriptor)
	local data = M.raw(descriptor)
	if not data then return nil, { "not a built descriptor" } end
	local copy = {}
	for k, v in pairs(data) do copy[k] = v end
	copy.generation = (data.generation or 0) + 1
	return M.build(copy)
end

return M
