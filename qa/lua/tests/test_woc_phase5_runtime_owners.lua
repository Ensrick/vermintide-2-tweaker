-- Phase-5 structural boundary tests for WOC runtime owners (#1159).

return function(H, repo_root)
	local root = repo_root .. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/"

	local function read(path)
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a")
		file:close()
		return source
	end

	local function count(source, needle)
		local found, cursor = 0, 1
		while true do
			local at = source:find(needle, cursor, true)
			if not at then return found end
			found = found + 1
			cursor = at + #needle
		end
	end

	local function nonblank(source)
		local lines = 0
		for line in (source .. "\n"):gmatch("(.-)\n") do
			if line:match("%S") then lines = lines + 1 end
		end
		return lines
	end

	H.test("WOC entry installs each phase-5 owner once and remains below target", function()
		local entry = read(root .. "weapons_of_chaos.lua")
		H.equal(count(entry, '"scripts/mods/weapons_of_chaos/_woc_relic_registration_owner").install(mod, {'), 1)
		H.equal(count(entry, '"scripts/mods/weapons_of_chaos/_woc_spirit_runtime_owner").new({'), 1)
		H.equal(count(entry, 'mod:hook("DeusWeaponGeneration"'), 0)
		H.equal(count(entry, 'local _spirit_state = {'), 0)
		H.equal(count(entry, 'local function _install_blightreaper_moveset()'), 0)
		H.truthy(nonblank(entry) <= 1500, "WOC entry crossed the 1,500-line completion target")
	end)

	H.test("relic registration owner owns hooks and exposes bounded state", function()
		local hooks, safe, checks = {}, {}, {}
		local mod = {}
		function mod:hook(_, method, fn) hooks[method] = fn end
		function mod:hook_safe(_, method, fn) safe[method] = fn end
		function mod:command() end
		function mod:get() return nil end
		function mod:echo() end
		function mod:info() end
		function mod:localize(key) return key end
		local dependency = {}
		local owner = assert(loadfile(root .. "_woc_relic_registration_owner.lua"))()
			.install(mod, {
				item_key = "woc_blightreaper", backend_id = "woc_blightreaper_001",
				base_weapon = "es_1h_sword", held_unit = "unit", inventory_icon = "icon",
				template = "woc_template", careers = { "es_mercenary" },
				display_names = {}, moveset = dependency, power = dependency,
				cursed = dependency, attack_order = dependency,
				chain_descriptor = {}, relic_policy = dependency,
				inventory_icons = dependency, network_lookup = dependency,
				career_weapon_actions = dependency, career_action_owner = "woc",
				rt_register = function(name) checks[name] = true end,
				dbg = function() end, ensure_appearance_aliases = function() end,
				reset_appearance_diag = function() end, start_spirits = function() end,
				stop_spirits = function() end, mark_poison = function() end,
				owner_has_wielded_trait = function() return false end,
			})
		H.equal(type(hooks.get_item_from_id), "function")
		H.equal(type(hooks.generate_item_from_item_key), "function")
		H.equal(type(hooks._play_3p_anim), "function")
		H.equal(type(safe.on_enter), "function")
		H.equal(type(safe.on_exit), "function")
		H.equal(type(owner.backend_items), "function")
		H.equal(type(owner.install_poison), "function")
		H.equal(owner:registration_state().registered, false)
		H.truthy(checks.issue637_unique_immutable_relic_inventory)
		H.truthy(checks.blightreaper_all_career_ability_actions)
	end)

	H.test("spirit owner owns native buff observation and bounded lifecycle", function()
		local safe, checks = {}, {}
		local mod = {}
		function mod:hook_safe(_, method, fn) safe[method] = fn end
		local owner = assert(loadfile(root .. "_woc_spirit_runtime_owner.lua"))()
			.new({
				mod = mod, spirits = {}, power = {}, moveset = {},
				remote_identity = {}, backend_items = function() return nil end,
				ensure_package = function() return false end,
				rt_register = function(name) checks[name] = true end,
			})
		H.equal(type(safe.rpc_add_buff_synced_params), "function")
		H.equal(type(mod._woc_on_blightreaper_kill), "function")
		H.equal(type(owner.start), "function")
		H.equal(type(owner.stop), "function")
		H.equal(type(owner.update), "function")
		H.equal(owner:owner_has_wielded_trait(nil, "trait"), false)
		owner:update(0)
		owner:stop("offline-test")
		H.truthy(checks.issue632_blightreaper_shyish_spirit_contract)
	end)

	H.test("phase-5 owner files remain below the per-file target", function()
		H.truthy(nonblank(read(root .. "_woc_relic_registration_owner.lua")) < 1500)
		H.truthy(nonblank(read(root .. "_woc_spirit_runtime_owner.lua")) < 1500)
	end)
end
