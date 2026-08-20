local function install(mod, ctx)
	local _om = assert(ctx.om, "cwv world equipment owner requires om")
	local _dbg = assert(ctx.dbg, "cwv world equipment owner requires dbg")
	local _resolve_field = assert(ctx.resolve_field,
		"cwv world equipment owner requires resolve_field")
	local _apply_cwv_hand_transform = assert(ctx.apply_cwv_hand_transform,
		"cwv world equipment owner requires apply_cwv_hand_transform")
	local _transform_consumers = assert(_om._cwv_transform_consumers,
		"cwv world equipment owner requires transform consumer contract")
	_om._cwv_world_transform_decision = function(item_data, skin, resolved_unit_name)
		return _transform_consumers.world(item_data, skin, resolved_unit_name)
	end

	local _crowbill_transform_miss_seen = {}
	local _crowbill_transform_miss_total = 0
	local _post_native_error_seen = {}
	local _post_native_error_count = 0
	local function _run_post_native(stage, callback)
		local ok, first, second, third = pcall(callback)
		if not ok then
			local token = tostring(stage) .. ":" .. tostring(first)
			if not _post_native_error_seen[token] and _post_native_error_count < 16 then
				_post_native_error_seen[token] = true
				_post_native_error_count = _post_native_error_count + 1
				pcall(printf,
					"[cwv:1155] post-native auxiliary failed surface=create_equipment stage=%s error=%s native_result_preserved=true count=%d/16 chat=false",
					tostring(stage), tostring(first), _post_native_error_count)
			end
		end
		return ok, first, second, third
	end
	_om._appearance_world_seen = setmetatable({}, { __mode = "k" })
	mod:hook("GearUtils", "create_equipment", function(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
		local result = func(world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
		if not result then return result end

		local item_mod_data = type(item_data) == "table"
			and type(item_data.mod_data) == "table" and item_data.mod_data or nil
		local backend_id = type(item_data) == "table"
			and (item_data.backend_id or (item_mod_data and item_mod_data.backend_id))
		local key_ok, cwv_key = _run_post_native("key", function()
			return _om._cwv_key_for_item(backend_id, item_data)
		end)
		if not key_ok then return result end
		local descriptor
		if cwv_key then
			local reason
			local descriptor_ok, _
			descriptor_ok, descriptor, _, reason = _run_post_native("descriptor", function()
				return _om._cwv_resolve_world_descriptor(item_data,
					result.skin, result.right_hand_unit_name, cwv_key, backend_id)
			end)
			if not descriptor_ok then
				_run_post_native("fade_after_descriptor_error", function()
					return _om.appearance_fade.created(unit_3p, result, is_bot)
				end)
				return result
			end
			if not descriptor then
				pcall(printf,
					"[cwv:660] lifecycle=world_spawn adapter=%s descriptor=DECLINED key=%s skin=%s reason=%s",
					is_bot and "bot" or "owner", tostring(cwv_key),
					tostring(result.skin), tostring(reason))
				_run_post_native("fade_after_descriptor_declined", function()
					return _om.appearance_fade.created(unit_3p, result, is_bot)
				end)
				return result
			end
			local observed_unit = result.right_unit_3p or result.left_unit_3p
			if observed_unit and not _om._appearance_world_seen[observed_unit] then
				_om._appearance_world_seen[observed_unit] = descriptor.fingerprint
				pcall(printf,
					"[cwv:660] lifecycle=world_spawn adapter=%s slot=%s descriptor=%s right=%s left=%s",
					is_bot and "bot" or "owner", tostring(slot_name),
					tostring(descriptor.fingerprint), tostring(descriptor.right_hand_unit),
					tostring(descriptor.left_hand_unit))
			end
		end
		-- #1155: Old Musket's descriptor is the sole model/material/pose writer.
		-- Construction owns `instance_load`; post-wield supplies the distinct
		-- stable `equip` edge. Bypass the generic transform writer entirely.
		if cwv_key == "cwv_es_musket_old" then
			local musket_mode = item_mod_data
				and item_mod_data.cwv_musket_stance or "ranged"
			local profile_1p_ok, profile_1p, reason_1p = _run_post_native(
				"profile_owner_1p", function()
					return _om._old_musket_held_profile(
						result.item_template, "1p", musket_mode)
				end)
			if not profile_1p_ok then
				profile_1p, reason_1p = nil, "auxiliary_error"
			end
			local profile_3p_ok, profile_3p, reason_3p = _run_post_native(
				is_bot and "profile_bot" or "profile_owner_3p", function()
					return _om._old_musket_held_profile(
						result.item_template, "3p", musket_mode)
				end)
			if not profile_3p_ok then
				profile_3p, reason_3p = nil, "auxiliary_error"
			end
			local observed_3p_name = result.right_hand_unit_name
			if type(observed_3p_name) == "string"
					and observed_3p_name:sub(-3) ~= "_3p" then
				observed_3p_name = observed_3p_name .. "_3p"
			end
			if not is_bot and profile_1p then
				_run_post_native("reconcile_owner_1p", function()
					return _om.old_musket_appearance.reconcile(result.right_unit_1p,
						"owner_1p", "instance_load", item_data, musket_mode,
						{ unit_name = result.right_hand_unit_name,
							attachment_profile = profile_1p })
				end)
			end
			if profile_3p then
				_run_post_native(is_bot and "reconcile_bot" or "reconcile_owner_3p",
					function()
						return _om.old_musket_appearance.reconcile(result.right_unit_3p,
							is_bot and "bot" or "owner_3p", "instance_load",
							item_data, musket_mode, { unit_name = observed_3p_name,
								attachment_profile = profile_3p })
					end)
			end
			if (not is_bot and not profile_1p) or not profile_3p then
				pcall(printf,
					"[cwv:1155] held attachment rejected edge=instance_load bot=%s mode=%s reason_1p=%s reason_3p=%s chat=false",
					tostring(is_bot == true), tostring(musket_mode),
					tostring(reason_1p), tostring(reason_3p))
			end
			_run_post_native("fade", function()
				return _om.appearance_fade.created(unit_3p, result, is_bot)
			end)
			return result
		end
		local def = _om._cwv_world_transform_decision(
			item_data, result.skin, result.right_hand_unit_name)
		if not def then
			local base_name = item_data and item_data.name
			local unit_name = result.right_hand_unit_name
			local looks_crowbill = base_name == _om.crowbill_family.SOURCE_ITEM
				or (type(unit_name) == "string" and unit_name:find("crowbill", 1, true))
			if looks_crowbill and _crowbill_transform_miss_total < 16 then
				local token = tostring(base_name) .. ":" .. tostring(unit_name) .. ":" .. tostring(result.skin)
				if not _crowbill_transform_miss_seen[token] then
					_crowbill_transform_miss_seen[token] = true
					_crowbill_transform_miss_total = _crowbill_transform_miss_total + 1
					pcall(printf,
						"[cwv:604] TRANSFORM MISS surface=create_equipment base=%s key=%s cwv_key=%s bid=%s mod_bid=%s skin=%s unit=%s career=%s count=%d/16",
						tostring(base_name), tostring(item_data and item_data.key),
						tostring(item_data and item_data.cwv_key),
						tostring(item_data and item_data.backend_id),
						tostring(item_data and item_data.mod_data and item_data.mod_data.backend_id),
						tostring(result.skin), tostring(unit_name), tostring(career_name),
						_crowbill_transform_miss_total)
				end
			end
			return result
		end

		_dbg("Applying transforms (slot=%s, skin=%s, item_key=%s, 3p_only=%s)",
			tostring(slot_name), tostring(result.skin), def.item_key, tostring(def.scale_3p_only or false))

		-- Per-perspective resolution: `_1p` / `_3p` variants override the unified
		-- field for that perspective only; if absent the unified field is used.
		-- scale_3p_only: skip 1P units (held first-person view) entirely but still
		-- apply 3P transforms (other players see this) and preview paths
		-- (HeroPreviewer / LootItemUnitPreviewer hooks below — 3P-style models).
		local right_scale     = _resolve_field(def, "right_hand_scale")
		local left_scale      = _resolve_field(def, "left_hand_scale")
		local right_offset    = _resolve_field(def, "right_hand_offset")
		local left_offset     = _resolve_field(def, "left_hand_offset")
		local right_scale_1p  = _resolve_field(def, "right_hand_scale_1p")  or right_scale
		local left_scale_1p   = _resolve_field(def, "left_hand_scale_1p")   or left_scale
		local right_offset_1p = _resolve_field(def, "right_hand_offset_1p") or right_offset
		local left_offset_1p  = _resolve_field(def, "left_hand_offset_1p")  or left_offset
		local right_scale_3p  = _resolve_field(def, "right_hand_scale_3p")  or right_scale
		local left_scale_3p   = _resolve_field(def, "left_hand_scale_3p")   or left_scale
		local right_offset_3p = _resolve_field(def, "right_hand_offset_3p") or right_offset
		local left_offset_3p  = _resolve_field(def, "left_hand_offset_3p")  or left_offset
		-- Rotation (WeaponAppearance): absolute-set orientation, resolved per hand
		-- per perspective exactly like scale/offset. nil = leave native orientation.
		local right_rot       = _resolve_field(def, "right_hand_rotation")
		local left_rot        = _resolve_field(def, "left_hand_rotation")
		local right_rot_1p    = _resolve_field(def, "right_hand_rotation_1p") or right_rot
		local left_rot_1p     = _resolve_field(def, "left_hand_rotation_1p")  or left_rot
		local right_rot_3p    = _resolve_field(def, "right_hand_rotation_3p") or right_rot
		local left_rot_3p     = _resolve_field(def, "left_hand_rotation_3p")  or left_rot
		if not def.scale_3p_only then
			_apply_cwv_hand_transform(result.right_unit_1p, def, "right", "1p", "owner_1p",
				result.right_hand_unit_name, result.skin)
			_apply_cwv_hand_transform(result.left_unit_1p, def, "left", "1p", "owner_1p",
				result.left_hand_unit_name, result.skin)
		end
		_apply_cwv_hand_transform(result.right_unit_3p, def, "right", "3p",
			is_bot and "bot" or "owner_3p", result.right_hand_unit_name, result.skin)
		_apply_cwv_hand_transform(result.left_unit_3p, def, "left", "3p",
			is_bot and "bot" or "owner_3p", result.left_hand_unit_name, result.skin)

		-- #604: same absolute pick/hammer face on held 1P and owner/bot 3P.
		-- Presentation composes from the authored rotation captured here; the weak
		-- record prevents the 180-degree delta accumulating on lifecycle replays.
		if def.crowbill_mode_family and _om._apply_crowbill_presentation then
			local crowbill_identity = _om._crowbill_render_identity(item_data, def,
				def.item_key .. ":" .. tostring(slot_name))
			_om._apply_crowbill_presentation(result.right_unit_1p, def, crowbill_identity,
				"owner_1p", right_rot_1p)
			_om._apply_crowbill_presentation(result.right_unit_3p, def, crowbill_identity,
				is_bot and "bot" or "owner_3p", right_rot_3p)
		end

		if cwv_key then
			_run_post_native("fade", function()
				return _om.appearance_fade.created(unit_3p, result, is_bot)
			end)
		end
		return result
	end)
end

return install
