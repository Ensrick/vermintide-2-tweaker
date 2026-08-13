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

	-- The send gate moved out of the entry chunk into its owner module by the
	-- #423 exact-catalog conversion; these checks follow it there.
	local runtime_path = repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_exact_wire_runtime.lua"
	local function runtime_source()
		local file = assert(io.open(runtime_path, "rb"))
		local source = file:read("*a")
		file:close()
		return source
	end

	H.test("CWV #423 send hook has no fail-open custom-id fallback", function()
		local source = runtime_source()
		H.truthy(source:find("damage_profile_wire.profile_id_for_send", 1, true))
		H.truthy(source:find('disposition == "drop"', 1, true))
		H.equal(source:find("return safe or id", 1, true), nil)
	end)

	-- The sender must key off the COMMITTED gate state, not the raw roster
	-- classifier. all_peers_have() flips true the instant the last ack lands,
	-- which is up to SETTLE_ENABLE seconds before the gate commits
	-- (_lib_peer_parity.lua:619-621) and ignores every _force_disable edge that
	-- does not change an already-acked peer's ack -- including the synchronous
	-- hot-join fence. Post-#423 the verdict additionally requires the exact
	-- catalog, so presence alone can no longer authorize a custom id at all.
	H.test("CWV #423 send-gate reads the committed exact state, not the roster classifier", function()
		local source = runtime_source()
		local start = assert(source:find("function mod._cwv_damage_wire_safe()", 1, true),
			"_cwv_damage_wire_safe verdict missing")
		local body_end = assert(source:find("om._wire_safe_damage_profile_id", start, true),
			"_cwv_damage_wire_safe body not delimited")
		local body = source:sub(start, body_end)
		H.truthy(body:find("pcall(pp.applied_state, pp)", 1, true))
		H.truthy(body:find('state == "enabled"', 1, true))
		H.truthy(body:find("catalog_intact", 1, true))
		H.equal(body:find("pcall(pp.all_peers_have, pp)", 1, true), nil)
	end)

	H.test("CWV #1204 Deus identity install reads committed parity state", function()
		local path = repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_item_registration_owner.lua"
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a")
		file:close()
		local start = assert(source:find("local function _deus_exact_identity_allowed(parity)", 1, true))
		local body_end = assert(source:find("local report = _om.deus_identity.install(", start, true))
		local body = source:sub(start, body_end)
		H.truthy(body:find("pcall(parity.applied_state, parity)", 1, true))
		H.truthy(body:find('state == "enabled"', 1, true))
		H.truthy(body:find("_deus_exact_identity_allowed(parity)", 1, true))
		H.equal(body:find("parity.all_peers_have", 1, true), nil,
			"the raw roster classifier must not authorize exact Deus identities")
	end)

	H.test("CWV #423 exact damage catalog pins its generation against late producers", function()
		-- capture() finalizes the WHOLE cwv_* namespace, so every cwv row must
		-- already carry a recorded donor; cwv_future_unmapped is exercised by
		-- the refusal test below.
		local mapped = lookup()
		mapped[9], mapped.cwv_future_unmapped = nil, nil
		local snapshot = assert(policy.capture(
			dofile(repo_root .. "/tools/shared_lib/_lib_wire_catalog.lua"),
			mapped, sources, 7))
		H.equal(policy.catalog_intact(snapshot, 7), true)
		-- A producer recording a new mapping after finalization must invalidate
		-- the catalog rather than leave a cwv id proven by a stale identity.
		H.equal(policy.catalog_intact(snapshot, 8), false)
		-- Exact rides only under a proven catalog; otherwise the donor floor.
		H.equal(select(1, policy.profile_id_for_send(false, 8, true, snapshot, 7)), 8)
		H.equal(select(2, policy.profile_id_for_send(false, 8, true, snapshot, 7)), "exact")
		H.equal(select(1, policy.profile_id_for_send(false, 8, false, snapshot, 7)), 1)
		H.equal(select(2, policy.profile_id_for_send(false, 8, false, snapshot, 7)), "source")
		H.equal(select(2, policy.profile_id_for_send(false, 8, true, snapshot, 9)), "source")
	end)

	H.test("CWV #423 capture refuses a cwv profile with no recorded vanilla donor", function()
		local snapshot, err = policy.capture(
			dofile(repo_root .. "/tools/shared_lib/_lib_wire_catalog.lua"),
			lookup(), sources, 1)
		H.equal(snapshot, nil)
		H.truthy(tostring(err):find("unmapped%-custom%-profile"))
	end)
end
