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
		es_sword_shield = { "empire", "bretonnian" },
		es_sword_shield_breton = { "bretonnian", "empire" },
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
	local native_bret_greatsword = policy.package("es_bastard_sword", "greatsword")
	local native_bret_kerillian = policy.package("es_bastard_sword", "kerillian")
	if not bret_package or not bret_package.presentation
			or bret_package.presentation.transform_key ~= "greatsword_bretonnian"
			or (native_bret_package and native_bret_package.presentation ~= nil)
			or not native_bret_greatsword or not native_bret_greatsword.presentation
			or native_bret_greatsword.presentation.transform_key ~= "bretonnian_greatsword_inverse"
			or not native_bret_kerillian or not native_bret_kerillian.presentation
			or native_bret_kerillian.presentation.transform_key ~= "bretonnian_greatsword_inverse" then
		return "Greatsword Bretonnian receiver presentation drifted"
	end
	local inverse = runtime:presentation("bretonnian_greatsword_inverse")
	if type(inverse) ~= "table"
			or inverse.item_key ~= "cwv_style_bretonnian_greatsword_inverse"
			or math.abs((inverse.right_hand_scale and inverse.right_hand_scale[2] or 0) - 1.25) > 0.000001
			or math.abs((inverse.right_hand_scale and inverse.right_hand_scale[3] or 0) - (1 / 0.9)) > 0.000001
			or math.abs((inverse.right_hand_offset and inverse.right_hand_offset[3] or 0) - 0.065) > 0.000001 then
		return "Bretonnian Greatsword inverse transform drifted"
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

_rt_register("issue786_peer_resolution_multi_return", function()
	local resolver = _om.peer_resolver
	if type(resolver) ~= "table" then return "shared peer resolver is not installed" end
	local marker = { is_player_controlled = function() return true end }
	local player, source = resolver.peer_player({
		player_from_peer_id = function(_, peer_id, local_player_id)
			if peer_id == "issue786_peer" and local_player_id == 1 then return marker end
		end,
	}, "issue786_peer", 1)
	if player ~= marker or source ~= "player_from_peer_id" then
		return "protected PlayerManager return value collapsed"
	end
	local bot = {
		peer_id = "issue786_peer",
		_local_player_id = 2,
		is_player_controlled = function() return false end,
	}
	local owner_player = resolver.owner({
		owner = function() return bot end,
	}, "issue786_bot_unit")
	local direct_player = resolver.peer_player({
		player_from_peer_id = function() return bot end,
	}, "issue786_peer", 1)
	if owner_player ~= nil or direct_player ~= nil then
		return "same-peer host bot consumed human style/mode identity"
	end
	local profile, career = resolver.profile_by_peer({
		profile_by_peer = function() return 5, 3 end,
	}, "issue786_peer", 1)
	if profile ~= 5 or career ~= 3 then
		return "protected ProfileSynchronizer tuple collapsed"
	end
	if _om.combat_style_policy.MAX_REMOTE_REFRESH_ATTEMPTS ~= 8
			or type(_om.combat_styles.step) ~= "function" then
		return "bounded remote style refresh owner is not installed"
	end
	-- #786 A1/A2 live wiring. Disconnecting either half must fail here: the
	-- husk re-wield rides the #1145 coalescer and the verdict is AND-semantics
	-- over the authored catalogue, never an OR of hand liveness.
	local rewield = _om.style_rewield
	if type(rewield) ~= "table"
			or rewield.MARKER ~= "cwv-style-rewield-and-semantics-v1"
			or type(rewield.queue_rebuild) ~= "function"
			or type(mod._cwv_rewield) ~= "table"
			or type(mod._cwv_rewield.request_peer_rewield) ~= "function" then
		return "#786 guarded style re-wield is not installed"
	end
	local expectation = rewield.expectation(_om.combat_style_policy,
		"spear_shield", "elven", "es_deus_01")
	if not expectation or expectation.left ~= true
			or expectation.template ~= _om.combat_style_policy.ELVEN_SPEAR_SHIELD_TEMPLATE then
		return "#786 authored re-wield expectation drifted"
	end
	local observed = { wielded = true, item_key = "es_deus_01",
		template = expectation.template, right_live = true, left_live = false }
	if rewield.verdict(expectation, observed) ~= "partial"
			or rewield.succeeded("partial") then
		return "#786 verdict accepted a partial re-wield (OR predicate is back)"
	end
	if type(_om.combat_styles.accept_style_edge) ~= "function"
			or _om.combat_style_policy.encode_style_rider("spear_shield", "elven")
				~= "spear_shield:elven" then
		return "#786 style axis is not on the identity transaction"
	end
end)

_rt_register("issue914_peer_ready_identity_lifecycle", function()
	local resolver = _om.peer_resolver
	local pull = _om.identity_peer_pull
	local policy = _om.appearance_lifecycle_policy
	if type(resolver) ~= "table" or type(resolver.husk_owner) ~= "function"
			or type(resolver.player_peer_id) ~= "function"
			or type(pull) ~= "table" or type(pull.slots_ready) ~= "function"
			or type(policy) ~= "table" or type(policy.new) ~= "function" then
		return "#914 peer lifecycle owners are not installed"
	end
	if mod._cwv914_client_peer_cleanup_installed ~= true then
		return "#914 client-visible PlayerManager cleanup hook is not installed"
	end
	if pull.slots_ready({}) or not pull.slots_ready({ slot_melee = {} }) then
		return "#914 pre-ready slot gate drifted"
	end
	local hinted = {
		peer_id = "issue914-peer",
		is_player_controlled = function() return true end,
	}
	local owner, source = resolver.husk_owner({
		owner = function() error("spawn owner table is not ready") end,
	}, "issue914-unit", hinted)
	if owner ~= hinted or source ~= "husk_extension_player"
			or resolver.player_peer_id(owner) ~= "issue914-peer" then
		return "#914 spawn-local husk player hint is not authoritative"
	end

	local sent = {}
	local lifecycle = policy.new({
		resolve_local = function()
			return {
				provider = "cwv", variant_key = "issue914-variant",
				base_item_key = "issue914-base", fingerprint = "issue914-fp",
			}, "issue914-base"
		end,
		resolve_remote = function() return nil, "unused" end,
		send = function(recipient, _, payload)
			sent[recipient .. "|" .. payload.slot] =
				(sent[recipient .. "|" .. payload.slot] or 0) + 1
			return true
		end,
	})
	local slots = { slot_melee = {} }
	lifecycle:publish(slots, "probe", "issue914-peer", false, true)
	lifecycle:publish(slots, "probe", "others", false, true)
	lifecycle:clear_peer("issue914-peer")
	lifecycle:publish(slots, "probe", "issue914-peer", false, true)
	lifecycle:publish(slots, "probe", "others", false, true)
	if sent["issue914-peer|slot_melee"] ~= 2
			or sent["others|slot_melee"] ~= 1 then
		return "#914 peer cleanup did not reopen only the departed peer route"
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
	local empire_sword = policy.package("es_sword_shield_breton", "empire")
	local bretonnian_sword = policy.package("es_sword_shield", "bretonnian")
	if not empire_sword or empire_sword.template ~= "one_handed_sword_shield_template_1"
			or empire_sword.resource ~= "units/beings/player/first_person_base/state_machines/melee/1h_sword_shield"
			or not bretonnian_sword
			or bretonnian_sword.template ~= "one_handed_sword_shield_template_2"
			or bretonnian_sword.resource ~= "units/beings/player/first_person_base/state_machines/melee/1h_sword_shield_breton"
			or bretonnian_sword.required_dlc ~= "lake" then
		return "reciprocal Empire/Bretonnian Sword and Shield descriptors drifted"
	end
	if type(rawget(Weapons, empire_sword.template)) ~= "table"
			or type(rawget(Weapons, bretonnian_sword.template)) ~= "table" then
		return "reciprocal Empire/Bretonnian Sword and Shield donor template missing"
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
			"hot_join_sync", "peer_ready" }) do
		if not (surfaces and surfaces[name]) then return "missing CWV identity surface: " .. name end
	end
	local plan = _om._cwv_identity_payloads
	local accept = _om._cwv_accept_identity
	local resolve = _om._cwv_identity_def_for_peer
	if type(plan) ~= "function" or type(accept) ~= "function" or type(resolve) ~= "function" then
		return "CWV item-identity side-channel helpers missing"
	end
	local skin_key = "cwv_es_longsword_nordland_skin"
	local payloads = plan({
		slot_melee = {
			item_data = { name = "es_bastard_sword", cwv_key = "cwv_es_longsword" },
			skin = skin_key,
		},
		slot_ranged = { item_data = { name = "es_handgun" } },
	})
	local by_slot = {}
	for _, payload in ipairs(payloads) do by_slot[payload.slot] = payload end
	if not by_slot.slot_melee or by_slot.slot_melee.item_key ~= "cwv_es_longsword"
			or by_slot.slot_melee.skin_key ~= skin_key
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
	local descriptor = _om._cwv_identity_descriptor_for_peer(
		"rt396-peer", "slot_melee", "es_bastard_sword")
	if not descriptor or descriptor.skin ~= skin_key then
		return "semantic identity channel lost the exact Helmgart illusion"
	end
	local native = by_slot.slot_ranged
	native.slot = "slot_melee"
	native.base_item_key = "es_bastard_sword"
	accept("rt396-peer", _om.appearance_lifecycle_policy.SCHEMA, native)
	if resolve("rt396-peer", "slot_melee", "es_bastard_sword") ~= nil then
		return "native-slot clear left stale CWV identity behind"
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
	if type(lifecycle.begin_request) ~= "function"
			or type(lifecycle.accept_request) ~= "function"
			or type(lifecycle.step_request) ~= "function"
			or type(_om._cwv_request_peer_identities) ~= "function"
			or not (mod._cwv_identity_surfaces
				and mod._cwv_identity_surfaces.mission_transition_peer_pull) then
		return "#401/#914 bounded mission-transition peer-ready pull is not installed"
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

_rt_register("issue719_imperial_crowbill_remote_identity", function()
	local family = _om.crowbill_family
	local plan = _om._cwv_identity_payloads
	local accept = _om._cwv_accept_identity
	local resolve = _om._cwv_identity_descriptor_for_peer
	if not family or type(plan) ~= "function" or type(accept) ~= "function"
			or type(resolve) ~= "function" then
		return "#719 exact Crowbill identity prerequisites are not installed"
	end
	if type(_om._husk_preselect_units) ~= "function"
			or type(_om._husk_rekey_units) ~= "function"
			or type(_om._husk_apply_cwv_transform) ~= "function" then
		return "#719 centralized husk appearance adapters are not installed"
	end
	local surfaces = mod._cwv_identity_surfaces
	if type(surfaces) ~= "table" or surfaces.network ~= true
			or surfaces.remote_husk ~= true or surfaces.husk_wield ~= true
			or surfaces.game_object_initialized ~= true
			or surfaces.spawn_resynced_loadout ~= true
			or surfaces.hot_join_sync ~= true or surfaces.peer_ready ~= true then
		return "#719 exact identity lifecycle surface coverage is incomplete"
	end
	-- GROUND TRUTH (#1156): the authored Crowbill catalog and variant table, never
	-- the resolver under test and never state the defect itself produces.
	local model = family.model_for_variant
		and family.model_for_variant("cwv_es_imperial_crowbill")
	if not model or type(model.right_hand_unit) ~= "string"
			or model.right_hand_unit == family.PLACEHOLDER_UNIT then
		return "#719 Imperial Crowbill model is absent or still resolves to Sienna's donor"
	end
	local authored = _find_def("cwv_es_imperial_crowbill")
	if not authored or authored.base_weapon ~= family.SOURCE_ITEM
			or authored.right_hand_unit ~= model.right_hand_unit then
		return "#719 authored variant def lost the Imperial model or its bw_1h_crowbill base"
	end
	local payloads = plan({
		slot_melee = {
			item_data = {
				name = family.SOURCE_ITEM,
				-- Canonical CIM synthetic shape: the cloned vanilla-base row keeps
				-- its exact acquisition identity inside mod_data.  Do not rely on
				-- a cwv-prefixed backend id or a top-level convenience stamp.
				mod_data = {
					backend_id = "rt719-guid-shaped-backend",
					cwv_key = "cwv_es_imperial_crowbill",
				},
			},
		},
	})
	local payload
	for _, candidate in ipairs(payloads) do
		if candidate.slot == "slot_melee" then payload = candidate; break end
	end
	if not payload or payload.item_key ~= "cwv_es_imperial_crowbill"
			or payload.base_item_key ~= family.SOURCE_ITEM
			or payload.skin_key ~= "" or type(payload.fingerprint) ~= "string"
			or payload.fingerprint == "" then
		return "#719 owner payload collapsed the skinless Imperial Crowbill to its donor"
	end
	local changed, descriptor, reason = accept("rt719-peer",
		_om.appearance_lifecycle_policy.SCHEMA, payload)
	if not changed or reason ~= "exact" or not descriptor
			or descriptor.variant_key ~= "cwv_es_imperial_crowbill"
			or descriptor.right_hand_unit ~= model.right_hand_unit
			or descriptor.right_hand_unit == family.PLACEHOLDER_UNIT then
		return "#719 receiver did not reconstruct the exact Imperial Crowbill model"
	end
	local retained, state = resolve("rt719-peer", "slot_melee", family.SOURCE_ITEM)
	if state ~= "exact" or retained ~= descriptor then
		return "#719 reconstructed Imperial Crowbill was not retained for husk wield"
	end
	local duplicate = accept("rt719-peer",
		_om.appearance_lifecycle_policy.SCHEMA, payload)
	if duplicate then
		return "#719 duplicate identity scheduled a second husk rebuild"
	end

	-- POSTCONDITION 1 (what the player sees): the remote peer must either know
	-- the exact variant at WIELD time from the vanilla wire alone, or own a
	-- mechanism that re-applies an identity that lands after the wield. The
	-- 2026-08-04 co-op session measured the exact identity arriving 41 s late.
	local career = family.IMPERIAL_DEFAULTS and family.IMPERIAL_DEFAULTS[1]
	local wield_def = career and type(_om._husk_resolve_display_def) == "function"
		and _om._husk_resolve_display_def(family.SOURCE_ITEM, career, nil) or nil
	local rewield = mod._cwv_rewield
	local late_reapply = type(rewield) == "table"
		and type(rewield.request_peer_rewield) == "function"
		and mod._cwv_rewield_update_installed == true
	if not ((wield_def and wield_def.item_key == "cwv_es_imperial_crowbill") or late_reapply) then
		return "#719 husk can neither resolve the Imperial Crowbill at wield time nor re-apply a late identity"
	end

	-- POSTCONDITION 2: neither path renders anything while the AUTHORED mesh is
	-- inadmissible on a remote peer. A husk admits a non-vanilla mesh only through
	-- the cwv custom-bundle arm (_om._husk_custom_bundle_unit, donor-material
	-- gated) or a units/weapons/player/ bounded lease (_om._husk_lease_override).
	-- A Crowbill model registered in neither keeps the shadowed bw_1h_crowbill
	-- donor for the whole mission, which is exactly the reported symptom.
	local inadmissible = {}
	for _, m in ipairs(family.usable_models and family.usable_models() or {}) do
		local unit = m.right_hand_unit
		local bundled = type(_om._husk_custom_bundle_unit) == "function"
			and _om._husk_custom_bundle_unit(unit) == true
		local leasable = type(unit) == "string"
			and unit:find("units/weapons/player/", 1, true) == 1
		if not (bundled or leasable) then inadmissible[#inadmissible + 1] = m.key end
	end
	if #inadmissible > 0 then
		return "#719 remote husk cannot admit the authored Crowbill mesh for "
			.. #inadmissible .. " model(s) (" .. table.concat(inadmissible, ", ")
			.. "): neither a registered cwv custom-bundle unit nor leasable -- the peer keeps the bw_1h_crowbill donor"
	end

	-- POSTCONDITION 3: admission is not enough on its own -- the spawn floor the
	-- husk actually consults must AGREE. `_husk_unit_spawnable` is what
	-- `_husk_preselection_ready` and the re-key gate call, and a self-contained
	-- bundle mesh declares no donor material, so it must clear that floor rather
	-- than fail closed on a donor that does not exist.
	local unspawnable = {}
	for _, m in ipairs(family.usable_models and family.usable_models() or {}) do
		if type(_om._husk_unit_spawnable) ~= "function"
				or _om._husk_unit_spawnable(m.right_hand_unit) ~= true then
			unspawnable[#unspawnable + 1] = m.key
		end
	end
	if #unspawnable > 0 then
		return "#719 husk spawn floor rejects the authored Crowbill mesh for "
			.. #unspawnable .. " model(s) (" .. table.concat(unspawnable, ", ")
			.. "): hand preselection defers and the peer keeps the bw_1h_crowbill donor"
	end

	-- The admission arm must stay SCOPED: a vanilla player mesh is owned by the
	-- residency/lease arms, never by the custom-bundle arm, or the #418 force-load
	-- reference contract collapses into "anything goes".
	if _om._husk_custom_bundle_unit(family.PLACEHOLDER_UNIT) ~= false then
		return "#719 custom-bundle admission leaked onto the vanilla bw_1h_crowbill donor mesh"
	end
end)

_rt_register("issue579_dual_axes_preview_and_husk_skin_continuity", function()
    local source_by_target = _om._dual_axes_source_by_skin
    local ws = rawget(_G, "WeaponSkins")
    if type(source_by_target) ~= "table" or type(ws) ~= "table" or type(ws.skins) ~= "table" then
        return "dual-axes generated skins not loaded yet (run in-keep)"
    end
    local apply_preview = mod._cwv_preview_meshswap_apply
    local plan_identity = _om._cwv_identity_payloads
    local receive_identity = _om._cwv_receive_identity
    local resolve_identity = _om._cwv_identity_descriptor_for_peer
    local lifecycle = _om._appearance_lifecycle
    local rewield = mod._cwv_rewield
    local husk_pre = _om._husk_adapter_pre
    if type(apply_preview) ~= "function" or type(plan_identity) ~= "function"
            or type(receive_identity) ~= "function" or type(resolve_identity) ~= "function"
            or type(lifecycle) ~= "table" or type(lifecycle.clear_peer) ~= "function"
            or type(rewield) ~= "table" or type(rewield.request_peer_rewield) ~= "function"
            or type(husk_pre) ~= "function" then
		return "#579 live identity receiver/per-hand husk adapter is not installed"
    end
    if not (mod._cwv_skin_wire_surfaces
            and mod._cwv_skin_wire_surfaces.vanilla_skin_replay_retired) then
		return "#579 unsafe numeric skin replay is not retired"
    end

    for _, target_key in ipairs({ "cwv_es_dual_axes", "cwv_wh_dual_axes" }) do
        -- GROUND TRUTH (#1156): the authored variant table declares a TWO-HANDLE
        -- pair, and each generated illusion's mesh is the vanilla cosmetic it was
        -- cut from. Neither expectation comes from the identity path under test,
        -- and neither is the already-collapsed value the defect produces.
        local authored = _find_def(target_key)
        if not authored or type(authored.right_hand_unit) ~= "string"
                or type(authored.left_hand_unit) ~= "string" or authored.no_left_hand then
            return target_key .. " authored def is no longer a two-handle pair"
        end
        local clones = source_by_target[target_key]
        if type(clones) ~= "table" then
            return target_key .. " has no generated illusion family for the continuity test"
        end
        -- Every generated skin, not a `next()` sample: one bad clone is the bug.
        local keys, mesh_of = {}, {}
        for clone in pairs(clones) do keys[#keys + 1] = clone end
        table.sort(keys)
        for _, clone in ipairs(keys) do
            local skin = ws.skins[clone]
            if type(skin) ~= "table" or type(skin.right_hand_unit) ~= "string"
                    or type(skin.left_hand_unit) ~= "string" then
                return clone .. " does not preserve both generated hands"
            end
            local source = ws.skins[clones[clone]]
            if type(source) ~= "table" or source.right_hand_unit ~= skin.right_hand_unit then
                return clone .. " drifted from its vanilla source mesh " .. tostring(clones[clone])
            end
            mesh_of[clone] = skin.right_hand_unit
        end
        -- The player-visible case from the 0.1.408-dev card: DISTINCT right and
        -- offhand illusions saved on one pair. Pick two clones whose authored
        -- meshes actually differ, so a pair collapsed onto a single model cannot
        -- satisfy the assertion by string equality (the pre-#1156 blind spot).
        local right_skin, left_skin
        for _, clone in ipairs(keys) do
            if not right_skin then
                right_skin = clone
            elseif mesh_of[clone] ~= mesh_of[right_skin] then
                left_skin = clone
                break
            end
        end
        if not left_skin then
            return target_key .. " family carries fewer than two distinct meshes; per-hand identity is unprovable"
        end

        -- Preview: each hand keeps the illusion saved for THAT hand. info.skin_name
        -- is the stored primary identity and must not clobber the exact offhand.
        local info = {
            skin_name = right_skin,
            spawn_data = {
                { right_hand = true, unit_name = mesh_of[right_skin] .. "_3p" },
                { left_hand = true, unit_name = mesh_of[left_skin] .. "_3p" },
            },
        }
        apply_preview(authored.base_weapon, target_key .. "_001", nil, info)
        if info.spawn_data[1].unit_name ~= mesh_of[right_skin] .. "_3p"
                or info.spawn_data[2].unit_name ~= mesh_of[left_skin] .. "_3p" then
            return target_key .. " preview collapsed the pair onto a single illusion"
        end

        -- Wire: the vanilla equipment wire receives n/a, so the same-mod semantic
        -- channel is the only transport for the pair. It must reconstruct the SAME
        -- per-hand pair on the receiver; one model for two authored hands is the
        -- husk collapse the player reports.
        local cosmetics = get_mod and get_mod("cosmetics_tweaker")
        local provider_owner = cosmetics and cosmetics._cos
        local real_provider = provider_owner and provider_owner.cwv_offhand_identity
        if type(real_provider) ~= "function" then
            return target_key .. " committed Cosmetics offhand identity provider is unavailable"
        end
        local backend_id = "rt579-instance-" .. target_key
        local provider_had_raw = rawget(provider_owner, "cwv_offhand_identity") ~= nil
        local provider_raw = rawget(provider_owner, "cwv_offhand_identity")
        rawset(provider_owner, "cwv_offhand_identity", function(bid, item_type, hand_field)
            if bid == backend_id and item_type == target_key
                    and hand_field == "left_hand_unit" then
                return left_skin, "rt579-committed"
            end
            return real_provider(bid, item_type, hand_field)
        end)
        local plan_ok, payloads = pcall(plan_identity, {
                slot_melee = {
                    item_data = {
                        name = authored.base_weapon,
                        cwv_key = target_key,
                        backend_id = backend_id,
                    },
                    skin = right_skin,
                },
                slot_ranged = { item_data = { name = "wh_crossbow" } },
            })
        rawset(provider_owner, "cwv_offhand_identity",
            provider_had_raw and provider_raw or nil)
        if not plan_ok then
            return target_key .. " semantic sender raised: " .. tostring(payloads)
        end
        local payload
        for _, candidate in ipairs(payloads) do
            if candidate.slot == "slot_melee" then payload = candidate end
        end
        if not payload or payload.item_key ~= target_key
                or payload.base_item_key ~= authored.base_weapon
                or payload.skin_key ~= right_skin
                or payload.offhand_skin_key ~= left_skin then
            return target_key .. " semantic payload lost variant/base/per-hand skin identity"
        end
        local peer_id = "rt579-" .. target_key
        lifecycle:clear_peer(peer_id)

        -- Drive the exact callback registered on cwv_item_identity, then the
        -- exact adapter called by GearUtils.spawn_inventory_unit for EACH hand.
        -- The old regression called lifecycle:accept directly and stopped at a
        -- descriptor, so either live bridge could be disconnected while it
        -- remained green.
        local rewield_calls, ack_calls = {}, {}
        local request_had_raw = rawget(rewield, "request_peer_rewield") ~= nil
        local request_raw = rawget(rewield, "request_peer_rewield")
        local send_had_raw = rawget(mod, "network_send") ~= nil
        local send_raw = rawget(mod, "network_send")
        local player_mgr = Managers and Managers.player
        local old_owner = player_mgr and player_mgr.owner
        local owner_had_raw = player_mgr and rawget(player_mgr, "owner") ~= nil
        local old_owner_raw = player_mgr and rawget(player_mgr, "owner")
        local fake_owner = {}
        local item_units = {
            skin = right_skin,
            right_hand_unit = authored.right_hand_unit,
            left_hand_unit = authored.left_hand_unit,
        }
        local suppress_right, suppress_left
        local live_ok, live_err = pcall(function()
            rawset(rewield, "request_peer_rewield", function(received_peer, received_slot)
                rewield_calls[#rewield_calls + 1] = {
                    peer = received_peer, slot = received_slot,
                }
                return true, "rt579-spy"
            end)
            rawset(mod, "network_send", function(_, channel, recipient, schema, ack)
                ack_calls[#ack_calls + 1] = {
                    channel = channel, recipient = recipient,
                    schema = schema, payload = ack,
                }
                return true
            end)
            receive_identity(peer_id, _om.appearance_lifecycle_policy.SCHEMA, payload)
            if not (player_mgr and type(old_owner) == "function") then
                error("Managers.player:owner is unavailable")
            end
            rawset(player_mgr, "owner", function(self, unit)
                if unit == fake_owner then return { peer_id = peer_id } end
                return old_owner(self, unit)
            end)
            suppress_right = husk_pre("right", {}, item_units, "slot_melee",
                { name = authored.base_weapon }, fake_owner)
            suppress_left = husk_pre("left", {}, item_units, "slot_melee",
                { name = authored.base_weapon }, fake_owner)
        end)
        rawset(rewield, "request_peer_rewield", request_had_raw and request_raw or nil)
        rawset(mod, "network_send", send_had_raw and send_raw or nil)
        if player_mgr then
            rawset(player_mgr, "owner", owner_had_raw and old_owner_raw or nil)
        end

        local descriptor = resolve_identity(peer_id, "slot_melee", authored.base_weapon)
        if not live_ok then
            lifecycle:clear_peer(peer_id)
            return target_key .. " live receiver/husk adapter raised: " .. tostring(live_err)
        end
        if #ack_calls ~= 1 or ack_calls[1].channel ~= "cwv_item_identity"
                or ack_calls[1].recipient ~= peer_id
                or ack_calls[1].schema ~= _om.appearance_lifecycle_policy.SCHEMA then
            lifecycle:clear_peer(peer_id)
            return target_key .. " live receiver did not ACK the reconstructed pair exactly once"
        end
        if #rewield_calls ~= 1 or rewield_calls[1].peer ~= peer_id
                or rewield_calls[1].slot ~= "slot_melee" then
            lifecycle:clear_peer(peer_id)
            return target_key .. " live receiver did not schedule one bounded slot re-wield"
        end
        if not descriptor then
            lifecycle:clear_peer(peer_id)
            return target_key .. " live receiver did not reconstruct the pair at all"
        end
        if descriptor.right_hand_unit ~= mesh_of[right_skin]
                or descriptor.left_hand_unit ~= mesh_of[left_skin] then
            lifecycle:clear_peer(peer_id)
            return string.format(
                "%s husk pair collapsed to one model: reconstructed right=%s left=%s, authored right=%s left=%s",
                target_key, tostring(descriptor.right_hand_unit),
                tostring(descriptor.left_hand_unit), mesh_of[right_skin], mesh_of[left_skin])
        end
        if suppress_right == true or suppress_left == true
                or item_units.right_hand_unit ~= mesh_of[right_skin]
                or item_units.left_hand_unit ~= mesh_of[left_skin] then
            lifecycle:clear_peer(peer_id)
            return string.format(
                "%s live per-hand husk apply failed: suppress_right=%s suppress_left=%s right=%s left=%s",
                target_key, tostring(suppress_right), tostring(suppress_left),
                tostring(item_units.right_hand_unit), tostring(item_units.left_hand_unit))
        end
        lifecycle:clear_peer(peer_id)
        local def, reason = _om._husk_resolve_display_def(authored.base_weapon,
            target_key == "cwv_es_dual_axes" and "es_mercenary" or "wh_captain", right_skin)
        if not def or def.item_key ~= target_key or reason ~= "skin" then
            return right_skin .. " does not resolve to its target on the husk"
        end
    end
end)

_rt_register("issue416_483_transition_generated_skin_identity", function()
    local exact_skin = "cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1"
    local plan_identity = _om._cwv_identity_payloads
    local accept_identity = _om._cwv_accept_identity
    local resolve_identity = _om._cwv_identity_descriptor_for_peer
    local null_skins = _om._wire_null_skins
    if type(plan_identity) ~= "function" or type(accept_identity) ~= "function"
            or type(resolve_identity) ~= "function" or type(null_skins) ~= "function" then
		return "#416/#483 transition semantic identity helpers are not installed"
    end
    if not (mod._cwv_identity_surfaces and mod._cwv_identity_surfaces.mission_transition)
            or not (mod._cwv_skin_wire_surfaces
                and mod._cwv_skin_wire_surfaces.vanilla_skin_replay_retired) then
		return "#416/#483 transition identity/unconditional fallback surfaces are not installed"
    end

    -- The exact generated pair from the repro must retain both authored meshes
    -- and its clone-name-clobbered vanilla base id in a semantic payload.
    local skin = WeaponSkins and WeaponSkins.skins and WeaponSkins.skins[exact_skin]
    if type(skin) ~= "table" or type(skin.right_hand_unit) ~= "string"
            or type(skin.left_hand_unit) ~= "string" then
        return exact_skin .. " is absent or lost one generated hand"
    end
    local payloads = plan_identity({
        slot_melee = {
            item_data = {
                name = "es_dual_wield_hammer_sword",
                cwv_key = "cwv_es_sword_and_mace",
            },
            skin = exact_skin,
        },
    })
    local payload = payloads[1]
    if #payloads ~= 1 or payload.item_key ~= "cwv_es_sword_and_mace"
			or payload.base_item_key ~= "es_dual_wield_hammer_sword"
            or payload.skin_key ~= exact_skin then
		return "Sword+Mace transition payload lost exact variant/base/generated-skin identity"
    end

    local changed, accepted = accept_identity("rt416-peer",
        _om.appearance_lifecycle_policy.SCHEMA, payload)
    local descriptor = resolve_identity("rt416-peer", "slot_melee",
        "es_dual_wield_hammer_sword")
    if changed ~= true or not accepted or not descriptor
            or descriptor.skin ~= exact_skin
            or descriptor.right_hand_unit ~= skin.right_hand_unit
            or descriptor.left_hand_unit ~= skin.left_hand_unit then
        return "Sword+Mace transition semantic identity did not reconstruct both hands"
    end

    -- Reproduce the vanilla transition send. Even a parity provider that claims
    -- success (or crashes) must be irrelevant: the wire sees n/a and the live
    -- owner slot is restored immediately after the sender returns.
    local real_pp = mod._cwv_peer_parity
    mod._cwv_peer_parity = { all_peers_have = function()
        error("transition appearance path consulted parity")
    end }
    local slot = { skin = exact_skin }
    local at_send
    local ok, err = pcall(null_skins, { slot }, function() at_send = slot.skin end,
        "rt416_transition")
    mod._cwv_peer_parity = real_pp
    if not ok then return "transition fallback raised/consulted parity: " .. tostring(err) end
    if at_send ~= nil or slot.skin ~= exact_skin then
		return "transition fallback leaked the CWV skin or failed to restore the live slot"
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

_rt_register("issue932_primary_slot_musket_ammo_pool_contract", function()
	local controller = _om.musket_ammo_pool
	if type(controller) ~= "table" or type(controller.contract_error) ~= "function" then
		return "owner-scoped Old Musket ammo controller is not installed"
	end
	return controller:contract_error()
end)

_rt_register("issue1107_melee_slot_reload_drains_reserve", function()
	-- Synthetic controller run: a melee-slot member (nil owner_buff_extension,
	-- matching generic_ammo_user_extension.lua:83-89) whose chamber grew across
	-- vanilla update must charge the pool by the refill; buff-exempt reloads
	-- and vanilla-charged ranged reloads must not double-drain.
	local policy = _om.musket_ammo_pool_policy
	if type(policy) ~= "table" or type(policy.new) ~= "function" then
		return "musket ammo pool policy module missing"
	end
	local c = policy.new({ reserve_per_musket = 10, alive = function() return true end })
	if type(c.end_reload_drain) ~= "function" then
		return "end_reload_drain surface missing from controller"
	end
	local owner = {}
	local ext = { unit = {}, owner_unit = owner,
		_current_ammo = 0, _shots_fired = 0, _ammo_per_clip = 1, _available_ammo = 10 }
	if not c:register(ext, owner, "slot_melee") then
		return "synthetic melee ext failed to register"
	end
	local before = c:begin_mutation(ext)
	ext._current_ammo = 1 -- vanilla chamber refill (:166) with no reserve charge (:168 nil gate)
	local drained = c:end_reload_drain(ext, 0, function() return false end)
	c:end_delta(ext, before)
	if drained ~= 1 or c:reserve_for(ext) ~= 9 then
		return string.format("melee reload drained %s, reserve %s (want 1 / 9)",
			tostring(drained), tostring(c:reserve_for(ext)))
	end
	before = c:begin_mutation(ext)
	ext._current_ammo = 2
	drained = c:end_reload_drain(ext, 1, function() return true end)
	c:end_delta(ext, before)
	if drained ~= 0 or c:reserve_for(ext) ~= 9 then
		return "buff-exempt reload drained the pool"
	end
	local rext = { unit = {}, owner_unit = owner,
		_current_ammo = 0, _shots_fired = 0, _available_ammo = 0, owner_buff_extension = {} }
	if not c:register(rext, owner, "slot_ranged") then
		return "synthetic ranged ext failed to register"
	end
	before = c:begin_mutation(rext)
	rext._current_ammo = 1
	rext._available_ammo = rext._available_ammo - 1 -- vanilla ranged charge (:174)
	drained = c:end_reload_drain(rext, 0, function() return false end)
	c:end_delta(rext, before)
	if drained ~= 0 then
		return "vanilla-charged ranged reload was double-drained"
	end
	if c:reserve_for(rext) ~= 8 then
		return string.format("pooled reserve %s after ranged reload (want 8)",
			tostring(c:reserve_for(rext)))
	end
end)

_rt_register("issue1108_primary_slot_musket_ammo_hud_contract", function()
	local adapter = _om.musket_ammo_hud
	if type(adapter) ~= "table" or type(adapter.contract_error) ~= "function" then
		return "Old Musket ammo HUD adapter is not installed"
	end
	local installed = adapter:contract_error()
	if installed then return installed end

	-- Execute the same engine-free selector used by both live post-sync hooks.
	-- Merely counting the hooks cannot prove that ranged-only HUD selection was
	-- replaced, so the positive fixture and every fail-closed edge live here.
	local policy = _om.musket_ammo_hud_policy
	if type(policy) ~= "table" or type(policy.select) ~= "function" then
		return "Old Musket ammo HUD selector surface is missing"
	end
	local owner, ammo_unit = {}, {}
	local extension = { unit = ammo_unit }
	local item_data = { name = "es_handgun", backend_id = "cwv_es_musket_custom_001" }
	local slot_data = { item_data = item_data, right_unit_1p = ammo_unit }
	local equipment = { wielded_slot = "slot_melee", slots = { slot_melee = slot_data } }
	local controller = {
		extension_for = function(_, queried_owner, slot_name)
			if queried_owner == owner and slot_name == "slot_melee" then
				return extension
			end
		end,
	}
	local template = function() return { ammo_data = { ammo_hand = "right" } } end
	local item, slot, selected = policy.select(controller, owner, equipment, template)
	if item ~= item_data or slot ~= slot_data or selected ~= extension then
		return "HUD selector did not pick the wielded primary-slot Musket extension"
	end

	equipment.wielded_slot = "slot_ranged"
	if policy.select(controller, owner, equipment, template) ~= nil then
		return "HUD selector overrode the ranged slot's native path"
	end
	equipment.wielded_slot = "slot_melee"
	slot_data.right_unit_1p = {}
	if policy.select(controller, owner, equipment, template) ~= nil then
		return "HUD selector accepted a mismatched ammo-hand unit"
	end
	slot_data.right_unit_1p = ammo_unit
	if policy.select(controller, owner, equipment, function() return {} end) ~= nil then
		return "HUD selector accepted a template without ammunition"
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
    local plan_identity = _om._cwv_identity_payloads
    local accept_identity = _om._cwv_accept_identity
    local resolve_identity = _om._cwv_identity_descriptor_for_peer
    if type(plan_identity) ~= "function" or type(accept_identity) ~= "function"
            or type(resolve_identity) ~= "function" then
        return "semantic identity helpers missing"
    end
    if not (mod._cwv_skin_wire_surfaces
            and mod._cwv_skin_wire_surfaces.vanilla_skin_replay_retired) then
		return "unsafe numeric skin replay is not retired"
    end
    local payloads = plan_identity({
        slot_melee = {
            item_data = { name = "es_handgun", cwv_key = "cwv_es_musket_old" },
            skin = "cwv_es_musket_old_skin",
        },
        slot_ranged = {
            item_data = { name = "es_handgun", cwv_key = "cwv_es_musket_old" },
            skin = "cwv_es_musket_old_skin",
        },
    })
    local by_slot = {}
    for _, payload in ipairs(payloads) do by_slot[payload.slot] = payload end
    for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
        local payload = by_slot[slot_name]
        if not payload or payload.item_key ~= "cwv_es_musket_old"
                or payload.base_item_key ~= "es_handgun"
				or payload.skin_key ~= "cwv_es_musket_old_skin" then
			return slot_name .. " lost Old Musket variant/base/skin semantic identity"
        end
        local peer_id = "rt474-peer"
        local changed, accepted = accept_identity(peer_id,
            _om.appearance_lifecycle_policy.SCHEMA, payload)
        local descriptor = resolve_identity(peer_id, slot_name, "es_handgun")
        if changed ~= true or not accepted or not descriptor
                or descriptor.skin ~= "cwv_es_musket_old_skin" then
            return slot_name .. " failed to reconstruct Old Musket semantic identity"
        end
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
	-- #474 (2026-07-18): stance + shot report additionally ride the delivering
	-- cwv_item_identity channel; the dedicated mode channel never delivered in
	-- the paired live logs. These are the identity-channel consumers.
	if type(_om._old_musket_accept_mode) ~= "function"
			or type(_om._old_musket_play_remote_fire) ~= "function"
			or type(_om._old_musket_mode_for_local_slot) ~= "function" then
		return "identity-channel stance/fire consumers are missing"
	end
	if _om._old_musket_play_remote_fire("rt474_no_such_peer", "not_the_rifle_event", "rt") ~= false then
		return "remote fire acceptor must reject a non-rifle event"
	end
	-- #1211: the shot report killed a client with a native access violation
	-- because it fed an Application-owned world handle -- one WorldManager never
	-- Wwise-registered -- into WwiseUtils. Prove the replacement resolver finds a
	-- REGISTERED wwise world right here in the keep, which is exactly where the
	-- client died, and that the acceptor still fails closed on an unknown peer.
	if type(_om._old_musket_wwise_world) ~= "function" then
		return "remote fire audio has no registered-wwise-world resolver"
	end
	local wwise_world, level_world = _om._old_musket_wwise_world()
	if not level_world then
		return "remote fire audio cannot resolve the level world"
	end
	if not wwise_world then
		return "remote fire audio resolved a world Wwise never registered"
	end
	if _om._old_musket_play_remote_fire("rt1211_no_such_peer",
			"player_combat_weapon_rifle_fire", "rt") ~= false then
		return "remote fire acceptor must fail closed on an unresolvable peer"
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
		"_apply_old_musket_textures",        -- resource-gated UV painter
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
	if type(_om.old_musket_appearance) ~= "table"
			or type(_om.old_musket_appearance.resolve) ~= "function"
			or type(_om.old_musket_appearance.reconcile) ~= "function"
			or type(_om.old_musket_appearance.disconnect) ~= "function" then
		return "Old Musket immutable descriptor/reconciler pilot is incomplete"
	end
	if not _om.old_musket_preview_pose
			or type(_om.old_musket_preview_pose.take_when_stable) ~= "function" then
		return "Old Musket final preview stability owner is missing"
	end
	-- Cross-mod bridge entrypoint the Cosmetics/CIM-Athanor previewers consume.
	if type(mod._cwv_resolve_preview_descriptor) ~= "function" then
		return "preview-bridge entrypoint mod._cwv_resolve_preview_descriptor missing"
	end
	local policy = _om.old_musket_preview
	if type(policy) ~= "table" or type(policy.resource_mode) ~= "function" then
		return "shared Old Musket resource-mode policy missing"
	end
	local package_bridge = _om._old_musket_package_bridge
	if type(package_bridge) ~= "table"
			or type(package_bridge.alias) ~= "function"
			or type(package_bridge.load) ~= "function"
			or type(package_bridge.unload) ~= "function"
			or type(package_bridge.has_loaded) ~= "function" then
		return "Old Musket material-owner package bridge missing"
	end
	if package_bridge.alias(policy.UNIT) ~= policy.NETWORK_PACKAGE_ALIAS_1P
			or package_bridge.alias(policy.UNIT_3P) ~= policy.NETWORK_PACKAGE_ALIAS_3P
			or package_bridge.alias(policy.NETWORK_PACKAGE_ALIAS_3P) ~= nil then
		return "Old Musket package bridge does not preserve the exact 1P/3P donor boundary"
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
		if type(d) ~= "table" or type(d.right_hand_unit) ~= "table"
				or type(d.right_hand_unit.unit) ~= "string"
				or (d.mode ~= "ranged" and d.mode ~= "melee")
				or type(d.transform_3p) ~= "table"
				or type(d.transform_3p.position) ~= "table"
				or type(d.transform_3p.scale) ~= "table" then
			return "preview descriptor incomplete for a positive Old Musket identity form"
		end
	end
end)

_rt_register("issue1155_old_musket_descriptor_reconciler", function()
	local pilot, descriptor_lib = _om.old_musket_appearance, _om.appearance_descriptor
	if type(pilot) ~= "table" or type(descriptor_lib) ~= "table" then
		return "Phase-3 Old Musket pilot modules are unavailable"
	end
	local descriptor, errors = pilot.resolve({
		backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
	}, "ranged", "inventory_preview")
	if not descriptor then return "descriptor rejected: " .. tostring(errors and errors[1]) end
	if type(descriptor.transform_1p) ~= "table"
			or type(descriptor.transform_3p) ~= "table"
			or type(descriptor.transform_3p.rotation) ~= "table"
			or #descriptor.transform_3p.rotation ~= 4 then
		return "descriptor lost a canonical pose channel"
	end
	local preview_surface = _om._cwv_loot_preview_surface
	if type(preview_surface) ~= "function"
			or preview_surface({ _cwv_cim_preview = true }) ~= "cim_preview"
			or preview_surface({}) ~= "illusion_browser"
			or preview_surface({ _cwv_cim_preview = false }) ~= "illusion_browser"
			or preview_surface({ _cwv_cim_preview = 1 }) ~= "illusion_browser" then
		return "Athanor preview marker does not preserve the generic browser boundary"
	end
	if not (pilot.implemented_cells.cim_preview
			and pilot.implemented_cells.cim_preview.preview_open == true) then
		return "Old Musket CIM preview-open adapter cell is not implemented"
	end
	for _, surface in ipairs(descriptor_lib.SURFACES or {}) do
		if not pilot.unit_surfaces[surface] then
			local result = pilot.reconcile({}, surface, "instance_load", {
				backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
			}, "ranged")
			if not result or result.fallback ~= true then
				return "fallback adapter missing for surface " .. tostring(surface)
			end
		end
	end
	local rejected = pilot.reconciler.reconcile(descriptor, "not_a_surface", "equip", {})
	if rejected.reason ~= "unknown-surface" then
		return "reconciler does not reject a foreign surface"
	end
	if pilot.disconnect() ~= true then return "disconnect cleanup failed" end
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
	local descriptor = _om.old_musket_appearance.resolve({
		ItemInstanceId = bid,
		key = "es_handgun",
		CustomData = { cwv_key = _om._cwv_key_for_item(bid, item) },
	}, "ranged", "illusion_browser")
	if not descriptor or descriptor.item_key ~= "cwv_es_musket_old"
			or descriptor.right_hand_unit.unit ~= _om.old_musket_preview.UNIT then
		return "canonical UUID did not reach the authored Old Musket preview descriptor"
	end
	-- payload_for now emits an explicit native record for the EMPTY melee slot
	-- (appearance fix wave 1), so the crafted payload must be selected by slot,
	-- never by array position.
	local payloads = _om._cwv_identity_payloads({
		slot_ranged = { item_data = item },
	})
	local ranged_payload
	for _, payload in ipairs(payloads) do
		if payload.slot == "slot_ranged" then ranged_payload = payload end
	end
	if not ranged_payload or ranged_payload.item_key ~= "cwv_es_musket_old" then
		return "canonical UUID did not reach the bounded husk identity channel"
	end
end)

_rt_register("cwv_inherits_base_name", function()
    -- Verify every cwv entry preserves its exact authored vanilla base identity.
    -- Per `feedback_cwv_clone_name_clobber.md` — vanilla code (e.g.
    -- world_hero_previewer.lua:674) does `item_data = ItemMasterList[item.name]`
    -- for fallback lookups. Clobbering entry.name to def.item_key made the
    -- lookup return nil and equip path crashed in BackendUtils.get_item_units.
    -- Must KEEP `entry.name == def.base_weapon`; native damage-source decoding
    -- and fallback item lookups both consume that wire-safe base key. The mod
    -- uses `entry.cwv_variant` as the discriminator instead. Nil is not an
    -- inherited identity: table.clone makes an ordinary table and a missing
    -- name would send no exact base identity at all.
    local entries, bail = _rt_iter_cwv_entries()
    if bail then return bail end
    local mismatched = {}
    for _, e in ipairs(entries) do
        local n = e.entry.name
        if type(e.def.base_weapon) ~= "string" or n ~= e.def.base_weapon then
            mismatched[#mismatched + 1] = string.format(
                "%s (name=%s base=%s)", e.key, tostring(n),
                tostring(e.def.base_weapon))
        end
    end
    if #mismatched > 0 then
        return "entry.name must equal exact base_weapon on: "
            .. table.concat(mismatched, "; ")
    end
end)

_rt_register("cwv_ammo_mirroring", function()
    -- For any variant whose BASE template has `ammo_unit`, the variant entry
    -- must mirror `ammo_unit`, `projectile_units_template`, `pickup_template_name`,
    -- `link_pickup_template_name` from the base. Per `feedback_cwv_ammo_unit_required.md` —
    -- the skin pipeline nukes these fields; without explicit mirroring the
    -- previewer/throw/pickup paths all crash on ammo-bearing variants.
    -- Skip non-ammo bases entirely (their nil ammo_unit is correct).
    --
    -- #399: `no_ammo_unit` defs are the deliberate opposite of this rule -- the
    -- variant changed visual family and must NOT wear the donor's ammo mesh, so
    -- `_build_entry` clears ammo_unit/ammo_unit_3p on purpose (entry :5416-5419)
    -- and `cwv_outrider_no_ammo_unit` locks that. Without this exclusion the two
    -- checks demand opposite things of the same Outrider entry and one of them
    -- always fails, which is why the harness could not be used to close #399.
    local entries, bail = _rt_iter_cwv_entries()
    if bail then return bail end
    local iml = rawget(_G, "ItemMasterList")
    local mismatched = {}
    local AMMO_FIELDS = { "ammo_unit", "projectile_units_template", "pickup_template_name", "link_pickup_template_name" }
    for _, e in ipairs(entries) do
        local base_key = e.def.base_weapon
        local base = base_key and rawget(iml, base_key)
        if base and base.ammo_unit and not e.def.no_ammo_unit then
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
    -- 1. Source-pattern: marker constant must be present. #1148: the constant is
    --    a file-scope local in the ENTRY file, so this relocated check reads it
    --    through the mod-table publication, never as a bare (nil) global.
    if not (mod._cwv_fix_markers
            and mod._cwv_fix_markers.iml_rawget == "cwv-itemmasterlist-rawget-auto-register-all") then
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
    -- 1. Source-pattern: marker constant must be present (#1148 mod-table read).
    if not (mod._cwv_fix_markers
            and mod._cwv_fix_markers.nl_rawget == "cwv-networklookup-rawget-hardened-3-sites") then
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
    -- 1. Source-pattern: marker constant must be present (#1148 mod-table read).
    if not (mod._cwv_fix_markers
            and mod._cwv_fix_markers.slot_extension == "cwv-slot-extension-scoped-to-cross-slot-variant-careers") then
        return "SLOT EXTENSION marker absent — was the v0.1.338 scoping fix reverted?"
    end
    if not _om._slot_extension_log_only then
        return "automatic slot-extension state is not marked log-only (issue 570 startup chat regression)"
    end
    -- 2. Compute the expected allowed-careers set from `_variant_definitions`.
    --    Walk every def, union the `careers` arrays of entries with
    --    `cross_slot = true`. As of v0.1.338 only `cwv_es_musket_old` is
    --    cross-slot, so the expected set is the four Empire careers.
    --    #1148: the collector is an entry-file local, published on `_om`.
    if type(_om._collect_cross_slot_careers) ~= "function" then
        return "cross-slot career collector not published on _om (#1148 scope break)"
    end
    local expected = _om._collect_cross_slot_careers()
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
    if type(_om.remote_audio_dispatch) ~= "table"
            or type(_om.remote_audio_dispatch.invoke) ~= "function" then
        return "cross-access pre-RPC dispatch boundary missing"
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

    -- Execute the SAME boundary as the live hook with a spy vanilla function.
    -- This fails if the resolver remains correct but the wrapper stops handing
    -- its receiver-native event to WeaponUnitExtension._play_3p_anim.
    local owner = {}
    local remote = {}
    local delegated = {}
    local function vanilla_spy(_, event_3p, event, got_owner, looping, scale)
        delegated[#delegated + 1] = {
            event_3p = event_3p, event = event, owner = got_owner,
            looping = looping, scale = scale,
        }
        return "delegated", event_3p
    end
    local function resolve(source)
        return _om._cross_access_target_event(
            "dr_dual_wield_axes", "es_mercenary", source)
    end
    local function lookup(target)
        return target == "attack_swing_heavy_right_diagonal" and 398 or nil
    end

    local status, passed = _om.remote_audio_dispatch.invoke(vanilla_spy, {},
        "attack_swing_heavy_right", "attack_one", owner, true, 1.25,
        owner, nil, resolve, lookup)
    if status ~= "delegated" or passed ~= "attack_swing_heavy_right_diagonal"
            or #delegated ~= 1 or delegated[1].owner ~= owner
            or delegated[1].event ~= "attack_one" or delegated[1].looping ~= true
            or delegated[1].scale ~= 1.25 then
        return "pre-RPC dispatch did not delegate the receiver-native event and original call context"
    end

    _om.remote_audio_dispatch.invoke(vanilla_spy, {},
        "attack_swing_heavy_right", "attack_one", remote, false, 1,
        owner, nil, resolve, lookup)
    if #delegated ~= 2 or delegated[2].event_3p ~= "attack_swing_heavy_right" then
        return "pre-RPC dispatch changed a remote/native owner event"
    end

    _om.remote_audio_dispatch.invoke(vanilla_spy, {},
        "attack_swing_heavy_right", "attack_one", owner, false, 1,
        owner, nil, resolve, function() return nil end)
    if #delegated ~= 3 or delegated[3].event_3p ~= "attack_swing_heavy_right" then
        return "pre-RPC dispatch did not fail closed when the target lookup was absent"
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

_rt_register("cwv_husk_stale_unit_and_postcondition", function()
    -- Issue 395 (stale husk override-unit drain) + issue 660 (retained-state
    -- postcondition). The drain releases a superseded per-(owner, slot, hand)
    -- override unit that vanilla teardown left alive (the no_left_hand Rapier
    -- leak floor); the postcondition reads the RETAINED transform back from the
    -- engine instead of trusting setter success. Assert both helpers + the weak
    -- ledger landed so a refactor can't silently drop them.
    if type(_om._husk_record_override_unit) ~= "function" then
        return "_om._husk_record_override_unit missing -- husk stale-unit drain lost (issue 395)"
    end
    if type(_om._husk_unit_ledger) ~= "table" then
        return "_om._husk_unit_ledger missing -- husk override-unit ledger lost (issue 395)"
    end
    if getmetatable(_om._husk_unit_ledger) == nil
            or getmetatable(_om._husk_unit_ledger).__mode ~= "k" then
        return "_om._husk_unit_ledger is not weak-keyed -- husk owners would leak across missions (issue 395)"
    end
    if type(_om._husk_postcondition_log) ~= "function" then
        return "_om._husk_postcondition_log missing -- husk retained-state proof lost (issue 660)"
    end
end)


_rt_register("issue399_outrider_husk_ammo_adapter", function()
    -- Issue 399 (Outrider Grenade Launcher on the REMOTE view): the husk showed
    -- "no animation, no model, torpedo sticking out" -- one failure, not three.
    -- Both ammo arms opened with the SAME descriptor gate the mesh re-key and the
    -- #398 clone template use, so a single negative descriptor state collapsed
    -- every concern to vanilla dr_deus_01 resolution. `cwv_no_ammo_strip_coverage`
    -- only proves the (base, career) LOOKUP is populated; it never drove the
    -- adapter, so the gate collapse was invisible to the harness. This check
    -- drives the real arms through `_husk_adapter_pre` / `_husk_adapter_post`.
    --
    -- Neighbouring husk concerns are stubbed for the drive (they queue package
    -- leases and touch spawned units); the ammo arms under test are the REAL
    -- ones, reached through the real adapter bodies.
    local pre, post = _om._husk_adapter_pre, _om._husk_adapter_post
    if type(pre) ~= "function" or type(post) ~= "function" then
        return "husk adapter halves missing -- issue 399 ammo arms are unreachable"
    end
    if type(_om._husk_ammo_nil_item_units) ~= "function"
            or type(_om._husk_strip_cwv_ammo) ~= "function" then
        return "husk ammo arms missing (_husk_ammo_nil_item_units / _husk_strip_cwv_ammo, issue 399)"
    end
    local def = _find_def("cwv_es_outrider_grenade_launcher")
    if not def then return nil end -- def removed: cwv_outrider_no_ammo_unit owns that
    local iml = rawget(_G, "ItemMasterList")
    local base = iml and rawget(iml, "dr_deus_01")
    if not (base and base.ammo_unit) then
        return "dr_deus_01 no longer carries ammo_unit -- the issue 399 fixture is stale"
    end

    -- Disjointness floor for the base+career fallback: no career that can
    -- natively wield the ammo base may sit in its strip set, or a real Bardin
    -- Trollhammer would lose its torpedo on every remote view.
    --
    -- Read against the LIVE can_wield only when nothing has expanded it. `wt` is
    -- the availability control surface and its per-(career, weapon) unlocks
    -- (weapon_tweaker_data.lua `unlock_es_*_dr_deus_01`) rewrite this list at
    -- runtime, so with wt installed the list is no longer the vanilla native set
    -- and an overlap here is a wt configuration, not a cwv defect. The vanilla
    -- sets are cited in the husk module's DESCRIPTOR-STATE POLICY block.
    local strip = _om._no_ammo_careers_by_base and _om._no_ammo_careers_by_base.dr_deus_01
    if type(strip) ~= "table" then
        return "dr_deus_01 missing from the husk ammo strip lookup (issue 399)"
    end
    local availability_mod = rawget(_G, "get_mod") and (get_mod("wt") or get_mod("wt_dev"))
    if not availability_mod then
        for _, c in ipairs(base.can_wield or {}) do
            if strip[c] then
                return string.format(
                    "career %s can natively wield dr_deus_01 and is in the strip set -- a real Trollhammer would be stripped (issue 399)",
                    tostring(c))
            end
        end
    end

    local saved_descriptor = _om._husk_identity_descriptor
    local saved_career = _om._husk_career_name
    local saved_ctx = _om._appearance_husk_wield_context
    local saved_rekey = _om._husk_rekey_units
    local saved_template = _om._husk_template_for_spawn
    local saved_transform = _om._husk_apply_cwv_transform
    local saved_probe = _om._probe_579_hand_compare

    local owner = { rt399 = true }          -- sentinel; the stubs answer for it
    local ammo_handle = { rt399_ammo = true } -- non-userdata: never reaches the engine
    local state, career_name, exact_descriptor

    local function fresh_units()
        return {
            right_hand_unit = def.right_hand_unit,
            ammo_unit       = base.ammo_unit,
            ammo_unit_3p    = base.ammo_unit_3p,
        }
    end
    local function ammo_cleared(units)
        return units.ammo_unit == nil and units.ammo_unit_3p == nil
    end

    local function drive()
        -- (1) exact Outrider descriptor, career deliberately UNRESOLVABLE:
        -- the proven identity alone must clear the ammo.
        exact_descriptor = { variant_key = "cwv_es_outrider_grenade_launcher",
            base_item_key = "dr_deus_01" }
        state, career_name = "exact", nil
        local units = fresh_units()
        pre("right", nil, units, "slot_ranged", { name = "dr_deus_01" }, owner)
        if not ammo_cleared(units) then
            return "exact Outrider descriptor did not clear item_units.ammo_unit/_3p (issue 399 pre-spawn arm)"
        end

        -- (2) native Trollhammer: real dwarf wielder, no descriptor at all.
        exact_descriptor, state, career_name = nil, "none", "dr_ironbreaker"
        units = fresh_units()
        pre("right", nil, units, "slot_ranged", { name = "dr_deus_01" }, owner)
        if ammo_cleared(units) then
            return "native dr_ironbreaker Trollhammer lost its ammo units -- #475 Invariant 1 violated (issue 399)"
        end

        -- (3) explicit-native descriptor over a strip-set career: the ONE state
        -- that must still hard-decline.
        state, career_name = "native", "es_huntsman"
        units = fresh_units()
        pre("right", nil, units, "slot_ranged", { name = "dr_deus_01" }, owner)
        if ammo_cleared(units) then
            return "explicit native descriptor did not decline the ammo strip (issue 399 / #475 Invariant 1)"
        end

        -- (4/5) the #399 fix: a negative descriptor state is NOT evidence of a
        -- native wielder, so it falls through to the career-scoped fallback.
        --
        -- #1188: that fallback is career-scoped AND native-pair discriminated. If
        -- weapon_tweaker's `unlock_es_huntsman_dr_deus_01` is enabled the pair is
        -- natively wieldable right now, so the correct answer INVERTS -- a
        -- skinless echo is then indistinguishable from a real Trollhammer and
        -- must keep its torpedo. Assert whichever answer the live can_wield
        -- makes correct rather than skipping.
        local wt_unlocked = _om._husk_pair_native_now("dr_deus_01", "es_huntsman") == true
        for _, negative in ipairs({ "unavailable", "stale_base" }) do
            state, career_name = negative, "es_huntsman"
            units = fresh_units()
            pre("right", nil, units, "slot_ranged", { name = "dr_deus_01" }, owner)
            if wt_unlocked then
                if ammo_cleared(units) then
                    return string.format(
                        "descriptor state %s stripped a wt-granted NATIVE Trollhammer's torpedo -- #475 Invariant 1 (issue 1188)",
                        negative)
                end
            elseif not ammo_cleared(units) then
                return string.format(
                    "descriptor state %s still collapsed the ammo decision -- Outrider keeps the inherited torpedo on the husk (issue 399)",
                    negative)
            end
        end

        -- (6) deferred hand-selection branch: it preserves the vanilla HAND
        -- selection, which has nothing to do with ammo.
        state, career_name = "unavailable", "es_huntsman"
        _om._appearance_husk_wield_context = {
            hand_selection_deferred = true,
            hand_selection_source = "rt399",
            owner_unit_3p = owner,
            slot_name = "slot_ranged",
        }
        units = fresh_units()
        pre("right", nil, units, "slot_ranged", { name = "dr_deus_01" }, owner)
        _om._appearance_husk_wield_context = saved_ctx
        -- Same #1188 inversion as (4/5): the deferred branch runs the ammo arm,
        -- and that arm now discriminates a wt-granted native pair.
        if wt_unlocked then
            if ammo_cleared(units) then
                return "deferred hand-selection branch stripped a wt-granted NATIVE Trollhammer's torpedo (issue 1188)"
            end
        elseif not ammo_cleared(units) then
            return "deferred hand-selection branch skipped the ammo-nil step -- torpedo survives the atomic preselection fallback (issue 399)"
        end

        -- (7) post-spawn strip signal. The entry consumes it as
        -- `if _om._husk_adapter_post(...) then v_a3p = nil end`
        -- (character_weapon_variants.lua :2679-2683), so a nil/false return
        -- leaves the husk equipment tracking the torpedo it just hid.
        exact_descriptor = { variant_key = "cwv_es_outrider_grenade_launcher",
            base_item_key = "dr_deus_01" }
        state, career_name = "exact", nil
        local stripped = post("right", { name = "dr_deus_01" }, fresh_units(),
            "slot_ranged", owner, nil, ammo_handle)
        if stripped ~= true then
            return string.format(
                "post-spawn arm returned %s for the Outrider -- the entry only nils its captured ammo return on an exact true (issue 399)",
                tostring(stripped))
        end
        exact_descriptor, state, career_name = nil, "none", "dr_ironbreaker"
        if post("right", { name = "dr_deus_01" }, fresh_units(),
                "slot_ranged", owner, nil, ammo_handle) then
            return "post-spawn arm signalled a strip for a native dr_ironbreaker Trollhammer (issue 399)"
        end
    end

    _om._husk_identity_descriptor = function() return exact_descriptor, state end
    _om._husk_career_name = function() return career_name end
    _om._husk_rekey_units = function() return false end
    _om._husk_template_for_spawn = function() return nil end
    _om._husk_apply_cwv_transform = function() return nil end
    _om._probe_579_hand_compare = function() return nil end
    local ok, result = pcall(drive)
    _om._husk_identity_descriptor = saved_descriptor
    _om._husk_career_name = saved_career
    _om._appearance_husk_wield_context = saved_ctx
    _om._husk_rekey_units = saved_rekey
    _om._husk_template_for_spawn = saved_template
    _om._husk_apply_cwv_transform = saved_transform
    _om._probe_579_hand_compare = saved_probe
    if not ok then
        return "husk ammo adapter drive errored: " .. tostring(result)
    end
    return result
end)

_rt_register("issue1204_deus_identity_uses_committed_parity", function()
	local allowed = _om.deus_exact_identity_allowed
	if type(allowed) ~= "function" then
		return "committed Deus identity parity gate is unavailable"
	end
	local function probe(state, classifier)
		return allowed({
			applied_state = function() return state end,
			all_peers_have = function() return classifier end,
		})
	end
	if not probe("enabled", false) then
		return "committed enabled state did not permit exact Deus identities"
	end
	if probe("disabled", true) or probe("pending", true) or probe(nil, true) then
		return "pre-commit peer classifier bypassed the committed Deus identity state"
	end
	if allowed({ applied_state = function() error("probe") end }) then
		return "throwing committed-state accessor did not fail closed"
	end
end)

end
