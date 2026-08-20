-- _cwv_custom_mesh_runtime.lua
-- CWV custom-mesh runtime owner (#1159).
--
-- Owns ONE question and its answer: what does a MOD-BUNDLED custom weapon mesh
-- need in order to behave, at runtime, like a unit the engine shipped? A custom
-- mesh has no sibling .package file, no entry in the strict
-- NetworkLookup.inventory_packages table, no skeleton for the vanilla template's
-- attachment links, and no flow graph for the weapon FX its actions fire. Each
-- of those gaps used to be patched by a separate inline block in the entry file;
-- they were consolidated here, and this owner now carries their later fixes:
--   * the Old Musket package bridge plus the PackageManager `load` / `unload` /
--     `has_loaded` hooks that map its master-bundled unit paths onto the exact
--     vanilla Handgun packages as balanced lifetime aliases - and the #474
--     `_om._husk_custom_bundle_unit` predicate that lets the husk mesh re-key
--     accept those same two paths (the vanilla-prefix residency gate from issue
--     418 deliberately rejects them);
--   * the forward-only NetworkLookup.inventory_packages aliases: the Old Musket
--     1P/3P pair aliased onto the vanilla empire-handgun indices, plus the #597
--     Greataxe and #604 Crowbill alias installs delegated to their family
--     modules. Forward direction only - the index -> vanilla-name mapping is
--     never overwritten, so no vanilla equip event is hijacked;
--   * four held Old Musket transform profiles (1P/3P x ranged/melee) plus the
--     distinct Loot display-carrier profile, and the canonical attachment
--     profile selector/source every render adapter resolves through;
--   * the #617/#742 texture-policy re-exports and the #1155 Phase 3 appearance
--     pilot `_om.old_musket_appearance`, with the `_om._old_musket_preview_descriptor`
--     / `_om._old_musket_preview_texture_targets` seams and the
--     `mod._cwv_resolve_preview_descriptor` handle the menu owner reads;
--   * the #474 Old Musket stance channel dofile, kept at its exact former
--     position in the load sequence (see ORDERING below);
--   * the v0.1.293 FX-proxy lifecycle - `_om._CWV_OLD_MUSKET_FX_PROXY` and its
--     spawn/destroy pair - with the four `Unit` redirect hooks (`node`,
--     `has_node`, `flow_event`, `set_flow_variable`) that route a lookup on our
--     skeleton-free mesh to the hidden vanilla rifle linked beside it, and the
--     `_om._reapply_old_musket_transforms_all` replay command seam;
--   * the v0.1.290 `GearUtils.link_units` attachment-node filter that drops
--     named rig targets our FBX has no node for (an unfiltered `Unit.node` call
--     on a missing node is an engine-level fatal that pcall cannot catch).
--
-- The original extraction was one contiguous byte-identical move, preserving
-- registration order. Subsequent fixes stay inside this owner so the entry file
-- cannot regain a second custom-mesh decision path.
--
-- BOUNDARY - this owner covers the mesh, not the weapon. It deliberately does
-- NOT hold:
--   * the Old Musket's item, template, stance-swap and ammo behavior, which stay
--     in `_cwv_musket_runtime.lua` and the entry's consolidated
--     `BackendUtils.get_item_template` hook;
--   * the texture/material preflight and single authored-material bind, which
--     stay in `_cwv_old_musket_preview.lua` (this file only re-exports its entry
--     points onto `_om`, exactly as the entry did);
--   * the bayonet child-unit lifecycle and its visibility hooks, which remain in
--     the entry - the bayonet is a second VANILLA unit linked to the rifle, not
--     a custom-mesh gap;
--   * the menu, husk and world presentation surfaces, which keep calling in
--     through the `_om` seams published here.
--
-- ORDERING - the `_cwv_old_musket_wire` dofile sits INSIDE the moved block and
-- stays there, in its original relative position. Its own header explains why
-- that position is load-bearing (its `_om` exports must exist before the fire
-- dispatch above it first runs and before the identity register far below routes
-- into them), and moving the surrounding block wholesale preserves it exactly.
-- A module dofiling a sibling module is the same shape `_cwv_weapon_transform_owner`
-- and `_cwv_appearance_fade` already use.
--
-- Registers exactly eight hooks, each the mod's SOLE registration on its
-- (Class, method) pair: PackageManager.load, PackageManager.unload,
-- PackageManager.has_loaded, Unit.node, Unit.has_node, Unit.flow_event,
-- Unit.set_flow_variable and GearUtils.link_units. VMF silently DROPS a
-- duplicate registration on a pair, so re-adding any of these to the entry would
-- shadow this owner rather than chain with it.
--
-- Load-time deps: the ctx table plus the `_om` slots the entry populates in its
-- module block - `_om.greataxe`, `_om.crowbill_family`, `_om.old_musket_preview`,
-- `_om.old_musket_appearance_policy`, `_om.appearance_descriptor` and
-- `_om.weapon_appearance` (entry lines 58-98). The owner loads at the exact point
-- the moved block ran, so those slots are as populated as they were before.
--
-- The two file-scope locals in the moved range - the custom-package table
-- and `_orig_unit_has_node` - each had ZERO references outside it before the
-- move, so nothing in the entry can reach in here any more. Removing them also
-- buys back two slots against the entry chunk's Lua 5.1 200-local ceiling.
--
-- ctx bindings are all BY VALUE, which is sound because every one of them is
-- declared exactly once at entry file scope, above this load point, and never
-- rebound:
--   om          entry line 55  (`local _om = {}`, mutated in place, never reassigned)
--   dbg         entry line 269 (`local function _dbg`)
--   dbg_alert   entry line 273 (`local function _dbg_alert`)
-- `_om` is passed as a table reference, so every slot this file publishes and
-- every slot it reads later from a hook body stays shared with the entry.
--
-- No native resource boundary moved with this block: it contains no
-- World.create_particles / create_screen_gui / Material.set_texture /
-- Unit.set_texture_for_materials / Managers.package call, so it needs no
-- `-- resource-safety:` marker. The Old Musket texture work it wires up is owned
-- (and annotated) by _cwv_old_musket_preview.lua.
--
-- Named (not anonymous) so the offline forward-reference lint keeps treating the
-- moved block as file-scope code: an anonymous `function(` wrapper makes every
-- construct-then-call pair below read as a closure capturing its own body. See
-- the same note in _cwv_menu_preview_owner.lua.
local function install(mod, ctx)
local _om = ctx.om
local _dbg = ctx.dbg
local _dbg_alert = ctx.dbg_alert

-- ============================================================
-- cwv_es_musket_old — LA-pattern PackageManager hooks
-- ============================================================
-- v0.1.286: completely replaced the v0.1.277-285 overlay system with the
-- Loremaster's Armoury pattern. Our custom mesh path IS the variant's
-- right_hand_unit; vanilla GearUtils spawns it directly, which means the
-- mesh gets the engine's first-person rendering pipeline for free (no
-- shadow in FP, correct depth, draws under the FP hand model).
--
-- The .unit files bind one CWV-owned PBR material from the mod's resident
-- master package. First-person rendering comes from the normal inventory-unit
-- spawn path and the 1P unit's render settings, not from a borrowed material.
--
-- The three hooks below intercept the engine's package_manager.load /
-- unload / has_loaded calls. The custom unit data is already in CWV's master
-- bundle. Map its nonexistent globally discoverable package name onto the
-- exact Handgun package only as a balanced PackageManager lifetime anchor,
-- preserving the caller reference and completion callback. The authored mesh,
-- PBR material and textures remain self-contained in CWV (#474/#742/#1155).
--
-- v0.1.271-276 had this same crash; the early "fix" attempts (sibling
-- packages, .mod packages list, etc.) all failed because the engine's
-- global Application.resource_package only finds vanilla bundles. The
-- The safe form still avoids looking up a nonexistent package; it redirects
-- that lifecycle to an engine-owned package which is globally discoverable.

local _old_musket_package_bridge = mod:dofile(
	"scripts/mods/character_weapon_variants/_cwv_old_musket_package_bridge")
	.new(_om.old_musket_preview)
_om._old_musket_package_bridge = _old_musket_package_bridge

-- (#474) Husk re-key residency arm for MOD-BUNDLED custom meshes. These units
-- live in cwv's own master bundle (always resident while the mod is loaded);
-- their load lifecycle is owned by the LA-pattern PackageManager hooks below,
-- and they must NEVER be queued through the vanilla residency force-load pass
-- (issue 403 boot fatal). `_om._resident_override_3p` deliberately rejects
-- them (vanilla-prefix gate, issue 418), so the husk mesh re-key needs this
-- second predicate to accept a skin-resolved custom mesh (the Old Musket).
-- Requires BOTH the base and "_3p" forms whitelisted: the husk spawn appends
-- "_3p" to whatever lands in item_units.
-- (#719) SECOND admission arm, catalog-driven. The Greataxe (#597) and Crowbill
-- (#604) model meshes are the same KIND of resource as the Old Musket's -- mod
-- master-bundle units outside `units/weapons/player/` -- but they are
-- self-contained: each `.unit` binds its OWN bundled `.material` and textures
-- (units/cwv_crowbill/<model>/<model>.material), so they borrow nothing from a
-- vanilla package and the Old Musket's alias bridge has no pair for them.
-- Before this arm, `_husk_custom_bundle_unit` answered false for every one of
-- them, `_om._resident_override_3p` rejected them on its vanilla-prefix gate
-- (#418) and `_husk_lease_override` rejected them on the same prefix -- so no
-- husk admission path existed at all and a remote peer kept the shadowed
-- bw_1h_crowbill / dr_2h_axe donor for the whole mission (the #719 symptom:
-- observers saw Sienna's Crowbill on Kruber's Imperial Crowbill).
--
-- Each family answers for its OWN authored model catalog (`is_bundled_unit`,
-- derived from the same MODELS rows the package manifest ships), so a model
-- added later is admitted the day it is authored and no key list lives here.
_om._husk_bundled_model_families = { _om.greataxe, _om.crowbill_family }

_om._husk_custom_bundle_unit = function(base_unit)
	if type(base_unit) ~= "string" or base_unit == "" then return false end
	if _old_musket_package_bridge.has_pair(base_unit) then return true end
	for _, family in ipairs(_om._husk_bundled_model_families) do
		if family.is_bundled_unit(base_unit) then return true end
	end
	return false
end

mod:hook(PackageManager, "load", function(func, self, package_name, reference_name, callback, asynchronous, prioritize)
	return _old_musket_package_bridge.load(func, self, package_name, reference_name,
		callback, asynchronous, prioritize)
end)

mod:hook(PackageManager, "unload", function(func, self, package_name, reference_name)
	return _old_musket_package_bridge.unload(func, self, package_name, reference_name)
end)

mod:hook(PackageManager, "has_loaded", function(func, self, package_name, reference_name)
	return _old_musket_package_bridge.has_loaded(func, self, package_name, reference_name)
end)

-- v0.1.287: register custom-mesh unit paths in NetworkLookup.inventory_packages.
-- The engine syncs equip events across multiplayer via this table — when our
-- custom right_hand_unit is equipped, the engine indexes `inventory_packages`
-- by our path. That table has a strict __index that errors on unknown keys
-- (see feedback_vt2_strict_lookup_rawget.md). LA's solution: alias our path
-- to an existing vanilla path's network index (forward direction only — we
-- do NOT overwrite the reverse index->path mapping like LA's skin-replacement
-- code does, because we don't want to hijack vanilla equip events).
-- Crash trail: v0.1.286 — "Table inventory_packages does not contain key:
-- units/cwv_es_musket_custom/cwv_es_musket_custom_3p" on equip.
do
	local nl_inventory = NetworkLookup and NetworkLookup.inventory_packages
	if nl_inventory then
		local vanilla_1p_idx = rawget(nl_inventory, "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1")
		local vanilla_3p_idx = rawget(nl_inventory, "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1_3p")
		if vanilla_1p_idx then
			nl_inventory["units/cwv_es_musket_custom/cwv_es_musket_custom"] = vanilla_1p_idx
		end
		if vanilla_3p_idx then
			nl_inventory["units/cwv_es_musket_custom/cwv_es_musket_custom_3p"] = vanilla_3p_idx
		end
		-- Issue #597: Greataxe model units live in CWV's resident bundle, but
		-- ProfileSynchronizer still serializes their 1P/3P package names through
		-- the vanilla inventory lookup. Forward-alias every custom name to the
		-- matching Bardin Greataxe index; keep index -> vanilla name untouched.
		local installed = _om.greataxe.install_network_package_aliases(nl_inventory)
		if installed > 0 then
			mod:info("[cwv:597] installed %d Greataxe inventory-package wire aliases", installed)
		end
		local crowbill_aliases = _om.crowbill_family.install_network_package_aliases(nl_inventory)
		if crowbill_aliases > 0 then
			mod:info("[cwv:604] installed %d Crowbill inventory-package wire aliases", crowbill_aliases)
		end
	end
end

-- ============================================================
-- cwv_es_musket_old — runtime texture binding + live-tunable transforms
-- ============================================================
-- Defined as GLOBAL (no `local`) so the spawn_inventory_unit hook above
-- (which is parsed before this code) can reach them at call time. Locals
-- are resolved at parse time and wouldn't be visible — see
-- feedback_lua_forward_reference.md.

-- Mutable transform constants. Edit via `cwv_om_pos_*` / `om_rot_*` /
-- `om_scale_*` commands. Split into three buckets:
--   1P RANGED — musket_template (rifle stance)
--   1P MELEE  — musket_template_melee (polearm stance) [TBD]
--   3P        — both modes share (works at identity per v0.1.295 user feedback)
-- v0.1.295 defaults for 1P ranged from user tune: pos (0, 0.62, 0),
-- rot axis (1,1,-1) @ -90°, scale (1, 1.2, 1.4).
-- v0.1.297: rotation state is now a QuaternionBox (or nil for identity). The
-- previous `{ax, ay, az, radians}` axis-angle table couldn't represent
-- composed rotations (e.g., diagonal axis-angle + an additional barrel-roll).
-- Quaternions compose via `Quaternion.multiply(q1, q2)` so the new
-- `cwv_om_rotmul_*` commands can stack rotations on top of whatever's
-- currently applied.
-- v0.1.298: WRAP in `QuaternionBox(...)`. Stingray's raw Quaternion type is
-- a stack-allocated temporary — valid only within the frame it was created.
-- Storing the raw value in a Lua global makes it stale across frames (the
-- memory gets recycled by other Quaternion temporaries). v0.1.297 stored
-- raw Quaternions; the gun appeared correct on first frame after equip but
-- then the rotation became garbage as the temp slot was reused. Vanilla
-- pattern (e.g., `bt_attack_action.lua:99`): `QuaternionBox(rotation)` to
-- box for long-term storage, `:unbox()` to get a fresh raw Quaternion when
-- you need to pass it to an API that wants a raw value.
-- Defaults for 1P-RANGED match v0.1.295 user-tuned values.
_om._CWV_OLD_MUSKET_POS_1P_RANGED   = { 0, 0.62, 0 }
_om._CWV_OLD_MUSKET_ROT_1P_RANGED   = QuaternionBox(Quaternion.axis_angle(Vector3(1, 1, -1), -math.pi / 2))
_om._CWV_OLD_MUSKET_SCALE_1P_RANGED = { 1, 1.2, 1.4 }

-- v0.1.299 1P MELEE defaults from user live-tune: pos (0, 0.06, 0),
-- rot axis (0, 1, 0) @ -90° (pure Y-axis rotation), scale identity.
_om._CWV_OLD_MUSKET_POS_1P_MELEE   = { 0, 0.06, 0 }
_om._CWV_OLD_MUSKET_ROT_1P_MELEE   = QuaternionBox(Quaternion.axis_angle(Vector3(0, 1, 0), -math.pi / 2))
_om._CWV_OLD_MUSKET_SCALE_1P_MELEE = { 1, 1, 1 }

-- v0.1.318: 3P split into _RANGED / _MELEE.
-- v0.1.320: final tuned values from user live-tune:
--   3P-RANGED — pos (0, 0.64, -0.01), rot Euler XYZ (-90, -90, 0), scale (1, 1.1, 1.1)
--   3P-MELEE  — pos (0, 0.045, 0.1) (unchanged from v0.1.318), rot (0, 1, 0) @ -90°
--               (unchanged), scale (1, 1.1, 1.1) (matched to 3P-RANGED per user
--               "do the same scaling for melee as well")
_om._CWV_OLD_MUSKET_POS_3P_RANGED   = { 0, 0.64, -0.01 }
_om._CWV_OLD_MUSKET_ROT_3P_RANGED   = QuaternionBox(Quaternion.from_euler_angles_xyz(-90, -90, 0))
_om._CWV_OLD_MUSKET_SCALE_3P_RANGED = { 1, 1.1, 1.1 }

_om._CWV_OLD_MUSKET_POS_3P_MELEE   = { 0, 0.045, 0.1 }
_om._CWV_OLD_MUSKET_ROT_3P_MELEE   = QuaternionBox(Quaternion.axis_angle(Vector3(0, 1, 0), -math.pi / 2))
_om._CWV_OLD_MUSKET_SCALE_3P_MELEE = { 1, 1.1, 1.1 }

-- #1155: LootItemUnitPreviewer links weapons to a camera-world display carrier,
-- not a character skeleton. Rain's 0.1.523 live run falsified the old assumption
-- that the held-rifle pose could be copied into that parent frame: the Musket
-- hovered high. Zero translation plus the imported rotation/scale is an explicit
-- diagnostic candidate, not a numerically verified final pose. Keeping it in a
-- distinct profile lets the live readback falsify or tune it without changing
-- any character-held surface and without creating one recipe per UI.
_om._CWV_OLD_MUSKET_POS_DISPLAY_3P   = { 0, 0, 0 }
_om._CWV_OLD_MUSKET_ROT_DISPLAY_3P   = QuaternionBox(Quaternion.from_euler_angles_xyz(-90, -90, 0))
_om._CWV_OLD_MUSKET_SCALE_DISPLAY_3P = { 1, 1.1, 1.1 }

_om.old_musket_attachment_profiles = {
	held_1p_rifle = "held_1p_rifle",
	held_1p_polearm = "held_1p_polearm",
	held_3p_rifle_character = "held_3p_rifle_character",
	held_3p_polearm_character = "held_3p_polearm_character",
	display_3p_rifle = "display_3p_rifle",
}

-- #617/#742/#1155: the dedicated policy owns material/texture preflight and
-- the single authored-material bind. There are no runtime texture C writes.
_om._old_musket_texture_resources_ready = _om.old_musket_preview.texture_resources_ready
_om._bind_old_musket_authored_material = _om.old_musket_preview.bind_authored_material
_om._prepare_old_musket_preview_material = _om.old_musket_preview.prepare_preview_material
_om._old_musket_unit_materials_ready = _om.old_musket_preview.unit_materials_ready
_om._apply_old_musket_appearance = _om.old_musket_preview.apply_material
_om._apply_old_musket_textures = _om.old_musket_preview.apply_textures

_om._old_musket_attachment_profile = function(perspective, mode, carrier)
	local profiles = _om.old_musket_attachment_profiles
	if carrier == "display" then return profiles.display_3p_rifle end
	if perspective == "1p" then
		return mode == "melee" and profiles.held_1p_polearm or profiles.held_1p_rifle
	end
	return mode == "melee" and profiles.held_3p_polearm_character
		or profiles.held_3p_rifle_character
end

_om._old_musket_held_profile = function(item_template, perspective, mode)
	return _om.old_musket_preview_pose.resolve_held_attachment_profile(
		item_template, perspective, mode, rawget(_G, "Weapons"),
		_om.old_musket_attachment_profiles)
end

_om._old_musket_transform_profile_components = function(profile)
	local profiles = _om.old_musket_attachment_profiles
	if profile == profiles.held_1p_rifle then
		return _om._CWV_OLD_MUSKET_POS_1P_RANGED, _om._CWV_OLD_MUSKET_ROT_1P_RANGED, _om._CWV_OLD_MUSKET_SCALE_1P_RANGED
	elseif profile == profiles.held_1p_polearm then
		return _om._CWV_OLD_MUSKET_POS_1P_MELEE, _om._CWV_OLD_MUSKET_ROT_1P_MELEE, _om._CWV_OLD_MUSKET_SCALE_1P_MELEE
	elseif profile == profiles.held_3p_rifle_character then
		return _om._CWV_OLD_MUSKET_POS_3P_RANGED, _om._CWV_OLD_MUSKET_ROT_3P_RANGED, _om._CWV_OLD_MUSKET_SCALE_3P_RANGED
	elseif profile == profiles.held_3p_polearm_character then
		return _om._CWV_OLD_MUSKET_POS_3P_MELEE, _om._CWV_OLD_MUSKET_ROT_3P_MELEE, _om._CWV_OLD_MUSKET_SCALE_3P_MELEE
	elseif profile == profiles.display_3p_rifle then
		return _om._CWV_OLD_MUSKET_POS_DISPLAY_3P, _om._CWV_OLD_MUSKET_ROT_DISPLAY_3P, _om._CWV_OLD_MUSKET_SCALE_DISPLAY_3P
	end
	return nil, nil, nil
end

-- Compatibility seam for tuning commands and older diagnostics. New appearance
-- adapters choose by exact attachment profile instead of perspective alone.
_om._old_musket_transform_components = function(perspective, mode)
	return _om._old_musket_transform_profile_components(
		_om._old_musket_attachment_profile(perspective, mode, "character"))
end

-- #1155 Phase 3: one canonical immutable descriptor + one bounded lifecycle
-- reconciler now owns all Old Musket surface application. The policy module
-- above retains only resource preflight; it no longer owns a preview recipe.
_om.old_musket_appearance = _om.old_musket_appearance_policy.new({
	descriptor = _om.appearance_descriptor,
	weapon_appearance = _om.weapon_appearance,
	policy = _om.old_musket_preview,
	unit = Unit,
	vector = { to_elements = Vector3.to_elements },
	-- Retail Quaternion is a callable table; the pilot needs both construction
	-- from descriptor x/y/z/w data and independent `to_elements` readback.
	quaternion = Quaternion,
	transform_profile_source = _om._old_musket_transform_profile_components,
	attachment_profiles = _om.old_musket_attachment_profiles,
	canonical_key = function(item)
		local data = item and item.data
		local bid = item and (item.backend_id or item.ItemInstanceId
			or (data and (data.backend_id or data.ItemInstanceId)))
		return _om._cwv_key_for_item and _om._cwv_key_for_item(bid, item)
	end,
	printf = printf,
})
_om._old_musket_preview_descriptor = function(item)
	local bid = item and (item.backend_id or item.ItemInstanceId
		or (item.data and (item.data.backend_id or item.data.ItemInstanceId)))
	local mode = bid and _om._old_musket_modes_by_backend
		and _om._old_musket_modes_by_backend[bid] or nil
	return _om.old_musket_appearance.resolve(item, mode, "illusion_browser", {
		attachment_profile = _om.old_musket_attachment_profiles.display_3p_rifle,
	})
end
_om._old_musket_preview_texture_targets = function(descriptor, units, spawn_data)
	return _om.old_musket_appearance.preview_targets(descriptor, units, spawn_data)
end
mod._cwv_resolve_preview_descriptor = _om._old_musket_preview_descriptor

-- #474: Old Musket stance is explicit, durable presentation state. Vanilla's
-- equipment RPC deliberately carries the base es_handgun identity, so the
-- stance cannot be inferred by a remote husk. This VMF channel sends one small
-- transition record on toggle/wield/state-entry and a query/reply on join. It
-- never polls or transmits per frame. Receivers cache by owner+slot; a late
-- husk/preview reconstruction consumes the same state as an immediate update.
-- Implementation lives in _cwv_old_musket_wire.lua (state caches, both-wire
-- acceptors, publish/query/fire). Dofiled HERE so its _om exports exist before
-- the fire-dispatch block above first runs and before the identity register
-- (defined later) routes into them.
mod:dofile("scripts/mods/character_weapon_variants/_cwv_old_musket_wire")(mod, { om = _om })

-- v0.1.293 approach A: spawn a hidden vanilla rifle alongside our custom mesh
-- so sound/VFX actions (which look up named nodes like "fx_muzzle" / "j_hammer"
-- on the weapon unit) can find them. The vanilla rifle's flow events + FX
-- emission points are baked into its compiled .unit; our custom mesh has none.
-- We hide the vanilla rifle (visibility=false), link it to our mesh, and proxy
-- Unit.node/Unit.has_node lookups so any action calling
-- `Unit.node(our_mesh, "fx_muzzle")` gets the vanilla rifle's node back.
-- Result: muzzle flash, smoke, sound, casing-eject all emit from the right
-- world position (our mesh's hand-attached position, since the proxy is
-- linked) while only our custom mesh renders.
_om._CWV_OLD_MUSKET_FX_PROXY = setmetatable({}, { __mode = "k" })  -- our_unit -> proxy_unit

_om._spawn_old_musket_fx_proxy = function(world, our_unit, vanilla_path, owner_unit, owner_hand_node_name)
	if not our_unit or not Unit.alive(our_unit) then
		-- v0.1.341-dev: promoted to `_dbg_alert` — "invalid unit" is an
		-- alert condition (the FX proxy can't be installed; FX won't fire).
		_dbg_alert("[cwv old-musket fx] our_unit invalid; skip proxy for %s", vanilla_path)
		return
	end
	if not Managers.state or not Managers.state.unit_spawner then
		-- v0.1.341-dev: promoted to `_dbg_alert` — "not available" is an
		-- alert (FX proxy can't be installed without unit_spawner).
		_dbg_alert("[cwv old-musket fx] unit_spawner not available; skip proxy")
		return
	end
	-- v0.1.296: link the proxy directly to the player's hand-attach bone
	-- rather than to our_unit's root. Why: our visible mesh has a rotation
	-- (e.g., axis (1,1,-1) @ -90° for 1P-ranged) that re-orients the gun to
	-- align with the player's grip. If the proxy inherits that rotation,
	-- its "fx_muzzle" node ends up pointing toward the camera/stomach
	-- instead of forward, so muzzle flash + bullet trail spawn at weird
	-- locations. By linking the proxy to the same bone vanilla rifle would
	-- link to, the proxy gets vanilla's natural pose — muzzle ends up where
	-- a vanilla empire-handgun's muzzle would be (in front of hand). That
	-- matches what the player visually expects regardless of how our
	-- visible mesh is reoriented.
	-- Falls back to linking to our_unit's root if the player unit + node
	-- aren't available (defensive only — they should always be present
	-- when called from the spawn_inventory_unit hook).
	local ok, proxy = pcall(function()
		return Managers.state.unit_spawner:spawn_local_unit(vanilla_path, Vector3(0, 0, 0), Quaternion.identity())
	end)
	if not ok or not proxy then
		mod:warning("[cwv old-musket fx] spawn proxy failed for %s: %s", vanilla_path, tostring(proxy))
		return
	end
	local linked_to = "fallback(our_unit root)"
	local lok = false
	if owner_unit and Unit.alive(owner_unit) and owner_hand_node_name and Unit.has_node(owner_unit, owner_hand_node_name) then
		local hand_idx = Unit.node(owner_unit, owner_hand_node_name)
		lok = pcall(World.link_unit, world, proxy, 0, owner_unit, hand_idx)
		linked_to = string.format("owner_unit %s.%s(idx=%d)", tostring(owner_unit), owner_hand_node_name, hand_idx)
	else
		lok = pcall(World.link_unit, world, proxy, 0, our_unit, 0)
	end
	-- Reset proxy's local transform so it sits exactly at the link parent's
	-- node. Without this the proxy retains its spawn-time pose relative to
	-- the new parent, which can shift its node offsets in world space.
	pcall(Unit.set_local_position, proxy, 0, Vector3(0, 0, 0))
	pcall(Unit.set_local_rotation, proxy, 0, Quaternion.identity())
	pcall(Unit.set_local_scale, proxy, 0, Vector3(1, 1, 1))
	local vok = pcall(Unit.set_unit_visibility, proxy, false)
	_om._CWV_OLD_MUSKET_FX_PROXY[our_unit] = proxy
	_dbg("[cwv old-musket fx] proxy spawned: path=%s linked_to=%s link_ok=%s vis_ok=%s",
		vanilla_path, linked_to, tostring(lok), tostring(vok))
end

_om._destroy_old_musket_fx_proxy = function(our_unit)
	local proxy = _om._CWV_OLD_MUSKET_FX_PROXY[our_unit]
	if proxy and Unit.alive(proxy) then
		if Managers and Managers.state and Managers.state.unit_spawner then
			pcall(function() Managers.state.unit_spawner:mark_for_deletion(proxy) end)
		end
	end
	_om._CWV_OLD_MUSKET_FX_PROXY[our_unit] = nil
end

-- Proxy Unit.node lookups: when called on our custom mesh and the requested
-- name doesn't resolve on it, redirect to the linked vanilla rifle. has_node
-- returns true if either has the node. Hooks are global (every Unit.node call
-- in the game routes through), but the proxy-table lookup is a cheap weak-
-- table read.
-- Capture the pre-hook Unit.has_node BEFORE installing any hooks so the
-- Unit.node hook can probe our mesh without invoking its own hook chain.
local _orig_unit_has_node = Unit.has_node
mod:hook(Unit, "node", function(orig, unit, name)
	local proxy = _om._CWV_OLD_MUSKET_FX_PROXY[unit]
	if proxy and Unit.alive(proxy) and not _orig_unit_has_node(unit, name) then
		return orig(proxy, name)
	end
	return orig(unit, name)
end)
mod:hook(Unit, "has_node", function(orig, unit, name)
	local proxy = _om._CWV_OLD_MUSKET_FX_PROXY[unit]
	if proxy and Unit.alive(proxy) then
		return orig(unit, name) or orig(proxy, name)
	end
	return orig(unit, name)
end)

-- v0.1.294: flow events drive most weapon FX in VT2 (muzzle flash, smoke,
-- bullet trail, casing eject, dry-fire click — all baked into the rifle's
-- compiled .unit as flow graph nodes triggered by named events fired from
-- Lua action code like ActionHandgun:line 194 `Unit.flow_event(weapon_unit,
-- "lua_bullet_trail")`). Our custom mesh has no flow graph, so firing on it
-- no-ops. Redirect to the proxy (which has the full vanilla flow graph).
-- Same proxy-table-lookup pattern as Unit.node hook above.
mod:hook(Unit, "flow_event", function(orig, unit, event_name)
	local proxy = _om._CWV_OLD_MUSKET_FX_PROXY[unit]
	if proxy and Unit.alive(proxy) then
		return orig(proxy, event_name)
	end
	return orig(unit, event_name)
end)
-- Flow VARIABLES seed values that flow graph nodes read (e.g. "hit_position"
-- on line 192 of action_handgun.lua). Redirect to proxy for the same reason.
mod:hook(Unit, "set_flow_variable", function(orig, unit, name, value)
	local proxy = _om._CWV_OLD_MUSKET_FX_PROXY[unit]
	if proxy and Unit.alive(proxy) then
		return orig(proxy, name, value)
	end
	return orig(unit, name, value)
end)

_om._reapply_old_musket_transforms_all = function()
	local count = _om.old_musket_appearance.reapply_tracked()
	mod:echo("[cwv old-musket] descriptor generation replayed to %d retained unit(s)", count)
end

-- v0.1.290: filter attachment_node_linking entries that reference skeleton
-- nodes not present on our custom mesh. The vanilla empire-rifle template's
-- `AttachmentNodeLinking.rifles.first_person.wielded` links 4 player-side
-- hand-component bones to 4 weapon-side rig nodes (j_lock, j_hammer,
-- j_trigger, plus node 0). Our FBX has no skeleton (just mesh geometry),
-- so the engine's `Unit.node(target, "j_lock")` call in `GearUtils.link_units`
-- crashes with `[Script Error]: j_lock`. Filter: keep entries whose target
-- is a node-index (always 0 = root, safe on any unit) or whose named target
-- actually resolves; drop the rest. The root link is what physically
-- attaches the weapon to the hand — the others are decorative finger-pose
-- attachments that only matter for vanilla rifles with the full rig.
mod:hook("GearUtils", "link_units", function(orig, world, attachment_node_linking, link_table, source, target)
	if not target then return orig(world, attachment_node_linking, link_table, source, target) end
	-- v0.1.291: `Unit.has_node` returns a boolean — verified used in vanilla
	-- ai_bot_group_system.lua:190 and similar. The v0.1.290 attempt used
	-- `pcall(Unit.node, ...)`, but Stingray's Unit.node throws an error that
	-- pcall doesn't catch (engine-level fatal, not a Lua error). has_node
	-- is the correct safe-existence API.
	for _, entry in ipairs(attachment_node_linking) do
		local tgt = entry.target
		if type(tgt) == "string" and not Unit.has_node(target, tgt) then
			-- Found a missing node — filter the whole table.
			local safe = {}
			for _, e in ipairs(attachment_node_linking) do
				local t = e.target
				if type(t) ~= "string" or Unit.has_node(target, t) then
					safe[#safe + 1] = e
				end
			end
			return orig(world, safe, link_table, source, target)
		end
	end
	return orig(world, attachment_node_linking, link_table, source, target)
end)

end

return install
