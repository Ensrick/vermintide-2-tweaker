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
		local family_policy = policy.FAMILIES.greatsword
		H.equal(family_policy.styles.longsword.template, "imperial_longsword_template")
		H.equal(family_policy.styles.longsword.resource,
			"units/beings/player/first_person_base/state_machines/melee/2h_sword")
		H.equal(family_policy.styles.bretonnian.template, "bastard_sword_template")
		H.equal(family_policy.styles.kerillian.template, policy.KERILLIAN_TEMPLATE)
		local next_id = policy.next_style("es_2h_sword", current)
		H.equal(next_id, "kerillian")
		next_id = policy.next_style("es_2h_sword", next_id)
		H.equal(next_id, "bretonnian")
		next_id = policy.next_style("es_2h_sword", next_id)
		H.equal(next_id, "greatsword")
		local bret_package = policy.package("es_2h_sword", "bretonnian")
		H.equal(bret_package.presentation.transform_key, "greatsword_bretonnian")
		H.equal(policy.package("es_bastard_sword", "bretonnian").presentation, nil)
		H.equal(policy.style("cwv_es_longsword"), "longsword")
		H.equal(policy.style("es_bastard_sword"), "bretonnian")
		H.equal(policy.next_style("es_bastard_sword", "bretonnian"), "greatsword")
		H.equal(policy.next_style("es_bastard_sword", "greatsword"), "kerillian")
		H.equal(policy.next_style("es_bastard_sword", "kerillian"), "bretonnian")
		H.equal(policy.package("es_bastard_sword", "greatsword").template,
			policy.BRETONNIAN_GREATSWORD_TEMPLATE)
		H.equal(policy.package("es_bastard_sword", "greatsword").presentation.transform_key,
			"bretonnian_greatsword_inverse")
		H.equal(policy.package("es_bastard_sword", "kerillian").presentation.transform_key,
			"bretonnian_greatsword_inverse")
		-- Retired Imperial/Black Guard rows already use Empire Greatsword meshes;
		-- they must never receive the native Bretonnian mesh's inverse transform.
		H.equal(policy.package("cwv_es_longsword", "greatsword").presentation, nil)
		H.equal(policy.style("wh_2h_sword"), "greatsword")
		H.equal(policy.next_style("wh_2h_sword", "greatsword"), "kerillian")
		H.equal(policy.next_style("wh_2h_sword", "kerillian"), "bretonnian")
		H.equal(policy.next_style("wh_2h_sword", "bretonnian"), "greatsword")
		local saltz_bret = policy.package("wh_2h_sword", "bretonnian")
		H.equal(saltz_bret.template, policy.SALTZ_BRETONNIAN_TEMPLATE)
		H.equal(saltz_bret.remap_key, "bretonnian_greatsword_to_saltz")
		H.equal(policy.package("wh_2h_sword", "kerillian").remap_key,
			"kerillian_greatsword_to_saltz")
		H.equal(policy.style("es_2h_hammer"), "kruber")
		H.equal(policy.next_style("es_2h_hammer", "kruber"), "warrior_priest")
		H.equal(policy.next_style("wh_2h_hammer", "warrior_priest"), "kruber")
		H.equal(policy.style("es_2h_heavy_spear"), "hunter")
		H.equal(policy.next_style("es_2h_heavy_spear", "hunter"), "infantry")
		H.equal(policy.style("cwv_es_infantry_spear"), nil)
		H.equal(policy.style("es_deus_01"), "empire")
		H.equal(policy.next_style("es_deus_01", "empire", function() return true end), "elven")
		H.equal(policy.style("we_1h_spears_shield"), "elven")
		H.equal(policy.next_style("we_1h_spears_shield", "elven", function() return true end), "empire")
		H.equal(policy.style("es_sword_shield"), "empire")
		H.equal(policy.next_style("es_sword_shield", "empire", function() return true end),
			"bretonnian")
		H.equal(policy.style("es_sword_shield_breton"), "bretonnian")
		H.equal(policy.next_style("es_sword_shield_breton", "bretonnian",
			function() return true end), "empire")
	end)

	H.test("CWV inventory indicator follows each exact member cycle", function()
		H.equal(policy.moveset_indicator("es_bastard_sword", "bretonnian"), "Moveset 1 / 3")
		H.equal(policy.moveset_indicator("es_bastard_sword", "greatsword"), "Moveset 2 / 3")
		H.equal(policy.moveset_indicator("es_bastard_sword", "kerillian", nil, true), "3 / 3")
		H.equal(policy.moveset_indicator("es_2h_sword", "greatsword"), "Moveset 1 / 3")
		H.equal(policy.moveset_indicator("es_2h_sword", "kerillian"), "Moveset 2 / 3")
		H.equal(policy.moveset_indicator("es_2h_sword", "bretonnian"), "Moveset 3 / 3")
		H.equal(policy.moveset_indicator("es_handgun", "greatsword"), nil)
	end)

	H.test("CWV Saltzpyre Greatsword member drives equipment-row eligibility", function()
		local runtime = policy.install({
			get = function() return nil end,
			set = function() end,
		}, {})
		local item = { name = "wh_2h_sword", backend_id = "saltz_greatsword_uuid" }
		local row = runtime:describe(item)
		H.truthy(row)
		H.equal(row.family_id, "greatsword")
		H.equal(row.style_id, "greatsword")
		local grid = {
			element = { passes = {} },
			content = { rows = 1, columns = 1, item_1_1 = item },
			style = {
				customize_hotspot_1_1 = { size = { 58, 58 }, offset = { 100, 210, 30 } },
				customize_item_hover_1_1 = { size = { 58, 58 }, offset = { 100, 210, 30 } },
			},
		}
		H.equal(policy.decorate_console_grid(grid, runtime), true)
		H.equal(policy.refresh_console_row_layout(grid, runtime), 1)
		H.equal(grid.content.cwv_style_hotspot_1_1.cwv_visible, true)
		grid.content.cwv_style_hotspot_1_1.parent = grid.content
		H.equal(grid.element.passes[1].content_check_function(
			grid.content.cwv_style_hotspot_1_1), true)
		H.equal(grid.content.cwv_style_hotspot_1_1.cwv_next_style_label,
			"Switch to: Kerillian Greatsword Combat Style")
	end)

	H.test("CWV reciprocal style catalogue is complete and unproven families fail closed", function()
		local valid, err = policy.validate_catalogue()
		H.equal(valid, true, err)
		local package = policy.package("es_deus_01", "elven")
		H.equal(package.template, policy.ELVEN_SPEAR_SHIELD_TEMPLATE)
		H.equal(package.resource,
			"units/beings/player/first_person_base/state_machines/melee/1h_spear_shield")
		H.equal(package.required_dlc, "scorpion")
		H.equal(package.remap_key, "spear_shield_to_deus")
		H.equal(policy.remap_event("es_deus_01", "elven", "es_knight", "attack_swing_stab_lh"),
			"attack_swing_stab")
		H.equal(policy.remap_event("we_1h_spears_shield", "empire", "we_maidenguard", "attack_swing_up"),
			"attack_swing_stab_lh")
		H.equal(policy.remap_event("wh_2h_sword", "kerillian", "wh_captain", "attack_swing_charge"),
			"attack_swing_charge_left_diagonal")
		H.equal(policy.remap_event("wh_2h_sword", "bretonnian", "wh_zealot", "attack_swing_up_left"),
			"attack_swing_left_diagonal")
		local empire_sword = policy.package("es_sword_shield_breton", "empire")
		local bretonnian_sword = policy.package("es_sword_shield", "bretonnian")
		H.equal(empire_sword.template, "one_handed_sword_shield_template_1")
		H.equal(empire_sword.resource,
			"units/beings/player/first_person_base/state_machines/melee/1h_sword_shield")
		H.equal(bretonnian_sword.template, "one_handed_sword_shield_template_2")
		H.equal(bretonnian_sword.resource,
			"units/beings/player/first_person_base/state_machines/melee/1h_sword_shield_breton")
		H.equal(bretonnian_sword.required_dlc, "lake")
		H.equal(empire_sword.remap_key, nil)
		H.equal(bretonnian_sword.remap_key, nil)
		for _, item_key in ipairs({ "dr_1h_axe", "wh_1h_axe", "we_1h_axe",
				"we_2h_axe", "dr_2h_axe", "es_1h_sword", "we_1h_sword", "we_spear" }) do
			H.equal(policy.member(item_key), nil)
			H.truthy(policy.diagnostic_candidate(item_key))
		end
	end)

	H.test("CWV native Sword and Shield styles never capture custom CWV clones", function()
		local runtime = policy.install({ get = function() end, set = function() end }, {
			cwv_key_for_item = function(backend_id)
				if backend_id == "elf_clone" then return "cwv_we_sword_shield" end
				if backend_id == "longsword_clone" then return "cwv_es_longsword_shield" end
				return nil
			end,
		})
		H.equal(runtime:describe({ backend_id = "elf_clone", name = "es_sword_shield" }), nil)
		H.equal(runtime:describe({ backend_id = "longsword_clone",
			name = "es_sword_shield_breton" }), nil)
		H.equal(runtime:describe({ backend_id = "native_empire",
			name = "es_sword_shield" }).style_id, "empire")
		H.equal(runtime:describe({ backend_id = "native_bretonnian",
			name = "es_sword_shield_breton" }).style_id, "bretonnian")
	end)

	H.test("CWV reciprocal style DLC gates skip unavailable donors", function()
		local own_grass_only = function(name) return name == "grass" end
		local next_id = policy.next_style("es_deus_01", "empire", own_grass_only)
		H.equal(next_id, "empire")
		next_id = policy.next_style("we_1h_spears_shield", "elven", own_grass_only)
		H.equal(next_id, "empire")
		local own_all = function() return true end
		H.equal(policy.next_style("es_deus_01", "empire", own_all), "elven")
		H.equal(policy.next_style("es_sword_shield", "empire", own_grass_only), "empire")
		H.equal(policy.next_style("es_sword_shield", "empire",
			function(name) return name == "lake" end), "bretonnian")
		H.equal(policy.next_style("es_sword_shield_breton", "bretonnian",
			function() return false end), "empire")
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
			moveset_indicator = function(_, item_key, style_id, compact)
				return policy.moveset_indicator(item_key, style_id, nil, compact)
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
		H.equal(#grid.element.passes, 8)
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
		local first_status_pass = grid.element.passes[4]
		H.equal(first_status_pass.content_check_function(grid.content), true)
		H.equal(grid.content.cwv_style_status_1_1, "1 / 2")
		grid.content.cwv_style_hotspot_2_1.parent = grid.content
		H.equal(grid.element.passes[5].content_check_function(grid.content.cwv_style_hotspot_2_1), false)
		H.equal(grid.content.cwv_style_hotspot_2_1.cwv_visible, false)

		grid.content.cwv_style_hotspot_1_1.on_pressed = true
		local item = policy.consume_console_style_press(grid.content, runtime)
		H.equal(item, nil)
		H.equal(grid.content.cwv_style_hotspot_1_1.on_pressed, false)
		grid.content.cwv_style_hotspot_1_1.on_release = true
		local suffix, row
		item, suffix, row = policy.consume_console_style_press(grid.content, runtime)
		H.equal(item.backend_id, "tuskgor_uuid")
		H.equal(suffix, "_1_1")
		H.equal(row.family_id, "spear")
		H.equal(grid.content.cwv_style_hotspot_1_1.on_release, false)
		H.equal(policy.consume_console_style_press(grid.content, runtime), nil)
		local pass_count = #grid.element.passes
		H.equal(policy.decorate_console_grid(grid, runtime), false)
		H.equal(#grid.element.passes, pass_count)
	end)

	H.test("CWV equipment click commits once and matches one hotkey cycle", function()
		local function make_runtime(identity)
			local commits = 0
			local fake_mod = {
				get = function() return nil end,
				set = function() commits = commits + 1 end,
			}
			local runtime = policy.install(fake_mod, {
				acquire_style_resource = function(_, callback)
					callback(true)
					return true
				end,
			})
			return runtime, { backend_id = identity, name = "es_2h_sword" },
				function() return commits end
		end

		local button_runtime, button_item, button_commits = make_runtime("button_greatsword")
		local hotkey_runtime, hotkey_item, hotkey_commits = make_runtime("hotkey_greatsword")
		local content = {
			rows = 1, columns = 1,
			item_1_1 = button_item,
			cwv_style_hotspot_1_1 = { cwv_visible = true },
		}
		local expected = { "kerillian", "bretonnian", "greatsword" }
		for index, style_id in ipairs(expected) do
			local hotspot = content.cwv_style_hotspot_1_1
			hotspot.on_pressed = true
			H.equal(policy.consume_console_style_press(content, button_runtime), nil)
			H.equal(button_commits(), index - 1)
			hotspot.on_release = true
			local clicked = policy.consume_console_style_press(content, button_runtime)
			H.equal(clicked, button_item)
			local accepted = button_runtime:cycle_item(clicked, nil, "equipment_style_button", true)
			H.equal(accepted, true)
			H.equal(button_commits(), index)
			H.equal(policy.consume_console_style_press(content, button_runtime), nil)
			H.equal(button_commits(), index)

			accepted = hotkey_runtime:cycle_item(hotkey_item, nil, "hotkey", true)
			H.equal(accepted, true)
			H.equal(hotkey_commits(), index)
			H.equal(button_runtime:describe(button_item).style_id, style_id)
			H.equal(hotkey_runtime:describe(hotkey_item).style_id, style_id)
		end
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
		local long = string.rep("x", policy.MAX_TOKEN + 20)
		local item = { backend_id = "mission_uuid", data = { name = "es_2h_sword" } }
		local row = { identity = "mission_uuid", family_id = "greatsword",
			style_id = "bretonnian" }
		local probe = policy.mission_ui_probe("console", "input_release", item, row,
			"_1_1", long)
		H.equal(probe.surface, "console")
		H.equal(probe.stage, "input_release")
		H.equal(probe.item_key, "es_2h_sword")
		H.equal(probe.raw_identity, "mission_uuid")
		H.equal(probe.identity, "mission_uuid")
		H.equal(probe.family, "greatsword")
		H.equal(probe.style, "bretonnian")
		H.equal(probe.row, "_1_1")
		H.equal(#probe.detail, policy.MAX_TOKEN)
		H.equal(policy.mission_ui_probe_key(probe),
			policy.mission_ui_probe_key(policy.mission_ui_probe("console",
				"input_release", item, row, "_1_1", long)))
		local emitted = {}
		local sink = policy.new_mission_ui_probe_sink(function(value, count, cap)
			emitted[#emitted + 1] = { value, count, cap }
		end, 2)
		local accepted, count = sink(probe)
		H.equal(accepted, true)
		H.equal(count, 1)
		accepted, count = sink(probe)
		H.equal(accepted, false)
		H.equal(count, 1)
		accepted, count = sink(policy.mission_ui_probe("desktop", "widget_missing"))
		H.equal(accepted, true)
		H.equal(count, 2)
		accepted, count = sink(policy.mission_ui_probe("desktop", "input_release"))
		H.equal(accepted, false)
		H.equal(count, 2)
		H.equal(#emitted, 2)
		H.equal(emitted[2][3], 2)

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
		H.equal(calls.elf_light.modifiers.damage, 1.075)
		H.equal(calls.elf_light.modifiers.stagger, 1.25)
		H.equal(calls.elf_light.modifiers.cleave, 1.25)
		H.equal(template.wield_anim_career_3p.es_mercenary, "to_bastard_sword")
		H.equal(template.wield_anim_career_3p.wh_captain, "to_2h_sword")
		H.equal(template.wield_anim_career_3p.wh_bountyhunter, "to_2h_sword")
		H.equal(template.wield_anim_career_3p.wh_zealot, "to_2h_sword")
		H.equal(donor.actions.action_one.light.anim_time_scale, 1.2)
		H.equal(donor.actions.action_one.light.damage_profile, "elf_light")
		H.equal(donor.wield_anim_career_3p, nil)
	end)

	H.test("CWV Saltzpyre Bretonnian style clones donor and owns receiver wield routes", function()
		local donor = {
			wield_anim = "to_bastard_sword",
			actions = { action_one = { light = { anim_event = "attack_swing_up_left" } } },
		}
		local template, err = policy.build_saltz_bretonnian_template({
			bastard_sword_template = donor,
		}, clone)
		H.truthy(template, err)
		H.equal(template.wield_anim, "to_bastard_sword")
		H.equal(template.wield_anim_career_3p.wh_captain, "to_2h_sword")
		H.equal(template.wield_anim_career_3p.wh_bountyhunter, "to_2h_sword")
		H.equal(template.wield_anim_career_3p.wh_zealot, "to_2h_sword")
		H.equal(template.wield_anim_career_3p.wh_priest, nil)
		H.equal(donor.wield_anim_career_3p, nil)
		H.equal(template.actions.action_one.light.anim_event, "attack_swing_up_left")
	end)

	H.test("CWV Bretonnian Greatsword style tunes power and preserves native reach", function()
		local greatsword = {
			actions = { action_one = {
				light = { graph = "kruber_greatsword", range_mod = 1.65,
					anim_time_scale = 1.2, damage_profile = "greatsword_light" },
				heavy = { graph = "kruber_greatsword", range_mod = 1.5,
					anim_time_scale = 0.8, damage_profile = "greatsword_heavy" },
			} },
			wield_anim = "to_2h_sword",
		}
		local bretonnian = {
			actions = { action_one = {
				light = { graph = "bretonnian", range_mod = 1.65, damage_profile = "bret_light" },
				heavy = { graph = "bretonnian", range_mod = 1.5, damage_profile = "bret_heavy" },
			} },
		}
		local calls = {}
		local template, err = policy.build_bretonnian_greatsword_template({
			two_handed_swords_template_1 = greatsword,
			bastard_sword_template = bretonnian,
		}, clone, function(source, prefix, modifiers)
			calls[source] = clone(modifiers)
			return prefix .. source
		end)
		H.truthy(template, err)
		H.equal(template.actions.action_one.light.graph, "kruber_greatsword")
		H.equal(template.actions.action_one.light.range_mod, 1.65)
		H.equal(template.actions.action_one.heavy.range_mod, 1.5)
		H.equal(template.actions.action_one.light.anim_time_scale, 1.2)
		H.equal(calls.greatsword_light.damage, 1)
		H.equal(calls.greatsword_light.stagger, 1.25)
		H.equal(calls.greatsword_light.cleave, 0.75)
		H.equal(greatsword.actions.action_one.light.damage_profile, "greatsword_light")
		H.equal(bretonnian.actions.action_one.light.damage_profile, "bret_light")

		bretonnian.actions.action_one.light.range_mod = 1.6
		template, err = policy.build_bretonnian_greatsword_template({
			two_handed_swords_template_1 = greatsword,
			bastard_sword_template = bretonnian,
		}, clone, function() end)
		H.equal(template, nil)
		H.truthy(err:find("attack%-range signature drift"))
	end)

	H.test("CWV Imperial Longsword style derives from Kruber Greatsword, not Bretonnian", function()
		local greatsword = {
			actions = { action_one = {
				light = { graph = "kruber_greatsword", anim_time_scale = 1.2,
					damage_profile = "greatsword_light" },
			} },
			wield_anim = "to_2h_sword",
		}
		local bretonnian = {
			actions = { action_one = { light = { graph = "bretonnian_longsword" } } },
			wield_anim = "to_bastard_sword",
		}
		local calls = {}
		local template = policy.build_imperial_template({
			two_handed_swords_template_1 = greatsword,
			bastard_sword_template = bretonnian,
		}, clone, function(source, prefix, modifiers)
			calls[source] = { prefix = prefix, modifiers = clone(modifiers) }
			return prefix .. source
		end)
		H.truthy(template)
		H.equal(template.actions.action_one.light.graph, "kruber_greatsword")
		H.equal(template.wield_anim, "to_2h_sword")
		H.truthy(math.abs(template.actions.action_one.light.anim_time_scale - 1.38) < 0.000001)
		H.equal(template.actions.action_one.light.damage_profile, "cwv_il_greatsword_light")
		H.equal(calls.greatsword_light.modifiers.damage, 0.85)
		H.equal(calls.greatsword_light.modifiers.stagger, 0.85)
		H.equal(calls.greatsword_light.modifiers.cleave, 1.15)
		H.equal(greatsword.actions.action_one.light.anim_time_scale, 1.2)
		H.equal(greatsword.actions.action_one.light.damage_profile, "greatsword_light")
		H.equal(template.actions.action_one.light.graph ==
			bretonnian.actions.action_one.light.graph, false)
	end)

	H.test("CWV Spear and Shield styles clone donors with reciprocal receiver wield routes", function()
		local empire = { wield_anim = "to_es_deus_01", state_machine = "melee/es_deus_01",
			actions = { action_one = { marker = "empire" }, action_two = { default = {
				kind = "block", anim_event = "parry_pose", weapon_action_hand = "left" } } } }
		local elven = { wield_anim = "to_1h_spear_shield", state_machine = "melee/1h_spear_shield",
			actions = { action_one = { marker = "elven" }, action_two = { default = {
				kind = "block", anim_event = "parry_pose", weapon_action_hand = "left" } } } }
		local built, err = policy.build_spear_shield_templates({
			es_deus_01_template = empire,
			one_handed_spears_shield_template = elven,
		}, clone)
		H.truthy(built, err)
		H.equal(built[policy.EMPIRE_SPEAR_SHIELD_TEMPLATE].wield_anim, "to_es_deus_01")
		H.equal(built[policy.EMPIRE_SPEAR_SHIELD_TEMPLATE].wield_anim_career_3p.we_maidenguard,
			"to_1h_spear_shield")
		H.equal(built[policy.ELVEN_SPEAR_SHIELD_TEMPLATE].wield_anim, "to_1h_spear_shield")
		H.equal(built[policy.ELVEN_SPEAR_SHIELD_TEMPLATE].state_machine,
			"melee/1h_spear_shield")
		H.equal(built[policy.ELVEN_SPEAR_SHIELD_TEMPLATE].actions.action_two.default.kind,
			"block")
		H.equal(built[policy.ELVEN_SPEAR_SHIELD_TEMPLATE].actions.action_two.default.anim_event,
			"parry_pose")
		H.equal(built[policy.ELVEN_SPEAR_SHIELD_TEMPLATE].actions.action_two.default.weapon_action_hand,
			"left")
		H.equal(built[policy.ELVEN_SPEAR_SHIELD_TEMPLATE].wield_anim_career_3p.es_knight,
			"to_es_deus_01")
		H.equal(empire.wield_anim_career_3p, nil)
		H.equal(elven.wield_anim_career_3p, nil)
	end)

	H.test("CWV Combat Style runtime resolves exact IDs and legacy defaults", function()
		local saved
		local registered
		local remote_rebuilds = 0
		local fake_mod = {
			get = function(_, key)
				if key == policy.SETTING_KEY then
					return { schema = 1, items = { uuid_a = "kerillian", uuid_c = "bretonnian" } }
				end
			end,
			set = function(_, key, value) saved = { key = key, value = clone(value) } end,
			network_register = function(_, channel, callback)
				registered = { channel = channel, callback = callback }
			end,
		}
		local runtime = policy.install(fake_mod, {
			cwv_key_for_item = function(backend_id)
				return backend_id == "legacy_cwv" and "cwv_es_longsword" or nil
			end,
			presentations = {
				imperial_longsword = { item_key = "imperial_test", right_hand_scale = { 1, 0.8, 0.9 } },
				greatsword_bretonnian = {
					item_key = "greatsword_bret_test",
					right_hand_scale_3p = { 1, 0.8, 0.9 },
					right_hand_offset_3p = { 0, 0, -0.065 },
				},
				bretonnian_greatsword_inverse = {
					item_key = "bret_greatsword_inverse_test",
					right_hand_scale = { 1, 1.25, 1 / 0.9 },
					right_hand_offset = { 0, 0, 0.065 },
				},
			},
			peer_for_owner = function(owner)
				return owner == "remote_owner" and "peer_a" or nil
			end,
			rebuild_remote = function(peer_id, slot_name)
				H.equal(peer_id, "peer_a")
				H.equal(slot_name, "slot_melee")
				remote_rebuilds = remote_rebuilds + 1
				return true, "rewielded"
			end,
		})
		local a = runtime:describe({ backend_id = "uuid_a", name = "es_2h_sword" })
		H.equal(a.style_id, "kerillian")
		local b = runtime:describe({ backend_id = "uuid_b", name = "es_2h_sword" })
		H.equal(b.style_id, "greatsword")
		local legacy = runtime:describe({ backend_id = "legacy_cwv", name = "es_bastard_sword" })
		H.equal(legacy.style_id, "longsword")
		H.equal(runtime:transform_decision({ backend_id = "legacy_cwv", name = "es_bastard_sword" }).item_key,
			"imperial_test")
		local receiver_transform = runtime:transform_decision({ backend_id = "uuid_c", name = "es_2h_sword" })
		H.equal(receiver_transform.item_key, "greatsword_bret_test")
		H.equal(receiver_transform.right_hand_scale, nil)
		H.equal(receiver_transform.right_hand_scale_3p[2], 0.8)
		H.equal(receiver_transform.right_hand_offset_3p[3], -0.065)
		H.equal(runtime:presentation("bretonnian_greatsword_inverse").item_key,
			"bret_greatsword_inverse_test")
		H.equal(runtime:presentation(false), nil)
		local inverse_transform = runtime:transform_decision({
			backend_id = "uuid_bret_greatsword", name = "es_bastard_sword",
		})
		H.equal(inverse_transform, false)
		local inverse_changed = runtime:set_item_style({
			backend_id = "uuid_bret_greatsword", name = "es_bastard_sword",
		}, nil, "greatsword", "test", false)
		H.equal(inverse_changed, true)
		inverse_transform = runtime:transform_decision({
			backend_id = "uuid_bret_greatsword", name = "es_bastard_sword",
		})
		H.equal(inverse_transform.item_key, "bret_greatsword_inverse_test")
		H.equal(inverse_transform.right_hand_scale[2], 1.25)
		H.truthy(math.abs(inverse_transform.right_hand_scale[3] - (1 / 0.9)) < 0.0000001)
		H.equal(inverse_transform.right_hand_offset[3], 0.065)
		H.equal(runtime:effective_template_name({ backend_id = "uuid_a", name = "es_2h_sword" }),
			policy.KERILLIAN_TEMPLATE)
		H.equal(fake_mod.get_effective_combat_style_template_name(
			{ backend_id = "uuid_c", name = "es_2h_sword" }),
			"bastard_sword_template")
		H.equal(registered.channel, policy.CHANNEL)
		registered.callback("peer_a", policy.SCHEMA, "state", "slot_melee", "greatsword", "bretonnian")
		H.equal(remote_rebuilds, 1)
		registered.callback("peer_a", policy.SCHEMA, "state", "slot_melee", "greatsword", "bretonnian")
		H.equal(remote_rebuilds, 1)
		H.equal(runtime:effective_template_name({ name = "es_2h_sword" }, nil,
			"remote_owner", "slot_melee"), "bastard_sword_template")
		H.equal(runtime:effective_template_name({ backend_id = "foreign_uuid",
			name = "es_2h_sword" }, nil, "remote_owner", "slot_melee"),
			"bastard_sword_template")
		H.equal(runtime:remote_transform("remote_owner", "slot_melee",
			{ name = "es_2h_sword" }).item_key, "greatsword_bret_test")
		H.equal(runtime:remote_transform("remote_owner", "slot_melee",
			{ name = "es_bastard_sword" }), false)
		registered.callback("peer_a", policy.SCHEMA, "state", "slot_melee", "greatsword", "greatsword")
		local remote_inverse = runtime:remote_transform("remote_owner", "slot_melee",
			{ name = "es_bastard_sword" })
		H.equal(remote_inverse.item_key, "bret_greatsword_inverse_test")
		local changed = runtime:set_item_style({ backend_id = "uuid_b", name = "es_2h_sword" },
			nil, "longsword", "test", false)
		H.equal(changed, true)
		H.equal(saved.key, policy.SETTING_KEY)
		H.equal(saved.value.items.uuid_b, "longsword")
	end)

	H.test("CWV remote style refresh fails closed before a partial empty-slot wield", function()
		local ready, reason = policy.remote_refresh_readiness({
			wielded_slot = "slot_melee",
			_equipment = { wielded_slot = "slot_melee", slots = {} },
		}, "slot_melee")
		H.equal(ready, false)
		H.equal(reason, "slot not ready")

		ready, reason = policy.remote_refresh_readiness({
			_equipment = {
				wielded_slot = "slot_melee",
				slots = { slot_melee = { item_data = { name = "es_sword_shield" } } },
			},
		}, "slot_melee")
		H.equal(ready, true)
		H.equal(reason, "ready")

		ready, reason = policy.remote_refresh_readiness({
			wielded_slot = "slot_ranged",
			_equipment = {
				wielded_slot = "slot_ranged",
				slots = { slot_melee = { item_data = { name = "es_sword_shield" } } },
			},
		}, "slot_melee")
                H.equal(ready, false)
                H.equal(reason, "slot not wielded")
        end)

        H.test("CWV #786 remote style refresh retries only bounded lifecycle gaps", function()
                local registered, attempts = nil, 0
                local runtime = policy.install({
                        get = function() end,
                        set = function() end,
                        network_register = function(_, _, callback) registered = callback end,
                }, {
                        rebuild_remote = function()
                                attempts = attempts + 1
                                if attempts < 3 then return false, "player unavailable" end
                                return true, "rewielded resolver=player_from_peer_id"
                        end,
                })
                registered("peer-a", policy.SCHEMA, "state", "slot_melee",
                        "greatsword", "bretonnian")
                H.equal(attempts, 1)
                H.equal(runtime:pending_remote_refresh_count(), 1)
                runtime:step(policy.REMOTE_REFRESH_INTERVAL - 0.01)
                H.equal(attempts, 1)
                runtime:step(0.01)
                H.equal(attempts, 2)
                local completed = runtime:step(policy.REMOTE_REFRESH_INTERVAL)
                H.equal(completed, 1)
                H.equal(attempts, 3)
                H.equal(runtime:pending_remote_refresh_count(), 0)

                -- An unwielded slot is terminal for active refresh; the next natural wield
                -- consumes the already-cached style instead of an update-loop retry.
                local terminal_calls = 0
                local terminal_callback
                local terminal = policy.install({
                        get = function() end,
                        set = function() end,
                        network_register = function(_, _, callback) terminal_callback = callback end,
                }, {
                        rebuild_remote = function()
                                terminal_calls = terminal_calls + 1
                                return false, "slot not wielded"
                        end,
                })
                terminal_callback("peer-b", policy.SCHEMA, "state", "slot_melee",
                        "greatsword", "kerillian")
                for _ = 1, 20 do terminal:step(1) end
                H.equal(terminal_calls, 1)
                H.equal(terminal:pending_remote_refresh_count(), 0)
        end)

        H.test("CWV #786 remote style lifecycle retry is attempt bounded", function()
                local registered, attempts, network_sends = nil, 0, 0
                local runtime = policy.install({
                        get = function() end,
                        set = function() end,
                        network_register = function(_, _, callback) registered = callback end,
                        network_send = function() network_sends = network_sends + 1 end,
                }, {
                        rebuild_remote = function()
                                attempts = attempts + 1
                                return false, "slot not ready"
                        end,
                })
                registered("peer-a", policy.SCHEMA, "state", "slot_melee",
                        "greatsword", "bretonnian")
                -- A long frame advances one local attempt, never a catch-up burst.
                runtime:step(policy.REMOTE_REFRESH_INTERVAL * 20)
                H.equal(attempts, 2)
                local expired = 0
                for _ = 1, policy.MAX_REMOTE_REFRESH_ATTEMPTS + 3 do
                        local _, count = runtime:step(policy.REMOTE_REFRESH_INTERVAL)
                        expired = expired + count
                end
                H.equal(attempts, policy.MAX_REMOTE_REFRESH_ATTEMPTS)
                H.equal(expired, 1)
                H.equal(runtime:pending_remote_refresh_count(), 0)
                H.equal(network_sends, 0)
        end)

        H.test("CWV owner style transition performs one bounded slot rebuild", function()
		local old_managers, old_unit, old_script_unit = _G.Managers, _G.Unit, _G.ScriptUnit
		local ok, err = pcall(function()
			local item = { backend_id = "owner_style_uuid", name = "es_2h_sword" }
			local equipment = {
				wielded_slot = "slot_melee",
				slots = { slot_melee = { item_data = item } },
			}
			local counts = { destroy = 0, add = 0, wield = 0 }
			local inventory = {
				equipment = function() return equipment end,
				destroy_slot = function() counts.destroy = counts.destroy + 1 end,
				add_equipment = function() counts.add = counts.add + 1 end,
				wield = function() counts.wield = counts.wield + 1 end,
			}
			local player_unit = {}
			_G.Managers = { player = { local_player = function() return { player_unit = player_unit } end } }
			_G.Unit = { alive = function() return true end }
			_G.ScriptUnit = { extension = function() return inventory end }

			local runtime = policy.install({ get = function() end, set = function() end }, {
				acquire_style_resource = function(_, complete) complete(true); return true end,
			})
			local accepted = runtime:cycle_item(item, nil, "test-owner-rebuild", true)
			H.equal(accepted, true)
			H.equal(counts.destroy, 1)
			H.equal(counts.add, 1)
			H.equal(counts.wield, 1)
			H.equal(runtime:describe(item).style_id, "kerillian")
		end)
		_G.Managers, _G.Unit, _G.ScriptUnit = old_managers, old_unit, old_script_unit
		if not ok then error(err) end
	end)

	H.test("CWV #645 diagnostics are deduplicated, capped, and never expose candidate styles", function()
		local old_printf = _G.printf
		local logs = {}
		_G.printf = function(fmt, ...)
			logs[#logs + 1] = string.format(fmt, ...)
		end
		local runtime = policy.install({ get = function() end, set = function() end }, {
			diagnostics_enabled = function() return true end,
		})
		H.equal(runtime:observe_candidate_action("we_2h_axe", "we_maidenguard", "attack_a"), true)
		H.equal(runtime:observe_candidate_action("we_2h_axe", "we_maidenguard", "attack_a"), false)
		for index = 2, policy.DIAGNOSTIC_EVENT_CAP + 3 do
			runtime:observe_candidate_action("we_2h_axe", "we_maidenguard", "attack_" .. index)
		end
		H.equal(#logs, policy.DIAGNOSTIC_EVENT_CAP)
		H.equal(runtime:observe_candidate_action("es_2h_sword", "es_knight", "attack"), false)
		H.equal(policy.member("we_2h_axe"), nil)
		_G.printf = old_printf
	end)

	H.test("CWV Combat Style wire accepts only bounded known state", function()
		H.equal(policy.valid_wire(1, "state", "slot_melee", "greatsword", "kerillian"), true)
		H.equal(policy.valid_wire(1, "state", "slot_melee", "greatsword", "unknown"), false)
		H.equal(policy.valid_wire(2, "state", "slot_melee", "greatsword", "kerillian"), false)
		H.equal(policy.valid_wire(1, "state", "slot_hat", "greatsword", "kerillian"), false)
		H.equal(policy.valid_wire(1, "query", "", "", ""), true)
	end)

	H.test("CWV #692 reciprocal Bretonnian transform reaches every appearance consumer", function()
		local function read(relative)
			local file = assert(io.open(repo_root .. "/" .. relative, "rb"))
			local source = file:read("*a")
			file:close()
			return source
		end
		local main = require("cwv_source").combined(repo_root)
		local husk = read("character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_husk_path.lua")
		H.truthy(main:find('item_key = "cwv_style_bretonnian_greatsword_inverse"', 1, true))
		H.truthy(main:find('right_hand_scale = inverse_bretonnian_scale', 1, true))
		H.truthy(main:find('right_hand_offset = inverse_bretonnian_offset', 1, true))
		H.truthy(main:find('"right", "1p", "owner_1p"', 1, true))
		H.truthy(main:find('is_bot and "bot" or "owner_3p"', 1, true))
		H.truthy(main:find('"right", "3p", "inventory_preview"', 1, true))
		H.truthy(main:find('_om.combat_styles:transform_decision(item_data, item.backend_id)', 1, true))
		H.truthy(husk:find('_om.combat_styles:remote_transform(owner_unit_3p, slot_name, item_data)', 1, true))
		H.truthy(husk:find('"3p", "remote_husk"', 1, true))
	end)

	H.test("CWV Combat Style production is consolidated and query replies do not echo", function()
		local function read(relative)
			local file = assert(io.open(repo_root .. "/" .. relative, "rb"))
			local source = file:read("*a")
			file:close()
			return source
		end
		local main = require("cwv_source").combined(repo_root)
		local module = read("character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_combat_styles.lua")
		H.truthy(main:find('_rt_register("issue620_per_instance_combat_styles"', 1, true))
		H.truthy(main:find("_om.combat_styles:resolve_template(item_data, backend_id)", 1, true))
		H.truthy(main:find("_om.combat_styles:on_local_wield(self, slot_name, item_data)", 1, true))
		H.truthy(main:find("remote_transform(owner_unit_3p, slot_name, item_data)", 1, true))
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
                H.truthy(module:find('"[cwv:774] surface=%s stage=%s', 1, true))
                H.truthy(module:find('M.MISSION_UI_DIAGNOSTIC_CAP = 24', 1, true))
                H.truthy(module:find('M.MAX_REMOTE_REFRESH_ATTEMPTS = 8', 1, true))
                H.truthy(main:find('_om.combat_styles:step(dt)', 1, true))
                H.truthy(main:find("policy.plan_legacy_migrations(saved", 1, true))
		H.truthy(main:find('_om._migrate_legacy_style_items = function()', 1, true))
		H.truthy(module:find('cwv_es_longsword_blackguard = {', 1, true))
		H.truthy(module:find('target_item = "es_2h_sword", style_id = "longsword"', 1, true))
		H.truthy(main:find('for _, mod_id in ipairs({ "cim_dev", "cim", "crafting_in_modded" })', 1, true))
		H.truthy(main:find('style_target_item = "es_2h_sword"', 1, true))
		H.truthy(main:find('if def.skin_only or def.cwv_retired then', 1, true))
		H.equal(main:find('item_key        = "cwv_es_infantry_spear"', 1, true), nil)
		H.truthy(main:find('{ [_om.infantry_spear.ITEM_KEY .. "_001"] = true }', 1, true))
		H.equal(select(2, main:gsub('mod:hook%("BackendUtils", "get_item_template"', "")), 1)
	end)
end
