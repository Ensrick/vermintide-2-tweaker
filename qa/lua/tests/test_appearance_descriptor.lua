return function(H, repo_root)
	local D = dofile(repo_root .. "/tools/shared_lib/_lib_appearance_descriptor.lua")

	local function musket_spec()
		return {
			item_key = "cwv_musket",
			identity_evidence = { kind = "backend_id", value = "uuid-1234" },
			right_hand_unit = { unit = "units/weapons/player/wpn_musket/wpn_musket", package = "resource_packages/cwv/musket" },
			transform_1p = { scale = { 1, 1, 1 }, offset = { 0, 0, -0.05 } },
			transform_3p = { scale = { 0.9, 0.9, 0.9 }, rotation = { -90, -90, -90 } },
			requires_mod = "character_weapon_variants",
			fallback = { right_hand_unit = { unit = "units/weapons/player/wpn_emp_handgun_t1/wpn_emp_handgun_t1" } },
		}
	end

	H.test("descriptor builds, freezes, and rejects mutation", function()
		local d, errors = D.build(musket_spec())
		H.truthy(d, errors and table.concat(errors, "; "))
		H.equal(d.item_key, "cwv_musket")
		H.equal(d.generation, 0)
		local mutated = pcall(function() d.item_key = "hacked" end)
		H.equal(mutated, false)
		H.equal(d.item_key, "cwv_musket")
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

		local g1, gerr = D.next_generation(a)
		H.truthy(g1, gerr and table.concat(gerr, "; "))
		H.equal(g1.generation, 1)
		H.truthy(D.fingerprint(a) ~= D.fingerprint(g1))
		H.equal(g1.item_key, a.item_key)
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

	H.test("census cell and edge vocabularies are closed and complete", function()
		H.equal(#D.CELLS, 10)
		H.equal(#D.EDGES, 8)
		local want = { owner_1p = true, owner_3p = true, bot = true, husk = true,
			inventory_preview = true, illusion_browser = true, cim_preview = true,
			lobby = true, score_team = true, hold_tab = true }
		for _, cell in ipairs(D.CELLS) do
			H.truthy(want[cell], "unexpected cell " .. tostring(cell))
			want[cell] = nil
		end
		H.equal(next(want), nil)
	end)
end
