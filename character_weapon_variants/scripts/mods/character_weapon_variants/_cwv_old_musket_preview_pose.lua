-- Pure lifecycle policy for the Old Musket inventory-character pose.
--
-- HeroPreviewer spawns item units before its preview is stable. A delayed
-- menu pose may still run later in the same post-update and overwrite the
-- weapon's wield event. Keep one small pending record on the previewer and
-- consume it exactly once after vanilla raises `_loading_done`.

local M = {}

M.MAX_TOKEN = 128
M.HELD_1P_RIFLE = "held_1p_rifle"
M.HELD_1P_POLEARM = "held_1p_polearm"
M.HELD_3P_RIFLE_CHARACTER = "held_3p_rifle_character"
M.HELD_3P_POLEARM_CHARACTER = "held_3p_polearm_character"

local function valid_token(value)
	return type(value) == "string" and value ~= "" and #value <= M.MAX_TOKEN
end

local function valid_identity(value)
	return value == nil or type(value) == "number" or valid_token(value)
end

local function valid_character_attachment_recipe(value)
	return type(value) == "table" and type(value.wielded) == "table"
		and type(value.unwielded) == "table"
end

function M.resolve_spawn_slot(previewer, item_name, spawn_data)
	if type(previewer) ~= "table" or type(previewer._item_info_by_slot) ~= "table" then
		return nil, nil, "previewer_missing"
	end
	if not valid_token(item_name) or type(spawn_data) ~= "table" then
		return nil, nil, "spawn_missing"
	end
	local slot_type
	local slot_index
	for _, row in ipairs(spawn_data) do
		if type(row) == "table" and row.item_slot_type then
			if slot_type and (slot_type ~= row.item_slot_type
					or slot_index ~= row.slot_index) then
				return nil, nil, "spawn_ambiguous"
			end
			slot_type = row.item_slot_type
			slot_index = row.slot_index
		end
	end
	if slot_type ~= "melee" and slot_type ~= "ranged" then
		return nil, nil, "slot_unsupported"
	end
	local info = previewer._item_info_by_slot[slot_type]
	if type(info) ~= "table" or info.name ~= item_name then
		return nil, nil, "item_changed"
	end
	if info.spawn_data ~= spawn_data then
		return nil, nil, "spawn_changed"
	end
	return slot_type, info, slot_index
end

-- Vanilla builds dual-hand preview spawn_data in left-then-right order. Never
-- infer the rendered rifle from array position: retain the exact right-hand
-- unit path that was actually authored for this slot, and reject malformed or
-- ambiguous generations before they can be armed for the later stable edge.
function M.resolve_right_hand_spawn_row(info, slot_type, expected_unit_name)
	if type(info) ~= "table" or type(info.spawn_data) ~= "table" then
		return nil, "spawn_missing"
	end
	if slot_type ~= "melee" and slot_type ~= "ranged" then
		return nil, "slot_unsupported"
	end
	if expected_unit_name ~= nil and not valid_token(expected_unit_name) then
		return nil, "unit_invalid"
	end

	local match
	for _, row in ipairs(info.spawn_data) do
		if type(row) == "table" and row.right_hand == true
				and row.item_slot_type == slot_type then
			if type(row.slot_index) ~= "number" then
				return nil, "slot_invalid"
			end
			if not valid_token(row.unit_name) then
				return nil, "unit_invalid"
			end
			if match then
				return nil, "spawn_ambiguous"
			end
			match = row
		end
	end

	if not match then
		return nil, "unit_missing"
	end
	if expected_unit_name ~= nil and match.unit_name ~= expected_unit_name then
		return nil, "unit_changed"
	end
	return match, "ready"
end

-- The character previewer links the spawned unit through the exact
-- `unit_attachment_node_linking` table stored on this row. Classify that real
-- parent-frame evidence; stance alone is not enough to select a transform.
function M.resolve_character_attachment_profile(row, stance, rifle_linking,
		polearm_linking, profiles)
	if type(row) ~= "table"
			or not valid_character_attachment_recipe(row.unit_attachment_node_linking) then
		return nil, "attachment_missing"
	end
	if stance ~= "ranged" and stance ~= "melee" then
		return nil, "stance_invalid"
	end
	if not valid_character_attachment_recipe(rifle_linking)
			or not valid_character_attachment_recipe(polearm_linking) then
		return nil, "attachment_recipe_missing"
	end
	if rifle_linking == polearm_linking then
		return nil, "attachment_recipe_ambiguous"
	end
	local rifle_profile = profiles and profiles.held_3p_rifle_character
		or M.HELD_3P_RIFLE_CHARACTER
	local polearm_profile = profiles and profiles.held_3p_polearm_character
		or M.HELD_3P_POLEARM_CHARACTER
	if rifle_profile ~= M.HELD_3P_RIFLE_CHARACTER
			or polearm_profile ~= M.HELD_3P_POLEARM_CHARACTER then
		return nil, "attachment_profile_invalid"
	end
	local observed = row.unit_attachment_node_linking
	local selected = observed == rifle_linking and rifle_profile
		or (observed == polearm_linking and polearm_profile) or nil
	if not selected then
		return nil, "attachment_unknown"
	end
	local expected = stance == "melee" and polearm_profile or rifle_profile
	if selected ~= expected then
		return nil, "attachment_stance_mismatch"
	end
	return selected, "ready"
end

-- Held gameplay units receive their parent frame from the exact item template
-- GearUtils stored on slot_data. Stance state alone is not evidence that a
-- rifle or polearm recipe was actually selected, so admit a transform profile
-- only when the live template is the registered stance clone and its concrete
-- per-perspective attachment recipe has the complete engine shape.
function M.resolve_held_attachment_profile(template, perspective, stance,
		weapons, profiles)
	if perspective ~= "1p" and perspective ~= "3p" then
		return nil, "perspective_invalid"
	end
	if stance ~= "ranged" and stance ~= "melee" then
		return nil, "stance_invalid"
	end
	if type(weapons) ~= "table" then return nil, "weapons_missing" end
	local expected = stance == "melee"
		and rawget(weapons, "old_musket_template_melee")
		or rawget(weapons, "old_musket_template")
	if type(expected) ~= "table" or template ~= expected then
		return nil, "template_stance_mismatch"
	end
	local linking = template.right_hand_attachment_node_linking
	local recipe = type(linking) == "table" and linking[
		perspective == "1p" and "first_person" or "third_person"] or nil
	if not valid_character_attachment_recipe(recipe) then
		return nil, "attachment_recipe_missing"
	end
	local selected
	if perspective == "1p" then
		selected = stance == "melee" and (profiles and profiles.held_1p_polearm)
			or (profiles and profiles.held_1p_rifle)
		local expected_profile = stance == "melee"
			and M.HELD_1P_POLEARM or M.HELD_1P_RIFLE
		if selected ~= expected_profile then return nil, "attachment_profile_invalid" end
	else
		selected = stance == "melee"
			and (profiles and profiles.held_3p_polearm_character)
			or (profiles and profiles.held_3p_rifle_character)
		local expected_profile = stance == "melee"
			and M.HELD_3P_POLEARM_CHARACTER or M.HELD_3P_RIFLE_CHARACTER
		if selected ~= expected_profile then return nil, "attachment_profile_invalid" end
	end
	return selected, "ready"
end

function M.resolve_wield_event(template, career_name)
	if type(template) ~= "table" then return nil end
	local by_3p = career_name and type(template.wield_anim_career_3p) == "table"
		and template.wield_anim_career_3p[career_name]
	local by_career = career_name and type(template.wield_anim_career) == "table"
		and template.wield_anim_career[career_name]
	return by_3p or by_career or template.wield_anim
end

-- SimpleHuskInventoryExtension has a distinct source precedence from the Hero
-- previewer above: its generic 3P event outranks the career-generic event.
function M.resolve_husk_wield_event(template, career_name)
	if type(template) ~= "table" then return nil end
	local by_3p = career_name and type(template.wield_anim_career_3p) == "table"
		and template.wield_anim_career_3p[career_name]
	local by_career = career_name and type(template.wield_anim_career) == "table"
		and template.wield_anim_career[career_name]
	return by_3p or template.wield_anim_3p or by_career or template.wield_anim
end

function M.arm(previewer, record)
	if type(previewer) ~= "table" or type(record) ~= "table" then
		return false
	end
	if (record.slot_type ~= "melee" and record.slot_type ~= "ranged")
			or (record.stance ~= "melee" and record.stance ~= "ranged")
			or record.character_unit == nil
			or not valid_token(record.item_name) or not valid_token(record.unit_name)
			or not valid_token(record.wield_event)
			or not valid_identity(record.backend_id) or type(record.slot_index) ~= "number"
			or not valid_character_attachment_recipe(record.attachment_node_linking) then
		return false
	end
	local expected_profile = record.stance == "melee"
		and M.HELD_3P_POLEARM_CHARACTER or M.HELD_3P_RIFLE_CHARACTER
	if record.attachment_profile ~= expected_profile then
		return false
	end
	-- Copy the closed schema; never retain a caller-owned item/spawn table. The
	-- one table-valued field is the immutable registered template recipe itself,
	-- retained only as opaque identity so the stable edge can detect relinking.
	previewer._cwv_old_musket_pose_pending = {
		character_unit = record.character_unit,
		item_name = record.item_name,
		backend_id = record.backend_id,
		slot_type = record.slot_type,
		slot_index = record.slot_index,
		stance = record.stance,
		surface = record.surface,
		attachment_profile = record.attachment_profile,
		attachment_node_linking = record.attachment_node_linking,
		unit_name = record.unit_name,
		wield_event = record.wield_event,
	}
	return true
end

function M.take_when_stable(previewer, stable)
	if type(previewer) ~= "table" then
		return nil, "previewer_missing"
	end

	local pending = previewer._cwv_old_musket_pose_pending
	if type(pending) ~= "table" then
		return nil, "not_armed"
	end
	if not stable then
		return nil, "loading"
	end

	-- A stable edge is terminal for this generation. Consume before checking
	-- identity so a stale request can never replay on a later item or character.
	previewer._cwv_old_musket_pose_pending = nil

	if previewer.character_unit ~= pending.character_unit then
		return nil, "character_changed"
	end
	if previewer._wielded_slot_type ~= pending.slot_type then
		return nil, "slot_changed"
	end

	local live = previewer._item_info_by_slot
		and previewer._item_info_by_slot[pending.slot_type]
	if type(live) ~= "table" then
		return nil, "item_missing"
	end
	if live.name ~= pending.item_name then
		return nil, "item_changed"
	end
	if pending.backend_id ~= nil and live.backend_id ~= pending.backend_id then
		return nil, "backend_changed"
	end
	local spawn_row, spawn_reason = M.resolve_right_hand_spawn_row(
		live, pending.slot_type, pending.unit_name)
	if not spawn_row then
		return nil, spawn_reason
	end
	if spawn_row.slot_index ~= pending.slot_index then
		return nil, "slot_changed"
	end
	if spawn_row.unit_attachment_node_linking ~= pending.attachment_node_linking then
		return nil, "attachment_changed"
	end

	return pending, "ready"
end

function M.install(mod, apply_transform, print_fn, debug_fn)
	-- `_spawn_item` runs inside `_poll_item_package_loading`, after vanilla's
	-- visibility pass. Consume the exact pending record once on vanilla's final
	-- `_loading_done` edge, then make both the pose and item transform the final
	-- bounded writers for this preview generation.
	local function on_update_units_visibility(func, self, dt)
		local was_loading_done = self._loading_done
		local result = func(self, dt)
		if not was_loading_done and self._loading_done then
			local pending, reason = M.take_when_stable(self, true)
			if pending then
				if Unit.alive(pending.character_unit) then
					local pose_ok, pose_error = pcall(
						Unit.animation_event, pending.character_unit, pending.wield_event)
					local slot = self._equipment_units
						and self._equipment_units[pending.slot_index]
					local weapon_unit = type(slot) == "table" and slot.right
					if weapon_unit and Unit.alive(weapon_unit) and apply_transform then
						local apply_ok, appearance = pcall(apply_transform,
							weapon_unit, "3p", pending.stance, pending)
						if apply_ok and appearance and appearance.retained == true then
							pcall(print_fn,
								"[cwv:474/792] preview transform retained slot=%s bid=%s mode=%s edge=loading_done",
								tostring(pending.slot_index), tostring(pending.backend_id),
								tostring(pending.stance))
						elseif debug_fn then
							debug_fn("[cwv:474/792] preview transform rejected reason=%s",
								tostring(apply_ok and appearance and appearance.reason
									or (apply_ok and "no-retained-report" or appearance)))
						end
					elseif debug_fn then
						debug_fn("[cwv:474/792] preview transform skipped reason=weapon_missing")
					end
					pcall(print_fn,
						"[cwv:792] preview pose attempted slot=%s bid=%s mode=%s anim=%s edge=loading_done dispatched=%s error=%s",
						tostring(pending.slot_index), tostring(pending.backend_id),
						tostring(pending.stance), tostring(pending.wield_event),
						tostring(pose_ok == true), tostring(pose_error))
				elseif debug_fn then
					debug_fn("[cwv:792] preview pose skipped reason=character_dead")
				end
			elseif reason ~= "not_armed" and debug_fn then
				debug_fn("[cwv:792] preview pose skipped reason=%s", tostring(reason))
			end
		end
		return result
	end

	-- #474 base-class hook trap: the keep inventory previewer is
	-- MenuWorldPreviewer, whose methods are COPIES of HeroPreviewer taken at
	-- class-definition time (foundation/scripts/util/class.lua:51-57), and its
	-- own `_update_units_visibility` override (menu_world_previewer.lua:315)
	-- can early-return without reaching the base entry. Register the SAME
	-- consume-once callback on BOTH classes (repo doctrine: hook the derived
	-- class, never only the base). Double delivery on one update is safe:
	-- `take_when_stable` consumes the pending record on the first stable edge
	-- and reports `not_armed` to the second wrapper.
	-- Pre-flight (CLAUDE.md NON-NEGOTIABLE #8): CWV's only other hooks on
	-- these classes are `equip_item` (hook_safe), `_spawn_item`, and
	-- `_load_packages` -- these are the sole CWV hooks on
	-- (HeroPreviewer, _update_units_visibility) and
	-- (MenuWorldPreviewer, _update_units_visibility).
	mod:hook("HeroPreviewer", "_update_units_visibility", on_update_units_visibility)
	mod:hook("MenuWorldPreviewer", "_update_units_visibility", on_update_units_visibility)
end

return M
