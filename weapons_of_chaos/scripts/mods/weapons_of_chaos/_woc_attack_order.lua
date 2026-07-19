-- Custom-weapon attack-order picker (pure module, no VMF/mod upvalues).
--
-- Given a WEAPON DESCRIPTOR and the author's dropdown selections, this module
-- produces and applies a PERMUTATION PLAN over a private weapon-template clone
-- (first consumer: the Blightreaper's `woc_blightreaper_template`; CWV weapons
-- register additional descriptors later via `M.register`).
--
-- MODEL
--   The chain graph is a fixed ring of CHARGE NODES (chain positions). Each
--   position offers one light release and one heavy release; each attack's
--   `allowed_chain_actions` names the NEXT charge node. The picker never edits
--   that wiring: `allowed_chain_actions`, `lookup_data`, `kind`,
--   `attack_hold_input`, and any `condition_func` stay with the POSITION
--   (M.PRESERVED_FIELDS). Everything else on an attack sub_action - anim_event,
--   anim_event_3p, anim_time_scale, damage profile and windows, baked_sweep,
--   buff_data, impact identity, aim assist - is the attack UNIT's payload and
--   moves as one indivisible block (never split). A heavy unit is the PAIR of
--   its release payload plus its native charge node's windup `anim_event`;
--   installing a heavy at a position also writes that windup into every charge
--   node that winds into the position, so charge and release always match.
--
-- APPLY DISCIPLINE
--   Sub_action TABLES are never replaced, only their fields are rewritten, so
--   engine-side references stay valid and a re-apply is visible immediately.
--   The pristine post-install payloads are captured ONCE and stored on the
--   template under M.BASELINE_KEY; every apply copies from that baseline, so
--   applies are idempotent, order-independent, and survive a VMF mod reload
--   (the baseline rides the template table in `Weapons`). Validation fails
--   closed: any unknown unit id, missing slot, or malformed descriptor returns
--   nil+reason BEFORE any mutation.
--
-- TRANSITIONS (design data layer; editing UI intentionally not shipped yet)
--   `descriptor.transitions` is the after-state map: keyed by what just
--   happened (entry, after_light[i], after_heavy[j], after_push_attack), the
--   value names the NEXT chain position (1..#positions). It mirrors the live
--   `allowed_chain_actions` wiring; `M.derive_transitions` re-reads the live
--   template so drift is detectable, and `M.describe_chains` renders the map in
--   plain English for the /woc_chains command. A future transition EDITOR
--   rewrites the continuation rows (`action == descriptor.action` entries)
--   inside `allowed_chain_actions` to retarget after-states; the preserved-
--   fields split above means that editor composes cleanly with this picker
--   (payloads and wiring are already independent layers). Note one topology
--   fact the editor must surface: chain positions may SHARE a heavy sub_action
--   (crowbill positions 2 and 4 both fire heavy slot 2), so their heavy exit is
--   necessarily shared until the editor clones the shared slot.

local M = {}

M.BASELINE_KEY = "woc_attack_order_baseline"

-- Position wiring: never moves between sub_actions.
M.PRESERVED_FIELDS = {
	allowed_chain_actions = true,
	lookup_data = true,
	kind = true,
	attack_hold_input = true,
	chain_condition_func = true,
	condition_func = true,
}

local function _copy_value(value, depth)
	if type(value) ~= "table" then return value end
	depth = (depth or 0) + 1
	if depth > 12 then return value end
	local copy = {}
	for key, child in pairs(value) do
		copy[key] = _copy_value(child, depth)
	end
	return copy
end

local function _units_by_id(units)
	local map = {}
	for i = 1, #units do map[units[i].id] = units[i] end
	return map
end

-- ============================================================
-- Descriptor validation (fails closed)
-- ============================================================

local function _validate_units(units, pool, need_charge)
	if type(units) ~= "table" or #units == 0 then
		return nil, pool .. "_units_missing"
	end
	local ids, slots = {}, {}
	for i = 1, #units do
		local unit = units[i]
		if type(unit) ~= "table" or type(unit.id) ~= "string"
				or type(unit.slot) ~= "string" then
			return nil, pool .. "_unit_" .. i .. "_malformed"
		end
		if ids[unit.id] then return nil, pool .. "_duplicate_id:" .. unit.id end
		if slots[unit.slot] then return nil, pool .. "_duplicate_slot:" .. unit.slot end
		if need_charge and type(unit.charge_slot) ~= "string" then
			return nil, pool .. "_unit_missing_charge_slot:" .. unit.id
		end
		ids[unit.id] = true
		slots[unit.slot] = true
	end
	return true
end

local function _validate_positions(positions, by_id, pool, count_key)
	if type(positions) ~= "table" or #positions == 0 then
		return nil, pool .. "_positions_missing"
	end
	for i = 1, #positions do
		local native = positions[i]
		local native_id = type(native) == "table" and native.native or native
		if type(native_id) ~= "string" or not by_id[native_id] then
			return nil, pool .. "_position_" .. i .. "_unknown_native:"
				.. tostring(native_id)
		end
	end
	return true
end

function M.validate_descriptor(descriptor)
	if type(descriptor) ~= "table" then return nil, "descriptor_not_a_table" end
	if type(descriptor.template_name) ~= "string" then return nil, "template_name_missing" end
	if type(descriptor.action) ~= "string" then return nil, "action_missing" end
	local ok, reason = _validate_units(descriptor.lights, "light", false)
	if not ok then return nil, reason end
	ok, reason = _validate_units(descriptor.heavies, "heavy", true)
	if not ok then return nil, reason end
	ok, reason = _validate_units(descriptor.push, "push", false)
	if not ok then return nil, reason end
	local lights_by_id = _units_by_id(descriptor.lights)
	local heavies_by_id = _units_by_id(descriptor.heavies)
	local push_by_id = _units_by_id(descriptor.push)
	ok, reason = _validate_positions(descriptor.light_positions, lights_by_id, "light")
	if not ok then return nil, reason end
	ok, reason = _validate_positions(descriptor.heavy_positions, heavies_by_id, "heavy")
	if not ok then return nil, reason end
	ok, reason = _validate_positions(descriptor.push_positions, push_by_id, "push")
	if not ok then return nil, reason end
	if type(descriptor.charge_nodes) ~= "table"
			or #descriptor.charge_nodes ~= #descriptor.light_positions then
		return nil, "charge_nodes_mismatch"
	end
	for i = 1, #descriptor.heavy_positions do
		local pos = descriptor.heavy_positions[i]
		if type(pos) ~= "table" or type(pos.charge_slots) ~= "table"
				or #pos.charge_slots == 0 then
			return nil, "heavy_position_" .. i .. "_charge_slots_missing"
		end
	end
	local transitions = descriptor.transitions
	if type(transitions) ~= "table" then return nil, "transitions_missing" end
	local position_count = #descriptor.light_positions
	local function in_range(value) return type(value) == "number"
		and value >= 1 and value <= position_count and value % 1 == 0 end
	if not in_range(transitions.entry) then return nil, "transitions_entry_invalid" end
	if type(transitions.after_light) ~= "table"
			or #transitions.after_light ~= position_count then
		return nil, "transitions_after_light_invalid"
	end
	for i = 1, position_count do
		if not in_range(transitions.after_light[i]) then
			return nil, "transitions_after_light_" .. i .. "_invalid"
		end
	end
	if type(transitions.after_heavy) ~= "table"
			or #transitions.after_heavy ~= #descriptor.heavy_positions then
		return nil, "transitions_after_heavy_invalid"
	end
	for i = 1, #descriptor.heavy_positions do
		if not in_range(transitions.after_heavy[i]) then
			return nil, "transitions_after_heavy_" .. i .. "_invalid"
		end
	end
	if not in_range(transitions.after_push_attack) then
		return nil, "transitions_after_push_attack_invalid"
	end
	return true
end

-- ============================================================
-- Plan building (pure; nil selection entries fall back to native)
-- ============================================================

local function _position_native(position)
	return type(position) == "table" and position.native or position
end

function M.native_selections(descriptor)
	local selections = { lights = {}, heavies = {}, push = {} }
	for i = 1, #descriptor.light_positions do
		selections.lights[i] = _position_native(descriptor.light_positions[i])
	end
	for i = 1, #descriptor.heavy_positions do
		selections.heavies[i] = _position_native(descriptor.heavy_positions[i])
	end
	for i = 1, #descriptor.push_positions do
		selections.push[i] = _position_native(descriptor.push_positions[i])
	end
	return selections
end

local function _plan_pool(positions, by_id, chosen, pool)
	local out = {}
	for i = 1, #positions do
		local native_id = _position_native(positions[i])
		local pick = chosen and chosen[i]
		if pick == nil then pick = native_id end
		if not by_id[pick] then
			return nil, "unknown_" .. pool .. "_unit:" .. tostring(pick)
		end
		out[i] = pick
	end
	return out
end

function M.build_plan(descriptor, selections)
	local ok, reason = M.validate_descriptor(descriptor)
	if not ok then return nil, reason end
	selections = type(selections) == "table" and selections or {}
	local lights, err = _plan_pool(descriptor.light_positions,
		_units_by_id(descriptor.lights), selections.lights, "light")
	if not lights then return nil, err end
	local heavies, heavy_err = _plan_pool(descriptor.heavy_positions,
		_units_by_id(descriptor.heavies), selections.heavies, "heavy")
	if not heavies then return nil, heavy_err end
	local push, push_err = _plan_pool(descriptor.push_positions,
		_units_by_id(descriptor.push), selections.push, "push")
	if not push then return nil, push_err end
	local identity = true
	for i = 1, #lights do
		if lights[i] ~= _position_native(descriptor.light_positions[i]) then identity = false end
	end
	for i = 1, #heavies do
		if heavies[i] ~= _position_native(descriptor.heavy_positions[i]) then identity = false end
	end
	for i = 1, #push do
		if push[i] ~= _position_native(descriptor.push_positions[i]) then identity = false end
	end
	return { lights = lights, heavies = heavies, push = push, identity = identity }
end

-- ============================================================
-- Baseline capture + payload install
-- ============================================================

local function _action_table(template, descriptor)
	local actions = type(template) == "table" and type(template.actions) == "table"
		and template.actions[descriptor.action]
	if type(actions) ~= "table" then return nil, "action_table_missing:" .. descriptor.action end
	return actions
end

local function _capture_payload(sub_action)
	local payload = {}
	for key, value in pairs(sub_action) do
		if not M.PRESERVED_FIELDS[key] then
			payload[key] = _copy_value(value)
		end
	end
	return payload
end

-- Captures every unit's pristine payload plus each heavy's charge windup.
function M.capture_baseline(template, descriptor)
	local actions, reason = _action_table(template, descriptor)
	if not actions then return nil, reason end
	local baseline = { payloads = {}, charge = {} }
	local pools = { descriptor.lights, descriptor.heavies, descriptor.push }
	for p = 1, #pools do
		for i = 1, #pools[p] do
			local unit = pools[p][i]
			local sub_action = actions[unit.slot]
			if type(sub_action) ~= "table" then
				return nil, "slot_missing:" .. unit.slot
			end
			baseline.payloads[unit.slot] = _capture_payload(sub_action)
			if unit.charge_slot then
				local charge = actions[unit.charge_slot]
				if type(charge) ~= "table" then
					return nil, "charge_slot_missing:" .. unit.charge_slot
				end
				baseline.charge[unit.charge_slot] = {
					anim_event = charge.anim_event,
					anim_event_3p = charge.anim_event_3p,
				}
			end
		end
	end
	return baseline
end

-- Rewrites target's fields from the baseline payload. Never replaces the
-- table; clears stale non-preserved fields (nil-able payload members such as
-- anim_event_3p / sweep_z_offset must not leak between units).
local function _install_payload(target, payload)
	for key in pairs(target) do
		if not M.PRESERVED_FIELDS[key] and payload[key] == nil then
			target[key] = nil
		end
	end
	for key, value in pairs(payload) do
		if not M.PRESERVED_FIELDS[key] then
			target[key] = _copy_value(value)
		end
	end
end

-- Applies `selections` to the live template. Fail-closed: validates and plans
-- before the first write; a nil return means the template was not touched.
function M.apply(template, descriptor, selections)
	local plan, reason = M.build_plan(descriptor, selections)
	if not plan then return nil, reason end
	local actions, actions_reason = _action_table(template, descriptor)
	if not actions then return nil, actions_reason end
	local baseline = template[M.BASELINE_KEY]
	if type(baseline) ~= "table" then
		local captured, capture_reason = M.capture_baseline(template, descriptor)
		if not captured then return nil, capture_reason end
		baseline = captured
	end
	-- Verify every write target/source before mutating anything.
	local lights_by_id = _units_by_id(descriptor.lights)
	local heavies_by_id = _units_by_id(descriptor.heavies)
	local push_by_id = _units_by_id(descriptor.push)
	local writes = {}
	for i = 1, #plan.lights do
		local position_slot = lights_by_id[_position_native(descriptor.light_positions[i])].slot
		local unit = lights_by_id[plan.lights[i]]
		if type(actions[position_slot]) ~= "table" then
			return nil, "slot_missing:" .. position_slot
		end
		if not baseline.payloads[unit.slot] then
			return nil, "baseline_missing:" .. unit.slot
		end
		writes[#writes + 1] = { target = position_slot, source = unit.slot }
	end
	for i = 1, #plan.heavies do
		local position = descriptor.heavy_positions[i]
		local position_slot = heavies_by_id[_position_native(position)].slot
		local unit = heavies_by_id[plan.heavies[i]]
		if type(actions[position_slot]) ~= "table" then
			return nil, "slot_missing:" .. position_slot
		end
		if not baseline.payloads[unit.slot] then
			return nil, "baseline_missing:" .. unit.slot
		end
		local windup = baseline.charge[unit.charge_slot]
		if not windup then return nil, "charge_baseline_missing:" .. unit.charge_slot end
		for c = 1, #position.charge_slots do
			if type(actions[position.charge_slots[c]]) ~= "table" then
				return nil, "charge_slot_missing:" .. position.charge_slots[c]
			end
		end
		writes[#writes + 1] = { target = position_slot, source = unit.slot,
			charge_slots = position.charge_slots, windup = windup }
	end
	for i = 1, #plan.push do
		local position_slot = push_by_id[_position_native(descriptor.push_positions[i])].slot
		local unit = push_by_id[plan.push[i]]
		if type(actions[position_slot]) ~= "table" then
			return nil, "slot_missing:" .. position_slot
		end
		if not baseline.payloads[unit.slot] then
			return nil, "baseline_missing:" .. unit.slot
		end
		writes[#writes + 1] = { target = position_slot, source = unit.slot }
	end
	-- All checks passed: commit. Store the baseline first so a mutated template
	-- can always be restored from it (survives VMF reload via `Weapons`).
	template[M.BASELINE_KEY] = baseline
	for i = 1, #writes do
		local write = writes[i]
		_install_payload(actions[write.target], baseline.payloads[write.source])
		if write.charge_slots then
			for c = 1, #write.charge_slots do
				local charge = actions[write.charge_slots[c]]
				charge.anim_event = write.windup.anim_event
				charge.anim_event_3p = write.windup.anim_event_3p
			end
		end
	end
	return { ok = true, identity = plan.identity, writes = #writes, plan = plan }
end

-- ============================================================
-- Transitions: live derivation + plain-English rendering
-- ============================================================

local function _charge_position(descriptor, charge_name)
	for i = 1, #descriptor.charge_nodes do
		if descriptor.charge_nodes[i] == charge_name then return i end
	end
	return nil
end

local function _next_position(descriptor, sub_action)
	local rows = type(sub_action) == "table" and sub_action.allowed_chain_actions
	if type(rows) ~= "table" then return nil end
	for i = 1, #rows do
		local row = rows[i]
		if type(row) == "table" and row.action == descriptor.action then
			local position = _charge_position(descriptor, row.sub_action)
			if position then return position end
		end
	end
	return nil
end

-- Reads the live wiring back out of the template (drift detector for the
-- descriptor.transitions data layer; also feeds /woc_chains).
function M.derive_transitions(template, descriptor)
	local actions, reason = _action_table(template, descriptor)
	if not actions then return nil, reason end
	local lights_by_id = _units_by_id(descriptor.lights)
	local heavies_by_id = _units_by_id(descriptor.heavies)
	local push_by_id = _units_by_id(descriptor.push)
	local derived = {
		entry = descriptor.transitions and descriptor.transitions.entry or 1,
		after_light = {},
		after_heavy = {},
	}
	for i = 1, #descriptor.light_positions do
		local slot = lights_by_id[_position_native(descriptor.light_positions[i])].slot
		derived.after_light[i] = _next_position(descriptor, actions[slot])
	end
	for i = 1, #descriptor.heavy_positions do
		local slot = heavies_by_id[_position_native(descriptor.heavy_positions[i])].slot
		derived.after_heavy[i] = _next_position(descriptor, actions[slot])
	end
	local push_slot = push_by_id[_position_native(descriptor.push_positions[1])].slot
	derived.after_push_attack = _next_position(descriptor, actions[push_slot])
	return derived
end

-- Plain-English chain map for /woc_chains. `label_fn(loc_key)` localizes unit
-- labels (tests pass identity). Reads the LIVE wiring, not the descriptor.
function M.describe_chains(template, descriptor, selections, label_fn)
	label_fn = label_fn or tostring
	local transitions, reason = M.derive_transitions(template, descriptor)
	if not transitions then return nil, reason end
	local plan, plan_reason = M.build_plan(descriptor, selections)
	if not plan then return nil, plan_reason end
	local lights_by_id = _units_by_id(descriptor.lights)
	local heavies_by_id = _units_by_id(descriptor.heavies)
	local push_by_id = _units_by_id(descriptor.push)
	local function unit_label(by_id, id)
		local unit = by_id[id]
		return unit and label_fn(unit.label or unit.id) or tostring(id)
	end
	-- Which heavy position serves each chain position (positions can share one).
	local heavy_position_for = {}
	for j = 1, #descriptor.heavy_positions do
		local pos = descriptor.heavy_positions[j]
		for c = 1, #pos.charge_slots do
			local position = _charge_position(descriptor, pos.charge_slots[c])
			if position then heavy_position_for[position] = j end
		end
	end
	local lines = {}
	lines[#lines + 1] = string.format(
		"Chain entry: attacks start at position %d.", transitions.entry)
	for i = 1, #descriptor.light_positions do
		local heavy_j = heavy_position_for[i]
		local heavy_text = "no heavy"
		if heavy_j then
			heavy_text = string.format("heavy %d \"%s\" then position %s", heavy_j,
				unit_label(heavies_by_id, plan.heavies[heavy_j]),
				tostring(transitions.after_heavy[heavy_j]))
		end
		lines[#lines + 1] = string.format(
			"Position %d: light \"%s\" then position %s; %s.",
			i, unit_label(lights_by_id, plan.lights[i]),
			tostring(transitions.after_light[i]), heavy_text)
	end
	lines[#lines + 1] = string.format(
		"Push follow-up: \"%s\" then position %s.",
		unit_label(push_by_id, plan.push[1]),
		tostring(transitions.after_push_attack))
	return lines
end

-- ============================================================
-- Registry for reuse (WoC today, CWV weapons later)
-- ============================================================

local _registry = {}

function M.register(descriptor)
	local ok, reason = M.validate_descriptor(descriptor)
	if not ok then return nil, reason end
	_registry[descriptor.template_name] = descriptor
	return true
end

function M.get(template_name)
	return _registry[template_name]
end

function M.registered_names()
	local names = {}
	for name in pairs(_registry) do names[#names + 1] = name end
	table.sort(names)
	return names
end

return M
