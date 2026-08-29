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

-- ============================================================
-- /cwv_regression_test checks (scaffold near top of file).
-- Each check returns nil for PASS or a string for FAIL.
-- Bail with a clear "not loaded (run in-keep)" message when globals
-- aren't ready — keep-load timing means ItemMasterList / NetworkLookup
-- may not be populated when the user runs the command pre-keep.
-- ============================================================

-- Build and validate the child before the first real registration. The
-- restricted dependencies omit `rt_register`, preventing partial mutation.
local _runtime_identity_dependencies = {
    mod = mod, om = _om, variant_definitions = _variant_definitions,
    find_def = _find_def, build_entry = _build_entry,
    auto_register_all = _auto_register_all,
    cross_access_action_remap = _cross_access_action_remap,
    wield_hook_registration_count = _cwv_wield_hook_registration_count,
}
local _load_regression_owner = ctx.regression_owner_loader
if type(_load_regression_owner) ~= "function" then
    error("CWV regression owner loader is unavailable")
end
local _runtime_identity_checks, _rt_iter_cwv_entries = _load_regression_owner({
    name = "_cwv_regression_runtime_identity",
    constructor = ctx.runtime_identity_owner,
    dependencies = _runtime_identity_dependencies,
    expected_count = 22,
    export_type = "function",
})

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
		es_2h_sword = { "greatsword", "kerillian", "bretonnian", "half_swording" },
		wh_2h_sword = { "greatsword", "kerillian", "bretonnian", "half_swording" },
		es_bastard_sword = { "bretonnian", "greatsword", "kerillian", "half_swording" },
		cwv_es_longsword = { "longsword", "bretonnian", "kerillian", "greatsword", "half_swording" },
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
	if runtime:moveset_indicator("es_bastard_sword", "greatsword") ~= "Moveset 2 / 4" then
		return "Bretonnian Longsword moveset indicator drifted"
	end
	if runtime:moveset_indicator("es_2h_sword", "bretonnian") ~= "Moveset 3 / 4" then
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

_rt_register("issue916_half_swording_combat_style_contract", function()
	-- #916: Half-Swording keeps the selected sword model rendering while the
	-- action graph comes from maul_template (the burn-scrubbed Sienna
	-- Morningstar clone). Pin family membership/order, maul_template selection,
	-- the burn scrub staying clone-local, the authored brw_hammer resource,
	-- presentation isolation, exact-instance persistence, and the wire edge.
	local policy = _om.combat_style_policy
	local runtime = _om.combat_styles
	if type(policy) ~= "table" or type(runtime) ~= "table" then
		return "Combat Style policy/runtime is not installed"
	end
	local weapons = rawget(_G, "Weapons")
	if type(weapons) ~= "table" then return "Weapons not loaded yet (run in-keep)" end
	local donor = rawget(weapons, "one_handed_hammer_wizard_template_1")
	local maul = rawget(weapons, "maul_template")
	if type(donor) ~= "table" then return nil end   -- Morningstar donor absent; nothing to protect
	if type(maul) ~= "table" then
		return "#916 maul_template is not registered while its donor exists"
	end
	local HALF_SWORDING_RESOURCE =
		"units/beings/player/first_person_base/state_machines/melee/brw_hammer"
	for _, item_key in ipairs({ "es_2h_sword", "wh_2h_sword", "es_bastard_sword",
			"cwv_es_longsword", "cwv_es_longsword_blackguard" }) do
		local _, _, _, member = policy.style(item_key)
		if type(member) ~= "table" or member.order[#member.order] ~= "half_swording" then
			return "#916 Half-Swording is not the appended ordinal for " .. item_key
		end
		if member.default == "half_swording" then
			return "#916 Half-Swording must never displace a member default: " .. item_key
		end
		local package = policy.package(item_key, "half_swording")
		if type(package) ~= "table" or package.template ~= "maul_template" then
			return "#916 Half-Swording package does not select maul_template for " .. item_key
		end
		if package.resource ~= HALF_SWORDING_RESOURCE then
			return "#916 Half-Swording resource is not the authored brw_hammer state machine"
		end
		if package.presentation ~= nil or package.remap_key ~= nil
				or package.required_dlc ~= nil then
			return "#916 Half-Swording leaked a presentation/remap/DLC gate for " .. item_key
		end
	end
	-- The declared style resource must be the 1P graph the clone actually runs.
	if maul.state_machine ~= HALF_SWORDING_RESOURCE then
		return "#916 maul_template no longer runs the declared brw_hammer state machine"
	end
	local function find_profile(template, profile)
		for _, action_group in pairs(template.actions or {}) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table"
							and sub_action.damage_profile == profile then
						return sub_action
					end
				end
			end
		end
		return nil
	end
	-- Burn scrub is clone-local: no burn profile reachable from a sword, while
	-- the untouched donor still carries it (proves no donor mutation).
	if find_profile(maul, "medium_blunt_smiter_heavy") then
		return "#916 the Maul burn scrub regressed: burn profile reachable from a sword"
	end
	if not find_profile(donor, "medium_blunt_smiter_heavy") then
		return "#916 burn-scrub fixture stale: the donor lost its burn profile"
	end
	-- Presentation isolation: 3P body events stay inside the proven greathammer
	-- vocabulary via anim_event_3p; spot-check the canonical heavy remap row.
	local function find_event(template, event)
		for _, action_group in pairs(template.actions or {}) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" and sub_action.anim_event == event then
						return sub_action
					end
				end
			end
		end
		return nil
	end
	local heavy = find_event(maul, "attack_swing_heavy_down")
	if not heavy or heavy.anim_event_3p ~= "attack_swing_heavy" then
		return "#916 maul_template 3P heavy remap drifted from the greathammer vocabulary"
	end
	-- Exact-instance persistence: commits for a greatsword identity, fails
	-- closed outside the family.
	local store = policy.normalize_store(nil)
	if policy.set(store, "issue916_identity", "es_2h_sword", "half_swording") ~= true
			or store.items.issue916_identity ~= "half_swording" then
		return "#916 Half-Swording does not persist per exact instance"
	end
	if select(1, policy.set(store, "issue916_leak", "es_2h_hammer", "half_swording")) ~= false then
		return "#916 Half-Swording leaked outside the greatsword family"
	end
	-- Peer synchronization: the bounded wire accepts the new edge and the
	-- identity rider stays under the shared cap.
	if policy.valid_wire(policy.SCHEMA, "state", "slot_melee", "greatsword", "half_swording") ~= true then
		return "#916 style wire rejects the Half-Swording edge"
	end
	if #("greatsword:half_swording") > policy.STYLE_RIDER_MAX then
		return "#916 Half-Swording rider exceeds STYLE_RIDER_MAX"
	end
	if runtime:moveset_indicator("es_2h_sword", "half_swording") ~= "Moveset 4 / 4" then
		return "#916 Half-Swording moveset ordinal drifted"
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

	-- Prove the state-ownership half of the contract, not only selection. A
	-- GamePad native sync may return early from its equipment cache while the
	-- post-hook still runs, so the adapter itself must replace its Musket-owned
	-- presentation with the current native ranged state before releasing.
	local ranged_item = { name = "es_crossbow", backend_id = "native-ranged" }
	local ranged_slot = { item_data = ranged_item, right_unit_1p = {} }
	equipment.slots.slot_ranged = ranged_slot
	equipment.wielded_slot = "slot_melee"
	equipment.wielded = item_data
	local inventory = { equipment = function() return equipment end }
	local calls = {}
	local probe = policy.new(controller, {
		get_item_template = template,
		get_inventory = function(queried_owner)
			if queried_owner == owner then return inventory end
		end,
		is_alive = function(queried_owner) return queried_owner == owner end,
	})
	local ui = {
		player = { player_unit = owner },
		_update_ammo_count = function(_, probed_item)
			calls[#calls + 1] = { kind = "update", item = probed_item }
		end,
		_set_ammo_text_focus = function(_, focused)
			calls[#calls + 1] = { kind = "focus", focused = focused }
		end,
	}
	if probe:refresh(ui) ~= true or not probe:is_active(ui) then
		return "HUD restoration probe did not engage the primary-slot Musket"
	end
	equipment.wielded_slot = "slot_ranged"
	equipment.wielded = ranged_item
	if probe:refresh(ui) ~= false then
		return "HUD restoration probe remained engaged after a ranged-slot switch"
	end
	local restored_item = calls[3]
	local restored_focus = calls[4]
	if not restored_item or restored_item.kind ~= "update"
			or restored_item.item ~= ranged_item then
		return "HUD restoration probe did not restore the native ranged item"
	end
	if not restored_focus or restored_focus.kind ~= "focus"
			or restored_focus.focused ~= true then
		return "HUD restoration probe did not restore native ranged focus"
	end
	if probe:is_active(ui) then
		return "HUD restoration probe released before clearing adapter ownership"
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
		"_apply_old_musket_appearance",      -- resource-gated authored material
		"_old_musket_attachment_profile",     -- exact parent-frame selector
		"_old_musket_transform_profile_components", -- profile-keyed pose source
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
			or type(_om.old_musket_appearance.live_status) ~= "function"
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
		return "Old Musket package-lifetime bridge missing"
	end
	if package_bridge.alias(policy.UNIT) ~= policy.NETWORK_PACKAGE_ALIAS_1P
			or package_bridge.alias(policy.UNIT_3P) ~= policy.NETWORK_PACKAGE_ALIAS_3P
			or package_bridge.alias(policy.NETWORK_PACKAGE_ALIAS_3P) ~= nil then
		return "Old Musket package bridge does not preserve the exact 1P/3P lifetime aliases"
	end
	-- All three positive-identity forms a surface can hold (item key, skin key,
	-- backend id) must resolve to the SAME custom unit plus a declared display
	-- attachment profile. A surface that resolves any of
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
				or d.attachment_profile ~= "display_3p_rifle"
				or type(d.transform_profiles) ~= "table"
				or type(d.transform_profiles.display_3p_rifle) ~= "table"
				or type(d.transform_profiles.display_3p_rifle.position) ~= "table"
				or type(d.transform_profiles.display_3p_rifle.scale) ~= "table" then
			return "preview descriptor incomplete for a positive Old Musket identity form"
		end
	end
end)

for index = 1, 22 do
    local check = _runtime_identity_checks[index]
    _rt_register(check.name, check.fn, check.opts)
end

end
