return function(H, repo_root)
    local source = require("cwv_source").combined(repo_root)
	local mesh_runtime_path = repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_custom_mesh_runtime.lua"
	local mesh_runtime_file = assert(io.open(mesh_runtime_path, "rb"))
	local mesh_runtime_source = mesh_runtime_file:read("*a")
	mesh_runtime_file:close()
	local policy_path = repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_preview.lua"
	local policy_file = assert(io.open(policy_path, "rb"))
	local policy_source = policy_file:read("*a")
	policy_file:close()
	local pose_policy = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_preview_pose.lua")
	local install_world_equipment_owner = assert(loadfile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_world_equipment_owner.lua"))()
	local MUSKET_UNIT_3P = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p"
	local HELD_RIFLE_PROFILE = "held_3p_rifle_character"
	local HELD_POLEARM_PROFILE = "held_3p_polearm_character"
	local DISPLAY_PROFILE = "display_3p_rifle"
	local function attachment_recipe()
		return { wielded = {}, unwielded = {} }
	end

	local function install_menu_owner(options)
		options = options or {}
		local hooks, hook_order = {}, {}
		local om = {
			old_musket_preview = {
				UNIT = "units/cwv_es_musket_custom/cwv_es_musket_custom",
				UNIT_3P = MUSKET_UNIT_3P,
				NETWORK_PACKAGE_ALIAS_1P =
					"units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1",
				NETWORK_PACKAGE_ALIAS_3P =
					"units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1_3p",
			},
			old_musket_attachment_profiles = options.attachment_profiles or {
				held_3p_rifle_character = HELD_RIFLE_PROFILE,
				held_3p_polearm_character = HELD_POLEARM_PROFILE,
				display_3p_rifle = DISPLAY_PROFILE,
			},
			old_musket_preview_pose = {
				install = function() end,
				resolve_spawn_slot = pose_policy.resolve_spawn_slot,
				resolve_right_hand_spawn_row = pose_policy.resolve_right_hand_spawn_row,
				resolve_character_attachment_profile =
					pose_policy.resolve_character_attachment_profile,
				resolve_wield_event = pose_policy.resolve_wield_event,
				arm = options.pose_arm or pose_policy.arm,
			},
			_cwv_transform_consumers = {
				preview = options.preview_transform or function() return nil end,
				browser = function() return nil, nil end,
			},
			outrider_animation = {
				runtime_event = function() return nil, nil end,
				dispatch_event = function() return nil, nil end,
				emit_evidence = function() end,
			},
			mod_unit_preview = {
				FALLBACK_MARKER = "_cwv_mod_unit_preview_fallback_v1",
				apply_loot_fallbacks = function() end,
			},
			_old_musket_preview_descriptor = options.preview_descriptor
				or function() return nil end,
			_old_musket_preview_texture_targets = options.preview_targets
				or function() return {} end,
			old_musket_appearance = {
				reconcile = options.reconcile or function() return nil end,
			},
		}
		local mod = {
			hook = function(_, class_name, method_name, callback)
				local key = class_name .. "." .. method_name
				H.equal(hooks[key], nil, "duplicate menu-preview hook " .. key)
				hooks[key] = { kind = "hook", callback = callback }
				hook_order[#hook_order + 1] = key
			end,
			hook_safe = function(_, class_name, method_name, callback)
				local key = class_name .. "." .. method_name
				H.equal(hooks[key], nil, "duplicate menu-preview hook " .. key)
				hooks[key] = { kind = "hook_safe", callback = callback }
				hook_order[#hook_order + 1] = key
			end,
		}
		local install = dofile(repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_menu_preview_owner.lua")
		install(mod, {
			om = om, dbg = function() end, dbg_alert = function() end,
			resolve_field = function() end,
			is_unit = options.is_unit or function() return false end,
			transform_unit = function() end,
			apply_cwv_hand_transform = options.apply_cwv_hand_transform
				or function() end,
			transform_map = {}, skin_transform_map = {}, crowbill_transform_by_unit = {},
			get_mod = options.get_mod or function() return nil end,
		})
		return om, hooks, hook_order, mod
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
		for name, state in pairs(saved) do
			rawset(_G, name, state.present and state.value or nil)
		end
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
		for name, state in pairs(saved) do
			rawset(_G, name, state.present and state.value or nil)
		end
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
			local bid = item and item.backend_id or "missing"
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
			surfaces = {},
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
			}
		end
		for _, surface in ipairs({
			"owner_1p", "owner_3p", "inventory_preview", "illusion_browser",
		}) do
			local edge = (surface == "owner_1p" or surface == "owner_3p")
				and "equip" or "preview_open"
			add_row(surface, "ranged", edge, live.identity)
			add_row(surface, "melee", edge, live.identity)
		end
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
		end)
		for name, state in pairs(saved) do
			rawset(_G, name, state.present and state.value or nil)
		end
		if not ok then error(err) end
	end)

	H.test("Old Musket binds one authored material and never paints native textures", function()
		local policy = dofile(policy_path)
		local bound, painted = {}, 0
		policy.set_resource_residency({
			VERSION = "test",
			texture_set_resident = function(bindings)
				H.equal(#bindings, 5)
				return true, "resident"
			end,
			material_resident = function(material)
				H.equal(material, policy.MATERIAL)
				return true, "resident"
			end,
			unit_materials_resident = function(unit)
				H.equal(unit, "musket-unit")
				return true, "resident", 1
			end,
		})
		local unit_api = {
			alive = function(unit) return unit == "musket-unit" end,
			set_all_materials = function(unit, material)
				bound[#bound + 1] = { unit = unit, material = material }
			end,
			set_texture_for_materials = function()
				painted = painted + 1
			end,
		}
		local retained, count = policy.apply_material("musket-unit", nil, {
			unit = unit_api,
			mesh = {},
			application = { can_get = function() return true end },
		})
		H.equal(retained, true)
		H.equal(count, 5)
		H.equal(#bound, 1)
		H.equal(bound[1].material, policy.MATERIAL)
		H.equal(painted, 0)
		H.equal(policy.PREVIEW_MATERIAL, policy.MATERIAL)
		H.equal(policy.apply_textures, policy.apply_material,
			"compatibility name must delegate to the authored-material binder")
		H.truthy(policy_source:find('function M.apply_material(unit, _, deps)', 1, true))
		H.truthy(policy_source:find('pcall(unit_api.set_all_materials, unit, M.MATERIAL)', 1, true))
		H.equal(policy_source:find('unit_api.set_texture_for_materials', 1, true), nil)
		H.equal(policy_source:find('Unit.set_texture_for_materials(unit', 1, true), nil)
		H.equal(policy_source:find('pcall(Material.set_texture', 1, true), nil)
		H.truthy(source:find('_om._apply_old_musket_appearance = _om.old_musket_preview.apply_material', 1, true))
	end)

	H.test("Old Musket menu owner registers exactly its eight lifecycle hooks", function()
		local _, hooks, order = install_menu_owner()
		H.deep_equal(order, {
			"TeamPreviewer._spawn_hero",
			"HeroWindowItemCustomization._setup_illusions",
			"HeroPreviewer._spawn_item",
			"MenuWorldPreviewer._spawn_item",
			"HeroPreviewer._destroy_item_units_by_slot",
			"LootItemUnitPreviewer._destroy_units",
			"LootItemUnitPreviewer.spawn_units",
			"LootItemUnitPreviewer._enable_item_units_visibility",
		})
		H.equal(hooks["LootItemUnitPreviewer.spawn_units"].kind, "hook")
		H.equal(hooks[
			"LootItemUnitPreviewer._enable_item_units_visibility"].kind, "hook_safe")
		H.equal(hooks[
			"HeroWindowWeaveProperties._create_item_previewer"], nil,
			"CWV must consume CIM's provider instead of registering a competing constructor hook")
	end)

	H.test("Old Musket HeroPreviewer rewrites and preserves the exact melee attachment profile", function()
		local character, weapon = {}, {}
		local rifle_linking, polearm_linking = attachment_recipe(), attachment_recipe()
		local left_path = "units/vanilla/left_decoy_3p"
		local spawn_data = {
			{
				left_hand = true, item_slot_type = "ranged", slot_index = 2,
				unit_name = left_path,
			},
			{
				right_hand = true, item_slot_type = "ranged", slot_index = 2,
				unit_name = MUSKET_UNIT_3P,
				unit_attachment_node_linking = rifle_linking,
			},
		}
		local info = {
			name = "es_handgun", backend_id = "musket-exact-path",
			item_data = { mod_data = { cwv_musket_stance = "melee" } },
			spawn_data = spawn_data,
		}
		local reconciled_context, armed_record
		local _, hooks = install_menu_owner({
			preview_transform = function()
				return { item_key = "cwv_es_musket_old" }
			end,
			is_unit = function(unit) return unit == weapon end,
			reconcile = function(_, surface, edge, _, mode, context)
				H.equal(surface, "inventory_preview")
				H.equal(edge, "instance_load")
				H.equal(mode, "melee")
				reconciled_context = context
				return { retained = true }
			end,
			pose_arm = function(_, record)
				armed_record = record
				return true
			end,
		})
		local previous_unit = rawget(_G, "Unit")
		local previous_weapons = rawget(_G, "Weapons")
		rawset(_G, "Unit", { alive = function(unit) return unit ~= nil end })
		rawset(_G, "Weapons", {
			old_musket_template = {
				wield_anim = "to_handgun",
				right_hand_attachment_node_linking = { third_person = rifle_linking },
			},
			old_musket_template_melee = {
				wield_anim = "to_2h_spear",
				right_hand_attachment_node_linking = { third_person = polearm_linking },
			},
		})
		local ok, err = pcall(function()
			local previewer = {
				character_unit = character,
				_wielded_slot_type = "ranged",
				_current_career_name = "es_huntsman",
				_item_info_by_slot = { ranged = info },
				_equipment_units = { [2] = { right = weapon } },
			}
			local native_calls = 0
			hooks["HeroPreviewer._spawn_item"].callback(function(self, item_name, rows)
				native_calls = native_calls + 1
				H.equal(self, previewer)
				H.equal(item_name, "es_handgun")
				H.equal(rows, spawn_data)
				H.equal(rows[2].unit_attachment_node_linking, polearm_linking,
					"the melee recipe must be installed before vanilla links the unit")
			end, previewer, "es_handgun", spawn_data)
			H.equal(native_calls, 1)
			H.truthy(reconciled_context)
			H.equal(reconciled_context.unit_name, MUSKET_UNIT_3P)
			H.equal(reconciled_context.attachment_profile, HELD_POLEARM_PROFILE)
			H.truthy(armed_record)
			H.equal(armed_record.unit_name, MUSKET_UNIT_3P)
			H.equal(armed_record.attachment_profile, HELD_POLEARM_PROFILE)
			H.equal(armed_record.attachment_node_linking, polearm_linking)
			H.equal(armed_record.slot_index, 2)
			H.equal(armed_record.unit_name == left_path, false,
				"left-first spawn order must never select the decoy path")
		end)
		rawset(_G, "Unit", previous_unit)
		rawset(_G, "Weapons", previous_weapons)
		if not ok then error(err, 0) end
	end)

	H.test("Old Musket character preview hooks preserve raw rows when attachment preparation rejects", function()
		local hook_names = {
			"HeroPreviewer._spawn_item",
			"MenuWorldPreviewer._spawn_item",
		}
		local cases = {
			{
				name = "ambiguous recipes",
				make = function()
					local shared = attachment_recipe()
					return shared, shared, nil
				end,
			},
			{
				name = "malformed polearm recipe",
				make = function()
					return attachment_recipe(), { wielded = {} }, nil
				end,
			},
			{
				name = "foreign profile vocabulary",
				make = function()
					return attachment_recipe(), attachment_recipe(), {
						held_3p_rifle_character = "foreign_rifle_profile",
						held_3p_polearm_character = HELD_POLEARM_PROFILE,
						display_3p_rifle = DISPLAY_PROFILE,
					}
				end,
			},
		}

		for _, hook_name in ipairs(hook_names) do
			for _, case in ipairs(cases) do
				local rifle_linking, polearm_linking, profiles = case.make()
				local original_linking = attachment_recipe()
				local spawn_data = { {
					right_hand = true, item_slot_type = "ranged", slot_index = 2,
					unit_name = MUSKET_UNIT_3P,
					unit_attachment_node_linking = original_linking,
				} }
				local info = {
					name = "es_handgun", backend_id = "musket-rejected-prepare",
					item_data = { mod_data = { cwv_musket_stance = "melee" } },
					spawn_data = spawn_data,
				}
				local reconciles = 0
				local _, hooks = install_menu_owner({
					attachment_profiles = profiles,
					preview_transform = function()
						return { item_key = "cwv_es_musket_old" }
					end,
					reconcile = function()
						reconciles = reconciles + 1
					end,
				})
				local previous_weapons = rawget(_G, "Weapons")
				rawset(_G, "Weapons", {
					old_musket_template = {
						right_hand_attachment_node_linking = { third_person = rifle_linking },
					},
					old_musket_template_melee = {
						right_hand_attachment_node_linking = { third_person = polearm_linking },
					},
				})
				local native_calls = 0
				local ok, err = pcall(function()
					local previewer = {
						_wielded_slot_type = "ranged",
						_item_info_by_slot = { ranged = info },
					}
					hooks[hook_name].callback(function(_, item_name, rows)
						native_calls = native_calls + 1
						H.equal(item_name, "es_handgun")
						H.equal(rows, spawn_data)
						H.equal(rows[1].unit_attachment_node_linking, original_linking,
							hook_name .. " mutated the raw row for " .. case.name)
					end, previewer, "es_handgun", spawn_data)
				end)
				rawset(_G, "Weapons", previous_weapons)
				if not ok then error(err, 0) end
				H.equal(native_calls, 1)
				H.equal(spawn_data[1].unit_attachment_node_linking, original_linking)
				H.equal(reconciles, 0,
					"rejected preparation must suppress CWV post-processing")
			end
		end
	end)

	H.test("Old Musket Team preview is terminally downgraded before vanilla spawn", function()
		local vanilla =
			"units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1_3p"
		local marker = "_cwv_mod_unit_preview_fallback_v1"
		local spawn_data = { {
			right_hand = true, item_slot_type = "ranged", slot_index = 2,
			unit_name = MUSKET_UNIT_3P,
			unit_attachment_node_linking = attachment_recipe(),
		} }
		local info = { name = "es_handgun", backend_id = "team-old-musket",
			spawn_data = spawn_data }
		local reconciles = 0
		local _, hooks = install_menu_owner({
			preview_transform = function()
				return { item_key = "cwv_es_musket_old" }, info, "ranged"
			end,
			reconcile = function() reconciles = reconciles + 1 end,
		})
		local native_calls = 0
		hooks["HeroPreviewer._spawn_item"].callback(function(_, _, rows)
			native_calls = native_calls + 1
			H.equal(rows[1].unit_name, vanilla)
			H.equal(rows[1][marker], vanilla,
				"unsupported Team fallback must be terminal downstream")
		end, { _cwv_team_preview = true }, "es_handgun", spawn_data)
		H.equal(native_calls, 1)
		H.equal(reconciles, 0,
			"unsupported Team preview must not enter the appearance owner")
	end)

	H.test("Old Musket consumes CIM's exact public preview-context provider", function()
		local cim_runtime = dofile(repo_root
			.. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_forge_preview.lua")
		local cim_hooks = {}
		local cim_mod = {}
		function cim_mod:hook(class_name, method_name, callback)
			local key = class_name .. "." .. method_name
			H.equal(cim_hooks[key], nil, "duplicate CIM context hook " .. key)
			cim_hooks[key] = callback
		end
		local active = true
		local installed = cim_runtime.install({
			mod = cim_mod,
			policy = { properties_preview_position = function() return nil end },
			is_active = function() return active end,
			unit_api = { alive = function() return false end },
			vector3 = function() end,
			vector3_box = function() end,
			printf = function() end,
		})
		H.equal(installed, true)
		local om = install_menu_owner({
			get_mod = function(id)
				H.equal(id, "cim_dev")
				return cim_mod
			end,
		})

		local constructors = {
			overview = function(func, self, ...)
				return cim_runtime.invoke_constructor(cim_mod, "overview", func, self, ...)
			end,
			weapons = assert(cim_hooks[
				"HeroWindowWeaveForgeWeapons._create_item_previewer"]),
			properties = assert(cim_hooks[
				"HeroWindowWeaveProperties._create_item_previewer"]),
		}
		for _, constructor in ipairs({ "overview", "weapons", "properties" }) do
			local item = {
				backend_id = "musket-" .. constructor,
				data = { key = "cwv_es_musket_old", item_type = "ranged" },
			}
			local previewer = constructors[constructor](function()
				return { _item = item }
			end, {}, {}, item)
			local context = om._cwv_cim_preview_context(previewer)
			H.truthy(context)
			H.equal(context.constructor, constructor)
			H.equal(context.backend_id, "musket-" .. constructor)
			H.equal(om._cwv_loot_preview_surface(previewer), "cim_preview")
		end

		active = false
		local native = {}
		local inactive = constructors.weapons(function() return native end,
			{}, {}, { backend_id = "inactive" })
		H.equal(inactive, native)
		H.equal(om._cwv_loot_preview_surface(inactive), "illusion_browser")
		H.equal(om._cwv_loot_preview_surface({}), "illusion_browser")

		local valid = {
			contract = "cim_preview_context_v1", surface = "cim_preview",
			provider = "cim_dev", constructor = "weapons", generation = 1,
			backend_id = "valid-musket", exact_backend_identity = true,
		}
		for field, bad in pairs({
			contract = "foreign_contract", surface = "inventory_preview",
			provider = "foreign", constructor = "unknown", generation = 0,
			backend_id = "", exact_backend_identity = false,
		}) do
			local marker = {}
			for key, value in pairs(valid) do marker[key] = value end
			marker[field] = bad
			H.equal(om._cwv_loot_preview_surface({ _cim_preview_context = marker,
				_item = { backend_id = "valid-musket" } }),
				"cim_preview", "malformed CIM marker must fail closed as CIM: " .. field)
		end
		for _, bad_generation in ipairs({ 1.5, math.huge }) do
			local marker = {}
			for key, value in pairs(valid) do marker[key] = value end
			marker.generation = bad_generation
			local rejected_generation, generation_reason = om._cwv_cim_preview_context({
				_cim_preview_context = marker,
				_item = { backend_id = "valid-musket" },
			})
			H.equal(rejected_generation, nil)
			H.equal(generation_reason, "context_invalid")
		end
		local mismatched = {}
		for key, value in pairs(valid) do mismatched[key] = value end
		H.equal(om._cwv_loot_preview_surface({ _cim_preview_context = mismatched,
			_item = { backend_id = "another-musket" } }), "cim_preview")
		local rejected, reason = om._cwv_cim_preview_context({
			_cim_preview_context = mismatched,
			_item = { backend_id = "another-musket" },
		})
		H.equal(rejected, nil)
		H.equal(reason, "identity_mismatch")
	end)

	H.test("Old Musket Loot preview retries only on the visible stable edge", function()
		local cim_runtime = dofile(repo_root
			.. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_forge_preview.lua")
		local cim_mod = { hook = function() end }
		H.truthy(cim_runtime.install({
			mod = cim_mod,
			policy = { properties_preview_position = function() return nil end },
			is_active = function() return true end,
			unit_api = { alive = function() return false end },
			vector3 = function() end,
			vector3_box = function() end,
			printf = function() end,
		}))
		local previewer = cim_runtime.invoke_constructor(cim_mod, "weapons",
			function() return {} end, {}, {}, {
				backend_id = "old-musket-instance",
				data = { key = "cwv_es_musket_old", item_type = "ranged" },
			})
		local item = {
			backend_id = "old-musket-instance",
			data = { key = "es_handgun", item_type = "ranged" },
		}
		local descriptor = { item_key = "cwv_es_musket_old", mode = "melee" }
		local calls = {}
		local om, hooks = install_menu_owner({
			get_mod = function(id)
				H.equal(id, "cim_dev")
				return cim_mod
			end,
			preview_descriptor = function(received)
				H.equal(received, item)
				return descriptor
			end,
			preview_targets = function(received, units, spawn_data)
				H.equal(received, descriptor)
				H.equal(#units, 1)
				H.equal(#spawn_data, 1)
				return units
			end,
			is_unit = function(unit) return type(unit) == "table" end,
			reconcile = function(unit, surface, edge, received, mode, context)
				calls[#calls + 1] = {
					unit = unit, surface = surface, edge = edge,
					item = received, mode = mode, context = context,
				}
				return { retained = edge == "preview_open" }
			end,
		})
		previewer._item = item
		local unit = {}
		local spawn_data = {
			{ unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p" },
		}
		local spawn = hooks["LootItemUnitPreviewer.spawn_units"].callback
		local native_calls = 0
		local units = spawn(function(received_self, received_spawn_data)
			native_calls = native_calls + 1
			H.equal(received_self, previewer)
			H.equal(received_spawn_data, spawn_data)
			return { unit }
		end, previewer, spawn_data)
		H.equal(native_calls, 1)
		H.equal(units[1], unit)
		H.equal(#calls, 1)
		H.equal(calls[1].surface, "cim_preview")
		H.equal(calls[1].edge, "instance_load")
		H.equal(calls[1].item, item)
		H.equal(calls[1].mode, "melee")
		H.equal(calls[1].context.unit_name, spawn_data[1].unit_name)
		H.equal(calls[1].context.attachment_profile, DISPLAY_PROFILE)
		H.equal(calls[1].context.cim_generation,
			previewer._cim_preview_context.generation)

		previewer._spawned_units = units
		previewer._units_to_spawn = spawn_data
		local visibility = hooks[
			"LootItemUnitPreviewer._enable_item_units_visibility"].callback
		visibility(previewer, "world", "unit", false)
		H.equal(#calls, 1, "hidden/teardown transitions must not consume the retry")
		visibility(previewer, "world", "unit", true)
		H.equal(#calls, 2)
		H.equal(calls[2].surface, "cim_preview")
		H.equal(calls[2].edge, "preview_open")
		H.equal(calls[2].unit, unit)
		H.equal(calls[2].context.unit_name, spawn_data[1].unit_name)
		H.equal(calls[2].context.attachment_profile, DISPLAY_PROFILE)

		local ordinary = { _item = item }
		om._cwv_reconcile_old_musket_loot(ordinary, units, spawn_data,
			"instance_load")
		H.equal(calls[3].surface, "illusion_browser")
		H.equal(calls[3].edge, "instance_load")
		H.equal(calls[3].context.attachment_profile, DISPLAY_PROFILE)
	end)

	H.test("Old Musket CIM evidence rejects late provider generations", function()
		local provider = {
			_cim_preview_context_for = function(previewer)
				return previewer and previewer._cim_preview_context
			end,
		}
		local calls = 0
		local om = install_menu_owner({
			get_mod = function() return provider end,
			preview_descriptor = function()
				return { item_key = "cwv_es_musket_old", mode = "ranged" }
			end,
			preview_targets = function(_, units) return units end,
			is_unit = function() return true end,
			reconcile = function() calls = calls + 1 return { retained = true } end,
		})
		local function previewer(generation, backend_id)
			return {
				_item = { backend_id = backend_id },
				_cim_preview_context = {
					contract = "cim_preview_context_v1", surface = "cim_preview",
					provider = "cim_dev", constructor = "weapons",
					generation = generation, backend_id = backend_id,
					exact_backend_identity = true,
				},
			}
		end
		local rows = { { unit_name = MUSKET_UNIT_3P } }
		local units = { {} }
		local first = previewer(1, "musket-one")
		local second = previewer(2, "musket-two")
		om._cwv_reconcile_old_musket_loot(
			previewer(math.huge, "poison-attempt"), units, rows, "instance_load")
		om._cwv_reconcile_old_musket_loot(
			previewer(1.5, "fraction-attempt"), units, rows, "instance_load")
		H.equal(calls, 0,
			"non-finite/fractional provider generations must not poison the watermark")
		om._cwv_reconcile_old_musket_loot(first, units, rows, "instance_load")
		H.equal(calls, 1)
		om._cwv_reconcile_old_musket_loot(second, units, rows, "instance_load")
		H.equal(calls, 2)
		om._cwv_reconcile_old_musket_loot(first, units, rows, "preview_open")
		H.equal(calls, 2, "late generation one must not re-arm after generation two")
		om._cwv_reconcile_old_musket_loot(second, units, rows, "preview_open")
		H.equal(calls, 3, "the current generation remains admissible")
		second._cim_preview_context.backend_id = "foreign"
		om._cwv_reconcile_old_musket_loot(second, units, rows, "preview_open")
		H.equal(calls, 3, "marker/item identity mismatch must fail closed")
	end)

	H.test("Old Musket real render call sites route through the shared resolver", function()
        -- issue 474: the recurring failure class was one render surface drifting
        -- off the shared resolver (husk shows the base handgun, inventory preview
        -- drops the stance pose, the Athanor shows nothing). Assert every surface
        -- routes through the single applicator/descriptor set so a refactor cannot
        -- silently drop one again.

        -- (1) owner in-world spawn: both 1P and 3P enter the shared applicator.
		H.truthy(source:find('_om.old_musket_appearance.reconcile(', 1, true))
		H.truthy(source:find('"owner_1p"', 1, true))
		H.truthy(source:find('"owner_3p"', 1, true))

		-- (1b) locally simulated bot 3P: GearUtils.create_equipment has its own
		-- adapter and must not be mistaken for the remote-husk spawn path.
		H.truthy(source:find('is_bot and "bot" or "owner_3p", "instance_load"', 1, true),
			"bot create_equipment must enter the shared Old Musket reconciler")

		-- (2) remote husk 3P: stance resolved from the bounded channel, not the wire.
		H.truthy(source:find('_om.old_musket_appearance.reconcile(weapon_unit_3p, "husk", "instance_load"', 1, true))
		H.truthy(source:find('rendered_unit_name = rendered_unit_name .. "_3p"', 1, true))
		H.truthy(source:find('unit_name = rendered_unit_name,', 1, true),
			"husk adapter must prove the spawned 3P alias, not the base unit path")
		H.truthy(source:find('_om.old_musket_appearance.reconcile(unit, "husk", "peer_ready"', 1, true))
        H.truthy(source:find('owner_unit_3p, slot_name, hinted_player)', 1, true),
            "remote spawn must resolve stance from the exact extension player and presented slot")

		-- (3) inventory / hero character preview: transform + stance wield-anim replay.
		H.truthy(source:find('"inventory_preview", "preview_open"', 1, true))
		H.truthy(source:find('Unit.animation_event, pending.character_unit, pending.wield_event)', 1, true))
		H.truthy(source:find('dispatched=%s error=%s', 1, true),
			"preview pose receipt must distinguish a successful dispatch from an attempted one")
		H.truthy(source:find('_om.old_musket_preview_pose.install(mod, function(unit, _, mode, record)', 1, true))
		H.truthy(source:find('record and record.surface or "inventory_preview", "preview_open"', 1, true),
			"final preview stability edge must re-enter the shared appearance owner")
		H.truthy(source:find('unit_name = record and record.unit_name,', 1, true),
			"stable preview retry must preserve the exact observed unit identity")
		H.truthy(source:find('[cwv:474/792] preview transform retained', 1, true))

		-- (4) illusion browser and CIM share LootItemUnitPreviewer. CWV consumes
		-- CIM's exact-instance public context across all three constructors and
		-- owns one construction edge plus one source-backed stable edge.
		H.truthy(source:find('local function _cwv_loot_preview_surface(previewer)', 1, true))
		H.truthy(source:find('_get_mod, "cim_dev"', 1, true))
		H.truthy(source:find('provider._cim_preview_context_for', 1, true))
		H.truthy(source:find('context.contract ~= "cim_preview_context_v1"', 1, true))
		H.truthy(source:find('_reconcile_old_musket_loot(self, units, spawn_data, "instance_load")', 1, true))
		H.truthy(source:find('_reconcile_old_musket_loot(self, self._spawned_units,', 1, true))
		H.truthy(source:find('self._units_to_spawn, "preview_open")', 1, true))
		H.equal(source:find('mod:hook("HeroWindowWeaveProperties", "_create_item_previewer"', 1, true), nil)
        H.truthy(source:find('_om._old_musket_preview_descriptor(item)', 1, true))

		-- (5) TeamPreviewer is explicitly marked, and unsupported Old Musket
		-- lobby/score rows are terminally returned to the resident Handgun.
		H.truthy(source:find('hero_previewer._cwv_team_preview = true', 1, true))
		H.truthy(source:find('if self and self._cwv_team_preview then', 1, true))
		H.truthy(source:find('row[marker] = fallback', 1, true))

		-- Each parent frame selects one explicit profile; a held-character offset
		-- must never leak into the camera-world display carrier.
		H.truthy(source:find('_old_musket_attachment_profile(', 1, true))
		H.truthy(source:find('attachment_profile = _om.old_musket_attachment_profiles.display_3p_rifle', 1, true))
		H.truthy(source:find('attachment_profile = old_musket_attachment_profile', 1, true))

        -- The in-keep executable half of this guard ships in the bundle too.
		H.truthy(source:find('issue474_old_musket_presentation_surface_coverage', 1, true))
	end)

	H.test("Old Musket preview resolves the exact spawned slot with duplicate item names", function()
		local template = {
			wield_anim = "default",
			wield_anim_3p = "default_3p",
			wield_anim_career = { es_huntsman = "career" },
			wield_anim_career_3p = { es_huntsman = "career_3p" },
		}
		H.equal(pose_policy.resolve_wield_event(template, "es_huntsman"), "career_3p")
		H.equal(pose_policy.resolve_wield_event(template, "es_mercenary"), "default",
			"Hero preview precedence does not consult generic wield_anim_3p")
		H.equal(pose_policy.resolve_husk_wield_event(template, "es_mercenary"), "default_3p")
		template.wield_anim_career_3p.es_huntsman = nil
		H.equal(pose_policy.resolve_wield_event(template, "es_huntsman"), "career")
		H.equal(pose_policy.resolve_husk_wield_event(template, "es_huntsman"), "default_3p",
			"native SimpleHusk precedence prefers generic 3P over career-generic")
		template.wield_anim_3p = nil
		H.equal(pose_policy.resolve_husk_wield_event(template, "es_huntsman"), "career")

		local melee_spawn = {
			{ item_slot_type = "melee", slot_index = 1 },
			{ item_slot_type = "melee", slot_index = 1 },
		}
		local ranged_spawn = { { item_slot_type = "ranged", slot_index = 2 } }
		local melee = { name = "es_handgun", backend_id = "musket-melee",
			spawn_data = melee_spawn }
		local ranged = { name = "es_handgun", backend_id = "musket-ranged",
			spawn_data = ranged_spawn }
		local previewer = { _item_info_by_slot = { melee = melee, ranged = ranged } }

		local slot, info, index = pose_policy.resolve_spawn_slot(previewer,
			"es_handgun", ranged_spawn)
		H.equal(slot, "ranged")
		H.equal(info, ranged)
		H.equal(index, 2)
		H.equal(info.backend_id, "musket-ranged")

		local cloned_spawn = { { item_slot_type = "ranged", slot_index = 2 } }
		slot, info, index = pose_policy.resolve_spawn_slot(previewer,
			"es_handgun", cloned_spawn)
		H.equal(slot, nil)
		H.equal(info, nil)
		H.equal(index, "spawn_changed")

		local ambiguous = {
			{ item_slot_type = "melee", slot_index = 1 },
			{ item_slot_type = "ranged", slot_index = 2 },
		}
		slot, info, index = pose_policy.resolve_spawn_slot(previewer,
			"es_handgun", ambiguous)
		H.equal(slot, nil)
		H.equal(info, nil)
		H.equal(index, "spawn_ambiguous")
	end)

	H.test("Old Musket preview path resolver rejects missing malformed and stale right-hand rows", function()
		local rifle_linking, polearm_linking = attachment_recipe(), attachment_recipe()
		local left = {
			left_hand = true, item_slot_type = "ranged", slot_index = 2,
			unit_name = "units/vanilla/left_first_3p",
		}
		local right = {
			right_hand = true, item_slot_type = "ranged", slot_index = 2,
			unit_name = MUSKET_UNIT_3P,
			unit_attachment_node_linking = rifle_linking,
		}
		local info = { spawn_data = { left, right } }
		local row, reason = pose_policy.resolve_right_hand_spawn_row(
			info, "ranged", MUSKET_UNIT_3P)
		H.equal(row, right)
		H.equal(reason, "ready")
		local profile
		profile, reason = pose_policy.resolve_character_attachment_profile(
			right, "ranged", rifle_linking, polearm_linking, {
				held_3p_rifle_character = HELD_RIFLE_PROFILE,
				held_3p_polearm_character = HELD_POLEARM_PROFILE,
			})
		H.equal(profile, HELD_RIFLE_PROFILE)
		H.equal(reason, "ready")
		profile, reason = pose_policy.resolve_character_attachment_profile(
			right, "melee", rifle_linking, polearm_linking)
		H.equal(profile, nil)
		H.equal(reason, "attachment_stance_mismatch")
		right.unit_attachment_node_linking = attachment_recipe()
		profile, reason = pose_policy.resolve_character_attachment_profile(
			right, "ranged", rifle_linking, polearm_linking)
		H.equal(profile, nil)
		H.equal(reason, "attachment_unknown")
		right.unit_attachment_node_linking = rifle_linking

		row, reason = pose_policy.resolve_right_hand_spawn_row(
			info, "ranged", "units/vanilla/es_handgun_3p")
		H.equal(row, nil)
		H.equal(reason, "unit_changed")

		row, reason = pose_policy.resolve_right_hand_spawn_row(
			{ spawn_data = { left } }, "ranged", MUSKET_UNIT_3P)
		H.equal(row, nil)
		H.equal(reason, "unit_missing")

		row, reason = pose_policy.resolve_right_hand_spawn_row({
			spawn_data = { {
				right_hand = true, item_slot_type = "ranged", slot_index = 2,
				unit_name = "",
			} },
		}, "ranged", MUSKET_UNIT_3P)
		H.equal(row, nil)
		H.equal(reason, "unit_invalid")

		row, reason = pose_policy.resolve_right_hand_spawn_row({
			spawn_data = { right, {
				right_hand = true, item_slot_type = "ranged", slot_index = 2,
				unit_name = MUSKET_UNIT_3P,
			} },
		}, "ranged", MUSKET_UNIT_3P)
		H.equal(row, nil)
		H.equal(reason, "spawn_ambiguous")
	end)

	H.test("Old Musket preview pose waits for and consumes one stable edge", function()
		local character = {}
		local polearm_linking = attachment_recipe()
		local spawn_data = { {
			right_hand = true, item_slot_type = "ranged", slot_index = 2,
			unit_name = MUSKET_UNIT_3P,
			unit_attachment_node_linking = polearm_linking,
		} }
		local previewer = {
			character_unit = character,
			_wielded_slot_type = "ranged",
			_item_info_by_slot = {
				ranged = {
					name = "es_handgun", backend_id = "musket-1",
					spawn_data = spawn_data,
				},
			},
		}
		local record = {
			character_unit = character,
			item_name = "es_handgun",
			backend_id = "musket-1",
			slot_type = "ranged",
			slot_index = 2,
			stance = "melee",
			attachment_profile = HELD_POLEARM_PROFILE,
			attachment_node_linking = polearm_linking,
			unit_name = MUSKET_UNIT_3P,
			wield_event = "to_2h_spear",
		}

		H.truthy(pose_policy.arm(previewer, record))
		local stored = previewer._cwv_old_musket_pose_pending
		H.truthy(stored)
		H.equal(stored == record, false)
		local pending, reason = pose_policy.take_when_stable(previewer, false)
		H.equal(pending, nil)
		H.equal(reason, "loading")
		H.equal(previewer._cwv_old_musket_pose_pending, stored)

		pending, reason = pose_policy.take_when_stable(previewer, true)
		H.equal(pending, stored)
		H.equal(reason, "ready")
		H.equal(pending.stance, "melee")
		H.equal(pending.attachment_profile, HELD_POLEARM_PROFILE)
		H.equal(pending.unit_name, MUSKET_UNIT_3P)
		H.equal(previewer._cwv_old_musket_pose_pending, nil)

		pending, reason = pose_policy.take_when_stable(previewer, true)
		H.equal(pending, nil)
		H.equal(reason, "not_armed")
	end)

	H.test("Old Musket preview pose rejects invalid and stale generations", function()
		local function armed()
			local character = {}
			local rifle_linking = attachment_recipe()
			local spawn_data = { {
				right_hand = true, item_slot_type = "ranged", slot_index = 2,
				unit_name = MUSKET_UNIT_3P,
				unit_attachment_node_linking = rifle_linking,
			} }
			local previewer = {
				character_unit = character,
				_wielded_slot_type = "ranged",
				_item_info_by_slot = {
					ranged = {
						name = "es_handgun", backend_id = "musket-1",
						spawn_data = spawn_data,
					},
				},
			}
			H.truthy(pose_policy.arm(previewer, {
				character_unit = character,
				item_name = "es_handgun",
				backend_id = "musket-1",
				slot_type = "ranged",
				slot_index = 2,
				attachment_profile = HELD_RIFLE_PROFILE,
				attachment_node_linking = rifle_linking,
				unit_name = MUSKET_UNIT_3P,
				wield_event = "to_handgun",
				stance = "ranged",
			}))
			return previewer, rifle_linking
		end

		H.equal(pose_policy.arm({}, { slot_type = "ranged" }), false)
		H.equal(pose_policy.arm({}, {
			character_unit = {}, item_name = "es_handgun", backend_id = string.rep("x", 129),
			slot_type = "ranged", slot_index = 2, stance = "ranged",
			attachment_profile = HELD_RIFLE_PROFILE,
			attachment_node_linking = attachment_recipe(),
			unit_name = MUSKET_UNIT_3P, wield_event = "to_handgun",
		}), false)
		H.equal(pose_policy.arm({}, {
			character_unit = {}, item_name = "es_handgun", backend_id = "musket-1",
			slot_type = "ranged", slot_index = 2, stance = "ranged",
			attachment_profile = HELD_RIFLE_PROFILE,
			attachment_node_linking = attachment_recipe(),
			unit_name = "", wield_event = "to_handgun",
		}), false)
		H.equal(pose_policy.arm({}, {
			character_unit = {}, item_name = "es_handgun", backend_id = "musket-1",
			slot_type = "ranged", slot_index = 2, stance = "ranged",
			attachment_profile = HELD_POLEARM_PROFILE,
			attachment_node_linking = attachment_recipe(),
			unit_name = MUSKET_UNIT_3P, wield_event = "to_handgun",
		}), false)
		local previewer = armed()
		previewer._wielded_slot_type = "melee"
		local pending, reason = pose_policy.take_when_stable(previewer, true)
		H.equal(pending, nil)
		H.equal(reason, "slot_changed")

		previewer = armed()
		previewer._item_info_by_slot.ranged.backend_id = "musket-2"
		pending, reason = pose_policy.take_when_stable(previewer, true)
		H.equal(pending, nil)
		H.equal(reason, "backend_changed")

		previewer = armed()
		previewer.character_unit = {}
		pending, reason = pose_policy.take_when_stable(previewer, true)
		H.equal(pending, nil)
		H.equal(reason, "character_changed")

		previewer = armed()
		previewer._item_info_by_slot.ranged.spawn_data[1].unit_name =
			"units/vanilla/es_handgun_3p"
		pending, reason = pose_policy.take_when_stable(previewer, true)
		H.equal(pending, nil)
		H.equal(reason, "unit_changed")

		previewer = armed()
		previewer._item_info_by_slot.ranged.spawn_data = {}
		pending, reason = pose_policy.take_when_stable(previewer, true)
		H.equal(pending, nil)
		H.equal(reason, "unit_missing")

		previewer = armed()
		previewer._item_info_by_slot.ranged.spawn_data[1].unit_name = false
		pending, reason = pose_policy.take_when_stable(previewer, true)
		H.equal(pending, nil)
		H.equal(reason, "unit_invalid")

		local original_linking
		previewer, original_linking = armed()
		previewer._item_info_by_slot.ranged.spawn_data[1]
			.unit_attachment_node_linking = attachment_recipe()
		pending, reason = pose_policy.take_when_stable(previewer, true)
		H.equal(pending, nil)
		H.equal(reason, "attachment_changed")
		H.truthy(original_linking)

		local reopened = armed()
		pending, reason = pose_policy.take_when_stable(reopened, true)
		H.truthy(pending)
		H.equal(reason, "ready")
	end)

	H.test("Old Musket crafted UUID identity does not regress to prefix-only gates", function()
        H.truthy(source:find('_om._cwv_key_for_item(_bid_for_tex, item_data)', 1, true))
        H.truthy(source:find('_spawn_cwv_key == "cwv_es_musket_old"', 1, true))
        H.truthy(source:find('_om._old_musket_bid_for_item = old_bid', 1, true))
        H.truthy(source:find('or item.ItemInstanceId', 1, true))
        H.equal(source:find('_bid_for_tex:match("^cwv_es_musket_old")', 1, true), nil)
        H.equal(source:find('or not bid:match("^cwv_es_musket_old")', 1, true), nil)
        H.truthy(source:find('issue484_crafted_old_musket_identity', 1, true))
    end)

    H.test("Old Musket authored-material bind fails closed before retention", function()
		H.truthy(policy_source:find('Old Musket appearance SKIP reason=%s detail=%s chat=false', 1, true))
		H.equal(policy_source:find('pcall(Material.set_texture', 1, true), nil)
		H.equal(policy_source:find('Unit.set_texture_for_materials(unit', 1, true), nil)
		local texture_at = assert(policy_source:find(
			'local ready, detail = M.texture_resources_ready(', 1, true))
		local bind_at = assert(policy_source:find(
			'ready, detail = M.bind_authored_material(unit, application_api, unit_api)',
			texture_at, true))
		local census_at = assert(policy_source:find(
			'ready, detail = M.unit_materials_ready(unit, unit_api, mesh_api)',
			bind_at, true))
		H.truthy(texture_at < bind_at and bind_at < census_at)
		H.truthy(source:find('issue742_old_musket_texture_material_preflight', 1, true))
		H.truthy(source:find('issue617_old_musket_preview_texture_consumer', 1, true))
		H.truthy(source:find(
			'resource preflight must fail closed with canonical not_resident and the exact denied albedo path',
			1, true))
		H.truthy(source:find('missing ~= "not_resident"', 1, true))
		H.truthy(source:find('color_map = denied_texture_path', 1, true))
		H.truthy(source:find('denied_path ~= denied_texture_path', 1, true))
		H.truthy(source:find('suppress_diagnostics = true', 1, true),
			"synthetic failures must not consume later live one-shot diagnostics")
	end)
end
