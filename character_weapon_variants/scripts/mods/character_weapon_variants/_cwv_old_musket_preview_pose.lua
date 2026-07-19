-- Pure lifecycle policy for the Old Musket inventory-character pose.
--
-- HeroPreviewer spawns item units before its preview is stable. A delayed
-- menu pose may still run later in the same post-update and overwrite the
-- weapon's wield event. Keep one small pending record on the previewer and
-- consume it exactly once after vanilla raises `_loading_done`.

local M = {}

M.MAX_TOKEN = 128

local function valid_token(value)
	return type(value) == "string" and value ~= "" and #value <= M.MAX_TOKEN
end

local function valid_identity(value)
	return value == nil or type(value) == "number" or valid_token(value)
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

function M.resolve_wield_event(template, career_name)
	if type(template) ~= "table" then return nil end
	local by_3p = career_name and type(template.wield_anim_career_3p) == "table"
		and template.wield_anim_career_3p[career_name]
	local by_career = career_name and type(template.wield_anim_career) == "table"
		and template.wield_anim_career[career_name]
	return by_3p or by_career or template.wield_anim
end

function M.arm(previewer, record)
	if type(previewer) ~= "table" or type(record) ~= "table" then
		return false
	end
	if (record.slot_type ~= "melee" and record.slot_type ~= "ranged")
			or (record.stance ~= "melee" and record.stance ~= "ranged")
			or record.character_unit == nil
			or not valid_token(record.item_name) or not valid_token(record.wield_event)
			or not valid_identity(record.backend_id) or type(record.slot_index) ~= "number" then
		return false
	end
	-- Copy the closed schema; never retain a caller-owned item/spawn table.
	previewer._cwv_old_musket_pose_pending = {
		character_unit = record.character_unit,
		item_name = record.item_name,
		backend_id = record.backend_id,
		slot_type = record.slot_type,
		slot_index = record.slot_index,
		stance = record.stance,
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

	return pending, "ready"
end

return M
