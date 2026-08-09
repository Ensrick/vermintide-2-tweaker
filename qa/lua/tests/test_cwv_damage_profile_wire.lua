return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_damage_profile_wire.lua")

	local function lookup(include_default)
		local out = {
			[1] = "light_slashing_linesman",
			light_slashing_linesman = 1,
			[8] = "cwv_il_light_slashing_linesman",
			cwv_il_light_slashing_linesman = 8,
			[9] = "cwv_future_unmapped",
			cwv_future_unmapped = 9,
		}
		if include_default ~= false then
			out[2] = "default"
			out.default = 2
		end
		return out
	end

	local sources = {
		cwv_il_light_slashing_linesman = "light_slashing_linesman",
	}

	H.test("CWV #423 substitutes the exact vanilla donor when parity is unknown", function()
		local id, disposition = policy.for_send(false, false, lookup(), sources, 8)
		H.equal(id, 1)
		H.equal(disposition, "source")
	end)

	H.test("CWV #423 preserves authored profile only under positive parity or server authority", function()
		local parity_id, parity_disposition = policy.for_send(false, true, lookup(), sources, 8)
		local server_id, server_disposition = policy.for_send(true, false, lookup(), sources, 8)
		H.equal(parity_id, 8)
		H.equal(parity_disposition, "parity")
		H.equal(server_id, 8)
		H.equal(server_disposition, "server")
	end)

	H.test("CWV #423 untracked custom profiles fall back to boot-stable vanilla default", function()
		local id, disposition = policy.for_send(false, false, lookup(), sources, 9)
		H.equal(id, 2)
		H.equal(disposition, "fallback")
	end)

	H.test("CWV #423 never returns a custom id when no vanilla fallback can be proven", function()
		local id, disposition = policy.for_send(false, false, lookup(false), sources, 9)
		H.equal(id, nil)
		H.equal(disposition, "drop")
	end)

	H.test("CWV #423 leaves vanilla profiles unchanged in mixed lobbies", function()
		local id, disposition = policy.for_send(false, false, lookup(), sources, 1)
		H.equal(id, 1)
		H.equal(disposition, "vanilla")
	end)

	H.test("CWV #423 source hook has no fail-open custom-id fallback", function()
		local path = repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a")
		file:close()
		H.truthy(source:find("damage_profile_wire.for_send", 1, true))
		H.truthy(source:find('disposition == "drop"', 1, true))
		H.equal(source:find("return safe or id", 1, true), nil)
	end)

	-- The damage-profile sender must key off the COMMITTED gate state, not the
	-- raw roster classifier. all_peers_have() flips true the instant the last ack
	-- lands, which is up to SETTLE_ENABLE seconds before the gate commits
	-- (_lib_peer_parity.lua:619-621) and ignores every _force_disable edge that
	-- does not change an already-acked peer's ack -- including the synchronous
	-- hot-join fence. cwv's thrown-pickup sender and wt's _wt431_profiles_allowed
	-- both read applied_state(); this keeps the third sender on the same edges.
	H.test("CWV #423 send-gate reads the committed parity state, not the roster classifier", function()
		local path = repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a")
		file:close()

		local start = assert(source:find("local function _wire_parity_live()", 1, true),
			"_wire_parity_live helper missing")
		local body_end = assert(source:find("_om._wire_parity_live = _wire_parity_live", start, true),
			"_wire_parity_live export missing")
		local body = source:sub(start, body_end)
		H.truthy(body:find("pcall(pp.applied_state, pp)", 1, true))
		H.truthy(body:find('res == "enabled"', 1, true))
		H.equal(body:find("pcall(pp.all_peers_have, pp)", 1, true), nil)
	end)

	H.test("CWV #423 capture is exclusive to damage-profile send-gate events", function()
		local path = repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a")
		file:close()

		-- Cosmetic skin nulling is a separate wire-safety axis. Its line must
		-- remain observable without satisfying an issue #423 log capture.
		H.truthy(source:find("[cwv:skin-wire] wire skin null", 1, true))
		H.equal(source:find("[cwv:423] wire skin null", 1, true), nil)

		-- Reserve the issue marker for the two outcomes produced by the
		-- WeaponSystem.send_rpc_attack_hit gate: substitute or fail closed.
		H.truthy(source:find("[cwv:423] wire dmg-profile sub:", 1, true))
		H.truthy(source:find("[cwv:423] blocked unsafe hit:", 1, true))
		local runtime_marker_count = 0
		for line in source:gmatch("[^\r\n]+") do
			if line:find('pcall(printf, "[cwv:423]', 1, true) then
				runtime_marker_count = runtime_marker_count + 1
			end
		end
		H.equal(runtime_marker_count, 2)
	end)
end
