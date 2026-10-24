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
		local package_manager = {
			has_loaded = function(_, package, reference)
				return package == spirits.PACKAGE
					and reference == spirits.PACKAGE_REFERENCE
			end,
		}
		H.equal(spirits.package_ready(package_manager), true)
		H.equal(spirits.package_ready({ has_loaded = function() return false end }), false)
		H.equal(spirits.CONVERT_AMOUNT, 5)
		H.equal(spirits.SPIRIT_DAMAGE, 5)
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
		H.equal(spirits.contact_damage(10, 0), 5)
		H.equal(spirits.contact_damage(3, 0), 2)
		H.equal(spirits.contact_damage(2, 4), 5)
		H.equal(spirits.contact_damage(1, 0), 0)
		H.equal(spirits.contact_damage(nil, 0), 0)
		H.equal(spirits.DAMAGE_TYPE, "death_explosion")
		H.equal(spirits.DAMAGE_SOURCE, "undefined")
		H.equal(spirits.HEAL_TYPE, "mutator")
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

	H.test("WOC spirit positions reject stale lookup userdata before arithmetic", function()
		local unit = {}
		local live = { vector = true, source = "live" }
		local stale = { source = "stale" }
		local function is_vector(value)
			return type(value) == "table" and value.vector == true
		end

		local position, reason = spirits.resolve_position(unit, function()
			return live
		end, { [unit] = stale }, is_vector)
		H.equal(position, live)
		H.equal(reason, "live")

		local fallback = { vector = true, source = "lookup" }
		position, reason = spirits.resolve_position(unit, function()
			error("dead engine unit")
		end, { [unit] = fallback }, is_vector)
		H.equal(position, fallback)
		H.equal(reason, "lookup")

		position, reason = spirits.resolve_position(unit, function()
			return stale
		end, { [unit] = stale }, is_vector)
		H.equal(position, nil)
		H.equal(reason, "invalid_live_and_lookup")
	end)

	H.test("WOC production spirit path is host-authoritative and traffic-bounded", function()
		local path = repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua"
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a")
		file:close()
		local owner_file = assert(io.open(repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_spirit_runtime_owner.lua", "rb"))
		local owner = owner_file:read("*a")
		owner_file:close()
		-- #1700: the phase-5 extraction moved the state/creators into this
		-- owner. Pin both the entry's dispatch and the owner's host-gated
		-- producers; scanning the old entry alone never exercises that seam.
		for _, needle in ipairs({
			'events:register(mod, "on_player_killed_enemy"',
			'"BuffSystem", "rpc_add_buff_synced_params"',
			'spawner:spawn_network_unit(_spirits.UNIT',
			'_spirits.package_ready(packages)',
			'damage_utils.add_damage_network(target, unit, amount',
			'damage_utils.heal_network(target, target, dealt',
			'if _spirit_state.count >= _spirits.MAX_ACTIVE then',
			'_owner_trait_evidence(',
			'"kill observed peer=%s damage=%s source=%s trait=%s identity=%s',
		}) do
			H.truthy(owner:find(needle, 1, true), "missing spirit owner boundary: " .. needle)
		end
		for _, needle in ipairs({
			'"scripts/mods/weapons_of_chaos/_woc_spirit_runtime_owner").new({',
			'_audio.update(dt)', '_spirit_runtime:update(dt)',
			'_spirit_runtime:stop("mod-disabled")', '_release_spirit_package("mod-disabled")',
			'_spirit_runtime:stop("mod-unload")', '_release_spirit_package("mod-unload")',
		}) do
			H.truthy(source:find(needle, 1, true), "missing spirit entry dispatch: " .. needle)
		end
		for _, definition in ipairs({
			'_mark_blight_poison = function(hit_unit, owner_unit)',
			'local function _spawn_spirit(killed_unit, target_unit, attribution)',
			'local function _on_blightreaper_kill(killing_blow, _, killed_unit)',
			'_start_spirit_runtime = function()',
		}) do
			local start = assert(owner:find(definition, 1, true), "missing host-owned producer")
			local finish = assert(owner:find("\nend", start, true), "unterminated producer")
			H.truthy(owner:sub(start, finish):find("network.is_server", 1, true),
				"producer lost its host boundary: " .. definition)
		end
		local _, update_count = source:gsub("mod%.update%s*=%s*function", "")
		H.equal(update_count, 1, "WOC audio and spirit work must share one update callback")
		H.equal((source .. owner):find('network_register("woc_blightreaper_spirit', 1, true), nil)
		H.equal((source .. owner):find('Application.can_get, "unit", _spirits.UNIT', 1, true), nil,
			"loaded native package is the spawn boundary; stale can_get blocked all spirits")
		H.equal((source .. owner):find('convert_to_temp', 1, true), nil,
			"contact must reproduce native death_explosion damage then mutator heal")
		H.truthy(owner:find('local target_pos, target_pos_reason = _spirit_position(target)',
			1, true), "chase target must pass the validated live-position seam")
		H.truthy(owner:find('local position, position_reason = _spirit_position(unit)',
			1, true), "spawned spirit must pass the validated live-position seam")
		H.truthy(owner:find('if not entry.chase_logged then', 1, true),
			"chase-start telemetry must be once per spirit, not per frame")
		H.equal(owner:find('local target_pos = POSITION_LOOKUP[target]', 1, true), nil,
			"stale lookup userdata must never reach Vector3 arithmetic directly")

		local package_path = repo_root
			.. "/weapons_of_chaos/resource_packages/weapons_of_chaos/weapons_of_chaos.package"
		local package_file = assert(io.open(package_path, "rb"))
		local package_source = package_file:read("*a")
		package_file:close()
		H.equal(package_source:find('"' .. spirits.UNIT .. '"', 1, true), nil,
			"unavailable native source unit must not break WOC compilation")
		H.truthy(source:find('_spirits.package_contract(rawget(_G, "DLCSettings"))',
			1, true), "production must resolve the source-backed real package")
		-- The entry's own runtime diagnostic quotes the forbidden spelling.
		-- Inspect the actual acquisition owner, not that inert quoted needle.
		local acquire_start = assert(source:find("local function _ensure_spirit_package()", 1, true))
		local acquire_end = assert(source:find("\nlocal function _release_spirit_package", acquire_start, true))
		local acquire = source:sub(acquire_start, acquire_end - 1)
		H.equal(acquire:find('load(_spirits.UNIT', 1, true), nil,
			"package acquisition must not force-load a unit as a package")
		H.equal(owner:find('load(_spirits.UNIT', 1, true), nil,
			"spirit runtime must not bypass the package acquisition owner")
	end)
end
