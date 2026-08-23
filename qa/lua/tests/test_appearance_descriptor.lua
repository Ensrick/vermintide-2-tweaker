return function(H, repo_root)
	local D = dofile(repo_root .. "/tools/shared_lib/_lib_appearance_descriptor.lua")

	local function musket_spec()
		return {
			item_key = "cwv_musket",
			identity_evidence = { kind = "backend_id", value = "uuid-1234" },
			right_hand_unit = { unit = "units/weapons/player/wpn_musket/wpn_musket", package = "resource_packages/cwv/musket" },
			transform_1p = { scale = { 1, 1, 1 }, offset = { 0, 0, -0.05 } },
			transform_3p = { scale = { 0.9, 0.9, 0.9 }, rotation = { -90, -90, -90 } },
			attachment_profile = "held_3p_rifle_character",
			transform_profiles = {
				held_3p_rifle_character = {
					scale = { 0.9, 0.9, 0.9 }, rotation = { -90, -90, -90 },
				},
				display_3p_rifle = {
					scale = { 0.9, 0.9, 0.9 }, rotation = { -90, -90, -90 },
				},
			},
			requires_mod = "character_weapon_variants",
			fallback = { right_hand_unit = { unit = "units/weapons/player/wpn_emp_handgun_t1/wpn_emp_handgun_t1" } },
		}
	end

	H.test("descriptor builds, freezes, and rejects mutation", function()
		local spec = musket_spec()
		local d, errors = D.build(spec)
		H.truthy(d, errors and table.concat(errors, "; "))
		H.equal(d.item_key, "cwv_musket")
		H.equal(d.generation, 0)
		local fingerprint = D.fingerprint(d)
		H.equal(d.fingerprint, fingerprint,
			"built descriptors expose their computed immutable fingerprint")
		H.equal(#d.fingerprint, 8)
		local mutated = pcall(function() d.item_key = "hacked" end)
		H.equal(mutated, false)
		H.equal(pcall(function() d.fingerprint = "00000000" end), false)
		H.equal(pcall(function()
			d.transform_profiles.display_3p_rifle.scale[1] = 99
		end), true, "nested reads must remain ordinary Lua 5.1 tables")
		H.equal(pcall(function()
			d.fallback.right_hand_unit.unit = "units/hacked"
		end), true, "nested fallback reads must remain ordinary Lua 5.1 tables")
		H.equal(d.transform_profiles.display_3p_rifle.scale[1], 0.9,
			"nested mutation must affect only the detached read snapshot")
		H.equal(d.fallback.right_hand_unit.unit,
			"units/weapons/player/wpn_emp_handgun_t1/wpn_emp_handgun_t1")

		-- Caller-owned tables are detached at build time. Mutating the original
		-- spec cannot mint a new reconciler token without a generation edge.
		spec.transform_profiles.display_3p_rifle.scale[1] = 77
		spec.right_hand_unit.unit = "units/caller_hacked"
		H.equal(d.item_key, "cwv_musket")
		local raw = D.raw(d)
		H.equal(raw.transform_profiles.display_3p_rifle.scale[1], 0.9)
		H.equal(raw.right_hand_unit.unit,
			"units/weapons/player/wpn_musket/wpn_musket")
		H.equal(D.fingerprint(d), fingerprint)
	end)

	H.test("descriptor generations deep-isolate nested state and raw snapshots", function()
		local original = assert(D.build(musket_spec()))
		local generated = assert(D.next_generation(original))
		H.equal(generated.generation, 1)
		H.truthy(original.transform_profiles ~= generated.transform_profiles,
			"generation views must not share nested proxies")
		H.equal(pcall(function()
			generated.transform_profiles.display_3p_rifle.rotation[1] = 0
		end), true)
		H.equal(generated.transform_profiles.display_3p_rifle.rotation[1], -90)

		local original_raw = D.raw(original)
		local generated_raw = D.raw(generated)
		original_raw.transform_profiles.display_3p_rifle.rotation[1] = 12
		generated_raw.transform_profiles.display_3p_rifle.rotation[1] = 34
		H.equal(D.raw(original).transform_profiles.display_3p_rifle.rotation[1], -90)
		H.equal(D.raw(generated).transform_profiles.display_3p_rifle.rotation[1], -90)
		H.truthy(D.fingerprint(original) ~= D.fingerprint(generated),
			"generation remains the only token-changing lifecycle axis")
	end)

	H.test("descriptor demands fallback for optional visual fields", function()
		local spec = musket_spec()
		spec.fallback = nil
		local d, errors = D.build(spec)
		H.equal(d, nil)
		H.truthy(table.concat(errors, " "):find("fallback", 1, true))

		-- No optional visual fields -> no fallback demanded.
		local bare, bare_err = D.build({
			item_key = "es_1h_sword",
			identity_evidence = { kind = "preview_slot", value = "melee" },
		})
		H.truthy(bare, bare_err and table.concat(bare_err, "; "))
	end)

	H.test("descriptor validates evidence kinds and transform shapes", function()
		local spec = musket_spec()
		spec.identity_evidence = { kind = "vibes" }
		local d, errors = D.build(spec)
		H.equal(d, nil)
		H.truthy(table.concat(errors, " "):find("identity_evidence", 1, true))

		spec = musket_spec()
		spec.transform_3p = { scale = { 1, 1 } }
		d, errors = D.build(spec)
		H.equal(d, nil)
		H.truthy(table.concat(errors, " "):find("triplet", 1, true))

		spec = musket_spec()
		spec.identity_evidence = { kind = "backend_id", value = "" }
		d, errors = D.build(spec)
		H.equal(d, nil)

		spec = musket_spec()
		spec.attachment_profile = "undeclared_parent"
		d, errors = D.build(spec)
		H.equal(d, nil)
		H.truthy(table.concat(errors, " "):find("declared transform_profiles", 1, true))

		spec = musket_spec()
		spec.transform_profiles.display_3p_rifle.scale = { 1, 1 }
		d, errors = D.build(spec)
		H.equal(d, nil)
		H.truthy(table.concat(errors, " "):find("transform_profiles.display_3p_rifle", 1, true))
	end)

	H.test("descriptor rejects a malformed optional third-person hand path", function()
		local malformed = musket_spec()
		malformed.right_hand_unit.unit_3p = ""
		local descriptor, errors = D.build(malformed)
		H.equal(descriptor, nil)
		H.truthy(table.concat(errors, "|"):find(
			"right_hand_unit.unit_3p must be a non-empty string", 1, true))
	end)

	H.test("fingerprint is stable, order-independent, and generation-sensitive", function()
		local a = D.build(musket_spec())
		local b = D.build(musket_spec())
		H.equal(D.fingerprint(a), D.fingerprint(b))
		H.equal(#D.fingerprint(a), 8)

		local changed_spec = musket_spec()
		changed_spec.transform_3p.rotation = { -90, -90, 0 }
		local c = D.build(changed_spec)
		H.truthy(D.fingerprint(a) ~= D.fingerprint(c))

		local display_changed = musket_spec()
		display_changed.transform_profiles.display_3p_rifle.position = { 0, 0.1, 0 }
		local display_descriptor = D.build(display_changed)
		H.truthy(D.fingerprint(a) ~= D.fingerprint(display_descriptor))

		local g1, gerr = D.next_generation(a)
		H.truthy(g1, gerr and table.concat(gerr, "; "))
		H.equal(g1.generation, 1)
		H.truthy(D.fingerprint(a) ~= D.fingerprint(g1))
		H.equal(g1.item_key, a.item_key)
	end)

	H.test("fingerprint is computed, source-qualified, and cannot be supplied", function()
		local forged = musket_spec()
		forged.fingerprint = "caller-controlled"
		local descriptor, errors = D.build(forged)
		H.equal(descriptor, nil)
		H.truthy(table.concat(errors, " "):find(
			"fingerprint is computed", 1, true))

		local base = assert(D.build(musket_spec()))
		for _, mutation in ipairs({
			function(spec) spec.style_id = "bretonnian" end,
			function(spec) spec.effective_template = "bastard_sword_template" end,
			function(spec) spec.transform_3p.offset = { 0.1, 0, 0 } end,
		}) do
			local changed = musket_spec()
			mutation(changed)
			local next_descriptor = assert(D.build(changed))
			H.truthy(next_descriptor.fingerprint ~= base.fingerprint,
				"every descriptor-owned appearance axis must change the fingerprint")
		end
	end)

	H.test("fingerprint rejects non-data descriptors", function()
		local spec = musket_spec()
		spec.on_apply = function() end
		local ok = pcall(function()
			local d = D.build(spec)
			return D.fingerprint(d)
		end)
		H.equal(ok, false)
	end)

	H.test("census surface and edge vocabularies are closed and complete", function()
		H.equal(#D.CELLS, 17)
		H.equal(#D.EDGES, 8)
		H.equal(D.SURFACES, D.CELLS)
		local want = { owner_1p = true, owner_3p = true, bot = true, husk = true,
			inventory_preview = true, illusion_browser = true, cim_preview = true,
			crafting_preview = true,
			lobby = true, score_team = true, hold_tab = true,
			specials = true, remote_audio = true, hud_panels = true, portraits = true,
			item_card_2d = true, inventory_tooltip = true }
		for _, cell in ipairs(D.CELLS) do
			H.truthy(want[cell], "unexpected surface " .. tostring(cell))
			want[cell] = nil
		end
		H.equal(next(want), nil)
	end)

	H.test("matrix expansion is total and never invents a state", function()
		local decl = {}
		for _, surface in ipairs(D.CELLS) do
			decl[surface] = { default = "implemented" }
		end
		decl.husk = {
			default = "implemented",
			note = "row fallback",
			edges = { peer_ready = "unsupported", mission_transition = "unsupported" },
			notes = { peer_ready = "hot-join has no replication channel" },
		}
		local matrix, errors = D.expand_matrix(decl)
		H.equal(#errors, 0, table.concat(errors, "\n"))
		H.equal(matrix.husk.equip.state, "implemented")
		H.equal(matrix.husk.peer_ready.state, "unsupported")
		H.equal(matrix.husk.peer_ready.note, "hot-join has no replication channel")
		-- The row note covers an overridden edge that has no per-edge note.
		H.equal(matrix.husk.mission_transition.note, "row fallback")

		local count = 0
		D.each_pair(matrix, function() count = count + 1 end)
		H.equal(count, #D.CELLS * #D.EDGES)

		-- Dropping one row must fail rather than default the surface.
		decl.portraits = nil
		local incomplete, row_errors = D.expand_matrix(decl)
		H.equal(incomplete, nil)
		H.equal(#row_errors, 1)
		H.truthy(row_errors[1]:find("portraits", 1, true))
	end)

	H.test("Appearance #1155 reconciler proves retained state independently and coalesces", function()
		local descriptor = D.build(musket_spec())
		local writes, reads = 0, 0
		local target = { retained = false }
		local reconciler = D.new_reconciler({
			apply = function(_, surface, edge, live)
				H.equal(surface, "owner_3p")
				H.equal(edge, "equip")
				writes = writes + 1
				live.retained = true
				return { setter_ok = true }
			end,
			observe = function(_, _, _, live, context)
				reads = reads + 1
				H.equal(context.probe, "engine-readback")
				return { retained = live.retained == true, reason = "retained" }
			end,
		})
		local first = reconciler.reconcile(descriptor, "owner_3p", "equip", target,
			{ probe = "engine-readback" })
		H.equal(first.retained, true)
		H.equal(writes, 1)
		H.equal(reads, 1)
		local duplicate = reconciler.reconcile(descriptor, "owner_3p", "equip", target,
			{ probe = "engine-readback" })
		H.equal(duplicate.coalesced, true)
		H.equal(writes, 1)
		H.equal(reads, 1)
	end)

	H.test("Appearance #1155 reconciler caps failures and clears disconnected targets", function()
		local descriptor = D.build(musket_spec())
		local writes = 0
		local target = {}
		local reconciler = D.new_reconciler({
			max_attempts = 2,
			apply = function() writes = writes + 1; return { setter_ok = true } end,
			observe = function() return { retained = false, reason = "engine-rejected" } end,
		})
		H.equal(reconciler.reconcile(descriptor, "husk", "peer_ready", target).ok, false)
		H.equal(reconciler.reconcile(descriptor, "husk", "peer_ready", target).ok, false)
		local capped = reconciler.reconcile(descriptor, "husk", "peer_ready", target)
		H.equal(capped.coalesced, true)
		H.equal(writes, 2)
		H.equal(reconciler.disconnect(), true)
		reconciler.reconcile(descriptor, "husk", "peer_ready", target)
		H.equal(writes, 3)
	end)

	H.test("Appearance #1155 reconciler prunes superseded generations per lifecycle axis", function()
		local descriptor = assert(D.build(musket_spec()))
		local target, writes = {}, 0
		local reconciler = D.new_reconciler({
			apply = function() writes = writes + 1; return {} end,
			observe = function() return { retained = true, reason = "retained" } end,
		})
		for generation = 0, 199 do
			local result = reconciler.reconcile(descriptor,
				"owner_3p", "customize", target)
			H.equal(result.retained, true)
			H.equal(reconciler.record_count(target), 1,
				"a long-lived unit may retain only the latest token for one axis")
			if generation < 199 then descriptor = assert(D.next_generation(descriptor)) end
		end
		H.equal(writes, 200)
		H.equal(reconciler.attempts(target, descriptor,
			"owner_3p", "customize"), 1)
		local prior = assert(D.build(musket_spec()))
		H.equal(reconciler.attempts(target, prior,
			"owner_3p", "customize"), 0,
			"superseded generations must not remain addressable")
		reconciler.reconcile(descriptor, "owner_3p", "equip", target)
		H.equal(reconciler.record_count(target), 2,
			"distinct source-qualified axes retain independent bounded records")
	end)

	H.test("Appearance #1155 fallback cells are bounded without a custom-retained claim", function()
		local descriptor = D.build(musket_spec())
		local reconciler = D.new_reconciler({
			apply = function()
				return { fallback = true, reason = "renderer-has-no-custom-adapter" }
			end,
			observe = function() error("fallback must not claim custom readback") end,
		})
		local result = reconciler.reconcile(descriptor, "hold_tab", "instance_load", {})
		H.equal(result.ok, true)
		H.equal(result.fallback, true)
		H.equal(result.reason, "renderer-has-no-custom-adapter")
	end)
end
