local function read(path)
	local file = assert(io.open(path, "rb"))
	local content = file:read("*a")
	file:close()
	return content
end

return function(H, repo_root)
	local module_root = repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
	local M = assert(loadfile(module_root .. "_cwv_outrider_projectile_wire.lua"))()
	local network_lookup = assert(loadfile(module_root .. "_lib_network_lookup.lua"))()

	-- Fixture in the exact shape the Outrider clone leaves weapons.lua's boot
	-- stamp: donor-named rows on the deep-copied actions, a blunderbuss-named
	-- row on the copied bash, and one action table shared BY IDENTITY with
	-- vanilla ActionTemplates that must never be written.
	local function make_clone()
		local shared_inspect = { default = { kind = "dummy", lookup_data = {
			item_template_name = "some_native_template",
			action_name = "action_inspect", sub_action_name = "default" } } }
		local clone = { actions = {
			action_one = {
				default = { kind = "grenade_thrower", lookup_data = {
					item_template_name = "dr_deus_01_template_1",
					action_name = "action_one", sub_action_name = "default" } },
				shoot_charged = { kind = "grenade_thrower", lookup_data = {
					item_template_name = "dr_deus_01_template_1",
					action_name = "action_one", sub_action_name = "shoot_charged" } },
			},
			action_two = {
				default = { kind = "shield_slam", lookup_data = {
					item_template_name = "blunderbuss_template_1",
					action_name = "action_two", sub_action_name = "default" } },
			},
			action_inspect = shared_inspect,
		} }
		return clone, shared_inspect
	end

	H.test("CWV #1320 planner takes only clone-private rows and stamps idempotently", function()
		local clone, shared_inspect = make_clone()
		local shared = M.shared_action_set({ action_inspect = shared_inspect })
		local rows, skipped = M.plan_restamp(clone, shared)
		H.equal(#rows, 3)
		H.equal(skipped, 1)
		H.equal(M.apply_restamp(rows, M.TEMPLATE_KEY), 3)
		H.equal(clone.actions.action_one.default.lookup_data.item_template_name,
			M.TEMPLATE_KEY)
		H.equal(clone.actions.action_two.default.lookup_data.item_template_name,
			M.TEMPLATE_KEY)
		-- Position identity is untouched: only the template name is re-pointed.
		H.equal(clone.actions.action_one.shoot_charged.lookup_data.sub_action_name,
			"shoot_charged")
		H.equal(clone.actions.action_two.default.lookup_data.action_name, "action_two")
		-- The shared vanilla table was skipped, never written.
		H.equal(shared_inspect.default.lookup_data.item_template_name,
			"some_native_template")
		-- Second pass is a no-op.
		H.equal(M.apply_restamp(rows, M.TEMPLATE_KEY), 0)
	end)

	H.test("CWV #1320 install registers a bidirectional id then stamps the clone", function()
		local old_w, old_nl, old_at = _G.Weapons, _G.NetworkLookup, _G.ActionTemplates
		local ok, err = pcall(function()
			local clone, shared_inspect = make_clone()
			_G.Weapons = { [M.TEMPLATE_KEY] = clone }
			local lookup = { "n/a", "dr_deus_01_template_1" }
			lookup["n/a"] = 1
			lookup.dr_deus_01_template_1 = 2
			_G.NetworkLookup = { item_template_names = lookup }
			_G.ActionTemplates = { action_inspect = shared_inspect }
			local om, logs = {}, {}
			local state = M.install(nil, { om = om, network_lookup = network_lookup,
				printf = function(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end })
			H.equal(om.outrider_projectile_wire, state)
			H.equal(state.registered, true)
			H.equal(state.reason, "registered")
			H.equal(state.lookup_index, 3)
			H.equal(rawget(lookup, 3), M.TEMPLATE_KEY)
			H.equal(rawget(lookup, M.TEMPLATE_KEY), 3)
			H.equal(state.rows, 3)
			H.equal(state.restamped, 3)
			H.equal(state.shared_skipped, 1)
			H.equal(clone.actions.action_one.default.lookup_data.item_template_name,
				M.TEMPLATE_KEY)
			H.equal(shared_inspect.default.lookup_data.item_template_name,
				"some_native_template")
			H.equal(#logs, 1)
			H.truthy(logs[1]:find("[cwv:1320]", 1, true))
			-- Re-install is idempotent: same reserved id, zero new stamps.
			local second = M.install(nil, { om = om, network_lookup = network_lookup })
			H.equal(second.registered, true)
			H.equal(second.lookup_index, 3)
			H.equal(second.restamped, 0)
		end)
		_G.Weapons, _G.NetworkLookup, _G.ActionTemplates = old_w, old_nl, old_at
		if not ok then error(err) end
	end)

	H.test("CWV #1320 fails closed: donor name keeps riding when the row is unprovable", function()
		local old_w, old_nl, old_at = _G.Weapons, _G.NetworkLookup, _G.ActionTemplates
		local ok, err = pcall(function()
			local clone = make_clone()
			_G.Weapons = { [M.TEMPLATE_KEY] = clone }
			-- Half-registered pair: the strict decode of a half pair is the #423
			-- crash class, so no re-stamp may proceed on top of it.
			local lookup = { "n/a" }
			lookup["n/a"] = 1
			lookup[M.TEMPLATE_KEY] = 5
			_G.NetworkLookup = { item_template_names = lookup }
			_G.ActionTemplates = {}
			local om = {}
			local state = M.install(nil, { om = om, network_lookup = network_lookup })
			H.equal(state.registered, false)
			H.equal(state.reason, "lookup:pair_asymmetric")
			H.equal(clone.actions.action_one.default.lookup_data.item_template_name,
				"dr_deus_01_template_1")
		end)
		_G.Weapons, _G.NetworkLookup, _G.ActionTemplates = old_w, old_nl, old_at
		if not ok then error(err) end
	end)

	H.test("CWV #1320 reports template_missing when the donor never built the clone", function()
		local old_w, old_nl = _G.Weapons, _G.NetworkLookup
		local ok, err = pcall(function()
			_G.Weapons = {}
			local lookup = { "n/a" }
			lookup["n/a"] = 1
			_G.NetworkLookup = { item_template_names = lookup }
			local om = {}
			local state = M.install(nil, { om = om, network_lookup = network_lookup })
			H.equal(state.registered, false)
			H.equal(state.reason, "template_missing")
			H.equal(rawget(lookup, M.TEMPLATE_KEY), nil)
		end)
		_G.Weapons, _G.NetworkLookup = old_w, old_nl
		if not ok then error(err) end
	end)

	H.test("CWV owns the exact canonical NetworkLookup helper copy", function()
		H.equal(read(module_root .. "_lib_network_lookup.lua"),
			read(repo_root .. "/tools/shared_lib/_lib_network_lookup.lua"),
			"CWV helper copy drifted")
		local manifest = read(repo_root .. "/tools/shared_lib/manifest.psd1")
		H.truthy(manifest:find(
			'"character_weapon_variants/scripts/mods/character_weapon_variants/_lib_network_lookup.lua"',
			1, true), "CWV helper is absent from the shared-library manifest")
		local transport = read(module_root .. "_cwv_item_identity_transport_owner.lua")
		H.truthy(transport:find(
			'mod:dofile("scripts/mods/character_weapon_variants/_cwv_outrider_projectile_wire")',
			1, true), "identity transport owner does not install the outrider wire")
		H.truthy(transport:find(
			'"scripts/mods/character_weapon_variants/_lib_network_lookup"',
			1, true), "identity transport owner does not load the shared helper")
	end)
end
