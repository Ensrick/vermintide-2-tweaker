-- _cwv_item_registration_owner.lua
-- CWV item-registration owner (#1159).
--
-- Owns the whole path from a variant DEFINITION row to a live, network-safe
-- backend item:
--   * the #482 identity ladder - `_registered_keys`, `_registered_cwv_key`,
--     `_remember_cwv_identity`, the positively-validated bid->key cache and its
--     16-shot legacy diagnostic - plus the shared `_om._cwv_key_for_item`
--     resolver every bid-keyed consumer in the mod calls;
--   * `_build_entry`, the single ItemMasterList clone constructor: the
--     `cwv_variant` cross-mod marker, the #482 `cwv_key` self-stamp, per-hand
--     unit / icon / can_wield / template overrides, the #279 ammo-unit clear,
--     the item_type -> skin_combination_table map, the traits+properties JSON
--     encode and the #592 definition-vs-instance `mod_data` split;
--   * `_auto_register_all`, the once-per-session deferred pass on
--     StateInGameRunning.on_enter: build, ItemMasterList mirror, #661 career
--     action integration, the #567 WeaponSkins reverse-index invalidate and
--     rebuild, the inline NetworkLookup.item_names append, #592 Blacksmith seed
--     registration and the legacy auto-grant purge;
--   * `_om.install_deus_identities` (#273) and the DeusMechanism._setup_run
--     last-chance boundary that re-runs it before Chaos Wastes reads
--     DeusStartingWeaponTypeMapping.
-- Extracted verbatim from the entry file; behavior is unchanged.
--
-- Registers exactly two hooks, each the mod's sole registration on its
-- (Class, method) pair: StateInGameRunning.on_enter (hook_safe) and
-- DeusMechanism._setup_run. The inline bidirectional NetworkLookup.item_names
-- register moved BYTE-IDENTICAL and is deliberately NOT folded onto the shared
-- lookup-registration helper: that fold is a behavior-adjacent #428 change and
-- rides its own slice, so the helper is not referenced anywhere in this file
-- (an offline gate asserts its absence).
--
-- Exports on ctx.om, read back by the entry's two context tables (commands
-- lifecycle + regression): `_om.item_registration.registered_keys`,
-- `.build_entry`, `.auto_register_all`. Publishing them on _om instead of
-- re-declaring entry file-scope locals also gives the top-level chunk three
-- slots back against the Lua 5.1 200-local ceiling (#284). Also assigns
-- `_om._cwv_key_for_item` and `_om.install_deus_identities`, and publishes
-- `mod._cwv567_skin_keys` / `mod._cwv567_validate_skin_association`.
--
-- Load-time deps: nothing beyond the ctx table. Every moved block is a
-- definition, an assignment or a hook registration; none of them reads game
-- state at load. `_variant_definitions`, `_custom_skin_keys`,
-- `_career_weapon_actions`, `_cwv_career_weapon_actions` and
-- `_career_action_owner` are each bound exactly once in the entry and never
-- rebound, so the captured references cannot go stale.
--
-- ORDER: the owner loads at the point the FIRST moved block ran (the
-- item-creation helper), which is what the entry's
-- `mod._cwv_resolve_item_key = _om._cwv_key_for_item` handle below requires.
-- The auto-registration half therefore evaluates roughly 500 lines earlier than
-- it did inline. That is unobservable: its only load-time effects are the two
-- sole-owner hook registrations and a set of table/function assignments, and
-- the code that used to sit between the two halves (the give command, the
-- `_om._resident_override_3p` guard and the #1158 exact-appearance spawn
-- descriptors) is itself definition-only.
--
-- BOUNDARY: the give command (`_give_variant`, `_om._give_refuses_skin_only`)
-- and the shared preview / illusion-browser mesh-swap descriptors stay in the
-- entry. The first is command surface owned by `_cwv_commands_lifecycle`, the
-- second is the #1158 exact-appearance channel. `_find_def` also stays: the
-- exact-appearance descriptor and `_cwv_husk_path` both reach it.
--
-- Named (not anonymous) so the offline forward-reference lint keeps treating
-- the moved block as file-scope code: an anonymous `function(` wrapper makes
-- every construct-then-call pair below read as a closure capturing its own
-- body. See the same note in _cwv_musket_runtime.lua.
local function install(mod, ctx)
local _om = ctx.om
local _dbg = ctx.dbg
local _dbg_alert = ctx.dbg_alert
local _variant_definitions = ctx.variant_definitions
local _custom_skin_keys = ctx.custom_skin_keys
local _career_weapon_actions = ctx.career_weapon_actions
local _cwv_career_weapon_actions = ctx.cwv_career_weapon_actions
local _career_action_owner = ctx.career_action_owner

-- ============================================================
-- Item creation helper (shared by give command)
-- ============================================================

local _registered_keys = {}

-- #482 legacy-instance compatibility. CIM persists the exact authored
-- `item_key`, but crafts made before CWV stamped `entry.cwv_key` can re-enter
-- the backend as a UUID item whose backend object still has `item.key = cwv_*`
-- while `item.data.cwv_key` is absent. Keep validation definition-backed:
-- never infer a variant from the inherited vanilla `name` or item_type.
local function _registered_cwv_key(candidate)
	if type(candidate) ~= "string" or not _registered_keys[candidate] then return nil end
	return candidate
end

-- A preview transition can temporarily make BackendInterfaceItem unavailable
-- after another surface already proved the UUID's identity. Cache only
-- positively validated identities; UUID/string keys are bounded by the live
-- inventory and no per-frame network traffic is introduced.
local _cwv_identity_by_backend_id = {}
local _cwv_legacy_identity_diag = {}
local _cwv_legacy_identity_diag_count = 0

local function _remember_cwv_identity(backend_id, key, evidence)
	key = _registered_cwv_key(key)
	if not key then return nil end
	if type(backend_id) == "string" and backend_id ~= "" then
		_cwv_identity_by_backend_id[backend_id] = key
		if evidence and not _cwv_legacy_identity_diag[backend_id]
				and _cwv_legacy_identity_diag_count < 16 then
			_cwv_legacy_identity_diag[backend_id] = true
			_cwv_legacy_identity_diag_count = _cwv_legacy_identity_diag_count + 1
			pcall(printf,
				"[cwv:482] legacy identity recovered bid=%s key=%s evidence=%s count=%d/16",
				tostring(backend_id), tostring(key), tostring(evidence),
				_cwv_legacy_identity_diag_count)
		end
	end
	return key
end

-- #482: resolve the variant item_key for ANY backend instance of a cwv item.
-- Single resolution ladder shared by every bid-keyed resolver so they cannot
-- drift on what counts as "a cwv instance":
--   1. backend_id pattern `cwv_<key>_NNN` -- CWV's own _001/_002 instances and
--      cim standard-forge crafts (issue 390). Cheap, no backend round-trip.
--   2. exact CIM/CWV stamps -- direct, nested-data, mod-data, or CustomData
--      `cim_acquisition_key` / `cwv_key`. Covers instances whose backend_id is
--      NOT cwv-shaped: CIM's Athanor mints Application.guid() UUIDs, which rung
--      1 can never match (the #482/#484 crafted-CWV identity loss).
--   3. backend items lookup by bid -> item.data.cwv_key -- for callers that
--      only carry the bid (the previewer's _item_info_by_slot holds just
--      {name, backend_id, skin_name, ...}, world_hero_previewer.lua:776).
--      pcall-guarded: interface readiness varies by menu state. The husk path
--      is unaffected (bid nil there, memory reference_vt2_husk_resolves_base_item_data).
-- Hung on _om: the top-level chunk sits at the Lua 5.1 200-local ceiling (#284).
_om._cwv_key_for_item = function(backend_id, item_data)
	if type(backend_id) == "string" then
		local key = backend_id:match("^(cwv_.-)_%d%d%d$")
		if key then return _remember_cwv_identity(backend_id, key) or key end
	end
	if item_data then
		local data = type(item_data.data) == "table" and item_data.data or nil
		local custom = type(item_data.CustomData) == "table" and item_data.CustomData
			or (data and type(data.CustomData) == "table" and data.CustomData)
		local mod_data = type(item_data.mod_data) == "table" and item_data.mod_data
			or (data and type(data.mod_data) == "table" and data.mod_data)
		local stamped = item_data.cim_acquisition_key
			or (data and data.cim_acquisition_key)
			or (custom and custom.cim_acquisition_key)
			or item_data.cwv_key
			or (data and data.cwv_key)
			or (mod_data and mod_data.cwv_key)
			or (custom and custom.cwv_key)
		if type(stamped) == "string" then
			local remembered = _remember_cwv_identity(backend_id, stamped, "canonical_stamp")
			if remembered then return remembered end
		end
	end
	if item_data then
		local exact = _registered_cwv_key(item_data.key)
			or _registered_cwv_key(item_data.ItemId)
			or (item_data.data and (_registered_cwv_key(item_data.data.key)
				or _registered_cwv_key(item_data.data.ItemId)))
		if exact then
			return _remember_cwv_identity(backend_id, exact, "item_data_exact_key")
		end
	end
	if type(backend_id) == "string" and backend_id ~= "" then
		local ok, item = pcall(function()
			local backend = Managers and Managers.backend
			local iface = backend and backend:get_interface("items")
			return iface and iface:get_item_from_id(backend_id)
		end)
		if ok and item then
			local data = item.data
			local custom = type(item.CustomData) == "table" and item.CustomData
				or (data and type(data.CustomData) == "table" and data.CustomData)
			local mod_data = type(item.mod_data) == "table" and item.mod_data
				or (data and type(data.mod_data) == "table" and data.mod_data)
			local stamped = item.cim_acquisition_key
				or (data and data.cim_acquisition_key)
				or (custom and custom.cim_acquisition_key)
				or item.cwv_key or (data and data.cwv_key)
				or (mod_data and mod_data.cwv_key)
				or (custom and custom.cwv_key)
			if type(stamped) == "string" then
				local remembered = _remember_cwv_identity(backend_id, stamped, "backend_canonical_stamp")
				if remembered then return remembered end
			end
			local exact = _registered_cwv_key(item.key)
				or _registered_cwv_key(item.ItemId)
				or (data and (_registered_cwv_key(data.key)
					or _registered_cwv_key(data.ItemId)))
			if exact then
				return _remember_cwv_identity(backend_id, exact, "backend_exact_key")
			end
		end
		return _cwv_identity_by_backend_id[backend_id]
	end
	return nil
end

local function _build_entry(def, backend_id)
	-- v0.1.345-dev: per-call _dbg trace. _build_entry is sparse (boot-time only,
	-- ~30 variants/session), so always-on.
	_dbg("[cwv:build_entry] event=enter key=%s base=%s backend_id=%s",
		tostring(def and def.item_key), tostring(def and def.base_weapon), tostring(backend_id))
	-- rawget: every variant declares a base_weapon key that's expected to exist, but the
	-- crashify metamethod on a missing key would surface as an opaque crash here. Failing
	-- soft with a warning lets the mod skip variants whose base weapon isn't installed.
	local base = rawget(ItemMasterList, def.base_weapon)
	if not base then
		_dbg_alert("[cwv:build_entry] event=fail_base_missing key=%s base=%s",
			tostring(def and def.item_key), tostring(def and def.base_weapon))
		mod:warning("Base weapon '%s' not found in ItemMasterList", def.base_weapon)
		return nil
	end

	local entry = table.clone(base, true)

	-- `cwv_variant` is the cross-mod marker contract. Sibling mods
	-- (cosmetics_tweaker, weapon_tweaker, future) check `item_data.cwv_variant`
	-- in their hooks and SKIP item-name-keyed overrides when it's truthy. This
	-- exists because the clone inherits `entry.name` from the base weapon
	-- (e.g. cwv_es_longsword.name == "es_bastard_sword"), which would
	-- otherwise spuriously match a sibling mod's `_weapon_grip_offsets[name]`
	-- or `_breton_sword_thiccc` lookup.
	--
	-- WHY NOT just clobber entry.name/.key to def.item_key? Because vanilla
	-- code (e.g. world_hero_previewer.lua's equip_item at line 674) does
	-- `item_data = ItemMasterList[item.name]` for fallback lookups. Setting
	-- name = cwv_key meant the lookup returned nil and the equip path
	-- crashed in BackendUtils.get_item_units. See
	-- `feedback_cwv_clone_name_clobber.md` for the full incident log.
	entry.cwv_variant = true

	-- #482: self-identifying clone. entry.name/.key MUST stay the BASE keys
	-- (clobber crashes equip, see above), and the backend_id pattern is NOT
	-- guaranteed on every instance -- cim's Athanor mints Application.guid()
	-- backend_ids (crafting_in_modded_dev.lua:4644), a UUID that carries no
	-- key. Every pattern-keyed resolver silently skipped such crafted
	-- instances, so a crafted CWV weapon rendered without its type-level
	-- scale/grip on the owner + preview paths. The clone carrying its own
	-- variant key gives resolvers a bid-shape-independent positive signal;
	-- it survives the table.clone in BackendUtils.get_item_from_masterlist
	-- (backend_utils.lua:68) that produces the item_data create_equipment sees.
	entry.cwv_key = def.item_key
	-- Crowbill Weapon-Special state is owned by the isolated hammer-mode
	-- module. Persist the stable family marker on definition rows and every
	-- CIM-built clone; do not infer membership from a display name or mesh.
	if def.crowbill_mode_family then
		entry.crowbill_mode_family = def.crowbill_mode_family
	end

	entry.display_name = def.item_key .. "_name"
	entry.description = def.item_key .. "_description"

	if def.right_hand_unit then
		entry.right_hand_unit = def.right_hand_unit
	end
	if def.left_hand_unit then
		entry.left_hand_unit = def.left_hand_unit
	end
	-- `no_left_hand = true` explicitly clears the inherited left_hand_unit
	-- from the clone. Used when the variant uses the BASE weapon's template
	-- (which mounts on a different hand than the variant) — e.g.
	-- `cwv_es_outrider_grenade_launcher` clones from `dr_deus_01` (Bardin
	-- trollhammer, left-hand-mount) but the cwv variant is right-hand-mount
	-- (blunderbuss). Without this flag, the inherited `left_hand_unit =
	-- "...wpn_dr_deus_01"` would render alongside our right-hand blunderbuss,
	-- giving Kruber TWO weapons in the preview. Distinct from
	-- `def.left_hand_unit = nil` (which the existing `if def.left_hand_unit`
	-- guard treats as "don't override" → inheritance kicks in).
	if def.no_left_hand then
		entry.left_hand_unit = nil
	end
	-- v0.1.365-dev (issue 279): `no_ammo_unit = true` clears the AMMO unit
	-- fields inherited from the base clone. Needed when the variant's visual
	-- family changed (e.g. cwv_es_outrider_grenade_launcher clones dr_deus_01,
	-- whose entry carries the trollhammer torpedo ammo_unit/ammo_unit_3p) —
	-- with the template's ammo_data intact, GearUtils.spawn_inventory_unit
	-- (gear_utils.lua:164/169/248) attaches the inherited ammo mesh to the
	-- variant's own hand unit whenever NO skin resolves for the item. The
	-- curated pre-applied skin masks this on native CWV items (a skin replaces
	-- the whole unit set incl. ammo_unit, backend_utils.lua:171-183), but a
	-- cim-CRAFTED copy of the variant has no skin and rendered BOTH meshes
	-- merged (issue 279). Ammo COUNT is untouched: it lives in the weapon
	-- template's ammo_data, not on these unit-path fields.
	if def.no_ammo_unit then
		entry.ammo_unit = nil
		entry.ammo_unit_3p = nil
		printf("[cwv:279] cleared inherited ammo units on %s (no_ammo_unit)", tostring(def.item_key))
	end
	if def.inventory_icon then
		entry.inventory_icon = def.inventory_icon
	end
	if def.hud_icon then
		entry.hud_icon = def.hud_icon
	end
	if def.careers then
		entry.can_wield = def.careers
	end
	if def.template then
		entry.template = def.template
	end
	-- Always set entry.item_type to a unique cwv-prefixed key. Without this,
	-- the variant inherits the base's item_type (e.g. cwv_es_shortsword
	-- inherits "bw_dagger"), and any vanilla UI that does
	-- `Localize(item_data.item_type)` displays the BASE weapon's name
	-- ("Dagger") even though the variant is called "Shortsword". Setting
	-- entry.item_type to def.item_type (when explicit) or def.item_key (as
	-- fallback) ensures Localize hits the cwv-specific localization
	-- registered below in `_display_names`. See the "Naming flow for cwv
	-- variants" section in `DEVELOPMENT.md`.
	entry.item_type = def.item_type or def.item_key

	-- v0.1.311 tried `entry.slot_type = "cwv_dual"` (custom value) but the
	-- item then disappeared from both grids entirely — MIL or vanilla
	-- silently drops items with unrecognized slot_type. v0.1.312 reverts:
	-- the entry keeps its inherited slot_type ("ranged" for the musket).
	-- Cross-slot visibility comes from career-level "ranged" inclusion in
	-- slot_melee plus a post-filter on `get_filtered_items` that scopes
	-- which ranged items survive the melee filter (`_CWV_CROSS_SLOT_PREFIXES`,
	-- in _cwv_musket_equip_surface.lua since the #1159 slice).
	-- The `def.cross_slot` field on variants is still meaningful — it's
	-- used by the post-filter to identify allowlisted items.
	-- Per-item_type custom skin_combination_table. Each entry has its own
	-- table registered by `_register_cwv_skin_combinations` so the variant's
	-- cosmetics menu shows ONLY the curated set we wire up — vanilla skins
	-- of the base weapon don't bleed into the variant.
	local _item_type_to_skin_table = {
		cwv_imperial_longsword         = "cwv_imperial_longsword_skins",
		cwv_es_longsword_shield        = "cwv_es_longsword_shield_skins",
		cwv_es_axe_shield              = "cwv_es_axe_shield_skins",
		cwv_es_infantry_spear          = "cwv_es_infantry_spear_skins",
		cwv_es_dual_swords             = "cwv_es_dual_swords_skins",
		cwv_es_dual_axes               = "cwv_es_dual_axes_skins",
		cwv_wh_dual_axes               = "cwv_wh_dual_axes_skins",
		cwv_es_dual_maces              = "cwv_es_dual_maces_skins",
		cwv_wh_dual_maces              = "cwv_wh_dual_maces_skins",
		cwv_dr_dawi_mace               = "cwv_dr_dawi_mace_skins",
		cwv_dr_dawi_mace_shield        = "cwv_dr_dawi_mace_shield_skins",
		cwv_dr_dawi_dual_maces         = "cwv_dr_dawi_dual_maces_skins",
		cwv_es_imperial_crowbill       = "cwv_es_imperial_crowbill_skins",
		cwv_dr_dawi_crowbill           = "cwv_dr_dawi_crowbill_skins",
		cwv_es_sword_and_mace          = "cwv_es_sword_and_mace_skins",
		cwv_es_warpriest_hammer        = "cwv_es_warpriest_hammer_skins",
		cwv_es_dual_warpriest_hammers  = "cwv_es_dual_warpriest_hammers_skins",
		cwv_es_warpriest_hammer_shield = "cwv_es_warpriest_hammer_shield_skins",
		cwv_es_priest_greathammer      = "cwv_es_priest_greathammer_skins",
		cwv_es_maul                    = "cwv_es_maul_skins",
		cwv_es_greataxe                = "cwv_es_greataxe_skins",
		cwv_es_rapier                  = "cwv_es_rapier_skins",
		cwv_es_outrider_grenade_launcher = "cwv_es_outrider_grenade_launcher_skins",
		cwv_es_musket                    = "cwv_es_musket_skins",
		cwv_es_musket_old                = "cwv_es_musket_old_skins",
	}
	if def.item_type and _item_type_to_skin_table[def.item_type] then
		entry.skin_combination_table = _item_type_to_skin_table[def.item_type]
	end
	-- CLARIFY: Clear required_dlc so non-DLC users (e.g. no "lake" DLC for
	-- bastard_sword-derived variants) can equip the variant. The actual model
	-- assets (wpn_empire_2h_sword_*, wpn_emp_gk_*) live in the base inventory
	-- package list, not in DLC-only packages, so the unit paths still resolve.
	-- POTENTIAL BUG: this is verified for the Empire greatsword units and
	-- es_sword_shield variants but NOT the Bretonnian units (wpn_emp_gk_shield_*)
	-- which DO require the lake DLC package to load. A non-lake-DLC user equipping
	-- a variant whose left/right unit lives only in lake's package would see the
	-- model fail to load.
	entry.required_dlc = nil

	local traits = def.traits or {}
	local properties = def.properties or {}
	local power_level = def.power_level or 300

	local traits_json = "["
	for i, t in ipairs(traits) do
		if i > 1 then traits_json = traits_json .. "," end
		traits_json = traits_json .. '"' .. t .. '"'
	end
	traits_json = traits_json .. "]"

	local props_json = "{"
	local first = true
	for k, v in pairs(properties) do
		if not first then props_json = props_json .. "," end
		props_json = props_json .. '"' .. k .. '":' .. tostring(v)
		first = false
	end
	props_json = props_json .. "}"

	entry.rarity = "default"
	entry.cwv_definition = backend_id == nil

	-- Registration and acquisition are deliberately separate (#592). The IML
	-- owner row is definition-only and therefore carries no backend identity.
	-- CIM supplies mod_data only when it mints an exact, persisted craft.
	if backend_id then
		entry.mod_data = {
			backend_id = backend_id,
			ItemInstanceId = backend_id,
			CustomData = {
				traits = traits_json,
				power_level = tostring(power_level),
				properties = props_json,
				rarity = "default",
			},
			rarity = "default",
			traits = table.clone(traits, true),
			power_level = power_level,
			properties = table.clone(properties, true),
		}
	else
		entry.mod_data = nil
	end

	-- Pre-apply the item's own illusion as the curated cosmetic ONLY for
	-- non-default-rarity variants. Exotic / unique CWV weapons ship with
	-- a fixed illusion as part of their curated identity. Default-rarity
	-- "blacksmith template" variants must NOT pre-apply a skin — vanilla
	-- blacksmith templates carry `mod_data.CustomData.skin = nil` and the
	-- forge requires that to treat the item as unlocked.
	--
	-- See the full recipe in `DEVELOPMENT.md` "Blacksmith Template
	-- Pattern" and `reference_cwv_blacksmith_template.md`. Default-rarity
	-- variants get their model from `entry.right_hand_unit` (set above);
	-- the `BackendUtils.get_item_units` cwv-override hook below ensures
	-- that mesh actually wins at render time regardless of which entry
	-- the upstream lookup resolved item_data to. The skin entry is still
	-- registered by `_register_variant_skins` so OTHER variants of the
	-- same item_type can apply this variant's look as an illusion.
	if backend_id and not def.no_skin and def.rarity ~= "default" then
		local skin_key = def.item_key .. "_skin"
		entry.mod_data.CustomData.skin = skin_key
		entry.mod_data.skin = skin_key
	end

	-- v0.1.345-dev: exit trace for diagnostics. Reports the resolved fields
	-- the engine will read at equip + render time.
	_dbg("[cwv:build_entry] event=exit key=%s template=%s item_type=%s slot_type=%s rhu=%s lhu=%s skin=%s",
		tostring(def and def.item_key), tostring(entry.template), tostring(entry.item_type),
		tostring(entry.slot_type), tostring(entry.right_hand_unit), tostring(entry.left_hand_unit),
		tostring(entry.mod_data and entry.mod_data.skin))
	return entry
end

-- ============================================================
-- Auto-registration (deferred until backend is ready)
-- ============================================================

local _auto_registered = false

-- Issue #273: Chaos Wastes converts starting weapons by exact item key. Every
-- concrete CWV owner receives a dedicated DeusWeapons identity whose base_item
-- remains that CWV row; borrowing only the vanilla generation contract keeps
-- properties/traits valid without collapsing template, item_type, skin pool,
-- or render units to def.base_weapon; #592 acquisition remains separately bounded.
_om.install_deus_identities = function(reason)
	local exact_identity_allowed = false
	local parity = mod._cwv_peer_parity
	if parity and type(parity.all_peers_have) == "function" then
		local ok, result = pcall(parity.all_peers_have, parity)
		exact_identity_allowed = ok and result == true
	end
	local report = _om.deus_identity.install(
		_variant_definitions, ItemMasterList,
		rawget(_G, "DeusStartingWeaponTypeMapping"),
		rawget(_G, "DeusWeapons"), exact_identity_allowed)
	local fingerprint = string.format("%d:%d:%d:%d:%s", report.installed,
		report.existing, report.degraded, #report.skipped,
		tostring(exact_identity_allowed))
	if fingerprint ~= _om.deus_identity_fingerprint then
		_om.deus_identity_fingerprint = fingerprint
		local sample = {}
		for index = 1, math.min(#report.skipped, 8) do
			sample[#sample + 1] = report.skipped[index]
		end
		pcall(printf,
			"[cwv:273] deus_identity reason=%s exact=%s installed=%d existing=%d degraded=%d skipped=%d sample=%s",
			tostring(reason), tostring(exact_identity_allowed), report.installed,
			report.existing, report.degraded, #report.skipped,
			table.concat(sample, ","))
	end
	return report
end

-- Issue #567: these are the three persisted custom skins that exposed a stale
-- vanilla reverse-index. WeaponSkins.matching_weapon_skin_item_key builds
-- `_matching_weapon_skin_item_keys` only once by walking ItemMasterList owners
-- and their skin_combination_table pools (weapon_skins.lua:7824-7855). CWV
-- registers skin definitions/pools at mod load, but the owning cwv weapon rows
-- are deferred until the backend is ready. If vanilla builds the cache before
-- `_auto_register_all`, the associations remain absent even after the owner rows
-- arrive, producing "Incorrectly configured weapon skins" on save/loadout refresh.
mod._cwv567_skin_keys = {
	"cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1",
	"cwv_es_dual_maces_es_1h_mace_skin_02_runed_01",
	"cwv_es_axe_shield_wpn_emp_shield_03__axe_02_t2",
}

mod._cwv567_validate_skin_association = function(skin_key)
	local skin_item = ItemMasterList and rawget(ItemMasterList, skin_key)
	if type(skin_item) ~= "table" then return false, "skin ItemMasterList row missing" end
	if skin_item.item_type ~= "weapon_skin" or skin_item.slot_type ~= "weapon_skin" then
		return false, "skin row type/slot is not weapon_skin"
	end
	if not (WeaponSkins and WeaponSkins.skins and WeaponSkins.skins[skin_key]) then
		return false, "WeaponSkins.skins row missing"
	end

	local owner_key = skin_item.matching_item_key
	local owner = owner_key and rawget(ItemMasterList, owner_key)
	if type(owner) ~= "table" then return false, "matching weapon row missing: " .. tostring(owner_key) end
	local combination_key = owner.skin_combination_table
	local combinations = combination_key and WeaponSkins.skin_combinations[combination_key]
	if type(combinations) ~= "table" then
		return false, "owner skin_combination_table missing: " .. tostring(combination_key)
	end

	for rarity, skins in pairs(combinations) do
		if type(skins) == "table" then
			for _, candidate in ipairs(skins) do
				if candidate == skin_key then
					return true, owner_key, combination_key, rarity
				end
			end
		end
	end
	return false, "skin absent from owner combination pool " .. tostring(combination_key)
end

local function _auto_register_all()
	-- v0.1.345-dev: entry trace. Sparse (one fire per session on
	-- StateInGameRunning.on_enter; subsequent fires hit _auto_registered guard).
	_dbg("[cwv:auto_register] event=enter auto_registered=%s defs_count=%d",
		tostring(_auto_registered), #_variant_definitions)
	if _auto_registered then
		_dbg("[cwv:auto_register] event=exit_already_registered")
		return
	end

	local mil = get_mod("MoreItemsLibrary")
	local cim_dev, cim_public = get_mod("cim_dev"), get_mod("cim")
	local is_cim_owned = mod._cwv_acquisition.owner_probe(cim_dev, cim_public)

	local entries = {}
	local seed_entries, protected_seed_ids = {}, {}
	local pending_defs = {}
	local n_skipped_skin_only = 0
	local n_skipped_already_registered = 0
	local n_built_ok = 0
	local n_build_failed = 0
	local n_seed_failed = 0
	for _, def in ipairs(_variant_definitions) do
		if def.skin_only or def.cwv_retired then
			n_skipped_skin_only = n_skipped_skin_only + 1
			goto continue
		end
		-- v0.1.347-dev: per-variant toggle gate. Currently only cwv_es_crossbow
		-- needs this (default-on; user can opt out). If disabled at session start,
		-- registration is skipped and the variant never appears in inventory until
		-- re-enabled + game restart. (Hot re-enable mid-session is not supported.)
		if def.item_key == "cwv_es_crossbow" and not mod:get("enable_cwv_es_crossbow") then
			goto continue
		end
		if _registered_keys[def.item_key] then
			n_skipped_already_registered = n_skipped_already_registered + 1
			goto continue
		end
		local entry = _build_entry(def, nil)
		if entry then
			n_built_ok = n_built_ok + 1
			entries[#entries + 1] = entry
			pending_defs[#pending_defs + 1] = { def = def, entry = entry }
			_registered_keys[def.item_key] = def.item_key

			local seed_entry, seed_id, seed_error = mod._cwv_acquisition.build_seed(
				def, _build_entry, function(value) return table.clone(value, true) end, is_cim_owned)
			if seed_entry then
				seed_entries[#seed_entries + 1] = seed_entry
				protected_seed_ids[seed_id] = true
			else
				n_seed_failed = n_seed_failed + 1
				printf("[cwv:592] seed unavailable for %s; preserving old rows: %s", tostring(def.item_key), tostring(seed_error))
			end
		else
			n_build_failed = n_build_failed + 1
		end
		::continue::
	end

	local seed_registration_ok = false
	if #entries > 0 then
		if ItemMasterList then
			for _, pending in ipairs(pending_defs) do
				local key = pending.def.item_key
				-- rawget: ItemMasterList has an __index metamethod that calls
				-- crashify.print_exception("ItemMasterList has no item %s") on
				-- missing keys, polluting the console with one exception per
				-- cwv_* item per keep load. rawget bypasses the metamethod.
				-- See CHANGELOG v0.1.333 + Issue tracking; the same defensive
				-- pattern is already used on NetworkLookup.item_names 20 lines below.
				if not rawget(ItemMasterList, key) then
					ItemMasterList[key] = pending.entry
				end
			end
		end

		-- Every registered provider row must make every authored career action
		-- available on its effective template.  Do this from the completed item
		-- catalog instead of hand-copying activated_ability[1] in individual
		-- constructors: Waywatcher has an alternate action row, and future
		-- private templates otherwise silently bypass the shared contract.
		local action_report = _cwv_career_weapon_actions.install(pending_defs,
			ItemMasterList, Weapons, CareerSettings, ActionTemplates,
			_career_weapon_actions, mod._cwv_effective_weapon_templates,
			_career_action_owner)
		if not action_report.ok then
			mod:error("[cwv:661] incomplete career-action integration: %s",
				table.concat(action_report, ","))
		else
			printf("[cwv:661] career-action integration ready templates=%d prepared=%d restored=%d discarded_claims=%d",
				action_report.template_count,
				action_report.prepared_templates or 0,
				action_report.restored_actions or 0,
				action_report.discarded_inherited_claims or 0)
		end

		-- Issue #567 root fix. The vanilla reverse-index is a lazy snapshot, not a
		-- live view (weapon_skins.lua:7824-7855). The custom skin rows and pools
		-- above were already valid; what was missing at the earlier snapshot was
		-- the deferred cwv owner row carrying `skin_combination_table`. Invalidate
		-- only after every owner has been mirrored into ItemMasterList, before the
		-- backend refresh can validate persisted skins. Force vanilla to rebuild
		-- the complete index now, then canonicalize every CWV skin to its explicit
		-- IML `matching_item_key`. The canonicalization matters where two variant
		-- owners share one combination pool: vanilla's pairs(ItemMasterList) walk
		-- would otherwise let whichever owner iterates last win nondeterministically.
		local skin_cache_was_built = WeaponSkins
			and type(WeaponSkins._matching_weapon_skin_item_keys) == "table"
		if WeaponSkins then WeaponSkins._matching_weapon_skin_item_keys = nil end
		local rebuild_ok, rebuild_err = false, "WeaponSkins matcher unavailable"
		if WeaponSkins and type(WeaponSkins.matching_weapon_skin_item_key) == "function" then
			rebuild_ok, rebuild_err = pcall(
				WeaponSkins.matching_weapon_skin_item_key,
				mod._cwv567_skin_keys[1]
			)
		end
		local rebuilt_cache = WeaponSkins and WeaponSkins._matching_weapon_skin_item_keys
		if rebuild_ok and type(rebuilt_cache) == "table" then
			for custom_skin_key in pairs(_custom_skin_keys) do
				local skin_item = rawget(ItemMasterList, custom_skin_key)
				local owner_key = skin_item and skin_item.matching_item_key
				if owner_key then
					rebuilt_cache[custom_skin_key] = {
						rarity = skin_item.rarity,
						item_key = owner_key .. "_skin",
					}
				end
			end
		else
			pcall(printf, "[cwv:567] reverse-index rebuild FAILED err=%s", tostring(rebuild_err))
		end
		for _, skin_key in ipairs(mod._cwv567_skin_keys) do
			local valid, owner_or_err, combination_key, rarity = mod._cwv567_validate_skin_association(skin_key)
			local cache_row = type(rebuilt_cache) == "table" and rebuilt_cache[skin_key]
			pcall(printf,
				"[cwv:567] cache_invalidated=%s rebuild=%s skin=%s association=%s owner=%s combination=%s rarity=%s cache_item=%s",
				tostring(skin_cache_was_built), tostring(rebuild_ok), tostring(skin_key), valid and "valid" or "INVALID",
				tostring(owner_or_err), tostring(combination_key), tostring(rarity),
				tostring(cache_row and cache_row.item_key))
		end

		-- CLARIFY: Per CHANGELOG v0.1.24, MIL.add_mod_items_to_local_backend does
		-- NOT inject into NetworkLookup.item_names (only add_mod_items_to_masterlist
		-- does). Without this manual injection, network serialization crashes when
		-- the item is referenced over the wire.
		if NetworkLookup and NetworkLookup.item_names then
			for _, pending in ipairs(pending_defs) do
				local key = pending.def.item_key
				if not rawget(NetworkLookup.item_names, key) then
					local idx = #NetworkLookup.item_names + 1
					rawset(NetworkLookup.item_names, idx, key)
					rawset(NetworkLookup.item_names, key, idx)
				end
			end
		end

		local backend_items
		if Managers and Managers.backend then
			pcall(function() backend_items = Managers.backend:get_interface("items") end)
		end
		local seed_report = mod._cwv_acquisition.register_seed_interfaces(seed_entries,
			#entries, mil, backend_items, "character_weapon_variants")
		seed_registration_ok = seed_report.ok and n_seed_failed == 0
		n_seed_failed = n_seed_failed + seed_report.failed
		if not seed_report.ok then
			printf("[cwv:592] Blacksmith seed registration incomplete; preserving old rows: %s",
				tostring(seed_report.error))
		end

		_dbg("Registered %d variant definitions and %d bounded Blacksmith seeds",
			#entries, #seed_entries)
	end

	-- Infantry Spear is no longer a variant definition at all (#620), but its
	-- historical deterministic auto-grant id still needs one final cleanup.
	local purge = seed_registration_ok and mod._cwv_acquisition.plan_removals(
		_variant_definitions,
		{ [_om.infantry_spear.ITEM_KEY .. "_001"] = true },
		is_cim_owned, protected_seed_ids) or {}
	local removed = 0
	if #purge > 0 and mil and type(mil.remove_mod_items_from_local_backend) == "function" then
		mil:remove_mod_items_from_local_backend(purge, "character_weapon_variants")
		removed = #purge
	end
	mod:info("[cwv:592] definitions=%d blacksmith_seeds=%d seed_failed=%d legacy_ids_purged=%d cim_exact_ids_preserved=true",
		#entries, #seed_entries, n_seed_failed, removed)
	_om._cwv_blacksmith_seed_ids = seed_registration_ok and protected_seed_ids or {}
	_om._cwv_blacksmith_seed_count = seed_registration_ok and #seed_entries or 0

	_auto_registered = true
	-- v0.1.356-dev: VISIBLE (mod:info, not _dbg) registration summary so the
	-- "only axe+shield shows" regression can be diagnosed from the user's log
	-- (INFO is on, DEBUG is off). If built_ok is ~28 but the inventory shows 1,
	-- it's a display/backend-merge issue; if built_ok is ~1, the build loop is
	-- bailing. Also lists the keys that made it into the registration batch.
	mod:info("[cwv:auto_register] SUMMARY built_ok=%d build_failed=%d skipped_skin_only=%d skipped_already=%d entries_added=%d (defs=%d)",
		n_built_ok, n_build_failed, n_skipped_skin_only, n_skipped_already_registered, #entries, #_variant_definitions)
	do
		local keys = {}
		for _, p in ipairs(pending_defs) do keys[#keys + 1] = p.def.item_key end
		mod:info("[cwv:auto_register] registered keys: %s", table.concat(keys, ", "))
	end
end

-- CLARIFY: StateInGameRunning.on_enter fires on entering the keep AND on every
-- mission load. _auto_register_all() guards via _auto_registered flag so it
-- runs at most once per session. Backend is guaranteed live by this state per
-- DEVELOPMENT.md / CHANGELOG v0.1.17.
-- QUESTION: If a user joins a friend's lobby BEFORE entering the keep (e.g. via
-- direct lobby join), does StateInGameRunning fire? In practice the keep is
-- always the first state, so this should be fine — flagged here in case the
-- assumption breaks for future game-state changes.
mod:hook_safe("StateInGameRunning", "on_enter", function()
	_auto_register_all()
	_om.install_deus_identities("gameplay_enter")
	-- #567: this boundary also covers a peer joining directly into an existing
	-- Keep/mission after the install-time VMF query ran without a network backend.
	-- Query every CWV owner, then publish our own current state. Both are bounded
	-- one-shot messages on gameplay entry, never update-loop traffic.
	if _om._exact_pair_query then _om._exact_pair_query("gameplay_enter") end
	if _om._exact_pair_publish_local then
		_om._exact_pair_publish_local("gameplay_enter")
	end
	if _om._migrate_legacy_style_items then
		_om._migrate_legacy_style_items()
	end
	if _om._ensure_tuskgor_foot_knight then
		_om._ensure_tuskgor_foot_knight()
	end
	if _om.combat_styles and _om.combat_styles.request_states then
		_om.combat_styles:request_states("gameplay_enter")
	end
end)

-- Last-chance boundary for starting a run in the same session before another
-- gameplay-enter callback. Installation is idempotent and completes before
-- vanilla reads DeusStartingWeaponTypeMapping inside _setup_run.
if rawget(_G, "DeusMechanism") then
	mod:hook("DeusMechanism", "_setup_run", function(func, self, ...)
		_om.install_deus_identities("setup_run")
		return func(self, ...)
	end)
end

-- Seam back to the entry. The commands-lifecycle and regression context tables
-- at the bottom of the entry consume these three by reference; publishing the
-- same table / function objects here keeps their identity unchanged.
_om.item_registration = {
	registered_keys = _registered_keys,
	build_entry = _build_entry,
	auto_register_all = _auto_register_all,
}

end

return install
