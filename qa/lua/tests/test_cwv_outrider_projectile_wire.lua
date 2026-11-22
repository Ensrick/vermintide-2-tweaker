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

	-- A2-F01: the clone name is a LOCAL item_template_names append. The fired
	-- projectile's own action_lookup_data copy is what the game-object
	-- initializer encodes for every peer (game_object_initializers_extractors.lua:737,755),
	-- and a peer decodes it with a strict lookup (:3284), so the wire must carry
	-- the donor's vanilla name.
	H.test("CWV A2-F01 wire_template_name maps only the clone name to the donor", function()
		H.equal(M.wire_template_name(M.TEMPLATE_KEY), M.DONOR_TEMPLATE_KEY)
		H.equal(M.wire_template_name("blunderbuss_template_1"), "blunderbuss_template_1")
		H.equal(M.wire_template_name(M.DONOR_TEMPLATE_KEY), M.DONOR_TEMPLATE_KEY)
		H.equal(M.wire_template_name(nil), nil)
	end)

	H.test("CWV A2-F01 sanitize_projectile_lookup leaves a vanilla-decodable name and the action names", function()
		local ext = { action_lookup_data = { item_template_name = M.TEMPLATE_KEY,
			action_name = "action_one", sub_action_name = "default" } }
		H.equal(M.sanitize_projectile_lookup(ext), true)
		local strict = setmetatable({ dr_deus_01_template_1 = 2, [2] = "dr_deus_01_template_1" },
			{ __index = function(_, k) error("missing " .. tostring(k)) end })
		H.equal(strict[ext.action_lookup_data.item_template_name], 2)
		H.equal(ext.action_lookup_data.action_name, "action_one")
		H.equal(ext.action_lookup_data.sub_action_name, "default")
		H.equal(M.sanitize_projectile_lookup(ext), false, "a second call changes nothing")
		H.equal(M.sanitize_projectile_lookup({}), false)
		H.equal(M.sanitize_projectile_lookup(nil), false)
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
			H.equal(#logs, 2)
			H.truthy(logs[1]:find("[cwv:1320] outrider projectile swap: rows=0 swapped=0", 1, true),
				"no Projectiles table in this fixture: the swap reports zero rows")
			H.truthy(logs[2]:find("[cwv:1320] outrider projectile wire:", 1, true))
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

	-- Vanilla stores the projectile config by reference only on the template
	-- file's local (weapon_templates/dr_deus_01.lua:56). The registered donor
	-- is `dr_deus_01_template_1 = table.clone(weapon_template)` (:326) and the
	-- Outrider clone deep-copies that donor; both copies are deep
	-- (foundation table.lua:31-49), exactly as this fixture does.
	local function deep_clone(value)
		if type(value) ~= "table" then return value end
		local copy = {}
		for key, child in pairs(value) do copy[key] = deep_clone(child) end
		return copy
	end
	local DONOR_INFO = { projectile_units_template = "dr_deus_01_head",
		gravity_settings = "drakegun", trajectory_template_name = "throw_trajectory" }
	local function make_base()
		return { actions = { action_one = {
			default = { kind = "grenade_thrower", projectile_info = DONOR_INFO },
			push = { kind = "push_stagger" },
		} } }
	end
	-- Weapons.dr_deus_01_template_1 as vanilla registers it: a deep copy.
	local function make_donor() return deep_clone(make_base()) end

	H.test("CWV #1320 deep-copied donor and clone defeat identity; planner matches the units template and swaps the clone only", function()
		local donor = make_donor()
		local donor_info_copy = donor.actions.action_one.default.projectile_info
		H.truthy(donor_info_copy ~= DONOR_INFO,
			"the registered donor is a deep copy, so a donor-identity match never held (rows=0 in game)")
		local clone = deep_clone(donor)
		local shoot = clone.actions.action_one.default
		H.truthy(shoot.projectile_info ~= DONOR_INFO,
			"the deep copy is why the old clone identity guard never matched")
		H.equal(shoot.projectile_info.projectile_units_template, "dr_deus_01_head")
		local grenade = deep_clone(DONOR_INFO)
		grenade.projectile_units_template = "grenade"
		local rows = M.plan_projectile_swap(clone, DONOR_INFO)
		H.equal(#rows, 1)
		H.equal(rows[1].sub_action_name, "default")
		H.equal(M.apply_projectile_swap(rows, grenade), 1)
		H.equal(shoot.projectile_info, grenade,
			"the fire action points at the authored grenade config (the #1320 check's assertion)")
		H.equal(donor.actions.action_one.default.projectile_info, donor_info_copy,
			"the NATIVE Trollhammer keeps the torpedo config (#475 Invariant 1)")
		H.equal(donor_info_copy.projectile_units_template, "dr_deus_01_head")
		H.equal(clone.actions.action_one.push.projectile_info, nil)
		H.equal(M.apply_projectile_swap(rows, grenade), 0, "second pass is a no-op")
		H.equal(#M.plan_projectile_swap(clone, DONOR_INFO), 0,
			"after the swap no clone row still carries the torpedo units template")
	end)

	H.test("CWV #1320 planner matches every row on the donor units template and skips foreign projectiles", function()
		local clone = deep_clone(make_donor())
		clone.actions.action_one.shoot_charged = { kind = "grenade_thrower",
			projectile_info = deep_clone(DONOR_INFO) }
		clone.actions.action_one.arrow = { kind = "grenade_thrower",
			projectile_info = { projectile_units_template = "we_deus_01_arrow" } }
		local rows = M.plan_projectile_swap(clone, DONOR_INFO)
		H.equal(#rows, 2)
		H.equal(rows[1].sub_action_name, "default")
		H.equal(rows[2].sub_action_name, "shoot_charged")
		local grenade = { projectile_units_template = "grenade" }
		H.equal(M.apply_projectile_swap(rows, grenade), 2)
		H.equal(clone.actions.action_one.arrow.projectile_info.projectile_units_template,
			"we_deus_01_arrow", "a sub-action on another projectile is never swapped")
		-- Fail-closed shapes: no config, no clone, no grenade config.
		H.equal(#M.plan_projectile_swap(clone, nil), 0)
		H.equal(#M.plan_projectile_swap(nil, DONOR_INFO), 0)
		H.equal(M.apply_projectile_swap(rows, nil), 0)
	end)

	H.test("CWV #1320 planner refuses to match when the donor config has no units template", function()
		local clone = { actions = { action_one = {
			default = { kind = "grenade_thrower", projectile_info = { gravity_settings = "drakegun" } },
			other = { kind = "grenade_thrower", projectile_info = { gravity_settings = "arrows" } },
		} } }
		H.equal(#M.plan_projectile_swap(clone, { gravity_settings = "drakegun" }), 0,
			"nil == nil must not select every projectile row")
		H.equal(#M.plan_projectile_swap(clone, { projectile_units_template = "" }), 0)
		H.equal(#M.plan_projectile_swap(clone, { projectile_units_template = 7 }), 0)
	end)

	H.test("CWV #1320 install swaps the fire action of a deep-copied donor's clone and leaves the donor alone", function()
		local old_w, old_nl, old_at, old_p = _G.Weapons, _G.NetworkLookup, _G.ActionTemplates, _G.Projectiles
		local ok, err = pcall(function()
			local donor = make_donor()
			donor.actions.action_one.default.lookup_data = {
				item_template_name = M.DONOR_TEMPLATE_KEY,
				action_name = "action_one", sub_action_name = "default" }
			local donor_info_copy = donor.actions.action_one.default.projectile_info
			local clone = deep_clone(donor)
			local grenade = deep_clone(DONOR_INFO)
			grenade.projectile_units_template = "grenade"
			_G.Weapons = { [M.TEMPLATE_KEY] = clone, [M.DONOR_TEMPLATE_KEY] = donor }
			_G.Projectiles = { [M.DONOR_PROJECTILE_KEY] = DONOR_INFO,
				[M.GRENADE_PROJECTILE_KEY] = grenade }
			local lookup = { "n/a" }
			lookup["n/a"] = 1
			_G.NetworkLookup = { item_template_names = lookup }
			_G.ActionTemplates = {}
			local logs = {}
			local state = M.install(nil, { om = {}, network_lookup = network_lookup,
				printf = function(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end })
			H.equal(state.registered, true)
			H.equal(state.projectile_rows, 1)
			H.equal(state.projectile_swapped, 1)
			H.equal(state.projectile_units_template, "grenade")
			H.equal(clone.actions.action_one.default.projectile_info, grenade,
				"the fire action points at the authored grenade config (the #1320 check's assertion)")
			H.equal(donor.actions.action_one.default.projectile_info, donor_info_copy,
				"the NATIVE Trollhammer keeps the torpedo config")
			H.equal(donor_info_copy.projectile_units_template, "dr_deus_01_head")
			H.truthy(logs[1]:find(
				"[cwv:1320] outrider projectile swap: rows=1 swapped=1 units_template=grenade", 1, true))
			-- Re-install: the swap is idempotent (nothing left to plan).
			local second = M.install(nil, { om = {}, network_lookup = network_lookup })
			H.equal(second.projectile_rows, 0)
			H.equal(second.projectile_swapped, 0)
			H.equal(clone.actions.action_one.default.projectile_info, grenade)
		end)
		_G.Weapons, _G.NetworkLookup, _G.ActionTemplates, _G.Projectiles = old_w, old_nl, old_at, old_p
		if not ok then error(err) end
	end)

	H.test("CWV #1320 the constructor no longer compares clone identity and the wire owner plans the swap", function()
		local constructor = read(module_root .. "_cwv_core_templates.lua")
		H.equal(constructor:find("if sub_action.projectile_info == Projectiles.dr_deus_01", 1, true), nil,
			"identity against the deep-copied clone can never match (table.lua:31-49)")
		H.equal(constructor:find("mod:dofile(", 1, true), nil,
			"the core-template owner takes no dofile (decomposition contract)")
		local wire = read(module_root .. "_cwv_outrider_projectile_wire.lua")
		H.truthy(wire:find("M.plan_projectile_swap(template, donor_info)", 1, true))
		H.equal(wire:find("donor_sub.projectile_info == donor_info", 1, true), nil,
			"the registered donor is a deep copy too (dr_deus_01.lua:326): no identity branch")
		H.truthy(wire:find("M.apply_projectile_swap(swap_rows, grenade_info)", 1, true))
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
