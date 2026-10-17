return function(H, repo_root)
	local contract = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
		.. "_cwv_javelin_recovery_contract.lua")
	local lookup_lib = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
		.. "_lib_network_lookup.lua")

    local function fixture()
        local production_queries = 0
		local owner = contract.new({
			inventory_for = function(unit)
                production_queries = production_queries + 1
                if unit == "production-player" then
                    return {
                        has_ammo_consuming_weapon_equipped = function(_, ammo_type)
                            return ammo_type == "throwing_javelin"
						end,
                    }
                end
            end,
			lookup_lib = lookup_lib,
            peer_id = function() return "production-peer" end,
            pickup_system = function()
                return { delete_limited_owned_pickup_unit = function() end }
            end,
        })
        local pickups, all_pickups, lookup = {}, {}, {}
        local ground, linked = owner.register({
            pickups = pickups,
            all_pickups = all_pickups,
            pickup_lookup = lookup,
            pickup_key = "ground",
            link_pickup_key = "linked",
            unit_name = "carrier",
        })
        local args = {
            pickups = pickups,
            all_pickups = all_pickups,
            skins = {
                kruber = {
                    pickup_template_name = "ground",
                    link_pickup_template_name = "linked",
                },
                saltzpyre = {
                    pickup_template_name = "ground",
                    link_pickup_template_name = "linked",
                },
            },
            template = {
                actions = {
                    action_one = {
                        throw = {
                            kind = "thrown_projectile",
                            impact_data = {
                                link_pickup = true,
                                pickup_settings = { use_weapon_skin = true },
                            },
                        },
                    },
                },
            },
            pickup_key = "ground",
            link_pickup_key = "linked",
			unit_name = "carrier",
            skin_keys = { "kruber", "saltzpyre" },
        }
        return owner, args, ground, linked, all_pickups, lookup,
            function() return production_queries end
    end

    H.test("CWV javelin recovery registers both exact interaction outcomes", function()
        local _, _, ground, linked, all_pickups, lookup = fixture()
        for key, settings in pairs({ ground = ground, linked = linked }) do
            H.equal(settings.pickup_name, key)
            H.equal(settings.unit_name, "carrier")
            H.equal(settings.unit_template_name, "limited_owned_pickup_unit")
            H.equal(settings.type, "ammo")
            H.equal(settings.ammo_kind, "thrown")
            H.equal(settings.refill_amount, 1)
            H.equal(all_pickups[key], settings)
            H.truthy(type(settings.can_interact_func) == "function")
            H.truthy(type(settings.outline_available_func) == "function")
            H.truthy(type(settings.on_pick_up_func) == "function")
            H.truthy(type(lookup[key]) == "number")
            H.equal(lookup[lookup[key]], key)
        end
        H.truthy(lookup.ground ~= lookup.linked)
    end)

    H.test("CWV issue296 proof executes registered eligibility, refill shape and cleanup", function()
        local owner, args = fixture()
        local ok, err = owner.exercise(args)
        H.equal(ok, true, tostring(err))
    end)

	H.test("CWV recovery re-registration re-owns callbacks without lookup growth", function()
        local owner, args, ground, linked, _, lookup = fixture()
        local before = #lookup
        local new_ground, new_linked = owner.register({
            pickups = args.pickups,
            all_pickups = args.all_pickups,
            pickup_lookup = lookup,
            pickup_key = "ground",
            link_pickup_key = "linked",
            unit_name = "carrier",
        })
        H.equal(#lookup, before)
        H.truthy(new_ground ~= ground)
        H.truthy(new_linked ~= linked)
        H.equal(args.all_pickups.ground, new_ground)
        H.equal(args.all_pickups.linked, new_linked)
        local ok, err = owner.exercise(args)
        H.equal(ok, true, tostring(err))
	end)

	H.test("CWV recovery registration rejects malformed lookup without publishing pickups", function()
		local owner, args = fixture()
		local pickups = { ground = "old-ground", linked = "old-linked" }
		local all_pickups = { ground = "old-all-ground", linked = "old-all-linked" }
		local lookup = { [1] = "foreign", foreign = 2 }
		local ground, linked, reason = owner.register({
			pickups = pickups,
			all_pickups = all_pickups,
			pickup_lookup = lookup,
			pickup_key = args.pickup_key,
			link_pickup_key = args.link_pickup_key,
			unit_name = args.unit_name,
		})
		H.equal(ground, nil)
		H.equal(linked, nil)
		H.equal(reason, "pair_asymmetric")
		H.equal(pickups.ground, "old-ground")
		H.equal(pickups.linked, "old-linked")
		H.equal(all_pickups.ground, "old-all-ground")
		H.equal(all_pickups.linked, "old-all-linked")
		H.equal(lookup[1], "foreign")
		H.equal(lookup.foreign, 2)
	end)

	H.test("CWV recovery registration rolls back first lookup row when second throws", function()
		local calls = 0
		local owner = contract.new({
			inventory_for = function() end,
			lookup_lib = {
				register = function(lookup, key)
					calls = calls + 1
					local index, inserted, reason = lookup_lib.register(lookup, key)
					if calls == 2 then error("planted second-row failure") end
					return index, inserted, reason
				end,
			},
			peer_id = function() return "peer" end,
			pickup_system = function() return {} end,
		})
		local pickups, all_pickups, lookup = {}, {}, {}
		local ground, linked, reason = owner.register({
			pickups = pickups,
			all_pickups = all_pickups,
			pickup_lookup = lookup,
			pickup_key = "ground",
			link_pickup_key = "linked",
			unit_name = "carrier",
		})
		H.equal(ground, nil)
		H.equal(linked, nil)
		H.truthy(reason:find("lookup_register_threw", 1, true))
		H.equal(next(pickups), nil)
		H.equal(next(all_pickups), nil)
		H.equal(next(lookup), nil)
	end)

	H.test("CWV recovery registration rolls back pickup maps when publication throws", function()
		local writes = 0
		local owner = contract.new({
			inventory_for = function() end,
			lookup_lib = lookup_lib,
			peer_id = function() return "peer" end,
			pickup_system = function() return {} end,
			write = function(target, key, value)
				writes = writes + 1
				rawset(target, key, value)
				if writes == 3 then error("planted pickup publication failure") end
			end,
		})
		local pickups = { ground = "old-ground", linked = "old-linked" }
		local all_pickups = { ground = "old-all-ground", linked = "old-all-linked" }
		local lookup = {}
		local ground, linked, reason = owner.register({
			pickups = pickups,
			all_pickups = all_pickups,
			pickup_lookup = lookup,
			pickup_key = "ground",
			link_pickup_key = "linked",
			unit_name = "carrier",
		})
		H.equal(ground, nil)
		H.equal(linked, nil)
		H.truthy(reason:find("pickup_publish_threw", 1, true))
		H.equal(pickups.ground, "old-ground")
		H.equal(pickups.linked, "old-linked")
		H.equal(all_pickups.ground, "old-all-ground")
		H.equal(all_pickups.linked, "old-all-linked")
		H.equal(next(lookup), nil)
	end)

	H.test("CWV recovery registration rejects a silently ignored pickup-map write", function()
		local writes = 0
		local owner = contract.new({
			inventory_for = function() end,
			lookup_lib = lookup_lib,
			peer_id = function() return "peer" end,
			pickup_system = function() return {} end,
			write = function(target, key, value)
				writes = writes + 1
				-- Model a proxy/replacement writer that reports no error but drops
				-- the linked AllPickups publication.
				if writes ~= 4 then rawset(target, key, value) end
			end,
		})
		local pickups = { ground = "old-ground", linked = "old-linked" }
		local all_pickups = { ground = "old-all-ground", linked = "old-all-linked" }
		local lookup = {}
		local ground, linked, reason = owner.register({
			pickups = pickups,
			all_pickups = all_pickups,
			pickup_lookup = lookup,
			pickup_key = "ground",
			link_pickup_key = "linked",
			unit_name = "carrier",
		})
		H.equal(ground, nil)
		H.equal(linked, nil)
		H.truthy(reason:find("AllPickups rejected linked", 1, true))
		H.equal(pickups.ground, "old-ground")
		H.equal(pickups.linked, "old-linked")
		H.equal(all_pickups.ground, "old-all-ground")
		H.equal(all_pickups.linked, "old-all-linked")
		H.equal(next(lookup), nil)
	end)

    H.test("CWV issue296 proof rejects malformed and foreign recovery axes", function()
        local owner, args, ground = fixture()
        ground.refill_amount = 2
        local ok, err = owner.exercise(args)
        H.equal(ok, nil)
        H.truthy(tostring(err):find("recovery fields malformed", 1, true) ~= nil)

        ground.refill_amount = 1
        -- Vanilla add_ammo_from_pickup fasserts on a row carrying both refill
        -- fields (simple_inventory_extension.lua:1266).
        ground.refill_percentage = 0.5
        ok, err = owner.exercise(args)
        H.equal(ok, nil)
        H.truthy(tostring(err):find("carries refill_percentage beside refill_amount", 1, true) ~= nil)

        ground.refill_percentage = nil
        args.skins.kruber.link_pickup_template_name = "foreign"
        ok, err = owner.exercise(args)
        H.equal(ok, nil)
        H.truthy(tostring(err):find("does not route both impact outcomes", 1, true) ~= nil)

        args.skins.kruber.link_pickup_template_name = "linked"
        args.template.actions.action_one.throw.impact_data.link_pickup = false
        ok, err = owner.exercise(args)
        H.equal(ok, nil)
        H.truthy(tostring(err):find("does not select", 1, true) ~= nil)

		args.template.actions.action_one.throw.impact_data.link_pickup = true
		ground.unit_name = "actorless-carrier"
		ok, err = owner.exercise(args)
		H.equal(ok, nil)
		H.truthy(tostring(err):find("carrier or unit template mismatch", 1, true) ~= nil)
    end)

    H.test("CWV issue296 proof restores private production dependencies after failure", function()
        local owner, args, ground, _, _, _, production_queries = fixture()
        ground.on_pick_up_func = function() error("planted cleanup failure") end
        local ok, err = owner.exercise(args)
        H.equal(ok, nil)
        H.truthy(tostring(err):find("planted cleanup failure", 1, true) ~= nil)
        -- The registered callback closes over the owner's dependency table.  A
        -- successful production-player query here proves the failed proof put
        -- the original dependency back rather than leaving its detached fake.
        H.equal(ground.can_interact_func("production-player"), true)
        H.equal(production_queries(), 1)
    end)

    H.test("CWV issue296 owner re-registers both recovery rows on every install", function()
        -- The pre-fix owner wrapped registration in `if not Pickups.ammo[_TJ_PICKUP_KEY]`
        -- (_cwv_javelin_runtime_owner.lua:262 at 0.1.545-dev), so a VMF reload kept
        -- the previous instance's callbacks. Between the Pickups.ammo presence check
        -- and the shared register call nothing may gate on an existing row.
        local file = assert(io.open(repo_root .. "/character_weapon_variants/scripts/mods/"
            .. "character_weapon_variants/_cwv_javelin_runtime_owner.lua", "rb"))
        local owner = file:read("*a")
        file:close()
        local start = assert(owner:find("if not Pickups or not Pickups.ammo then", 1, true))
        local call = assert(owner:find("_recovery.register({", start, true),
            "the owner no longer registers recovery rows through the shared contract")
        local between = owner:sub(start, call)
        for _, guard in ipairs({ "Pickups.ammo[", "rawget(Pickups.ammo", "AllPickups[" }) do
            H.equal(between:find(guard, 1, true), nil,
                "an existing-row guard skips re-registration on reload: " .. guard)
        end
        H.equal(owner:find("Pickups.ammo[_TJ_PICKUP_KEY]", 1, true), nil,
            "the owner writes recovery rows outside the shared contract")
        H.equal(owner:find("Pickups.ammo[_TJ_LINK_PICKUP_KEY]", 1, true), nil,
            "the owner writes recovery rows outside the shared contract")
    end)

    H.test("CWV issue296 named runtime check consumes the shared owner", function()
        local source = require("cwv_source").combined(repo_root)
        H.truthy(source:find("issue296_tuskgor_javelin_recovery_transaction", 1, true))
        H.truthy(source:find("_om._tj_recovery_transaction_check", 1, true))
        H.truthy(source:find("javelin_recovery_contract = _recovery", 1, true))
    end)
end
