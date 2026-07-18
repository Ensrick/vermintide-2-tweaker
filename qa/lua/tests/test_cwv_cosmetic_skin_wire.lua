return function(H, repo_root)
	local module_path = repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_cosmetic_skin_wire.lua"
	local policy = assert(loadfile(module_path))()

	local skin_keys = { cwv_es_greataxe_skin = true, es_base_variant_skin = true }
	local custom_skin_keys = { cwv_pairing_illusion = true }

	H.test("CWV #423 cosmetic-skin predicate flags every cwv key set + the cwv_ prefix", function()
		-- cwv_ prefix (the 2026-07-18 crash key was cwv_es_musket_old_skin).
		H.equal(policy.is_cwv_skin("cwv_es_musket_old_skin", skin_keys, custom_skin_keys), true)
		-- base-variant key set membership (a non-prefixed key would still be caught).
		H.equal(policy.is_cwv_skin("es_base_variant_skin", skin_keys, custom_skin_keys), true)
		-- pairing/illusion custom key set membership.
		H.equal(policy.is_cwv_skin("cwv_pairing_illusion", skin_keys, custom_skin_keys), true)
	end)

	H.test("CWV #423 cosmetic-skin predicate leaves vanilla + malformed skins alone", function()
		H.equal(policy.is_cwv_skin("wh_sword_skin_01", skin_keys, custom_skin_keys), false)
		H.equal(policy.is_cwv_skin("n/a", skin_keys, custom_skin_keys), false)
		H.equal(policy.is_cwv_skin(nil, skin_keys, custom_skin_keys), false)
		H.equal(policy.is_cwv_skin(42, skin_keys, custom_skin_keys), false)
		-- Absent key sets must not throw; the prefix rule still applies.
		H.equal(policy.is_cwv_skin("cwv_anything", nil, nil), true)
		H.equal(policy.is_cwv_skin("wh_sword_skin_01", nil, nil), false)
	end)

	H.test("CWV #423 wire_safe_skin coerces a cwv skin to the vanilla no-skin key", function()
		local safe, subbed = policy.wire_safe_skin("cwv_es_musket_old_skin", skin_keys, custom_skin_keys)
		H.equal(safe, "n/a")
		H.equal(safe, policy.VANILLA_NO_SKIN)
		H.equal(subbed, true)
	end)

	H.test("CWV #423 wire_safe_skin passes a vanilla or nil skin through unchanged", function()
		local safe, subbed = policy.wire_safe_skin("wh_sword_skin_01", skin_keys, custom_skin_keys)
		H.equal(safe, "wh_sword_skin_01")
		H.equal(subbed, false)
		local nil_safe, nil_subbed = policy.wire_safe_skin(nil, skin_keys, custom_skin_keys)
		H.equal(nil_safe, nil)
		H.equal(nil_subbed, false)
	end)

	H.test("CWV #423 substitution is unconditional -- no parity-gated entry point", function()
		-- Parity/is_server gating belongs ONLY to the gameplay (damage_profile) axis,
		-- whose module exposes for_send / resolve_unconfirmed. The cosmetic-skin axis
		-- must expose NEITHER: a cwv skin can never ride this profile-sync wire
		-- regardless of roster, so there is no parity-conditional API to call.
		H.equal(policy.for_send, nil)
		H.equal(policy.resolve_unconfirmed, nil)
		-- The only decision surface is the roster-independent coercion.
		H.equal(type(policy.wire_safe_skin), "function")
		H.equal(type(policy.is_cwv_skin), "function")
	end)

	H.test("CWV #423 main file wires the update_cosmetic_slot sender to this module", function()
		local main_path = repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
		local file = assert(io.open(main_path, "rb"))
		local text = file:read("*a")
		file:close()

		-- Module is loaded onto _om.
		H.truthy(text:find('_om.cosmetic_skin_wire = mod:dofile', 1, true))
		-- The FOURTH sender is hooked (plain-table CosmeticUtils -> table-form hook).
		H.truthy(text:find('mod:hook(CosmeticUtils, "update_cosmetic_slot"', 1, true))
		-- The hook decides via the tested pure function and forwards the safe value.
		H.truthy(text:find("_om.cosmetic_skin_wire.wire_safe_skin", 1, true))
		H.truthy(text:find("return func(player, slot, item_name, safe)", 1, true))
		-- The surface is recorded for /cwv_regression_test coverage.
		H.truthy(text:find("mod._cwv_skin_wire_surfaces.update_cosmetic_slot = true", 1, true))
		-- The predicate has a single source of truth (the equipment-sender path
		-- delegates to the same module rather than re-implementing the check).
		H.truthy(text:find("_om.cosmetic_skin_wire.is_cwv_skin(skin, _om._skin_keys, _custom_skin_keys)", 1, true))
	end)
end
