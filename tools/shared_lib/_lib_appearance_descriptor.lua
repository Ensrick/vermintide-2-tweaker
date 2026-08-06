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

-- The acceptance SURFACES every registered family must declare against every
-- lifecycle edge. qa/lua/tests/test_appearance_census.lua enforces this list.
-- M.CELLS keeps its historical name (the surface vector); M.SURFACES is the
-- clearer alias. A "cell" in the #1157 schema is one (surface, edge) PAIR.
M.CELLS = {
	"owner_1p", "owner_3p", "bot", "husk",
	"inventory_preview", "illusion_browser", "cim_preview",
	"lobby", "score_team", "hold_tab",
	-- Added 2026-08-04 (#1157). Six surfaces the vector-era census could not
	-- name at all, so their gaps were invisible rather than declared.
	"specials", "remote_audio", "hud_panels", "portraits",
	"item_card_2d", "inventory_tooltip",
}

M.SURFACES = M.CELLS

M.EDGES = {
	"instance_load", "peer_ready", "equip", "customize",
	"preview_open", "mission_transition", "respawn", "mod_disable_restore",
}

M.CELL_STATES = { implemented = true, unsupported = true }

M.CENSUS_SCHEMA_VERSION = 2

-- Every mod that overrides weapon/cosmetic appearance, and where its census
-- lives. Shared by qa/lua/tests/test_appearance_census.lua and by
-- tools/gen-appearance-gaps so coverage can never drift between the gate and
-- the report. Order is the report order; `mirror_of` marks a byte-parity clone
-- whose pairs are the same backlog counted twice.
M.CENSUS_FILES = {
	{ mod = "character_weapon_variants",
	  path = "character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_appearance_census.lua" },
	{ mod = "cosmetics_tweaker",
	  path = "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_appearance_census.lua" },
	{ mod = "weapon_tweaker",
	  path = "weapon_tweaker/scripts/mods/weapon_tweaker/_wt_appearance_census.lua" },
	{ mod = "weapon_tweaker_dev", mirror_of = "weapon_tweaker",
	  path = "weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_appearance_census.lua" },
	{ mod = "weapons_of_chaos",
	  path = "weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_appearance_census.lua" },
}

local SURFACE_SET, EDGE_SET = {}, {}
for _, s in ipairs(M.CELLS) do SURFACE_SET[s] = true end
for _, e in ipairs(M.EDGES) do EDGE_SET[e] = true end

M.SURFACE_SET, M.EDGE_SET = SURFACE_SET, EDGE_SET

-- Surface x edge matrix expansion (#1157).
--
-- WHY the matrix. The vector-era census declared surfaces and edges as two
-- INDEPENDENT lists, so "husk = implemented" and "mission_transition =
-- unsupported" could coexist with no way to say "husk AT mission transition is
-- the thing that breaks" - which is the exact recurring failure class (#914,
-- #233, #692/#786). Declaring the pair removes that blind spot.
--
-- AUTHORING FORMAT (compact, one row per surface; expanded here to the full
-- matrix). A row states its default EXPLICITLY and may override single edges:
--
--   matrix = {
--     husk = {
--       default = "implemented",
--       note    = "row-level fallback note, used by any unsupported pair",
--       edges   = { peer_ready = "unsupported", mission_transition = "unsupported" },
--       notes   = { peer_ready = "per-edge note; wins over the row note" },
--     },
--     ... one row for EVERY entry of M.CELLS ...
--   }
--
-- EXPANSION RULE. state(surface, edge) = row.edges[edge] or row.default, and
-- note(surface, edge) = row.notes[edge] or row.note. Nothing is implicit: a
-- missing row, a missing/invalid default, an unknown surface or edge, or an
-- unsupported pair with no note is an ERROR. The expander never guesses a
-- state, because a false "implemented" is the failure this gate exists to kill.
--
-- Returns (matrix, {}) on success where matrix[surface][edge] = { state=,
-- note= }, or (nil, errors) with every problem listed.
function M.expand_matrix(decl, path)
	path = path or "matrix"
	local errors = {}
	if type(decl) ~= "table" then
		return nil, { path .. " must be a table" }
	end
	for surface in pairs(decl) do
		if not SURFACE_SET[surface] then
			errors[#errors + 1] = path .. ": unknown surface '" .. tostring(surface) .. "'"
		end
	end
	local out = {}
	for _, surface in ipairs(M.CELLS) do
		local row = decl[surface]
		local prefix = path .. "." .. surface
		if type(row) ~= "table" then
			errors[#errors + 1] = prefix .. ": missing surface row (every surface must be declared)"
		else
			if not M.CELL_STATES[row.default] then
				errors[#errors + 1] = prefix
					.. ".default must be stated explicitly as implemented or unsupported"
			end
			local overrides, notes = row.edges, row.notes
			if overrides ~= nil and type(overrides) ~= "table" then
				errors[#errors + 1] = prefix .. ".edges must be a table when present"
				overrides = nil
			end
			if notes ~= nil and type(notes) ~= "table" then
				errors[#errors + 1] = prefix .. ".notes must be a table when present"
				notes = nil
			end
			if overrides then
				for edge in pairs(overrides) do
					if not EDGE_SET[edge] then
						errors[#errors + 1] = prefix .. ".edges: unknown edge '" .. tostring(edge) .. "'"
					end
				end
			end
			if notes then
				for edge in pairs(notes) do
					if not EDGE_SET[edge] then
						errors[#errors + 1] = prefix .. ".notes: unknown edge '" .. tostring(edge) .. "'"
					end
				end
			end
			if row.note ~= nil and type(row.note) ~= "string" then
				errors[#errors + 1] = prefix .. ".note must be a string when present"
			end
			local row_out = {}
			for _, edge in ipairs(M.EDGES) do
				local state = (overrides and overrides[edge]) or row.default
				local note = (notes and notes[edge]) or row.note
				if not M.CELL_STATES[state] then
					errors[#errors + 1] = prefix .. "." .. edge
						.. ": unresolved state '" .. tostring(state) .. "'"
				else
					if state == "unsupported" and (type(note) ~= "string" or #note == 0) then
						errors[#errors + 1] = prefix .. "." .. edge
							.. ": unsupported pair needs a fallback note"
					end
					row_out[edge] = { state = state, note = note }
				end
			end
			out[surface] = row_out
		end
	end
	if #errors > 0 then return nil, errors end
	return out, errors
end

-- Convenience for report generators: walk the expanded matrix in the canonical
-- surface-then-edge order so output is deterministic across runs and hosts.
function M.each_pair(matrix, fn)
	for _, surface in ipairs(M.CELLS) do
		local row = matrix[surface]
		if row then
			for _, edge in ipairs(M.EDGES) do
				local pair = row[edge]
				if pair then fn(surface, edge, pair.state, pair.note) end
			end
		end
	end
end

local function is_triplet(v)
	return type(v) == "table" and #v == 3
		and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number"
end

local function is_quaternion(v)
	return type(v) == "table" and #v == 4
		and type(v[1]) == "number" and type(v[2]) == "number"
		and type(v[3]) == "number" and type(v[4]) == "number"
end

local function validate_transform(t, path, errors)
	if t == nil then return end
	if type(t) ~= "table" then
		errors[#errors + 1] = path .. " must be a table"
		return
	end
	for _, field in ipairs({ "scale", "offset", "position" }) do
		local v = t[field]
		if v ~= nil and not is_triplet(v) then
			errors[#errors + 1] = path .. "." .. field .. " must be a numeric triplet"
		end
	end
	if t.rotation ~= nil and not is_triplet(t.rotation) and not is_quaternion(t.rotation) then
		errors[#errors + 1] = path .. ".rotation must be Euler XYZ or quaternion numeric data"
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

-- Bounded lifecycle reconciler (#1155 / #660 S3).
--
-- The reconciler deliberately knows nothing about Stingray.  A family injects
-- one adapter and one independent observer.  Setter success is never accepted
-- as proof: an apply is committed only when the observer reports the retained
-- postcondition.  The ledger is weak-keyed by the actual render target so a
-- destroyed world cannot be retained by diagnostics or retry bookkeeping.
-- Duplicate lifecycle delivery is coalesced by
-- (target, surface, edge, descriptor fingerprint, generation).  A failed
-- postcondition may be retried only up to max_attempts (default 2); there is no
-- update-loop or timer owned here.
function M.new_reconciler(options)
	options = options or {}
	local apply = options.apply
	local observe = options.observe
	local max_attempts = tonumber(options.max_attempts) or 2
	if max_attempts < 1 then max_attempts = 1 end
	local records = setmetatable({}, { __mode = "k" })
	local R = {}

	local function valid_axis(value, set)
		return type(value) == "string" and set[value] == true
	end

	local function token_for(descriptor, surface, edge)
		local ok, fp = pcall(M.fingerprint, descriptor)
		if not ok then return nil, tostring(fp) end
		return table.concat({ surface, edge, fp, tostring(descriptor.generation or 0) }, "|")
	end

	function R.reconcile(descriptor, surface, edge, target, context)
		if not M.raw(descriptor) then return { ok = false, reason = "descriptor-unbuilt" } end
		if not valid_axis(surface, SURFACE_SET) then
			return { ok = false, reason = "unknown-surface" }
		end
		if not valid_axis(edge, EDGE_SET) then return { ok = false, reason = "unknown-edge" } end
		if target == nil then return { ok = false, reason = "target-missing" } end
		local token, token_error = token_for(descriptor, surface, edge)
		if not token then return { ok = false, reason = "fingerprint-failed", detail = token_error } end

		local target_records = records[target]
		if not target_records then target_records = {}; records[target] = target_records end
		local record = target_records[token]
		if record and (record.completed or record.retained or record.attempts >= max_attempts) then
			return {
				ok = record.retained == true or record.fallback == true,
				retained = record.retained == true,
				fallback = record.fallback == true,
				coalesced = true,
				attempts = record.attempts,
				reason = record.reason,
				token = token,
			}
		end
		record = record or { attempts = 0, retained = false }
		record.attempts = record.attempts + 1
		target_records[token] = record

		if type(apply) ~= "function" then
			record.reason = "adapter-missing"
			return { ok = false, attempts = record.attempts, reason = record.reason, token = token }
		end
		local call_ok, apply_report = pcall(apply, descriptor, surface, edge, target, context)
		if not call_ok then
			record.reason = "adapter-error"
			record.detail = tostring(apply_report)
			return { ok = false, attempts = record.attempts, reason = record.reason,
				detail = record.detail, token = token }
		end
		if type(apply_report) == "table" and apply_report.fallback == true then
			record.completed = true
			record.fallback = true
			record.reason = apply_report.reason or "vanilla-fallback"
			return { ok = true, retained = false, fallback = true, attempts = record.attempts,
				reason = record.reason, token = token, apply = apply_report }
		end
		if type(observe) ~= "function" then
			record.reason = "observer-missing"
			return { ok = false, attempts = record.attempts, reason = record.reason,
				token = token, apply = apply_report }
		end
		-- `observe` receives the descriptor and live target, never the setter
		-- result.  This keeps the evidence path independent by construction.
		local observed_ok, observation = pcall(observe, descriptor, surface, edge, target, context)
		if not observed_ok then
			record.reason = "observer-error"
			record.detail = tostring(observation)
		else
			record.retained = type(observation) == "table"
				and observation.retained == true or observation == true
			record.reason = type(observation) == "table" and observation.reason
				or (record.retained and "retained" or "postcondition-failed")
		end
		return {
			ok = record.retained,
			retained = record.retained,
			attempts = record.attempts,
			reason = record.reason,
			detail = record.detail,
			token = token,
			apply = apply_report,
			observation = observation,
		}
	end

	function R.forget(target)
		if target == nil then return false end
		local existed = records[target] ~= nil
		records[target] = nil
		return existed
	end

	function R.disconnect()
		records = setmetatable({}, { __mode = "k" })
		return true
	end

	function R.attempts(target, descriptor, surface, edge)
		local token = target and token_for(descriptor, surface, edge)
		local record = token and records[target] and records[target][token]
		return record and record.attempts or 0
	end

	return R
end

return M
