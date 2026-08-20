-- #482: crafted UUID identity must select one canonical transform definition
-- through every production consumer, rather than four drifting local ladders.
return function(H, repo_root)
	local root = repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
	local Contract = assert(loadfile(root .. "_cwv_transform_consumer_contract.lua"))()

	local target = { item_key = "cwv_es_longsword_shield" }
	local skin = { item_key = "skin-specific" }
	local model = { item_key = "model-specific" }
	local maps = { cwv_es_longsword_shield = target }
	local skins = { selected_skin = skin }
	local cache = {}
	local function resolve_key(backend_id, item_data)
		local stamped = item_data and item_data.cwv_key
		if stamped == target.item_key then cache[backend_id] = stamped; return stamped end
		return cache[backend_id]
	end
	local bound = Contract.bind({
		resolve_key = resolve_key,
		resolve_def = function(item_data, selected_skin)
			if selected_skin and skins[selected_skin] then return skins[selected_skin] end
			local key = item_data and resolve_key(item_data.backend_id, item_data)
			return maps[key]
		end,
		transform_map = maps,
		skin_transform_map = skins,
		style_decision = function() return false, nil end,
	})

	H.test("#482 stamped UUID reaches owner preview browser through one contract", function()
		local uuid = "48200000-0000-4000-8000-000000000482"
		H.equal(bound.world({ backend_id = uuid, cwv_key = target.item_key }), target)
		H.equal(bound.preview("es_sword_shield_breton", { backend_id = uuid }, nil), target)
		local browser, key = bound.browser({
			backend_id = uuid,
			data = { key = "es_sword_shield_breton" },
		}, "es_sword_shield_breton", nil, nil)
		H.equal(browser, target)
		H.equal(key, target.item_key)
	end)

	H.test("#482 stronger skin model and style identities keep precedence", function()
		H.equal(bound.preview("base", { skin_name = "selected_skin" }, model), skin)
		H.equal(bound.preview("base", {}, model), model)
		H.equal(bound.browser({}, "base", model, skin), model)

		local style = { item_key = "style" }
		local styled = Contract.bind({
			resolve_key = function() return nil end,
			resolve_def = function() return nil end,
			transform_map = maps,
			skin_transform_map = skins,
			style_decision = function() return true, style end,
		})
		H.equal(styled.preview("base", { skin_name = "selected_skin" }, model), style)
		H.equal(styled.browser({}, "base", model, skin), style)
	end)

	H.test("#482 native controls fail closed without inferred base identity", function()
		local native = { backend_id = "native", data = { key = "es_1h_sword" } }
		H.equal(bound.world(native.data, nil, nil), nil)
		H.equal(bound.preview("es_1h_sword", { backend_id = "native" }, nil), nil)
		H.equal(bound.browser(native, "es_1h_sword", nil, nil), nil)
	end)

	local function read(name)
		local file = assert(io.open(root .. name, "rb"))
		local source = file:read("*a")
		file:close()
		return source
	end
	local world = read("_cwv_world_equipment_owner.lua")
	local menu = read("_cwv_menu_preview_owner.lua")
	local transform = read("_cwv_weapon_transform_owner.lua")
	local regression = read("_cwv_regression_render.lua")
	local husk = read("_cwv_husk_path.lua")

	H.test("#482 live consumers and named regression share executable seams", function()
		H.truthy(transform:find("_CONSUMER_CONTRACT.bind({", 1, true))
		H.truthy(world:find("local def = _om._cwv_world_transform_decision(", 1, true))
		H.truthy(menu:find("local def, info, slot_type = _om._cwv_preview_transform_decision(", 1, true))
		H.truthy(menu:find("_om._cwv_browser_transform_decision(item, spawn_data)", 1, true))
		H.truthy(husk:find("_om._cwv_select_husk_transform_def(hand, exact,", 1, true))
		H.truthy(regression:find('_rt_register("issue482_crafted_uuid_transform_consumers"', 1, true))
		for _, seam in ipairs({
			"_om._cwv_world_transform_decision",
			"_om._cwv_preview_transform_decision",
			"_om._cwv_browser_transform_decision",
			"_om._cwv_select_husk_transform_def",
		}) do
			H.truthy(regression:find(seam, 1, true), "named check must drive " .. seam)
		end
	end)
end
