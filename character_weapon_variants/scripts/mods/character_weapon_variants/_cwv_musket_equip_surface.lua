-- _cwv_musket_equip_surface.lua
-- CWV musket equip-surface owner (#1159).
--
-- Owns ONE question and its answer: what does vanilla have to do DIFFERENTLY
-- for a CWV musket between the moment the item shows up in an inventory grid
-- and the moment its weapon unit is destroyed? Every surface below exists for
-- the same root cause. A CWV variant deliberately inherits its base weapon's
-- `item_data.name` (clobbering it crashes equip - see
-- `feedback_cwv_clone_name_clobber.md`), so every name-keyed vanilla lookup on
-- the equip path resolves the BASE item, not the variant. The blocks the entry
-- used to carry inline to correct that moved here verbatim:
--   * the cross-slot inventory recognizer `_is_cwv_musket_item` with its
--     `_CWV_CROSS_SLOT_PREFIXES` list and the v0.1.327 all-candidate-id ladder
--     (a single short-circuit on the inherited base name is what made the
--     musket vanish from the melee grid);
--   * the v0.1.338 scoped career slot-type override - `_cwv_collect_cross_slot_careers`,
--     the `_do_extend` mutation and its `mod.on_all_mods_loaded` re-run - which
--     appends "ranged" to `slot_melee` ONLY on careers that own a `cross_slot`
--     variant, plus the ItemGridUI category/filter pair and the single
--     `BackendInterfaceItemPlayfab.get_filtered_items` post-filter that narrows
--     the result back down (the #424 javelin availability gate and the #935
--     combined-category preservation ride that same hook unchanged);
--   * the defensive `WeaponSpreadExtension` init/update pair, which is the same
--     inherited-name failure one layer down: vanilla reads
--     `ItemMasterList[item_name]` and gets the BASE spear template, whose
--     missing `default_spread_template` leaves `spread_settings` nil and faults
--     the next update frame's `max_pitch` arithmetic;
--   * the bayonet child-unit lifecycle end to end - the 1P/3P sword unit paths,
--     the tuned translation / rotation / scale constants, the
--     `_MUSKET_BAYONET_DATA_KEY` unit-data slot, the weak-keyed
--     `_musket_bayonet_pairs` ledger, the `Managers.package` force-load of both
--     sword units and of the polearm state machine the melee stance needs, and
--     the spawn / attach / detach / orphan-prune / visibility-sync helpers;
--   * the hooks that drive that lifecycle: `GearUtils.spawn_inventory_unit`
--     (the sole spawn chokepoint, where the bayonet attach and the v0.1.220-247
--     melee-stance rotation, scale and grip offset are applied inline),
--     `SimpleInventoryExtension._wield_slot` (bayonet visibility plus the
--     v0.1.305 auto-reload-on-wield anti-exploit), the two
--     `show_*_person_inventory` camera-toggle hooks that re-mirror the linked
--     bayonet's per-camera visibility, and `GearUtils.destroy_wielded`.
--
-- PASSENGERS. Sibling owners dispatch through the spawn and wield hooks moved
-- here, and every one of those calls is a late-bound `_om` lookup resolved at
-- fire time, long after all module loads finish - so the calls travel unchanged
-- and their owners keep their jobs: the husk path (`_om._husk_adapter_pre` /
-- `_om._husk_adapter_post`, the `not owner_unit_1p` discriminator and the #279
-- spawn probe), the Old Musket appearance / FX-proxy / ammo-pool surfaces, and
-- the #922 fade plus #604 Crowbill forget-transform edges. The v0.1.322 javelin
-- 3P spare-offhand hide rides the wield and camera hooks for the same reason.
--
-- Extracted verbatim from the entry file; behavior is unchanged. The move is a
-- pure relocation, so every log string, hook registration and tuning constant
-- is byte-identical to what the entry carried.
--
-- ORDERING. The block is INTERLEAVED in the entry: the recognizer, the career
-- override, the spread guard and the bayonet constants ran BEFORE the
-- dual-weapon FP residency, the husk-residency owner load and the husk wield
-- diagnostic, while the spawn and wield hooks ran AFTER all three. Install is
-- therefore two-phase. `install` runs the first half at the first former
-- position and RETURNS the second half as a closure; the entry calls that
-- closure at the exact second former position. Both halves share this file's
-- upvalues, so the bayonet ledger and constants declared in phase one are the
-- same objects phase two mutates. Hook registration order across the whole mod
-- is unchanged, which matters because VMF chains wrappers in registration order
-- and silently DROPS a duplicate registration on the same (Class, method).
--
-- Named (not anonymous) so the offline forward-reference lint keeps treating the
-- moved block as file-scope code: an anonymous `function(` wrapper makes every
-- construct-then-call pair below read as a closure capturing its own body. Same
-- note as _cwv_husk_residency_owner.lua and _cwv_musket_runtime.lua.
--
-- resource-safety: cwv1159-musket-equip-surface-force-load
-- One file-level marker covers every `Managers.package:load` boundary in this
-- file - three leases (the 1P bayonet sword unit, the 3P bayonet sword unit and
-- the polearm first-person state machine the melee stance needs) across two call
-- sites, since the two bayonet units share one `_load` helper - instead of
-- inline annotations, so the 914 moved lines stay byte-identical to what the
-- entry ran; that byte-identity is this slice's behavior-neutrality proof.
-- check_native_resource_safety collects markers per FILE and its own self-test
-- pins the one-marker-covers-many-calls case. There is no matching `unload`:
-- all three leases are deliberately held for the mod's lifetime (a bayonet can
-- be re-attached at any equip), which is why the spawn helper fails CLOSED on
-- `Managers.package:has_loaded` rather than loading on demand from inside the
-- spawn path. Evidence lives in
-- qa/lua/tests/test_cwv_entry_decomposition.lua, which locks the marker's
-- presence here, its absence from the entry, and the has_loaded precondition.

local function install(mod, ctx)

local _om                  = ctx.om
local _dbg                 = ctx.dbg
local _variant_definitions = ctx.variant_definitions

-- ============================================================
-- Cross-slot inventory: musket items appear in BOTH ranged AND melee
-- inventory grids
-- ============================================================
-- v0.1.268: per user direction, both `cwv_es_musket` (ranged-slot
-- inheritance) and `cwv_es_musket_polearm` (melee-slot inheritance)
-- should be equippable in EITHER slot. Player picks which musket
-- goes where; equipping consumes the item from both lists.
--
-- Mechanism: vanilla's `BackendInterfaceItemPlayfab:get_filtered_items`
-- evaluates the slot-grid filter string ("slot_type == ranged" /
-- "slot_type == melee") against each backend item. Our hook detects
-- those filters and APPENDS any musket items the player owns that
-- weren't already in the result. Since each item is a unique backend
-- entry, equipping it in one slot prevents it from showing as
-- available in the other (the slot tracks the equipped ItemId).
--
-- This is a UI-layer trick — the items keep their declared slot_type
-- in IML; the filter just becomes permissive for our muskets. The
-- equip path doesn't check slot_type compatibility, so vanilla accepts
-- the cross-slot equip without complaint. The wielded weapon's
-- behavior is determined by its template (musket_template), not by
-- its slot, so it fires identically in either slot.

-- v0.1.308: list of cwv item-key prefixes that should be cross-slot
-- equippable. These items inherit slot_type="ranged" via their base_weapon
-- but the player should be able to equip them in either slot_ranged or
-- slot_melee via the cross-slot inject below. Other cwv ranged weapons
-- (e.g. cwv_es_outrider_grenade_launcher) are NOT in this list and remain
-- ranged-only.
local _CWV_CROSS_SLOT_PREFIXES = {
	"cwv_es_musket",          -- musket family (covers cwv_es_musket and cwv_es_musket_old + backend_ids)
}

-- v0.1.327: check ALL candidate id fields, not just the first non-nil one.
-- Earlier `data.key or data.name or item.ItemId or item.backend_id` would
-- short-circuit on the first non-nil — if `data.name` happened to be the
-- inherited base name "es_handgun", the function returned false even though
-- `item.ItemId` was "cwv_es_musket_old_001". Likely root cause of "musket
-- doesn't appear in melee slot" in v0.1.316+ (post-filter scoping dropped
-- the item because the gate returned false).
local function _is_cwv_musket_item(item)
	if not item then return false end
	local data = item.data or item.master_item or item
	local bid = item.backend_id or item.ItemInstanceId
		or (data and (data.backend_id or data.ItemInstanceId))
	local canonical_key = _om._cwv_key_for_item and _om._cwv_key_for_item(bid, item)
	if canonical_key == "cwv_es_musket" or canonical_key == "cwv_es_musket_old" then
		return true
	end
	local function _check(key)
		if type(key) ~= "string" then return false end
		for _, prefix in ipairs(_CWV_CROSS_SLOT_PREFIXES) do
			if string.find(key, prefix, 1, true) == 1 then
				return true
			end
		end
		return false
	end
	if _check(data and data.key) then return true end
	if _check(data and data.name) then return true end
	if _check(item.ItemId) then return true end
	if _check(item.backend_id) then return true end
	if _check(data and data.backend_id) then return true end
	if _check(data and data.mod_data and data.mod_data.backend_id) then return true end
	return false
end

-- ============================================================
-- Career slot-type override + scoped post-filter
-- ============================================================
-- v0.1.312: combine the v0.1.304 broad career override (which actually
-- surfaced items in the melee grid) with a post-filter on the result that
-- removes non-allowlisted ranged items. End result: only items flagged
-- with `def.cross_slot = true` (currently just `cwv_es_musket_old`) appear
-- in BOTH grids; other ranged weapons stay in slot_ranged only.
--
-- History:
--   v0.1.304 — added "ranged" to slot_melee. Worked but showed ALL ranged.
--   v0.1.310 — reverted to cross-slot inject only. Didn't surface items.
--   v0.1.311 — tried entry.slot_type = "cwv_dual" custom. Item disappeared
--              from BOTH grids (MIL/vanilla doesn't accept unknown slot_type).
--   v0.1.312 — back to broad career override + post-filter for scope.
-- v0.1.313: iterate ALL careers (not just hardcoded Kruber list). Append
-- "ranged" to any career's slot_melee that's exactly {"melee"} (i.e., the
-- default Kruber-style careers). Also clean up cwv_dual leftovers from
-- v0.1.311. Mutation deferred via `mod.on_all_mods_loaded` to ensure
-- CareerSettings is fully populated.
-- Post-filter REMOVED (was scoping items too aggressively or not running
-- on the path the user's UI uses). v0.1.304 broad behavior is restored —
-- ALL ranged weapons will appear in melee grid until we confirm what's
-- breaking, then re-scope.
--
-- v0.1.338 (BUG FIX — Grail Knight FP rig corruption): the broad mutation
-- above hit ALL 28 careers in `CareerSettings`. Once a career's `slot_melee`
-- accepts both `"melee"` and `"ranged"`, the keep loadout/preview resolver
-- can pick up TWO defaults for the same slot (one melee item, one ranged
-- item), leading to two FP state machines fighting over a single first-person
-- rig. User confirmed via bisect that disabling CWV restores the FP rig;
-- Grail Knight (`es_questingknight`) was the consistent repro case
-- (`es_bastard_sword` 2H + `es_sword_shield_breton` 1H+shield both spawning
-- their FP units, with two state_machines loaded simultaneously). See marker
-- constant `CT_CWV_SLOT_EXTENSION_MARKER_v0_1_338` near the top of file.
--
-- Fix: only mutate careers that actually need cross-slot support — careers
-- that own at least one variant flagged `cross_slot = true`. Right now that's
-- the four Empire careers (`_es_all_careers`) because only `cwv_es_musket_old`
-- is cross-slot. Other 24 careers are left alone, restoring vanilla slot
-- behavior everywhere a cross-slot variant can't be equipped. The bug surface
-- remains on the 4 Empire careers (where the musket is the whole point of the
-- feature), but is removed from the other 24 careers where the broad mutation
-- was pure overshoot.
local function _cwv_collect_cross_slot_careers()
	local set = {}
	for _, def in ipairs(_variant_definitions) do
		if def.cross_slot == true and type(def.careers) == "table" then
			for _, career_name in ipairs(def.careers) do
				set[career_name] = true
			end
		end
	end
	return set
end
do _om._collect_cross_slot_careers = _cwv_collect_cross_slot_careers   -- #1148: the relocated check reads it through _om, not as a bare global
	local function _do_extend()
		if not CareerSettings then
			mod:warning("[cwv slot] CareerSettings nil — skip extension")
			return 0
		end
		local allowed_careers = _cwv_collect_cross_slot_careers()
		local allowed_count = 0
		for _ in pairs(allowed_careers) do allowed_count = allowed_count + 1 end
		if allowed_count == 0 then
			mod:info("[cwv slot] no cross_slot variants defined — skip slot_melee extension")
			return 0
		end
		local extended, skipped = 0, 0
		for career_name, career in pairs(CareerSettings) do
			if type(career) == "table" and career.item_slot_types_by_slot_name then
				local slot_map = career.item_slot_types_by_slot_name
				if slot_map.slot_melee then
					-- Cleanup cwv_dual leftovers from v0.1.311 — apply this
					-- unconditionally to every career so legacy state from
					-- prior versions is purged even on careers that we no
					-- longer extend.
					for i = #slot_map.slot_melee, 1, -1 do
						if slot_map.slot_melee[i] == "cwv_dual" then
							table.remove(slot_map.slot_melee, i)
						end
					end
					if slot_map.slot_ranged then
						for i = #slot_map.slot_ranged, 1, -1 do
							if slot_map.slot_ranged[i] == "cwv_dual" then
								table.remove(slot_map.slot_ranged, i)
							end
						end
					end
					-- v0.1.338: only extend careers that own a cross_slot
					-- variant. Other careers keep vanilla slot_melee.
					if allowed_careers[career_name] then
						local has_ranged = false
						for _, t in ipairs(slot_map.slot_melee) do
							if t == "ranged" then has_ranged = true; break end
						end
						if not has_ranged then
							slot_map.slot_melee[#slot_map.slot_melee + 1] = "ranged"
							extended = extended + 1
						end
					else
						-- Also REVERT any pre-v0.1.338 in-memory mutation on
						-- non-allowed careers, in case the broad extension
						-- already ran (e.g. CareerSettings was populated
						-- before this file reloaded). Drop only the trailing
						-- "ranged" we would have added — never touch a slot
						-- that legitimately listed "ranged" originally
						-- (vanilla doesn't, but be defensive).
						for i = #slot_map.slot_melee, 1, -1 do
							if slot_map.slot_melee[i] == "ranged" then
								table.remove(slot_map.slot_melee, i)
								skipped = skipped + 1
								break
							end
						end
					end
				end
			end
		end
		pcall(printf, "[cwv slot] extended slot_melee with 'ranged' on %d careers (scoped to cross_slot variants; %d non-allowed careers reverted)", extended, skipped)
		return extended
	end
	_om._slot_extension_log_only = true
	_do_extend()
	-- Re-run after all mods loaded in case CareerSettings was partial earlier.
	function mod.on_all_mods_loaded()
		_do_extend()
	end
end

-- v0.1.314: SINGLE consolidated post-filter hook on get_filtered_items.
-- The career mutation above adds "ranged" to slot_melee, which surfaces
-- ALL ranged weapons in the melee grid. This filter scopes that down so
-- only items whose key matches `_CWV_CROSS_SLOT_PREFIXES` (currently the
-- musket and jav+shield families) remain in a MELEE-ONLY result. Native
-- melee items are kept untouched. A combined `(melee or ranged)` category
-- is deliberately not narrowed: Career Tweaker uses that category when
-- Foot Knight's secondary slot accepts both weapon types (#935).
--
-- Replaces the prior dual-hook setup (inject + post-filter) that had
-- potential chain-ordering issues. One hook, one job: take the result
-- vanilla produces, drop the unwanted ranged items from melee grid.
--
-- #935: the primary and secondary loadout categories can both serialize to
-- the same `(melee or ranged)` filter. ItemGridUI therefore carries the
-- category's exact slot_name across the synchronous backend call; filter text
-- alone is not treated as surface identity.
mod:hook("ItemGridUI", "_on_category_index_change", function(func, self, index, ...)
	local settings = self._category_settings and self._category_settings[index]
	local slot_name = settings and (settings.slot_name or settings.name)
	self._cwv_filter_slot_name =
		(slot_name == "slot_melee" or slot_name == "slot_ranged") and slot_name or nil
	return func(self, index, ...)
end)

mod:hook("ItemGridUI", "_get_items_by_filter", function(func, self, item_filter)
	local previous = _om._cwv_filter_slot_name
	_om._cwv_filter_slot_name = self._cwv_filter_slot_name
	local ok, result = pcall(func, self, item_filter)
	_om._cwv_filter_slot_name = previous
	if not ok then
		error(result)
	end
	return result
end)

mod:hook("BackendInterfaceItemPlayfab", "get_filtered_items", function(func, self, filter, params)
	local items = func(self, filter, params)
	if not items or type(filter) ~= "string" then return items end

	-- #424: a Tuskgor Javelin is a genuine modded thrown-resource feature, not
	-- merely an alternate icon. Keep it out of the ranged loadout picker until
	-- the peer-parity feature is positively enabled. Persisted/equipped items are
	-- not deleted; the action gate below covers that hot-join state.
	if string.find(filter, "slot_type == ranged", 1, true) then
		local gate = mod._cwv_peer_parity
		local state = "disabled"
		if gate and type(gate.applied_state) == "function" then
			local ok, applied = pcall(gate.applied_state, gate)
			if ok then state = applied end
		end
		local hidden
		items, hidden = _om.javelin_gate.filter_unavailable(items, state)
		if hidden > 0 then
			_dbg("[cwv:424] hid %d Tuskgor Javelin row(s): peer capability is %s",
				hidden, tostring(state))
		end
	end
	local slot_name = _om._cwv_filter_slot_name
	if not _om.cross_slot_filter.should_narrow(filter, slot_name) then
		if _om.cross_slot_filter.kind(filter) == "combined" then
			_dbg("[cwv:935] preserved combined equipment category slot=%s",
				tostring(slot_name))
		end
		return items
	end

	local filtered, kept, dropped, dropped_examples =
		_om.cross_slot_filter.apply(items, filter, slot_name, _is_cwv_musket_item)
	_dbg("[cwv melee-grid filter] kept=%d  dropped_ranged=%d  drop_samples=[%s]",
		kept, dropped, table.concat(dropped_examples, ", "))
	return filtered
end)

-- ============================================================
-- Defensive WeaponSpreadExtension.init hook
-- ============================================================
-- v0.1.265: vanilla `WeaponSpreadExtension.init` does
-- `ItemMasterList[item_name]` to fetch the weapon's template — for
-- our cwv polearm musket variant `item_name` is the inherited base
-- name "es_2h_heavy_spear" (per `feedback_cwv_clone_name_clobber.md`),
-- so the lookup returns the BASE spear IML whose template has no
-- `default_spread_template`. Vanilla then sets
-- `self.spread_settings = SpreadTemplates[nil] = nil`, which crashes
-- the next update frame's arithmetic on `state_settings.max_pitch`.
--
-- Our `BackendUtils.get_item_template` hook can't intercept because
-- the call comes from a name-keyed lookup with no cwv marker.
--
-- Defensive fix: hook init AFTER vanilla, check for nil
-- spread_settings, fall back to handgun spread defaults. This only
-- triggers when the original lookup returned a template without
-- spread settings — vanilla weapons that have proper spread settings
-- never hit the nil branch.

mod:hook_safe("WeaponSpreadExtension", "init", function(self, extension_init_context, unit, extension_init_data)
	if not self.spread_settings and SpreadTemplates and SpreadTemplates.handgun then
		self.spread_settings = SpreadTemplates.handgun
		mod:info("[cwv musket] patched WeaponSpreadExtension nil spread_settings → SpreadTemplates.handgun (item_name=%s)",
			tostring(extension_init_data and extension_init_data.item_name))
	end
end)

-- Belt-and-suspenders: also patch in update. v0.1.265's init-only hook
-- fired (per log) but the user still crashed, suggesting either a fresh
-- spread extension was created without our init hook firing, OR
-- spread_settings became nil at some point post-init. Wrapping update
-- with `mod:hook` (full wrapper) lets us patch BEFORE vanilla's update
-- logic runs each frame — guaranteed safety.
mod:hook("WeaponSpreadExtension", "update", function(func, self, unit, input, dt, context, t)
	if not self.spread_settings and SpreadTemplates and SpreadTemplates.handgun then
		self.spread_settings = SpreadTemplates.handgun
	end
	return func(self, unit, input, dt, context, t)
end)

-- ============================================================
-- Musket bayonet — child-link a scaled 1H sword to the rifle unit
-- ============================================================
-- The musket carries a fixed bayonet visual: a copy of Kruber's 1H
-- sword (`wpn_emp_sword_02_t1`), scaled thin/short, spawned as its
-- own unit and `World.link_unit`'d to the rifle unit so it inherits
-- the rifle's transform (any animation, swap, holster motion etc.
-- carries the bayonet along). Two units total — one linked to the 1P
-- rifle (player's first-person view) and one to the 3P rifle (other
-- players + previewer + Versus opponents). Both spawned in the
-- `GearUtils.spawn_inventory_unit` post-hook below.
--
-- Lifetime: each bayonet is tracked on the rifle's unit data via
-- `Unit.set_data(rifle, "cwv_musket_bayonet", bayonet_unit)`. When
-- vanilla destroys the rifle (weapon swap, pickup drop, level end),
-- the `GearUtils.destroy_wielded` hook below reads that data slot,
-- destroys the bayonet, and falls through to vanilla. Without this
-- the bayonet would orphan as a free-floating world unit.
--
-- Position/scale tuning: the rifle .unit's local +Y is barrel-forward
-- (verified by visual reference to Kruber's vanilla wield pose), so
-- the bayonet sits at +Y 0.55m relative to the rifle root and is
-- scaled to a thin spike. These two constants are the tuning knobs —
-- if the bayonet floats off the muzzle or reads too thick/long, edit
-- _MUSKET_BAYONET_LOCAL_TRANSLATION and _MUSKET_BAYONET_SCALE.
--
-- Cross-character package note: the rifle's package is auto-loaded
-- by inventory (right_hand_unit), but the sword unit isn't part of
-- that chain. Force-load the sword via `Managers.package:load`
-- (Tuskgor Javelin pup pattern, per `feedback_cwv_cross_character_unit_packages.md`).

-- v0.1.212: switched to wpn_emp_sword_03_t1 — the "Soldier's Longsword"
-- cosmetic skin for `es_1h_sword` (verified via cosmetics_tweaker/
-- VETERAN_SKIN_CATALOG.md:900). v0.1.211's wpn_emp_sword_04_t1 turned
-- out to be the falchion mesh (matching_item_key = "wh_1h_falchion"
-- in item_master_list_weapon_skins.lua:5185), not a real es_1h_sword
-- variant — explains "that's the falchion model". The new path is a
-- proper Kruber 1H sword distinct from the default skin_01 mesh.
local _MUSKET_BAYONET_UNIT_1P    = "units/weapons/player/wpn_emp_sword_03_t1/wpn_emp_sword_03_t1"
local _MUSKET_BAYONET_UNIT_3P    = "units/weapons/player/wpn_emp_sword_03_t1/wpn_emp_sword_03_t1_3p"
-- {x, y, z} relative to rifle root. v0.1.206: re-deduced axis convention
-- from the user's prior "elongate the rifle on the Y axis" hint — rifle's
-- local +Y IS the barrel direction (which is why scaling Y stretches the
-- rifle along its length). v0.1.204's {0, 0, 0.55} placed the bayonet
-- 0.55m along rifle's local +Z, which must be the perpendicular "up"
-- axis — explains "floating above". v0.1.205 went MORE along Z (worse).
-- v0.1.206 puts the bayonet along +Y (toward muzzle) with zero Z offset:
--   * X 0    (centered on the barrel)
--   * Y 1.0  (push 1.0m toward the muzzle along the barrel)
--   * Z 0    (no vertical offset; bayonet sits AT barrel level)
-- TUNABLE — if the bayonet is still misplaced, edit these and rebuild.
-- Orientation rotation below is per v0.1.204 user confirmation; don't
-- touch the rotation constants.
local _MUSKET_BAYONET_LOCAL_TRANSLATION = { 0, 0.8, 0.025 }
-- Rotation: the sword model's blade extends along +Y (1H sword convention).
-- Rotate -90° about X to align the blade with the rifle's barrel direction.
-- v0.1.204 user confirmed this orientation is correct. Don't change unless
-- the rifle .unit's local axis convention is empirically different.
local _MUSKET_BAYONET_LOCAL_ROTATION_AXIS  = { 1, 0, 0 }
local _MUSKET_BAYONET_LOCAL_ROTATION_ANGLE = -math.pi / 2
-- Scale: applied in the bayonet's MODEL space (before rotation). Y is the
-- blade-length axis; X/Z thin the blade cross-section.
local _MUSKET_BAYONET_SCALE = { 0.35, 0.6, 0.2 }

local _MUSKET_BAYONET_DATA_KEY = "cwv_musket_bayonet"

-- Weak-keyed table mapping rifle units to their bayonet child units. Used
-- by the visibility-sync hook below (vanilla wield doesn't propagate
-- visibility to linked child units, so when a player holsters the rifle
-- the bayonet stays visible floating in space). Weak rifle keys = entries
-- auto-cleared when the rifle is GC'd.
local _musket_bayonet_pairs = setmetatable({}, { __mode = "k" })

local function _force_load_musket_bayonet_units()
	if not (Managers and Managers.package) then return end
	local function _load(unit_path, ref)
		local ok, err = pcall(function()
			Managers.package:load(unit_path, ref, nil, true, true)
		end)
		if ok then
			mod:info("[cwv musket-bayonet] force-loaded %s (ref=%s)", unit_path, ref)
		else
			mod:warning("[cwv musket-bayonet] failed to force-load %s: %s", unit_path, tostring(err))
		end
	end
	_load(_MUSKET_BAYONET_UNIT_1P, "cwv_musket_bayonet_1p")
	_load(_MUSKET_BAYONET_UNIT_3P, "cwv_musket_bayonet_3p")
end

_force_load_musket_bayonet_units()

-- ============================================================
-- Musket melee template — force-load polearm state machine
-- ============================================================
-- v0.1.227: reverted from Kerillian's elf spear back to Kruber's NATIVE
-- tuskgor spear (`two_handed_heavy_spears_template`) per user direction.
-- The elf spear's animations didn't read well on the rifle, and the
-- display_unit caused load issues. Tuskgor is Kruber-native; only the
-- polearm state machine needs force-loading (vanilla loads it for
-- Kruber only when his loadout includes es_2h_heavy_spear).

local _MUSKET_MELEE_STATE_MACHINE = "units/beings/player/first_person_base/state_machines/melee/polearm"

local function _force_load_musket_melee_assets()
	if not (Managers and Managers.package) then return end
	local ok, err = pcall(function()
		Managers.package:load(_MUSKET_MELEE_STATE_MACHINE, "cwv_musket_melee_sm", nil, true, true)
	end)
	if ok then
		mod:info("[cwv musket-melee] force-loaded %s (ref=%s)", _MUSKET_MELEE_STATE_MACHINE, "cwv_musket_melee_sm")
	else
		mod:warning("[cwv musket-melee] failed to force-load %s: %s", _MUSKET_MELEE_STATE_MACHINE, tostring(err))
	end
end

_force_load_musket_melee_assets()

-- ============================================================
-- PHASE TWO (see ORDERING above)
-- ============================================================
-- Returned to the entry and called back at the second former position, after
-- the dual-weapon FP residency, the husk-residency owner load and the husk
-- wield diagnostic have run.
local function install_spawn_surface()

local function _spawn_and_link_musket_bayonet(world, rifle_unit, bayonet_unit_path, package_ref)
	if not world or not rifle_unit or not Unit.alive(rifle_unit) then return nil end
	if not (Managers and Managers.package and Managers.package:has_loaded(bayonet_unit_path, package_ref)) then
		-- Package not ready yet — bail silently; bayonet will be missing on
		-- this equip. Player can re-equip after the load completes (rare race
		-- only at first equip immediately after mod load).
		return nil
	end
	local pos = Unit.world_position(rifle_unit, 0)
	local rot = Unit.world_rotation(rifle_unit, 0)
	local ok_spawn, bayonet = pcall(World.spawn_unit, world, bayonet_unit_path, pos, rot)
	if not ok_spawn or not bayonet then
		mod:warning("[cwv musket-bayonet] spawn failed: %s", tostring(bayonet))
		return nil
	end

	-- Link to root node. The child inherits the parent's full transform
	-- (translation + rotation + scale). Subsequent local_position/scale
	-- ops override the inherited translation/scale at composition time.
	pcall(World.link_unit, world, bayonet, 0, rifle_unit, 0)

	local t = _MUSKET_BAYONET_LOCAL_TRANSLATION
	pcall(Unit.set_local_position, bayonet, 0, Vector3(t[1], t[2], t[3]))
	local r_axis = _MUSKET_BAYONET_LOCAL_ROTATION_AXIS
	local r_ang  = _MUSKET_BAYONET_LOCAL_ROTATION_ANGLE
	pcall(Unit.set_local_rotation, bayonet, 0, Quaternion.axis_angle(Vector3(r_axis[1], r_axis[2], r_axis[3]), r_ang))
	local s = _MUSKET_BAYONET_SCALE
	pcall(Unit.set_local_scale, bayonet, 0, Vector3(s[1], s[2], s[3]))

	return bayonet
end

local function _attach_musket_bayonets(world, rifle_3p, rifle_1p)
	-- Idempotent: skip per-rifle if a bayonet is already tracked for it.
	-- Without this, a code path that re-fires our spawn hook on the same
	-- rifle (e.g. cosmetic application that refreshes equipment without
	-- going through destroy_wielded) would attach a SECOND bayonet,
	-- leaving the first as an orphan tracked-but-not-cleaned-up unit.
	local skipped_3p, skipped_1p = false, false
	if rifle_3p and Unit.alive(rifle_3p) and not _musket_bayonet_pairs[rifle_3p] then
		local bayonet_3p = _spawn_and_link_musket_bayonet(world, rifle_3p, _MUSKET_BAYONET_UNIT_3P, "cwv_musket_bayonet_3p")
		if bayonet_3p then
			pcall(Unit.set_data, rifle_3p, _MUSKET_BAYONET_DATA_KEY, bayonet_3p)
			_musket_bayonet_pairs[rifle_3p] = bayonet_3p
		end
	elseif rifle_3p then
		skipped_3p = true
	end
	if rifle_1p and Unit.alive(rifle_1p) and not _musket_bayonet_pairs[rifle_1p] then
		local bayonet_1p = _spawn_and_link_musket_bayonet(world, rifle_1p, _MUSKET_BAYONET_UNIT_1P, "cwv_musket_bayonet_1p")
		if bayonet_1p then
			pcall(Unit.set_data, rifle_1p, _MUSKET_BAYONET_DATA_KEY, bayonet_1p)
			_musket_bayonet_pairs[rifle_1p] = bayonet_1p
		end
	elseif rifle_1p then
		skipped_1p = true
	end
	-- Diagnostic log: counts pairs after each attach so duplicate-attach
	-- bugs are visible in mod log. v0.1.239 added to debug user-reported
	-- "floating bayonet on both melee and ranged".
	local pair_count = 0
	for _ in pairs(_musket_bayonet_pairs) do pair_count = pair_count + 1 end
	_dbg("[cwv musket-bayonet] attach: 3p=%s 1p=%s (skipped: 3p=%s 1p=%s) total_pairs=%d",
		tostring(rifle_3p ~= nil), tostring(rifle_1p ~= nil),
		tostring(skipped_3p), tostring(skipped_1p), pair_count)
end

local function _detach_musket_bayonet(world, rifle_unit)
	if not world or not rifle_unit then return end
	local has_data = false
	local ok_check = pcall(function() has_data = Unit.has_data(rifle_unit, _MUSKET_BAYONET_DATA_KEY) end)
	if not ok_check or not has_data then return end
	local bayonet
	pcall(function() bayonet = Unit.get_data(rifle_unit, _MUSKET_BAYONET_DATA_KEY) end)
	if not bayonet then return end
	-- Hide the bayonet IMMEDIATELY before queuing for deletion. mark_for_deletion
	-- runs at the end of the next frame; without the visibility flag, the
	-- bayonet stays rendered for that frame at its last world position
	-- (frozen where the rifle was when destroyed). User reported this as
	-- a "floating bayonet" after stance toggle — the old bayonet flickered
	-- visible while the new rifle's bayonet was already attached.
	pcall(Unit.set_unit_visibility, bayonet, false)
	if Managers and Managers.state and Managers.state.unit_spawner then
		pcall(function() Managers.state.unit_spawner:mark_for_deletion(bayonet) end)
	else
		pcall(World.destroy_unit, world, bayonet)
	end
end

mod:hook("GearUtils", "spawn_inventory_unit", function(func, world, hand, item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)
	-- Husk MESH re-key (issues 396/401, #474/#475) -- WEAPON_APPEARANCE_STANDARD
	-- section 3. MUST run BEFORE the vanilla spawn: the husk resolves the BASE
	-- item_data (name = base weapon), so vanilla spawn_inventory_unit would select
	-- the BASE mesh even for a cross-character variant (#392). Resolution is
	-- SKIN-PRIMARY (#474: a wire skin in a cwv namespace positively identifies the
	-- variant regardless of can_wield); a present non-cwv skin NEVER re-keys
	-- (#475 Invariant 1); only a skinless echo falls back to the base+career
	-- signal with can_wield evaluated lazily at wield time. Residency-guarded
	-- (vanilla overrides via the resident-3p helper, mod-bundled custom meshes
	-- via the custom-bundle predicate). No-op when nothing resolves.
	-- COMPLETE husk adapter, PRE-SPAWN half (issues 394/398/399/401/474/476/482/
	-- 719 -- BUG_CLASSES class 27; body in the husk-path module, entry is
	-- size-ratcheted). One call resolves the FULL variant definition: mesh re-key
	-- with fail-closed residency (KEEP base identity when an override/donor
	-- material is not resident -- the #474 MeshObject AV killer), pre-spawn
	-- ammo-nil (#399), and clone-template identity for the spawn (#398).
	-- `suppress` is the #478 residency-gated defer: vanilla only reached this
	-- hand because item_units[hand.."_hand_unit"] is truthy
	-- (simple_husk_inventory_extension.lua:665/669), so returning all-nil is
	-- exactly a hand vanilla never spawned. The template override feeds ONLY the
	-- vanilla call below; owner-path gates further down keep reading the
	-- caller's item_template.
	local husk_spawn_template
	if not owner_unit_1p and _om._husk_adapter_pre then
		local suppress, husk_tpl = _om._husk_adapter_pre(hand, item_template, item_units, slot_name, item_data, owner_unit_3p)
		if suppress then
			if _om._probe_279_spawn then
				_om._probe_279_spawn(hand, item_data, item_units, owner_unit_1p, owner_unit_3p, nil, "deferred_478")
			end
			return nil, nil, nil, nil
		end
		husk_spawn_template = husk_tpl
	end
	local v_w3p, v_a3p, v_w1p, v_a1p =
		func(world, hand, husk_spawn_template or item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)

	-- issue 279 (2nd repro): capture the full ammo-attach decision at EVERY
	-- spawn (owner + husk, both hands) for a no_ammo_unit variant's base. Self-gates
	-- on base being a no_ammo base; pure diagnostic (see the helper for the trace).
	if _om._probe_279_spawn then
		_om._probe_279_spawn(hand, item_data, item_units, owner_unit_1p, owner_unit_3p, v_a3p, nil)
	end

	-- ============================================================
	-- Husk (remote-player) CWV apply -- COMPLETE adapter, POST-SPAWN half
	-- ============================================================
	-- This hook is the ONLY GearUtils path that fires for husks:
	-- SimpleHuskInventoryExtension._wield_slot -> spawn_inventory_unit
	-- (simple_husk_inventory_extension.lua:666/670). The owner/bot path runs
	-- GearUtils.create_equipment (1P rig present); husks have no 1P rig, so
	-- `owner_unit_1p == nil` is the husk/bot discriminator, and everything here
	-- is IDEMPOTENT with the create_equipment apply so a bot spawn reaching both
	-- paths is harmless. Post half = #399 ammo-strip net (returns true -> nil
	-- the captured ammo return), transform/texture/presentation apply
	-- (397/394/604), and the #579 per-hand compare probe. Helpers live on `_om`
	-- (populated at load time; entry locals are not visible from the module).
	if not owner_unit_1p and _om._husk_adapter_post then
		if _om._husk_adapter_post(hand, item_data, item_units, slot_name, owner_unit_3p, v_w3p, v_a3p) then
			v_a3p = nil
		end
	end

	-- Gate: only attach for the musket variant on its right-hand spawn.
	-- IMPORTANT: cwv variants inherit `entry.name` from the base weapon
	-- (per `feedback_cwv_clone_name_clobber.md` — clobbering crashes equip),
	-- so `item_data.name` for cwv_es_musket is "es_handgun", not the cwv key.
	-- Compare the template-table reference instead. v0.1.205: the musket
	-- has TWO templates (ranged + melee for stance toggle); fire for both.
	if hand ~= "right" then
		return v_w3p, v_a3p, v_w1p, v_a1p
	end
	if not item_template or not Weapons then
		return v_w3p, v_a3p, v_w1p, v_a1p
	end
	local _bid_for_tex = item_data and (item_data.backend_id or item_data.ItemInstanceId)
	local _spawn_cwv_key = item_data and _om._cwv_key_for_item
		and _om._cwv_key_for_item(_bid_for_tex, item_data)
	local _spawn_is_old_musket = _spawn_cwv_key == "cwv_es_musket_old"
		or item_template == Weapons.old_musket_template
		or item_template == Weapons.old_musket_template_melee
	-- v0.1.300-301: gate accepts both musket families (cwv_es_musket and
	-- cwv_es_musket_old), ranged and melee templates. The bayonet attach
	-- is suppressed below for old musket (its mesh has bayonet baked in);
	-- texture/transform/FX-proxy fire for either family.
	if item_template ~= Weapons.musket_template and item_template ~= Weapons.musket_template_melee
	   and item_template ~= Weapons.old_musket_template and item_template ~= Weapons.old_musket_template_melee then
		if owner_unit_1p and _om._cwv_musket_unregister_slot then
			_om._cwv_musket_unregister_slot(owner_unit_3p, slot_name)
		end
		return v_w3p, v_a3p, v_w1p, v_a1p
	end
	if owner_unit_1p and not _spawn_is_old_musket and _om._cwv_musket_unregister_slot then
		_om._cwv_musket_unregister_slot(owner_unit_3p, slot_name)
	end

	-- Old Musket exact identity enters the Phase-3 appearance reconciler for
	-- both render perspectives, then keeps the established hidden vanilla rifle
	-- proxy solely for FX emission. All work is gated on the canonical backend id.
	if _spawn_is_old_musket then
		-- v0.1.295: distinguish ranged vs melee mode for 1P transform tuning.
		-- The user wants different pos/rot/scale per stance.
		local _mode = (item_template == Weapons.musket_template_melee
		               or item_template == Weapons.old_musket_template_melee) and "melee" or "ranged"
		_om.old_musket_appearance.reconcile(v_w1p, "owner_1p", "equip",
			item_data, _mode, { unit_name = _om.old_musket_preview.UNIT })
		_om.old_musket_appearance.reconcile(v_w3p, "owner_3p", "equip",
			item_data, _mode, { unit_name = _om.old_musket_preview.UNIT_3P })
		_om._spawn_old_musket_fx_proxy(world, v_w1p, "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1",     owner_unit_1p, "j_rightweaponattach")
		_om._spawn_old_musket_fx_proxy(world, v_w3p, "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1_3p", owner_unit_3p, "j_rightweaponattach")

		-- v0.1.306: register the spawned ammo extension into the shared
		-- reserve pool so cross-slot equipped cwv muskets share reserve
		-- ammo (chambered ammo stays per-item). 1P unit only — 3P doesn't
		-- have ammo_system in vanilla rifle template.
		if _om._cwv_musket_register_ammo_ext and v_w1p and Unit.alive(v_w1p)
				and ScriptUnit.has_extension(v_w1p, "ammo_system") then
			_om._cwv_musket_register_ammo_ext(
				ScriptUnit.extension(v_w1p, "ammo_system"), owner_unit_3p, slot_name)
		end
	end

	-- v0.1.248: aggressive orphan prune BEFORE attaching new bayonet.
	-- Catches stale entries from any code path that bypassed our
	-- destroy_wielded cleanup hook (e.g. world transition / hot-load /
	-- any equipment re-creation that doesn't go through destroy_slot).
	-- Without this, an orphan from a previous spawn floats while a
	-- fresh bayonet attaches to the new rifle — user sees a SECOND
	-- floating bayonet on every equip.
	local orphans_pruned = 0
	for rifle, bayonet in pairs(_musket_bayonet_pairs) do
		if not Unit.alive(rifle) then
			if Unit.alive(bayonet) then
				pcall(Unit.set_unit_visibility, bayonet, false)
				if Managers and Managers.state and Managers.state.unit_spawner then
					pcall(function() Managers.state.unit_spawner:mark_for_deletion(bayonet) end)
				end
			end
			_musket_bayonet_pairs[rifle] = nil
			orphans_pruned = orphans_pruned + 1
		end
	end
	if orphans_pruned > 0 then
		_dbg("[cwv musket-bayonet] pruned %d orphan(s) before new attach", orphans_pruned)
	end

	-- v0.1.278: skip bayonet attach for cwv_es_musket_old — the custom mesh
	-- already has a fixed bayonet baked into the model.
	local _is_old_musket = _spawn_is_old_musket

	if not _is_old_musket then
		-- pcall outer: bayonet failure should never break the equip itself.
		pcall(_attach_musket_bayonets, world, v_w3p, v_w1p)
	end
	-- v0.1.286: cwv_es_musket_old overlay system DELETED. The variant now uses
	-- our custom mesh path as right_hand_unit and the vanilla GearUtils pipeline
	-- spawns it directly. See PackageManager hooks at top of file for the
	-- "Resource not found" workaround, and the .unit files for the
	-- `data.mat_to_use` vanilla-material reference that gives FP rendering.

	-- v0.1.220: in melee mode (musket_template_melee), the polearm
	-- attachment_node_linking holds the rifle perpendicular to its
	-- intended orientation. Apply rotations to correct it. v0.1.226
	-- composes Y barrel-spin + Z. v0.1.227: melee template is back to
	-- Kruber's tuskgor spear (also AttachmentNodeLinking.polearm) so
	-- same correction applies.
	if item_template == Weapons.musket_template_melee then
		-- v0.1.241: per user "rotate along z-axis about 90 degrees more",
		-- bump outermost q_z2 from π to 3π/2 (adds another 90° at the
		-- outermost composition position).
		-- Total composition: `q_z2(3π/2) * q_y(-π/2) * q_z(π/2) * q_x(π)`.
		local q_y  = Quaternion.axis_angle(Vector3(0, 1, 0), -math.pi / 2)
		local q_z  = Quaternion.axis_angle(Vector3(0, 0, 1), math.pi / 2)
		local q_x  = Quaternion.axis_angle(Vector3(1, 0, 0), math.pi)
		local q_z2 = Quaternion.axis_angle(Vector3(0, 0, 1), math.pi * 1.5)
		local q    = Quaternion.multiply(q_z2, Quaternion.multiply(Quaternion.multiply(q_y, q_z), q_x))
		if v_w3p and Unit.alive(v_w3p) then
			pcall(Unit.set_local_rotation, v_w3p, 0, q)
		end
		if v_w1p and Unit.alive(v_w1p) then
			pcall(Unit.set_local_rotation, v_w1p, 0, q)
		end

		-- v0.1.227: per user, scale the rifle DOWN in 1st person ONLY
		-- when in melee mode (3P stays at the type-level scale so other
		-- players see the normal-sized musket-bayonet). Multiply the
		-- existing local scale by the factor below — the type-level
		-- {0.9, 1.35, 0.9} is already applied by the
		-- GearUtils.create_equipment hook by the time we get here.
		-- Reading current scale and multiplying composes correctly
		-- regardless of pre-existing scale.
		-- v0.1.247: per-axis scale factors per user "0.8x and 0.8y"
		-- (Z unchanged). v0.1.265: Y bumped 0.8 → 1.2 per user "make
		-- 1P melee 1.8y" — composes against type-level 1P Y of 1.5 to
		-- give 1.5 * 1.2 = 1.8 for 1P melee. 3P unchanged at 1.35.
		local _MELEE_1P_SCALE_FACTOR = { 0.8, 1.2, 1.0 }  -- TUNABLE per-axis
		if v_w1p and Unit.alive(v_w1p) then
			pcall(function()
				local current = Unit.local_scale(v_w1p, 0)
				local cx, cy, cz = Vector3.to_elements(current)
				local f = _MELEE_1P_SCALE_FACTOR
				Unit.set_local_scale(v_w1p, 0, Vector3(cx * f[1], cy * f[2], cz * f[3]))
			end)
		end

		-- v0.1.229: melee grip height/forward offset. After the rotation
		-- correction the rifle sits too low and slightly back from where
		-- a polearm grip should hold it. Apply a translation delta on
		-- top of vanilla's attachment_node_linking offset (read current
		-- local position, ADD our delta, set back). Compose-friendly so
		-- it doesn't fight the polearm attachment offset.
		--   Y +0.1 — push slightly forward along the rifle's barrel axis
		--   Z -0.3 — drop the grip height
		-- Applied to BOTH 1P and 3P so the held view and other players
		-- see the same pose. TUNABLE constants.
		local _MELEE_LOCAL_OFFSET = { 0, 0.06, -0.3 }
		local function _apply_melee_offset(unit)
			if not unit or not Unit.alive(unit) then return end
			pcall(function()
				local current = Unit.local_position(unit, 0)
				local cx, cy, cz = Vector3.to_elements(current)
				Unit.set_local_position(unit, 0, Vector3(
					cx + _MELEE_LOCAL_OFFSET[1],
					cy + _MELEE_LOCAL_OFFSET[2],
					cz + _MELEE_LOCAL_OFFSET[3]))
			end)
		end
		_apply_melee_offset(v_w3p)
		_apply_melee_offset(v_w1p)
	end

	return v_w3p, v_a3p, v_w1p, v_a1p
end)

-- ============================================================
-- Musket bayonet visibility sync
-- ============================================================
-- VT2's wield system DOESN'T destroy the rifle's units when the player
-- swaps to a different weapon — it just hides them via
-- Unit.set_unit_visibility(rifle, false). The bayonet is a separate
-- World.link_unit'd unit that doesn't inherit the rifle's visibility
-- flag (Stingray links transforms, not visibility), so it stays visible
-- floating in space when the rifle is hidden.
--
-- Fix: track all spawned bayonet pairs in a weak-keyed table. Hook the
-- inventory paths that change wielded state (`_wield_slot` runs whenever
-- the player switches weapons). After each, walk the table and set each
-- bayonet's visibility based on whether its rifle is the currently-
-- wielded weapon. When player wields the rifle: bayonet shows. When they
-- swap to a different slot: bayonet hides.

-- (_musket_bayonet_pairs declared above near the bayonet constants so
-- _attach_musket_bayonets can register entries directly.)

-- Sync visibility of all tracked bayonets based on current wielded state.
-- Also opportunistically destroys ORPHAN bayonets (rifle is dead but
-- bayonet still alive — happens when a code path bypasses our
-- destroy_wielded cleanup hook, e.g. cosmetic application or any
-- equipment refresh that swaps the rifle without firing destroy_wielded).
local function _sync_all_bayonets_visibility(equipment)
	if not equipment then return end
	local wielded_3p = equipment.right_hand_wielded_unit_3p
	local wielded_1p = equipment.right_hand_wielded_unit
	local orphans, shown, hidden = 0, 0, 0
	for rifle, bayonet in pairs(_musket_bayonet_pairs) do
		if not Unit.alive(rifle) then
			-- Orphan: rifle gone but bayonet lingers. Hide and destroy.
			if Unit.alive(bayonet) then
				pcall(Unit.set_unit_visibility, bayonet, false)
				if Managers and Managers.state and Managers.state.unit_spawner then
					pcall(function() Managers.state.unit_spawner:mark_for_deletion(bayonet) end)
				end
			end
			_musket_bayonet_pairs[rifle] = nil
			orphans = orphans + 1
		elseif Unit.alive(bayonet) then
			local should_show = (rifle == wielded_3p) or (rifle == wielded_1p)
			pcall(Unit.set_unit_visibility, bayonet, should_show)
			if should_show then shown = shown + 1 else hidden = hidden + 1 end
		end
	end
	if orphans + shown + hidden > 0 then
		_dbg("[cwv musket-bayonet] sync: orphans=%d shown=%d hidden=%d", orphans, shown, hidden)
	end
end

-- Hook the wield path. Full wrapper because we need PRE and POST work:
--   PRE  — detect if the outgoing wielded weapon is one of our cwv muskets
--          AND mid-reload. If so, flag item_data so we can cancel the
--          auto-reload-on-wield that vanilla triggers when wielding back.
--   POST — sync bayonet visibility against the new wielded state (existing
--          v0.1.281 behavior), AND if the newly-wielded weapon is a flagged
--          cwv musket that just got auto-reload-on-wield kicked off, abort it.
-- v0.1.305: anti-exploit. User report: empty rifle reload start → swap to
-- melee → swap back → fully reloaded immediately. Root cause: vanilla
-- `SimpleInventoryExtension._wield_slot:2046-2068` auto-starts a reload
-- on wield if ammo_count == 0. The earlier abort_reload (line 1937) of the
-- old reload progress was working, but vanilla's auto-on-wield gave the
-- player a free "instant restart" of the reload that they could complete
-- visually without paying the full reload_time wait. Fix: when our cwv
-- musket was reloading at unwield time, abort the auto-reload-on-wield
-- when re-wielded. Player must press R explicitly to start a fresh reload.
-- v0.1.306: backend_id is stored at `item_data.mod_data.backend_id` for cwv
-- entries (see _build_entry — `entry.mod_data.backend_id = backend_id`).
-- Sometimes vanilla also copies it to `item_data.backend_id` directly
-- (other hooks in this file rely on that), so check BOTH locations.
local function _item_backend_id(item_data)
	if not item_data then return nil end
	local bid = item_data.backend_id
	if type(bid) ~= "string" then
		bid = item_data.mod_data and item_data.mod_data.backend_id
	end
	return type(bid) == "string" and bid or nil
end

mod:hook("SimpleInventoryExtension", "_wield_slot", function(orig, self, equipment, slot_data, unit_1p, unit_3p, buff_extension)
	-- PRE — detect unwield-of-reloading-cwv-musket.
	local outgoing_unit = equipment.right_hand_wielded_unit
	if outgoing_unit and Unit.alive(outgoing_unit) and ScriptUnit.has_extension(outgoing_unit, "ammo_system") then
		local outgoing_slot = equipment.wielded_slot
		local outgoing_slot_data = outgoing_slot and equipment.slots[outgoing_slot]
		local outgoing_item_data = outgoing_slot_data and outgoing_slot_data.item_data
		local outgoing_bid = _item_backend_id(outgoing_item_data)
		if outgoing_bid and outgoing_bid:match("^cwv_es_musket") then
			local ammo_ext = ScriptUnit.extension(outgoing_unit, "ammo_system")
			if ammo_ext and ammo_ext.is_reloading and ammo_ext:is_reloading() then
				outgoing_item_data.mod_data = outgoing_item_data.mod_data or {}
				outgoing_item_data.mod_data.cwv_musket_reload_interrupted = true
			end
		end
	end

	-- Run vanilla. Vanilla aborts the outgoing reload (clean) AND triggers
	-- auto-reload-on-wield for the incoming weapon if its clip is empty.
	local result = orig(self, equipment, slot_data, unit_1p, unit_3p, buff_extension)

	-- POST — cancel the auto-reload-on-wield for flagged cwv musket items.
	local incoming_item_data = slot_data and slot_data.item_data
	local incoming_bid = _item_backend_id(incoming_item_data)
	if incoming_bid and incoming_bid:match("^cwv_es_musket")
			and incoming_item_data.mod_data
			and incoming_item_data.mod_data.cwv_musket_reload_interrupted then
		-- One-shot flag: clear after handling so a future manual reload works.
		incoming_item_data.mod_data.cwv_musket_reload_interrupted = nil
		local incoming_unit = equipment.right_hand_wielded_unit
		if incoming_unit and Unit.alive(incoming_unit) and ScriptUnit.has_extension(incoming_unit, "ammo_system") then
			local ammo_ext = ScriptUnit.extension(incoming_unit, "ammo_system")
			if ammo_ext and ammo_ext.is_reloading and ammo_ext:is_reloading() then
				pcall(function() ammo_ext:abort_reload() end)
			end
		end
	end

	-- POST — bayonet visibility sync (v0.1.281 behavior, preserved).
	_sync_all_bayonets_visibility(self._equipment or equipment)

	-- v0.1.322: hide the duplicated 3P offhand spare boar spear for cwv
	-- javelin variants. Vanilla _wield_slot (simple_inventory_extension.lua:2153)
	-- sets ammo_unit_3p visible when the weapon is wielded. For our javelin
	-- the IML's `left_hand_unit` AND the resolved `ammo_unit` both point
	-- at the boar spear (per v0.1.314 revert — keeping ammo_unit on the
	-- held mesh is mandatory for projectile/pickup paths). Result: 3P
	-- renders two boar spears (held + spare offhand). We can't blank
	-- ammo_unit on the data table without breaking the ammo paths, so we
	-- runtime-hide the spawned 3P instance instead. 1P offhand left alone.
	local js_bid = _item_backend_id(slot_data and slot_data.item_data)
	if js_bid and (js_bid:match("^cwv_es_javelin_") or js_bid:match("^cwv_wh_javelin_")) then
		if slot_data.left_ammo_unit_3p and Unit.alive(slot_data.left_ammo_unit_3p) then
			pcall(Unit.set_unit_visibility, slot_data.left_ammo_unit_3p, false)
		end
		if slot_data.right_ammo_unit_3p and Unit.alive(slot_data.right_ammo_unit_3p) then
			pcall(Unit.set_unit_visibility, slot_data.right_ammo_unit_3p, false)
		end
	end; local incoming_cwv_key = _om._cwv_key_for_item(incoming_bid, incoming_item_data); if incoming_cwv_key then _om.appearance_fade.owner_wield(self, equipment) end -- #922 owner 3P

	return result
end)

-- v0.1.263: hook FP/3P camera-mode toggle methods. When player switches
-- between first-person and third-person view, vanilla toggles the
-- relevant rifle units' visibility — but `World.link_unit` doesn't
-- propagate visibility to children, so the linked bayonet keeps
-- rendering in BOTH cameras (visible from 3P even though 1P rifle is
-- hidden). User reported this as a "floating dagger" in third-person
-- view. Now the bayonet's visibility mirrors its parent rifle's
-- per-camera state.
mod:hook_safe("SimpleInventoryExtension", "show_first_person_inventory", function(self, show)
	local equipment = self._equipment
	if not equipment then return end
	local rifle_1p = equipment.right_hand_wielded_unit
	if rifle_1p and Unit.alive(rifle_1p) then
		local bayonet = _musket_bayonet_pairs[rifle_1p]
		if bayonet and Unit.alive(bayonet) then
			pcall(Unit.set_unit_visibility, bayonet, show)
		end
	end
end)

mod:hook_safe("SimpleInventoryExtension", "show_third_person_inventory", function(self, show)
	local equipment = self._equipment
	if not equipment then return end
	local rifle_3p = equipment.right_hand_wielded_unit_3p
	if rifle_3p and Unit.alive(rifle_3p) then
		local bayonet = _musket_bayonet_pairs[rifle_3p]
		if bayonet and Unit.alive(bayonet) then
			pcall(Unit.set_unit_visibility, bayonet, show)
		end
	end

	-- v0.1.322: re-hide cwv javelin 3P spare boar spear when the engine
	-- toggles 3P inventory visibility to true (camera switch, level start).
	-- Without this, the _wield_slot-time hide is undone on every FP→3P
	-- camera flip. show=false naturally hides everything, no work needed.
	if show then
		local wielded_slot = equipment.wielded_slot
		local slot_data = wielded_slot and equipment.slots and equipment.slots[wielded_slot]
		local item_data = slot_data and slot_data.item_data
		local bid = _item_backend_id(item_data)
		if bid and (bid:match("^cwv_es_javelin_") or bid:match("^cwv_wh_javelin_")) then
			if slot_data.left_ammo_unit_3p and Unit.alive(slot_data.left_ammo_unit_3p) then
				pcall(Unit.set_unit_visibility, slot_data.left_ammo_unit_3p, false)
			end
			if slot_data.right_ammo_unit_3p and Unit.alive(slot_data.right_ammo_unit_3p) then
				pcall(Unit.set_unit_visibility, slot_data.right_ammo_unit_3p, false)
			end
		end
	end
end)

-- Cleanup: when the rifle is destroyed (weapon swap, holster, level end),
-- destroy any bayonet linked to it. Run BEFORE vanilla so we still have a
-- live unit handle to read get_data from.
mod:hook("GearUtils", "destroy_wielded", function(func, world, wielded_unit)
	if wielded_unit and Unit.alive(wielded_unit) then
		if _om._cwv_forget_crowbill_transform_unit then
			_om._cwv_forget_crowbill_transform_unit(wielded_unit, "destroy_wielded")
		end
		-- Also clear any tracking entry to avoid using a dead key.
		_musket_bayonet_pairs[wielded_unit] = nil
		_detach_musket_bayonet(world, wielded_unit)
		-- v0.1.293: destroy Old Musket FX-proxy (hidden vanilla rifle) when
		-- our custom mesh is destroyed.
		if _om._destroy_old_musket_fx_proxy then
			_om._destroy_old_musket_fx_proxy(wielded_unit)
		end
	end
	return func(world, wielded_unit)
end)

end

return install_spawn_surface

end

return install
