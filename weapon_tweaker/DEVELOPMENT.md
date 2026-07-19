# Weapon Tweaker — Development Notes

## Executioner's Sword light-headshot transaction (Issue #664)

The native template has four light sweeps, including the push follow-up, and all
four point to `medium_slashing_linesman_executioner`; its two heavy sweeps point
to `heavy_slashing_smiter_executioner` [src:
`scripts/settings/equipment/weapon_templates/2h_swords_executioner.lua:230-961`].
The light profile is shared data, so WT never edits it. `_wt_axe_balance.lua`
deep-clones it as `wt_executioner_light_headshot_130`, marks only that private
clone, and repoints only light actions through the existing bounded restore and
#431 peer-parity transaction.

VT2 calculates complete damage, including armor, buffs, and stagger, before
`DamageUtils.calculate_damage` returns [src:
`scripts/helpers/damage_utils.lua:449-569`]. Its canonical headshot classifier
is `DamageUtils.get_breed_damage_multiplier_type` [src:
`scripts/helpers/damage_utils.lua:54-61`]. WT's single preflight-audited hook
multiplies the returned damage by `1.30` only when both the private profile
marker and the engine's `headshot` classification are present. This makes the
requested total-damage delta exact without changing body or heavy profile data.

## Isolated weapon balance transactions (Issues #601/#621/#622/#623)

Weapon Tweaker owns the three default-on controls under `Weapon Tweaks`:
Greataxe light critical chance, Dual Axes light critical chance, and Dual Axes
cleave. `_wt_axe_balance.lua` is engine-free and reversible. It always targets
the native templates and treats `cwv_greataxe_template` as optional, scanning
again when CWV's late registration becomes ready. CWV absence is therefore a
normal supported state, not an error or dependency boundary.

Generated `wt_axe_cleave_*` profiles clone source damage and cleave rows,
scaling only cleave attack/impact. Disabling restores exact captured action
fields; repeated enabled reconciliation only discovers previously unseen late
actions and never compounds existing mutations.

Three additional controls are default-off and share the same lifecycle owner:

- **1H Axe cleave nerf (#621):** discovers templates by the exact combat
  capability tuple `weapon_type=AXE_1H`, `buff_type=MELEE_1H`,
  `state_machine=.../melee/1h_axe`, and no left-hand unit. This includes
  donor-faithful WT/CWV clones without maintaining display-name lists. It
  deliberately excludes Dual Axes (`.../dual_axes`), Axe and Shield
  (`AXE_1H_SHIELD`, `.../1h_axe_shield`), throwing axes, and 2H axes. Direct
  attack profiles are privately cloned at 0.90x attack/impact cleave; source
  profiles and shared PowerLevelTemplates remain untouched.
- **Cog Hammer heavy speed nerf (#622):** scales only the four release nodes
  `heavy_attack_left/right` and `heavy_attack_left/right_charged` by `1/1.10`.
  Lights (including charged-mode lights), wind-ups, push, block, wield, and
  weapon special are outside the action allow-list.
- **Mace and Sword speed nerf (#623):** targets only vanilla
  `dual_wield_hammer_sword_template`: L1 `light_attack_left_diagonal`, L2
  `light_attack_right`, and `heavy_attack`/`heavy_attack_2`. The CWV reversed
  `sword_and_mace_template`, later lights, push, block, wield, and inspect are
  excluded by exact template/action identity.

For speed, `anim_time_scale` is the authoritative action scalar: vanilla
divides completion and chain-window times by it
(`weapon_unit_extension.lua:487-489,930-937`). Therefore dividing the authored
scale by 1.10 makes the selected attacks take 10% longer without rewriting
every damage window or chain timestamp. All policies restore captured nil and
non-nil values exactly and are safe to reapply on state transitions.

## Conditional CWV ownership

Issue #620 uses a conditional default rather than an ownership handoff. Native
`es_2h_heavy_spear` remains the one Tuskgor item in both mods. WT-alone keeps
Foot Knight default-off; active CWV marks the live item with
`cwv_combat_style_family="spear"` and `cwv_combat_style_ready=true`. Only after
both positive markers exist does `_wt_availability.lua` seed the exact Foot
Knight setting on once per profile. The seed sentinel prevents later state
transitions or CWV hot reloads from overriding a user's subsequent choice.

Combat Styles retire WT catalogue rows in the same release that CWV retires
their craft definitions. `cwv_es_infantry_spear`, `cwv_es_longsword`, and
`cwv_es_longsword_blackguard` are restore-only keys; never add WT
masters/children/localization for them again. Their native Tuskgor/Greatsword
rows remain the sole availability controls.

WT fallback ports remain real features when their dedicated CWV equivalent is
absent. A row in `cwv_conditional_managed` is a live ownership handoff, not a
permanent tombstone: WT suppresses the donor-native pair only while CWV is
loaded and enabled, then restores the user's WT toggle when CWV is disabled or
removed. Issue #368 removes the legacy `cwv_managed` cede entirely; WT and
CWV may overlap, and WT is the final availability control surface.

Use `_wt_cwv_ownership.lua` on both the `can_wield` writer and backend cache
reader. Reconcile only on active-state transitions. Keep settings widgets and
localization intact so suppressed preferences return without a restart; never
suppress the donor's native careers.

Issue #593 applies this handoff to both Kruber and standard Saltzpyre. With CWV
active, WT suppresses Bardin's `dr_shield_axe` for those seven receivers and
exposes `cwv_es_axe_shield` / `_veteran` to the three standard Saltzpyre careers.
The catalog's `conditional_careers` field marks only WT-added cross-receiver
owners; an inactive CWV or disabled WT strips those additions without touching
CWV's four authored Kruber owners. Warrior Priest is outside this handoff.
The same transition reconciliation rebuilds template career-action injections;
otherwise disabling CWV would leave Saltzpyre ability actions on the variant's
shared template, while a default-on variant with the donor fallback disabled
would never receive those actions in the first place.

## Baked shield rotations

Receiver-specific rotation belongs to the durable 3P transform owner, not a
shared attachment-linking template. Issue #112 seats Kruber-derived shield
ports on standard Saltzpyre bodies with local Euler `{25, -17.5, -15}` while
they use the Axe+Falchion animation vocabulary. The catalog includes
`es_mace_shield`, `es_sword_shield`, `es_sword_shield_breton`, both CWV Empire
Axe+Shield identities, and the live CWV donor-name alias `dr_shield_axe`.
`es_deus_01` (Spear & Shield) is deliberately excluded.

The orientation tracker boxes canonical rotation at spawn and rebuilds
`canonical * delta` while wielded for owner, bot, husk, and inventory-preview
3P units. Do not multiply the live rotation or mutate shared templates: either
would accumulate or affect native Kruber. First-person units and network state
remain outside this path.

Architecture, gotchas, and conventions for `weapon_tweaker`. Read alongside
`CHANGELOG.md` (history), `CODE_REVIEW.md` (current health), `REGRESSION_CHECKLIST.md`
(pre-release gates), and `CROSS_CHARACTER_PORT_RECIPE.md` (the seven-step procedure
for adding a new cross-character weapon port).

---

## Module map (v0.12.237-dev)

`weapon_tweaker.lua` is still the primary file (~5,320 lines) — this is an
IN-PROGRESS decomposition (OOP_REFACTOR_PLAN WS5, PROJECT_STANDARDS §2.2a), not a
finished one. Phase 1 carved out the four cleanest self-contained concerns;
Phase 2 (v0.12.210-dev) extracted the 3P anim-remap CORE (the funnel + redirect
layers + remap tables + per-unit state + wield hooks) into `_wt_anim_remap.lua`.
Issue #2's v0.12.235-dev slice then moved its declarative per-template catalog
to `_wt_anim_remap_data.lua`, leaving the event-hot module below the hard limit.
Still living in / beside the entry, pending later phases: the
`wield_anim_career_3p` template patchers + cross-character port pipeline (the
mesh-swap `spawn_inventory_unit` path, force-loads, previewer hooks — they READ
the anim redirect data the core owns but are their own concern), the per-frame
grip offsets, the P0 crash guards (`link_units` filter, `create_equipment`
compensations), the `anim_event_with_variable_float` crash guard, the
weapon-behavior features (Authentic Brace, WP punch, Moonfire; Bolt Staff's
scalar transaction is extracted), and the on-ice
Big-Rebalance module.

**Shared namespace `mod._wt`** (the event_tweaker `mod._evt` / cosmetics `mod._cos`
pattern) carries cross-module state. It is created in the entry manifest and
populated with the handles the `_wt_*` modules consume BEFORE they are
`mod:dofile`'d: `MOD_VERSION` (regression banner), `weapon_unlock_map` +
`cwv_conditional_managed` (the narrow #593 native-substitution handoff), and — for the anim core — `feature_enabled`,
`local_career_name`, `dbg`, `dev_anim_picker` (the four hot-path handles the
funnel reads, captured as module-local upvalues so the per-event path never
indirects through `mod._wt`), plus the one-time `build_3p_template_remaps`
builder loaded immediately before the anim core. `mod:dofile` is NOT a
singleton, so modules never dofile each other — each is dofile'd exactly once
from the manifest. It is a
SEPARATE key from the established flat `mod._wt_*` fields (`mod._wt_link_filter`,
`mod._wt_tf_*`, `mod._wt_loc_raw`, ...), which are untouched.

| Module | Owns / public surface (on `mod._wt` unless noted) |
|---|---|
| `weapon_tweaker.lua` (entry) | MOD_VERSION (launcher parses it here — never move it), the load banner/echo, the pre-existing dofile manifest (`_safe_hook`, `wt_dev_anim_picker`, `wt_dev_hold_pose`, `_wt_brett_sword_shield_buff`, `wt_unlock_data`, `wt_wield_patches`, backend, BR-on-ice), the `mod._wt` namespace setup + `_wt_*` manifest, the mod-wide lifecycle callbacks (`on_game_state_changed`/`on_setting_changed`/`on_disabled`), and everything not yet extracted: the `wield_anim_career_3p` template patchers + cross-character port pipeline (spawn/link/previewer hooks), the per-frame grip offsets, the weapon-behavior features (Authentic Brace, WP punch, Moonfire), the P0 guards (`link_units`, `create_equipment`, `anim_event_with_variable_float`), and the ~30 inline `/wt_regression_test` check bodies. `feature_enabled` + `_local_career_name` stay here (generic player-state helpers the anim funnel reads on a hot path; published to `mod._wt` for the core to capture). |
| `_wt_grip_offset_policy.lua` | Pure receiver/hand routing for baked scale, grip-offset, and rotation descriptors, plus bounded retained transform readbacks (#701 position, #735 rotation). It owns no transform values and sends no RPC; the entry-point catalogs remain the single source. |
| `_wt_paired_preview_transform.lua` | Sole `MenuWorldPreviewer._spawn_item` owner. It bridges source-authored `spawn_data` hand flags and numeric slot indices to the exact paired preview unit, then invokes the injected transform owners; no inferred hand and no RPC (#735). |
| `_wt_anim_remap_data.lua` | Declarative `_3p_template_remaps` catalog. Returns a one-time builder that receives the three existing shared remap tables and returns one mutable template catalog; no `mod`, engine, hook, command, or runtime-event dependency. The entry manifest loads it immediately before `_wt_anim_remap.lua` and publishes the builder as `mod._wt.build_3p_template_remaps`. |
| `_wt_anim_remap.lua` | The 3P anim-remap CORE (v0.12.210-dev Phase 2, catalog split in v0.12.235-dev). Owns the three redirect layers (`_anim_redirect`/`_career_anim_redirect`/`_suffix_career_map` + `_try_suffix_redirect`/`_safe_has_anim`), the per-weapon/key remap tables (`_3p_remap_*`/`_3p_key_remaps`), constructs the sibling's `_3p_template_remaps` catalog, and owns all resolvers, the weak-keyed per-unit remap state (`_unit_state`/`_state_for`), the `Unit.animation_event` funnel hook, the two wield hooks (`SimpleInventoryExtension`/`SimpleHuskInventoryExtension`) that populate the state, the anim-funnel commands (`/info`,`/animlog`,`/force3p`,`/force1p`), and the keep-previewer pose resolver `_resolve_preview_wield_event`. Hot tables are file-local upvalues (per-event-hot path). Reads `mod._wt.feature_enabled`/`.local_career_name`/`.dbg`/`.dev_anim_picker`/`.MOD_VERSION`/`.weapon_unlock_map`/`.build_3p_template_remaps`; exports `mod._wt.safe_has_anim`/`.resolve_preview_wield_event`/`.unit_career_name`/`.unit_state`/`.suffix_career_map`/`.three_p_template_remaps` (all non-hot-path reads by the entry's port pipeline, previewer, and rt-checks). The `wield_anim_career_3p` patchers, force-loads, and mesh swaps stay in the entry (port-pipeline-coupled, Phase 3). |
| `_wt_regression.lua` | `/wt_regression_test` harness: `_RT_CHECKS` + `rt_register` + the command. Loads FIRST. Reads `mod._wt.MOD_VERSION`; exports `mod._wt.rt_register`. The check bodies stay inline in the entry (they close over its file-locals) via `local _rt_register = mod._wt.rt_register`. |
| `_wt_availability.lua` | Cross-character weapon availability: `apply_weapon_unlocks` (can_wield strip/add), CWV marked-variant final writes, provider-neutral all-row career-ability action injection, disable cleanup, and removed-pair tombstones. Reads `mod._wt.weapon_unlock_map`, `.cwv_conditional_managed`, `wt_cwv_variant_catalog.lua`, `_wt_cwv_availability_policy.lua`, and the synced `_lib_career_weapon_actions.lua`; exports the four lifecycle functions. CWV item masters retain #368's IDs and compose with exact per-career child settings (#391). |
| `_wt_cwv_effective_template.lua` | Fail-closed consumer for CWV's optional Combat Style donor-template-name contract. It accepts only a registered `Weapons` key and otherwise preserves the native item template; family/style knowledge remains in CWV. Used by owner and husk wield-state population before WT selects its existing 3P remap. |
| `_wt_master_toggles.lua` | Issue #611 Weapon Availability batch controls. Builds one master per receiving-career/slot/source-character bucket inside each career leaf, ordered Kruber/Bardin/Kerillian/Saltzpyre/Sienna. Each master owns its weapon checkboxes as `sub_widgets`, giving Mod Tweaker's gear/advanced-options path one bulk checkbox plus independent manual choices without flat duplication. Owns bounded cascade, one-master child recompute, load-time derived state, open-menu refresh, and the VMF checkbox-factory `font_button_normal` style. The file is byte-identical in the dev parity mirror. |
| `_wt_trait_pools.lua` | CW weapon-trait pool filtering (`_trait_pool_sources`, snapshot, `apply_trait_filters` / `revert_trait_pools`). Currently a retired no-op stub (menu removed 2026-06-29) kept so nothing dangles. Reads `WeaponTraits`; exports `mod._wt.apply_trait_filters` / `.revert_trait_pools` + the legacy flat `mod._apply_trait_filters` / `mod._revert_trait_pools`. |
| `_wt_diagnostics.lua` | Read-only diagnostic dump/probe commands (`/sm_probe`, `/dump`, `/dump_actions`, `/dump_weapons`, `/wt_dump_wielded`) + the wield-time weapon-data dump and its sole `SimpleInventoryExtension._wield_slot` hook_safe. Reads engine globals only; no exports; leaf. |
| `_wt_bolt_staff_overcharge.lua` | Issue #341's hook-free Bolt Staff primary-overcharge transaction. Owns the 0.6 planner plus snapshot/apply/revert runtime for the unique `PlayerUnitStatusSettings.overcharge_values.spark` scalar. Returns its module table directly; the entry wires init, lifecycle, setting-change, disable, and runtime regression surfaces. |
| `_wt_axe_balance.lua` | Engine-free reversible Weapon Tweaks transactions for #601/#621/#622/#623. Owns exact action/template capability boundaries, private cleave-profile generation, deterministic registration, authored speed snapshots, and hot-toggle restoration. The entry owns setting/lifecycle dispatch and #621's existing #431 peer-parity gate. |
| `_wt_overcharge_presentation.lua` + `_policy` | Issue #388's cross-career Deepwood parity. The owner-side module reversibly projects `OverchargeData.we_thornsister` onto the local player's existing overcharge extension while `we_life_staff` is equipped, and lazily hooks `OverchargeBarUI.set_charge_bar_fraction` for local/spectator native colors. The pure sibling owns identity/profile/color tests. No transport is added. |
| `_wt_flamestorm_fx_policy.lua` / `_wt_flamestorm_fx.lua` | #400 exact cross-career Flamestorm target policy plus observer-side replicated 3P flame orientation. Keeps the 3P muzzle position, replaces only particle rotation with network `aim_direction`, and owns the `WeaponSystem.rpc_start_flamethrower` / `update_synced_flamethrower_particle_effects` post-hooks. |
| `wt_dev_hold_pose.lua` | #616 local-owner transform authoring. Owns separate first-person and third-person right/left offset, Euler rotation, and absolute scale channels; channel-local weak baseline caches; non-destructive enable/bypass/restore; per-frame apply; reset/dump commands; and its widget/localization subtree. The entry dispatches `wt_dev_hp_*` setting changes and disable cleanup. It must never target previewers, bots, husks, score presentation, or committed appearance definitions. |

Pre-existing `_*.lua` / `wt_*.lua` modules (`_safe_hook`, `_wt_brett_sword_shield_buff`,
`_wt_passive_charge`, `wt_dev_anim_picker`, `wt_dev_hold_pose`, `wt_unlock_data`,
`wt_wield_patches`, `wt_port_status`, `weapon_tweaker_backend`) predate this split —
leave their internals alone. The retired Big Rebalance implementation and definitions
were deleted under #433 and remain recoverable from git history.

### Hold-Pose tuner channel boundary (#616)

The development tuner has two isolated local-owner channels. `first_person`
resolves only `equipment.right_hand_wielded_unit` / `left_hand_wielded_unit`
(or the selected slot's `*_unit_1p` fields). `third_person` resolves only the
matching `*_wielded_unit_3p` / `*_unit_3p` fields. Each channel captures its
own weak-keyed canonical baseline and applies position, rotation, and scale
through separate setters.

The master and channel enable switches are bypasses, not resets. The master
defaults off and restores both cached channels when disabled. Disabling one channel restores
only that channel's dirty units to their captured canonical/baked values and
clears only its ephemeral baseline cache. VMF retains every numeric setting;
re-enabling resumes with those values. `/wt_dev_hp_reset` is the sole operation
that writes identity values to both channels. The live tuner is deliberately
not an appearance fan-out system: inventory/hero preview, bots, remote husks,
score/team presentation, and baked transforms remain untouched.

### Where new code goes

- **New diagnostic dump/probe command** → `_wt_diagnostics.lua` (globals only; route through `mod:info`/`mod:debug`).
- **New (career, weapon) unlock or can_wield / career-ability behavior** → `_wt_availability.lua`; the (career, weapon) pair itself goes in `wt_unlock_data.lua`.
- **New regression check** → `_rt_register("name", fn)` inline in the entry next to the code it probes (the alias is live); the harness itself is frozen.
- **New per-template 3P remap catalog row** → `_wt_anim_remap_data.lua`; keep the returned table declarative and engine-free.
- **New effective clone template from CWV** → if it inherits a donor action
  graph, alias both its `_wt_anim_remap_data.lua` receiver map and
  `wt_wield_patches.lua` row to the donor table **by identity**. WT resolves by
  the effective template name supplied at wield time; copying a table permits
  later donor safety fixes to drift, while omitting the clone key falls through
  to raw donor events on the receiver skeleton (#732). Preserve native
  `prefix = false` branches and cover owner plus husk state with one contract.
- **New bounded weapon-behavior scalar** → a pure `_wt_<feature>.lua` planner/runtime module, wired into the entry lifecycle like `_wt_bolt_staff_overcharge.lua`; snapshot and restore the exact pre-WT value.
- **New cross-career weapon FX presentation** → an engine-free target-policy sibling plus a focused `_wt_<feature>.lua` runtime module; separate owner-local and synchronized observer surfaces from source before choosing hooks.
- **New 3P redirect / shared remap table / resolver, or a change to the `Unit.animation_event` funnel or the wield-state hooks** → `_wt_anim_remap.lua` (keep its hot tables file-local upvalues; export via `mod._wt` only for non-hot-path cross-module reads).
- **Anything touching the port pipeline / `wield_anim_career_3p` template patchers, the grip offsets, the previewer hooks, or a P0 guard** → stays in `weapon_tweaker.lua` until a later phase; grep ALL files for an existing hook on the `(Class, method)` before adding one (VMF drops the second — NON-NEGOTIABLE 8).
- **New cross-module value** → export onto `mod._wt` in the owning module (earlier in the manifest than its consumers) and localize it at the consumer's top.

---

## Design direction (2026-05-23)

weapon_tweaker's role is **full-freedom cross-character weapons**: a wielder
can equip any career's weapon they want. To keep the bystander 3P view
plausible, wt maps 3P anim events onto a functionally-similar native weapon's
vocab on the receiver's skeleton.

### User's verbatim framing

> "Those aren't cross-skeleton ports. The first person animations just work.
> Everyone's first person hand models work with all animations from all
> weapons so far. What we've done for weapon tweaker is allow the weapons,
> but map 3rd person animations onto them; this is where Isaak's mod should
> help quite a bit. Things like Kerillian's sword has a moveset that
> Kruber's 1H sword 3rd person animations can look mostly natural with if
> we put the animation events in the right order. For weapons like the
> Longbow on Saltzpyre or Brace of Pistols on Kruber, there are no
> animations that look right, but there are weapons that are functionally
> similar enough to where we can make the 3rd person model look like it's
> using a weapon that functions similarly enough that it looks natural to
> players in 3rd person. To other players it looks like Kruber is using a
> repeater rifle when he uses Saltzpyre's brace of pistols, but the player
> with the pistols gets to enjoy trying that weapon on a character they
> may have never been able to experiment with it on. Weapon Tweaker is
> meant to allow cross career/character weapons with complete freedom
> while still looking normal in 3rd person to other players."

### Key terminology correction

These are **NOT cross-skeleton ports**. 1P animations just work
everywhere. Only 3P needs a remap onto the receiver's existing vocab.

### Canonical wt examples to keep

- **Brace of Pistols on Kruber** — bystanders see Kruber using "a repeater
  rifle"; the wielder enjoys playing brace on Kruber.
- **Longbow on Saltzpyre** — bystanders see something like Saltzpyre's
  crossbow; wielder gets longbow.
- **Billhook on non-Kruber** — and similar genuine cross-character ports.

### The reversal (2026-05-23)

Cases where the source weapon is **functionally identical** to a receiver's
native (e.g. Bardin's axe ported onto Saltzpyre when Saltzpyre already has
a falchion-family weapon) add no gameplay value. These are being **removed
from wt** and moved to a planned `cosmetics_tweaker` cross-character
cosmetic swap.

Genuine functional cross-character ports (brace, longbow, billhook, etc.)
**stay in wt**.

### Sister projects (do not conflate)

- **`character_weapon_variants`** — semi-lore-friendly variant items that
  clone from cross-character base templates. Donor's 1P moveset is free;
  3P side uses `anim_event_3p` remap onto a good-enough native vocab. CWV
  variants are **designed to play differently enough** to feel like new
  weapons, distinct from wt's full-freedom cross-character access.
  **Independent of wt (Issue #368):** neither mod suppresses the other;
  overlap is allowed. wt is the availability control surface — its
  per-weapon toggles default ON when CWV is installed and also cover CWV's
  `cwv_variant` items with independent authored-career children (CWV has no
  availability toggles). The old
  `_cwv_managed` cede table is being removed. See `CROSS_MOD_ARCHITECTURE.md`.
- **`cosmetics_tweaker` cross-char cosmetic swap (planned)** — destination
  for identical-functional ports being removed from wt.

### Native base vs dedicated variant ownership

When CWV owns a dedicated receiver-specific item, WT must not also expose the
donor's native base to that receiver. The two entries are not interchangeable:
the CWV key owns its curated cosmetics, persistence identity, and receiver-side
presentation routing. Offering the native key beside it bypasses those contracts
and leaves CWV correct but unable to recognize the item.

Issue #582 is the canonical boundary: Bardin's native `dr_dual_wield_axes`
remains native for Bardin and keeps WT's existing Kerillian access, but Kruber
and Saltzpyre receive only `cwv_es_dual_axes` and `cwv_wh_dual_axes`. Removing a
previous WT pair requires all four layers in one change: unlock-map row, widget,
localization/dev-picker claim, and an idempotent `can_wield` tombstone plus stale
loadout-cache rejection. Regression must assert both the native exclusion and
the dedicated variant registrations.

---

## Animation remap

### 1P animations are universal — never touch

**Recurring correction across sessions.** 1P animations work on every
character with every weapon by default, with zero work from us. The 1P
first-person view is "just hands" — `first_person_base` is shared across
all six characters and any weapon's 1P state machine plays correctly on
any character's first-person unit. **Never override `anim_event` (1P),
`wield_anim` (1P), or `state_machine` per character.** Only
`anim_event_3p`, `wield_anim_3p`, and `wield_anim_career_3p` matter.

Every section below is about 3P only. There is no parallel 1P version of
the closed-vocab rule because 1P needs none.

### Unit architecture: player_unit, first_person_unit, and husks

VT2 has three types of units that receive `animation_event` calls:

- **player_unit** (`player.player_unit`, `is_local=true`) — the local
  player's **3P body**. Needs all redirects and remaps for cross-career
  weapons to work in 3P.
- **first_person_unit** (`self._first_person_unit`, `is_local=false`) —
  the local player's **1P hands**. Must NEVER receive redirects. 1P
  animations work correctly by default; redirecting wield events on this
  unit puts the 1P state machine in the wrong weapon state, breaking all
  attack animations.
- **husks** (other players' units, `is_local=false`) — need redirects
  and remaps for multiplayer 3P.

**Critical:** `is_local` does NOT distinguish 1P from 3P. `is_local=true`
means player_unit (3P body). The 1P first_person_unit has
`is_local=false` — same as husks. You cannot use `is_local` to protect
1P.

**Why:** v0.9.69 — early-returning `is_local` to protect 1P crashed the
game because it also skipped redirects on the 3P body (player_unit),
sending events that don't exist on the skeleton. The 1P first_person_unit
must be identified separately via `_local_fp_unit` (captured in the wield
hook from `self._first_person_unit`).

**How to apply:** The wield hook captures
`_local_fp_unit = self._first_person_unit` (local-only — for 1P
identification). It ALSO populates a weak-keyed `_unit_state[self._unit]`
entry **for every player including husks and bots** so the
animation_event hook can read each unit's own weapon. In the
animation_event hook, the first_person_unit gets an early return
(`if _local_fp_unit and unit == _local_fp_unit then return func(...)`).
All redirect/remap logic runs on everything else (player_unit + husks)
using per-unit state and the unit's OWN career via
`_unit_career_name(unit)`. Never gate redirects with `is_local` and never
read remap state from a single global.

### Per-unit state, weak-keyed

The animation remap system in `weapon_tweaker.lua` tracks each 3P body's
current weapon + active remap table in a **weak-keyed per-unit state
table**, NOT in module-level globals. Always read remap state via
`_state_for(unit)` and read the unit's career via `_unit_career_name(unit)`.

**Why:** v0.12.34 had a single set of globals (`_current_weapon_template`,
`_current_weapon_key`, `_3p_weapon_remap`, `_last_remap_template`) that
only the local viewer's wield populated. The `Unit.animation_event` hook
then applied the local viewer's remap to every 3P body it saw —
including remote-player husks. Result: remote cross-career weapons
rendered with wrong/missing 3P anims unless the local viewer happened to
hold the same weapon on the same career. v0.12.35 migrated to per-unit
state.

**How to apply:**

- `SimpleInventoryExtension.wield` hook populates
  `_unit_state[self._unit]` for **every** wield (local, husks, bots). Do
  NOT gate state capture on `self._unit == player.player_unit`. Only
  `_local_fp_unit` capture stays local-gated — and it's used solely for
  the redirect-skip early return.
- `Unit.animation_event` hook reads `state = _state_for(unit)` and
  `career = _unit_career_name(unit)`. Both per-unit. Never reach for
  `_local_career_name()` for the remap path — fallback to local career
  is OK only when the per-unit lookup returns nil for the local player's
  own unit.
- The `to_*` remap reset is per-unit (`state.last_remap_id` tracks
  weapon change per unit, not globally).
- The flail direct-redirect block (Saltzpyre + Sienna flaming flail
  cross-career fixes) reads `state.key` per-unit, not the global. Was
  previously `is_local`-only — that's no longer needed since per-unit
  weapon scoping prevents the direct-redirect from hijacking other
  players' weapons.
- The 1P early return MUST be **above** the state lookup so 1P events
  don't allocate empty state entries on the 1P hands unit.
- Weak-keyed table (`__mode = "k"`) means dead units release
  automatically; no cleanup needed.

### Husk extension class pair

VT2 has separate `Simple*Extension` / `SimpleHusk*Extension` classes for
self-owned vs remote units. Hooking one silently no-ops on the other.
Audit `unit_extension_templates.lua` and register both. wt v0.12.37 was
the fix that completed v0.12.35's per-unit migration.

### Closed-vocabulary rule for remap targets

When picking a substitute event for a 3P cross-character animation remap
(System B template clone, cross-access runtime remap, or weapon_tweaker
System A), the substitute MUST appear in the `anim_event` column of the
**target body's wield-SM-matching template** — the template whose
`wield_anim` matches the value of `wield_anim_career_3p` set for the
foreign wielder.

**Why:** This keeps recurring as a failure mode — picking remap targets
from the skeleton-events probe table or from
`Unit.has_animation_event` TRUE results, then watching them produce no
visible animation in-game. The master state machine knows event names
that have no visible clip in the current sub-graph; only events authored
on the wield SM's template are guaranteed to have a real clip behind
them. Bug class confirmed in CWV v0.1.158:
`_kruber_axe_falchion_remap` had `attack_push → attack_swing_left_diagonal`
even though `attack_push` was already in `dual_wield_hammer_sword_template`'s
authored set — the remap was substituting a working native clip for a
different one. Multiple earlier sessions wasted hours guessing targets
from the skeleton probe.

**How to apply:**

- Before adding any remap entry, pull the target template's full
  `anim_event` list from `dumps/weapon_actions.txt` (or live via
  `wt dump_actions <template>`). Write it down. That is the closed
  universe of valid remap targets.
- For each source event, ask THREE questions:
  1. **In target's closed list?** If no → remap to a substitute from the
     closed list.
  2. **Target's CLIP for that event matches the visual intent?** If no →
     remap to a different in-vocab event whose clip does. (Example:
     v0.1.158 left source push-attack `attack_swing_down` alone because
     it was in vocab; target's clip is a right-hand mace chop, but
     design wanted a left-hand falchion swing, so v0.1.161 remapped to
     `attack_swing_left`.)
  3. **Body's chain state has a clip for the target event in that
     state?** Closed-vocab is NOT sufficient on its own. An in-vocab
     event can produce no animation if the body's current chain state
     (idle / after-light / after-heavy) has no clip mapped for it. Pick
     a target that the target template fires from an EQUIVALENT chain
     position. (Example: v0.1.158-v0.1.192 mapped axe+falchion's H1
     from idle to `heavy_right_diagonal`; Kruber's body has no clip for
     that event from idle — `heavy_right_diagonal` is reachable only
     via the H2 chain. Body stood still on H1. Fixed in v0.1.193 by
     mapping H1 to `heavy_left_diagonal`, which IS Kruber's idle-H1
     native event.)
- The source for chain-position-to-event mapping: read the target
  template Lua at
  `Vermintide-2-Source-Code/scripts/settings/equipment/weapon_templates/<target>.lua`.
  Action sub-tables (`action_one.default`, `action_one.heavy_attack`,
  `action_one.default_right_heavy`, etc.) show which event fires from
  which chain position.
- For substitutes: pick from the closed list, prefer direction-matched
  AND chain-position-matched. If a heavy release is remapped, walk the
  source chain graph and remap the paired charge to a wind-up of the
  same direction.
- `wt force3p` is visual verification but limited — it fires from idle,
  so it can prove "this event has an idle-state clip" but not "this
  event has a clip from chain state X."
- `wt animlog` does NOT confirm playback. It logs every event fired with
  a `[MISSING]` flag from `Unit.has_animation_event` — but
  `[MISSING]=false` only means the SM knows the event name, not that a
  clip plays. Visual observation is the only confirmation.
- The full procedure with a worked Kruber-axe-falchion example lives at
  `character_weapon_variants/ANIMATION_FIX_PLAYBOOK.md`.

**Don't:**

- Don't pick targets from the 3P skeleton events table (below) alone —
  that's a per-character skeleton probe, not a per-template authoring
  list.
- Don't compile candidates from "all events the target character uses" —
  too broad. Different wield SMs on the same body have different
  authored vocabularies, and an event in template A is often a stub in
  template B.
- Don't add a remap for a source event that's already in the target's
  closed list. That overrides a working native clip with a different
  one.

### `Unit.has_animation_event` lies — verify visually

A TRUE result from `Unit.has_animation_event(unit, event)` only means
the SM has a transition declared for the event. It does NOT mean firing
the event produces a visible animation on the currently-loaded weapon
SM. Some events return TRUE on the skeleton table but play nothing when
fired (e.g. `attack_swing_heavy_left` on flail+Kruber).

**Why:** v0.9.81-v0.9.87 wasted hours guessing remap targets that
"existed" on the skeleton per the probe table but produced no visible
animation in 3P. The skeleton events reference (below) was probed
without a weapon SM loaded; results don't reflect what actually animates
when a specific weapon is wielded.

**How to apply:** Before picking a remap target, equip the weapon on
the target career, stand idle, and run `wt force3p <event>` for each
candidate. Visually confirm a complete strike plays. Only then add the
remap. The skeleton events table is useful for ruling OUT events
(FALSE = definitely missing) but TRUE entries are not a guarantee of
visible playback.

### No bows on Warrior Priest

When adding any cross-character port that targets a bow, crossbow, or
longbow 3P mesh (e.g. `we_longbow`-on-Saltzpyre → empire crossbow 3P;
`es_longbow`-on-Saltzpyre → empire crossbow 3P), do NOT add `wh_priest`
to the unlock map, the `_data.lua` widgets, the `_localization.lua`
labels, or the `_<PORT>_WIELD_3P` table.

**Why:** Warrior Priest's 3P body skeleton authors only the six
universal wields plus `to_2h_hammer` (see "3P skeleton events" below).
It does NOT author `to_crossbow`, `to_longbow`, `to_repeating_crossbow`,
or any other ranged-stance event. Cross-character bow/crossbow ports
that include him are dead UI at best — the missing wield event silently
no-ops and the body holds the previous weapon's idle stance (NOT a
T-pose despite older descriptions) — and engine-fatal at worst (some
downstream paths assert the wield event resolved). His vanilla weapon
list is also restricted enough that the unlock checkbox is dead UI even
when it doesn't crash.

**How to apply:**

- Cross-character RANGED ports targeting bows / crossbows / longbows /
  volley-crossbows: omit `wh_priest` from every table and widget.
- Cross-character MELEE ports: still permissible to include `wh_priest`,
  gated on his skeleton's actual melee vocabulary (he has
  `to_1h_hammer`, `to_2h_hammer`, `to_1h_hammer_shield`).
- Auditing precedent: `_SP_LONGBOW_CROSSBOW_WIELD_3P` (Empire Longbow on
  Saltzpyre port) historically included `wh_priest = "to_crossbow"` —
  was dead code (his `can_wield` excluded the longbow), now removed for
  consistency in v0.12.46-dev.

Established 2026-05-19 during the `we_longbow`-on-Saltzpyre Port A
shipment; user stated the rule directly after seeing the Port A patcher
table.

### Persistent weapon resources follow equipped-slot lifecycle

Player resource extensions such as Moonfire energy belong to the player and
survive weapon swaps; they are not recreated when `slot_ranged` changes. A
per-frame compatibility helper therefore has two separate questions:

1. Eligibility follows the item equipped in `slot_ranged`, not merely the
   currently wielded slot. Otherwise a stowed Moonfire stops regenerating
   (#584).
2. When the energy weapon leaves `slot_ranged`, nonnative residual energy must
   return to its neutral/full value once. Vanilla `EnergyBarUI` renders from the
   persistent energy extension, so package unload or inventory refresh alone
   cannot hide a stranded bar (#585).

Keep both operations owner-local and mutually exclusive through one planner and
one `energy_system:add_energy` site. Read the ranged slot once per tick; return
before inventory inspection when the career already owns a nonzero native
recharge rate. Tests must cover wielded/stowed parity, repeated slot swaps,
non-energy replacements, empty slots, full-state no-op, and native Kerillian.

### Weapon-scoped presentation over a career-scoped overcharge extension (#388)

Deepwood Staff is an overcharge weapon (`staff_life.lua` actions name `overcharge_type` and query `overcharge_system`), not an `energy_system` weapon. At player construction, `BulldozerPlayer` selects `OverchargeData[career_name]` (`bulldozer_player.lua:206`) and `PlayerUnitOverchargeExtension.init` copies the selected row's decay, warning sounds, screen particles, and explosion policy into scalar fields (`player_unit_overcharge_extension.lua:9-77`). `OverchargeBarUI.set_charge_bar_fraction` separately reads the career row on every draw (`overcharge_bar_ui.lua:234-271`). Therefore an off-career Deepwood cannot inherit Sister presentation from its item template.

WT resolves that mismatch at the two actual owners: `_wt_overcharge_presentation` snapshots and projects the native Sister profile on the local owner extension while the exact staff is in `slot_ranged`, then restores on removal/disable; its lazy HUD post-hook applies `OverchargeData.we_thornsister.overcharge_ui` after vanilla has populated the widget. `PlayerHuskOverchargeExtension` only consumes replicated values and has no warning/particle policy (`player_husk_overcharge_extension.lua:7-133`), so no husk mutation or RPC is appropriate. Spectator HUDs resolve the spectated inventory locally through the same HUD hook.

### Three-layer remap system

The animation remap system uses three layers, in resolution order:

1. **`_anim_redirect`** — global event renames (every unit, every
   weapon).
2. **`_career_anim_redirect`** — career-prefix-aware redirects (`we_`,
   `es_`, `wh_`, with `_default` fallback).
3. **`_suffix_career_map`** — suffix-based event swaps.

Then per-weapon remap tables (`_3p_remap_spear_to_billhook`, etc.) are
selected via `_3p_remap_triggers` based on the active weapon's career
+ template/key. Template-based remaps (`_3p_template_remaps`) use the
weapon template name (e.g. `we_one_hand_sword_template_1`). Key-based
remaps (`_3p_key_remaps`) use the weapon key (e.g. `we_1h_sword`).
Resolution order: template first, key as fallback. Both support
career-prefix matching with `_default` fallback, and `false` to
explicitly skip a career (e.g. `we_ = false` means Kerillian uses
native animations).

### Remap-table gotchas

- **Remap tables need both 1P and 3P event name variants.** Charge
  events have swapped word order between 1P and 3P (e.g.
  `attack_swing_stab_charge` vs `attack_swing_charge_stab`). Both
  variants must be in the remap table.
- **Clear only on actual weapon switch.** The game re-fires wield
  animation events (`to_polearm`) during push/block/ability. The
  re-fired event is the REDIRECTED name, not the original. It doesn't
  go through career redirect, so the remap never gets re-set. Guard the
  clear with `remap_id ~= _last_remap_template`, where
  `remap_id = _current_weapon_template or _current_weapon_key`.
- **`_current_weapon_template` can be nil.** During career ability or
  non-weapon slot activation, the template becomes nil. The `remap_id`
  fallback to `_current_weapon_key` handles this — if both are nil,
  `remap_id` is nil and the clear is skipped.
- **Polearm charge events on Kruber:**
  `attack_swing_charge_right` = thrust windup,
  `attack_swing_charge` = overhead windup. Match charge remap targets
  to the heavy release type.
- **Force-fire via `_original_animation_event` for SM-breaking events.**
  Some events (e.g. `attack_swing_stab_02`) corrupt the entire SM
  chain when added to the remap table — even mapping to valid targets
  like `stab` or `left_diagonal` breaks ALL animations, not just the
  target. For these events, bypass the remap table and call
  `_original_animation_event(unit, target)` directly. This is the same
  code path as `wt force3p` and works where the remap table fails.
  **Why:** `stab_02 → stab` in the remap table broke L1-L3 as well
  (v0.9.43). Force-fire of the same target event works (v0.9.47). Root
  cause unknown — possibly the billhook SM uses `stab_02` internally.
- **Force-fire blocks must be scoped to their remap table.** Force-fires
  run inside the `if _3p_weapon_remap` block, so they apply to ANY
  active remap. Guard with
  `_3p_weapon_remap == _3p_remap_spear_to_billhook` (or whichever table
  the force-fires target). Without this, billhook-specific force-fires
  (e.g. `heavy_left→heavy_stab`) incorrectly intercept the same events
  on other weapons like elf spear+shield. **Why:** v0.9.56 — elf using
  Kruber's spear+shield had H1/H2 silently hijacked by billhook
  force-fires.
- **Bidirectional remap tables for shared wield events.** When two
  weapon types share a wield event redirect (e.g.
  `to_1h_spear_shield` ↔ `to_es_deus_01`), the remap direction depends
  on which character is using the weapon. Use career-prefix entries in
  `_3p_remap_triggers` to select the correct direction: `_default` for
  the common case, `we_` / `es_` / `wh_` for career-specific overrides.
- **Billhook has a 3-light chain.** The billhook SM cycles:
  `stab → left_diagonal → stab → loop`. `light_attack_bopp` is push
  follow-up, not L4. Weapons with 4+ chained lights need force-fire for
  attacks beyond position 3.
- **Billhook event name inversion.** On the billhook SM, event names
  are visually inverted: `stab_charge` LOOKS like a swing windup,
  `charge_left_diagonal` LOOKS like a stab windup. Same for releases:
  `heavy_stab` looks like diagonal, `heavy_left_diagonal` looks like
  stab. When mapping charge→release pairs, the "matching" visual pair
  uses opposite-named events.

### Heavy-attack chains are 3-position, not 2-position

Many cross-career weapons have a 3-position heavy chain that confused
the v0.9.108-v0.9.114 work:

- **H1 (from idle):** event-pair A
- **H2:** event-pair B (different events from A)
- **H3+ (loops with H2):** event-pair C — but the *release* event in C
  is often the SAME as A's release. The SM differentiates by chain
  state, not event.

This means redirecting A's release also redirects H3+'s release. If you
want H1 ≠ H3+ visually, you can't — they share the release event. What
you CAN make distinct is the charge windup; remap C's unique charge
event (e.g. `attack_swing_charge_left_pose` on
`one_handed_swords_template_1`) to match H1's release direction so the
chain stays visually coherent.

**Why:** v0.9.113 — bw_sword chain on Bardin: H1 was
`charge_left/heavy`, H2 was `charge_right_pose/heavy_right`, H3+ was
`charge_left_pose/heavy`. H3 inherited H1's right-swing release (because
both fire `heavy`) but had no remap on `charge_left_pose`, so H3 fired
without a visible windup. User reported "first heavy loses charge
animation" — the chained-loop variant. Adding a windup remap for the
H3-specific charge event fixed it without changing H1.

**How to apply:** When fixing cross-career heavies, capture animlog of
4+ chained heavies (not just 2). Look for a third event pair beyond H1
and H2. If H3+'s release event matches H1's, only remap H3+'s charge to
match the visual; leave the release alone (already correct via H1's
remap).

### Three-heavy chains exist on some weapons

The elf 1h sword (`we_one_hand_sword_template_1`) has three distinct
heavy events: H1 `charge_down → heavy_down`, H2
`charge_left → heavy_left_up`, H3
`charge_right_diagonal_pose → heavy_down_right`. H3 is its own event
pair, not a loop variant. Charge event
`attack_swing_charge_right_diagonal_pose` is also fired during light L2
charge — remapping it affects both, but light charges are too brief to
notice the change.

### Known weapon-specific remaps

- **Bardin Greataxe on non-WP Saltzpyre (#286):**
  `two_handed_axes_template_1.wield_anim_career_3p` routes `wh_captain`,
  `wh_bountyhunter`, and `wh_zealot` to `to_2h_hammer_priest`. The old
  `to_2h_sword` target produced a Greatsword idle/stance; Warrior Priest's
  greathammer stance is the confirmed target. Keep the source table and applied
  live template aligned; `/wt_regression_test`
  `issue286_greataxe_saltzpyre_wield_pose` guards both layers.
- **Greatsword cross-career remap (template-based).**
  `two_handed_swords_template_1` (es/wh greatsword) on Kerillian
  (`we_`): stance redirect `to_2h_sword` → `to_2h_sword_we`, plus 8
  template remaps for diagonal events that don't exist on the elf
  skeleton. Push-attack (`attack_swing_down_right`) maps to
  `attack_swing_heavy` (the elf greatsword's default heavy release). H1
  heavy release (`attack_swing_heavy_left_diagonal`) maps to
  `attack_swing_left` to match L1's visual direction. Grip offset
  `-0.085` Z on both `es_2h_sword` and `wh_2h_sword` for `we_*`. Tuned
  through several iterations: `-0.07` imperceptible, `-0.25`
  overcorrection, `-0.15` slightly too much, `-0.085` final.
- **`we_1h_sword` on non-Kerillian:** `attack_swing_stab` →
  `attack_swing_down` (light 3), `attack_swing_heavy_left_up` →
  `attack_swing_heavy` (heavy 2). Kerillian skipped via
  `we_ = false`.
- **`es_1h_flail` on non-Saltzpyre:** H1 release `attack_swing_left` →
  `attack_swing_heavy`, H2 release `attack_swing_heavy_left` →
  `attack_swing_heavy` (v0.9.88). Both are direct
  `func(unit, target, ...)` calls in the hook BEFORE the remap-table
  block — the remap table corrupts the SM for `attack_swing_left` (same
  pattern as billhook `stab_02`).
- **`bw_1h_flail_flaming` on non-Sienna:** only H2 release
  `attack_swing_heavy_left` → `attack_swing_heavy` needs the redirect
  (v0.9.92). H1 charge `attack_swing_charge_down` and release
  `attack_swing_heavy_down` fire natively as the correct overhead — DO
  NOT remap them. Earlier versions (≤v0.9.91) added template-table
  entries for these and broke H1's animation on Kruber.
- **Heavy remap target must play a full strike animation.**
  `attack_swing_heavy_left` only plays charge / nothing on Kruber's
  skeleton even though `Unit.has_animation_event` reports it TRUE.
  `attack_swing_heavy` plays a complete heavy strike.

### Vanilla bug fixed via narrow native-wielder redirect (v0.9.96)

`es_1h_flail` push-attack on Saltzpyre native: vanilla
`attack_swing_right` release fires on the 3P body but produces no
visible animation. User confirmed via `wt force3p` testing that
`attack_swing_right_diagonal` plays a visible L2-style swing on
Saltzpyre's flail SM. Added a narrow redirect (`attack_swing_right` →
`attack_swing_right_diagonal`) gated on
`_current_weapon_key == "es_1h_flail"` AND career prefix `wh_`. This is
the only place we modify a native-wielder animation; the user
explicitly authorized it after testing confirmed the vanilla event was
broken.

**Why the rule "don't modify native-wielder animations" was relaxed
here:** The native event was demonstrably broken (no visible animation
even from idle), and the user verified via `force3p` that an
alternative event produced the correct visual. Without those two
confirmations, do not redirect a native-wielder event.

### Inventory preview uses a separate code path (MenuWorldPreviewer)

The new (post-WoM) inventory character preview uses
`MenuWorldPreviewer`, not `HeroPreviewer` or `GearUtils.create_equipment`.
Hooks on `GearUtils.create_equipment` apply only to the in-game keep
player_unit, not the menu preview's own spawned units. To affect the
menu preview:

- Hook `MenuWorldPreviewer:equip_item(item_key, slot, backend_id)` to
  capture the weapon key per slot. This is the only place the actual
  weapon key is exposed.
- Hook `MenuWorldPreviewer:_spawn_item_unit(unit, slot_type, item_data, ...)`
  to apply scale/offset to an unpaired spawned `unit`. Note: `item_data` here
  is the weapon TEMPLATE (e.g. `we_one_hand_axe_template`), NOT an
  inventory item — so `item_data.key`/`name` returns the template name,
  not the weapon key. Look up the captured key from the equip_item map
  by `slot_type` (which is "melee"/"ranged"/"hat", not "slot_melee").
- A paired weapon template makes `_spawn_item_unit` hand-ambiguous. For a
  transform descriptor scoped to `hand = "left"` or `"right"`, defer the
  write until `MenuWorldPreviewer:_spawn_item` returns. Its `spawn_data`
  retains `left_hand`/`right_hand`, while `spawn_data[i].slot_index` bridges
  the string-keyed `_item_info_by_slot` data to numeric `_equipment_units`.
  Apply the descriptor only to that exact spawned hand; never guess from
  template shape. This is the #735 shield/sword separation contract.
- Use a weak-keyed table (`setmetatable({}, {__mode = "k"})`) for the
  previewer→key mapping so dismissed previewers don't leak.

**Why:** v0.9.129 added grip/scale support for the menu inventory after
the user noticed in-game changes weren't reflected in the preview. The
two code paths are entirely separate; this is not documented anywhere
obvious in VT2 modkit.

---

## 3P animation fix process

### When to use

A cross-career weapon plays wrong or missing 3P animations (visible in
keep lobby or to other players). Common symptoms: attack plays
charge/windup but no strike, body holds the previous weapon's idle
stance with no fire/swing animation (the silent missing-event no-op —
NOT a T-pose; see `PROJECT_STANDARDS.md` § 9.8 for the terminology
rule), or a completely wrong swing direction.

### Step 1: Enable animlog

Run `wt animlog` in-game chat. This toggles animation event logging.
Output goes to both `mod:echo` (in-game chat) and `mod:info` (console
log file). Only attack/wield/parry events are logged; idle/locomotion
filtered out.

### Step 2: Perform the attack combo

Do the full light chain and heavy chain. Each attack fires two events:
a charge event first, then a strike event. Light attacks have ~50-120ms
charge-to-strike gap; heavies ~500-660ms. The log shows `1P` and `3P`
tags, and `[MISSING]` if the event doesn't exist on the skeleton.

### Step 3: Read the console log

Log file: `%APPDATA%\Fatshark\Vermintide 2\console_logs\` (most
recent). Search for `[MOD][wt]`. Events show as:

```
1P attack_swing_stab
3P attack_swing_stab [MISSING]
```

A `[MISSING]` tag on the 3P line means the skeleton doesn't have that
animation event.

### Step 4: Identify the broken event

Compare 1P and 3P lines. If 3P shows `[MISSING]`, that event needs a
remap. Cross-reference with the 3P skeleton events table (below) to
find which attack events exist on the target character's skeleton.

### Step 5: Choose a remap target — CLOSED VOCABULARY + VISUAL VERIFY

**Closed-vocabulary rule (load-bearing):** every remap target MUST be a
string already authored in the `anim_event` column of the **target
body's wield-SM-matching template** (the template whose `wield_anim`
matches the value of `wield_anim_career_3p` set for the foreign
wielder). Anything outside that set is invention regardless of what the
skeleton-events probe or `Unit.has_animation_event` reports.

Workflow:

1. Identify the target template. For a cross-character cross-access
   weapon, this is the template whose `wield_anim` matches the value
   the foreign career was routed to (e.g. axe+falchion on Kruber
   routes to `to_dual_hammer_sword_es`, so the target template is
   `dual_wield_hammer_sword_template`).
2. Read every `anim_event` value from that template — `dumps/weapon_actions.txt`
   (organized) or live via `wt dump_actions <template>`. That is the
   closed list of allowed remap targets.
3. For each broken source event: pick a substitute from the closed
   list whose visual direction matches the source's intent. Source
   events that are ALREADY in the closed list need no remap — they
   play natively.
4. Verify visually: equip on the target career, idle in keep, run
   `wt force3p <candidate>`, watch the 3P body. Only "the body visibly
   moved through a complete strike" counts. `force3p exists=true` is
   necessary but not sufficient.

Do NOT pick a target from the 3P skeleton events table alone. The
skeleton table is useful for ruling things OUT (FALSE = definitely
missing) but TRUE entries are not a guarantee of visible playback in
the current sub-graph.

The closed-vocabulary rule supersedes the older "common heavy-strike
candidates" list and the "all events from the target character's native
weapon template" guidance — both were too broad. The right scope is
**the wield-SM-matching template only**, not "everything that character
ever uses." See `character_weapon_variants/ANIMATION_FIX_PLAYBOOK.md`
for the full step-by-step procedure with a worked example.

### Step 6: Add the remap

**Default path:** add to `_3p_key_remaps` (by weapon key) or
`_3p_template_remaps` (by template name). Use career prefix matching:
`we_ = false` skips the weapon's native character, `_default` covers
all others.

**Fallback path (SM-corrupting events):** some events break ALL
animations when added to the remap table even with a valid target —
`attack_swing_left` (flail), `attack_swing_stab_02` (billhook). For
these, add a hardcoded direct-redirect block in the `animation_event`
hook BEFORE the `_3p_weapon_remap` block, calling
`func(unit, target, ...)` with full varargs:

```lua
if _current_weapon_key == "es_1h_flail" and career and career:sub(1, 3) ~= "wh_" then
    if event_name == "attack_swing_left" or event_name == "attack_swing_heavy_left" then
        return func(unit, "attack_swing_heavy", ...)
    end
end
```

Symptom that you need this path: the table-based remap "fires" per the
log but no animation plays, or it breaks unrelated attacks in the same
chain.

### Step 7: Build, deploy, test

Bump MOD_VERSION, build, deploy, hot-reload in-game. Re-equip the
weapon (wield hook must fire to pick up new template/key). Run
`wt animlog` again to verify the remap fires and the 3P event changes.
Check visually that the animation plays correctly.

### Step 8: Verify menu inventory preview matches

For scale and grip-offset changes specifically, check the inventory
character preview after the in-game change works — the new (post-WoM)
inventory uses `MenuWorldPreviewer`, which spawns its OWN units
separate from the in-game body. The mod handles both paths via shared
helpers (see the comment block above `_weapon_scale_overrides` in
weapon_tweaker.lua), so adding entries works automatically — but if
you change the scale/offset hook plumbing itself, validate both paths.
Animation remaps don't go through MenuWorldPreviewer (the preview pose
is static, not driven by the in-game animation_event hook), so this
step only matters for scale/offset edits.

### Key gotchas

- Must re-equip weapon after hot reload (wield hook sets template/key).
- **Never redirect the first_person_unit** (1P hands). It has
  `is_local=false` — same as husks. Identify it via `_local_fp_unit`
  (captured from `self._first_person_unit` in the wield hook) and
  early-return it before any redirect logic.
- **player_unit IS the 3P body** (`is_local=true`). It NEEDS redirects
  and remaps. Never skip it.
- `is_local` does NOT distinguish 1P from 3P — do not use it to protect
  1P animations.
- Some events that exist on a skeleton don't play a visible strike
  (only charge) — always test visually.
- Console log requires game to flush; open inventory or exit game to
  force flush.

---

## 3P skeleton events reference

Probed 2026-04-26 via `wt sm_probe` on each character in the keep
lobby. Useful for ruling OUT events (FALSE = definitely missing) but
TRUE entries DO NOT guarantee visible playback when a specific weapon
SM is loaded (see "Unit.has_animation_event lies" above).

### Wield Events (FALSE = needs redirect)

| Event                  | Kruber | Saltz | WPriest | Kerill | Bardin | Sienna |
|------------------------|--------|-------|---------|--------|--------|--------|
| to_2h_sword            | T      | T     | F       | F      | F      | T      |
| to_2h_sword_we         | F      | T     | F       | T      | F      | F      |
| to_bastard_sword       | T      | T     | F       | F      | F      | F      |
| to_spear               | T      | T     | T       | T      | T      | T      |
| to_polearm             | T      | T     | T       | T      | T      | T      |
| to_1h_sword            | T      | T     | T       | T      | T      | T      |
| to_1h_hammer           | T      | T     | T       | T      | T      | T      |
| to_2h_billhook         | F      | T     | F       | F      | F      | T      |
| to_longbow             | T      | T     | F       | T      | F      | F      |
| to_es_longbow          | T      | T     | F       | F      | F      | F      |
| to_1h_sword_shield     | T      | T     | F       | T      | T      | F      |
| to_1h_hammer_shield    | T      | T     | F       | T      | T      | T      |
| to_dual_wield          | F      | F     | F       | F      | F      | F      |
| to_2h_hammer           | T      | T     | T       | F      | T      | T      |
| to_2h_axe              | F      | F     | F       | F      | F      | F      |
| to_1h_axe              | T      | T     | T       | T      | T      | T      |
| to_1h_falchion         | F      | F     | F       | F      | F      | F      |
| to_1h_flail            | T      | T     | T       | T      | T      | T      |
| to_crossbow            | T      | T     | F       | F      | T      | T      |
| to_repeating_crossbow  | F      | T     | F       | F      | F      | T      |
| to_handgun             | T      | T     | F       | F      | T      | F      |
| to_blunderbuss         | T      | T     | F       | F      | F      | F      |

### Attack Events (only listing those FALSE on any skeleton)

| Event                           | Kruber | Saltz | WPriest | Kerill | Bardin | Sienna |
|---------------------------------|--------|-------|---------|--------|--------|--------|
| attack_swing_charge_down_pose   | T      | F     | F       | F      | F      | T      |
| attack_swing_stab_lh            | T      | F     | F       | T      | F      | F      |
| attack_swing_down_left_axe      | F      | F     | F       | T      | T      | T      |
| push_stab                       | T      | F     | F       | T      | T      | F      |

All other attack events (attack_swing_right, attack_swing_left,
attack_swing_down, attack_swing_up_left, attack_swing_down_left,
attack_swing_down_right, attack_swing_heavy, attack_swing_heavy_right,
attack_swing_heavy_left, attack_swing_heavy_down,
attack_swing_heavy_left_diagonal, attack_swing_heavy_right_diagonal,
attack_swing_charge, attack_swing_charge_left, attack_swing_charge_right,
attack_swing_charge_left_diagonal,
attack_swing_charge_right_diagonal_pose,
attack_swing_charge_left_diagonal_pose, attack_swing_charge_stab,
attack_swing_charge_down, attack_swing_stab, attack_swing_stab_02,
attack_swing_left_diagonal, attack_push, parry_pose) are TRUE on all 6
skeletons.

### Key observations

1. **Universal wield events** (TRUE everywhere): to_spear, to_polearm,
   to_1h_sword, to_1h_hammer, to_1h_axe, to_1h_flail. **CAVEAT:**
   `to_1h_hammer` is phantom on Kerillian — TRUE in probe but no
   visible animation. Redirect to `to_1h_sword` fixes it (confirmed
   2026-04-29). Other "universal" events may have similar phantom
   behavior on specific skeletons.
2. **Universally missing**: to_dual_wield, to_2h_axe, to_1h_falchion —
   no skeleton has these.
3. **Warrior Priest** is the most stripped — only the 6 universal
   wields + to_2h_hammer. No ranged, no shields, no swords/bastard.
4. **Saltzpyre (non-Priest)** is the most complete — has almost
   everything including to_2h_billhook natively.
5. **to_2h_billhook** only exists on Saltzpyre and Sienna.
6. **to_bastard_sword** only exists on Kruber and Saltzpyre.
7. **to_2h_sword** only exists on Kruber, Saltzpyre, and Sienna.
8. **to_2h_sword_we** only exists on Saltzpyre and Kerillian.
9. **Kerillian** has the most complete attack set (only missing
   attack_swing_charge_down_pose).
10. **Kruber** only missing attack_swing_down_left_axe from attacks —
    most complete after Kerillian.

---

## QA tooling

### Runtime regression registration — `_wt_runtime_checks.lua`

`weapon_tweaker.lua` owns the regression registry and chat-command lifecycle.
`_wt_runtime_checks.lua` receives the registry plus the private runtime
tables/helpers that its closures inspect, then registers the checks in their
historical order. The module also owns the single
`/verify_wt_availability_sort` registration. Keep the public and dev copies
normalized-identical outside paired `WT_DEV_OVERLAY` regions; the dev-only
animation picker, hold-pose, and zoom checks belong inside those overlays.
Runtime checks must stay lazy so later initialization can populate the tables
they inspect. `test_wt_runtime_checks_module.lua` protects the check boundaries,
counts, dependency contract, overlay delta, and singleton command ownership.

### Widget-tree reorder verifier — `_qa_wt_reorder.py`

When QA-ing a VMF widget reorder pass (shuffling `setting_id = "unlock_*"` rows in `weapon_tweaker_data.lua` and the matching keys in `weapon_tweaker_localization.lua`), use the verifier script at the repo root: `C:\Users\danjo\source\repos\vermintide-2-tweaker\_qa_wt_reorder.py`.

**Gates it checks:**
- `setting_id` parity between `_data.lua` and `_localization.lua`.
- No add/drop vs pre-edit `.bak` files.
- No `default_value` flips.
- Widget tree integrity (brace balance + structural soundness per subtree).
- `MOD_VERSION` bump.
- Intentional per-career divergence preservation.

**Important: brace-aware tree walker, NOT naive regex.** A naive regex that scans N chars forward from each `setting_id` will dive into nested `sub_widgets` and false-positive group-level `default_value` flips. The verifier uses a brace-aware tree walker that scopes `default_value` lookup to the immediate widget table only. This also gives a stronger structural guarantee than counting `{` vs `}` (a walker catches imbalances in specific subtrees, not just file-total counts).

VMF widget nesting in this repo uses `sub_widgets = { ... }`, NOT `parent_group_name = "..."` — the walker is structured around `sub_widgets` keys.

Authored 2026-05-23 during the weapon_tweaker v0.12.71-dev reorder pass. Lives at the repo root because nothing prevents reuse on other mods' data/loc files — adapt the input paths per mod.

Related: § Conventions "Maintain alphabetical order" below — moving a `setting_id` between groups requires moving the loc string at the same time; the verifier catches mismatches.

---

## Conventions

### CWV authored defaults and expansion careers

CWV catalog rows may declare `default_careers` separately from `careers` (introduced for #596 Infantry Spear). `careers` is the complete bounded set WT may manage; `default_careers` is the subset whose child toggles start enabled. Use `authored_careers` when deactivation must restore the CWV definition to a narrower native set. On WT/CWV deactivation, remove WT-only expansion careers and restore that authored set; never persist expanded `can_wield` membership into the inactive owner.

The availability pass must also inject the source weapon's career-ability action template for every enabled career, including authored defaults. This keeps newly defined CWV items functional on both their intended careers and explicit WT expansions without a per-frame hook or new transport.

### Maintain alphabetical order in weapon menus

The runtime data pass sorts every per-career melee/ranged leaf alphabetically
by its tag-stripped player-facing English label (issue #408). It reads the raw
localization DATA table per `docs/LOCALIZATION_STANDARD.md` section 12 and uses
the setting id only as a deterministic fallback/tie-break, so computed status
tags and weapon-key prefixes cannot change the visible order.

**Why:** The VMF mod menu renders weapons in data-tree order. The central sort
keeps that order aligned with the names users actually see, including future
ports and renamed localization entries.

**How to apply:** Keep the authored data and localization blocks tidy for
review, but do not hand-build source-character ordering. New unlock rows are
sorted automatically at data load. Run `/verify_wt_availability_sort` or the
`issue408_availability_rows_sorted_by_name` regression check after changing the
sort or dynamic labels.
