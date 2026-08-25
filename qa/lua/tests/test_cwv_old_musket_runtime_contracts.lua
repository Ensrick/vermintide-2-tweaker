return function(H, repo_root)
    local source = require("cwv_source").combined(repo_root)
	local mesh_runtime_path = repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_custom_mesh_runtime.lua"
	local mesh_runtime_file = assert(io.open(mesh_runtime_path, "rb"))
	local mesh_runtime_source = mesh_runtime_file:read("*a")
	mesh_runtime_file:close()
	local pose_policy = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_preview_pose.lua")
	local install_world_equipment_owner = assert(loadfile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_world_equipment_owner.lua"))()
	local MUSKET_UNIT_3P = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p"
	local function snapshot_globals(names)
		local saved = {}
		for _, name in ipairs(names) do
			saved[name] = {
				present = rawget(_G, name) ~= nil,
				value = rawget(_G, name),
			}
		end
		return saved
	end
	local function restore_globals(saved)
		for name, state in pairs(saved) do
			if state.present then
				rawset(_G, name, state.value)
			else
				rawset(_G, name, nil)
			end
		end
	end

    H.test("Old Musket mode uses one event-driven state channel", function()
        -- The channel implementation lives in _cwv_old_musket_wire.lua
        -- (extracted 0.1.449-dev); the entry keeps the dofile + call sites.
        local start = assert(source:find('local CHANNEL, SCHEMA = "cwv_old_musket_mode_v1", 1', 1, true))
        local finish = assert(source:find('_om._old_musket_mode_channel = CHANNEL', start, true))
        local channel = source:sub(start, finish)
        H.truthy(source:find('mod:network_register(CHANNEL', 1, true))
        H.truthy(source:find('send("others", "query")', 1, true))
        H.truthy(source:find('_om._old_musket_record_and_publish(player_unit, wielded_slot', 1, true))
        H.equal(channel:find('mod.update = function(dt)', 1, true), nil)
        -- #474 (2026-07-18): stance and shot report ALSO ride the delivering
        -- cwv_item_identity channel through ONE shared acceptor pair.
        H.truthy(channel:find('_om._old_musket_accept_mode = accept_mode', 1, true))
        H.truthy(channel:find('_om._old_musket_play_remote_fire = play_remote_fire', 1, true))
        H.truthy(source:find('payload.musket_mode = mode', 1, true))
        H.truthy(source:find('payload.slot == "cwv_musket_fire"', 1, true))
        H.truthy(source:find('slot = "cwv_musket_fire"', 1, true))
    end)

    H.test("Old Musket consumers share cached owner and backend state", function()
        -- Husk stance is keyed by the PRESENTED slot (the owner publishes it
        -- that way); equipment.wielded_slot lags the wield RPC (#474).
        H.truthy(source:find('_om._old_musket_mode_for_owner(', 1, true))
        H.truthy(source:find('owner_unit_3p, slot_name, hinted_player)', 1, true),
            "husk stance must consume the source-qualified extension player before owner mapping is ready")
        H.equal(source:find('_om._old_musket_mode_for_owner(owner_unit_3p, wielded_slot)', 1, true), nil)
        H.truthy(source:find('_om._old_musket_modes_by_backend[info.backend_id]', 1, true))
        H.truthy(source:find('Weapons.old_musket_template_melee', 1, true))
		H.truthy(source:find('_om.old_musket_preview_pose.arm(self, {', 1, true))
    end)

    H.test("Old Musket rifle report bypasses absent NetworkLookup safely", function()
        local start = assert(source:find('_om._dispatch_old_musket_remote_fire = function', 1, true))
        local finish = assert(source:find('if rawget(_G, "ActionHandgun")', start, true))
        local dispatch = source:sub(start, finish)
        H.truthy(dispatch:find('_om._old_musket_publish_fire', 1, true))
        H.equal(dispatch:find('rawget(sounds', 1, true), nil)
        H.truthy(source:find('WwiseUtils.trigger_unit_event, world, event_name, owner_unit, 0', 1, true))
    end)

    H.test("Old Musket transform resolves explicit attachment profiles through the bounded descriptor", function()
		H.truthy(source:find('_om.old_musket_attachment_profiles = {', 1, true))
		H.truthy(source:find('held_3p_rifle_character = "held_3p_rifle_character"', 1, true))
		H.truthy(source:find('held_3p_polearm_character = "held_3p_polearm_character"', 1, true))
		H.truthy(source:find('display_3p_rifle = "display_3p_rifle"', 1, true))
		H.truthy(source:find('_om._old_musket_transform_profile_components = function(profile)', 1, true))
		H.truthy(source:find('_om.old_musket_appearance_policy.new({', 1, true))
		H.truthy(source:find('transform_profile_source = _om._old_musket_transform_profile_components', 1, true))
		H.truthy(source:find('attachment_profiles = _om.old_musket_attachment_profiles', 1, true))
		H.truthy(source:find('quaternion = Quaternion,', 1, true),
			"production must inject the callable retail Quaternion constructor")
		H.equal(source:find('quaternion = { to_elements = Quaternion.to_elements }', 1, true), nil)
		H.truthy(source:find('_om.old_musket_appearance.reapply_tracked()', 1, true))
		H.equal(source:find('Unit.set_local_position, unit, 0, Vector3(pos[1], pos[2], pos[3])', 1, true), nil)
		H.truthy(mesh_runtime_source:find(
			'_om._CWV_OLD_MUSKET_ROT_1P_RANGED   = QuaternionBox(Quaternion.identity())',
			1, true), "normalized Handgun-frame rifle profile must start at identity")
		H.truthy(mesh_runtime_source:find(
			'_om._CWV_OLD_MUSKET_ROT_3P_RANGED   = QuaternionBox(Quaternion.identity())',
			1, true))
		H.truthy(mesh_runtime_source:find(
			'_om._CWV_OLD_MUSKET_ROT_DISPLAY_3P   = QuaternionBox(Quaternion.identity())',
			1, true), "display remains independently named but starts from the normalized asset frame")
		local polearm_adapter =
			'Quaternion.axis_angle(Vector3(1, 0, 0), math.pi / 2)'
		local first_adapter = mesh_runtime_source:find(polearm_adapter, 1, true)
		local second_adapter = first_adapter
			and mesh_runtime_source:find(polearm_adapter,
				first_adapter + #polearm_adapter, true)
		local third_adapter = second_adapter
			and mesh_runtime_source:find(polearm_adapter,
				second_adapter + #polearm_adapter, true)
		H.truthy(first_adapter and second_adapter and not third_adapter,
			"1P and 3P polearm parents must own exactly one +90-degree X adapter")
		H.equal(mesh_runtime_source:find(
			'Vector3(0, 1, 0), -math.pi / 2', 1, true), nil,
			"the malformed +X source-frame Y correction must not survive normalization")
		H.equal(mesh_runtime_source:find(
			'Quaternion.from_euler_angles_xyz(-90, -90, 0)', 1, true), nil,
			"historical raw-asset Euler compensation must not double-transform the normalized FBX")
    end)

	H.test("Old Musket held profile admits only the exact registered stance template and recipe", function()
		local function recipe(tag)
			return {
				first_person = { wielded = { tag = tag .. "-1p-w" },
					unwielded = { tag = tag .. "-1p-u" } },
				third_person = { wielded = { tag = tag .. "-3p-w" },
					unwielded = { tag = tag .. "-3p-u" } },
			}
		end
		local profiles = {
			held_1p_rifle = "held_1p_rifle",
			held_1p_polearm = "held_1p_polearm",
			held_3p_rifle_character = "held_3p_rifle_character",
			held_3p_polearm_character = "held_3p_polearm_character",
		}
		local rifle = { right_hand_attachment_node_linking = recipe("rifle") }
		local polearm = { right_hand_attachment_node_linking = recipe("polearm") }
		local weapons = {
			old_musket_template = rifle,
			old_musket_template_melee = polearm,
		}
		for _, case in ipairs({
			{ rifle, "1p", "ranged", profiles.held_1p_rifle },
			{ rifle, "3p", "ranged", profiles.held_3p_rifle_character },
			{ polearm, "1p", "melee", profiles.held_1p_polearm },
			{ polearm, "3p", "melee", profiles.held_3p_polearm_character },
		}) do
			local profile, reason = pose_policy.resolve_held_attachment_profile(
				case[1], case[2], case[3], weapons, profiles)
			H.equal(profile, case[4])
			H.equal(reason, "ready")
		end

		for _, case in ipairs({
			{ {}, "3p", "ranged", "template_stance_mismatch" },
			{ polearm, "3p", "ranged", "template_stance_mismatch" },
			{ rifle, "3p", "melee", "template_stance_mismatch" },
			{ rifle, "camera", "ranged", "perspective_invalid" },
			{ rifle, "3p", "foreign", "stance_invalid" },
			{ rifle, "3p", "ranged", "weapons_missing", nil },
		}) do
			local candidate_weapons = case[5] == nil and weapons or case[5]
			if case[4] == "weapons_missing" then candidate_weapons = nil end
			local profile, reason = pose_policy.resolve_held_attachment_profile(
				case[1], case[2], case[3], candidate_weapons, profiles)
			H.equal(profile, nil)
			H.equal(reason, case[4])
		end

		local missing_recipe = {
			right_hand_attachment_node_linking = recipe("missing"),
		}
		weapons.old_musket_template = missing_recipe
		missing_recipe.right_hand_attachment_node_linking.third_person.unwielded = nil
		local profile, reason = pose_policy.resolve_held_attachment_profile(
			missing_recipe, "3p", "ranged", weapons, profiles)
		H.equal(profile, nil)
		H.equal(reason, "attachment_recipe_missing")

		weapons.old_musket_template = rifle
		local drifted_profiles = {}
		for key, value in pairs(profiles) do drifted_profiles[key] = value end
		drifted_profiles.held_3p_rifle_character = "foreign_profile"
		profile, reason = pose_policy.resolve_held_attachment_profile(
			rifle, "3p", "ranged", weapons, drifted_profiles)
		H.equal(profile, nil)
		H.equal(reason, "attachment_profile_invalid")
	end)

	H.test("Old Musket installed GearUtils owner and bot adapters consume the returned exact template", function()
		local function recipe(tag)
			return {
				first_person = { wielded = { tag = tag .. "-1p-w" }, unwielded = {} },
				third_person = { wielded = { tag = tag .. "-3p-w" }, unwielded = {} },
			}
		end
		local profiles = {
			held_1p_rifle = "held_1p_rifle",
			held_1p_polearm = "held_1p_polearm",
			held_3p_rifle_character = "held_3p_rifle_character",
			held_3p_polearm_character = "held_3p_polearm_character",
		}
		local weapons = {
			old_musket_template = { right_hand_attachment_node_linking = recipe("rifle") },
			old_musket_template_melee = { right_hand_attachment_node_linking = recipe("polearm") },
		}
		local reconciles, fade_calls = {}, 0
		local om = {
			_cwv_transform_consumers = { world = function() return nil end },
			_cwv_key_for_item = function() return "cwv_es_musket_old" end,
			_cwv_resolve_world_descriptor = function()
				return { fingerprint = "fp", right_hand_unit = MUSKET_UNIT_3P,
					left_hand_unit = nil }
			end,
			_old_musket_held_profile = function(template, perspective, mode)
				return pose_policy.resolve_held_attachment_profile(
					template, perspective, mode, weapons, profiles)
			end,
			old_musket_appearance = {
				reconcile = function(unit, surface, edge, item, mode, context)
					reconciles[#reconciles + 1] = { unit = unit, surface = surface,
						edge = edge, item = item, mode = mode, context = context }
					return { retained = true }
				end,
			},
			appearance_fade = { created = function() fade_calls = fade_calls + 1 end },
		}
		local installed
		install_world_equipment_owner({
			hook = function(_, class_name, method_name, callback)
				H.equal(class_name, "GearUtils")
				H.equal(method_name, "create_equipment")
				installed = callback
			end,
		}, {
			om = om, dbg = function() end, resolve_field = function() return nil end,
			apply_cwv_hand_transform = function() error("generic writer must be bypassed") end,
		})
		H.truthy(installed)

		local function exercise(mode, is_bot, returned_template)
			local item = { backend_id = "old-musket-" .. mode,
				mod_data = { cwv_musket_stance = mode } }
			local result = {
				item_template = returned_template,
				skin = "cwv_es_musket_old_skin",
				right_unit_1p = { id = mode .. "-1p" },
				right_unit_3p = { id = mode .. "-3p" },
				right_hand_unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom",
			}
			local native_calls = 0
			local returned = installed(function()
				native_calls = native_calls + 1
				return result
			end, {}, "slot_ranged", item, {}, {}, is_bot, nil, nil, nil,
				nil, nil, "es_huntsman")
			H.equal(returned, result)
			H.equal(native_calls, 1)
			return item, result
		end

		local owner_item, owner_result = exercise(
			"ranged", false, weapons.old_musket_template)
		H.equal(#reconciles, 2)
		H.deep_equal({ reconciles[1].surface, reconciles[2].surface },
			{ "owner_1p", "owner_3p" })
		H.equal(reconciles[1].unit, owner_result.right_unit_1p)
		H.equal(reconciles[2].unit, owner_result.right_unit_3p)
		H.equal(reconciles[1].edge, "instance_load")
		H.equal(reconciles[2].edge, "instance_load")
		H.equal(reconciles[1].item, owner_item)
		H.equal(reconciles[1].context.unit_name,
			"units/cwv_es_musket_custom/cwv_es_musket_custom")
		H.equal(reconciles[2].context.unit_name,
			"units/cwv_es_musket_custom/cwv_es_musket_custom_3p")
		H.equal(reconciles[1].context.attachment_profile, profiles.held_1p_rifle)
		H.equal(reconciles[2].context.attachment_profile,
			profiles.held_3p_rifle_character)

		local _, bot_result = exercise(
			"melee", true, weapons.old_musket_template_melee)
		H.equal(#reconciles, 3)
		H.equal(reconciles[3].surface, "bot")
		H.equal(reconciles[3].unit, bot_result.right_unit_3p)
		H.equal(reconciles[3].context.unit_name,
			"units/cwv_es_musket_custom/cwv_es_musket_custom_3p")
		H.equal(reconciles[3].context.attachment_profile,
			profiles.held_3p_polearm_character)

		exercise("melee", false, weapons.old_musket_template)
		H.equal(#reconciles, 3,
			"a stance/template mismatch must not self-label an owner profile")
		H.equal(fade_calls, 3, "fade enrollment still runs on every native result")
	end)

	H.test("Old Musket installed SimpleInventory equip adapter admits only the exact returned stance template", function()
		local function recipe(tag)
			return {
				first_person = { wielded = { tag = tag .. "-1p-w" }, unwielded = {} },
				third_person = { wielded = { tag = tag .. "-3p-w" }, unwielded = {} },
			}
		end
		local profiles = {
			held_1p_rifle = "held_1p_rifle",
			held_1p_polearm = "held_1p_polearm",
			held_3p_rifle_character = "held_3p_rifle_character",
			held_3p_polearm_character = "held_3p_polearm_character",
		}
		local weapons = {
			old_musket_template = { right_hand_attachment_node_linking = recipe("rifle") },
			old_musket_template_melee = { right_hand_attachment_node_linking = recipe("polearm") },
		}
		local reconciles, fade_calls = {}, 0
		local om = {
			_cwv_key_for_item = function() return "cwv_es_musket_old" end,
			_old_musket_held_profile = function(template, perspective, mode)
				return pose_policy.resolve_held_attachment_profile(
					template, perspective, mode, weapons, profiles)
			end,
			old_musket_appearance = {
				reconcile = function(unit, surface, edge, item, mode, context)
					reconciles[#reconciles + 1] = { unit = unit, surface = surface,
						edge = edge, item = item, mode = mode, context = context }
					return { retained = true }
				end,
			},
			appearance_fade = { owner_wield = function() fade_calls = fade_calls + 1 end },
			cross_slot_filter = {
				kind = function() return "unrelated" end,
				should_narrow = function() return false end,
				apply = function(items) return items, 0, 0, {} end,
			},
			javelin_gate = { filter_unavailable = function(items) return items, 0 end },
		}
		local hooks = {}
		local mod = {
			hook = function(_, class_name, method_name, callback)
				local key = class_name .. "." .. method_name
				H.equal(hooks[key], nil, "duplicate equip-surface hook " .. key)
				hooks[key] = callback
			end,
			hook_safe = function(_, class_name, method_name, callback)
				local key = class_name .. "." .. method_name
				H.equal(hooks[key], nil, "duplicate equip-surface hook " .. key)
				hooks[key] = callback
			end,
			warning = function() end,
			info = function() end,
		}

		-- This module's first phase conditionally reads live engine globals while
		-- installing unrelated cross-slot/package hooks. Preserve their exact raw
		-- shape so this installed-callback test cannot leak fixture state to later
		-- suites, including when an assertion fails.
		local saved = {}
		for _, name in ipairs({ "Managers", "CareerSettings" }) do
			saved[name] = { present = rawget(_G, name) ~= nil, value = rawget(_G, name) }
			rawset(_G, name, nil)
		end
		local ok, err = pcall(function()
			local install = assert(loadfile(repo_root
				.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_musket_equip_surface.lua"))()
			local install_spawn_surface = install(mod, {
				om = om, dbg = function() end, variant_definitions = {},
			})
			H.equal(type(install_spawn_surface), "function")
			install_spawn_surface()
			local installed = hooks["SimpleInventoryExtension._wield_slot"]
			H.equal(type(installed), "function")

			local function exercise(mode, is_bot, returned_template)
				local item = { backend_id = "old-musket-equip-" .. mode,
					mod_data = { cwv_musket_stance = mode } }
				local slot_data = {
					item_data = item,
					item_template = returned_template,
					right_hand_unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom",
					right_unit_1p = { id = mode .. "-equip-1p" },
					right_unit_3p = { id = mode .. "-equip-3p" },
				}
				local equipment = { slots = { slot_ranged = slot_data } }
				local self = { is_bot = is_bot, _equipment = equipment }
				local native_calls, sentinel = 0, { result = mode }
				local result = installed(function()
					native_calls = native_calls + 1
					return sentinel
				end, self, equipment, slot_data, nil, nil, nil)
				H.equal(native_calls, 1)
				H.equal(result, sentinel)
				return item, slot_data
			end

			local owner_item, owner_slot = exercise(
				"ranged", false, weapons.old_musket_template)
			H.equal(#reconciles, 2)
			H.deep_equal({ reconciles[1].surface, reconciles[2].surface },
				{ "owner_1p", "owner_3p" })
			H.equal(reconciles[1].edge, "equip")
			H.equal(reconciles[2].edge, "equip")
			H.equal(reconciles[1].unit, owner_slot.right_unit_1p)
			H.equal(reconciles[2].unit, owner_slot.right_unit_3p)
			H.equal(reconciles[1].item, owner_item)
			H.equal(reconciles[1].context.attachment_profile, profiles.held_1p_rifle)
			H.equal(reconciles[2].context.attachment_profile,
				profiles.held_3p_rifle_character)
			H.equal(reconciles[1].context.unit_name,
				"units/cwv_es_musket_custom/cwv_es_musket_custom")
			H.equal(reconciles[2].context.unit_name,
				"units/cwv_es_musket_custom/cwv_es_musket_custom_3p")

			local _, bot_slot = exercise(
				"melee", true, weapons.old_musket_template_melee)
			H.equal(#reconciles, 3)
			H.equal(reconciles[3].surface, "bot")
			H.equal(reconciles[3].unit, bot_slot.right_unit_3p)
			H.equal(reconciles[3].context.attachment_profile,
				profiles.held_3p_polearm_character)

			exercise("melee", false, weapons.old_musket_template)
			H.equal(#reconciles, 3,
				"a stale ranged template must not be relabeled as a melee Old Musket")
			exercise("ranged", true, {})
			H.equal(#reconciles, 3,
				"an unregistered template reference must not reach the stable equip owner")
			H.equal(fade_calls, 4,
				"the unrelated fade owner must still observe each successfully returned wield")
		end)
		restore_globals(saved)
		if not ok then error(err) end
	end)

	H.test("#1155 GearUtils post-native auxiliary faults preserve the exact native result", function()
		local function recipe()
			return {
				first_person = { wielded = {}, unwielded = {} },
				third_person = { wielded = {}, unwielded = {} },
			}
		end
		local profiles = {
			held_1p_rifle = "held_1p_rifle",
			held_3p_rifle_character = "held_3p_rifle_character",
		}
		local template = { right_hand_attachment_node_linking = recipe() }
		for _, fault in ipairs({ "key", "profile", "reconcile", "fade" }) do
			local native_calls, profile_calls, reconcile_calls, fade_calls = 0, {}, {}, 0
			local om = {
				_cwv_transform_consumers = { world = function() return nil end },
				_cwv_key_for_item = function()
					if fault == "key" then error("key-fault") end
					return "cwv_es_musket_old"
				end,
				_cwv_resolve_world_descriptor = function()
					return { fingerprint = "fp", right_hand_unit = MUSKET_UNIT_3P }
				end,
				_old_musket_held_profile = function(_, perspective)
					profile_calls[#profile_calls + 1] = perspective
					if fault == "profile" and perspective == "1p" then
						error("profile-fault")
					end
					return perspective == "1p" and profiles.held_1p_rifle
						or profiles.held_3p_rifle_character
				end,
				old_musket_appearance = {
					reconcile = function(_, surface)
						reconcile_calls[#reconcile_calls + 1] = surface
						if fault == "reconcile" and surface == "owner_1p" then
							error("reconcile-fault")
						end
						return { retained = true }
					end,
				},
				appearance_fade = {
					created = function()
						fade_calls = fade_calls + 1
						if fault == "fade" then error("fade-fault") end
					end,
				},
			}
			local installed
			install_world_equipment_owner({
				hook = function(_, class_name, method_name, callback)
					H.equal(class_name, "GearUtils")
					H.equal(method_name, "create_equipment")
					installed = callback
				end,
			}, {
				om = om, dbg = function() end, resolve_field = function() return nil end,
				apply_cwv_hand_transform = function()
					error("generic transform must remain bypassed")
				end,
			})
			local native_result = {
				item_template = template, skin = "cwv_es_musket_old_skin",
				right_unit_1p = {}, right_unit_3p = {},
				right_hand_unit_name =
					"units/cwv_es_musket_custom/cwv_es_musket_custom",
			}
			local ok, returned = pcall(installed, function()
				native_calls = native_calls + 1
				return native_result
			end, {}, "slot_ranged", {
				backend_id = "old-musket-fault-" .. fault,
				mod_data = { cwv_musket_stance = "ranged" },
			}, {}, {}, false, nil, nil, nil, nil, nil, "es_huntsman")
			H.equal(ok, true, fault .. " auxiliary escaped the GearUtils post-native boundary")
			H.equal(returned, native_result,
				fault .. " auxiliary replaced the exact native equipment result")
			H.equal(native_calls, 1)
			if fault == "key" then
				H.equal(#profile_calls, 0)
				H.equal(#reconcile_calls, 0)
				H.equal(fade_calls, 0)
			elseif fault == "profile" then
				H.deep_equal(profile_calls, { "1p", "3p" },
					"an independent 3P profile observer must survive a 1P profile fault")
				H.deep_equal(reconcile_calls, { "owner_3p" })
				H.equal(fade_calls, 1)
			elseif fault == "reconcile" then
				H.deep_equal(reconcile_calls, { "owner_1p", "owner_3p" },
					"the 3P reconciler must survive an independent 1P reconciler fault")
				H.equal(fade_calls, 1)
			else
				H.deep_equal(reconcile_calls, { "owner_1p", "owner_3p" })
				H.equal(fade_calls, 1)
			end
		end
	end)

	H.test("#1155 SimpleInventory post-native auxiliary faults preserve the exact native result", function()
		local function recipe()
			return {
				first_person = { wielded = {}, unwielded = {} },
				third_person = { wielded = {}, unwielded = {} },
			}
		end
		local profiles = {
			held_1p_rifle = "held_1p_rifle",
			held_3p_rifle_character = "held_3p_rifle_character",
		}
		local template = { right_hand_attachment_node_linking = recipe() }
		local saved = {}
		for _, name in ipairs({ "Managers", "CareerSettings" }) do
			saved[name] = { present = rawget(_G, name) ~= nil, value = rawget(_G, name) }
			rawset(_G, name, nil)
		end
		local ok_matrix, matrix_error = pcall(function()
			for _, fault in ipairs({ "key", "profile", "reconcile", "fade" }) do
				local native_calls, profile_calls, reconcile_calls, fade_calls = 0, {}, {}, 0
				local om = {
					_cwv_key_for_item = function()
						if fault == "key" then error("key-fault") end
						return "cwv_es_musket_old"
					end,
					_old_musket_held_profile = function(_, perspective)
						profile_calls[#profile_calls + 1] = perspective
						if fault == "profile" and perspective == "1p" then
							error("profile-fault")
						end
						return perspective == "1p" and profiles.held_1p_rifle
							or profiles.held_3p_rifle_character
					end,
					old_musket_appearance = {
						reconcile = function(_, surface)
							reconcile_calls[#reconcile_calls + 1] = surface
							if fault == "reconcile" and surface == "owner_1p" then
								error("reconcile-fault")
							end
							return { retained = true }
						end,
					},
					appearance_fade = {
						owner_wield = function()
							fade_calls = fade_calls + 1
							if fault == "fade" then error("fade-fault") end
						end,
					},
					cross_slot_filter = {
						kind = function() return "unrelated" end,
						should_narrow = function() return false end,
						apply = function(items) return items, 0, 0, {} end,
					},
					javelin_gate = { filter_unavailable = function(items) return items, 0 end },
				}
				local hooks = {}
				local mod = {
					hook = function(_, class_name, method_name, callback)
						hooks[class_name .. "." .. method_name] = callback
					end,
					hook_safe = function(_, class_name, method_name, callback)
						hooks[class_name .. "." .. method_name] = callback
					end,
					warning = function() end, info = function() end,
				}
				local install = assert(loadfile(repo_root
					.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_musket_equip_surface.lua"))()
				install(mod, { om = om, dbg = function() end, variant_definitions = {} })()
				local installed = hooks["SimpleInventoryExtension._wield_slot"]
				H.equal(type(installed), "function")
				local item = { backend_id = "old-musket-wield-fault-" .. fault,
					mod_data = { cwv_musket_stance = "ranged" } }
				local slot_data = {
					item_data = item, item_template = template,
					right_hand_unit_name =
						"units/cwv_es_musket_custom/cwv_es_musket_custom",
					right_unit_1p = {}, right_unit_3p = {},
				}
				local equipment = { slots = { slot_ranged = slot_data } }
				local self = { is_bot = false, _equipment = equipment }
				local native_result = { fault = fault }
				local ok, returned = pcall(installed, function()
					native_calls = native_calls + 1
					return native_result
				end, self, equipment, slot_data, nil, nil, nil)
				H.truthy(ok,
					fault .. " auxiliary escaped the SimpleInventory post-native boundary: "
						.. tostring(returned))
				H.equal(returned, native_result,
					fault .. " auxiliary replaced the exact native wield result")
				H.equal(native_calls, 1)
				if fault == "key" then
					H.equal(#profile_calls, 0)
					H.equal(#reconcile_calls, 0)
					H.equal(fade_calls, 0)
				elseif fault == "profile" then
					H.deep_equal(profile_calls, { "1p", "3p" })
					H.deep_equal(reconcile_calls, { "owner_3p" })
					H.equal(fade_calls, 1)
				elseif fault == "reconcile" then
					H.deep_equal(reconcile_calls, { "owner_1p", "owner_3p" })
					H.equal(fade_calls, 1)
				else
					H.deep_equal(reconcile_calls, { "owner_1p", "owner_3p" })
					H.equal(fade_calls, 1)
				end
			end
		end)
		restore_globals(saved)
		if not ok_matrix then error(matrix_error) end
	end)

	H.test("#1155 runtime gate binds PASS to the exact currently wielded Old Musket targets", function()
		local expected_bid = "old-musket-equipped-exact"
		local cim_bid = "old-musket-cim-exact"
		local player_unit, retained_1p, retained_3p = {}, {}, {}
		local profiles = {
			held_1p_rifle = "held_1p_rifle",
			held_1p_polearm = "held_1p_polearm",
			held_3p_rifle_character = "held_3p_rifle_character",
			held_3p_polearm_character = "held_3p_polearm_character",
			display_3p_rifle = "display_3p_rifle",
		}
		local policy = {
			ITEM_KEY = "cwv_es_musket_old",
			MATERIAL = "units/cwv_es_musket_custom/cwv_es_musket_custom",
			texture_resources_ready = function() return true end,
		}
		local descriptor_lib = {
			raw = function(descriptor) return descriptor end,
			fingerprint = function(descriptor) return descriptor.fingerprint end,
		}
		local function profile_for(surface, mode)
			if surface == "illusion_browser" or surface == "cim_preview" then
				return profiles.display_3p_rifle
			end
			if surface == "owner_1p" then
				return mode == "melee" and profiles.held_1p_polearm
					or profiles.held_1p_rifle
			end
			return mode == "melee" and profiles.held_3p_polearm_character
				or profiles.held_3p_rifle_character
		end
		local function resolve(item, mode, surface, context)
			local profile = context and context.attachment_profile
			local bid = item and item.backend_id
				or (context and context.preview_identity) or "missing"
			return {
				attachment_profile = profile,
				transform_profiles = {
					held_3p_rifle_character = { rotation = { 0, 0, 0, 1 } },
					display_3p_rifle = { rotation = { 0, 0, 0, 1 } },
				},
				materials = { authored = policy.MATERIAL, preview = policy.MATERIAL },
				fingerprint = table.concat({ tostring(surface), tostring(mode),
					tostring(profile), tostring(bid) }, "|"),
			}
		end
		local live = {
			epoch = 4, generation = 7, cim_generation = 3,
			identity = { kind = "backend_id", value = expected_bid },
			cim_identity = { kind = "backend_id", value = cim_bid },
			surfaces = {}, preview_lifecycles = {},
		}
		local function add_row(surface, mode, edge, identity)
			local profile = profile_for(surface, mode)
			local descriptor = resolve({ backend_id = identity.value }, mode,
				surface, { attachment_profile = profile })
			live.surfaces[surface] = live.surfaces[surface] or {}
			live.surfaces[surface][mode] = {
				retained = true, fallback = false, edge = edge, attempts = 1,
				profile = profile, epoch = live.epoch, generation = live.generation,
				identity = { kind = identity.kind, value = identity.value },
				fingerprint = descriptor.fingerprint,
				paint = true, apply = true, materials = true,
				position = true, scale = true, rotation = true,
				transform_mode = "atomic-local-pose", transform_error = nil,
				rotation_constructed = true, position_write = true,
				scale_write = true, rotation_write = true,
			}
		end
		for _, surface in ipairs({
			"owner_1p", "owner_3p", "inventory_preview",
		}) do
			local edge = (surface == "owner_1p" or surface == "owner_3p")
				and "equip" or "preview_open"
			add_row(surface, "ranged", edge, live.identity)
			add_row(surface, "melee", edge, live.identity)
		end
		local browser_identity = {
			kind = "preview_slot", value = "browser:visible-musket-skin",
		}
		add_row("illusion_browser", "ranged", "preview_open", browser_identity)
		live.surfaces.illusion_browser.ranged.preview_generation = 12
		live.preview_lifecycles.illusion_browser = {
			generation = 12,
			identity = { kind = browser_identity.kind, value = browser_identity.value },
		}
		add_row("cim_preview", "ranged", "preview_open", live.cim_identity)

		local evidence_targets = {
			["owner_1p:ranged"] = retained_1p,
			["owner_3p:ranged"] = retained_3p,
		}
		local pilot = {
			resolve = resolve,
			implemented_cells = {
				cim_preview = { instance_load = true, preview_open = true },
			},
			reconciler = {
				reconcile = function(_, surface)
					return { reason = surface == "not_a_surface"
						and "unknown-surface" or "unexpected" }
				end,
			},
			live_status = function() return live end,
			live_target_matches = function(surface, mode, target, identity)
				return evidence_targets[surface .. ":" .. mode] == target
					and identity and identity.kind == "backend_id"
					and identity.value == expected_bid
			end,
		}
		local item_data = {
			backend_id = expected_bid, cwv_key = policy.ITEM_KEY,
			mod_data = { backend_id = expected_bid, cwv_musket_stance = "ranged" },
		}
		local old_slot = { item_data = item_data }
		local equipment = {
			wielded_slot = "slot_ranged",
			slots = { slot_ranged = old_slot,
				slot_melee = { item_data = { backend_id = "vanilla-sword" } } },
			right_hand_wielded_unit = retained_1p,
			right_hand_wielded_unit_3p = retained_3p,
		}
		local inventory = { _equipment = equipment }
		local om = {
			old_musket_appearance = pilot,
			appearance_descriptor = descriptor_lib,
			old_musket_preview = policy,
			old_musket_attachment_profiles = profiles,
			_old_musket_attachment_profile = function(perspective, mode)
				return profile_for(perspective == "1p" and "owner_1p" or "owner_3p", mode)
			end,
			_cwv_loot_preview_surface = function(previewer)
				return previewer and previewer._cim_preview_context
					and "cim_preview" or "illusion_browser"
			end,
			_cwv_cim_preview_context = function(previewer)
				local context = previewer and previewer._cim_preview_context
				local item = previewer and previewer._item
				if context and context.contract == "cim_preview_context_v1"
						and context.provider == "cim_dev"
						and item and item.backend_id == context.backend_id then
					return context
				end
			end,
			_cwv_key_for_item = function(bid, item)
				return bid == expected_bid and item == item_data and policy.ITEM_KEY or nil
			end,
		}
		local captured
		local mod = {
			_cwv_dev_anim_picker = { install = function() end },
			info = function() end,
		}

		local saved = {}
		for _, name in ipairs({
			"Application", "Managers", "Unit", "ScriptUnit", "_MEM_PROBE_T0_CWV",
		}) do
			saved[name] = { present = rawget(_G, name) ~= nil, value = rawget(_G, name) }
		end
		local ok, err = pcall(function()
			rawset(_G, "Application", { can_get = function() return true end })
			rawset(_G, "Managers", { player = {
				local_player = function(_, index)
					return index == 1 and { player_unit = player_unit } or nil
				end,
			} })
			rawset(_G, "Unit", {
				alive = function(unit) return unit ~= nil and unit.dead ~= true end,
			})
			rawset(_G, "ScriptUnit", {
				extension = function(unit, extension_name)
					if unit == player_unit and extension_name == "inventory_system" then
						return inventory
					end
					error("unexpected extension")
				end,
			})
			rawset(_G, "_MEM_PROBE_T0_CWV", collectgarbage("count"))

			local install = assert(loadfile(repo_root
				.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_regression_render.lua"))()
			install(mod, {
				mod_version = "qa-1155", om = om, dbg = function() end,
				rt_register = function(name, check)
					if name == "issue1155_old_musket_descriptor_reconciler" then
						captured = check
					end
				end,
				variant_definitions = {}, registered_keys = {}, display_names = {},
				find_def = function() return nil end, build_entry = function() end,
				auto_register_all = function() end, cross_access_action_remap = {},
				wield_hook_registration_count = 0, transform_map = {},
				skin_transform_map = {}, crowbill_transform_by_unit = {},
				custom_skin_keys = {},
			})
			H.equal(type(captured), "function")
			H.equal(captured(), nil,
				"the exact current item and retained 1P/3P targets must pass")

			equipment.wielded_slot = "slot_melee"
			local verdict = captured()
			H.equal(type(verdict), "string")
			H.truthy(verdict:find(
				"found the exact tested instance in the ranged slot", 1, true))
			H.truthy(verdict:find(
				"not currently wielded; wield Old Musket and rerun /cwv_regression_test",
				1, true))
			equipment.wielded_slot = "slot_ranged"

			equipment.slots.slot_ranged = {
				item_data = { backend_id = "different-instance" },
			}
			verdict = captured()
			H.equal(type(verdict), "string")
			H.truthy(verdict:find("no longer the exact equipped instance", 1, true))
			equipment.slots.slot_ranged = old_slot

			equipment.right_hand_wielded_unit = {}
			verdict = captured()
			H.equal(type(verdict), "string")
			H.truthy(verdict:find("current wielded units do not match", 1, true))
			equipment.right_hand_wielded_unit = retained_1p

			equipment.right_hand_wielded_unit_3p = {}
			verdict = captured()
			H.equal(type(verdict), "string")
			H.truthy(verdict:find("current wielded units do not match", 1, true))
			equipment.right_hand_wielded_unit_3p = retained_3p

			local browser = live.surfaces.illusion_browser.ranged
			browser.edge = "instance_load"
			verdict = captured()
			H.truthy(verdict:find("illusion_browser/ranged", 1, true),
				"missing final visibility edge must fail")
			browser.edge = "preview_open"

			local fingerprint = browser.fingerprint
			browser.fingerprint = "foreign"
			verdict = captured()
			H.truthy(verdict:find("fingerprint=foreign", 1, true),
				"wrong visible descriptor fingerprint must fail")
			browser.fingerprint = fingerprint

			live.preview_lifecycles.illusion_browser.generation = 13
			verdict = captured()
			H.truthy(verdict:find("identity/generation evidence is inconsistent", 1, true),
				"stale browser generation must fail")
			live.preview_lifecycles.illusion_browser.generation = 12

			local postcondition_faults = {
				{ key = "paint", value = false, label = "paint readback" },
				{ key = "apply", value = false, label = "apply verdict" },
				{ key = "materials", value = false, label = "material readback" },
				{ key = "position", value = false, label = "position readback" },
				{ key = "scale", value = false, label = "scale readback" },
				{ key = "rotation", value = false, label = "rotation readback" },
				{ key = "transform_mode", value = "partial-pose",
					label = "atomic pose adapter" },
				{ key = "rotation_constructed", value = false,
					label = "rotation construction" },
				{ key = "position_write", value = false, label = "position write" },
				{ key = "scale_write", value = false, label = "scale write" },
				{ key = "rotation_write", value = false, label = "rotation write" },
				{ key = "transform_error", value = "pose-write-rejected",
					label = "transform error channel" },
			}
			for _, fault in ipairs(postcondition_faults) do
				local original = browser[fault.key]
				browser[fault.key] = fault.value
				verdict = captured()
				H.equal(type(verdict), "string",
					"a failed browser " .. fault.label .. " must fail the named gate")
				browser[fault.key] = original
			end
		end)
		restore_globals(saved)
		if not ok then error(err) end
	end)

	H.test("#1156 global restoration preserves an existing false raw value", function()
		local name = "__cwv_issue1156_false_global"
		local original = snapshot_globals({ name })
		local ok, err = pcall(function()
			rawset(_G, name, false)
			local saved_false = snapshot_globals({ name })
			rawset(_G, name, { changed = true })
			restore_globals(saved_false)
			H.equal(rawget(_G, name), false,
				"false is a present raw value and must not be restored as nil")
		end)
		restore_globals(original)
		if not ok then error(err) end
	end)

end
