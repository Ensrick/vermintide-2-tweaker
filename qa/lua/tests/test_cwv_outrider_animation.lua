local function read(path)
	local file = assert(io.open(path, "rb"))
	local source = file:read("*a")
	file:close()
	return source
end

return function(H, repo_root)
	local root = repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
	local policy = assert(loadfile(root .. "_cwv_outrider_animation.lua"))()
	local anim_lookup = {
		to_repeater_pistol = 669,
		[669] = "to_repeater_pistol",
	}

	H.test("CWV #760 applies receiver-native Outrider 3P stance only to standard Saltzpyre", function()
		local template = {
			state_machine = "units/beings/player/first_person_base/state_machines/ranged/blunderbuss",
			wield_anim = "to_blunderbuss",
			wield_anim_no_ammo = "to_blunderbuss_noammo",
		}
		H.equal(policy.apply_template(template, anim_lookup), 3)
		local valid, reason = policy.template_contract(template, anim_lookup)
		H.truthy(valid, reason)
		for _, career in ipairs(policy.SALTZPYRE_CAREERS) do
			H.equal(template.wield_anim_career_3p[career], "to_repeater_pistol")
		end
		H.equal(template.wield_anim, "to_blunderbuss")
		H.equal(template.wield_anim_no_ammo, "to_blunderbuss_noammo")
		H.equal(template.state_machine,
			"units/beings/player/first_person_base/state_machines/ranged/blunderbuss")
		H.equal(template.wield_anim_career_3p.wh_priest, nil)
		H.equal(template.wield_anim_career_3p.es_mercenary, nil)
	end)

	H.test("CWV #760 fails closed when the resident animation contract is absent", function()
		local template = { wield_anim = "to_blunderbuss" }
		local count, reason = policy.apply_template(template, {})
		H.equal(count, 0)
		H.equal(reason, "network_event_unavailable")
		H.equal(template.wield_anim_career_3p, nil)
		local malformed = { wield_anim_career_3p = "invalid" }
		count, reason = policy.apply_template(malformed, anim_lookup)
		H.equal(count, 0)
		H.equal(reason, "career_map_invalid")
		H.equal(malformed.wield_anim_career_3p, "invalid")
		local valid, contract_reason = policy.template_contract(malformed, anim_lookup)
		H.equal(valid, false)
		H.equal(contract_reason, "career map invalid")
	end)

	H.test("CWV #760 preview resolver is exact item and receiver scoped", function()
		for _, career in ipairs(policy.SALTZPYRE_CAREERS) do
			H.equal(policy.preview_event(policy.ITEM_KEY, career), "to_repeater_pistol")
			H.equal(policy.runtime_event(policy.ITEM_KEY, career, anim_lookup),
				"to_repeater_pistol")
		end
		H.equal(policy.preview_event(policy.ITEM_KEY, "wh_priest"), nil)
		H.equal(policy.preview_event(policy.ITEM_KEY, "es_mercenary"), nil)
		H.equal(policy.preview_event("dr_deus_01", "wh_bountyhunter"), nil)
		H.equal(policy.runtime_event(policy.ITEM_KEY, "wh_bountyhunter", {}), nil)
	end)

	H.test("CWV #760 husk resolver requires exact semantic Outrider identity", function()
		H.equal(policy.husk_event({ variant_key = policy.ITEM_KEY },
			"wh_bountyhunter", anim_lookup), "to_repeater_pistol")
		H.equal(policy.husk_event({ variant_key = "dr_deus_01" },
			"wh_bountyhunter", anim_lookup), nil)
		H.equal(policy.husk_event(nil, "wh_bountyhunter", anim_lookup), nil)
		H.equal(policy.husk_event({ variant_key = policy.ITEM_KEY },
			"es_mercenary", anim_lookup), nil)
	end)

	H.test("CWV #760 dispatch and evidence fail closed with a hard cap", function()
		local events = {}
		local api = {
			alive = function(unit) return unit == "live" end,
			animation_event = function(unit, event)
				events[#events + 1] = unit .. ":" .. event
			end,
		}
		local ok, result = policy.dispatch_event("live", "to_repeater_pistol", api)
		H.truthy(ok)
		H.equal(result, "dispatched_unverified")
		H.equal(events[1], "live:to_repeater_pistol")
		ok, result = policy.dispatch_event("dead", "to_repeater_pistol", api)
		H.equal(ok, false)
		H.equal(result, "unit_not_alive")
		H.equal(#events, 1)

		policy._reset_evidence_for_tests()
		local lines = {}
		local logger = function(fmt, ...)
			lines[#lines + 1] = string.format(fmt, ...)
		end
		for i = 1, 80 do
			policy.emit_evidence(logger, "surface_" .. i, "wh_bountyhunter",
				"to_repeater_pistol", "result_" .. i .. string.rep("x", 300),
				"exact_identity")
		end
		H.equal(#lines, policy.EVIDENCE_LIMIT)
		H.truthy(lines[1]:find("visual=unverified", 1, true))
		H.truthy(#lines[1] < 500)
		H.equal(policy.emit_evidence(logger, "surface_1", "wh_bountyhunter",
			"to_repeater_pistol", "result_1" .. string.rep("x", 300),
			"exact_identity"), false)
	end)

	H.test("CWV #760 runtime regression owns template and preview invariants", function()
		local text = read(root .. "_cwv_regression_render.lua")
		H.truthy(text:find(
			'_rt_register("cwv_issue760_outrider_saltzpyre_repeater_stance"', 1, true))
		local main = read(root .. "character_weapon_variants.lua")
		local husk = read(root .. "_cwv_husk_path.lua")
		H.truthy(husk:find("outrider_animation.emit_evidence", 1, true))
		-- #1159: the inventory-preview
		-- replay moved verbatim into the keep/menu preview-surface owner. Follow
		-- the code instead of dropping the surface from this gate, and assert the
		-- entry kept no second copy that could replay the stance twice.
		local menu_preview = read(root .. "_cwv_menu_preview_owner.lua")
		H.truthy(menu_preview:find("outrider_animation.runtime_event", 1, true))
		H.truthy(menu_preview:find("outrider_animation.emit_evidence", 1, true))
		H.truthy(menu_preview:find('"inventory_preview"', 1, true))
		H.truthy(main:find('"inventory_preview"', 1, true) == nil,
			"entry must not keep a second inventory-preview stance replay")
	end)

	H.test("CWV #760 husk replay is exact semantic identity gated", function()
		local husk = read(root .. "_cwv_husk_path.lua")
		H.truthy(husk:find("outrider_animation.husk_event", 1, true))
		H.truthy(husk:find('"remote_husk_3p"', 1, true))
		H.truthy(husk:find('"exact_identity"', 1, true))
	end)
end
