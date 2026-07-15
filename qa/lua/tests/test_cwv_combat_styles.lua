return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_combat_styles.lua")

	local function clone(value, seen)
		if type(value) ~= "table" then return value end
		seen = seen or {}
		if seen[value] then return seen[value] end
		local copy = {}; seen[value] = copy
		for key, child in pairs(value) do copy[clone(key, seen)] = clone(child, seen) end
		return copy
	end

	H.test("CWV Combat Styles expose deterministic multi-style family cycles", function()
		local current, style, family = policy.style("es_2h_sword")
		H.equal(current, "greatsword")
		H.equal(style.template, "two_handed_swords_template_1")
		H.equal(family, "greatsword")
		local next_id = policy.next_style("es_2h_sword", current)
		H.equal(next_id, "longsword")
		next_id = policy.next_style("es_2h_sword", next_id)
		H.equal(next_id, "bretonnian")
		next_id = policy.next_style("es_2h_sword", next_id)
		H.equal(next_id, "kerillian")
		next_id = policy.next_style("es_2h_sword", next_id)
		H.equal(next_id, "greatsword")
		H.equal(policy.style("cwv_es_longsword"), "longsword")
		H.equal(policy.style("es_bastard_sword"), "bretonnian")
		H.equal(policy.style("es_2h_hammer"), "kruber")
		H.equal(policy.next_style("es_2h_hammer", "kruber"), "warrior_priest")
		H.equal(policy.next_style("wh_2h_hammer", "warrior_priest"), "kruber")
		H.equal(policy.style("es_2h_heavy_spear"), "hunter")
		H.equal(policy.next_style("es_2h_heavy_spear", "hunter"), "infantry")
		H.equal(policy.style("cwv_es_infantry_spear"), nil)
	end)

	H.test("CWV Combat Style input descriptions never exceed the vanilla widget pool", function()
		local full = {
			{ input_action = "d_vertical", priority = 1 },
			{ input_action = "l2_r2", priority = 2 },
			{ input_action = "right_stick_press", priority = 3 },
			{ input_action = "show_gamercard", priority = 4 },
			{ input_action = "refresh", priority = 5 },
			{ input_action = "confirm", priority = 6 },
			{ input_action = "back", priority = 7 },
		}
		local bounded, mode = policy.bounded_style_actions(full, 7)
		H.equal(mode, "replaced")
		H.equal(#bounded, 7)
		H.equal(bounded[4].input_action, "special_1")
		H.equal(bounded[4].priority, 4)
		H.equal(full[4].input_action, "show_gamercard")

		local six = {}
		for index = 1, 6 do six[index] = full[index] end
		bounded, mode = policy.bounded_style_actions(six, 7)
		H.equal(mode, "appended")
		H.equal(#bounded, 7)
		H.equal(bounded[7].input_action, "special_1")

		local tiny = policy.bounded_style_actions(full, 3)
		H.equal(#tiny, 3)
		H.equal(tiny[3].input_action, "special_1")
	end)

	H.test("CWV console equipment row exposes a non-overlapping authored style control", function()
		local runtime = {
			describe = function(_, item)
				if item and item.name == "es_2h_heavy_spear" and item.backend_id then
					local style_id, style, family_id, member = policy.style(item.name, "hunter")
					return { item_key = item.name, identity = item.backend_id, style_id = style_id,
						style = style, family_id = family_id, member = member }
				end
			end,
		}
		local grid = {
			element = { passes = {} },
			content = { rows = 2, columns = 1 },
			style = {
				customize_hotspot_1_1 = { size = { 58, 58 }, offset = { 100, 210, 30 } },
				customize_item_hover_1_1 = { size = { 58, 58 }, offset = { 100, 210, 30 } },
				customize_hotspot_2_1 = { size = { 58, 58 }, offset = { 100, 110, 30 } },
				customize_item_hover_2_1 = { size = { 58, 58 }, offset = { 100, 110, 30 } },
			},
		}
		grid.content.item_1_1 = { name = "es_2h_heavy_spear", backend_id = "tuskgor_uuid" }
		grid.content.item_2_1 = { name = "es_handgun", backend_id = "handgun_uuid" }

		local installed, rows = policy.decorate_console_grid(grid, runtime)
		H.equal(installed, true)
		H.equal(rows, 2)
		H.equal(#grid.element.passes, 6)
		H.equal(grid.content.cwv_style_icon, "icon_switch")
		-- Decoration is layout-neutral until the populated item rows are known.
		H.equal(grid.style.customize_hotspot_1_1.offset[1], 100)
		H.equal(grid.style.customize_hotspot_1_1.offset[2], 210)
		H.equal(grid.style.customize_hotspot_2_1.offset[1], 100)
		H.equal(grid.style.customize_hotspot_2_1.offset[2], 110)
		H.equal(policy.refresh_console_row_layout(grid, runtime), 1)
		-- Eligible row: same x, style above cog, native hover follows cog.
		H.equal(grid.style.customize_hotspot_1_1.offset[1], 100)
		H.equal(grid.style.customize_hotspot_1_1.offset[2], 183)
		H.equal(grid.style.customize_item_hover_1_1.offset[2], 183)
		H.equal(grid.style.cwv_style_hotspot_1_1.offset[1], 104)
		H.equal(grid.style.cwv_style_hotspot_1_1.offset[2], 245)
		-- Ordinary row is exact vanilla, not globally displaced.
		H.equal(grid.style.customize_hotspot_2_1.offset[1], 100)
		H.equal(grid.style.customize_hotspot_2_1.offset[2], 110)
		H.equal(grid.style.customize_item_hover_2_1.offset[2], 110)

		local first_hotspot_pass = grid.element.passes[1]
		grid.content.cwv_style_hotspot_1_1.parent = grid.content
		H.equal(first_hotspot_pass.content_check_function(grid.content.cwv_style_hotspot_1_1), true)
		H.equal(grid.content.cwv_style_hotspot_1_1.cwv_next_style_label,
			"Switch to: Infantry Combat Style")
		grid.content.cwv_style_hotspot_2_1.parent = grid.content
		H.equal(grid.element.passes[4].content_check_function(grid.content.cwv_style_hotspot_2_1), false)
		H.equal(grid.content.cwv_style_hotspot_2_1.cwv_visible, false)

		grid.content.cwv_style_hotspot_1_1.on_pressed = true
		local item, suffix, row = policy.consume_console_style_press(grid.content, runtime)
		H.equal(item.backend_id, "tuskgor_uuid")
		H.equal(suffix, "_1_1")
		H.equal(row.family_id, "spear")
		H.equal(grid.content.cwv_style_hotspot_1_1.on_pressed, false)
		local pass_count = #grid.element.passes
		H.equal(policy.decorate_console_grid(grid, runtime), false)
		H.equal(#grid.element.passes, pass_count)
	end)

	H.test("CWV style transition cannot commit before its resource is ready", function()
		local saved, callbacks = nil, {}
		local fake_mod = {
			get = function() return nil end,
			set = function(_, key, value)
				saved = { key = key, value = clone(value) }
			end,
		}
		local runtime = policy.install(fake_mod, {
			acquire_style_resource = function(path, callback)
				H.equal(path, "units/beings/player/first_person_base/state_machines/melee/spear")
				callbacks[#callbacks + 1] = callback
				return true
			end,
		})
		local spear = { backend_id = "spear_uuid", name = "es_2h_heavy_spear" }
		local completed = {}
		local accepted, state = runtime:cycle_item(spear, nil, "test", true,
			function(changed, err) completed[#completed + 1] = { changed, err } end)
		H.equal(accepted, true)
		H.equal(state, "transition pending")
		H.equal(saved, nil)
		H.equal(runtime:describe(spear).style_id, "hunter")
		local duplicate, duplicate_err = runtime:cycle_item(spear, nil, "double", true)
		H.equal(duplicate, false)
		H.equal(duplicate_err, "transition pending")
		callbacks[1](false, "load failed")
		H.equal(saved, nil)
		H.equal(runtime:describe(spear).style_id, "hunter")
		H.equal(completed[1][1], false)

		accepted = runtime:cycle_item(spear, nil, "retry", true,
			function(changed, err) completed[#completed + 1] = { changed, err } end)
		H.equal(accepted, true)
		H.equal(saved, nil)
		callbacks[2](true)
		H.equal(completed[2][1], true)
		H.equal(saved.key, policy.SETTING_KEY)
		H.equal(saved.value.items.spear_uuid, "infantry")
		H.equal(runtime:describe(spear).style_id, "infantry")
	end)

	H.test("CWV Combat Style persistence is exact-instance and compact", function()
		local store = policy.normalize_store(nil)
		local changed = policy.set(store, "greatsword_a", "es_2h_sword", "longsword")
		H.equal(changed, true)
		H.equal(store.items.greatsword_a, "longsword")
		H.equal(store.items.greatsword_b, nil)
		changed = policy.set(store, "greatsword_b", "es_2h_sword", "kerillian")
		H.equal(changed, true)
		H.equal(store.items.greatsword_a, "longsword")
		H.equal(store.items.greatsword_b, "kerillian")
		changed = policy.set(store, "greatsword_a", "es_2h_sword", "greatsword")
		H.equal(changed, true)
		H.equal(store.items.greatsword_a, nil)
		local bad, err = policy.set(store, "greatsword_a", "es_2h_sword", "warrior_priest")
		H.equal(bad, false)
		H.equal(err, "unsupported style")
	end)

	H.test("CWV legacy style migration is lossless, deterministic, and fail closed", function()
		local saved = {
			uuid_c = { item_key = "cwv_es_longsword_blackguard", skin = nil,
				properties = { crit = 0.05 }, power_level = 287 },
			uuid_a = { item_key = "cwv_es_infantry_spear", skin = "cwv_es_infantry_spear_skin",
				trait = "keep_me" },
			uuid_b = { item_key = "cwv_es_longsword", skin = "cwv_il_wh_02",
				custom = { nested = true } },
			ordinary = { item_key = "es_1h_sword", skin = "ordinary_skin" },
		}
		local valid_skins = {
			cwv_tuskgor_spear_01 = "es_2h_heavy_spear",
			cwv_il_wh_02 = "es_2h_sword",
			cwv_es_longsword_blackguard_skin = "es_2h_sword",
		}
		local patches, err = policy.plan_legacy_migrations(saved,
			function(key) return key == "es_2h_sword" or key == "es_2h_heavy_spear" end,
			function(skin, target) return valid_skins[skin] == target end)
		H.equal(err, nil)
		H.equal(#patches, 3)
		H.equal(patches[1].identity, "uuid_a")
		H.equal(patches[1].target_item, "es_2h_heavy_spear")
		H.equal(patches[1].skin, "cwv_tuskgor_spear_01")
		H.equal(patches[2].identity, "uuid_b")
		H.equal(patches[2].target_item, "es_2h_sword")
		H.equal(patches[2].style_id, "longsword")
		H.equal(patches[2].skin, "cwv_il_wh_02")
		H.equal(patches[3].skin, "cwv_es_longsword_blackguard_skin")
		-- Planning is observation-only: every unrelated field and legacy key is
		-- untouched until the runtime has validated the complete transaction.
		H.equal(saved.uuid_c.item_key, "cwv_es_longsword_blackguard")
		H.equal(saved.uuid_c.properties.crit, 0.05)
		H.equal(saved.uuid_b.custom.nested, true)
		local rejected, reject_err = policy.plan_legacy_migrations(saved,
			function() return true end, function() return false end)
		H.equal(rejected, nil)
		H.truthy(reject_err:find("missing migration skin", 1, true))
		H.equal(saved.uuid_a.item_key, "cwv_es_infantry_spear")
	end)

	H.test("CWV Kerillian style clones donor timing and power references", function()
		local donor = {
			actions = { action_one = {
				light = { kind = "sweep", anim_time_scale = 1.2, damage_profile = "elf_light" },
				heavy = { kind = "sweep", anim_time_scale = 0.8, damage_profile = "elf_heavy" },
				block = { kind = "block" },
			} },
			wield_anim = "to_2h_sword_we",
		}
		local calls = {}
		local template = policy.build_kerillian_template(
			{ two_handed_swords_wood_elf_template = donor }, clone,
			function(source, prefix, modifiers)
				calls[source] = { prefix = prefix, modifiers = clone(modifiers) }
				return prefix .. source
			end)
		H.truthy(template)
		H.truthy(math.abs(template.actions.action_one.light.anim_time_scale - 1.02) < 0.000001)
		H.truthy(math.abs(template.actions.action_one.heavy.anim_time_scale - 0.68) < 0.000001)
		H.equal(template.actions.action_one.light.damage_profile, "cwv_style_kerillian_gs_elf_light")
		H.equal(calls.elf_light.modifiers.damage, 1)
		H.equal(calls.elf_light.modifiers.stagger, 1.15)
		H.equal(calls.elf_light.modifiers.cleave, 1.15)
		H.equal(template.wield_anim_career_3p.es_mercenary, "to_bastard_sword")
		H.equal(donor.actions.action_one.light.anim_time_scale, 1.2)
		H.equal(donor.actions.action_one.light.damage_profile, "elf_light")
		H.equal(donor.wield_anim_career_3p, nil)
	end)

	H.test("CWV Combat Style runtime resolves exact IDs and legacy defaults", function()
		local saved
		local fake_mod = {
			get = function(_, key)
				if key == policy.SETTING_KEY then
					return { schema = 1, items = { uuid_a = "kerillian" } }
				end
			end,
			set = function(_, key, value) saved = { key = key, value = clone(value) } end,
		}
		local runtime = policy.install(fake_mod, {
			cwv_key_for_item = function(backend_id)
				return backend_id == "legacy_cwv" and "cwv_es_longsword" or nil
			end,
			imperial_transform = { item_key = "imperial_test", right_hand_scale = { 1, 0.8, 0.9 } },
		})
		local a = runtime:describe({ backend_id = "uuid_a", name = "es_2h_sword" })
		H.equal(a.style_id, "kerillian")
		local b = runtime:describe({ backend_id = "uuid_b", name = "es_2h_sword" })
		H.equal(b.style_id, "greatsword")
		local legacy = runtime:describe({ backend_id = "legacy_cwv", name = "es_bastard_sword" })
		H.equal(legacy.style_id, "longsword")
		H.equal(runtime:transform_decision({ backend_id = "legacy_cwv", name = "es_bastard_sword" }).item_key,
			"imperial_test")
		local changed = runtime:set_item_style({ backend_id = "uuid_b", name = "es_2h_sword" },
			nil, "longsword", "test", false)
		H.equal(changed, true)
		H.equal(saved.key, policy.SETTING_KEY)
		H.equal(saved.value.items.uuid_b, "longsword")
	end)

	H.test("CWV Combat Style wire accepts only bounded known state", function()
		H.equal(policy.valid_wire(1, "state", "slot_melee", "greatsword", "kerillian"), true)
		H.equal(policy.valid_wire(1, "state", "slot_melee", "greatsword", "unknown"), false)
		H.equal(policy.valid_wire(2, "state", "slot_melee", "greatsword", "kerillian"), false)
		H.equal(policy.valid_wire(1, "state", "slot_hat", "greatsword", "kerillian"), false)
		H.equal(policy.valid_wire(1, "query", "", "", ""), true)
	end)

	H.test("CWV Combat Style production is consolidated and query replies do not echo", function()
		local function read(relative)
			local file = assert(io.open(repo_root .. "/" .. relative, "rb"))
			local source = file:read("*a")
			file:close()
			return source
		end
		local main = read("character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua")
		local module = read("character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_combat_styles.lua")
		H.truthy(main:find('_rt_register("issue620_per_instance_combat_styles"', 1, true))
		H.truthy(main:find("_om.combat_styles:resolve_template(item_data, backend_id)", 1, true))
		H.truthy(main:find("_om.combat_styles:on_local_wield(self, slot_name, item_data)", 1, true))
		H.truthy(module:find('if op == "query" then runtime:publish_loadout(sender_peer_id, "query_reply"); return end', 1, true))
		H.equal(module:find('if op == "query" then runtime:request_states', 1, true), nil)
		H.truthy(module:find('"Switch to: " ..', 1, true))
		H.truthy(module:find("hero_window_loadout_console_definitions", 1, true))
		H.truthy(module:find('mod:hook("HeroWindowLoadoutConsole", "_handle_input"', 1, true))
		H.truthy(module:find('icon = "icon_switch"', 1, true))
		H.truthy(module:find('"cwv_style_hotspot" .. suffix', 1, true))
		H.truthy(module:find('function runtime:request_item_style', 1, true))
		H.truthy(module:find('acquire_style_resource', 1, true))
		H.truthy(module:find('function M.refresh_console_row_layout', 1, true))
		H.truthy(main:find("policy.plan_legacy_migrations(saved", 1, true))
		H.truthy(main:find('_om._migrate_legacy_style_items = function()', 1, true))
		H.truthy(module:find('cwv_es_longsword_blackguard = {', 1, true))
		H.truthy(module:find('target_item = "es_2h_sword", style_id = "longsword"', 1, true))
		H.truthy(main:find('for _, mod_id in ipairs({ "cim_dev", "cim", "crafting_in_modded" })', 1, true))
		H.truthy(main:find('style_target_item = "es_2h_sword"', 1, true))
		H.truthy(main:find('if def.skin_only or def.cwv_retired then', 1, true))
		H.equal(main:find('item_key        = "cwv_es_infantry_spear"', 1, true), nil)
		H.truthy(main:find('legacy_ids[_om.infantry_spear.ITEM_KEY .. "_001"] = true', 1, true))
		H.equal(select(2, main:gsub('mod:hook%("BackendUtils", "get_item_template"', "")), 1)
	end)
end
