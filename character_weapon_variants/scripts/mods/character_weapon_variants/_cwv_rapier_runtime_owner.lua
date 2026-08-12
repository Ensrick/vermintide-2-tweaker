local function install(mod, ctx)
	local _om = assert(ctx.om, "cwv rapier owner requires om")
	local _always_false = assert(ctx.always_false,
		"cwv rapier owner requires always_false")

	-- ============================================================
	-- Rapier template (modified fencing_sword_template_1)
	-- Saltzpyre's fencing-sword moveset cloned for Kruber. Pistol-shoot
	-- weapon special (action_three, kind="handgun") disabled via
	-- _always_false condition_func — keeps the action defined for
	-- state-machine / network consistency but it never fires. Same pattern
	-- as the tuskgor javelin auto-catch reload disable (v0.1.65).
	--
	-- 3P wield routes to Kruber's native to_1h_sword SM (the empire-soldier
	-- body authors no fencing-sword wield), and per-action remap covers
	-- fencing events not in 1h_sword's closed vocabulary.
	--
	-- ANIM ADDENDUM: 3P-only. 1P universal — see top-of-file ANIMATION
	-- ARCHITECTURE.
	-- ============================================================

	-- 3P remap — source (fencing_sword_template_1) → target
	-- (one_handed_swords_template_1, Kruber 1h sword vocabulary).
	-- Closed list for to_1h_sword (verified against 1h_swords.lua):
	--   charges:   attack_swing_charge_left, attack_swing_charge_right_pose,
	--              attack_swing_charge_left_pose
	--   strikes:   attack_swing_heavy, attack_swing_heavy_right,
	--              attack_swing_left_diagonal, attack_swing_right,
	--              attack_swing_down, attack_swing_right_diagonal
	--   universal: attack_push, parry_pose
	-- Source events already in target (attack_swing_right,
	-- attack_swing_right_diagonal, attack_push, parry_pose) need no entry.
	-- #284: rapier constructor + its two private 3P remap tables wrapped in a
	-- do..end so their top-level locals release after the block (Lua 5.1 200-local
	-- limit). `_always_false` (referenced inside) stays declared above the block.
	do
	local _RAPIER_ANIM_REMAP_3P = {
		-- Stab charge → heavy charge (closest charge anim).
		attack_swing_stab_charge = "attack_swing_charge_left",
		-- Stab strike → right_diagonal (closest forward-leaning strike).
		attack_swing_stab        = "attack_swing_right_diagonal",
		-- Source has plain attack_swing_left; target has _left_diagonal only.
		attack_swing_left        = "attack_swing_left_diagonal",
	}

	local _rapier_kruber_wield_3p = {
		es_mercenary      = "to_1h_sword",
		es_huntsman       = "to_1h_sword",
		es_knight         = "to_1h_sword",
		es_questingknight = "to_1h_sword",
	}

	local function _create_rapier_template()
		if not Weapons or not Weapons.fencing_sword_template_1 then
			mod:warning("fencing_sword_template_1 not found — Rapier template unavailable")
			return
		end
		if Weapons.rapier_template then return end

		local template = table.clone(Weapons.fencing_sword_template_1, true)

		-- Disable the pistol action and remove its ammo contract together. Keeping
		-- cloned ammo_data while omitting the left-hand pistol makes the stock HUD
		-- request ammo_system from a nil unit when this melee weapon occupies Grail
		-- Knight's second (slot_ranged) weapon slot (#807).
		_om.rapier_contract.disable_pistol(template, _always_false)

		-- Per-action 3P remap on every sub-action whose anim_event has a
		-- substitute. 3P-only — never write anim_event (1P).
		if template.actions then
			for _, action_group in pairs(template.actions) do
				if type(action_group) == "table" then
					for _, sub_action in pairs(action_group) do
						if type(sub_action) == "table"
								and sub_action.anim_event
								and _RAPIER_ANIM_REMAP_3P[sub_action.anim_event] then
							sub_action.anim_event_3p = _RAPIER_ANIM_REMAP_3P[sub_action.anim_event]
						end
					end
				end
			end
		end

		template.wield_anim_3p = "to_1h_sword"
		template.wield_anim_career_3p = template.wield_anim_career_3p or {}
		for k, v in pairs(_rapier_kruber_wield_3p) do
			template.wield_anim_career_3p[k] = v
		end

		Weapons.rapier_template = template

		-- Patch the BASE template's wield_anim_career_3p so the inventory
		-- previewer (HeroPreviewer reads BASE template, not our clone — see
		-- feedback_cwv_previewer_template_lookup.md) shows the right wield
		-- pose for Kruber careers. Scoped to es_* only — Saltzpyre careers
		-- fall through to original behavior (his body has the fencing wield
		-- authored natively).
		local base = Weapons.fencing_sword_template_1
		if base then
			base.wield_anim_career_3p = base.wield_anim_career_3p or {}
			for k, v in pairs(_rapier_kruber_wield_3p) do
				base.wield_anim_career_3p[k] = v
			end
		end

		mod:info("Created rapier_template (pistol-shoot disabled, 3p anim remap: %d entries, wield_3p=to_1h_sword for es_*)",
			3)
	end

	_create_rapier_template()
	end -- #284: end rapier constructor do..end block
end

return install
