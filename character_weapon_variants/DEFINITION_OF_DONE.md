# Character Weapon Variants — Definition of Done

**A variant is NOT done until every applicable gate below is walked.**

This is a verification gate, not a how-to. For procedural recipes see
`RECIPES.md`; for architecture see `DEVELOPMENT.md`; for the full
animation procedure see `ANIMATION_FIX_PLAYBOOK.md`. This file
supersedes the "Pre-deploy checklist" and "Verification matrix" in
`RECIPES.md` when there is conflict.

If a gate cannot be satisfied right now, you must either:
1. Fix it before declaring complete, OR
2. Record an explicit deferral in `CHANGELOG.md` for that version with
   (a) the gate name, (b) the failure mode (dump output, repro steps),
   and (c) the reason for deferral. Then add a `TODO.md` entry.

A variant landed without walking these gates IS the bug class this
file exists to prevent. Version history is full of variants that
shipped "looking right" then broke on equip / fire / forge / preview /
dual-wield render. Every one was a missed gate.

---

## Design intent — cross-character base templates are the feature

CWV variants intentionally clone from cross-character base templates
to bring other characters' movesets onto receivers (Kruber wielding
Sienna's 2H mace, Bardin wielding Saltzpyre's priest hammer, Kruber
wielding Kerillian's dual swords, etc.). This is the design, not a
bug — the whole point is semi-lore-friendly variants that play
differently enough from a receiver's vanilla loadout to feel like
natural new weapons. 1P side is universal across characters and needs
no work. The 3P side is where the work lives: remap source-weapon
events onto the receiver's good-enough native 3P vocabulary so
bystanders in the lobby see something plausible. **G-CROSS-CHAR** and
**G-3P-ANIM** below capture the discipline for that remap. See
`ISAAK_RECIPE.md` for the lessons-learned reference on 3P remap
technique.

---

## How to use this file

1. Identify which **trait gates** apply by walking the matrix below.
2. Walk **Universal gates** (mandatory).
3. Walk each applicable **trait gate**.
4. Paste the **Definition of Done footer** into the variant's
   `CHANGELOG.md` entry, listing which gates were walked and any
   deferrals.

### Trait matrix

| Trait | Apply gate | Skip if |
|---|---|---|
| `left_hand_unit` is set OR registered as dual-wield | **G-DUAL** | Single weapon only |
| Base weapon has `ammo_unit` / `ammo_unit_3p` / `projectile_units_template` | **G-RANGED** | Pure melee |
| Variant is a thrown projectile (javelin, throwing axe, etc.) | **G-THROWN** | Not throwable |
| ANY unit ref (right/left, illusion, pickup, projectile, 3P override) comes from a different character's package than `base_weapon`'s native owner | **G-CROSS-CHAR** | All units native to the wielder's package |
| `rarity = "default"` (forge-friendly blacksmith template) | **G-BLACKSMITH** | rarity is exotic / unique / magic / common |
| Variant's mesh is also used by another variant or vanilla item_type | **G-MESH-FAMILY** | Mesh appears in this variant only |
| Variant uses cross-character moveset (different character's `state_machine` / `anim_event_3p` / `wield_anim_3p`) | **G-3P-ANIM** | Native moveset only |
| Variant has a special-key-toggleable second moveset | **G-STANCE** | Single moveset |
| Variant adds custom illusions to its picker (curated `skin_combination_table`) | **G-CUSTOM-ILLUSION** | Reuses base weapon's vanilla skin pool or has no `item_type` override |
| Variant overrides ANY of units / transform (scale/offset/rotation) / texture / ammo relative to `base_weapon` (i.e. essentially every cross-character variant) | **G-APPEARANCE** | Renders exactly like `base_weapon` on every path and observer |

---

## Universal gates (every variant)

### U-1. IML and template verified against source

- [ ] Read the base weapon's `ItemMasterList` entry from
  `Vermintide-2-Source-Code/scripts/settings/equipment/item_master_list_*.lua`.
  Confirmed: `template`, `item_type`, `slot_type`, `right_hand_unit`,
  `left_hand_unit` (if shield/dual), `can_wield`, `skin_combination_table`,
  `ammo_unit*` (if ranged), `projectile_units_template` (if ranged),
  `pickup_template_name` (if ranged).
- [ ] Read the source weapon template at
  `Vermintide-2-Source-Code/scripts/settings/equipment/weapon_templates/*.lua`.
  Noted `wield_anim`, `state_machine`, every `anim_event`, every
  `damage_profile`, every `hit_effect`, every `impact_sound_event`.
- [ ] If the resolved damage_profile chain references a different
  element than the variant should have (fire on a non-fire wielder,
  etc.), the **Damage-type swap add-on** in `RECIPES.md` is applied.

### U-2. Item key, character prefix, careers

- [ ] `item_key = "cwv_<wielder_prefix>_<short_name>"`. Wielder's
  prefix, NOT the source weapon's.
- [ ] `careers` list is correct for the variant's intent. Used the
  helpers (`_es_all_careers` etc.) where they apply.
- [ ] If `item_type` is overridden, also added to `_seed_targets` and
  `_item_type_to_skin_table`.
- [ ] If the variant ships pre-baked traits + properties (curated
  exotic / unique / modded-rarity instances), the trait/property
  choices are aimed at a **real Cataclysm breakpoint** confirmed
  with the user or against the Royale w/ Cheese community
  breakpoint spreadsheet — NOT fabricated. Crit-dependent
  breakpoints are only "reliable" when paired with a guaranteed-crit
  talent. See `DEVELOPMENT.md` "Build discipline — don't fabricate
  breakpoints".

### U-3. Build-from-ground-up integrity

This gate guards against "I cloned a similar variant and it looks
mostly right" — the dominant failure mode behind missing pickup
templates, missing ammo mirrors, missing display rigs, missing
package preloads.

- [ ] Variant def lists every field from the BASE template that the
  variant's behavior depends on, even if "the same as base" — do not
  rely on inheritance through skin systems. Specifically:
  - `right_hand_unit` (always)
  - `left_hand_unit` (if shield or dual)
  - `ammo_unit`, `ammo_unit_3p` (if ranged)
  - `projectile_units_template` (if ranged)
  - `pickup_template_name`, `link_pickup_template_name` (if ranged
    or thrown)
  - `display_dual_weapons` (if dual; matching rig — see G-DUAL)
- [ ] If the variant clones a template and the base has any
  per-character logic (career-keyed previewer fields, ammo-data,
  damage-profile chains), the BASE template was patched in the
  appropriate hook — NOT only the cloned template (see
  `feedback_cwv_previewer_template_lookup.md`,
  `feedback_cwv_projectile_template_lookup.md`).

### U-4. Scale and grip applied

- [ ] If the wield pose differs from base (hand on blade, weapon
  floating, off-axis), `entry._type_transforms[item_type]` carries
  scale / offset / rotation overrides.
- [ ] Grip Z sign is **POSITIVE** to lower the grip in-hand
  (i.e. hand moves DOWN the haft). Negative Z raises the grip
  (typical "hand on blade" failure). Reference:
  `feedback_grip_offset_sign.md`.
- [ ] If the grip needs different values per perspective, used
  `_1p` / `_3p` suffixes (RECIPES.md "Per-perspective scale").

### U-5. Inventory icon + HUD icon

- [ ] Variant has its own `inventory_icon` and `hud_icon`, OR
- [ ] Variant explicitly points at the source weapon's vanilla icons
  AND a `TODO.md` entry exists for custom icons.

A variant without any icon plan is NOT done. "I'll do icons later"
without a TODO is the failure mode.

### U-6. Localization

- [ ] `<item_key>_name` and `<item_key>_description` resolve via the
  Localize hook (default behavior for entries that set
  `display_name` / `description` in the def — verify by reading the
  loc map at line ~2303).
- [ ] If the variant has a custom `skin_display_name`,
  `<item_key>_skin_name` is mapped.

### U-7. Forward-reference audit

- [ ] Skimmed from edit point down to file end. Every function/local
  called from new code is defined ABOVE the call site. Ref:
  `feedback_lua_forward_reference.md` — five shipped crashes from
  this single bug class.

### U-8. Build hygiene

- [ ] `MOD_VERSION` (line 3 of `character_weapon_variants.lua`)
  bumped — required for visual confirmation the build loaded.
- [ ] `CHANGELOG.md` entry added with concrete fix description (the
  repo's style is "what changed and why", not "fixed bug").
- [ ] Built (`vmb.js build character_weapon_variants ...`).
- [ ] `bundleV2/` files regenerated (timestamp check).
- [ ] Deployed to
  `C:\Program Files (x86)\Steam\steamapps\workshop\content\552500\3716869446`.

### U-9. Live verification matrix

After a full game restart (hot-reload is unsafe), walk every cell:

- [ ] **Inventory list:** variant appears with correct name,
  description, icon, rarity color.
- [ ] **HeroPreviewer (inventory character preview):** mesh renders
  correctly. No stuck idle stance, no base-weapon mesh fallback
  (see `feedback_vt2_no_tpose_default_stance.md` — missing-event
  symptom is "previous-weapon idle held," not a T-pose). Wield pose
  looks right. Scale + grip applied to BOTH hands (if dual).
  Reference: `feedback_preview_slot_keying.md`.
- [ ] **Illusion picker:** opens without crash. Curated illusions
  show; vanilla skins don't bleed through (or do, intentionally,
  per design). Each thumbnail spawns correctly.
- [ ] **In-game equip:** Held mesh visible in 1P. 3P body mesh
  visible (mirror or spectator). Correct wield pose on the 3P body.
- [ ] **In-game combat:** L1 / L2 / L3 / H1 / H2 / push /
  push-attack each play visibly on the 3P body. Run `/animlog` —
  no `[MISSING]` warnings.
- [ ] **Native-wielder regression:** equipped the BASE weapon on
  its native wielder; nothing changed for them.

If the in-game pass surfaces a 3P animation gap and you cannot fix
it now, **G-3P-ANIM** is the gate that records the deferral.

---

## G-DUAL — Dual-wield gate

### Why

Dual-wield variants have repeatedly shipped with one hand invisible,
crashed in the picker, or animated a single hand for a two-hand
moveset. ~20 versions of debugging produced the `_force_display_unit`
rule. Reference: `J_LEFTWEAPONATTACH_INVESTIGATION.md`,
`feedback_cwv_dual_wield_display_rig.md`.

### Gates

- [ ] `_force_display_unit[item_key]` is set with the correct rig
  (`display_dual_weapons` or matching dual rig).
- [ ] `display_dual_weapons` set in BOTH the IML entry and on
  `WeaponSkins.skins[<skin_key>]` for every illusion.
- [ ] `left_hand_unit` set in BOTH the IML entry and on every
  `WeaponSkins.skins[<skin_key>]` entry.
- [ ] If the variant uses inverse-hand layout, the
  **Inverse-hand add-on** in `RECIPES.md` is applied.
- [ ] If the off-hand mesh is from a different character than the
  main hand, **G-CROSS-CHAR** also applies.
- [ ] **Live test:** illusion picker thumbnails show BOTH hands
  rendered. (The single-hand picker is the j_leftweaponattach
  regression.)
- [ ] **Live test:** in-mission combat shows BOTH hands swinging
  through L1/L2/L3 chain. No invisible off-hand.

---

## G-RANGED — Ranged ammo gate

### Why

Skin systems nuke ammo fields by default. Missing
`ammo_unit_3p` → 3P body shoots empty hands. Missing
`pickup_template_name` → pickup crash. Missing init hook → projectile
reads BASE template's actions and ignores variant tuning. Reference:
`feedback_cwv_ammo_unit_required.md`,
`feedback_cwv_projectile_template_lookup.md`.

### Gates

- [ ] Variant def mirrors from base: `ammo_unit`, `ammo_unit_3p`,
  `projectile_units_template`, `pickup_template_name`,
  `link_pickup_template_name`.
- [ ] If `def.left_hand_unit` is fallback-set in code, the fallback
  is gated on `base.ammo_unit` existing (non-ammo bases like brace
  crash on the assertion otherwise — v0.1.184 lesson).
- [ ] `PlayerProjectileUnitExtension` init hook covers this variant
  if its projectile init reads from `BackendUtils.get_item_template`
  on the base — without the hook, the variant's projectile ignores
  the cloned template's tuning.
- [ ] **Live test:** fire the weapon. Projectile spawns with correct
  visual. Ammo count decrements. Reload completes cleanly.
- [ ] **Live test:** drop pickup, walk away, walk back, pick up. No
  crash, no missing visual.

---

## G-THROWN — Thrown-projectile gate

### Why

Thrown weapons need a 7-layer fix stack: template clone, projectile
system swap (init hook), pickup template registration, impact_data
swap, carrier-unit pattern (held meshes have 0 actors), package
force-load, derived-class hooks. Canonical:
`cwv_es_outrider_grenade_launcher` and Tuskgor Javelin. Reference:
`reference_cwv_thrown_weapon_recipe.md`,
`reference_cwv_thrown_weapon_template_clone.md`.

### Gates

- [ ] All seven layers of `reference_cwv_thrown_weapon_recipe.md`
  applied (template clone, projectile-system init hook, pickup
  template registered, impact_data swapped, carrier-unit visual
  attach if held mesh has no actors, package force-load, derived
  class hooks where applicable).
- [ ] Auto-catch reload disabled via `condition_func` override on
  the cloned action template, NOT via timing fields.
- [ ] If using carrier-unit hide-parent trick, the
  `_carrier_visuals` map is populated so OutlineSystem forwarding
  works (v0.1.248 lesson — tagged-pickup outlines).
- [ ] **Live test:** throw, walk to landed projectile, pick it up
  by tag (white outline visible) and walk-over.
- [ ] **Live test:** throw at wall — projectile sticks (or
  bounces/dissipates per design). No crash on impact.
- [ ] If the recovered pickup uses a mod-only `NetworkLookup` key,
  preserve that functional pickup only under confirmed peer parity;
  the mixed-lobby fallback must remain wire-safe. Verify solo,
  all-modded host/client, and one non-modded peer.

---

## G-CROSS-CHAR — Cross-character package gate

### Why

Vanilla queues packages off the variant's own `right_hand_unit` /
`left_hand_unit` only. Any unit ref from a different character's kit
(pickup units, 3P override units, cosmetic illusion meshes,
projectile units) crashes on `World.spawn_unit` if not pre-loaded.
Hit at least twice — Tuskgor Javelin v0.1.118, Brace-Repeater
v0.1.180+. Reference: `feedback_cwv_cross_character_unit_packages.md`.

### Gates

- [ ] Cataloged every unit ref the variant introduces (right/left
  hand, illusion meshes from other characters, pickup units,
  projectile units, 3P override units).
- [ ] Every cross-character unit ref is either:
  (a) a static dependency in
      `resource_packages/character_weapon_variants/character_weapon_variants.package`,
      OR
  (b) force-loaded at runtime via `Managers.package` before any
      code path can request the spawn.
- [ ] **Live test:** equip the variant on a fresh game launch (no
  prior load of the source character's package). No
  `World.spawn_unit` crash.
- [ ] **Live test (host + client):** equip in a multiplayer lobby.
  No item-sync crash.

---

## G-BLACKSMITH — Blacksmith template (rarity = "default") gate

### Why

`rarity = "default"` variants hit the forge: re-roll properties,
salvage, apply illusion. Skipping the BackendUtils override hook
means `get_item_template` returns the base template at runtime and
all variant tuning is dead code. Skipping `matching_item_key = base_weapon`
means the forge applies illusions wrongly. Reference:
`reference_cwv_blacksmith_template.md`.

### Gates

- [ ] `entry.rarity`, `entry.mod_data.rarity`,
  `entry.mod_data.CustomData.rarity` all set to `"default"`.
- [ ] `_auto_register_all` post-registration rarity upgrade is
  SKIPPED for this variant (it's gated on
  `def.rarity ~= "default"`; verify the def has
  `rarity = "default"`).
- [ ] `matching_item_key` set to the BASE weapon (NOT the variant
  key) — wrong value causes forge to apply illusions to the wrong
  item.
- [ ] `BackendUtils.get_item_template` override hook covers this
  variant.
- [ ] No skin pre-application during registration (the forge
  applies skins; do not double-apply).
- [ ] **Live test:** open the forge. Re-roll properties → variant
  takes new properties. Salvage → currency awarded. Apply illusion
  → illusion attaches without crash and shows on the variant.
- [ ] **Live test:** variant shows as unlocked, not as a
  locked-illusion.

---

## G-MESH-FAMILY — Shared mesh tuning gate

### Why

When the same mesh is used by multiple variants/item_types,
duplicating scale/grip overrides per-variant rots fast. Tunes go in
`_type_transforms[item_type]`. Per-variant override only for genuine
model-axis deviations (e.g. one specific Frankenstein variant where
the mesh sits at an unusual angle). Reference:
`feedback_cwv_imperial_longsword_family.md`.

### Gates

- [ ] Scale/grip is in `_type_transforms[item_type]`, NOT
  duplicated across every variant of the same item_type.
- [ ] Per-variant override exists ONLY if the variant genuinely
  deviates on a model axis the other variants don't share.
- [ ] If the mesh is shared with a vanilla item_type, the override
  doesn't regress vanilla wielders (test on at least one vanilla
  user of that mesh).

---

## G-3P-ANIM — 3P animation gate (cross-character moveset)

### Why

1P animations are universal across all six characters; 3P body
animations are character-specific. Any cross-character variant whose
3P moveset uses a different character's `state_machine` /
`anim_event_3p` / `wield_anim_3p` will silently no-op missing events
on the wielder's body (the body holds the previous weapon's idle
stance — see `feedback_vt2_no_tpose_default_stance.md`; **not** a
T-pose, despite older docs) or play wrong clips. Reference:
`ANIMATION_FIX_PLAYBOOK.md`,
`feedback_1p_animations_universal.md`,
`feedback_animation_remap_rules.md`,
`feedback_anim_closed_vocabulary.md`.

### Gates

- [ ] Followed `ANIMATION_FIX_PLAYBOOK.md` 9-step procedure for
  EVERY missing event surfaced by `/animlog`.
- [ ] Remap targets are in the target wield-SM template's
  `anim_event` set — NO skeleton-probe invention. Closed vocabulary
  rule.
- [ ] 1P fields (`anim_event`, `wield_anim`, `state_machine`) NOT
  overridden — only 3P fields touched.
- [ ] **Live test:** `/animlog` shows zero `[MISSING]` warnings
  for the variant during the L1/L2/L3/H1/H2/push/push-attack chain.
- [ ] **Husk check:** another player or a bot wields the variant —
  their body animates correctly (cross-access remap doesn't cover
  husks by default; if the husk holds a stale idle stance / misses
  attack animations — see `feedback_vt2_no_tpose_default_stance.md`,
  the actual missing-event symptom — record it as a deferral, not a
  complete-blocker).

### Acceptable deferral

If 3P animation work is non-trivial (new closed vocabulary, new
remap table entries) and would block shipping otherwise polished
work, defer with:

- `TODO.md` entry naming the variant and missing events.
- `CHANGELOG.md` entry naming the gap explicitly: e.g.
  `Known issue: 3P L3 no-ops for X career (body holds previous idle —
  see feedback_vt2_no_tpose_default_stance); fix tracked in TODO.md`.

A 3P animation gap is the ONE gate where shipping with explicit
deferral is acceptable — every other gate in this file must be
either fixed or explicitly TODO'd before declaring complete.

---

## G-STANCE — Stance toggle (runtime template swap) gate

### Why

Variants with a special-key-toggleable second moveset
(musket → bayonet melee, etc.) require a 7-component stack:
two templates, destroy_slot+add_equipment+wield cycle,
BackendUtils.get_item_template hook, ammo persistence, lookup_data
attach, SM force-load, per-template runtime overrides. Canonical:
`cwv_es_musket` v0.1.231+. Reference:
`reference_cwv_stance_toggle_recipe.md`,
`reference_cwv_bayonet_pattern.md`.

### Gates

- [ ] Both templates registered. Each has its own
  `_type_transforms` entry.
- [ ] Stance switch via `destroy_slot` → `add_equipment` → `wield`
  cycle (NOT direct unit swap).
- [ ] `BackendUtils.get_item_template` hook returns the correct
  template per current stance.
- [ ] Ammo state preserved across stance switches.
- [ ] State machine package force-loaded.
- [ ] Per-template runtime overrides (scale, grip, rotation) apply
  correctly per stance.
- [ ] If a fixed-attachment child unit is involved (welded bayonet),
  every gate in the bayonet pattern reference is also walked
  (visibility sync, orphan prune, package force-load,
  mark_for_deletion async handling).
- [ ] **Live test:** equip → toggle stance → equip another item →
  re-equip → toggle stance again. No crash, no orphan, no
  invisible bayonet, no floating bayonet.
- [ ] **Live test:** toggle stance during combat. No state-machine
  break.

---

## G-CUSTOM-ILLUSION — Curated illusion picker gate

### Why

Custom illusions need three table injections + an unlocked-skins
hook + a Localize hook. Missing any of them yields locked-illusion
display, missing names, or skins that don't appear. If illusions
have a paint pipeline (Loremaster's Armoury offhand etc.), more
gates apply. Reference: `reference_la_offhand_paint.md`,
`feedback_loot_previewer_hook_not_safe.md`.

### Gates

- [ ] `ItemMasterList[skin_key]` set with `matching_item_key`
  pointing at the variant.
- [ ] `WeaponSkins.skins[skin_key]` set with unit paths and
  visual data. If dual-wield, includes `left_hand_unit` and
  matching `display_dual_weapons`.
- [ ] `WeaponSkins.skin_combinations[<curated_table>]` lists every
  skin under the appropriate rarity tier.
- [ ] `BackendInterfaceCraftingPlayfab.get_unlocked_weapon_skins`
  hook marks custom skins as unlocked.
- [ ] `_G.Localize` hook returns display names for skin keys.
- [ ] If illusion source meshes come from another character,
  **G-CROSS-CHAR** also applies.
- [ ] If wrapping `LootItemUnitPreviewer.spawn_units`, used
  `mod:hook` (full wrapper), NOT `mod:hook_safe` —
  `self._spawned_units` is assigned by caller AFTER spawn_units
  returns. Reference: `feedback_loot_previewer_hook_not_safe.md`.
- [ ] **Live test:** open picker for the variant. Every curated
  illusion thumbnail spawns correctly. No vanilla bleed-through
  (unless designed). Names display correctly. Apply each illusion
  in inventory → mesh changes correctly on the character preview
  AND in mission.

---

## G-APPEARANCE — Weapon appearance across render paths + observers

### Why

The recurring bug class: an attribute (mesh / transform / texture / ammo) is
correct in ONE render path or for ONE observer and wrong in another — right for
the wielder, wrong for a teammate's husk; right in-world, wrong on the inventory
preview. Full contract: `docs/WEAPON_APPEARANCE_STANDARD.md` (the four render
paths, the five appearance concerns as one interface, the concern×path matrix).

### Gates

- [ ] Every overridden concern resolves through its standard §2 module — NO
  inline `Unit.set_local_*` (use `WA` / `mod._cwv_weapon_appearance`), NO
  `Material.set_texture` (use `Unit.set_texture_for_materials`), NO hand-spawned
  preview unit (mutate `spawn_data.unit_name`). One owner per concern.
- [ ] The variant renders its own mesh on ALL FOUR paths: owner in-world, husk
  (remote), inventory preview (`MenuWorldPreviewer`), illusion browser
  (`LootItemUnitPreviewer`). Preview/browser receive the BASE key, so a mesh
  override needs an explicit swap there (standard §4.1).
- [ ] Transform (scale/offset/rotation) applies on the owner AND the husk paths;
  1P and 3P stay on SEPARATE units.
- [ ] Custom textures use the per-unit primitive and persist per `backend_id`
  (re-equip / unequip restores them — like vanilla illusions).
- [ ] Override units are force-loaded resident on every peer that must render
  them (husk residency; owner too when the unit is in a package the wielder's
  career does not natively load).
- [ ] If husk correctness depends on the cwv identity surviving the wire, the §5
  sync marker is in place OR the CHANGELOG explicitly declares the husk limit
  (the husk receives the BASE key — #392).
- [ ] **Live test:** walk the standard §6 verification matrix — owner keep + owner
  mission + client/husk mission + inventory preview + illusion browser + re-equip
  + hot-join. A cell that passes for the owner but fails for the husk is the #392
  class; a cell that passes in-world but fails in preview is the #237 class. User
  confirms in-game (compile is not verification).

CHANGELOG footer add-on when this gate applies:
`Gates: G-APPEARANCE (matrix cells verified: <list; e.g. owner-keep, preview>).`

### Executable census prerequisite

- [ ] The changed appearance concern is registered in
  `qa/appearance_contracts.psd1`; every canonical surface and replay edge is
  explicitly covered, deferred, or not-applicable.
- [ ] Every covered cell maps to a named offline test and
  `qa/check_appearance_contracts.ps1` passes.
- [ ] Treat that pass as structural evidence only. Live owner/peer observation
  and retained postconditions above are still required before verification.

---

## Definition of Done footer (paste into CHANGELOG entry)

When a variant is declared complete (or substantially updated),
the CHANGELOG entry must end with:

```
**DoD:** Universal walked. Trait gates: <list, e.g. G-DUAL, G-CROSS-CHAR>.
Deferrals: <none, OR list with TODO refs>.
```

Examples:

```
**DoD:** Universal walked. Trait gates: G-RANGED, G-CROSS-CHAR.
Deferrals: G-3P-ANIM — H2 plays as base spear thrust on Bardin;
TODO.md "Tuskgor Javelin Bardin H2 anim".
```

```
**DoD:** Universal walked. Trait gates: G-DUAL, G-MESH-FAMILY,
G-CUSTOM-ILLUSION. Deferrals: none.
```

If you can't honestly write the footer, the work isn't done — go
fix the gates or record explicit deferrals.

---

## Maintenance

When you discover a new gap that should have been caught here, ADD
A GATE — don't just fix the bug. The cost of one new checklist line
is much less than the cost of the user finding the same gap class
again.
