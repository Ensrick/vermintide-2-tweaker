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

	-- #692: execute the production writer AND the surface that selects it. The
	-- engine boundary is a private unit-state ledger, not copied transform math.
	-- The authored inverse and its arithmetic are lifted verbatim from the entry
	-- because loading the whole mod would require unrelated VMF/game systems.
	local function clone(value)
		if type(value) ~= "table" then return value end
		local result = {}
		for key, member in pairs(value) do result[key] = clone(member) end
		return result
	end
	local function between(source, first, last)
		local start = assert(source:find(first, 1, true), first)
		local finish = assert(source:find(last, start + #first, true), last)
		return source:sub(start, finish - 1)
	end
	local entry = read("character_weapon_variants.lua")
	local inverse_source = between(entry, "\tlocal imperial_transform =",
		"\n\t-- #786: engine surfaces")
	local presentation_source = between(entry, "\t\tpresentations = {",
		"\n\t\tstyle_descriptor_transform =")
		:gsub("^%s*presentations = ", ""):gsub(",%s*$", "")

	local function fixture692(options)
		options = options or {}
		local hooks, writes, env, mod, om = {}, {}, {}, {}, {}
		local residency_boot = { logs = {}, hooks = {} }
		local residency_booting = false
		local function node_zero(node) assert(node == 0, "wrong transform node") end
		local unit_api = {
			alive = function(unit) return type(unit) == "table" and unit.alive == true end,
			has_node = function(unit, node) return unit.alive == true and node == 0 end,
			local_position = function(unit, node) node_zero(node); return unit.position end,
			local_scale = function(unit, node) node_zero(node); return unit.scale end,
			local_rotation = function(unit, node) node_zero(node); return unit.rotation end,
			set_local_pose = function(unit, node, pose)
				node_zero(node)
				writes[#writes + 1] = { unit = unit, pose = clone(pose) }
				if options.discard_write then return end
				unit.position, unit.scale, unit.rotation = clone(pose.position),
					clone(pose.scale), clone(pose.rotation)
			end,
		}
		local vector = setmetatable({
			to_elements = function(value) return unpack(value) end,
		}, { __call = function(_, x, y, z) return { x, y, z } end })
		local private_table = setmetatable({ clone = clone }, { __index = table })
		setmetatable(env, { __index = _G })
		env._G, env.Unit, env.Vector3, env.table = env, unit_api, vector, private_table
		env.printf = function(fmt, ...)
			if residency_booting then
				residency_boot.logs[#residency_boot.logs + 1] = string.format(fmt, ...)
			end
		end
		env._residency_boot, env.Managers = residency_boot, false
		env.Quaternion = {
			from_euler_angles_xyz = function(x, y, z) return { x, y, z, 1 } end,
		}
		env.Matrix4x4 = { from_quaternion_position_scale = function(rotation, position, scale)
			return { rotation = rotation, position = position, scale = scale }
		end }
		env.NetworkLookup, env.ItemMasterList = { anims = {} }, {}
		env.WeaponSkins, env.Weapons = { skins = {} }, {}
		local function load(name)
			local chunk
			if name == "_cwv_combat_styles" and options.disconnect_descriptor then
				-- Mutate only the two live descriptor-consumption guards in memory.
				-- Leave the real fallback and every surface callback unchanged.
				local mutated, replacements = read(name .. ".lua"):gsub(
					'type%(deps%.style_descriptor_transform%) == "function"', "false")
				assert(replacements == 2, "both descriptor guards must be mutated")
				chunk = assert(loadstring(mutated, "@issue692/disconnected-descriptor-guards"))
			else
				chunk = assert(loadfile(root .. name .. ".lua"))
			end
			setfenv(chunk, env)
			return chunk()
		end
		mod.dofile = function(_, path)
			return load(assert(path:match("/([^/]+)$")))
		end
		local function hook(_, class, method, callback)
			local key = class .. "." .. method
			assert(hooks[key] == nil, "duplicate fixture hook " .. key)
			hooks[key] = callback
			if residency_booting then
				residency_boot.hooks[#residency_boot.hooks + 1] = key
			end
		end
		mod.hook, mod.hook_safe = hook, hook
		local store = { schema = 1, items = {} }
		mod.get = function(_, key) return key == "cwv_combat_style_state" and store or nil end
		mod.set = function() end
		mod.network_register = function(_, _, callback) mod.receive_style = callback end
		for key, name in pairs({
			greataxe = "_cwv_greataxe", crowbill_family = "_cwv_crowbill_family",
			crowbill_hammer_mode = "_cwv_crowbill_hammer_mode",
			crowbill_presentation = "_cwv_crowbill_presentation",
			husk_transform_policy = "_cwv_husk_transform_policy",
			peer_resolver = "_cwv_peer_resolver",
			combat_style_appearance = "_cwv_combat_style_appearance",
		}) do om[key] = load(name) end
		om._cwv_key_for_item = function() return nil end
		load("_cwv_weapon_transform_owner")(mod, {
			om = om, variant_definitions = {}, find_def = function() end,
			custom_illusions = {}, custom_skin_keys = {},
		})
		local transform = om.weapon_transform
		local author = assert(loadstring(inverse_source .. "\nreturn " .. presentation_source,
			"@issue692/authored-entry-presentation"))
		local author_env = setmetatable({ _type_transforms = transform.type_transforms },
			{ __index = env })
		setfenv(author, author_env)
		local authored_presentations = author()
		if options.change_definition then
			options.change_definition(authored_presentations.bretonnian_greatsword_inverse)
		end
		local presentations = clone(authored_presentations)
		local policy = load("_cwv_combat_styles")
		local descriptors = {}
		local runtime = policy.install(mod, {
			presentations = presentations,
			cwv_key_for_item = om._cwv_key_for_item,
			style_descriptor_transform = om.combat_style_appearance.transform_decision,
			local_style_descriptor = function(identity) return descriptors[identity] end,
			peer_for_owner = function(owner)
				return owner == "observer-owner" and "observer-peer" or nil
			end,
		})
		om.combat_styles = runtime
		local function apply(...)
			if options.drop_apply then return false end
			return transform.apply_cwv_hand_transform(...)
		end
		local ctx = {
			om = om, dbg = function() end, dbg_alert = function() end,
			resolve_field = transform.resolve_field, is_unit = unit_api.alive,
			transform_unit = transform.transform_unit, apply_cwv_hand_transform = apply,
			skin_transform_map = transform.skin_transform_map,
			crowbill_transform_by_unit = transform.crowbill_transform_by_unit,
			get_mod = function() end,
		}
		load("_cwv_world_equipment_owner")(mod, ctx)
		om.old_musket_preview_pose = {
			install = function() end,
			resolve_spawn_slot = load("_cwv_old_musket_preview_pose").resolve_spawn_slot,
		}
		om.old_musket_preview = { UNIT = "unused-musket", UNIT_3P = "unused-musket-3p" }
		om.outrider_animation = { runtime_event = function() end }
		om.mod_unit_preview = { apply_loot_fallbacks = function() end }
		om._old_musket_preview_descriptor = function() end
		load("_cwv_menu_preview_owner")(mod, ctx)
		residency_booting = true
		load("_cwv_husk_residency_owner")(mod, { om = om, variant_definitions = {} })
		residency_booting = false
		load("_cwv_husk_path")(mod, {
			om = om, variant_definitions = {}, find_def = function() end,
			is_unit = unit_api.alive, apply_cwv_hand_transform = apply,
			triplet_text = transform.triplet_text,
		})

		local function unit()
			return { alive = true, position = { 2, -3, 4 }, scale = { 1, 1, 1 },
				rotation = { 0.1, 0.2, 0.3, 0.4 } }
		end
		local function select_style(style, identity)
			identity = identity or "bret-instance"
			runtime.store.items[identity] = style
			mod.receive_style("observer-peer", policy.SCHEMA, "state", "slot_melee",
				"greatsword", style)
			if options.descriptor then
				local row = runtime:describe({ name = "es_bastard_sword", backend_id = identity })
				local key = row.package.presentation and row.package.presentation.transform_key
				local descriptor_library = load("_lib_appearance_descriptor")
				local descriptor, reason = om.combat_style_appearance.build({
					descriptor = descriptor_library, encode_style_rider = policy.encode_style_rider,
				}, {
					slot_name = "slot_melee", row = row,
					world = { right_hand_unit = "native-blade", skin = "native-skin" },
					base = { key = "es_bastard_sword", right_hand_unit = "native-blade" },
					presentation = authored_presentations[key],
				})
				assert(descriptor, reason)
				descriptors[identity] = descriptor
				-- The immutable route must stand on its own. Otherwise deleting
				-- its production branch silently succeeds through the equivalent
				-- legacy record and this fixture cannot falsify the regression.
				if key then presentations[key] = nil end
				runtime:accept_style_edge("observer-peer", "slot_melee", "greatsword",
					style, "identity", descriptor)
			end
		end
		local function run(surface, style, args)
			args = args or {}
			select_style(style, args.identity)
			local right, left = unit(), unit()
			if args.dead then right.alive = false end
			local data = { name = args.item or "es_bastard_sword",
				backend_id = args.identity or "bret-instance" }
			if surface == "owner" or surface == "bot" then
				local equipment = { right_unit_1p = unit(), left_unit_1p = unit(),
					right_unit_3p = right, left_unit_3p = left, skin = "native-skin",
					right_hand_unit_name = "native-blade", left_hand_unit_name = "native-offhand" }
				if surface == "bot" then equipment.right_unit_1p, equipment.left_unit_1p = nil, nil end
				local result = hooks["GearUtils.create_equipment"](function()
					return equipment
				end, "world", "slot_melee", data, "body-1p", "body-3p", surface == "bot")
				assert(result == equipment, "native equipment result lost")
				return { right, equipment.right_unit_1p }, { left, equipment.left_unit_1p }
			elseif surface == "husk" then
				om._husk_apply_cwv_transform("right", { name = data.name },
					{ skin = "native-skin", right_hand_unit = "native-blade" }, right,
					args.owner or "observer-owner", args.slot or "slot_melee")
				return { right }, { left }
			elseif surface == "browser" then
				local previewer = { _item = { backend_id = data.backend_id,
					data = { key = data.name, name = data.name } } }
				local result = hooks["LootItemUnitPreviewer.spawn_units"](function()
					return { right }
				end, previewer, { { unit_name = "native-blade" } })
				assert(result[1] == right, "native browser return lost")
				return result, { left }
			else
				local rows = { { slot_index = args.slot_index or 3,
					item_slot_type = "melee", unit_name = "native-blade" } }
				local info = { name = data.name, backend_id = data.backend_id,
					skin_name = "native-skin", spawn_data = rows }
				local previewer = { _item_info_by_slot = { melee = info },
					_equipment_units = { [3] = { right = right, left = left } } }
				local result = hooks[surface .. "._spawn_item"](function() return "native-spawn" end,
					previewer, data.name, rows)
				assert(result == "native-spawn", "native preview return lost")
				return { right }, { left }
			end
		end
		return { run = run, writes = writes, hooks = hooks, om = om,
			runtime = runtime, select_style = select_style,
			transform = transform, presentations = presentations, unit = unit }
	end

	local function retained692(units, corrected)
		local wanted_scale = corrected and { 1, 1.25, 1 / 0.9 } or { 1, 1, 1 }
		local wanted_position = corrected and { 2, -3, 4.065 } or { 2, -3, 4 }
		for _, unit in ipairs(units) do
			for axis = 1, 3 do
				if math.abs(unit.scale[axis] - wanted_scale[axis]) > 0.000001 then
					return "scale axis " .. axis
				end
				if math.abs(unit.position[axis] - wanted_position[axis]) > 0.000001 then
					return "position axis " .. axis
				end
			end
			for axis, value in ipairs({ 0.1, 0.2, 0.3, 0.4 }) do
				if unit.rotation[axis] ~= value then return "rotation axis " .. axis end
			end
		end
		return nil
	end
	local function verify_descriptor_surface692(fixture, surface, style)
		local right, left = fixture.run(surface, style)
		H.equal(#right, surface == "owner" and 2 or 1)
		H.equal(#left, surface == "owner" and 2 or 1)
		H.equal(retained692(right, style ~= "bretonnian"), nil, style)
		H.equal(retained692(left, false), nil)
	end
	local surfaces692 = { "owner", "bot", "HeroPreviewer", "MenuWorldPreviewer", "browser", "husk" }
	for _, surface in ipairs(surfaces692) do
		H.test("#692 production " .. surface .. " retains both reciprocal inverse styles", function()
			local fixture = fixture692()
			for _, style in ipairs({ "greatsword", "kerillian" }) do
				local right, left = fixture.run(surface, style)
				H.equal(#right, surface == "owner" and 2 or 1, "every expected right unit exists")
				H.equal(#left, surface == "owner" and 2 or 1, "every expected offhand exists")
				H.equal(retained692(right, true), nil, surface .. ":" .. style)
				H.equal(retained692(left, false), nil, "offhand must remain native")
			end
		end)
		H.test("#692 production " .. surface .. " rebuild restores native without stale inverse", function()
			local fixture = fixture692()
			for _, style in ipairs({ "bretonnian", "greatsword", "kerillian", "bretonnian" }) do
				local before = #fixture.writes
				local right, left = fixture.run(surface, style)
				H.equal(retained692(right, style ~= "bretonnian"), nil, style)
				H.equal(retained692(left, false), nil)
				if style == "bretonnian" then H.equal(#fixture.writes, before) end
			end
		end)
		H.test("#692 immutable descriptor reaches production " .. surface .. " writer", function()
			local fixture = fixture692({ descriptor = true })
			for _, style in ipairs({ "greatsword", "kerillian", "bretonnian" }) do
				verify_descriptor_surface692(fixture, surface, style)
			end
		end)
		H.test("#692 production " .. surface .. " rejects disconnected immutable branches", function()
			for _, style in ipairs({ "greatsword", "kerillian" }) do
				local fixture = fixture692({ descriptor = true, disconnect_descriptor = true })
				local passed, message = pcall(verify_descriptor_surface692, fixture, surface, style)
				H.equal(passed, false, "descriptor-only surface oracle accepted legacy fallback")
				H.truthy(tostring(message):find("scale axis 2", 1, true),
					"mutation must fail retained inverse, not fixture setup: " .. tostring(message))
				H.equal(#fixture.writes, 0, "disconnected descriptor cannot use legacy presentation")
			end
		end)
	end

	H.test("#692 actual writer is idempotent across duplicate lifecycle application", function()
		local fixture = fixture692()
		local right = fixture.run("owner", "greatsword")
		local def = fixture.runtime:transform_decision({ name = "es_bastard_sword",
			backend_id = "bret-instance" })
		for _, unit in ipairs(right) do
			for _ = 1, 3 do
				fixture.transform.apply_cwv_hand_transform(unit, def, "right", "3p", "owner_3p")
			end
		end
		H.equal(retained692(right, true), nil)
	end)

	H.test("#692 missing dead foreign and stale-slot consumers cannot claim a write", function()
		local fixture = fixture692()
		for _, route in ipairs({
			{ "husk", { dead = true } },
			{ "husk", { owner = "foreign-owner" } },
			{ "husk", { slot = "slot_ranged" } },
			{ "husk", { item = "es_handgun" } },
			{ "MenuWorldPreviewer", { slot_index = 99 } },
			{ "owner", { item = "es_1h_sword" } },
		}) do
			local right = fixture.run(route[1], "greatsword", route[2])
			H.equal(retained692(right, false), nil)
		end
		local def = fixture.presentations.bretonnian_greatsword_inverse
		H.equal(fixture.transform.apply_cwv_hand_transform(nil, def, "right", "3p"), false)
		H.equal(fixture.transform.apply_cwv_hand_transform(fixture.unit(), nil, "right", "3p"), false)
		H.equal(#fixture.writes, 0)
	end)

	H.test("#692 readback falsifies axis sign discarded and disconnected writer regressions", function()
		for _, options in ipairs({
			{ change_definition = function(def) def.right_hand_offset[3] = -0.065 end },
			{ change_definition = function(def)
				def.right_hand_scale[2], def.right_hand_scale[3] =
					def.right_hand_scale[3], def.right_hand_scale[2]
			end },
			{ discard_write = true },
			{ drop_apply = true },
		}) do
			for _, surface in ipairs({ "owner", "MenuWorldPreviewer", "husk" }) do
				local fixture = fixture692(options)
				local right = fixture.run(surface, "greatsword")
				H.truthy(retained692(right, true), "planted " .. surface .. " fault escaped readback")
			end
		end
	end)

	H.test("#692 final readback rejects later native overwrite rather than setter success", function()
		local fixture = fixture692()
		local right = fixture.run("MenuWorldPreviewer", "greatsword")
		H.equal(retained692(right, true), nil)
		H.truthy(#fixture.writes > 0)
		-- Model a later attachment owner restoring native state. This is the
		-- boundary owned by #747; the #692 oracle must not report setter success.
		right[1].scale, right[1].position = { 1, 1, 1 }, { 2, -3, 4 }
		H.equal(retained692(right, true), "scale axis 2")
	end)
end
