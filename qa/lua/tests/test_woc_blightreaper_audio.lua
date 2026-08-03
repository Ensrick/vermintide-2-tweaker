return function(H, repo_root)
	local path = repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_audio.lua"
	local Audio = dofile(path)

	local function fixture(package_loaded)
		local calls = { trigger = {}, stop = {}, log = {} }
		local player_unit = {}
		local level_world = {}
		local next_id = 100
		local api = {
			unit = {
				alive = function(unit) return unit ~= nil and not unit.dead end,
			},
			wwise_utils = {
				trigger_unit_event = function(world, event, unit, node)
					next_id = next_id + 1
					calls.trigger[#calls.trigger + 1] = {
						world = world, event = event, unit = unit, node = node,
					}
					return next_id, {}, world
				end,
			},
			wwise_world = {
				is_playing = function() return true end,
				stop_event = function(world, playing_id)
					calls.stop[#calls.stop + 1] = { world, playing_id }
				end,
			},
			managers = {
				package = {
					has_loaded = function(_, package_name, reference)
						calls.package_query = { package_name, reference }
						return package_loaded ~= false
					end,
				},
				world = {
					world = function(_, name)
						if name == "level_world" then return level_world end
					end,
				},
			},
			local_player_unit = function() return player_unit end,
			printf = function(format, ...)
				calls.log[#calls.log + 1] = string.format(format, ...)
			end,
		}
		return Audio.new(api), calls, player_unit, level_world
	end

	H.test("WOC #633 locks exact native audio provenance", function()
		H.equal(Audio.INSPECT_EVENT, "nds_skull_inspect")
		H.equal(Audio.INSPECT_EVENT_ID, 0x094a950d)
		H.equal(Audio.INSPECT_BANK, "wwise/event_geheimnisnacht")
		H.equal(Audio.INSPECT_PACKAGE,
			"resource_packages/dlcs/geheimnisnacht_2021")
		H.equal(Audio.AMBIENT_EVENT, "emitter_trophy_evil_sword")
		H.equal(Audio.AMBIENT_EVENT_ID, 0x83e93b19)
		H.equal(Audio.AMBIENT_BANK, "wwise/level_hub")
		H.equal(Audio.SWING_EVENT, "sword_2h_swing")
		H.equal(Audio.CHARGE_EVENT, "rare_sword_2h_charge_swing_execution")
		H.equal(Audio.SWING_BANK, "wwise/two_handed_swords")
	end)

	H.test("WOC #633 plays exact Executioner charge and swing only for Blightreaper", function()
		local runtime, calls, player = fixture()
		local unit_1p, unit_3p = {}, {}
		runtime.observe_spawn(unit_3p, unit_1p, {}, player)
		local action = { world = {}, weapon_unit = unit_1p }
		H.truthy(runtime.play_swing(action, "charge"))
		H.truthy(runtime.play_swing(action, "release"))
		H.equal(calls.trigger[1].event, Audio.CHARGE_EVENT)
		H.equal(calls.trigger[2].event, Audio.SWING_EVENT)
		H.equal(calls.trigger[1].unit, unit_1p)
		H.equal(runtime.play_swing({ world = {}, weapon_unit = {} }, "release"), false)
		H.equal(#calls.trigger, 2)
	end)

	H.test("WOC #633 inspect is local 1P and single-owner", function()
		local runtime, calls, player = fixture()
		local owner_1p, unit_1p, unit_3p = {}, {}, {}
		runtime.observe_spawn(unit_3p, unit_1p, owner_1p, player)
		local first_action = { world = {}, weapon_unit = unit_1p }
		local second_action = { world = {}, weapon_unit = unit_1p }

		local ok, reason = runtime.start_inspect(first_action)
		H.truthy(ok)
		H.equal(reason, "started")
		H.equal(calls.package_query[1], Audio.INSPECT_PACKAGE)
		H.equal(calls.package_query[2], "boot")
		H.equal(calls.trigger[1].event, Audio.INSPECT_EVENT)
		H.equal(calls.trigger[1].unit, unit_1p)
		H.equal(runtime.snapshot().inspect, 1)

		-- A distinct action still replaces the one owned local whisper.
		H.truthy(runtime.start_inspect(second_action))
		H.equal(#calls.trigger, 2)
		H.equal(#calls.stop, 1)
		H.equal(runtime.snapshot().inspect, 1)
		H.truthy(runtime.finish_inspect(second_action, "release"))
		H.equal(#calls.stop, 2)
		H.equal(runtime.snapshot().active, 0)
	end)

	H.test("WOC #633 inspect fails closed for unrelated or absent resources", function()
		local runtime, calls = fixture()
		local ok, reason = runtime.start_inspect({ world = {}, weapon_unit = {} })
		H.equal(ok, false)
		H.equal(reason, "not-blightreaper")
		H.equal(#calls.trigger, 0)

		local absent, absent_calls, player = fixture(false)
		local unit_1p, unit_3p = {}, {}
		absent.observe_spawn(unit_3p, unit_1p, {}, player)
		ok, reason = absent.start_inspect({ world = {}, weapon_unit = unit_1p })
		H.equal(ok, false)
		H.equal(reason, "package-not-loaded")
		H.equal(#absent_calls.trigger, 0)
	end)

	H.test("WOC #633 every inspect lifecycle edge stops owned playback", function()
		local runtime, calls, player = fixture()
		local unit_1p, unit_3p = {}, {}
		runtime.observe_spawn(unit_3p, unit_1p, {}, player)
		local action = { world = {}, weapon_unit = unit_1p }

		H.truthy(runtime.start_inspect(action))
		runtime.update(Audio.INSPECT_MAX_SECONDS)
		H.equal(runtime.snapshot().active, 0)
		H.equal(#calls.stop, 1)

		H.truthy(runtime.start_inspect(action))
		runtime.stop_equipment({ right_hand_wielded_unit = unit_1p }, "destroy")
		H.equal(runtime.snapshot().active, 0)
		H.equal(#calls.stop, 2)

		H.truthy(runtime.start_inspect(action))
		unit_1p.dead = true
		runtime.update(0)
		H.equal(runtime.snapshot().active, 0)
		H.equal(#calls.stop, 3)
		unit_1p.dead = nil

		H.truthy(runtime.start_inspect(action))
		runtime.stop_all("world-exit")
		H.equal(runtime.snapshot().active, 0)
		H.equal(#calls.stop, 4)
	end)

	H.test("WOC #633 ambient diagnostic is spatial, bounded, and capped", function()
		local runtime, calls, player, level_world = fixture()
		local unit_1p, unit_3p = {}, {}
		runtime.observe_spawn(unit_3p, unit_1p, {}, player)

		for _ = 1, Audio.PROBE_MAX_RUNS do
			H.truthy(runtime.probe_ambient())
			runtime.update(Audio.PROBE_MAX_SECONDS)
		end
		local ok, reason = runtime.probe_ambient()
		H.equal(ok, false)
		H.equal(reason, "probe-cap")
		H.equal(#calls.trigger, Audio.PROBE_MAX_RUNS)
		H.equal(#calls.stop, Audio.PROBE_MAX_RUNS)
		for i = 1, #calls.trigger do
			H.equal(calls.trigger[i].event, Audio.AMBIENT_EVENT)
			H.equal(calls.trigger[i].unit, unit_3p)
			H.equal(calls.trigger[i].world, level_world)
		end
		H.equal(runtime.snapshot().active, 0)
	end)

	H.test("WOC #633 never force-loads or networks level audio", function()
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a")
		file:close()
		H.equal(source:find("Managers.package" .. ":load(", 1, true), nil)
		H.equal(source:find("network_send", 1, true), nil)
		H.truthy(source:find("PROBE_MAX_RUNS = 3", 1, true))
		H.truthy(source:find("PROBE_MAX_SECONDS = 8", 1, true))
	end)

	H.test("WOC #633 named semantic regression drives ownership and probe lifecycle", function()
		H.equal(Audio.regression_check(), nil)
	end)

	H.test("WOC #633 runtime hooks are singleton and fully cleaned", function()
		local main_path = repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua"
		local file = assert(io.open(main_path, "rb"))
		local source = file:read("*a")
		file:close()
		local needles = {
			'mod:hook("ActionInspect", "client_owner_start_action"',
			'mod:hook("ActionInspect", "finish"',
			'mod:hook("GearUtils", "destroy_equipment"',
			'mod:hook("ActionMeleeStart", "client_owner_start_action"',
			'mod:hook("ActionSweep", "client_owner_start_action"',
		}
		for _, needle in ipairs(needles) do
			local count, position = 0, 1
			while true do
				local found = source:find(needle, position, true)
				if not found then break end
				count = count + 1
				position = found + 1
			end
			H.equal(count, 1)
		end
		H.truthy(source:find('_audio.stop_all("game-state-exit:', 1, true))
		H.truthy(source:find('_audio.stop_all("mod-disabled")', 1, true))
		H.truthy(source:find('_audio.stop_all("mod-unload")', 1, true))
		H.truthy(source:find('local semantic_error = _audio_lib.regression_check()', 1, true))
		for _, surface in ipairs({
			"spawn_observer", "inspect_start", "inspect_finish", "charge_audio",
			"swing_audio", "equipment_cleanup", "contract_command", "probe_command",
			"bounded_update", "game_state_cleanup", "disable_cleanup", "unload_cleanup",
		}) do
			H.truthy(source:find('_woc633_surface("' .. surface .. '")', 1, true),
				"missing #633 live surface registration: " .. surface)
		end
	end)
end
