-- _cwv_husk_path.lua — cross-character husk display + transform + ledger machinery
--
-- Owns the husk-side (remote-player) appearance resolution for CWV variants: the
-- mesh re-key / handedness preselection (#474/#475/#478), the no_ammo_unit
-- ammo-strip (#399), the scale/offset transform apply (#397/#394/#604), the
-- stale-override-unit ledger + supersession drain (#395), and the #660 huskpath
-- postcondition log. All logic is assigned onto the shared `mod._om` namespace as
-- `_om._husk_*` fields; the husk-reaching hooks reach these helpers through the
-- `_om` upvalue at call time. GearUtils.spawn_inventory_unit and
-- SimpleHuskInventoryExtension._wield_slot stay in the entry;
-- SimpleHuskInventoryExtension.start_weapon_fx moved to
-- _cwv_husk_residency_owner with the #280 force-loads it backs up (#1159), and
-- reaches nothing here. Pure structural
-- extraction (OOP W5, PROJECT_STANDARDS §2.2a) — no behavior change; every printf
-- marker is byte-identical to its pre-split form.
--
-- Owned by: character_weapon_variants.lua entry point. Consumed via: mod:dofile —
-- dofiled at the husk-apply-helpers position so its file-local dependencies
-- (_variant_definitions, _find_def, _is_unit, _apply_cwv_hand_transform,
-- _triplet_text) are already defined in the entry when it runs.
return function(mod, ctx)
	local _om = ctx.om
	local _variant_definitions = ctx.variant_definitions
	local _find_def = ctx.find_def
	local _is_unit = ctx.is_unit
	local _apply_cwv_hand_transform = ctx.apply_cwv_hand_transform
	local _triplet_text = ctx.triplet_text

-- ============================================================
-- Husk apply helpers  (issues 397/394/399) — assigned onto `_om`
-- ============================================================
-- These run from the GearUtils.spawn_inventory_unit hook (~line 4525, the
-- husk-reaching path). They are DEFINED here — below `_transform_unit`,
-- `_resolve_field`, `_resolve_cwv_def`, `_is_unit` — because Lua locals are
-- only visible after their declaration point; the hook above can't see these
-- helpers directly, so it reaches them through the `_om` upvalue table
-- (declared near the top of the file), whose fields are populated at load
-- time before any in-mission spawn. See the husk block in that hook.
do
	-- issue 399 lookup: base_weapon -> career-set for every no_ammo_unit
	-- variant. On the husk the item resolves to the BASE item_data (name =
	-- base weapon), so backend_id/skin/cwv markers are unreliable. But the
	-- variant's base weapon on a career that CANNOT natively wield it is a
	-- husk-reliable POSITIVE signal (e.g. dr_deus_01 is Bardin-exclusive, so a
	-- non-dwarf wielding it can only be the CWV Outrider). We gate strictly on
	-- (item_data.name == base_weapon) AND (career in the variant's own careers
	-- list) so a genuine dwarf wielding the real Trollhammer is never touched.
	local _no_ammo_careers_by_base = {}
	for _, def in ipairs(_variant_definitions) do
		if def.no_ammo_unit and type(def.base_weapon) == "string" then
			local set = _no_ammo_careers_by_base[def.base_weapon] or {}
			for _, c in ipairs(def.careers or {}) do set[c] = true end
			_no_ammo_careers_by_base[def.base_weapon] = set
		end
	end
	-- Exposed for the `cwv_no_ammo_strip_coverage` regression test, which
	-- asserts every no_ammo_unit def contributes its base + careers here.
	_om._no_ammo_careers_by_base = _no_ammo_careers_by_base

	-- issues 396/397/401 husk display resolution, restructured for #474/#475.
	--
	-- RESOLUTION ORDER (the husk display contract -- WEAPON_APPEARANCE_STANDARD §3):
	--   1. WIRE SKIN, PRIMARY (positive identity): a skin in either cwv skin
	--      namespace (base "<item_key>_skin" or pairing "<item_key>_<tail>")
	--      positively identifies the variant -> re-key REGARDLESS of can_wield.
	--      #474 root: vanilla es_handgun.can_wield includes es_mercenary, so the
	--      can_wield-excluded (base,career) map could never fire for the Old
	--      Musket even though the wire skin named it outright.
	--   2. A present NON-cwv skin = native item (or foreign illusion): NEVER
	--      re-key. #475 Invariant 1: mis-applying a variant to a native weapon
	--      is strictly worse than a variant degrading to its base display.
	--   3. SKINLESS echo only: (base,career) fallback, with can_wield evaluated
	--      LAZILY at wield time. #475 root: the old boot-time snapshot ran
	--      before weapon_tweaker expanded can_wield, so a wt-freedom native
	--      wield (host mercenary + native Bretonnian LS&S) matched the map and
	--      got re-keyed to the cwv variant. If the career can CURRENTLY wield
	--      the base (vanilla or wt), the skinless shape is ambiguous -> show
	--      base; a genuine variant's skinned wield still re-keys via arm 1.
	--
	-- The claims map is UNFILTERED (no build-time can_wield exclusion -- that is
	-- now the lazy check), deduped so an ambiguous (base,career) resolves to nil.
	local _husk_def_by_base_career = {}
	do
		local _seen = {}   -- "base|career" -> def, or false once ambiguous
		for _, def in ipairs(_variant_definitions) do
			local base = def.base_weapon
			if type(base) == "string" then
				for _, career in ipairs(def.careers or {}) do
					if type(career) == "string" then
						local k = base .. "|" .. career
						local slot = _husk_def_by_base_career[base]
						if not slot then slot = {}; _husk_def_by_base_career[base] = slot end
						if _seen[k] == nil then
							_seen[k] = def
							slot[career] = def
						elseif _seen[k] ~= def then
							_seen[k] = false          -- two variants share (base, career): ambiguous
							slot[career] = nil
						end
					end
				end
			end
		end
	end
	_om._husk_def_by_base_career = _husk_def_by_base_career   -- exposed for regression

	-- Lazy native check (#475): reads the CURRENT ItemMasterList[base].can_wield
	-- at husk-wield time, so weapon_tweaker's runtime expansion (wt is the last
	-- writer of can_wield, re-applied on game-state transitions) is respected no
	-- matter the boot order. Unknown/malformed -> native (decline re-key;
	-- conservative toward Invariant 1). Assigned to _om (not a local): this
	-- chunk sits at the Lua 5.1 200-local ceiling.
	_om._husk_pair_native_now = function(base_key, career)
		local base = rawget(ItemMasterList, base_key)
		local cw = type(base) == "table" and base.can_wield
		if type(cw) ~= "table" then return true end
		for _, c in ipairs(cw) do if c == career then return true end end
		return false
	end

	-- (#474) Skin -> variant-def identity lookup covering the two def-keyed cwv
	-- skin namespaces:
	--   * base variant skins  "<item_key>_skin"  -- seeded eagerly below;
	--   * pairing/illusion skins "<item_key>_<tail>" (e.g. cwv_es_longsword_
	--     shield_wpn_emp_shield_03_runed_01__nordland) -- resolved lazily by
	--     longest-prefix match (they register in _register_*_illusions AFTER
	--     this chunk runs) and cached, so the wield path stays allocation-free.
	-- KNOWN NON-MEMBERS (correct declines, do not "fix"): the cross-source
	-- illusion families named outside any def's item_key -- cwv_il_es_* /
	-- cwv_il_wh_* (Imperial Longsword) and cwv_es_priest_es_* / cwv_es_priest_
	-- wh_* (Sigmarite Greathammer). Their skin data carries the source mesh, so
	-- vanilla already renders them; they need no re-key and no def transforms
	-- (none registered), and on the anomalous base-reverted shape they degrade
	-- to base display per Invariant 2.
	-- Deliberately separate from _skin_transform_map: that map is gated on
	-- transform registration and also holds synthetic custom-illusion defs
	-- (transform-only, no base_weapon) that must never drive a mesh re-key.
	-- Cache stores false as the negative for a cwv_-prefixed non-variant skin;
	-- non-cwv skins return nil without touching the cache (no unbounded growth).
	_om._husk_skin_def_cache = {}
	for _, def in ipairs(_variant_definitions) do
		if type(def.item_key) == "string" and not def.no_skin then
			_om._husk_skin_def_cache[def.item_key .. "_skin"] = def
		end
	end
	_om._husk_skin_def = function(skin)
		if type(skin) ~= "string" then return nil end
		local cache = _om._husk_skin_def_cache
		local hit = cache[skin]
		if hit ~= nil then return hit or nil end
		if skin:sub(1, 4) ~= "cwv_" then return nil end
		local best, best_len = false, 0
		for _, def in ipairs(_variant_definitions) do
			local ik = def.item_key
			if type(ik) == "string" and #ik > best_len
					and skin:sub(1, #ik + 1) == ik .. "_" then
				best, best_len = def, #ik
			end
		end
		cache[skin] = best
		return best or nil
	end

	-- SINGLE husk display decision point (#474/#475): the mesh re-key AND the
	-- transform fallback both route through this so they can never disagree.
	-- Returns def, reason. Resolve reasons: "skin" | "base_career". Decline
	-- reasons (nil def): "skin_foreign" (non-cwv skin = native, Invariant 1) |
	-- "skin_base_mismatch" (defensive: skin and wire item disagree) |
	-- "native_pair" (skinless + pair currently wieldable) | "no_pair".
	_om._husk_resolve_display_def = function(base_name, career, skin)
		if skin ~= nil then
			local def = _om._husk_skin_def(skin)
			if not def then return nil, "skin_foreign" end
			if type(def.base_weapon) == "string" and base_name ~= nil
					and def.base_weapon ~= base_name then
				return nil, "skin_base_mismatch"
			end
			return def, "skin"
		end
		if not (base_name and career) then return nil, "no_pair" end
		local slot = _husk_def_by_base_career[base_name]
		local def = slot and slot[career]
		if not def then return nil, "no_pair" end
		if _om._husk_pair_native_now(base_name, career) then return nil, "native_pair" end
		return def, "base_career"
	end

	-- Set of every CWV base_weapon key — used only to scope the "no def
	-- resolved" husk diagnostic so it doesn't spam on the common native-weapon
	-- wield case (fires only for weapons whose base a CWV variant clones).
	local _cwv_base_weapons = {}
	for _, def in ipairs(_variant_definitions) do
		if type(def.base_weapon) == "string" then _cwv_base_weapons[def.base_weapon] = true end
	end

	-- Once-per-key throttle for the defensive husk diagnostics below. A husk
	-- weapon spawns on every wield, so an un-throttled printf on a silent-return
	-- path would spam the log each swap/frame. Key by a stable string (reason +
	-- base + hand) so each distinct silent-return reason surfaces exactly once,
	-- giving the next paired peer log the "why a variant didn't get its apply"
	-- evidence without the noise (task 5 defensive-logging requirement).
	local _husk_logged_once = {}
	local function _husk_log_once(key, fmt, ...)
		if _husk_logged_once[key] then return end
		_husk_logged_once[key] = true
		printf(fmt, ...)
	end

	-- General (non-Crowbill) husk evidence keeps its own budget. Exact Crowbill
	-- generations are sampled next tick by the dedicated #604 evidence owner, so
	-- unrelated CWV weapons can never consume that issue's diagnostic capacity.
	local _HUSK_GENERAL_RETAINED_LOG_LIMIT = 64
	local _husk_retained_seen = {}
	local _husk_retained_diag = {
		limit = _HUSK_GENERAL_RETAINED_LOG_LIMIT,
		count = 0,
	}
	_om._cwv_husk_retained_diag = _husk_retained_diag

	-- (#399 candidate B) Husk career lookup, two sources in priority order:
	--   1. `career_system` extension `:career_name()` -- the live authority.
	--   2. `inventory_system._career_name` -- the husk inventory extension caches
	--      the career at init (simple_husk_inventory_extension.lua:39/52, set from
	--      `player:career_name()` BEFORE extensions_ready runs our hooks), so it is
	--      populated on the exact seam the husk ammo/mesh adapters run on even when
	--      the career extension is not yet resolvable on this peer.
	-- A nil career fails the (base, career) strip gate, which is how #399's
	-- inherited torpedo survived on the remote view: candidate B of the two live
	-- holes. Both reads use ScriptUnit.has_extension (a pure Entities[unit] table
	-- lookup, script_unit.lua:72 -> local_extension) and stay pcall-safe.
	local function _husk_career_name(owner_unit_3p)
		if not owner_unit_3p then return nil end
		local name
		pcall(function()
			if ScriptUnit.has_extension(owner_unit_3p, "career_system") then
				name = ScriptUnit.extension(owner_unit_3p, "career_system"):career_name()
			end
		end)
		if type(name) ~= "string" or name == "" then
			name = nil
			pcall(function()
				local inv = ScriptUnit.has_extension(owner_unit_3p, "inventory_system")
				local cached = inv and inv._career_name
				if type(cached) == "string" and cached ~= "" then name = cached end
			end)
		end
		return name
	end
	-- Exposed so the husk ammo arms resolve the career through one swappable
	-- seam (the issue399_outrider_husk_ammo_adapter regression drives it) and so
	-- a future module can reuse the hardened lookup instead of re-deriving it.
	_om._husk_career_name = _husk_career_name

	-- #474/#660 atomic hand-selection admission. Preselection runs before
	-- vanilla decides which hand spawns exist, so writing an unspawnable custom
	-- unit here cannot be repaired by the later re-key guard: the crash-floor
	-- sees the already-written custom path and suppresses that hand, leaving the
	-- whole weapon invisible. Admit every authored hand as one transaction or
	-- preserve the untouched vanilla table for this wield. The spawnability
	-- predicate also queues the Old Musket's donor-material lease; ordinary
	-- vanilla overrides additionally use the bounded override lease.
	local function _husk_preselection_ready(candidate, source)
		for _, field in ipairs({ "right_hand_unit", "left_hand_unit" }) do
			local unit_name = candidate and candidate[field]
			if type(unit_name) == "string" and unit_name ~= ""
					and (not _om._husk_unit_spawnable
						or not _om._husk_unit_spawnable(unit_name)) then
				if _om._husk_lease_override then
					_om._husk_lease_override(unit_name)
				end
				local wield_ctx = _om._appearance_husk_wield_context
				if wield_ctx then
					wield_ctx.hand_selection_deferred = true
					wield_ctx.hand_selection_source = source
				end
				_husk_log_once("474_preselect_defer:" .. tostring(source) .. ":" .. field
						.. ":" .. unit_name,
					"[cwv:474/660] lifecycle=husk_wield adapter=hand_selection deferred source=%s hand=%s unit=%s base_preserved=true -- residency not proven",
					tostring(source), tostring(field), tostring(unit_name))
				return false
			end
		end
		return true
	end
	_om._husk_preselection_ready = _husk_preselection_ready

	-- #478 handedness preselection. SimpleHuskInventoryExtension._wield_slot
	-- asks BackendUtils for the unit table and THEN decides which per-hand
	-- GearUtils.spawn_inventory_unit calls exist (simple_husk_inventory_extension
	-- .lua:662-670). The later _husk_rekey_units hook cannot move a skinless
	-- cross-character variant from the base weapon's hand to the authored hand:
	-- for Outrider, vanilla has already scheduled only dr_deus_01's LEFT call,
	-- while the variant is a RIGHT-mounted blunderbuss with no left unit.
	--
	-- Rewrite the unit table at the upstream decision seam, but only for the same
	-- conservative skinless base+career identity accepted by the shared husk
	-- resolver. A backend id or any skin is stronger identity owned by another
	-- path and is left untouched. The later residency re-key/crash-floor remains
	-- authoritative over whether the selected unit is actually safe to spawn.
	_om._husk_preselect_units = function(result, item_data, backend_id, skin, career_name)
		local effective_backend_id = (item_data and item_data.backend_id) or backend_id
		if type(result) ~= "table" or effective_backend_id ~= nil then return false end
		local resolved_skin = result.skin or skin
		if resolved_skin ~= nil and resolved_skin ~= "" then return false end
		local base_name = item_data and item_data.name
		local ctx = _om._appearance_husk_wield_context
		local exact, exact_state
		if ctx and _om._husk_identity_descriptor then
			exact, exact_state = _om._husk_identity_descriptor(
				ctx.owner_unit_3p, ctx.slot_name, base_name)
		end
		if exact_state == "exact" and exact then
			if not _husk_preselection_ready(exact, exact.fingerprint or exact.variant_key) then
				return false
			end
			if type(exact.right_hand_unit) == "string" then
				result.right_hand_unit = exact.right_hand_unit
			end
			if type(exact.left_hand_unit) == "string" then
				result.left_hand_unit = exact.left_hand_unit
			else
				result.left_hand_unit = nil
			end
			_husk_log_once("660_preselect:" .. tostring(exact.fingerprint),
				"[cwv:660] lifecycle=husk_wield adapter=hand_selection descriptor=%s right=%s left=%s",
				tostring(exact.fingerprint), tostring(exact.right_hand_unit),
				tostring(exact.left_hand_unit))
			return true, _find_def(exact.variant_key), exact
		elseif exact_state and exact_state ~= "none" then
			-- Explicit native, unavailable-provider, or stale-slot evidence is
			-- stronger than the legacy base+career guess. Preserve vanilla units.
			return false
		end
		local def, reason = _om._husk_resolve_display_def(base_name, career_name, nil)
		if not def or reason ~= "base_career" then return false end
		if not _husk_preselection_ready(def, def.item_key or base_name) then return false end

		if type(def.right_hand_unit) == "string" and def.right_hand_unit ~= "" then
			result.right_hand_unit = def.right_hand_unit
		end
		if def.no_left_hand then
			result.left_hand_unit = nil
		elseif type(def.left_hand_unit) == "string" and def.left_hand_unit ~= "" then
			result.left_hand_unit = def.left_hand_unit
		end

		_husk_log_once("478_preselect:" .. tostring(base_name) .. ":" .. tostring(career_name),
			"[cwv:478] husk preselected hands before vanilla spawn branching: base=%s career=%s def=%s right=%s left=%s",
			tostring(base_name), tostring(career_name), tostring(def.item_key),
			tostring(result.right_hand_unit), tostring(result.left_hand_unit))
		return true, def
	end

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

	-- (#474 crash killer) Custom-bundle meshes reference a VANILLA material via
	-- the .unit's `data.mat_to_use` (LA-pattern block in the entry). The unit
	-- data is mod-resident, but the DONOR material lives in the vanilla weapon
	-- package -- spawning the custom mesh while that package is absent on this
	-- peer is the console-2026-07-18-03.56.47 AV: `[MeshObject] Failed looking
	-- up material #ID[b6d0945a]` inside GearUtils.spawn_inventory_unit. Gate
	-- every custom-mesh husk write on donor-material residency; on a miss KEEP
	-- the base identity (wrong-but-stable, never crash) and package-lease the
	-- donor (weapons_of_chaos Managers.package:load lease recipe,
	-- _woc_mod_unit_preview.lua:100) so a later wield of this slot resolves.
	local _CUSTOM_UNIT_MATERIAL_DONORS = {
		["units/cwv_es_musket_custom/cwv_es_musket_custom"] =
			"units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1",
		["units/cwv_es_musket_custom/cwv_es_musket_custom_3p"] =
			"units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1_3p",
	}
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
	-- loaded, but #474 fail-closed: its vanilla donor MATERIAL must also be
	-- resident, else spawning it is the MeshObject AV -- so it routes through the
	-- donor gate instead of an unconditional accept. Used by the husk re-key to
	-- suppress a spawn that would otherwise error at gear_utils.lua:189
	-- (weapon_unit_name .. "_3p" over a missing package).
	_om._husk_unit_spawnable = function(base_unit)
		if type(base_unit) ~= "string" or base_unit == "" then return false end
		if _om._husk_custom_bundle_unit and _om._husk_custom_bundle_unit(base_unit) then
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
	-- #478 crash floor above (_om._husk_unit_spawnable, incl. the #474
	-- donor-material gate for units/cwv_* custom meshes -- the Old Musket's
	-- MeshObject-AV class can no longer reach World.spawn_unit unguarded through
	-- a preview). Decision shape is pure and shared with the offline lock:
	-- exact_appearance.resolve_preview_3p. _om fields are read at CALL time so
	-- entry-load order stays irrelevant.
	_om._preview_override_3p = function(base_unit)
		return _om.exact_appearance.resolve_preview_3p(base_unit,
			_om._resident_override_3p, _om._husk_unit_spawnable)
	end

	-- Husk MESH re-key (issues 396/401, restructured for #474/#475). Runs BEFORE
	-- the vanilla spawn (the caller mutates item_units in place). Resolution
	-- order + invariants: the RESOLUTION ORDER block above; the actual decision
	-- is _om._husk_resolve_display_def, shared with the transform apply so mesh
	-- and transform can never disagree.
	--
	-- Write guards, in order:
	--   * For a skin-resolved def the skin template's OWN per-hand unit wins
	--     over the def default -- pairing skins carry their exact combination
	--     (e.g. a Nordland-shield pairing) and the def default would stomp it.
	--   * Residency (issue 403 crash-floor): a vanilla override must be
	--     force-loaded resident (shared _om._resident_override_3p, issue 418);
	--     a mod-bundled custom mesh (the Old Musket) is accepted via
	--     _om._husk_custom_bundle_unit instead (always resident in cwv's own
	--     bundle, and deliberately REJECTED by the vanilla-prefix resident
	--     guard -- force-loading it is the issue 403 boot fatal).
	--   * Idempotent and fail-safe: decline/no-op leaves item_units untouched
	--     (vanilla then spawns whatever the skin data already put there).
	_om._husk_rekey_units = function(hand, item_data, item_units, owner_unit_3p, slot_name)
		if not (item_data and item_units) then return end
		local base_name = item_data.name
		if not base_name then return end
		local skin = item_units.skin
		local career = _husk_career_name(owner_unit_3p)
		local exact, identity_state
		if _om._husk_identity_descriptor then
			exact, identity_state = _om._husk_identity_descriptor(owner_unit_3p, slot_name, base_name)
		end
		if identity_state and identity_state ~= "none" and identity_state ~= "exact" then
			-- A sender explicitly proved this slot native, or its exact provider
			-- descriptor is unavailable locally. Never replace that evidence with
			-- the ambiguous base+career heuristic.
			return
		end
		local def = exact and _find_def(exact.variant_key)
		local reason = def and "identity" or nil
		if exact and exact.skin then skin = exact.skin end
		if not def then def, reason = _om._husk_resolve_display_def(base_name, career, skin) end
		if not def then
			-- Decision diagnostics (#474/#475), scoped to bases a cwv variant
			-- clones so common native wields don't spam; once per shape.
			if _cwv_base_weapons[base_name] then
				if reason == "skin_foreign" or reason == "skin_base_mismatch" then
					-- Wording split: cwv_-prefixed skins that don't resolve are the
					-- known cross-source illusion families outside the <item_key>_
					-- namespaces (cwv_il_*, cwv_es_priest_es/wh_*) -- genuinely cwv,
					-- display-complete via their skin data, correctly not re-keyed;
					-- don't label them native (log-triage accuracy, review finding).
					local skin_is_cwv = type(skin) == "string" and skin:sub(1, 4) == "cwv_"
					_husk_log_once("475_skin_decline:" .. tostring(base_name) .. ":" .. tostring(career) .. ":" .. tostring(skin),
						skin_is_cwv
							and "[cwv:475] husk re-key declined (%s): base=%s career=%s skin=%s -- cwv skin outside the <item_key>_ namespaces (cross-source illusion family); skin data already drives its display, no re-key"
							or  "[cwv:475] husk re-key DECLINED (%s): base=%s career=%s skin=%s -- non-cwv skin = native item, never re-key (Invariant 1)",
						tostring(reason), tostring(base_name), tostring(career), tostring(skin))
				elseif reason == "native_pair" then
					_husk_log_once("475_native_pair:" .. tostring(base_name) .. ":" .. tostring(career) .. ":" .. tostring(hand),
						"[cwv:475] husk re-key DECLINED (native_pair): base=%s career=%s -- skinless echo and the pair is currently wieldable (vanilla or wt); ambiguous shows base, a skinned wield still re-keys",
						tostring(base_name), tostring(career))
				else
					_husk_log_once("474_no_pair:" .. tostring(base_name) .. ":" .. tostring(career) .. ":" .. tostring(hand),
						"[cwv:474] husk re-key no def (%s): base=%s career=%s skin=nil -- skinless echo without an unambiguous (base,career) claim",
						tostring(reason), tostring(base_name), tostring(career))
				end
			end
			return
		end
		local field = (hand == "right") and "right_hand_unit" or "left_hand_unit"
		local override
		if reason == "identity" and exact then
			override = exact[field]
		elseif reason == "skin" and WeaponSkins and WeaponSkins.skins then
			local skin_tmpl = rawget(WeaponSkins.skins, skin)
			local skin_unit = skin_tmpl and skin_tmpl[field]
			if type(skin_unit) == "string" and skin_unit ~= "" then override = skin_unit end
		end
		if override == nil then override = def[field] end
		if type(override) == "string" and override ~= "" and item_units[field] ~= override then
			-- Residency admissibility (FAIL-CLOSED, #474/#403/#418): we write the
			-- BASE-form path, vanilla spawn_inventory_unit appends "_3p".
			--   * custom-bundle mesh: unit data is mod-resident, but its vanilla
			--     donor MATERIAL must be resident too (#474 MeshObject AV killer);
			--   * force-loaded vanilla override (HUSK_OVERRIDE_REF, issue 418):
			--     admissible unless the engine positively denies the resource;
			--   * any other vanilla override (pairing-skin / crafted exact units
			--     outside the def force-load set, #476/#482): admissible only on
			--     direct engine proof (Application.can_get); on a miss KEEP the
			--     base identity this wield and queue a bounded lease.
			local admissible
			if _om._husk_custom_bundle_unit and _om._husk_custom_bundle_unit(override) then
				admissible = _om._husk_material_donor_ready(override)
			elseif _om._resident_override_3p and _om._resident_override_3p(override) then
				admissible = _resource_ready("unit", override .. "_3p") ~= false
			else
				admissible = _resource_ready("unit", override .. "_3p") == true
				if not admissible and _om._husk_lease_override then
					_om._husk_lease_override(override)
				end
			end
			if admissible then
				item_units[field] = override
				_husk_log_once("474_rekey:" .. tostring(base_name) .. ":" .. tostring(career) .. ":" .. tostring(hand) .. ":" .. tostring(skin),
					"[cwv:474] husk re-keyed hand=%s base=%s career=%s via %s (skin=%s) -> %s",
					tostring(hand), tostring(base_name), tostring(career), tostring(reason), tostring(skin), tostring(override))
			else
				-- Override not cwv-resident: cannot re-key to it. Leave the base
				-- leftover in item_units and fall through to the #478 crash-floor,
				-- which suppresses the spawn if that leftover is itself non-resident.
				_husk_log_once("474_residency:" .. tostring(override) .. ":" .. tostring(hand),
					"[cwv:474] husk re-key DEFERRED (residency): hand=%s base=%s def=%s override=%s not resident -- showing base this wield (issue 403 crash-floor)",
					tostring(hand), tostring(base_name), tostring(def.item_key), tostring(override))
			end
		end
		-- #478 crash-floor (residency-gated defer): whatever now sits in
		-- item_units[field] is what vanilla spawn_inventory_unit will spawn -- the
		-- re-keyed override above, an idempotent pre-applied skin unit, or the base
		-- leftover for a hand the variant does NOT override (e.g. the Outrider's
		-- no_left_hand keeps dr_deus_01's Deus-only Trollhammer left-mount). If that
		-- unit is NON-RESIDENT on this peer, vanilla errors at gear_utils.lua:189
		-- (weapon_unit_name .. "_3p" over a missing package -> entity_manager2.lua:114
		-- "table index is nil" -> invisible wield; async C-assert risk on a
		-- harder-missing package, BUG_CLASSES 28). Return SUPPRESS=true so the spawn
		-- hook skips the vanilla call for THIS hand -- fail-safe (no mesh this hand,
		-- never force-load mid-mission). A non-resident mesh cannot render anyway, so
		-- suppressing removes only a crash, never a visible unit. Bounded to a
		-- resolved cwv def, so a genuine native wield is never touched (#475 Inv. 1).
		local final_unit = item_units[field]
		if type(final_unit) == "string" and final_unit ~= "" and not _om._husk_unit_spawnable(final_unit) then
			pcall(_husk_log_once, "478_defer:" .. tostring(base_name) .. ":" .. tostring(hand) .. ":" .. tostring(final_unit),
				"[cwv:478] husk DEFER: hand=%s base=%s career=%s def=%s -- NON-RESIDENT spawn unit %s suppressed (would crash vanilla spawn); no mesh this hand (fail-safe, no force-load)",
				tostring(hand), tostring(base_name), tostring(career), tostring(def.item_key), tostring(final_unit))
			return true
		end
	end

	-- Returns true if it stripped a torpedo/ammo unit (caller then nils its
	-- returned ammo_unit_3p so the husk equipment stops tracking it).
	--
	-- issue 399 (DESCRIPTOR-PRIMARY, restructured for #660): the strip is a
	-- CWV-POSITIVE identity decision, resolved through the SAME evidence the mesh
	-- re-key and transform husk adapters use so the ammo concern can never
	-- disagree with them (WEAPON_APPEARANCE_STANDARD §2 -- one source of truth per
	-- render path). Order:
	--   1. EXACT identity descriptor (#660, strongest): a proven CWV instance's
	--      def decides -- strip iff `def.no_ammo_unit`, never otherwise. An
	--      explicitly-native / unavailable-provider / stale-slot state DECLINES
	--      (never touch a genuine vanilla ammo weapon -- #475 Invariant 1).
	--   2. SKINLESS base+career fallback: the (base_weapon, career) positive
	--      signal (a career that cannot natively wield the ammo base can only be a
	--      CWV variant). This is descriptor evidence, NOT a bare `item_key` guess.
	-- A bare base-key match alone is never sufficient (a real dwarf Trollhammer
	-- shares the base name on the husk).
	--
	-- DESCRIPTOR-STATE POLICY (#399 fix, 2026-08-07). The gate used to decline on
	-- EVERY non-exact/non-none state, which put the ammo concern behind the same
	-- switch as the mesh re-key and the #398 clone template: one descriptor
	-- decline collapsed all of them, and the husk fell back to complete vanilla
	-- dr_deus_01 resolution -- the reported "no animation, no model, torpedo
	-- sticking out" triple. The ammo decision does not need the descriptor:
	--   * "native"                -> HARD DECLINE. The sender explicitly proved a
	--                                native wielder; #475 Invariant 1 says never
	--                                touch a genuine vanilla ammo weapon.
	--   * "unavailable"/"stale_base" -> FALL THROUGH to the base+career fallback.
	--                                Absent/mismatched provider evidence is no
	--                                evidence, and the fallback carries its own
	--                                positive proof (a career that cannot natively
	--                                wield the ammo base).
	--   * "exact"                 -> the resolved def decides (strip iff no_ammo_unit).
	--   * "none"                  -> base+career fallback (unchanged).
	-- Safety: `_no_ammo_careers_by_base` is career-scoped and the two contributing
	-- bases are disjoint from their vanilla can_wield sets -- dr_deus_01 admits
	-- only dr_ironbreaker (item_master_list_morris.lua:23-25) and wh_fencing_sword
	-- only wh_bountyhunter/wh_captain/wh_zealot
	-- (item_master_list_exported.lua:7574-7578), while both no_ammo_unit defs list
	-- es_* careers only. A real Bardin Trollhammer can never enter the strip set.
	_om._husk_strip_cwv_ammo = function(item_data, owner_unit_3p, ammo_unit_3p, slot_name)
		if not (item_data and ammo_unit_3p) then return false end
		local base_name = item_data.name
		local why, career

		-- (1) exact identity descriptor -- authoritative when present.
		local exact, identity_state
		if _om._husk_identity_descriptor then
			exact, identity_state = _om._husk_identity_descriptor(owner_unit_3p, slot_name, base_name)
		end
		if identity_state == "native" then
			-- Sender proved this slot native: never strip a real ammo weapon.
			return false
		end
		if exact then
			local edef = _find_def(exact.variant_key)
			if edef then
				-- Proven CWV instance: its def decides. A non-`no_ammo_unit` variant
				-- KEEPS its ammo -- the descriptor overrules base+career; do not strip.
				if edef.no_ammo_unit then why = "descriptor" else return false end
			end
			-- edef nil: exact key is unknown locally (schema drift). Fall through to
			-- base+career, mirroring the mesh re-key adapter so the two never disagree.
		end
		if not why then
			-- (2) skinless base+career fallback.
			local careers = base_name and _no_ammo_careers_by_base[base_name]
			if not careers then return false end
			career = (_om._husk_career_name or _husk_career_name)(owner_unit_3p)
			if not (career and careers[career]) then
				-- The base IS a no_ammo variant's base (careers table present), but
				-- the wielder's career isn't in the strip set. Two possibilities: a
				-- genuine native wielder of the real ammo weapon (correct no-strip),
				-- or a husk career-lookup miss (career=nil) that WOULD have stripped.
				-- Log once per (base, career) so a miss is visible in the paired log
				-- instead of silently leaving the inherited torpedo attached.
				_husk_log_once("ammo_career_miss:" .. tostring(base_name) .. ":" .. tostring(career),
					"[cwv husk-ammo-strip] SKIP: base=%s is a no_ammo variant base but career=%s not in strip set -- native wielder OR husk career-lookup miss (issue 399 diag)",
					tostring(base_name), tostring(career))
				return false
			end
			why = "base_career"
		end

		-- `_is_unit` is a typed predicate (userdata + Unit.alive, _cwv_peer_resolver
		-- .lua:9-14), so a non-unit handle can never reach the engine calls below.
		-- The strip DECISION still reports true: the caller nils its captured
		-- ammo return either way, and the regression drives this arm with a
		-- sentinel handle.
		local alive = _is_unit(ammo_unit_3p)
		if alive then
			pcall(Unit.set_unit_visibility, ammo_unit_3p, false)
			if Managers and Managers.state and Managers.state.unit_spawner then
				pcall(function() Managers.state.unit_spawner:mark_for_deletion(ammo_unit_3p) end)
			end
		end
		printf("[cwv husk-ammo-strip] stripped inherited ammo 3P unit (base=%s career=%s via=%s) -- issue 399",
			tostring(base_name), tostring(career), tostring(why))
		return true
	end

	-- ============================================================
	-- issue 395: stale husk override-unit ledger + supersession drain
	-- ============================================================
	-- A weapon slot renders exactly ONE 3P unit per hand, so when a husk RE-SPAWNS
	-- a slot's hand (re-equip, loadout resync, or a mission-transition respawn) the
	-- previously spawned override unit for that same (owner, slot, hand) is
	-- definitively superseded. Vanilla `GearUtils.destroy_equipment` normally
	-- frees it, but a custom-template variant -- the `no_left_hand` Rapier
	-- (item key cwv_es_rapier) is the reported #395 case -- can leave the
	-- prior cross-character override alive, so it "bleeds into" the newly-equipped
	-- weapon on the remote view. We record every CWV-resolved husk override unit
	-- per (owner, slot, hand) and, on the next record for that key, release the
	-- prior unit if it is STILL ALIVE (a leak). mark_for_deletion + hide mirrors
	-- the ammo-strip discipline above.
	--
	-- SAFETY: the ledger is weak-keyed by the husk OWNER unit, so a despawned husk
	-- (mission transition, disconnect) drops its whole ledger and vanilla teardown
	-- frees those units -- no cross-mission reference is retained. Recording is
	-- bounded to CWV-RESOLVED defs (called only from the husk transform apply after
	-- a positive identity), so a native weapon's unit is never tracked or touched
	-- (#475 Invariant 1). The per-hand supersession NEVER fires on a wield-toggle
	-- (melee<->ranged holsters via visibility, not respawn -- no new spawn record),
	-- so a holstered weapon is never drained.
	_om._husk_unit_ledger = setmetatable({}, { __mode = "k" })
	_om._husk_record_override_unit = function(owner_unit_3p, slot_name, hand, unit)
		if not (owner_unit_3p and slot_name and hand and unit) then return false end
		local by_slot = _om._husk_unit_ledger[owner_unit_3p]
		if not by_slot then by_slot = {}; _om._husk_unit_ledger[owner_unit_3p] = by_slot end
		local hands = by_slot[slot_name]
		if not hands then hands = {}; by_slot[slot_name] = hands end
		local field = (hand == "left") and "left" or "right"
		local prev = hands[field]
		hands[field] = unit
		if not prev or prev == unit then return false end
		local alive = false
		pcall(function() alive = Unit.alive(prev) and true or false end)
		if not alive then return false end
		if _om._cwv_forget_crowbill_transform_unit then
			_om._cwv_forget_crowbill_transform_unit(prev, "husk_superseded")
		end
		pcall(Unit.set_unit_visibility, prev, false)
		if Managers and Managers.state and Managers.state.unit_spawner then
			pcall(function() Managers.state.unit_spawner:mark_for_deletion(prev) end)
		end
		_husk_log_once("395_drain:" .. tostring(slot_name) .. ":" .. field,
			"[cwv:395] husk stale override unit released: slot=%s hand=%s -- superseded 3P unit was still alive on re-spawn (no_left_hand Rapier leak floor); hidden + marked for deletion",
			tostring(slot_name), field)
		return true
	end

	-- issue 660 POSTCONDITION PROOF for the husk apply. Setter-success ("applied=y")
	-- is NOT retained-state evidence: a `set_local_*` call can succeed while the
	-- engine keeps the native pose (#660 documented false-positive). After the husk
	-- apply resolves a CWV def, read the RETAINED transform BACK from the engine
	-- (Unit.local_scale/position/rotation at node 0) plus the resolved unit
	-- identity, and emit ONE bounded line. Guarded by Unit.alive + Unit.has_node;
	-- throttled once per (slot, hand, def, retained-fingerprint) so a stable render
	-- logs exactly once and any drift surfaces as a NEW fingerprint. This is the
	-- husk twin of the owner-side [cwv:604] delivery proof.
	_om._husk_postcondition_log = function(owner_unit_3p, slot_name, hand, def, def_source, unit, unit_name)
		if not (unit and def) then return end
		if def.crowbill_model_key and _om._cwv_durable_crowbill_owner then
			-- Do not read immediately after the setter: that only proves the setter's
			-- own write and occurs before the final hammer/pick presentation. Annotate
			-- the tracked generation; the durable owner samples pre-repair next tick
			-- and again after the final presentation writer.
			_om._cwv_durable_crowbill_owner:annotate(unit, {
				owner_id = tostring(owner_unit_3p),
				slot_name = slot_name,
				def_source = def_source,
			})
			return
		end
		if _husk_retained_diag.count >= _husk_retained_diag.limit then return end
		local alive = false
		pcall(function() alive = Unit.alive(unit) and true or false end)
		if not alive then return end
		local has0 = false
		pcall(function() has0 = Unit.has_node(unit, 0) and true or false end)
		if not has0 then return end
		local s, p, r = "nil", "nil", "nil"
		pcall(function()
			local v = Unit.local_scale(unit, 0)
			if v then s = _triplet_text({ Vector3.to_elements(v) }) end
		end)
		pcall(function()
			local v = Unit.local_position(unit, 0)
			if v then p = _triplet_text({ Vector3.to_elements(v) }) end
		end)
		pcall(function()
			local q = Unit.local_rotation(unit, 0)
			if q then
				local x, y, z, w = Quaternion.to_elements(q)
				r = string.format("%.3f,%.3f,%.3f,%.3f", x or 0, y or 0, z or 0, w or 0)
			end
		end)
		local fp = s .. "|" .. p .. "|" .. r
		local key = tostring(owner_unit_3p) .. ":" .. tostring(slot_name) .. ":"
			.. tostring(hand) .. ":" .. tostring(def.item_key) .. ":"
			.. tostring(unit_name) .. ":" .. tostring(unit) .. ":" .. fp
		if _husk_retained_seen[key] then return end
		_husk_retained_seen[key] = true
		_husk_retained_diag.count = _husk_retained_diag.count + 1
		printf(
			"[cwv:huskpath] slot=%s hand=%s def=%s source=%s unit=%s retained_scale=(%s) retained_pos=(%s) retained_rot=(%s) retained_index=%d/%d",
			tostring(slot_name), tostring(hand), tostring(def.item_key or def.item_type),
			tostring(def_source), tostring(unit_name), s, p, r,
			_husk_retained_diag.count, _husk_retained_diag.limit)
	end

	-- issue 279 (2ND repro, 2026-07-12). The v0.1.365 entry-clear + the issue-399
	-- career-gated husk strip did NOT end the merged Outrider render: the user still
	-- sees the Trollhammer torpedo mesh "sometimes, host and client" on a CRAFTED
	-- Outrider. Source trace this session (gear_utils.lua / backend_utils.lua /
	-- simple_husk_inventory_extension.lua):
	--   * The OWNER path is clean after v0.1.365: item_data.ammo_unit is cleared,
	--     and vanilla gear_utils.lua:164 gates the attach on item_units.ammo_unit.
	--   * The HUSK resolves the BASE dr_deus_01 item_data (backend_id is nil at
	--     simple_husk_inventory_extension.lua:662). The #478 preselection now fixes
	--     authored hands before vanilla branches, while dr_deus_01.ammo_unit IS the
	--     torpedo unless the post-spawn strip below removes it -> vanilla attaches
	--     it. A NATIVE item dodges this (the cwv skin rides the wire; skin.ammo_unit
	--     = nil), a CRAFTED item does not (no skin) -- which is exactly why the bug
	--     is CRAFTED-only. The ammo defense remains the career-gated post-spawn strip
	--     above; #478's preselection + per-hand defer separately own weapon hands.
	-- UNCONFIRMED: the exact per-hand rekey / #478-defer / strip branch that leaves
	-- the torpedo, and whether "sometimes" == a husk career-lookup miss. This probe
	-- logs the full decision at every spawn_inventory_unit call so the next 2-player
	-- repro pins it. Pure diagnostic: pcall-wrapped, printf (visible with mod-logging
	-- OFF), throttled once per distinct decision key.
	_om._probe_279_spawn = function(hand, item_data, item_units, owner_unit_1p, owner_unit_3p, ammo_unit_3p, note)
		pcall(function()
			local base_name = item_data and item_data.name
			if not (base_name and _no_ammo_careers_by_base[base_name]) then return end
			local side = owner_unit_1p and "owner" or "husk"
			local career = _husk_career_name(owner_unit_3p)
			local careers = _no_ammo_careers_by_base[base_name]
			local in_strip_set = (career and careers[career]) and true or false
			local iu_ammo = item_units and item_units.ammo_unit
			local iu_ammo3p = item_units and item_units.ammo_unit_3p
			_husk_log_once(
				"probe279:" .. side .. ":" .. tostring(base_name) .. ":" .. tostring(hand)
					.. ":" .. tostring(career) .. ":" .. tostring(iu_ammo ~= nil) .. ":" .. tostring(note),
				"[cwv:279] spawn side=%s hand=%s base=%s bid=%s note=%s skin=%s career=%s in_strip_set=%s "
					.. "iu.right=%s iu.left=%s iu.ammo_unit=%s iu.ammo_unit_3p=%s vanilla_attached_ammo_3p=%s",
				side, tostring(hand), tostring(base_name),
				tostring(item_data and item_data.backend_id), tostring(note),
				tostring(item_units and item_units.skin), tostring(career), tostring(in_strip_set),
				tostring(item_units and item_units.right_hand_unit),
				tostring(item_units and item_units.left_hand_unit),
				tostring(iu_ammo), tostring(iu_ammo3p), tostring(ammo_unit_3p ~= nil))
		end)
	end

	-- Apply the CWV scale/offset transform to the husk 3P weapon unit,
	-- mirroring the owner-side create_equipment hook. Resolves the CWV def
	-- ONLY via cwv-POSITIVE signals (skin / backend_id / cwv item_data key) —
	-- NEVER a bare base_weapon match, which would corrupt a genuinely native
	-- weapon that shares the base key on the husk (e.g. Kruber's own
	-- es_bastard_sword vs the cwv longsword are indistinguishable on the husk
	-- once the skin/backend_id are absent). When nothing resolves and the item
	-- is a CWV base weapon, log it: that is the disambiguating evidence for the
	-- #392 base-resolution umbrella (husk never sees the CWV instance).
	_om._husk_apply_cwv_transform = function(hand, item_data, item_units, weapon_unit_3p, owner_unit_3p, slot_name)
		if not (weapon_unit_3p and _is_unit(weapon_unit_3p)) then
			-- The 3P weapon unit is nil/dead. For a CWV base weapon this means the
			-- spawn returned nothing (override unit non-resident on this client, or
			-- the base-path spawn failed) — the deeper cause behind an invisible
			-- husk. Log once per (base, hand) so it isn't a silent return.
			local base_name = item_data and item_data.name
			if base_name and _cwv_base_weapons[base_name] then
				_husk_log_once("no_unit:" .. tostring(base_name) .. ":" .. tostring(hand),
					"[cwv husk-transform] SKIP: hand=%s base=%s -- 3P weapon unit nil/dead (spawn failed / override non-resident?) issue 396/397 diag",
					tostring(hand), tostring(base_name))
			end
			return
		end
		local skin = item_units and item_units.skin
		local style_decision
		if _om.combat_styles and _om.combat_styles.remote_transform then
			style_decision = _om.combat_styles:remote_transform(owner_unit_3p, slot_name, item_data)
		end
		if style_decision == false then return end
		local resolved_unit_name = item_units and item_units[
			hand == "right" and "right_hand_unit" or "left_hand_unit"]
		local exact, identity_state
		if _om._husk_identity_descriptor then
			exact, identity_state = _om._husk_identity_descriptor(
				owner_unit_3p, slot_name, item_data and item_data.name)
		end
		if identity_state and identity_state ~= "none" and identity_state ~= "exact" then
			return
		end
		if exact and exact.skin then skin = exact.skin end
		local def, def_source = _om._cwv_select_husk_transform_def(hand, exact,
			item_data, skin, resolved_unit_name, style_decision)
		if def_source == "exact_unit_mismatch" then return end
		if not def and skin == nil then
			-- #392/#397 fallback, #475-hardened: base+career positive signal for
			-- SKINLESS echoes only, can_wield evaluated LAZILY at wield time. A
			-- present non-cwv skin means a native item (Invariant 1): no fallback
			-- -- exactly the mesh re-key's rule; both route through
			-- _om._husk_resolve_display_def so mesh and transform cannot disagree.
			local bc_career = _husk_career_name(owner_unit_3p)
			local bc_def, bc_reason = _om._husk_resolve_display_def(item_data and item_data.name, bc_career, nil)
			def = bc_def
			if def then def_source = "base_career" end
			if def then
				_husk_log_once("bc_xform:" .. tostring(item_data and item_data.name) .. ":" .. tostring(bc_career) .. ":" .. tostring(hand),
					"[cwv:474] husk transform resolved via base+career: base=%s career=%s def=%s hand=%s (skinless echo, pair not currently wieldable)",
					tostring(item_data and item_data.name), tostring(bc_career), tostring(def.item_key), tostring(hand))
			elseif bc_reason == "native_pair" and _cwv_base_weapons[item_data and item_data.name] then
				_husk_log_once("475_xform_native:" .. tostring(item_data and item_data.name) .. ":" .. tostring(bc_career) .. ":" .. tostring(hand),
					"[cwv:475] husk transform fallback DECLINED (native_pair): base=%s career=%s -- skinless echo, pair currently wieldable (vanilla or wt)",
					tostring(item_data and item_data.name), tostring(bc_career))
			end
		end
		if not def then
			local base_name = item_data and item_data.name
			if base_name and _cwv_base_weapons[base_name] then
				-- Throttled: the husk resolves the BASE item (no cwv_ backend_id, and
				-- no curated skin synced), so no CWV def is reachable and the
				-- transform can't apply. This is the issue-392 base-resolution
				-- umbrella evidence — the husk never sees the CWV instance. Key by
				-- (base, hand, skin) so a genuinely skinless equip logs once, but a
				-- later skinned equip (which SHOULD resolve) still surfaces if it
				-- unexpectedly falls through.
				_husk_log_once("no_def:" .. tostring(base_name) .. ":" .. tostring(hand) .. ":" .. tostring(skin),
					"[cwv husk-transform] no cwv def resolved: hand=%s base=%s backend_id=%s skin=%s -- husk saw BASE item only (issue 397/392 diag)",
					tostring(hand), tostring(base_name),
					tostring(item_data and item_data.backend_id), tostring(skin))
			end
			return
		end
		-- issue 395: record this CWV-resolved husk override unit for the slot so a
		-- superseded prior unit (a #395 leaked Rapier override) is drained on the
		-- next re-spawn of the same (owner, slot, hand).
		if _om._husk_record_override_unit then
			_om._husk_record_override_unit(owner_unit_3p, slot_name, hand, weapon_unit_3p)
		end
		local plan = _om._cwv_husk_transform_apply_plan(hand, def, def_source)
		local scale = plan and plan.scale
		local scale_multiplier = plan and plan.scale_multiplier
		local offset = plan and plan.offset
		local rotation = plan and plan.rotation
		if plan and plan.should_apply then
			_apply_cwv_hand_transform(weapon_unit_3p, def, hand, "3p", "remote_husk",
				resolved_unit_name, skin)
			printf("[cwv husk-transform] applied hand=%s def=%s source=%s scale=%s scale_multiplier=%s offset=%s rotation=%s -- issues 397/394/604",
				tostring(hand), tostring(def.item_key or def.item_type),
				tostring(plan.source), scale and "y" or "n",
				scale_multiplier and "y" or "n", offset and "y" or "n",
				rotation and "y" or "n")
		end
		-- issue 660 postcondition: read the RETAINED transform back from the engine
		-- (not the setter return) and emit one bounded [cwv:huskpath] line proving
		-- the resolved unit identity + what the engine actually kept.
		if _om._husk_postcondition_log then
			_om._husk_postcondition_log(owner_unit_3p, slot_name, hand, def,
				plan and plan.source or def_source, weapon_unit_3p, resolved_unit_name)
		end
		-- #604 remote husks consume the same absolute presentation resolver as
		-- owners and previews.  The render identity is bounded owner+slot state;
		-- a network transition can target it once without per-frame pose traffic.
		if def.crowbill_mode_family and _om._apply_crowbill_presentation then
			local identity = _om.crowbill_runtime and _om.crowbill_runtime.remote_identity
				and _om.crowbill_runtime.remote_identity(owner_unit_3p, slot_name, def.item_key)
				or _om._crowbill_render_identity(item_data, def,
					(def.item_key or "cwv_crowbill") .. ":" .. tostring(slot_name))
			_om._apply_crowbill_presentation(weapon_unit_3p, def, identity,
				"remote_husk", rotation)
		end
		-- (#474) Old Musket husk display parity. Its look is NOT generic def
		-- fields: custom mesh + bespoke ABSOLUTE 3P pose + runtime-bound
		-- textures, which the owner path gates on backend_id + musket template
		-- -- both absent on the husk (wire item is the base es_handgun), so the
		-- owner block at the spawn hook never fires here. Apply only when the
		-- def positively identifies the Old Musket AND the custom mesh actually
		-- spawned (item_units reflects the pre-spawn re-key decision): the
		-- absolute pose is authored for the custom mesh and must never touch a
		-- base handgun that spawned on a residency decline. Stance comes from
		-- the bounded #474 presentation channel; ranged is only the safe
		-- pre-handshake fallback.
		if def.item_key == "cwv_es_musket_old" and hand == "right"
				and item_units and item_units.right_hand_unit == def.right_hand_unit then
			local rendered_unit_name = resolved_unit_name
			if type(rendered_unit_name) == "string"
					and rendered_unit_name:sub(-3) ~= "_3p" then
				rendered_unit_name = rendered_unit_name .. "_3p"
			end
			-- #474 (2026-07-18): the stance cache is keyed by the slot the item
			-- SITS in (the owner publishes it that way), so the lookup must use
			-- slot_name of the unit being presented. The husk's
			-- equipment.wielded_slot lags the wield RPC (paired log: presentation
			-- printed slot=slot_melee during a slot_ranged wield) and is logged
			-- only as context.
			local wielded_slot = nil
			if owner_unit_3p and Unit.alive(owner_unit_3p) then
				local ok_inv, inv = pcall(ScriptUnit.extension, owner_unit_3p, "inventory_system")
				local eq = ok_inv and inv and inv.equipment and inv:equipment()
				wielded_slot = eq and eq.wielded_slot
			end
			local mode = _om._old_musket_mode_for_owner
				and _om._old_musket_mode_for_owner(owner_unit_3p, slot_name) or "ranged"
			local presentation = _om.old_musket_appearance and _om.old_musket_appearance.reconcile
				and _om.old_musket_appearance.reconcile(weapon_unit_3p, "husk", "equip", {
					cwv_key = "cwv_es_musket_old", skin = skin,
				}, mode, {
					peer_id = tostring(owner_unit_3p), slot_name = slot_name,
					unit_name = rendered_unit_name,
				})
			pcall(printf, "[cwv:474] husk old-musket descriptor presentation: mode=%s retained=%s reason=%s (slot=%s wielded=%s hand=%s skin=%s)",
				tostring(mode), tostring(presentation and presentation.retained == true),
				tostring(presentation and presentation.reason), tostring(slot_name),
				tostring(wielded_slot), tostring(hand), tostring(skin))
		end
	end

	-- ============================================================
	-- COMPLETE husk adapter (issues 394/398/399/401/474/476/482/719 + #579 probe)
	-- ============================================================
	-- BUG_CLASSES class 27 root cause: cwv husk coverage grew per-concern
	-- per-variant, so any concern not explicitly routed fell back to base. These
	-- two entry-facing seams make the GearUtils.spawn_inventory_unit hook consume
	-- ONE full-definition resolution for every husk concern: display units +
	-- fail-closed residency (mesh re-key), ammo-nil, clone-template identity
	-- (audio/FX metadata), transforms/textures/presentation, and the #579
	-- per-hand compare evidence. The owner/bot path (create_equipment, 1P rig
	-- present) is untouched.

	-- (#399, complete-adapter arm) PRE-SPAWN ammo-nil. The post-spawn strip
	-- (above) hides+deletes an already-attached torpedo; this clears
	-- item_units.ammo_unit/_3p BEFORE vanilla's attach gate reads them
	-- (gear_utils.lua:159-170 gates on item_units.ammo_unit), so the inherited
	-- ammo mesh never spawns at all. Same descriptor-primary decision order as
	-- the strip: exact identity (#660) first, skinless base+career fallback
	-- second; explicit-native / unavailable-provider evidence declines. The
	-- strip stays installed as the belt-and-suspenders net for a spawn that
	-- reached vanilla before identity arrived.
	--
	-- Same DESCRIPTOR-STATE POLICY as the strip arm above (#399 fix, 2026-08-07):
	-- only an explicit "native" declines; "unavailable" and "stale_base" fall
	-- through to the career-scoped base+career fallback. Read that arm's policy
	-- block for the disjointness argument that keeps a real Trollhammer safe.
	_om._husk_ammo_nil_item_units = function(item_data, item_units, owner_unit_3p, slot_name)
		if not (item_data and item_units) then return false end
		if item_units.ammo_unit == nil and item_units.ammo_unit_3p == nil then return false end
		local base_name = item_data.name
		local why
		local exact, identity_state
		if _om._husk_identity_descriptor then
			exact, identity_state = _om._husk_identity_descriptor(owner_unit_3p, slot_name, base_name)
		end
		if identity_state == "native" then
			return false
		end
		if exact then
			local edef = _find_def(exact.variant_key)
			if edef then
				if edef.no_ammo_unit then why = "descriptor" else return false end
			end
		end
		if not why then
			local careers = base_name and _no_ammo_careers_by_base[base_name]
			if not careers then return false end
			local career = (_om._husk_career_name or _husk_career_name)(owner_unit_3p)
			if not (career and careers[career]) then
				-- Mirrors the post-spawn arm's SKIP needle so BOTH ammo arms are
				-- diagnosable from one log. A career=nil line here is candidate B
				-- of #399 (husk career-lookup miss); a real career that simply is
				-- not in the strip set is the correct native-wielder no-op.
				_husk_log_once("399_prenil_career_miss:" .. tostring(base_name) .. ":" .. tostring(career),
					"[cwv husk-ammo-nil] SKIP: base=%s is a no_ammo variant base but career=%s not in strip set (state=%s) -- native wielder OR husk career-lookup miss (issue 399 diag)",
					tostring(base_name), tostring(career), tostring(identity_state))
				return false
			end
			why = "base_career"
		end
		item_units.ammo_unit = nil
		item_units.ammo_unit_3p = nil
		_husk_log_once("399_prenil:" .. tostring(base_name) .. ":" .. tostring(why),
			"[cwv:399] husk ammo-nil pre-spawn: base=%s via=%s -- item_units.ammo_unit/_3p cleared before vanilla attach (complete husk adapter)",
			tostring(base_name), tostring(why))
		return true
	end

	-- (#398) Clone-TEMPLATE identity for the husk spawn. The husk resolves
	-- item_template from the BASE item_data (simple_husk_inventory_extension
	-- .lua:662), so template-level cwv changes (impact/audio metadata, hit
	-- effects, ammo_data shape) never reach the spawned 3P unit's weapon_system
	-- extension (gear_utils.lua:181-186 stores item_template into the extension
	-- init data). When the SAME positive identity the mesh re-key trusts
	-- resolves a def with an authored clone template (def.template ->
	-- Weapons[name], set by _build_entry), hand that template to the vanilla
	-- spawn call ONLY. Fail-closed structural guards: the per-hand
	-- attachment_node_linking vanilla will index must exist on the clone
	-- (gear_utils.lua:172 reads node_linking_settings.third_person.wielded), and
	-- an ammo-handed clone must carry ammo_unit_attachment_node_linking or the
	-- vanilla fassert would fire. Any guard miss keeps the base template.
	_om._husk_template_for_spawn = function(hand, item_template, item_units, slot_name, item_data, owner_unit_3p)
		local base_name = item_data and item_data.name
		if not base_name then return nil end
		local exact, identity_state
		if _om._husk_identity_descriptor then
			exact, identity_state = _om._husk_identity_descriptor(owner_unit_3p, slot_name, base_name)
		end
		if identity_state and identity_state ~= "none" and identity_state ~= "exact" then
			return nil
		end
		local skin = item_units and item_units.skin
		if exact and exact.skin then skin = exact.skin end
		local def = exact and _find_def(exact.variant_key)
		if not def then
			def = _om._husk_resolve_display_def(base_name, _husk_career_name(owner_unit_3p), skin)
		end
		if not (def and type(def.template) == "string") then return nil end
		local weapons = rawget(_G, "Weapons")
		local ctpl = weapons and rawget(weapons, def.template)
		if type(ctpl) ~= "table" or ctpl == item_template then return nil end
		local link = ctpl[hand .. "_hand_attachment_node_linking"]
		if not (type(link) == "table" and type(link.third_person) == "table"
				and link.third_person.wielded) then
			return nil
		end
		local ad = ctpl.ammo_data
		if ad and ad.ammo_hand == hand and item_units and item_units.ammo_unit
				and not ad.ammo_unit_attachment_node_linking then
			return nil
		end
		_husk_log_once("398_template:" .. tostring(base_name) .. ":" .. tostring(def.item_key) .. ":" .. hand,
			"[cwv:398] husk template identity: base=%s def=%s hand=%s -> template=%s (clone audio/FX metadata now reaches the husk spawn)",
			tostring(base_name), tostring(def.item_key), tostring(hand), tostring(def.template))
		return ctpl, def
	end

	-- (#579) Per-hand ID compare, the evidence the 2026-07-18 log sweep found
	-- missing (only the replay count line fired). One capped printf per distinct
	-- shape comparing, for THIS hand at the husk spawn seam: the descriptor's
	-- expected unit, what item_units actually carries into vanilla, and whether
	-- a 3P unit came back. Wire payload / host receive per-hand IDs already ride
	-- the lifecycle fingerprint logs (right|left are fingerprint components).
	local _p579_seen, _p579_total = {}, 0
	_om._probe_579_hand_compare = function(hand, item_data, item_units, slot_name, owner_unit_3p, weapon_unit_3p)
		pcall(function()
			local base_name = item_data and item_data.name
			if not (base_name and _cwv_base_weapons[base_name]) then return end
			if _p579_total >= 24 then return end
			local exact, state
			if _om._husk_identity_descriptor then
				exact, state = _om._husk_identity_descriptor(owner_unit_3p, slot_name, base_name)
			end
			local field = (hand == "right") and "right_hand_unit" or "left_hand_unit"
			local expected = exact and exact[field]
			local actual = item_units and item_units[field]
			local match = (expected == nil) and "n/a" or tostring(expected == actual)
			local skin = (exact and exact.skin) or (item_units and item_units.skin)
			local key = tostring(slot_name) .. "|" .. hand .. "|" .. tostring(expected)
				.. "|" .. tostring(actual) .. "|" .. tostring(skin) .. "|" .. tostring(state)
			if _p579_seen[key] then return end
			_p579_seen[key] = true
			_p579_total = _p579_total + 1
			printf("[cwv:579] husk hand-compare slot=%s hand=%s state=%s skin=%s expected_%s=%s item_units_%s=%s expected==actual=%s spawned_3p=%s (%d/24)",
				tostring(slot_name), hand, tostring(state), tostring(skin),
				field, tostring(expected), field, tostring(actual), match,
				tostring(weapon_unit_3p ~= nil), _p579_total)
		end)
	end

	-- PRE-SPAWN half, called once per hand by the entry hook (husk/bot side
	-- only). Returns (suppress, template_override): suppress = #478
	-- residency-gated defer (the entry returns all-nil for this hand instead of
	-- letting vanilla error over a non-resident unit); template_override is
	-- consumed ONLY by the vanilla spawn call.
	_om._husk_adapter_pre = function(hand, item_template, item_units, slot_name, item_data, owner_unit_3p)
		local wield_ctx = _om._appearance_husk_wield_context
		local transaction_deferred = wield_ctx
			and wield_ctx.hand_selection_deferred == true
			and wield_ctx.owner_unit_3p == owner_unit_3p
			and wield_ctx.slot_name == slot_name
		if transaction_deferred then
			_husk_log_once("474_adapter_base:" .. tostring(slot_name) .. ":"
					.. tostring(wield_ctx.hand_selection_source),
				"[cwv:474/660] lifecycle=husk_wield adapter=spawn deferred source=%s slot=%s base_preserved=true -- hand-selection transaction declined",
				tostring(wield_ctx.hand_selection_source), tostring(slot_name))
			-- Preserve the vanilla HAND SELECTION: no per-hand re-key or
			-- clone-template override after an atomic preselection residency miss.
			-- (#399) The ammo decision is NOT part of that transaction -- it
			-- chooses whether an inherited torpedo attaches, never which hand
			-- spawns -- so it runs here too. Without this the deferred branch
			-- returned at the crash floor / tail below and left the inherited
			-- dr_deus_01 torpedo bolted to the Outrider on every remote view.
			if _om._husk_ammo_nil_item_units then
				_om._husk_ammo_nil_item_units(item_data, item_units, owner_unit_3p, slot_name)
			end
			-- Keep the #478 crash floor: an inherited cross-character base can
			-- itself be unavailable on this peer.
			local field = (hand == "right") and "right_hand_unit" or "left_hand_unit"
			local base_unit = item_units and item_units[field]
			if type(base_unit) == "string" and base_unit ~= ""
					and (not _om._husk_unit_spawnable
						or not _om._husk_unit_spawnable(base_unit)) then
				_husk_log_once("478_deferred_base:" .. tostring(slot_name) .. ":"
						.. tostring(hand) .. ":" .. tostring(base_unit),
					"[cwv:478] husk DEFER: hand=%s slot=%s retained base unit %s is non-resident -- spawn suppressed (atomic hand-selection fallback)",
					tostring(hand), tostring(slot_name), tostring(base_unit))
				return true, nil
			end
			return false, nil
		end
		local suppress
		if _om._husk_rekey_units then
			suppress = _om._husk_rekey_units(hand, item_data, item_units, owner_unit_3p, slot_name) == true
		end
		if _om._husk_ammo_nil_item_units then
			_om._husk_ammo_nil_item_units(item_data, item_units, owner_unit_3p, slot_name)
		end
		local husk_tpl
		if not suppress and _om._husk_template_for_spawn then
			husk_tpl = _om._husk_template_for_spawn(hand, item_template, item_units, slot_name, item_data, owner_unit_3p)
		end
		return suppress == true, husk_tpl
	end

	-- POST-SPAWN half. Returns true when the caller must nil its captured
	-- ammo_unit_3p return (the #399 strip fired). All four spawn returns are
	-- captured by the entry hook (gear_utils.lua multi-return: weapon_3p,
	-- ammo_3p, weapon_1p, ammo_1p) -- only the 3P pair exists for husks.
	_om._husk_adapter_post = function(hand, item_data, item_units, slot_name, owner_unit_3p, v_w3p, v_a3p)
		local stripped = false
		if _om._husk_strip_cwv_ammo and _om._husk_strip_cwv_ammo(item_data, owner_unit_3p, v_a3p, slot_name) then
			stripped = true
		end
		if _om._husk_apply_cwv_transform then
			_om._husk_apply_cwv_transform(hand, item_data, item_units, v_w3p, owner_unit_3p, slot_name)
		end
		if _om._probe_579_hand_compare then
			_om._probe_579_hand_compare(hand, item_data, item_units, slot_name, owner_unit_3p, v_w3p)
		end
		return stripped
	end
end

end
