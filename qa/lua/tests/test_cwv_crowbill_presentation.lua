return function(H, repo_root)
	local path = repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_crowbill_presentation.lua"
	local presentation = dofile(path)

	local function read(file_path)
		local file = assert(io.open(file_path, "rb"))
		local source = file:read("*a")
		file:close()
		return source
	end

	local ops = {
		identity = function() return "identity" end,
		axis_angle = function(axis, degrees)
			return { kind = "axis_angle", axis = axis, degrees = degrees }
		end,
		multiply = function(base, delta)
			return { kind = "multiply", left = base, right = delta }
		end,
	}

	H.test("Crowbill hammer presentation composes exact local-Z rotation", function()
		local pick = presentation.compose_rotation("authored_base", "pick", ops)
		H.equal(pick, "authored_base")
		local hammer = presentation.compose_rotation("authored_base", "hammer", ops)
		H.equal(hammer.kind, "multiply")
		H.equal(hammer.left, "authored_base")
		H.equal(hammer.right.kind, "axis_angle")
		H.deep_equal(hammer.right.axis, { 0, 0, 1 })
		H.equal(hammer.right.degrees, 180)
		local no_base = presentation.compose_rotation(nil, "hammer", ops)
		H.equal(no_base.left, "identity")
		H.equal(presentation.compose_rotation("base", "bad-mode", ops), nil)
	end)

	H.test("Crowbill presentation replay is absolute and bounded", function()
		local modes = { weapon_1 = "hammer" }
		local writes = {}
		local owner = presentation.new({
			alive = function(unit) return unit.alive end,
			mode_for = function(identity) return modes[identity] or "pick" end,
			retain_rotation = function(rotation) return { boxed = rotation } end,
			resolve_rotation = function(rotation) return rotation and rotation.boxed end,
			rotation_ops = ops,
			write_rotation = function(unit, rotation)
				writes[#writes + 1] = rotation
				unit.rotation = rotation
				return true
			end,
		})
		local unit = { alive = true }
		H.truthy(owner:apply(unit, "weapon_1", "owner_3p", "authored_base"))
		H.equal(writes[1].left, "authored_base")
		-- Simulate a duplicated preview/lifecycle hook passing the current pose.
		H.truthy(owner:apply(unit, "weapon_1", "owner_3p", writes[1]))
		H.equal(writes[2].left, "authored_base")
		modes.weapon_1 = "pick"
		H.equal(owner:reapply("weapon_1"), 1)
		H.equal(writes[3], "authored_base")
		unit.alive = false
		H.equal(owner:reapply("weapon_1"), 0)
	end)

	H.test("Crowbill score identity accepts exact humans and rejects owner-aliased bots", function()
		local scores = {
			local_human = { peer_id = "peer-local", local_player_id = 1,
				profile_index = 5, career_index = 4, is_player_controlled = true },
			remote_human = { peer_id = "peer-remote", local_player_id = 1,
				profile_index = 5, career_index = 1, is_player_controlled = true },
			bot = { peer_id = "peer-local", local_player_id = 1,
				profile_index = 1, career_index = 4, is_player_controlled = false },
		}
		local peer, source = presentation.resolve_score_peer(5, 1, scores)
		H.equal(peer, "peer-remote")
		H.equal(source, "score_snapshot")
		local bot_peer, bot_source = presentation.resolve_score_peer(1, 4, scores)
		H.equal(bot_peer, nil)
		H.equal(bot_source, "score_bot")
		H.equal(presentation.resolve_score_peer(5, 3, scores), nil)
	end)

	H.test("Crowbill presentation standard names every required surface", function()
		for _, surface in ipairs({
			"owner_1p", "owner_3p", "bot", "remote_husk",
			"inventory_preview", "lobby_preview", "score_preview",
			"item_browser", "customization_preview",
		}) do
			H.equal(presentation.SURFACES[surface], true, "missing surface " .. surface)
		end
	end)

	H.test("Crowbill runtime routes all reconstruction seams through one owner", function()
		local main = read(repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua")
		for _, marker in ipairs({
			'"owner_1p", right_rot_1p',
			'is_bot and "bot" or "owner_3p"',
			'"remote_husk", rotation',
			'local preview_surface = "inventory_preview"',
			'and "score_preview" or "lobby_preview"',
			'"item_browser", rotation',
			'mod:hook("TeamPreviewer", "_spawn_hero"',
			'_om.crowbill_mode_state = _om.crowbill_mode_state or',
			'_om.crowbill_runtime.remote_identity(owner_unit_3p',
			'mod:hook("HeroPreviewer", "_spawn_item"',
			'mod:hook("MenuWorldPreviewer", "_spawn_item"',
			'mod:hook("LootItemUnitPreviewer", "spawn_units"',
		}) do
			H.truthy(main:find(marker, 1, true), "missing runtime route: " .. marker)
		end
		H.truthy(main:find("_cwv_crowbill_set_mode", 1, true))
		H.truthy(main:find("_cwv_crowbill_apply_remote_mode", 1, true))
	end)

	H.test("Crowbill presentation is model-manifest agnostic and non-polling", function()
		local source = read(path)
		H.equal(source:find("units/", 1, true), nil)
		H.equal(source:find("mod.update", 1, true), nil)
		H.equal(source:find("network_send", 1, true), nil)
		H.truthy(source:find("base_rotation", 1, true))
	end)
end
