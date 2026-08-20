-- Regression checks are installed at the entry module's original registration point.
return function(mod, ctx)
local MOD_VERSION = ctx.mod_version
local _om = ctx.om
local _dbg = ctx.dbg
local _rt_register = ctx.rt_register
local _variant_definitions = ctx.variant_definitions
local _registered_keys = ctx.registered_keys
local _display_names = ctx.display_names
local _find_def = ctx.find_def
local _build_entry = ctx.build_entry
local _auto_register_all = ctx.auto_register_all
local _cross_access_action_remap = ctx.cross_access_action_remap
local _cwv_wield_hook_registration_count = ctx.wield_hook_registration_count
local _transform_map = ctx.transform_map
local _skin_transform_map = ctx.skin_transform_map
local _crowbill_transform_by_unit = ctx.crowbill_transform_by_unit
local _custom_skin_keys = ctx.custom_skin_keys

_rt_register("cwv_unit_bearing_variants_registered", function()
    -- Issue #417: a variant that overrides a hand unit must resolve a def on every
    -- def-keyed render path, or its mesh swaps (via _find_def) while transform and
    -- texture silently bail at the nil-def guard. The registration gate now keys on
    -- unit-override presence; assert the invariant so a future gate edit can't drop
    -- it and reintroduce the per-item force_register crutch (the musket, #409).
    if type(mod._cwv_transform_registered) ~= "function" then
        return "mod._cwv_transform_registered missing -- #417 invariant unguardable"
    end
    local defs = _om._variant_defs
    if type(defs) ~= "table" then
        return "_om._variant_defs not exposed -- cannot assert the #417 registration invariant"
    end
    local missing = {}
    for _, def in ipairs(defs) do
        local ru, lu = def.right_hand_unit, def.left_hand_unit
        local has_unit = (type(ru) == "string" and ru ~= "") or (type(lu) == "string" and lu ~= "")
        if has_unit and not mod._cwv_transform_registered(def.item_key) then
            missing[#missing + 1] = tostring(def.item_key)
        end
    end
    if #missing > 0 then
        return "unit-bearing variants NOT in _transform_map (#417 reg-gate fork): " .. table.concat(missing, ", ")
    end
end)

_rt_register("issue482_crafted_uuid_transform_consumers", function()
	local key = "cwv_es_longsword_shield"
	local target = _find_def(key)
	local expected = _transform_map and _transform_map[key]
	local plan_transform = _om.weapon_transform
		and _om.weapon_transform.plan_cwv_hand_transform
	if not target or not expected or target ~= expected or not _registered_keys[key] then
		return "#482 Imperial Longsword and Shield transform registration missing"
	end
	if type(plan_transform) ~= "function"
			or type(_om._cwv_world_transform_decision) ~= "function"
			or type(_om._cwv_preview_transform_decision) ~= "function"
			or type(_om._cwv_browser_transform_decision) ~= "function"
			or type(_om._cwv_select_husk_transform_def) ~= "function"
			or type(_om._cwv_husk_transform_apply_plan) ~= "function" then
		return "#482 production transform consumer seam missing"
	end

	local function same_triplet(actual, wanted)
		if actual == nil or wanted == nil then return actual == wanted end
		return type(actual) == "table" and type(wanted) == "table"
			and actual[1] == wanted[1] and actual[2] == wanted[2]
			and actual[3] == wanted[3]
	end
	local function same_plan(actual, wanted)
		return type(actual) == "table"
			and same_triplet(actual.scale, wanted.scale)
			and same_triplet(actual.scale_multiplier, wanted.scale_multiplier)
			and same_triplet(actual.offset, wanted.offset)
			and same_triplet(actual.rotation, wanted.rotation)
			and actual.should_apply == wanted.should_apply
	end

	-- This UUID shape cannot satisfy CWV's patterned-backend-id rung. The world
	-- decision must therefore consume the exact canonical stamp and prime the
	-- positively validated cache used by preview records that carry only the id.
	local uuid = "48200000-0000-4000-8000-000000000482"
	local stamped = {
		backend_id = uuid,
		cwv_key = key,
		name = target.base_weapon,
		key = target.base_weapon,
	}
	local world_def = _om._cwv_world_transform_decision(stamped, nil,
		target.right_hand_unit)
	local preview_self = {
		_item_info_by_slot = {
			melee = {
				name = target.base_weapon,
				backend_id = uuid,
				spawn_data = { { slot_index = 1 } },
			},
		},
	}
	local preview_def = _om._cwv_preview_transform_decision(
		preview_self, target.base_weapon, nil)
	local browser_def, browser_key = _om._cwv_browser_transform_decision({
		backend_id = uuid,
		data = { key = target.base_weapon, name = target.base_weapon },
	}, {})
	local husk_def, husk_source = _om._cwv_select_husk_transform_def("right", {
		variant_key = key,
		right_hand_unit = target.right_hand_unit,
	}, { name = target.base_weapon }, nil, target.right_hand_unit, nil)
	if world_def ~= expected or preview_def ~= expected or browser_def ~= expected
			or browser_key ~= key or husk_def ~= expected
			or husk_source ~= "exact_variant" then
		return "#482 crafted UUID did not select one canonical def on every consumer"
	end

	local expected_1p = plan_transform(expected, "right", "1p")
	local expected_3p = plan_transform(expected, "right", "3p")
	if not same_triplet(expected_1p.scale, { 1.0, 0.8, 0.9 })
			or not same_triplet(expected_3p.scale, { 0.9, 0.7, 0.8 })
			or not same_triplet(expected_1p.offset, { 0, 0, -0.065 })
			or not same_triplet(expected_3p.offset, { 0, 0, -0.065 })
			or expected_1p.rotation ~= nil or expected_3p.rotation ~= nil then
		return "#482 canonical Imperial Longsword and Shield tuple drifted"
	end
	for _, def in ipairs({ world_def, preview_def, browser_def }) do
		if not same_plan(plan_transform(def, "right", "3p"), expected_3p) then
			return "#482 owner or menu consumer lost the canonical 3P tuple"
		end
	end
	local husk_plan = _om._cwv_husk_transform_apply_plan("right", husk_def, husk_source)
	if not same_plan(husk_plan, expected_3p) then
		return "#482 husk consumer lost the canonical 3P tuple"
	end

	local native = {
		backend_id = "482-native-control",
		name = "es_1h_sword",
		key = "es_1h_sword",
	}
	local native_preview = {
		_item_info_by_slot = {
			melee = { name = native.name, backend_id = native.backend_id,
				spawn_data = { { slot_index = 1 } } },
		},
	}
	local native_husk, native_source = _om._cwv_select_husk_transform_def(
		"right", nil, native, nil, nil, nil)
	if _om._cwv_world_transform_decision(native, nil, nil) ~= nil
			or _om._cwv_preview_transform_decision(native_preview, native.name, nil) ~= nil
			or _om._cwv_browser_transform_decision({
				backend_id = native.backend_id, data = native,
			}, {}) ~= nil
			or native_husk ~= nil or native_source ~= "miss" then
		return "#482 native control acquired a CWV transform"
	end
end)

_rt_register("issue597_greataxe_replaces_poleaxe", function()
	local greataxe = _om.greataxe
	if type(_skin_transform_map) ~= "table" then
		return "Greataxe regression skin-transform dependency missing"
	end
	local function same_triplet(a, b)
		return type(a) == "table" and type(b) == "table"
			and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
	end
	if _find_def("cwv_es_poleaxe") then return "retired Poleaxe definition still registered" end
	local def = _find_def(greataxe.ITEM_KEY)
	if not def or def.base_weapon ~= greataxe.BASE_WEAPON then
		return "Greataxe definition/base contract missing"
	end
	if #(def.careers or {}) ~= 4 then return "Greataxe must default to four Kruber careers" end
	local model = greataxe.default_model()
	if not model
			or not same_triplet(model.right_hand_scale_3p, { 0.5, 0.5, 0.5 })
			or not same_triplet(model.right_hand_offset_3p, { -0.010, 0.153, -0.309 })
			or not same_triplet(model.right_hand_rotation_3p, { -90, 180, -90 }) then
		return "Greataxe Model 01 reviewed transform drifted"
	end
	local base_skin_transform = _skin_transform_map[greataxe.ITEM_KEY .. "_skin"]
	if not base_skin_transform
			or not same_triplet(base_skin_transform.right_hand_scale_3p, model.right_hand_scale_3p)
			or not same_triplet(base_skin_transform.right_hand_offset_3p, model.right_hand_offset_3p)
			or not same_triplet(base_skin_transform.right_hand_rotation_3p, model.right_hand_rotation_3p) then
		return "Greataxe Model 01 generated base skin lost its exact transform"
	end
	for index = 2, #greataxe.MODELS do
		local control = _skin_transform_map[greataxe.MODELS[index].key]
		if not control or control.right_hand_scale_3p or control.right_hand_offset_3p
				or control.right_hand_rotation_3p then
			return "Greataxe Model 01 transform leaked to Model " .. tostring(index)
		end
	end
	local source = Weapons and Weapons.two_handed_axes_template_1
	local clone = Weapons and Weapons[greataxe.TEMPLATE_KEY]
	if not source or not clone then return "Greataxe source/clone template missing" end
	local walked = 0
	for action_name, source_group in pairs(source.actions or {}) do
		local clone_group = clone.actions and clone.actions[action_name]
		if type(source_group) == "table" and type(clone_group) == "table" then
			for sub_name, source_action in pairs(source_group) do
				local clone_action = clone_group[sub_name]
				if type(source_action) == "table" and type(clone_action) == "table" then
					walked = walked + 1
					if clone_action.damage_profile ~= source_action.damage_profile
							or clone_action.anim_time_scale ~= source_action.anim_time_scale then
						return string.format("Greataxe gameplay drift at %s.%s", action_name, sub_name)
					end
				end
			end
		end
	end
	if walked == 0 then return "Greataxe gameplay comparison was vacuous" end
	for source_event, target_event in pairs(greataxe.ANIM_REMAP_3P) do
		for _, career in ipairs(greataxe.DEFAULT_CAREERS) do
			if _om._cross_access_target_event(greataxe.ITEM_KEY, career, source_event) ~= target_event then
				return string.format("Greataxe 3P remap drift: %s/%s", career, source_event)
			end
		end
	end
end)

_rt_register("cwv_issue596_infantry_spear_contract", function()
	local infantry = _om.infantry_spear
	local def = _find_def(infantry.ITEM_KEY)
	if def ~= nil then
		return "standalone Infantry Spear remains in variant definitions"
	end
	if rawget(ItemMasterList, infantry.ITEM_KEY) ~= nil then
		return "standalone Infantry Spear leaked into ItemMasterList"
	end
	if rawget(ItemMasterList, infantry.ITEM_KEY .. "_skin") ~= nil then
		return "retired Infantry Spear skin leaked into ItemMasterList"
	end
	if #(infantry.DEFAULT_CAREERS or {}) ~= 3 or infantry.DEFAULT_CAREERS[1] ~= "es_mercenary"
			or infantry.DEFAULT_CAREERS[2] ~= "es_huntsman"
			or infantry.DEFAULT_CAREERS[3] ~= "es_knight" then
		return "Infantry style authored careers drifted (must exclude Grail Knight)"
	end
	local tuskgor = rawget(ItemMasterList, "es_2h_heavy_spear")
	if not (tuskgor and table.contains(tuskgor.can_wield or {}, "es_knight")) then
		return "Tuskgor Spear is not CWV-default-on for Foot Knight"
	end
	local source = Weapons and Weapons.two_handed_spears_elf_template_1
	local tuned = Weapons and Weapons[infantry.TEMPLATE_KEY]
	if not source or not tuned then return "Infantry Spear source/tuned template missing" end
	local checked_timing, checked_profiles = 0, 0
	for action_name, source_group in pairs(source.actions or {}) do
		local tuned_group = tuned.actions and tuned.actions[action_name]
		if type(source_group) == "table" and type(tuned_group) == "table" then
			for sub_name, source_action in pairs(source_group) do
				local tuned_action = tuned_group[sub_name]
				if type(source_action) == "table" and type(tuned_action) == "table" then
					local expected = infantry.scaled_attack_time(
						source_action.kind, source_action.anim_time_scale)
					if source_action.kind == "melee_start" or source_action.kind == "sweep" then
						checked_timing = checked_timing + 1
						if type(tuned_action.anim_time_scale) ~= "number"
								or math.abs(tuned_action.anim_time_scale - expected) > 0.000001 then
							return string.format("Infantry Spear timing drift at %s.%s", action_name, sub_name)
						end
					end
					if source_action.damage_profile then
						checked_profiles = checked_profiles + 1
						local key = tuned_action.damage_profile
						if type(key) ~= "string" or key:find("cwv_infantry_spear_", 1, true) ~= 1
								or _om._cwv_damage_profile_wire_source[key] ~= source_action.damage_profile then
							return string.format("Infantry Spear profile drift at %s.%s", action_name, sub_name)
						end
					end
				end
			end
		end
	end
	if checked_timing == 0 or checked_profiles == 0 then
		return "Infantry Spear contract walk was vacuous"
	end
end)

_rt_register("cwv_husk_override_ref_shared", function()
    -- Issue #418: the residency producer and the preview/browser swap consumer must
    -- key on ONE constant, and the swap guard must be the shared helper -- a
    -- duplicated ref literal silently degraded every swap to the base mesh.
    if _om.HUSK_OVERRIDE_REF ~= "cwv_husk_override_units" then
        return "_om.HUSK_OVERRIDE_REF missing/changed -- producer/consumer ref may have drifted (#418)"
    end
    if type(_om._resident_override_3p) ~= "function" then
        return "_om._resident_override_3p missing -- shared preview/browser swap guard lost (#418)"
    end
end)

_rt_register("cwv_husk_base_career_rekey", function()
    -- Phase C (#392/#394/#396/#397/#401), restructured by #474/#475: the husk
    -- base+career fallback resolves a SKINLESS cross-char variant echo on remote
    -- screens. SAFETY INVARIANT (Invariant 1): the RESOLVER must decline every
    -- (base, career) pair the career can CURRENTLY wield -- the map itself now
    -- holds unfiltered claims and the can_wield check runs lazily at wield time
    -- (#475: the old boot-time exclusion snapshot predated weapon_tweaker's
    -- can_wield expansion, so a wt-freedom native wield got re-keyed to a cwv
    -- variant). This walks every claimed pair through the REAL resolver.
    if type(_om._husk_def_by_base_career) ~= "table" then
        return "_om._husk_def_by_base_career not exposed -- husk base+career fallback missing (Phase C)"
    end
    if type(_om._husk_rekey_units) ~= "function" then
        return "_om._husk_rekey_units missing -- husk mesh re-key lost (issues 396/401)"
    end
    if type(_om._husk_resolve_display_def) ~= "function" or type(_om._husk_pair_native_now) ~= "function" then
        return "_om._husk_resolve_display_def/_husk_pair_native_now missing -- shared husk decision point lost (#474/#475)"
    end
    for base, slot in pairs(_om._husk_def_by_base_career) do
        local master = rawget(ItemMasterList, base)
        local cw = type(master) == "table" and master.can_wield
        if type(cw) == "table" then
            for career in pairs(slot) do
                for _, native in ipairs(cw) do
                    if native == career then
                        local def = _om._husk_resolve_display_def(base, career, nil)
                        if def ~= nil then
                            return string.format(
                                "husk resolver re-keys CURRENTLY-NATIVE pair base=%s career=%s -- would mis-apply a variant to a native weapon on husks (#475 Invariant 1)",
                                tostring(base), tostring(career))
                        end
                    end
                end
            end
        end
    end
end)

_rt_register("cwv_husk_skin_primary_resolution", function()
    -- (#474) Skin-key resolution is the PRIMARY husk display signal and must
    -- cover BOTH cwv skin namespaces:
    --   * base variant skins "<item_key>_skin" (e.g. cwv_es_musket_old_skin)
    --   * pairing/illusion skins "<item_key>_<tail>" via lazy longest-prefix
    -- A cwv wire skin must re-key even when the (base,career) pair is natively
    -- wieldable -- that suppression was #474's mechanism 1.
    if type(_om._husk_skin_def) ~= "function" then
        return "_om._husk_skin_def missing -- skin-primary husk resolution lost (#474)"
    end
    local defs = _om._variant_defs
    if type(defs) ~= "table" then
        return "_om._variant_defs not exposed -- cannot enumerate skin namespaces (#474)"
    end
    -- Namespace 1: every non-no_skin def's base skin must resolve to ITS def.
    for _, def in ipairs(defs) do
        if type(def.item_key) == "string" and not def.no_skin then
            local got = _om._husk_skin_def(def.item_key .. "_skin")
            if got ~= def then
                return string.format("base variant skin %s_skin resolves to %s, expected its own def (#474)",
                    tostring(def.item_key), tostring(got and got.item_key))
            end
        end
    end
    -- Namespace 2: the pairing-skin longest-prefix arm (canonical #475-session
    -- example key; lazy resolution must pick the LS&S def, not the plain
    -- longsword def that shares the prefix).
    local pairing = _om._husk_skin_def("cwv_es_longsword_shield_wpn_emp_shield_03_runed_01__nordland")
    if not (pairing and pairing.item_key == "cwv_es_longsword_shield") then
        return string.format("pairing skin longest-prefix resolution broken: got %s, expected cwv_es_longsword_shield (#474)",
            tostring(pairing and pairing.item_key))
    end
    -- End-to-end: a cwv skin must resolve through the shared decision point
    -- REGARDLESS of native wieldability (es_handgun+es_mercenary is native).
    local def, reason = _om._husk_resolve_display_def("es_handgun", "es_mercenary", "cwv_es_musket_old_skin")
    if not (def and def.item_key == "cwv_es_musket_old" and reason == "skin") then
        return string.format("skin-primary end-to-end broken: def=%s reason=%s for the Old Musket wire shape (#474)",
            tostring(def and def.item_key), tostring(reason))
    end
end)

_rt_register("cwv_husk_native_never_rekeyed", function()
    -- (#475 Invariant 1) A native item must NEVER be re-keyed:
    --   * vanilla/LA skin present -> decline, whatever the (base,career) map says
    --     (the #475 wire shape: native Bret LS&S + vanilla skin on a wt-freedom
    --     mercenary host got re-keyed to the cwv Imperial LS&S on the client);
    --   * skinless echo whose pair is CURRENTLY wieldable -> decline (ambiguous
    --     between a wt-freedom native wield and a variant echo -> show base).
    if type(_om._husk_resolve_display_def) ~= "function" then
        return "_om._husk_resolve_display_def missing (#474/#475)"
    end
    local def, reason = _om._husk_resolve_display_def("es_sword_shield_breton", "es_mercenary", "es_sword_shield_breton_skin_01")
    if def ~= nil or reason ~= "skin_foreign" then
        return string.format("vanilla-skinned native item resolved to def=%s reason=%s -- #475 regression (must decline as skin_foreign)",
            tostring(def and def.item_key), tostring(reason))
    end
    -- Skinless + currently-native pair: vanilla es_handgun.can_wield contains
    -- es_mercenary, so the lazy native check must decline the Old Musket's
    -- claim on that pair (only cwv_es_musket_old claims it; the first musket
    -- variant is retired/commented out, so no ambiguity dedupe applies here).
    local def2 = _om._husk_resolve_display_def("es_handgun", "es_mercenary", nil)
    if def2 ~= nil then
        return string.format("skinless echo of a currently-wieldable pair resolved to %s -- #475 lazy can_wield regression",
            tostring(def2.item_key))
    end
    -- The custom-bundle residency arm must accept exactly the Old Musket custom
    -- mesh (mod-bundled, always resident) and reject arbitrary paths.
    if type(_om._husk_custom_bundle_unit) ~= "function"
            or not _om._husk_custom_bundle_unit("units/cwv_es_musket_custom/cwv_es_musket_custom")
            or _om._husk_custom_bundle_unit("units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1") then
        return "_om._husk_custom_bundle_unit missing or mis-scoped -- Old Musket husk re-key residency arm broken (#474)"
    end
end)

_rt_register("cwv_issue762_outrider_blunderbuss_owner", function()
    local expected =
        "units/weapons/player/wpn_empire_blunderbuss_t1/wpn_empire_blunderbuss_t1"
    local def = _find_def("cwv_es_outrider_grenade_launcher")
    if not def or def.right_hand_unit ~= expected then
        return string.format("Outrider definition visual drifted: %s (expected %s) (#762)",
            tostring(def and def.right_hand_unit), expected)
    end

    local entry = ItemMasterList
        and rawget(ItemMasterList, "cwv_es_outrider_grenade_launcher")
    if not entry or entry.right_hand_unit ~= expected then
        return string.format("Outrider item visual drifted: %s (expected %s) (#762)",
            tostring(entry and entry.right_hand_unit), expected)
    end

    local skin = WeaponSkins and WeaponSkins.skins
        and rawget(WeaponSkins.skins, "cwv_es_outrider_grenade_launcher_skin")
    if not skin or skin.right_hand_unit ~= expected then
        return string.format("Outrider generated skin visual drifted: %s (expected %s) (#762)",
            tostring(skin and skin.right_hand_unit), expected)
    end
end)

_rt_register("cwv_issue760_outrider_saltzpyre_repeater_stance", function()
	local policy = _om.outrider_animation
	local template = Weapons and Weapons[policy and policy.TEMPLATE_KEY]
	local donor = Weapons and Weapons.dr_deus_01_template_1
	if not policy then return "#760 Outrider animation policy missing" end
	local valid, reason = policy.template_contract(template,
		NetworkLookup and NetworkLookup.anims)
	if not valid then return "#760 " .. tostring(reason) end
	if template.wield_anim ~= "to_blunderbuss"
			or template.state_machine ~= "units/beings/player/first_person_base/state_machines/ranged/blunderbuss" then
		return "#760 changed the Outrider's functional 1P/Kruber contract"
	end
	if donor and donor.wield_anim_career_3p == template.wield_anim_career_3p then
		return "#760 private Outrider career map aliases shared Trollhammer donor"
	end
	if policy.runtime_event(policy.ITEM_KEY, "wh_bountyhunter",
		NetworkLookup and NetworkLookup.anims) ~= "to_repeater_pistol" then
		return "#760 Saltzpyre preview resolver drifted"
	end
	if policy.preview_event(policy.ITEM_KEY, "es_mercenary") ~= nil then
		return "#760 Saltzpyre preview stance leaked to Kruber"
	end
end)

_rt_register("cwv_husk_nonresident_spawn_deferred", function()
    -- Issue #478: a resolved CWV variant husk must NEVER let vanilla
    -- spawn_inventory_unit spawn a NON-RESIDENT unit. A Deus-only base (e.g.
    -- dr_deus_01's Trollhammer left-mount) is not resident outside Chaos Wastes,
    -- so a hand the variant does not override (the Outrider's no_left_hand) left
    -- that base mesh in item_units and vanilla errored (gear_utils.lua:189 nil
    -- "_3p" concat once the husk guard skipped it -> entity_manager2.lua:114 "table
    -- index is nil" -> invisible wield; async C-assert risk, BUG_CLASSES 28). The
    -- fix: _husk_rekey_units returns a SUPPRESS flag the spawn hook uses to skip the
    -- vanilla call (residency-gated defer). Lock the predicate, the suppress
    -- contract, and the native-scope guard.
    if type(_om._husk_unit_spawnable) ~= "function" then
        return "_om._husk_unit_spawnable missing -- #478 crash-floor residency predicate lost"
    end
    if type(_om._husk_rekey_units) ~= "function" then
        return "_om._husk_rekey_units missing -- husk re-key/suppress contract lost (#478)"
    end
	if type(_om._husk_preselect_units) ~= "function" then
		return "_om._husk_preselect_units missing -- #478 handedness still runs after vanilla's spawn branch"
	end
	-- PRE-HAND-SELECTION: vanilla's dr_deus_01 result offers only its native
	-- left mount. A skinless Kruber echo must become the Outrider's right-mounted
	-- blunderbuss and clear the left field BEFORE vanilla decides which hand calls
	-- to make. This is the whole-weapon-invisible root from the paired client log.
	local outrider = _find_def("cwv_es_outrider_grenade_launcher")
	local base_units = {
		left_hand_unit = "units/weapons/player/wpn_dr_deus_01/wpn_dr_deus_01",
	}
	local changed, pre_def = _om._husk_preselect_units(base_units,
		{ name = "dr_deus_01" }, nil, nil, "es_mercenary")
	if not changed or pre_def ~= outrider then
		return "skinless dr_deus_01+es_mercenary did not resolve to Outrider before hand selection (#478)"
	end
	if base_units.right_hand_unit ~= outrider.right_hand_unit or base_units.left_hand_unit ~= nil then
		return "Outrider preselection did not schedule right blunderbuss + clear native Trollhammer left hand (#478)"
	end
	-- Scope: explicit backend identity and any skin belong to the normal owner /
	-- skin resolution paths and must never be rewritten by this fallback.
	local backend_guard = { left_hand_unit = "native-left" }
	if _om._husk_preselect_units(backend_guard, { name = "dr_deus_01" }, "some_backend_id", nil, "es_mercenary")
			or backend_guard.left_hand_unit ~= "native-left" or backend_guard.right_hand_unit ~= nil then
		return "Outrider preselection overreached into a backend-identified item (#478)"
	end
	local embedded_backend_guard = { left_hand_unit = "native-left" }
	if _om._husk_preselect_units(embedded_backend_guard,
			{ name = "dr_deus_01", backend_id = "embedded_backend_id" }, nil, nil, "es_mercenary")
			or embedded_backend_guard.left_hand_unit ~= "native-left"
			or embedded_backend_guard.right_hand_unit ~= nil then
		return "Outrider preselection ignored item_data.backend_id (#478 owner-scope regression)"
	end
	local skin_guard = { left_hand_unit = "native-left" }
	if _om._husk_preselect_units(skin_guard, { name = "dr_deus_01" }, nil, "dr_deus_01_skin_01", "es_mercenary")
			or skin_guard.left_hand_unit ~= "native-left" or skin_guard.right_hand_unit ~= nil then
		return "Outrider preselection overreached into a skinned item (#478/#475 Invariant 1)"
	end
    -- Predicate: a non-existent unit path is never resident under any reference.
    if _om._husk_unit_spawnable("units/weapons/player/__cwv_rt_nonresident_478__/__cwv_rt_nonresident_478__") ~= false then
        return "_husk_unit_spawnable returned true for a non-existent unit -- crash-floor would let a non-resident spawn through (#478)"
    end
    -- Predicate (#474 fail-closed): a cwv mod-bundled custom mesh is UNIT-resident
    -- while loaded, but spawnable only when its vanilla DONOR MATERIAL is also
    -- resident on this peer (the MeshObject AV killer). Assert the donor is
    -- declared and that the spawnable answer equals the donor gate -- never the
    -- old unconditional accept.
    if type(_om._husk_material_donor_ready) ~= "function" then
        return "_om._husk_material_donor_ready missing -- #474 donor-material gate lost"
    end
    local _custom_mesh = "units/cwv_es_musket_custom/cwv_es_musket_custom"
    local _donors = _om._husk_custom_unit_material_donors
    if type(_donors) ~= "table" or not _donors[_custom_mesh .. "_3p"] then
        return "Old Musket custom mesh has no declared 3P material donor -- #474 gate cannot protect it"
    end
    if _om._husk_unit_spawnable(_custom_mesh) ~= _om._husk_material_donor_ready(_custom_mesh) then
        return "_husk_unit_spawnable disagrees with the donor-material gate for the Old Musket custom mesh (#474 fail-closed contract)"
    end
    -- End-to-end SUPPRESS: the Outrider (base dr_deus_01) resolved by its wire
    -- skin, carrying ONLY a guaranteed-non-resident left-mount leftover, must
    -- return suppress=true so the spawn hook skips vanilla's left spawn. Synthetic
    -- leftover path keeps this deterministic whether or not the tester is in Chaos
    -- Wastes (the real Trollhammer mesh is resident there). Left hand: the Outrider
    -- has no_left_hand, so no override is written and the leftover survives.
    local iu_defer = {
        skin = "cwv_es_outrider_grenade_launcher_skin",
        left_hand_unit = "units/weapons/player/__cwv_rt_nonresident_478__/__cwv_rt_nonresident_478__",
    }
    if not _om._husk_rekey_units("left", { name = "dr_deus_01" }, iu_defer, nil) then
        return "resolved Outrider husk did NOT suppress a non-resident left-mount spawn -- #478 crash-floor broken"
    end
    -- Scope: with NO cwv def resolved (unknown base, no skin, no career), the
    -- re-key must NOT suppress -- a genuine native husk wield is never touched even
    -- when its leftover is non-resident (#475 Invariant 1 scope, no #478 overreach).
    if _om._husk_rekey_units("left", { name = "__cwv_rt_no_such_base__" },
            { left_hand_unit = "units/weapons/player/__cwv_rt_nonresident_478__/__cwv_rt_nonresident_478__" }, nil) then
        return "re-key suppressed a spawn with NO resolved cwv def -- #478 overreach into native wields (#475 Invariant 1)"
    end
end)

_rt_register("cwv_wire_safe_skin_installed", function()
    -- (issue 278 weapon_skin_id axis / issue 371 / issue 495) Every cwv-registered
    -- NetworkLookup.weapon_skins key must be null-able on the wire so a non-cwv peer
    -- never cold-decodes it from rpc_add_equipment (strict __index CTD). Asserts the
    -- wire-safety machinery is installed on ALL THREE live-slot senders and that the
    -- predicate covers every cwv key actually sitting in NetworkLookup.weapon_skins.
    if _om._skin_wire_hook_installed ~= true then
        return "weapon_skin_id wire-safety hooks not installed (issue 278 non-cwv-peer CTD regression)"
    end
    local surfaces = mod._cwv_skin_wire_surfaces
    if type(surfaces) ~= "table" then
        return "mod._cwv_skin_wire_surfaces flag table missing (issue 495 senders unhooked?)"
    end
    for _, key in ipairs({ "game_object_initialized", "spawn_resynced_loadout", "hot_join_sync" }) do
        if not surfaces[key] then
            return "skin-axis wire-null not registered on sender surface: " .. key .. " (issue 495)"
        end
    end
    if type(_om._skin_keys) ~= "table" or next(_om._skin_keys) == nil then
        return "no cwv skin keys tracked -- wire-safety would null nothing (registration/tracking broke)"
    end
    -- Every tracked key must actually be a registered weapon_skins entry, else the
    -- null-on-wire substitution is guarding a phantom -- and EVERY cwv_ key in the
    -- live lookup must satisfy the wire predicate (a registration site that forgot
    -- both registries is caught by the prefix arm; a non-cwv_-prefixed cwv key
    -- would be a real leak and fails here).
    local NL = rawget(_G, "NetworkLookup")
    local ws = NL and NL.weapon_skins
    local pred = _om._wire_skin_predicate
    if type(pred) ~= "function" then
        return "_om._wire_skin_predicate missing (issue 495)"
    end
    if type(ws) == "table" then
        for skin_key in pairs(_om._skin_keys) do
            if rawget(ws, skin_key) == nil then
                return string.format("tracked cwv skin key %s absent from NetworkLookup.weapon_skins", tostring(skin_key))
            end
        end
        for k in pairs(ws) do
            if type(k) == "string" and k:sub(1, 4) == "cwv_" and not pred(k) then
                return string.format("cwv weapon_skins key %s not covered by the wire predicate (issue 495 leak)", tostring(k))
            end
        end
    end
end)

_rt_register("issue741_cwv_skin_wire_unconditional", function()
    -- Same-mod presence cannot prove numeric NetworkLookup parity. The helper
    -- must null every CWV skin without even consulting the parity service, then
    -- restore the owner's live slot after the vanilla sender returns.
    local helper = _om._wire_null_skins
    if type(helper) ~= "function" then return "_om._wire_null_skins helper missing" end
    local real_pp = mod._cwv_peer_parity
    mod._cwv_peer_parity = {
        all_peers_have = function() error("appearance helper consulted parity") end,
    }
    local cwv = { skin = "cwv___rt741_fake_skin" }
    local vanilla = { skin = "wh_sword_skin_01" }
    local cwv_at_send, vanilla_at_send
    local ok, err = pcall(helper, { cwv, vanilla }, function()
        cwv_at_send, vanilla_at_send = cwv.skin, vanilla.skin
    end, "rt741")
    mod._cwv_peer_parity = real_pp
    if not ok then return "helper raised/consulted parity: " .. tostring(err) end
    if cwv_at_send ~= nil then return "CWV skin reached the vanilla numeric wire" end
    if vanilla_at_send ~= "wh_sword_skin_01" then return "vanilla skin was altered" end
    if cwv.skin ~= "cwv___rt741_fake_skin" then return "owner CWV skin was not restored" end
    if not (mod._cwv_skin_wire_surfaces
            and mod._cwv_skin_wire_surfaces.vanilla_skin_replay_retired) then
        return "unsafe vanilla skin replay is not marked retired"
    end
end)

_rt_register("cwv_wire_safe_thrown_variant_installed", function()
    -- (issue 424 / issue 371, BUG_CLASSES 31) The Tuskgor Javelin thrown axes
    -- (impact pickup names + the bomb's in-flight boar-spear husk /
    -- projectile_units) append cwv-only NetworkLookup indices that ride vanilla
    -- projectile/pickup spawn RPCs. Assert BOTH sender-side substitution hooks
    -- are installed AND that the pickup helper retains gameplay only with
    -- positive peer parity, while unconfirmed parity coerces every tracked
    -- modded index to a real vanilla one.
    if _om._tj_pickup_wire_hook_installed ~= true then
        return "thrown-pickup wire-safety senders not installed (issue 424 non-cwv-peer CTD regression)"
    end
    if _om._projectile_wire_hook_installed ~= true then
        return "in-flight projectile wire-safety hook not installed (issue 424 boar-spear husk CTD regression)"
    end
    if _om._cwv424_throw_gate_installed ~= true then
        return "mixed-lobby thrown-action gate not installed"
    end
    if _om._cwv424_actionutils_sender_guard_installed ~= true then
        return "grenade-slot ActionUtils sender guard not installed"
    end
    if _om._cwv424_transient_sender_guard_installed ~= true then
        return "transient projectile/husk hot-join sender guard not installed"
    end
    if _om._cwv424_hot_join_fence_installed ~= true then
        return "pre-roster hot-join fence not installed"
    end
    if _om._cwv424_feature_registered ~= true then
        return "Tuskgor Javelin parity feature not registered"
    end
    if type(_om.javelin_gate) ~= "table"
            or type(_om.javelin_gate.should_block) ~= "function" then
        return "Tuskgor Javelin pure gate policy missing"
    end
    -- Hot-join world sweep coverage. A cwv pickup that is merely LYING IN THE
    -- LEVEL crashes a joining non-cwv peer with no cwv RPC involved: the pickup
    -- game object carries a NetworkLookup.pickup_names INDEX and the joiner
    -- decodes it strictly at game_object_initializers_extractors.lua:3411. The
    -- grenade-slot bomb is the one that pool ejection alone cannot retract, so
    -- assert it is enrolled alongside the two thrown-javelin recovery pickups.
    local fenced = _om.javelin_gate.fenced_pickup_names
    if type(fenced) ~= "table" or #fenced == 0 then
        return "hot-join pickup fence registry empty (world-resident cwv pickups would reach a joiner)"
    end
    local fenced_set = {}
    for i = 1, #fenced do fenced_set[fenced[i]] = true end
    for _, required in ipairs({ "cwv_tuskgor_javelin_bomb" }) do
        if not fenced_set[required] then
            return string.format("%s not enrolled in the hot-join pickup fence (issue 424 world-resident pickup CTD)", required)
        end
    end
    for cwv_key in pairs(_om._tj_pickup_wire_map or {}) do
        if not fenced_set[cwv_key] then
            return string.format("%s not enrolled in the hot-join pickup fence", tostring(cwv_key))
        end
    end
    if type(_om._cwv424_remove_live_recovery_pickups) ~= "function" then
        return "hot-join world sweep not exposed"
    end
    if _om._cwv424_gate_close_sweep_installed ~= true then
        return "gate-close world sweep not installed (pool eject alone cannot retract a spawned bomb)"
    end
    local fake_cwv = { item_data = { mod_data = { backend_id = "cwv_es_javelin_001" } } }
    if not _om.javelin_gate.should_block(fake_cwv, "disabled") then
        return "unconfirmed parity did not disable a concrete Tuskgor Javelin"
    end
    if _om.javelin_gate.should_block(fake_cwv, "enabled") then
        return "confirmed parity did not restore a concrete Tuskgor Javelin"
    end
    if _om.javelin_gate.should_block({ item_data = { name = "we_javelin" } }, "disabled") then
        return "mixed-lobby gate disabled the native Kerillian Javelin control"
    end
    if type(_om._tj_pickup_disposition) ~= "function" then
        return "_om._tj_pickup_disposition helper missing"
    end
    if type(_om._tj_pickup_wire_map) ~= "table" or next(_om._tj_pickup_wire_map) == nil then
        return "no cwv thrown pickups tracked -- wire-safety would coerce nothing"
    end
    local policy = _om.thrown_wire_policy
    if type(policy) ~= "table" then return "thrown wire policy module missing" end
    local NL = rawget(_G, "NetworkLookup")
    local pn = NL and NL.pickup_names
    -- Drive every tracked cwv pickup key through the helper: it must SUBSTITUTE to
    -- its declared vanilla target, and that target must be a non-cwv key present
    -- in NetworkLookup.pickup_names on every peer.
    for cwv_key, vanilla_key in pairs(_om._tj_pickup_wire_map) do
        local disposition, safe = _om._tj_pickup_disposition(cwv_key, false)
        if disposition ~= policy.SUBSTITUTE or safe ~= vanilla_key then
            return string.format("pickup %s did not coerce to its vanilla target (got %s/%s)",
                tostring(cwv_key), tostring(disposition), tostring(safe))
        end
        if type(safe) ~= "string" or safe:sub(1, 4) == "cwv_" then
            return string.format("pickup substitute %s is not a vanilla key", tostring(safe))
        end
        if type(pn) == "table" and rawget(pn, safe) == nil then
            return string.format("pickup substitute %s absent from NetworkLookup.pickup_names", tostring(safe))
        end
        if _om._tj_pickup_disposition(cwv_key, true) ~= policy.RIDE_CUSTOM then
            return string.format("pickup %s was substituted despite a proven exact catalog", tostring(cwv_key))
        end
    end
    -- #424 three-valued invariant: a cwv-owned pickup with NO declared donor must
    -- resolve to DROP, never to "keep the custom id". This is the exact hole the
    -- grenade-slot bomb key fell through while the helper returned nil for both
    -- "parity confirmed" and "no fallback declared".
    if _om._tj_pickup_disposition("cwv_tuskgor_javelin_bomb", false) ~= policy.DROP then
        return "an undeclared cwv pickup key did not fail closed to DROP (issue 424 nil-ambiguity)"
    end
    -- Negative control: a genuine vanilla pickup rides unchanged, so the coercion
    -- can only ever touch cwv-owned keys.
    local vanilla_disposition, vanilla_name =
        _om._tj_pickup_disposition("ammo_throwing_axe_01_t1", false)
    if vanilla_disposition ~= policy.RIDE_CUSTOM or vanilla_name ~= "ammo_throwing_axe_01_t1" then
        return "wire-safe helper coerced a vanilla pickup name (should only map cwv keys)"
    end
    -- In-flight projectile axis: a fake projectile_units carrying the cwv
    -- boar-spear unit must NEVER survive the helper (its husk would reach the wire).
    if type(_om._wire_safe_projectile_units) == "function" then
        local coerced = _om._wire_safe_projectile_units({ projectile_unit_name = _om._TJ_INFLIGHT_MODDED_UNIT })
        if coerced and coerced.projectile_unit_name == _om._TJ_INFLIGHT_MODDED_UNIT then
            return "in-flight projectile helper let the cwv boar-spear husk survive to the wire path"
        end
        -- And a vanilla projectile_units must pass through untouched.
        local vanilla_in = { projectile_unit_name = "units/weapons/player/wpn_we_javelin_01/prj_we_javelin_01_3ps" }
        if _om._wire_safe_projectile_units(vanilla_in) ~= vanilla_in then
            return "in-flight projectile helper mutated a vanilla projectile (should pass through)"
        end
    end
end)

_rt_register("cwv_wire_safe_damage_profile_gate", function()
    -- (issue 423 / issue 371, BUG_CLASSES 31, GAMEPLAY axis) cwv clones append
    -- damage_profile keys to NetworkLookup.damage_profiles as modded indices that
    -- ride the client->server rpc_attack_hit (weapon_system.lua:182). A non-cwv
    -- HOST strict-decodes (weapon_system.lua:243) -> CTD. The send-gate degrades a
    -- modded index to its vanilla SOURCE id when peer parity is unconfirmed, and
    -- lets it ride under confirmed parity. Assert the hook is installed, NO tracked
    -- cwv profile can ever survive to the wire when parity is unconfirmed, and the
    -- gate decision honors parity + is_server (stubbed beacon like the skin gate).
    if _om._dp_wire_hook_installed ~= true then
        return "send_rpc_attack_hit wire-safety gate not installed (issue 423 non-cwv host CTD regression)"
    end
    local resolve = _om._wire_safe_damage_profile_id
    local decide  = _om._wire_dp_for_send
    if type(resolve) ~= "function" or type(decide) ~= "function" then
        return "wire-safe damage-profile helpers missing"
    end
    local NL = rawget(_G, "NetworkLookup")
    local dp = NL and NL.damage_profiles
    if type(dp) ~= "table" then return "NetworkLookup.damage_profiles absent" end

    -- (1) Crash-safety over EVERY cwv-registered profile: the resolver must coerce
    -- each modded index to a REAL vanilla index present on every peer.
    local checked = 0
    for k, v in pairs(dp) do
        if type(k) == "string" and k:sub(1, 4) == "cwv_" and type(v) == "number" then
            local safe = resolve(v)
            if type(safe) ~= "number" then
                return string.format("cwv profile %s did not resolve to a vanilla id (would ride to a non-cwv host)", k)
            end
            local safe_name = rawget(dp, safe)
            if type(safe_name) ~= "string" or safe_name:sub(1, 4) == "cwv_" then
                return string.format("cwv profile %s resolved to a non-vanilla id %s (%s)", k, tostring(safe), tostring(safe_name))
            end
            checked = checked + 1
        end
    end
    if checked == 0 then
        return "no cwv damage profiles registered -- wire-safety would coerce nothing (registration regressed?)"
    end

    -- (2) Negative control: a genuine vanilla profile id passes through untouched.
    local van_id = _om._cwv_wire_fallback_profile_id
    if type(van_id) == "number" and resolve(van_id) ~= nil then
        return "wire-safe resolver coerced a vanilla profile id (should only touch cwv keys)"
    end

    -- (3) Gameplay-axis behavioral gate with a stubbed beacon:
    -- pick any tracked cwv profile whose source differs, then drive the decision.
    local cwv_id, src_id
    for k, v in pairs(dp) do
        if type(k) == "string" and k:sub(1, 4) == "cwv_" and type(v) == "number" then
            local s = resolve(v)
            if type(s) == "number" and s ~= v then cwv_id, src_id = v, s; break end
        end
    end
    if cwv_id then
        -- #423 exact catalog: the sender reads mod._cwv_damage_peer_parity (the
        -- dedicated exact channel), not the presence beacon. Every accessor the
        -- verdict consults is stubbed, so a fixture that supplied only the raw
        -- classifier would pass for the wrong reason (a pcall on a missing
        -- accessor fails safe to "substitute" and would mask a real regression).
        local real_pp = mod._cwv_damage_peer_parity
        mod._cwv_damage_peer_parity = {
            is_installed   = function() return true end,
            all_peers_have = function() return false end,
            applied_state  = function() return "disabled" end,
        }
        local unconfirmed_client = decide(false, cwv_id)
        local host_authoritative = decide(true,  cwv_id)
        mod._cwv_damage_peer_parity = {
            is_installed   = function() return true end,
            all_peers_have = function() return true end,
            applied_state  = function() return "enabled" end,
        }
        local confirmed_client = decide(false, cwv_id)
        -- The divergent fixture is the point of the check: the roster classifier
        -- answers "all acked" while the gate has NOT committed. That is the live
        -- shape during SETTLE_ENABLE (_lib_peer_parity.lua:619-621) and after the
        -- synchronous hot-join fence force-disables. The sender must follow the
        -- committed state and keep substituting.
        mod._cwv_damage_peer_parity = {
            is_installed   = function() return true end,
            all_peers_have = function() return true end,
            applied_state  = function() return "disabled" end,
        }
        local settling_client = decide(false, cwv_id)
        mod._cwv_damage_peer_parity = real_pp
        if unconfirmed_client ~= src_id then
            return "parity-unconfirmed client did not degrade the cwv profile to its vanilla source (issue 423 CTD shape live)"
        end
        if confirmed_client ~= cwv_id then
            return "exact-confirmed client degraded the cwv profile (variant damage would regress under a proven exact catalog)"
        end
        if host_authoritative ~= cwv_id then
            return "is_server path substituted (host is authoritative; rpc_attack_hit runs in-process, no foreign decode)"
        end
        if settling_client ~= src_id then
            return "sender followed the raw roster classifier, not the committed parity state (issue 423 settle / hot-join window)"
        end
    end

    -- (4) Terminal fail-safe: an untracked future cwv profile first degrades to
    -- vanilla `default`; if even that vanilla row cannot be proven it is dropped,
    -- never returned as the original custom id (`safe or id` was the old leak).
    local policy = _om.damage_profile_wire
    if type(policy) ~= "table" or type(policy.for_send) ~= "function" then
        return "engine-free damage-profile wire policy missing"
    end
    local fixture = {
        [1] = "default", default = 1,
        [9] = "cwv___rt423_unmapped", cwv___rt423_unmapped = 9,
    }
    local fallback_id, fallback_disposition = policy.for_send(false, false, fixture, {}, 9)
    if fallback_id ~= 1 or fallback_disposition ~= "fallback" then
        return "unmapped cwv profile did not degrade to the boot-stable vanilla default"
    end
    fixture[1], fixture.default = nil, nil
    local dropped_id, dropped_disposition = policy.for_send(false, false, fixture, {}, 9)
    if dropped_id ~= nil or dropped_disposition ~= "drop" then
        return "unmapped cwv profile failed open after every vanilla fallback was removed"
    end
end)

-- ----------------------------------------------------------------------------
-- Peer-parity beacon regression checks (issue 371 / issue 424 / BUG_CLASSES 31)
-- ----------------------------------------------------------------------------
_rt_register("cwv_peer_parity_lib_loaded", function()
    -- The COPIED shared lib (master tools/shared_lib/_lib_peer_parity.lua) built
    -- an instance and exposed the contract API.
    local pp = mod._cwv_peer_parity
    if type(pp) ~= "table" then return "mod._cwv_peer_parity not built (lib load or factory failed)" end
    for _, m in ipairs({ "install", "register_gated_feature", "all_peers_have",
                         "tick", "feature_count", "applied_state", "is_installed" }) do
        if type(pp[m]) ~= "function" then return "beacon missing method: " .. m end
    end
end)

_rt_register("cwv_peer_parity_beacon_registered", function()
    -- The beacon's VMF mod-to-mod channel is registered (presence handshake).
    -- If VMF's network API is present (it is in-game), is_installed must be true.
    local pp = mod._cwv_peer_parity
    if type(pp) ~= "table" then return "beacon absent" end
    if type(mod.network_register) == "function" and not pp:is_installed() then
        return "beacon channel not registered despite VMF network_register present"
    end
end)

_rt_register("cwv_peer_parity_gated_feature_registered", function()
    -- At least one gated feature is registered (the Tuskgor Javelin bomb pool).
    local pp = mod._cwv_peer_parity
    if type(pp) ~= "table" then return "beacon absent" end
    if pp:feature_count() < 1 then
        return "gated-feature registry empty -- bomb pool injection was not registered behind the beacon"
    end
end)

_rt_register("cwv_peer_parity_failsafe_posture", function()
    -- Chosen posture: features are INERT until all peers are POSITIVELY confirmed.
    local pp = mod._cwv_peer_parity
    if type(pp) ~= "table" then return "beacon absent" end
    -- Immutable record of the init state (fail-safe = disabled at t0).
    if pp._initial_applied ~= "disabled" then
        return "beacon did not initialise to the fail-safe (disabled) state"
    end
    if pp.FAILSAFE_POSTURE ~= "feature_inert_until_confirmed" then
        return "beacon failsafe posture marker changed unexpectedly"
    end
    -- Pure classifier: solo (no peers) is trivially all-present; a present but
    -- un-acked peer must fail-safe to NOT-all-present; an acked peer counts.
    local c = pp.__classify
    if type(c) ~= "function" then return "beacon classifier (__classify) missing" end
    if c({}, {}) ~= true then return "solo (no other peers) must classify all-present" end
    if c({ p1 = true }, {}) ~= false then
        return "a present-but-unacked peer must fail-safe to NOT-all-present"
    end
    if c({ p1 = true }, { p1 = true }) ~= true then return "an acked peer must count as present" end
    if c({ p1 = true, p2 = true }, { p1 = true }) ~= false then
        return "a partially-acked lobby must classify NOT-all-present"
    end
    -- all_peers_have must never throw (pcall-wrapped internally -> false on error).
    local ok = pcall(function() return pp:all_peers_have() end)
    if not ok then return "all_peers_have threw (must fail-safe to false, never error)" end
end)

_rt_register("cwv_peer_parity_registration_unconditional", function()
    -- Class-31 invariant: the NetworkLookup / AllPickups / ItemMasterList
    -- REGISTRATION for the bomb pickup is never peer-gated; only the pool
    -- INJECTION (spawn/world axis) gates. The source marker records that split,
    -- and the gated feature's id is the POOL, not the registration.
    if _om._TJB_REGISTRATION_UNGATED_MARKER ~= "cwv-tjb-networklookup-registration-never-peer-gated" then
        return "registration-parity marker missing/altered -- registration must stay ungated (class 31)"
    end
end)

_rt_register("issue343_smoke_bomb_diagnostics", function()
    local probe = mod._cwv_smoke_bomb_probe
    if type(probe) ~= "table" or type(probe.classify) ~= "function"
            or type(probe.collect_snapshot) ~= "function" or type(probe.run) ~= "function"
            or type(probe.auto_run) ~= "function" then
        return "issue #343 smoke-bomb probe module did not load"
    end
    if probe.MAX_RUNS ~= 3 then
        return "issue #343 probe cap changed from three explicit runs"
    end
    local result = probe.classify({
        grenade_template = true, grenade_projectile = true,
        ranger_template = true, ranger_item = true, smoke_explosion = true,
        ranger_area_buff = true, buff_area_position_contract = true,
        pool_count = 3, pool_sum = 1,
    })
    if not (result.base_ready and result.area_ready and result.pool_healthy)
            or result.exact_z_scale_ready ~= false
            or result.registration_quarantined ~= true then
        return "issue #343 diagnostic truth table failed"
    end
end)

_rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    local ok = pcall(_dbg, "smoke test")
    if not ok then return "_dbg raised" end
    ok = pcall(_dbg_alert, "smoke test")
    if not ok then return "_dbg_alert raised" end
end)


_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/character_weapon_variants/character_weapon_variants_localization")
    if not ok or type(loc) ~= "table" then return end  -- can't reach loc; skip
    for k, v in pairs(loc) do
        if type(v) == "table" and type(v.en) == "string" then
            local fmt_ok, fmt_err = pcall(string.format, v.en)
            if not fmt_ok then
                return string.format(
                    "loc key %q has invalid format string (escape literal %% as %%%%): %s",
                    k, tostring(fmt_err))
            end
        end
    end
end)
_rt_register("mace_sword_rename_prefix_match", function()
    -- audit 2026-06-07 (F15, v0.1.349-dev): guard the mace+sword rename prefix
    -- match against off-by-one death. The prior `key:sub(1, 30) ==
    -- "es_dual_wield_hammer_sword_skin"` compared 30 chars against a 31-char
    -- literal, so it was ALWAYS false and the rename never fired for any
    -- skinned mace+sword. Behavioral assertion: a representative skin key MUST
    -- match the prefix, and a non-matching key MUST NOT.
    local has_prefix = mod._cwv_has_prefix
    local prefix = mod._cwv_mace_sword_skin_prefix
    if type(has_prefix) ~= "function" then
        return "_cwv_has_prefix helper missing"
    end
    if prefix ~= "es_dual_wield_hammer_sword_skin" then
        return string.format("unexpected mace+sword skin prefix: %q", tostring(prefix))
    end
    -- Representative key the player's inventory/cosmetics UI actually passes to
    -- Localize when a non-default illusion is applied (skin_02 + _name suffix).
    local rep_key = "es_dual_wield_hammer_sword_skin_02_name"
    if not has_prefix(rep_key, prefix) then
        return string.format(
            "prefix match FAILED for representative key %q (off-by-one regression: sub() length must equal #prefix=%d)",
            rep_key, #prefix)
    end
    -- Negative control: an unrelated key must NOT match.
    if has_prefix("es_dual_wield_hammer_falchion_skin_01_name", prefix) then
        return "prefix match spuriously succeeded for a non-mace+sword key"
    end
end)

_rt_register("weapon_appearance_module_present", function()
    -- Phase 1 (issue 409 + the rotation abstraction): the single WeaponAppearance
    -- module must own scale/offset/position/rotation and be reachable, and its
    -- rotation normalizer must accept {x,y,z} euler DEGREES, a QuaternionBox, and
    -- nil — so every render path shares ONE rotation math path instead of the four
    -- bespoke quaternion blocks this replaces.
    local WA = mod._cwv_weapon_appearance
    if type(WA) ~= "table" then return "mod._cwv_weapon_appearance (WeaponAppearance) missing" end
    for _, m in ipairs({ "apply", "apply_scale", "apply_offset", "apply_position", "apply_rotation" }) do
        if type(WA[m]) ~= "function" then return "WeaponAppearance." .. m .. " missing" end
    end
    local to_q = mod._wa_to_quaternion_for_rt
    if type(to_q) ~= "function" then return "rotation normalizer not exposed" end
    if to_q(nil) ~= nil then return "nil rotation must normalize to nil (leave native)" end
    if to_q({ 90, 0, 0 }) == nil then return "euler {90,0,0} did not normalize to a quaternion" end
    local ok_qb, qb = pcall(QuaternionBox, Quaternion.identity())
    if ok_qb and to_q(qb) == nil then return "QuaternionBox did not normalize to a quaternion" end
    if to_q({ "not", "numbers" }) ~= nil then return "non-numeric table must normalize to nil, not crash" end
end)

_rt_register("musket_old_force_registered", function()
    -- Issue 409: cwv_es_musket_old carries no generic scale/offset (native mesh),
    -- so before force_register it never entered _transform_map -> the preview /
    -- illusion-browser resolvers returned nil and bailed BEFORE its pose+texture
    -- block. force_register must put it in the map so the resolver-driven paths
    -- reach its apply. Regression: if the gate stops honoring force_register, the
    -- inventory preview mis-poses the musket again.
    local check = mod._cwv_transform_registered
    if type(check) ~= "function" then return "mod._cwv_transform_registered helper missing" end
    if not check("cwv_es_musket_old") then
        return "#409 regression: cwv_es_musket_old NOT registered in _transform_map (force_register gate broke)"
    end
end)

_rt_register("issue617_old_musket_preview_texture_consumer", function()
	if type(_om._apply_old_musket_textures) ~= "function" then
		return "Old Musket per-unit texture helper missing"
	end
	local resources_ready = _om._old_musket_texture_resources_ready
	if type(resources_ready) ~= "function" then
		return "Old Musket C-call resource preflight missing"
	end
	local seen = {}
	local ready, detail = resources_ready(function(kind, path)
		seen[path] = kind
		return true
	end)
	local seen_count = 0
	for _, kind in pairs(seen) do
		if kind ~= "texture" then return "resource preflight queried a non-texture" end
		seen_count = seen_count + 1
	end
	if not ready or detail ~= nil or seen_count ~= 3 then
		return "resource preflight must prove all three authored textures"
	end
	local denied, missing = resources_ready(function(_, path)
		return not path:find("_albedo", 1, true)
	end)
	if denied or not missing or not missing:find("_albedo", 1, true) then
		return "resource preflight must fail closed on one missing texture"
	end
	local plan = _om._old_musket_preview_texture_targets
	if type(plan) ~= "function" then
		return "Old Musket LootItemUnitPreviewer target planner missing"
	end
	local custom_3p, vanilla_fallback, custom_base = {}, {}, {}
	local def = _om._old_musket_preview_descriptor({
		backend_id = "cwv_es_musket_old_regression_617",
		cwv_key = "cwv_es_musket_old",
	})
	if not def or not def.right_hand_unit or not def.right_hand_unit.unit then
		return "canonical Old Musket descriptor did not resolve for preview regression"
	end
	local custom_path = def.right_hand_unit.unit
	local targets = plan(def,
		{ custom_3p, vanilla_fallback, custom_base },
		{
			{ unit_name = def.right_hand_unit.unit_3p },
			{ unit_name = "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1_3p" },
			{ unit_name = custom_path },
		})
	if #targets ~= 2 or targets[1] ~= custom_3p or targets[2] ~= custom_base then
		return "preview target planner must paint both custom paths and reject vanilla fallback"
	end
	if #plan(def, { vanilla_fallback }, { {
			unit_name = def.fallback.right_hand_unit.unit_3p,
		} }) ~= 0 then
		return "preview target planner painted the canonical vanilla fallback"
	end
	if #plan(nil, { custom_3p }, { { unit_name = def.right_hand_unit.unit_3p } }) ~= 0 then
		return "preview target planner accepted a missing/non-Old-Musket descriptor"
	end
end)

_rt_register("issue742_old_musket_texture_material_preflight", function()
	local policy = _om.old_musket_preview
	local census = policy and policy.unit_materials_ready
	if type(census) ~= "function" then
		return "Old Musket unit-material preflight policy missing"
	end
	local meshes = {
		{ "#ID[12345678]" },
		{ "#ID[abcdef01]" },
	}
	local unit_api = {
		num_meshes = function() return #meshes end,
		mesh = function(_, index) return meshes[index + 1] end,
	}
	local mesh_api = {
		num_materials = function(mesh) return #mesh end,
		material = function(mesh, index) return mesh[index + 1] end,
	}
	local ready, count = census({}, unit_api, mesh_api)
	if not ready or count ~= 2 then
		return "material preflight rejected a fully bound two-mesh unit"
	end
	meshes[2][1] = "#ID[00000000]"
	local denied, reason = census({}, unit_api, mesh_api)
	if denied or reason ~= "material-null-1-0" then
		return "material preflight must reject a null binding on any mesh"
	end
end)

_rt_register("preview_meshswap_guards", function()
    -- Issue 237 (WEAPON_APPEARANCE_STANDARD §4.1): the inventory-preview
    -- unit-resolution layer rewrites spawn_data entry.unit_name to the cwv
    -- variant's authored mesh. The GUARDS are load-bearing: a non-cwv backend_id
    -- or a user-selected illusion (non-empty skin) must leave spawn_data
    -- untouched, and the helper must be reachable. The positive rewrite depends
    -- on runtime package residency, so it is covered by the in-game verify.
    local apply = mod._cwv_preview_meshswap_apply
    if type(apply) ~= "function" then return "mod._cwv_preview_meshswap_apply missing" end
    local function _mk() return { spawn_data = { { right_hand = true, unit_name = "BASE_3p" } } } end
    local a = _mk(); apply("es_sword_shield", "es_sword_shield_001", nil, a)
    if a.spawn_data[1].unit_name ~= "BASE_3p" then return "#237 guard: non-cwv backend_id must not rewrite" end
    local b = _mk(); apply("es_sword_shield", "cwv_we_sword_shield_001", "some_skin", b)
    if b.spawn_data[1].unit_name ~= "BASE_3p" then return "#237 guard: user-selected illusion (skin) must win, no rewrite" end
    local c = _mk(); c.skin_name = "stored_preview_skin"
    apply("es_sword_shield", "cwv_we_sword_shield_001", nil, c)
    if c.spawn_data[1].unit_name ~= "BASE_3p" then
        return "#579 guard: info.skin_name must win when copied preview callback drops skin arg"
    end
    -- #237/#419 resolved-3p contract: the historical collapsed guard
    -- (`resolver or blind base.."_3p" concat`) must FAIL. The spawn-target
    -- resolver honors the husk answer, then the injected spawn floor; a
    -- sentinel, foreign-prefix, or floor-declined target degrades to the base
    -- mesh; packaged units/cwv_ families still resolve through the floor.
    local gate = _om.exact_appearance and _om.exact_appearance.resolve_preview_3p
    if type(gate) ~= "function" then return "#237/#419 resolve_preview_3p policy missing" end
    if type(_om._preview_override_3p) ~= "function" then
        return "#237/#419 _om._preview_override_3p production gate missing"
    end
    local yes, no = function() return true end, function() return false end
    if gate("units/weapons/player/wpn_rt237/wpn_rt237", nil, no) ~= nil then
        return "#237/#419 collapsed guard regressed: floor-declined vanilla target must degrade to base"
    end
    if gate("units/weapons/player/wpn_invisible_weapon/wpn_invisible_weapon", nil, yes) ~= nil then
        return "#237/#419 invisible-weapon sentinel must degrade to base, never blind concat"
    end
    if gate("units/beings/player/rt237/rt237", nil, yes) ~= nil then
        return "#237/#419 non-player-prefix target must degrade to base, never blind concat"
    end
    if gate("units/weapons/player/wpn_rt237/wpn_rt237", nil, yes)
            ~= "units/weapons/player/wpn_rt237/wpn_rt237_3p" then
        return "#237/#419 floor-confirmed vanilla target must still resolve (preview swap lost)"
    end
    if gate("units/cwv_es_musket_custom/cwv_es_musket_custom", nil, yes)
            ~= "units/cwv_es_musket_custom/cwv_es_musket_custom_3p" then
        return "#237/#419 packaged units/cwv_ family must still resolve (preview swap lost)"
    end
    if gate("units/cwv_es_musket_custom/cwv_es_musket_custom", nil, no) ~= nil then
        return "#474 musket floor decline must degrade to base (MeshObject AV guard lost)"
    end
    if gate("units/weapons/player/wpn_rt237/wpn_rt237",
            function(u) return u .. "_3p" end, no) ~= "units/weapons/player/wpn_rt237/wpn_rt237_3p" then
        return "#418 husk-resident resolver answer must stay final (co-op path changed)"
    end
end)

_rt_register("browser_meshswap_guards", function()
    -- Issue #419 (WEAPON_APPEARANCE_STANDARD §3 path 4): the illusion-browser
    -- spawn_units pre-pass rewrites spawn_data unit_name to the cwv variant's
    -- authored mesh when the upstream BackendUtils.get_item_units resolution
    -- missed (the browser rebinds item_data to the BASE IML entry, so the #482
    -- stamp rung is dead there; a UUID-bid crafted instance can fall through).
    -- The GUARDS are load-bearing: an applied illusion (item.skin) must win,
    -- and a non-cwv item must pass untouched. The positive rewrite depends on
    -- runtime package residency, so it is covered by the in-game verify.
    local apply = mod._cwv_browser_meshswap_apply
    if type(apply) ~= "function" then return "mod._cwv_browser_meshswap_apply missing" end
    local UNTOUCHED = "units/weapons/player/wpn_rt419/wpn_rt419_3p"
    local sd = { { unit_name = UNTOUCHED } }
    apply({ backend_id = "es_sword_shield_rt419", data = { name = "es_sword_shield" } }, sd)
    if sd[1].unit_name ~= UNTOUCHED then return "#419 guard: non-cwv item must not rewrite" end
    sd = { { unit_name = UNTOUCHED } }
    apply({ backend_id = "cwv_es_greataxe_001", skin = "some_skin", data = nil }, sd)
    if sd[1].unit_name ~= UNTOUCHED then return "#419 guard: applied illusion (skin) must win, no rewrite" end
    -- #237/#419 resolved-3p contract on the base_identity adapter: when the
    -- residency resolver declines, the adapter must DEGRADE to the recipe's
    -- authored base mesh -- the historical collapsed guard blind-concatenated
    -- base.."_3p" and rewrote anyway (the #403 class the safety contract at
    -- the descriptor site documents).
    local policy = _om.exact_appearance
    if type(policy) ~= "table" or type(policy.resolve_spawn_descriptor) ~= "function" then
        return "#419 exact_appearance descriptor policy missing"
    end
    local descriptor = policy.resolve_spawn_descriptor({
        variant = { item_key = "cwv_rt419",
            right_hand_unit = "units/weapons/player/wpn_rt419v/wpn_rt419v" },
        base = { right_hand_unit = "units/weapons/player/wpn_rt419/wpn_rt419" },
    })
    if not descriptor then return "#419 degrade-probe descriptor failed to resolve" end
    local probe = { { unit_name = UNTOUCHED } }
    local swapped = policy.apply_spawn_descriptor(
        descriptor, probe, function() return nil end, "base_identity")
    if swapped ~= 0 or probe[1].unit_name ~= UNTOUCHED then
        return "#419 resolver decline must degrade to the base mesh (blind concat regressed)"
    end
    swapped = policy.apply_spawn_descriptor(descriptor, probe, nil, "base_identity")
    if swapped ~= 0 or probe[1].unit_name ~= UNTOUCHED then
        return "#419 missing resolver must fail closed to the base mesh (collapsed guard regressed)"
    end
end)

_rt_register("issue419_browser_prepass_precedes_vanilla_spawn", function()
    -- Issue #419, re-review path 1. `browser_meshswap_guards` above proves the
    -- NEGATIVE controls and the pure adapter, but it never carries a stamped
    -- crafted instance through the production helper and never touches the
    -- LootItemUnitPreviewer wrapper -- so deleting the pre-pass restored the
    -- base-mesh-plus-variant-transform symptom while it stayed green. This
    -- check drives both halves of the live contract.
    local apply = mod._cwv_browser_meshswap_apply
    local wrapper = mod._cwv_browser_spawn_units
    if type(apply) ~= "function" then return "#419 browser mesh-swap helper missing" end
    if type(wrapper) ~= "function" then
        return "#419 browser spawn_units wrapper is not a named, drivable seam -- hook delivery is unprovable"
    end
    local iml = rawget(_G, "ItemMasterList")
    if type(iml) ~= "table" then return "ItemMasterList not loaded yet (run in-keep)" end

    -- GROUND TRUTH (#1156): the authored catalog picks the fixture -- a REGISTERED
    -- variant that overrides its base's right hand. Never the resolver under test,
    -- and never the collapsed base value the defect produces.
    local def, base
    for _, candidate in ipairs(_variant_definitions) do
        if not candidate.skin_only and _registered_keys[candidate.item_key]
                and type(candidate.right_hand_unit) == "string"
                and not candidate.right_hand_unit:find("wpn_invisible_weapon", 1, true) then
            local entry = rawget(iml, candidate.base_weapon)
            if type(entry) == "table" and type(entry.right_hand_unit) == "string"
                    and entry.right_hand_unit ~= candidate.right_hand_unit then
                def, base = candidate, entry
                break
            end
        end
    end
    if not def then
        return "#419 no registered variant overrides its base right hand -- fixture cannot be built"
    end
    local BASE_3P = base.right_hand_unit .. "_3p"
    local WANT_3P = def.right_hand_unit .. "_3p"

    -- The exact shape the issue is about: an Athanor craft. Its backend_id is a
    -- guid, so the #482 bid-pattern rung CANNOT match and identity survives only
    -- through the mod_data stamp -- the rung `_load_item_units` kills by rebinding
    -- item_data to the base master-list entry before asking for units.
    local function crafted_item()
        return {
            backend_id = "rt419-3f9d5218-b649-4a59-bdb0-0ac51415ce46",
            data = {
                name = def.base_weapon,
                key = def.base_weapon,
                mod_data = { cwv_key = def.item_key },
            },
        }
    end

    -- Residency is a runtime fact the keep cannot supply for every variant, so
    -- substitute the production spawn-target gate for the drive and restore it.
    local saved_resolver = _om._preview_override_3p
    local observed, result
    local ok, err = pcall(function()
        _om._preview_override_3p = function(unit) return unit .. "_3p" end

        -- (a) the helper itself rewrites a stamped crafted instance.
        local rows = { { unit_name = BASE_3P } }
        apply(crafted_item(), rows)
        if rows[1].unit_name ~= WANT_3P then
            result = "#419 stamped crafted instance did not reach the variant mesh: got "
                .. tostring(rows[1].unit_name)
            return
        end

        -- (b) DELIVERY: the real wrapper must rewrite BEFORE vanilla reads the
        -- recipe. The spy stands in for vanilla spawn_units and records what it
        -- was actually handed; returning nil keeps the post-spawn transform pass
        -- out of the drive (it needs live units).
        local spy_saw
        local spy = function(_, spawn_data)
            spy_saw = spawn_data[1] and spawn_data[1].unit_name
            return nil
        end
        wrapper(spy, { _item = crafted_item() }, { { unit_name = BASE_3P } })
        if spy_saw ~= WANT_3P then
            result = "#419 vanilla spawn_units received " .. tostring(spy_saw)
                .. " -- the mesh-swap pre-pass did not run before the spawn"
            return
        end

        -- (c) negative control through the SAME delivery path: a non-cwv item is
        -- handed to vanilla untouched.
        spy_saw = nil
        wrapper(spy, { _item = { backend_id = "rt419-native", data = { name = def.base_weapon } } },
            { { unit_name = BASE_3P } })
        if spy_saw ~= BASE_3P then
            result = "#419 native item was rewritten on the browser path: " .. tostring(spy_saw)
        end
    end)
    _om._preview_override_3p = saved_resolver
    if not ok then return "#419 browser delivery drive errored: " .. tostring(err) end
    return result
end)

_rt_register("issue660_preview_descriptor_adapter_parity", function()
    local policy = _om.exact_appearance
    if type(policy) ~= "table" or type(policy.resolve_spawn_descriptor) ~= "function"
            or type(policy.apply_spawn_descriptor) ~= "function" then
        return "#660 canonical preview descriptor/adapter API missing"
    end
    local descriptor, reason = policy.resolve_spawn_descriptor({
        variant = {
            item_key = "cwv_rt660",
            right_hand_unit = "variant_right",
            left_hand_unit = "variant_left",
        },
        base = {
            right_hand_unit = "base_right",
            left_hand_unit = "base_left",
        },
    })
    if not descriptor then return "#660 descriptor failed: " .. tostring(reason) end
    local fingerprint = descriptor.fingerprint
    local inventory = {
        { right_hand = true, unit_name = "base_right_3p" },
        { left_hand = true, unit_name = "base_left_3p" },
    }
    local browser = {
        { unit_name = "base_left_3p" },
        { unit_name = "base_right_3p" },
    }
    local resolve = function(unit) return unit .. "_3p" end
    local a = policy.apply_spawn_descriptor(descriptor, inventory, resolve, "hand_flags")
    local b = policy.apply_spawn_descriptor(descriptor, browser, resolve, "base_identity")
    if a ~= 2 or b ~= 2
            or inventory[1].unit_name ~= "variant_right_3p"
            or inventory[2].unit_name ~= "variant_left_3p"
            or browser[1].unit_name ~= "variant_left_3p"
            or browser[2].unit_name ~= "variant_right_3p" then
        return "#660 preview adapters did not converge on the descriptor's exact hand units"
    end
    if descriptor.fingerprint ~= fingerprint then
        return "#660 preview adapter mutated the canonical descriptor"
    end
end)

_rt_register("issue279_no_ammo_preview_descriptor", function()
    local policy = _om.exact_appearance
    if type(policy) ~= "table" or type(policy.resolve_spawn_descriptor) ~= "function"
            or type(policy.apply_spawn_descriptor) ~= "function" then
        return "#279 canonical preview descriptor/adapter API missing"
    end
    local descriptor, reason = policy.resolve_spawn_descriptor({
        variant = {
            item_key = "cwv_es_outrider_grenade_launcher",
            right_hand_unit = "rt_launcher",
            no_ammo_unit = true,
        },
        base = { right_hand_unit = "rt_trollhammer" },
    })
    if not descriptor then return "#279 descriptor failed: " .. tostring(reason) end
    -- Real engine recipe shape: vanilla stamps `is_ammo_unit = ammo_unit ~= nil`
    -- onto the WEAPON row itself (world_hero_previewer.lua:707/731); there is no
    -- dedicated ammo-only row. The adapter must CLEAR the inherited ammo flag
    -- and rewrite the row -- deleting flagged rows would vanish the weapon.
    local recipe = {
        { right_hand = true, is_ammo_unit = true, unit_name = "rt_trollhammer_3p" },
    }
    local changed = policy.apply_spawn_descriptor(descriptor, recipe,
        function(unit) return unit .. "_3p" end, "hand_flags")
    if changed ~= 2 or #recipe ~= 1 or recipe[1].unit_name ~= "rt_launcher_3p"
            or recipe[1].is_ammo_unit ~= nil then
        return "#279 inherited ammo flag was not cleared off the weapon row"
    end
    if policy.apply_spawn_descriptor(descriptor, recipe,
            function(unit) return unit .. "_3p" end, "hand_flags") ~= 0 then
        return "#279 descriptor application is not idempotent"
    end
end)

_rt_register("give_refuses_skin_only", function()
    -- Issue #538: /cwv_give must REFUSE skin_only (illusion-only) variants. Giving
    -- one builds a backend_id and mirrors the def into ItemMasterList, resurrecting
    -- the issue-390 crafts-as-wrong-item class for that key. Two locks:
    --  (1) the guard predicate exists and discriminates on def.skin_only (io is nil
    --      in the retail sandbox, so a source self-grep check is impossible -- this
    --      predicate is the testable seam the give command shares), and
    --  (2) the standing invariant it protects: no skin_only variant is ever present
    --      in _registered_keys. _auto_register_all excludes them (:9665) and the
    --      give guard is the only other registration entry point.
    local pred = _om._give_refuses_skin_only
    if type(pred) ~= "function" then return "_om._give_refuses_skin_only guard missing (#538)" end
    if pred({ skin_only = true }) ~= true then return "#538 guard: skin_only def must be refused" end
    if pred({ skin_only = nil }) ~= false then return "#538 guard: real (non-skin_only) def must be allowed" end
    if pred(nil) ~= false then return "#538 guard: nil def must not raise" end
    local leaked = {}
    for _, d in ipairs(_variant_definitions) do
        if d.skin_only and _registered_keys[d.item_key] then
            leaked[#leaked + 1] = d.item_key
        end
    end
    if #leaked > 0 then
        return "#538: skin_only variant(s) leaked into the ownable registry: " .. table.concat(leaked, ", ")
    end
end)

_rt_register("issue592_bounded_blacksmith_acquisition", function()
	local ownership = mod._cwv_acquisition
	if type(ownership) ~= "table" then return "#592 acquisition helper missing" end
	local legacy = ownership.legacy_auto_grant_ids(_variant_definitions)
	if not legacy.cwv_es_musket_old_001 or not legacy.cwv_es_musket_old_002 then
		return "#592 historical multi-instance migration ledger incomplete"
	end
	if ownership.should_remove("cwv_es_musket_old_001", legacy, function() return false end) ~= true then
		return "#592 exact historical auto-grant was not removable"
	end
	if ownership.should_remove("cwv_es_musket_old_001", legacy, function() return true end) ~= false then
		return "#592 exact CIM-owned craft was not preserved"
	end
	if ownership.should_remove("cwv_es_musket_old_100", legacy, function() return false end) ~= false then
		return "#592 CIM craft range was captured by migration"
	end
	local seeds = mod._cwv_blacksmith_seed_ids
	if type(seeds) ~= "table" then return "#592 seed ledger missing" end
	local expected, observed = 0, 0
	for _ in pairs(seeds) do observed = observed + 1 end
	local backend_items = Managers.backend and Managers.backend:get_interface("items")
	for _, def in ipairs(_variant_definitions) do
		if ownership.is_seed_eligible(def) and _registered_keys[def.item_key] then
			expected = expected + 1
			-- The runtime ledger is authoritative when a CIM-owned _001 forced
			-- the collision fallback; accept exactly one of the two bounded ids.
			if not seeds[def.item_key .. "_001"] and not seeds[def.item_key .. "_000"] then
				return "#592 Blacksmith seed missing: " .. tostring(def.item_key)
			end
			local seed_id = seeds[def.item_key .. "_001"] and def.item_key .. "_001"
				or def.item_key .. "_000"
			local item
			if backend_items then
				pcall(function() item = backend_items:get_item_from_id(seed_id) end)
			end
			if not item then return "#592 live Blacksmith item missing: " .. tostring(seed_id) end
			if item.rarity ~= "default" or tonumber(item.power_level) ~= 5
					or item.skin ~= nil then
				return "#592 malformed Blacksmith seed: " .. tostring(seed_id)
			end
			local row = ItemMasterList and rawget(ItemMasterList, def.item_key)
			if not row or row.cwv_definition ~= true or row.mod_data ~= nil then
				return "#592 definition row acquired backend identity: " .. tostring(def.item_key)
			end
		end
	end
	if observed ~= expected or mod._cwv_blacksmith_seed_count ~= expected then
		return string.format("#592 seed cardinality drift expected=%d ledger=%d built=%s",
			expected, observed, tostring(mod._cwv_blacksmith_seed_count))
	end
end)

_rt_register("cwv_crowbill_family_registration_contract", function()
	local family = mod._cwv_crowbill_family
	local hammer = mod._cwv_crowbill_hammer_mode
	if type(family) ~= "table" or type(hammer) ~= "table" then
		return "Crowbill family or hammer-mode policy missing"
	end
	if hammer.SOURCE_TEMPLATE_KEY ~= family.SOURCE_TEMPLATE
			or hammer.HAMMER_CLEAVE_MULT ~= family.HAMMER_MODE.attack_cleave_multiplier
			or hammer.HAMMER_DAMAGE_MULT ~= family.HAMMER_MODE.direct_damage_multiplier
			or hammer.MODEL_FLIP_DEGREES ~= family.HAMMER_MODE.rotation_degrees then
		return "Crowbill registration and hammer-mode constants drifted"
	end
	for _, variant in ipairs(family.VARIANTS) do
		local entry = ItemMasterList and rawget(ItemMasterList, variant.key)
		if type(entry) ~= "table" or entry.cwv_variant ~= true
				or entry.cwv_definition ~= true or entry.mod_data ~= nil then
			return variant.key .. " definition row acquired backend identity"
		end
		if entry.template ~= family.SOURCE_TEMPLATE
				or entry.item_type ~= variant.key
				or entry.skin_combination_table ~= variant.key .. "_skins"
				or entry.crowbill_mode_family ~= family.HAMMER_MODE_FAMILY then
			return variant.key .. " registration contract drifted"
		end
	end
end)

_rt_register("issue604_imperial_crowbill_model05_transform", function()
	local family = mod._cwv_crowbill_family
	if type(_skin_transform_map) ~= "table" then
		return "#604 Crowbill regression skin-transform dependency missing"
	end
	if type(family) ~= "table" or type(family.MODELS) ~= "table" then
		return "#604 Crowbill model manifest missing"
	end
	local function same_triplet(actual, expected)
		return type(actual) == "table"
			and actual[1] == expected[1] and actual[2] == expected[2]
			and actual[3] == expected[3]
	end
	local target
	for _, model in ipairs(family.MODELS) do
		if model.key == "cwv_es_imperial_crowbill_skin_05" then target = model; break end
	end
	if not target
			or not same_triplet(target.right_hand_scale, { 0.45, 0.45, 0.45 })
			or not same_triplet(target.right_hand_offset, { 0, -0.03, -0.20 })
			or not same_triplet(target.right_hand_rotation, { -90, -90, -90 }) then
		return "#604 Imperial Crowbill Model 05 reviewed transform drifted"
	end
	local applied = _skin_transform_map[target.key]
	if not applied
			or not same_triplet(applied.right_hand_scale, target.right_hand_scale)
			or not same_triplet(applied.right_hand_offset, target.right_hand_offset)
			or not same_triplet(applied.right_hand_rotation, target.right_hand_rotation)
			or applied.right_hand_scale_1p or applied.right_hand_offset_1p
			or applied.right_hand_rotation_1p or applied.right_hand_scale_3p
			or applied.right_hand_offset_3p or applied.right_hand_rotation_3p then
		return "#604 Model 05 transform is not on the canonical all-surface map"
	end
	for _, model in ipairs(family.MODELS) do
		if model.key ~= target.key and model.key ~= "cwv_dr_dawi_crowbill_skin" then
			local control = _skin_transform_map[model.key]
			if not control or control.right_hand_scale
					or control.right_hand_offset or control.right_hand_rotation then
				return "#604 Model 05 transform leaked to " .. tostring(model.key)
			end
		end
	end
	if type(_om._cwv_select_husk_transform_def) ~= "function"
			or type(_om._cwv_husk_transform_apply_plan) ~= "function" then
		return "#604 remote husk transform boundary missing"
	end
	local exact = {
		variant_key = target.variant_key,
		right_hand_unit = target.right_hand_unit,
	}
	local selected, source = _om._cwv_select_husk_transform_def("right", exact,
		{ name = family.SOURCE_ITEM }, nil, target.right_hand_unit, nil)
	local plan = _om._cwv_husk_transform_apply_plan("right", selected, source)
	if selected ~= applied or source ~= "exact_model" or not plan
			or plan.should_apply ~= true or plan.durable ~= true
			or not same_triplet(plan.scale, { 0.45, 0.45, 0.45 })
			or plan.scale_multiplier ~= nil
			or not same_triplet(plan.offset, { 0, -0.03, -0.20 })
			or not same_triplet(plan.rotation, { -90, -90, -90 }) then
		return "#604 exact Imperial husk does not preserve its canonical absolute transform"
	end
end)

_rt_register("issue604_dawi_crowbill_model01_transform", function()
	local family = mod._cwv_crowbill_family
	if type(_skin_transform_map) ~= "table"
			or type(_transform_map) ~= "table"
			or type(_crowbill_transform_by_unit) ~= "table" then
		return "#604 Crowbill regression transform dependencies missing"
	end
	if type(family) ~= "table" or type(family.MODELS) ~= "table" then
		return "#604 Crowbill model manifest missing"
	end
	local function same_triplet(actual, expected)
		return type(actual) == "table"
			and actual[1] == expected[1] and actual[2] == expected[2]
			and actual[3] == expected[3]
	end
	local target
	for _, model in ipairs(family.MODELS) do
		if model.key == "cwv_dr_dawi_crowbill_skin" then target = model; break end
	end
	if not target
			or not same_triplet(target.right_hand_scale_multiplier_3p, { 0.5, 0.5, 0.5 })
			or not same_triplet(target.right_hand_rotation_1p, { -90, -90, -90 })
			or not same_triplet(target.right_hand_rotation_3p, { -90, -90, -90 })
			or target.right_hand_offset
			or target.right_hand_scale or target.right_hand_rotation
			or target.right_hand_scale_1p then
		return "#604 Dawi Crowbill Model 01 reviewed transform drifted"
	end
	local applied = _skin_transform_map[target.key]
	if not applied
			or not same_triplet(applied.right_hand_scale_multiplier_3p,
				target.right_hand_scale_multiplier_3p)
			or not same_triplet(applied.right_hand_rotation_1p, target.right_hand_rotation_1p)
			or not same_triplet(applied.right_hand_rotation_3p, target.right_hand_rotation_3p)
			or applied.right_hand_offset
			or applied.right_hand_scale or applied.right_hand_rotation
			or applied.right_hand_scale_1p then
		return "#604 Dawi Model 01 transform is not isolated to the canonical perspective map"
	end
	local unit_def = _crowbill_transform_by_unit[target.right_hand_unit]
	local unit_3p_def = _crowbill_transform_by_unit[target.right_hand_unit .. "_3p"]
	if unit_def ~= applied or unit_3p_def ~= applied then
		return "#604 Dawi exact unit-path resolver is not bound to Model 01"
	end
	if _transform_map[target.variant_key] ~= applied then
		return "#604 skinless Dawi default variant does not resolve Model 01 transform"
	end
	if type(_om._cwv_resolve_crowbill_transform) ~= "function"
			or type(_om._cwv_crowbill_transform_delivery) ~= "table" then
		return "#604 Crowbill runtime delivery/diagnostic seam missing"
	end
	if type(_om._cwv_select_husk_transform_def) ~= "function"
			or type(_om._cwv_husk_transform_apply_plan) ~= "function" then
		return "#604 remote husk transform boundary missing"
	end
	local exact = {
		variant_key = target.variant_key,
		right_hand_unit = target.right_hand_unit,
	}
	local selected, source = _om._cwv_select_husk_transform_def("right", exact,
		{ name = family.SOURCE_ITEM }, nil, target.right_hand_unit, nil)
	local plan = _om._cwv_husk_transform_apply_plan("right", selected, source)
	if selected ~= applied or source ~= "exact_model" or not plan
			or plan.should_apply ~= true or plan.durable ~= true
			or plan.scale ~= nil
			or not same_triplet(plan.scale_multiplier, { 0.5, 0.5, 0.5 })
			or not same_triplet(plan.rotation, { -90, -90, -90 }) then
		return "#604 exact Dawi husk does not select/apply its canonical durable 3P transform"
	end
	local mismatch = _om._cwv_select_husk_transform_def("right", exact,
		{ name = family.SOURCE_ITEM }, nil, family.PLACEHOLDER_UNIT, nil)
	if mismatch ~= nil then
		return "#604 exact Dawi transform did not fail closed on post-rekey unit mismatch"
	end
	local control
	for _, model in ipairs(family.MODELS) do
		if model.variant_key == "cwv_es_imperial_crowbill"
				and model.right_hand_scale == nil and model.right_hand_offset == nil
				and model.right_hand_rotation == nil and model.right_hand_scale_3p == nil
				and model.right_hand_rotation_3p == nil then
			control = model
			break
		end
	end
	local control_def, control_source = control and _om._cwv_select_husk_transform_def(
		"right", { variant_key = control.variant_key, right_hand_unit = control.right_hand_unit },
		{ name = family.SOURCE_ITEM }, nil, control.right_hand_unit, nil)
	local control_plan = _om._cwv_husk_transform_apply_plan("right", control_def, control_source)
	if not control or not control_def or control_source ~= "exact_model" or not control_plan
			or control_plan.should_apply ~= false or control_plan.durable ~= false
			or control_plan.scale or control_plan.scale_multiplier
			or control_plan.offset or control_plan.rotation then
		return "#604 Dawi remote transform leaked into the untuned Imperial control"
	end
	local native_def, native_source = _om._cwv_select_husk_transform_def("right", nil,
		{ name = family.SOURCE_ITEM }, nil, family.PLACEHOLDER_UNIT, nil)
	if native_def ~= nil or native_source ~= "miss" then
		return "#604 native Sienna Crowbill acquired a CWV transform"
	end
	local evidence = _om._cwv_crowbill_transform_evidence
	local retained_diag = evidence and evidence:stats()
	if type(retained_diag) ~= "table" or retained_diag.limit ~= 96
			or retained_diag.per_model_limit ~= 16
			or type(retained_diag.count) ~= "number"
			or retained_diag.count < 0 or retained_diag.count > retained_diag.limit then
		return "#604 dedicated retained-state diagnostics are missing or unbounded"
	end
end)

_rt_register("issue604_preview_alias_teardown_contract", function()
	local bridge = _om.mod_unit_preview
	local family = _om.crowbill_family
	if type(bridge) ~= "table" or type(bridge.reconcile_for_unload) ~= "function"
			or type(bridge.claim_teardown) ~= "function" then
		return "Crowbill preview teardown policy missing"
	end
	local custom = family.MODELS[1].right_hand_unit .. "_3p"
	local alias = family.PREVIEW_PACKAGE_ALIAS
	local previewer = {
		_loaded_packages = { [custom] = true },
		_packages_to_load = { [custom] = false },
	}
	local acquired = 0
	local report = bridge.reconcile_for_unload(previewer, family.preview_package_alias,
		function(candidate)
			acquired = acquired + 1
			return candidate == alias
		end)
	if acquired ~= 1 or report.repaired ~= 1 or report.mapped ~= 1
			or rawget(previewer._loaded_packages, custom) ~= nil
			or previewer._loaded_packages[alias] ~= true
			or previewer._packages_to_load[alias] ~= false then
		return "Crowbill preview lease repair is not balanced"
	end
	if bridge.claim_teardown(previewer) ~= true or bridge.claim_teardown(previewer) ~= false then
		return "Crowbill preview teardown is not idempotent"
	end
end)

_rt_register("cwv_crowbill_hammer_runtime_contract", function()
	local runtime = mod._cwv_crowbill_runtime
	local policy = mod._cwv_crowbill_hammer_mode
	if type(runtime) ~= "table" or runtime._installed ~= true then
		return "Crowbill hammer runtime not installed"
	end
	local source = Weapons and Weapons[policy.SOURCE_TEMPLATE_KEY]
	local pick = Weapons and Weapons[runtime.PICK_TEMPLATE_KEY]
	local hammer = Weapons and Weapons[policy.HAMMER_TEMPLATE_KEY]
	if type(source) ~= "table" or type(pick) ~= "table" or type(hammer) ~= "table" then
		return "Crowbill source/pick/hammer templates not all registered"
	end
	if source.actions and source.actions.action_three ~= nil then
		return "vanilla Crowbill source template was mutated with Weapon Special"
	end
	local pick_special = pick.actions and pick.actions.action_three
		and pick.actions.action_three.default
	local hammer_special = hammer.actions and hammer.actions.action_three
		and hammer.actions.action_three.default
	if type(pick_special) ~= "table" or type(hammer_special) ~= "table"
			or type(pick_special.enter_function) ~= "function"
			or type(hammer_special.enter_function) ~= "function" then
		return "Weapon Special toggle missing from one Crowbill mode"
	end
	if pick_special.lookup_data.item_template_name ~= runtime.PICK_TEMPLATE_KEY
			or hammer_special.lookup_data.item_template_name ~= policy.HAMMER_TEMPLATE_KEY then
		return "Crowbill Weapon Special lookup_data drifted"
	end
	for action_name, class in pairs(policy.DIRECT_ACTIONS) do
		local pick_action = pick.actions.action_one[action_name]
		local hammer_action = hammer.actions.action_one[action_name]
		if not pick_action or not hammer_action
				or pick_action.damage_profile == hammer_action.damage_profile then
			return "Crowbill mode profile missing: " .. tostring(action_name)
		end
		if pick_action.anim_time_scale ~= hammer_action.anim_time_scale
				or pick_action.total_time ~= hammer_action.total_time then
			return "Crowbill timing drifted: " .. tostring(action_name) .. "/" .. tostring(class)
		end
		if _om._cwv_damage_profile_wire_source[hammer_action.damage_profile]
				~= pick_action.damage_profile then
			return "Crowbill mixed-peer damage fallback missing: " .. tostring(action_name)
		end
	end
	if type(runtime.resolve_template) ~= "function"
			or type(runtime.request_states) ~= "function"
			or type(runtime.on_local_wield) ~= "function"
			or type(runtime.on_husk_wield) ~= "function" then
		return "Crowbill runtime lifecycle surface incomplete"
	end
end)

_rt_register("cwv_parity_applied_state_committed_before_callbacks", function()
    -- Issue 506: the shared peer-parity lib must commit _applied BEFORE it fires
    -- the gated-feature callbacks, so a callback reading inst:applied_state()
    -- observes the transition it is part of. cwv's own gated callbacks
    -- (_inject_pool / _eject_pool) do not read applied_state today, so cwv was
    -- never bitten -- but cwv ships a copy of the lib, so lock the master
    -- ordering here too (a future cwv gated feature could rely on it). Build a
    -- THROWAWAY instance (never install()d -> no VMF channel, no mod.update
    -- wrap), register a probe whose on_enable records applied_state(), drive a
    -- solo enable, and assert it saw "enabled". Skip (not fail) if the transition
    -- cannot be driven here (a populated lobby holds the probe disabled).
    local ok, factory = pcall(mod.dofile, mod, "scripts/mods/character_weapon_variants/_lib_peer_parity")
    if not ok or type(factory) ~= "function" then return "peer-parity lib not loadable" end
    local inst = factory(mod, {
        channel           = "cwv_rt_probe_parity",
        echo_prefix       = "[cwv-rt]",
        poll_interval     = 0,
        announce_interval = 1e12,   -- suppress the probe's network announce
    })
    if type(inst) ~= "table" then return "parity factory did not return an instance" end
    local seen_state
    inst:register_gated_feature("__cwv_rt_order_probe__", {
        on_enable = function() seen_state = inst:applied_state() end,
    })
    pcall(function() inst:tick(10) end)   -- solo enables on the first tick (settle 0)
    if seen_state == nil then return end  -- enable did not fire in this env; skip
    if seen_state ~= "enabled" then
        return string.format(
            "applied_state() inside on_enable was %q, expected \"enabled\" -- shared lib fired callbacks before committing _applied (issue 506 regression)",
            tostring(seen_state))
    end
end)

_rt_register("issue567_skin_reverse_index_valid", function()
    -- The three persisted skins from issue #567 must satisfy BOTH layers of
    -- vanilla's contract: live IML/WeaponSkins ownership and, whenever vanilla's
    -- lazy reverse-index has been rebuilt, a cache row pointing at that owner.
    local validate = mod._cwv567_validate_skin_association
    if type(validate) ~= "function" then return "#567 association validator missing" end
    local expected = {
        cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1 = "cwv_es_sword_and_mace",
        cwv_es_dual_maces_es_1h_mace_skin_02_runed_01 = "cwv_es_dual_maces",
        cwv_es_axe_shield_wpn_emp_shield_03__axe_02_t2 = "cwv_es_axe_shield",
    }
    for skin_key, owner_key in pairs(expected) do
        local valid, owner_or_err = validate(skin_key)
        if not valid then return skin_key .. ": " .. tostring(owner_or_err) end
        if owner_or_err ~= owner_key then
            return string.format("%s owner=%s expected=%s", skin_key, tostring(owner_or_err), owner_key)
        end
        local cache = WeaponSkins and WeaponSkins._matching_weapon_skin_item_keys
        if type(cache) == "table" then
            local row = cache[skin_key]
            if type(row) ~= "table" then return skin_key .. ": missing from rebuilt vanilla reverse-index" end
            if row.item_key ~= owner_key .. "_skin" then
                return string.format("%s reverse-index item_key=%s expected=%s_skin",
                    skin_key, tostring(row.item_key), owner_key)
            end
        end
    end
    if type(_om._exact_pair_skin_predicate) ~= "function" then
        return "#567 exact-pair protocol predicate missing"
    end
    local exact = "cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1"
    if not _om._exact_pair_skin_predicate(exact) then
        return "#567 exact Sword+Mace skin is outside replay protocol"
    end
    local skin = WeaponSkins and WeaponSkins.skins and WeaponSkins.skins[exact]
    if not skin
        or not tostring(skin.right_hand_unit):find("wpn_emp_sword_02_t1", 1, true)
        or not tostring(skin.left_hand_unit):find("wpn_emp_mace_03_t1", 1, true) then
        return "#567 exact skin lost sword-right/mace-left authored hand order"
    end
end)

_rt_register("issue704_canonical_skin_owner_and_sword_mace_sources", function()
	local function require_owner(keys, label)
		for skin_key in pairs(keys or {}) do
			local row = ItemMasterList and rawget(ItemMasterList, skin_key)
			if type(row) ~= "table" then
				return string.format("%s skin missing from ItemMasterList: %s",
					label, tostring(skin_key))
			end
			if type(row.cwv_owner_item_type) ~= "string"
					or row.cwv_owner_item_type == "" then
				return string.format("%s skin lacks canonical owner: %s matching=%s",
					label, tostring(skin_key), tostring(row.matching_item_key))
			end
		end
	end
	local problem = require_owner(_om._skin_keys, "generated")
		or require_owner(_custom_skin_keys, "custom")
	if problem then return problem end

	local vanilla = { es_1h_sword = {}, es_1h_mace = {} }
	for _, row in pairs(ItemMasterList or {}) do
		local family = type(row) == "table" and row.matching_item_key
		if vanilla[family] and row.item_type == "weapon_skin"
				and not row.cwv_owner_item_type and row.right_hand_unit then
			vanilla[family][row.right_hand_unit] = true
		end
	end
	local combo = WeaponSkins and WeaponSkins.skin_combinations
		and WeaponSkins.skin_combinations.cwv_es_sword_and_mace_skins
	for _, bucket in pairs(combo or {}) do
		for _, skin_key in ipairs(type(bucket) == "table" and bucket or {}) do
			local row = ItemMasterList and rawget(ItemMasterList, skin_key)
			if type(row) == "table" and row.cwv_owner_item_type == "cwv_es_sword_and_mace" then
				if not vanilla.es_1h_sword[row.right_hand_unit] then
					return "Sword+Mace pair admitted non-vanilla sword owner: " .. tostring(skin_key)
				end
				if not vanilla.es_1h_mace[row.left_hand_unit] then
					return "Sword+Mace pair admitted non-vanilla mace owner: " .. tostring(skin_key)
				end
			end
		end
	end
end)

_rt_register("issue915_maul_illusion_vanilla_provenance", function()
	-- #915: the Maul picker pool must contain only illusions copied from
	-- VANILLA es_dual_wield_hammer_sword skins (mace in right_hand_unit).
	-- CWV's Sword and Mace base skin borrows that matching key with a SWORD
	-- in the right hand; if it ever re-enters the pool, the Maul renders a
	-- 1H sword. Provenance field per #704: cwv_owner_item_type.
	local vanilla_right_units = {}
	for _, row in pairs(ItemMasterList or {}) do
		if type(row) == "table" and row.item_type == "weapon_skin"
				and row.matching_item_key == "es_dual_wield_hammer_sword"
				and not row.cwv_owner_item_type and row.right_hand_unit then
			vanilla_right_units[row.right_hand_unit] = true
		end
	end
	local combo = WeaponSkins and WeaponSkins.skin_combinations
		and WeaponSkins.skin_combinations.cwv_es_maul_skins
	for _, bucket in pairs(combo or {}) do
		for _, skin_key in ipairs(type(bucket) == "table" and bucket or {}) do
			local source_key = type(skin_key) == "string"
				and skin_key:match("^cwv_es_maul_(.+)$")
			-- Only judge registrar-generated keys: their suffix resolves to a
			-- real IML source row. The variant's own base skin
			-- (cwv_es_maul_skin) also matches the prefix but has no source.
			local source_row = source_key and ItemMasterList
				and rawget(ItemMasterList, source_key)
			if type(source_row) == "table" then
				if source_row.cwv_owner_item_type then
					return "Maul pool admitted CWV-owned source: " .. skin_key
				end
				local row = ItemMasterList and rawget(ItemMasterList, skin_key)
				if type(row) == "table" and row.right_hand_unit
						and not vanilla_right_units[row.right_hand_unit] then
					return "Maul illusion carries non-vanilla right hand: "
						.. skin_key .. " -> " .. tostring(row.right_hand_unit)
				end
			end
		end
	end
end)

mod._cwv_dev_anim_picker.install()

mod:info("Character Weapon Variants v%s loaded", MOD_VERSION)

mod:info("[mem-probe] cwv boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_CWV) / 1024)

end
