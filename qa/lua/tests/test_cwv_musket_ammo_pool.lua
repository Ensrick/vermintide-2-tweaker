return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_musket_ammo_pool.lua")

	local function extension(owner, slot_name, reserve)
		return {
			unit = {},
			owner_unit = owner,
			slot_name = slot_name,
			_available_ammo = reserve or 10,
			_current_ammo = 1,
			_ammo_per_clip = 1,
			_max_ammo = 11,
		}
	end

	H.test("CWV #932 scopes Old Musket reserve by owner and equipment slot", function()
		local controller = policy.new({ alive = function() return true end })
		local owner_a, owner_b = {}, {}
		local melee_a = extension(owner_a, "slot_melee")
		local ranged_a = extension(owner_a, "slot_ranged")
		local melee_b = extension(owner_b, "slot_melee")
		H.truthy(controller:register(melee_a))
		H.truthy(controller:register(ranged_a))
		H.truthy(controller:register(melee_b))
		H.equal(controller:capacity_for(melee_a), 20)
		H.equal(controller:reserve_for(melee_a), 20)
		H.equal(controller:reserve_for(ranged_a), 20)
		H.equal(controller:capacity_for(melee_b), 10)
		H.equal(controller:reserve_for(melee_b), 10)
	end)

	H.test("CWV #932 shares reserve consumption but preserves separate chambers", function()
		local controller = policy.new({ alive = function() return true end })
		local owner = {}
		local melee = extension(owner, "slot_melee")
		local ranged = extension(owner, "slot_ranged")
		controller:register(melee)
		controller:register(ranged)
		local before = controller:begin_mutation(melee)
		melee._available_ammo = melee._available_ammo - 1
		controller:end_delta(melee, before)
		H.equal(melee._available_ammo, 19)
		H.equal(ranged._available_ammo, 19)
		H.equal(melee._current_ammo, 1)
		H.equal(ranged._current_ammo, 1)
		H.equal(controller:max_ammo_for(melee), 21)
		H.equal(melee._max_ammo, 11, "native max field must remain untouched")
		controller:end_remove(melee, controller:begin_mutation(melee), 5)
		H.equal(controller:reserve_for(melee), 14,
			"removal above the native per-item cap must use the pool total")
		controller:end_add(ranged, controller:begin_mutation(ranged), 3)
		H.equal(controller:reserve_for(ranged), 17,
			"direct reserve additions must use the pool total")
	end)

	H.test("CWV #932 stance replacement cannot grant a fresh reserve", function()
		local controller = policy.new({ alive = function() return true end })
		local owner = {}
		local original = extension(owner, "slot_melee")
		controller:register(original)
		local before = controller:begin_mutation(original)
		original._available_ammo = 3
		controller:end_delta(original, before)
		local replacement = extension(owner, "slot_melee", 10)
		controller:register(replacement)
		H.equal(controller:reserve_for(replacement), 3)
		H.equal(replacement._available_ammo, 3)
		H.equal(controller:reserve_for(original), nil)
	end)

	H.test("CWV #932 unregisters a replaced slot and clamps the shared reserve", function()
		local controller = policy.new({ alive = function() return true end })
		local owner = {}
		local melee = extension(owner, "slot_melee")
		local ranged = extension(owner, "slot_ranged")
		controller:register(melee)
		controller:register(ranged)
		H.truthy(controller:unregister_slot(owner, "slot_ranged"))
		H.equal(controller:capacity_for(melee), 10)
		H.equal(controller:reserve_for(melee), 10)
		H.equal(controller:reserve_for(ranged), nil)
	end)

	H.test("CWV #1108 exposes only the active exact owner-slot extension", function()
		local alive = setmetatable({}, { __mode = "k" })
		local controller = policy.new({ alive = function(unit) return alive[unit] == true end })
		local owner, other_owner = {}, {}
		local melee = extension(owner, "slot_melee")
		alive[melee.unit] = true
		H.truthy(controller:register(melee))
		H.equal(controller:extension_for(owner, "slot_melee"), melee)
		H.equal(controller:extension_for(owner, "slot_ranged"), nil)
		H.equal(controller:extension_for(other_owner, "slot_melee"), nil)

		local replacement = extension(owner, "slot_melee")
		alive[replacement.unit] = true
		H.truthy(controller:register(replacement))
		H.equal(controller:extension_for(owner, "slot_melee"), replacement)
		H.equal(controller:reserve_for(melee), nil, "replaced extension remained active")

		alive[replacement.unit] = false
		H.equal(controller:extension_for(owner, "slot_melee"), nil,
			"dead extension was exposed to the HUD")
		alive[replacement.unit] = true
		H.truthy(controller:unregister_slot(owner, "slot_melee"))
		H.equal(controller:extension_for(owner, "slot_melee"), nil)
	end)

	H.test("CWV #932 applies one ammo pickup transaction to the shared pool", function()
		local controller = policy.new({ alive = function() return true end })
		local owner = {}
		local melee = extension(owner, "slot_melee")
		local ranged = extension(owner, "slot_ranged")
		controller:register(melee)
		controller:register(ranged)
		local before = controller:begin_mutation(melee)
		melee._available_ammo = 0
		controller:end_delta(melee, before)
		controller:begin_pickup(owner, { refill_percentage = 0.5 })
		controller:end_add(melee, controller:begin_mutation(melee), 10.5)
		controller:end_add(ranged, controller:begin_mutation(ranged), 10.5)
		controller:end_pickup(owner)
		H.equal(controller:reserve_for(melee), 10)
		H.equal(controller:reserve_for(ranged), 10)
	end)

	H.test("CWV #932 production owns every reserve mutation seam", function()
		local path = repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_musket_ammo_pool.lua"
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a")
		file:close()
		for _, method_name in ipairs({
			"update", "add_ammo", "remove_ammo", "add_ammo_to_reserve",
			"instant_reload", "refresh_buffs", "reset", "max_ammo",
		}) do
			H.truthy(source:find('"' .. method_name .. '"', 1, true), method_name)
		end
		H.truthy(source:find('"SimpleInventoryExtension", "add_ammo_from_pickup"', 1, true))
		H.equal(source:find("._max_ammo =", 1, true), nil,
			"the pool must not widen an engine max-ammo field")
	end)

	H.test("CWV #932 no dangling _cwv_musket_sync_pool call survives", function()
		-- The nil-guarded _om._cwv_musket_sync_pool call was silently dead:
		-- the helper was never defined anywhere after the v0.1.307-era
		-- refactor. Reserve sync is owned by the #932 pool controller above;
		-- lock the dangling name out of the shipped runtime source.
		local combined = require("cwv_source").combined(repo_root)
		H.equal(combined:find("_cwv_musket_sync_pool", 1, true), nil,
			"dangling _cwv_musket_sync_pool reference reintroduced")
	end)
end
