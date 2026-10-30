-- _cwv_husk_residency_owner.lua
-- CWV cross-character husk package-residency owner (#1159/#2).
--
-- Owns every boot-time load that makes a remote-player (husk) spawn of a CWV
-- cross-character variant survivable and correct on a client that is not
-- playing the source career:
--   * the `dr_shield_axe` BASE-unit force-load, the issue #280 crash floor for
--     the no-skin base-path husk spawn;
--   * the data-driven OVERRIDE-unit residency pass (issues 396/401) that walks
--     every variant definition and force-loads any per-hand unit differing from
--     its base weapon, plus the shared
--     `_om._husk_override_unit_needs_residency` predicate the regression test
--     derives from and the attempt-capped `mod.on_all_mods_loaded` retry;
--   * the `SimpleHuskInventoryExtension.start_weapon_fx` nil-slot guard, the
--     belt-and-suspenders crash floor behind those loads (#280).
-- Also owns the late resource-truth/donor/override-lease/preview closures.
-- The private deferred initializer receives the husk path's exact logger and
-- runs at its original definition boundary, not at this earlier boot install.
-- Existing closure bodies, load policy and per-install ledgers are unchanged.
-- Returns the exact resource-truth closure for the husk re-key's private capture;
-- later replacement of the test-facing _om export must not redirect that caller.
--
-- Registers exactly one hook: SimpleHuskInventoryExtension.start_weapon_fx.
-- The sibling SimpleHuskInventoryExtension._wield_slot husk-wield diagnostic
-- stays in the entry immediately after this module's load point - it is a
-- dispatch hub for the exact-identity, combat-style, Crowbill and fade
-- channels, not residency, and VMF would drop a duplicate hook if either pair
-- were registered twice.
--
-- Publishes the same four bare globals the inline blocks did, read by
-- `_cwv_regression_identity`: _cwv_axe_shield_residency_ran,
-- _cwv_husk_override_residency_ran, _cwv_husk_override_paths,
-- _cwv_husk_fx_guard_installed. Also assigns
-- `_om._husk_override_unit_needs_residency`.
--
-- Load-time deps: `_om.HUSK_OVERRIDE_REF` and `_om.variant_catalog` must
-- already exist (this loads at the same point in the entry as before, well
-- after both). `_variant_definitions` arrives through ctx: the entry binds it
-- once at its line 413 and never rebinds it, so the reference cannot go stale.
-- The `mod.on_all_mods_loaded` chain captures whatever handler the entry had
-- installed at this position, exactly as the inline block did.
--
-- Named (not anonymous) so the offline forward-reference lint keeps treating
-- the moved block as file-scope code: an anonymous `function(` wrapper makes
-- every construct-then-call pair below read as a closure capturing its own
-- body. See the same note in _cwv_musket_runtime.lua.
--
-- resource-safety: cwv1159-husk-residency-force-load -- boot and deferred leases
-- One file-level marker covers all FOUR `Managers.package:load` boundaries:
-- the two boot passes and the deferred donor/override runtime leases.
-- check_native_resource_safety collects markers per FILE, and its own self-test
-- pins the one-marker-covers-many-calls case. Evidence lives in
-- qa/lua/tests/test_cwv_residency_ledger.lua: boot records successful loads
-- with bounded retries; runtime leases consume attempts before protected loads.
-- The moved query/lease bodies retain late global/_om reads and original errors.
local function install(mod, ctx)
local _om = ctx.om
local _variant_definitions = ctx.variant_definitions

-- ============================================================
-- Cross-character husk weapon residency  (Issue #280)
-- ============================================================
-- CLIENT CTD when a remote player (husk) wields the Kruber Axe & Shield
-- variant (`cwv_es_axe_shield`, base `dr_shield_axe`).
--
-- ROOT CAUSE (confirmed against decompiled source):
--   * CWV variant entries inherit `.name` from their cloned base — the
--     "clone-name-clobber" (feedback_cwv_clone_name_clobber.md). The variant
--     `cwv_es_axe_shield` therefore has `.name = "dr_shield_axe"`.
--   * The host wields the variant; the equipment RPC syncs the item to peers
--     by its `.name`, i.e. the BASE key `dr_shield_axe` (Bardin's 1H axe &
--     shield). A remote client that is NOT playing Bardin looks up the
--     VANILLA `ItemMasterList.dr_shield_axe`
--     (item_master_list_exported.lua:7358) and tries to spawn its 3P units:
--       - right_hand_unit "units/weapons/player/wpn_dw_axe_01_t1/wpn_dw_axe_01_t1"
--       - left_hand_unit  "units/weapons/player/wpn_dw_shield_01_t1/wpn_dw_shield_01"
--     Both are NON-resident on that client (nobody there loaded Bardin's kit).
--   * Vanilla `SimpleHuskInventoryExtension._wield_slot`
--     (simple_husk_inventory_extension.lua:641) spawns the 3P unit at
--     gear_utils.lua:190. On a non-resident unit it faults AFTER
--     `GearUtils.destroy_equipment` (line 658, which clears
--     `equipment.wielded_slot`) but BEFORE line 775 re-sets it.
--     cosmetics_tweaker's `_wield_slot` wrap pcall-swallows that fault
--     (cosmetics_tweaker.lua:7363), so vanilla `wield()` proceeds with
--     `equipment.wielded_slot == nil`, and `start_weapon_fx` (line 790) then
--     indexes `equipment.slots[nil]` -> `get_item_template(nil)` -> hard
--     CLIENT CTD. (The local wielder is fine: its own loadout stores the real
--     variant key, so it resolves the variant's Kruber-native, resident units.)
--
-- PRIMARY FIX: force-load the BASE weapon's units (1P + 3P) so they are
-- resident on EVERY client. Then the husk spawn succeeds, `_wield_slot`
-- reaches line 775, `equipment.wielded_slot` is set, and `start_weapon_fx`
-- reads a real slot. Mirrors the shipped musket-bayonet / javelin idiom:
-- `Managers.package:load(unit_path, ref, nil, sync=true, prioritize=true)`,
-- pcall-guarded (a unit path IS the vanilla pickup_package_loader form — see
-- the throwing-axe / javelin loaders in this file), residency re-verified via
-- `has_loaded`. `Application.can_get` is deliberately NOT used as a pre-gate:
-- for the units we must load it reports `false` (that non-residency is the
-- whole bug), so gating on it would skip exactly the loads we need.
-- Wrapped in `do ... end` so the constant + helper locals release back to the
-- main chunk (Lua 5.1 hard 200-local ceiling — this file already sits at the
-- limit; see the `_om` holder note near the top). Runs once, immediately.
do
	local _AXE_SHIELD_BASE_KEY = "dr_shield_axe"

	local function _force_load_axe_shield_husk_units()
		if not (Managers and Managers.package) then return end
		local base = rawget(ItemMasterList, _AXE_SHIELD_BASE_KEY)
		if type(base) ~= "table" then
			printf("[cwv axe-shield-residency] base '%s' absent from ItemMasterList; skipping force-load", _AXE_SHIELD_BASE_KEY)
			return
		end
		local ref = "cwv_axe_shield_husk_units"
		-- Husks spawn the 3P unit only (owner_unit_1p is nil for husks;
		-- gear_utils.lua appends "_3p" at line 189). Load the 1P form too so any
		-- inspect / hot-join / edge path is also covered — cost is two small
		-- meshes, matching how the musket bayonet loads both hands.
		local seen = {}
		for _, field in ipairs({ "right_hand_unit", "left_hand_unit" }) do
			local u = base[field]
			if type(u) == "string" and u ~= "" then
				for _, path in ipairs({ u, u .. "_3p" }) do
					if not seen[path] then
						seen[path] = true
						local ok, err = pcall(function()
							Managers.package:load(path, ref, nil, true, true)
						end)
						if ok then
							local resident = false
							pcall(function() resident = Managers.package:has_loaded(path, ref) and true or false end)
							printf("[cwv axe-shield-residency] force-loaded %s (ref=%s, resident=%s)", path, ref, tostring(resident))
						else
							printf("[cwv axe-shield-residency] FAILED to force-load %s: %s", path, tostring(err))
						end
					end
				end
			end
		end
		_cwv_axe_shield_residency_ran = true
	end

	_force_load_axe_shield_husk_units()
end

-- ============================================================
-- Cross-character husk OVERRIDE-unit residency  (issues 401, 396)
-- ============================================================
-- The axe_shield residency above force-loads the vanilla BASE units
-- (dr_shield_axe = Bardin's DWARF axe/shield) so the base-path husk spawn
-- can't CTD (issue 280 crash floor). But those base units are NOT what the
-- variant renders: the CWV entry overrides them with EMPIRE meshes
-- (wpn_axe_02_t1 + wpn_emp_shield_02; veteran = wpn_axe_hatchet_t2_magic_01 +
-- wpn_es_deus_shield_02_magic). Issue 401 confirmed (2 paired peer logs): the
-- husk showed the dwarf base because only the dwarf units were resident, so
-- the skin-path spawn of the Empire override units failed. Issue 396 is the
-- same class for the Imperial Longsword family, whose Empire greatsword mesh
-- (wpn_empire_2h_sword_04_t1) and Bretonnian-base shield variant units are
-- likewise non-resident on a client not playing a career that natively loads
-- them -> invisible husk.
--
-- The curated skin a CWV variant syncs carries the SAME per-hand override
-- units as the def (`_register_variant_skins` sets skin.right_hand_unit =
-- def.right_hand_unit, skin.left_hand_unit = def.left_hand_unit), so the def
-- override paths ARE the skin-path meshes the husk spawns — covering the def
-- fields covers the curated skin by construction.
--
-- Fix (v0.1.367-dev): DATA-DRIVEN residency. Instead of a hand-maintained key
-- list (which covered only 5 of the 27 variants whose override differs from
-- its base — 22 latent invisible-husk gaps, e.g. every dual-wield, the maul,
-- greataxe, greathammers, cudgel, shortsword, we_sword_shield, javelin boar
-- spear, outrider blunderbuss), walk EVERY def and force-load any
-- right_hand_unit / left_hand_unit (+ its `_3p` form) that DIFFERS from the
-- base weapon's same-field unit. New variants are covered automatically. Reads
-- straight from the variant DEFS (the authoritative source of the override
-- paths — the built entries don't exist yet this early in the file), compares
-- against `rawget(ItemMasterList, base_weapon)` (vanilla bases are resident at
-- boot). This is boot-time (at the keep, NOT mission load), a bounded set of
-- ~23 unique specific meshes deduped + ref-held for the session — NOT a
-- blanket mission-load force-load (the wt+cosmetics 1 GiB Lua-heap crash
-- class). The dwarf base load above is intentionally KEPT (it is the issue-280
-- crash floor for the base-path spawn, i.e. the no-skin case where the husk
-- spawns the base units); this block is purely additive residency for the
-- correct override meshes the skin-path spawn needs. Overrides that EQUAL the
-- base (musket / rapier reuse the base mesh) and the invisible-weapon sentinel
-- (javelin right hand) are skipped — nothing extra to load.
do
	-- Resolve the base weapon's same-field unit so we only force-load OVERRIDES
	-- that actually differ from what the base already renders. Vanilla bases are
	-- resident in ItemMasterList at boot; a nil base (e.g. a CW-only base not yet
	-- merged) is treated as "differs" so we conservatively load the override.
	local function _base_field_unit(base_weapon, field)
		local base = type(base_weapon) == "string" and rawget(ItemMasterList, base_weapon)
		return (type(base) == "table") and base[field] or nil
	end

	-- Shared predicate: is `u` an override unit that needs its own residency
	-- (real path, not the invisible-weapon sentinel, and differs from the base
	-- weapon's same-field unit)? Used by BOTH this pass and the regression test
	-- so the loaded set and the assertion derive from one rule (issues 396/401).
	_om._husk_override_unit_needs_residency = function(def, field)
		local u = def and def[field]
		if type(u) ~= "string" or u == "" then return nil end
		if u:find("wpn_invisible_weapon", 1, true) then return nil end
		-- Issue 403 boot fatal: ONLY vanilla weapon meshes are loadable
		-- per-unit packages. A mod-bundled mesh (units/cwv_*, e.g. the old
		-- musket custom unit) is NOT a package; queuing it via
		-- Managers.package:load is an UNCATCHABLE engine fatal when the async
		-- queue pops (PackageManager._pop_queue) - the pcall around load()
		-- cannot protect it. Mod-bundled meshes are resident wherever the mod
		-- is installed, so they never need residency anyway.
		if u:find("units/weapons/player/", 1, true) ~= 1 then return nil end
		if u == _base_field_unit(def.base_weapon, field) then return nil end
		return u
	end

	-- #401: the ledger records SUCCESS, not attempts (a pre-write made failed
	-- loads count as loaded and never re-attempted -- log-only residency).
	local _loaded = {}     -- path -> true (load call SUCCEEDED); exposed for the regression test
	local _attempts, _MAX_LOAD_ATTEMPTS = {}, 3   -- path -> attempt count; bounded retry cap

	local function _force_load_husk_override_units()
		if not (Managers and Managers.package) then return end
		local ref = _om.HUSK_OVERRIDE_REF
		for _, d in ipairs(_variant_definitions) do
			for _, field in ipairs({ "right_hand_unit", "left_hand_unit" }) do
				local u = _om._husk_override_unit_needs_residency(d, field)
				if u then
					for _, path in ipairs({ u, u .. "_3p" }) do
						if not _loaded[path] and (_attempts[path] or 0) < _MAX_LOAD_ATTEMPTS then
							_attempts[path] = (_attempts[path] or 0) + 1
							local ok, err = pcall(function()
								Managers.package:load(path, ref, nil, true, true)
							end)
							if ok then
								_loaded[path] = true
								local resident = false
								pcall(function() resident = Managers.package:has_loaded(path, ref) and true or false end)
								printf("[cwv husk-override-residency] force-loaded %s (ref=%s, resident=%s, for=%s.%s)",
									path, ref, tostring(resident), tostring(d.item_key), field)
							else
								printf("[cwv husk-override-residency] FAILED to force-load %s (attempt %d/%d, for=%s.%s): %s",
									path, _attempts[path], _MAX_LOAD_ATTEMPTS, tostring(d.item_key), field, tostring(err))
							end
						end
					end
				end
			end
		end
		_cwv_husk_override_residency_ran = true
		_cwv_husk_override_paths = _loaded
	end

	_force_load_husk_override_units()

	-- #401 bounded retry: re-run the attempt-capped pass once at all-mods-loaded
	-- (re-attempts only FAILED loads); preserve the earlier handler at ~:3099.
	do local previous_on_all_mods_loaded = mod.on_all_mods_loaded
		function mod.on_all_mods_loaded()
			if previous_on_all_mods_loaded then previous_on_all_mods_loaded() end
			_force_load_husk_override_units()
		end
	end
end

-- ============================================================
-- Defensive guard: husk start_weapon_fx nil-slot crash  (Issue #280)
-- ============================================================
-- Belt-and-suspenders behind the force-load above. Even with the units
-- resident, another residency edge case (a hot-join before the load lands, a
-- DIFFERENT cross-char base whose units nobody preloaded, a mod load-order
-- gap) can still leave vanilla `_wield_slot` bailing before it sets
-- `equipment.wielded_slot` (simple_husk_inventory_extension.lua:775) — because
-- cosmetics_tweaker's `_wield_slot` wrap pcall-swallows the spawn fault. When
-- that happens, vanilla `start_weapon_fx` (line 790) indexes
-- `equipment.slots[equipment.wielded_slot]` with a nil slot name ->
-- `get_item_template(nil)` -> CLIENT CTD.
--
-- This wrapper no-ops the fx spawn when the wielded slot / slot_data is nil:
-- the weapon particle fx simply does not play that frame (cosmetic, never a
-- crash). Zero behavior change for the normal case (slot_data present ->
-- vanilla runs verbatim). This is general (protects ANY husk weapon, not just
-- the axe & shield), which is why it is the durable half of the fix.
--
-- HOOK PRE-FLIGHT (CLAUDE.md NON-NEGOTIABLE #8): grepped this file for
-- `SimpleHuskInventoryExtension` / `start_weapon_fx` hooks before adding this.
-- CWV's only other SimpleHuskInventoryExtension-class touch is none; the sole
-- pre-existing husk-adjacent hook is `BackendUtils.get_item_template`
-- (line ~3827, a different (Class, method)). This is the ONLY hook on
-- (SimpleHuskInventoryExtension, start_weapon_fx) in CWV.
mod:hook("SimpleHuskInventoryExtension", "start_weapon_fx", function(func, self, fx_name)
	local equipment = self and self._equipment
	local wielded_slot = equipment and equipment.wielded_slot
	local slot_data = wielded_slot and equipment.slots and equipment.slots[wielded_slot]
	if not slot_data then
		-- Log-only via engine `printf` (CLAUDE.md #9: user runs mod-logging
		-- OFF, so mod:info/mod:warning are invisible / chat-spammy). pcall so
		-- the diagnostic itself can never fault the wield path.
		pcall(function()
			printf("[cwv husk-fx-guard] SKIP start_weapon_fx: equipment.wielded_slot=%s slot_data=nil self.wielded_slot=%s career=%s fx=%s husk_unit=%s -- vanilla start_weapon_fx would CTD here (Issue #280); fx skipped, host+client stay alive",
				tostring(wielded_slot), tostring(self and self.wielded_slot),
				tostring(self and self._career_name), tostring(fx_name), tostring(self and self._unit))
		end)
		return
	end
	return func(self, fx_name)
end)
_cwv_husk_fx_guard_installed = true

_om._install_husk_residency_queries = function(_husk_log_once)
	-- ============================================================
	-- Residency truth + leases (fail-closed) -- issues 474/476/482/401
	-- ============================================================
	-- Direct engine resource truth, the weapons_of_chaos recipe
	-- (_woc_mod_unit_preview.lua:16-19 / _woc_blightreaper_pulse.lua:41-45):
	-- Application.can_get asks the resource system whether the resource is
	-- obtainable RIGHT NOW under any reference. Package-reference bookkeeping
	-- (has_loaded) can miss a resource another path already made resident, and
	-- a custom-bundle unit can be resident while its donor material is not.
	-- Returns true/false, or nil when the API is unavailable (offline tests).
	local function _resource_ready(kind, name)
		local app = rawget(_G, "Application")
		local can_get = app and app.can_get
		if type(can_get) ~= "function" then return nil end
		local ok, ready = pcall(can_get, kind, name)
		if not ok then return nil end
		return ready == true
	end
	_om._husk_resource_ready = _resource_ready   -- exposed for tests/regression

	-- Optional donor-material gate for future borrowed-material custom meshes.
	-- Old Musket was removed from this table by #1155: its .unit now binds the
	-- same CWV-owned material as every other self-contained imported family.
	-- Keeping a donor declaration would make remote husks depend on an unrelated
	-- vanilla Handgun package and would recreate the renderer-scope race.
	local _CUSTOM_UNIT_MATERIAL_DONORS = {}
	_om._husk_custom_unit_material_donors = _CUSTOM_UNIT_MATERIAL_DONORS
	local _donor_lease_attempted = {}
	_om._husk_material_donor_ready = function(base_unit)
		if type(base_unit) ~= "string" or base_unit == "" then return false end
		-- The husk spawn appends "_3p"; gate on the 3P donor form.
		local donor = _CUSTOM_UNIT_MATERIAL_DONORS[base_unit .. "_3p"]
			or _CUSTOM_UNIT_MATERIAL_DONORS[base_unit]
		if not donor then return true end   -- no donor declared: nothing to gate
		if _resource_ready("material", donor) == true then return true end
		-- FAIL-CLOSED (unknown counts as missing) + one bounded donor lease. The
		-- donor is a vanilla per-unit package (the same shape the boot force-load
		-- pass loads), NEVER the units/cwv_* path itself (#403 boot fatal).
		if Managers and Managers.package and not _donor_lease_attempted[donor] then
			_donor_lease_attempted[donor] = true
			local ok = pcall(function()
				Managers.package:load(donor, _om.HUSK_OVERRIDE_REF, nil, true, true)
			end)
			_husk_log_once("474_donor_lease:" .. donor,
				"[cwv:474] husk donor-material lease %s: %s (ref=%s) -- custom mesh kept BASE identity this wield (fail-closed residency)",
				ok and "queued" or "FAILED", donor, tostring(_om.HUSK_OVERRIDE_REF))
		end
		return false
	end

	-- (#476/#482) Bounded lease for a positively-identified vanilla override
	-- outside the def force-load set (pairing/illusion-skin units, crafted exact
	-- units): base identity renders this wield, the next wield finds it resident.
	local _override_lease_attempted = {}
	_om._husk_lease_override = function(base_unit)
		if type(base_unit) ~= "string" or base_unit == "" then return false end
		if base_unit:find("units/weapons/player/", 1, true) ~= 1 then return false end
		if base_unit:find("wpn_invisible_weapon", 1, true) then return false end
		if not (Managers and Managers.package) then return false end
		local queued = false
		for _, path in ipairs({ base_unit, base_unit .. "_3p" }) do
			if not _override_lease_attempted[path] then
				_override_lease_attempted[path] = true
				local ok = pcall(function()
					Managers.package:load(path, _om.HUSK_OVERRIDE_REF, nil, true, true)
				end)
				queued = queued or (ok == true)
				_husk_log_once("husk_lease:" .. path,
					"[cwv:476] husk override lease %s: %s (ref=%s) -- base identity kept this wield (fail-closed residency)",
					ok and "queued" or "FAILED", path, tostring(_om.HUSK_OVERRIDE_REF))
			end
		end
		return queued
	end

	-- #478 crash-floor residency predicate. Can vanilla spawn_inventory_unit spawn
	-- this unit's "_3p" form on THIS peer without an async C-assert? DISTINCT from
	-- _om._resident_override_3p (issue 418), which demands cwv's OWN force-load
	-- reference: the crash-floor only asks whether the resource is resident under
	-- ANY reference -- a naturally game-loaded base mesh counts (has_loaded with no
	-- reference_name returns the plain loaded flag, package_manager.lua:286-293).
	-- A cwv custom-bundle mesh (units/cwv_*) is unit-resident while the mod is
	-- loaded. Self-contained families pass immediately; any future mesh that
	-- explicitly borrows a foreign material routes through the donor gate. Used by the husk re-key to
	-- suppress a spawn that would otherwise error at gear_utils.lua:189
	-- (weapon_unit_name .. "_3p" over a missing package).
	_om._husk_unit_spawnable = function(base_unit)
		if type(base_unit) ~= "string" or base_unit == "" then return false end
		if _om._husk_custom_bundle_unit and _om._husk_custom_bundle_unit(base_unit) then
			-- (#719) The donor gate is the ONLY variable for a mod-bundle mesh.
			-- Unit residency is structural: these paths ship in CWV's master
			-- package, which VMF loads with the mod, so this code cannot run while
			-- they are absent -- and asking the global resource system about a
			-- Workshop bundle path is exactly the lookup that does not answer
			-- reliably. A mesh that borrows a foreign material still fails closed
			-- on that material; self-contained Old Musket/Greataxe/Crowbill units
			-- declare no donor and pass.
			return _om._husk_material_donor_ready(base_unit)
		end
		local ready = _resource_ready("unit", base_unit .. "_3p")
		if ready ~= nil then return ready end
		if not (Managers and Managers.package) then return false end
		local ok, res = pcall(Managers.package.has_loaded, Managers.package, base_unit .. "_3p")
		return ok and res == true
	end

	-- (#237/#419) Preview-time resolved-3p gate for the two solo-keep preview
	-- adapters (_cwv_preview_meshswap_apply "hand_flags" and
	-- _cwv_browser_meshswap_apply "base_identity" in the entry).
	-- _om._resident_override_3p demands HUSK_OVERRIDE_REF residency, which only
	-- the boot force-load pass and the husk leases above (:379/:402) establish --
	-- outside that set the old adapter call sites collapsed a nil resolver answer
	-- into a blind `base .. "_3p"` spawn target, silently voiding the documented
	-- degrade-to-base contract (entry :8900-:8907). This predicate keeps the husk
	-- resolver's answer when it speaks (co-op unchanged) and otherwise applies the
	-- #478 crash floor above (_om._husk_unit_spawnable, incl. the optional #474
	-- donor-material gate for explicitly borrowed custom meshes). Old Musket's
	-- self-contained material closure can no longer reach World.spawn_unit with an unresolved donor through
	-- a preview). Decision shape is pure and shared with the offline lock:
	-- exact_appearance.resolve_preview_3p. _om fields are read at CALL time so
	-- entry-load order stays irrelevant.
	_om._preview_override_3p = function(base_unit)
		return _om.exact_appearance.resolve_preview_3p(base_unit,
			_om._resident_override_3p, _om._husk_unit_spawnable)
	end
	return _resource_ready
end

end

return install
