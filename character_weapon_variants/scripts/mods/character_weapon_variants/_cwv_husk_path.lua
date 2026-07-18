-- _cwv_husk_path.lua — cross-character husk display + transform + ledger machinery
--
-- Owns the husk-side (remote-player) appearance resolution for CWV variants: the
-- mesh re-key / handedness preselection (#474/#475/#478), the no_ammo_unit
-- ammo-strip (#399), the scale/offset transform apply (#397/#394/#604), the
-- stale-override-unit ledger + supersession drain (#395), and the #660 huskpath
-- postcondition log. All logic is assigned onto the shared `mod._om` namespace as
-- `_om._husk_*` fields; the three husk-reaching hooks (GearUtils.spawn_inventory_unit,
-- SimpleHuskInventoryExtension._wield_slot / start_weapon_fx) stay in the entry and
-- reach these helpers through the `_om` upvalue at call time. Pure structural
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

	local function _husk_career_name(owner_unit_3p)
		if not owner_unit_3p then return nil end
		local name
		pcall(function()
			if ScriptUnit.has_extension(owner_unit_3p, "career_system") then
				name = ScriptUnit.extension(owner_unit_3p, "career_system"):career_name()
			end
		end)
		return name
	end

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

	-- #478 crash-floor residency predicate. Can vanilla spawn_inventory_unit spawn
	-- this unit's "_3p" form on THIS peer without an async C-assert? DISTINCT from
	-- _om._resident_override_3p (issue 418), which demands cwv's OWN force-load
	-- reference: the crash-floor only asks whether the resource is resident under
	-- ANY reference -- a naturally game-loaded base mesh counts (has_loaded with no
	-- reference_name returns the plain loaded flag, package_manager.lua:286-293) --
	-- OR is a cwv custom-bundle mesh (units/cwv_*, always resident while the mod is
	-- loaded; the vanilla-prefix resident guard deliberately rejects it, issue 403).
	-- Used by the husk re-key to suppress a spawn that would otherwise error at
	-- gear_utils.lua:189 (weapon_unit_name .. "_3p" over a missing package).
	_om._husk_unit_spawnable = function(base_unit)
		if type(base_unit) ~= "string" or base_unit == "" then return false end
		if _om._husk_custom_bundle_unit and _om._husk_custom_bundle_unit(base_unit) then return true end
		if not (Managers and Managers.package) then return false end
		local ok, res = pcall(Managers.package.has_loaded, Managers.package, base_unit .. "_3p")
		return ok and res == true
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
			-- Residency: helper checks the "_3p" form; we write the BASE-form path,
			-- vanilla spawn_inventory_unit appends "_3p". A vanilla override must be
			-- cwv-force-loaded under HUSK_OVERRIDE_REF (issue 418); a mod-bundled
			-- custom mesh is accepted via the custom-bundle predicate.
			if (_om._resident_override_3p and _om._resident_override_3p(override))
					or (_om._husk_custom_bundle_unit and _om._husk_custom_bundle_unit(override)) then
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
	_om._husk_strip_cwv_ammo = function(item_data, owner_unit_3p, ammo_unit_3p, slot_name)
		if not (item_data and ammo_unit_3p) then return false end
		local base_name = item_data.name
		local why, career

		-- (1) exact identity descriptor -- authoritative when present.
		local exact, identity_state
		if _om._husk_identity_descriptor then
			exact, identity_state = _om._husk_identity_descriptor(owner_unit_3p, slot_name, base_name)
		end
		if identity_state and identity_state ~= "none" and identity_state ~= "exact" then
			-- Sender proved this slot native, or its exact descriptor is
			-- unavailable locally: never strip on the ambiguous base+career guess.
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
			career = _husk_career_name(owner_unit_3p)
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

		local alive = false
		pcall(function() alive = Unit.alive(ammo_unit_3p) and true or false end)
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
		_husk_log_once("huskpath:" .. tostring(slot_name) .. ":" .. tostring(hand) .. ":" .. tostring(def.item_key) .. ":" .. fp,
			"[cwv:huskpath] slot=%s hand=%s def=%s source=%s unit=%s retained_scale=(%s) retained_pos=(%s) retained_rot=(%s)",
			tostring(slot_name), tostring(hand), tostring(def.item_key or def.item_type),
			tostring(def_source), tostring(unit_name), s, p, r)
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
		local offset = plan and plan.offset
		local rotation = plan and plan.rotation
		if plan and plan.should_apply then
			_apply_cwv_hand_transform(weapon_unit_3p, def, hand, "3p", "remote_husk",
				resolved_unit_name, skin)
			printf("[cwv husk-transform] applied hand=%s def=%s source=%s scale=%s offset=%s -- issues 397/394/604",
				tostring(hand), tostring(def.item_key or def.item_type),
				tostring(plan.source), scale and "y" or "n", offset and "y" or "n")
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
			local wielded_slot = nil
			if owner_unit_3p and Unit.alive(owner_unit_3p) then
				local ok_inv, inv = pcall(ScriptUnit.extension, owner_unit_3p, "inventory_system")
				local eq = ok_inv and inv and inv.equipment and inv:equipment()
				wielded_slot = eq and eq.wielded_slot
			end
			local mode = _om._old_musket_mode_for_owner
				and _om._old_musket_mode_for_owner(owner_unit_3p, wielded_slot) or "ranged"
			pcall(_om._apply_old_musket_textures, weapon_unit_3p)
			pcall(_om._track_old_musket_unit, weapon_unit_3p, "3p", mode)
			pcall(_om._apply_old_musket_transform, weapon_unit_3p, "3p", mode)
			pcall(printf, "[cwv:474] husk old-musket presentation: textures + 3p %s pose applied (slot=%s hand=%s skin=%s)",
				tostring(mode), tostring(wielded_slot), tostring(hand), tostring(skin))
		end
	end
end

end
