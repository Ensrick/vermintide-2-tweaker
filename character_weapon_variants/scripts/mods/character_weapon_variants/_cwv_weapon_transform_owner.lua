-- _cwv_weapon_transform_owner.lua
-- CWV weapon-transform owner (#1159).
--
-- Owns ONE question and its answer: given an item, a selected skin and (for the
-- Crowbill family) a resolved unit name, WHICH transform record applies, and how
-- is that record written onto a spawned weapon unit. Everything the entry used to
-- carry for that job moved here verbatim:
--   * the authored `_type_transforms` type table and the per-variant-over-type
--     precedence resolver `_resolve_field`;
--   * the four registries built from it at load - `_transform_map`,
--     `_skin_transform_map`, the #597 Greataxe per-model defs, the #604 Crowbill
--     per-model defs plus their `_crowbill_transform_by_unit` index, the
--     `_custom_illusions` synthetic defs, and the longest-match inherit pass that
--     gives a dynamically-registered cross-character illusion its variant's scale
--     (issue 409 `force_register` and issue 417 unit-bearing registration are the
--     two gate signals that decide membership);
--   * the WeaponAppearance (#420) instance every render path shares, its
--     `_apply_scale` / `_apply_offset` / `_transform_unit` wrappers, and the
--     `mod._wa_to_quaternion_for_rt` / `mod._cwv_weapon_appearance` handles;
--   * the #604 Crowbill presentation owner with its rotation ops, the render
--     identity helper, the `mod._cwv_crowbill_set_mode` /
--     `_cwv_crowbill_apply_remote_mode` / `_cwv_crowbill_apply_presentation`
--     seams, and the durable / relative-scale / evidence / transform-runtime
--     library wiring behind them;
--   * the single per-hand applier `_apply_cwv_hand_transform` with its bounded
--     64-shot `[cwv:604] transform scheduled` evidence and `_triplet_text`;
--   * the resolvers the surfaces call - `_resolve_cwv_def` (combat-style decision,
--     skin, exact Crowbill unit, #482 backend-id ladder, vanilla-key fallback and
--     the toggled `es_dual_wield_hammer_sword` mace+sword tweak def),
--     `_om._cwv_resolve_crowbill_transform`, and the #604 husk transform-policy
--     bind that exports `_om._cwv_select_husk_transform_def` /
--     `_om._cwv_husk_transform_apply_plan`.
--
-- Extracted verbatim from the entry file; behavior is unchanged. Three moved
-- ranges, each an unbroken byte-identical block, and the entry was reconstructed
-- from the new entry plus these three ranges to prove it.
--
-- ORDERING - two of the three ranges used to sit BELOW the Combat Style install
-- and now run above it. That is safe by inspection, not by luck: `_resolve_cwv_def`
-- is only a function DEFINITION here and reads `_om.combat_styles` through the
-- shared table at CALL time, and `_om.husk_transform_policy.bind` only type-checks
-- its deps and returns closures. Neither has a load-time side effect, and no
-- caller of either runs during load. What DOES depend on order is unchanged: the
-- registries are built before the Combat Style install reads
-- `cwv_imperial_longsword` out of the type table.
--
-- BOUNDARY - this owner is a PRODUCER, not a surface. It registers no hook, no
-- network channel and no command; the four presentation surfaces stay exactly
-- where they were and keep calling in:
--   * WORLD / BOT equipment      - the entry's `GearUtils.create_equipment` hook,
--     which keeps its own transform-miss evidence counters (nothing here reads
--     them);
--   * MENU / keep previews       - `_cwv_menu_preview_owner`;
--   * REMOTE husk display        - `_cwv_husk_path`, through the husk
--     transform-policy bind published here;
--   * EXACT appearance / identity - `_om._cwv_resolve_world_descriptor` and the
--     `BackendUtils.get_item_units` hook stay in the entry; they are the #1158
--     wire channel and only borrow `_resolve_cwv_def` as a fallback rung.
-- The Combat Style install block also stays in the entry: it authors weapon
-- TEMPLATES, and only reads one authored record (`cwv_imperial_longsword`) from
-- the type table this owner publishes.
--
-- Thirteen of the twenty-three moved file-scope locals had ZERO references
-- outside the moved ranges before the move (proved with a word-boundary scope
-- probe over the pristine entry) and are now unreachable from the entry. The
-- other ten stay reachable through `_om.weapon_transform`, and the entry
-- re-binds them under their original names so every surviving statement in the
-- entry is byte-identical.
--
-- ctx bindings are all BY VALUE and all sound: each is declared exactly once at
-- entry file scope above this load point and never rebound (grep-verified):
--   mod, om                                     entry lines 1 / 55
--   variant_definitions                         entry line 413
--   custom_illusions, custom_skin_keys          entry lines 4015 / 4016
--   find_def                                    entry line 4077
-- `custom_skin_keys` and the three registries travel as table references, so the
-- in-place population that happens around this load point still reaches here, as
-- it did when the blocks were inline.
--
-- No native resource boundary moved with these blocks: nothing here creates
-- particles or a screen GUI, writes a material or unit texture, or takes a
-- package lease, so this file needs no resource-safety evidence marker and adds
-- no qa/native_resource_contracts.psd1 row. Deliberately worded without those
-- API literals: the offline suite counts them as code needles.
--
-- Named (not anonymous) so the offline forward-reference lint keeps treating the
-- moved blocks as file-scope code: an anonymous `function(` wrapper makes every
-- construct-then-call pair below read as a closure capturing its own body. See
-- the same note in _cwv_menu_preview_owner.lua.
local function install(mod, ctx)
local _om = ctx.om
local _variant_definitions = ctx.variant_definitions
local _find_def = ctx.find_def
local _custom_illusions = ctx.custom_illusions
local _custom_skin_keys = ctx.custom_skin_keys

-- ============================================================
-- Model scaling and grip offsets
-- ============================================================
--
-- Two layers, in precedence order:
--   1. Per-variant fields on the def (`right_hand_scale`, `right_hand_offset`,
--      `left_hand_scale`, `left_hand_offset`) — model-specific overrides.
--   2. Type-level entry in `_type_transforms[item_type]` — applies to every
--      variant sharing that item_type. This is how a "weapon type" gets
--      defined as a single tunable: each `cwv_*` item_type represents a new
--      conceptual weapon (e.g. cwv_imperial_longsword), and any change to
--      the type cascades to all variants of that type automatically.
--
-- A variant only needs the per-variant fields when it deviates from its type.
-- The type table is the canonical place to tune family-wide proportions /
-- grip behaviour, so a future "make Imperial Longswords thinner" change is
-- one edit, not three.

local _type_transforms = {
	-- Imperial Longsword family (Imperial Longsword, Helmgart Watchsword, Black Guard Blade).
	-- Y trims 20% off width (Imperial greatsword's wide axis is Y, not X like the
	-- Bretonian — this is independent of cosmetics_tweaker's `_breton_sword_thiccc`
	-- factor `{0.65, 1, 1}` on `wpn_emp_gk_sword_*`); Z trims 10% off blade length.
	-- Lateral X grip nudge so the hand sits on the hilt after Y-thinning. Sign per
	-- `feedback_grip_offset_sign.md`.
	cwv_imperial_longsword = {
		right_hand_scale  = { 1.0, 0.8, 0.9 },
		-- User-tuned along Z. The negative direction is correct for this model
		-- family (flipped from `feedback_grip_offset_sign.md`'s general
		-- "+Z = grip lower" rule — per-model authoring axes can invert it).
		right_hand_offset = { 0, 0, -0.065 },
	},
	-- Longsword + Shield: same right-hand sword mesh as the 2H Imperial
	-- Longsword family (`wpn_empire_2h_sword_04_t1`), per-perspective
	-- scaled. 3P body shows the smaller-feeling sword (better silhouette
	-- next to a shield, where a 2H greatsword reads too oversized),
	-- while 1P keeps the original 2H family scale because the held view
	-- looked too small at the shrunk values. Tuning history:
	--   v0.1.197 unified {1.0, 0.8, 0.9} — matches 2H family
	--   v0.1.206 unified {0.85, 0.65, 0.75} — −0.15 on every axis
	--   v0.1.210 SPLIT — 1P back to {1.0, 0.8, 0.9}, 3P stays at {0.85, 0.65, 0.75}
	-- Resolution: `_1p`/`_3p` variants override the unified field for
	-- that perspective only (per `_resolve_field`). Grip offset is
	-- unified — same Z=-0.065 works for both perspectives. Left hand
	-- (the shield) is untouched. Variant uses its own item_type (not
	-- cwv_imperial_longsword) so it can carry its own curated
	-- shield-illusion picker — that's why this is a separate entry
	-- rather than sharing the 2H family's type.
	cwv_es_longsword_shield = {
		right_hand_scale_1p = { 1.0, 0.8, 0.9 },     -- 1P held view: full 2H family scale
		right_hand_scale_3p = { 0.9, 0.7, 0.8 },  -- 3P body: shrunk for shield pairing (+0.05 each axis v0.1.309)
		right_hand_offset   = { 0, 0, -0.065 },
	},
	-- Maul: scale Kruber's 1H mace meshes (mace+sword mace + es_1h_mace
	-- skins) up to a 2H silhouette. User-tuned to {1.075, 1.075, 1.4}
	-- v0.1.171 (was {1.4, 1.4, 2.0} in v0.1.168 — too big). The lighter
	-- X/Y bump keeps the mace from looking inflated; Z +40% adds enough
	-- length to read as a 2H maul. Type-level so default + every illusion
	-- in cwv_es_maul_skins picker inherit.
	cwv_es_maul = {
		right_hand_scale  = { 1.0, 1.0, 1.6 },
		-- Grip offset Z lowers Kruber's hand toward the haft. Per
		-- `feedback_grip_offset_sign.md`, +Z lowers grip on this family.
		-- Tuning history: 0.5 (v0.1.176) → 0.35 (v0.1.213) — the original
		-- pulled the hand too far toward the bottom of the haft; this is
		-- a more moderate drop.
		right_hand_offset = { 0, 0, 0.2 },
	},
	-- Rapier: lightly broaden the fencing-sword mesh — X +5%, Y +15%,
	-- Z native. Tuning history:
	--   v0.1.187 {1.1, 1.25, 1.0} initial basket-hilt feel
	--   v0.1.191 {1.1, 1.45, 1.0} Y bump
	--   v0.1.196 {1.0, 1.75, 1.0} maximal Y for broadsword silhouette
	--   v0.1.212 {1.05, 1.15, 1.0} restored to a subtler bump per user —
	--     v0.1.196's 1.75 read as exaggerated; this is a lighter touch.
	-- Type-level so the default mesh + every wh_fencing_sword_skin_*
	-- illusion in cwv_es_rapier_skins inherits.
	cwv_es_rapier = {
		right_hand_scale = { 1.05, 1.15, 1.0 },
	},
	-- Musket: stretch Kruber's rifle 1.35x along Y (length axis) and
	-- thin X/Z (barrel/cross-section). v0.1.250 dropped X/Z another 0.1
	-- (`0.9 → 0.8`). v0.1.256 split Y per perspective: 3P stays 1.35,
	-- 1P bumped to 1.5 (+0.15) per user "1P needs 0.15 longer on Y" —
	-- held view reads slightly short of where the muzzle should be.
	-- Per-perspective via `_resolve_field` precedence: `_1p` field
	-- overrides the unified `right_hand_scale` for 1P only.
	cwv_es_musket = {
		right_hand_scale    = { 0.8, 1.35, 0.8 },
		right_hand_scale_1p = { 0.8, 1.5,  0.8 },
	},
	-- Old Musket (cwv_es_musket_old): custom mesh is already the right
	-- shape (proportions baked into the FBX) — no Y stretch needed, no
	-- X/Z thinning, so it carries NO generic scale/offset. But it still
	-- needs its bespoke pose + textures applied on the resolver-driven
	-- render paths (inventory preview / illusion browser), which bail at
	-- the nil-def guard unless the def is registered. `force_register`
	-- (issue 409) puts it into `_transform_map` with no transform values,
	-- so `_resolve_preview_def` returns it and `_cwv_spawn_item_post`
	-- reaches the Old-Musket pose/texture block instead of early-returning.
	-- (Its actual pose is still the absolute per-perspective/stance pose in
	-- the `_om` module — the custom mesh needs an absolute reset, not the
	-- generic additive offset.)
	cwv_es_musket_old = { force_register = true },
}

-- Per-variant override > type-level default > nil.
local function _resolve_field(def, field)
	if def[field] ~= nil then return def[field] end
	local tt = def.item_type and _type_transforms[def.item_type]
	return tt and tt[field] or nil
end

local _transform_map = {}
local _skin_transform_map = {}
for _, def in ipairs(_variant_definitions) do
	-- Register if EITHER the def itself OR its type contributes any transform.
	-- This is what lets a variant with no per-variant scale fields still pick
	-- up the type-level entry — without it, _transform_map[item_key] is nil
	-- and `_resolve_cwv_def` returns nil at apply time.
	-- Includes the per-perspective `_1p` / `_3p` variants so a def that only
	-- sets a 1P-specific or 3P-specific transform is still registered.
	-- Issue 409: `force_register` lets a custom-mesh item that needs NO generic
	-- scale/offset (native authored scale) still enter `_transform_map`, so every
	-- resolver-driven render path (preview, illusion browser) resolves its def and
	-- reaches its rotation/texture apply instead of bailing at the nil-def guard.
	-- Rotation fields are also gate signals now — a rotation-only def must register.
	if _resolve_field(def, "force_register")
			or _resolve_field(def, "right_hand_scale")
			or _resolve_field(def, "left_hand_scale")
			or _resolve_field(def, "right_hand_offset")
			or _resolve_field(def, "left_hand_offset")
			or _resolve_field(def, "right_hand_scale_1p")
			or _resolve_field(def, "left_hand_scale_1p")
			or _resolve_field(def, "right_hand_offset_1p")
			or _resolve_field(def, "left_hand_offset_1p")
			or _resolve_field(def, "right_hand_scale_3p")
			or _resolve_field(def, "left_hand_scale_3p")
			or _resolve_field(def, "right_hand_scale_multiplier_3p")
			or _resolve_field(def, "left_hand_scale_multiplier_3p")
			or _resolve_field(def, "right_hand_offset_3p")
			or _resolve_field(def, "left_hand_offset_3p")
			or _resolve_field(def, "right_hand_rotation")
			or _resolve_field(def, "left_hand_rotation")
			or _resolve_field(def, "right_hand_rotation_1p")
			or _resolve_field(def, "left_hand_rotation_1p")
			or _resolve_field(def, "right_hand_rotation_3p")
			or _resolve_field(def, "left_hand_rotation_3p")
			-- Issue #417: a variant that OVERRIDES a hand unit (renders its own
			-- mesh) must resolve a def on every def-keyed path too, or the mesh
			-- swaps (via _find_def, registration-independent) while transform and
			-- texture bail at the nil-def guard -- silently. That trap forced the
			-- per-item `force_register` crutch (the musket, #409). Registering on
			-- unit-override presence generalizes the crutch: mesh-bearing =>
			-- def-resolving, so units and every other concern stay coupled for all
			-- current AND future variants. Behavior-neutral today (WA.apply no-ops
			-- on nil scale/offset/rotation; texture stays musket-gated).
			or _resolve_field(def, "right_hand_unit")
			or _resolve_field(def, "left_hand_unit") then
		_transform_map[def.item_key] = def
		if not def.no_skin then
			_skin_transform_map[def.item_key .. "_skin"] = def
		end
	end
end

-- Exposed for /cwv_regression_test (musket_old_force_registered, #409).
mod._cwv_transform_registered = function(key) return _transform_map[key] ~= nil end
-- Exposed for cwv_unit_bearing_variants_registered (#417): the test asserts every
-- def declaring a hand-unit override is registered (mesh-bearing => def-resolving).
_om._variant_defs = _variant_definitions

-- #597 Greataxe model transforms are illusion-specific. The generated base
-- skin uses `<item>_skin`, while the manifest calls that same row `_skin_01`;
-- bind both names to Model 01's reviewed transform. Every later model gets a
-- synthetic def even when it has no transform, which deliberately blocks the
-- dynamic inherit pass below from leaking Model 01's scale/offset/rotation to
-- Models 02-05. These defs feed the same shared WeaponAppearance path used by
-- owner/bot 3P, husks, inventory, lobby, score/team, and item previews.
for index, model in ipairs(_om.greataxe.usable_models()) do
	local transform_def = {
		item_key = model.key,
		right_hand_scale_3p = model.right_hand_scale_3p,
		right_hand_offset_3p = model.right_hand_offset_3p,
		right_hand_rotation_3p = model.right_hand_rotation_3p,
	}
	_skin_transform_map[model.key] = transform_def
	if index == 1 then
		_skin_transform_map[_om.greataxe.ITEM_KEY .. "_skin"] = transform_def
	end
end

-- #604 Crowbill transforms are model-specific. Register every
-- model as an explicit control so a reviewed tune can never leak into a sibling
-- through the dynamic family-inheritance pass below. These synthetic defs feed
-- the same shared WeaponAppearance consumers as Greataxe: owner/bot 3P, remote
-- husks, inventory/lobby/score character previews, and item/Athanor previews.
-- The exact spawned unit path is also indexed: default-rarity/CIM blacksmith
-- instances are intentionally skinless, and GearUtils may receive base-shaped
-- item_data, but the resolved unit is still an unambiguous model identity.
-- Default Model 01 additionally becomes the variant fallback so a skinless
-- default instance resolves the same transform before/after reconstruction.
local _crowbill_transform_by_unit = {}
for _, model in ipairs(_om.crowbill_family.usable_models()) do
	local base_def = _find_def(model.variant_key)
	local transform_def = base_def and table.clone(base_def, true) or {}
	transform_def.item_key = model.variant_key
	transform_def.crowbill_model_key = model.key
	transform_def.crowbill_mode_family = _om.crowbill_family.HAMMER_MODE_FAMILY
	transform_def.right_hand_unit = model.right_hand_unit
	transform_def.right_hand_scale = model.right_hand_scale
	transform_def.right_hand_offset = model.right_hand_offset
	transform_def.right_hand_rotation = model.right_hand_rotation
	transform_def.right_hand_scale_1p = model.right_hand_scale_1p
	transform_def.right_hand_offset_1p = model.right_hand_offset_1p
	transform_def.right_hand_rotation_1p = model.right_hand_rotation_1p
	transform_def.right_hand_scale_3p = model.right_hand_scale_3p
	transform_def.right_hand_scale_multiplier_3p = model.right_hand_scale_multiplier_3p
	transform_def.right_hand_offset_3p = model.right_hand_offset_3p
	transform_def.right_hand_rotation_3p = model.right_hand_rotation_3p
	_skin_transform_map[model.key] = transform_def
	_crowbill_transform_by_unit[model.right_hand_unit] = transform_def
	_crowbill_transform_by_unit[model.right_hand_unit .. "_3p"] = transform_def
	if _om.crowbill_family.model_for_variant(model.variant_key) == model then
		_transform_map[model.variant_key] = transform_def
	end
end

_om._cwv_crowbill_transform_by_unit = _crowbill_transform_by_unit

-- Custom illusions with their own scale/offset fields (e.g. greathammer
-- skins applied to 1H mace targets need to scale the oversized 2H model
-- down). These aren't variant defs — they live in `_custom_illusions` —
-- but the apply path keys by skin_key, so we register them in
-- `_skin_transform_map` with a synthetic def carrying just the transform
-- fields. `_resolve_field` reads `def[field]` first, finds these directly.
for _, illusion in ipairs(_custom_illusions) do
	local has_transform = illusion.right_hand_scale or illusion.left_hand_scale
		or illusion.right_hand_offset or illusion.left_hand_offset
		or illusion.right_hand_scale_1p or illusion.left_hand_scale_1p
		or illusion.right_hand_scale_3p or illusion.left_hand_scale_3p
	if has_transform then
		_skin_transform_map[illusion.skin_key] = {
			item_key             = illusion.skin_key,  -- for log/identification
			right_hand_scale     = illusion.right_hand_scale,
			left_hand_scale      = illusion.left_hand_scale,
			right_hand_offset    = illusion.right_hand_offset,
			left_hand_offset     = illusion.left_hand_offset,
			right_hand_scale_1p  = illusion.right_hand_scale_1p,
			left_hand_scale_1p   = illusion.left_hand_scale_1p,
			right_hand_scale_3p  = illusion.right_hand_scale_3p,
			left_hand_scale_3p   = illusion.left_hand_scale_3p,
			right_hand_offset_1p = illusion.right_hand_offset_1p,
			left_hand_offset_1p  = illusion.left_hand_offset_1p,
			right_hand_offset_3p = illusion.right_hand_offset_3p,
			left_hand_offset_3p  = illusion.left_hand_offset_3p,
		}
	end
end

-- Inherit-from-variant pass for dynamically-registered cross-character
-- illusions (registered via _register_*_illusions functions, NOT via
-- _custom_illusions). Detection: skin_key starts with a known variant
-- item_key followed by "_". The dynamic illusion shares the variant's
-- type-level transform via the variant's def — `_resolve_field` falls
-- through to `_type_transforms[def.item_type]` when the def has no
-- per-field override, so this gives the dynamic illusion picker preview
-- the same scale the variant's default mesh uses in-game.
--
-- The in-game render path (`GearUtils.create_equipment` →
-- `_resolve_cwv_def`) already handles this via the backend_id fallback —
-- it resolves the cwv variant from the equipped item's backend_id and
-- finds the type-level transform there. The picker (`LootItemUnitPreviewer`)
-- doesn't have a backend_id on the previewed weapon_skin entry, so
-- without this pass it shows un-scaled illusions.
--
-- Per-illusion overrides in _custom_illusions take precedence (above
-- block), so a dynamic illusion that needs a different scale than its
-- variant should be moved to _custom_illusions with explicit scale fields.
--
-- LONGEST-MATCH RULE (v0.1.255): when multiple variant defs share a
-- prefix relationship (e.g. `cwv_es_longsword` is a prefix of
-- `cwv_es_longsword_shield`), the iterate-and-break loop used to pick
-- whichever def appeared FIRST in `_variant_definitions` — so
-- `cwv_es_longsword_shield_*` illusions inherited from the 2H Imperial
-- Longsword variant instead of the shield-specific one, applying the
-- wrong scale. Now we walk every variant, track the longest item_key
-- that's a prefix of the skin_key, and use that one.
for skin_key in pairs(_custom_skin_keys) do
	if not _skin_transform_map[skin_key] then
		local best_def = nil
		local best_len = 0
		for _, def in ipairs(_variant_definitions) do
			if _transform_map[def.item_key]
					and #def.item_key > best_len
					and skin_key:sub(1, #def.item_key + 1) == def.item_key .. "_" then
				best_def = def
				best_len = #def.item_key
			end
		end
		if best_def then
			_skin_transform_map[skin_key] = _transform_map[best_def.item_key]
		end
	end
end

local function _is_unit(v) return _om.peer_resolver.alive_unit(v, Unit) end

-- ============================================================
-- WeaponAppearance (WA) — copied shared appearance primitive (#420)
-- ============================================================
-- The byte-identical bundled library owns scale / offset / position / rotation
-- math for a weapon unit, called by EVERY render path:
--   1. in-world owner/bot  — GearUtils.create_equipment
--   2. husk (remote)       — GearUtils.spawn_inventory_unit (owner_unit_1p==nil)
--   3. inventory preview    — MenuWorldPreviewer/_spawn_item -> _cwv_spawn_item_post
--   4. illusion browser     — LootItemUnitPreviewer.spawn_units
-- Full contract: docs/WEAPON_APPEARANCE_STANDARD.md. Identity, hand,
-- perspective, residency, and render-path resolution remain CWV-owned.
--
-- Conventions (DO NOT reintroduce per-site copies of this math):
--   * scale    — ABSOLUTE set. Idempotent by nature.
--   * offset   — ADDITIVE nudge from the mesh's native local position. Guarded
--                idempotent (weak table) because MenuWorldPreviewer's _spawn_item
--                super-call fires the hook TWICE per spawn and additive would
--                double. (This is why scale/rotation/position, being absolute,
--                need no guard.)
--   * position — ABSOLUTE set, for custom meshes that need a full pose reset
--                (e.g. the Old Musket). Mutually exclusive with offset; if both
--                are present, position wins.
--   * rotation — ABSOLUTE set. Accepts EITHER {x,y,z} Euler DEGREES (the human-
--                tunable standard: Quaternion.from_euler_angles_xyz takes degrees,
--                memory reference_vt2_euler_angles_degrees) OR a QuaternionBox /
--                raw Quaternion for hand-authored non-principal-axis poses.
--   * 1P and 3P are applied to SEPARATE units BY THE CALLER; the library never
--     infers perspective, so a 3P change can never touch the 1P grip (and vice
--     versa). Callers resolve `<field>_1p` / `<field>_3p` / unified via
--     `_resolve_field` and hand WA the already-resolved value.
local _WA_LIBRARY = mod:dofile(
	"scripts/mods/character_weapon_variants/_lib_weapon_appearance")
local WA = _WA_LIBRARY.new()
mod._wa_to_quaternion_for_rt = WA.to_quaternion -- compatibility: /cwv regression
mod._cwv_weapon_appearance = WA  -- cross-file / cross-mod handle (Phase 2+)

-- #604 Crowbill pick/hammer presentation.  One owner composes the authored
-- base rotation with the mode-local 180-degree Z flip for every render path.
-- The owner weak-tracks spawned units so a Weapon Special/network transition
-- reapplies once; it never runs from update and never derives from a previously
-- flipped unit pose.
_om.crowbill_mode_state = _om.crowbill_mode_state or _om.crowbill_hammer_mode.new()
_om.crowbill_presentation_owner = _om.crowbill_presentation.new({
	alive = function(unit) return unit and Unit.alive(unit) end,
	mode_for = function(identity) return _om.crowbill_mode_state:mode(identity) end,
	-- Raw Stingray quaternions are frame-temporary. Persist only QuaternionBox
	-- values in the presentation record and unbox immediately before compose.
	retain_rotation = function(rotation) return rotation and QuaternionBox(rotation) or nil end,
	resolve_rotation = function(rotation)
		return rotation and rotation.unbox and rotation:unbox() or rotation
	end,
	rotation_ops = {
		identity = function() return Quaternion.identity() end,
		axis_angle = function(axis, degrees)
			return Quaternion.axis_angle(Vector3(axis[1], axis[2], axis[3]), math.rad(degrees))
		end,
		-- base * delta applies the delta in the weapon model's local space.
		multiply = function(base, delta) return Quaternion.multiply(base, delta) end,
	},
	write_rotation = function(unit, rotation)
		return pcall(Unit.set_local_rotation, unit, 0, rotation)
	end,
})

_om._crowbill_render_identity = function(item_data, def, fallback)
	local bid = item_data and (item_data.backend_id
		or (item_data.mod_data and item_data.mod_data.backend_id))
	if type(bid) == "string" and bid ~= "" then return bid end
	if type(fallback) == "string" and fallback ~= "" then return fallback end
	return def and def.item_key or nil
end

_om._apply_crowbill_presentation = function(unit, def, identity, surface, base_rotation, explicit_mode)
	if not (def and def.crowbill_mode_family == _om.crowbill_family.HAMMER_MODE_FAMILY)
			or not (unit and Unit.alive(unit)) then return false end
	local base = WA.to_quaternion(base_rotation)
	if not base then
		local ok, current = pcall(Unit.local_rotation, unit, 0)
		if ok then base = current end
	end
	return _om.crowbill_presentation_owner:apply(unit, identity, surface, base, explicit_mode)
end

-- Live-state seam used by the Weapon Special/RPC owner.  The returned payload
-- is the hammer-mode module's bounded transition envelope; callers send it once
-- on a real transition and use `_cwv_crowbill_apply_remote_mode` on receipt.
mod._cwv_crowbill_set_mode = function(identity, mode)
	local changed, payload, err = _om.crowbill_mode_state:set_mode(identity, mode)
	if changed then _om.crowbill_presentation_owner:reapply(identity, mode) end
	return changed, payload, err
end
mod._cwv_crowbill_apply_remote_mode = function(payload)
	local changed, err = _om.crowbill_mode_state:apply_remote(payload)
	if changed then
		_om.crowbill_presentation_owner:reapply(payload.identity, payload.mode)
	end
	return changed, err
end
mod._cwv_crowbill_apply_presentation = _om._apply_crowbill_presentation

-- Legacy thin wrappers so existing call sites read unchanged; `_transform_unit`
-- now also carries rotation. New code should call WA.apply directly.
local function _apply_scale(unit, scale_tbl)  WA.apply_scale(unit, scale_tbl) end
local function _apply_offset(unit, offset_tbl) WA.apply_offset(unit, offset_tbl) end
local function _transform_unit(unit, scale_tbl, offset_tbl, rotation)
	return WA.apply(unit, { scale = scale_tbl, offset = offset_tbl, rotation = rotation })
end

-- #604 single transform-scheduling owner. Every world/presentation consumer
-- calls this helper, which resolves the same hand+perspective fields and emits
-- one bounded scheduling line per spawned tuned Crowbill unit. Retained proof
-- is deliberately deferred to the durable owner's next-tick pre/final samples.
local _crowbill_transform_diag_seen = setmetatable({}, { __mode = "k" })
local _crowbill_transform_diag_total = 0
_om._cwv_crowbill_transform_delivery = { counts = {} }
local _DURABLE_TRANSFORM_LIBRARY = mod:dofile(
	"scripts/mods/character_weapon_variants/_cwv_durable_transform")
local _RELATIVE_SCALE_LIBRARY = mod:dofile(
	"scripts/mods/character_weapon_variants/_cwv_relative_scale")
local _TRANSFORM_EVIDENCE_LIBRARY = mod:dofile(
	"scripts/mods/character_weapon_variants/_cwv_transform_evidence")
local _CROWBILL_TRANSFORM_RUNTIME_LIBRARY = mod:dofile(
	"scripts/mods/character_weapon_variants/_cwv_crowbill_transform_runtime")
local _crowbill_transform_runtime = _CROWBILL_TRANSFORM_RUNTIME_LIBRARY.new({
	om = _om,
	appearance = WA,
	durable_library = _DURABLE_TRANSFORM_LIBRARY,
	relative_library = _RELATIVE_SCALE_LIBRARY,
	evidence_library = _TRANSFORM_EVIDENCE_LIBRARY,
	emit = printf,
})
local _durable_crowbill_owner = _crowbill_transform_runtime.durable
_om._cwv_durable_crowbill_owner, _om._cwv_crowbill_transform_evidence = _durable_crowbill_owner, _crowbill_transform_runtime.evidence
_om._cwv_forget_crowbill_transform_unit = function(unit, reason)
	if not unit then return false end
	_durable_crowbill_owner:forget(unit, reason)
	return true
end
local function _triplet_text(value)
	if type(value) ~= "table" then return "nil" end
	return string.format("%.3f,%.3f,%.3f", value[1] or 0, value[2] or 0, value[3] or 0)
end
local function _apply_cwv_hand_transform(unit, def, hand, perspective, surface, unit_name, skin)
	if not def then return false end
	local prefix = hand == "left" and "left_hand_" or "right_hand_"
	local scale = _resolve_field(def, prefix .. "scale_" .. perspective)
		or _resolve_field(def, prefix .. "scale")
	local scale_multiplier = _resolve_field(def, prefix .. "scale_multiplier_" .. perspective)
		or _resolve_field(def, prefix .. "scale_multiplier")
	local offset = _resolve_field(def, prefix .. "offset_" .. perspective)
		or _resolve_field(def, prefix .. "offset")
	local rotation = _resolve_field(def, prefix .. "rotation_" .. perspective)
		or _resolve_field(def, prefix .. "rotation")
	local applied = _transform_unit(unit, scale, offset, rotation)
	local generation
	if def.crowbill_model_key and (scale or scale_multiplier or offset or rotation)
			and unit and _is_unit(unit)
			and _durable_crowbill_owner then
		-- Offset is authored as native+delta, but durable replay must be absolute
		-- or it would accumulate every frame. Capture the resolved post-write
		-- position in a Vector3Box; raw Stingray vectors are frame-temporary.
		local position_box
		if offset then
			local ok, position = pcall(Unit.local_position, unit, 0)
			if ok and position then position_box = Vector3Box(position) end
		end
		local _, assigned_generation = _durable_crowbill_owner:track(unit, {
			def = def,
			model_key = def.crowbill_model_key,
			hand = hand,
			perspective = perspective,
			surface = surface,
			unit_name = unit_name,
			skin = skin,
			scale = scale,
			scale_multiplier = scale_multiplier,
			position = position_box,
			rotation = rotation,
		})
		generation = assigned_generation
	end
	if def.crowbill_model_key and (scale or scale_multiplier or offset or rotation) and unit
			and _is_unit(unit) and _crowbill_transform_diag_total < 64 then
		local surfaces = _crowbill_transform_diag_seen[unit]
		if not surfaces then
			surfaces = {}
			_crowbill_transform_diag_seen[unit] = surfaces
		end
		local token = tostring(surface) .. ":" .. tostring(perspective) .. ":" .. tostring(hand)
		if not surfaces[token] then
			surfaces[token] = true
			_crowbill_transform_diag_total = _crowbill_transform_diag_total + 1
			local counts = _om._cwv_crowbill_transform_delivery.counts
			counts[surface] = (counts[surface] or 0) + 1
			pcall(printf,
				"[cwv:604] transform scheduled surface=%s perspective=%s hand=%s variant=%s model=%s unit=%s skin=%s generation=%s scale_multiplier=(%s) absolute_scale=(%s) offset=(%s) rotation=(%s) initial_apply=%s count=%d/64",
				tostring(surface), tostring(perspective), tostring(hand),
				tostring(def.item_key), tostring(def.crowbill_model_key),
				tostring(unit_name), tostring(skin), tostring(generation),
				_triplet_text(scale_multiplier), _triplet_text(scale),
				_triplet_text(offset), _triplet_text(rotation), tostring(applied),
				_crowbill_transform_diag_total)
		end
	end
	return applied
end

-- Vanilla mace+sword cosmetic tweak (toggleable via "mace_sword_tweak"
-- setting, default ON). When the toggle is on:
--   * The vanilla `es_dual_wield_hammer_sword` item gets renamed to
--     "Cudgel and Short Sword" via the Localize hook below.
--   * The sword half (left_hand_unit = wpn_emp_sword_06_t1) is scaled to
--     {0.7, 0.7, 1.0} on the 3P body so the mace and sword visually match
--     the standalone Cudgel + Shortsword variants.
-- This is the VANILLA item, not the CWV `cwv_es_sword_and_mace` (Sword and
-- Mace) variant — that one is a separate weapon and is unaffected by this
-- toggle.
local _ES_MACE_SWORD_TWEAK_DEF = {
	item_key        = "es_dual_wield_hammer_sword",
	-- Right hand (mace, wpn_emp_mace_04_t2) keeps native scale.
	-- Left hand (sword, wpn_emp_sword_06_t1) shrinks to match the
	-- cwv_es_shortsword variant.
	left_hand_scale = { 0.7, 0.7, 1.0 },
}

local function _resolve_cwv_def(item_data, skin, resolved_unit_name)
	if _om.combat_styles and _om.combat_styles.transform_decision then
		local style_decision = _om.combat_styles:transform_decision(item_data,
			item_data and item_data.backend_id)
		if style_decision ~= nil then return style_decision or nil end
	end
	if skin and _skin_transform_map[skin] then return _skin_transform_map[skin] end
	-- #604: exact spawned Crowbill model identity outranks the base-shaped item
	-- row. This is the canonical path for skinless default-rarity/CIM instances.
	if resolved_unit_name and _crowbill_transform_by_unit[resolved_unit_name] then
		return _crowbill_transform_by_unit[resolved_unit_name]
	end
	if not item_data then return nil end
	-- CLARIFY: backend_id resolution is the canonical path for cwv items per
	-- memory note feedback_cwv_backend_id_lookup.md — item_data.key/.name return
	-- the BASE weapon key, never the cwv_* key.
	-- #482 ladder: bid pattern (`cwv_<key>_NNN`, CWV's own instances + cim
	-- standard-forge crafts, issue 390) -> item_data.cwv_key stamp -> backend
	-- lookup. The stamp rung is what restores scale/grip for Athanor-crafted
	-- instances, whose UUID backend_id the pattern can never match.
	local cwv_key = _om._cwv_key_for_item(item_data.backend_id, item_data)
	if cwv_key and _transform_map[cwv_key] then return _transform_map[cwv_key] end
	-- Vanilla item key fallback (used by the mace_sword_tweak path below; cwv
	-- items don't reach here because backend_id resolution above takes over).
	local key = item_data.key or item_data.name
	if key and _transform_map[key] then return _transform_map[key] end
	-- Vanilla mace+sword cosmetic tweak — gated on the user-facing toggle so
	-- it can be disabled at runtime without a mod reload. Per
	-- feedback_cwv_backend_id_lookup.md, `item_data.key` returns the BASE
	-- weapon key for cwv variants too — so we must check the backend_id
	-- prefix to ensure we don't accidentally apply this to
	-- cwv_es_sword_and_mace (which shares the same base_weapon).
	if key == "es_dual_wield_hammer_sword" and mod:get("mace_sword_tweak") then
		local bid_str = item_data.backend_id
		local is_cwv_variant = bid_str and type(bid_str) == "string" and bid_str:sub(1, 4) == "cwv_"
		if not is_cwv_variant then
			return _ES_MACE_SWORD_TWEAK_DEF
		end
	end
	return nil
end

_om._cwv_resolve_crowbill_transform = function(skin, resolved_unit_name, variant_key)
	if skin and _skin_transform_map[skin] then return _skin_transform_map[skin], "skin" end
	if resolved_unit_name and _crowbill_transform_by_unit[resolved_unit_name] then
		return _crowbill_transform_by_unit[resolved_unit_name], "unit"
	end
	if variant_key and _transform_map[variant_key]
			and _transform_map[variant_key].crowbill_model_key then
		return _transform_map[variant_key], "variant_default"
	end
	return nil, "miss"
end

-- #604 schema-2 exact identity must select the reconstructed model definition,
-- not its transform-free base variant. Production and regression share this policy.
_om._cwv_husk_transform_policy = _om.husk_transform_policy.bind({ find_def = _find_def,
	resolve_def = _resolve_cwv_def, resolve_field = _resolve_field,
	model_by_unit = _crowbill_transform_by_unit })
_om._cwv_select_husk_transform_def = _om._cwv_husk_transform_policy.select
_om._cwv_husk_transform_apply_plan = _om._cwv_husk_transform_policy.plan

-- Published under one namespace so the entry can re-bind the producers its
-- remaining surfaces call without adding ten `_om` top-level keys. Every value
-- is the exact object built above; nothing is copied or re-wrapped.
_om.weapon_transform = {
	type_transforms            = _type_transforms,
	resolve_field              = _resolve_field,
	transform_map              = _transform_map,
	skin_transform_map         = _skin_transform_map,
	crowbill_transform_by_unit = _crowbill_transform_by_unit,
	is_unit                    = _is_unit,
	transform_unit             = _transform_unit,
	triplet_text               = _triplet_text,
	apply_cwv_hand_transform   = _apply_cwv_hand_transform,
	resolve_cwv_def            = _resolve_cwv_def,
}

end

return install
