-- _cwv_regression_runtime_identity.lua -- low-level item/husk identity checks.
--
-- This owner collects the contiguous tail formerly embedded in
-- _cwv_regression_identity.lua. Collection is deliberately side-effect-free:
-- the parent validates the complete bounded row set before its first real
-- _rt_register call, then appends these rows at their original tail position.
-- Check bodies, names, messages, options, and runtime order remain unchanged.
return function(deps)
if type(deps) ~= "table" then
    error("CWV runtime-identity regression dependencies are missing")
end
for _, required in ipairs({
    { "mod", "table" },
    { "om", "table" },
    { "variant_definitions", "table" },
    { "find_def", "function" },
    { "build_entry", "function" },
    { "auto_register_all", "function" },
    { "cross_access_action_remap", "table" },
    { "wield_hook_registration_count", "number" },
}) do
    if type(deps[required[1]]) ~= required[2] then
        error("CWV runtime-identity regression dependency is invalid: " .. required[1])
    end
end
local mod = deps.mod
local _om = deps.om
local _variant_definitions = deps.variant_definitions
local _find_def = deps.find_def
local _build_entry = deps.build_entry
local _auto_register_all = deps.auto_register_all
local _cross_access_action_remap = deps.cross_access_action_remap
local _cwv_wield_hook_registration_count = deps.wield_hook_registration_count
local runtime = { checks = {} }
runtime.register = function(name, fn, opts)
    runtime.checks[#runtime.checks + 1] = { name = name, fn = fn, opts = opts }
end
local _rt_register = runtime.register

-- Canonical iterator shared by the retained first check and this owner's moved
-- tail. Returning it avoids both a duplicated helper and a global dependency.
runtime.iter_cwv_entries = function()
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
local _rt_iter_cwv_entries = runtime.iter_cwv_entries
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
	local descriptor = _om._old_musket_preview_descriptor({
		ItemInstanceId = bid,
		key = "es_handgun",
		CustomData = { cwv_key = _om._cwv_key_for_item(bid, item) },
	})
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


return runtime.checks, _rt_iter_cwv_entries
end
