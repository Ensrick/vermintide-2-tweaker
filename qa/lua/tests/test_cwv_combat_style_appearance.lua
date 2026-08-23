return function(H, repo_root)
	local D = dofile(repo_root .. "/tools/shared_lib/_lib_appearance_descriptor.lua")
	local A = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
		.. "_cwv_combat_style_appearance.lua")
	local Lifecycle = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
		.. "_cwv_appearance_lifecycle.lua")

	local function row(style_id)
		local packages = {
			greatsword = { template = "two_handed_swords_template_1" },
			bretonnian = { template = "bastard_sword_template",
				resource = "units/state_machines/bastard_sword",
				presentation = { transform_key = "greatsword_bretonnian" } },
		}
		return { item_key = "es_2h_sword", family_id = "greatsword",
			style_id = style_id, package = packages[style_id] }
	end

	local function args(style_id)
		return {
			slot_name = "slot_melee",
			row = row(style_id),
			world = {
				base_item_key = "es_2h_sword", source = "skin",
				skin = "es_2h_sword_skin_02",
				right_hand_unit = "units/weapons/player/greatsword_02",
			},
			base = { key = "es_2h_sword",
				right_hand_unit = "units/weapons/player/greatsword_01" },
			presentation = style_id == "bretonnian" and {
				right_hand_scale_3p = { 1, 0.8, 0.9 },
				right_hand_offset_3p = { -0.1, 0, 0 },
			} or nil,
		}
	end

	local deps = {
		descriptor = D,
		encode_style_rider = function(family, style)
			if family ~= "greatsword" then return nil end
			return family .. ":" .. style
		end,
	}

	H.test("CWV #660 Greatsword style descriptor owns template transform and hands", function()
		local descriptor, err = A.build(deps, args("bretonnian"))
		H.truthy(descriptor, err)
		H.equal(descriptor.provider, A.PROVIDER)
		H.equal(descriptor.style_rider, "greatsword:bretonnian")
		H.equal(descriptor.effective_template, "bastard_sword_template")
		H.equal(descriptor.transform_3p.scale[2], 0.8)
		H.equal(descriptor.transform_3p.offset[1], -0.1)
		H.equal(descriptor.transform_1p, nil)
		H.equal(A.hand_unit(descriptor, "right"),
			"units/weapons/player/greatsword_02")
		H.equal(A.hand_unit(descriptor, "right", "3p"),
			"units/weapons/player/greatsword_02_3p")
		H.equal(descriptor.fallback.right_hand_unit.unit,
			"units/weapons/player/greatsword_01")
		local expected = assert(A.expectation(descriptor))
		H.equal(expected.item_key, "es_2h_sword")
		H.equal(expected.template, "bastard_sword_template")
		H.equal(expected.right, true)
		H.equal(expected.left, false)
		H.equal(expected.right_unit, "units/weapons/player/greatsword_02_3p")
		H.equal(expected.left_unit, nil)
		H.equal(expected.fingerprint, descriptor.fingerprint)
		local decision = A.transform_decision(descriptor, "3p")
		H.equal(decision.right_hand_scale[2], 0.8)
		H.equal(decision.right_hand_offset[1], -0.1)
		H.equal(A.transform_decision(descriptor, "1p"), false)
		local all_views = A.transform_decision(descriptor)
		H.equal(all_views.right_hand_scale_3p[2], 0.8)
		H.equal(all_views.right_hand_scale_1p, nil)
	end)

	H.test("CWV #660 sender and observer reconstruct one source-qualified fingerprint", function()
		local owner = assert(A.build(deps, args("bretonnian")))
		local observer_args = args("bretonnian")
		observer_args.backend_id = "observer-must-ignore-owner-uuid"
		local observer = assert(A.build(deps, observer_args))
		H.equal(owner.fingerprint, observer.fingerprint)
		H.equal(owner.identity_evidence.value, observer.identity_evidence.value)

		local switched = assert(A.build(deps, args("greatsword")))
		H.truthy(switched.fingerprint ~= owner.fingerprint,
			"style/template changes cannot be swallowed by identity dedupe")
	end)

	H.test("CWV #660 style descriptor composes unified and perspective transforms", function()
		local authored = args("bretonnian")
		authored.presentation = {
			right_hand_scale = { 0.9, 0.9, 0.9 },
			right_hand_offset = { 0, 0, -0.1 },
			right_hand_offset_3p = { 0.2, 0, 0 },
			right_hand_rotation = { -90, 0, 0 },
		}
		local descriptor = assert(A.build(deps, authored))
		H.equal(descriptor.transform_1p.scale[1], 0.9)
		H.equal(descriptor.transform_1p.offset[3], -0.1)
		H.equal(descriptor.transform_3p.scale[1], 0.9)
		H.equal(descriptor.transform_3p.offset[1], 0.2)
		H.equal(descriptor.transform_3p.rotation[1], -90)
	end)

	H.test("CWV #660 style descriptor fails closed on foreign and incomplete input", function()
		local foreign = args("greatsword")
		foreign.row.family_id = "greathammer"
		H.equal(A.build(deps, foreign), nil)

		local missing_fallback = args("greatsword")
		missing_fallback.base.right_hand_unit = nil
		H.equal(A.build(deps, missing_fallback), nil)

		local bad_deps = { descriptor = D, encode_style_rider = function() return nil end }
		H.equal(A.build(bad_deps, args("greatsword")), nil)
	end)

	H.test("CWV #660 legacy and immutable descriptors share one hand accessor", function()
		H.equal(A.hand_unit({ right_hand_unit = "units/legacy" }, "right"),
			"units/legacy")
		H.equal(A.expectation({ provider = "cwv", style_family = "greatsword" }), nil)
	end)

	H.test("CWV #660 Greatsword planner payload and receiver form one exact transaction", function()
		local sent = {}
		local owner_style = "bretonnian"
		local lifecycle = Lifecycle.new({
			resolve_local = function(_, slot_name)
				if slot_name ~= "slot_melee" then return nil, "es_longbow" end
				return A.build(deps, args(owner_style)), "es_2h_sword"
			end,
			resolve_remote = function(payload)
				local family, style = payload.style:match("^([^:]+):([^:]+)$")
				if family ~= "greatsword" or (style ~= "greatsword"
						and style ~= "bretonnian") then return nil, "style invalid" end
				local rebuilt = args(style)
				rebuilt.world.skin = payload.skin_key ~= "" and payload.skin_key or nil
				return A.build(deps, rebuilt)
			end,
			send = function(_, _, payload)
				sent[#sent + 1] = payload
				return true
			end,
		})
		local payload = assert(lifecycle:payload_for("slot_melee", {}))
		H.equal(payload.provider, A.PROVIDER)
		H.equal(payload.style, "greatsword:bretonnian")
		H.equal(payload.right_hand_unit, nil,
			"unit paths remain local reconstruction data")
		local changed, descriptor, reason = lifecycle:accept(
			"peer-style", Lifecycle.SCHEMA, payload)
		H.equal(changed, true)
		H.equal(reason, "exact")
		H.equal(descriptor.fingerprint, payload.fingerprint)
		H.equal(descriptor.effective_template, "bastard_sword_template")

		H.equal(lifecycle:publish({ slot_melee = {} }, "initial"), 2)
		H.equal(lifecycle:publish({ slot_melee = {} }, "duplicate"), 0)
		owner_style = "greatsword"
		H.equal(lifecycle:publish({ slot_melee = {} }, "style_switch"), 1)
		H.truthy(sent[#sent].fingerprint ~= payload.fingerprint)

		local tampered = {}
		for key, value in pairs(payload) do tampered[key] = value end
		tampered.style = "greatsword:greatsword"
		local _, rejected, rejected_reason = lifecycle:accept(
			"peer-tamper", Lifecycle.SCHEMA, tampered)
		H.equal(rejected, nil)
		H.equal(rejected_reason, "fingerprint_mismatch")
	end)
end
