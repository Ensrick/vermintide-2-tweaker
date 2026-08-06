-- _cwv_core_templates.lua -- Owns CWV core weapon-template/profile constructors.
--
-- This module receives every entry-owned engine table explicitly, installs the
-- original template constructors once in their original order, and returns only
-- the shared damage-profile clone used by later template families. It owns no
-- hooks, commands, appearance decisions, or peer transport.
--
-- Owned by: character_weapon_variants.lua entry point.
-- Consumed via: one injected mod:dofile call at the original constructor boundary.

local _clone_damage_profile

return function(mod, deps)
	deps = deps or {}
	local _om = deps.om
	local Weapons = deps.Weapons
	local DamageProfileTemplates = deps.DamageProfileTemplates
	local PowerLevelTemplates = deps.PowerLevelTemplates
	local NetworkLookup = deps.NetworkLookup
	local ItemMasterList = deps.ItemMasterList
	local AttachmentNodeLinking = deps.AttachmentNodeLinking
	local Projectiles = deps.Projectiles
	local ActionTemplates = deps.ActionTemplates
	local printf = deps.printf

	assert(type(_om) == "table", "_cwv_core_templates requires deps.om")
-- ============================================================
-- Imperial Longsword template (modified Kruber Greatsword template)
-- -15% damage, +15% speed, +15% cleave, -15% stagger
-- ============================================================

-- CLARIFY: Damage-profile clone. Each cwv template clone calls this once per
-- sub-action's damage_profile string; the function is idempotent (early-return
-- on existing clone) so the same source profile shared across multiple
-- sub-actions is cloned only once.
-- Prefix-collision risk: prefixes are tied to the specific multiplier set
-- ("cwv_il_" = imperial longsword, "cwv_ess_" = elven sword+shield). DO NOT
-- reuse a prefix with different `mults` — the second caller will reuse the
-- first caller's already-mutated PowerLevelTemplates entry and silently inherit
-- the wrong multipliers.
_clone_damage_profile = function(source_name, prefix, mults)
	if not DamageProfileTemplates then return source_name end
	local source = DamageProfileTemplates[source_name]
	if not source then return source_name end

	local new_name = prefix .. source_name
	_om._record_cwv_dp_source(new_name, source_name)   -- issue 423 wire-safe map
	if DamageProfileTemplates[new_name] then return new_name end

	local dmg_mult = mults.damage or 1
	local stg_mult = mults.stagger or 1
	local clv_mult = mults.cleave or 1

	local clone = table.clone(source, true)

	if type(clone.cleave_distribution) == "string" and PowerLevelTemplates then
		local key = clone.cleave_distribution
		local src = PowerLevelTemplates[key]
		if src then
			local new_key = prefix .. key
			if not PowerLevelTemplates[new_key] then
				local c = table.clone(src, true)
				if c.attack then c.attack = c.attack * clv_mult end
				if c.impact then c.impact = c.impact * clv_mult end
				PowerLevelTemplates[new_key] = c
			end
			clone.cleave_distribution = new_key
		end
	end

	if type(clone.default_target) == "string" and PowerLevelTemplates then
		local key = clone.default_target
		local src = PowerLevelTemplates[key]
		if src then
			local new_key = prefix .. key
			if not PowerLevelTemplates[new_key] then
				local c = table.clone(src, true)
				if c.power_distribution then
					if c.power_distribution.attack then c.power_distribution.attack = c.power_distribution.attack * dmg_mult end
					if c.power_distribution.impact then c.power_distribution.impact = c.power_distribution.impact * stg_mult end
				end
				PowerLevelTemplates[new_key] = c
			end
			clone.default_target = new_key
		end
	end

	if type(clone.targets) == "string" and PowerLevelTemplates then
		local key = clone.targets
		local src = PowerLevelTemplates[key]
		if src then
			local new_key = prefix .. key
			if not PowerLevelTemplates[new_key] then
				local c = table.clone(src, true)
				for _, target in ipairs(c) do
					if target.power_distribution then
						if target.power_distribution.attack then target.power_distribution.attack = target.power_distribution.attack * dmg_mult end
						if target.power_distribution.impact then target.power_distribution.impact = target.power_distribution.impact * stg_mult end
					end
				end
				PowerLevelTemplates[new_key] = c
			end
			clone.targets = new_key
		end
	end

	if type(clone.critical_strike) == "string" and PowerLevelTemplates then
		local key = clone.critical_strike
		local src = PowerLevelTemplates[key]
		if src then
			local new_key = prefix .. key
			if not PowerLevelTemplates[new_key] then
				local c = table.clone(src, true)
				if c.power_distribution then
					if c.power_distribution.attack then c.power_distribution.attack = c.power_distribution.attack * dmg_mult end
					if c.power_distribution.impact then c.power_distribution.impact = c.power_distribution.impact * stg_mult end
				end
				PowerLevelTemplates[new_key] = c
			end
			clone.critical_strike = new_key
		end
	end

	DamageProfileTemplates[new_name] = clone

	if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, new_name) then
		local tbl = NetworkLookup.damage_profiles
		local idx = #tbl + 1
		rawset(tbl, idx, new_name)
		rawset(tbl, new_name, idx)
	end

	return new_name
end

-- ============================================================
-- Infantry Spear (Kerillian spear moveset on Kruber's unshielded CW spear)
-- ============================================================
do
	local infantry = _om.infantry_spear

	local function _create_infantry_spear_template()
		if not Weapons or not Weapons.two_handed_spears_elf_template_1 then
			mod:warning("two_handed_spears_elf_template_1 not found - Infantry Spear unavailable")
			return
		end
		if Weapons[infantry.TEMPLATE_KEY] then return end

		local template = table.clone(Weapons.two_handed_spears_elf_template_1, true)
		for _, action_group in pairs(template.actions or {}) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						local scaled = infantry.scaled_attack_time(
							sub_action.kind, sub_action.anim_time_scale)
						if scaled ~= nil then sub_action.anim_time_scale = scaled end
						-- Only direct attack profiles are tuned. The spear's ordinary
						-- push uses damage_profile_inner/outer and remains vanilla.
						if sub_action.damage_profile then
							sub_action.damage_profile = _clone_damage_profile(
								sub_action.damage_profile, "cwv_infantry_spear_", {
									damage = infantry.DAMAGE_MULT,
									stagger = infantry.STAGGER_MULT,
									cleave = infantry.CLEAVE_MULT,
								})
						end
					end
				end
			end
		end

		-- 3P only. Kruber's existing WT elf-spear port enters the polearm
		-- graph; the two per-action substitutions are applied career-locally
		-- by `_cross_access_action_remap` before vanilla replicates the event.
		-- Keeping them out of shared action fields preserves Kerillian when WT
		-- enables this item on its source owner.
		template.wield_anim_3p = "to_polearm"
		template.wield_anim_career_3p = template.wield_anim_career_3p or {}
		for _, career in ipairs({
			"es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
		}) do
			template.wield_anim_career_3p[career] = "to_polearm"
		end
		Weapons[infantry.TEMPLATE_KEY] = template
		-- CWV entries inherit `.name = we_spear`; inventory preview template
		-- lookup therefore resolves the base table. Patch only Kruber's 3P
		-- career stance so the preview and runtime use the same polearm graph.
		local preview_base = Weapons.two_handed_spears_elf_template_1
		preview_base.wield_anim_career_3p = preview_base.wield_anim_career_3p or {}
		for _, career in ipairs({
			"es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
		}) do
			preview_base.wield_anim_career_3p[career] = "to_polearm"
		end
		mod:info("Created %s (speed=%.1f%% damage=%.1f%% stagger=%.1f%% cleave=%.1f%%)",
			infantry.TEMPLATE_KEY, infantry.SPEED_MULT * 100,
			infantry.DAMAGE_MULT * 100, infantry.STAGGER_MULT * 100,
			infantry.CLEAVE_MULT * 100)
	end

	_create_infantry_spear_template()
	-- #620 CWV expands the native Tuskgor Spear to Foot Knight. WT may still
	-- expose its per-career checkbox, but CWV's authored default is ON whenever
	-- this style family is present. No item instance is granted.
	_om._ensure_tuskgor_foot_knight = function()
		local tuskgor = ItemMasterList and rawget(ItemMasterList, "es_2h_heavy_spear")
		if tuskgor then
			tuskgor.cwv_combat_style_family = "spear"
			tuskgor.cwv_combat_style_ready = true
			tuskgor.can_wield = tuskgor.can_wield or {}
			if not table.contains(tuskgor.can_wield, "es_knight") then
				tuskgor.can_wield[#tuskgor.can_wield + 1] = "es_knight"
			end
		end
	end
	_om._ensure_tuskgor_foot_knight()
end

-- ANIM ADDENDUM: this function only touches stats + 3P fields. 1P animations
-- are universal (see top-of-file ANIMATION ARCHITECTURE) and need no work.
-- #284: The Imperial Longsword (2H) and Imperial Longsword + Shield
-- constructors share the _IL_* multipliers, so both are scoped in one do..end
-- (a sibling to the per-template blocks below) to release their top-level
-- locals back to the main chunk. Lua 5.1 caps any function (incl. the main
-- chunk) at 200 simultaneously-active locals. Both constructors are still
-- defined and invoked exactly once, in original order, inside the block. The
-- shared `_clone_damage_profile` helper stays OUTSIDE (declared above) because
-- later weapon families reference it too.
do  -- #284: scope imperial-longsword (2H + shield) template locals off the top-level chunk (>200-local limit)
local _IL_DAMAGE_MULT  = _om.combat_style_policy.IMPERIAL_DAMAGE_MULT
local _IL_SPEED_MULT   = _om.combat_style_policy.IMPERIAL_SPEED_MULT
local _IL_CLEAVE_MULT  = _om.combat_style_policy.IMPERIAL_CLEAVE_MULT
local _IL_STAGGER_MULT = _om.combat_style_policy.IMPERIAL_STAGGER_MULT

local function _create_imperial_longsword_template()
	if not Weapons or not Weapons.two_handed_swords_template_1 then
		mod:warning("two_handed_swords_template_1 not found — Imperial Longsword stat modifications unavailable")
		return
	end
	if Weapons.imperial_longsword_template then return end

	-- #644: the Imperial style is deliberately derived from native Greatsword.
	-- Bretonnian Longsword remains the next distinct action graph in the family.
	local template, err = _om.combat_style_policy.build_imperial_template(Weapons,
		function(value) return table.clone(value, true) end, _clone_damage_profile)
	if not template then
		mod:warning("Imperial Longsword template unavailable: %s", tostring(err))
		return
	end

	Weapons.imperial_longsword_template = template
	mod:info("[cwv:644] registered Imperial Longsword style from Kruber Greatsword (dmg=%.0f%% spd=%.0f%% cleave=%.0f%% stagger=%.0f%%)",
		_IL_DAMAGE_MULT * 100, _IL_SPEED_MULT * 100, _IL_CLEAVE_MULT * 100, _IL_STAGGER_MULT * 100)
end

_create_imperial_longsword_template()

-- ============================================================
-- Imperial Longsword + Shield template (modified one_handed_sword_shield_template_2)
-- Same tune as the 2H Imperial Longsword (-15% damage, +15% speed, +15% cleave,
-- -15% stagger), but applied ONLY to sword-swing sub-actions. Shield bashes
-- (shield_slam*, shield_push), the block action, and the universal push
-- (medium_push) are left at vanilla so the shield half behaves like a normal
-- shield. Filter: skip sub_action if `kind == "block"` OR its damage_profile
-- starts with "shield_". The push baseline uses `damage_profile_inner` /
-- `damage_profile_outer` (no plain `damage_profile`), so it's naturally skipped.
--
-- Prefix `cwv_il_` is intentionally REUSED from the 2H Imperial Longsword: the
-- multipliers are identical, the damage_profile names don't overlap (bastard
-- sword uses 2H slashing profiles, bret sword+shield uses 1h slashing profiles),
-- and `_clone_damage_profile` is idempotent within a prefix.
local function _create_imperial_longsword_shield_template()
	if not Weapons or not Weapons.one_handed_sword_shield_template_2 then
		mod:warning("one_handed_sword_shield_template_2 not found — Imperial Longsword + Shield stat mods unavailable")
		return
	end
	if Weapons.imperial_longsword_shield_template then return end

	local template = table.clone(Weapons.one_handed_sword_shield_template_2, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						local dp = sub_action.damage_profile
						local is_shield_action = (sub_action.kind == "block")
							or (type(dp) == "string" and dp:sub(1, 7) == "shield_")
						if not is_shield_action then
							if sub_action.anim_time_scale then
								sub_action.anim_time_scale = sub_action.anim_time_scale * _IL_SPEED_MULT
							end
							if sub_action.damage_profile then
								sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_il_", {
									damage = _IL_DAMAGE_MULT, stagger = _IL_STAGGER_MULT, cleave = _IL_CLEAVE_MULT,
								})
							end
						end
					end
				end
			end
		end
	end

	Weapons.imperial_longsword_shield_template = template
	mod:info("Created imperial_longsword_shield_template (sword-only: dmg=%.0f%% spd=%.0f%% cleave=%.0f%% stagger=%.0f%%)",
		_IL_DAMAGE_MULT * 100, _IL_SPEED_MULT * 100, _IL_CLEAVE_MULT * 100, _IL_STAGGER_MULT * 100)
end

_create_imperial_longsword_shield_template()
end  -- #284: end imperial-longsword (2H + shield) do-block

-- ============================================================
-- Elven Sword+Shield template (modified one_handed_sword_shield_template_1)
-- +15% speed, -15% stagger
--
-- ANIM ADDENDUM: _ess_anim_remap remaps 3P body events ONLY (anim_event_3p
-- field — see _create_elven_sword_shield_template body). The 1P side is
-- universal across characters and needs no remapping — see top-of-file
-- ANIMATION ARCHITECTURE.
-- ============================================================

do  -- #284: scope elven-sword-shield template locals off the top-level chunk (>200-local limit)
local _ESS_SPEED_MULT   = 1.15
local _ESS_STAGGER_MULT = 0.85

-- 3P body event remap: keys are events the cloned template fires; values are
-- substitutes that exist on the empire-soldier 3P skeleton. 1P unaffected.
local _ess_anim_remap = {
	attack_swing_left_diagonal     = "attack_swing_left",
	attack_swing_charge            = "attack_swing_charge_stab",
	attack_swing_heavy             = "attack_push",
	attack_swing_heavy_right       = "attack_swing_heavy_down_right",
	attack_swing_charge_right_pose = "attack_swing_charge_right_diagonal_pose",
}

-- ANIM ADDENDUM: this function only touches stats + 3P fields. 1P is universal.
local function _create_elven_sword_shield_template()
	if not Weapons or not Weapons.one_handed_sword_shield_template_1 then
		mod:warning("one_handed_sword_shield_template_1 not found — Elven Sword+Shield stat modifications unavailable")
		return
	end
	if Weapons.elven_sword_shield_template then return end

	local template = table.clone(Weapons.one_handed_sword_shield_template_1, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						if sub_action.anim_time_scale then
							sub_action.anim_time_scale = sub_action.anim_time_scale * _ESS_SPEED_MULT
						end
						if sub_action.damage_profile then
							sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_ess_", {
								stagger = _ESS_STAGGER_MULT,
							})
						end
						if sub_action.anim_event and _ess_anim_remap[sub_action.anim_event] then
							sub_action.anim_event_3p = _ess_anim_remap[sub_action.anim_event]
						end
					end
				end
			end
		end
	end

	template.wield_anim_3p = "to_1h_spear_shield"
	template.wield_anim_career_3p = {
		we_waywatcher  = "to_1h_spear_shield",
		we_maidenguard = "to_1h_spear_shield",
		we_shade       = "to_1h_spear_shield",
		we_thornsister = "to_1h_spear_shield",
	}

	Weapons.elven_sword_shield_template = template

	-- CLARIFY: Per memory note feedback_cwv_previewer_template_lookup.md, the
	-- inventory previewer resolves item templates via item_data.name (= base
	-- weapon key for cwv items), so it reads one_handed_sword_shield_template_1
	-- NOT our elven_sword_shield_template. Patch the BASE template's
	-- wield_anim_career_3p so the menu preview pose is correct for elf careers.
	-- Scoped to elf careers only — Kruber/etc. fall through to original behavior.
	local elf_wield_3p = {
		we_waywatcher  = "to_1h_spear_shield",
		we_maidenguard = "to_1h_spear_shield",
		we_shade       = "to_1h_spear_shield",
		we_thornsister = "to_1h_spear_shield",
	}
	local base = Weapons.one_handed_sword_shield_template_1
	if base then
		base.wield_anim_career_3p = base.wield_anim_career_3p or {}
		for k, v in pairs(elf_wield_3p) do
			base.wield_anim_career_3p[k] = v
		end
	end
	-- QUESTION: Attack-event remaps from _ess_anim_remap are only applied to the
	-- cloned template. The previewer reads the BASE template (see comment above),
	-- so previewer attack animations would NOT pick up the remap. Currently this
	-- is fine because the previewer doesn't fire attack events — only the
	-- wield_anim. If that changes, the attack remaps must also be patched onto
	-- the base template (probably via career_anim_event tables).

	mod:info("Created elven_sword_shield_template (spd=%.0f%% stagger=%.0f%%, %d 3p anim remaps, wield_3p=to_1h_spear_shield) + patched base template career_3p table for elf careers",
		_ESS_SPEED_MULT * 100, _ESS_STAGGER_MULT * 100, 5)
end

_create_elven_sword_shield_template()
end  -- #284: end elven-sword-shield do-block

-- ============================================================
-- Imperial Dual Swords template (modified dual_wield_swords_template_1)
-- −20% attack speed, +15% power (damage + stagger).
-- 3P anim redirect to Kruber's dual_wield_hammer_sword_template.
--
-- ANIM ADDENDUM: All anim work below is 3P-only (anim_event_3p,
-- wield_anim_3p, wield_anim_career_3p). 1P is universal — see top-of-file
-- ANIMATION ARCHITECTURE.
-- ============================================================

do  -- #284: scope imperial-dual-swords template locals off the top-level chunk (>200-local limit)
local _IDS_SPEED_MULT = 0.80
local _IDS_POWER_MULT = 1.15

-- 3P body event remap: elf dual-sword events with no 1:1 on Kruber's
-- dual_wield_hammer_sword_template. Substitutes are picked from the empire-
-- soldier 3P skeleton's authored vocabulary so a valid clip plays. Same-named
-- events (attack_swing_left, attack_swing_right, attack_swing_left_diagonal,
-- etc.) need no remap — Kruber's mace+sword template uses those same names
-- and they're authored on the empire-soldier 3P skeleton. 1P unaffected.
--
-- Heavy combo release reversed on 3P: H1 release (source anim_event
-- attack_swing_heavy_left_diagonal) plays right-diagonal on the body;
-- H2 release (source attack_swing_heavy_right) plays left-diagonal. 1P keeps
-- the source events unchanged.
--
-- push_stab → attack_swing_right: a native dual_hammer_sword event (line
-- 1082 of dual_wield_hammer_sword.lua), a fast lateral swing with the lead
-- sword. Picked after the SM has no visible stab — investigation summary:
--
-- The dual_hammer_sword 3P sub-graph doesn't author a visible stab clip;
-- the empire-soldier skeleton's stab clips live in the 1h_sword_shield
-- sub-graph. Attempts to reach them failed:
--   1. attack_swing_stab as a plain anim_event_3p remap → force3p reports
--      exists=true but no visible clip plays (stub transition).
--   2. SM-switch graft (v0.1.89) via pre_action_anim_event =
--      "to_1h_sword_shield" + anim_end_event_3p = "to_dual_hammer_sword_es"
--      → the wield-change clip eats the damage window AND push_stab's
--      anim_end_event_condition_func returns false on action_complete
--      which gates ALL end events including our return transition — body
--      got stuck in 1h_sword_shield sub-graph permanently.
--   3. Full SM switch (change template's wield_anim_3p to to_1h_sword_shield)
--      → gives visible stab but breaks the dual-wield idle/wield identity
--      (left sword renders in shield-defensive stance). Reference pattern:
--      Peregrinaje's markus_torch_and_shield uses exactly this approach
--      with model aligned to the SM (torch fits axe+shield); not applicable
--      to two swords without a model rework.
-- Decision: stay native to dual_hammer_sword, use a non-stab clip that reads
-- as a committed forward strike. attack_swing_right reads as a quick
-- follow-up swing after the push.
local _ids_anim_remap = {
	-- Charge for H1 from idle — matches H1's swapped strike direction.
	-- Elf source `default` sub-action fires attack_swing_charge_diagonal; we
	-- route to charge_right (not charge_left) so the wind-up direction
	-- aligns with H1's release (heavy_right_diagonal). Cock right → strike
	-- right. Was incoherent (left cock, right strike) prior to v0.1.102.
	attack_swing_charge_diagonal     = "attack_swing_charge_right",
	-- Heavy combo release reversed.
	attack_swing_heavy_left_diagonal = "attack_swing_heavy_right_diagonal",
	attack_swing_heavy_right         = "attack_swing_heavy_left_diagonal",
	-- Push-attack — see comment block above.
	push_stab                        = "attack_swing_right",
}

-- ANIM ADDENDUM: this function touches stats + 3P fields. 1P is universal.
local function _create_imperial_dual_swords_template()
	if not Weapons or not Weapons.dual_wield_swords_template_1 then
		mod:warning("dual_wield_swords_template_1 not found — Imperial Dual Swords template unavailable")
		return
	end
	if Weapons.imperial_dual_swords_template then return end

	local template = table.clone(Weapons.dual_wield_swords_template_1, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						if sub_action.anim_time_scale then
							sub_action.anim_time_scale = sub_action.anim_time_scale * _IDS_SPEED_MULT
						end
						if sub_action.damage_profile then
							sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_eds_", {
								damage = _IDS_POWER_MULT, stagger = _IDS_POWER_MULT,
							})
						end
						if sub_action.anim_event and _ids_anim_remap[sub_action.anim_event] then
							sub_action.anim_event_3p = _ids_anim_remap[sub_action.anim_event]
						end
					end
				end
			end
		end
	end

	template.wield_anim_3p = "to_dual_hammer_sword_es"
	template.wield_anim_career_3p = {
		es_mercenary      = "to_dual_hammer_sword_es",
		es_huntsman       = "to_dual_hammer_sword_es",
		es_knight         = "to_dual_hammer_sword_es",
		es_questingknight = "to_dual_hammer_sword_es",
	}

	Weapons.imperial_dual_swords_template = template

	-- Same patch pattern as _create_elven_sword_shield_template: the inventory
	-- previewer reads the BASE template (dual_wield_swords_template_1), not our
	-- clone, so patch the base template's wield_anim_career_3p for Kruber careers
	-- to keep the menu preview pose correct. Scoped to es_* only — elf careers
	-- fall through to the original wield anim.
	local kruber_wield_3p = {
		es_mercenary      = "to_dual_hammer_sword_es",
		es_huntsman       = "to_dual_hammer_sword_es",
		es_knight         = "to_dual_hammer_sword_es",
		es_questingknight = "to_dual_hammer_sword_es",
	}
	local base = Weapons.dual_wield_swords_template_1
	if base then
		base.wield_anim_career_3p = base.wield_anim_career_3p or {}
		for k, v in pairs(kruber_wield_3p) do
			base.wield_anim_career_3p[k] = v
		end
	end

	mod:info("Created imperial_dual_swords_template (spd=%.0f%% power=%.0f%%, 3p anim redirect to mace+sword, wield_3p=to_dual_hammer_sword_es)",
		_IDS_SPEED_MULT * 100, _IDS_POWER_MULT * 100)
end

_create_imperial_dual_swords_template()
end  -- #284: end imperial-dual-swords do-block

-- ============================================================
-- Cudgel template (one_hand_falchion_template_1 — recoloured to blunt)
-- ============================================================
-- Saltzpyre's falchion moveset (charge-and-release light combo, smiter
-- heavy) but every cutting hit becomes a crushing one. Cosmetic stays
-- the empire mace mesh — only the moveset, damage_type, and impact
-- effects/sounds change.
--
-- Damage profile swap: the falchion uses one of three slashing profile
-- families across its sweeps. Each maps to a vanilla blunt cousin with
-- the same cleave/range/stagger shape:
--
--   light_slashing_axe_linesman       → light_blunt_tank_diag    (light combo sweeps)
--   light_slashing_axe_linesman_upper → light_blunt_tank_upper   (light upper variants)
--   medium_slashing_smiter_1h         → medium_blunt_smiter_1h   (heavy attack)
--
-- All three blunt targets are vanilla DamageProfileTemplates entries
-- (see damage_profile_templates.lua:253+ / 430+). Push profiles
-- (medium_push / light_push) are universal and stay untouched.
--
-- Effects/sounds: hit_effect → melee_hit_hammers_1h, slashing_hit
-- swoosh/impact → blunt_hit (and _armour). display_unit and block-arc
-- sound also swapped so the inventory rig and parry foley match a
-- mace, not a falchion.
do  -- #284: scope cudgel template locals off the top-level chunk (>200-local limit)
local _CUDGEL_DAMAGE_PROFILE_SWAP = {
	light_slashing_axe_linesman       = "light_blunt_tank_diag",
	light_slashing_axe_linesman_upper = "light_blunt_tank_upper",
	medium_slashing_smiter_1h         = "medium_blunt_smiter_1h",
}

local _CUDGEL_HIT_EFFECT_SWAP = {
	melee_hit_axes_1h  = "melee_hit_hammers_1h",
	melee_hit_sword_1h = "melee_hit_hammers_1h",
}

local _CUDGEL_IMPACT_SOUND_SWAP = {
	slashing_hit         = "blunt_hit",
	slashing_hit_armour  = "blunt_hit_armour",
}

local function _create_cudgel_template()
	if not Weapons or not Weapons.one_hand_falchion_template_1 then
		mod:warning("one_hand_falchion_template_1 not found — Cudgel template unavailable")
		return
	end
	if Weapons.cudgel_template then return end

	local template = table.clone(Weapons.one_hand_falchion_template_1, true)

	local swapped, hit_swapped, sound_swapped = 0, 0, 0
	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						local dp = sub_action.damage_profile
						if dp and _CUDGEL_DAMAGE_PROFILE_SWAP[dp] then
							sub_action.damage_profile = _CUDGEL_DAMAGE_PROFILE_SWAP[dp]
							swapped = swapped + 1
						end
						local hit = sub_action.hit_effect
						if hit and _CUDGEL_HIT_EFFECT_SWAP[hit] then
							sub_action.hit_effect = _CUDGEL_HIT_EFFECT_SWAP[hit]
							hit_swapped = hit_swapped + 1
						end
						local imp = sub_action.impact_sound_event
						if imp and _CUDGEL_IMPACT_SOUND_SWAP[imp] then
							sub_action.impact_sound_event = _CUDGEL_IMPACT_SOUND_SWAP[imp]
							sound_swapped = sound_swapped + 1
						end
						local nd = sub_action.no_damage_impact_sound_event
						if nd and _CUDGEL_IMPACT_SOUND_SWAP[nd] then
							sub_action.no_damage_impact_sound_event = _CUDGEL_IMPACT_SOUND_SWAP[nd]
						end
					end
				end
			end
		end
	end

	-- Inventory / preview shows on a hammer display rig (mace mesh sits in
	-- the hammer cradle), not the falchion's. Block-arc swoosh swapped
	-- to the wood-block blunt foley used by 1h hammers.
	template.display_unit = "units/weapons/weapon_display/display_1h_hammer"
	template.sound_event_block_within_arc = "weapon_foley_blunt_1h_block_wood"

	Weapons.cudgel_template = template
	mod:info("Created cudgel_template (one_hand_falchion_template_1 → blunt: %d damage profiles, %d hit effects, %d impact sounds swapped)",
		swapped, hit_swapped, sound_swapped)
end

_create_cudgel_template()
end  -- #284: end cudgel do-block

-- ============================================================
-- Sword and Mace template — INVERSE of dual_wield_hammer_sword
-- Native Kruber mace+sword has: mace in RIGHT hand, sword in LEFT hand.
-- Inverse:                       sword in RIGHT hand, mace in LEFT hand.
--
-- The variant def sets right_hand_unit = sword, left_hand_unit = mace.
-- Sub-actions in the cloned template have weapon_action_hand = "right" /
-- "left" / "both" — we walk them and swap damage profile / hit effect /
-- impact sound fields so that:
--   * Right-hand strikes (was mace=blunt) now play sword/slashing
--   * Left-hand strikes  (was sword=slashing) now play mace/blunt
--   * Both-hand strikes:  swap damage_profile_left ↔ damage_profile_right
--                         where they differ (so each hand's damage type
--                         follows whichever weapon is in that hand now).
--
-- Per-hand `range_mod` override (v0.1.163): the dual-wield baseline is
-- shorter than the 1h equivalents (1.1 / 1.15 vs the 1h templates' 1.2),
-- but the user wants each weapon to feel like its 1h source. Override
-- per-hand sweeps to match `es_1h_sword` / `es_1h_mace` light-attack reach.
-- See `_SAM_HAND_RANGE_MOD` below for the values and rationale.
--
-- ANIM ADDENDUM: the underlying anim events / state machine are unchanged —
-- the body still goes through `to_dual_hammer_sword_es` and plays the same
-- dual-wield clips. Only damage / sound / hit-effect / range data per-action swaps.
-- ============================================================

-- Right-hand strike fields (was mace=blunt → sword=slashing).
do  -- #284: scope sword-and-mace template locals off the top-level chunk (>200-local limit)
local _SAM_RIGHT_HAND_SWAP = {
	damage_profile = {
		light_blunt_tank_diag = "light_slashing_linesman",
	},
	hit_effect = {
		melee_hit_hammers_1h = "melee_hit_sword_1h",
	},
	impact_sound_event = {
		blunt_hit = "slashing_hit",
	},
	no_damage_impact_sound_event = {
		blunt_hit_armour = "slashing_hit_armour",
	},
}

-- Left-hand strike fields (was sword=slashing → mace=blunt).
local _SAM_LEFT_HAND_SWAP = {
	damage_profile = {
		light_slashing_linesman = "light_blunt_tank_diag",
	},
	hit_effect = {
		melee_hit_sword_1h = "melee_hit_hammers_1h",
	},
	impact_sound_event = {
		slashing_hit = "blunt_hit",
	},
	no_damage_impact_sound_event = {
		slashing_hit_armour = "blunt_hit_armour",
	},
}

-- Per-hand `range_mod` override. range_mod is per-sub-action (each sweep has its
-- own value), so the reach overhaul is per-hit, not template-level.
--
-- Vanilla `dual_wield_hammer_sword` is a close-quarters dual-wield: right-hand
-- mace sweeps run at 1.15 and left-hand sword sweeps at 1.1 — shorter than the
-- 1h variants because both arms are committed and the wielder reads "tighter
-- box". Our variant flips the hands but the user wants each weapon's reach to
-- match its single-hand source instead of the tighter dual-wield baseline:
--
--   right hand (sword in our variant) → 1h_swords light_attack reach (1.2)
--   left hand  (mace  in our variant) → 1h_hammers light_attack reach (1.2)
--
-- Both numerically land at 1.2 because that's what each 1h template uses for
-- its light attacks (the heavies in 1h_swords go up to 1.25 and in 1h_hammers
-- to 1.3, but every per-hand sweep in dual_wield_hammer_sword is a LIGHT
-- attack — the heavies are `weapon_action_hand = "both"`, left untouched here
-- since they involve both weapons swung together).
--
-- "both"-hand sweeps, push, and block don't have a sword/mace assignment, so
-- they're absent from this map and keep the vanilla dual-wield range.
local _SAM_HAND_RANGE_MOD = {
	right = 1.2,  -- matches es_1h_sword light_attack range_mod (1h_swords.lua light_attack actions)
	left  = 1.2,  -- matches es_1h_mace  light_attack range_mod (1h_hammers.lua light_attack actions)
}

local function _sam_apply_field_swaps(sub_action, swaps)
	for field, swap_map in pairs(swaps) do
		local current = sub_action[field]
		if current and swap_map[current] then
			sub_action[field] = swap_map[current]
		end
	end
end

local function _create_sword_and_mace_template()
	if not Weapons or not Weapons.dual_wield_hammer_sword_template then
		mod:warning("dual_wield_hammer_sword_template not found — Sword and Mace template unavailable")
		return
	end
	if Weapons.sword_and_mace_template then return end

	local template = table.clone(Weapons.dual_wield_hammer_sword_template, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						local hand = sub_action.weapon_action_hand
						if hand == "right" then
							_sam_apply_field_swaps(sub_action, _SAM_RIGHT_HAND_SWAP)
						elseif hand == "left" then
							_sam_apply_field_swaps(sub_action, _SAM_LEFT_HAND_SWAP)
						elseif hand == "both" then
							-- For dual-hand strikes, swap left/right damage profile
							-- references where they differ (so left=mace and
							-- right=sword damage types follow the new hand
							-- placement).
							local pl = sub_action.damage_profile_left
							local pr = sub_action.damage_profile_right
							if pl and pr and pl ~= pr then
								sub_action.damage_profile_left  = pr
								sub_action.damage_profile_right = pl
							end
						end
						-- Per-hand reach override (independent of damage/sound swaps).
						-- Only sweeps have range_mod authored; we guard on its presence
						-- so non-sweep sub-actions (push, block_break, etc.) don't get
						-- a range_mod field accidentally introduced.
						if sub_action.range_mod and _SAM_HAND_RANGE_MOD[hand] then
							sub_action.range_mod = _SAM_HAND_RANGE_MOD[hand]
						end
					end
				end
			end
		end
	end

	Weapons.sword_and_mace_template = template
	mod:info("Created sword_and_mace_template (inverse of dual_wield_hammer_sword: damage/sound/effect swap by hand; per-hand range_mod = right %.2f / left %.2f)",
		_SAM_HAND_RANGE_MOD.right, _SAM_HAND_RANGE_MOD.left)
end

_create_sword_and_mace_template()
end  -- #284: end sword-and-mace do-block

-- ============================================================
-- Shortsword template (modified one_handed_daggers_template_1)
-- −20% attack speed, +15% power (damage + stagger).
-- Fire DoT removed: burning damage profiles swapped to non-burning slashing
-- analogs. Slam-specific aoe/target damage profile fields are nilled out
-- because no non-burning slam analog exists for Sienna's body — the heavy
-- slam loses its AoE component but the visual + main-target damage remain.
--
-- ANIM ADDENDUM: native template applies on Sienna's bright_wizard body — no
-- anim work needed. 1P universal across characters.
-- ============================================================

do  -- #284: scope shortsword template locals off the top-level chunk (>200-local limit)
local _SHORTSWORD_SPEED_MULT = 0.92
local _SHORTSWORD_POWER_MULT = 1.15

-- Burning damage profiles → non-burning analogs. `false` means "remove the
-- field entirely" (used for AoE/target slam fields with no clean non-burning
-- analog — see header for the AoE-loss caveat).
-- v0.1.151 used `medium_slashing_linesman_fencer` as the slam swap — that
-- name DOES NOT exist in DamageProfileTemplates. NetworkLookup.damage_profiles
-- is a strict-lookup table that crashes on missing keys, so heavy_attack_left
-- fire crashed the game. Fixed v0.1.152: use `medium_slashing_linesman`
-- (real, heavy slashing — closest non-burning analog by damage shape).
local _SHORTSWORD_DAMAGE_PROFILE_SWAP = {
	dagger_burning_slam_fencer        = "medium_slashing_linesman",
	dagger_burning_slam_fencer_aoe    = false,
	dagger_burning_slam_target_fencer = false,
	medium_burning_smiter_stab_H      = "medium_slashing_smiter_stab",
}

-- Fire-themed FX/sound fields → sword-themed analogs. The dagger's burning
-- heavies hardcode hit_effect = "staff_spark" + fire_hit sounds at the
-- sub-action level. v0.1.155 left these untouched and the engine crashed
-- when `World.create_particles("fx/wpnfx_staff_spark_impact")` fired during
-- a sweep on Kruber's body — the staff_spark FX package isn't loaded for
-- empire-soldier wielders. Fixed v0.1.156 by swapping these fields too so
-- the shortsword reads as steel-on-target (no fire visuals or sounds).
local _SHORTSWORD_FX_SWAP = {
	hit_effect = {
		staff_spark = "melee_hit_sword_1h",
	},
	impact_sound_event = {
		fire_hit = "slashing_hit",
	},
	armor_impact_sound_event = {
		fire_hit = "slashing_hit",
	},
	no_damage_impact_sound_event = {
		fire_hit_armour = "slashing_hit_armour",
	},
}

local function _create_shortsword_template()
	if not Weapons or not Weapons.one_handed_daggers_template_1 then
		mod:warning("one_handed_daggers_template_1 not found — Shortsword template unavailable")
		return
	end
	if Weapons.shortsword_template then return end

	local template = table.clone(Weapons.one_handed_daggers_template_1, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						if sub_action.anim_time_scale then
							sub_action.anim_time_scale = sub_action.anim_time_scale * _SHORTSWORD_SPEED_MULT
						end
						-- Step 1: swap burning damage profiles to non-burning
						-- analogs (or remove for AoE/target slam fields).
						-- Order matters — must run BEFORE _clone_damage_profile
						-- so the power scaling clones the swapped profile.
						local swap_fields = { "damage_profile", "damage_profile_aoe", "damage_profile_target" }
						for _, field in ipairs(swap_fields) do
							local profile = sub_action[field]
							if profile and _SHORTSWORD_DAMAGE_PROFILE_SWAP[profile] ~= nil then
								local replacement = _SHORTSWORD_DAMAGE_PROFILE_SWAP[profile]
								sub_action[field] = replacement or nil
							end
						end
						-- Step 2: scale power on the (possibly swapped) damage_profile.
						if sub_action.damage_profile then
							sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_shortsword_", {
								damage = _SHORTSWORD_POWER_MULT, stagger = _SHORTSWORD_POWER_MULT,
							})
						end
						-- Step 3: swap fire-themed FX / sounds → sword-themed
						-- analogs. Without this, sub-actions that previously
						-- referenced burning damage profiles still ran their
						-- staff_spark hit_effect — and the staff_spark FX
						-- package isn't loaded for empire-soldier wielders, so
						-- World.create_particles crashed mid-sweep (v0.1.155
						-- regression — fixed v0.1.156).
						for field, swap_map in pairs(_SHORTSWORD_FX_SWAP) do
							local current = sub_action[field]
							if current and swap_map[current] then
								sub_action[field] = swap_map[current]
							end
						end
					end
				end
			end
		end
	end

	Weapons.shortsword_template = template
	mod:info("Created shortsword_template (spd=%.0f%% power=%.0f%%, fire DoT removed)",
		_SHORTSWORD_SPEED_MULT * 100, _SHORTSWORD_POWER_MULT * 100)
end

_create_shortsword_template()
end  -- #284: end shortsword do-block

-- ============================================================
-- Maul template (modified one_handed_hammer_wizard_template_1)
-- Sienna's Morningstar moveset cloned for Kruber. H1 heavy attack's
-- damage_profile (medium_blunt_smiter_heavy) is swapped to a non-burn
-- analog (medium_blunt_smiter_2h_hammer) — wizard fire is in the
-- damage-profile resolution chain, not the FX/sound fields.
--
-- 3P wield routes to Kruber's greathammer SM (to_2h_hammer); per-action
-- 3P remap covers wizard-mace events not authored on
-- two_handed_hammers_template_1's vocabulary.
--
-- ANIM ADDENDUM: 3P-only. 1P universal — see top-of-file ANIMATION
-- ARCHITECTURE.
-- ============================================================

-- Single-entry burn swap. Verified that medium_blunt_smiter_heavy is the
-- ONLY profile in the wizard mace template that resolves to a _burn_*
-- PowerLevelTemplates entry. Other damage profiles (light_blunt_tank,
-- light_blunt_smiter, medium_blunt_tank_upper_1h, medium_push, light_push)
-- are clean. FX/sound fields already non-fire (melee_hit_hammers_1h /
-- blunt_hit / blunt_hit_armour) — no FX swap pass needed.
do  -- #284: scope maul template locals off the top-level chunk (>200-local limit)
local _MAUL_DAMAGE_PROFILE_SWAP = {
	medium_blunt_smiter_heavy = "medium_blunt_smiter_2h_hammer",
}

-- 3P remap — source events (one_handed_hammer_wizard_template_1) →
-- target events (two_handed_hammers_template_1, Kruber greathammer SM).
-- Closed-vocabulary rule: every value MUST appear in the greathammer
-- template's anim_event set. Verified against
-- weapon_templates/2h_hammers.lua: charge / charge_right / charge_left /
-- heavy_right / heavy / down_left / left / left_diagonal / down_right /
-- push / parry_pose. Source events already in target (left_diagonal,
-- left, push, parry_pose) need no entry.
local _MAUL_ANIM_REMAP_3P = {
	-- charges: source has _diagonal / _pose suffixes; target has none.
	attack_swing_charge_left_diagonal = "attack_swing_charge_left",
	attack_swing_charge_left_pose     = "attack_swing_charge_left",
	attack_swing_charge_right_pose    = "attack_swing_charge_right",
	-- heavies: source overhead / sided "_up" variants; target has plain
	-- heavy + heavy_right (no heavy_left).
	attack_swing_heavy_down           = "attack_swing_heavy",
	attack_swing_heavy_right_up       = "attack_swing_heavy_right",
	attack_swing_heavy_left_up        = "attack_swing_heavy",
	-- lights: source right_diagonal / down / left_diagonal_last need
	-- closest-in-vocab strikes.
	attack_swing_right_diagonal       = "attack_swing_down_right",
	attack_swing_down                 = "attack_swing_down_right",
	attack_swing_left_diagonal_last   = "attack_swing_left_diagonal",
}

local _maul_kruber_wield_3p = {
	es_mercenary      = "to_2h_hammer",
	es_huntsman       = "to_2h_hammer",
	es_knight         = "to_2h_hammer",
	es_questingknight = "to_2h_hammer",
}

local function _create_maul_template()
	if not Weapons or not Weapons.one_handed_hammer_wizard_template_1 then
		mod:warning("one_handed_hammer_wizard_template_1 not found — Maul template unavailable")
		return
	end
	if Weapons.maul_template then return end

	local template = table.clone(Weapons.one_handed_hammer_wizard_template_1, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						-- Step 1: scrub fire by swapping the burn-bearing
						-- damage_profile to a non-burn analog. Single-entry
						-- map; nothing else in this template fires.
						local profile = sub_action.damage_profile
						if profile and _MAUL_DAMAGE_PROFILE_SWAP[profile] then
							sub_action.damage_profile = _MAUL_DAMAGE_PROFILE_SWAP[profile]
						end
						-- Step 2: 3P body event remap (3P only —
						-- never write anim_event / 1P fields).
						if sub_action.anim_event and _MAUL_ANIM_REMAP_3P[sub_action.anim_event] then
							sub_action.anim_event_3p = _MAUL_ANIM_REMAP_3P[sub_action.anim_event]
						end
					end
				end
			end
		end
	end

	template.wield_anim_3p = "to_2h_hammer"
	template.wield_anim_career_3p = template.wield_anim_career_3p or {}
	for k, v in pairs(_maul_kruber_wield_3p) do
		template.wield_anim_career_3p[k] = v
	end

	-- Override attachment_node_linking from the source template's
	-- `AttachmentNodeLinking.brw_hammer` to the generic two-handed linking.
	-- The wizard linking specifies `unwielded.source = "a_unwielded_brw_mace"`
	-- — a bone authored ONLY on Sienna's 3P body skeleton. When Kruber
	-- (who lacks that bone) unequips the maul, the engine's `Unit.node()`
	-- lookup fails and crashes (`[Script Error]: a_unwielded_brw_mace`,
	-- crash GUID 37ead770-8f34-4821-b71d-2de354929a80, v0.1.167). The
	-- visual silhouette is two-handed (the variant scales the mesh up to
	-- 1.4×1.4×2.0), so two_handed_melee_weapon linking — `a_unwielded_2h`
	-- for unwielded, which Kruber has — is the right choice both visually
	-- and skeletally. Wielded source is `j_rightweaponattach` either way.
	if AttachmentNodeLinking and AttachmentNodeLinking.two_handed_melee_weapon then
		template.right_hand_attachment_node_linking = AttachmentNodeLinking.two_handed_melee_weapon
	end

	Weapons.maul_template = template

	-- Patch the BASE template's wield_anim_career_3p so the inventory
	-- previewer (HeroPreviewer reads BASE template, not our clone — see
	-- feedback_cwv_previewer_template_lookup.md) shows the right wield
	-- pose for Kruber careers. Scoped to es_* only — Sienna careers fall
	-- through to original behavior.
	local base = Weapons.one_handed_hammer_wizard_template_1
	if base then
		base.wield_anim_career_3p = base.wield_anim_career_3p or {}
		for k, v in pairs(_maul_kruber_wield_3p) do
			base.wield_anim_career_3p[k] = v
		end
	end

	-- Patch the BASE template's right_hand_attachment_node_linking too.
	-- Reason: the inventory previewer reads BASE template attachments,
	-- not our clone (per `feedback_cwv_previewer_template_lookup.md`).
	-- Without this, opening the inventory on a Kruber career carrying
	-- the Maul triggers `[Script Error]: a_unwielded_brw_mace` on the
	-- preview body. Crash GUID `258c5f1c-dbe0-4ebd-8ef6-0b43d95c3b9d`,
	-- v0.1.187. Replace ONLY the `third_person.unwielded` binding —
	-- `wielded` uses the universal `j_rightweaponattach` (all bodies
	-- have it), so leaving it alone preserves Sienna's native
	-- in-hand behavior. Cost: Sienna's holstered-mace pose now sits on
	-- standard hips instead of her dedicated mace-bone — small visual
	-- regression for her, fixes Kruber crash. AttachmentNodeLinking.brw_hammer
	-- is referenced by ONLY this one weapon template (verified via
	-- source-wide grep), so the patch is well-scoped.
	if base and base.right_hand_attachment_node_linking
			and base.right_hand_attachment_node_linking.third_person then
		base.right_hand_attachment_node_linking.third_person.unwielded = {
			{ source = "j_hips", target = 0 },
		}
	end

	mod:info("Created maul_template (burn scrub: %d profile swap, 3p anim remap: %d entries, wield_3p=to_2h_hammer)",
		1, 9)
end

_create_maul_template()
end  -- #284: end maul do-block

-- ============================================================
-- #597 Greataxe template (exact Bardin behavior, Kruber 3P redirects)
-- ============================================================
do
	local greataxe = _om.greataxe
	local function _create_greataxe_template()
		if not Weapons or not Weapons.two_handed_axes_template_1 then
			mod:warning("two_handed_axes_template_1 not found - Greataxe unavailable")
			return
		end
		if Weapons[greataxe.TEMPLATE_KEY] then return end

		-- No timing or damage-profile edits: #597 requires an exact gameplay
		-- analogue of Bardin's Greataxe. Only receiver-local 3P fields differ.
		local template = table.clone(Weapons.two_handed_axes_template_1, true)
		template.wield_anim_career_3p = template.wield_anim_career_3p or {}
		for _, career in ipairs(greataxe.DEFAULT_CAREERS) do
			template.wield_anim_career_3p[career] = "to_2h_hammer"
		end

		Weapons[greataxe.TEMPLATE_KEY] = template
		mod:info("Created %s (exact dr_2h_axe stats/moveset; Kruber wield=to_2h_hammer)",
			greataxe.TEMPLATE_KEY)
	end

	_create_greataxe_template()
end

-- ============================================================
-- Outrider Grenade Launcher template (modified dr_deus_01_template_1)
-- Behavior comes from Bardin Engineer's Trollhammer Torpedo
-- (`dr_deus_01_template_1`); visual layer is swapped to Kruber's
-- blunderbuss (state machine, wield anims, display unit, attachment
-- node linking). The trollhammer's action_one fires `attack_shoot`,
-- which is also a blunderbuss-state-machine event — so no per-action
-- anim_event remap is needed. 3P body anims work because Kruber's
-- empire-soldier skeleton has `attack_shoot` authored for his vanilla
-- blunderbuss.
--
-- Tunes vs vanilla trollhammer (per user, v0.1.176):
--   * speed × 1.4   (2500 → 3500 — faster projectile, "travels further")
--   * reload × 0.65 (3.0s → ~1.95s — faster reload than trollhammer)
--   * damage × 0.65 (proportionally smaller damage and stagger via
--                    cloned damage profile)
--   * max_range 20 → 30 (longer aim-assist reach)
--
-- Hand swap: trollhammer mounts the gun on the LEFT hand
-- (`weapon_action_hand = "left"`, `ammo_data.ammo_hand = "left"`,
-- `left_hand_unit = "...wpn_dr_deus_01"`). Blunderbuss is right-hand.
-- All `weapon_action_hand` and `ammo_hand` fields swapped to "right";
-- left_hand_unit cleared, right_hand_attachment set to
-- `AttachmentNodeLinking.rifles` (matches vanilla blunderbuss).
--
-- WIP / TODO:
--   * Explosion radius — `ExplosionTemplates.dr_deus_01` isn't in the
--     decompiled source we work from, so the explosion template is
--     used as-is. Smaller-radius tune is a follow-up.
--   * Projectile model — currently the trollhammer torpedo. User
--     mentioned wanting a grenade-shaped projectile; that's a follow-up
--     once `Projectiles.cwv_outrider_grenade` is set up.
-- ============================================================

do  -- #284: scope outrider grenade-launcher template locals off the top-level chunk (>200-local limit)
local _OUTRIDER_PROJECTILE_SPEED = 3500
local _OUTRIDER_RELOAD_MULT      = 0.75   -- 0.75× trollhammer reload = ~25% faster reload
local _OUTRIDER_DAMAGE_MULT      = 0.65
local _OUTRIDER_MAX_RANGE        = 30
local _OUTRIDER_MAX_AMMO         = 10     -- v0.1.260: bumped from inherited 7 (trollhammer base)

local function _create_outrider_grenade_launcher_template()
	if not Weapons or not Weapons.dr_deus_01_template_1 then
		mod:warning("dr_deus_01_template_1 not found — Outrider Grenade Launcher template unavailable (Outcast Engineer DLC required)")
		return
	end
	if Weapons.outrider_grenade_launcher_template then return end

	local template = table.clone(Weapons.dr_deus_01_template_1, true)

	-- Swap visual layer: blunderbuss state machine + anims + display unit.
	-- 1P state machine and anim assets live on the shared first_person_base
	-- unit, so loading the blunderbuss state machine works on any character.
	template.state_machine          = "units/beings/player/first_person_base/state_machines/ranged/blunderbuss"
	template.wield_anim             = "to_blunderbuss"
	template.wield_anim_no_ammo     = "to_blunderbuss_noammo"
	template.wield_anim_not_loaded  = nil   -- blunderbuss has no "not_loaded" wield variant
	template.display_unit           = "units/weapons/weapon_display/display_blunderbusses"
	template.reload_event           = "reload"   -- vanilla blunderbuss event name (kept for clarity)
	-- #760: 3P only. WT may expose this exact CWV item to the three standard
	-- Saltzpyre careers. Route their body into their native Repeater Pistol
	-- stance while Kruber retains the authored blunderbuss stance. The 1P
	-- launcher state machine above remains shared and unchanged.
	local receiver_count, receiver_reason = _om.outrider_animation.apply_template(
		template, NetworkLookup and NetworkLookup.anims)
	_om.outrider_animation.emit_evidence(printf, "template", "wh_standard",
		_om.outrider_animation.SALTZPYRE_WIELD_3P,
		receiver_reason or ("mapped_" .. tostring(receiver_count)), "private_clone")

	-- Hand swap: weapon mounts on the right hand instead of left.
	template.left_hand_unit                    = ""
	template.left_hand_attachment_node_linking = nil
	if AttachmentNodeLinking and AttachmentNodeLinking.rifles then
		template.right_hand_attachment_node_linking = AttachmentNodeLinking.rifles
	end

	-- ammo_data: swap ammo_hand to right (it's set to "left" on the trollhammer
	-- because the gun is held in the left hand there). Also bump max_ammo
	-- from inherited 7 (trollhammer base) to _OUTRIDER_MAX_AMMO per user.
	if template.ammo_data then
		template.ammo_data.ammo_hand   = "right"
		template.ammo_data.reload_time = (template.ammo_data.reload_time or 3) * _OUTRIDER_RELOAD_MULT
		template.ammo_data.max_ammo    = _OUTRIDER_MAX_AMMO
	end

	-- attack_meta_data.max_range: bump for "travels further" reach.
	if template.attack_meta_data then
		template.attack_meta_data.max_range = _OUTRIDER_MAX_RANGE
	end

	-- wwise_dep_left_hand: rename to right_hand since the gun lives on the
	-- right now. The wwise dependency package is loaded based on the
	-- weapon's hand mount, so this matters for sound bank loading.
	template.wwise_dep_right_hand = template.wwise_dep_left_hand
	template.wwise_dep_left_hand  = nil

	-- Projectile-visual swap: replace the trollhammer torpedo mesh with
	-- the hand grenade mesh, keeping all other trollhammer projectile
	-- physics intact (gravity, life_time, impact_type, trajectory).
	-- `Projectiles.dr_deus_01` is the trollhammer's projectile config;
	-- `ProjectileUnits.grenade` is the hand grenade visual
	-- (`wpn_emp_grenade_01_t1_3p`). Build our own Projectiles entry
	-- by cloning and swapping just `projectile_units_template`.
	-- The cloned config is referenced from each shoot sub-action below.
	if Projectiles and Projectiles.dr_deus_01
			and not Projectiles.cwv_outrider_grenade_projectile then
		local p = table.clone(Projectiles.dr_deus_01, true)
		p.projectile_units_template = "grenade"
		Projectiles.cwv_outrider_grenade_projectile = p
	end

	-- Per-action tunes: walk action_one and the reload/wield variants.
	-- Specifically: action_one.default is the shoot action (kind = grenade_thrower).
	if template.actions and template.actions.action_one then
		for _, sub_action in pairs(template.actions.action_one) do
			if type(sub_action) == "table" then
				-- Hand swap: every weapon_action_hand = "left" → "right".
				if sub_action.weapon_action_hand == "left" then
					sub_action.weapon_action_hand = "right"
				end
				-- Speed tune: bump projectile speed.
				if sub_action.speed then
					sub_action.speed = _OUTRIDER_PROJECTILE_SPEED
				end
				-- Damage tune: clone damage profile in impact_data with reduced
				-- damage and stagger multipliers.
				if sub_action.impact_data and sub_action.impact_data.damage_profile then
					sub_action.impact_data.damage_profile = _clone_damage_profile(
						sub_action.impact_data.damage_profile,
						"cwv_outrider_grenade_launcher_",
						{ damage = _OUTRIDER_DAMAGE_MULT, stagger = _OUTRIDER_DAMAGE_MULT })
				end
				-- Projectile visual swap: point at our cloned config.
				-- Only swap if vanilla had this sub-action pointed at the
				-- trollhammer projectile config (defensive — other sub-actions
				-- in this group might use different projectiles).
				if sub_action.projectile_info == Projectiles.dr_deus_01
						and Projectiles.cwv_outrider_grenade_projectile then
					sub_action.projectile_info = Projectiles.cwv_outrider_grenade_projectile
				end
			end
		end
	end

	-- default_loaded_projectile_settings reads `action.speed` at template-load
	-- time. Since we just bumped action.speed above, sync the cached value.
	if template.default_loaded_projectile_settings then
		template.default_loaded_projectile_settings.speed = _OUTRIDER_PROJECTILE_SPEED
	end

	-- weapon_type identifier — used by some sibling-mod hooks for filtering.
	template.weapon_type = "cwv_es_outrider_grenade_launcher"

	-- Right-click bash (replaces trollhammer's left-handed push). Without
	-- this, right-click crashes on the cwv variant because the trollhammer's
	-- action_one.push has `weapon_action_hand = "left"` (Bardin holds the
	-- gun in his left hand, so push is naturally left-handed) — and our
	-- variant has `no_left_hand = true`, so there's no left-hand wielded
	-- unit to back the push. Crash:
	-- `player_character_state_helper.lua: tried to start a left hand
	-- weapon action without a left hand wielded unit` (GUID 33e82f2c).
	--
	-- Per user, the bash should feel like the blunderbuss's. Copy the
	-- blunderbuss's `action_two.default` directly — kind = "shield_slam",
	-- damage_profile = "shield_slam_shotgun", anim_event = "attack_push".
	-- This is right-handed (no `weapon_action_hand` field set on
	-- blunderbuss bash), so it works with our right-mounted gun.
	if Weapons.blunderbuss_template_1 and Weapons.blunderbuss_template_1.actions
			and Weapons.blunderbuss_template_1.actions.action_two then
		template.actions.action_two = table.clone(Weapons.blunderbuss_template_1.actions.action_two, true)
	end

	-- Inspect / wield action templates: trollhammer uses the LEFT-handed
	-- variants (`ActionTemplates.action_inspect_left`, `wield_left`)
	-- because its weapon mount is left-handed. Swap to right-handed to
	-- match our right-mounted blunderbuss model.
	if ActionTemplates and ActionTemplates.action_inspect then
		template.actions.action_inspect = ActionTemplates.action_inspect
	end
	if ActionTemplates and ActionTemplates.wield then
		template.actions.action_wield = ActionTemplates.wield
	end

	-- Drop the trollhammer's chained push (`action_one.push`) — it had
	-- `weapon_action_hand = "left"` and `kind = "push_stagger"`. Even
	-- though the iterator above flipped the hand to "right", the action's
	-- chain entry references action_two now, and we'd rather have the
	-- bash be the user-facing right-click than a chained push.
	if template.actions.action_one then
		template.actions.action_one.push = nil
	end

	Weapons.outrider_grenade_launcher_template = template

	-- Patch BASE template (`dr_deus_01_template_1`) too. The inventory
	-- previewer (`world_hero_previewer.lua` `equip_item`) calls
	-- `ItemHelper.get_template_by_item_name(item_name)` where item_name is
	-- the BASE weapon's name (cwv variants inherit `entry.name` from the
	-- clone — see `feedback_cwv_clone_name_clobber.md`), so the previewer
	-- reads the BASE template, NOT our clone (per
	-- `feedback_cwv_previewer_template_lookup.md`).
	--
	-- Vanilla `dr_deus_01_template_1` has only `left_hand_attachment_node_linking`
	-- set (Bardin's trollhammer is a left-hand-mount weapon — his
	-- `right_hand_unit` is nil natively, so the previewer's
	-- `if right_hand_unit then` branch never fires for him). For our
	-- cwv variant on Kruber, `entry.right_hand_unit` IS set (the blunderbuss
	-- model), so the previewer hits that branch and reads
	-- `item_template.right_hand_attachment_node_linking.third_person` →
	-- crashes if the BASE template doesn't have right_hand_attachment_node_linking
	-- (crash GUID c847908d-c1e0-46be-8d15-c45c2a80e8a0, v0.1.179).
	--
	-- Fix: add `right_hand_attachment_node_linking = AttachmentNodeLinking.rifles`
	-- to the BASE template. Bardin still doesn't reach the right-hand path
	-- (his right_hand_unit stays nil) so this is harmless for vanilla
	-- trollhammer; our cwv variant does reach the path and now has a valid
	-- linking.
	if Weapons.dr_deus_01_template_1 and AttachmentNodeLinking and AttachmentNodeLinking.rifles then
		Weapons.dr_deus_01_template_1.right_hand_attachment_node_linking = AttachmentNodeLinking.rifles
	end

	mod:info("Created outrider_grenade_launcher_template (blunderbuss visuals + trollhammer behavior, speed=%d, reload×%.2f, damage×%.2f, max_range=%d)",
		_OUTRIDER_PROJECTILE_SPEED, _OUTRIDER_RELOAD_MULT, _OUTRIDER_DAMAGE_MULT, _OUTRIDER_MAX_RANGE)
end

_create_outrider_grenade_launcher_template()
end  -- #284: end outrider grenade-launcher do-block

	return {
		clone_damage_profile = _clone_damage_profile,
	}
end
