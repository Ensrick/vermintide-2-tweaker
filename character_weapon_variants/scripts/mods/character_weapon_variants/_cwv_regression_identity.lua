-- Regression checks are installed at the entry module's original registration point.
local _rt_iter_cwv_entries
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

-- ============================================================
-- /cwv_regression_test checks (scaffold near top of file).
-- Each check returns nil for PASS or a string for FAIL.
-- Bail with a clear "not loaded (run in-keep)" message when globals
-- aren't ready — keep-load timing means ItemMasterList / NetworkLookup
-- may not be populated when the user runs the command pre-keep.
-- ============================================================

-- Per-mod helper: walk every cwv_* IML entry that originated from this mod.
-- Returns an array of { key = string, entry = table, def = table }. Bails
-- (returns nil + "reason string") when ItemMasterList isn't ready or no
-- variants are registered yet.
function _rt_iter_cwv_entries()
    local iml = rawget(_G, "ItemMasterList")
    if type(iml) ~= "table" then
        return nil, "ItemMasterList not loaded yet (run in-keep)"
    end
    local out = {}
    for _, def in ipairs(_variant_definitions) do
        if not def.skin_only then
            local entry = rawget(iml, def.item_key)
            if entry then
                out[#out + 1] = { key = def.item_key, entry = entry, def = def }
            end
        end
    end
    if #out == 0 then
        return nil, "no cwv variants registered in ItemMasterList yet (run in-keep)"
    end
    return out, nil
end

_rt_register("cwv_variant_flag_present", function()
    -- Verify every cwv_* ItemMasterList entry carries `cwv_variant = true`.
    -- Per `feedback_cwv_clone_name_clobber.md` — sibling mods (cosmetics_tweaker,
    -- weapon_tweaker, gt_lobby manifest formerly lobby_tweaker) gate item-name-keyed overrides
    -- on `item_data.cwv_variant`. Missing flag = sibling mods spuriously
    -- match the inherited base-weapon name and apply the wrong override.
    local entries, bail = _rt_iter_cwv_entries()
    if bail then return bail end
    local missing = {}
    for _, e in ipairs(entries) do
        if e.entry.cwv_variant ~= true then
            missing[#missing + 1] = e.key
        end
    end
    if #missing > 0 then
        return "cwv_variant flag missing on " .. #missing .. " entries: " .. table.concat(missing, ", ")
    end
end)

_rt_register("issue620_per_instance_combat_styles", function()
	local policy = _om.combat_style_policy
	local runtime = _om.combat_styles
	if type(policy) ~= "table" or type(runtime) ~= "table" then
		return "Combat Style policy/runtime is not installed"
	end
	local expected = {
		es_2h_sword = { "greatsword", "kerillian", "bretonnian" },
		wh_2h_sword = { "greatsword", "kerillian", "bretonnian" },
		es_bastard_sword = { "bretonnian", "greatsword", "kerillian" },
		cwv_es_longsword = { "longsword", "bretonnian", "kerillian", "greatsword" },
		es_2h_hammer = { "kruber", "warrior_priest" },
		es_2h_heavy_spear = { "hunter", "infantry" },
	}
	for item_key, order in pairs(expected) do
		local _, _, _, member = policy.style(item_key)
		if type(member) ~= "table" or #member.order ~= #order then
			return "Combat Style order missing for " .. item_key
		end
		for index, style_id in ipairs(order) do
			if member.order[index] ~= style_id then
				return "Combat Style order mismatch for " .. item_key
			end
		end
	end
	if type(rawget(Weapons, policy.KERILLIAN_TEMPLATE)) ~= "table" then
		return "Kerillian Combat Style template is not registered"
	end
	if type(rawget(Weapons, policy.BRETONNIAN_GREATSWORD_TEMPLATE)) ~= "table" then
		return "Bretonnian receiver Greatsword Combat Style template is not registered"
	end
	if type(rawget(Weapons, policy.SALTZ_BRETONNIAN_TEMPLATE)) ~= "table" then
		return "Saltzpyre Bretonnian Greatsword Combat Style template is not registered"
	end
	local saltz_bret = policy.package("wh_2h_sword", "bretonnian")
	local saltz_elf = policy.package("wh_2h_sword", "kerillian")
	if not saltz_bret or saltz_bret.template ~= policy.SALTZ_BRETONNIAN_TEMPLATE
			or saltz_bret.remap_key ~= "bretonnian_greatsword_to_saltz"
			or not saltz_elf or saltz_elf.remap_key ~= "kerillian_greatsword_to_saltz" then
		return "Saltzpyre Greatsword receiver package drifted"
	end
	if policy.remap_event("wh_2h_sword", "kerillian", "wh_captain", "attack_swing_charge")
			~= "attack_swing_charge_left_diagonal"
			or policy.remap_event("wh_2h_sword", "bretonnian", "wh_zealot", "attack_swing_up_left")
			~= "attack_swing_left_diagonal" then
		return "Saltzpyre Greatsword receiver animation remap drifted"
	end
	if runtime:moveset_indicator("es_bastard_sword", "greatsword") ~= "Moveset 2 / 3" then
		return "Bretonnian Longsword moveset indicator drifted"
	end
	if runtime:moveset_indicator("es_2h_sword", "bretonnian") ~= "Moveset 3 / 3" then
		return "Greatsword deduplicated moveset indicator drifted"
	end
	local bret_package = policy.package("es_2h_sword", "bretonnian")
	local native_bret_package = policy.package("es_bastard_sword", "bretonnian")
	if not bret_package or not bret_package.presentation
			or bret_package.presentation.transform_key ~= "greatsword_bretonnian"
			or (native_bret_package and native_bret_package.presentation ~= nil) then
		return "Greatsword Bretonnian receiver presentation drifted"
	end
	local imperial = rawget(Weapons, "imperial_longsword_template")
	local greatsword = rawget(Weapons, "two_handed_swords_template_1")
	local longsword_style = policy.FAMILIES.greatsword.styles.longsword
	if type(imperial) ~= "table" or type(greatsword) ~= "table"
			or imperial.wield_anim ~= greatsword.wield_anim
			or longsword_style.resource ~= "units/beings/player/first_person_base/state_machines/melee/2h_sword" then
		return "Imperial Longsword style is not derived from the Kruber Greatsword graph"
	end
	local probe_item = { backend_id = "issue644_release_probe", name = "es_2h_sword" }
	local probe_content = {
		rows = 1, columns = 1, item_1_1 = probe_item,
		cwv_style_hotspot_1_1 = { cwv_visible = true, on_pressed = true },
	}
	if policy.consume_console_style_press(probe_content, runtime) ~= nil then
		return "Combat Style equipment button still commits on press"
	end
	probe_content.cwv_style_hotspot_1_1.on_release = true
	if policy.consume_console_style_press(probe_content, runtime) ~= probe_item
			or policy.consume_console_style_press(probe_content, runtime) ~= nil then
		return "Combat Style equipment button does not consume exactly one release edge"
	end
	for _, legacy_key in ipairs({ "cwv_es_longsword", "cwv_es_longsword_blackguard" }) do
		local def = _find_def(legacy_key)
		if not def or def.cwv_retired ~= true or def.rarity ~= "promo"
				or def.style_target_item ~= "es_2h_sword" then
			return "retired Longsword bridge drifted: " .. legacy_key
		end
		local skin = rawget(ItemMasterList, legacy_key .. "_skin")
		if not skin or skin.matching_item_key ~= "es_2h_sword" then
			return "retired Longsword illusion is not native-owned: " .. legacy_key
		end
	end
	if policy._ui_installed ~= true then
		return "Combat Style loadout control is not installed"
	end
	if policy._console_ui_installed ~= true then
		return "Combat Style console equipment-row control is not installed"
	end
	local layout = policy.console_style_layout({ 100, 200, 30 })
	if not layout or layout.cog_offset[1] ~= 100 or layout.cog_offset[2] ~= 173
			or layout.style_hitbox_offset[1] ~= 104 or layout.style_hitbox_offset[2] ~= 235 then
		return "Combat Style console equipment-row layout drifted"
	end
end)

_rt_register("issue645_reciprocal_style_descriptors", function()
	local policy = _om.combat_style_policy
	local runtime = _om.combat_styles
	if type(policy) ~= "table" or type(runtime) ~= "table" then
		return "Combat Style policy/runtime is not installed"
	end
	local valid, catalogue_err = policy.validate_catalogue()
	if not valid then return catalogue_err end
	for _, template_name in ipairs({ policy.EMPIRE_SPEAR_SHIELD_TEMPLATE,
			policy.ELVEN_SPEAR_SHIELD_TEMPLATE }) do
		if type(rawget(Weapons, template_name)) ~= "table" then
			return "reciprocal Spear and Shield template missing: " .. tostring(template_name)
		end
	end
	local empire = policy.package("we_1h_spears_shield", "empire")
	local elven = policy.package("es_deus_01", "elven")
	if not empire or empire.remap_key ~= "deus_to_spear_shield"
			or not elven or elven.remap_key ~= "spear_shield_to_deus" then
		return "reciprocal Spear and Shield remap descriptors drifted"
	end
	if policy.remap_event("we_1h_spears_shield", "empire", "we_maidenguard",
			"attack_swing_up") ~= "attack_swing_stab_lh"
			or policy.remap_event("es_deus_01", "elven", "es_knight",
				"attack_swing_stab_lh") ~= "attack_swing_stab" then
		return "reciprocal Spear and Shield event translations drifted"
	end
	for _, item_key in ipairs({ "dr_1h_axe", "wh_1h_axe", "we_1h_axe",
			"we_2h_axe", "dr_2h_axe", "es_1h_sword", "we_1h_sword", "we_spear" }) do
		if policy.member(item_key) ~= nil or policy.diagnostic_candidate(item_key) == nil then
			return "unproven family escaped fail-closed diagnostics: " .. item_key
		end
	end
	if policy.DIAGNOSTIC_EVENT_CAP > 32 then return "#645 diagnostic cap is unbounded" end
end)

_rt_register("issue317_career_scoped_animation_picker", function()
	return mod._cwv_dev_anim_picker.regression_check()
end)

_rt_register("dual_axes_cosmetic_family_parity", function()
    local ws = rawget(_G, "WeaponSkins")
    local iml = rawget(_G, "ItemMasterList")
    if type(ws) ~= "table" or type(ws.skins) ~= "table"
            or type(ws.skin_combinations) ~= "table" or type(iml) ~= "table" then
        return "WeaponSkins/ItemMasterList not loaded yet (run in-keep)"
    end
	local source_combo = ws.skin_combinations.wh_1h_axe_skins
	local source_by_target = _om._dual_axes_source_by_skin
	local icon_by_source = _om._dual_axes_inventory_icon_by_source
	if type(source_combo) ~= "table" or type(source_by_target) ~= "table" then
		return "dual-axes source/destination cosmetic family was not registered"
	end
	if type(icon_by_source) ~= "table" then
		return "dual-axes primary-icon mapping was not registered"
	end

    local expected = {}
    local memberships = {}
    for tier_name, tier in pairs(source_combo) do
        for _, source_key in ipairs(tier) do
            expected[source_key] = true
            memberships[source_key] = memberships[source_key] or {}
            memberships[source_key][tier_name] = true
        end
    end
    local default_skin = ws.default_skins and ws.default_skins.wh_1h_axe
    if default_skin then expected[default_skin] = true end

    local targets = {
        cwv_es_dual_axes = "cwv_es_dual_axes_skins",
        cwv_wh_dual_axes = "cwv_wh_dual_axes_skins",
    }
    for target_key, combo_name in pairs(targets) do
        local clone_combo = ws.skin_combinations[combo_name]
        local source_by_clone = source_by_target[target_key]
        if type(clone_combo) ~= "table" or type(source_by_clone) ~= "table" then
            return "dual-axes target family was not registered: " .. target_key
        end
        local actual = {}
        for clone_key, source_key in pairs(source_by_clone) do
            actual[source_key] = true
            local source = ws.skins[source_key]
            local clone = ws.skins[clone_key]
            local source_item = rawget(iml, source_key)
            local clone_item = rawget(iml, clone_key)
            if not source or not clone or not source_item or not clone_item then
                return string.format("dual-axes clone incomplete: %s <- %s", clone_key, source_key)
            end
			if clone.right_hand_unit ~= source.right_hand_unit
					or clone.left_hand_unit ~= source.right_hand_unit
					or clone.display_unit ~= "units/weapons/weapon_display/display_dual_axes" then
				return string.format("dual-axes hand/display mismatch: %s <- %s", clone_key, source_key)
			end
			local expected_icon = icon_by_source[source.inventory_icon]
			if not expected_icon or clone.inventory_icon ~= expected_icon
					or clone_item.inventory_icon ~= expected_icon then
				return string.format("dual-axes primary icon mismatch: %s <- %s (%s)",
					clone_key, source_key, tostring(source.inventory_icon))
			end
            if clone_item.matching_item_key ~= target_key
                    or clone_item.required_dlc ~= source_item.required_dlc then
                return string.format("dual-axes owner/DLC mismatch: %s <- %s", clone_key, source_key)
            end
            if not rawget(NetworkLookup.weapon_skins, clone_key)
                    or not rawget(NetworkLookup.item_names, clone_key) then
                return "dual-axes clone missing network lookup: " .. clone_key
            end
            for tier_name in pairs(memberships[source_key] or {}) do
                local found = false
                for _, key in ipairs(clone_combo[tier_name] or {}) do
                    if key == clone_key then found = true break end
                end
                if not found then
                    return string.format("dual-axes tier parity missing: %s in %s", clone_key, tier_name)
                end
            end
        end

        local missing, extra = {}, {}
        for source_key in pairs(expected) do
            if not actual[source_key] then missing[#missing + 1] = source_key end
        end
        for source_key in pairs(actual) do
            if not expected[source_key] then extra[#extra + 1] = source_key end
        end
        if #missing > 0 or #extra > 0 then
            table.sort(missing)
            table.sort(extra)
            return string.format("dual-axes cosmetic set drift for %s: missing=[%s] extra=[%s]",
                target_key, table.concat(missing, ","), table.concat(extra, ","))
        end
    end
end)

_rt_register("issue396_imperial_longsword_identity_and_remote_husk", function()
	local owner = _find_def("cwv_es_longsword")
	local illusion = _find_def("cwv_es_longsword_nordland")
	if not owner or owner.display_name ~= "Imperial Longsword" then
		return "owned cwv_es_longsword is not canonically named Imperial Longsword"
	end
	if not illusion or not illusion.skin_only
			or illusion.skin_display_name ~= "Helmgart Watchsword" then
		return "save-compatible cwv_es_longsword_nordland is not a distinct Helmgart Watchsword illusion"
	end
	if _display_names.cwv_imperial_longsword ~= "Imperial Longsword"
			or _display_names.cwv_es_longsword_nordland_skin_name ~= "Helmgart Watchsword" then
		return "weapon-family and illusion localization keys are conflated"
	end

	local surfaces = mod._cwv_identity_surfaces
	for _, name in ipairs({ "network", "game_object_initialized", "spawn_resynced_loadout",
			"hot_join_sync", "parity_replay" }) do
		if not (surfaces and surfaces[name]) then return "missing CWV identity surface: " .. name end
	end
	local plan = _om._cwv_identity_payloads
	local accept = _om._cwv_accept_identity
	local resolve = _om._cwv_identity_def_for_peer
	if type(plan) ~= "function" or type(accept) ~= "function" or type(resolve) ~= "function" then
		return "CWV item-identity side-channel helpers missing"
	end
	local payloads = plan({
		slot_melee = { item_data = { name = "es_bastard_sword", cwv_key = "cwv_es_longsword" } },
		slot_ranged = { item_data = { name = "es_handgun" } },
	})
	local by_slot = {}
	for _, payload in ipairs(payloads) do by_slot[payload.slot] = payload end
	if not by_slot.slot_melee or by_slot.slot_melee.item_key ~= "cwv_es_longsword"
			or not by_slot.slot_ranged or by_slot.slot_ranged.item_key ~= "" then
		return "identity planner did not preserve CWV owner and native clear payloads"
	end
	local changed = accept("rt396-peer", _om.appearance_lifecycle_policy.SCHEMA, by_slot.slot_melee)
	local resolved = resolve("rt396-peer", "slot_melee", "es_bastard_sword")
	if changed ~= true or resolved ~= owner then
		return "receiver did not resolve the explicit Imperial Longsword marker over its vanilla base"
	end
	if resolve("rt396-peer", "slot_melee", "es_handgun") ~= nil then
		return "identity marker crossed its authored base-weapon boundary"
	end
	local native = by_slot.slot_ranged
	native.slot = "slot_melee"
	native.base_item_key = "es_bastard_sword"
	accept("rt396-peer", _om.appearance_lifecycle_policy.SCHEMA, native)
	if resolve("rt396-peer", "slot_melee", "es_bastard_sword") ~= nil then
		return "native-slot clear left stale CWV identity behind"
	end

	local replay = _om._cwv_skin_replay_payloads
	local skin_key = "cwv_es_longsword_nordland_skin"
	local skin_payloads = replay and replay({
		wielded_slot = "slot_melee",
		slots = { slot_melee = { item_data = { name = "es_bastard_sword" }, skin = skin_key } },
	}) or {}
	if #skin_payloads ~= 1 or skin_payloads[1].skin ~= skin_key
			or skin_payloads[1].item_name ~= "es_bastard_sword" or not skin_payloads[1].wielded then
		return "hot-join/transition replay lost the exact Helmgart illusion or current wield"
	end
	local skin_def, reason = _om._husk_resolve_display_def("es_bastard_sword", "es_mercenary", skin_key)
	if skin_def ~= illusion or reason ~= "skin" then
		return "Helmgart skin does not positively resolve its exact remote-husk mesh"
	end
	local preview = mod._cwv_preview_meshswap_apply
	local info = {
		skin_name = skin_key,
		spawn_data = { { right_hand = true, unit_name = illusion.right_hand_unit .. "_3p" } },
	}
	if type(preview) ~= "function" then return "inventory preview mesh-swap helper missing" end
	preview("es_bastard_sword", "cwv_es_longsword_001", skin_key, info)
	if info.spawn_data[1].unit_name ~= illusion.right_hand_unit .. "_3p" then
		return "inventory character preview replaced the selected Helmgart mesh"
	end
end)

_rt_register("issue660_world_identity_lifecycle_replay", function()
	local lifecycle = _om._appearance_lifecycle
	local plan = _om._cwv_identity_payloads
	local accept = _om._cwv_accept_identity
	local resolve = _om._cwv_identity_descriptor_for_peer
	if not lifecycle or type(plan) ~= "function" or type(accept) ~= "function"
			or type(resolve) ~= "function" then
		return "#660 exact world-identity lifecycle is not installed"
	end
	local payload = plan({
		slot_melee = {
			item_data = { name = "es_bastard_sword", cwv_key = "cwv_es_longsword" },
		},
	})[1]
	if not payload or payload.base_item_key ~= "es_bastard_sword"
			or payload.item_key ~= "cwv_es_longsword"
			or type(payload.fingerprint) ~= "string" or payload.fingerprint == "" then
		return "#660 owner descriptor payload omitted exact item/base/model fingerprint"
	end
	local changed, descriptor, reason = accept("rt660-peer",
		_om.appearance_lifecycle_policy.SCHEMA, payload)
	if not changed or not descriptor or reason ~= "exact"
			or descriptor.fingerprint ~= payload.fingerprint then
		return "#660 receiver did not reconstruct the sender's exact local descriptor"
	end
	local changed_again = accept("rt660-peer",
		_om.appearance_lifecycle_policy.SCHEMA, payload)
	if changed_again then return "#660 duplicate descriptor caused a second lifecycle replay" end
	local bad = {}
	for k, v in pairs(payload) do bad[k] = v end
	bad.fingerprint = payload.fingerprint .. "-provider-drift"
	local declined = accept("rt660-peer", _om.appearance_lifecycle_policy.SCHEMA, bad)
	local missing, state = resolve("rt660-peer", "slot_melee", "es_bastard_sword")
	if not declined or missing ~= nil or state ~= "unavailable" then
		return "#660 provider/fingerprint drift did not fail closed and clear stale exact identity"
	end
	if resolve("rt660-peer", "slot_melee", "different_base") ~= nil then
		return "#660 remote descriptor crossed its vanilla base boundary"
	end
end)

_rt_register("issue579_dual_axes_preview_and_husk_skin_continuity", function()
    local source_by_target = _om._dual_axes_source_by_skin
    local ws = rawget(_G, "WeaponSkins")
    if type(source_by_target) ~= "table" or type(ws) ~= "table" or type(ws.skins) ~= "table" then
        return "dual-axes generated skins not loaded yet (run in-keep)"
    end
    local apply_preview = mod._cwv_preview_meshswap_apply
    local plan_replay = _om._cwv_skin_replay_payloads
    if type(apply_preview) ~= "function" or type(plan_replay) ~= "function" then
        return "#579 preview/replay helpers are not installed"
    end
    if not (mod._cwv_skin_wire_surfaces and mod._cwv_skin_wire_surfaces.parity_replay) then
        return "#579 post-handshake parity replay is not registered"
    end

    for _, target_key in ipairs({ "cwv_es_dual_axes", "cwv_wh_dual_axes" }) do
        local clones = source_by_target[target_key]
        local generated_skin = clones and next(clones)
        local skin = generated_skin and ws.skins[generated_skin]
        if not skin then return target_key .. " has no generated skin for continuity test" end
        if type(skin.right_hand_unit) ~= "string" or type(skin.left_hand_unit) ~= "string" then
            return generated_skin .. " does not preserve both generated hands"
        end

        -- Vanilla has already built spawn_data from the selected skin. The
        -- copied preview callback may pass skin=nil; info.skin_name is the
        -- authoritative stored identity and must prevent the def-default swap.
        local info = {
            skin_name = generated_skin,
            spawn_data = {
                { right_hand = true, unit_name = skin.right_hand_unit .. "_3p" },
                { left_hand = true, unit_name = skin.left_hand_unit .. "_3p" },
            },
        }
        apply_preview("dr_dual_wield_axes", target_key .. "_001", nil, info)
        if info.spawn_data[1].unit_name ~= skin.right_hand_unit .. "_3p"
                or info.spawn_data[2].unit_name ~= skin.left_hand_unit .. "_3p" then
            return generated_skin .. " was overwritten by the preview fallback"
        end

        -- Hot join initially sends the vanilla base item with a nulled cwv skin.
        -- After parity, the replay planner must retain that clone-name-clobbered
        -- base id while restoring the exact generated skin and current wield.
        local payloads = plan_replay({
            wielded_slot = "slot_melee",
            slots = {
                slot_melee = {
                    item_data = { name = "dr_dual_wield_axes" },
                    skin = generated_skin,
                },
                slot_ranged = {
                    item_data = { name = "wh_crossbow" },
                    skin = "wh_crossbow_skin_01",
                },
            },
        })
        if #payloads ~= 1 or payloads[1].item_name ~= "dr_dual_wield_axes"
                or payloads[1].skin ~= generated_skin or payloads[1].wielded ~= true then
            return generated_skin .. " parity replay payload lost base/skin/wield identity"
        end
        local def, reason = _om._husk_resolve_display_def("dr_dual_wield_axes",
            target_key == "cwv_es_dual_axes" and "es_mercenary" or "wh_captain", generated_skin)
        if not def or def.item_key ~= target_key or reason ~= "skin" then
            return generated_skin .. " does not resolve to its target on the husk"
        end
    end
end)

_rt_register("issue416_483_transition_generated_skin_replay", function()
    local exact_skin = "cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1"
    local plan_replay = _om._cwv_skin_replay_payloads
    local null_skins = _om._wire_null_skins
    local step = _om._cwv_skin_replay_pending_step
    if type(plan_replay) ~= "function" or type(null_skins) ~= "function" or type(step) ~= "function" then
        return "#416/#483 transition replay helpers are not installed"
    end
    if not (mod._cwv_skin_wire_surfaces and mod._cwv_skin_wire_surfaces.transition_replay) then
        return "#416/#483 bounded transition replay update is not installed"
    end

    -- The exact generated pair from the repro must retain both authored meshes
    -- and its clone-name-clobbered vanilla base id in a replay payload.
    local skin = WeaponSkins and WeaponSkins.skins and WeaponSkins.skins[exact_skin]
    if type(skin) ~= "table" or type(skin.right_hand_unit) ~= "string"
            or type(skin.left_hand_unit) ~= "string" then
        return exact_skin .. " is absent or lost one generated hand"
    end
    local payloads = plan_replay({
        wielded_slot = "slot_melee",
        slots = {
            slot_melee = {
                item_data = { name = "es_dual_wield_hammer_sword" },
                skin = exact_skin,
            },
        },
    })
    if #payloads ~= 1 or payloads[1].item_name ~= "es_dual_wield_hammer_sword"
            or payloads[1].skin ~= exact_skin or payloads[1].wielded ~= true then
        return "Sword+Mace mission-transition replay lost exact base+generated-skin+wield identity"
    end

    -- Reproduce the transition send: parity is transiently false, so the wire
    -- sees n/a, the selected live skin is restored, and a deferred replay is
    -- scheduled. Restore global probe state before assertions return.
    local real_pp = mod._cwv_peer_parity
    local real_pending = _om._cwv_skin_replay_pending
    mod._cwv_peer_parity = { all_peers_have = function() return false end }
    local slot = { skin = exact_skin }
    local at_send
    null_skins({ slot }, function() at_send = slot.skin end, "rt416_transition", false)
    local pending = _om._cwv_skin_replay_pending
    mod._cwv_peer_parity = real_pp
    _om._cwv_skin_replay_pending = real_pending
    if at_send ~= nil or slot.skin ~= exact_skin or type(pending) ~= "table" then
        return "transition null did not restore the live Sword+Mace skin and schedule recovery"
    end

    -- No unsafe replay while parity is false. The first confirmed half-second
    -- poll sends exactly once and consumes the pending state even if the shared
    -- feature never observed a disable->enable edge.
    local calls = 0
    local p, sent = step(pending, 0.5, function() return false end,
        function() calls = calls + 1 return 1 end)
    if not p or sent ~= 0 or calls ~= 0 then
        return "deferred generated-skin replay ran while parity was unconfirmed"
    end
    p, sent = step(p, 0.5, function() return true end,
        function() calls = calls + 1 return 1 end)
    if p ~= nil or sent ~= 1 or calls ~= 1 then
        return "deferred generated-skin replay did not send exactly once after parity recovery"
    end
end)

_rt_register("issue412_old_musket_universal_special_interrupt", function()
	local audit = mod._cwv_old_musket_interrupt and mod._cwv_old_musket_interrupt.audit
	if type(audit) ~= "function" then return "interrupt policy missing" end
	for _, template_name in ipairs({ "old_musket_template", "old_musket_template_melee" }) do
		local ok, detail = audit(Weapons and Weapons[template_name], "action_three")
		if not ok then return template_name .. ": " .. tostring(detail) end
	end
	local melee = Weapons and Weapons.old_musket_template_melee
	local toggle = melee and melee.actions and melee.actions.action_three
	toggle = toggle and toggle.default
	if not toggle or toggle.anim_end_event ~= "attack_finished"
			or type(toggle.anim_end_event_condition_func) ~= "function" then
		return "melee toggle interruption animation cleanup missing"
	end
end)

_rt_register("issue273_cwv_deus_identity_is_exact", function()
	local report = _om.install_deus_identities("runtime_regression")
	if #report.skipped > 0 then
		return string.format("%d CWV owners lack a dedicated Deus identity: %s",
			#report.skipped, table.concat(report.skipped, ","))
	end
	for _, item_key in ipairs({ "cwv_wh_dual_axes", "cwv_es_dual_axes" }) do
		local deus_key = rawget(DeusStartingWeaponTypeMapping, item_key)
		if not report.exact_identity_allowed then
			if deus_key ~= "deus_dr_dual_wield_axes" then
				return item_key .. " mixed-parity fallback is not wire-safe Dual Axes"
			end
			goto continue_issue273
		end
		local row = deus_key and rawget(DeusWeapons, deus_key)
		local owner = rawget(ItemMasterList, item_key)
		local single_axe = rawget(ItemMasterList, "dr_1h_axe")
		if deus_key ~= "deus_" .. item_key or not row or row.base_item ~= item_key then
			return item_key .. " collapses to a non-CWV Deus owner"
		end
		if not owner or owner.item_type ~= item_key
				or (single_axe and owner.template == single_axe.template) then
			return item_key .. " lost its individualized item_type/template"
		end
		::continue_issue273::
	end
end)

_rt_register("issue474_old_musket_hot_join_identity_and_remote_fire", function()
    local plan_replay = _om._cwv_skin_replay_payloads
    if type(plan_replay) ~= "function" then return "post-parity skin replay planner missing" end
    if not (mod._cwv_skin_wire_surfaces and mod._cwv_skin_wire_surfaces.parity_replay) then
        return "post-parity skin replay is not registered"
    end
    local payloads = plan_replay({
        wielded_slot = "slot_melee",
        slots = {
            slot_melee = {
                item_data = { name = "es_handgun" },
                skin = "cwv_es_musket_old_skin",
            },
            slot_ranged = {
                item_data = { name = "es_handgun" },
                skin = "cwv_es_musket_old_skin",
            },
        },
    })
    local by_slot = {}
    for _, payload in ipairs(payloads) do by_slot[payload.slot_name] = payload end
    for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
        local payload = by_slot[slot_name]
        if not payload or payload.item_name ~= "es_handgun"
                or payload.skin ~= "cwv_es_musket_old_skin" then
            return slot_name .. " lost Old Musket base+skin identity in the parity replay"
        end
    end
    if not by_slot.slot_melee.wielded or by_slot.slot_ranged.wielded then
        return "cross-slot replay lost the currently wielded slot"
    end

    local template = Weapons and Weapons.old_musket_template
    local action_one = template and template.actions and template.actions.action_one
    local default = action_one and action_one.default
    local zoomed = action_one and action_one.zoomed_shot
    if not default or not zoomed then return "Old Musket ranged actions missing" end
    if not _om._is_old_musket_ranged_action(default)
            or not _om._is_old_musket_ranged_action(zoomed) then
        return "Old Musket hip/ADS action identity is not recognized"
    end
    if not _om._old_musket_shot_completed(default, "waiting_to_shoot", false, "shot", false)
            or _om._old_musket_shot_completed(default, "shot", false, "shot", false) then
        return "Old Musket shot edge is not exactly-once"
    end
    if not _om._old_musket_remote_fire_hook_installed then
        return "ActionHandgun remote-fire hook missing"
    end
	local event = _om._old_musket_remote_fire_event
	if event ~= "player_combat_weapon_rifle_fire"
			or type(_om._old_musket_publish_fire) ~= "function" then
		return "compiled rifle report is not routed through the bounded CWV channel"
	end
	if _om._old_musket_mode_channel ~= "cwv_old_musket_mode_v1"
			or _om._old_musket_mode_schema ~= 1
			or type(_om._old_musket_record_and_publish) ~= "function"
			or type(_om._old_musket_mode_for_owner) ~= "function"
			or type(_om._old_musket_modes_by_backend) ~= "table" then
		return "Old Musket explicit presentation-state contract is incomplete"
	end
	for _, perspective in ipairs({ "1p", "3p" }) do
		for _, mode in ipairs({ "ranged", "melee" }) do
			local pos, rot, scale = _om._old_musket_transform_components(perspective, mode)
			if type(pos) ~= "table" or not rot or type(scale) ~= "table"
					or pos[1] == nil or pos[2] == nil or pos[3] == nil
					or scale[1] == nil or scale[2] == nil or scale[3] == nil then
				return perspective .. "/" .. mode .. " does not preserve the full saved transform"
			end
		end
	end
end)

_rt_register("issue474_old_musket_presentation_surface_coverage", function()
	-- issue 474 root cause was PROCESS, not a single weapon: the Old Musket
	-- display kept regressing because one render surface at a time drifted off
	-- the shared resolver (husk showed the base handgun, inventory preview
	-- dropped the stance pose, the Athanor showed nothing). This guard asserts
	-- the single shared presentation contract is intact so a future refactor
	-- cannot silently strip a surface again. The per-surface CALL SITES are
	-- pattern-verified offline in
	-- qa/lua/tests/test_cwv_old_musket_presentation.lua ("... fans out to every
	-- render surface ..."); this in-keep half asserts every shared entrypoint
	-- those surfaces call actually exists and resolves.
	local shared = {
		"_apply_old_musket_transform",       -- owner 1P/3P, husk, both previews
		"_track_old_musket_unit",            -- live-tune bucket membership
		"_apply_old_musket_textures",        -- the one UV painter for every surface
		"_old_musket_transform_components",  -- the single pos/rot/scale source
		"_old_musket_mode_for_owner",        -- husk stance from the bounded channel
		"_old_musket_record_and_publish",    -- owner -> channel publish
		"_old_musket_preview_descriptor",    -- one item/skin -> unit/mat/pose descriptor
		"_old_musket_preview_texture_targets", -- LootItemUnitPreviewer paint planner
	}
	for _, name in ipairs(shared) do
		if type(_om[name]) ~= "function" then
			return "shared Old Musket presentation resolver missing: _om." .. name
		end
	end
	-- Cross-mod bridge entrypoint the Cosmetics/CIM-Athanor previewers consume.
	if type(mod._cwv_resolve_preview_descriptor) ~= "function" then
		return "preview-bridge entrypoint mod._cwv_resolve_preview_descriptor missing"
	end
	local policy = _om.old_musket_preview
	if type(policy) ~= "table" or type(policy.resolve) ~= "function"
			or type(policy.resource_mode) ~= "function" then
		return "shared Old Musket preview policy (resolve/resource_mode) missing"
	end
	-- All three positive-identity forms a surface can hold (item key, skin key,
	-- backend id) must resolve to the SAME custom unit plus a full stance
	-- transform triplet from the ONE descriptor. A surface that resolves any of
	-- these to nil is exactly the base-handgun regression this issue chased.
	for _, probe in ipairs({
		{ data = { cwv_key = "cwv_es_musket_old" } },
		{ skin = "cwv_es_musket_old_skin" },
		{ backend_id = "cwv_es_musket_old_002" },
	}) do
		local d = _om._old_musket_preview_descriptor(probe)
		if type(d) ~= "table" or type(d.unit) ~= "string"
				or (d.mode ~= "ranged" and d.mode ~= "melee")
				or type(d.transform) ~= "table"
				or type(d.transform.position) ~= "table"
				or type(d.transform.scale) ~= "table" then
			return "preview descriptor incomplete for a positive Old Musket identity form"
		end
	end
end)

_rt_register("issue582_dual_axes_native_variant_ownership_boundary", function()
    local expected = {
        cwv_es_dual_axes = { prefix = "es_", careers = {
            "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
        } },
        cwv_wh_dual_axes = { prefix = "wh_", careers = {
            "wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest",
        } },
    }
    local defs = {}
    for _, def in ipairs(_variant_definitions) do
        if expected[def.item_key] then defs[def.item_key] = def end
    end

    local iml = rawget(_G, "ItemMasterList")
    if type(iml) ~= "table" then return "ItemMasterList not loaded yet (run in-keep)" end
    for item_key, contract in pairs(expected) do
        local def = defs[item_key]
        local entry = rawget(iml, item_key)
        if not def or def.base_weapon ~= "dr_dual_wield_axes" then
            return item_key .. " definition/base ownership missing"
        end
        if not entry or entry.cwv_variant ~= true then
            return item_key .. " dedicated CWV ItemMasterList entry missing"
        end
        local careers = {}
        for _, career in ipairs(entry.can_wield or {}) do
            if career:sub(1, #contract.prefix) == contract.prefix then careers[career] = true end
        end
        for _, career in ipairs(contract.careers) do
            if not careers[career] then
                return string.format("%s missing receiver ownership %s", item_key, career)
            end
            careers[career] = nil
        end
        local extra = next(careers)
        if extra then
            return string.format("%s has unexpected receiver ownership %s", item_key, tostring(extra))
        end
    end

    local native = rawget(iml, "dr_dual_wield_axes")
    if not native then return "native dr_dual_wield_axes missing" end
    for _, career in ipairs(native.can_wield or {}) do
        if career:sub(1, 3) == "es_" or career:sub(1, 3) == "wh_" then
            return "native Bardin Dual Axes leaked to dedicated CWV receiver: " .. career
        end
    end
end)

_rt_register("issue593_kruber_axe_shield_canonical_ownership", function()
    local expected = {
        es_mercenary = true, es_huntsman = true,
        es_knight = true, es_questingknight = true,
    }
    for _, item_key in ipairs({ "cwv_es_axe_shield", "cwv_es_axe_shield_veteran" }) do
        local def = _find_def(item_key)
        if not def or def.base_weapon ~= "dr_shield_axe" then
            return "#593 canonical CWV definition missing: " .. item_key
        end
        local seen = {}
        for _, career in ipairs(def.careers or {}) do seen[career] = true end
        for career in pairs(expected) do
            if not seen[career] then return item_key .. " missing " .. career end
            seen[career] = nil
        end
        if next(seen) then return item_key .. " has non-Kruber receiver" end
        local skin_table = def.item_type == "cwv_es_axe_shield"
        if not skin_table then return item_key .. " cosmetic family changed" end
    end
end)

_rt_register("issue586_cross_character_dual_axes_fp_residency", function()
    local catalog = _om.DUAL_WEAPON_FP_RESIDENCY
    if type(catalog) ~= "table" or #catalog ~= 5 then
        return "generated dual-weapon FP residency catalog must contain five source state machines"
    end
    if type(_om._acquire_dual_weapon_fp_residency) ~= "function"
        or type(_om._release_dual_weapon_fp_residency) ~= "function" then
        return "generated dual-weapon FP residency lifecycle is not installed"
    end
    if _om._dual_axes_fp_game_state_retry_installed ~= true then
        return "game-state retry is not wired for a cold chunk-load PackageManager"
    end

    local package_manager = Managers and Managers.package
    if not package_manager then return "package manager unavailable" end
    if not _om._acquire_dual_weapon_fp_residency("regression_prepare") then
        return "generated dual-weapon FP residency initial acquire failed"
    end
    local before = {}
    for _, lease in ipairs(catalog) do
        if before[lease.path] ~= nil then return "duplicate FP lease path: " .. tostring(lease.path) end
        before[lease.path] = package_manager:reference_count(lease.path, lease.ref) or 0
    end
    if not _om._acquire_dual_weapon_fp_residency("regression_idempotence") then
        return "generated dual-weapon FP residency repeat acquire failed"
    end
    for _, lease in ipairs(catalog) do
        local after = package_manager:reference_count(lease.path, lease.ref) or 0
        if before[lease.path] ~= 1 or after ~= 1 then
            return string.format("FP lease is not singular/idempotent path=%s before=%d after=%d",
                lease.path, before[lease.path], after)
        end
        if not package_manager:has_loaded(lease.path, lease.ref)
                or _om._dual_weapon_fp_residency_held[lease.path] ~= true then
            return "FP state machine is not resident under CWV lease: " .. tostring(lease.path)
        end
    end
    if _om._dual_weapon_fp_residency_complete ~= true then return "catalog completion flag is false" end

    local receiver_careers = {
        cwv_es_dual_swords = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" },
        cwv_es_sword_and_mace = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" },
        cwv_es_dual_axes = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" },
        cwv_wh_dual_axes = { "wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest" },
        cwv_es_dual_maces = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" },
        cwv_wh_dual_maces = { "wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest" },
        cwv_es_dual_warpriest_hammers = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" },
    }
    local iml = rawget(_G, "ItemMasterList")
    if type(iml) ~= "table" then return "ItemMasterList not loaded yet (run in-keep)" end
    local covered_items = {}
    for _, lease in ipairs(catalog) do
        for item_key, _ in pairs(lease.items or {}) do
            if covered_items[item_key] then return "dual item appears in multiple FP leases: " .. item_key end
            covered_items[item_key] = true
            local careers = receiver_careers[item_key]
            if not careers then return "dual FP lease has no receiver matrix: " .. item_key end
            local entry = rawget(iml, item_key)
            if not entry then return item_key .. " missing from ItemMasterList" end
            local item_template = BackendUtils.get_item_template(entry)
            if not item_template then return item_key .. " template missing" end
            for _, career_name in ipairs(careers) do
                local resolved = WeaponUtils.get_item_state_machine(item_template, career_name)
                if resolved ~= lease.path then
                    return string.format("%s/%s resolves FP state machine %s, expected %s",
                        item_key, career_name, tostring(resolved), lease.path)
                end
            end
        end
    end
    for item_key, _ in pairs(receiver_careers) do
        if not covered_items[item_key] then return "dual receiver is absent from FP lease catalog: " .. item_key end
    end
end)

_rt_register("cwv_key_resolution_uuid_safe", function()
    -- Issue #482: an Athanor-crafted cwv instance carries a UUID backend_id
    -- (Application.guid(), crafting_in_modded_dev.lua:4644) that the
    -- `cwv_<key>_NNN` pattern can never match -- transforms/mesh resolution
    -- must instead ride the `cwv_key` field _build_entry stamps on the IML
    -- clone, through the shared `_om._cwv_key_for_item` ladder.
    -- (1) Stamp present on every registered entry.
    local entries, bail = _rt_iter_cwv_entries()
    if bail then return bail end
    local missing = {}
    for _, e in ipairs(entries) do
        if e.entry.cwv_key ~= e.key then
            missing[#missing + 1] = e.key
        end
    end
    if #missing > 0 then
        return "cwv_key stamp missing/wrong on " .. #missing .. " entries: " .. table.concat(missing, ", ")
    end
    -- (2) Ladder rungs behave: pattern, stamp, legacy exact-key, transition
    -- cache, and no-signal cases. The exact-key case models a persisted CIM
    -- UUID crafted before `cwv_key` existed; it must not require recrafting.
    local ladder = _om._cwv_key_for_item
    if type(ladder) ~= "function" then
        return "_om._cwv_key_for_item missing (#482 resolver ladder gone)"
    end
    if ladder("cwv_es_greataxe_001", nil) ~= "cwv_es_greataxe" then
        return "#482 ladder rung 1 broken: cwv_<key>_NNN bid no longer resolves"
    end
    if ladder("a9f48814-0000-4000-8000-000000000000", { cwv_key = "cwv_es_greataxe" }) ~= "cwv_es_greataxe" then
        return "#482 ladder rung 2 broken: item_data.cwv_key stamp not consulted for UUID bid"
    end
	local legacy_bid = "48200000-0000-4000-8000-000000000419"
	if ladder(legacy_bid, { key = "cwv_es_longsword_blackguard", name = "es_bastard_sword" })
			~= "cwv_es_longsword_blackguard" then
		return "#482 legacy exact CWV key did not recover persisted Imperial Longsword identity"
	end
	if ladder(legacy_bid, nil) ~= "cwv_es_longsword_blackguard" then
		return "#482 proven UUID identity did not survive a backend-unavailable preview transition"
	end
    if ladder("not-a-registered-bid-482", { name = "dr_2h_axe" }) ~= nil then
        return "#482 ladder false-positive: non-cwv item resolved a cwv key"
    end
end)

_rt_register("issue484_crafted_old_musket_identity", function()
	local bid = "48400000-0000-4000-8000-000000000484"
	local item = {
		backend_id = bid,
		key = "es_handgun",
		template = "handgun_template_1",
		CustomData = {
			cim_acquisition_key = "cwv_es_musket_old",
			cwv_key = "cwv_es_musket_old",
		},
	}
	if _om._cwv_key_for_item(bid, item) ~= "cwv_es_musket_old" then
		return "canonical resolver lost the CIM UUID Old Musket stamp"
	end
	if type(_om._old_musket_bid_for_item) ~= "function"
			or _om._old_musket_bid_for_item(item) ~= bid then
		return "Old Musket stance channel rejected a canonical UUID instance"
	end
	if type(_om._old_musket_valid_bid) ~= "function"
			or not _om._old_musket_valid_bid(bid)
			or _om._old_musket_valid_bid(string.rep("x", 129)) then
		return "Old Musket opaque-id wire bound is missing"
	end
	local descriptor = _om.old_musket_preview.resolve({
		ItemInstanceId = bid,
		key = "es_handgun",
	}, "ranged", {}, _om._cwv_key_for_item(bid, item))
	if not descriptor or descriptor.item_key ~= "cwv_es_musket_old"
			or descriptor.unit ~= _om.old_musket_preview.UNIT then
		return "canonical UUID did not reach the authored Old Musket preview descriptor"
	end
	local payloads = _om._cwv_identity_payloads({
		slot_ranged = { item_data = item },
	})
	if not payloads[1] or payloads[1].item_key ~= "cwv_es_musket_old" then
		return "canonical UUID did not reach the bounded husk identity channel"
	end
end)

_rt_register("cwv_inherits_base_name", function()
    -- Verify NO cwv_* entry has `entry.name` clobbered to the cwv key.
    -- Per `feedback_cwv_clone_name_clobber.md` — vanilla code (e.g.
    -- world_hero_previewer.lua:674) does `item_data = ItemMasterList[item.name]`
    -- for fallback lookups. Clobbering entry.name to def.item_key made the
    -- lookup return nil and equip path crashed in BackendUtils.get_item_units.
    -- Must KEEP the inherited base name; mod uses `entry.cwv_variant` as the
    -- discriminator instead. Allow `entry.name == nil` (cloned tables may
    -- inherit via metamethod; only fail on the explicit cwv_-prefix clobber).
    local entries, bail = _rt_iter_cwv_entries()
    if bail then return bail end
    local clobbered = {}
    for _, e in ipairs(entries) do
        local n = e.entry.name
        if type(n) == "string" and n:sub(1, 4) == "cwv_" then
            clobbered[#clobbered + 1] = string.format("%s (name=%s)", e.key, n)
        end
    end
    if #clobbered > 0 then
        return "entry.name clobbered with cwv_ prefix on: " .. table.concat(clobbered, "; ")
    end
end)

_rt_register("cwv_ammo_mirroring", function()
    -- For any variant whose BASE template has `ammo_unit`, the variant entry
    -- must mirror `ammo_unit`, `projectile_units_template`, `pickup_template_name`,
    -- `link_pickup_template_name` from the base. Per `feedback_cwv_ammo_unit_required.md` —
    -- the skin pipeline nukes these fields; without explicit mirroring the
    -- previewer/throw/pickup paths all crash on ammo-bearing variants.
    -- Skip non-ammo bases entirely (their nil ammo_unit is correct).
    local entries, bail = _rt_iter_cwv_entries()
    if bail then return bail end
    local iml = rawget(_G, "ItemMasterList")
    local mismatched = {}
    local AMMO_FIELDS = { "ammo_unit", "projectile_units_template", "pickup_template_name", "link_pickup_template_name" }
    for _, e in ipairs(entries) do
        local base_key = e.def.base_weapon
        local base = base_key and rawget(iml, base_key)
        if base and base.ammo_unit then
            for _, f in ipairs(AMMO_FIELDS) do
                if base[f] ~= nil and e.entry[f] == nil then
                    mismatched[#mismatched + 1] = string.format("%s missing %s (base=%s has it)", e.key, f, base_key)
                end
            end
        end
    end
    if #mismatched > 0 then
        return "ammo-mirroring gaps on " .. #mismatched .. " entries: " .. table.concat(mismatched, "; ")
    end
end)

_rt_register("cwv_in_inventory_package_list", function()
    -- For each cwv variant's `right_hand_unit` and `left_hand_unit` paths,
    -- check whether the path appears in `NetworkLookup.inventory_packages`.
    -- Per `feedback_vt2_force_load_only_listed_paths.md` — Managers.package:load
    -- succeeds synchronously but async-fatals "Resource not found" if the path
    -- isn't listed; the fatal bypasses pcall. Vanilla unit paths ARE listed;
    -- mod-defined custom-mesh paths (e.g. Old Musket) are NOT, but those
    -- variants use the LA custom-mesh overlay pattern with vanilla paths in
    -- the actual `right_hand_unit` slot.
    --
    -- Informational-only for INHERITED vanilla paths (which legitimately may
    -- not all be listed depending on DLC). FAIL only when the path looks like
    -- a mod-prefixed custom mesh: `units/weapons/player_cwv/...`. If any future
    -- variant ships a custom-mesh path that didn't get listed, this will catch it.
    local entries, bail = _rt_iter_cwv_entries()
    if bail then return bail end
    local NL = rawget(_G, "NetworkLookup")
    local list = NL and NL.inventory_packages
    if type(list) ~= "table" then
        return "NetworkLookup.inventory_packages not loaded yet (run in-keep)"
    end
    -- Build a fast lookup set: path -> true. The list is array-form only; no
    -- reverse-index in vanilla.
    local listed = {}
    for _, p in ipairs(list) do listed[p] = true end
    local missing = {}
    for _, e in ipairs(entries) do
        for _, slot in ipairs({ "right_hand_unit", "left_hand_unit" }) do
            local p = e.entry[slot]
            if type(p) == "string" and p ~= "" then
                -- Mod-custom-mesh paths under a dedicated subtree must be
                -- present; vanilla paths are informational.
                if p:find("/player_cwv/", 1, true) or p:find("character_weapon_variants/", 1, true) then
                    if not listed[p] then
                        missing[#missing + 1] = string.format("%s.%s=%s (custom-mesh path not in InventoryPackageList)", e.key, slot, p)
                    end
                end
            end
        end
    end
    if #missing > 0 then
        return "InventoryPackageList gaps on " .. #missing .. " custom-mesh paths: " .. table.concat(missing, "; ")
    end
end)

_rt_register("cwv_itemmasterlist_uses_rawget", function()
    -- v0.1.333 (Issue #20): the membership check in `_auto_register_all`
    -- (`character_weapon_variants.lua:8167-area`) probes `ItemMasterList[key]`
    -- before deciding whether to mirror our entry. `ItemMasterList.__index`
    -- calls `crashify.print_exception("ItemMaster List has no item %s")` on
    -- missing keys, so a plain index produced 27 crashify exceptions per
    -- keep load. Fix: `not rawget(ItemMasterList, key)`. This runtime test is
    -- the §15 belt-and-suspenders companion (the strict-table-lookup lint
    -- catches static-pattern regressions; this catches metatable behavior
    -- changes at runtime).
    --
    -- 1. Source-pattern: marker constant must be present.
    if CT_CWV_ITEMMASTERLIST_RAWGET_MARKER_v0_1_333 ~= "cwv-itemmasterlist-rawget-auto-register-all" then
        return "ITEMMASTERLIST RAWGET marker absent — was the v0.1.333 fix reverted?"
    end
    -- 2. Runtime-state: rawget on a known-bad key against ItemMasterList must
    --    return nil without raising. If the engine ever switched the
    --    metatable behavior (or the table itself was replaced), the rawget
    --    guard would no longer be load-bearing and we'd want to know.
    local IML = rawget(_G, "ItemMasterList")
    if type(IML) == "table" then
        local ok, value = pcall(rawget, IML, "__cwv_iml_rawget_probe_does_not_exist__")
        if not ok then
            return "rawget(ItemMasterList, <bad-key>) RAISED — strict-metatable behavior changed"
        end
        if value ~= nil then
            return "rawget(ItemMasterList, <bad-key>) returned non-nil — unexpected"
        end
    end
end)

_rt_register("cwv_networklookup_uses_rawget", function()
    -- v0.1.330/.332: three call sites in `character_weapon_variants.lua`
    -- (damage_profiles reverse lookup ~L5185, pickup_names reverse lookups
    -- ~L5270 + ~L5285) resolve RPC-payload IDs through
    -- `rawget(NetworkLookup.*, key)` so a malformed/out-of-range ID returns
    -- nil instead of raising the strict `__index` metatable. The
    -- strict-table-lookup lint covers static-pattern regressions; this runtime
    -- check is the belt-and-suspenders companion required by §15 of
    -- PROJECT_STANDARDS.md.
    --
    -- 1. Source-pattern: marker constant must be present.
    if CT_CWV_NETWORKLOOKUP_RAWGET_MARKER_v0_1_332 ~= "cwv-networklookup-rawget-hardened-3-sites" then
        return "RAWGET marker absent — was the v0.1.330 three-site RPC hardening reverted?"
    end
    -- 2. Runtime-state: rawget on a known-bad key against the two NL subtables
    --    that the three sites read (damage_profiles + pickup_names). Both
    --    must return nil without raising.
    local NL = rawget(_G, "NetworkLookup")
    for _, sub in ipairs({ "damage_profiles", "pickup_names" }) do
        local tbl = NL and NL[sub]
        if type(tbl) == "table" then
            local ok, value = pcall(rawget, tbl, "__cwv_rawget_probe_does_not_exist__")
            if not ok then
                return string.format("rawget(NetworkLookup.%s, <bad-key>) RAISED — strict-metatable behavior changed", sub)
            end
            if value ~= nil then
                return string.format("rawget(NetworkLookup.%s, <bad-key>) returned non-nil — unexpected", sub)
            end
        end
    end
end)

_rt_register("cwv_slot_extension_scoped", function()
    -- v0.1.338: the slot_melee "ranged" extension MUST be scoped to only
    -- careers that own a `cross_slot = true` variant. Broad application
    -- across all 28 careers caused a dual-state-machine collision on
    -- Grail Knight (and other multi-melee-archetype careers): two FP
    -- state machines were loaded simultaneously into one FP rig, producing
    -- wrong-grip / corrupted-looking first-person weapons. See marker
    -- constant `CT_CWV_SLOT_EXTENSION_MARKER_v0_1_338`.
    --
    -- 1. Source-pattern: marker constant must be present.
    if CT_CWV_SLOT_EXTENSION_MARKER_v0_1_338 ~= "cwv-slot-extension-scoped-to-cross-slot-variant-careers" then
        return "SLOT EXTENSION marker absent — was the v0.1.338 scoping fix reverted?"
    end
    if not _om._slot_extension_log_only then
        return "automatic slot-extension state is not marked log-only (issue 570 startup chat regression)"
    end
    -- 2. Compute the expected allowed-careers set from `_variant_definitions`.
    --    Walk every def, union the `careers` arrays of entries with
    --    `cross_slot = true`. As of v0.1.338 only `cwv_es_musket_old` is
    --    cross-slot, so the expected set is the four Empire careers.
    local expected = _cwv_collect_cross_slot_careers()
    local expected_count = 0
    for _ in pairs(expected) do expected_count = expected_count + 1 end
    if expected_count == 0 then
        return "no cross_slot variants defined — definition table changed shape?"
    end
    -- 3. Runtime-state: walk CareerSettings; every allowed career MUST have
    --    "ranged" in its slot_melee, every non-allowed career MUST NOT.
    local CS = rawget(_G, "CareerSettings")
    if type(CS) ~= "table" then
        return "CareerSettings not loaded yet (run in-keep)"
    end
    local missing, leaked = {}, {}
    for career_name, career in pairs(CS) do
        if type(career) == "table" and career.item_slot_types_by_slot_name then
            local sm = career.item_slot_types_by_slot_name.slot_melee
            if type(sm) == "table" then
                local has_ranged = false
                for _, t in ipairs(sm) do
                    if t == "ranged" then has_ranged = true; break end
                end
                if expected[career_name] and not has_ranged then
                    missing[#missing + 1] = career_name
                elseif (not expected[career_name]) and has_ranged then
                    leaked[#leaked + 1] = career_name
                end
            end
        end
    end
    if #missing > 0 then
        return "expected slot_melee 'ranged' missing on allowed careers: " .. table.concat(missing, ", ")
    end
    if #leaked > 0 then
        return "slot_melee 'ranged' leaked to NON-allowed careers (broad-extension regression): " .. table.concat(leaked, ", ")
    end
end)

_rt_register("cwv_wield_hook_unique", function()
    -- v0.1.339 (Issue #33): assert there is exactly ONE
    -- `mod:hook_safe("SimpleInventoryExtension", "wield", ...)` registration
    -- in this file. VMF's `mod:hook_safe` does NOT chain — a second
    -- registration on the same (Class, method) silently overwrites the first
    -- (VMF_RECIPES.md § 1). v0.1.336 burned this exact bug: a debug-mode
    -- wield dump added at ~line 9499 shadowed the cross-access tracking at
    -- line 1336, silently breaking 3P animation remap. v0.1.337 consolidated
    -- both bodies into one callback; this regression test guards against
    -- reintroduction.
    --
    -- Mechanism: file-scope counter `_cwv_wield_hook_registration_count` is
    -- incremented at the registration site immediately before the
    -- `mod:hook_safe` call. Any future duplicate site would increment it
    -- again at module-load time. Counter is set at file scope, so this check
    -- runs against the cumulative count after the whole file has loaded.
    if _cwv_wield_hook_registration_count ~= 1 then
        -- Error string intentionally avoids the literal hook_safe call signature
        -- so the mod-lint regex doesn't flag this regression-check site as a
        -- second registration. See `tools/mod-lint/lint-mod.ps1` $rxHook.
        return string.format(
            "expected exactly 1 SimpleInventoryExtension wield safe-hook registration, got %d -- duplicate-hook regression (VMF silently shadows the first body; see VMF_RECIPES.md sec 1)",
            _cwv_wield_hook_registration_count)
    end
end)

_rt_register("issue398_cross_access_audio_uses_networked_receiver_event", function()
    if _cwv_networked_3p_remap_installed ~= true then
        return "WeaponUnitExtension._play_3p_anim network remap hook not installed"
    end
    if type(_om._cross_access_target_event) ~= "function" then
        return "cross-access receiver-event resolver missing"
    end

    local checked = 0
    local anims = rawget(_G, "NetworkLookup")
    anims = anims and anims.anims
    for item_key, careers in pairs(_cross_access_action_remap) do
        for career, remaps in pairs(careers) do
            for source, expected in pairs(remaps) do
                checked = checked + 1
                local target = _om._cross_access_target_event(item_key, career, source)
                if target ~= expected then
                    return string.format("network receiver-event drift %s/%s %s -> %s (expected %s)",
                        tostring(item_key), tostring(career), tostring(source),
                        tostring(target), tostring(expected))
                end
                if type(anims) == "table" and rawget(anims, target) == nil then
                    return string.format("network receiver event absent from NetworkLookup.anims: %s", target)
                end
            end
        end
    end
    if checked == 0 then
        return "cross-access network audio regression checked no remaps"
    end
    if _om._cross_access_target_event("es_1h_sword", "es_mercenary", "attack_swing_left") ~= nil then
        return "network remap leaked to unrelated/native weapon"
    end
end)

_rt_register("cwv_husk_fx_guard_installed", function()
    -- Issue #280 (CLIENT CTD): a remote player wielding the Kruber Axe &
    -- Shield variant crashed every non-Bardin client. Root cause: the variant
    -- inherits `.name = "dr_shield_axe"` (clone-name-clobber), so the husk
    -- resolves the vanilla base's NON-resident 3P units; vanilla `_wield_slot`
    -- bails before setting `equipment.wielded_slot` (line 775),
    -- cosmetics_tweaker's `_wield_slot` wrap pcall-swallows the fault, and
    -- vanilla `start_weapon_fx` then indexes `equipment.slots[nil]` -> CTD.
    -- Two-part fix: (1) force-load the base units so they are resident on
    -- every client; (2) a defensive guard on start_weapon_fx that no-ops when
    -- the wielded slot is nil. This test asserts BOTH landed at load time.
    if _cwv_husk_fx_guard_installed ~= true then
        return "SimpleHuskInventoryExtension.start_weapon_fx guard hook not installed (Issue #280 client-CTD regression)"
    end
    if _cwv_axe_shield_residency_ran ~= true then
        return "dr_shield_axe base-unit force-load did not run (Issue #280 husk-residency primary fix)"
    end
end)

_rt_register("cwv_net_safe_loadout_sync_installed", function()
    -- Issue #278 (CLIENT CTD): the host equipping a cwv item (native or
    -- cim-crafted) broadcast `rpc_sync_loadout_slot` with the HOST-LOCAL
    -- `NetworkLookup.item_names` index of the cwv key. That index depends on
    -- which other mods appended to item_names on each peer (LA via
    -- cosmetics_tweaker's _la_bridge being the big divergence source), so a
    -- client with a shorter table CTD'd in the strict __index metamethod
    -- (network_lookup.lua:2521 via loadout_utils.lua:72). The fix substitutes
    -- the variant's vanilla `base_weapon` key on the wire (shadow item).
    -- This asserts the sender-side hook actually installed at load time.
    if _cwv_net_safe_loadout_hook_installed ~= true then
        return "LoadoutUtils.sync_loadout_slot net-safe hook not installed (Issue #278 client-CTD regression)"
    end
    -- Every non-skin-only def must carry a base_weapon that resolves in
    -- ItemMasterList — it is the wire fallback key.
    for _, d in ipairs(_variant_definitions) do
        if not d.skin_only and (type(d.base_weapon) ~= "string"
                or not rawget(ItemMasterList, d.base_weapon)) then
            return string.format(
                "variant %s has no resolvable base_weapon (%s) — net-safe loadout sync cannot substitute it (Issue #278)",
                tostring(d.item_key), tostring(d.base_weapon))
        end
    end
end)

_rt_register("cwv_outrider_no_ammo_unit", function()
    -- Issue #279 (merged render): the outrider entry inherited dr_deus_01's
    -- torpedo ammo_unit/ammo_unit_3p from the clone; with the template's
    -- ammo_data intact (ammo_hand flipped to "right"), any NO-SKIN resolution
    -- (cim-crafted copies carry no pre-applied skin) attached the trollhammer
    -- torpedo to the blunderbuss (gear_utils.lua:164/169/248). The def now
    -- declares `no_ammo_unit = true` and `_build_entry` clears both fields.
    local d = _find_def("cwv_es_outrider_grenade_launcher")
    if not d then return nil end -- def removed entirely: nothing to guard
    if d.no_ammo_unit ~= true then
        return "cwv_es_outrider_grenade_launcher def lost no_ammo_unit = true (Issue #279 merged-render regression)"
    end
    local entry = ItemMasterList and rawget(ItemMasterList, "cwv_es_outrider_grenade_launcher")
    if entry and (entry.ammo_unit ~= nil or entry.ammo_unit_3p ~= nil) then
        return string.format(
            "outrider ItemMasterList entry still carries ammo units (ammo_unit=%s ammo_unit_3p=%s) — torpedo will merge into no-skin renders (Issue #279)",
            tostring(entry.ammo_unit), tostring(entry.ammo_unit_3p))
    end
end)

_rt_register("cwv_husk_override_residency", function()
    -- Issues 401 / 396 (confirmed, paired peer logs): the husk spawns a CWV
    -- variant's curated-skin mesh, which carries the def's per-hand OVERRIDE
    -- units. When those override units are non-resident on a client not playing
    -- the source character, the skin-path spawn fails and the husk shows the
    -- base (or nothing). v0.1.366-dev shipped a HARD-CODED 5-key residency list;
    -- v0.1.367-dev makes the pass DATA-DRIVEN (walks every def, force-loads any
    -- right/left override unit that differs from its base). This test asserts
    -- coverage is complete BY CONSTRUCTION: every override unit the shared
    -- predicate flags as needing residency (+ its `_3p` form) is in the loaded
    -- set. Derived from the SAME predicate the pass uses, so a new variant with
    -- an override mesh can never silently slip past residency.
    if _cwv_husk_override_residency_ran ~= true then
        return "husk override-unit residency did not run (issues 401/396 fix missing)"
    end
    local loaded = _cwv_husk_override_paths
    if type(loaded) ~= "table" then
        return "_cwv_husk_override_paths not exposed (issue 401 residency-target guard)"
    end
    local needs = _om._husk_override_unit_needs_residency
    if type(needs) ~= "function" then
        return "_om._husk_override_unit_needs_residency predicate not exposed (issues 396/401)"
    end
    local n_checked = 0
    for _, d in ipairs(_variant_definitions) do
        for _, field in ipairs({ "right_hand_unit", "left_hand_unit" }) do
            local u = needs(d, field)
            if u then
                n_checked = n_checked + 1
                if not loaded[u] then
                    return string.format(
                        "husk override residency missing %s for %s.%s (issues 396/401 -- data-driven pass gap)",
                        tostring(u), tostring(d.item_key), field)
                end
                if not loaded[u .. "_3p"] then
                    return string.format(
                        "husk override residency missing %s_3p for %s.%s (issues 396/401 -- _3p form not loaded)",
                        tostring(u), tostring(d.item_key), field)
                end
            end
        end
    end
    -- Sanity floor: the axe & shield Empire override (the original issue-401
    -- repro) must specifically be present, and we must have covered more than
    -- the old 5-key hard-coded list (guards against the predicate degenerating
    -- to nil-for-everything and the loop vacuously passing).
    local axe = _find_def("cwv_es_axe_shield")
    if axe and type(axe.right_hand_unit) == "string" and not loaded[axe.right_hand_unit] then
        return string.format(
            "husk residency missing the Empire override unit %s for cwv_es_axe_shield (issue 401)",
            tostring(axe.right_hand_unit))
    end
    if n_checked < 6 then
        return string.format(
            "husk override residency covered only %d override units -- predicate likely degenerated (issues 396/401)",
            n_checked)
    end
end)

_rt_register("cwv_no_ammo_strip_coverage", function()
    -- Issue 399: the husk resolves the BASE item_data, so a variant that set
    -- `no_ammo_unit = true` (its base carries an ammo/torpedo unit the variant
    -- must not show) needs its (base_weapon, career) pair in the husk strip
    -- lookup. The lookup is built by walking every def, so coverage is
    -- structural -- this test locks that: every no_ammo_unit def must appear in
    -- `_om._no_ammo_careers_by_base` with ALL its careers, or the inherited
    -- ammo mesh would render on the husk (the merged-render bug of issue 279).
    local cov = _om._no_ammo_careers_by_base
    if type(cov) ~= "table" then
        return "_om._no_ammo_careers_by_base not exposed -- husk ammo-strip coverage guard (issue 399)"
    end
    for _, d in ipairs(_variant_definitions) do
        if d.no_ammo_unit then
            local set = cov[d.base_weapon]
            if type(set) ~= "table" then
                return string.format(
                    "no_ammo_unit def %s (base %s) missing from husk strip lookup -- inherited ammo would render on husk (issue 399)",
                    tostring(d.item_key), tostring(d.base_weapon))
            end
            for _, c in ipairs(d.careers or {}) do
                if not set[c] then
                    return string.format(
                        "no_ammo_unit def %s career %s not covered by husk strip lookup (issue 399)",
                        tostring(d.item_key), tostring(c))
                end
            end
        end
    end
end)

_rt_register("cwv_husk_transform_coverage", function()
    -- Issues 397/394: the husk 3P weapon spawns through
    -- GearUtils.spawn_inventory_unit (the only GearUtils path husks hit), NOT
    -- create_equipment where the owner-side transforms live. v0.1.366-dev wires
    -- the transform apply into that husk hook via `_om._husk_apply_cwv_transform`
    -- and the ammo strip via `_om._husk_strip_cwv_ammo`. Assert both landed so
    -- the coverage can't silently disappear on a refactor.
    if type(_om._husk_apply_cwv_transform) ~= "function" then
        return "_om._husk_apply_cwv_transform missing -- husk transform coverage lost (issues 397/394)"
    end
    if type(_om._husk_strip_cwv_ammo) ~= "function" then
        return "_om._husk_strip_cwv_ammo missing -- husk ammo-strip coverage lost (issue 399)"
    end
    if _cwv_husk_wield_diag_installed ~= true then
        return "husk _wield_slot diagnostic hook not installed (issues 395/398 evidence arm)"
    end
end)


end
