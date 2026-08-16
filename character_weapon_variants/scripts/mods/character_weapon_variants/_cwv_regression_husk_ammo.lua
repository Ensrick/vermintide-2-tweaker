-- _cwv_regression_husk_ammo.lua -- husk ammo + projectile-tune regression owner.
--
-- Holds the two /cwv_regression_test checks whose subject is what a variant's
-- weapon DATA does after the engine has resolved it from the BASE item:
--   * issue1186_outrider_projectile_reads_cloned_tunes -- a fired projectile
--     re-derives its own action from `ItemMasterList[item_name]`, and a CWV
--     clone inherits the base key as its `name`, so a variant whose template was
--     cloned under a NEW name flies with donor impact/projectile data;
--   * issue1188_wt_native_trollhammer_keeps_ammo -- the husk ammo arms decide
--     from a (base_weapon, career) signal that is only CWV-positive while the
--     base's can_wield stays disjoint from the strip set, which a weapon_tweaker
--     unlock removes at runtime.
-- Both drive PRODUCTION seams (`_om._cwv_apply_renamed_projectile_template`,
-- `_om._husk_adapter_pre` / `_husk_adapter_post`, `_om._husk_ammo_pair_admits`)
-- against live game tables, and both restore every seam and every table they
-- mutate through a guaranteed-restore tail.
--
-- Split out of _cwv_regression_identity.lua VERBATIM: that file crossed the
-- PROJECT_STANDARDS section 2.1 hard limit of 2500 non-blank lines (2576) and
-- check_file_sizes flags a hard-limit regression as an ERROR. Pure structural
-- extraction -- no check body, name, message or assertion changed.
--
-- Owned by: character_weapon_variants.lua entry point. Consumed via mod:dofile
-- BETWEEN the identity and render regression owners, which is load-bearing:
-- `_rt_register` appends to one ordered runner list, so keeping this module at
-- that exact position preserves the registration ORDER these two checks already
-- had (immediately after the identity checks, before the render checks) and the
-- /cwv_regression_test runner is unchanged. Receives the same shared
-- `_cwv_regression_context` table as its two siblings and reads only the four
-- entries its checks use.
return function(mod, ctx)
local _om = ctx.om
local _rt_register = ctx.rt_register
local _variant_definitions = ctx.variant_definitions
local _find_def = ctx.find_def

_rt_register("issue1186_outrider_projectile_reads_cloned_tunes", function()
	-- Issue #1186: a projectile re-resolves its own action from
	-- `ItemMasterList[item_name]`, and a CWV clone inherits the BASE key as its
	-- `name` -- so a variant whose template was cloned under a NEW name flies with
	-- donor data. Only the javelin family had an arm here; the Outrider Grenade
	-- Launcher's 0.65x damage clone and grenade projectile_info never applied.
	local policy = _om.projectile_tunes
	local apply_arm = _om._cwv_apply_renamed_projectile_template
	if type(policy) ~= "table" or type(policy.renamed_template_defs) ~= "function"
			or type(policy.resolve) ~= "function" or type(policy.apply) ~= "function" then
		return "#1186 renamed-clone projectile policy is not installed"
	end
	if type(apply_arm) ~= "function" or type(_om._cwv_projectile_owner_slot) ~= "function" then
		return "#1186 projectile init arm / owner-slot seam is not installed"
	end
	local iml = rawget(_G, "ItemMasterList")
	local weapons = rawget(_G, "Weapons")
	if type(iml) ~= "table" or type(weapons) ~= "table" then
		return "ItemMasterList/Weapons not loaded yet (run in-keep)"
	end
	local def = _find_def("cwv_es_outrider_grenade_launcher")
	if not def then return nil end   -- variant removed; nothing to protect

	-- GROUND TRUTH: the authored catalog + the two live templates, never the
	-- resolver under test. If the clone ever stops differing from its donor the
	-- fixture is meaningless, so prove the difference first.
	local overrides = policy.renamed_template_defs(_variant_definitions, function(base)
		local entry = rawget(iml, base)
		return type(entry) == "table" and entry.template or nil
	end)
	if overrides[def.item_key] ~= def.template then
		return "#1186 the Outrider's renamed clone is missing from the projectile override map"
	end
	if overrides.cwv_es_javelin == nil and _find_def("cwv_es_javelin") then
		return "#1186 the javelin family fell out of the shared renamed-clone map"
	end
	local donor = rawget(weapons, "dr_deus_01_template_1")
	local clone = rawget(weapons, def.template)
	local donor_action = donor and donor.actions and donor.actions.action_one
		and donor.actions.action_one.default
	local clone_action = clone and clone.actions and clone.actions.action_one
		and clone.actions.action_one.default
	if type(donor_action) ~= "table" or type(clone_action) ~= "table" then
		return "#1186 Outrider fixture stale: donor/clone action_one.default is gone (Outcast Engineer DLC?)"
	end
	if clone_action == donor_action or clone_action.speed == donor_action.speed then
		return "#1186 the Outrider clone no longer tunes action_one.default -- nothing to deliver"
	end
	local clone_profile = clone_action.impact_data and clone_action.impact_data.damage_profile
	if type(clone_profile) ~= "string" or clone_profile:sub(1, 4) ~= "cwv_" then
		return "#1186 the Outrider clone lost its own damage profile -- the 0.65x tune is gone"
	end

	-- Drive the REAL init arm with a fixture wielded slot in the shape a crafted
	-- (UUID backend_id) Outrider arrives in, and read the projectile back.
	local saved_slot = _om._cwv_projectile_owner_slot
	local projectile = {
		action_lookup_data = {
			item_template_name = "dr_deus_01_template_1",
			action_name = "action_one",
			sub_action_name = "default",
		},
		_current_action = donor_action,
		_impact_data = donor_action.impact_data,
		_impact_damage_profile_id = -1,
		projectile_info = donor_action.projectile_info,
	}
	local result
	local ok, err = pcall(function()
		_om._cwv_projectile_owner_slot = function()
			return {
				id = "slot_ranged",
				master_item = {
					name = def.base_weapon,
					backend_id = "rt1186-0231d6f6-9bda-4f34-b016-9b7c7c371c1c",
					mod_data = { cwv_key = def.item_key },
				},
			}
		end
		local changed = apply_arm(projectile, {
			item_name = def.base_weapon, owner_unit = { rt1186 = true },
		})
		if projectile._current_action ~= clone_action then
			result = "#1186 the fired projectile still reads the donor action -- authored tunes never applied"
			return
		end
		if projectile._impact_data ~= clone_action.impact_data then
			result = "#1186 impact_data stayed on the donor profile (the 0.65x damage tune)"
			return
		end
		local want_id = rawget(NetworkLookup.damage_profiles, clone_profile)
		if want_id and projectile._impact_damage_profile_id ~= want_id then
			result = "#1186 the wire damage-profile id still names the donor profile"
			return
		end
		if not changed or changed < 3 then
			result = "#1186 projectile re-point reported " .. tostring(changed)
				.. " field writes -- the transfer collapsed"
			return
		end
		-- Idempotent: a second pass over an already-re-pointed projectile is a
		-- no-op, so a repeated init can never double-apply.
		if apply_arm(projectile, {
				item_name = def.base_weapon, owner_unit = { rt1186 = true },
			}) ~= 0 then
			result = "#1186 projectile re-point is not idempotent"
			return
		end
		-- #475 Invariant 1 for the projectile path: a NATIVE Bardin Trollhammer
		-- (no cwv identity on the slot) must keep every donor value.
		_om._cwv_projectile_owner_slot = function()
			return { id = "slot_ranged", master_item = { name = "dr_deus_01" } }
		end
		local native = {
			action_lookup_data = projectile.action_lookup_data,
			_current_action = donor_action,
			_impact_data = donor_action.impact_data,
		}
		if apply_arm(native, { item_name = "dr_deus_01", owner_unit = { rt1186 = true } }) ~= 0
				or native._current_action ~= donor_action then
			result = "#1186 a native Trollhammer projectile was re-pointed at the CWV clone"
		end
	end)
	_om._cwv_projectile_owner_slot = saved_slot
	if not ok then return "#1186 projectile arm drive errored: " .. tostring(err) end
	return result
end)

_rt_register("issue1188_wt_native_trollhammer_keeps_ammo", function()
	-- Issue #1188: the husk ammo arms decided on `_no_ammo_careers_by_base`
	-- membership alone. That set is only a CWV-positive signal while dr_deus_01's
	-- can_wield stays disjoint from it, and weapon_tweaker's
	-- `unlock_es_*_dr_deus_01` toggles delete that disjointness at runtime -- so a
	-- wt-granted Kruber Trollhammer had its torpedo stripped on every remote view.
	-- Driven against the LIVE can_wield the discriminator actually reads.
	local admits = _om._husk_ammo_pair_admits
	local pre, post = _om._husk_adapter_pre, _om._husk_adapter_post
	if type(admits) ~= "function" then
		return "#1188 shared ammo native-pair discriminator is not installed"
	end
	if type(pre) ~= "function" or type(post) ~= "function" then
		return "#1188 husk adapter halves missing -- the ammo arms are unreachable"
	end
	local def = _find_def("cwv_es_outrider_grenade_launcher")
	if not def then return nil end
	local iml = rawget(_G, "ItemMasterList")
	local base = iml and rawget(iml, "dr_deus_01")
	if not (base and base.ammo_unit and type(base.can_wield) == "table") then
		return "#1188 dr_deus_01 fixture is stale (no ammo_unit / can_wield)"
	end
	-- Prefer a career the pair is NOT already native for, so the disjoint
	-- baseline is real. If weapon_tweaker has already unlocked every one of the
	-- variant's careers the baseline is skipped and only the guard is asserted.
	local strip_career, disjoint_now
	for _, career in ipairs(def.careers or {}) do
		if not _om._husk_pair_native_now("dr_deus_01", career) then
			strip_career, disjoint_now = career, true
			break
		end
	end
	strip_career = strip_career or (def.careers and def.careers[1])
	if type(strip_career) ~= "string" then
		return "#1188 the Outrider def lists no careers -- fixture cannot be built"
	end
	local skin_key = def.item_key .. "_skin"

	local saved_descriptor = _om._husk_identity_descriptor
	local saved_career = _om._husk_career_name
	local saved_rekey = _om._husk_rekey_units
	local saved_template = _om._husk_template_for_spawn
	local saved_transform = _om._husk_apply_cwv_transform
	local saved_probe = _om._probe_579_hand_compare
	local can_wield = base.can_wield
	local unlocked_index

	local owner, state, exact_descriptor = { rt1188 = true }, "none", nil
	local function units(skin)
		return {
			right_hand_unit = def.right_hand_unit,
			ammo_unit = base.ammo_unit,
			ammo_unit_3p = base.ammo_unit_3p,
			skin = skin,
		}
	end
	local function cleared(u) return u.ammo_unit == nil and u.ammo_unit_3p == nil end

	local result
	local ok, err = pcall(function()
		_om._husk_identity_descriptor = function() return exact_descriptor, state end
		_om._husk_career_name = function() return strip_career end
		_om._husk_rekey_units = function() return false end
		_om._husk_template_for_spawn = function() return nil end
		_om._husk_apply_cwv_transform = function() return nil end
		_om._probe_579_hand_compare = function() return nil end

		local u
		-- (1) BASELINE, pair disjoint: the strip career is not in can_wield, so
		-- career membership still decides and the Outrider keeps working. Skipped
		-- only when weapon_tweaker has already unlocked every Outrider career, in
		-- which case there is no disjoint pair left to baseline against.
		if disjoint_now then
			if select(1, admits("dr_deus_01", strip_career, nil)) ~= true then
				result = "#1188 the disjoint pair stopped admitting the strip -- the Outrider lost its torpedo fix (#399)"
				return
			end
			u = units(nil)
			pre("right", nil, u, "slot_ranged", { name = "dr_deus_01" }, owner)
			if not cleared(u) then
				result = "#1188 the disjoint base+career fallback no longer clears the inherited torpedo (#399 regression)"
				return
			end
			-- (2) Simulate the wt unlock on the LIVE table the lazy check reads.
			unlocked_index = #can_wield + 1
			can_wield[unlocked_index] = strip_career
		end
		local pair_admits, reason = admits("dr_deus_01", strip_career, nil)
		if pair_admits ~= false or reason ~= "native_pair" then
			result = "#1188 a wt-granted native pair still admitted the strip (reason=" .. tostring(reason) .. ")"
			return
		end
		u = units(nil)
		pre("right", nil, u, "slot_ranged", { name = "dr_deus_01" }, owner)
		if cleared(u) then
			result = "#1188 pre-spawn arm stripped a wt-granted NATIVE Trollhammer's torpedo (#475 Invariant 1)"
			return
		end
		if post("right", { name = "dr_deus_01" }, u, "slot_ranged", owner, nil,
				{ rt1188_ammo = true }) then
			result = "#1188 post-spawn arm signalled a strip for a wt-granted native Trollhammer"
			return
		end

		-- (3) The Outrider must survive that same unlock whenever CWV identity is
		-- positive. A cwv skin names the variant regardless of can_wield...
		if rawget(WeaponSkins and WeaponSkins.skins or {}, skin_key) then
			u = units(skin_key)
			pre("right", nil, u, "slot_ranged", { name = "dr_deus_01" }, owner)
			if not cleared(u) then
				result = "#1188 a cwv-skinned Outrider lost its ammo fix under the wt unlock"
				return
			end
		end
		-- ...and a proven exact descriptor decides ahead of the fallback entirely.
		exact_descriptor, state = { variant_key = def.item_key,
			base_item_key = "dr_deus_01" }, "exact"
		u = units(nil)
		pre("right", nil, u, "slot_ranged", { name = "dr_deus_01" }, owner)
		if not cleared(u) then
			result = "#1188 a proven Outrider descriptor lost its ammo fix under the wt unlock"
		end
	end)
	if unlocked_index then can_wield[unlocked_index] = nil end
	_om._husk_identity_descriptor = saved_descriptor
	_om._husk_career_name = saved_career
	_om._husk_rekey_units = saved_rekey
	_om._husk_template_for_spawn = saved_template
	_om._husk_apply_cwv_transform = saved_transform
	_om._probe_579_hand_compare = saved_probe
	if not ok then return "#1188 husk ammo discriminator drive errored: " .. tostring(err) end
	return result
end)

end
