-- The javelin owner intentionally keeps all five appended lookup rows, their
-- exact vanilla fallbacks, and the render carrier in one transaction.
-- resource-safety: cwv1159-javelin-runtime-force-load
local function install(mod, ctx)
	local _om = assert(ctx.om, "cwv javelin owner requires om")
	local _dbg = assert(ctx.dbg, "cwv javelin owner requires dbg")
	local _clone_damage_profile = assert(ctx.clone_damage_profile,
		"cwv javelin owner requires clone_damage_profile")

	-- (#1186) Renamed-clone projectile policy. This owner holds the mod's ONLY
	-- PlayerProjectileUnitExtension.init registration (VMF drops a second hook on
	-- the same (Class, method) pair), so every variant whose fired projectile has
	-- to reach a renamed template rides that one handler. The decision itself is
	-- engine-free and lives in its own module so the offline suite can drive it.
	-- Published on `_om` rather than held as a chunk local: this chunk is near the
	-- Lua 5.1 200-local ceiling (memory reference_cwv_lua_200_local_ceiling).
	_om.projectile_tunes = mod:dofile(
		"scripts/mods/character_weapon_variants/_cwv_projectile_tunes")

	-- ============================================================
	-- Tuskgor Javelin template (modified javelin_template)
	-- 15 max ammo, no auto-catch reload, ammo pickups refill, 2x damage, 0.5x speed
	--
	-- ANIM ADDENDUM: this template clone is shared across Kruber and Saltzpyre
	-- variants (cwv_es_javelin / cwv_wh_javelin). 1P animations are universal —
	-- the 1P state machine and clips reference shared first_person_base assets
	-- and play correctly on every character without intervention. Only 3P body
	-- anims need cross-character work, via anim_event_3p / wield_anim_3p /
	-- wield_anim_career_3p. See top-of-file ANIMATION ARCHITECTURE.
	-- ============================================================
	--
	-- Differs from the longsword/sword+shield clones in two important ways:
	--
	-- 1. Ammo system: vanilla javelin uses `unique_ammo_type=true` + a custom
	--    auto-replenish action (`weapon_reload.default` with `kind="catch"`) that
	--    magically refills the player's javelin stack to max whenever they're
	--    below it. We override `condition_func`/`chain_condition_func` to always
	--    return false, which keeps the action defined for state-machine/network
	--    purposes but prevents it from ever firing — turning the weapon into a
	--    finite-stack thrown weapon. Combined with `block_ammo_pickup=false` and
	--    `unique_ammo_type=false`, vanilla ammo crates refill it like any other
	--    Kruber ranged weapon (handgun/blunderbuss/longbow style).
	--
	-- 2. Damage profile shape: the throw projectile uses `thrown_javelin`, which
	--    is an INLINE damage profile (`default_target.power_distribution_near.attack`
	--    is a literal number) — NOT the PowerLevelTemplates string-key indirection
	--    used by melee weapons. The shared `_clone_damage_profile` helper assumes
	--    the string-key shape, so we use a dedicated `_clone_inline_throw_profile`
	--    for the throw and reuse `_clone_damage_profile` for the melee stab
	--    sub-actions (which DO use the string-key shape).
	--
	-- The "half speed" axis multiplies `total_time` and `minimum_hold_time` on
	-- `kind="thrown_projectile"` sub-actions, plus `attack_meta_data.minimum_charge_time`
	-- (the wind-up). Most javelin sub-actions don't carry `anim_time_scale`, so
	-- the longsword-style anim_time_scale multiplication is mostly a no-op here —
	-- timing fields are the actual lever.

	local _TJ_DAMAGE_MULT          = 2.0
	local _TJ_SPEED_MULT           = 0.5   -- action speed: half = 2x wind-up + recovery duration
	local _TJ_PROJECTILE_SPEED_MULT = 0.9  -- in-flight projectile velocity (sub_action.speed) — slower than vanilla javelin
	local _TJ_MAX_AMMO             = 10

	-- Custom projectile + pickup keys (registered below). Variant defs reference
	-- these via projectile_units_template / pickup_template_name /
	-- link_pickup_template_name, which the skin registration mirrors onto the
	-- weapon skin entry so the engine resolves them at projectile spawn time.
	local _TJ_PROJECTILE_KEY        = "cwv_tuskgor_javelin"
	local _TJ_PICKUP_KEY            = "cwv_tuskgor_javelin_pickup"
	local _TJ_LINK_PICKUP_KEY       = "cwv_tuskgor_javelin_link_pickup"
	-- Pickup + in-flight unit selection.
	--
	-- v0.1.73 split the in-flight unit (boar spear) from the pickup unit (elf
	-- javelin prj_*_3ps), with the rationale that the elf javelin had verified
	-- physics + correct axes for pickup spawn while the held boar spear _3p
	-- might lack those.
	--
	-- v0.1.118 reverts to using the boar spear _3p for BOTH paths, because:
	--   * The elf javelin _3ps unit is in the woods DLC's per-weapon package,
	--     which is loaded with the elf's `we_javelin` inventory entry — but
	--     OUR cwv_es_javelin item declares the boar spear in left_hand_unit/
	--     right_hand_unit, so the package loader never queues the elf javelin
	--     unit for our equipped variant. Result: `World.spawn_unit` crashes
	--     when the engine tries to spawn the unloaded prj_we_javelin_01_3ps
	--     pickup unit (crash GUID b7936944).
	--   * The mod-tools compiler doesn't ship DLC units locally, so we can't
	--     reference the elf javelin in our resource_packages/.package file.
	--   * The boar spear _3p IS reliably loaded (it's our held mesh).
	--
	-- Trade-off: the boar spear may have weak physics for pickup interaction
	-- and wrong local axes (hand-attachment), so v0.1.71's symptoms (no F/E
	-- prompt + 90° rotation off) may resurface. But those are now actually
	-- diagnosable since the link_pickup branch is finally engaged. We can
	-- iterate from there with rotation hooks and see if pickup interaction
	-- actually works with the held mesh.
	local _TJ_BOAR_SPEAR_UNIT       = "units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01_3p"
	-- v0.1.164: carrier-unit pattern. Probe data (v0.1.137 dump) confirmed the
	-- boar spear _3p has 0 actors while pup_dw_thrown_axe_01_t1 has 3. Without
	-- actors the interactor's aim raycast finds nothing → no E-prompt. Use the
	-- throwing axe pup as the actual spawn unit (real interaction collision)
	-- and attach the boar spear visually as a child via World.link_unit at
	-- extensions_ready time. Player sees boar spear, interacts with throwing
	-- axe collision underneath. Force-loaded via Managers.package:load() at
	-- mod init since base inventory doesn't queue the pup package.
	local _TJ_THROWING_AXE_PUP      = "units/weapons/player/wpn_dw_thrown_axe_01_t1/pup_dw_thrown_axe_01_t1"
	local _TJ_PICKUP_UNIT           = _TJ_THROWING_AXE_PUP
	-- v0.1.314: REVERTED v0.1.258 / v0.1.263's pull-back fix. The
	-- `pos - Quaternion.forward(rot) * offset` math along the spear's forward
	-- axis didn't visibly change stuck-javelin depth — see TODO in
	-- character_weapon_variants/TODO.md. Constant kept at 0 so the math
	-- branch is a no-op; the spawn position equals the parent's pose
	-- exactly. Real fix is unknown — likely the parent unit's rotation
	-- doesn't have its forward axis aligned with the spear's pointing
	-- direction (so `Quaternion.forward(rot)` is the wrong axis), or the
	-- parent isn't at the contact point we assume.
	local _TJ_VISUAL_PULL_BACK_M    = 0

	-- ============================================================================
	-- issue 424 (BUG_CLASSES 31): thrown-variant NetworkLookup wire-safety
	-- ============================================================================
	-- The Tuskgor Javelin appends pickup, husk, and projectile lookup keys.
	-- The full sender/hot-join containment rationale and hooks live in
	-- _cwv_javelin_gate.lua; this entry file retains only the configured map.

	_om._TJ_INFLIGHT_MODDED_UNIT   = _TJ_BOAR_SPEAR_UNIT
	_om._TJ_INFLIGHT_SAFE_TEMPLATE = "javelin"   -- vanilla ProjectileUnits key (elf javelin)
	-- The exact thrown-resource spec: the five appended rows plus the proven
	-- vanilla donor each one degrades to. `pickup_fallbacks` is the ONLY declared
	-- donor map; a cwv_-prefixed pickup absent from it is not "keep the custom id"
	-- (the pre-#424 nil-ambiguity that let `cwv_tuskgor_javelin_bomb` wire its own
	-- appended index) but a DROP -- see _cwv_thrown_wire_policy.is_owned_pickup.
	_om._TJ_WIRE_SPEC = {
		projectile_key        = _TJ_PROJECTILE_KEY,
		safe_projectile_key   = _om._TJ_INFLIGHT_SAFE_TEMPLATE,
		inflight_unit         = _TJ_BOAR_SPEAR_UNIT,
		safe_projectile_unit  = "units/weapons/player/wpn_we_javelin_01/prj_we_javelin_01_3ps",
		carrier_unit          = _TJ_PICKUP_UNIT,
		pickup_key            = _TJ_PICKUP_KEY,
		link_pickup_key       = _TJ_LINK_PICKUP_KEY,
		safe_pickup_key       = "ammo_throwing_axe_01_t1",
		safe_link_pickup_key  = "link_ammo_throwing_axe_01_t1",
		pickup_fallbacks = {
			-- cwv thrown-impact pickup key -> a base-game pickup with a boot-stable
			-- pickup_names index on every peer (throwing axe: same pup_ unit, and the
			-- link_ variant shares our `limited_owned_pickup_unit` template).
			[_TJ_PICKUP_KEY]      = "ammo_throwing_axe_01_t1",
			[_TJ_LINK_PICKUP_KEY] = "link_ammo_throwing_axe_01_t1",
		},
	}
	_om._tj_pickup_wire_map = _om._TJ_WIRE_SPEC.pickup_fallbacks
	-- Three-valued by construction: RIDE_CUSTOM (send `name` as given) /
	-- SUBSTITUTE (send the returned proven vanilla donor) / DROP (suppress the
	-- spawn). The optional override exists for deterministic regression checks
	-- only; live callers omit it and the exact thrown verdict decides.
	function _om._tj_pickup_disposition(pickup_name, exact_override)
		local exact = exact_override
		if exact == nil then
			local ok, safe = pcall(mod._cwv_thrown_wire_safe)
			exact = ok and safe == true
		end
		return _om.thrown_wire_policy.pickup_disposition(
			pickup_name, exact, _om._TJ_WIRE_SPEC, _G)
	end
	-- UNCONDITIONAL in-flight floor (never parity- or toggle-gated): our boar-spear
	-- husk must never ride a vanilla GameObject. Returns the vanilla donor table,
	-- the input unchanged when it is not ours, or nil when the donor cannot be
	-- proven -- the ProjectileSystem preflight in _cwv_javelin_gate refuses the
	-- spawn on nil rather than let vanilla dereference it.
	function _om._wire_safe_projectile_units(projectile_units)
		local disposition, resolved = _om.thrown_wire_policy.projectile_disposition(
			projectile_units, _om._TJ_WIRE_SPEC, _G)
		if disposition == _om.thrown_wire_policy.DROP then return nil end
		return resolved
	end

	local function _register_tuskgor_javelin_assets()
		-- 1. Projectile unit — controls the in-flight + stuck mesh when the throw
		-- action's `use_weapon_skin = true` resolves to our skin's
		-- projectile_units_template = _TJ_PROJECTILE_KEY.
		if not ProjectileUnits then
			mod:warning("ProjectileUnits global missing — projectile/pickup model swap unavailable")
			return
		end
		if not ProjectileUnits[_TJ_PROJECTILE_KEY] then
			ProjectileUnits[_TJ_PROJECTILE_KEY] = {
				dummy_linker_unit_name = _TJ_BOAR_SPEAR_UNIT,
				projectile_unit_name   = _TJ_BOAR_SPEAR_UNIT,
			}
			if NetworkLookup and NetworkLookup.projectile_units
				and not rawget(NetworkLookup.projectile_units, _TJ_PROJECTILE_KEY)
			then
				local tbl = NetworkLookup.projectile_units
				local idx = #tbl + 1
				rawset(tbl, idx, _TJ_PROJECTILE_KEY)
				rawset(tbl, _TJ_PROJECTILE_KEY, idx)
			end
			mod:info("Registered ProjectileUnits.%s -> %s", _TJ_PROJECTILE_KEY, _TJ_BOAR_SPEAR_UNIT)
		end

		-- 1b. Husk lookup injection — required for non-link pickup spawn path.
		-- PlayerProjectileUnitExtension._spawn_pickup_projectile (player_projectile_unit_extension.lua:1382)
		-- looks up `NetworkLookup.husks[pickup_unit_name]` before sending the spawn
		-- RPC. The boar spear's `_3p` unit was never registered as husk-spawnable
		-- (anvil_common_settings.lua:8-18 declares the throwing axe's pup_/prj_/_3p
		-- variants in `husk_lookup`, but the boar spear only got the held _3p
		-- declaration in anvil_equipment_settings.lua's player_units list — that
		-- list doesn't feed into NetworkLookup.husks). Without this injection,
		-- throws that take the non-link path (friendly hits, shields, certain
		-- terrain with allow_link=false) crash with the "Table husks does not
		-- contain key" error from network_lookup.lua's __index metamethod.
		-- v0.1.71 hit this crash on the very first thrown javelin.
		if NetworkLookup and NetworkLookup.husks
			and not rawget(NetworkLookup.husks, _TJ_BOAR_SPEAR_UNIT)
		then
			local tbl = NetworkLookup.husks
			local idx = #tbl + 1
			rawset(tbl, idx, _TJ_BOAR_SPEAR_UNIT)
			rawset(tbl, _TJ_BOAR_SPEAR_UNIT, idx)
			mod:info("Injected '%s' into NetworkLookup.husks at index %d", _TJ_BOAR_SPEAR_UNIT, idx)
		end

		-- 1c. Throwing axe pup unit force-load + husks injection.
		-- Carrier-unit pattern (v0.1.164): the boar spear has 0 actors so the
		-- interactor can't detect aim hits on it. The throwing axe pup unit has
		-- 3 actors (verified via cwv_probe_unit). Use the throwing axe pup as
		-- the actual spawned pickup, attach the boar spear visually as a child
		-- in the extensions_ready hook below.
		-- The pup unit isn't loaded by base inventory (only loads when Bardin
		-- equips throwing axes AND throws one). Force-load via the same API
		-- vanilla pickup_package_loader uses (`Managers.package:load(unit_path,
		-- ref, nil, async, prioritize)`), reference at pickup_package_loader.lua:191.
		if Managers and Managers.package then
			local ok, err = pcall(function()
				Managers.package:load(_TJ_THROWING_AXE_PUP, "cwv_throwing_axe_pup", nil, true, true)
			end)
			if ok then
				mod:info("Force-loaded throwing axe pup unit: %s", _TJ_THROWING_AXE_PUP)
			else
				mod:warning("Failed to force-load throwing axe pup: %s", tostring(err))
			end
		end
		if NetworkLookup and NetworkLookup.husks
			and not rawget(NetworkLookup.husks, _TJ_THROWING_AXE_PUP)
		then
			local tbl = NetworkLookup.husks
			local idx = #tbl + 1
			rawset(tbl, idx, _TJ_THROWING_AXE_PUP)
			rawset(tbl, _TJ_THROWING_AXE_PUP, idx)
			mod:info("Injected '%s' into NetworkLookup.husks at index %d", _TJ_THROWING_AXE_PUP, idx)
		end

		-- 2. Pickup templates — define ground pickup + linked-pickup (stuck variant).
		-- Modeled after anvil_pickup_settings.lua's throwing_axe pickups, but the
		-- can_interact / outline checks query for ammo_type "throwing_javelin"
		-- (vanilla javelin's ammo_type, which we kept on tuskgor_javelin_template)
		-- so only players wielding our javelin can pick these up — and any actual
		-- elf carrying we_javelin would also see them, which is fine since they
		-- share the ammo_type.
		if not Pickups or not Pickups.ammo then
			mod:warning("Pickups.ammo missing — link_pickup behavior unavailable")
			return
		end
		if not Pickups.ammo[_TJ_PICKUP_KEY] then
			local function _can_interact(interactor_unit, _interactable_unit, _data)
				local inv = ScriptUnit.has_extension(interactor_unit, "inventory_system")
				local result = inv and inv:has_ammo_consuming_weapon_equipped("throwing_javelin") or false
				_dbg("[cwv stick] can_interact_func -> %s (inv=%s)", tostring(result), tostring(inv ~= nil))
				return result
			end
			local function _outline_available(local_player_unit)
				local inv = ScriptUnit.has_extension(local_player_unit, "inventory_system")
				return inv and inv:has_ammo_consuming_weapon_equipped("throwing_javelin") or false
			end
			local function _on_pick_up(_world, _interactor_unit, _is_server, interactable_unit)
				_dbg("[cwv stick] on_pick_up_func fired")
				local peer_id = Network.peer_id()
				local pickup_system = Managers.state.entity:system("pickup_system")
				pickup_system:delete_limited_owned_pickup_unit(peer_id, interactable_unit)
			end
			local base = {
				ammo_kind            = "thrown",
				consumable_item      = true,
				debug_pickup_category = "throwing_weapons",
				hud_description      = "cwv_interaction_ammunition_javelin",  -- v0.1.183: own loc string (was "interaction_ammunition_axe" — wrong text)
				local_pickup_sound   = true,
				only_once            = true,
				outline_distance     = "small_pickup",
				pickup_sound_event   = "pickup_ammo",
				refill_amount        = 1,
				spawn_weighting      = 1e-06,
				type                 = "ammo",
				can_interact_func    = _can_interact,
				outline_available_func = _outline_available,
				on_pick_up_func      = _on_pick_up,
			}
			-- v0.1.118: unit_name = boar spear _3p for both variants (held mesh
			-- is reliably loaded for our cwv weapon, unlike the elf javelin
			-- prj_*_3ps which is in the woods DLC's per-weapon package).
			-- v0.1.119: unit_template_name = "limited_owned_pickup_unit" for BOTH
			-- variants (was "limited_owned_pickup_projectile_unit" for the
			-- non-link/dropped variant). The "_projectile_unit" template requires
			-- the unit to have a physics actor named "throw" for bouncy ground
			-- pickup behavior — the boar spear _3p doesn't have that actor and
			-- crashes Actor.create_actor (crash GUID 86d07a4e on dummy hit). The
			-- non-projectile template doesn't need it; pickups spawn statically
			-- at the impact position instead of bouncing. Acceptable trade-off.
			Pickups.ammo[_TJ_PICKUP_KEY] = table.clone(base)
			Pickups.ammo[_TJ_PICKUP_KEY].unit_name          = _TJ_PICKUP_UNIT
			Pickups.ammo[_TJ_PICKUP_KEY].unit_template_name = "limited_owned_pickup_unit"
			Pickups.ammo[_TJ_PICKUP_KEY].pickup_name        = _TJ_PICKUP_KEY
			Pickups.ammo[_TJ_LINK_PICKUP_KEY] = table.clone(base)
			Pickups.ammo[_TJ_LINK_PICKUP_KEY].unit_name          = _TJ_PICKUP_UNIT
			Pickups.ammo[_TJ_LINK_PICKUP_KEY].unit_template_name = "limited_owned_pickup_unit"
			Pickups.ammo[_TJ_LINK_PICKUP_KEY].pickup_name        = _TJ_LINK_PICKUP_KEY
			-- Re-attach the function refs after table.clone (closures get shallow-copied
			-- correctly, but be explicit so a future refactor doesn't trip us).
			for _, key in ipairs({ _TJ_PICKUP_KEY, _TJ_LINK_PICKUP_KEY }) do
				Pickups.ammo[key].can_interact_func      = _can_interact
				Pickups.ammo[key].outline_available_func = _outline_available
				Pickups.ammo[key].on_pick_up_func        = _on_pick_up
			end

			-- AllPickups is built once at boot from Pickups.<group>.<name> and is
			-- the lookup the pickup system reads. Mirror our entries in.
			if AllPickups then
				AllPickups[_TJ_PICKUP_KEY]      = Pickups.ammo[_TJ_PICKUP_KEY]
				AllPickups[_TJ_LINK_PICKUP_KEY] = Pickups.ammo[_TJ_LINK_PICKUP_KEY]
			end

			-- NetworkLookup.pickup_names is built from AllPickups at boot. Mirror
			-- our keys in via rawset (the table has an error-throwing __index).
			if NetworkLookup and NetworkLookup.pickup_names then
				local tbl = NetworkLookup.pickup_names
				for _, key in ipairs({ _TJ_PICKUP_KEY, _TJ_LINK_PICKUP_KEY }) do
					if not rawget(tbl, key) then
						local idx = #tbl + 1
						rawset(tbl, idx, key)
						rawset(tbl, key, idx)
					end
				end
			end

			mod:info("Registered pickups: %s + %s (boar spear unit, ammo_type=throwing_javelin)",
				_TJ_PICKUP_KEY, _TJ_LINK_PICKUP_KEY)
		end
	end

	-- ============================================================
	-- Stuck-pickup rotation cleanup (Tuskgor Javelin) — INSTRUMENTED
	-- ============================================================
	-- v0.1.81 hooked ProjectileLinkerSystem.link_pickup but that fires AFTER
	-- PickupSystem._spawn_pickup has already set the unit's world rotation
	-- (pickup_system.lua:1441 _spawn_pickup → 1446 link_pickup). For the common
	-- "stuck in a level wall" case, hit_unit doesn't have a projectile_linker_system
	-- extension, so link_pickup falls through to the else branch which never
	-- re-applies link_rotation. The hook therefore had no effect on wall-sticks.
	--
	-- v0.1.82 moves the hook earlier: PickupSystem.rpc_spawn_linked_pickup runs
	-- server-side BEFORE _spawn_pickup is called, with link_rotation as a parameter
	-- we can rewrite. Modifying it here propagates through the spawn AND through
	-- the subsequent rpc_link_pickup that fans to clients.
	--
	-- Also rotation logic upgraded: horizontal-projection variant. The engine
	-- applies random_pitch (math.pi/6 to math.pi/3 = 30°-60° around unit-left)
	-- and random_roll (±18° around unit-forward) on top of the clean directional
	-- look. To wipe both completely, project the rotated forward onto the
	-- horizontal plane (Stingray world: x,y horizontal; z vertical) and rebuild
	-- look using world up. Cost: floor/ceiling sticks would point sideways
	-- instead of into-the-surface. Acceptable trade-off given vertical walls
	-- are >90% of stick locations.
	--
	-- Verbose logging (mod:info) on every fire — input rotation axes, output
	-- rotation axes, pickup name. Lets us see in console.log whether the hook
	-- fires AND whether the math produces the correction we expect.
	local function _log_quat(prefix, q)
		-- v0.1.336: helper only ever called from the `[cwv stick]` diagnostic
		-- hooks below, all of which are now gated on `cwv_debug_mode`. Route
		-- through `_dbg` so the formatting cost is also skipped when off.
		local fwd = Quaternion.forward(q)
		local rgt = Quaternion.right(q)
		local up  = Quaternion.up(q)
		_dbg("  %s: fwd=(%.2f,%.2f,%.2f) right=(%.2f,%.2f,%.2f) up=(%.2f,%.2f,%.2f)",
			prefix,
			Vector3.x(fwd), Vector3.y(fwd), Vector3.z(fwd),
			Vector3.x(rgt), Vector3.y(rgt), Vector3.z(rgt),
			Vector3.x(up),  Vector3.y(up),  Vector3.z(up))
	end

	local function _is_our_pickup(pickup_name)
		return pickup_name == _TJ_PICKUP_KEY or pickup_name == _TJ_LINK_PICKUP_KEY
	end

	local function _clean_horizontal_rotation(rot)
		local fwd = Quaternion.forward(rot)
		local horizontal = Vector3(Vector3.x(fwd), Vector3.y(fwd), 0)
		if Vector3.length(horizontal) <= 0.01 then return rot, false end
		horizontal = Vector3.normalize(horizontal)
		local clean = Quaternion.look(horizontal, Vector3.up())
		-- v0.1.119: boar spear's local +Z is the tip axis (held mesh, hand grip
		-- pose). Engine's Quaternion.look orients local +Y to forward, so the
		-- visible tip ends up pointing world up — user reports "stuck straight
		-- up and down vertically". Post-multiply by a -90° rotation around the
		-- unit's local right axis (+X) to swing local +Z (tip) onto local +Y
		-- (link_direction). After this, the visible tip points along link_direction
		-- = into the wall.
		local tip_correction = Quaternion(Vector3.right(), -math.pi / 2)
		return Quaternion.multiply(clean, tip_correction), true
	end

	-- ============================================================================
	-- THE ACTUAL FIX (v0.1.97): force projectile/action system to use our cloned
	-- template, not the base.
	-- ============================================================================
	-- v0.1.96 diagnostic confirmed the engine reads `javelin_template` (base) at
	-- projectile init, NOT `tuskgor_javelin_template`. Cause: per memory note
	-- `feedback_cwv_backend_id_lookup.md`, `item_data.name`/`.key` returns the
	-- BASE weapon key for cwv items. The projectile system does
	-- `ItemMasterList[item_name]` (item_name = "we_javelin") then
	-- `BackendUtils.get_item_template(item_data)` reads `item_data.template`
	-- which is the base template name. Our cloned template was dead code at
	-- runtime — every stat/timing/impact_data override never took effect.
	--
	-- Hook `BackendUtils.get_item_template`. When the backend_id matches our cwv
	-- javelin pattern, return `Weapons.tuskgor_javelin_template` instead of the
	-- resolved base template.
	--
	-- Scope: only fires when backend_id matches `cwv_..._javelin_001`. Other cwv
	-- weapons hit the same bug in principle but happen to share the SAME template
	-- name as their base (e.g. cwv_es_longsword still uses `imperial_longsword_template`
	-- which the engine resolves correctly via the base lookup since our clone IS
	-- registered under that exact name). Javelin is special because we cloned to
	-- a DIFFERENT name (`tuskgor_javelin_template` vs base `javelin_template`)
	-- and the engine doesn't know about the rename.
	-- v0.1.97 hook on BackendUtils.get_item_template was a no-op: the projectile
	-- system passes `ItemMasterList[item_name]` where item_name = "we_javelin"
	-- (BASE key, since cwv items return base for item_data.name/.key per memory
	-- `feedback_cwv_backend_id_lookup.md`). The base entry has no backend_id, so
	-- the cwv match never fired.
	--
	-- v0.1.98 fix: hook PlayerProjectileUnitExtension.init AFTER vanilla init
	-- runs, look up the OWNER's slot_ranged backend_id (where the cwv prefix
	-- actually lives), and if it matches our javelin pattern, swap
	-- self._current_action / self._impact_data / self.projectile_info to point
	-- at our cloned tuskgor_javelin_template's throw_charged sub-action. The
	-- projectile then reads OUR fields for the rest of its lifecycle (impact
	-- handling, link_pickup, pickup_settings, etc.).
	-- (#1186) Runtime half of the renamed-clone arm. Everything here is a lazy
	-- `_om` read so entry load order stays irrelevant: `_cwv_key_for_item`
	-- (#482 ladder) and `_husk_skin_def` are both published after this owner.
	--
	-- OWNERSHIP LADDER for "which variant fired this projectile", strongest first:
	--   1. the wielded slot's own item identity through the shared #482 ladder
	--      (backend_id pattern, then the CIM/CWV stamps a crafted UUID instance
	--      carries) -- this is the rung a CRAFTED variant needs and the one the
	--      javelin block below never had;
	--   2. the slot's wire SKIN through the canonical `<item_key>_` resolver, the
	--      shape a curated/given instance arrives in.
	-- Neither rung can answer for a native weapon, so a vanilla Trollhammer or
	-- elf javelin resolves to nothing and the projectile keeps vanilla data.
	_om._cwv_renamed_template_overrides = nil
	_om._cwv_projectile_receipts = {}
	_om._cwv_projectile_receipt_count = 0
	-- Engine lookup kept behind its own named seam so the regression can drive
	-- the applier below with a fixture slot instead of a live inventory.
	_om._cwv_projectile_owner_slot = function(owner_unit)
		local inv = owner_unit and ScriptUnit.has_extension(owner_unit, "inventory_system")
		if not inv then return nil end
		local equipment = inv.equipment and inv:equipment()
		local slot_name = equipment and equipment.wielded_slot or "slot_ranged"
		return inv.get_slot_data and inv:get_slot_data(slot_name) or nil
	end
	_om._cwv_apply_renamed_projectile_template = function(projectile, init_data)
		local policy = _om.projectile_tunes
		local catalog = _om.variant_catalog
		local definitions = catalog and catalog.definitions
		if not (policy and definitions and rawget(_G, "ItemMasterList")) then return 0 end
		if not _om._cwv_renamed_template_overrides then
			_om._cwv_renamed_template_overrides = policy.renamed_template_defs(
				definitions, function(base)
					local entry = rawget(ItemMasterList, base)
					return type(entry) == "table" and entry.template or nil
				end)
		end
		local slot_data = _om._cwv_projectile_owner_slot(init_data and init_data.owner_unit)
		if not slot_data then return 0, "no_slot" end
		local master = slot_data.master_item or slot_data.item_data
		local backend_id = (master and master.backend_id) or slot_data.backend_id
		local key = _om._cwv_key_for_item and _om._cwv_key_for_item(backend_id, master)
		if not key and _om._husk_skin_def then
			local skin_def = _om._husk_skin_def(slot_data.skin)
			key = skin_def and skin_def.item_key or nil
		end
		local variant_base
		for _, def in ipairs(definitions) do
			if def.item_key == key then variant_base = def.base_weapon; break end
		end
		local action, reason = policy.resolve({
			overrides = _om._cwv_renamed_template_overrides,
			variant_key = key,
			variant_base = variant_base,
			item_name = init_data and init_data.item_name,
			weapons = rawget(_G, "Weapons"),
			lookup = projectile.action_lookup_data,
			base_action = projectile._current_action,
		})
		if not action then return 0, reason end
		local changed = policy.apply(projectile, action, function(name)
			local lookup = NetworkLookup and NetworkLookup.damage_profiles
			return lookup and rawget(lookup, name) or nil
		end)
		-- Bounded receipt: a projectile inits on EVERY shot, so key it by the
		-- resolved shape and print each distinct one once.
		local receipt = tostring(key) .. "|" .. tostring(reason) .. "|"
			.. tostring(projectile.action_lookup_data and projectile.action_lookup_data.action_name)
			.. "|" .. tostring(projectile.action_lookup_data and projectile.action_lookup_data.sub_action_name)
		if not _om._cwv_projectile_receipts[receipt] and _om._cwv_projectile_receipt_count < 16 then
			_om._cwv_projectile_receipts[receipt] = true
			_om._cwv_projectile_receipt_count = _om._cwv_projectile_receipt_count + 1
			pcall(printf,
				"[cwv:1186] projectile re-pointed variant=%s base=%s clone=%s action=%s/%s fields=%d damage_profile=%s (%d/16)",
				tostring(key), tostring(variant_base), tostring(reason),
				tostring(projectile.action_lookup_data and projectile.action_lookup_data.action_name),
				tostring(projectile.action_lookup_data and projectile.action_lookup_data.sub_action_name),
				changed, tostring(action.impact_data and action.impact_data.damage_profile),
				_om._cwv_projectile_receipt_count)
		end
		return changed, reason
	end

	-- Single init hook combining the v0.1.98 fix and the v0.1.96 diagnostic
	-- trace. v0.1.99 had two separate `hook_safe` registrations on the same
	-- method which silently never fired (VMF doesn't chain multiple hook_safe
	-- handlers for one method).
	mod:hook_safe("PlayerProjectileUnitExtension", "init", function(self, extension_init_context, unit, extension_init_data)
		-- 1) Diagnostic trace (always fires).
		local item = extension_init_data and extension_init_data.item_name or "?"
		local tmpl = extension_init_data and extension_init_data.item_template_name or "?"
		local action = extension_init_data and extension_init_data.action_name or "?"
		local sub = extension_init_data and extension_init_data.sub_action_name or "?"
		_dbg("[cwv stick] PROJ INIT item=%s tmpl=%s action=%s sub=%s",
			tostring(item), tostring(tmpl), tostring(action), tostring(sub))

		-- 2) (#1186) Renamed-clone arm for EVERY variant that authored a template
		--    under a new name. It runs ahead of the javelin-specific block below
		--    so that block stays the LAST writer for its own weapon and its
		--    v0.1.98 behavior is provably unchanged (both resolve the same
		--    tuskgor_javelin_template sub-action; the writes are identical).
		--    The variant this exists for is the Outrider Grenade Launcher, whose
		--    0.65x damage-profile clone and grenade projectile_info never reached
		--    the fired projectile: the engine re-resolves the DONOR template from
		--    the base item key, and only the javelin family had an arm here.
		pcall(_om._cwv_apply_renamed_projectile_template, self, extension_init_data)

		-- 3) Post-fix: if this projectile belongs to one of our cwv javelin
		--    variants, swap the action data references onto our cloned template.
		--    Filter to javelin-class items only to avoid log spam on arrows/bolts.
		if item ~= "we_javelin" then return end

		local owner_unit = extension_init_data and extension_init_data.owner_unit
		if not owner_unit then
			_dbg("[cwv stick] post-fix BAIL: no owner_unit in extension_init_data")
			return
		end
		local inv = ScriptUnit.has_extension(owner_unit, "inventory_system")
		if not inv then
			_dbg("[cwv stick] post-fix BAIL: no inventory_system extension on owner")
			return
		end
		local slot_data = inv:get_slot_data("slot_ranged")
		if not slot_data then
			_dbg("[cwv stick] post-fix BAIL: no slot_ranged slot_data")
			return
		end
		-- v0.1.106 diagnostic dump revealed: slot_data.id is the slot NAME
		-- ("slot_ranged"), slot_data.backend_id is nil. The cwv identifier
		-- actually lives in slot_data.skin (e.g. "cwv_es_javelin_skin").
		-- Match the skin field instead.
		local skin = slot_data.skin
		if type(skin) ~= "string" or not skin:match("^cwv_.+_javelin_skin$") then
			_dbg("[cwv stick] post-fix BAIL: skin=%s did not match cwv javelin pattern", tostring(skin))
			return
		end

		if not (Weapons and Weapons.tuskgor_javelin_template) then return end
		local our_template = Weapons.tuskgor_javelin_template
		local lookup = self.action_lookup_data
		if not lookup then return end
		local action_group = our_template.actions and our_template.actions[lookup.action_name]
		local our_action = action_group and action_group[lookup.sub_action_name]
		if not our_action then return end

		self._current_action = our_action
		self._impact_data    = our_action.impact_data
		self.projectile_info = our_action.projectile_info or self.projectile_info
		if our_action.impact_data and our_action.impact_data.damage_profile then
			local dmg_id = rawget(NetworkLookup.damage_profiles, our_action.impact_data.damage_profile)
			if dmg_id then self._impact_damage_profile_id = dmg_id end
		end
		_dbg("[cwv stick] init post-fix swap: skin=%s -> tuskgor_javelin_template (action=%s sub=%s, link=%s link_pickup=%s)",
			tostring(skin), tostring(lookup.action_name), tostring(lookup.sub_action_name),
			tostring(our_action.impact_data and our_action.impact_data.link),
			tostring(our_action.impact_data and our_action.impact_data.link_pickup))

		-- v0.1.125–v0.1.156 carried a child-node rotation correction here for the
		-- boar spear's wrong-axis in-flight visual. v0.1.157 made the in-flight
		-- unit the vanilla elf javelin (correctly authored, +Y is tip), so the
		-- correction is no longer applicable — and would actively wrongly rotate
		-- the elf javelin's child nodes. Removed.
	end)

	mod:hook_safe("PlayerProjectileUnitExtension", "hit_level_unit", function(self, impact_data, hit_unit)
		local lookup = self.action_lookup_data
		local tmpl = lookup and lookup.item_template_name or "?"
		-- v0.1.345-dev: dummy-path marker. Historical crash GUID 86d07a4e (see
		-- ~line 5210 above) fired when the Tuskgor Javelin's pickup spawn on
		-- dummy hits routed through `limited_owned_pickup_projectile_unit` —
		-- whose physics actor name "throw" doesn't exist on the boar spear _3p
		-- mesh, crashing `Actor.create_actor`. The fix swapped to
		-- `limited_owned_pickup_unit` (no physics). hit_level_unit is the
		-- engine entry point that dispatches to pickup spawn (PATH A
		-- `rpc_spawn_linked_pickup` for `link_pickup=true`, PATH B
		-- `rpc_spawn_pickup_projectile` otherwise). Capture hit_unit shape
		-- so dummy hits are identifiable.
		local hit_unit_alive = hit_unit and Unit.alive(hit_unit)
		_dbg("[cwv stick] HIT_LEVEL_UNIT tmpl=%s link=%s link_pickup=%s hit_unit_alive=%s",
			tostring(tmpl),
			tostring(impact_data and impact_data.link),
			tostring(impact_data and impact_data.link_pickup),
			tostring(hit_unit_alive))
		-- v0.1.345-dev: dummy-path explicit marker — if hit_unit is a training
		-- dummy (heuristic: live unit with no health_system extension, or a
		-- level unit named "training_dummy"), log explicitly so the next session
		-- log captures whether the historical crash path is reached.
		if hit_unit_alive and ScriptUnit and ScriptUnit.has_extension
				and not ScriptUnit.has_extension(hit_unit, "health_system") then
			_dbg("[cwv:dummy_path] event=hit_level_unit_no_health_system tmpl=%s — was historical crash site (GUID 86d07a4e on dummy hit), monitoring",
				tostring(tmpl))
		end
	end)

	mod:hook("PlayerProjectileUnitExtension", "_handle_linking", function(func, self, impact_data, hit_unit, hit_position, hit_direction, hit_normal, hit_actor, damage_amount, allow_link, shield_blocked, hit_enemy_or_player)
		local lookup = self.action_lookup_data
		local tmpl = lookup and lookup.item_template_name or "?"
		_dbg("[cwv stick] HANDLE_LINKING tmpl=%s allow_link=%s link=%s link_pickup=%s",
			tostring(tmpl), tostring(allow_link),
			tostring(impact_data and impact_data.link),
			tostring(impact_data and impact_data.link_pickup))
		return func(self, impact_data, hit_unit, hit_position, hit_direction, hit_normal, hit_actor, damage_amount, allow_link, shield_blocked, hit_enemy_or_player)
	end)

	-- One-shot dump command: read the live runtime tuskgor_javelin_template's
	-- impact_data. Tells us if our modifications actually persisted into the
	-- runtime template state, or if something overwrote them.
	mod:command("cwv_dump_javelin_impact", "Dump runtime tuskgor_javelin_template throw_charged.impact_data", function()
		if not Weapons or not Weapons.tuskgor_javelin_template then
			mod:echo("Weapons.tuskgor_javelin_template not found")
			return
		end
		mod:echo("=== tuskgor_javelin_template runtime dump ===")
		for action_name, action_group in pairs(Weapons.tuskgor_javelin_template.actions) do
			if type(action_group) == "table" then
				for sub_name, sub in pairs(action_group) do
					if type(sub) == "table" and sub.kind == "thrown_projectile" then
						mod:echo("action.%s.%s:", action_name, sub_name)
						mod:echo("  speed=%s total_time=%s",
							tostring(sub.speed), tostring(sub.total_time))
						if sub.impact_data then
							local i = sub.impact_data
							mod:echo("  link=%s link_pickup=%s wall_nail=%s",
								tostring(i.link), tostring(i.link_pickup), tostring(i.wall_nail))
							mod:echo("  flow_walls=%s flow_init=%s",
								tostring(i.flow_event_on_walls), tostring(i.flow_event_on_init))
							mod:echo("  pickup_settings=%s",
								tostring(i.pickup_settings))
						else
							mod:echo("  impact_data = nil")
						end
					end
				end
			end
		end
	end)

	-- Path A entry on thrower's side — trace + issue 424 wire-safe substitution.
	-- The vanilla body encodes NetworkLookup.pickup_names[pickup_name] and sends
	-- rpc_spawn_linked_pickup (player_projectile_unit_extension.lua:1354-1359);
	-- while parity is unconfirmed, swapping the cwv key for a vanilla one BEFORE
	-- func() keeps a non-cwv peer from cold-decoding the appended index
	-- (BUG_CLASSES 31). Confirmed-CWV lobbies retain the functional original.
	mod:hook("PlayerProjectileUnitExtension", "_spawn_linked_pickup_projectile", function(func, self, pickup_name, ...)
		if _is_our_pickup(pickup_name) then
			_dbg("[cwv stick:trace] _spawn_linked_pickup_projectile fired (pickup=%s)", tostring(pickup_name))
		end
		local disposition, safe = _om._tj_pickup_disposition(pickup_name)
		if disposition == _om.thrown_wire_policy.DROP then
			printf("[cwv:424] linked pickup DROPPED %s (no exact row and no proven vanilla donor)", tostring(pickup_name))
			return
		elseif disposition == _om.thrown_wire_policy.SUBSTITUTE then
			printf("[cwv:424] linked pickup wire-safe %s -> %s", tostring(pickup_name), tostring(safe))
			return func(self, safe, ...)
		end
		return func(self, pickup_name, ...)
	end)

	-- Path B entry on thrower's side — trace + issue 424 wire-safe substitution.
	-- Encodes pickup_name_id (+ pickup-unit husk id, already vanilla) and sends
	-- rpc_spawn_pickup_projectile (player_projectile_unit_extension.lua:1376-1395).
	mod:hook("PlayerProjectileUnitExtension", "_spawn_pickup_projectile", function(func, self, pickup_name, ...)
		if _is_our_pickup(pickup_name) then
			_dbg("[cwv stick:trace] _spawn_pickup_projectile (PATH B) fired (pickup=%s)", tostring(pickup_name))
		end
		local disposition, safe = _om._tj_pickup_disposition(pickup_name)
		if disposition == _om.thrown_wire_policy.DROP then
			printf("[cwv:424] dropped pickup SUPPRESSED %s (no exact row and no proven vanilla donor)", tostring(pickup_name))
			return
		elseif disposition == _om.thrown_wire_policy.SUBSTITUTE then
			printf("[cwv:424] dropped pickup wire-safe %s -> %s", tostring(pickup_name), tostring(safe))
			return func(self, safe, ...)
		end
		return func(self, pickup_name, ...)
	end)
	_om._tj_pickup_wire_hook_installed = true

	-- issue 424 (BUG_CLASSES 31): in-flight projectile husk / projectile_units axis.
	-- The Tuskgor Javelin BOMB throws a boar-spear in-flight unit that is a cwv-only
	-- NetworkLookup.husks key; ProjectileSystem.spawn_player_projectile spawns it via
	-- spawn_network_unit (projectile_system.lua:247-249), and the same cwv
	-- projectile_units_template rides TransientPackageLoader.hot_join_sync
	-- (transient_package_loader.lua:187-193). Substitute the resolved projectile_units
	-- (returned by _get_projectile_units_names, projectile_system.lua:159-176) to the
	-- vanilla "javelin" entry so the projectile GameObject encodes a vanilla husk and
	-- the transient sync encodes a vanilla projectile_units index; a joining/present
	-- non-cwv peer never cold-decodes an appended index. Cosmetic only (in-flight mesh
	-- becomes the slim vanilla javelin); the action's impact_data/damage are untouched.
	-- Sole cwv hook on this method (grep-verified). Ungateable pure swap.
	mod:hook("ProjectileSystem", "_get_projectile_units_names", function(func, self, projectile_info, owner_unit)
		return _om._wire_safe_projectile_units(func(self, projectile_info, owner_unit))
	end)
	_om._projectile_wire_hook_installed = true

	-- Path A server-side: PickupSystem.rpc_spawn_linked_pickup.
	mod:hook("PickupSystem", "rpc_spawn_linked_pickup", function(func, self, channel_id, pickup_name_id, link_position, link_rotation, spawn_type_id, hit_unit_go_id, node_index, is_level_unit, spawn_limit, material_settings_name_id)
		local pickup_name = NetworkLookup and NetworkLookup.pickup_names and rawget(NetworkLookup.pickup_names, pickup_name_id)
		if _is_our_pickup(pickup_name) then
			_dbg("[cwv stick] PATH A rpc_spawn_linked_pickup fired (pickup=%s)", tostring(pickup_name))
			_log_quat("  input ", link_rotation)
			local cleaned, ok = _clean_horizontal_rotation(link_rotation)
			if ok then link_rotation = cleaned; _log_quat("  output", link_rotation)
			else _dbg("  forward is near-vertical; skipping correction") end
		end
		return func(self, channel_id, pickup_name_id, link_position, link_rotation, spawn_type_id, hit_unit_go_id, node_index, is_level_unit, spawn_limit, material_settings_name_id)
	end)

	-- Path B server-side: ProjectileSystem.rpc_spawn_pickup_projectile (DIFFERENT
	-- class than PickupSystem). Pickup has physics so it bounces/lands rather
	-- than sticking; align rotation with velocity for a sensible resting pose.
	mod:hook("ProjectileSystem", "rpc_spawn_pickup_projectile", function(func, self, channel_id, projectile_unit_name_id, projectile_unit_template_name_id, network_position, network_rotation, network_velocity, network_angular_velocity, pickup_name_id, pickup_spawn_type_id, spawn_limit, always_show, objective_active, material_settings_name_id)
		local pickup_name = NetworkLookup and NetworkLookup.pickup_names and rawget(NetworkLookup.pickup_names, pickup_name_id)
		if _is_our_pickup(pickup_name) then
			_dbg("[cwv stick] PATH B rpc_spawn_pickup_projectile fired (pickup=%s)", tostring(pickup_name))
			local vel = AiAnimUtils.velocity_network_scale(network_velocity)
			if vel and Vector3.length(vel) > 0.1 then
				local fwd = Vector3.normalize(vel)
				local cleaned = Quaternion.look(fwd, Vector3.up())
				network_rotation = AiAnimUtils.rotation_network_scale(cleaned, true)
				_log_quat("  velocity-aligned", cleaned)
			end
		end
		return func(self, channel_id, projectile_unit_name_id, projectile_unit_template_name_id, network_position, network_rotation, network_velocity, network_angular_velocity, pickup_name_id, pickup_spawn_type_id, spawn_limit, always_show, objective_active, material_settings_name_id)
	end)

	-- v0.1.248: parent→visual map for the outline mirror hook below. Weak keys so
	-- entries auto-clear when a parent unit gets GC'd without _detach firing.
	local _carrier_visuals = setmetatable({}, { __mode = "k" })

	-- Carrier-unit pattern (v0.1.164, hook target fixed in v0.1.172): when our
	-- pickup spawns (the throwing axe pup unit — chosen for its baked-in
	-- interaction collision actors), spawn the boar spear _3p mesh as a visual
	-- on top, link it to the parent's transform so it follows wall-stuck
	-- position/rotation, and shrink the parent to near-zero scale so only the
	-- boar spear is visible.
	--
	-- v0.1.172 fix: hook target was `PickupUnitExtension` (base class) and
	-- silently never fired. Per memory `feedback_vt2_class_hook_derived.md`,
	-- VT2's class() copies methods into derived classes at definition time, so
	-- a hook on the base never fires for derived-class instances. Our pickup
	-- uses `unit_template_name = "limited_owned_pickup_unit"` which instantiates
	-- `LimitedOwnedPickupUnitExtension`. Hook the derived class instead, plus
	-- the two siblings as cheap insurance for future variants.
	local function _attach_carrier_visual(self)
		if not _is_our_pickup(self.pickup_name) then return end
		local parent = self.unit
		if not parent then return end
		_dbg("[cwv stick] extensions_ready fired (pickup=%s)", tostring(self.pickup_name))

		-- Clean rotation — orient the parent so the spear visual hangs off it
		-- pointing into the wall.
		local current_rot = Unit.world_rotation(parent, 0)
		local cleaned, did_clean = _clean_horizontal_rotation(current_rot)
		if did_clean then
			Unit.set_local_rotation(parent, 0, cleaned)
		end

		-- Spawn boar spear visual at parent's pose, pulled back along the
		-- forward (into-wall) axis so the spear doesn't sit too deep in the
		-- geometry. See _TJ_VISUAL_PULL_BACK_M for the offset.
		local world = self.world or (Managers.world and Managers.world:world("level_world"))
		if not world then return end
		local pos = Unit.world_position(parent, 0)
		local rot = Unit.world_rotation(parent, 0)
		if _TJ_VISUAL_PULL_BACK_M and _TJ_VISUAL_PULL_BACK_M ~= 0 then
			local fwd = Quaternion.forward(rot)
			pos = pos - fwd * _TJ_VISUAL_PULL_BACK_M
		end
		local ok_spawn, visual = pcall(World.spawn_unit, world, _TJ_BOAR_SPEAR_UNIT, pos, rot)
		if not ok_spawn or not visual then
			mod:warning("[cwv stick] failed to spawn boar spear visual: %s", tostring(visual))
			return
		end

		-- v0.1.175: do NOT link visual to parent. World.link_unit composes the
		-- child's transform with the parent's, so shrinking the parent to 0.001
		-- scale (below) made the boar spear inherit that scale and disappear
		-- too. For our use case the pickup is static (link_pickup attaches it
		-- to a wall via projectile_linker_system, parent doesn't move after
		-- spawn), so the visual doesn't need to track the parent. Spawn at
		-- parent's pose once, leave as free-standing world unit at scale 1.0.
		-- Edge case: javelins stuck in moving enemies won't have visual follow;
		-- revisit if that materializes in practice.

		-- v0.1.183: switched from scale-to-tiny hide to Unit.set_unit_visibility.
		-- Scale-to-0.001 also shrunk the OutlineExtension's silhouette target,
		-- killing the white tagged-pickup outline. Visibility is a render flag
		-- independent of physics — actors still detect interaction, mesh isn't
		-- drawn, and the outline shader may still compute on the hidden mesh
		-- (the shader's target rect is per-unit metadata, not directly tied to
		-- the rendered pass). If the outline is STILL missing after this change,
		-- the OutlineExtension genuinely needs a visible mesh and we'll need to
		-- attach it to the boar spear visual instead.
		pcall(Unit.set_unit_visibility, parent, false)

		self._cwv_visual_unit = visual
		self._cwv_world       = world
		_carrier_visuals[parent] = visual
		_dbg("[cwv stick] carrier visual attached: parent=%s child=%s", tostring(_TJ_PICKUP_UNIT), tostring(_TJ_BOAR_SPEAR_UNIT))
	end

	local function _detach_carrier_visual(self)
		if self.unit then _carrier_visuals[self.unit] = nil end
		if not self._cwv_visual_unit then return end
		local visual = self._cwv_visual_unit
		self._cwv_visual_unit = nil
		if Managers and Managers.state and Managers.state.unit_spawner then
			pcall(function() Managers.state.unit_spawner:mark_for_deletion(visual) end)
		elseif self._cwv_world then
			pcall(World.destroy_unit, self._cwv_world, visual)
		end
	end

	-- v0.1.248: mirror outline_unit calls from parent (hidden) → visual.
	-- Why: `Unit.set_unit_visibility(parent, false)` (the hide path used by the
	-- carrier pattern since v0.1.190) excludes the parent from every render pass,
	-- including the outline pass. Tagged-pickup outlines stopped showing because
	-- the engine outlines the parent throwing-axe unit, not our visual boar
	-- spear. Forwarding every outline_unit call onto the visual gives it the
	-- same outline state without needing the parent visible.
	mod:hook("OutlineSystem", "outline_unit", function(func, self, unit, flag, channel, do_outline, apply_method, outline_settings)
		local visual = _carrier_visuals[unit]
		if visual and Unit.alive(visual) then
			pcall(func, self, visual, flag, channel, do_outline, apply_method, outline_settings)
		end
		return func(self, unit, flag, channel, do_outline, apply_method, outline_settings)
	end)

	mod:hook_safe("LimitedOwnedPickupUnitExtension", "extensions_ready", _attach_carrier_visual)
	mod:hook_safe("LifeTimePickupUnitExtension",     "extensions_ready", _attach_carrier_visual)
	mod:hook_safe("PlayerTeleportingPickupExtension","extensions_ready", _attach_carrier_visual)
	mod:hook_safe("LimitedOwnedPickupUnitExtension", "destroy",          _detach_carrier_visual)
	mod:hook_safe("LifeTimePickupUnitExtension",     "destroy",          _detach_carrier_visual)
	mod:hook_safe("PlayerTeleportingPickupExtension","destroy",          _detach_carrier_visual)

	-- Linker-extension branch (rare).
	mod:hook("ProjectileLinkerSystem", "link_pickup", function(func, self, pickup_unit, link_position, link_rotation, hit_unit, node_index)
		local ok, pickup_name = pcall(Unit.get_data, pickup_unit, "pickup_name")
		if ok and _is_our_pickup(pickup_name) then
			_dbg("[cwv stick] link_pickup fired (linker-extension branch, pickup=%s)", tostring(pickup_name))
			_log_quat("  input ", link_rotation)
			local cleaned, did = _clean_horizontal_rotation(link_rotation)
			if did then link_rotation = cleaned; _log_quat("  output", link_rotation) end
		end
		return func(self, pickup_unit, link_position, link_rotation, hit_unit, node_index)
	end)

	local function _clone_inline_throw_profile(source_name, prefix, damage_mult)
		if not DamageProfileTemplates then return source_name end
		local source = DamageProfileTemplates[source_name]
		if not source then return source_name end

		local new_name = prefix .. source_name
		_om._record_cwv_dp_source(new_name, source_name)   -- issue 423 wire-safe map
		if DamageProfileTemplates[new_name] then return new_name end

		local clone = table.clone(source, true)

		-- thrown_javelin shape (verified against
		-- damage_profile_templates_dlc_woods.lua:263): default_target carries
		-- power_distribution_near / power_distribution_far, each with .attack
		-- (damage) and .impact (stagger). We multiply only .attack so "double
		-- damage" doesn't accidentally amp stagger too. Also handle the generic
		-- power_distribution case in case a future thrown profile uses it.
		local function scale_target(target)
			if type(target) ~= "table" then return end
			if target.power_distribution_near and target.power_distribution_near.attack then
				target.power_distribution_near.attack = target.power_distribution_near.attack * damage_mult
			end
			if target.power_distribution_far and target.power_distribution_far.attack then
				target.power_distribution_far.attack = target.power_distribution_far.attack * damage_mult
			end
			if target.power_distribution and target.power_distribution.attack then
				target.power_distribution.attack = target.power_distribution.attack * damage_mult
			end
		end

		scale_target(clone.default_target)
		if type(clone.targets) == "table" then
			for _, t in ipairs(clone.targets) do scale_target(t) end
		end

		DamageProfileTemplates[new_name] = clone

		if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, new_name) then
			local tbl = NetworkLookup.damage_profiles
			local idx = #tbl + 1
			rawset(tbl, idx, new_name)
			rawset(tbl, new_name, idx)
		end

		return new_name
	end

	-- Module-scope so it can't be re-created per call (Lua closure identity matters
	-- for VMF hook bookkeeping, and the function is small enough to share).
	local function _always_false() return false end

	-- 3P body wield routing for Tuskgor Javelin (Kruber + Saltzpyre variants).
	-- Each character body has a different "spear+shield" sub-graph in its master SM:
	--   * Kruber  (empire-soldier 3P body): es_deus_01 — Empire Chaos Wastes spear+shield
	--   * Saltzpyre wh_captain/bountyhunter/zealot (witch-hunter 3P body): no native
	--     spear+shield SM, falls back to 1h_sword_shield (closest in-stance analog)
	--   * Saltzpyre wh_priest: native 1h_hammer_shield (warrior priest stance)
	-- Mappings sourced from weapon_tweaker.lua's _career_anim_redirect / _suffix_career_map
	-- which already encodes the cross-character spear+shield routing rules.
	local _tj_wield_3p_by_career = {
		es_mercenary      = "to_es_deus_01",
		es_huntsman       = "to_es_deus_01",
		es_knight         = "to_es_deus_01",
		es_questingknight = "to_es_deus_01",
		wh_captain        = "to_1h_sword_shield",
		wh_bountyhunter   = "to_1h_sword_shield",
		wh_zealot         = "to_1h_sword_shield",
		wh_priest         = "to_1h_hammer_shield",
	}

	-- 3P body event remap for Tuskgor Javelin. Routes the elf javelin template's
	-- action events to events that are commonly authored across es_deus_01,
	-- 1h_sword_shield, AND 1h_hammer_shield — so the same anim_event_3p plays
	-- visibly regardless of which sub-graph the body wielded into. Verified
	-- against the source templates: attack_swing_stab, attack_swing_charge_stab,
	-- attack_swing_heavy_stab, attack_swing_heavy_left, attack_push, parry_pose
	-- all appear in 1h_swords_shield.lua, es_deus_01.lua, and dual_wield_hammers_priest
	-- families (the priest hammer+shield template uses these too).
	--
	-- TRADE-OFF: shield-stance SMs are MELEE-ONLY. attack_throw and throw_charge
	-- have no equivalent — body stands still during the throw windup/release while
	-- the projectile system fires the javelin from 1P. Throw mechanics still work
	-- (projectile spawn / damage / pickup are separate from the 3P clip); just no
	-- visible body throw motion. Same for `reload`. User-accepted trade vs.
	-- keeping the elf javelin SM (which may not be authored on Kruber/Saltzpyre
	-- 3P bodies, leading to silent wield failure).
	--
	-- 1P UNCHANGED: the source javelin SM remains the 1P state_machine and handles
	-- all 1P playback (including throw windup) correctly via first_person_base.
	local _tj_anim_remap = {
		-- Light combo chain: 3-step stab progression
		attack_chain_01          = "attack_swing_stab",
		attack_chain_02          = "attack_swing_heavy_left",   -- left-side strike for variety
		attack_chain_03          = "attack_swing_heavy_stab",   -- combo finisher
		-- Directional lights → stab-flavored events
		attack_swing_left        = "attack_swing_heavy_left",
		attack_swing_right       = "attack_swing_stab",
		attack_swing_up          = "attack_swing_heavy_stab",
		-- Charges/heavy stabs
		attack_swing_charge      = "attack_swing_charge_stab",
		attack_swing_stab_charge = "attack_swing_charge_stab",
		attack_swing_stab_02     = "attack_swing_heavy_stab",
		-- attack_swing_stab unchanged (universal across all three target SMs)
		-- attack_throw, throw_charge, reload: deliberately not remapped — see header
	}

	-- Careers that need the base-template wield-patch for the inventory previewer
	-- (HeroPreviewer reads BASE javelin_template, not our clone — same pattern as
	-- elven_sword_shield and imperial_dual_swords). Same set as the keys of
	-- _tj_wield_3p_by_career, but kept ordered for the loop.
	local _tj_kruber_saltzpyre_careers = {
		"es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
		"wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest",
	}

	-- ANIM ADDENDUM: this function only touches stats + (eventually) 3P fields.
	-- 1P is universal across characters — see top-of-file ANIMATION ARCHITECTURE.
	local function _create_tuskgor_javelin_template()
		if not Weapons or not Weapons.javelin_template then
			mod:warning("javelin_template not found — Tuskgor Javelin stat modifications unavailable")
			return
		end
		if Weapons.tuskgor_javelin_template then return end

		local template = table.clone(Weapons.javelin_template, true)

		-- Ammo system rewrite: finite stack, vanilla pickups refill.
		if template.ammo_data then
			template.ammo_data.max_ammo            = _TJ_MAX_AMMO
			template.ammo_data.block_ammo_pickup   = false
			template.ammo_data.unique_ammo_type    = false
			-- Keep ammo_per_clip / ammo_per_reload at 1 (vanilla) — those control
			-- how many javelins are "drawn" per reload anim, not pickup behaviour.
		end

		-- Disable the magic auto-catch reload (vanilla refills on-demand).
		if template.actions.weapon_reload and template.actions.weapon_reload.default then
			template.actions.weapon_reload.default.condition_func       = _always_false
			template.actions.weapon_reload.default.chain_condition_func = _always_false
		end

		-- Half throw speed: extend wind-up before the projectile fires.
		if template.attack_meta_data and template.attack_meta_data.minimum_charge_time then
			template.attack_meta_data.minimum_charge_time =
				template.attack_meta_data.minimum_charge_time * (1 / _TJ_SPEED_MULT)
		end

		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						-- anim_time_scale (mostly a no-op for javelin — kept for parity
						-- with the other template clones in case a sub-action does set it)
						if sub_action.anim_time_scale then
							sub_action.anim_time_scale = sub_action.anim_time_scale * _TJ_SPEED_MULT
						end
						-- Slow the throw action: total_time + minimum_hold_time.
						-- fire_time stays put — moving it would desync the projectile
						-- spawn point on the animation.
						if sub_action.kind == "thrown_projectile" then
							if sub_action.total_time and sub_action.total_time ~= math.huge then
								sub_action.total_time = sub_action.total_time * (1 / _TJ_SPEED_MULT)
							end
							if sub_action.minimum_hold_time then
								sub_action.minimum_hold_time = sub_action.minimum_hold_time * (1 / _TJ_SPEED_MULT)
							end
							-- Projectile flight speed (sub_action.speed) — slower in-air
							-- velocity. Distinct from the action timing fields above:
							-- those control wind-up/recovery, this controls how fast the
							-- thrown javelin actually travels.
							if sub_action.speed then
								sub_action.speed = sub_action.speed * _TJ_PROJECTILE_SPEED_MULT
							end
							-- Throwing-axe-style stick + pickup. Vanilla javelin uses
							-- `link = true` + `wall_nail = true` + `flow_event_on_walls
							-- = "teleport_out"` (the magic auto-recall behavior). Strip
							-- those and replace with the throwing-axe combo:
							-- `link_pickup = true` + `pickup_settings = {...}`. The
							-- engine then spawns a pickup on the stuck projectile that
							-- the player can walk up to and grab for +1 ammo.
							-- Reference: 1h_throwing_axes.lua:80-89 / 163-172.
							if sub_action.impact_data then
								local imp = sub_action.impact_data
								imp.link                  = nil
								imp.wall_nail             = nil
								imp.flow_event_on_init    = nil
								imp.flow_event_on_walls   = nil
								imp.link_pickup           = true
								imp.no_stop_on_friendly_fire = true
								imp.pickup_settings       = {
									use_weapon_skin = true,
									link_hit_zones  = { "head", "neck", "torso" },
								}
								-- v0.1.123: vanilla javelin depth = 0.7 buries most of
								-- the spear shaft in the wall; user reports "sticks
								-- way too deep". Throwing axe uses 0.2; pick 0.25 for
								-- a long polearm so the tip + a bit of shaft penetrates
								-- while most of the shaft sticks out.
								imp.depth                 = 0.25
								imp.depth_offset          = -0.2
							end
						end
						-- Melee stab damage profiles use the PowerLevelTemplates
						-- string-key indirection — existing helper handles those.
						if sub_action.damage_profile then
							sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_tj_", {
								damage = _TJ_DAMAGE_MULT,
							})
						end
						-- Throw projectile damage profile is INLINE — needs the
						-- inline-clone helper, not the string-key one.
						if sub_action.impact_data and sub_action.impact_data.damage_profile then
							sub_action.impact_data.damage_profile = _clone_inline_throw_profile(
								sub_action.impact_data.damage_profile, "cwv_tj_", _TJ_DAMAGE_MULT
							)
						end
						-- 3P body anim remap: route elf javelin events to
						-- 1h_spear_shield-vocab events so Kruber/Saltzpyre's
						-- 3P bodies play visible spear stabs for the melee combo.
						-- Throw/reload events deliberately not remapped — see
						-- _tj_anim_remap header for rationale.
						if sub_action.anim_event and _tj_anim_remap[sub_action.anim_event] then
							sub_action.anim_event_3p = _tj_anim_remap[sub_action.anim_event]
						end
					end
				end
			end
		end

		-- 3P wield: route each cwv-javelin career into its character body's native
		-- spear+shield sub-graph (or closest analog for Saltzpyre, which has no
		-- native spear+shield SM). Elf careers (we_*) wielding the vanilla
		-- we_javelin keep their native to_javelin wield because we patch only
		-- the cwv-using careers below.
		template.wield_anim_3p = "to_es_deus_01"  -- default for unrecognised careers
		template.wield_anim_career_3p = template.wield_anim_career_3p or {}
		for career, wield in pairs(_tj_wield_3p_by_career) do
			template.wield_anim_career_3p[career] = wield
		end

		Weapons.tuskgor_javelin_template = template

		-- BASE TEMPLATE PATCH: HeroPreviewer (inventory character preview) reads
		-- the base javelin_template's wield_anim_career_3p, NOT our clone's, so
		-- the menu preview pose follows the vanilla javelin wield unless we
		-- patch the base. Scoped tightly to Kruber + Saltzpyre careers so elf
		-- careers fall through to the original wield_anim. Same pattern as
		-- _create_imperial_dual_swords_template / _create_elven_sword_shield_template.
		local base = Weapons.javelin_template
		if base then
			base.wield_anim_career_3p = base.wield_anim_career_3p or {}
			for career, wield in pairs(_tj_wield_3p_by_career) do
				base.wield_anim_career_3p[career] = wield
			end
		end
		mod:info("Created tuskgor_javelin_template (max_ammo=%d, ammo_pickups=on, no auto-catch, link_pickup stick, %.0f%% dmg, %.0f%% action speed, %.0f%% projectile speed, 3p wield=es_*->to_es_deus_01, wh_*->to_1h_sword_shield, wh_priest->to_1h_hammer_shield)",
			_TJ_MAX_AMMO, _TJ_DAMAGE_MULT * 100, _TJ_SPEED_MULT * 100, _TJ_PROJECTILE_SPEED_MULT * 100)
	end

	_register_tuskgor_javelin_assets()
	_create_tuskgor_javelin_template()

	-- ============================================================================
	-- issue 424: fail-closed mixed-lobby Tuskgor Javelin feature gate.
	-- ORDER MATTERS: the exact thrown channel must exist before the gate installs,
	-- because gate_state() reads mod._cwv_thrown_wire_safe. Both run AFTER
	-- _register_tuskgor_javelin_assets so every appended row is capturable.
	_om.exact_wire_runtime.install_thrown(mod, _om, _G, _om._TJ_WIRE_SPEC)
	_om.javelin_gate.install({
		mod = mod,
		om = _om,
		pickup_key = _TJ_PICKUP_KEY,
		link_pickup_key = _TJ_LINK_PICKUP_KEY,
		projectile_key = _TJ_PROJECTILE_KEY,
		inflight_unit = _TJ_BOAR_SPEAR_UNIT,
		safe_template_key = _om._TJ_INFLIGHT_SAFE_TEMPLATE,
		wire_safe = mod._cwv_thrown_wire_safe,
		catalog_intact = mod._cwv_thrown_catalog_intact,
		donor_policy = _om.thrown_wire_policy,
		globals = _G,
	})

	-- ============================================================================
	-- Tuskgor Javelin (BOMB SLOT) — single-use thrown spear "grenade"  (v0.1.352-dev)
	-- ============================================================================
	-- A NEW archetype for CWV: an item that lives in slot_grenade (the bomb slot)
	-- rather than a backend weapon slot. It is acquired via a NEW grenade pickup
	-- injected into Pickups.grenades — it does NOT replace frag/fire bombs, it just
	-- joins the bomb-pickup pool that can spawn in every game mode.
	--
	-- BEHAVIOUR (per user 2026-06-29): NOT a bomb. It is the literal javelin throw
	-- in the grenade slot — a single straight-flying spear that:
	--   * pierces ARMOUR  (damage profile armor_modifier raised across the board)
	--   * penetrates SEVERAL enemies in a line: cleave_distribution drives the
	--     projectile's _max_mass (player_projectile_unit_extension.lua get_max_targets),
	--     so the spear keeps travelling until cumulative enemy mass is spent, THEN
	--     links/sticks (link/wall_nail).
	--   * goes through SHIELDS  (thrown_javelin damage profile shield_break = true)
	--   * high damage to MONSTERS + on HEADSHOT (power scale + headshot boost curve)
	--   * single use (ammo_data.max_ammo = 1, destroy_when_out_of_ammo = true)
	--
	-- WHY it can't use the normal _variant_definitions path: slot_grenade items are
	-- stored_in_backend = false, never equipped from the keep, and resolved via
	-- ItemMasterList[key].temporary_template -> Weapons[name]. So it is registered
	-- directly as ItemMasterList entry + Weapons template + Pickups.grenades entry,
	-- NOT a MoreItemsLibrary backend item.
	--
	-- MECHANICS CONFIRMED (decompiled source, 2026-06-29):
	--   * kind = "thrown_projectile" => ActionThrownProjectile is registered for
	--     everyone (weapon_unit_extension.lua:101-106 merges every DLC's
	--     action_classes_lookup; throwing axes ship with the game). It applies
	--     DIRECT impact damage from impact_data.damage_profile with NO aoe / NO
	--     explosion — unlike kind="charged_projectile" (vanilla grenades) which
	--     always explodes.
	--   * Pickup pool: pickup_system reads Pickups.grenades directly via weighted
	--     random; AllPickups + NetworkLookup.pickup_names are built at boot, so a
	--     post-boot mod entry must be mirrored in manually (same as the ranged
	--     javelin's ammo pickups above). The grenade group is renormalised to sum
	--     to 1.0 (guards the pickup-sampler total<1.0 crash class).
	--   * MP: the equipped grenade syncs by item_name index (rpc_add_equipment ->
	--     NetworkLookup.item_names); the husk (remote) view reads right_hand_unit
	--     from the ItemMasterList entry; the HUD slot icon reads ItemMasterList.hud_icon.
	--   * Mesh load: PickupPackageLoader._load_pickup preloads the temporary_template's
	--     right/left_hand_unit (+_3p), so the boar spear loads automatically for the
	--     pickup; its _3p IS the projectile unit, already husk-registered by
	--     _register_tuskgor_javelin_assets above (ProjectileUnits "cwv_tuskgor_javelin").
	--
	-- Wrapped in do...end so its locals release back to the top-level chunk
	-- (Lua 5.1 200-local limit — this file is large).
	do
		local _TJB_TEMPLATE_NAME    = "cwv_tuskgor_javelin_bomb_template"
		local _TJB_ITEM_KEY         = "cwv_grenade_tuskgor_javelin"
		local _TJB_PICKUP_KEY       = "cwv_tuskgor_javelin_bomb"
		local _TJB_DAMAGE_PROFILE   = "cwv_tuskgor_javelin_bomb"
		local _TJB_PROJECTILE_INFO  = "cwv_tuskgor_javelin_bomb"
		-- Reuse the ranged javelin's boar-spear ProjectileUnits entry (registered +
		-- husk-injected by _register_tuskgor_javelin_assets above).
		local _TJB_PROJECTILE_UNITS = _TJ_PROJECTILE_KEY   -- "cwv_tuskgor_javelin"
		local _TJB_HELD_UNIT        = "units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01"
		-- Interim world-pickup model: the frag-bomb pickup unit (has interaction
		-- actors + is always loaded). A spear-shaped carrier pickup can replace this
		-- later (see the ranged javelin's throwing-axe-pup carrier pattern).
		local _TJB_PICKUP_UNIT      = "units/weapons/player/pup_grenades/pup_grenade_01_t1"
		local _TJB_SPAWN_SHARE      = 0.15   -- fraction of grenade-pool rolls that are the javelin
		local _TJB_DAMAGE_MULT      = 2.5
		local _TJB_DEPTH            = 1.5
		local _TJB_CLEAVE           = 2.5
		local _TJB_HEADSHOT_BOOST   = 3.0
		local _TJB_THROW_SPEED      = 5000

		-- Feature master switch (declared HERE, above every register/inject function,
		-- so all of them capture it as an upvalue -- a local declared below them would
		-- be invisible to the closures and silently resolve to a nil global).
		--
		-- ⚠ TEMPORARILY DISABLED (v0.1.354-dev) — REGRESSION TRIAGE.
		-- After this bomb-slot block was added (v0.1.352/.353), the user reported
		-- that ALL CWV variant weapons stopped appearing (musket, dual axes,
		-- axe+shield, etc.). The 23.56 log shows the mod loading fully with NO
		-- registration error, so the cause is a global side-effect of running this
		-- block at file load (suspects: NetworkLookup.item_names injection, the
		-- Pickups.grenades renormalise, or the javelin_template clone). Guarded OFF
		-- to restore content immediately; if content returns with this off, the
		-- cause is confirmed here and the feature is re-introduced surgically. This
		-- is SEPARATE from the peer-parity gate below (issue 371): the gate governs
		-- WHEN the pool injects in a mixed lobby; this switch governs WHETHER the
		-- feature exists at all while the load-time regression is unresolved.
		local _TJB_FEATURE_ON = false

		-- 1. Damage profile — buffed thrown_javelin (armour pierce, multi-pierce,
		--    monster + headshot damage; keeps shield_break). Deep-cloned so the
		--    vanilla thrown_javelin (used by the ranged javelin + Kerillian) is
		--    untouched.
		local function _register_profile()
			if not DamageProfileTemplates then return end
			if DamageProfileTemplates[_TJB_DAMAGE_PROFILE] then return end
			local source = DamageProfileTemplates.thrown_javelin
			if not source then
				mod:warning("thrown_javelin damage profile missing — bomb javelin unavailable")
				return
			end
			local p = table.clone(source, true)
			p.shield_break = true
			local function bump_armor(m)
				if m and m.attack then
					for i = 1, #m.attack do m.attack[i] = math.max(m.attack[i], 1.5) end
				end
			end
			bump_armor(p.armor_modifier_near)
			bump_armor(p.armor_modifier_far)
			p.cleave_distribution = p.cleave_distribution or {}
			p.cleave_distribution.attack = _TJB_CLEAVE
			p.cleave_distribution.impact = _TJB_CLEAVE
			if p.default_target then
				p.default_target.boost_curve_coefficient_headshot = _TJB_HEADSHOT_BOOST
				local function scale(t) if t and t.attack then t.attack = t.attack * _TJB_DAMAGE_MULT end end
				scale(p.default_target.power_distribution_near)
				scale(p.default_target.power_distribution_far)
				scale(p.default_target.power_distribution)
			end
			DamageProfileTemplates[_TJB_DAMAGE_PROFILE] = p
			if NetworkLookup and NetworkLookup.damage_profiles
				and not rawget(NetworkLookup.damage_profiles, _TJB_DAMAGE_PROFILE) then
				local tbl = NetworkLookup.damage_profiles
				local idx = #tbl + 1
				rawset(tbl, idx, _TJB_DAMAGE_PROFILE)
				rawset(tbl, _TJB_DAMAGE_PROFILE, idx)
			end
		end

		-- 2. Projectile — boar spear in flight (NOT the woods-DLC elf javelin unit,
		--    which isn't loaded for our item). Reuses the husk-registered boar-spear
		--    ProjectileUnits entry.
		local function _register_projectile()
			if not Projectiles or not Projectiles.javelin then
				mod:warning("Projectiles.javelin missing — bomb javelin projectile unavailable")
				return
			end
			if Projectiles[_TJB_PROJECTILE_INFO] then return end
			local p = table.clone(Projectiles.javelin, true)
			p.projectile_units_template = _TJB_PROJECTILE_UNITS
			p.use_weapon_skin = false
			Projectiles[_TJB_PROJECTILE_INFO] = p
		end

		-- 3. Weapon template — the JAVELIN moveset (melee stabs + aimed throw) made
		--    into a ONE-SHOT consumable that lives in the grenade slot: full size,
		--    keeps the melee attacks, throwing it consumes it (destroy on out-of-ammo).
		--    Cloned from javelin_template (NOT the grenade template) so it carries the
		--    full action set + boot-populated lookup_data; the projectile resolves THIS
		--    template via our ItemMasterList entry's temporary_template
		--    (backend_interface_item.lua:770 reads temporary_template first), so no
		--    runtime template-swap hook is needed.
		local function _register_template()
			if not Weapons then return end
			if Weapons[_TJB_TEMPLATE_NAME] then return end
			local source = Weapons.javelin_template
			if not source then
				mod:warning("javelin_template missing — bomb javelin unavailable")
				return
			end
			local t = table.clone(source, true)

			-- Held mesh: boar spear, FULL SIZE (no scale override anywhere — the
			-- ranged variant's 0.80 shrink lives on the item def, which this item
			-- does not set).
			t.right_hand_unit = _TJB_HELD_UNIT
			t.left_hand_unit  = _TJB_HELD_UNIT

			-- One-shot: a single javelin, destroyed when thrown. No refill, no
			-- vanilla auto-catch recall.
			if t.ammo_data then
				t.ammo_data.max_ammo = 1
				t.ammo_data.ammo_per_clip = 1
				t.ammo_data.ammo_per_reload = 1
				t.ammo_data.block_ammo_pickup = true
				t.ammo_data.unique_ammo_type = false
				t.ammo_data.reload_on_ammo_pickup = false
				t.ammo_data.destroy_when_out_of_ammo = true
			end
			if t.actions and t.actions.weapon_reload and t.actions.weapon_reload.default then
				local function _false() return false end
				t.actions.weapon_reload.default.condition_func = _false
				t.actions.weapon_reload.default.chain_condition_func = _false
			end

			-- Walk sub-actions: buff the melee stabs, and rewrite the throw to the
			-- buffed boar-spear projectile (direct impact, multi-pierce, no recovery —
			-- it sticks where it lands and is gone).
			for _, action_group in pairs(t.actions) do
				if type(action_group) == "table" then
					for _, sub in pairs(action_group) do
						if type(sub) == "table" then
							-- Melee stab damage (string-key profiles) — buff to match.
							if sub.kind == "sweep" and sub.damage_profile then
								sub.damage_profile = _clone_damage_profile(sub.damage_profile, "cwv_tjb_", { damage = _TJB_DAMAGE_MULT })
							end
							-- The throw (kind = "thrown_projectile").
							if sub.kind == "thrown_projectile" then
								sub.speed = _TJB_THROW_SPEED
								sub.projectile_info = Projectiles[_TJB_PROJECTILE_INFO] or sub.projectile_info
								sub.impact_data = {
									damage_profile = (DamageProfileTemplates[_TJB_DAMAGE_PROFILE] and _TJB_DAMAGE_PROFILE) or "thrown_javelin",
									depth = _TJB_DEPTH,
									depth_damage_modifier_min = 1,
									depth_damage_modifier_max = 1.2,
									depth_offset = -0.2,
									link = true,
									wall_nail = true,
									no_stop_on_friendly_fire = true,
									flow_event_on_init = "link_projectile_show",
									flow_event_on_walls = "teleport_out",
								}
							end
						end
					end
				end
			end

			Weapons[_TJB_TEMPLATE_NAME] = t
			mod:info("Created %s (javelin moveset, one-shot, full size, slot_grenade)", _TJB_TEMPLATE_NAME)
		end

		-- 4. ItemMasterList entry + NetworkLookup.item_names (MP equip sync). Husk
		--    view reads right_hand_unit here; HUD slot icon reads hud_icon here.
		local function _register_item()
			if not ItemMasterList then return end
			if rawget(ItemMasterList, _TJB_ITEM_KEY) then return end
			rawset(ItemMasterList, _TJB_ITEM_KEY, {
				name = _TJB_ITEM_KEY,
				key = _TJB_ITEM_KEY,
				description = "cwv_grenade_tuskgor_javelin_description",
				display_name = "cwv_grenade_tuskgor_javelin_name",
				gamepad_hud_icon = "hud_icon_bomb_01",
				hud_icon = "hud_inventory_icon_bomb",
				inventory_icon = "icons_placeholder",
				is_local = true,
				item_type = "grenade",
				right_hand_unit = _TJB_HELD_UNIT,   -- husk (remote) view reads this
				rarity = "exotic",
				slot_type = "grenade",
				temporary_template = _TJB_TEMPLATE_NAME,
				can_wield = CanWieldAllItemTemplates,
			})
			if NetworkLookup and NetworkLookup.item_names
				and not rawget(NetworkLookup.item_names, _TJB_ITEM_KEY) then
				local tbl = NetworkLookup.item_names
				local idx = #tbl + 1
				rawset(tbl, idx, _TJB_ITEM_KEY)
				rawset(tbl, _TJB_ITEM_KEY, idx)
			end
		end

		-- 5. Pickup settings + resolve-by-name lookups. Registered UNCONDITIONALLY so
		--    every peer can resolve a host-spawned pickup even if their own toggle is
		--    off. AllPickups + Pickups.grenades share the same settings object (as
		--    vanilla does).
		local _pickup_settings = {
			bots_mule_pickup = true,
			consumable_item = true,
			debug_pickup_category = "grenades",
			dupable = true,
			hud_description = "cwv_tuskgor_javelin_bomb",
			individual_pickup = false,
			item_description = "cwv_tuskgor_javelin_bomb",
			item_name = _TJB_ITEM_KEY,
			local_pickup_sound = true,
			only_once = true,
			pickup_sound_event = "pickup_grenade",
			slot_name = "slot_grenade",
			type = "inventory_item",
			unit_name = _TJB_PICKUP_UNIT,
			pickup_name = _TJB_PICKUP_KEY,
			spawn_weighting = 0,   -- set during pool injection (step 6)
		}
		local function _register_pickup_lookups()
			if AllPickups and not AllPickups[_TJB_PICKUP_KEY] then
				AllPickups[_TJB_PICKUP_KEY] = _pickup_settings
			end
			if NetworkLookup and NetworkLookup.pickup_names
				and not rawget(NetworkLookup.pickup_names, _TJB_PICKUP_KEY) then
				local tbl = NetworkLookup.pickup_names
				local idx = #tbl + 1
				rawset(tbl, idx, _TJB_PICKUP_KEY)
				rawset(tbl, _TJB_PICKUP_KEY, idx)
			end
		end

		-- 6. Pool membership — add to Pickups.grenades + renormalise the group to sum
		--    to 1.0. Gated on the local toggle (the host's pool decides what spawns in
		--    their game; clients still resolve via step 5). Runs once (existence guard).
		local function _inject_pool()
			-- Master switch first: with the feature OFF the register functions never
			-- ran, so there is no backing template/ItemMasterList/NetworkLookup entry
			-- and injecting a pool member would spawn an unregistered pickup. The
			-- peer-parity gate calls this as its on_enable, so this guard also keeps
			-- the gate inert while the load-time regression triage is unresolved.
			if not _TJB_FEATURE_ON then return end
			if not Pickups or not Pickups.grenades then return end
			if Pickups.grenades[_TJB_PICKUP_KEY] then return end
			local enabled = true
			local ok, v = pcall(function() return mod:get("enable_cwv_tuskgor_javelin_bomb") end)
			if ok and v == false then enabled = false end
			if not enabled then
				mod:info("Tuskgor Javelin bomb disabled by setting — not added to the grenade pool")
				return
			end
			-- Pre-renorm raw weight so the final normalised share ~= _TJB_SPAWN_SHARE
			-- (the other entries were already normalised to sum ~1.0 at boot).
			_pickup_settings.spawn_weighting = _TJB_SPAWN_SHARE / (1 - _TJB_SPAWN_SHARE)
			Pickups.grenades[_TJB_PICKUP_KEY] = _pickup_settings
			local total = 0
			for _, s in pairs(Pickups.grenades) do total = total + (s.spawn_weighting or 0) end
			if total > 0 then
				for _, s in pairs(Pickups.grenades) do
					s.spawn_weighting = (s.spawn_weighting or 0) / total
				end
			end
			mod:info("Injected '%s' into the grenade pickup pool (share ~%.0f%%)", _TJB_PICKUP_KEY, _TJB_SPAWN_SHARE * 100)
		end

		-- Peer-parity on_disable: pull the bomb back OUT of the grenade pool and
		-- renormalise the remaining entries to sum ~1.0, so a lobby with a non-cwv
		-- peer never has the modded pickup rolled into the world (issue 371/424:
		-- the WORLD/pool pickup is the GAMEPLAY axis that cannot be wire-substituted).
		-- Idempotent: no-op when the bomb was never injected. Inject/eject cycles are
		-- stable -- eject restores the other entries to a ~1.0 sum and inject always
		-- resets the bomb's raw weight to the same pre-norm value.
		local function _eject_pool()
			if not Pickups or not Pickups.grenades then return end
			if not Pickups.grenades[_TJB_PICKUP_KEY] then return end
			Pickups.grenades[_TJB_PICKUP_KEY] = nil
			local total = 0
			for _, s in pairs(Pickups.grenades) do total = total + (s.spawn_weighting or 0) end
			if total > 0 then
				for _, s in pairs(Pickups.grenades) do
					s.spawn_weighting = (s.spawn_weighting or 0) / total
				end
			end
			mod:info("Ejected '%s' from the grenade pickup pool (peer-parity: a peer lacks cwv)", _TJB_PICKUP_KEY)
			-- #424: an already-spawned bomb is retracted by the javelin gate's on_disable.
		end

		-- Registration (UNCONDITIONAL when the feature is on -- class-31: registration
		-- parity is NEVER peer-gated; every peer that has cwv registers the same
		-- damage-profile / projectile / template / ItemMasterList / NetworkLookup /
		-- AllPickups indices). Only the pool INJECTION (what actually spawns in the
		-- world) is the gameplay axis, and that is gated by the peer-parity beacon
		-- below -- NOT called directly here. (_TJB_FEATURE_ON is the separate
		-- load-time-regression master switch declared at the top of this block.)
		if _TJB_FEATURE_ON then
			_register_profile()
			_register_projectile()
			_register_template()
			_register_item()
			_register_pickup_lookups()
		end

		-- Peer-parity gate for the WORLD/pool pickup injection (issue 371 / issue 424
		-- / BUG_CLASSES 31). Registered UNCONDITIONALLY (independent of
		-- _TJB_FEATURE_ON) so the gated-feature registry is populated for the
		-- regression suite; _inject_pool self-guards on _TJB_FEATURE_ON + the setting,
		-- so registering here is fully inert while the master switch is off. When the
		-- feature is on, the beacon calls _inject_pool once all peers are confirmed to
		-- have cwv and _eject_pool the moment one does not -- so a non-cwv client never
		-- has the modded grenade rolled into their world (which would CTD them on the
		-- server-authoritative rpc_spawn_pickup). The NetworkLookup/AllPickups/
		-- ItemMasterList registration above stays unconditional (registration parity
		-- is never gated); only this spawn/pool FEATURE gates.
		_om._TJB_REGISTRATION_UNGATED_MARKER = "cwv-tjb-networklookup-registration-never-peer-gated"
		-- #424: enrol the bomb in the javelin gate's world sweep (install() ran above).
		_om.javelin_gate.fence_pickup(_TJB_PICKUP_KEY)
		if mod._cwv_peer_parity and type(mod._cwv_peer_parity.register_gated_feature) == "function" then
			mod._cwv_peer_parity:register_gated_feature("cwv_tuskgor_javelin_bomb_pool", {
				label      = "cwv_gated_javelin_bomb_pool",
				on_enable  = function() _inject_pool() end,
				on_disable = function() _eject_pool() end,
			})
			mod:info("[cwv:371] gated 'cwv_tuskgor_javelin_bomb_pool' behind peer-parity beacon")
		end

		-- Test/grant command: drop the one-shot Tuskgor Javelin straight into the
		-- local player's bomb slot (bypasses the random pickup pool). Wield it with
		-- the grenade key, then melee-stab or aim+throw; throwing it consumes it.
		mod:command("cwv_give_javelin", "Give the single-use Tuskgor Javelin into your bomb slot", function()
			local player = Managers.player and Managers.player:local_player()
			local unit = player and player.player_unit
			if not (unit and Unit.alive(unit)) then mod:echo("[cwv] no local player unit (be in a level)"); return end
			local inv = ScriptUnit.has_extension(unit, "inventory_system")
			if not inv then mod:echo("[cwv] no inventory extension on player unit"); return end
			local item_data = rawget(ItemMasterList, _TJB_ITEM_KEY)
			if not item_data then mod:echo("[cwv] javelin-bomb item not registered"); return end
			-- The /give path bypasses PickupPackageLoader, which normally preloads the
			-- temporary_template's held + _3p (projectile) units — force-load them so
			-- the held mesh + thrown projectile don't spawn an unloaded unit.
			if Managers.package then
				pcall(function() Managers.package:load(_TJB_HELD_UNIT, "cwv_javelin_bomb", nil, true, true) end)
				pcall(function() Managers.package:load(_TJB_HELD_UNIT .. "_3p", "cwv_javelin_bomb", nil, true, true) end)
			end
			local ok_add, err_add = pcall(function() inv:add_equipment("slot_grenade", item_data) end)
			if not ok_add then mod:echo("[cwv] add_equipment failed: " .. tostring(err_add)); return end
			pcall(function() inv:wield("slot_grenade") end)
			mod:echo("[cwv] Tuskgor Javelin granted to bomb slot — wield (grenade key), melee or aim+throw. One use.")
		end)
	end

	return {
		always_false = _always_false,
	}
end

return install
