return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_appearance_policy.lua")
	local identity = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_team_preview_identity.lua")
	local preview_module = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_mod_unit_preview.lua")
	local ITEM_KEY = "woc_blightreaper"
	local BACKEND_ID = "woc_blightreaper_001"

	local function with_preview(body)
		local names = {
			"Application", "InventorySettings", "Managers", "WeaponUtils", "printf",
		}
		local saved = {}
		for _, name in ipairs(names) do saved[name] = rawget(_G, name) end

		local hooks, applications, reapplies, forgotten = {}, {}, {}, {}
		local snapshots = {}
		_G.printf = function() end
		_G.Application = {
			can_get = function(resource_type, name)
				H.equal(resource_type, "unit")
				return name ~= nil
			end,
		}
		_G.InventorySettings = {
			slots_by_name = {
				slot_melee = { name = "slot_melee", type = "melee" },
				slot_ranged = { name = "slot_ranged", type = "ranged" },
			},
		}
		_G.Managers = {
			package = { load = function() end },
			player = {},
			state = { network = {} },
		}
		_G.WeaponUtils = {}

		local mod = {}
		function mod:hook(target, method, callback)
			local owner = type(target) == "string" and target
				or target == _G.WeaponUtils and "WeaponUtils" or "table"
			hooks[owner .. "." .. method] = callback
		end
		local appearance = {
			apply = function(unit, spec, perspective, surface)
				applications[#applications + 1] = {
					unit = unit, spec = spec, perspective = perspective,
					surface = surface,
				}
				return true
			end,
		}
		local transform_owner = {
			reapply = function(_, unit, edge)
				reapplies[#reapplies + 1] = { unit = unit, edge = edge }
				return true, "retained"
			end,
			forget = function(_, unit)
				forgotten[#forgotten + 1] = unit
				return true
			end,
		}
		local runtime = preview_module.install(policy, appearance, {
			mod = mod,
			transform_owner = transform_owner,
			team_identity = identity,
			item_key = ITEM_KEY,
			backend_id = BACKEND_ID,
			identity_for_peer = function(peer_id) return snapshots[peer_id] end,
			test_api = true,
		})
		local env = {
			hooks = hooks,
			applications = applications,
			reapplies = reapplies,
			forgotten = forgotten,
			appearance = appearance,
			transform_owner = transform_owner,
			snapshots = snapshots,
			runtime = runtime,
		}

		local ok, failure = xpcall(function() body(env) end, debug.traceback)
		for _, name in ipairs(names) do _G[name] = saved[name] end
		if not ok then error(failure, 0) end
	end

	local function authenticated_snapshot(generation, melee, ranged)
		return {
			key = ITEM_KEY,
			peer_id = "peer-wearer",
			authority_peer = "peer-host",
			authority_epoch = 2,
			generation = generation,
			slot_melee = melee,
			slot_ranged = ranged,
		}
	end

	local function spawn_team_preview(env, context, expected_source)
		local equips = {}
		local hero = {
			world = {},
			_session_id = 41,
			_equipment_units = {},
			_item_info_by_slot = {},
		}
		local function vanilla_equip(_, item_name, slot, backend_id, skin,
				skip_wield_anim)
			equips[#equips + 1] = {
				item_name = item_name, slot = slot.name, backend_id = backend_id,
				skin = skin, skip_wield_anim = skip_wield_anim,
			}
			return item_name
		end
		function hero:equip_item(...)
			return env.hooks["HeroPreviewer.equip_item"](
				vanilla_equip, self, ...)
		end
		function hero:clear_units()
			return env.hooks["HeroPreviewer.clear_units"](
				function(self)
					self._equipment_units = {}
					return "cleared-before-request"
				end, self)
		end
		local score_context = {
				players_session_score = {
					wearer = {
						peer_id = "peer-wearer", local_player_id = 1,
						profile_index = 5, career_index = 4,
						is_player_controlled = true,
					},
				},
		}
		local team = { _context = context or score_context }
		local result = env.hooks["TeamPreviewer._spawn_hero"](
			function(_, previewer, hero_data)
				H.equal(previewer, hero)
				H.equal(hero_data.profile_index, 5)
				H.equal(previewer:clear_units(), "cleared-before-request",
					"engine-shaped request_spawn_hero_unit must clear synchronously")
				return "spawned"
			end,
			team, hero, { profile_index = 5, career_index = 4 })
		H.equal(result, "spawned")
		local record = env.runtime:test_snapshot(hero).record
		H.equal(record.peer_id, "peer-wearer")
		H.equal(record.source, expected_source or "score_snapshot")
		H.equal(record.session_id, 41)
		return hero, equips
	end

	H.test("WOC #613 package hooks borrow aliases and preserve only resident custom units", function()
		with_preview(function(env)
			local collected = env.hooks["WeaponUtils.get_weapon_packages"](
				function(marker)
					H.equal(marker, "all-packages")
					return { policy.UNIT_1P, "native-package", policy.UNIT_3P }
				end, "all-packages")
			H.deep_equal(collected, {
				policy.VANILLA_1P, "native-package", policy.VANILLA_3P,
			})

			local function exercise(class_name, custom_resident)
				Application.can_get = function(resource_type, name)
					H.equal(resource_type, "unit")
					H.truthy(name == policy.UNIT_1P or name == policy.UNIT_3P)
					return custom_resident
				end
				local previewer = {
					_item_info_by_slot = {
						melee = { spawn_data = {
							{ unit_name = policy.UNIT_1P },
							{ unit_name = "native-unit" },
						} },
					},
				}
				local packages = { policy.UNIT_1P, "native-package" }
				local native_packages
				local result = env.hooks[class_name .. "._load_packages"](
					function(self, received)
						H.equal(self, previewer)
						native_packages = received
						return class_name .. "-loaded"
					end, previewer, packages)
				H.equal(result, class_name .. "-loaded")
				H.equal(native_packages[1], policy.VANILLA_1P)
				H.equal(native_packages[2], "native-package")
				H.equal(previewer._item_info_by_slot.melee.spawn_data[1].unit_name,
					custom_resident and policy.UNIT_1P or policy.VANILLA_1P)
				H.equal(previewer._item_info_by_slot.melee.spawn_data[2].unit_name,
					"native-unit")
			end

			exercise("HeroPreviewer", true)
			exercise("MenuWorldPreviewer", false)
		end)
	end)

	H.test("WOC #613 delayed TeamPreviewer identity replays once and fails stale closed", function()
		with_preview(function(env)
			local hero, equips = spawn_team_preview(env)
			hero:equip_item("es_1h_sword", InventorySettings.slots_by_name.slot_melee,
				"vanilla-backend", "vanilla-skin", false)
			H.equal(#equips, 1)
			H.equal(equips[1].item_name, "es_1h_sword")

			env.snapshots["peer-wearer"] = authenticated_snapshot(7, true, false)
			H.equal(env.runtime:notify_identity("peer-wearer",
				env.snapshots["peer-wearer"], "host-snapshot"), 1)
			H.equal(env.runtime:notify_identity("peer-wearer",
				env.snapshots["peer-wearer"], "identical-replay"), 0)
			env.hooks["HeroPreviewer.post_update"](
				function() return "updated" end, hero, 0.016)
			H.equal(#equips, 2)
			H.equal(equips[2].item_name, ITEM_KEY)
			H.equal(equips[2].backend_id, BACKEND_ID)
			H.equal(equips[2].skin, nil)

			env.snapshots["peer-wearer"] = authenticated_snapshot(8, false, false)
			H.equal(env.runtime:notify_identity("peer-wearer",
				env.snapshots["peer-wearer"], "release"), 1)
			env.hooks["HeroPreviewer.post_update"](
				function() end, hero, 0.016)
			H.equal(#equips, 3)
			H.equal(equips[3].item_name, "es_1h_sword")
			H.equal(equips[3].backend_id, "vanilla-backend")
			H.equal(equips[3].skin, "vanilla-skin")

			-- A later semantic snapshot makes the queued generation stale.
			env.snapshots["peer-wearer"] = authenticated_snapshot(9, true, false)
			H.equal(env.runtime:notify_identity("peer-wearer",
				env.snapshots["peer-wearer"], "generation-9"), 1)
			env.snapshots["peer-wearer"] = authenticated_snapshot(10, true, false)
			env.hooks["HeroPreviewer.post_update"](
				function() end, hero, 0.016)
			H.equal(#equips, 3, "a stale generation must not rebuild the preview")

			-- Reusing the same preview object for the same peer must not let an
			-- event bound to the retired consumer rebuild the replacement row.
			env.snapshots["peer-wearer"] = authenticated_snapshot(11, true, false)
			H.equal(env.runtime:notify_identity("peer-wearer",
				env.snapshots["peer-wearer"], "generation-11"), 1)
			env.hooks["TeamPreviewer._spawn_hero"](
				function() return "reused" end,
				{ _context = {
					players_session_score = {
						wearer = {
							peer_id = "peer-wearer", local_player_id = 1,
							profile_index = 5, career_index = 4,
							is_player_controlled = true,
						},
					},
				} },
				hero, { profile_index = 5, career_index = 4 })
			env.hooks["HeroPreviewer.post_update"](
				function() end, hero, 0.016)
			H.equal(#equips, 3,
				"a pending event must be bound to the retired consumer record")

			-- Queue the current generation, then retire the consumer before its
			-- event drain. Destroyed worlds and replacement sessions are no-ops.
			hero:equip_item("es_1h_sword", InventorySettings.slots_by_name.slot_melee,
				"vanilla-backend", "vanilla-skin", false)
			env.snapshots["peer-wearer"] = authenticated_snapshot(12, false, false)
			H.equal(env.runtime:notify_identity("peer-wearer",
				env.snapshots["peer-wearer"], "generation-12"), 1)
			hero.world = nil
			hero._session_id = 42
			env.hooks["HeroPreviewer.post_update"](
				function() end, hero, 0.016)
			H.equal(#equips, 4)
		end)
	end)

	H.test("WOC #613 live lobby resolver stamps the exact human wearer", function()
		with_preview(function(env)
			local synchronized = 0
			Managers.state.network.profile_synchronizer = {
				profile_by_peer = function(_, peer_id, local_player_id)
					synchronized = synchronized + 1
					H.equal(peer_id, "peer-wearer")
					H.equal(local_player_id, 1)
					return 5, 4
				end,
			}
			Managers.player.human_players = function()
				return {
					{
						peer_id = "peer-wearer",
						local_player_id = function() return 1 end,
						profile_index = function() error("synchronizer must win") end,
						career_index = function() error("synchronizer must win") end,
					},
					{
						peer_id = "peer-wearer", bot_player = true,
						local_player_id = function() return 1 end,
						profile_index = function() return 5 end,
						career_index = function() return 4 end,
					},
				}
			end
			local hero, equips = spawn_team_preview(env, {}, "live_profile")
			H.equal(synchronized, 1)
			env.snapshots["peer-wearer"] = authenticated_snapshot(3, true, false)
			hero:equip_item("es_1h_sword", InventorySettings.slots_by_name.slot_melee,
				"vanilla-backend", nil, true)
			H.equal(equips[1].item_name, ITEM_KEY)
			H.equal(equips[1].backend_id, BACKEND_ID)

			local unit = {}
			hero._equipment_units[1] = { right = unit }
			env.hooks["HeroPreviewer._spawn_item"](
				function() end, hero, ITEM_KEY, {
					{ unit_name = policy.UNIT_3P, slot_index = 1, right_hand = true },
				})
			H.equal(env.applications[1].surface, "lobby-preview")
		end)
	end)

	H.test("WOC #613 MenuWorldPreviewer executes its copied lifecycle hooks", function()
		with_preview(function(env)
			local unit = {}
			local menu = {
				world = {}, _session_id = 23,
				_equipment_units = { { right = unit } },
				_item_info_by_slot = {
					melee = { spawn_data = {
						{ slot_index = 1, right_hand = true },
					} },
				},
			}
			local spawn_data = {
				{ unit_name = policy.UNIT_3P, slot_index = 1, right_hand = true },
			}
			H.equal(env.hooks["MenuWorldPreviewer._spawn_item"](
				function() return "spawned-menu-item" end,
				menu, ITEM_KEY, spawn_data), "spawned-menu-item")
			H.equal(env.applications[1].unit, unit)
			H.equal(env.applications[1].surface, "character-preview")

			env.hooks["MenuWorldPreviewer.trigger_pose_animation"](
				function() return "posed" end, menu, "inventory_idle")
			H.equal(env.hooks["MenuWorldPreviewer.post_update"](
				function() return "updated" end, menu, 0.016), "updated")
			H.equal(#env.reapplies, 1)
			H.equal(env.reapplies[1].unit, unit)

			H.equal(env.hooks[
				"MenuWorldPreviewer._destroy_item_units_by_slot"](
				function() return "destroyed" end, menu, "melee"), "destroyed")
			H.equal(#env.forgotten, 1)
			H.equal(env.forgotten[1], unit)
			H.equal(env.hooks["MenuWorldPreviewer.on_exit"](
				function() return "exited" end, menu), "exited")
		end)
	end)

	H.test("WOC #613 preview animation edges coalesce to absolute reapply readback", function()
		with_preview(function(env)
			local hero = spawn_team_preview(env)
			local unit = {}
			hero._equipment_units[1] = { right = unit }
			hero._item_info_by_slot.melee = {
				spawn_data = {
					{ slot_index = 1, right_hand = true },
				},
			}
			local spawn_data = {
				{ unit_name = policy.UNIT_3P, slot_index = 1, right_hand = true },
			}
			env.hooks["HeroPreviewer._spawn_item"](
				function() return "spawned-item" end,
				hero, ITEM_KEY, spawn_data)
			H.equal(#env.applications, 1)
			H.equal(env.applications[1].unit, unit)
			H.equal(env.applications[1].surface, "score-preview")
			H.equal(env.applications[1].perspective, "3p")

			env.hooks["HeroPreviewer.play_character_animation"](
				function() return "played" end, hero, "idle")
			env.hooks["HeroPreviewer.reset_pose_animation"](
				function() return "reset" end, hero)
			H.equal(#env.reapplies, 0)
			env.hooks["HeroPreviewer.post_update"](
				function() end, hero, 0.016)
			H.equal(#env.reapplies, 1)
			H.equal(env.reapplies[1].unit, unit)
			H.equal(env.reapplies[1].edge,
				"preview-post-animation:reset_pose_animation")
			env.hooks["HeroPreviewer.post_update"](
				function() end, hero, 0.016)
			H.equal(#env.reapplies, 1, "event replay must not become frame polling")

			env.hooks["HeroPreviewer._destroy_item_units_by_slot"](
				function() return "destroyed" end, hero, "melee")
			H.equal(#env.forgotten, 1)
			H.equal(env.forgotten[1], unit)

			local replacement = {}
			hero._equipment_units[1] = { right = replacement }
			local cleared = env.hooks["HeroPreviewer.clear_units"](
				function(self)
					self._equipment_units = {}
					return "cleared"
				end, hero)
			H.equal(cleared, "cleared")
			H.equal(#env.forgotten, 2)
			H.equal(env.forgotten[2], replacement)
			H.equal(env.runtime:test_snapshot(hero).record, nil,
				"clear_units must retire the TeamPreviewer consumer before respawn")
		end)
	end)

	H.test("WOC #613 Athanor surface is marked only by the exact vararg factory", function()
		with_preview(function(env)
			local athanor = { _spawned_units = {} }
			local result = env.hooks[
				"HeroWindowWeaveProperties._create_item_previewer"](
				function(self, first, second)
					H.equal(self.kind, "weave-properties")
					H.equal(first, "keep-vararg")
					H.equal(second, 17)
					return athanor
				end,
				{ kind = "weave-properties" }, "keep-vararg", 17)
			H.equal(result, athanor)
			H.truthy(athanor._woc_cim_preview)

			local cim_unit, generic_unit = {}, {}
			env.hooks["LootItemUnitPreviewer.spawn_units"](
				function() return { cim_unit } end,
				athanor, { { unit_name = policy.UNIT_1P } })
			env.hooks["LootItemUnitPreviewer.spawn_units"](
				function() return { generic_unit } end,
				{}, { { unit_name = policy.UNIT_1P } })
			H.equal(env.applications[1].surface, "cim-preview")
			H.equal(env.applications[2].surface, "item-preview")

			env.hooks["LootItemUnitPreviewer._destroy_units"](
				function(self)
					self._spawned_units = {}
					return "destroyed"
				end,
				{ _spawned_units = { cim_unit, generic_unit } })
			H.equal(#env.forgotten, 2)
			H.equal(env.forgotten[1], cim_unit)
			H.equal(env.forgotten[2], generic_unit)
		end)
	end)

	H.test("WOC #613 preview close cancels an in-flight borrowed package lease", function()
		with_preview(function(env)
			local callback, loads, unloads, completions = nil, {}, {}, {}
			Managers.package.load = function(_, name, reference, cb, asynchronous)
				loads[#loads + 1] = { name = name, reference = reference,
					asynchronous = asynchronous }
				callback = cb
			end
			Managers.package.unload = function(_, name, reference)
				unloads[#unloads + 1] = { name = name, reference = reference }
			end
			local preview = {
				_unique_id = 73,
				_packages_to_load = {},
				_loaded_packages = {},
			}
			function preview:_on_load_complete(name)
				completions[#completions + 1] = name
			end

			env.hooks["LootItemUnitPreviewer.load_package"](
				function() error("custom package must be borrowed") end,
				preview, policy.UNIT_1P)
			H.equal(#loads, 1)
			H.equal(loads[1].name, policy.VANILLA_1P)
			H.equal(loads[1].reference, "LootItemUnitPreviewer73")
			H.equal(loads[1].asynchronous, true)
			H.equal(preview._packages_to_load[policy.UNIT_1P], true)

			local result = env.hooks["LootItemUnitPreviewer._unload_packages"](
				function(self)
					for name in pairs(self._loaded_packages or {}) do
						Managers.package:unload(name, "LootItemUnitPreviewer73")
					end
					for name, unload in pairs(self._packages_to_load or {}) do
						if unload then
							Managers.package:unload(name, "LootItemUnitPreviewer73")
						end
					end
					return "unloaded"
				end, preview)
			H.equal(result, "unloaded")
			H.equal(#unloads, 1)
			H.equal(unloads[1].name, policy.VANILLA_1P)
			H.equal(preview._woc_preview_aliases, nil)
			H.equal(preview._woc_preview_fallbacks, nil)

			callback()
			H.equal(#completions, 0,
				"a callback after close must not resurrect the retired custom key")
		end)
	end)

	H.test("WOC #613 preview-owned callbacks fail closed without leaking state", function()
		with_preview(function(env)
			local unit = {}
			env.appearance.apply = function() error("appearance callback rejected") end
			local units = env.hooks["LootItemUnitPreviewer.spawn_units"](
				function() return { unit } end,
				{}, { { unit_name = policy.UNIT_1P } })
			H.equal(units[1], unit)

			local hero = {
				world = {}, _session_id = 7,
				_equipment_units = { { right = unit } },
			}
			env.transform_owner.reapply = function()
				error("reapply callback rejected")
			end
			env.hooks["HeroPreviewer.play_character_animation"](
				function() return "played" end, hero, "idle")
			H.equal(env.hooks["HeroPreviewer.post_update"](
				function() return "updated" end, hero, 0.016), "updated")

			env.transform_owner.forget = function()
				error("forget callback rejected")
			end
			H.equal(env.hooks["LootItemUnitPreviewer._destroy_units"](
				function() return "destroyed" end,
				{ _spawned_units = { unit } }), "destroyed")
		end)
	end)

	H.test("WOC #613 rejected identity replay unwinds its guard and stays event driven", function()
		with_preview(function(env)
			local hero, equips = spawn_team_preview(env)
			hero:equip_item("es_1h_sword",
				InventorySettings.slots_by_name.slot_melee,
				"vanilla-backend", "vanilla-skin", false)
			local working_equip = hero.equip_item
			env.snapshots["peer-wearer"] = authenticated_snapshot(17, true, false)
			H.equal(env.runtime:notify_identity("peer-wearer",
				env.snapshots["peer-wearer"], "generation-17"), 1)
			hero.equip_item = function() error("preview equip rejected") end
			env.hooks["HeroPreviewer.post_update"](
				function() return "updated" end, hero, 0.016)
			local record = env.runtime:test_snapshot(hero).record
			H.equal(record.reapplying, false,
				"a rejected asynchronous replay must unwind its recursion guard")
			H.equal(env.runtime:test_snapshot(hero).identity_pending, nil,
				"a rejected replay must not become an implicit frame poll")

			-- A later authoritative generation remains eligible and can rebuild.
			hero.equip_item = working_equip
			env.snapshots["peer-wearer"] = authenticated_snapshot(18, true, false)
			H.equal(env.runtime:notify_identity("peer-wearer",
				env.snapshots["peer-wearer"], "generation-18"), 1)
			env.hooks["HeroPreviewer.post_update"](
				function() return "updated" end, hero, 0.016)
			H.equal(#equips, 2)
			H.equal(equips[2].item_name, ITEM_KEY)
		end)
	end)

	H.test("WOC #613 rejected borrowed-package load rolls back its lease maps", function()
		with_preview(function(env)
			Managers.package.load = function()
				error("package load rejected")
			end
			local preview = {
				_unique_id = 91,
				_packages_to_load = {},
				_loaded_packages = {},
			}
			env.hooks["LootItemUnitPreviewer.load_package"](
				function() error("custom package must be borrowed") end,
				preview, policy.UNIT_3P)
			H.equal(preview._packages_to_load[policy.UNIT_3P], nil)
			H.equal(preview._woc_preview_aliases[policy.UNIT_3P], nil)
			H.equal(preview._woc_preview_fallbacks, nil,
				"resident custom units do not need a fallback map")
		end)
	end)
end
