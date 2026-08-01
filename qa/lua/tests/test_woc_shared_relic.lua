return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_shared_relic.lua")
	local main_file = assert(io.open(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua", "rb"))
	local main_source = main_file:read("*a")
	main_file:close()
	local runtime_file = assert(io.open(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_shared_relic_runtime.lua",
		"rb"))
	local runtime_source = runtime_file:read("*a")
	runtime_file:close()
	local contract_source = main_source .. "\n" .. runtime_source
	local runtime_module = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_shared_relic_runtime.lua")

	local function with_runtime(options, body)
		local saved = {}
		for _, name in ipairs({
			"BackendUtils", "HeroViewStateOverview", "KeepDecorationTrophyExtension",
			"Managers", "Network", "ScriptUnit", "SimpleInventoryExtension",
			"SPProfiles", "Unit", "printf",
		}) do
			saved[name] = rawget(_G, name)
		end

		local callbacks, hooks, sends = {}, {}, {}
		local remote_identity = {}
		local backend = {
			slot_melee = options.persisted_melee,
			slot_ranged = options.persisted_ranged,
		}
		local set_calls = 0
		local inventory = {
			_equipment = { slots = {} },
			player = nil,
		}
		local function set_live(slot_name, backend_id)
			inventory._equipment.slots[slot_name] = backend_id and {
				item_data = { backend_id = backend_id },
			} or nil
		end
		set_live("slot_melee", options.live_melee)
		set_live("slot_ranged", options.live_ranged)
		function inventory:destroy_slot(slot_name)
			set_live(slot_name, nil)
			return true
		end
		function inventory:create_equipment_in_slot(slot_name, backend_id)
			set_live(slot_name, backend_id)
			return true
		end

		local local_player = {
			peer_id = options.local_peer or "peer-local",
			_local_player_id = 1,
			player_unit = "local-unit",
		}
		inventory.player = local_player
		function local_player:local_player_id() return self._local_player_id end
		function local_player:career_name() return "es_mercenary" end
		local remote_players = {}
		local network_state = { is_server = options.is_server ~= false }
		local env = {
			callbacks = callbacks,
			hooks = hooks,
			sends = sends,
			remote_identity = remote_identity,
			backend = backend,
			inventory = inventory,
			inventory_ready = options.inventory_ready ~= false,
			local_player = local_player,
			remote_players = remote_players,
			host_peer = options.host_peer or local_player.peer_id,
			network_state = network_state,
			set_failures_remaining = options.set_failures or 0,
			set_live = set_live,
		}
		function env:set_calls() return set_calls end

		_G.printf = function() end
		_G.Network = {
			peer_id = function() return local_player.peer_id end,
		}
		_G.Unit = { alive = function(unit) return unit ~= nil end }
		_G.ScriptUnit = {
			has_extension = function(unit, extension)
				if extension == "inventory_system" and unit == "local-unit"
						and env.inventory_ready then
					return inventory
				end
				local player = remote_players[unit]
				return player and player.inventory or nil
			end,
		}
		_G.Managers = {
			mechanism = {
				server_peer_id = function() return env.host_peer end,
			},
			player = {
				local_player = function() return local_player end,
				player_from_peer_id = function(_, peer_id)
					if peer_id == local_player.peer_id then return local_player end
					return remote_players[peer_id]
				end,
			},
			state = {
				network = network_state,
			},
		}
		_G.BackendUtils = {
			get_loadout_item_id = function(_, slot_name)
				return backend[slot_name]
			end,
			set_loadout_item = function(backend_id, _, slot_name)
				set_calls = set_calls + 1
				if env.set_failures_remaining > 0 then
					env.set_failures_remaining = env.set_failures_remaining - 1
					return false
				end
				backend[slot_name] = backend_id
				return true
			end,
		}
		_G.HeroViewStateOverview = {
			_set_loadout_item = function() return true end,
		}
		_G.SimpleInventoryExtension = {
			create_equipment_in_slot = function() return true end,
		}
		_G.KeepDecorationTrophyExtension = {
			_load_trophy = function() return true end,
		}

		local mod = {}
		function mod:network_register(channel, callback)
			callbacks[channel] = callback
		end
		function mod:network_send(channel, recipient, ...)
			sends[#sends + 1] = {
				channel = channel,
				recipient = recipient,
				args = { ... },
			}
		end
		function mod:hook(target, method, callback)
			local owner = type(target) == "string" and target
				or target == _G.BackendUtils and "BackendUtils"
				or "table"
			hooks[owner .. "." .. method] = callback
		end
		function mod:command() end

		local runtime = runtime_module.new({
			mod = mod,
			policy = policy,
			backend_id = policy.BACKEND_ID,
			item_key = policy.ITEM_KEY,
			remote_identity = remote_identity,
			rt_register = function() end,
			test_api = true,
		})
		env.runtime = runtime

		local ok, failure = xpcall(function() body(env) end, debug.traceback)
		for name, value in pairs(saved) do _G[name] = value end
		for _, name in ipairs({
			"BackendUtils", "HeroViewStateOverview", "KeepDecorationTrophyExtension",
			"Managers", "Network", "ScriptUnit", "SimpleInventoryExtension",
			"SPProfiles", "Unit", "printf",
		}) do
			if saved[name] == nil then _G[name] = nil end
		end
		if not ok then error(failure, 0) end
	end

	H.test("WOC #934 first lobby claimant owns the unique relic", function()
		local state = policy.new_state()
		local changed, verdict = policy.apply_identity(
			state, "peer-a", "slot_melee", true)
		H.truthy(changed)
		H.equal(verdict, "granted")
		H.equal(state.holder, "peer-a")
		H.equal(state.generation, 1)
	end)

	H.test("WOC #934 rival claim is denied and never queued", function()
		local state = policy.new_state()
		policy.apply_identity(state, "peer-a", "slot_melee", true)
		local changed, verdict = policy.apply_identity(
			state, "peer-b", "slot_melee", true)
		H.equal(changed, false)
		H.equal(verdict, "denied")
		H.equal(state.holder, "peer-a")
		H.equal(state.claims["peer-b"], nil)
		H.equal(state.generation, 1)
	end)

	H.test("WOC #934 final equipped slot releases the lease", function()
		local state = policy.new_state()
		policy.apply_identity(state, "peer-a", "slot_melee", true)
		policy.apply_identity(state, "peer-a", "slot_ranged", true)
		local changed_one, verdict_one = policy.apply_identity(
			state, "peer-a", "slot_melee", false)
		H.truthy(changed_one)
		H.equal(verdict_one, "slot-released")
		H.equal(state.holder, "peer-a")
		H.equal(state.generation, 3)
		local changed_two, verdict_two = policy.apply_identity(
			state, "peer-a", "slot_ranged", false)
		H.truthy(changed_two)
		H.equal(verdict_two, "released")
		H.equal(state.holder, nil)
		H.equal(state.generation, 4)
	end)

	H.test("WOC #934 disconnect releases only the current holder", function()
		local state = policy.new_state()
		policy.apply_identity(state, "peer-a", "slot_melee", true)
		local absent = policy.forget_peer(state, "peer-b")
		H.equal(absent, false)
		H.equal(state.holder, "peer-a")
		local changed, verdict = policy.forget_peer(state, "peer-a")
		H.truthy(changed)
		H.equal(verdict, "disconnected")
		H.equal(state.holder, nil)
		H.equal(state.generation, 2)
	end)

	H.test("WOC #934 equip and rollback policy is peer exact", function()
		H.truthy(policy.can_equip(nil, "peer-a"))
		H.truthy(policy.can_equip("peer-a", "peer-a"))
		H.equal(policy.can_equip("peer-a", "peer-b"), false)
		H.truthy(policy.can_equip_backend(
			"peer-a", "peer-b", "ordinary-item", "slot_melee"))
		H.truthy(policy.can_equip_backend(
			"peer-a", "peer-b", policy.BACKEND_ID, "slot_hat"))
		H.equal(policy.can_equip_backend(
			"peer-a", "peer-b", policy.BACKEND_ID, "slot_melee"), false)
		H.truthy(policy.should_rollback("peer-a", "peer-b", true))
		H.equal(policy.should_rollback("peer-a", "peer-b", false), false)
		H.equal(policy.should_rollback("peer-a", "peer-a", true), false)
	end)

	H.test("WOC #934 trophy substitution is exact and transient", function()
		H.equal(policy.trophy_for("hub_trophy_bogenhafen", "peer-a"),
			"hub_trophy_empty")
		H.equal(policy.trophy_for("hub_trophy_bogenhafen", nil),
			"hub_trophy_bogenhafen")
		H.equal(policy.trophy_for("hub_trophy_drachenfels", "peer-a"),
			"hub_trophy_drachenfels")
	end)

	H.test("WOC #934 authority snapshots reject stale and conflicting replays", function()
		local ok, verdict, generation, holder = policy.accept_snapshot(
			2, "peer-a", 3, "peer-b")
		H.truthy(ok)
		H.equal(verdict, "advanced")
		H.equal(generation, 3)
		H.equal(holder, "peer-b")
		local stale, stale_reason = policy.accept_snapshot(3, "peer-b", 2, "peer-a")
		H.equal(stale, false)
		H.equal(stale_reason, "stale")
		local conflict, conflict_reason = policy.accept_snapshot(
			3, "peer-b", 3, "peer-a")
		H.equal(conflict, false)
		H.equal(conflict_reason, "conflict")
		local replay, replay_reason = policy.accept_snapshot(
			3, "peer-b", 3, "peer-b")
		H.truthy(replay)
		H.equal(replay_reason, "replay")
	end)

	H.test("WOC #934 host promotion rebuilds the authenticated holder epoch", function()
		local local_state, local_status = policy.rebuild_authority(
			"peer-a", "peer-a", { slot_melee = true }, {})
		H.equal(local_status, "confirmed")
		H.equal(local_state.holder, "peer-a")
		H.truthy(local_state.claims["peer-a"].slot_melee)

		local remote_state, remote_status = policy.rebuild_authority(
			"peer-b", "peer-a", {}, {
				["peer-b"] = { slot_ranged = true },
			})
		H.equal(remote_status, "confirmed")
		H.equal(remote_state.holder, "peer-b")
		H.truthy(remote_state.claims["peer-b"].slot_ranged)

		local reserved, reserved_status = policy.rebuild_authority(
			"peer-c", "peer-a", {}, {})
		H.equal(reserved_status, "reserved")
		H.equal(reserved.holder, "peer-c")
		H.truthy(policy.is_migration_reserved(reserved))
		local retained, retained_reason = policy.apply_identity(
			reserved, "peer-c", "slot_melee", true)
		H.truthy(retained)
		H.equal(retained_reason, "retained")
		H.equal(policy.is_migration_reserved(reserved), false)

		local expiring = policy.rebuild_authority("peer-c", "peer-a", {}, {})
		local expired, expired_reason = policy.expire_migration_reservation(expiring)
		H.truthy(expired)
		H.equal(expired_reason, "reservation-expired")
		H.equal(expiring.holder, nil)
		H.equal(expiring.generation, 2)
	end)

	H.test("WOC #934 rollback requires exact backend readback", function()
		H.truthy(policy.rollback_verified(true, "prior-123", "prior-123"))
		H.equal(policy.rollback_verified(true, "prior-123", "other-456"), false)
		H.equal(policy.rollback_verified(true, "prior-123", nil), false)
		H.equal(policy.rollback_verified(false, "prior-123", "prior-123"), false)
	end)

	H.test("WOC #934 pre-equipped loser never guesses a fallback", function()
		local exact, exact_reason = policy.rollback_target("prior-123")
		H.equal(exact, "prior-123")
		H.equal(exact_reason, "exact-prior")
		local missing, missing_reason = policy.rollback_target(nil)
		H.equal(missing, nil)
		H.equal(missing_reason, "deferred-no-prior")
		local relic, relic_reason = policy.rollback_target(policy.BACKEND_ID)
		H.equal(relic, nil)
		H.equal(relic_reason, "deferred-no-prior")
		H.equal(policy.ROLLBACK_RETRY_BASE_SECONDS, 0.5)
		H.equal(policy.ROLLBACK_RETRY_MAX_SECONDS, 8)
		H.equal(policy.ROLLBACK_FAIL_CLOSED_AFTER, 4)
		H.equal(policy.rollback_retry_delay(1), 0.5)
		H.equal(policy.rollback_retry_delay(2), 1)
		H.equal(policy.rollback_retry_delay(5), 8)
		H.equal(policy.rollback_retry_delay(30), 8)
		H.equal(policy.rollback_is_terminal_fail_closed(3), false)
		H.truthy(policy.rollback_is_terminal_fail_closed(4))
		H.equal(policy.MIGRATION_RESERVATION_SECONDS, 4)
	end)

	H.test("WOC #934 retail local-player method publishes the host claim", function()
		with_runtime({ is_server = true }, function(env)
			H.equal(type(env.local_player.local_player_id), "function",
				"the harness must model VT2's local_player_id() method")
			H.equal(env.local_player._local_player_id, 1)
			env.runtime:on_game_state_changed("enter", "StateIngame")
			env.runtime:update(0)
			local is_local = env.runtime:observe_loadout_sync(
				env.local_player, "slot_melee", true)
			H.truthy(is_local)
			local snapshot = env.runtime:test_snapshot()
			H.truthy(snapshot.local_melee)
			H.equal(snapshot.holder, env.local_player.peer_id)
			H.truthy(env.remote_identity[env.local_player.peer_id].slot_melee)
			local state_send
			for i = #env.sends, 1, -1 do
				if env.sends[i].channel == "woc_relic_lease_state_v1" then
					state_send = env.sends[i]
					break
				end
			end
			H.truthy(state_send)
			H.equal(#state_send.args, 7,
				"the authority snapshot payload must remain fixed and bounded")
			H.equal(state_send.args[6], 1)
			H.equal(state_send.args[7], 0)
		end)
	end)

	H.test("WOC #934 remote and bot replay cannot author identity", function()
		with_runtime({ is_server = true }, function(env)
			env.runtime:on_game_state_changed("enter", "StateIngame")
			env.runtime:update(0)
			local sends_before = #env.sends
			local remote = {
				peer_id = "peer-remote",
				_local_player_id = 1,
				local_player_id = function(self) return self._local_player_id end,
			}
			local bot = {
				peer_id = env.local_player.peer_id,
				_local_player_id = 1,
				bot_player = true,
				local_player_id = function(self) return self._local_player_id end,
			}
			H.equal(env.runtime:observe_loadout_sync(
				remote, "slot_melee", true), false)
			H.equal(env.runtime:observe_loadout_sync(
				bot, "slot_melee", true), false)
			H.equal(env.runtime:test_snapshot().holder, nil)
			H.equal(next(env.remote_identity), nil)
			H.equal(#env.sends, sends_before)
		end)
	end)

	H.test("WOC #934 delayed local seed immediately enforces host denial", function()
		with_runtime({
			is_server = true,
			inventory_ready = false,
		}, function(env)
			env.runtime:on_game_state_changed("enter", "StateIngame")
			env.runtime:update(0)
			env.callbacks.woc_relic_lease_intent_v1(
				"peer-holder", policy.SCHEMA, env.local_player.peer_id, 1,
				"slot_melee", 1)
			env.remote_players["peer-holder"] = {
				peer_id = "peer-holder",
				player_unit = "remote-holder-unit",
			}
			H.equal(env.runtime:test_snapshot().holder, "peer-holder")

			env.backend.slot_melee = policy.BACKEND_ID
			env:set_live("slot_melee", policy.BACKEND_ID)
			env.inventory_ready = true
			env.runtime:update(0)

			H.equal(env.backend.slot_melee, nil,
				"delayed seed must clear the denied durable relic immediately")
			H.equal(env.inventory._equipment.slots.slot_melee, nil,
				"delayed seed must remove the denied live relic immediately")
			H.equal(env:set_calls(), 1)
			H.equal(env.runtime:test_snapshot().local_melee, false)
		end)
	end)

	H.test("WOC #934 rollback survives more than four backend failures", function()
		with_runtime({
			is_server = true,
			set_failures = 5,
		}, function(env)
			env.runtime:on_game_state_changed("enter", "StateIngame")
			env.runtime:update(0)
			env.callbacks.woc_relic_lease_intent_v1(
				"peer-holder", policy.SCHEMA, env.local_player.peer_id, 1,
				"slot_melee", 1)
			env.remote_players["peer-holder"] = {
				peer_id = "peer-holder",
				player_unit = "remote-holder-unit",
			}

			env.backend.slot_melee = policy.BACKEND_ID
			env:set_live("slot_melee", policy.BACKEND_ID)
			env.runtime:observe_loadout_sync(
				env.local_player, "slot_melee", true)
			H.equal(env:set_calls(), 1)
			H.equal(env.inventory._equipment.slots.slot_melee, nil,
				"the first failed durable write must still fail closed live")

			for _ = 1, 4 do env.runtime:update(8) end
			local terminal = env.runtime:test_snapshot().retries.slot_melee
			H.equal(terminal.attempts, 5)
			H.truthy(terminal.fail_closed)
			H.equal(terminal.delay, 8)
			H.equal(env.backend.slot_melee, policy.BACKEND_ID,
				"failed durable writes must remain pending, never declared released")
			H.equal(env.inventory._equipment.slots.slot_melee, nil,
				"terminal fail-closed must not strand the rival live")
			env.runtime:update(8)
			H.equal(env:set_calls(), 6,
				"rollback must keep retrying beyond the old four-attempt cap")
			H.equal(env.backend.slot_melee, nil)
			H.equal(env.inventory._equipment.slots.slot_melee, nil)
			H.equal(env.runtime:test_snapshot().retries.slot_melee, nil,
				"retry state must retire only after durable/live convergence")
		end)
	end)

	H.test("WOC #934 reset rejects delayed packets from the old authority epoch", function()
		with_runtime({ is_server = true }, function(env)
			env.runtime:on_game_state_changed("enter", "StateIngame")
			env.runtime:update(0)
			env.callbacks.woc_relic_lease_intent_v1(
				"peer-old", policy.SCHEMA, env.local_player.peer_id, 1,
				"slot_melee", 1)
			H.equal(env.runtime:test_snapshot().holder, "peer-old")
			H.truthy(env.remote_identity["peer-old"].slot_melee)

			env.runtime:reset("mod-disabled")
			H.equal(env.runtime:test_snapshot().active, false)
			local sends_after_exit = #env.sends
			env.callbacks.woc_relic_lease_intent_v1(
				"peer-delayed", policy.SCHEMA, env.local_player.peer_id, 1,
				"slot_melee", 1)
			env.callbacks.woc_relic_lease_state_v1(
				env.host_peer, policy.SCHEMA, 1, 9, "peer-delayed", 1, 1, 0)
			env.callbacks.woc_relic_lease_state_v1(
				env.host_peer, policy.SCHEMA, 2, 9, "peer-delayed", 1, 1, 0)
			env.callbacks.woc_relic_lease_query_v1(
				"peer-delayed", policy.SCHEMA, env.local_player.peer_id, 1, 1)
			H.equal(#env.sends, sends_after_exit,
				"inactive callbacks must have no response or mutation")
			H.equal(next(env.remote_identity), nil)

			env.runtime:on_game_state_changed("enter", "StateIngame")
			env.runtime:update(0)
			H.equal(env.runtime:test_snapshot().authority_epoch, 2)
			local sends_before_old_query = #env.sends
			env.callbacks.woc_relic_lease_intent_v1(
				"peer-delayed", policy.SCHEMA, env.local_player.peer_id, 1,
				"slot_melee", 1)
			env.callbacks.woc_relic_lease_state_v1(
				env.host_peer, policy.SCHEMA, 1, 9, "peer-delayed", 1, 1, 0)
			env.callbacks.woc_relic_lease_state_v1(
				env.host_peer, policy.SCHEMA, 2, 9, "peer-delayed", 1, 1, 0)
			env.callbacks.woc_relic_lease_query_v1(
				"peer-delayed", policy.SCHEMA, env.local_player.peer_id, 1, 1)
			H.equal(#env.sends, sends_before_old_query,
				"old-session query must not receive a new-session snapshot")
			H.equal(env.runtime:test_snapshot().holder, nil)
			H.equal(next(env.remote_identity), nil)

			env.callbacks.woc_relic_lease_intent_v1(
				"peer-new", policy.SCHEMA, env.local_player.peer_id, 2,
				"slot_melee", 1)
			H.equal(env.runtime:test_snapshot().holder, "peer-new",
				"the current authority epoch must remain functional")
		end)
	end)

	H.test("WOC #934 disable then re-enable opens a fresh guarded session", function()
		with_runtime({ is_server = true }, function(env)
			env.runtime:on_game_state_changed("enter", "StateIngame")
			env.runtime:update(0)
			H.equal(env.runtime:test_snapshot().authority_epoch, 1)

			env.runtime:reset("mod-disabled")
			H.equal(env.runtime:test_snapshot().active, false)
			H.truthy(env.runtime:on_enabled("mod-enabled"))
			env.runtime:update(0)
			local snapshot = env.runtime:test_snapshot()
			H.truthy(snapshot.active)
			H.equal(snapshot.authority_epoch, 2)

			env.callbacks.woc_relic_lease_intent_v1(
				"peer-old", policy.SCHEMA, env.local_player.peer_id, 1,
				"slot_melee", 1)
			H.equal(env.runtime:test_snapshot().holder, nil,
				"the retired session must stay closed after re-enable")
			env.callbacks.woc_relic_lease_intent_v1(
				"peer-current", policy.SCHEMA, env.local_player.peer_id, 2,
				"slot_melee", 1)
			H.equal(env.runtime:test_snapshot().holder, "peer-current")
		end)
	end)

	H.test("WOC #934 host packet outruns update without reusing old authority", function()
		with_runtime({
			is_server = false,
			host_peer = "peer-host-old",
		}, function(env)
			env.runtime:on_game_state_changed("enter", "StateIngame")
			env.runtime:update(0)
			env.callbacks.woc_relic_lease_state_v1(
				"peer-host-old", policy.SCHEMA, 1, 1, "peer-holder-old", 0, 1, 0)
			H.equal(env.runtime:test_snapshot().holder, "peer-holder-old")
			H.truthy(env.remote_identity["peer-holder-old"].slot_melee)

			-- The network manager can expose the promoted host before the next
			-- mod.update. Its first snapshot must establish a separate
			-- authority even when both hosts happen to use epoch 1.
			env.host_peer = "peer-host-new"
			env.callbacks.woc_relic_lease_state_v1(
				"peer-host-new", policy.SCHEMA, 1, 1, "peer-holder-new", 0, 0, 1)
			H.equal(env.runtime:test_snapshot().holder, "peer-holder-new")
			H.equal(env.runtime:test_snapshot().view_epoch, 1)
			H.equal(env.remote_identity["peer-holder-old"].slot_melee, false,
				"new authority must clear the retired holder atomically")
			H.truthy(env.remote_identity["peer-holder-new"].slot_ranged,
				"new authority must publish the exact holder slot atomically")

			env.callbacks.woc_relic_lease_state_v1(
				"peer-host-old", policy.SCHEMA, 2, 9, "peer-rival", 0, 1, 0)
			H.equal(env.remote_identity["peer-rival"], nil,
				"a retired host cannot author a rival render identity")
		end)
	end)

	H.test("WOC #934 promoted-host reservation reasserts the holder slot", function()
		with_runtime({
			is_server = false,
			host_peer = "peer-host-new",
			persisted_melee = policy.BACKEND_ID,
			live_melee = policy.BACKEND_ID,
		}, function(env)
			env.runtime:on_game_state_changed("enter", "StateIngame")
			env.runtime:update(0)

			-- A promoted host reserves the authenticated prior holder before it
			-- has that holder's exact slot snapshot. The reservation's false
			-- slot bits must not make the client consider its claim complete.
			env.callbacks.woc_relic_lease_state_v1(
				"peer-host-new", policy.SCHEMA, 1, 1,
				env.local_player.peer_id, 0, 0, 0)
			while #env.sends > 0 do table.remove(env.sends) end

			env.runtime:update(1)
			H.equal(#env.sends, 3,
				"one retry must emit exactly two slot intents and one query")
			local melee_intent = env.sends[1]
			local ranged_intent = env.sends[2]
			local query = env.sends[3]
			H.equal(melee_intent.channel, "woc_relic_lease_intent_v1",
				"the reserved holder must reassert its equipped slot first")
			H.equal(melee_intent.args[4], "slot_melee")
			H.equal(melee_intent.args[5], 1)
			H.equal(ranged_intent.channel, "woc_relic_lease_intent_v1",
				"migration reassertion must carry a complete two-slot snapshot")
			H.equal(ranged_intent.args[4], "slot_ranged")
			H.equal(ranged_intent.args[5], 0)
			H.equal(query.channel, "woc_relic_lease_query_v1",
				"the complete slot reassertion must precede another snapshot query")

			-- Once the host acknowledges the complete slot snapshot, the client
			-- must not keep reasserting or polling on later update ticks.
			env.callbacks.woc_relic_lease_state_v1(
				"peer-host-new", policy.SCHEMA, 1, 2,
				env.local_player.peer_id, 0, 1, 0)
			while #env.sends > 0 do table.remove(env.sends) end
			env.runtime:update(8)
			H.equal(#env.sends, 0,
				"an acknowledged reservation must retire migration traffic")
		end)
	end)

	H.test("WOC #934 duplicate and rival intents do not amplify host traffic", function()
		with_runtime({ is_server = true }, function(env)
			env.runtime:on_game_state_changed("enter", "StateIngame")
			env.runtime:update(0)
			while #env.sends > 0 do table.remove(env.sends) end

			env.callbacks.woc_relic_lease_intent_v1(
				"peer-holder", policy.SCHEMA, env.local_player.peer_id, 1,
				"slot_melee", 1)
			H.equal(#env.sends, 1)
			H.equal(env.sends[1].channel, "woc_relic_lease_state_v1")
			H.equal(env.runtime:test_snapshot().holder, "peer-holder")

			env.callbacks.woc_relic_lease_intent_v1(
				"peer-holder", policy.SCHEMA, env.local_player.peer_id, 1,
				"slot_melee", 1)
			H.equal(#env.sends, 1,
				"a duplicate holder claim must not publish another snapshot")

			env.callbacks.woc_relic_lease_intent_v1(
				"peer-rival", policy.SCHEMA, env.local_player.peer_id, 1,
				"slot_melee", 1)
			H.equal(#env.sends, 2,
				"a rival receives one unchanged denial snapshot")
			H.equal(env.runtime:test_snapshot().holder, "peer-holder",
				"a denied rival must not replace or queue behind the holder")

			env.callbacks.woc_relic_lease_intent_v1(
				"peer-rival", policy.SCHEMA, env.local_player.peer_id, 1,
				"slot_ranged", 0)
			H.equal(#env.sends, 2,
				"a rival's inactive companion slot must remain traffic-free")
		end)
	end)

	H.test("WOC #934 slot identity is monotonic with the host snapshot", function()
		with_runtime({
			is_server = false,
			host_peer = "peer-host",
		}, function(env)
			env.runtime:on_game_state_changed("enter", "StateIngame")
			env.runtime:update(0)
			env.callbacks.woc_relic_lease_state_v1(
				"peer-host", policy.SCHEMA, 1, 1, "peer-holder", 0, 1, 0)
			H.truthy(env.remote_identity["peer-holder"].slot_melee)

			env.callbacks.woc_relic_lease_state_v1(
				"peer-host", policy.SCHEMA, 1, 2, "peer-holder", 0, 0, 1)
			H.equal(env.remote_identity["peer-holder"].slot_melee, false)
			H.truthy(env.remote_identity["peer-holder"].slot_ranged)

			env.callbacks.woc_relic_lease_state_v1(
				"peer-host", policy.SCHEMA, 1, 1, "peer-holder", 0, 1, 0)
			H.equal(env.remote_identity["peer-holder"].slot_melee, false,
				"a delayed prior-generation slot snapshot must be rejected")
			H.truthy(env.remote_identity["peer-holder"].slot_ranged)

			env.callbacks.woc_relic_lease_state_v1(
				"peer-host", policy.SCHEMA, 1, 3, "", 0, 1, 0)
			H.equal(env.runtime:test_snapshot().generation, 2,
				"an empty holder cannot carry an active slot bit")
		end)
	end)

	H.test("WOC #934 losing equip resolves exact prior or durable clear", function()
		local resolution, target = policy.loser_resolution(
			"prior-123", policy.BACKEND_ID)
		H.equal(resolution, "restore-exact")
		H.equal(target, "prior-123")

		resolution, target = policy.loser_resolution(
			nil, policy.BACKEND_ID)
		H.equal(resolution, "clear-persisted")
		H.equal(target, nil)

		resolution, target = policy.loser_resolution(
			nil, "manual-456")
		H.equal(resolution, "align-persisted")
		H.equal(target, "manual-456")

		resolution, target = policy.loser_resolution(
			nil, nil)
		H.equal(resolution, "clear-persisted")
		H.equal(target, nil)
	end)

	H.test("WOC #934 release requires persisted and exact live convergence", function()
		H.truthy(policy.rollback_converged(
			"restore-exact", "prior-123", "prior-123", "prior-123", true, true))
		H.equal(policy.rollback_converged(
			"restore-exact", "prior-123", "prior-123",
			policy.BACKEND_ID, true, true), false)
		H.equal(policy.rollback_converged(
			"restore-exact", "prior-123", "prior-123",
			"stale-sync-456", true, true), false)
		H.equal(policy.rollback_converged(
			"restore-exact", "prior-123", "other-456",
			"prior-123", true, true), false)
		H.equal(policy.rollback_converged(
			"restore-exact", policy.BACKEND_ID,
			policy.BACKEND_ID, policy.BACKEND_ID, true, true), false)
		H.equal(policy.rollback_converged(
			"restore-exact", "prior-123", "prior-123",
			"prior-123", false, true), false)
		H.equal(policy.rollback_converged(
			"restore-exact", "prior-123", "prior-123",
			"prior-123", true, false), false)

		H.truthy(policy.rollback_converged(
			"align-persisted", "manual-456", "manual-456",
			"manual-456", true, true))
		H.equal(policy.rollback_converged(
			"align-persisted", "manual-456", "manual-456",
			policy.BACKEND_ID, true, true), false)

		H.truthy(policy.clear_verified(true, nil, "readback"))
		H.equal(policy.clear_verified(true, policy.BACKEND_ID, "readback"), false)
		H.equal(policy.clear_verified(false, nil, "readback"), false)
		H.equal(policy.clear_verified(true, nil, "readback-error"), false)
		H.truthy(policy.rollback_converged(
			"clear-persisted", nil, nil, nil, true, true))
		H.truthy(policy.rollback_converged(
			"clear-persisted", nil, nil, "ordinary-live-456", true, true))
		H.equal(policy.rollback_converged(
			"clear-persisted", nil, nil, policy.BACKEND_ID, true, true), false)
		H.equal(policy.rollback_converged(
			"clear-persisted", nil, policy.BACKEND_ID, nil, true, true), false)
		H.equal(policy.rollback_converged(
			"clear-persisted", nil, nil, nil, false, true), false)
		H.equal(policy.rollback_converged(
			"clear-persisted", nil, nil, nil, true, false), false)
	end)

	H.test("WOC #934 stale sync and transition cannot release pre-equipped loser", function()
		local state = policy.new_state()
		policy.apply_identity(state, "peer-host", "slot_melee", true)
		local accepted, verdict = policy.apply_identity(
			state, "peer-loser", "slot_melee", true)
		H.equal(accepted, false)
		H.equal(verdict, "denied")

		local mode, target = policy.loser_resolution(nil, policy.BACKEND_ID)
		H.equal(mode, "clear-persisted")
		H.equal(target, nil)
		H.equal(policy.rollback_converged(
			mode, target, nil, policy.BACKEND_ID, true, true), false,
			"a queued ordinary sync cannot prove the live relic is gone")
		H.truthy(policy.rollback_converged(
			mode, target, nil, nil, true, true))

		-- A new game-state transition can still spawn a stale live relic. The
		-- same durable-empty policy must deny release until that exact slot is
		-- inspected and cleared again.
		mode, target = policy.loser_resolution(nil, nil)
		H.equal(mode, "clear-persisted")
		H.equal(policy.rollback_converged(
			mode, target, nil, policy.BACKEND_ID, true, true), false)
		H.truthy(policy.rollback_converged(
			mode, target, nil, nil, true, true))
	end)

	H.test("WOC #934 migration reservation outranks disconnect grace", function()
		local reserved = policy.rebuild_authority(
			"peer-b", "peer-a", {}, {})
		H.truthy(policy.is_migration_reserved(reserved))
		H.equal(policy.disconnect_expired(
			reserved, policy.DISCONNECT_GRACE_SECONDS), false)
		H.equal(policy.disconnect_expired(
			reserved, policy.MIGRATION_RESERVATION_SECONDS), false)
		policy.expire_migration_reservation(reserved)

		local active = policy.new_state()
		policy.apply_identity(active, "peer-b", "slot_melee", true)
		H.equal(policy.disconnect_expired(
			active, policy.DISCONNECT_GRACE_SECONDS - 0.01), false)
		H.truthy(policy.disconnect_expired(
			active, policy.DISCONNECT_GRACE_SECONDS))
	end)

	H.test("WOC #934 session reset clears every remote identity in place", function()
		local cache = {
			["peer-a"] = { slot_melee = true },
			["peer-b"] = { slot_ranged = true },
		}
		local same = policy.clear_identity_cache(cache)
		H.equal(same, cache)
		H.equal(next(cache), nil)
		cache["peer-a"] = { slot_melee = false }
		policy.clear_identity_cache(cache)
		H.equal(next(cache), nil)
	end)

	H.test("WOC #934 runtime uses same-mod authority and vanilla trophy ids", function()
		H.truthy(contract_source:find(
			'mod:network_register("woc_relic_lease_intent_v1"', 1, true))
		H.truthy(contract_source:find(
			'mod:network_register("woc_relic_lease_state_v1"', 1, true))
		H.truthy(contract_source:find(
			'mod:network_register("woc_relic_lease_query_v1"', 1, true))
		H.equal(contract_source:find(
			'mod:network_register("woc_blightreaper_identity"', 1, true), nil,
			"clients must have no independent render-identity write channel")
		H.equal(contract_source:find(
			'mod.network_send, mod, "woc_blightreaper_identity"', 1, true), nil,
			"loadout replay must not publish client-authored render identity")
		H.truthy(contract_source:find(
			'mod:hook(BackendUtils, "set_loadout_item"', 1, true))
		H.truthy(contract_source:find(
			'mod:hook("HeroViewStateOverview", "_set_loadout_item"', 1, true),
			"the native Hero caller ignores BackendUtils return values")
		H.truthy(contract_source:find(
			'mod:hook("SimpleInventoryExtension", "create_equipment_in_slot"',
			1, true), "direct live equipment creation needs the same denial gate")
		H.truthy(contract_source:find(
			'mod:hook("KeepDecorationTrophyExtension", "_load_trophy"', 1, true))
		H.truthy(contract_source:find(
			'_lease_on_local_identity(slot_name, is_blightreaper)', 1, true))
		H.truthy(contract_source:find('_lease_is_local_human(player)', 1, true))
		H.truthy(contract_source:find(
			'local career = pending.career or _lease_local_career_name()',
			1, true), "pre-equipped losing clients need an active-career rollback")
		H.truthy(contract_source:find(
			'local restored = _shared_relic_policy.rollback_verified(', 1, true),
			"rollback state must require exact backend readback")
		H.truthy(contract_source:find(
			'local function _lease_recreate_exact_live(', 1, true),
			"verified backend rollback must recreate the exact live item")
		H.truthy(contract_source:find(
			'local function _lease_empty_exact_relic_live(', 1, true),
			"a pre-equipped loser without prior state must fail closed")
		H.truthy(contract_source:find(
			'local rollback_pending = is_local_human', 1, true),
			"sync payloads must not publish intent while exact rollback is pending")
		H.truthy(contract_source:find(
			'type(player.local_player_id) == "function"', 1, true),
			"local-human gating must support VT2's callable player API")
		H.truthy(contract_source:find(
			'type(player._local_player_id) == "number"', 1, true),
			"local-human gating must support the retail backing field")
		H.truthy(contract_source:find(
			'_lease_apply_authoritative_remote_identity(', 1, true),
			"render identity must be applied from the host snapshot")
		H.truthy(contract_source:find(
			'_shared_relic_policy.rollback_converged(', 1, true),
			"release publication must require persisted and live convergence")
		H.truthy(contract_source:find(
			'local function _lease_live_read_verified(status)', 1, true),
			"an unavailable live inventory must not masquerade as an empty slot")
		H.equal(contract_source:find('"verified-live-sync"', 1, true), nil,
			"a LoadoutUtils payload must never prove rollback completion")
		H.truthy(contract_source:find(
			'if is_local_human and not _relic_lease_rollback', 1, true),
			"synchronous loadout sync must wait for rollback readback")
		H.truthy(contract_source:find(
			'local function _lease_seed_local_slots()', 1, true),
			"every game-state session must rehydrate pre-equipped identity")
		H.truthy(contract_source:find(
			'pcall(BackendUtils.set_loadout_item,', 1, true))
		H.truthy(contract_source:find(
			'nil, career, slot_name)', 1, true),
			"a pre-equipped loser must durably clear the persisted slot")
		H.truthy(contract_source:find(
			'_shared_relic_policy.rebuild_authority(', 1, true),
			"host promotion must rebuild a fresh authority epoch")
		H.truthy(contract_source:find(
			'_lease_send_reassert_and_query(host)', 1, true),
			"host migration must reassert before accepting an eager snapshot")
		H.equal(contract_source:find("_lease_find_base_backend_id", 1, true), nil,
			"pre-equipped rollback must not guess an inventory fallback")
		H.truthy(contract_source:find(
			'_lease_reset("game-state-exit:" .. tostring(state_name))', 1, true),
			"lobby leases must not survive the owning game-state session")
		H.truthy(contract_source:find(
			'_relic_lease_state_active = false', 1, true),
			"the public reset path must close the callback session")
		H.truthy(contract_source:find(
			'_shared_relic_runtime:on_enabled("mod-enabled")', 1, true),
			"mod re-enable must open a fresh guarded lease session")
		H.truthy(contract_source:find(
			'_shared_relic_policy.clear_identity_cache(_remote_blightreaper)',
			1, true), "remote identity may not survive a session reset")
		H.equal(select(2, contract_source:gsub(
			'_relic_trophy_extensions = setmetatable%(%{%}, %{%s*__mode = "k"%s*%}%)',
			"")), 2, "trophy extensions must be declared and replaced at reset")
		H.truthy(contract_source:find(
			'_shared_relic_policy.disconnect_expired(', 1, true),
			"disconnect cleanup must honor migration reservation")
		H.truthy(contract_source:find('"hub_trophy_empty"', 1, true) == nil,
			"trophy ids must remain single-sourced in the policy module")
		H.equal(contract_source:find(
			'mod:network_send, mod, "woc_relic_lease_query_v1", "server"',
			1, true), nil)
	end)
end
