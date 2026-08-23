-- _cwv_combat_style_appearance.lua -- immutable Greatsword style appearance.
--
-- The first #660 family migration makes the effective Combat Style template,
-- presentation transform, exact hand units, and compact style rider one
-- fingerprinted descriptor.  Owner and observer build from the same semantic
-- slot snapshot; no backend UUID or engine object crosses the wire.
--
-- Owned by: character_weapon_variants.lua. Consumed by the exact identity
-- transport and guarded husk re-wield path. Engine-free; dependencies arrive
-- through build().

local M = {}

M.PROVIDER = "cwv_style"
M.FAMILY = "greatsword"

local function nonempty(value)
	return type(value) == "string" and value ~= "" and value or nil
end

local function copy_triplet(value)
	if type(value) ~= "table" then return nil end
	if type(value[1]) ~= "number" or type(value[2]) ~= "number"
			or type(value[3]) ~= "number" then return nil end
	return { value[1], value[2], value[3] }
end

local function transform_for(presentation, perspective)
	if type(presentation) ~= "table" then return nil end
	local result = {}
	for _, field in ipairs({ "scale", "offset", "rotation" }) do
		local authored = presentation["right_hand_" .. field .. "_" .. perspective]
			or presentation["right_hand_" .. field]
		local value = copy_triplet(authored)
		if value then result[field] = value end
	end
	return next(result) and result or nil
end

local function hand(unit)
	unit = nonempty(unit)
	if not unit then return nil end
	return { unit = unit, unit_3p = unit .. "_3p" }
end

local function semantic_identity(args, row, base_item_key, world)
	return table.concat({
		tostring(args.slot_name or "slot_unknown"),
		tostring(row.item_key),
		tostring(base_item_key),
		tostring(world.skin or ""),
		tostring(world.offhand_skin or ""),
	}, "|")
end

function M.build(deps, args)
	deps, args = deps or {}, args or {}
	local D = deps.descriptor
	local encode = deps.encode_style_rider
	local row, world, base = args.row, args.world, args.base
	if type(D) ~= "table" or type(D.build) ~= "function" then
		return nil, "descriptor unavailable"
	end
	if type(row) ~= "table" or row.family_id ~= M.FAMILY
			or type(row.package) ~= "table" then
		return nil, "family unsupported"
	end
	if type(world) ~= "table" or type(base) ~= "table" then
		return nil, "appearance unavailable"
	end
	local style_rider = type(encode) == "function"
		and encode(row.family_id, row.style_id) or nil
	if not style_rider then return nil, "style rider invalid" end
	local base_item_key = nonempty(args.base_item_key)
		or nonempty(world.base_item_key) or nonempty(base.key)
	if not base_item_key or not nonempty(row.item_key)
			or not nonempty(row.package.template) then
		return nil, "identity incomplete"
	end

	local right = hand(world.right_hand_unit)
	local left = hand(world.left_hand_unit)
	local fallback_right = hand(base.right_hand_unit)
	local fallback_left = hand(base.left_hand_unit)
	if (right and not fallback_right) or (left and not fallback_left) then
		return nil, "fallback incomplete"
	end
	if not right and not left then return nil, "hands missing" end

	local presentation = args.presentation
	local spec = {
		item_key = row.item_key,
		variant_key = row.item_key,
		base_item_key = base_item_key,
		fallback_item_key = base_item_key,
		provider = M.PROVIDER,
		identity_evidence = {
			kind = "loadout_snapshot",
			value = semantic_identity(args, row, base_item_key, world),
		},
		skin = nonempty(world.skin),
		offhand_skin = nonempty(world.offhand_skin),
		source = nonempty(world.source) or "item",
		right_hand_unit = right,
		left_hand_unit = left,
		fallback = {
			right_hand_unit = fallback_right,
			left_hand_unit = fallback_left,
		},
		style_family = row.family_id,
		style_id = row.style_id,
		style_rider = style_rider,
		effective_template = row.package.template,
		resource = nonempty(row.package.resource),
		remap_key = nonempty(row.package.remap_key),
		transform_key = type(row.package.presentation) == "table"
			and nonempty(row.package.presentation.transform_key) or nil,
		transform_1p = transform_for(presentation, "1p"),
		transform_3p = transform_for(presentation, "3p"),
		requires_mod = "character_weapon_variants",
		generation = tonumber(args.generation) or 0,
	}
	local descriptor, errors = D.build(spec)
	if not descriptor then
		return nil, type(errors) == "table" and table.concat(errors, "; ")
			or "descriptor rejected"
	end
	return descriptor
end

function M.hand_unit(descriptor, hand_name, perspective)
	if type(descriptor) ~= "table" then return nil end
	local value = descriptor[hand_name .. "_hand_unit"]
	if type(value) == "string" then return nonempty(value) end
	if type(value) ~= "table" then return nil end
	return nonempty(perspective == "3p" and value.unit_3p or value.unit)
end

function M.expectation(descriptor)
	if type(descriptor) ~= "table" or descriptor.provider ~= M.PROVIDER
			or descriptor.style_family ~= M.FAMILY then
		return nil, "descriptor unsupported"
	end
	if not nonempty(descriptor.variant_key) or not nonempty(descriptor.style_id)
			or not nonempty(descriptor.effective_template)
			or not nonempty(descriptor.style_rider) then
		return nil, "descriptor incomplete"
	end
	return {
		family_id = descriptor.style_family,
		style_id = descriptor.style_id,
		-- The ordinary vanilla equipment wire intentionally exposes the stable
		-- base item to the husk. Exact variant identity remains in the descriptor,
		-- while the independent post-wield observer must compare what the husk can
		-- truthfully read back.
		item_key = descriptor.base_item_key,
		template = descriptor.effective_template,
		right = M.hand_unit(descriptor, "right") ~= nil,
		left = M.hand_unit(descriptor, "left") ~= nil,
		right_unit = M.hand_unit(descriptor, "right", "3p"),
		left_unit = M.hand_unit(descriptor, "left", "3p"),
		fingerprint = descriptor.fingerprint,
	}
end

function M.transform_decision(descriptor, perspective)
	if type(descriptor) ~= "table" or descriptor.provider ~= M.PROVIDER
			or (perspective ~= nil and perspective ~= "1p" and perspective ~= "3p") then
		return nil
	end
	if perspective == nil then
		local result = {
			item_key = "cwv_style_descriptor:" .. tostring(descriptor.fingerprint),
		}
		local has_transform = false
		for _, view in ipairs({ "1p", "3p" }) do
			local transform = descriptor["transform_" .. view]
			if type(transform) == "table" then
				has_transform = true
				result["right_hand_scale_" .. view] = copy_triplet(transform.scale)
				result["right_hand_offset_" .. view] = copy_triplet(transform.offset)
				result["right_hand_rotation_" .. view] = copy_triplet(transform.rotation)
			end
		end
		return has_transform and result or false
	end
	local transform = descriptor["transform_" .. perspective]
	if type(transform) ~= "table" then return false end
	return {
		item_key = "cwv_style_descriptor:" .. tostring(descriptor.fingerprint),
		right_hand_scale = copy_triplet(transform.scale),
		right_hand_offset = copy_triplet(transform.offset),
		right_hand_rotation = copy_triplet(transform.rotation),
	}
end

return M
