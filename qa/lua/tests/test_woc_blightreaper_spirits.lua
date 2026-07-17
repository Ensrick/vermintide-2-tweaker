return function(H, repo_root)
	local spirits = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_spirits.lua")

	H.test("WOC Blightreaper spirits preserve native rank-one Shyish policy", function()
		H.equal(spirits.UNIT, "units/fx/vfx_animation_death_spirit_02")
		H.equal(spirits.UNIT_TEMPLATE, "position_synched_dummy_unit")
		H.equal(spirits.PACKAGE, "resource_packages/dlcs/mutators_batch_04")
		H.equal(spirits.PACKAGE_REFERENCE, "woc_blightreaper_spirits")
		local package, reason = spirits.package_contract({
			mutators_batch_04 = { package_name = spirits.PACKAGE },
		})
		H.equal(package, spirits.PACKAGE)
		H.equal(reason, "source_backed")
		H.equal(spirits.package_contract({}), nil)
		H.equal(spirits.CONVERT_AMOUNT, 5)
		H.equal(spirits.DELAY_TIME, 3)
		H.equal(spirits.CHASE_SPEED, 1)
		H.equal(spirits.CHASE_TIME, 6)
		H.equal(spirits.HIT_DISTANCE, 1)
		H.equal(spirits.MAX_ACTIVE, 32)
		H.deep_equal(spirits.audio_contract(), {
			release = "Play_winds_death_gameplay_spirit_release",
			loop = "Play_winds_death_gameplay_spirit_loop",
			explode = "Play_winds_death_gameplay_spirit_explode",
		})
		H.equal(spirits.convert_amount(10), 5)
		H.equal(spirits.convert_amount(3), 2)
		H.equal(spirits.convert_amount(1), 0)
		H.equal(spirits.convert_amount(nil), 0)
	end)

	H.test("WOC Blightreaper direct and Hagbane DOT kills attribute exactly", function()
		local ok, reason = spirits.kill_is_attributable(
			true, "light_attack", false, nil)
		H.equal(ok, true)
		H.equal(reason, "direct_or_wielded")

		ok, reason = spirits.kill_is_attributable(
			false, "arrow_poison_dot", true, 3)
		H.equal(ok, true)
		H.equal(reason, "hagbane_dot")

		ok, reason = spirits.kill_is_attributable(
			false, "arrow_poison_dot", true, 5)
		H.equal(ok, false)
		H.equal(reason, "stale_poison")

		ok, reason = spirits.kill_is_attributable(
			false, "arrow_poison_dot", false, 1)
		H.equal(ok, false)
		H.equal(reason, "not_blightreaper")

		ok = spirits.kill_is_attributable(false, "burninating", true, 1)
		H.equal(ok, false)
	end)

	H.test("WOC production spirit path is host-authoritative and traffic-bounded", function()
		local path = repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua"
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a")
		file:close()
		for _, needle in ipairs({
			'events:register(mod, "on_player_killed_enemy"',
			'"BuffSystem", "rpc_add_buff_synced_params"',
			'spawner:spawn_network_unit(_spirits.UNIT',
			'health:convert_to_temp(_spirits.CONVERT_AMOUNT)',
			'if _spirit_state.count >= _spirits.MAX_ACTIVE then',
			'if network and network.is_server then _update_spirits(dt) end',
			'_audio.update(dt)',
		}) do
			H.truthy(source:find(needle, 1, true), "missing spirit boundary: " .. needle)
		end
		local _, update_count = source:gsub("mod%.update%s*=%s*function", "")
		H.equal(update_count, 1, "WOC audio and spirit work must share one update callback")
		H.equal(source:find('network_register("woc_blightreaper_spirit', 1, true), nil)

		local package_path = repo_root
			.. "/weapons_of_chaos/resource_packages/weapons_of_chaos/weapons_of_chaos.package"
		local package_file = assert(io.open(package_path, "rb"))
		local package_source = package_file:read("*a")
		package_file:close()
		H.equal(package_source:find('"' .. spirits.UNIT .. '"', 1, true), nil,
			"unavailable native source unit must not break WOC compilation")
		H.truthy(source:find('_spirits.package_contract(rawget(_G, "DLCSettings"))',
			1, true), "production must resolve the source-backed real package")
		H.equal(source:find('load(_spirits.UNIT', 1, true), nil,
			"native spirit must not be force-loaded as a package")
	end)
end
