-- Phase-3 appearance pilot for the CWV Old Musket (#1155/#474/#660).
--
-- One immutable descriptor is resolved before an engine adapter runs.  Every
-- surface enters through `reconcile`; no surface owns a model/material/pose
-- recipe.  The shared reconciler applies once per exact lifecycle token and
-- commits only after this module reads retained state back from the
-- live unit.  Unsupported renderers explicitly retain vanilla presentation.
local M = {}

local UNIT_SURFACES = {
	owner_1p = true, owner_3p = true, bot = true, husk = true,
	inventory_preview = true, illusion_browser = true, cim_preview = true,
	lobby = true, score_team = true,
}

local IMPLEMENTED_CELLS = {
	owner_1p = { instance_load = true, equip = true, customize = true },
	owner_3p = { instance_load = true, equip = true, customize = true },
	bot = { instance_load = true, equip = true },
	husk = { instance_load = true, equip = true, peer_ready = true },
	inventory_preview = { instance_load = true, preview_open = true },
	illusion_browser = { instance_load = true, preview_open = true },
	cim_preview = { instance_load = true, preview_open = true },
}

local function item_backend_id(item)
	local data = type(item) == "table" and item.data or nil
	local mod_data = type(item) == "table" and (item.mod_data
		or (data and data.mod_data)) or nil
	return type(item) == "table" and (item.backend_id or item.ItemInstanceId
		or (data and (data.backend_id or data.ItemInstanceId))
		or (mod_data and mod_data.backend_id)) or nil
end

local function identity_evidence(item, surface, context)
	-- HeroWindow reconstructs LootItemUnitPreviewer when the player selects an
	-- illusion.  Each previewer's `_item` is stable, but the new preview item is
	-- not necessarily the equipped backend instance that opened the browser.
	-- Its source-backed identity is the exact previewer+item token supplied by
	-- the adapter, not the owner's held backend id (#1156).
	local preview_identity = surface == "illusion_browser" and context
		and context.preview_identity or nil
	if type(preview_identity) == "string" and preview_identity ~= ""
			and #preview_identity <= 128 then
		return { kind = "preview_slot", value = preview_identity }
	end
	local bid = item_backend_id(item)
	if type(bid) == "string" and #bid > 0 then
		return { kind = "backend_id", value = bid }
	end
	if context and context.peer_id and context.slot_name then
		return { kind = "loadout_snapshot", value = tostring(context.peer_id)
			.. ":" .. tostring(context.slot_name) }
	end
	return { kind = "preview_slot", value = tostring(surface or "unknown") }
end

local function vector_elements(api, value)
	if type(value) == "table" and type(value[1]) == "number"
			and type(value[2]) == "number" and type(value[3]) == "number" then
		return { value[1], value[2], value[3] }
	end
	if not value or not api or type(api.to_elements) ~= "function" then return nil end
	local ok, x, y, z = pcall(api.to_elements, value)
	return ok and { x, y, z } or nil
end

local function quaternion_elements(api, value)
	if not value or not api or type(api.to_elements) ~= "function" then return nil end
	local ok, x, y, z, w = pcall(api.to_elements, value)
	if not ok then return nil end
	local function finite(element)
		return type(element) == "number" and element == element
			and element ~= math.huge and element ~= -math.huge
	end
	if not finite(x) or not finite(y) or not finite(z) or not finite(w) then return nil end
	return { x, y, z, w }
end

local function near3(actual, expected, epsilon)
	if type(actual) ~= "table" or type(expected) ~= "table" then return false end
	for i = 1, 3 do
		if type(actual[i]) ~= "number" or type(expected[i]) ~= "number"
				or math.abs(actual[i] - expected[i]) > epsilon then return false end
	end
	return true
end

local function quaternion_near(actual, expected, epsilon)
	if type(actual) ~= "table" or type(expected) ~= "table" then return false end
	local dot = 0
	for i = 1, 4 do
		if type(actual[i]) ~= "number" or type(expected[i]) ~= "number" then return false end
		dot = dot + actual[i] * expected[i]
	end
	-- q and -q encode the same rotation.
	return math.abs(math.abs(dot) - 1) <= epsilon
end

local function copy_evidence_value(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, child in pairs(value) do
		copy[key] = copy_evidence_value(child)
	end
	return copy
end

local function tuple_text(value, count)
	if type(value) ~= "table" then return "unavailable" end
	local parts = {}
	for index = 1, count do
		local element = value[index]
		parts[index] = type(element) == "number"
			and string.format("%.5f", element) or "unavailable"
	end
	return table.concat(parts, ",")
end

function M.new(args)
	args = args or {}
	local D, WA, policy = args.descriptor, args.weapon_appearance, args.policy
	local unit_api = args.unit
	local vector_api = args.vector
	local quaternion_api = args.quaternion
	local transform_profile_source = args.transform_profile_source
	local attachment_profiles = args.attachment_profiles
	local canonical_key = args.canonical_key
	local printf_fn = args.printf or function() end
	assert(type(D) == "table" and type(D.build) == "function", "descriptor contract required")
	assert(type(WA) == "table" and type(WA.apply_report) == "function", "appearance writer required")
	assert(type(policy) == "table", "Old Musket resource policy required")
	assert(type(transform_profile_source) == "function", "attachment transform source required")
	assert(type(attachment_profiles) == "table", "attachment profile vocabulary required")

	local tracked = setmetatable({}, { __mode = "k" })
	-- Bounded session evidence. One latest result per canonical surface+stance prevents
	-- `/cwv_regression_test` from reporting PASS before any live renderer was
	-- exercised, while a later retained stable edge supersedes an earlier
	-- construction-time miss. Only CIM's exact preview selection arms the tested
	-- item identity; other equipped slots/bots cannot steal that bounded epoch.
	-- This is one fixed key per canonical surface+stance, never a unit history.
	local evidence = {}
	local evidence_targets = {}
	local evidence_epoch = 0
	local cim_identity
	local held_identity
	local cim_generation = 0
	local preview_lifecycles = {}
	local generation = 0
	local reconciler
	local C = {}
	local function descriptor_data(descriptor)
		return D.raw(descriptor) or descriptor
	end

	local function mode_for(item, explicit)
		if explicit == "melee" then return "melee" end
		local data = type(item) == "table" and item.data or nil
		local md = type(item) == "table" and (item.mod_data
			or (data and data.mod_data)) or nil
		return md and md.cwv_musket_stance == "melee" and "melee" or "ranged"
	end

	local function copy_identity(identity)
		return type(identity) == "table" and {
			kind = identity.kind, value = identity.value,
		} or nil
	end

	local function same_identity(a, b)
		return type(a) == "table" and type(b) == "table"
			and a.kind == b.kind and a.value == b.value
	end

	local function clear_non_cim_evidence()
		for key, row in pairs(evidence) do
			if row.surface ~= "cim_preview" then
				evidence[key] = nil
				evidence_targets[key] = nil
			end
		end
		preview_lifecycles = {}
	end

	local function arm_cim_identity(surface, identity, provider_generation)
		if surface ~= "cim_preview" then return false, "not_cim" end
		if type(identity) ~= "table" or identity.kind ~= "backend_id"
				or type(identity.value) ~= "string" or identity.value == ""
				or #identity.value > 128 then
			return false, "identity_invalid"
		end
		if type(provider_generation) ~= "number" or provider_generation <= 0
				or provider_generation ~= provider_generation
				or provider_generation == math.huge
				or provider_generation % 1 ~= 0 then
			return false, "generation_invalid"
		end
		if provider_generation < cim_generation then
			return false, "generation_stale"
		end
		if provider_generation == cim_generation then
			return same_identity(cim_identity, identity),
				same_identity(cim_identity, identity) and "ready" or "generation_identity_mismatch"
		end
		if provider_generation > cim_generation then
			cim_generation = provider_generation
			cim_identity = copy_identity(identity)
			held_identity = nil
			evidence = {}
			evidence_targets = {}
			preview_lifecycles = {}
			-- The evidence epoch must not inherit a completed/coalesced token from
			-- a pre-arm renderer call. Clear only the bounded reconciler ledger; the
			-- next real lifecycle edge will apply and observe fresh live state.
			if reconciler then reconciler.disconnect() end
			evidence_epoch = evidence_epoch + 1
		end
		return true, "ready"
	end

	local function evidence_identity(surface, candidate)
		local exact_backend = type(candidate) == "table"
			and candidate.kind == "backend_id"
			and type(candidate.value) == "string"
			and candidate.value ~= "" and #candidate.value <= 128
		if surface == "cim_preview" then
			return exact_backend and same_identity(cim_identity, candidate)
				and cim_identity or nil
		end
		if surface == "owner_1p" or surface == "owner_3p" then
			if not exact_backend then return nil end
			if not same_identity(held_identity, candidate) then
				held_identity = copy_identity(candidate)
				clear_non_cim_evidence()
			end
			return held_identity
		end
		if surface == "inventory_preview" or surface == "illusion_browser" then
			if surface == "illusion_browser" and type(candidate) == "table"
					and candidate.kind == "preview_slot"
					and type(candidate.value) == "string" and candidate.value ~= "" then
				return candidate
			end
			return same_identity(held_identity, candidate) and held_identity or nil
		end
		return nil
	end

	local function finite_positive_integer(value)
		return type(value) == "number" and value > 0 and value == value
			and value ~= math.huge and value % 1 == 0
	end

	-- Vanilla owns two useful browser edges: spawn_units constructs the exact
	-- units, then `_enable_item_units_visibility(..., true)` makes those same
	-- units visible after mip streaming.  Keep one bounded lifecycle record for
	-- the latest browser generation.  A stale/mismatched final edge is evidence
	-- failure only; it must never interfere with the renderer itself.
	local function preview_lifecycle_evidence(surface, edge, identity, context)
		if surface ~= "illusion_browser" then return true, nil end
		local preview_generation = context and context.preview_generation
		if not finite_positive_integer(preview_generation)
				or type(identity) ~= "table" or identity.kind ~= "preview_slot" then
			return false, "preview-lifecycle-invalid"
		end
		local current = preview_lifecycles[surface]
		if edge == "instance_load" then
			if current and preview_generation < current.generation then
				-- An older previewer can finish after its replacement became visible.
				-- Reject that delivery, but preserve the newer authoritative row so a
				-- harmless late callback cannot turn a visible success into a false
				-- regression failure (#1156).
				return false, "preview-generation-stale", true
			end
			if current and preview_generation == current.generation
					and not same_identity(current.identity, identity) then
				return false, "preview-identity-mismatch"
			end
			preview_lifecycles[surface] = {
				generation = preview_generation,
				identity = copy_identity(identity),
			}
			return true, nil
		end
		if edge == "preview_open" then
			if not current then return false, "preview-construction-missing" end
			if preview_generation ~= current.generation then
				if preview_generation < current.generation then
					return false, "preview-generation-stale", true
				end
				return false, "preview-construction-missing"
			end
			if not same_identity(current.identity, identity) then
				return false, "preview-identity-mismatch"
			end
			return true, nil
		end
		return false, "preview-edge-invalid"
	end

	local function evidence_row(surface, mode, edge, identity, values, target)
		if not (IMPLEMENTED_CELLS[surface] and IMPLEMENTED_CELLS[surface][edge]) then
			return
		end
		local row = {
			surface = surface, mode = mode, edge = edge,
			identity = copy_identity(identity),
			generation = generation, epoch = evidence_epoch,
		}
		for key, value in pairs(values or {}) do
			row[key] = copy_evidence_value(value)
		end
		-- The ordinary illusion browser has no rifle/bayonet stance control.
		-- Its one latest visible preview lifecycle is the evidence unit; inventing
		-- two mode cells produced #1156's false FAIL.
		local key = surface == "illusion_browser"
			and surface .. ":visible" or surface .. ":" .. mode
		evidence[key] = row
		evidence_targets[key] = target
	end

	local function recipe(profile)
		local position, rotation, scale = transform_profile_source(profile)
		if position == nil or rotation == nil or scale == nil then return nil end
		local unboxed = rotation
		if rotation ~= nil then
			local ok, value = pcall(function()
				return rotation.unbox and rotation:unbox() or rotation
			end)
			unboxed = ok and value or nil
		end
		return {
			position = vector_elements(vector_api, position),
			scale = vector_elements(vector_api, scale),
			rotation = quaternion_elements(quaternion_api, unboxed),
		}
	end

	function C.resolve(item, explicit_mode, surface, context)
		local key = canonical_key(item)
		if key ~= policy.ITEM_KEY and not policy.matches_item(item, key) then return nil end
		local mode = mode_for(item, explicit_mode)
		local selected_profile = context and context.attachment_profile
		local transform_profiles = {}
		for _, profile in pairs(attachment_profiles) do
			transform_profiles[profile] = recipe(profile)
		end
		if type(selected_profile) ~= "string"
				or transform_profiles[selected_profile] == nil then
			return nil, { "exact attachment_profile required for " .. tostring(surface) }
		end
		local descriptor, errors = D.build({
			item_key = policy.ITEM_KEY,
			skin_key = policy.SKIN_KEY,
			identity_evidence = identity_evidence(item, surface, context),
			mode = mode,
			requires_mod = "character_weapon_variants",
			right_hand_unit = { unit = policy.UNIT, unit_3p = policy.UNIT_3P,
				package = policy.PREVIEW_PACKAGE_ALIAS },
			textures = policy.TEXTURES,
			materials = { authored = policy.MATERIAL,
				preview = policy.PREVIEW_MATERIAL },
			attachment_profile = selected_profile,
			transform_profiles = transform_profiles,
			fallback = {
				right_hand_unit = { unit = policy.NETWORK_PACKAGE_ALIAS_1P,
					unit_3p = policy.NETWORK_PACKAGE_ALIAS_3P,
					package = policy.PREVIEW_PACKAGE_ALIAS },
				textures = {}, materials = {},
			},
			generation = generation,
		})
		if not descriptor then return nil, errors end
		return descriptor
	end

	local function target_is_custom(descriptor, surface, context)
		descriptor = descriptor_data(descriptor)
		local observed = context and context.unit_name
		if type(observed) ~= "string" or observed == "" then return false end
		local expected = surface == "owner_1p" and descriptor.right_hand_unit.unit
			or descriptor.right_hand_unit.unit_3p
		return observed == expected and context.attachment_profile == descriptor.attachment_profile
	end

	local function engine_rotation_box(value)
		local state = { constructed = false }
		if type(value) ~= "table" or #value ~= 4 then return nil, state end
		for index = 1, 4 do
			local element = value[index]
			if type(element) ~= "number" or element ~= element
					or element == math.huge or element == -math.huge then return nil, state end
		end
		if type(quaternion_api) ~= "table"
				or type(quaternion_api.from_elements) ~= "function" then return nil, state end
		-- Never retain or expose Stingray's stack-temporary Quaternion. This
		-- descriptor-scoped box constructs a fresh raw value exactly when the
		-- shared atomic writer unboxes it in the same frame. VT2's native quartet
		-- reconstruction path is Quaternion.from_elements, not field access.
		return { unbox = function()
			state.constructed = false
			local fresh_ok, fresh = pcall(quaternion_api.from_elements,
				value[1], value[2], value[3], value[4])
			if not fresh_ok or fresh == nil then
				error("Quaternion.from_elements rejected descriptor quartet")
			end
			if quaternion_elements(quaternion_api, fresh) == nil then
				error("Quaternion.from_elements returned invalid values")
			end
			state.constructed = true
			return fresh
		end }, state
	end

	local function apply(descriptor, surface, edge, target, context)
		descriptor = descriptor_data(descriptor)
		if not UNIT_SURFACES[surface] or not (IMPLEMENTED_CELLS[surface]
				and IMPLEMENTED_CELLS[surface][edge]) then
			return { fallback = true, reason = "surface-retains-vanilla-presentation" }
		end
		if not target_is_custom(descriptor, surface, context) then
			return { fallback = true, reason = "custom-unit-not-retained" }
		end
		local preview = surface == "inventory_preview" or surface == "illusion_browser"
			or surface == "cim_preview" or surface == "lobby" or surface == "score_team"
		local apply_visual = policy.apply_material or policy.apply_textures
		if type(apply_visual) ~= "function" then
			return { ok = false, reason = "material-adapter-missing" }
		end
		local painted, texture_count = apply_visual(target, preview)
		context = context or {}
		context._appearance_required_paint = painted == true
			and (texture_count or 0) >= #(descriptor.textures or {})
		local spec = descriptor.transform_profiles[descriptor.attachment_profile]
		local resolved_rotation, rotation_state = engine_rotation_box(spec.rotation)
		local report = WA.apply_report(target, {
			position = spec.position, scale = spec.scale,
			rotation = resolved_rotation,
		})
		context._appearance_required_apply = resolved_rotation ~= nil and report.ok == true
		context._appearance_transform_report = {
			mode = report.transform_mode,
			node = report.transform_node,
			error = report.transform_error,
			rotation_constructed = rotation_state
				and rotation_state.constructed == true or false,
			position = report.channels and report.channels.position,
			scale = report.channels and report.channels.scale,
			rotation = report.channels and report.channels.rotation,
		}
		report.painted = painted == true
		report.texture_writes = texture_count or 0
		tracked[target] = { item = context and context.item, mode = descriptor.mode,
			surface = surface, edge = edge, context = context }
		return report
	end

	local function observe(descriptor, surface, _, target, context)
		descriptor = descriptor_data(descriptor)
		if not target_is_custom(descriptor, surface, context) then
			return { retained = false, reason = "unit-identity-mismatch" }
		end
		local alive_ok, alive = pcall(unit_api.alive, target)
		if not alive_ok or alive ~= true then return { retained = false, reason = "unit-dead" } end
		if not UNIT_SURFACES[surface] then return { retained = true, reason = "vanilla-fallback" } end
		local spec = descriptor.transform_profiles[descriptor.attachment_profile]
		local ok_p, position = pcall(unit_api.local_position, target, 0)
		local ok_s, scale = pcall(unit_api.local_scale, target, 0)
		local ok_r, rotation = pcall(unit_api.local_rotation, target, 0)
		local actual_position = ok_p and vector_elements(vector_api, position) or nil
		local actual_scale = ok_s and vector_elements(vector_api, scale) or nil
		local actual_rotation = ok_r
			and quaternion_elements(quaternion_api, rotation) or nil
		local retained_position = near3(actual_position, spec.position, 0.002)
		local retained_scale = near3(actual_scale, spec.scale, 0.002)
		local retained_rotation = ok_r and quaternion_near(
			actual_rotation, spec.rotation, 0.003)
		local materials_ready = policy.unit_materials_ready(target)
		local retained = context and context._appearance_required_paint == true
			and context._appearance_required_apply == true
			and retained_position and retained_scale and retained_rotation
			and materials_ready == true
		local transform = context and context._appearance_transform_report or {}
		return {
			retained = retained,
			reason = retained and "retained" or "retained-postcondition-failed",
			position = retained_position, scale = retained_scale,
			rotation = retained_rotation, materials = materials_ready == true,
			paint = context and context._appearance_required_paint == true,
			apply = context and context._appearance_required_apply == true,
			actual_position = actual_position,
			expected_position = copy_evidence_value(spec.position),
			actual_scale = actual_scale,
			expected_scale = copy_evidence_value(spec.scale),
			actual_rotation = actual_rotation,
			expected_rotation = copy_evidence_value(spec.rotation),
			transform_mode = transform.mode,
			transform_node = transform.node,
			transform_error = transform.error,
			rotation_constructed = transform.rotation_constructed,
			position_write = transform.position,
			scale_write = transform.scale,
			rotation_write = transform.rotation,
		}
	end

	-- A duplicate wrapper in the same call stack must never consume a retry.
	-- Recovery belongs to a distinct, source-backed lifecycle edge (for example
	-- preview construction -> loading_done), so one attempt per exact token is
	-- sufficient and deterministic.
	reconciler = D.new_reconciler({ apply = apply, observe = observe, max_attempts = 1 })

	function C.reconcile(target, surface, edge, item, explicit_mode, context)
		context = context or {}; context.item = item
		local key = canonical_key(item)
		local is_old_musket = key == policy.ITEM_KEY or policy.matches_item(item, key)
		local candidate_mode = mode_for(item, explicit_mode)
		local candidate_identity = identity_evidence(item, surface, context)
		local preview_evidence_ok, preview_evidence_reason,
			preserve_preview_evidence = true, nil, false
		if is_old_musket then
			preview_evidence_ok, preview_evidence_reason,
				preserve_preview_evidence =
				preview_lifecycle_evidence(surface, edge, candidate_identity, context)
		end
		local cim_armed = true
		if is_old_musket then
			if surface == "cim_preview" then
				cim_armed = arm_cim_identity(
					surface, candidate_identity, context.cim_generation)
			end
		end
		if not cim_armed then
			return { ok = false, reason = "identity-unresolved",
				errors = { "CIM evidence epoch rejected" } }
		end
		local selected_evidence_identity = evidence_epoch > 0 and is_old_musket
			and preview_evidence_ok
			and evidence_identity(surface, candidate_identity) or nil
		local records_active_identity = selected_evidence_identity ~= nil
		local descriptor, errors = C.resolve(item, explicit_mode, surface, context)
		if not descriptor then
			if records_active_identity then
				evidence_row(surface, candidate_mode, edge, candidate_identity, {
					retained = false, fallback = false, reason = "identity-unresolved",
					attempts = 0,
				}, target)
			end
			return { ok = false, reason = "identity-unresolved", errors = errors }
		end
		local result = reconciler.reconcile(descriptor, surface, edge, target, context)
		local data = descriptor_data(descriptor)
		local descriptor_identity = data.identity_evidence or candidate_identity
		local observation = type(result.observation) == "table"
			and result.observation or {}
		local fingerprint = D.fingerprint(descriptor)
		if evidence_epoch > 0 and is_old_musket and surface == "illusion_browser"
				and not preview_evidence_ok and not preserve_preview_evidence then
			evidence_row(surface, candidate_mode, edge, candidate_identity, {
				retained = false, fallback = false,
				reason = preview_evidence_reason, attempts = 0,
				preview_generation = context.preview_generation,
			}, target)
		elseif selected_evidence_identity
				and same_identity(selected_evidence_identity, descriptor_identity)
				and result.coalesced ~= true then
			evidence_row(surface, descriptor.mode, edge, descriptor_identity, {
				retained = result.retained == true,
				fallback = result.fallback == true,
				reason = result.reason,
				attempts = result.attempts or 0,
				fingerprint = fingerprint,
				profile = descriptor.attachment_profile,
				generation = descriptor.generation,
				paint = observation.paint,
				apply = observation.apply,
				materials = observation.materials,
				position = observation.position,
				scale = observation.scale,
				rotation = observation.rotation,
				actual_position = observation.actual_position,
				expected_position = observation.expected_position,
				actual_scale = observation.actual_scale,
				expected_scale = observation.expected_scale,
				actual_rotation = observation.actual_rotation,
				expected_rotation = observation.expected_rotation,
				transform_mode = observation.transform_mode,
				transform_node = observation.transform_node,
				transform_error = observation.transform_error,
				rotation_constructed = observation.rotation_constructed,
				position_write = observation.position_write,
				scale_write = observation.scale_write,
				rotation_write = observation.rotation_write,
				preview_generation = context.preview_generation,
			}, target)
		end
		-- One structured receipt per exact reconciler token. Duplicate wrappers can
		-- revisit this function in the same lifecycle stack, but they must neither
		-- overwrite the first observation nor produce log spam.
		if result.coalesced ~= true then
			pcall(printf_fn,
				"[cwv:1155] family=old_musket surface=%s edge=%s profile=%s fingerprint=%s retained=%s fallback=%s reason=%s attempts=%s paint=%s apply=%s materials=%s position=%s scale=%s rotation=%s transform_mode=%s transform_node=%s transform_error=%s rotation_constructed=%s position_write=%s scale_write=%s rotation_write=%s actual_position=[%s] expected_position=[%s] actual_scale=[%s] expected_scale=[%s] actual_rotation=[%s] expected_rotation=[%s] chat=false",
				tostring(surface), tostring(edge), tostring(descriptor.attachment_profile),
				fingerprint, tostring(result.retained == true),
				tostring(result.fallback == true), tostring(result.reason),
				tostring(result.attempts or 0), tostring(observation.paint),
				tostring(observation.apply), tostring(observation.materials),
				tostring(observation.position), tostring(observation.scale),
				tostring(observation.rotation),
				tostring(observation.transform_mode),
				tostring(observation.transform_node),
				tostring(observation.transform_error or "none"),
				tostring(observation.rotation_constructed),
				tostring(observation.position_write),
				tostring(observation.scale_write),
				tostring(observation.rotation_write),
				tuple_text(observation.actual_position, 3),
				tuple_text(observation.expected_position, 3),
				tuple_text(observation.actual_scale, 3),
				tuple_text(observation.expected_scale, 3),
				tuple_text(observation.actual_rotation, 4),
				tuple_text(observation.expected_rotation, 4))
		end
		return result, descriptor
	end

	function C.forget(target) return reconciler.forget(target) end
	function C.disconnect()
		tracked = setmetatable({}, { __mode = "k" })
		evidence = {}
		evidence_targets = {}
		cim_identity = nil
		held_identity = nil
		cim_generation = 0
		preview_lifecycles = {}
		evidence_epoch = evidence_epoch + 1
		return reconciler.disconnect()
	end

	-- Live regression gates compare the currently wielded 1P/3P units against
	-- the exact targets that produced the retained evidence. This prevents a
	-- prior Old Musket from passing after the player swaps to another item.
	function C.live_target_matches(surface, mode, target, identity)
		local key = tostring(surface) .. ":" .. tostring(mode)
		local row = evidence[key]
		return type(row) == "table" and row.retained == true
			and target ~= nil and evidence_targets[key] == target
			and same_identity(row.identity, identity)
	end

	function C.live_status()
		local status = { exercised = 0, retained = 0, failed = 0,
			fallback = 0, surfaces = {}, cells = {}, generation = generation,
			epoch = evidence_epoch, identity = copy_identity(held_identity),
			cim_identity = copy_identity(cim_identity),
			cim_generation = cim_generation, preview_lifecycles = {} }
		for surface, lifecycle in pairs(preview_lifecycles) do
			status.preview_lifecycles[surface] = {
				generation = lifecycle.generation,
				identity = copy_identity(lifecycle.identity),
			}
		end
		for evidence_key, row in pairs(evidence) do
			local copy = {}
			for key, value in pairs(row) do
				copy[key] = key == "identity" and copy_identity(value)
					or copy_evidence_value(value)
			end
			status.cells[evidence_key] = copy
			status.surfaces[row.surface] = status.surfaces[row.surface] or {}
			status.surfaces[row.surface][row.mode] = copy
			status.exercised = status.exercised + 1
			if row.retained then status.retained = status.retained + 1
			elseif row.fallback then status.fallback = status.fallback + 1
			else status.failed = status.failed + 1 end
		end
		return status
	end

	-- Dev tuning is an explicit generation edge, never an update-loop owner.
	function C.reapply_tracked()
		generation = generation + 1
		local applied = 0
		for target, record in pairs(tracked) do
			local alive_ok, alive = pcall(unit_api.alive, target)
			if alive_ok and alive then
				local result = C.reconcile(target, record.surface, "customize",
					record.item, record.mode, record.context)
				if result and result.retained == true then applied = applied + 1 end
			else tracked[target] = nil end
		end
		return applied
	end

	function C.preview_targets(descriptor, units, spawn_data)
		local targets = {}
		if not descriptor or type(units) ~= "table" or type(spawn_data) ~= "table" then return targets end
		descriptor = descriptor_data(descriptor)
		for index, unit in ipairs(units) do
			local path = spawn_data[index] and spawn_data[index].unit_name
			if path == descriptor.right_hand_unit.unit or path == descriptor.right_hand_unit.unit_3p then
				targets[#targets + 1] = unit
			end
		end
		return targets
	end

	C.reconciler = reconciler
	C.unit_surfaces = UNIT_SURFACES
	C.implemented_cells = IMPLEMENTED_CELLS
	return C
end

return M
